# Troubleshooting

The common failure modes and how to diagnose them, in roughly the order people hit them. v0.2.x-specific fixes that landed long ago are no longer listed here - see [CHANGELOG.md](CHANGELOG.md) for the bug-fix history.

## Tile shows "Connecting…" longer than ~10 seconds

The app gives every printer up to one full poll cycle (4 s) before falling back to the tunnel, then up to another 8 s for the tunnel attempt. If a tile stays on "Connecting…" longer than ~15 s on a fresh launch:

- Check Moonraker is running on the Pi:
  ```bash
  sudo systemctl status moonraker
  ```
- Check the Moongate plugin loaded:
  ```bash
  grep -i moongate ~/printer_data/logs/moonraker.log | tail -20
  ```
- Check the auth proxy is running (v0.4+):
  ```bash
  sudo systemctl status moongate-authproxy
  ```
- Check the tunnel service:
  ```bash
  sudo systemctl status moongate-tunnel
  ```

All four (`moonraker`, `klipper`, `moongate-authproxy`, `moongate-tunnel`) need to be `active (running)` for the tile to flip from "Connecting…" to a live status.

## KlipperScreen: "Cannot connect to Moonraker - Connection refused"

Moongate binds Moonraker to `127.0.0.1` (localhost) during install, so the only thing exposed on your network is the EdDSA-gated tunnel proxy - not Moonraker itself. Any client **on the Pi** that reaches Moonraker by its **LAN IP** (instead of localhost) therefore stops working and shows `[Errno 111] Connection refused`. KlipperScreen is the usual one to break, since it's often configured with the Pi's IP.

Point it at `127.0.0.1`. Edit `~/printer_data/config/KlipperScreen.conf`, find the `[printer <name>]` section, and set the Moonraker host to localhost:

```ini
[printer My Printer]
moonraker_host: 127.0.0.1
moonraker_port: 7125
```

This lives under `[printer …]`, **not** `[server]` - KlipperScreen has no `[server]` section and rejects the file with *"Section [server] not recognized"* if you add one. If there's no `moonraker_host` line, add it under the existing `[printer …]` header. Then restart KlipperScreen - over SSH:

```bash
sudo systemctl restart KlipperScreen
```

…or restart it from the **Services** panel in Mainsail / Fluidd (no SSH needed).

`127.0.0.1` is also sturdier than a LAN IP - it survives the Pi's address changing on a DHCP renewal. A client on a **separate device** (a standalone KlipperScreen tablet, a second Pi) can't use localhost and is fundamentally incompatible with the rebind; run it on the printer Pi instead.

## All your printers suddenly show offline (and you use a VPN)

If every printer goes offline at once, especially after reinstalling the app or changing networks, and trying to connect shows a `trycloudflare.com` address failing, check whether a **VPN** on your phone is in the way.

Moongate reaches your printers either on your home Wi-Fi or over a Cloudflare tunnel. A VPN reroutes the app's traffic through the VPN's own servers, which usually can't reach your home network or the tunnel, so every printer reads offline.

- **If you use a VPN with per-app "split tunnelling"** (Mullvad and similar), Moongate needs to be on the **excluded / bypass** list so it skips the VPN. **Reinstalling the app removes it from that list**, so re-add Moongate to the split-tunnelling exclusions after any reinstall.
- **Otherwise, turn the VPN off** and reopen Moongate. If the printers come back, the VPN was the cause.
- The same applies to ad-blocker, private-DNS, and firewall apps that run as a "VPN" on Android. They can block the connection the same way.

If a printer still shows offline with the right address after the printer's Pi has rebooted, **force-stop Moongate and reopen it**. The app caches a printer's remote address for a while, and a reboot can change it, so a force-stop makes the app fetch the current one.

## A printer you switched back on still shows offline

If you power a printer back on (from Home Assistant, a smart plug, or its own switch) while Moongate is in the background, its tile can still read **offline** when you return to the app.

To save battery, your phone can freeze Moongate while it's in the background, which briefly drops its live-status link - so on return the app still thinks the printer is off, even though the notifications may already show it back. Since **v0.9.45**, Moongate re-checks every printer's live status the moment you switch back to it, so the tile clears itself within a few seconds, no force-close needed. On older versions, force-stop Moongate and reopen it to refresh.

