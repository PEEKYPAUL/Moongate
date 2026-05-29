#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Moongate installer
# Run on your Klipper Pi:
#   curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh | bash
#
# Re-running is safe — existing tokens, config, and cloudflared are untouched.
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

# Loopback port the v0.4 auth proxy binds to. cloudflared targets this
# instead of Moonraker directly. Override with MG_AUTHPROXY_PORT=NNNN.
MG_AUTHPROXY_PORT="${MG_AUTHPROXY_PORT:-8443}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)      [[ -n "${2-}" ]] || die "--port needs a value"; MOONGATE_PORT="$2"; shift 2;;
        --port=*)    MOONGATE_PORT="${1#*=}"; shift;;
        *)           shift;;
    esac
done
[[ "$MOONGATE_PORT" =~ ^[0-9]+$ ]] \
    || die "Port must be numeric — got: $MOONGATE_PORT"
[[ "$MOONGATE_PORT" -ge 1 && "$MOONGATE_PORT" -le 65535 ]] \
    || die "Port out of range (1-65535): $MOONGATE_PORT"
info "HTTP port: $MOONGATE_PORT"

# ── Detect environment ────────────────────────────────────────────────────────
MOONGATE_REPO="https://github.com/PEEKYPAUL/moongate.git"
MOONGATE_DIR="${MOONGATE_DIR:-$HOME/moongate}"
MOONRAKER_DIR="${MOONRAKER_DIR:-$HOME/moonraker}"
MAINSAIL_DIR="${MAINSAIL_DIR:-$HOME/mainsail}"
PRINTER_DATA="${PRINTER_DATA:-$HOME/printer_data}"
MOONRAKER_CONF="$PRINTER_DATA/config/moonraker.conf"
COMPONENTS_DIR="$MOONRAKER_DIR/moonraker/components"
KLIPPER_CFG_DIR="$PRINTER_DATA/config"

[[ -d "$MOONRAKER_DIR" ]]  || die "Moonraker not found at $MOONRAKER_DIR. Set MOONRAKER_DIR= if installed elsewhere."
[[ -f "$MOONRAKER_CONF" ]] || die "moonraker.conf not found at $MOONRAKER_CONF."

ARCH=$(uname -m)

# Pick the cloudflared deb that matches the dpkg system architecture.
# uname -m alone is unreliable: the kernel reports armv7l on a system
# whose userland is armhf, and dpkg refuses to install an "arm" deb on
# an "armhf" host. dpkg --print-architecture is what dpkg uses when
# matching a .deb, so it's the authoritative source here.
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
    # No dpkg — unusual on a Klipper Pi, but fall back to uname so the
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

# ── 1. Clone or update the Moongate repo ─────────────────────────────────────
# Cloning to ~/moongate lets Moonraker's update manager track the repo and
# show updates in Mainsail's update panel — just like Klipper/Mainsail itself.
info "Setting up Moongate repository at $MOONGATE_DIR..."

if [[ -d "$MOONGATE_DIR/.git" ]]; then
    CURRENT_BRANCH="$(git -C "$MOONGATE_DIR" branch --show-current 2>/dev/null || echo unknown)"
    if [[ "$CURRENT_BRANCH" == "master" ]]; then
        info "Repo on master — pulling latest..."
        # Robust update: `git pull --ff-only` can fail fatally for several
        # reasons — divergent history (force-push upstream), dirty working
        # tree (CRLF conversion, manual edits), untracked files that would
        # be overwritten, or local commits ahead of master. set -e would
        # then abort the installer mid-way. Fall back to re-cloning fresh,
        # preserving the broken clone for forensic inspection. (Git's own
        # error message printed above tells the user the specific cause.)
        if git -C "$MOONGATE_DIR" fetch origin master \
            && git -C "$MOONGATE_DIR" merge --ff-only origin/master; then
            success "Repository updated."
        else
            BROKEN_DIR="${MOONGATE_DIR}.broken-$(date +%Y%m%d-%H%M%S)"
            warn "Local clone can't fast-forward to origin/master (see git error above)."
            warn "Moving aside to $BROKEN_DIR and re-cloning fresh."
            mv "$MOONGATE_DIR" "$BROKEN_DIR"
            git clone --depth=1 "$MOONGATE_REPO" "$MOONGATE_DIR"
            success "Repository re-cloned. Old clone preserved at $BROKEN_DIR"
        fi
    else
        warn "Repo on branch '$CURRENT_BRANCH' (not master) — skipping git pull."
        warn "Run 'git pull' manually if you intended to update."
    fi
