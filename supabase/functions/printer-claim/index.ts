// POST /functions/v1/printer-claim
//
// Called by the app immediately after the user scans the QR. Atomically
// validates the enrollment token, creates the printer row with
// owner_user_id = caller's anon Supabase uid, and marks the token used.
//
// Caller MUST present a Supabase JWT (anonymous or otherwise) in the
// Authorization header.
//
// Request body:
//   {
//     "enrollment_token": "<raw string, e.g. GATE-XXXX-XXXX>",
//     "pi_public_key":    "<base64 Ed25519 pubkey from the QR>",
//     "name":             "<user-chosen name>"
//   }
//
// Response 200:
//   { "printer_id": "<uuid>" }
//
// Errors:
//   400 — malformed body
//   401 — no/invalid JWT
//   404 — token invalid for any reason (expired, used, mismatched, not found)
//   409 — this Pi pubkey is already paired (use MOONGATE_RESET_OWNER on Pi)
//   500 — internal

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  jsonResponse, badRequest, unauthorized, notFound, conflict,
  methodNotAllowed, internalError,
} from "../_shared/responses.ts";
import { adminClient, getUserFromRequest } from "../_shared/supabaseClients.ts";
import { base64ToBytes, bytesToBase64, sha256 } from "../_shared/cryptoUtils.ts";

const MAX_NAME_LENGTH = 64;

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  const user = await getUserFromRequest(req);
  if (!user) return unauthorized();

  let body: { enrollment_token?: unknown; pi_public_key?: unknown; name?: unknown };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  const enrollmentToken = body.enrollment_token;
  const piPubKey        = body.pi_public_key;
  const name            = body.name;

  if (typeof enrollmentToken !== "string" || enrollmentToken.length === 0) {
    return badRequest("enrollment_token required");
  }
  if (typeof piPubKey !== "string") {
    return badRequest("pi_public_key required");
  }
  if (typeof name !== "string" || name.length === 0 || name.length > MAX_NAME_LENGTH) {
    return badRequest(`name required (1-${MAX_NAME_LENGTH} chars)`);
  }

  try {
    const pkBytes = base64ToBytes(piPubKey);
    if (pkBytes.length !== 32) return badRequest("pi_public_key must decode to 32 bytes");
  } catch {
    return badRequest("invalid pi_public_key base64");
  }

  // Hash the raw token to look it up against enrollment_tokens.token_hash
  const tokenBytes = new TextEncoder().encode(enrollmentToken);
  const tokenHash  = await sha256(tokenBytes);
  const tokenHashB64 = bytesToBase64(tokenHash);

  const db = adminClient();
  const { data, error } = await db.rpc("claim_printer", {
    p_token_hash_b64: tokenHashB64,
    p_pi_public_key:  piPubKey,
    p_name:           name.trim(),
    p_user_id:        user.id,
  });

  if (error) {
    console.error("claim_printer rpc error", error);
    return internalError();
  }

  // claim_printer returns a set of one row: { printer_id, status }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return internalError();

  switch (row.status) {
    case "ok":
      return jsonResponse({ printer_id: row.printer_id });
    case "already_paired":
      return conflict("already_paired");
    case "not_found":
    default:
      return notFound();
  }
});
