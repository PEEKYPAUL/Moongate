# Security

> The README has a [TL;DR version of this](README.md#security). This is the full audit-grade write-up — what we defend, what we don't, and how to verify both. If you find something wrong here please open an issue or contact me directly (see [Reporting a vulnerability](#reporting-a-vulnerability) below).

---

## Threat model

What Moongate **claims** to protect:

| You | Adversary | Defence |
|---|---|---|
| You ran `MOONGATE_PAIR` once | A stranger somehow learning the tunnel URL | URL alone is useless without a JWT — every API call requires one |
| You scanned the QR code on your PC | A bystander seeing the screen for ~2 s | Code is 10-minute TTL, 5 attempts, single-use; the embedded JWT is single-use |
| You installed the app on your phone | Another app on the same phone trying to read the JWT | Token sits in Android Keystore via `flutter_secure_storage` — hardware-encrypted, sandboxed to our app's UID |
| You lost the phone | Whoever finds it tries to control your printer | Revoke that one token from any other paired device; every other device keeps working |
| Someone records your remote-access request mid-flight | Replays it later | Revocation is real-time. Also: every request is HTTPS (tunnel) so capturing it requires breaking TLS first |
| You're at a friend's house showing off the app | His WiFi happens to share your home subnet *and* an unrelated device is at your printer's IP | Status poll's 3 s timeout + non-Moonraker response detection routes back to tunnel; the WebView's `onHttpError` no longer surfaces an overlay for this case (v0.2.18) |

What Moongate **does not** claim to protect:

| Situation | Why we can't help |
|---|---|
| The Pi itself is compromised (rooted, malicious user has shell) | The JWT signing secret lives at `~/.config/moongate/secret.key`. If an attacker reads it, they can forge tokens. We use file mode 0600 + owner-only, but root sees everything. **You must trust your Pi.** |
| Your unlocked phone is in a hostile party's hands | Android Keystore stops other apps from reading the token; it doesn't stop someone using the unlocked app interactively |
| Cloudflare is compromised or compelled (subpoena, court order) | Cloudflare terminates TLS on their edge. They see the request URL, headers, and body in plaintext. Their ToS apply. If this is unacceptable for your threat model, swap `cloudflared` for a self-hosted tunnel — the rest of Moongate doesn't change |
| HTTP traffic between your phone and the Pi is sniffed on your LAN | Local Moonraker is HTTP. This is the standard Klipper setup, not a Moongate choice. If you need LAN encryption, put nginx + TLS in front of Moonraker (outside Moongate's scope) |
| You port-forward port 80 / 7125 from your router to the Pi | Don't. The whole point of the Cloudflare tunnel is so you never need to. If you do anyway, anyone who finds the IP can hammer Moonraker directly |
| A malicious developer pushes a backdoored APK | All releases are GitHub Actions builds from `master`. You can read the commits. You can build the APK yourself (see [DEVELOPMENT.md](DEVELOPMENT.md)) |

---

## Authentication

### JWT — format

| Field | Value |
|---|---|
| **Algorithm** | HS256 (HMAC-SHA256) |
| **Header** | `{"alg":"HS256","typ":"JWT"}`, base64url-encoded |
| **Payload** | `{"sub":"<token_id>","iat":<unix>,"exp":<unix>}` (the `exp` claim is omitted only if `ttl_days` was explicitly `null`) |
| **Signature** | `base64url(HMAC-SHA256(secret, header + "." + payload))` |
| **Library** | None. Pure stdlib (`hashlib`, `hmac`, `json`, `base64`) — no external Python dep means no supply-chain surface beyond what Moonraker already pulls in |

The signing/verification code is short enough to read in full:

- `AuthManager._sign_token` in [`klipper-plugin/moongate_standalone.py`](klipper-plugin/moongate_standalone.py)
- `AuthManager._verify_token` in the same file

Verification uses **`hmac.compare_digest`** for the constant-time comparison — no timing side channel.

### JWT — the secret key

```
Path:    ~/.config/moongate/secret.key
Created: Auto-created on first plugin load
Source:  os.urandom(32)
Size:    32 bytes (256 bits)
Mode:    0600 (owner read/write only)
Owner:   The user running Moonraker (typically `pi` or `klipper`)
```

The secret never leaves the Pi. It is never sent in any request, written to any log, or exposed via any API.

Rotating the secret: `rm ~/.config/moongate/secret.key && sudo systemctl restart moonraker`. This invalidates every previously-issued token. You'll need to re-pair every device.

### Token lifecycle

Each device gets its own token with these properties:

| Property | Value |
|---|---|
| **`token_id`** | UUID v4 |
| **`device_name`** | String the app sent at pair time (e.g. "Samsung S24") |
| **`issued_at`** | Unix timestamp of issue |
| **`expires_at`** | Unix timestamp of expiry, or null. Default 30 days |
| **`last_seen`** | Unix timestamp; updated on every successful validate |
| **`revoked`** | Bool; true once explicitly revoked |

Stored at `~/.config/moongate/tokens.json` (the file is rewritten on every change — not append-only). Look there if you want to audit what's currently authorised.

### Revocation

Real-time. `POST /server/moongate/revoke` with `{"token_id":"..."}` (auth: a still-valid JWT for some token on the same Pi). Sets `revoked=true`, persists. Next validation of that token returns null → request rejected with 401.

This is the action to take if a phone is lost or you suspect a token has leaked. The other tokens are unaffected.

To revoke everything at once: rotate the secret (see above).

### Phone-side storage

`flutter_secure_storage` is used to read/write the token on the Dart side. On Android this backs onto the **Android Keystore**:

- The keystore key is bound to the device's hardware-backed `StrongBox` if available, otherwise the TEE
- The token is encrypted at rest with that key
- Another app on the same device running with a different UID cannot read it
- If the device is wiped, the keystore key is gone — the token is unrecoverable without a fresh pairing

The token is read once per `AuthService` call. It is held in process memory only for the duration of the call.

---

## Pairing flow

### How a pair code is built

```
Generation     → random.choices(string.digits, k=4) twice → "GATE-1234-5678"
Internal store → {raw: PairingCode(code, created_at, expires_at, attempts=0, used=False)}
Display TTL    → 10 minutes (configurable)
Attempt cap    → 5 wrong tries before invalidation
```

The character set is digits only (10⁸ combinations) — picked for easy typing on a phone keypad. Combined with the TTL and attempt cap, the **online brute-force success probability per code is ≈ 5 × 10⁻⁸**:

```
attempts allowed before the code dies = 5
total codes possible                   = 10^8
P(guess one of 5 random tries hits)    = 5 / 10^8 ≈ 5e-8
```

At 1 request/second that's still vastly below 1 successful guess per code lifetime. Codes also expire 10 minutes after generation regardless of attempt count.

### The two pair paths

**Manual code path** (user types the code):

```
PC (Klipper console)      Phone                   Pi (Moonraker + plugin)
─────────────────────     ─────────────           ────────────────────────
1. MOONGATE_PAIR
2.                        ──────────────────►     /pair (returns code + qr_payload + tunnel_url)
3. [code visible on        ←───── code (M118) ────
   console]
4.                        user types code
5.                        ────────────────────►   POST /auth {code, device_name}
6.                        ←──────── JWT ──────
7.                        store in Keystore
```

The JWT travels back over whichever URL the user told the app to use (local or tunnel). If local, it's HTTP on LAN — the attacker would need to be on the same LAN. If tunnel, it's HTTPS — the attacker would need to break TLS.

**QR path** (user scans the QR with the app):

```
PC (browser)              Phone                   Pi (Moonraker + plugin)
────────────              ─────────────           ────────────────────────
1.                                                MOONGATE_PAIR generates code + pre-issues JWT
                                                  internally; stores qr_url with token in it
2. moongate-pair.html
   loads
3. fetches /qr
4. renders QR
5.                        user scans QR
6.                        app parses URL params:
                          local, remote, token
7.                        no network call —
                          token is already in
                          hand from step 1
```

The pre-issued JWT in the QR is generated in step 1 and is visible only to whoever can see the screen rendering the QR. The code is still issued alongside and still tracked in `_pending_codes`, but the QR path doesn't *use* the code — the embedded JWT is the authentication. (If a user scans the QR on one phone and types the code on another, both succeed and end up with two valid tokens. This is intentional.)

Both paths produce a `DeviceToken` entry in `tokens.json`. The names of the tokens differ — "Paired via QR" vs whatever device name the app sent — so you can tell them apart in `/server/moongate/tokens`.

---

## Transport

### Local (LAN)

```
Phone ──HTTP/1.1── Wi-Fi router ──HTTP/1.1── Pi:80 (nginx) ── localhost:7125 (Moonraker)
```

- Plain HTTP. Same as Mainsail's own UI when you load it from a browser
- JWT carried as the `mg_token` query parameter on Moongate-plugin endpoints, or as part of the path on native Moonraker endpoints (which we currently call unauthenticated since they're standard Moonraker)
- Anyone on the same Wi-Fi can already reach Moonraker without Moongate, so we're not creating new exposure
- If you want LAN-level encryption: stand up nginx + Let's Encrypt or a self-signed cert, point Moonraker through it, and tell the Moongate app to use `https://` in the host field. Nothing in Moongate prevents this; we just don't ship it as the default because most setups don't need it

### Remote (Cloudflare Quick Tunnel)

```
Phone ──HTTPS/QUIC── Cloudflare edge ──TLS── cloudflared (on Pi) ── localhost:80 (nginx)
```

- `cloudflared` runs as a systemd service ([`moongate-tunnel.service`](klipper-plugin/install.sh)) configured by the installer
- The tunnel makes an **outbound** connection from the Pi to Cloudflare's edge — no inbound ports are opened on your router
- Cloudflare assigns a random subdomain like `racing-partly-mouse-surprised.trycloudflare.com`
- The subdomain is not enumerable (3 random words from a large dictionary), but **it should not be treated as a secret**. Treat it as you would a public URL. The JWT is the actual auth
- TLS is terminated at Cloudflare's edge, then re-established for the leg to the Pi. Cloudflare sees plaintext requests in between. **By using a Cloudflare tunnel you are accepting Cloudflare's [terms of service](https://www.cloudflare.com/website-terms/).**

If you don't want Cloudflare in the picture:

- **Self-hosted tunnel**: replace `cloudflared` with `wireguard` peer + nginx, `tailscale`, `frp`, `ngrok` (paid), or any other tunneling layer. Moongate doesn't care — it just needs a URL that reaches `localhost:80` on your Pi. Edit `klipper-plugin/install.sh` accordingly and re-pair
- **WireGuard (Phase 2)**: see the next section

---

## About the "VPN"

**The current shipping path is a Cloudflare HTTPS tunnel, not a VPN.** Despite the name `VpnService` appearing in the Android code, the app does not currently route any of your phone's traffic through anything. Your browser, social media apps, etc. are entirely unaffected when Moongate is running.

### Why the VPN code exists at all

A WireGuard-based path is planned for Phase 2:

- **Pi side**: implemented and functional. `WireGuardManager` in `moongate_standalone.py` can add/remove peers, generate per-device WireGuard configs, and rewrite `/etc/wireguard/wg0.conf`. The `/auth` endpoint accepts a `wg_pubkey` parameter and returns a usable `[Interface] … [Peer] …` config when WireGuard is configured on the Pi
- **Phone side**: stub only. `MoongateVpnService.kt` declares the `android.net.VpnService` so the OS recognises it (this is why you may see the VPN key icon in your status bar), but `connect()` only stores the config text — it does **not** create a TUN device, does **not** route any IP traffic. WireGuard-Go is not yet bundled

If you see the Android VPN key icon: **no traffic is being routed**. It's an OS-level indicator that an app has registered a `VpnService`, not that one is active. The app does not call `Builder().establish()`.

### What changes in Phase 2

When WireGuard does land:

- The app will route only `192.168.x.x` (or whatever your home subnet is) through the tunnel — not all phone traffic. Split-tunnel by default
- Cloudflare drops out of the picture for remote access. End-to-end is just phone ↔ WireGuard server on the Pi
- The JWT authentication on top stays exactly the same. WireGuard adds *network*-layer auth; JWT continues to add *application*-layer auth. Defence in depth

If/when this ships, this document will be updated and the README will move v0.2.x's Cloudflare-only status into history.

---

## What the plugin can see and do

The Moongate plugin is a Moonraker component, which means it runs in the Moonraker process with the privileges of whoever launched Moonraker (typically the `klipper` user). Moonraker has full control over Klipper.

Practical implications:

- **Any holder of a valid JWT can run `pause`, `resume`, `cancel`, or `firmware_restart`.** Print control is the explicit purpose of the auth-gated endpoints
- **Status polling reads any Moonraker object** the plugin asks for. We ask only for the well-known ones (`print_stats`, `extruder`, `heater_bed`, `display_status`, `virtual_sdcard`, the discovered chamber sensor)
- **The plugin does not run arbitrary G-code on behalf of JWT holders.** There is no `POST /server/moongate/gcode` endpoint. Print control is restricted to the four whitelisted actions in `_handle_control`. If you want to add more, you must edit `klipper-plugin/moongate_standalone.py` and audit the new behaviour
- **The plugin reads its own state from `~/.config/moongate/`**, the cloudflared log at `/run/moongate-tunnel.log`, and calls out to `systemctl` / `journalctl` to discover the tunnel URL when its own log lookup fails. It does not read `printer.cfg` or any other Klipper internals beyond what Moonraker exposes

---

## How to audit Moongate yourself

| Question | Where to look |
|---|---|
| How is the JWT signed? | `AuthManager._sign_token` in `klipper-plugin/moongate_standalone.py` |
| How is the JWT verified? | `AuthManager._verify_token` (same file) |
| How is the signing secret created? | `AuthManager._load_or_create_secret` (same file) |
| How does the pair code lifecycle work? | `AuthManager.generate_pair_code`, `exchange_code`, `_sweep_expired_codes` (same file) |
| Where are tokens stored on the Pi? | `~/.config/moongate/tokens.json`. Open and read — it's plain JSON |
| What endpoints exist and who can hit them? | `MoongatePlugin.__init__` calls `register_endpoint()` for each — grep for it |
| How is the JWT stored on the phone? | `mobile/lib/services/auth_service.dart` → `_storage.write(key: _tokenKey, ...)` using `flutter_secure_storage` |
| Is the JWT ever logged on the phone? | `auth_service.dart` logs `_token != null ? "present" : "null"` — the token value itself is not logged |
| Where does the Cloudflare tunnel get installed from? | `klipper-plugin/install.sh` sections 6 and 7. It downloads `cloudflared` from the official Cloudflare GitHub release |
| What ProGuard rules are active in release? | `mobile/android/app/proguard-rules.pro` |
| How does CI sign the APK? | `.github/workflows/build-android.yml` step "Set up release signing" — decodes a base64 keystore from GitHub Secrets |

If any of those don't match the code at HEAD, this document is wrong — please open an issue.

---

## Reporting a vulnerability

If you find a security issue, please **do not** open a public GitHub issue. Instead:

- Open a private security advisory: <https://github.com/PEEKYPAUL/Moongate/security/advisories/new>
- Or message [@PEEKYPAUL](https://github.com/PEEKYPAUL) directly

Reports should include:

1. The affected version (`Drawer → Moongate vX.Y.Z` or the value in `mobile/pubspec.yaml`)
2. A short description of the issue
3. The simplest steps to reproduce it
4. The impact you believe it has

Reasonable-disclosure window: I'll aim to acknowledge within 7 days and ship a fix within 30 days when feasible. Coordinated disclosure timing is welcome — if you're a researcher with a publication plan, say so in the initial report.

There is no bug bounty. There is gratitude.
