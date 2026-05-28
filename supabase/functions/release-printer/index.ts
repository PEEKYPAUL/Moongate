// POST /functions/v1/release-printer
//
// Two auth modes, distinguished by request body shape:
//
//   1. User-JWT (app's "Remove printer"):
//        Authorization: Bearer <supabase jwt>
//        body: { "printer_id": "<uuid>" }
//      Ownership enforced inside release_printer RPC; non-owners get 404.
//
//   2. Pi-signed force-release (Pi's MOONGATE_RESET_OWNER):
//        body: { "pi_public_key": "<b64>", "timestamp": <unix>, "signature": "<b64>" }
//      Pi signs canonical payload with its Ed25519 device key; signature
//      proves physical access. Deletes the row regardless of current owner,
//      so a fresh app install can re-pair without 'already_paired'.
//
// Idempotent in both modes. 200 even if the row was already gone.
//
// Errors:
//   400 — malformed body
//   401 — user mode: missing/invalid JWT; Pi mode: bad signature or replay window
//   404 — user mode only: printer exists but caller isn't the owner (constant shape)
//   500 — internal

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  jsonResponse, badRequest, unauthorized, notFound,
  methodNotAllowed, internalError,
} from "../_shared/responses.ts";
import { adminClient, getUserFromRequest } from "../_shared/supabaseClients.ts";
import { verifyEd25519, base64ToBytes } from "../_shared/cryptoUtils.ts";

const REPLAY_WINDOW_SECONDS = 60;

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  let body: {
    printer_id?:    unknown;
    pi_public_key?: unknown;
    timestamp?:     unknown;
    signature?:     unknown;
  };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  // Body shape discriminates the auth mode. Presence of pi_public_key
  // selects the Pi-signed path; anything else falls through to user-JWT.
  if (body.pi_public_key !== undefined) {
    return await handlePiSignedRelease(body);
  }
  return await handleUserRelease(req, body);
});

async function handlePiSignedRelease(body: {
  pi_public_key?: unknown;
  timestamp?:     unknown;
  signature?:     unknown;
}): Promise<Response> {
  const piPubKey  = body.pi_public_key;
  const timestamp = body.timestamp;
  const signature = body.signature;

  if (typeof piPubKey  !== "string") return badRequest("pi_public_key required");
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) {
    return badRequest("timestamp required (unix seconds)");
  }
  if (typeof signature !== "string") return badRequest("signature required");

  try {
    const pkBytes = base64ToBytes(piPubKey);
    if (pkBytes.length !== 32) return badRequest("pi_public_key must decode to 32 bytes");
  } catch {
    return badRequest("invalid pi_public_key base64");
  }

  // Replay window — mirrors printer-heartbeat (±60s on server clock).
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > REPLAY_WINDOW_SECONDS) {
    return unauthorized();
  }

  // Canonical payload matches what the Pi plugin signs in _release_in_cloud.
  // Domain-separated from heartbeat by the first line ("moongate-release"
  // vs "moongate-heartbeat") so a captured heartbeat signature can't be
  // replayed as a release.
  const canonical = `moongate-release\n${piPubKey}\n${timestamp}`;
  const message   = new TextEncoder().encode(canonical);
  const ok        = await verifyEd25519(piPubKey, signature, message);
  if (!ok) return unauthorized();

  const db = adminClient();
  const { error } = await db.rpc("release_printer_by_pubkey", {
    p_pi_public_key: piPubKey,
  });
  if (error) {
    console.error("release_printer_by_pubkey rpc error", error);
    return internalError();
  }
  return jsonResponse({ ok: true });
}

async function handleUserRelease(req: Request, body: {
  printer_id?: unknown;
}): Promise<Response> {
  const user = await getUserFromRequest(req);
  if (!user) return unauthorized();

  const printerId = body.printer_id;
  if (typeof printerId !== "string" || printerId.length === 0) {
    return badRequest("printer_id required");
  }

  const db = adminClient();
  const { data, error } = await db.rpc("release_printer", {
    p_printer_id: printerId,
    p_user_id:    user.id,
  });

  if (error) {
    console.error("release_printer rpc error", error);
    return internalError();
  }

  // release_printer returns text: 'ok' or 'not_found'
  const status = typeof data === "string" ? data : (Array.isArray(data) ? data[0] : null);

  switch (status) {
    case "ok":
      return jsonResponse({ ok: true });
    case "not_found":
    default:
      return notFound();
  }
}
