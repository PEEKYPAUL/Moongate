#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Moongate uninstaller
# Run on your Klipper Pi:
#   curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/uninstall.sh | MOONGATE_YES=1 bash
# or, with an interactive confirmation prompt:
#   curl -fsSL https://raw.githubusercontent.com/PEEKYPAUL/moongate/master/klipper-plugin/uninstall.sh -o /tmp/u.sh && bash /tmp/u.sh
#
# Removes the plugin, tunnel service, repo clone, and all config data.
# Does NOT remove cloudflared itself (it may be used by other services).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[moongate]${NC} $*"; }
success() { echo -e "${GREEN}[moongate]${NC} $*"; }
warn()    { echo -e "${YELLOW}[moongate]${NC} $*"; }
die()     { echo -e "${RED}[moongate] ERROR:${NC} $*" >&2; exit 1; }

MOONGATE_DIR="${MOONGATE_DIR:-$HOME/moongate}"
MOONRAKER_DIR="${MOONRAKER_DIR:-$HOME/moonraker}"
PRINTER_DATA="${PRINTER_DATA:-$HOME/printer_data}"
MOONRAKER_CONF="$PRINTER_DATA/config/moonraker.conf"
COMPONENTS_DIR="$MOONRAKER_DIR/moonraker/components"

echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Moongate Uninstaller${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "This will remove:"
echo "  • moongate-tunnel systemd service (cloudflared tunnel)"
echo "  • moongate-authproxy systemd service (v0.4 auth proxy)"
echo "  • Moongate Moonraker plugin"
echo "  • ~/moongate repository clone"
echo "  • ~/.config/moongate (tokens + secret key + v0.4 backup dir)"
echo "  • [moongate] entries in moonraker.conf"
echo "  • MOONGATE_PAIR macro from printer config"
echo "  • moongate-pair.html from Mainsail"
echo "  • Avahi mDNS service file + sudoers entry (v0.4.4)"
echo ""
echo "And RESTORE (from ~/.config/moongate/v0.4-backup/ if present):"
echo "  • moonraker.conf — back to pre-v0.4 (Moonraker bound to 0.0.0.0)"
echo ""
# Honor explicit non-interactive confirmation (env var or flag) before the
# TTY check. Required for `curl ... | bash` because bash's stdin is the
# script content — `read` can't reach the user's keyboard, so an interactive
# prompt would silently abort.
if [[ "${MOONGATE_YES:-}" == "1" ]] || [[ "${1:-}" == "-y" ]] || [[ "${1:-}" == "--yes" ]]; then
    confirm=y
elif [[ -t 0 ]]; then
    read -r -p "Continue? [y/N] " confirm
else
    die "Cannot prompt for confirmation (stdin is not a terminal).
To run via curl|bash, set MOONGATE_YES=1:
    curl -fsSL <url> | MOONGATE_YES=1 bash
Or download first and run with -y:
    curl -fsSL <url> -o /tmp/u.sh && bash /tmp/u.sh -y"
fi
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

# ── 1. Stop and remove the tunnel service ────────────────────────────────────
info "Stopping moongate-tunnel service..."
if systemctl is-active --quiet moongate-tunnel 2>/dev/null; then
    sudo systemctl stop moongate-tunnel
    success "moongate-tunnel stopped"
else
    warn "moongate-tunnel was not running"
fi

if systemctl is-enabled --quiet moongate-tunnel 2>/dev/null; then
    sudo systemctl disable moongate-tunnel
fi

if [[ -f /etc/systemd/system/moongate-tunnel.service ]]; then
    sudo rm -f /etc/systemd/system/moongate-tunnel.service
    sudo systemctl daemon-reload
    success "moongate-tunnel service removed"
fi

# Kill any lingering cloudflared process — guarantees a fresh tunnel URL on
# the next install. systemctl stop reaps the managed PID, but a manually-
# started cloudflared (or one orphaned from a half-finished prior install)
# would survive otherwise and hold the existing URL.
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    sleep 1
    success "Killed lingering cloudflared tunnel process(es)"
fi

# Tunnel log
sudo rm -f /run/moongate-tunnel.log /tmp/moongate-tunnel.log

# ── 1b. Stop and remove the v0.4 auth proxy service ──────────────────────────
info "Stopping moongate-authproxy service..."
if systemctl is-active --quiet moongate-authproxy 2>/dev/null; then
    sudo systemctl stop moongate-authproxy
    success "moongate-authproxy stopped"
else
    warn "moongate-authproxy was not running"
fi

if systemctl is-enabled --quiet moongate-authproxy 2>/dev/null; then
    sudo systemctl disable moongate-authproxy
fi

if [[ -f /etc/systemd/system/moongate-authproxy.service ]]; then
    sudo rm -f /etc/systemd/system/moongate-authproxy.service
    sudo systemctl daemon-reload
    success "moongate-authproxy service removed"
fi

sudo rm -f /run/moongate-authproxy.log

# ── 1c. Restore v0.4 backups BEFORE wiping ~/.config/moongate ────────────────
# Order matters: the backup dir lives inside ~/.config/moongate which step 4
# removes. Restore configs first, then nuke the config dir.
V04_BACKUP_DIR="$HOME/.config/moongate/v0.4-backup"

if [[ -d "$V04_BACKUP_DIR" ]]; then
    info "Restoring v0.4 backups..."

    # Moonraker config — restore from the pristine pre-v0.4 snapshot.
    if [[ -f "$V04_BACKUP_DIR/moonraker.conf.orig" && -f "$MOONRAKER_CONF" ]]; then
        cp "$V04_BACKUP_DIR/moonraker.conf.orig" "$MOONRAKER_CONF"
        success "moonraker.conf restored"
    fi

    # nginx-*.orig backups may exist from an earlier draft of v0.4 that
    # patched nginx too. We don't restore them (the corresponding install
    # path was removed before ship), but we don't delete them either —
    # if a user has them, the corresponding nginx vhost was already
    # restored manually or never modified.
else
    info "No v0.4 backup dir found — skipping restore (Pi was never v0.4 or already cleaned)."
fi

# ── 1d. Remove Avahi mDNS advertisement + sudoers entry (v0.4.4) ─────────────
# The plugin normally removes its own service file on _wipe_owner, but we
# clean up here defensively in case (a) the plugin was uninstalled without
# running MOONGATE_RESET_OWNER first, (b) sudo failed during plugin
# shutdown, or (c) the file was left over from a manual edit. avahi-daemon
# itself is left alone — other services on the system use it.
info "Removing Avahi mDNS advertisement..."
if [[ -f /etc/avahi/services/moongate.service ]]; then
    sudo rm -f /etc/avahi/services/moongate.service
    success "Avahi service file removed"
fi
if [[ -f /etc/sudoers.d/moongate-avahi ]]; then
    sudo rm -f /etc/sudoers.d/moongate-avahi
    success "Avahi sudoers entry removed"
fi

# ── 2. Remove plugin from Moonraker components ────────────────────────────────
info "Removing Moonraker plugin..."
if [[ -e "$COMPONENTS_DIR/moongate.py" ]]; then
    rm -f "$COMPONENTS_DIR/moongate.py"
    success "Plugin removed from $COMPONENTS_DIR"
else
    warn "Plugin not found at $COMPONENTS_DIR/moongate.py"
fi

# ── 3. Remove repo clone ──────────────────────────────────────────────────────
info "Removing repo clone at $MOONGATE_DIR..."
if [[ -d "$MOONGATE_DIR" ]]; then
    rm -rf "$MOONGATE_DIR"
    success "Repo clone removed"
else
    warn "$MOONGATE_DIR not found (may have been manually removed)"
fi

# ── 4. Remove config data (tokens, secret key) ───────────────────────────────
info "Removing ~/.config/moongate..."
if [[ -d "$HOME/.config/moongate" ]]; then
    rm -rf "$HOME/.config/moongate"
    success "Config data removed"
else
    warn "~/.config/moongate not found"
fi

# ── 5. Remove [moongate] blocks from moonraker.conf ──────────────────────────
info "Cleaning moonraker.conf..."
if [[ -f "$MOONRAKER_CONF" ]]; then
    python3 - "$MOONRAKER_CONF" << 'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
# Remove [moongate] section (everything up to the next section header or EOF)
content = re.sub(r'\n\[moongate\].*?(?=\n\[|\Z)', '', content, flags=re.DOTALL)
# Remove [update_manager moongate] section
content = re.sub(r'\n\[update_manager moongate\].*?(?=\n\[|\Z)', '', content, flags=re.DOTALL)
with open(path, 'w') as f:
    f.write(content)
print("moonraker.conf cleaned.")
PYEOF
    success "Removed [moongate] and [update_manager moongate] from moonraker.conf"
else
    warn "moonraker.conf not found at $MOONRAKER_CONF"
fi

# ── 6. Remove macro from Klipper config ──────────────────────────────────────
info "Removing MOONGATE_PAIR macro..."

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

if [[ -n "$PRINTER_CFG" ]]; then
    MOONGATE_CFG="$(dirname "$PRINTER_CFG")/moongate.cfg"

    # Remove [include moongate.cfg] from printer.cfg
    if grep -q '\[include moongate\.cfg\]' "$PRINTER_CFG"; then
        sed -i '/\[include moongate\.cfg\]/d' "$PRINTER_CFG"
        success "Removed [include moongate.cfg] from printer.cfg"
    fi

    # Remove moongate.cfg
    if [[ -f "$MOONGATE_CFG" ]]; then
        rm -f "$MOONGATE_CFG"
        success "Removed moongate.cfg"
    fi
else
    warn "printer.cfg not found — skipping macro removal"
fi

# ── 7. Remove pair page from web roots ───────────────────────────────────────
info "Removing moongate-pair.html from web roots..."
for webroot in "$HOME/mainsail" "$HOME/printer_data/www" "$HOME/fluidd"; do
    if [[ -f "$webroot/moongate-pair.html" ]]; then
        rm -f "$webroot/moongate-pair.html"
        success "Removed from $webroot"
    fi
done

# ── 8. Restart Moonraker ──────────────────────────────────────────────────────
info "Restarting Moonraker..."
sudo systemctl restart moonraker
sleep 3
systemctl is-active --quiet moonraker \
    && success "Moonraker restarted cleanly" \
    || warn "Check Moonraker: sudo systemctl status moonraker"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Moongate has been uninstalled.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  cloudflared binary was left in place (may be used elsewhere)."
echo "  To remove it too:  sudo apt remove cloudflared"
echo ""
echo "  Don't forget to uninstall the Moongate app from your phone."
echo ""
