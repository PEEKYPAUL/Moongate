// POST /functions/v1/printer-access
//
// Called by the app immediately before sending a control command to the Pi.
// Returns the current tunnel URL (decrypted) and a fresh 5-minute access
// token signed with the server's Ed25519 key.
//
// Caller MUST present a Supabase JWT in the Authorization header.
// Ownership is enforced inside the RPC; non-owners get an indistinguishable
// 404 response.
//
// Request body:
//   { "printer_id": "<uuid>" }
//
// Response 200:
//   {
//     "tunnel_url":   "https://xxx.trycloudflare.com",
//     "access_token": "<EdDSA JWT, ~5 min TTL>",
//     "expires_in":   300
//   }
//
// Errors:
//   400 — malformed body
//   401 — no/invalid JWT
//   404 — printer doesn't exist OR not owned by caller (constant shape)
//   503 — printer exists but Pi has not sent a heartbeat yet; retry_after seconds

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  jsonResponse, badRequest, unauthorized, notFound,
  methodNotAllowed, internalError, serviceUnavailable,
} from "../_shared/responses.ts";
import { adminClient, getUserFromRequest } from "../_shared/supabaseClients.ts";
import { decryptTunnelUrl } from "../_shared/cryptoUtils.ts";
import { mintAccessToken } from "../_shared/accessToken.ts";

const RETRY_AFTER_SECONDS = 5;

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  const user = await getUserFromRequest(req);
  if (!user) return unauthorized();

  let body: { printer_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  const printerId = body.printer_id;
  if (typeof printerId !== "string" || printerId.length === 0) {
    return badRequest("printer_id required");
  }

  const db = adminClient();
  const { data, error } = await db.rpc("get_printer_access", {
    p_printer_id: printerId,
    p_user_id:    user.id,
  });

  if (error) {
    console.error("get_printer_access rpc error", error);
    return internalError();
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return notFound();

  // Pi hasn't heartbeated yet — ciphertext+nonce will both be null
  if (!row.tunnel_url_enc_b64 || !row.tunnel_url_nonce_b64) {
    return serviceUnavailable(RETRY_AFTER_SECONDS);
  }

  let tunnelUrl: string;
  try {
    tunnelUrl = await decryptTunnelUrl(row.tunnel_url_enc_b64, row.tunnel_url_nonce_b64);
  } catch (e) {
    console.error("decrypt failed", e);
    return internalError();
  }

  const { token, expiresIn } = await mintAccessToken({
    userId:    user.id,
    printerId: row.printer_id,
  });

  return jsonResponse({
    tunnel_url:   tunnelUrl,
    access_token: token,
    expires_in:   expiresIn,
  });
});
