#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Moongate installer
# Run on your Klipper Pi:
#   curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/install.sh | bash
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[moongate]${NC} $*"; }
success() { echo -e "${GREEN}[moongate]${NC} $*"; }
warn()    { echo -e "${YELLOW}[moongate]${NC} $*"; }
die()     { echo -e "${RED}[moongate] ERROR:${NC} $*" >&2; exit 1; }

# ── Detect environment ────────────────────────────────────────────────────────
MOONRAKER_DIR="${MOONRAKER_DIR:-$HOME/moonraker}"
MAINSAIL_DIR="${MAINSAIL_DIR:-$HOME/mainsail}"
PRINTER_DATA="${PRINTER_DATA:-$HOME/printer_data}"
MOONRAKER_CONF="$PRINTER_DATA/config/moonraker.conf"
COMPONENTS_DIR="$MOONRAKER_DIR/moonraker/components"
KLIPPER_CFG_DIR="$PRINTER_DATA/config"

[[ -d "$MOONRAKER_DIR" ]]  || die "Moonraker not found at $MOONRAKER_DIR. Set MOONRAKER_DIR= if installed elsewhere."
[[ -f "$MOONRAKER_CONF" ]] || die "moonraker.conf not found at $MOONRAKER_CONF."

ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64) CF_ARCH="arm64" ;;
    armv7l|armhf)  CF_ARCH="arm"   ;;
    x86_64)        CF_ARCH="amd64" ;;
    *) die "Unsupported architecture: $ARCH" ;;
esac

info "Architecture: $ARCH → cloudflared: $CF_ARCH"

# ── 1. Install Moongate Moonraker plugin ──────────────────────────────────────
info "Installing Moongate plugin..."

PLUGIN_URL="https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/moongate_standalone.py"
curl -fsSL "$PLUGIN_URL" -o "$COMPONENTS_DIR/moongate.py"
success "Plugin installed at $COMPONENTS_DIR/moongate.py"

if grep -q '^\[moongate\]' "$MOONRAKER_CONF"; then
    info "[moongate] already in moonraker.conf"
else
    printf '\n[moongate]\n# Moongate pairing + remote access plugin\n' >> "$MOONRAKER_CONF"
    success "[moongate] added to moonraker.conf"
fi

# ── 2. Add MOONGATE_PAIR macro to Klipper config ──────────────────────────────
info "Adding MOONGATE_PAIR macro to Klipper config..."

MOONGATE_CFG="$KLIPPER_CFG_DIR/moongate.cfg"

# Always overwrite so re-running the installer updates the macro.
cat > "$MOONGATE_CFG" << 'MACROEOF'
# ── Moongate ──────────────────────────────────────────────────────────────────
# Managed by the Moongate installer — do not edit manually.
# Re-run install.sh to update.

[gcode_macro MOONGATE_PAIR]
description: Generate a Moongate pairing code for the mobile app
gcode:
    {action_call_remote_method("moongate_generate_pair_code")}
MACROEOF

success "Macro written to $MOONGATE_CFG"

# Add [include moongate.cfg] to printer.cfg if it isn't already there.
PRINTER_CFG="$KLIPPER_CFG_DIR/printer.cfg"
if [[ -f "$PRINTER_CFG" ]]; then
    if grep -q '\[include moongate\.cfg\]' "$PRINTER_CFG"; then
        info "[include moongate.cfg] already in printer.cfg"
    else
        printf '\n[include moongate.cfg]\n' >> "$PRINTER_CFG"
        success "[include moongate.cfg] added to printer.cfg"
    fi
else
    warn "printer.cfg not found at $PRINTER_CFG"
    warn "Add the following line to your printer.cfg manually:"
    warn "  [include moongate.cfg]"
fi

# ── 3. Deploy QR pairing page to Mainsail ────────────────────────────────────
if [[ -d "$MAINSAIL_DIR" ]]; then
    HTML_URL="https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/moongate-pair.html"
    curl -fsSL "$HTML_URL" -o "$MAINSAIL_DIR/moongate-pair.html"
    success "QR page deployed to $MAINSAIL_DIR/moongate-pair.html"
else
    warn "Mainsail not found at $MAINSAIL_DIR — skipping QR page"
fi

# ── 4. Install cloudflared ────────────────────────────────────────────────────
info "Installing cloudflared..."

CF_DEB="cloudflared-linux-${CF_ARCH}.deb"
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_DEB"
TMP_DEB="/tmp/$CF_DEB"

curl -fsSL "$CF_URL" -o "$TMP_DEB"
sudo dpkg -i "$TMP_DEB"
rm -f "$TMP_DEB"
success "cloudflared installed"

# ── 5. Create moongate-tunnel systemd service ─────────────────────────────────
info "Creating moongate-tunnel systemd service..."

sudo tee /etc/systemd/system/moongate-tunnel.service > /dev/null << UNIT
[Unit]
Description=Moongate Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/cloudflared tunnel --url http://localhost:80 --no-autoupdate --logfile /run/moongate-tunnel.log
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable moongate-tunnel
sudo systemctl restart moongate-tunnel
success "moongate-tunnel service started"

# ── 6. Restart Moonraker then Klipper ────────────────────────────────────────
info "Restarting Moonraker..."
sudo systemctl restart moonraker
sleep 3
systemctl is-active moonraker > /dev/null \
    && success "Moonraker running" \
    || warn "Check Moonraker: sudo systemctl status moonraker"

info "Restarting Klipper to load MOONGATE_PAIR macro..."
# Try common Klipper service names.
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
    sleep 2
    systemctl is-active "$KLIPPER_SVC" > /dev/null \
        && success "Klipper restarted — MOONGATE_PAIR macro is ready" \
        || warn "Check Klipper: sudo systemctl status $KLIPPER_SVC"
else
    warn "Klipper service not found — do a Firmware Restart in Mainsail to load the macro"
fi

# ── 7. Show tunnel URL ────────────────────────────────────────────────────────
echo ""
info "Waiting for Cloudflare tunnel (~20s)..."
sleep 20

LOCAL_IP=$(hostname -I | awk '{print $1}')
TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /run/moongate-tunnel.log 2>/dev/null || true)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Moongate installed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Pairing page : ${BLUE}http://$LOCAL_IP/moongate-pair.html${NC}"
if [[ -n "$TUNNEL_URL" ]]; then
    echo -e "  Remote access: ${GREEN}$TUNNEL_URL${NC} ✓"
else
    echo -e "  Remote access: ${YELLOW}tunnel starting — check in 30s:${NC}"
    echo -e "    grep -o 'https://.*trycloudflare.com' /run/moongate-tunnel.log"
fi
echo ""
echo -e "  Next step: run ${YELLOW}MOONGATE_PAIR${NC} in Klipper console,"
echo -e "  open the pairing page above on your PC, and scan with the app."
echo ""
