#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Moongate installer
# Run on your Klipper Pi:
#   curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh | bash
#
# Re-running is safe - existing tokens, config, and cloudflared are untouched.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[moongate]${NC} $*"; }
success() { echo -e "${GREEN}[moongate]${NC} $*"; }
warn()    { echo -e "${YELLOW}[moongate]${NC} $*"; }
die()     { echo -e "${RED}[moongate] ERROR:${NC} $*" >&2; exit 1; }

# ── HTTP port (defaults to 80) ───────────────────────────────────────────────
# Tell the installer that Moonraker / Mainsail is reachable on a non-standard
# port.  Stock KIAUH / MainsailOS use port 80, which is the default here.
# Override one of two ways:
#
#   Locally:  bash install.sh --port 8080
#   Piped:    MOONGATE_PORT=8080 bash -c "$(curl -fsSL <url>)"
#
# The cloudflared tunnel will forward to this port and the plugin will embed
# it in the QR URL and the pair-page link.
MOONGATE_PORT="${MOONGATE_PORT:-80}"

# ── LAN-only mode (--lan-only / MOONGATE_LAN_ONLY=1) ─────────────────────────
# Skip the Cloudflare tunnel + auth proxy entirely and keep Moonraker on the
# LAN. For users who reach their printer over their own VPN / WireGuard and
# don't want an outbound tunnel or external exposure. The plugin, [moongate]
# config, MOONGATE_PAIR macro, and mDNS advertisement are still installed, so
# a later full re-run (without --lan-only) can enable remote access.
#
#   Locally:  bash install.sh --lan-only
#   Piped:    MOONGATE_LAN_ONLY=1 bash -c "$(curl -fsSL <url>)"
#
# No flag and no env var at all -> the interactive chooser below asks. Any
# explicit setting (either value, or the flag) skips the question, so
# automation that wants the tunnel default unchanged sets MOONGATE_LAN_ONLY=0.
# Set-ness must be captured before the :- default collapses "unset" and
# "empty" into the same thing.
MG_LAN_MODE_EXPLICIT="${MOONGATE_LAN_ONLY+x}"
MOONGATE_LAN_ONLY="${MOONGATE_LAN_ONLY:-}"

# Loopback port the v0.4 auth proxy binds to. cloudflared targets this
# instead of Moonraker directly. Override with MG_AUTHPROXY_PORT=NNNN.
MG_AUTHPROXY_PORT="${MG_AUTHPROXY_PORT:-8443}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)      [[ -n "${2-}" ]] || die "--port needs a value"; MOONGATE_PORT="$2"; shift 2;;
        --port=*)    MOONGATE_PORT="${1#*=}"; shift;;
        --lan-only)  MOONGATE_LAN_ONLY=1; MG_LAN_MODE_EXPLICIT=x; shift;;
        *)           shift;;
    esac
done
[[ "$MOONGATE_PORT" =~ ^[0-9]+$ ]] \
    || die "Port must be numeric - got: $MOONGATE_PORT"
[[ "$MOONGATE_PORT" -ge 1 && "$MOONGATE_PORT" -le 65535 ]] \
    || die "Port out of range (1-65535): $MOONGATE_PORT"
info "HTTP port: $MOONGATE_PORT"

# ── Connection-mode chooser ──────────────────────────────────────────────────
# Runs only when the caller expressed no preference (no --lan-only flag,
# MOONGATE_LAN_ONLY unset) AND a terminal is reachable. The answer is read
# from /dev/tty, not stdin: under `curl ... | bash` stdin is the script
# itself, so a plain `read` would swallow script text - /dev/tty still
# reaches the keyboard. Headless runs (no controlling terminal: CI,
# provisioning tools) skip the question and get the full cloud install,
# exactly the pre-chooser behaviour.
#
# The default answer keeps an existing install's current mode: this script
# doubles as the mode CONVERTER (re-running without --lan-only flips a box
# back to cloud), so a LAN-only user re-running it to repair must not be
# converted - and handed an internet tunnel - by an idle Enter. Fresh
# installs default to cloud.
if [[ -z "$MG_LAN_MODE_EXPLICIT" ]] && ( : </dev/tty ) 2>/dev/null; then
    MG_MODE_DEFAULT=1
    # Existing LAN-only box -> keep its mode (§5b writes this file).
    grep -qs '"lan_only"[[:space:]]*:[[:space:]]*true' "$HOME/.config/moongate/config.json" \
        && MG_MODE_DEFAULT=2
    echo
    info "How will your phone connect to this printer?"
    echo "    1) Moongate cloud   - remote access from anywhere (secure tunnel)"
    echo "    2) Direct (LAN/VPN) - home network / your own VPN only, no cloud"
    while :; do
        read -r -p "Choose 1 or 2 [default: $MG_MODE_DEFAULT]: " MG_MODE_CHOICE </dev/tty \
            || MG_MODE_CHOICE=""   # EOF (e.g. ctrl-D) -> take the default
        MG_MODE_CHOICE="${MG_MODE_CHOICE:-$MG_MODE_DEFAULT}"
        [[ "$MG_MODE_CHOICE" == "1" || "$MG_MODE_CHOICE" == "2" ]] && break
        warn "Please answer 1 or 2."
    done
    [[ "$MG_MODE_CHOICE" == "2" ]] && MOONGATE_LAN_ONLY=1 || MOONGATE_LAN_ONLY=""
fi

# Normalise to "1" (on) or "" (off) so MOONGATE_LAN_ONLY=0 opts OUT - matches
# how uninstall.sh treats MOONGATE_YES. --lan-only above already set it to 1.
# Every check below is an emptiness test, so "" reliably means tunnel mode.
[[ "$MOONGATE_LAN_ONLY" == "1" ]] && MOONGATE_LAN_ONLY=1 || MOONGATE_LAN_ONLY=""
[[ -n "$MOONGATE_LAN_ONLY" ]] \
    && info "LAN-only mode: no Cloudflare tunnel or auth proxy will be installed."

# ── Keep-bind opt-out (MOONGATE_KEEP_BIND=1) ─────────────────────────────────
# Cloud (tunnel) mode normally binds Moonraker's [server] host to 127.0.0.1
# (step 2e) so only the EdDSA-gated proxy is network-exposed. Setups where
# OTHER machines talk to Moonraker directly at <pi-ip>:7125 - a central "farm"
# Mainsail/Fluidd, monitoring tools - can opt out: MOONGATE_KEEP_BIND=1 leaves
# [server] host exactly as it is, and a re-run with it set never re-binds.
# Env-only on purpose (no flag, no prompt): it loosens the default posture, so
# it should be a deliberate, documented choice - most setups don't need it
# because the Pi's nginx already serves the full Moonraker API on port 80.
# Normalised like MOONGATE_LAN_ONLY: only a literal "1" enables it. Ignored in
# LAN-only mode, which manages the bind itself (and needs to be able to un-do
# OUR old loopback bind on a converted box - keep-bind would wrongly pin it).
[[ "${MOONGATE_KEEP_BIND:-}" == "1" ]] && MOONGATE_KEEP_BIND=1 || MOONGATE_KEEP_BIND=""
if [[ -n "$MOONGATE_KEEP_BIND" && -n "$MOONGATE_LAN_ONLY" ]]; then
    info "MOONGATE_KEEP_BIND ignored: LAN-only mode manages the Moonraker bind itself."
    MOONGATE_KEEP_BIND=""
