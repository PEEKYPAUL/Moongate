# Updating &amp; removing Moongate

Moongate has two parts - the **app** on your phone and the **plugin** on your Pi - and they update independently. For first-time setup, see the [Quick start](../README.md#quick-start) in the README.

---

## Updating the app

How the app updates depends on where you installed it:

**App Store (iPhone) and Google Play (Android)** - the store delivers updates like any other app; there's nothing to do inside Moongate. Store releases carry the stable channel, so a version can land there a little after the same release appears on GitHub (store review takes time).

**Early-access APK (Android - GitHub Releases / KIAUH)** - the app updates itself. When a new version is out, it shows an **update banner** on launch. Tap **Update** and Moongate downloads the new version **inside the app** (with a progress bar), then hands it to Android's installer - just confirm the install. It installs **in place** (same signing key, so it's an upgrade, not a fresh install) and your printers and settings are kept. The first time, Android may ask you to let Moongate **install unknown apps** - allow it once, and after that an update is a single tap plus the install confirmation.

Prefer to do it by hand? Tap **What's new** on the banner to read the changes first, or **[download the latest APK](https://github.com/PEEKYPAUL/Moongate/releases/latest)** from the Releases page and install over your existing copy. (If an in-app update ever fails - no network, or the permission declined - the app falls back to opening the download in your browser, so you're never stuck.)

> As long as you **install over** the existing app (rather than uninstalling first), your identity is kept and nothing needs re-pairing. That includes **switching channels**: the Play build and the APK share a signing key, so moving between them installs in place too.

---

## Updating the plugin

Pi-side updates appear automatically in **Mainsail → Machine → Software Updates → Moongate** - click **Update** there, no SSH needed.

> Updating from **KlipperScreen** instead? If the update console seems to freeze on a line like `create mode 100644`, the update has completed - the console just loses its connection when Moonraker restarts at the end. See [Troubleshooting](../TROUBLESHOOTING.md#updating-moongate-from-klipperscreen-looks-stuck-on-create-mode-100644).

Prefer the command line? SSH in and re-run the installer - it pulls the latest and restarts the services:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/install.sh | bash
```

> The installer asks how your phone connects (cloud or Direct LAN/VPN). On a re-run the default is the mode the box already uses, so just pressing Enter updates without changing anything.

> Some releases note **"re-run the Pi installer"** in the changelog - that means a plugin-side change shipped (e.g. v0.5.1's instant-pairing QR). Update the plugin to get it.

---

## Reinstalling the app (or moving to a new phone)

This is the one case that needs care. A fresh install - uninstalling and reinstalling, clearing app data, or setting up a new phone - creates a **brand-new app identity**. Your printers are still tied to the *old* identity in the cloud, so after a fresh install every tile shows offline until you re-pair.

To reinstall cleanly:

1. **Before uninstalling**, for each printer run **`MOONGATE_RESET_OWNER`** in the Klipper console. This releases the cloud association so the printer can be claimed again.
   *(Optional: menu → **Back up config** to save your printer names + layout. This restores the list, but not the connection - re-pairing is what reconnects.)*
2. Uninstall the old app / set up the new phone, and install Moongate.
3. *(If you backed up)* menu → **Restore config** to bring your printer list back.
4. For each printer: run `MOONGATE_PAIR` on the Pi and scan the QR (or type the GATE code) - see [Step 3 - Pair](../README.md#3-pair).

> **Forgot to run `MOONGATE_RESET_OWNER` first?** No problem - run it now (it works any time), then `MOONGATE_PAIR` and pair again. See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md#all-tiles-offline-after-reinstalling-the-app-or-a-new-phone).

> **Just upgrading the app over the top?** None of this applies - your identity is kept and your printers stay paired.

> **Direct (LAN/VPN) printers** (v0.9.51+) sit outside all of this: they have no cloud identity, so a fresh install plus **Restore config** brings them back **fully working** - the backup carries their address, which is all they need. No `MOONGATE_RESET_OWNER`, no re-pairing. Just keep the Pi on a fixed address (DHCP reservation).

---

## Removing Moongate

To completely remove Moongate from your Pi, SSH in and run:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/uninstall.sh | MOONGATE_YES=1 bash
```

(`MOONGATE_YES=1` skips the confirmation prompt, which can't be answered interactively when piping through `bash`. Omit it if you download the script first.)

This removes:

- The `moongate-tunnel` and `moongate-authproxy` systemd services
- The Moongate Moonraker plugin and auth proxy
- The `~/moongate` repository clone
- `~/.config/moongate` (local state - owner record, device key)
- The `[moongate]` and `[update_manager moongate]` entries from `moonraker.conf`
- The Moonraker `host:` override the v0.4 installer applied (restored from its pre-install backup)
- The `MOONGATE_PAIR` macro from your Klipper config
- The `moongate-pair.html` page from Mainsail
- `cloudflared` itself - the binary plus its cached state (`~/.cloudflared`, `/etc/cloudflared`)

`cloudflared` is removed by default. If the uninstaller detects it's used by something else on the Pi - a named-tunnel config, or a standalone `cloudflared` systemd service - it leaves it in place instead (Moongate's own Quick Tunnel creates none of those, so a Moongate-only Pi always has it removed). To keep `cloudflared` regardless, pass `MOONGATE_KEEP_CLOUDFLARED=1`:

```bash
curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/uninstall.sh | MOONGATE_KEEP_CLOUDFLARED=1 MOONGATE_YES=1 bash
```

Don't forget to uninstall the Moongate app from your phone as well.