## Chamber temperature missing on the dashboard

If a printer's chamber temperature doesn't appear on its tile even though it shows in Mainsail, update to **v0.9.32 or newer**. That release made chamber detection robust for combined chamber sensors (`temperature_combined`) and sensors named with capital letters, especially over the remote tunnel.

## The light bulb shows the wrong state (on when the light's off)

The bulb's on/off comes from the **Light Status Source** you set for that printer (**menu → Lighting**). If it's blank, the bulb just tracks your taps and assumes the light starts *off* - so it can read backwards. Set it to the light's Klipper object: the `[output_pin …]`, `[led …]` or `[neopixel …]` section name from your `printer.cfg` - e.g. `output_pin caselight` (the object name, **not** a raw pin like `PE3`). The bulb then follows that object's real value and self-corrects on each poll, even when you switch the light from Mainsail.

## Tile shows "Connected - Printer idle"

This is **not** an error - it's the v0.4 way of saying "the Pi is reachable, but Klipper isn't producing usable status right now". Common causes:

- The printer's power toggle inside Mainsail is off (Creality K3 and similar - Klipper isn't running until the printer-power switch is on).
- Klipper crashed or is in an error state. Check `~/printer_data/logs/klippy.log` for the cause.
- The Pi is rebooting and Klipper hasn't come back up yet.
- **Just after restoring a backup:** the printer loads fine when you tap the tile, but the dashboard sits on "Connected - Printer idle". The Pi is likely on a **pre-v0.6.3 plugin** that doesn't yet recognise the restored app - update the plugin (*Mainsail → Update Manager*, or re-run the installer) and restart Moonraker.

If the printer should be ready and the tile still shows "Connected - Printer idle":
- Restart Klipper: `sudo systemctl restart klipper`
- Restart Moonraker: `sudo systemctl restart moonraker`

The tile will flip to live status within a couple of poll cycles after the underlying issue clears.

Not sure which cause applies? **Menu → Report a problem** (in the app) sends a diagnostic report that records exactly why the status request failed - `404` (endpoint / proxy route missing), `401` (auth / owner), or `timeout` (slow or wrong network) - so it can be pinned down without guesswork. Since **v0.6.4** the report also carries the **remote (tunnel)** result and the **Pi's plugin version**, so an out-of-date plugin (a frequent cause of "works on LAN, fails remotely") shows up at a glance.

## Tile shows "Offline - Printer unreachable"

The app's reachability probe got no response from either the LAN URL or the tunnel URL. Either the Pi is fully unreachable (powered off, network cable out, WiFi router down) or every service on it is down. Verify with:

```bash
ping <pi-ip>
curl -s -o /dev/null -w "%{http_code}\n" http://<pi-ip>/
curl -s -o /dev/null -w "%{http_code}\n" https://<your-tunnel-url>/
```

- The first should respond.
- The second should return `200` (or `301`/`302`) if nginx is up.
- The third should return `401` if the auth proxy is running. ANY HTTP code (even 401, 502) proves the tunnel side is alive.

If none of the three respond, the Pi is fully offline. If only the third fails, restart `moongate-tunnel` and `moongate-authproxy`.

## Tile shows "Tunnel" badge when I'm on home WiFi

In v0.4.0 the app retries LAN on every poll, so this should self-correct within one cycle (~4 s). If it doesn't:

- Force-close the app and re-open. The LAN URL is rebuilt from the cached config + the current status reply.
- Verify the Pi's LAN IP hasn't changed (DHCP lease expired and got a new address):
  ```bash
  ip -4 addr show | grep -A1 'state UP'
  ```
- If the IP changed: remove the printer in the app and re-pair on the new IP. The LAN URL persists across launches but isn't auto-discovered after a DHCP change.

## Remote tunnel not connecting

- Check the systemd unit:
  ```bash
  sudo systemctl status moongate-tunnel
  ```
- View the captured stdout (this is where the tunnel URL appears):
  ```bash
  cat /run/moongate-tunnel.log
  ```
- The Cloudflare Quick Tunnel URL changes on **every** restart of `cloudflared`. The app fetches the latest URL automatically - you do not need to re-pair when this happens.

## Re-pairing takes minutes to show online