fi

# ── Detect environment ────────────────────────────────────────────────────────
MOONGATE_REPO="https://github.com/PEEKYPAUL/moongate.git"
MOONGATE_DIR="${MOONGATE_DIR:-$HOME/moongate}"
MOONRAKER_DIR="${MOONRAKER_DIR:-$HOME/moonraker}"
MAINSAIL_DIR="${MAINSAIL_DIR:-$HOME/mainsail}"
PRINTER_DATA="${PRINTER_DATA:-$HOME/printer_data}"
MOONRAKER_CONF="$PRINTER_DATA/config/moonraker.conf"
COMPONENTS_DIR="$MOONRAKER_DIR/moonraker/components"
KLIPPER_CFG_DIR="$PRINTER_DATA/config"

[[ -d "$MOONRAKER_DIR" ]]  || die "Moonraker not found at $MOONRAKER_DIR. Set MOONRAKER_DIR= if installed elsewhere. On a vendor/embedded printer (e.g. OpenCentauri)? This installer targets Pi-style hosts - follow docs/third-party-printers.md instead."
[[ -f "$MOONRAKER_CONF" ]] || die "moonraker.conf not found at $MOONRAKER_CONF. On a vendor/embedded printer (e.g. OpenCentauri)? This installer targets Pi-style hosts - follow docs/third-party-printers.md instead."

# ── Clock sanity check ────────────────────────────────────────────────────────
# Moongate's remote access is cryptographically time-bound: the Pi signs every
# heartbeat with its clock and the cloud REJECTS anything more than 60s off its
# own (replay protection); the short-lived access tokens are time-checked too. A
# Raspberry Pi has no battery-backed clock, so when NTP (UDP/123) is blocked -
# common on locked-down networks - the clock silently drifts and ALL remote
# access fails with cryptic 401s while everything else looks perfectly fine.
#
# timedatectl can't be trusted here (it happily reports an active-but-never-synced
# client), so measure the REAL skew against an HTTPS Date header - the same path
# the Pi uses to reach Supabase. -k because a badly-wrong clock fails TLS validity
# (chicken-and-egg) and we're only reading a timestamp, not trusting a secret.
# When NTP can't sync, keep time honest with htpdate (HTTP-based, survives blocked
# UDP/123). Runs before apt/cloudflared below so those don't trip over TLS dates.
MG_TIME_HOST="${MG_TIME_HOST:-https://www.cloudflare.com}"
MG_CLOCK_MAX_SKEW=30   # seconds; the server's hard cutoff is 60

# Skipped in LAN-only mode: this check (and the htpdate timer it can install)
# exists solely to keep the *cloud* auth from rejecting signed heartbeats as
# replays. LAN-only has no tunnel, so we skip the check and never stand up the
# recurring htpdate timer. Guard body left un-indented to keep the htpdate
# systemd heredocs byte-for-byte identical.
# NB: print push notifications are also signed calls with a 60s clock window.
# On a plugin with the lan_only config flag (0.6.17+, written below) the
# print-event watcher never starts so nothing is lost; on an older converged
# box the watcher still runs and a badly wrong clock silently loses those
# sends - re-running this installer writes the flag.
if [[ -z "$MOONGATE_LAN_ONLY" ]]; then
info "Checking the system clock (remote auth needs it within 60s of real time)..."
MG_HTTP_DATE=$(curl -fsSI -k --max-time 10 "$MG_TIME_HOST" 2>/dev/null \
               | grep -i '^date:' | head -n1 | cut -d' ' -f2- || true)
MG_HTTP_DATE=${MG_HTTP_DATE%$'\r'}
MG_HTTP_EPOCH=$(date -d "$MG_HTTP_DATE" +%s 2>/dev/null || true)

if [[ -z "$MG_HTTP_DATE" || -z "$MG_HTTP_EPOCH" ]]; then
    warn "Couldn't verify the clock against network time - skipping (non-fatal)."
    warn "If remote access later fails with repeated 'Heartbeat 401', check 'timedatectl' first."
else
    MG_NOW_EPOCH=$(date +%s)
    MG_SKEW=$(( MG_NOW_EPOCH > MG_HTTP_EPOCH ? MG_NOW_EPOCH - MG_HTTP_EPOCH : MG_HTTP_EPOCH - MG_NOW_EPOCH ))
    if (( MG_SKEW <= MG_CLOCK_MAX_SKEW )); then
        success "Clock is accurate (within ${MG_SKEW}s of network time)."
    else
        warn "Pi clock is off by ~${MG_SKEW}s - remote auth needs it within 60s, correcting now."
        warn "(No battery clock + blocked NTP makes it drift; every signed heartbeat is then"
        warn " rejected as a replay, so remote access silently fails.)"
        if sudo date -s "$MG_HTTP_DATE" >/dev/null 2>&1; then
            success "Clock set from network time: $(date '+%Y-%m-%d %H:%M:%S %Z')."
        else
            warn "Couldn't set the clock automatically. Run by hand: sudo date -s \"$MG_HTTP_DATE\""
        fi

        # Keep it correct across reboots. If NTP genuinely works, leave it alone;
        # otherwise install htpdate + a small timer so it can't drift back.
        if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi true; then
            info "NTP is working - no extra time daemon needed."
        elif sudo apt-get install -y htpdate >/dev/null 2>&1; then
            MG_HTPDATE_BIN=$(command -v htpdate || echo /usr/sbin/htpdate)
            sudo tee /etc/systemd/system/moongate-timesync.service >/dev/null <<UNIT
[Unit]
Description=Moongate HTTPS time sync (htpdate) - for networks where NTP is blocked
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$MG_HTPDATE_BIN -s www.cloudflare.com www.google.com www.microsoft.com
UNIT
            sudo tee /etc/systemd/system/moongate-timesync.timer >/dev/null <<UNIT
[Unit]
Description=Keep the clock synced over HTTPS for Moongate remote auth

[Timer]
OnBootSec=45
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
            sudo systemctl daemon-reload >/dev/null 2>&1 || true
            sudo systemctl enable --now moongate-timesync.timer >/dev/null 2>&1 || true
            sudo systemctl start moongate-timesync.service >/dev/null 2>&1 || true
            success "htpdate installed + timer enabled - clock stays synced over HTTPS (NTP is blocked here)."
        else
            warn "Couldn't install htpdate. Open outbound UDP/123 (NTP) on your router, or"
            warn "re-sync after each reboot with the 'sudo date -s' command above."
        fi
    fi
fi
fi  # end LAN-only clock-check guard

