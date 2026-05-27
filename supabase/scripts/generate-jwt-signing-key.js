// generate-jwt-signing-key.js
//
// Generates an Ed25519 keypair and prints the PRIVATE key as a JWK JSON
// string. That JSON goes into MOONGATE_JWT_SIGNING_KEY (Supabase Edge
// Functions secrets). The public key is derivable from the private key
// and is automatically exposed via the /jwks Edge Function — you don't
// need to copy it anywhere.
//
// Run from PowerShell:
//   node .\supabase\scripts\generate-jwt-signing-key.js
//
// Output is printed to console only. NOT saved to disk.
// Copy the JWK JSON into your password manager AND into Supabase Edge
// Functions secrets. Do NOT paste it into any chat or commit it anywhere.

const crypto = require("crypto");

const { privateKey, publicKey } = crypto.generateKeyPairSync("ed25519");

const privateJwk = privateKey.export({ format: "jwk" });
const publicJwk  = publicKey.export({  format: "jwk" });

// jose expects these annotations for sig keys
privateJwk.alg = "EdDSA";
privateJwk.use = "sig";

const json = JSON.stringify(privateJwk);

console.log("");
console.log("MOONGATE_JWT_SIGNING_KEY (private JWK JSON — secret):");
console.log("");
console.log("    " + json);
console.log("");
console.log("Public key (for reference; auto-served by the /jwks endpoint):");
console.log("    " + JSON.stringify(publicJwk));
console.log("");
console.log("Next steps:");
console.log("  1. Copy the PRIVATE JWK JSON above into your password manager.");
console.log("  2. Supabase dashboard -> Edge Functions -> Manage secrets.");
console.log("  3. Add a secret named MOONGATE_JWT_SIGNING_KEY with the JSON as value.");
console.log("  4. Save.");
console.log("");
console.log("Do NOT commit this key. Rotating it invalidates all in-flight access tokens.");
console.log("");
