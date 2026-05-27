// GET /functions/v1/jwks
//
// Public JWKS endpoint for the access-token signing key. The Pi fetches this
// (and caches it) to verify access tokens that the app presents.
//
// No auth required — this is intentionally public, like every JWKS endpoint.
//
// Response 200:
//   {
//     "keys": [
//       {
//         "kty": "OKP",
//         "crv": "Ed25519",
//         "x":   "<base64url>",
//         "kid": "moongate-access-1",
//         "alg": "EdDSA",
//         "use": "sig"
//       }
//     ]
//   }

import { handleCorsPreflight } from "../_shared/cors.ts";
import { jsonResponse, methodNotAllowed, internalError } from "../_shared/responses.ts";
import { publicJwks } from "../_shared/accessToken.ts";

Deno.serve(async (req) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;
  if (req.method !== "GET" && req.method !== "POST") return methodNotAllowed();

  try {
    const jwks = await publicJwks();
    return new Response(JSON.stringify(jwks), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        // Tell clients (Pi) they may cache for an hour. Adjust if we ever rotate.
        "Cache-Control": "public, max-age=3600",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (e) {
    console.error("jwks load failed", e);
    return internalError();
  }
});