# Pick the cloudflared deb that matches the dpkg system architecture.
# uname -m alone is unreliable: the kernel reports armv7l on a system
# whose userland is armhf, and dpkg refuses to install an "arm" deb on
# an "armhf" host. dpkg --print-architecture is what dpkg uses when
# matching a .deb, so it's the authoritative source here.
# Skipped in LAN-only mode: CF_ARCH only feeds the cloudflared download in
# the remote-access section (itself LAN-only-skipped), and the unsupported-
# architecture die must not kill a LAN-only install that never needs
# cloudflared. Guard body left un-indented, matching the guards above.
if [[ -z "$MOONGATE_LAN_ONLY" ]]; then
ARCH=$(uname -m)
DPKG_ARCH=""
if command -v dpkg &>/dev/null; then
    DPKG_ARCH="$(dpkg --print-architecture)"
    case "$DPKG_ARCH" in
        arm64)  CF_ARCH="arm64" ;;
        armhf)  CF_ARCH="armhf" ;;
        armel)  CF_ARCH="arm"   ;;
        amd64)  CF_ARCH="amd64" ;;
        i386)   CF_ARCH="386"   ;;
        *) die "Unsupported dpkg architecture: $DPKG_ARCH (uname: $ARCH)" ;;
    esac
else
    # No dpkg - unusual on a Klipper Pi, but fall back to uname so the
    # diagnostic still fires before we try to install cloudflared.
    case "$ARCH" in
        aarch64|arm64) CF_ARCH="arm64" ;;
        armv7l)        CF_ARCH="armhf" ;;
        armv6l)        CF_ARCH="arm"   ;;
        x86_64)        CF_ARCH="amd64" ;;
        i686|i386)     CF_ARCH="386"   ;;
        *) die "Unsupported architecture: $ARCH" ;;
    esac
fi

info "Architecture: $ARCH (dpkg: ${DPKG_ARCH:-n/a}) → cloudflared: $CF_ARCH"
fi  # end LAN-only arch guard

# ── 1. Clone or update the Moongate repo ─────────────────────────────────────
# Cloning to ~/moongate lets Moonraker's update manager track the repo and
# show updates in Mainsail's update panel - just like Klipper/Mainsail itself.
info "Setting up Moongate repository at $MOONGATE_DIR..."

if [[ -d "$MOONGATE_DIR/.git" ]]; then
    CURRENT_BRANCH="$(git -C "$MOONGATE_DIR" branch --show-current 2>/dev/null || echo unknown)"
    if [[ "$CURRENT_BRANCH" != "master" ]]; then
        warn "Repo on branch '$CURRENT_BRANCH' (not master) - skipping git pull."
        warn "Run 'git pull' manually if you intended to update."
    elif [[ -f "$MOONGATE_DIR/.git/shallow" ]]; then
        # Older installs used `git clone --depth=1` - a shallow clone carries
        # no git tags, so Moonraker can't determine a version and Mainsail's
        # Software Update panel shows "v0.0.0-…-inferred" instead of vX.Y.Z.
        # A shallow clone can't be cheaply converted in place, so re-clone.
        # --filter=blob:none keeps it small AND skips the hundreds of MB of
        # release APKs that lived in this repo's history before they moved to
        # GitHub Release assets. Old clone preserved for safety.
        BROKEN_DIR="${MOONGATE_DIR}.shallow-$(date +%Y%m%d-%H%M%S)"
        warn "Existing clone is shallow - no tags, so the update panel can't show a version."
        warn "Re-cloning with full tag history. Old clone preserved at $BROKEN_DIR"
        mv "$MOONGATE_DIR" "$BROKEN_DIR"
        git clone --filter=blob:none "$MOONGATE_REPO" "$MOONGATE_DIR"
        success "Repository re-cloned with tags. Old clone preserved at $BROKEN_DIR"
    else
        info "Repo on master - pulling latest..."
        # Robust update: `git pull --ff-only` can fail fatally for several
        # reasons - divergent history (force-push upstream), dirty working
        # tree (CRLF conversion, manual edits), untracked files that would
        # be overwritten, or local commits ahead of master. set -e would
        # then abort the installer mid-way. Fall back to re-cloning fresh,
        # preserving the broken clone for forensic inspection. (Git's own
        # error message printed above tells the user the specific cause.)
        # --tags pulls new release tags so the update panel's version keeps up.
        if git -C "$MOONGATE_DIR" fetch origin master --tags \
            && git -C "$MOONGATE_DIR" merge --ff-only origin/master; then
            success "Repository updated."
        else
            BROKEN_DIR="${MOONGATE_DIR}.broken-$(date +%Y%m%d-%H%M%S)"
            warn "Local clone can't fast-forward to origin/master (see git error above)."
            warn "Moving aside to $BROKEN_DIR and re-cloning fresh."
            mv "$MOONGATE_DIR" "$BROKEN_DIR"
            git clone --filter=blob:none "$MOONGATE_REPO" "$MOONGATE_DIR"
            success "Repository re-cloned. Old clone preserved at $BROKEN_DIR"
        fi
    fi
else
    git clone --filter=blob:none "$MOONGATE_REPO" "$MOONGATE_DIR"
    success "Repository cloned to $MOONGATE_DIR"
fi

PLUGIN_SRC="$MOONGATE_DIR/klipper-plugin/moongate_standalone.py"

# ── 2. Install Moongate Moonraker plugin (symlink) ───────────────────────────
# Using a symlink means git pull automatically gives you the new plugin -
# no manual file copy needed. Moonraker's update manager restarts Moonraker
# after each pull so the new version loads cleanly.
info "Linking plugin into Moonraker components..."
ln -sf "$PLUGIN_SRC" "$COMPONENTS_DIR/moongate.py"
success "Plugin linked: $COMPONENTS_DIR/moongate.py → $PLUGIN_SRC"

# ── 2b. Install Python dependencies into Moonraker's venv ────────────────────
# v0.3 plugin needs PyJWT[crypto] (EdDSA verification) and cryptography
# (Ed25519 keypair generation + heartbeat signing). Both are pure-Python or
# have prebuilt wheels for the architectures we care about (arm64, armv7, x86_64).
info "Installing Python dependencies into Moonraker's venv..."

MOONRAKER_VENV=""
for candidate in \
    "$HOME/moonraker-env" \
    "$MOONRAKER_DIR/venv" \
    "$MOONRAKER_DIR/../moonraker-env"; do
    if [[ -f "$candidate/bin/pip" ]]; then
        MOONRAKER_VENV="$candidate"
        break
    fi
done

if [[ -n "$MOONRAKER_VENV" ]]; then
    "$MOONRAKER_VENV/bin/pip" install --upgrade --quiet \
        "PyJWT[crypto]>=2.8" \
        "cryptography>=41" \
        "aiohttp>=3.9" \
        || die "Failed to install Python deps into $MOONRAKER_VENV"
    success "Python deps installed in $MOONRAKER_VENV"
else
    warn "Could not find Moonraker venv. Install manually:"
    warn "  ~/moonraker-env/bin/pip install 'PyJWT[crypto]>=2.8' 'cryptography>=41' 'aiohttp>=3.9'"
fi

