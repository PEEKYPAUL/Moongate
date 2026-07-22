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

## Updating Moongate from KlipperScreen looks stuck on "create mode 100644"

Cosmetic - the update has actually completed. A Moongate plugin update restarts Moonraker as its final step, and KlipperScreen's update console watches the update through a live Moonraker connection. The restart cuts that connection mid-scroll, so the console freezes on the last line it received (usually one of git's `create mode 100644` file lines) and the "finished" message never arrives. Close the dialog and carry on, or restart KlipperScreen from Mainsail's **Services** panel if it won't dismiss. You can confirm the update landed under **Machine → Software Updates**: Moongate shows up to date.

(Klipper itself is left alone on purpose: the plugin lives inside Moonraker, so a plugin update never needs to touch a running print.)

## The Pi acts strangely after weeks of uptime (failed updates, sudo password errors)

Plugin versions before **0.6.14** kept the remote-access proxy's request log on a small memory-backed disk (`/run`) that nothing trimmed. A printer left powered on for a few weeks could fill it completely, and a full `/run` makes unrelated things on the Pi misbehave: `sudo` fails with odd errors, updates act up, services get flaky. Check with:

```bash
df -h /run
```

If it shows 100% (and `du -sh /run/*` blames `moongate-authproxy.log`), that's this. Fix: **update the Moongate plugin to 0.6.14 or later** (Mainsail → Machine → Software Updates), which stops the log growing for good, then **reboot the Pi once** to empty the memory disk. After that it can't recur: the proxy now logs almost nothing, and what it does log goes to the system journal, which cleans up after itself.

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

## Your print-status notification vanished, or notifications stopped updating

If print notifications were on but the ongoing status notification is gone and you're no longer getting updates, you may have **paused** them. Since **v0.9.46** there's a **pause/play button** in the dashboard top bar (it appears when notifications are on): tapping **pause** stops Moongate checking your printers in the background, which saves battery and removes the ongoing notification. Tap the same button (now a **play** icon) to resume. A pause is remembered across app restarts and reboots, so it stays off until you tap play.

## Chamber temperature missing on the dashboard

If a printer's chamber temperature doesn't appear on its tile even though it shows in Mainsail, update to **v0.9.32 or newer**. That release made chamber detection robust for combined chamber sensors (`temperature_combined`) and sensors named with capital letters, especially over the remote tunnel.

## No time remaining on a printing tile

Since **v0.9.53** a printing tile shows the time left (or the projected finish time) after its temperatures. If it's missing:

- **The print just started.** The readout appears once the estimate is meaningful - roughly a couple of minutes in (about 2% progress). Too early, the maths would show nonsense, so it's withheld.
- **The print is paused.** A paused print's estimate can't be trusted (the print clock is frozen), so the readout hides until it resumes.
- **The switch is off.** Check **menu → Dashboard Layout → Show time remaining** - the same place also switches between **Time left** ("~1h09m") and **Finish time** ("15:27").

The tile and the print notification share the same estimate, so they always agree - but like Mainsail's ETA it's a projection from progress so far, and it settles as the print runs.

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

The app finds printers on your network two ways: the address it learned at pairing, and an automatic broadcast discovery (mDNS) that heals address changes. A tile stuck on **Tunnel** at home means both are failing for that printer - almost always a network quirk, not the printer:

- **The instant fix: set the address by hand.** Open the printer's page, tap the **pencil**, and type its LAN address into **Printer address** (e.g. `192.168.1.50`). That field exists precisely for networks where discovery can't work.
- **Separate 2.4GHz and 5GHz WiFi names?** Many routers block broadcast discovery *between* the two bands, so a phone on the "5G" network can never discover a printer on the 2.4GHz one. The manual address fixes it; joining the same band as the printer also works.
- **Still stuck even with the right address typed in?** Check the router / access point for a "client isolation" or "allow WiFi devices to communicate with each other" setting - and if everything looks right, **reboot the access point**. A real field case: an AP had silently stopped forwarding traffic from its 5GHz clients to its 2.4GHz clients entirely; a reboot fixed everything at once.
- **The Pi's IP changed** (a new DHCP lease)? Update the **Printer address** field - no need to remove or re-pair. When broadcast discovery works on your network this heals itself; the manual field is the belt-and-braces. Giving the printer a fixed IP in the router stops it recurring.
- Guest networks and some mesh systems isolate devices from each other by design - a printer on one of those may only ever be reachable through the tunnel.

## Every printer away from home shows offline (orange crossed-out cloud in the top bar)

That's the **Local only** switch (v0.9.48): while it's on, Moongate deliberately makes no remote connections, so only printers on your current network connect and everything else settles to offline. Tap the orange crossed-out cloud in the top bar to turn remote back on (a snackbar confirms), or turn the whole button off under the menu's **Local-only button** switch - switching the menu entry off also turns the mode off. The state survives app restarts, so a toggle you flipped days ago is the usual culprit.

## A Direct (LAN/VPN) printer shows offline

