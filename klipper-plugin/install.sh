#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Moongate installer
# Run on your Klipper Pi:
#   curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/main/klipper-plugin/install.sh | bash
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

# ── 1. Install Moongate Klipper plugin ───────────────────────────────────────
info "Installing Moongate plugin..."

PLUGIN_URL="https://raw.githubusercontent.com/PEEKYPAUL/moongate/main/klipper-plugin/moongate_standalone.py"
curl -fsSL "$PLUGIN_URL" -o "$COMPONENTS_DIR/moongate.py"
success "Plugin installed at $COMPONENTS_DIR/moongate.py"

if grep -q '^\[moongate\]' "$MOONRAKER_CONF"; then
    info "[moongate] already in moonraker.conf"
else
    printf '\n[moongate]\n# Moongate pairing + remote access plugin\n' >> "$MOONRAKER_CONF"
    success "[moongate] added to moonraker.conf"
fi

# ── 2. Deploy QR pairing page to Mainsail ────────────────────────────────────
if [[ -d "$MAINSAIL_DIR" ]]; then
    HTML_URL="https://raw.githubusercontent.com/PEEKYPAUL/moongate/main/klipper-plugin/moongate-pair.html"
    curl -fsSL "$HTML_URL" -o "$MAINSAIL_DIR/moongate-pair.html"
    success "QR page deployed to $MAINSAIL_DIR/moongate-pair.html"
else
    warn "Mainsail not found at $MAINSAIL_DIR — skipping QR page"
fi

# ── 3. Install cloudflared ────────────────────────────────────────────────────
info "Installing cloudflared..."

CF_DEB="cloudflared-linux-${CF_ARCH}.deb"
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/$CF_DEB"
TMP_DEB="/tmp/$CF_DEB"

curl -fsSL "$CF_URL" -o "$TMP_DEB"
sudo dpkg -i "$TMP_DEB"
rm -f "$TMP_DEB"
success "cloudflared installed"

# ── 4. Create moongate-tunnel systemd service ─────────────────────────────────
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

# ── 5. Restart Moonraker ──────────────────────────────────────────────────────
info "Restarting Moonraker..."
sudo systemctl restart moonraker
sleep 3
systemctl is-active moonraker > /dev/null \
    && success "Moonraker running" \
    || warn "Check Moonraker: sudo systemctl status moonraker"

# ── 6. Show tunnel URL ────────────────────────────────────────────────────────
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