# ── 2c. Wipe v0.2.x state if migrating ───────────────────────────────────────
# v0.2.x stored tokens.json / secret.key / peers.json in ~/.config/moongate/.
# v0.3 uses device_ed25519 / owner.json / jwks.json - none of the old files
# are valid for the new model. Move them aside so re-running install.sh on
# a v0.2.x box gets a clean v0.3 install.
LEGACY_DIR="$HOME/.config/moongate/legacy-v0.2.x"
if [[ -f "$HOME/.config/moongate/tokens.json" || -f "$HOME/.config/moongate/secret.key" ]]; then
    info "Migrating v0.2.x state out of the way..."
    mkdir -p "$LEGACY_DIR"
    for f in tokens.json secret.key peers.json; do
        [[ -f "$HOME/.config/moongate/$f" ]] && mv "$HOME/.config/moongate/$f" "$LEGACY_DIR/" 2>/dev/null || true
    done
    success "v0.2.x state moved to $LEGACY_DIR (safe to delete after v0.3 verified)"
fi

# ── 2d. v0.4 backup directory ────────────────────────────────────────────────
# Originals of every system config we patch (moonraker.conf, nginx vhosts,
# moongate-tunnel.service) land here. uninstall.sh restores from these on
# downgrade. Each file is backed up exactly once - re-running install.sh
# doesn't overwrite an existing backup with an already-patched copy.
V04_BACKUP_DIR="$HOME/.config/moongate/v0.4-backup"
mkdir -p "$V04_BACKUP_DIR"
chmod 700 "$V04_BACKUP_DIR"

backup_once() {
    # $1 = source path, $2 = backup filename (relative to V04_BACKUP_DIR)
    local src="$1"
    local dst="$V04_BACKUP_DIR/$2"
    if [[ -f "$src" && ! -f "$dst" ]]; then
        cp "$src" "$dst"
        chmod 600 "$dst"
    fi
}

# ── 2e. Bind Moonraker's [server] host ───────────────────────────────────────
# Default (tunnel) mode: bind to 127.0.0.1. The cloudflared tunnel terminates
# at moongate-authproxy (port 8443), so Moonraker becomes loopback-only and
# cannot be reached via the tunnel without passing the EdDSA gate. LAN access
# via the Pi's local IP is unchanged because moonraker's `trusted_clients`
# still allows the LAN subnet.
#
# LAN-only mode: keep Moonraker reachable on the LAN / the user's own VPN
# (there is no tunnel or auth proxy to front it). We only ever flip an explicit
# `host: 127.0.0.1` (our own prior full install) back to 0.0.0.0 - we do NOT
# append a host line where none exists (Moonraker already defaults to all
# interfaces) and we do NOT overwrite a deliberate bind such as a WireGuard-
# only interface IP. Default (tunnel) mode still force-sets 127.0.0.1.
if [[ -n "$MOONGATE_KEEP_BIND" ]]; then
    # Deliberate opt-out (env knob above): honour whatever [server] host the
    # user runs. The tunnel still needs Moonraker reachable over loopback -
    # the auth proxy targets http://127.0.0.1:7125 - which an absent host,
    # 0.0.0.0 or :: all provide. A single specific interface IP does not:
    # flag it rather than die, the user asked for their bind to be kept.
    info "MOONGATE_KEEP_BIND=1: leaving Moonraker's [server] host untouched."
    backup_once "$MOONRAKER_CONF" "moonraker.conf.orig"
    MG_CURRENT_HOST="$(sed -n '/^\[server\]/,/^\[/p' "$MOONRAKER_CONF" \
        | sed -n 's/^[[:space:]]*host[[:space:]]*[:=][[:space:]]*\([^[:space:]#]*\).*/\1/p' \
        | head -1)"
    case "${MG_CURRENT_HOST:-0.0.0.0}" in
        0.0.0.0|::|127.0.0.1) : ;;
        *) warn "[server] host is '$MG_CURRENT_HOST' - remote access reaches Moonraker at 127.0.0.1:7125, which this bind does not serve. The tunnel will fail until the host covers loopback (e.g. 0.0.0.0)." ;;
    esac
    success "Moonraker [server] host kept as-is (MOONGATE_KEEP_BIND=1)."
else

if [[ -n "$MOONGATE_LAN_ONLY" ]]; then
    MG_MOONRAKER_HOST="0.0.0.0"
    MG_HOST_ONLY_IF_LOOPBACK=1
    info "Ensuring Moonraker stays reachable on the LAN (LAN-only mode)..."
else
    MG_MOONRAKER_HOST="127.0.0.1"
    MG_HOST_ONLY_IF_LOOPBACK=""
    info "Binding Moonraker to 127.0.0.1 (v0.4 hardening)..."
fi
backup_once "$MOONRAKER_CONF" "moonraker.conf.orig"

python3 - "$MOONRAKER_CONF" "$MG_MOONRAKER_HOST" "$MG_HOST_ONLY_IF_LOOPBACK" << 'PYEOF'
import re, sys
path = sys.argv[1]
host = sys.argv[2]
only_if_loopback = sys.argv[3] == "1"   # LAN-only: only touch host: 127.0.0.1
with open(path) as f:
    content = f.read()

# Find or create the [server] section.
server_match = re.search(r'(?m)^\[server\]\s*$', content)
if not server_match:
    if only_if_loopback:
        # LAN-only: no [server] block -> Moonraker binds all interfaces by
        # default, which is already LAN-reachable. Nothing to change.
        print("moonraker.conf: no [server] block - left as-is (LAN-only)")
        sys.exit(0)
    # No [server] block at all - append one with our settings.
    content = content.rstrip() + f"\n\n[server]\nhost: {host}\nport: 7125\n"
else:
    # Locate the end of the [server] block (next [section] or EOF).
    start = server_match.end()
    next_section = re.search(r'(?m)^\[', content[start:])
    end = start + next_section.start() if next_section else len(content)
    section = content[start:end]

    host_match = re.search(r'(?m)^\s*host\s*[:=]\s*(\S+)', section)
    if host_match:
        current = host_match.group(1)
        if only_if_loopback and current != "127.0.0.1":
            # LAN-only: leave a deliberate bind (e.g. a WireGuard IP) alone.
            print(f"moonraker.conf: [server] host={current} - left as-is (LAN-only)")
            sys.exit(0)
        # host: already set - force to our target host.
        new_section = re.sub(
            r'(?m)^(\s*host\s*[:=]\s*).*$',
            r'\g<1>' + host,
            section,
            count=1,
        )
    else:
        if only_if_loopback:
            # LAN-only: no host line -> default (all interfaces). Leave it.
            print("moonraker.conf: [server] has no host - left as-is (LAN-only)")
            sys.exit(0)
        # No host: line in [server] - inject one right after the header.
        new_section = f"\nhost: {host}" + section

    content = content[:start] + new_section + content[end:]

with open(path, 'w') as f:
    f.write(content)
print(f"moonraker.conf: [server] host={host}")
PYEOF
if [[ -n "$MOONGATE_LAN_ONLY" ]]; then
    success "Moonraker [server] host ready for LAN access."
else
    success "Moonraker bound to 127.0.0.1"
fi

fi  # MOONGATE_KEEP_BIND (the python block above is column-0 for its heredoc)

