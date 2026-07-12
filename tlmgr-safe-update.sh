#!/usr/bin/env bash
#
# tlmgr-safe-update.sh
#
# Tests the currently configured TeX Live repository before running an
# update. If it's unreachable, tests a list of known-good German/EU
# mirrors (in order) and offers to switch to the first one that responds,
# recording the choice in ~/.tlmgr_repo_current.
#
# Usage:
#   ./tlmgr-safe-update.sh            # dry run: `tlmgr update --list` (no sudo)
#   ./tlmgr-safe-update.sh --update   # real update: `sudo tlmgr update --self --all`
#   ./tlmgr-safe-update.sh --choose   # interactive only: test ALL known mirrors,
#                                      # show a numbered list of working ones,
#                                      # let you pick one to set as default
#
# Unattended (launchd/cron) use:
#   The script auto-detects whether it has a controlling terminal. With no
#   TTY (e.g. run from launchd), it:
#     - never uses `read -rp` — mirror fallback is chosen automatically
#       and logged, not confirmed interactively
#     - refuses --choose, since it requires interactive input
#     - runs sudo with `-n` (non-interactive): if passwordless sudo isn't
#       configured for tlmgr, it fails fast with a clear log message
#       instead of hanging forever waiting for a password no one will type
#
#   For unattended --update to work at all, passwordless sudo must be
#   configured once for the tlmgr binary:
#     sudo visudo -f /etc/sudoers.d/tlmgr-nopasswd
#   and add a line like:
#     yourusername ALL=(root) NOPASSWD: /Library/TeX/texbin/tlmgr
#
# `--self --all` together is tlmgr's own sanctioned combined form: it
# updates the infrastructure first and, if that succeeds, automatically
# restarts itself to finish updating everything else in one call. This is
# what TeX Live Utility does under the hood, so this script always uses
# the combined form rather than offering --all/--self as separate choices.

set -uo pipefail

# launchd (and cron) run jobs with a minimal PATH that often excludes
# /Library/TeX/texbin and Homebrew — unlike an interactive shell, which
# picks these up from .zshrc/.bash_profile. Set explicitly so tlmgr, curl,
# and sudo all resolve regardless of how this script is invoked. The
# companion plist also sets this via EnvironmentVariables; this is a
# second, redundant safeguard in case the script is ever run some other way.
export PATH="/Library/TeX/texbin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

STATE_FILE="$HOME/.tlmgr_repo_current"
TIMEOUT=8

# Where logs are written and how many to keep.
LOG_DIR="$HOME/Code/FourM/Logs"
LOG_KEEP=30

# Ordered candidate mirrors. First entry is tried first; the multiplexor
# alias is the last-resort fallback since it auto-routes but is less
# predictable in speed than a pinned German mirror.
REPOS=(
  "https://ftp.gwdg.de/pub/ctan/systems/texlive/tlnet"
  "https://ftp.fau.de/ctan/systems/texlive/tlnet"
  "https://de.mirrors.cicku.me/ctan/systems/texlive/tlnet"
  "https://ftp.rrze.uni-erlangen.de/ctan/systems/texlive/tlnet"
  "https://ftp.tu-chemnitz.de/pub/tex/systems/texlive/tlnet"
  "https://mirrors.ctan.org/systems/texlive/tlnet"
)

# --- interactivity detection -------------------------------------------

# No controlling terminal on stdin (launchd/cron) means no one can answer
# a prompt. Detect this once, up front, and change behavior accordingly.
if [[ -t 0 ]]; then
  AUTO_MODE=false
else
  AUTO_MODE=true
fi

# --- logging -------------------------------------------------------------

mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/tlmgr_update_${TIMESTAMP}.log"

# Mirror everything (stdout and stderr) to the log file. In an interactive
# session it still prints to the terminal as normal; under launchd, only
# the log file captures it, which is the point.
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

rotate_logs() {
  # ── Log rotation: keep last $LOG_KEEP logs ──────────────────────────
  local log_count
  log_count=$(ls -1 "$LOG_DIR"/tlmgr_update_*.log 2>/dev/null | wc -l | tr -d ' \n')
  if [[ "$log_count" -gt "$LOG_KEEP" ]]; then
    local to_delete=$(( log_count - LOG_KEEP ))
    ls -1 "$LOG_DIR"/tlmgr_update_*.log | sort | head -"$to_delete" | xargs rm -f
    log "Pruned $to_delete old log(s)"
  fi
}

# --- helpers ---------------------------------------------------------------

test_repo() {
  # Returns 0 (success) if the mirror answers with the small checksum file.
  local url="$1"
  curl -fsS --max-time "$TIMEOUT" --head "${url%/}/tlpkg/texlive.tlpdb.sha512" >/dev/null 2>&1
}

