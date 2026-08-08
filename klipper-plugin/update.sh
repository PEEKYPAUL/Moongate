#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Moongate - post-update hook
#
# Called automatically by Moonraker's update manager after every git pull.
# Ensures the plugin symlink is in place and refreshes the QR pair page.
# Does NOT re-install cloudflared or the systemd service - those only run
# once during the initial install.sh.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[moongate]${NC} $*"; }
ok()   { echo -e "${GREEN}[moongate]${NC} $*"; }
warn() { echo -e "${YELLOW}[moongate]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOONGATE_DIR="$(dirname "$SCRIPT_DIR")"          # repo root  (~/moongate)
PLUGIN_SRC="$SCRIPT_DIR/moongate_standalone.py"

MOONRAKER_DIR="${MOONRAKER_DIR:-$HOME/moonraker}"
COMPONENTS_DIR="$MOONRAKER_DIR/moonraker/components"

# ── 1. Re-create symlink (in case it was removed) ────────────────────────────
if [[ -d "$COMPONENTS_DIR" ]]; then
    ln -sf "$PLUGIN_SRC" "$COMPONENTS_DIR/moongate.py"
    ok "Plugin symlink updated → $COMPONENTS_DIR/moongate.py"
else
    warn "Moonraker components dir not found at $COMPONENTS_DIR"
    warn "Set MOONRAKER_DIR= if Moonraker is installed elsewhere."
fi

# ── 2. Refresh QR pair page in common web-root locations ─────────────────────
HTML_SRC="$SCRIPT_DIR/moongate-pair.html"
DEPLOYED=0
for webroot in "$HOME/mainsail" "$HOME/printer_data/www" "$HOME/fluidd"; do
    if [[ -d "$webroot" ]]; then
        cp "$HTML_SRC" "$webroot/moongate-pair.html"
        ok "Pair page updated → $webroot/moongate-pair.html"
        DEPLOYED=1
    fi
done
[[ $DEPLOYED -eq 0 ]] && warn "No web-root found - pair page not deployed"

# ── 3. One-time migration: move authproxy logging off /run ───────────────────
# Units written before plugin 0.6.14 appended stdout/stderr to
# /run/moongate-authproxy.log with no rotation; at the app's poll rate that
# fills the /run tmpfs (~168 MB on a Pi) in a couple of weeks of uptime,
# which breaks sudo and anything else that writes to /run. New installs log
# to the journal; migrate old units here. Best effort only: this hook runs
# from Moonraker with no terminal, so it can only sudo when passwordless
# sudo is configured (the MainsailOS default) - otherwise print the manual
# commands. Moonraker restarts itself right after this hook and PartOf=
# propagates that restart to the authproxy, which picks up the new unit.
UNIT_FILE=/etc/systemd/system/moongate-authproxy.service
if grep -qs 'append:/run/moongate-authproxy\.log' "$UNIT_FILE"; then
    if sudo -n true 2>/dev/null; then
        sudo -n sed -i \
            -e 's|^StandardOutput=append:/run/moongate-authproxy\.log$|StandardOutput=journal|' \
            -e 's|^StandardError=append:/run/moongate-authproxy\.log$|StandardError=journal|' \
            "$UNIT_FILE"
        grep -q '^SyslogIdentifier=' "$UNIT_FILE" || sudo -n sed -i \
            '/^StandardError=journal$/a SyslogIdentifier=moongate-authproxy' "$UNIT_FILE"
        sudo -n rm -f /run/moongate-authproxy.log
        sudo -n systemctl daemon-reload
        ok "authproxy logging moved to the journal (journalctl -u moongate-authproxy)"
    else
        warn "authproxy still logs to /run/moongate-authproxy.log and will slowly fill /run."
        warn "Fix manually:"
        warn "  sudo sed -i 's|append:/run/moongate-authproxy.log|journal|' $UNIT_FILE"
        warn "  sudo rm -f /run/moongate-authproxy.log"
        warn "  sudo systemctl daemon-reload && sudo systemctl restart moongate-authproxy"
        warn "If /run is already full, a single power-cycle also clears it (/run is a"
        warn "RAM disk, emptied on every boot) - the updated proxy then stays quiet."
    fi
fi
# /run/moongate-tunnel.log intentionally stays a file: the plugin reads the
# cloudflared tunnel URL out of it, and cloudflared only writes a banner plus
# occasional reconnect lines (KBs over weeks, cleared on every boot).

# ── 4. Migration: let Moonraker manage the tunnel service (tunnel watchdog) ──
# The tunnel watchdog (plugin 0.6.23) heals a wedged cloudflared by asking
# Moonraker's machine API for a restart, which Moonraker only permits for
# units listed in moonraker.asvc. Tunnel-mode boxes get the entry here;
# LAN-only boxes have no tunnel unit and are skipped. No sudo needed (the
# file lives in printer_data), and Moonraker's own post-update restart makes
# it take effect immediately.
PRINTER_DATA="${PRINTER_DATA:-$HOME/printer_data}"
ASVC_FILE="$PRINTER_DATA/moonraker.asvc"
if [[ -f /etc/systemd/system/moongate-tunnel.service ]] \
   && ! grep -qxs 'moongate-tunnel' "$ASVC_FILE"; then
    echo 'moongate-tunnel' >> "$ASVC_FILE"
    ok "moongate-tunnel added to moonraker.asvc (tunnel watchdog active from this update)"
fi

ok "Update complete."
