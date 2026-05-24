# Troubleshooting

The common failure modes and how to diagnose them, in roughly the order people hit them.

## Printer shows Offline

- Check that Moonraker is running:
  ```bash
  sudo systemctl status moonraker
  ```
- Confirm the plugin loaded — look for `[moongate]` in Moonraker's logs:
  ```bash
  grep -i moongate ~/printer_data/logs/moonraker.log
  ```
- Confirm `moonraker.conf` has the `[moongate]` block. The installer adds it automatically, but a manual edit could have removed it.

## Remote tunnel not connecting

- Check the systemd unit:
  ```bash
  sudo systemctl status moongate-tunnel
  ```
- View the captured stdout (this is where the tunnel URL appears):
  ```bash
  cat /run/moongate-tunnel.log
  ```
- The Cloudflare Quick Tunnel URL changes on **every** restart of `cloudflared`. The app fetches the latest URL automatically via the status endpoint on each poll, so you do **not** need to re-pair — the new URL is detected within a few seconds and persisted.

## Webcam not showing

- The app fetches snapshots from whatever path Moonraker reports for the configured webcam — typically `/webcam/?action=snapshot` for mjpg-streamer setups.
- Make sure your webcam is configured in Mainsail (or Fluidd) under Settings → Webcams, and that the URL works in a browser.
- If you're behind a non-standard port, the v0.2.22 install option `--port N` (or `MOONGATE_PORT=N`) needs to match — the tunnel will only forward to the port `cloudflared` was started with.

## Dashboard tile shows the wrong printer when on a friend's network

**Fixed in v0.2.18.** The app now compares your phone's WiFi subnet against each printer's at cold launch and on every resume. If they don't match it skips the local probe entirely and goes straight to the tunnel — no 3-second timeout, no false-positive from an unrelated device on the stranger LAN.

If you're on v0.2.18+ and still see this: the v0.2.26 "stuck on tunnel" auto-recovery should pick it back up within 20 s of you re-opening the dashboard. If not, force-close and reopen the app once.

## Camera error when scanning the QR code

- **Fixed in v0.2.19** (upgrade of `mobile_scanner` from 5.x to 7.x to dodge a Samsung One UI `analysis.resolutionInfo!!` NPE).
- **Fixed again in v0.2.20** (added ProGuard rules for ML Kit so R8 stops stripping the bundled barcode scanner — without them the release build crashes with an obfuscated NPE that doesn't happen in debug).
- If you're on v0.2.20+ and the camera still fails: grant camera permission when prompted, or go to **Settings → Apps → Moongate → Permissions** and enable Camera.

## Progress percentage on the tile doesn't match Mainsail

**Fixed in v0.2.16.** The app now uses `print_duration / estimated_time` from `/server/files/metadata` — the same formula Mainsail uses — instead of:

- `display_status.progress` (which is `0` until the slicer emits `M73` gcode), or
- `virtual_sdcard.progress` (which runs ahead of the actual toolhead position due to Klipper's look-ahead buffering)

The slicer's estimated time is fetched once per file and cached.

## In-app update banner not appearing

**Fixed in v0.2.27.** Before that version, the update check was a `FutureProvider.autoDispose` that ran once per session and never re-checked. If a new release went live while you had the app open, you'd never see the banner without force-closing and re-launching.

From v0.2.27 onward:

- The update check re-runs on every app **resume** (foregrounding from background)
- Each fetch appends a cache-buster to the manifest URL so GitHub's raw CDN can't serve a stale "no update" body

If you're stuck on a pre-v0.2.27 release, the workaround is:

1. Swipe up in the recents drawer to force-close the app
2. Re-launch from the icon
3. The fresh provider run will see the new manifest and show the banner

Or just download the latest APK manually from the [APK folder](https://github.com/PEEKYPAUL/Moongate/tree/master/APK).

## Tunnel URL leaks — what's actually exposed?

This isn't a bug, but it comes up enough to mention here. The Cloudflare tunnel exposes everything bound to `localhost:80` on your Pi — that's Mainsail, the Moonraker API, and the webcam stream, alongside the JWT-protected Moongate endpoints. **If someone gets your tunnel URL they can drive your printer through Mainsail without a token**, bounded to the printer (no LAN pivot, no SSH).

The full breakdown, including how to mitigate with Cloudflare Access or tightened Moonraker auth, lives in [SECURITY.md → "What does URL leakage actually expose?"](SECURITY.md#what-does-url-leakage-actually-expose).

## I shared my tunnel URL with someone and they got into my printer

This is a real incident if it happens to you. The Cloudflare tunnel exposes Mainsail at the root of the tunnel URL — anyone who can reach that URL, in a *browser*, can drive your printer. No app, no token, no QR code needed on their end. The pair page at `/moongate-pair.html` is also reachable, so even if they used the Moongate app instead they could scan the QR and pair their own device.

**Recover from it (in this order):**

1. **Run `MOONGATE_REVOKE_ALL` in your Klipper console.** Added in v0.2.29. This invalidates every issued device token, including theirs *and* yours — every paired Moongate device will need to re-pair. One command.

2. **Restart the Cloudflare tunnel to get a new URL:**
   ```bash
   sudo systemctl restart moongate-tunnel
   ```
   Cloudflare assigns a fresh random subdomain. The old URL is dead immediately. Your own app picks up the new URL automatically on the next status poll — no re-pairing needed beyond step 1.

3. **Re-pair your own devices** by running `MOONGATE_PAIR` once per device and scanning the new QR.

**To check who currently has access:**

```bash
MOONGATE_LIST_TOKENS
```

Added in v0.2.29. Lists every issued token with `device_name`, issued date, and active/expired/revoked state on the Mainsail console. Use this to spot which entry belongs to whoever you shared with vs your own devices, then `revoke` selectively via the API if you don't want to nuke all of them.

**To prevent it next time:**

- v0.2.29 also shortens the **QR's pre-issued token TTL from 30 days to 10 minutes** initially. The token only "promotes" to 30 days once the app actually uses it. So if you share the pair URL but the recipient doesn't scan within 10 minutes, the embedded token auto-expires. Doesn't close the full hole (browser-direct access to Mainsail still works while the tunnel is up), but it kills the QR-pairing leak window dead.
- For the *real* fix — closing browser-direct access to Mainsail — see [SECURITY.md → "What does URL leakage actually expose?"](SECURITY.md#what-does-url-leakage-actually-expose). The two practical options are Cloudflare Access (recommended; free; edge-level login) or removing `127.0.0.0/8` from Moonraker's `trusted_clients` with `force_logins: True`.

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
# Live tail of Moonraker
journalctl -u moonraker -f
# or
tail -f ~/printer_data/logs/moonraker.log
```

For tunnel issues:

```bash
journalctl -u moongate-tunnel -f
tail -f /run/moongate-tunnel.log
```

## Anything else

- Read [CHANGELOG.md](CHANGELOG.md) for the bug-fix history — many issues that surfaced in earlier releases have known fixes
- Read [SECURITY.md](SECURITY.md) for anything auth, transport, or tunnel-leak related
- Open a [GitHub issue](https://github.com/PEEKYPAUL/Moongate/issues/new) with the relevant logcat / journalctl output if none of the above match