# NOTE: We intentionally do NOT patch nginx vhosts in v0.4.0. The original
# v0.4 design considered binding nginx to 127.0.0.1 (defense in depth), but
# that would break the LAN-first path that v0.3 introduced - Mainsail loaded
# from http://<pi-lan-ip>/ would 404 because nothing would be listening on
# the LAN interface. The actual security guarantee comes from retargeting
# cloudflared (step 7 below) to the auth proxy: the tunnel no longer reaches
# nginx, only the EdDSA gate. nginx stays reachable on LAN exactly as today.
# If a user explicitly port-forwards :80, they have made nginx public on
# their own initiative - same risk profile as v0.3 in that scenario.

if grep -q '^\[moongate\]' "$MOONRAKER_CONF"; then
    info "[moongate] already in moonraker.conf"
else
    printf '\n[moongate]\n# Moongate pairing + remote access plugin\n' >> "$MOONRAKER_CONF"
    success "[moongate] added to moonraker.conf"
fi

# ── 3. Register with Moonraker's update manager ───────────────────────────────
# This adds Moongate to the Software Updates panel in Mainsail - same as
# Klipper, Mainsail, etc. One-click updates from the web UI from now on.
info "Registering with Moonraker update manager..."

if grep -q '^\[update_manager moongate\]' "$MOONRAKER_CONF"; then
    info "[update_manager moongate] already in moonraker.conf"
else
    cat >> "$MOONRAKER_CONF" << EOF

[update_manager moongate]
type: git_repo
path: $MOONGATE_DIR
origin: $MOONGATE_REPO
primary_branch: master
managed_services: moonraker
install_script: klipper-plugin/update.sh
EOF
    success "[update_manager moongate] added to moonraker.conf"
fi

# ── 4. Add MOONGATE_PAIR macro to Klipper config ─────────────────────────────
info "Adding MOONGATE_PAIR macro to Klipper config..."

PRINTER_CFG=""
for candidate in \
    "$PRINTER_DATA/config/printer.cfg" \
    "$HOME/klipper_config/printer.cfg" \
    "$HOME/printer_data/config/printer.cfg"; do
    if [[ -f "$candidate" ]]; then
        PRINTER_CFG="$candidate"
        break
    fi
done

if [[ -z "$PRINTER_CFG" ]]; then
    die "Cannot find printer.cfg - tried:
  $PRINTER_DATA/config/printer.cfg
  $HOME/klipper_config/printer.cfg
  $HOME/printer_data/config/printer.cfg
Set PRINTER_DATA=/path/to/printer_data and re-run."
fi

info "Found printer.cfg at $PRINTER_CFG"
KLIPPER_CFG_DIR="$(dirname "$PRINTER_CFG")"
MOONGATE_CFG="$KLIPPER_CFG_DIR/moongate.cfg"

# Detect whether [respond] is already declared anywhere in the user's
# Klipper config. The MOONGATE_PAIR macro uses M118 to print the pair
# code, QR URL, and instructions to the Mainsail console; M118 is only
# available when [respond] is enabled. Many stock setups (vanilla
# MainsailOS / KIAUH) ship without it.
#
# We exclude moongate.cfg itself from the scan: on re-install, our own
# previously-written [respond] would otherwise trip the detector and
# we'd strip it back out, breaking M118 again. Excluding our file means
# the check answers "is [respond] declared *outside* of us?".
RESPOND_PRESENT=0
while IFS= read -r f; do
    [[ "$(basename "$f")" == "moongate.cfg" ]] && continue
    if grep -qE '^\s*\[respond\]' "$f"; then
        RESPOND_PRESENT=1
        break
    fi
done < <(find "$KLIPPER_CFG_DIR" -maxdepth 2 -name "*.cfg" 2>/dev/null)

# Build moongate.cfg. Always emits the two macros; conditionally emits
# [respond] only when no other config file already declares it
# (declaring [respond] twice is a fatal Klipper config error).
{
    cat << 'HEADER'
# ── Moongate ──────────────────────────────────────────────────────────────────
# Managed by the Moongate installer - do not edit manually.
# Updates are handled automatically via Moonraker's update manager.

HEADER

    if [[ $RESPOND_PRESENT -eq 0 ]]; then
        cat << 'RESPONDSECTION'
# [respond] enables the M118 command, which MOONGATE_PAIR uses to print
# the pair code, QR URL, and instructions to the Mainsail/Fluidd console.
# Without this, MOONGATE_PAIR would log "Unknown command: M118" instead.
# If you later add [respond] elsewhere in your config, remove this block
# - Klipper refuses to start with two [respond] sections.
[respond]

RESPONDSECTION
    fi

    cat << 'MACROS'
[gcode_macro MOONGATE_PAIR]
description: Start a Moongate pairing session and show a QR for the mobile app
gcode:
    {action_call_remote_method("moongate_generate_pair_code")}

[gcode_macro MOONGATE_RESET_OWNER]
description: Wipe local Moongate owner binding so the printer can be re-paired
gcode:
    {action_call_remote_method("moongate_reset_owner")}

[gcode_macro MOONGATE_STATUS]
description: Report Moongate cloud + tunnel health in the console
gcode:
    {action_call_remote_method("moongate_status")}
MACROS
} > "$MOONGATE_CFG"

if [[ $RESPOND_PRESENT -eq 1 ]]; then
    info "[respond] already enabled in your config - moongate.cfg uses your existing one"
else
    success "[respond] auto-added to moongate.cfg (required for MOONGATE_PAIR's M118 output)"
fi
success "Macro written to $MOONGATE_CFG"

if grep -q '\[include moongate\.cfg\]' "$PRINTER_CFG"; then
    info "[include moongate.cfg] already present in printer.cfg"
else
    { printf '[include moongate.cfg]\n\n'; cat "$PRINTER_CFG"; } > "${PRINTER_CFG}.tmp" \
        && mv "${PRINTER_CFG}.tmp" "$PRINTER_CFG"
    success "[include moongate.cfg] added to top of printer.cfg"
fi

# ── 5. Deploy QR pairing page to web root ────────────────────────────────────
HTML_SRC="$MOONGATE_DIR/klipper-plugin/moongate-pair.html"
DEPLOYED=0
for webroot in "$MAINSAIL_DIR" "$HOME/printer_data/www" "$HOME/fluidd"; do
    if [[ -d "$webroot" ]]; then
        cp "$HTML_SRC" "$webroot/moongate-pair.html"
        success "QR page deployed to $webroot/moongate-pair.html"
        DEPLOYED=1
    fi
done
[[ $DEPLOYED -eq 0 ]] && warn "No web-root found - skipping QR page"

# ── 5b. Persist HTTP port to the plugin config ────────────────────────────────
# The plugin reads this file on each Moonraker start and embeds the port in
# the QR URL and pair-page link.  We merge with any existing config so other
# settings (TTL, attempts cap, etc.) survive a re-install.
PLUGIN_CFG_DIR="$HOME/.config/moongate"
PLUGIN_CFG_FILE="$PLUGIN_CFG_DIR/config.json"
mkdir -p "$PLUGIN_CFG_DIR"

