// POST /functions/v1/release-printer
//
// Called by the app when the user taps "Remove printer". Deletes the printer
// row in Supabase so the Pi can be re-paired. Idempotent: returns 200 even
// if the row is already gone.
//
// Caller MUST present a Supabase JWT in the Authorization header.
// Ownership is enforced inside the RPC; non-owners get an indistinguishable
// 404 response.
//
// Request body:
//   { "printer_id": "<uuid>" }
//
// Response 200:
//   { "ok": true }
//
// Errors:
//   400 — malformed body
//   401 — no/invalid JWT
//   404 — printer exists but not owned by caller (constant shape)
//   500 — internal

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  jsonResponse, badRequest, unauthorized, notFound,
  methodNotAllowed, internalError,
} from "../_shared/responses.ts";
import { adminClient, getUserFromRequest } from "../_shared/supabaseClients.ts";

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
});