else
    git clone --depth=1 "$MOONGATE_REPO" "$MOONGATE_DIR"
    success "Repository cloned to $MOONGATE_DIR"
fi

PLUGIN_SRC="$MOONGATE_DIR/klipper-plugin/moongate_standalone.py"

# ── 2. Install Moongate Moonraker plugin (symlink) ───────────────────────────
# Using a symlink means git pull automatically gives you the new plugin —
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
# v0.3 uses device_ed25519 / owner.json / jwks.json — none of the old files
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
# downgrade. Each file is backed up exactly once — re-running install.sh
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

# ── 2e. Bind Moonraker to 127.0.0.1 (v0.4 auth proxy fronts everything) ──────
# In v0.4 the cloudflared tunnel terminates at moongate-authproxy (port 8443).
# Moonraker becomes loopback-only so it cannot be reached via the tunnel
# without passing the EdDSA gate. LAN access via the Pi's local IP is
# unchanged because moonraker's `trusted_clients` still allows the LAN
# subnet.
info "Binding Moonraker to 127.0.0.1 (v0.4 hardening)..."
backup_once "$MOONRAKER_CONF" "moonraker.conf.orig"

python3 - "$MOONRAKER_CONF" << 'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

# Find or create the [server] section.
server_match = re.search(r'(?m)^\[server\]\s*$', content)
if not server_match:
    # No [server] block at all — append one with our settings.
    content = content.rstrip() + "\n\n[server]\nhost: 127.0.0.1\nport: 7125\n"
else:
    # Locate the end of the [server] block (next [section] or EOF).
    start = server_match.end()
    next_section = re.search(r'(?m)^\[', content[start:])
    end = start + next_section.start() if next_section else len(content)
    section = content[start:end]

    if re.search(r'(?m)^\s*host\s*[:=]', section):
        # host: already set — force to 127.0.0.1.
        new_section = re.sub(
            r'(?m)^(\s*host\s*[:=]\s*).*$',
            r'\g<1>127.0.0.1',
            section,
            count=1,
        )
    else:
        # No host: line in [server] — inject one right after the header.
        new_section = "\nhost: 127.0.0.1" + section

    content = content[:start] + new_section + content[end:]

with open(path, 'w') as f:
    f.write(content)
print("moonraker.conf: [server] host=127.0.0.1")
PYEOF
success "Moonraker bound to 127.0.0.1"

# NOTE: We intentionally do NOT patch nginx vhosts in v0.4.0. The original
# v0.4 design considered binding nginx to 127.0.0.1 (defense in depth), but
# that would break the LAN-first path that v0.3 introduced — Mainsail loaded
# from http://<pi-lan-ip>/ would 404 because nothing would be listening on
# the LAN interface. The actual security guarantee comes from retargeting
# cloudflared (step 7 below) to the auth proxy: the tunnel no longer reaches
# nginx, only the EdDSA gate. nginx stays reachable on LAN exactly as today.
# If a user explicitly port-forwards :80, they have made nginx public on
# their own initiative — same risk profile as v0.3 in that scenario.

if grep -q '^\[moongate\]' "$MOONRAKER_CONF"; then
    info "[moongate] already in moonraker.conf"
else
    printf '\n[moongate]\n# Moongate pairing + remote access plugin\n' >> "$MOONRAKER_CONF"
    success "[moongate] added to moonraker.conf"
fi

# ── 3. Register with Moonraker's update manager ───────────────────────────────
# This adds Moongate to the Software Updates panel in Mainsail — same as
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
    die "Cannot find printer.cfg — tried:
  $PRINTER_DATA/config/printer.cfg
  $HOME/klipper_config/printer.cfg
  $HOME/printer_data/config/printer.cfg
Set PRINTER_DATA=/path/to/printer_data and re-run."
fi

info "Found printer.cfg at $PRINTER_CFG"
KLIPPER_CFG_DIR="$(dirname "$PRINTER_CFG")"
MOONGATE_CFG="$KLIPPER_CFG_DIR/moongate.cfg"

cat > "$MOONGATE_CFG" << 'MACROEOF'
# ── Moongate ──────────────────────────────────────────────────────────────────
# Managed by the Moongate installer — do not edit manually.
# Updates are handled automatically via Moonraker's update manager.

[gcode_macro MOONGATE_PAIR]
description: Start a Moongate pairing session and show a QR for the mobile app
gcode:
    {action_call_remote_method("moongate_generate_pair_code")}