# In LAN-only mode we also flip the plugin's lan_only flag on; in tunnel mode
# we flip it OFF, so re-running without --lan-only converts a box back.
MG_PLUGIN_LAN_ONLY=$([[ -n "$MOONGATE_LAN_ONLY" ]] && echo true || echo false)
if command -v python3 &>/dev/null; then
    python3 - "$PLUGIN_CFG_FILE" "$MOONGATE_PORT" "$MG_PLUGIN_LAN_ONLY" << 'PY'
import json, sys
path, port, lan_only = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "true"
try:
    with open(path) as f:
        data = json.load(f)
        if not isinstance(data, dict):
            data = {}
except (FileNotFoundError, ValueError):
    data = {}
data["http_port"] = port
data["lan_only"]  = lan_only
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
else
    # Best-effort fallback when python3 isn't on PATH - overwrites other keys
    cat > "$PLUGIN_CFG_FILE" << EOF
{
  "http_port": $MOONGATE_PORT,
  "lan_only": $MG_PLUGIN_LAN_ONLY
}
EOF
fi
success "Plugin config saved to $PLUGIN_CFG_FILE (lan_only=$MG_PLUGIN_LAN_ONLY)"

# ── 6-7. Remote-access stack: cloudflared + auth proxy + tunnel ──────────────
# Skipped entirely in LAN-only mode. The `if` guard runs to just before the
# Avahi block (§7b); its body is left un-indented so the systemd/sudoers
# heredocs below stay byte-for-byte identical to the tunnel-mode install.
if [[ -z "$MOONGATE_LAN_ONLY" ]]; then

# ── 6. Install cloudflared (skip if already installed) ───────────────────────
# Two install paths so this works on the variety of SBCs Klipper runs on:
#   • Debian-family (dpkg present): grab the matching .deb. Covers
#     stock MainsailOS / FluiddPI / KIAUH on Raspberry Pi, plus Armbian
#     on Orange Pi / NanoPi / Odroid etc.
#   • Anything else (no dpkg): pull the raw binary into /usr/local/bin.
#     Covers Arch Linux ARM, Alpine, and any future distro where dpkg
#     isn't around.
# Cloudflare publishes both shapes for every arch we care about, so a
# single $CF_ARCH variable drives both paths.
if command -v cloudflared &>/dev/null; then
    info "cloudflared already installed at $(command -v cloudflared) - skipping."
else
    CF_BASE="https://github.com/cloudflare/cloudflared/releases/latest/download"
    if command -v dpkg &>/dev/null; then
        info "Installing cloudflared via dpkg (cloudflared-linux-${CF_ARCH}.deb)..."
        TMP_DEB="/tmp/cloudflared-linux-${CF_ARCH}.deb"
        curl -fsSL "$CF_BASE/cloudflared-linux-${CF_ARCH}.deb" -o "$TMP_DEB" \
            || die "Failed to download cloudflared deb for $CF_ARCH"
        sudo dpkg -i "$TMP_DEB" || die "dpkg failed installing $TMP_DEB"
        rm -f "$TMP_DEB"
    else
        # No dpkg - install the binary directly. /usr/local/bin is on
        # PATH on every Linux we'd realistically run on. systemd will
        # find it via the resolved $CLOUDFLARED_BIN below.
        info "Installing cloudflared binary to /usr/local/bin (no dpkg detected)..."
        sudo curl -fsSL "$CF_BASE/cloudflared-linux-${CF_ARCH}" \
            -o /usr/local/bin/cloudflared \
            || die "Failed to download cloudflared binary for $CF_ARCH"
        sudo chmod +x /usr/local/bin/cloudflared
    fi
    success "cloudflared installed at $(command -v cloudflared)"
fi

# Resolve the cloudflared path once so the systemd unit below uses
# whichever location it actually ended up in: /usr/bin via dpkg,
# /usr/local/bin via binary, or somewhere else for a pre-existing
# install (e.g. the user dropped it in ~/bin). Avoids hard-coding
# /usr/bin/cloudflared which is wrong on non-Debian systems.
CLOUDFLARED_BIN="$(command -v cloudflared)"
[[ -n "$CLOUDFLARED_BIN" ]] || die "cloudflared not on PATH after install"

# ── 6b. Install moongate-authproxy systemd service (v0.4) ────────────────────
# The auth proxy must be running BEFORE cloudflared starts pointing at it,
# otherwise the tunnel comes up against a connection-refused upstream and
# stays in that state for 30+ seconds while cloudflared backs off.
#
# The unit file in the repo (moongate-authproxy.service) is a template with
# REPLACE_ placeholders documenting the intended shape. Here we write the
# real unit inline with the actual paths substituted - same pattern as the
# moongate-tunnel unit below.
info "Installing moongate-authproxy systemd service..."

# Resolve the Python that has aiohttp + PyJWT + cryptography. Prefer the
# Moonraker venv (where step 2b installed the deps); fall back to system
# python3 with a clear warning.
if [[ -n "$MOONRAKER_VENV" && -x "$MOONRAKER_VENV/bin/python3" ]]; then
    MG_PYTHON="$MOONRAKER_VENV/bin/python3"
else
    MG_PYTHON="$(command -v python3 || true)"
    warn "Using system python3 ($MG_PYTHON) - make sure aiohttp/PyJWT/cryptography are installed."
fi

PLUGIN_DIR="$MOONGATE_DIR/klipper-plugin"

sudo tee /etc/systemd/system/moongate-authproxy.service > /dev/null << UNIT
[Unit]
Description=Moongate v0.4 auth proxy
Documentation=https://github.com/PEEKYPAUL/Moongate
After=network-online.target moonraker.service
Wants=network-online.target
PartOf=moonraker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$PLUGIN_DIR
ExecStart=$MG_PYTHON $PLUGIN_DIR/moongate_authproxy.py

Restart=on-failure
RestartSec=3
TimeoutStopSec=10

Environment=MG_LISTEN_HOST=127.0.0.1
Environment=MG_LISTEN_PORT=$MG_AUTHPROXY_PORT
Environment=MG_MOONRAKER=http://127.0.0.1:7125
Environment=MG_MAINSAIL=http://127.0.0.1:$MOONGATE_PORT
Environment=MG_PLUGIN_DIR=$PLUGIN_DIR
Environment=MG_LOG_LEVEL=INFO

StandardOutput=journal
StandardError=journal
SyslogIdentifier=moongate-authproxy

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/run $HOME/.config/moongate
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
RestrictSUIDSGID=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable moongate-authproxy
sudo systemctl restart moongate-authproxy

# Give the proxy a couple of seconds to bind before cloudflared connects.
# Empirical: aiohttp + JWKS fetch is ready within ~1s on a Pi 4.
sleep 2
if systemctl is-active --quiet moongate-authproxy; then
    success "moongate-authproxy running on 127.0.0.1:$MG_AUTHPROXY_PORT"
else
    warn "moongate-authproxy failed to start. Check: sudo journalctl -u moongate-authproxy -n 50"
    warn "Cloudflared will still come up but every request will return 502."
fi

