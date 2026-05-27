# Security

> The README has a [TL;DR version](README.md#how-it-works) of the architecture. This is the longer write-up — what we defend, what we don't, and how to verify both. If you find something wrong here please open an issue or contact me directly (see [Reporting a vulnerability](#reporting-a-vulnerability) below).

---

## What changed in v0.4

The v0.2 version of this document documented a known hole in the original Cloudflare-Quick-Tunnel design: the tunnel terminated at nginx on the Pi, which served Mainsail to anyone with the URL. **v0.4 closes that hole.** The Cloudflare tunnel now terminates at an auth proxy on the Pi that rejects any request without a short-lived signed access token; nginx and Moonraker are no longer reachable directly from the internet.

If you're running v0.2.x and want the protection in v0.4: re-install via the v0.4 `install.sh` and re-pair. No data migrates from v0.2 — it's a hard cutover.

---

## Threat model

What Moongate **claims** to protect (v0.4):

| You | Adversary | Defence |
|---|---|---|
| Your printer is paired | A stranger somehow learning the tunnel URL — saw your screen, fished it out of a log, social-engineered a friend | The Pi-side auth proxy gates every internet-facing path behind a short-lived signed access token. The URL alone returns flat `401 Unauthorized` with a constant-length 13-byte body, no `WWW-Authenticate`, no `Server` header, no fingerprint of what's running underneath. **Empirically verified** across a 35-vector attack matrix on a live tunnel — see [Verifying the promise](#verifying-the-promise) below |
| You scanned the QR code on your PC | A bystander seeing the screen for a few seconds | Pair codes are time-limited, attempt-capped, single-use. The pair page is **LAN-only** — visiting the equivalent URL through the tunnel returns 401 |
| You installed the app on your phone | Another app on the same phone trying to read your session | Sensitive material is stored via `flutter_secure_storage` → Android Keystore (hardware-encrypted, sandboxed to the app's UID) |
| You lost the phone | Whoever finds it tries to control your printer | Un-pair the printer from any other paired device — `Dashboard → Remove printer`. The cloud middleman releases the association and any cached tokens become useless. The lost phone must re-pair from scratch (which requires being on your home WiFi) to recover access |
| Someone records a request mid-flight | Replays it later | Every request goes over HTTPS (tunnel) or HTTP-on-LAN. Access tokens are short-lived (minutes, not days); the replay window is small, and the same token never works again after refresh |
| You're at a friend's house showing the app | His WiFi happens to share your home subnet AND an unrelated device sits at your printer's LAN IP | The LAN attempt fails to produce a valid Moongate-shaped response — the tile falls through to the tunnel within ~2 s |

What Moongate **does not** claim to protect:

| Situation | Why we can't help |
|---|---|
| The Pi itself is compromised (rooted, malicious user has shell) | The device signing key lives on the Pi. If an attacker has root, they can sign requests. We rely on standard POSIX file permissions (mode 0600, owner-only) — sufficient against the standard "other Pi user" / "Moonraker bug grants read access to non-owner files" cases, useless against root. **You must trust your Pi.** |
| Your unlocked phone is in a hostile party's hands | Android Keystore stops other apps from reading the session; it doesn't stop someone using the unlocked app interactively. They have the same access you would |
| The cloud middleman is compromised | The middleman's compromise is bounded — it can issue tokens but cannot send G-code. An attacker who fully compromises the middleman could issue tokens for any printer paired to it. We rely on the operator's security; the [`docs/v0.3-supabase-design.md`](docs/v0.3-supabase-design.md) design doc covers the specific isolation guarantees and the layered defences (per-tenant database-side isolation, per-Pi key binding, per-tenant token-claim binding) |
| Cloudflare is compromised or compelled (subpoena, court order) | Cloudflare terminates TLS at their edge. They see request URLs, headers, and bodies in plaintext for the leg between your phone and the edge. Their ToS apply. If this is unacceptable, swap `cloudflared` for any other tunnel that points at the auth proxy's port — Moongate doesn't care which tunnel you use |
| HTTP traffic between your phone and the Pi is sniffed on your LAN | Local Moonraker is plain HTTP. This is the standard Klipper setup, not a Moongate choice. The access token is sent in headers; on LAN, anyone with the WiFi password who is actively MITM-ing your TCP can read it. If you need LAN encryption, put nginx + TLS in front of Moonraker (outside Moongate's scope) |
| You port-forward port 80 / 7125 from your router to the Pi | Don't. The whole point of the tunnel + auth proxy is so you never need to. If you do anyway, the public LAN port bypasses the auth proxy and anyone who finds the IP can hammer Moonraker directly |
| A malicious developer pushes a backdoored APK | All releases are GitHub Actions builds from `master`. You can read the commits. You can build the APK yourself (see [DEVELOPMENT.md](DEVELOPMENT.md)) |
| You pair a friend's phone and they later misuse it | Once paired, a phone has full operator-level control over the printer. Same as handing them the Mainsail URL on your LAN. Un-pair the device from `Dashboard → Remove printer` when you no longer want them to have access |

---

## What the tunnel actually exposes (v0.4)

Short answer: **just 401s.**

Every request through `https://<your-tunnel>.trycloudflare.com` reaches the auth proxy first. The proxy checks for a valid short-lived access token in (priority order):

1. `Authorization: Bearer <token>` header
2. `mg_token=<token>` cookie
3. `mg_token=<token>` query parameter

If none of those is valid, the proxy returns `401 Unauthorized` with:
- A constant-length 13-byte body (`unauthorized\n`)
- `Cache-Control: no-store`
- **No** `WWW-Authenticate` challenge (would tell an attacker what kind of auth is expected)
- **No** `Server` header (would tell an attacker what's behind it)
- **No** Moonraker-specific headers, no nginx fingerprint, no Mainsail HTML

If the token IS valid, the proxy forwards to nginx, which routes to Mainsail / Moonraker / the webcam stream / the Moongate plugin exactly as it always did on LAN.

### Verifying the promise

The "tunnel URL leak → nothing" promise was empirically tested across a 35-vector attack matrix on a live tunnel during v0.4.0 testing. Covered:

- **Path traversal:** bare `/`, `/moongate-pair.html`, `/index.html`, literal `..`, percent-encoded `%2e%2e`
- **Native Moonraker endpoints:** `/printer/info`, `/server/info`, `/printer/objects/list`, `/server/files/list`, `/access/info`, `/machine/system_info`, `/api/version`
- **Dangerous POSTs:** `gcode/script` (with `M104 S280` to try heating the hotend), `print/start`, `emergency_stop`, `firmware_restart`, `files/upload` multipart, `DELETE /files/...`
- **Garbage auth:** Bearer with random bytes, `mg_token` cookie with random bytes, query-param with random bytes, all three combined
- **WebSocket upgrades:** with and without WS headers
- **Method variants:** HEAD, OPTIONS, PUT, PATCH
- **Mainsail static assets:** chunked JS bundle names, manifest, config.json, favicons
- **Fingerprinting:** poking response headers for `Server`, `X-Powered-By`, version banners

Every single vector returned 401 with the constant 13-byte body. The only headers reaching the client come from Cloudflare itself (`Server: cloudflare`, `CF-Ray: ...`) — those identify Cloudflare's edge, not what's behind it.

To verify on your own Pi: pick any path, hit it with `curl -s -o /dev/null -w "%{http_code} %{size_download}\n" https://<your-tunnel>/whatever`. You should see `401 13`. If you see anything else, please open an issue.

### What an attacker with a valid token CAN do

If an attacker somehow obtains a *live, unexpired* token (e.g. they have root on the Pi and read the signing key, or they have control of the cloud middleman):

- Everything Mainsail can do — control the printer in real time, upload G-code, run macros, watch the webcam, trigger emergency stop, etc.

The token IS the perimeter. We protect the token; the token protects the printer.

---

## Pairing flow

### LAN-only by design

The pair page is reachable at `http://<pi-ip>/moongate-pair.html` on your home WiFi only. Visiting the equivalent URL through the tunnel returns 401, because the auth proxy gates everything — including the pair page — and the user pairing does not yet have a token.

This is intentional. Pairing requires being on the same network as the Pi anyway; gating the pair page closes the v0.2.x window where a leaked tunnel URL meant anyone could pair their own device.

### The two pair paths

**Manual code path** (user types the code):

```
PC / tablet (Klipper console)    Phone (Moongate app)         Pi
────────────────────────────     ────────────────────         ────────────────
1. MOONGATE_PAIR
2. [code visible in console]
3.                               user types code
4.                               app → middleman → claim ──►  plugin sees new owner
                                                              on next heartbeat
5.                               printer appears in
                                 dashboard
```

**QR path** (user scans the QR with the app):

```
PC / tablet (browser)            Phone (Moongate app)         Pi
────────────────────────────     ────────────────────         ────────────────
1.                                                            MOONGATE_PAIR generates
                                                              code + pair record
2. open moongate-pair.html       
   on the LAN URL
3. browser fetches QR
4. renders QR
5.                               user scans QR
6.                               app → middleman → claim ──►  plugin sees new owner
                                                              on next heartbeat
7.                               printer appears in
                                 dashboard
```

Both paths produce the same outcome: an entry in the dashboard, and the printer's auth proxy newly aware that this user is the owner.

---

## Transport

### LAN

```
Phone ──HTTP/1.1── WiFi router ──HTTP/1.1── Pi:80 (nginx) ── localhost:7125 (Moonraker)
```

- Plain HTTP. Same as Mainsail's own UI when you load it from a browser.
- The access token is carried in the `Authorization: Bearer` header on every Moongate-mediated call. Moonraker's own endpoints (called as a fallback) ignore the header — they're trusted-clients on LAN by default.
- Anyone on the same WiFi can already reach Moonraker without Moongate, so we're not creating new exposure.
- If you want LAN-level encryption: stand up nginx + Let's Encrypt or a self-signed cert, point Moonraker through it, and the Moongate app will hit it the same way (HTTPS LAN URL works the same as HTTP LAN URL).

### Remote (Cloudflare Quick Tunnel)

```
Phone ──HTTPS/QUIC── Cloudflare edge ──TLS── cloudflared (on Pi) ── localhost:<auth_proxy>
                                                                       │
                                                                       ▼
                                                                     nginx (on localhost)
                                                                       │
                                                                       ▼
                                                                     Moonraker / Mainsail / webcam
```

- `cloudflared` runs as `moongate-tunnel.service` configured by the installer.
- The tunnel makes an **outbound** connection from the Pi to Cloudflare's edge — no inbound ports are opened on your router.
- Cloudflare assigns a random subdomain like `racing-partly-mouse-surprised.trycloudflare.com`. The subdomain rotates each time `cloudflared` restarts.
- The subdomain is not enumerable (random words from a large dictionary), but **it does not need to be a secret** — leaking it gives an attacker only 401s. The access token is the actual auth.
- TLS is terminated at Cloudflare's edge and re-established for the leg to the Pi. Cloudflare sees plaintext requests in between. **By using a Cloudflare tunnel you are accepting Cloudflare's [terms of service](https://www.cloudflare.com/website-terms/).**

If you don't want Cloudflare in the picture, point the cloudflared step at any other tunneling layer that reaches the auth proxy's port (Tailscale Funnel, frp, ngrok paid, a self-hosted nginx-on-VPS reverse proxy, etc.). The auth proxy doesn't care what's in front of it.

---

## What the plugin can see and do

The Moongate plugin is a Moonraker component, which means it runs in the Moonraker process with the privileges of whoever launched Moonraker (typically the `klipper` or `pi` user). Moonraker has full control over Klipper.

Practical implications:

- **Any holder of a valid access token can run `pause`, `resume`, `cancel`, or `firmware_restart`.** Print control is the explicit purpose of the auth-gated `/server/moongate/control` endpoint.
- **Status polling reads Moonraker objects** that the plugin asks for — `print_stats`, `extruder`, `heater_bed`, `display_status`, `virtual_sdcard`, the discovered chamber sensor. Nothing else.
- **The plugin does not run arbitrary G-code on behalf of token holders.** There is no `POST /server/moongate/gcode` endpoint. Print control is restricted to the four whitelisted actions; adding more requires editing [`klipper-plugin/moongate_standalone.py`](klipper-plugin/moongate_standalone.py) and auditing the new behaviour.
- **The plugin reads its own state from `~/.config/moongate/`** and calls `systemctl` / `journalctl` to discover the current tunnel URL when its own log lookup fails. It does not read `printer.cfg` or any other Klipper internals beyond what Moonraker exposes.

The auth proxy is even more constrained — it doesn't talk to Klipper at all, it just routes HTTP / WebSocket between Cloudflare and nginx. The verifier classes it uses for token checks are imported from the plugin file, not duplicated, so signature semantics stay single-source.

---

## How to audit Moongate yourself

| Question | Where to look |
|---|---|
| How is each request authenticated on the Pi side? | [`klipper-plugin/moongate_authproxy.py`](klipper-plugin/moongate_authproxy.py) — `AccessTokenVerifier` is imported from `moongate_standalone.py` and called per request |
| What endpoints does the plugin expose, and which are gated? | `MoongatePlugin.__init__` in `klipper-plugin/moongate_standalone.py` — grep for `register_endpoint`. Anything under `/server/moongate/*` reaching the plugin already cleared the auth proxy on the tunnel side |
| What does the proxy return for an unauthenticated request? | [`klipper-plugin/moongate_authproxy.py`](klipper-plugin/moongate_authproxy.py) — search for the constant 401 path |
| Where are tokens stored on the phone? | [`mobile/lib/services/supabase_service.dart`](mobile/lib/services/supabase_service.dart) — the app's session uses `flutter_secure_storage` underneath, backed by Android Keystore |
| What about per-printer access tokens? | [`mobile/lib/services/printer_access_cache.dart`](mobile/lib/services/printer_access_cache.dart) — short-lived, in-memory only, refreshed via the middleman |
| Where does the Cloudflare tunnel get installed from? | [`klipper-plugin/install.sh`](klipper-plugin/install.sh) — downloads `cloudflared` from the official Cloudflare GitHub release |
| What ProGuard rules are active in release? | [`mobile/android/app/proguard-rules.pro`](mobile/android/app/proguard-rules.pro) |
| How does CI sign the APK? | [`.github/workflows/build-android.yml`](.github/workflows/build-android.yml) step "Set up release signing" — decodes a base64 keystore from GitHub Secrets |
| What's the deep design rationale for the cloud middleman? | [`docs/v0.3-supabase-design.md`](docs/v0.3-supabase-design.md) and [`docs/v0.4-secure-remote-access-design.md`](docs/v0.4-secure-remote-access-design.md) — threat model, key isolation guarantees, alternatives discussion (why not WireGuard / Tailscale / ZeroTier / mesh VPN) |

If any of those don't match the code at HEAD, this document is wrong — please open an issue.

---

## What we explicitly chose not to do

These are real options that came up during v0.4 design and were rejected, in case you're wondering why we didn't.

- **WireGuard on Android.** Requires the user to grant the OS-level `VpnService` permission, which Google Play increasingly disfavours for non-VPN-product apps. No native NAT-traversal mechanism — needs a relay anyway for ~85% of home networks. Closed off at the design stage; see the alternatives appendix in [`docs/v0.4-secure-remote-access-design.md`](docs/v0.4-secure-remote-access-design.md).
- **Tailscale / Headscale / ZeroTier / NetBird.** Either paid above 3 nodes, requires accounts, or requires self-hosting infrastructure that defeats "no VPN setup". Documented in the same appendix.
- **Browser-side Mainsail login via `force_logins` in Moonraker.** Was the v0.2.x recommended mitigation; the auth-proxy approach in v0.4 is strictly stronger (no Mainsail HTML ever leaves the Pi for unauthenticated requests) and doesn't require the user to type a Moonraker password into Mainsail every time the cookie expires.
- **A Moongate-operated print server / relay.** Would centralise G-code, print history, and live status with us. Off the table — both for privacy and for "this is meant to stay a tiny project".

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
