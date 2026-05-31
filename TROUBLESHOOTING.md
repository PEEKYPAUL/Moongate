# Troubleshooting

The common failure modes and how to diagnose them, in roughly the order people hit them. v0.2.x-specific fixes that landed long ago are no longer listed here — see [CHANGELOG.md](CHANGELOG.md) for the bug-fix history.

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

## Tile shows "Connected — Printer idle"

This is **not** an error — it's the v0.4 way of saying "the Pi is reachable, but Klipper isn't producing usable status right now". Common causes:

- The printer's power toggle inside Mainsail is off (Creality K3 and similar — Klipper isn't running until the printer-power switch is on).
- Klipper crashed or is in an error state. Check `~/printer_data/logs/klippy.log` for the cause.
- The Pi is rebooting and Klipper hasn't come back up yet.

If the printer should be ready and the tile still shows "Connected — Printer idle":
- Restart Klipper: `sudo systemctl restart klipper`
- Restart Moonraker: `sudo systemctl restart moonraker`

The tile will flip to live status within a couple of poll cycles after the underlying issue clears.

## Tile shows "Offline — Printer unreachable"

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
- The Cloudflare Quick Tunnel URL changes on **every** restart of `cloudflared`. The app fetches the latest URL automatically — you do not need to re-pair when this happens.

## Auth proxy returns 401 for me, not just attackers

If your own app is getting 401s from the tunnel side (status tile is stuck offline, but LAN works):

- Verify the access proxy is running and the plugin can sign valid tokens:
  ```bash
  sudo systemctl status moongate-authproxy
  journalctl -u moongate-authproxy -n 50
  ```
- Check `~/.config/moongate/owner.json` exists and references your user. If it's missing or refers to a stale pair, run `MOONGATE_RESET_OWNER` in the Klipper console and re-pair.
- A token mismatch can happen if the device signing key was regenerated (uninstall / re-install / manual `~/.config/moongate/` wipe). The app's cached token becomes invalid. Force-close and re-open the app — it'll refresh on next poll.

## Webcam not showing

- The app uses the snapshot path Moonraker reports for your webcam — typically `/webcam/?action=snapshot` for mjpg-streamer setups.
- Make sure your webcam is configured in Mainsail / Fluidd under Settings → Webcams, and the snapshot URL works in a browser on your LAN.
- If you don't have a webcam, the tile falls back to the **Mainsail or Fluidd logo** (whichever you run). That's the expected v0.4 behaviour — it's not an error.

## QR scan won't work / camera fails

- Grant camera permission when prompted, or via **Settings → Apps → Moongate → Permissions → Camera**.
- The QR scanner only works in **release** builds with the ProGuard rules in [`mobile/android/app/proguard-rules.pro`](mobile/android/app/proguard-rules.pro). Debug builds also work; R8 doesn't run in debug.
- If the camera opens but fails to read the code: type the **GATE code** instead. Tap **+** to open Add Printer; the two 4-digit boxes for the `GATE-XXXX-XXXX` code shown in the Klipper console are right below the Scan QR button (numpad keyboard).

## Pairing fails / "already paired" error

In **v0.4.2+** the recovery is one macro: `MOONGATE_RESET_OWNER` on the Pi (Klipper console) wipes the local owner record **and** releases the cloud-side association (the Pi signs the release request with its own device key — same key it already uses for heartbeats). Then `MOONGATE_PAIR` and pair again from any app install.

Before v0.4.2 the cloud row could be orphaned by a fresh app install (new anonymous identity), which would cause `already_paired` on re-pair. That's gone now — the Pi can clean up its own cloud row without the original app being reachable.

## All tiles offline after reinstalling the app (or a new phone)

**Symptom:** You reinstalled Moongate, or switched to a new phone, and every printer shows offline — even sitting on your home WiFi.

**Cause:** A fresh install creates a new anonymous app identity. Your printers are still associated with the *previous* identity in the cloud, so the new install owns nothing and every tile reads offline. Importing a config backup brings back the printer names and layout, but not the cloud association.

**Fix:** Re-pair each printer. On the Pi, run `MOONGATE_RESET_OWNER` in the Klipper console, then `MOONGATE_PAIR`, and scan the QR (or type the GATE code) in the app.

> **Save yourself a step:** run `MOONGATE_RESET_OWNER` *before* you uninstall the old app. Then a fresh install just needs `MOONGATE_PAIR` and a scan.

## Tunnel URL leakage — what's actually exposed in v0.4?

**Nothing.** This was a real concern in v0.2.x where the tunnel terminated at nginx serving Mainsail without auth. In v0.4 the tunnel terminates at the auth proxy, which returns flat 401s for every request without a valid short-lived token. The URL alone is useless. Share it with anyone — they get 401s.

See [SECURITY.md → "What the tunnel actually exposes (v0.4)"](SECURITY.md#what-the-tunnel-actually-exposes-v04) for the empirical 35-vector attack-matrix verification.

If you're still running v0.2.x: upgrade. The known browser-direct-to-Mainsail hole was the explicit driver for v0.4.0.

## Need to capture a fresh log

For mobile-side issues:

```bash
# Stream logs from the running app process
adb logcat --pid=$(adb shell pidof com.moongate.app.moongate)

# Or filter by tag — the app uses "MOONGATE" for its own dev.log() calls
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

- Read [CHANGELOG.md](CHANGELOG.md) for the version history — many issues from earlier releases have known fixes
- Read [SECURITY.md](SECURITY.md) for auth / transport / threat-model questions
- Open a [GitHub issue](https://github.com/PEEKYPAUL/Moongate/issues/new) with the relevant logcat / journalctl output if none of the above match
