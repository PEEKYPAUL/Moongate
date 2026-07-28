# 3rd-party printer support

Moongate's normal installer targets Raspberry-Pi-style hosts (MainsailOS,
FluiddPI: bash, systemd, sudo, pip, git). Plenty of interesting machines run a
real Moonraker without any of that - vendor printers with community firmware,
appliance-style embedded builds - and from **plugin 0.6.17** Moongate's
**Direct (LAN/VPN) mode** runs on them too, with zero extra Python
dependencies and no installer: **copy one file, add one config section,
restart Moonraker.**

Cloud mode (tunnel, notifications) is out of scope on these machines - they
rarely have the RAM or the packages for it. Direct mode covers home use out of
the box, and remote use through your own VPN (see
[Remote access](#remote-access-vpn) below).

## Supported machines

**Find your machine here first.** Every supported machine has its own
complete section below - follow that section start to finish and skip the
rest of this page.

| Machine | Firmware | Install |
|---|---|---|
| Elegoo Centauri Carbon | [OpenCentauri COSMOS](https://github.com/OpenCentauri/cosmos) | ✅ community-validated - [follow the Centauri Carbon section](#elegoo-centauri-carbon-opencentauri-cosmos) |

**Machine not listed?** Use the
[generic recipe](#unlisted-machines-the-generic-recipe) below - it works on
anything with a real Moonraker. Please
[open an issue](https://github.com/PEEKYPAUL/Moongate/issues) with your
results either way - working reports are how machines get added to this
table, with their own step-by-step section.

## What the machine needs

- A genuine [Moonraker](https://github.com/Arksine/moonraker) (0.9+) you can
  drop a component file into - Moonraker forks with the components system
  stripped out won't work
- Python 3.9+ (Moonraker's own requirement; no extra packages needed)
- A writable directory for Moongate's state (a few KB)
- Moonraker's `[authorization] trusted_clients` covering your phone's network
  - vendor images usually ship this for all private ranges
- The app talks to the same host and port Moonraker serves on, so no extra
  ports, proxies, or firewall holes

## Unlisted machines: the generic recipe

**Skip this section if your machine is in the table above** - its own
section has everything, adapted to that machine's quirks. This recipe is the
starting point for machines nobody has tried yet.

1. Copy `klipper-plugin/moongate_standalone.py` from this repo into
   Moonraker's components directory as `moongate.py`. (Download to `/tmp`
   first and check the file is real before moving it, silent download
   failures are the top trap. If the copy then fails with a read-only
   filesystem, your machine seals its root, use the bind-mount pattern
   from the COSMOS section below.)
2. Add to `moonraker.conf`:

   ```ini
   [moongate]
   lan_only: true
   data_path: /path/to/somewhere/writable
   ```

   `data_path` holds Moongate's state (defaults to `~/.config/moongate`,
   which embedded systems often can't write). A third option,
   `moonraker_port`, exists for the rare setup where Moonraker's port can't
   be auto-detected.
3. Restart Moonraker.
4. Confirm it loaded: `moonraker.log` shows
   `Moongate LAN-only mode: cloud loops disabled (no tunnel, no Supabase).`
5. In the app: **Add Printer → Direct (LAN/VPN)**, enter a name and the
   printer's address (e.g. `http://192.168.1.50`, add `:port` if Moonraker
   isn't on port 80 there). Give the printer a fixed address on your router -
   the app stores it.

## Elegoo Centauri Carbon (OpenCentauri COSMOS)

**These are the complete instructions for this machine** - if you're here,
you don't need the generic recipe above, everything it covers is folded in
below, adapted to COSMOS.

Community-validated on a real Centauri Carbon (2026-07-18). COSMOS ships a
genuine Moonraker on port 80 with `trusted_clients` preconfigured, so the
app side just works. The OS is BusyBox-based (no bash, git, pip, or
systemd), which is fine, nothing below needs them. The twist is the disk:
the root filesystem, including Moonraker's components folder, is **sealed
squashfs** (not even remountable). Only `/etc` persists, as an overlay
backed by the `/data` partition. So the plugin lives on `/etc`, and a small
boot script bind-mounts a copy of the components folder, carrying
`moongate.py`, over the sealed original before Moonraker starts.

Measured on a real board: the plugin rides inside Moonraker's existing
process, and the printer idled around 80 MB used of its 112 MB with
Moongate loaded. That headroom is also why cloud/tunnel mode is not
offered on this machine.

SSH in as root, then:

```sh
# 1. Master copy of the plugin (on /etc = survives reboots AND updates).
#    COSMOS's wget skips TLS validation but downloads fine; alternatively
#    scp the file from a computer to /etc/moongate/moongate.py
mkdir -p /etc/moongate
wget -O /etc/moongate/moongate.py \
  https://raw.githubusercontent.com/PEEKYPAUL/Moongate/master/klipper-plugin/moongate_standalone.py
grep -m1 'MOONGATE_PLUGIN_VERSION = ' /etc/moongate/moongate.py  # sanity check: prints the version

# 2. Config - append to the WRITABLE conf (not the moonraker-readonly one)
printf '\n[moongate]\nlan_only: true\ndata_path: /etc/moongate\n' \
  >> /etc/klipper/config/moonraker.conf

# 3. Boot script: rebuilds the components copy and bind-mounts it over the
#    sealed folder on every boot, just before Moonraker starts (S95 < S96)
cat > /etc/init.d/moongate-overlay << 'EOF'
#!/bin/sh
# Moongate on COSMOS: root is sealed squashfs, so Moonraker's components
# folder can't take the plugin directly. Rebuild a writable copy on /etc
# from the sealed originals plus moongate.py, and bind-mount it over the
# top. Rebuilding EVERY boot means a firmware update's own new components
# are never masked by a stale copy.
SEALED=/usr/share/moonraker/moonraker/components
COPY=/etc/moongate-components
MASTER=/etc/moongate/moongate.py
case "${1:-start}" in
  start)
    [ -f "$MASTER" ] || exit 0
    mount | grep -q " on $SEALED type " && exit 0
    rm -rf "$COPY"
    mkdir -p "$COPY"
    cp -a "$SEALED"/. "$COPY"/
    cp "$MASTER" "$COPY/moongate.py"
    mount -o bind "$COPY" "$SEALED"
    ;;
  stop)
    umount "$SEALED" 2>/dev/null || true
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
esac
exit 0
EOF
chmod +x /etc/init.d/moongate-overlay
for d in /etc/rc2.d /etc/rc3.d /etc/rc4.d /etc/rc5.d; do
  [ -d "$d" ] && ln -sf ../init.d/moongate-overlay "$d/S95moongate-overlay"
done

# 4. Activate now
/etc/init.d/moongate-overlay start
/etc/init.d/moonraker restart
```

Then add the printer in the app: **Add Printer → Direct (LAN/VPN)**, plain
`http://<printer-ip>` (COSMOS serves Moonraker on port 80).

Verify: the log lives at `/board-resource/moonraker.log` and shows
`Moongate LAN-only mode: cloud loops disabled` on a good start, and from a
browser on your LAN `http://<printer-ip>/server/moongate/status` returns a
wall of JSON including the plugin version.

- **Updating the plugin later:** re-run step 1's `wget`, then
  `/etc/init.d/moongate-overlay restart` and `/etc/init.d/moonraker restart`.
- **COSMOS firmware updates:** handled automatically, the boot script
  rebuilds its copy from the new firmware's own components on the next
  boot. If an update ever moves Moonraker's install dir, re-check the
  `SEALED` path in the script.
- COSMOS is beta firmware on a very RAM-limited board, and its authors warn
  against piling on plugins. LAN-only Moongate is about as light as they
  come (no tunnel, no timers, no outbound calls), but temper expectations
  accordingly.
- **Measured footprint, for the curious:** loading the module into an
  already-running Moonraker costs about **1 MB of RAM** on a 32-bit Pi
  (expect low single digits on other boards/Python versions) - for scale,
  Moonraker itself runs ~19 MB on a Centauri Carbon. On disk the whole
  install is the one plugin file plus the ~2 MB components copy the
  bind-mount needs. If you measure something wildly different on your
  machine, please open an issue with the numbers - `grep VmRSS
  /proc/<moonraker-pid>/status` before and after is the comparison that
  counts.

### Uninstalling

Everything the install put on the machine lives on `/etc` - the sealed root
was never touched - so removal is a config trim, a few deletes, and a
restart. SSH in as root, then:

```sh
# 1. Trim the [moongate] section off the conf. The install appended it at
#    the end of the file, so this cuts from that line down; if you've added
#    other sections below it since, edit the file with vi instead.
sed -i '/^\[moongate\]/,$d' /etc/klipper/config/moonraker.conf

# 2. Unmount the components copy and remove the boot script + its rc links
/etc/init.d/moongate-overlay stop
rm -f /etc/init.d/moongate-overlay /etc/rc?.d/S95moongate-overlay

# 3. Confirm the unmount took - NO output means it did. If a line prints
#    (the mount was busy), reboot the printer instead: the boot script is
#    gone, so it comes back up unmounted - then continue with step 4.
mount | grep ' on /usr/share/moonraker/moonraker/components '

# 4. Delete the plugin file, Moongate's state, and the components copy
rm -rf /etc/moongate /etc/moongate-components

# 5. Restart Moonraker on the stock components folder
/etc/init.d/moonraker restart
```

Then remove the printer's tile in the app: **menu → Remove printer**, tap
the printer. That's everything - all three pieces Moongate added (the
plugin file and its state, the components copy, the boot script) lived on
`/etc` and are gone, so the machine is back to stock.

## Remote access (VPN)

Direct mode away from home rides your own VPN, and the easy path is a
**subnet router** (Tailscale or WireGuard on any always-on box at home,
advertising your LAN). Your phone's traffic then arrives at the printer
looking like home-LAN traffic, which the stock `trusted_clients` ranges
already cover - no printer-side changes at all.

If instead you address the printer by a Tailscale IP directly, that traffic
comes from `100.64.0.0/10`, which stock configs do **not** trust - add that
range to `trusted_clients` in the writable moonraker.conf.

## What you give up vs a Pi install

- **No print notifications** - they're a cloud feature, and this is the
  cloud-free mode.
- **No update badge / one-tap update** - these machines have no Moonraker
  update_manager. Updating Moongate = re-copying the file.
- **No mDNS discovery** - the app uses the fixed address you gave it.