[gcode_macro MOONGATE_RESET_OWNER]
description: Wipe local Moongate owner binding so the printer can be re-paired
gcode:
    {action_call_remote_method("moongate_reset_owner")}
MACROEOF

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
[[ $DEPLOYED -eq 0 ]] && warn "No web-root found — skipping QR page"

# ── 5b. Persist HTTP port to the plugin config ────────────────────────────────
# The plugin reads this file on each Moonraker start and embeds the port in
# the QR URL and pair-page link.  We merge with any existing config so other
# settings (TTL, attempts cap, etc.) survive a re-install.
PLUGIN_CFG_DIR="$HOME/.config/moongate"
PLUGIN_CFG_FILE="$PLUGIN_CFG_DIR/config.json"
mkdir -p "$PLUGIN_CFG_DIR"

if command -v python3 &>/dev/null; then
    python3 - "$PLUGIN_CFG_FILE" "$MOONGATE_PORT" << 'PY'
import json, sys
path, port = sys.argv[1], int(sys.argv[2])
try:
    with open(path) as f:
        data = json.load(f)
        if not isinstance(data, dict):
            data = {}
except (FileNotFoundError, ValueError):
    data = {}
data["http_port"] = port
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
else
    # Best-effort fallback when python3 isn't on PATH — overwrites other keys
    cat > "$PLUGIN_CFG_FILE" << EOF
{
  "http_port": $MOONGATE_PORT
}
EOF
fi
success "Plugin HTTP port saved to $PLUGIN_CFG_FILE"

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
    info "cloudflared already installed at $(command -v cloudflared) — skipping."
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
        # No dpkg — install the binary directly. /usr/local/bin is on
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
# real unit inline with the actual paths substituted — same pattern as the
# moongate-tunnel unit below.
info "Installing moongate-authproxy systemd service..."

# Resolve the Python that has aiohttp + PyJWT + cryptography. Prefer the
# Moonraker venv (where step 2b installed the deps); fall back to system
# python3 with a clear warning.
if [[ -n "$MOONRAKER_VENV" && -x "$MOONRAKER_VENV/bin/python3" ]]; then
    MG_PYTHON="$MOONRAKER_VENV/bin/python3"
else
    MG_PYTHON="$(command -v python3 || true)"
    warn "Using system python3 ($MG_PYTHON) — make sure aiohttp/PyJWT/cryptography are installed."
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

StandardOutput=append:/run/moongate-authproxy.log
StandardError=append:/run/moongate-authproxy.log

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
        success "Klipper restarted — MOONGATE_PAIR macro is ready"
    else
        warn "Klipper restart may have failed. Check: sudo systemctl status $KLIPPER_SVC"
        warn "Then do a Firmware Restart in Mainsail."
    fi
else
    warn "Could not find Klipper service — please do a Firmware Restart in Mainsail."
fi

# ── 9. Show tunnel URL ────────────────────────────────────────────────────────
echo ""
info "Waiting for Cloudflare tunnel (~20s)..."
sleep 20

LOCAL_IP=$(hostname -I | awk '{print $1}')
TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /run/moongate-tunnel.log 2>/dev/null || true)

# Only show ":port" in the pair-page URL when it isn't the HTTP default
PORT_SUFFIX=""
[[ "$MOONGATE_PORT" -ne 80 ]] && PORT_SUFFIX=":$MOONGATE_PORT"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Moongate installed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Updates   : ${BLUE}Mainsail → Software Updates → Moongate${NC}"
echo -e "  Pairing   : ${BLUE}http://$LOCAL_IP$PORT_SUFFIX/moongate-pair.html${NC} (LAN only)"
echo -e "  Auth proxy: ${BLUE}127.0.0.1:$MG_AUTHPROXY_PORT${NC} (every tunnel request EdDSA-gated)"
if [[ -n "$TUNNEL_URL" ]]; then
    SUBDOMAIN="${TUNNEL_URL#https://}"
    SUBDOMAIN="${SUBDOMAIN%.trycloudflare.com}"
    echo -e "  Tunnel    : ${GREEN}$TUNNEL_URL${NC} ✓"
    echo -e "  Subdomain : ${GREEN}$SUBDOMAIN${NC} (paste into app tunnel field)"
else
    echo -e "  Tunnel    : ${YELLOW}still starting — check in 30s:${NC}"
    echo -e "    grep -o 'https://.*trycloudflare.com' /run/moongate-tunnel.log"
fi
echo ""
echo -e "  Run ${YELLOW}MOONGATE_PAIR${NC} in Klipper console to pair."
echo ""