# ── 7. Create moongate-tunnel systemd service ────────────────────────────────
# Always (re)write the unit file so fixes to it are applied on re-runs.
# Use StandardOutput/StandardError instead of cloudflared's --logfile flag:
# cloudflared prints the tunnel URL banner to stdout; systemd captures it
# and appends it to /run/moongate-tunnel.log where the plugin can read it.
# NOTE: unlike the authproxy unit (which logs to the journal, see step 6),
# this one MUST stay an append: file - the plugin parses the tunnel URL from
# it. That is safe only because cloudflared is quiet (a banner + occasional
# reconnect lines, KBs over weeks); never point a chatty service at /run.
#
# v0.4: target is now the auth proxy ($MG_AUTHPROXY_PORT) instead of
# Moonraker / Mainsail directly. Every request goes through the EdDSA gate
# before reaching any backend.
info "Installing moongate-tunnel systemd service (cloudflared → :$MG_AUTHPROXY_PORT)..."
sudo tee /etc/systemd/system/moongate-tunnel.service > /dev/null << UNIT
[Unit]
Description=Moongate Cloudflare Tunnel
After=network-online.target moongate-authproxy.service
Wants=network-online.target moongate-authproxy.service

[Service]
Type=simple
User=$USER
ExecStart=$CLOUDFLARED_BIN tunnel --url http://localhost:$MG_AUTHPROXY_PORT --no-autoupdate
Restart=on-failure
RestartSec=10
StandardOutput=append:/run/moongate-tunnel.log
StandardError=append:/run/moongate-tunnel.log

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable moongate-tunnel
# Stop any orphan cloudflared process before starting the managed service
pkill -f "cloudflared tunnel" 2>/dev/null || true
sleep 1
sudo systemctl restart moongate-tunnel
success "moongate-tunnel service started"

# ── 7b. Let Moonraker manage the tunnel service (tunnel watchdog) ─────────────
# The plugin's tunnel watchdog (0.6.23+) self-heals a wedged tunnel by asking
# Moonraker's machine API to restart moongate-tunnel. Moonraker only touches
# units listed in moonraker.asvc, so add ours (idempotent; the file is
# user-owned, and Moonraker re-reads it on the restart at the end of this
# install).
ASVC_FILE="$PRINTER_DATA/moonraker.asvc"
if grep -qxs 'moongate-tunnel' "$ASVC_FILE"; then
    info "moongate-tunnel already in moonraker.asvc"
else
    echo 'moongate-tunnel' >> "$ASVC_FILE"
    success "moongate-tunnel added to moonraker.asvc (tunnel watchdog can self-heal)"
fi

else
    # ── LAN-only: retire any tunnel stack from a prior full install ──────────
    # Converts an existing tunnel-mode box to LAN-only: stop + disable the
    # tunnel, auth proxy, and the htpdate time-sync timer (that one calls out
    # every 30 min, so leaving it would defeat the no-external-traffic point).
    # Moonraker was already rebound in §2e, so LAN access keeps working.
    MG_RETIRED_TUNNEL=""
    for unit in moongate-tunnel.service moongate-authproxy.service moongate-timesync.timer; do
        if systemctl list-unit-files "$unit" &>/dev/null \
           && systemctl cat "$unit" &>/dev/null; then
            sudo systemctl disable --now "$unit" 2>/dev/null || true
            info "Disabled $unit (LAN-only mode)"
            [[ "$unit" == "moongate-tunnel.service" ]] && MG_RETIRED_TUNNEL=1
        fi
    done

    # Only clean up after OUR tunnel, and only if it existed. systemctl already
    # stopped the managed process above; this catches a stray one from a crash
    # or old run. The pattern is the exact moongate invocation so a user's own
    # cloudflared (e.g. a Home Assistant tunnel) as the same user is left alone.
    if [[ -n "$MG_RETIRED_TUNNEL" ]]; then
        pkill -f "cloudflared tunnel --url http://localhost:$MG_AUTHPROXY_PORT" 2>/dev/null || true
        # Drop the tunnel-URL logs: the plugin's _get_tunnel_url() reads these
        # as a fallback, so a stale URL here would keep a paired printer
        # heartbeating a dead tunnel to the server until the next reboot.
        sudo rm -f /run/moongate-tunnel.log /tmp/moongate-tunnel.log
        info "Cleared stale tunnel URL logs (LAN-only mode)"
    fi
fi

# ── 7b. Avahi mDNS advertisement - sudoers + daemon (v0.4.4) ────────────────
# Lets the plugin advertise this Pi on the local network as _moongate._tcp
# so the v0.5+ app can find it without depending on Supabase + Cloudflare.
# See docs/v0.5-lan-discovery-design.md §6 for the full design.
#
# Two pieces:
#   (1) Sudoers entry letting the plugin (running as $USER via Moonraker)
#       install + remove /etc/avahi/services/moongate.service without a
#       password. Tightly scoped: exact source and dest paths only.
#   (2) Make sure avahi-daemon is enabled. On stock MainsailOS/FluiddPI
#       it already is; this is a defensive no-op in the common case.
#
# The plugin only WRITES the service file after a successful pair (per
# §6.4 Option B). Unpaired Pis stay invisible on the LAN by design.
info "Installing Avahi mDNS sudoers entry..."
SUDOERS_FILE="/etc/sudoers.d/moongate-avahi"
sudo tee "$SUDOERS_FILE" > /dev/null << SUDOERS
# Moongate v0.4.4 - installed by klipper-plugin/install.sh
# Allows the Moonraker user to manage the Avahi mDNS advertisement.
# Tightly scoped: exactly one cp source/dest pair and one rm target.
$USER ALL=(root) NOPASSWD: /bin/cp $HOME/.config/moongate/moongate-avahi.service.tmp /etc/avahi/services/moongate.service
$USER ALL=(root) NOPASSWD: /bin/rm -f /etc/avahi/services/moongate.service
SUDOERS
sudo chmod 0440 "$SUDOERS_FILE"

# visudo -c validates syntax; reject the file rather than ship a broken
# sudoers entry that could lock out sudo for $USER on the next login.
if sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
    success "Avahi sudoers entry installed at $SUDOERS_FILE"
else
    sudo rm -f "$SUDOERS_FILE"
    warn "Avahi sudoers entry rejected by visudo - mDNS will be unavailable."
    warn "Other Moongate features are unaffected; tunnel + LAN-via-IP still work."
fi

# Make sure avahi-daemon is enabled. On stock MainsailOS / FluiddPI this is
# already true (Mainsail's <hostname>.local resolution uses it).
if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    info "avahi-daemon already running"
elif command -v systemctl &>/dev/null; then
    if sudo systemctl enable --now avahi-daemon 2>/dev/null; then
        success "avahi-daemon enabled"
    else
        warn "avahi-daemon could not be enabled (not installed?) - mDNS will be unavailable."
        warn "On Debian/Ubuntu: sudo apt install avahi-daemon"
    fi
fi

# ── 8. Restart Moonraker then Klipper ────────────────────────────────────────
info "Restarting Moonraker..."
sudo systemctl restart moonraker
sleep 3
systemctl is-active --quiet moonraker \
    && success "Moonraker running" \
    || warn "Check Moonraker: sudo systemctl status moonraker"

