// POST /functions/v1/printer-heartbeat
//
// Called by the Pi on boot and whenever cloudflared rotates the tunnel URL.
// Updates the encrypted tunnel URL on the printer record and bumps last_seen.
//
// Auth model: the Pi has no Supabase user. Authenticity is established by
// the Pi signing a canonical payload with its Ed25519 device key. The server
// looks up the printer by pi_public_key and verifies the signature against
// it. Replay is bounded by a 60-second window on the timestamp.
//
// Request body:
//   {
//     "pi_public_key": "<base64 Ed25519 pubkey>",
//     "tunnel_url":    "https://xxx.trycloudflare.com",
//     "timestamp":     <unix seconds>,
//     "signature":     "<base64 Ed25519 signature over canonical payload>"
//   }
//
// Canonical payload (UTF-8 bytes signed by Pi):
//   "moongate-heartbeat\n" + pi_public_key + "\n" + tunnel_url + "\n" + timestamp
//
// Response 204 on success.
//
// Errors:
//   400 — malformed body
//   401 — signature invalid OR timestamp out of window
//   404 — no printer with this pi_public_key (Pi should treat as unpaired)
//   500 — internal

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  emptyResponse, badRequest, unauthorized, notFound,
  methodNotAllowed, internalError,
} from "../_shared/responses.ts";
import { adminClient } from "../_shared/supabaseClients.ts";
import { encryptTunnelUrl, verifyEd25519, base64ToBytes } from "../_shared/cryptoUtils.ts";

const REPLAY_WINDOW_SECONDS = 60;
const MAX_TUNNEL_URL_LENGTH = 256;

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  let body: {
    pi_public_key?: unknown;
    tunnel_url?:    unknown;
    timestamp?:     unknown;
    signature?:     unknown;
  };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  const piPubKey  = body.pi_public_key;
  const tunnelUrl = body.tunnel_url;
  const timestamp = body.timestamp;
  const signature = body.signature;

  if (typeof piPubKey  !== "string") return badRequest("pi_public_key required");
  if (typeof tunnelUrl !== "string" || tunnelUrl.length === 0 || tunnelUrl.length > MAX_TUNNEL_URL_LENGTH) {
    return badRequest(`tunnel_url required (1-${MAX_TUNNEL_URL_LENGTH} chars)`);
  }
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) {
    return badRequest("timestamp required (unix seconds)");
  }
  if (typeof signature !== "string") return badRequest("signature required");

  // Sanity-check pubkey length before doing crypto
  try {
    const pkBytes = base64ToBytes(piPubKey);
    if (pkBytes.length !== 32) return badRequest("pi_public_key must decode to 32 bytes");
  } catch {
    return badRequest("invalid pi_public_key base64");
  }

  // Replay window check (server time vs claimed timestamp)
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > REPLAY_WINDOW_SECONDS) {
    return unauthorized();
  }

  // Verify signature
  const canonical = `moongate-heartbeat\n${piPubKey}\n${tunnelUrl}\n${timestamp}`;
  const message   = new TextEncoder().encode(canonical);
  const ok        = await verifyEd25519(piPubKey, signature, message);
  if (!ok) return unauthorized();

  // Encrypt the new tunnel URL
  let ciphertextB64: string, nonceB64: string;
  try {
    const enc = await encryptTunnelUrl(tunnelUrl);
    ciphertextB64 = enc.ciphertextB64;
    nonceB64      = enc.nonceB64;
  } catch (e) {
    console.error("encryptTunnelUrl failed", e);
    return internalError();
  }

  // Update the printer row (lookup by pi_public_key)
  const db = adminClient();
  const { data, error } = await db.rpc("record_heartbeat", {
    p_pi_public_key:        piPubKey,
    p_tunnel_url_enc_b64:   ciphertextB64,
    p_tunnel_url_nonce_b64: nonceB64,
  });

  if (error) {
    console.error("record_heartbeat rpc error", error);
    return internalError();
  }

  // record_heartbeat returns the printer_id (uuid) on success, null if no row
  if (!data) return notFound();

  return emptyResponse(204);
});