A printer added through **Add Printer → Direct (LAN/VPN)** (v0.9.51+) has exactly one path to it - the address you gave it, over your network - so "offline" always means one of these:

1. **The phone isn't on the printer's network.** On WiFi at home this is your LAN; away from home it means your **own VPN must be connected** (WireGuard, Tailscale). Direct printers have no tunnel to fall back to - that's the mode's whole point.
2. **Moonraker is rejecting the phone.** The app talks straight to Moonraker, so the phone's network must be inside `[authorization] trusted_clients` in `moonraker.conf`. Home subnets usually already are; **VPN subnets usually are not** - WireGuard setups often use `10.x` ranges that happen to be covered, but **Tailscale's `100.64.0.0/10` almost never is**. Add the subnet and restart Moonraker:
   ```ini
   [authorization]
   trusted_clients:
       192.168.1.0/24
       100.64.0.0/10   # Tailscale
   ```
3. **The Pi isn't actually in LAN-only mode.** Direct mode needs the plugin installed in LAN-only mode - answer **2) Direct (LAN/VPN)** when the installer asks, or pass `--lan-only` (see the README's LAN-only install section). Against a normal cloud-mode install the plugin still demands a token and answers `401`, so the tile sits offline. Check from any PC on the LAN:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" "http://<pi-ip>/server/moongate/status?mg_token="
   ```
   `200` = LAN-only mode; `401` = cloud mode (re-run the installer and pick **Direct (LAN/VPN)**, or pair the printer through the cloud instead).
4. **The Pi's address changed** (DHCP handed it a new IP). The app stores the address a Direct printer was added with - fix it in the printer's edit dialog (the pencil on its page), and give the Pi a **DHCP reservation / static IP** so it stops moving.

Also by design: Direct printers have **no print notifications** (there's no cloud to send them), so a quiet notification shade for one isn't a fault.

## A Direct printer works at home but not over my VPN

Same checklist as above with the VPN hat on: the VPN must be **connected on the phone**, its subnet must be in Moonraker's `trusted_clients` (point 2 above - this is the usual culprit, especially Tailscale's `100.64.0.0/10`), and the printer's stored address must be reachable *through* the VPN - for router-based WireGuard that's the printer's normal LAN IP; for Tailscale it's the Pi's Tailscale address, which is what you should have entered when adding the printer.

## Mainsail warns: "error detected while loading the moonraker component 'moongate'"

Moonraker tried to load the Moongate plugin and couldn't. The two usual causes:

1. **The plugin file isn't where Moonraker looks** - a `[moongate]` section exists in `moonraker.conf` but `moongate.py` never landed in Moonraker's components folder (a silently failed download is the classic way; on machines with a sealed filesystem the copy itself can fail). Installing on a vendor / embedded printer? Follow [3rd-party printer support](docs/third-party-printers.md) - its per-machine steps avoid exactly these traps.
2. **A cloud-mode install is missing its Python libraries** (a broken or rebuilt Moonraker environment). From plugin **0.6.17** this no longer stops the plugin loading - it keeps running, and says exactly what's missing in `moonraker.log` and the `MOONGATE_PAIR` console output. On older plugins, reinstall: `curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash`

Either way `moonraker.log` has the specific reason - search it for `moongate`.

## Dashboard tiles flicker or swap places every minute or so

Some routers micro-drop the WiFi for a fraction of a second at regular intervals (re-authentication, access-point roaming). Before **v0.9.54** each drop could fail exactly one status check, briefly blanking a tile's webcam and temperatures - and, with **Auto-arrange by status** on, reshuffling the tile order as the printer dipped through "offline" and back. Update the app: from v0.9.54 a single failed check never changes what you see, and a printer only shows offline after two consecutive misses (a few seconds) - genuinely unplugged printers still read offline promptly.

## Opening a printer shows "the web interface isn't answering yet"

From v0.9.48 this friendly message (with an automatic retry every few seconds) replaces the raw Cloudflare **"Bad gateway / Error 502"** page you used to see when opening a printer whose Pi was still starting up - the tunnel comes up a little before Mainsail does, so the first moments after a Pi boot can answer 502. It normally clears by itself within a minute. If it doesn't: check Mainsail loads in a browser on the printer's own network, and that Moonraker/Klipper are actually running on the Pi - the tunnel being up only proves the Pi is powered, not that the web stack behind it is healthy.

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
- **Works on Wi-Fi but not remotely (cellular)?** Remote cameras go through the Pi, which needs the **v0.9.0 / plugin 0.6.8+** update - re-run the Pi installer (or *Mainsail → Software Updates*) and let it restart. Also note: only **home-network (private) cameras** can be reached remotely; a camera on a public address won't relay through the tunnel, by design. The URL must also be a **numeric LAN address** over plain `http` (like `http://192.168.1.20:8080/video`) - a name like `http://mypi.local/...` or an `https://` address works on your Wi-Fi, where the phone fetches the camera directly, but won't relay remotely, so the tile sits on the logo away from home.
- **Auto-detected camera wrong or missing?** Moongate reads the *first* webcam from Mainsail's webcam list. If you have several, set the one you want by hand with the gear, or reorder them in Mainsail.
- **Gears in the way?** Turn them off under **Menu → Camera config icons** - that hides every tile's gear without affecting the camera feed.

