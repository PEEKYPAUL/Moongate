#!/usr/bin/env bash
# Moongate plugin installer for Moonraker on Raspberry Pi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOONRAKER_HOME="${MOONRAKER_HOME:-$HOME/moonraker}"
EXTRAS_DIR="$MOONRAKER_HOME/moonraker/components"
PRINTER_DATA="${PRINTER_DATA:-$HOME/printer_data}"
MOONRAKER_CONF="$PRINTER_DATA/config/moonraker.conf"
PRINTER_CFG="$PRINTER_DATA/config/printer.cfg"

echo "==> Moongate plugin installer"
echo "    Moonraker home : $MOONRAKER_HOME"
echo "    Extras dir     : $EXTRAS_DIR"
echo "    moonraker.conf : $MOONRAKER_CONF"

# ---- 1. Copy plugin ----
if [ ! -d "$EXTRAS_DIR" ]; then
    echo "ERROR: Moonraker components dir not found at $EXTRAS_DIR"
    echo "       Set MOONRAKER_HOME if Moonraker is installed elsewhere."
    exit 1
fi

echo "==> Copying plugin to $EXTRAS_DIR/moongate/"
cp -r "$SCRIPT_DIR/moongate" "$EXTRAS_DIR/"
echo "    Done."

# ---- 2. moonraker.conf ----
if [ -f "$MOONRAKER_CONF" ]; then
    if grep -q "\[moongate\]" "$MOONRAKER_CONF"; then
        echo "==> [moongate] section already present in moonraker.conf — skipping."
    else
        echo "==> Adding [moongate] to moonraker.conf"
        cat >> "$MOONRAKER_CONF" <<'EOF'

[moongate]
# Moongate secure pairing plugin
# See https://github.com/PEEKYPAUL/moongate for configuration options
EOF
        echo "    Done."
    fi
else
    echo "WARN: moonraker.conf not found at $MOONRAKER_CONF"
    echo "      Add '[moongate]' manually to your moonraker.conf."
fi

# ---- 3. MOONGATE_PAIR macro ----
if [ -f "$PRINTER_CFG" ]; then
    if grep -q "MOONGATE_PAIR" "$PRINTER_CFG"; then
        echo "==> MOONGATE_PAIR macro already in printer.cfg — skipping."
    else
        echo "==> Adding MOONGATE_PAIR macro to printer.cfg"
        cat >> "$PRINTER_CFG" <<'EOF'

[gcode_macro MOONGATE_PAIR]
description: Generate a Moongate pairing code
gcode:
    {action_call_remote_method("moongate_generate_pair_code")}
EOF
        echo "    Done."
    fi
else
    echo "WARN: printer.cfg not found at $PRINTER_CFG"
    echo "      Add the MOONGATE_PAIR macro manually — see docs/setup-guide.md."
fi

# ---- 4. Restart Moonraker ----
echo "==> Restarting Moonraker..."
if systemctl is-active --quiet moonraker; then
    sudo systemctl restart moonraker
    echo "    Moonraker restarted."
else
    echo "    Moonraker service not found — restart it manually."
fi

echo ""
echo "==> Moongate plugin installed successfully."
echo "    Run MOONGATE_PAIR in your Klipper console to generate a pairing code."