info "Restarting Klipper to load MOONGATE_PAIR macro..."
KLIPPER_SVC=""
for svc in klipper klipper-1; do
    if systemctl is-active --quiet "$svc" 2>/dev/null || \
       systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        KLIPPER_SVC="$svc"
        break
    fi
done

if [[ -n "$KLIPPER_SVC" ]]; then
    sudo systemctl restart "$KLIPPER_SVC"
    sleep 3
    if systemctl is-active --quiet "$KLIPPER_SVC"; then
        success "Klipper restarted - MOONGATE_PAIR macro is ready"
    else
        warn "Klipper restart may have failed. Check: sudo systemctl status $KLIPPER_SVC"
        warn "Then do a Firmware Restart in Mainsail."
    fi
else
    warn "Could not find Klipper service - please do a Firmware Restart in Mainsail."
fi

# ── 9. Show access summary ────────────────────────────────────────────────────
echo ""
LOCAL_IP=$(hostname -I | awk '{print $1}')

# Only show ":port" in the pair-page URL when it isn't the HTTP default
PORT_SUFFIX=""
[[ "$MOONGATE_PORT" -ne 80 ]] && PORT_SUFFIX=":$MOONGATE_PORT"

if [[ -z "$MOONGATE_LAN_ONLY" ]]; then
    info "Waiting for Cloudflare tunnel (~20s)..."
    sleep 20
    TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /run/moongate-tunnel.log 2>/dev/null || true)
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Moongate installed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Updates   : ${BLUE}Mainsail → Software Updates → Moongate${NC}"
echo -e "  Pairing   : ${BLUE}http://$LOCAL_IP$PORT_SUFFIX/moongate-pair.html${NC} (LAN only)"
if [[ -n "$MOONGATE_LAN_ONLY" ]]; then
    echo -e "  Mode      : ${GREEN}LAN-only${NC} (no Cloudflare tunnel / auth proxy)"
    echo -e "  Mainsail  : ${GREEN}http://$LOCAL_IP$PORT_SUFFIX/${NC}"
    echo -e "  Moonraker : ${GREEN}http://$LOCAL_IP:7125${NC} (reach over your LAN / VPN)"
else
    echo -e "  Auth proxy: ${BLUE}127.0.0.1:$MG_AUTHPROXY_PORT${NC} (every tunnel request EdDSA-gated)"
    if [[ -n "$TUNNEL_URL" ]]; then
        SUBDOMAIN="${TUNNEL_URL#https://}"
        SUBDOMAIN="${SUBDOMAIN%.trycloudflare.com}"
        echo -e "  Tunnel    : ${GREEN}$TUNNEL_URL${NC} ✓"
        echo -e "  Subdomain : ${GREEN}$SUBDOMAIN${NC} (paste into app tunnel field)"
    else
        echo -e "  Tunnel    : ${YELLOW}still starting - check in 30s:${NC}"
        echo -e "    grep -o 'https://.*trycloudflare.com' /run/moongate-tunnel.log"
    fi
fi
echo ""
echo -e "  Run ${YELLOW}MOONGATE_PAIR${NC} in Klipper console to pair."
echo ""

# ── 10. Moonraker-clients heads-up ───────────────────────────────────────────
# The 127.0.0.1 rebind in step 2e hides Moonraker from the LAN, which breaks any
# client that reached it by IP:7125 - ON this Pi that's usually KlipperScreen
# ("Cannot connect to Moonraker - Connection refused"), and on OTHER machines a
# central/farm Mainsail or Fluidd managing several printers by IP. The fixes
# differ (localhost vs the Pi's nginx on port 80), so the box covers both.
# We only PROMPT when a real terminal is attached: an interactive `curl | bash`
# can still read the answer from /dev/tty even though its stdin is the pipe,
# while a headless / KIAUH / MOONGATE_YES run has none - there we just print
# the notice so it's never lost, and never block on a `read` under `set -e`.
mg_moonraker_clients_box() {
    local line
    printf -v line '#%.0s' {1..70}
    echo -e "${YELLOW}"
    echo "$line"
    printf '# %-66s #\n' ""
    printf '# %-66s #\n' "OTHER APPS TALK TO THIS PRINTER'S MOONRAKER DIRECTLY?"
    printf '# %-66s #\n' ""
    printf '# %-66s #\n' "Moongate just bound Moonraker to 127.0.0.1 (localhost) so only"
    printf '# %-66s #\n' "its secure tunnel is exposed. Anything that reached Moonraker"
    printf '# %-66s #\n' "at this Pi's LAN IP on port 7125 now fails with:"
    printf '# %-66s #\n' "    Connection refused"
    printf '# %-66s #\n' ""
    printf '# %-66s #\n' "ON THIS PI (KlipperScreen, HelixScreen, ...):  use localhost."
    printf '# %-66s #\n' "Edit ~/printer_data/config/KlipperScreen.conf, [printer ...]:"
    printf '# %-66s #\n' "    moonraker_host: 127.0.0.1"
    printf '# %-66s #\n' "    moonraker_port: 7125"
    printf '# %-66s #\n' "then:  sudo systemctl restart KlipperScreen  (or the Services"
    printf '# %-66s #\n' "panel in Mainsail / Fluidd)."
    printf '# %-66s #\n' ""
    printf '# %-66s #\n' "FROM ANOTHER MACHINE (central/farm Mainsail or Fluidd, tools):"
    printf '# %-66s #\n' "use port 80 - this Pi's nginx serves the full Moonraker API"
    printf '# %-66s #\n' "there. Change the printer entry <pi-ip>:7125 to just <pi-ip>."
    printf '# %-66s #\n' ""
    printf '# %-66s #\n' "Need raw :7125 open on the LAN like a stock install? Re-run"
    printf '# %-66s #\n' "this installer with MOONGATE_KEEP_BIND=1 (see TROUBLESHOOTING)."
    printf '# %-66s #\n' ""
    echo "$line"
    echo -e "${NC}"
}

if [[ -n "$MOONGATE_LAN_ONLY" ]]; then
    # LAN-only kept Moonraker on 0.0.0.0, so clients that reach it by IP
    # (KlipperScreen, a farm Mainsail) are unaffected - nothing to warn about.
    info "LAN-only mode: Moonraker stays on the LAN - existing clients are unaffected."
elif [[ -n "$MOONGATE_KEEP_BIND" ]]; then
    # Bind untouched by request - whatever talked to Moonraker still can.
    info "Keep-bind: Moonraker's bind is unchanged - existing clients are unaffected."
elif [[ -z "${MOONGATE_YES:-}" && -r /dev/tty ]]; then
    printf '%b' "${YELLOW}[moongate]${NC} Do you use KlipperScreen, a central/farm Mainsail, or other apps that talk to Moonraker directly? [y/N] "
    read -r MG_KS_ANS < /dev/tty || MG_KS_ANS=""
    case "$MG_KS_ANS" in
        [Yy]*) mg_moonraker_clients_box ;;
        *)     info "No other Moonraker clients - nothing else to do." ;;
    esac
else
    mg_moonraker_clients_box
fi