After re-pairing a printer (reinstalling the app, moving to a new phone, or running `MOONGATE_RESET_OWNER`), the tile can sit on "Starting up…" for several minutes before it connects - most noticeable on networks where the app can't reach the Pi directly over local WiFi.

Fixed in **plugin 0.6.7+**: the Pi now reports its connection to the cloud within seconds of the re-pair, instead of waiting for its next 5-minute check-in. **Plugin 0.6.9** hardens this further - if the Pi hits a brief network hiccup at that exact moment (common on flaky-WiFi boards), it keeps retrying every few seconds rather than dropping back to the 5-minute wait. **Re-run the Pi installer** (or update via **Mainsail → Software Updates → Moongate**) to get the latest. Scanning the QR instead of typing the GATE code also connects instantly over local WiFi.

## Auth proxy returns 401 for me, not just attackers

If your own app is getting 401s from the tunnel side (status tile is stuck offline, but LAN works):

- Verify the access proxy is running and the plugin can sign valid tokens:
  ```bash
  sudo systemctl status moongate-authproxy
  journalctl -u moongate-authproxy -n 50
  ```
- Check `~/.config/moongate/owner.json` exists and references your user. If it's missing or refers to a stale pair, run `MOONGATE_RESET_OWNER` in the Klipper console and re-pair.
- A token mismatch can happen if the device signing key was regenerated (uninstall / re-install / manual `~/.config/moongate/` wipe). The app's cached token becomes invalid. Force-close and re-open the app - it'll refresh on next poll.

## Remote access fails over the internet but LAN works (v0.6.3 Pi)

If a printer is healthy on home WiFi but every **remote (tunnel)** request fails - typically a **500** - and the Pi was last updated around **v0.6.3**, this is the v0.6.3 auth-proxy regression. The proxy failed *closed* (it denied every request - nothing was exposed), which is why LAN access kept working and it slipped through.

**Fix:** update the Pi to **v0.6.4 or newer** (*Mainsail → Update Manager*, or re-run the installer), then let the services restart:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash
```

A bug report (see above) now shows the **Pi's plugin version**, so you can confirm the Pi is on v0.6.4+ afterwards.

## Webcam not showing

- The app uses the snapshot path Moonraker reports for your webcam - typically `/webcam/?action=snapshot` for mjpg-streamer setups.
- Make sure your webcam is configured in Mainsail / Fluidd under Settings → Webcams, and the snapshot URL works in a browser on your LAN.
- If you don't have a webcam, the tile falls back to the **Mainsail or Fluidd logo** (whichever you run). That's the expected v0.4 behaviour - it's not an error.

## A custom / external camera isn't showing (v0.9.0+)

You can point a tile at a camera that isn't connected to Klipper (e.g. an old phone running an IP-webcam app) via the **gear** in the corner of the tile's camera. If it doesn't appear:

- **Use the camera's snapshot or stream URL** - the same address that works in a browser on your LAN (e.g. `http://192.168.0.107:8080/video`). The tile pulls one frame at a time, so a stream URL is fine; the camera's web-UI *page* URL is not.
- **On Wi-Fi but blank?** Confirm the URL opens in your phone's browser while on the same network. The app fetches the camera directly on the LAN, so if the browser can't reach it, neither can the tile.
- **Works on Wi-Fi but not remotely (cellular)?** Remote cameras go through the Pi, which needs the **v0.9.0 / plugin 0.6.8+** update - re-run the Pi installer (or *Mainsail → Software Updates*) and let it restart. Also note: only **home-network (private) cameras** can be reached remotely; a camera on a public address won't relay through the tunnel, by design.
- **Auto-detected camera wrong or missing?** Moongate reads the *first* webcam from Mainsail's webcam list. If you have several, set the one you want by hand with the gear, or reorder them in Mainsail.
- **Gears in the way?** Turn them off under **Menu → Camera config icons** - that hides every tile's gear without affecting the camera feed.

## A tile shows the logo, or a printer has no camera at all

If a tile shows the **Mainsail/Fluidd logo** instead of a live picture, that feed just isn't loading - the printer is offline or connecting, or it has no camera configured. The full-screen camera view (the eye on a tile, or the camera icon on the printer page) still works whenever there's a feed.

