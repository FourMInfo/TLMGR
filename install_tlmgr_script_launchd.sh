#!/usr/bin/env bash
# install_tlmgr_script_launchd.sh
# Installs the TLMGR safe update as a launchd job running at 1am.
#
# Usage:
#   ./install_tlmgr_script_launchd.sh
#
# UPDATING AN ALREADY-INSTALLED JOB
#   Just run this script again. You do not delete anything by hand.
#
#   Editing the plist in this repo, or the installed copy, has NO effect on
#   its own: launchd holds the loaded job in memory, so a changed file sits
#   inert until the job is booted out and bootstrapped again. That is exactly
#   what re-running this script does, and it is safe to run repeatedly.
#
#   Re-run it on EVERY machine that runs the job — each has its own copy of
#   the plist under ~/Library/LaunchAgents.
#
# To uninstall:
#   launchctl bootout gui/$(id -u)/info.fourm.tlmgr-script
#   rm ~/Library/LaunchAgents/info.fourm.tlmgr-script.plist

set -euo pipefail

# --- configuration -------------------------------------------------------

# SCRIPT_DIR has to be derived here because it is what locates config.sh.
# config.sh may override it; if it doesn't, this script's own directory wins.
_self_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$_self_dir/config.sh" ]]; then
    echo "ERROR: config.sh not found at $_self_dir/config.sh"
    echo "  Copy config.sh.example to config.sh and fill in your values."
    exit 1
fi
# shellcheck source=/dev/null
source "$_self_dir/config.sh"
SCRIPT_DIR="${SCRIPT_DIR:-$_self_dir}"

# Same fallback rule as tlmgr-safe-update.sh: a missing key is expected on a
# hand-carried config.sh, and must announce itself rather than pick silently.
if [[ -z "${LOG_DIR:-}" ]]; then
    LOG_DIR="$HOME/Library/Logs/tlmgr"
    echo "NOTE: LOG_DIR not set in config.sh — using $LOG_DIR"
fi

LABEL="info.fourm.tlmgr-script"
DOMAIN="gui/$(id -u)"
PLIST_SRC="$SCRIPT_DIR/$LABEL.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
TLMGR_SCRIPT="$SCRIPT_DIR/tlmgr-safe-update.sh"

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

# Boot out any existing job. `bootout`/`bootstrap` are the modern replacement
# for `unload`/`load` — recent macOS versions are unreliable about the legacy
# pair, often failing with a generic I/O error when nothing is actually wrong.
# This also handles the transition cleanly for a job originally loaded with
# `launchctl load`: it is the same job in the same domain either way.
echo "  Booting out any existing job (harmless if none is loaded)..."
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

# Write the plist with the real script path substituted in. The template ships
# with a __TLMGR_SCRIPT__ placeholder rather than a hardcoded path: the old
# version substituted only the username, so /Code/FourM/TLMGR stayed baked in
# and a clone anywhere else installed cleanly and then ran nothing at 1am.
# Substitution uses bash's own ${var//pat/repl} rather than sed, so / and & in
# the path need no escaping.
#
# Build and validate in a temp file before moving it into place. Parameter
# expansion solves sed's delimiter problem but not XML's: a path containing
# & or < still yields a malformed plist. Writing straight to the destination
# would leave the machine with a broken plist AND no loaded job, since the
# old one has just been booted out. Validate first, install second.
plist_tmp="$(mktemp -t tlmgr-plist)"
plist_template="$(cat "$PLIST_SRC")"
printf '%s\n' "${plist_template//__TLMGR_SCRIPT__/$TLMGR_SCRIPT}" > "$plist_tmp"
if ! plutil -lint "$plist_tmp" > /dev/null 2>&1; then
    rm -f "$plist_tmp"
    echo "ERROR: the generated plist is not valid XML."
    echo "  Path substituted: $TLMGR_SCRIPT"
    echo "  A path containing & or < cannot be used as-is; move the repo"
    echo "  somewhere without those characters, or set SCRIPT_DIR in config.sh."
    echo "  Nothing was installed; the previous job was booted out and can be"
    echo "  restored by fixing the path and running this script again."
    exit 1
fi
mv "$plist_tmp" "$PLIST_DEST"
chmod 644 "$PLIST_DEST"
echo "  ✓ Plist installed to $PLIST_DEST"
echo "    Runs: $TLMGR_SCRIPT"

# Load the job. Once bootstrapped, launchd reloads it automatically at every
# subsequent login or reboot; this script only needs running again when the
# plist changes or you are setting up another machine.
launchctl bootstrap "$DOMAIN" "$PLIST_DEST"
echo "  ✓ launchd job loaded"

echo ""
echo "=========================================="
echo "  Done. TLMGR safe update will run nightly at 1am."
echo ""
echo "  Logs: $LOG_DIR/tlmgr_update_<timestamp>.log"
echo ""
echo "  To run manually right now:"
echo "    bash $TLMGR_SCRIPT"
echo ""
echo "  To check the job is loaded:"
echo "    launchctl print $DOMAIN/$LABEL"
echo "    launchctl list | grep tlmgr"
echo ""
echo "  To uninstall:"
echo "    launchctl bootout $DOMAIN/$LABEL"
echo "    rm $PLIST_DEST"
echo "=========================================="
