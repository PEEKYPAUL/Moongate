// POST /functions/v1/send-push
//
// Called by the Pi (Moongate plugin) when a print changes state. Delivers a
// background notification to the printer owner's iPhone(s) via Apple's APNs.
// Android is intentionally not handled here yet (it keeps its existing
// foreground-service notifications); the device_push_tokens platform column
// lets Android join later without touching this contract.
//
// Auth model: identical to printer-heartbeat. The Pi has no Supabase user; it
// signs a canonical payload with its Ed25519 device key, and we look the
// printer up by pi_public_key and verify. Replay is bounded by a 60s window.
//
// Request body:
//   {
//     "pi_public_key": "<base64 Ed25519 pubkey>",
//     "event":         "started" | "completed" | "failed" | "error" | "custom",
//     "detail":        "<optional - gcode filename, shutdown reason, or for
//                       "custom" the whole message (plugin 0.6.25+)>",
//     "timestamp":     <unix seconds>,
//     "signature":     "<base64 Ed25519 signature over canonical payload>"
//   }
//
// Canonical payload (UTF-8 bytes signed by Pi):
//   "moongate-push\n" + pi_public_key + "\n" + event + "\n" + detail + "\n" + timestamp
//
// Response 204 on success (including "owner has no iOS devices" - nothing to do
// is still success). Errors mirror printer-heartbeat: 400 / 401 / 404 / 500.

import { handleCorsPreflight } from "../_shared/cors.ts";
import {
  emptyResponse, badRequest, unauthorized, notFound,
  methodNotAllowed, internalError,
} from "../_shared/responses.ts";
import { adminClient } from "../_shared/supabaseClients.ts";
import { verifyEd25519, base64ToBytes } from "../_shared/cryptoUtils.ts";
import { sendApns, ApnsAlert } from "./apns.ts";

const REPLAY_WINDOW_SECONDS = 60;
const MAX_DETAIL = 200;
const EVENTS = new Set(["started", "completed", "failed", "error", "custom"]);

// Server-side message text. English for v1; APNs loc-keys can localise this
// later against the app's iOS strings without changing the signed contract.
function buildAlert(event: string, printerName: string, detail: string): ApnsAlert {
  // "custom" (plugin 0.6.25+, the MOONGATE_NOTIFY macro): the detail IS the
  // message, already sanitised and capped on the Pi (and re-capped here).
  if (event === "custom") {
    return { title: printerName, body: detail || "Notification" };
  }
  const base = event === "started"
    ? "Print started"
    : event === "completed"
    ? "Print finished"
    : event === "error"
    ? "Printer error"
    : "Print failed";
  return { title: printerName, body: detail ? `${base}: ${detail}` : base };
}

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return methodNotAllowed();

  let body: {
    pi_public_key?: unknown;
    event?:         unknown;
    detail?:        unknown;
    timestamp?:     unknown;
    signature?:     unknown;
  };
  try {
    body = await req.json();
  } catch {
    return badRequest("invalid_json");
  }

  const piPubKey  = body.pi_public_key;
  const event     = body.event;
  const timestamp = body.timestamp;
  const signature = body.signature;
  // detail is optional; normalise to a capped string (also part of the signed
  // payload, so "" must be signed when absent, and the signature must be
  // checked over the text AS SIGNED - sanitising waits until after
  // verification, for display only.
  const detailRaw = typeof body.detail === "string" ? body.detail.slice(0, MAX_DETAIL) : "";

  if (typeof piPubKey !== "string") return badRequest("pi_public_key required");
  if (typeof event !== "string" || !EVENTS.has(event)) {
    return badRequest("event must be started, completed, failed, error, or custom");
  }
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) {
    return badRequest("timestamp required (unix seconds)");
  }
  if (typeof signature !== "string") return badRequest("signature required");

  try {
    if (base64ToBytes(piPubKey).length !== 32) {
      return badRequest("pi_public_key must decode to 32 bytes");
    }
  } catch {
    return badRequest("invalid pi_public_key base64");
  }

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestamp) > REPLAY_WINDOW_SECONDS) return unauthorized();

  const canonical = `moongate-push\n${piPubKey}\n${event}\n${detailRaw}\n${timestamp}`;
  const message   = new TextEncoder().encode(canonical);
  if (!(await verifyEd25519(piPubKey, signature, message))) return unauthorized();

  // Verified - now scrub control chars for display. The 0.6.25 Pi sanitises
  // before signing anyway; this is the backstop for whatever else signs.
  const detail = detailRaw.replace(/[\u0000-\u001f\u007f]/g, " ");

  const db = adminClient();

  // Look the printer (and its owner) up by the verified key.
  const { data: printer, error: pErr } = await db
    .from("printers")
    .select("owner_user_id, name")
    .eq("pi_public_key", piPubKey)
    .is("revoked_at", null)
    .maybeSingle();
  if (pErr) {
    console.error("printer lookup error", pErr);
    return internalError();
  }
  if (!printer) return notFound(); // unpaired / revoked - Pi should re-pair

  // Fetch the owner's iOS device tokens.
  const { data: rows, error: tErr } = await db
    .from("device_push_tokens")
    .select("token")
    .eq("user_id", printer.owner_user_id)
    .eq("platform", "ios");
  if (tErr) {
    console.error("token lookup error", tErr);
    return internalError();
  }
  if (!rows || rows.length === 0) return emptyResponse(204); // nobody to notify

  const alert = buildAlert(event, printer.name, detail);

  // Deliver to each token; collect any APNs says are permanently dead.
  const dead: string[] = [];
  await Promise.all(rows.map(async ({ token }) => {
    try {
      const r = await sendApns(token as string, alert);
      if (r.unregistered) dead.push(token as string);
      else if (!r.ok) console.error("apns send failed", r.status, r.reason);
    } catch (e) {
      console.error("apns send threw", e);
    }
  }));

  // Prune dead tokens so we stop wasting sends on them.
  if (dead.length > 0) {
    const { error: dErr } = await db
      .from("device_push_tokens")
      .delete()
      .in("token", dead);
    if (dErr) console.error("token prune error", dErr);
  }

  return emptyResponse(204);
});