If a printer has **no camera area at all** (a slim, compact tile), its webcam is switched **off**: open **Menu → Webcams** and turn it back on. Turning a printer's webcam off there collapses its tile to save space and data; turning it on restores the full tile with its feed.

## The power button isn't showing on my printer's tile

The power button (bottom-left of a tile's camera) appears only when **Moonraker reports a power device** - a `[power …]` section in `moonraker.conf` (any type: GPIO, Shelly, TP-Link, Tasmota, …). It's detected automatically; there's no app setting. If it's missing:

- **No power device configured.** Add a `[power <name>]` section to `moonraker.conf` and restart Moonraker.
- **Moonraker isn't reachable.** The button needs to reach Moonraker over WiFi or the tunnel. A printer powered *off* by its own device is fine - Moonraker stays up, so the button shows (dim) and can switch it back on. But if the whole **Pi** is off, nothing answers and no button shows.

Mid-print, the button is **greyed out** for a device Moonraker marks `locked_while_printing` - it won't cut power to a running print.

## "Power all machines" skips a printer, or won't switch a macro printer

The top-bar **Power all machines** button (switch it on in the menu) powers your whole fleet at once, and it only shows the buttons your fleet supports. A printer that's **printing** is always left on, and one that's **offline** is skipped.

If a printer's power is a **Klipper macro** (the Advanced Power Switch) rather than a Moonraker power device, give it a **Power Off** (and/or Power On) macro and the fleet button will use it. A single **toggle** macro works only from that printer's own tile button, not from Power all machines, because a toggle can't tell which way to switch a whole fleet at once. Most macro setups are **power-off only** (you can't switch a machine back on with a Klipper macro once it's off), and that's fine: the fleet button just shows that printer as "off only".

## What's the red triangle on a tile? (Emergency stop)

Every **online** tile shows a small red warning triangle by its temperatures - it's an **emergency stop**. **Double-tap** it to halt the printer immediately with Klipper's `M112`; a single tap does nothing, so a stray touch can't fire it, and there's no confirm dialog (the double-tap *is* the safeguard).

After an emergency stop the machine is **shut down**, not just idle - so the triangle turns into an **orange restart button**. Tap it once to run `FIRMWARE_RESTART` and bring the printer back online; the triangle returns once it's healthy. The restart is a deliberate manual tap rather than automatic, since an emergency stop can mean something's worth checking first.

## In-app update didn't install, or asks for a permission

Tapping **Update** downloads the new version inside the app, then hands it to Android's package installer. The **first** time, Android asks you to allow Moongate to **install unknown apps** - expected for an app installed outside the Play Store. Grant it (the system jumps you straight to the toggle), come back, and tap **Update** again; after that it's a single tap plus the standard install confirmation.

If the download or install fails for any reason, Moongate **falls back to opening the APK in your browser** - finish there and open it to install. Either route installs **in place** over your existing app (same signing key), so your printers and settings are kept.

## QR scan won't work / camera fails

- Grant camera permission when prompted, or via **Settings → Apps → Moongate → Permissions → Camera**.
- The QR scanner only works in **release** builds with the ProGuard rules in [`mobile/android/app/proguard-rules.pro`](mobile/android/app/proguard-rules.pro). Debug builds also work; R8 doesn't run in debug.
- If the camera opens but fails to read the code: type the **GATE code** instead. Tap **+** to open Add Printer; the two 4-digit boxes for the `GATE-XXXX-XXXX` code shown in the Klipper console are right below the Scan QR button (numpad keyboard).

## Pairing fails / "already paired" error

In **v0.4.2+** the recovery is one macro: `MOONGATE_RESET_OWNER` on the Pi (Klipper console) wipes the local owner record **and** releases the cloud-side association (the Pi signs the release request with its own device key - same key it already uses for heartbeats). Then `MOONGATE_PAIR` and pair again from any app install.

Before v0.4.2 the cloud row could be orphaned by a fresh app install (new anonymous identity), which would cause `already_paired` on re-pair. That's gone now - the Pi can clean up its own cloud row without the original app being reachable.

## All tiles offline after reinstalling the app (or a new phone)

**Symptom:** You reinstalled Moongate, or switched to a new phone, and every printer shows offline - even on your home WiFi.

**Cause:** A fresh install creates a new anonymous app identity. Your printers are still associated with the *previous* identity in the cloud, so a brand-new install owns nothing.

**Fix (v0.6.3+): restore from a config backup.** If the backup was made by **v0.6.3 or newer**, it carries a single-use restore code that re-links your printers to the new install - they come back **online automatically, with no re-pairing**. Use **Menu → Restore config**, or **Import config from file** on the Add Printer screen. Each Pi must be on the **v0.6.3+ plugin** (update via *Mainsail → Update Manager*, or re-run the installer) so it recognises the restored app - otherwise restored tiles sit on "Connected / idle" (see above). Since **v0.6.4** the app is explicit about the result - it tells you which printers actually came back online and which still need a re-pair, instead of always reporting success.

**If your backup predates v0.6.3** (no restore code), or you don't have one, re-pair each printer: on the Pi run `MOONGATE_RESET_OWNER` then `MOONGATE_PAIR`, and scan the QR (or type the GATE code) in the app.

> **Best practice:** back up your config *before* you uninstall - a v0.6.3+ backup carries the restore code, so restoring on the new install brings everything back online.

## Tunnel URL leakage - what's actually exposed in v0.4?

**Nothing.** This was a real concern in v0.2.x where the tunnel terminated at nginx serving Mainsail without auth. In v0.4 the tunnel terminates at the auth proxy, which returns flat 401s for every request without a valid short-lived token. The URL alone is useless. Share it with anyone - they get 401s.

See [SECURITY.md → "What the tunnel actually exposes (v0.4)"](SECURITY.md#what-the-tunnel-actually-exposes-v04) for the empirical 35-vector attack-matrix verification.

If you're still running v0.2.x: upgrade. The known browser-direct-to-Mainsail hole was the explicit driver for v0.4.0.

## Moonraker behind a reverse proxy (Traefik, Caddy, NPM) or in Docker

Moongate assumes the standard Klipper layout: it connects to your printer **directly over plain HTTP, by IP address, on your LAN** - by default port 80, where one web server serves the Mainsail/Fluidd page *and* proxies the Moonraker API. A homelab where Moonraker sits behind a hostname-routing reverse proxy (Traefik, Caddy, Nginx Proxy Manager) or runs in Docker breaks that assumption:

- Moongate talks to an **IP over plain HTTP** - no hostname, no HTTPS - so a proxy that terminates TLS on 443 and routes by hostname is never in a form Moongate can use.
- The LAN address Moongate advertises comes from the printer host's own "which interface reaches the internet" lookup. Inside a Docker bridge network that returns a container-internal address (e.g. `172.x.x.x`) your phone can't reach.

You don't have to route Moongate *through* your proxy - you just have to give it a plain-HTTP door straight to your Klipper web stack. Your existing `https://…` proxy hostname can stay exactly as it is; Moongate simply doesn't use it. (Remote access, when you're away from home, runs over Moongate's own tunnel and is independent of your proxy.)

### "Connection refused" right after adding the printer

Adding a printer is a cloud step, so the tile appears even with no local connectivity. The first status poll then tries `http://<ip>:<http_port>/server/moongate/status`, nothing is listening there, and you get connection refused.

**Easiest - set the address in the app:** when adding the printer, expand **Advanced - printer on a custom network?** and enter the address you use to open its web page in a browser (e.g. `192.168.1.50:7125`). Already added it? Open the printer, tap the ✏️ icon, and set **Printer address** there. This points the app straight at your printer and skips the auto-discovery a reverse-proxy / Docker setup breaks - no server changes needed. Use an address that serves the Mainsail/Fluidd **page**, since that same origin also proxies the API - that's what fixes "Bad Gateway" below, too.

**Server-side alternative** - makes the QR and auto-discovery advertise the right port for *every* device:

1. Expose your Klipper web server (the one serving Mainsail/Fluidd) on the LAN on a normal HTTP port - not only the proxy's `https://…` hostname. If it runs in Docker, publish that port to the **host's LAN**, not just the container network.
2. On the machine running Moonraker, edit (create if missing) `~/.config/moongate/config.json` and set that port:
   ```json
   { "http_port": 80 }
   ```
   Use whatever port that web server actually listens on - `80` is the default; set e.g. `"http_port": 8080` if that's what you exposed. (In Docker this file lives under the home of the user Moonraker runs as, *inside* the container.)
3. Restart Moonraker so the plugin reloads, then **re-pair** in the app - remove the printer and add it again so the new pairing carries the right port.
4. Pair while your phone is on the **same WiFi/LAN** as the printer; initial pairing is LAN-only by design.

If the address still looks wrong (the app lands on a `172.x` Docker address it can't reach), run the Moonraker container with **host networking** so it advertises your real LAN IP.

### Tile connects, but opening the printer shows "Bad Gateway" (502)

The dashboard tile only uses the Moonraker **API** (`/server/…`). Tapping into a printer opens the **full Mainsail/Fluidd web page** in a built-in browser, by loading `http://<ip>:<http_port>/`. A 502 there is emitted by *your* web server or proxy - the app reached that layer, but it couldn't get the page from its upstream.

The usual cause: `http_port` points at **Moonraker directly (port 7125)**, which serves the API but has no web page, or at a proxy whose web-UI backend is down. `http_port` must point at the origin that serves **both** the Mainsail/Fluidd page **and** proxies the Moonraker API - the same single URL a browser uses to open your printer's interface.

**Confirm it's server-side, not the app** - on a computer on the same network, open the exact URL the app uses, `http://<the-ip-and-http_port-you-set>/`, in a browser:

- Bad Gateway in the browser too → it's your server/proxy config, not Moongate. Whatever serves that port can't reach its upstream (the Mainsail/Fluidd files, or Moonraker).
- The interface loads fine in the browser but not in the app → [open an issue](https://github.com/PEEKYPAUL/Moongate/issues/new); that's unusual.

**Fix:** point Moongate at the origin that serves the Mainsail/Fluidd page *and* proxies `/server`, `/websocket`, `/printer` to Moonraker. Quickest is in the app - open the printer, tap ✏️, and set **Printer address** to the address you open the web page at. Server-side, set `http_port` to that same port and restart Moonraker. Then re-open the printer.

## Software Update panel shows an `inferred` version for Moongate

**Symptom:** In Mainsail/Fluidd → **Settings → Software Update**, the Moongate entry shows something like `v0.0.0-1-gff62f74f-inferred` or a bare commit hash instead of a clean `v0.6.5`.

**Cause:** The Pi was set up with an older installer that did a **shallow clone** (`git clone --depth=1`). A shallow clone carries no git tags, and Moonraker derives a component's version from tags - with none present it falls back to an inferred placeholder. This is cosmetic: one-click updates still work (Moonraker compares your commit against `origin/master`, not the tag), and the plugin itself is unaffected.

**Fix:** Re-run the installer once. It detects the shallow clone and re-clones with full tag history (a small *blobless* clone), after which the panel shows a proper version:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash
```

Your pairing, owner state, and device key live in `~/.config/moongate/` and are **not** touched. The old clone is preserved alongside the new one (e.g. `~/moongate.shallow-<timestamp>/`); you can delete it once the panel looks right.

> The version in the panel tracks the **whole-project release** (the same `vX.Y.Z` as the app), so it's the number to quote when reporting a plugin issue.

## Need to capture a fresh log

For mobile-side issues:

```bash
# Stream logs from the running app process
adb logcat --pid=$(adb shell pidof com.moongate.app.moongate)

# Or filter by tag - the app uses "MOONGATE" for its own dev.log() calls
adb logcat -s MOONGATE
```

For plugin-side issues:

```bash
# Live tail of Moonraker (the moongate plugin logs here)
journalctl -u moonraker -f

# or directly:
tail -f ~/printer_data/logs/moonraker.log
```

For auth-proxy issues (v0.4+):

```bash
journalctl -u moongate-authproxy -f
```

For tunnel issues:

```bash
journalctl -u moongate-tunnel -f
tail -f /run/moongate-tunnel.log
```

## Anything else

- Read [CHANGELOG.md](CHANGELOG.md) for the version history - many issues from earlier releases have known fixes
- Read [SECURITY.md](SECURITY.md) for auth / transport / threat-model questions
- Open a [GitHub issue](https://github.com/PEEKYPAUL/Moongate/issues/new) with the relevant logcat / journalctl output if none of the above match