get_current_repo() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
    return
  fi
  tlmgr option repository 2>/dev/null | awk -F': ' '/repository/ {print $2}'
}

record_repo() {
  echo "$1" > "$STATE_FILE"
}

# Wraps sudo so unattended runs fail fast instead of hanging on a
# password prompt that will never be answered.
run_sudo() {
  if [[ "$AUTO_MODE" == true ]]; then
    if ! sudo -n "$@"; then
      log "ERROR: sudo requires a password and this is running unattended."
      log "Fix: sudo visudo -f /etc/sudoers.d/tlmgr-nopasswd"
      log "     and add: \$(whoami) ALL=(root) NOPASSWD: \$(command -v tlmgr)"
      exit 1
    fi
  else
    sudo "$@"
  fi
}

set_repo() {
  local url="$1"
  log "Setting tlmgr default repository to: $url"
  run_sudo tlmgr option repository "$url"
  record_repo "$url"
}

choose_repo() {
  if [[ "$AUTO_MODE" == true ]]; then
    log "ERROR: --choose requires an interactive terminal; refusing to run unattended."
    exit 1
  fi

  echo "== Testing all known mirrors =="
  echo

  local working_urls=()
  local i=1
  for repo in "${REPOS[@]}"; do
    printf "  [%d] %-70s " "$i" "$repo"
    if test_repo "$repo"; then
      echo "OK"
      working_urls+=("$repo")
    else
      echo "failed"
    fi
    ((i++))
  done

  echo

  if [[ ${#working_urls[@]} -eq 0 ]]; then
    log "None of the known mirrors responded — this is unusual."
    log "This may indicate a broader network issue on your end, or a genuine"
    log "problem with TeX Live's infrastructure. Bring this output to Claude"
    log "for guidance before proceeding further."
    exit 1
  fi

  echo "Working mirrors:"
  local idx
  for idx in "${!working_urls[@]}"; do
    printf "  %d) %s\n" "$((idx + 1))" "${working_urls[$idx]}"
  done
  echo

  local choice
  read -rp "Select a mirror to set as default [1-${#working_urls[@]}], or press Enter to cancel: " choice

  if [[ -z "$choice" ]]; then
    echo "No change made."
    exit 0
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#working_urls[@]} )); then
    echo "Invalid selection. No change made."
    exit 1
  fi

  local selected="${working_urls[$((choice - 1))]}"
  set_repo "$selected"
  log "Default repository set to: $selected"
}

# --- main --------------------------------------------------------------

mode="${1:-}"

log "== tlmgr-safe-update starting (mode: ${mode:-list}, auto: $AUTO_MODE) =="

if [[ "$mode" == "--choose" ]]; then
  choose_repo
  rotate_logs
  exit 0
fi

current="$(get_current_repo)"
if [[ -z "$current" ]]; then
  log "No repository currently recorded or configured; defaulting to first known mirror."
  current="${REPOS[0]}"
fi

log "Current repository: $current"
log "Testing connectivity..."

if test_repo "$current"; then
  log "OK: $current"
  record_repo "$current"
else
  log "FAILED: $current"
  log "Testing known alternatives in order..."

  found=""
  for repo in "${REPOS[@]}"; do
    [[ "$repo" == "$current" ]] && continue
    printf "  %-70s " "$repo"
    if test_repo "$repo"; then
      echo "OK"
      found="$repo"
      break
    else
      echo "failed"
    fi
  done

  if [[ -n "$found" ]]; then
    if [[ "$AUTO_MODE" == true ]]; then
      log "AUTO: switching default repository to $found (unattended run, no confirmation needed)"
      set_repo "$found"
      current="$found"
    else
      echo
      read -rp "Switch default repository to $found? [Y/n] " answer
      answer="${answer:-Y}"
      if [[ "$answer" =~ ^[Yy] ]]; then
        set_repo "$found"
        current="$found"
      else
        log "Keeping current (unreachable) repository. The update below will likely fail."
      fi
    fi
  else
    log "None of the known mirrors responded — this is unusual."
    log "This may indicate a broader network issue, or a genuine problem with"
    log "TeX Live's infrastructure. Bring this log to Claude for guidance."
    rotate_logs
    exit 1
  fi
fi

# --- run the actual update --------------------------------------------

if [[ "$mode" == "--update" ]]; then
  log "Running: sudo tlmgr update --self --all  (repository: $current)"
  run_sudo tlmgr update --self --all
else
  log "Running: tlmgr update --list  (repository: $current)"
  log "(dry run — pass --update to actually install, or --choose to switch mirrors)"
  tlmgr update --list
fi

log "== tlmgr-safe-update finished =="

rotate_logs
