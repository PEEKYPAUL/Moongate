// POST /functions/v1/enroll-prepare
//
// Called by the Pi when MOONGATE_PAIR is run. Pre-registers a hash of the
// enrollment token (the Pi keeps the raw token secret, only shares it via QR).
//
// No JWT required — the Pi has no user identity yet.
// Per-IP rate limiting handled by Supabase platform; further app-level
// limits can be added if abuse is observed.
//
// Request body:
//   {
//     "pi_public_key": "<base64 Ed25519 pubkey, 32 bytes>",
//     "token_hash":    "<base64 SHA-256 of the raw enrollment token, 32 bytes>"
//   }
//
// Response 200:
//   { "expires_at": "<ISO8601>" }
//
// Errors:
//   400 — malformed body
//   500 — internal

import { handleCorsPreflight } from "../_shared/cors.ts";
import { jsonResponse, badRequest, methodNotAllowed, internalError } from "../_shared/responses.ts";
import { adminClient } from "../_shared/supabaseClients.ts";
import { base64ToBytes } from "../_shared/cryptoUtils.ts";

const TTL_SECONDS = 600; // 10 minutes

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  let body: { pi_public_key?: unknown; token_hash?: unknown };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  const piPubKey = body.pi_public_key;
  const tokenHash = body.token_hash;
  if (typeof piPubKey !== "string" || typeof tokenHash !== "string") {
    return badRequest("pi_public_key and token_hash required as base64 strings");
  }

  try {
    const pkBytes   = base64ToBytes(piPubKey);
    const hashBytes = base64ToBytes(tokenHash);
    if (pkBytes.length   !== 32) return badRequest("pi_public_key must decode to 32 bytes");
    if (hashBytes.length !== 32) return badRequest("token_hash must decode to 32 bytes");
  } catch {
    return badRequest("invalid base64");
  }

  const db = adminClient();
  const { data, error } = await db.rpc("upsert_enrollment_token", {
    p_pi_public_key:  piPubKey,
    p_token_hash_b64: tokenHash,
    p_ttl_seconds:    TTL_SECONDS,
  });

  if (error) {
    console.error("enroll-prepare rpc error", error);
    return internalError();
  }

  return jsonResponse({ expires_at: data });
});
