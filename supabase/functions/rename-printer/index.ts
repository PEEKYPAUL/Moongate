// POST /functions/v1/rename-printer
//
// User-JWT only (the app's Edit-printer dialog and its launch catch-up):
//   Authorization: Bearer <supabase jwt>
//   body: { "printer_id": "<uuid>", "name": "<new display name>" }
//
// Writes the printer's display name to its row. The iPhone push title is
// built server-side by send-push from printers.name, and until this function
// existed the row kept the pairing-time name for ever: a typo corrected in
// the app still headed every notification. Android builds its notifications
// from the phone's own list and never needed this.
//
// Clients have UPDATE revoked on printers (v03 schema), so the write goes
// through the service role here, scoped to the caller's own un-revoked row.
// Idempotent: renaming to the current name is a 200 like any other.
//
// Errors:
//   400 - malformed body, printer_id not a uuid, name empty or over 64 chars
//   401 - missing/invalid JWT
//   404 - no un-revoked printer with that id under this owner (constant
//         shape, same as release-printer: no existence leak)
//   500 - internal

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  jsonResponse, badRequest, unauthorized, notFound,
  methodNotAllowed, internalError,
} from "../_shared/responses.ts";
import { adminClient, getUserFromRequest } from "../_shared/supabaseClients.ts";

const MAX_NAME_LENGTH = 64; // mirrors printer-claim
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  const user = await getUserFromRequest(req);
  if (!user) return unauthorized();

  let body: { printer_id?: unknown; name?: unknown };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  const printerId = body.printer_id;
  if (typeof printerId !== "string" || !UUID_RE.test(printerId)) {
    return badRequest("printer_id required (uuid)");
  }
  const name = typeof body.name === "string" ? body.name.trim() : "";
  if (name.length === 0 || name.length > MAX_NAME_LENGTH) {
    return badRequest(`name required (1-${MAX_NAME_LENGTH} chars)`);
  }

  const db = adminClient();
  const { data, error } = await db
    .from("printers")
    .update({ name })
    .eq("id", printerId)
    .eq("owner_user_id", user.id)
    .is("revoked_at", null)
    .select("id");

  if (error) {
    console.error("rename-printer update error", error);
    return internalError();
  }
  if (!data || data.length === 0) return notFound();
  return jsonResponse({ ok: true });
});
