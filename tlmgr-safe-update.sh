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
#   ./tlmgr-safe-update.sh --choose   # test ALL known mirrors, show a numbered
#                                      # list of working ones, let you pick one
#                                      # to set as the default (no update run)
#
# `--self --all` together is tlmgr's own sanctioned combined form: it
# updates the infrastructure first and, if that succeeds, automatically
# restarts itself to finish updating everything else in one call. This is
# what TeX Live Utility does under the hood, so this script always uses
# the combined form rather than offering --all/--self as separate choices.
#
# `--choose` exists for the case where you've fallen back through several
# mirrors over time and want to deliberately move back "up" to a preferred
# one (e.g. GWDG) once it's healthy again, rather than only ever accepting
# whatever the automatic fallback found first.

set -uo pipefail

STATE_FILE="$HOME/.tlmgr_repo_current"
TIMEOUT=8

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
  # Fall back to whatever tlmgr itself has configured.
  tlmgr option repository 2>/dev/null | awk -F': ' '/repository/ {print $2}'
}

record_repo() {
  echo "$1" > "$STATE_FILE"
}

set_repo() {
  local url="$1"
  echo "Setting tlmgr default repository to: $url"
  sudo tlmgr option repository "$url"
  record_repo "$url"
}

choose_repo() {
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
    echo "None of the known mirrors responded — this is unusual."
    echo "This may indicate a broader network issue on your end, or a genuine"
    echo "problem with TeX Live's infrastructure. Bring this output to Claude"
    echo "for guidance before proceeding further."
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
  echo "Default repository set to: $selected"
}

# --- main --------------------------------------------------------------

mode="${1:-}"

if [[ "$mode" == "--choose" ]]; then
  choose_repo
  exit 0
fi

echo "== TeX Live repository check =="

current="$(get_current_repo)"
if [[ -z "$current" ]]; then
  echo "No repository currently recorded or configured; defaulting to first known mirror."
  current="${REPOS[0]}"
fi

echo "Current repository: $current"
printf "Testing connectivity... "

if test_repo "$current"; then
  echo "OK"
  record_repo "$current"
else
  echo "FAILED"
  echo
  echo "Repository unreachable: $current"
  echo "Testing known alternatives in order..."
  echo

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
    echo
    read -rp "Switch default repository to $found? [Y/n] " answer
    answer="${answer:-Y}"
    if [[ "$answer" =~ ^[Yy] ]]; then
      set_repo "$found"
      current="$found"
    else
      echo "Keeping current (unreachable) repository. The update below will likely fail."
    fi
  else
    echo
    echo "None of the known mirrors responded — this is unusual."
    echo "This may indicate a broader network issue on your end, or a genuine"
    echo "problem with TeX Live's infrastructure. Bring this output to Claude"
    echo "for guidance before proceeding further."
    exit 1
  fi
fi

# --- run the actual update --------------------------------------------

if [[ "$mode" == "--update" ]]; then
  echo
  echo "Running: sudo tlmgr update --self --all  (repository: $current)"
  echo
  sudo tlmgr update --self --all
else
  echo
  echo "Running: tlmgr update --list  (repository: $current)"
  echo "(dry run — pass --update to actually install, or --choose to switch mirrors)"
  echo
  tlmgr update --list
fi
