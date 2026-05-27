// Short-lived (~5 min) access tokens minted by /printer-access and verified
// on the Pi.
//
// Algorithm: EdDSA (Ed25519). Private key is a JWK stored in
// MOONGATE_JWT_SIGNING_KEY env var. Public key is exposed via the /jwks
// Edge Function so the Pi can fetch it for verification.
//
// Why asymmetric: if the Pi is ever compromised, an attacker holding only
// the public key cannot mint tokens. Symmetric (HS256 with Supabase's main
// JWT secret) would let a Pi-side compromise mint JWTs for any Supabase
// user — too large a blast radius.

import * as jose from "npm:jose@5";

const ACCESS_TOKEN_TTL_SECONDS = 300; // 5 minutes
export const KID      = "moongate-access-1";
export const AUDIENCE = "moongate-printer";
export const ISSUER   = "moongate";
export const ALG      = "EdDSA";

interface CachedKeys {
  privateKey: CryptoKey;
  publicJwk:  jose.JWK;
}

let cached: CachedKeys | null = null;

async function loadKeys(): Promise<CachedKeys> {
  if (cached) return cached;

  const raw = Deno.env.get("MOONGATE_JWT_SIGNING_KEY");
  if (!raw) throw new Error("MOONGATE_JWT_SIGNING_KEY not set");

  let jwk: jose.JWK;
  try {
    jwk = JSON.parse(raw);
  } catch {
    throw new Error("MOONGATE_JWT_SIGNING_KEY is not valid JSON (expected an Ed25519 OKP JWK)");
  }

  if (jwk.kty !== "OKP" || jwk.crv !== "Ed25519") {
    throw new Error("MOONGATE_JWT_SIGNING_KEY must be an Ed25519 OKP JWK (kty=OKP, crv=Ed25519)");
  }

  const privateKey = await jose.importJWK(jwk, ALG) as CryptoKey;

  // Strip the private 'd' component to produce a public-only JWK
  const publicJwk: jose.JWK = {
    kty: jwk.kty,
    crv: jwk.crv,
    x:   jwk.x,
    kid: KID,
    alg: ALG,
    use: "sig",
  };

  cached = { privateKey, publicJwk };
  return cached;
}

export async function mintAccessToken(opts: {
  userId:    string;
  printerId: string;
}): Promise<{ token: string; expiresIn: number }> {
  const { privateKey } = await loadKeys();
  const now = Math.floor(Date.now() / 1000);

  const token = await new jose.SignJWT({
    printer_id: opts.printerId,
    jti:        crypto.randomUUID(),
  })
    .setProtectedHeader({ alg: ALG, kid: KID, typ: "JWT" })
    .setSubject(opts.userId)
    .setAudience(AUDIENCE)
    .setIssuer(ISSUER)
    .setIssuedAt(now)
    .setExpirationTime(now + ACCESS_TOKEN_TTL_SECONDS)
    .sign(privateKey);

  return { token, expiresIn: ACCESS_TOKEN_TTL_SECONDS };
}

export async function publicJwks(): Promise<{ keys: jose.JWK[] }> {
  const { publicJwk } = await loadKeys();
  return { keys: [publicJwk] };
}