## A go2rtc camera: tiles work, but it's black or freezes inside Mainsail (v0.9.52+)

From v0.9.52 the app understands **go2rtc** cameras (a `stream.html?src=...` address in Mainsail's webcam settings): the dashboard tile and the full-screen camera show them as live stills automatically, whether auto-detected from Mainsail or pasted into a tile's gear. Away from home a go2rtc camera follows the external-camera rules above: the address in Mainsail's webcam settings must be a numeric LAN `http://` URL (like `http://192.168.1.20:1984/stream.html?src=cam`), or the tile shows only the logo remotely.

The **printer page** is different: there you're looking at the real Mainsail, which plays the camera as live video with go2rtc's own player. If that video stays black, says "disconnected", or **plays a few seconds and then freezes** - and does the same in Chrome on your phone or PC while Firefox plays it fine - the cause is your camera's video encoding, not the app: the stream contains **B-frames**, which the WebRTC video protocol can't carry, so every Chrome-based browser (including the app's built-in one) gives up on it. Two fixes, either works:

- **Stop producing B-frames.** If go2rtc encodes the camera itself (an `ffmpeg:` source), remove `#hardware` from the stream line, or keep it and append `#raw=-bf 0`. If the camera encodes its own H.264, look for a B-frames / GOP option in its settings, or pick the "baseline" H.264 profile.
- **Sidestep the codec entirely** by giving Mainsail go2rtc's MJPEG endpoints instead: service type *MJPEG-Streamer / IP-Camera*, stream `.../api/stream.mjpeg?src=NAME`, snapshot `.../api/frame.jpeg?src=NAME`. Works in every browser; uses more bandwidth than WebRTC.

After **any** webcam config change, tap the **refresh icon** in the top-right of the app's printer page - the app keeps each printer's Mainsail page loaded for instant opening, so without a refresh it can keep showing the old camera setup.

## A tile shows the logo, or a printer has no camera at all

Newer app versions show a small **"Camera waking up…"** spinner in the camera box while the first picture is still being fetched - on-demand cameras (like go2rtc) genuinely take a moment to start when nobody was watching. If the spinner gives way to the **Mainsail/Fluidd logo**, the feed really isn't coming: the printer is offline or connecting, it has no camera configured, or the camera itself isn't answering. The full-screen camera view (the eye on a tile, or the camera icon on the printer page) still works whenever there's a feed.

Two diagnostics if a camera stays on the logo:

- The **in-app bug report** (menu → Report a problem) now includes what each tile's camera fetch is actually doing - which address it tried and what came back - so a report tells us (and you) where it stops.
- Away from home, remote camera pictures travel via the Pi, and the Pi now keeps a note when that fails (plugin 0.6.18+): `journalctl -u moongate-authproxy` on the Pi names the reason - a rejected camera address, a camera error, or a camera that answered with nothing (typically a camera whose device is stuck; a replug or Pi reboot usually revives it).

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

## An amber update icon appeared on a printer's tile

That printer's **Moongate Pi plugin is older than the one this app version shipped with** (v0.9.50+). It's a reminder, not an error - the printer keeps working - and it stays until the plugin is updated, then clears by itself on the next status refresh.

Tap the icon:

- On plugins **0.6.16 or newer** you get an **Update now** button - one tap and the printer fetches and applies the update itself in the background (about a minute). The button is greyed out while that printer is **mid-print**; update after the print finishes.
- On **older plugins** the dialog points you at the printer's web interface instead: **Mainsail (or Fluidd) → Software Updates → Moongate → Update**. After that first manual update the one-tap path is available forever.

If a one-tap update doesn't seem to take (the icon never clears), do it once from Mainsail's Software Updates panel - the usual cause is a hand-installed plugin that Moonraker's update manager doesn't know about.

## The Klipper console says the printer was released and "cloud contact is paused"

This appears when the printer's cloud registration is gone - usually because the printer was **removed in the app** (or the record was reset). Rather than checking in every few minutes forever, the plugin (0.6.15+) goes quiet and waits. **Nothing about the printer itself is affected** - printing, Mainsail, and LAN use all keep working.

To reconnect it to the app, just run **`MOONGATE_PAIR`** in the Klipper console and pair as normal - pairing instantly wakes the plugin, no restart or reinstall needed.

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

**Restoring onto a dashboard that already has printers (v0.9.47+):** restore is a **merge** - printers you've paired since the backup was made are **kept**, with the backup's printers added alongside them. If the backup doesn't include some of your current printers, a dialog offers **Keep them** (the default), **Remove them** (make the dashboard match the backup exactly), or **Cancel** - cancelling changes nothing and does **not** spend the backup's single-use restore code. (Before v0.9.47, restoring always made the dashboard match the backup exactly, which could silently drop a newly-paired printer.)

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
