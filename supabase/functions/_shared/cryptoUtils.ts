// Crypto helpers used by the Edge Functions:
//   - AES-256-GCM encryption of tunnel URLs (master key from env var)
//   - Ed25519 signature verification of Pi heartbeats
//   - SHA-256 hashing of enrollment tokens
//   - base64 encoding helpers

function getMasterKeyBytes(): Uint8Array {
  const b64 = Deno.env.get("MOONGATE_TUNNEL_URL_KEY");
  if (!b64) throw new Error("MOONGATE_TUNNEL_URL_KEY not set");
  const bytes = base64ToBytes(b64);
  if (bytes.length !== 32) {
    throw new Error(`MOONGATE_TUNNEL_URL_KEY must decode to 32 bytes; got ${bytes.length}`);
  }
  return bytes;
}

let cachedMasterKey: CryptoKey | null = null;
async function masterKey(): Promise<CryptoKey> {
  if (cachedMasterKey) return cachedMasterKey;
  cachedMasterKey = await crypto.subtle.importKey(
    "raw",
    getMasterKeyBytes(),
    "AES-GCM",
    false,
    ["encrypt", "decrypt"],
  );
  return cachedMasterKey;
}

/**
 * Encrypt a tunnel URL with AES-256-GCM.
 * Returns base64-encoded ciphertext and nonce, ready for SQL insertion.
 */
export async function encryptTunnelUrl(url: string): Promise<{ ciphertextB64: string; nonceB64: string }> {
  const key = await masterKey();
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    new TextEncoder().encode(url),
  );
  return {
    ciphertextB64: bytesToBase64(new Uint8Array(ciphertext)),
    nonceB64:      bytesToBase64(nonce),
  };
}

/**
 * Decrypt a tunnel URL. Inputs are base64-encoded as returned by the RPC
 * functions (which use encode(..., 'base64') in SQL).
 */
export async function decryptTunnelUrl(ciphertextB64: string, nonceB64: string): Promise<string> {
  const key = await masterKey();
  const ciphertext = base64ToBytes(ciphertextB64);
  const nonce      = base64ToBytes(nonceB64);
  const plaintext  = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(plaintext);
}

/**
 * Verify an Ed25519 signature. publicKey and signature are base64-encoded.
 * Returns false on any decoding/verification error (constant-failure shape).
 */
export async function verifyEd25519(
  publicKeyB64: string,
  signatureB64: string,
  message: Uint8Array,
): Promise<boolean> {
  try {
    const pk  = base64ToBytes(publicKeyB64);
    const sig = base64ToBytes(signatureB64);
    if (pk.length !== 32 || sig.length !== 64) return false;
    const key = await crypto.subtle.importKey("raw", pk, "Ed25519", false, ["verify"]);
    return await crypto.subtle.verify("Ed25519", key, sig, message);
  } catch {
    return false;
  }
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

// ---- base64 ----

export function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}
