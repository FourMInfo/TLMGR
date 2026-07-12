#!/usr/bin/env bash
# install_tlmgr_script_launchd.sh
# Installs the TLMGR safe update as a launchd job running at 1am
#
# Usage:
#   ./install_tlmgr_script_launchd.sh
#
# To uninstall:
#   launchctl unload ~/Library/LaunchAgents/info.fourm.tlmgr-script.plist
#   rm ~/Library/LaunchAgents/info.fourm.tlmgr-script.plist

set -euo pipefail

SCRIPTS_DIR="$HOME/Code/FourM/TLMGR"
PLIST_SRC="$SCRIPTS_DIR/info.fourm.tlmgr-script.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/info.fourm.tlmgr-script.plist"
TLMGR_SCRIPT="$SCRIPTS_DIR/tlmgr-safe-update.sh"
LOG_DIR="$HOME/Code/FourM/Logs"

echo "=========================================="
echo "  Install TLMGR Safe Update launchd Job"
echo "=========================================="
echo ""

# Checks
if [[ ! -f "$TLMGR_SCRIPT" ]]; then
    echo "ERROR: TLMGR script not found at $TLMGR_SCRIPT"
    exit 1
fi

if [[ ! -f "$PLIST_SRC" ]]; then
    echo "ERROR: Plist not found at $PLIST_SRC"
    exit 1
fi

mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

# Unload existing job if present
if launchctl list | grep -q "info.fourm.tlmgr-script" 2>/dev/null; then
    echo "  Unloading existing launchd job..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Copy plist to LaunchAgents and substitute YOUR_USERNAME with actual username
sed "s/YOUR_USERNAME/$USER/g" "$PLIST_SRC" > "$PLIST_DEST"
echo "  ✓ Plist installed to $PLIST_DEST"

# Load the job
launchctl load "$PLIST_DEST"
echo "  ✓ launchd job loaded"

echo ""
echo "=========================================="
echo "  Done. TLMGR safe update will run nightly at 1am."
echo ""
echo "  To run manually right now:"
echo "    bash $TLMGR_SCRIPT"
echo ""
echo "  To check job is loaded:"
echo "    launchctl list | grep tlmgr"
echo ""
echo "  To uninstall:"
echo "    launchctl unload $PLIST_DEST"
echo "    rm $PLIST_DEST"
echo "=========================================="
