// Standard response helpers.
//
// 404 / 401 use identical shapes regardless of underlying cause to avoid
// enumeration leaks. Do NOT add detail strings to error responses that
// would let a caller distinguish "doesn't exist" from "not yours" from
// "expired" — that's the whole point.

import { corsHeaders } from "./cors.ts";

const JSON_HEADERS = { ...corsHeaders, "Content-Type": "application/json" };

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

export function emptyResponse(status: number): Response {
  return new Response(null, { status, headers: corsHeaders });
}

export function notFound(): Response {
  return jsonResponse({ error: "not_found" }, 404);
}

export function unauthorized(): Response {
  return jsonResponse({ error: "unauthorized" }, 401);
}

export function forbidden(): Response {
  return jsonResponse({ error: "forbidden" }, 403);
}

export function conflict(detail: string): Response {
  return jsonResponse({ error: "conflict", detail }, 409);
}

export function serviceUnavailable(retryAfterSeconds: number): Response {
  return new Response(
    JSON.stringify({ error: "service_unavailable", retry_after: retryAfterSeconds }),
    {
      status: 503,
      headers: { ...JSON_HEADERS, "Retry-After": retryAfterSeconds.toString() },
    },
  );
}

export function badRequest(detail = "bad_request"): Response {
  return jsonResponse({ error: "bad_request", detail }, 400);
}

export function methodNotAllowed(): Response {
  return jsonResponse({ error: "method_not_allowed" }, 405);
}

export function internalError(): Response {
  return jsonResponse({ error: "internal_error" }, 500);
}
