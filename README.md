# Tex Live Manager (TLMGR) Doco and Scripts

## Background

This repo provides documentation and tools to replace the core functionality of TeX Live Utility (TLU). The maintainer of that Mac OS software has stepped back from the project and I recently ran into issues when trying to update packages. In this repo you will find:

1. a cheet-sheet for the CLI `tlmgr` tool which is the TeX Live CLI utility which TLU is based on
2. a simple script which replaces the core functionality of TLU that I personally used
3. A Mac OS plist to run the update nightly
4. A script to install the plist into launchd so it runs nightly

## Script Commands

### Check for updates (safe, read-only)

```bash
./tlmgr-safe-update.sh
```

Tests the current mirror, falls back if needed, then runs `tlmgr update --list`. No `sudo`, nothing is installed — this just tells you what's outdated.

### Actually update

```bash
./tlmgr-safe-update.sh --update
```

Same mirror check, then runs:

```bash
sudo tlmgr update --self --all
```

`--self` and `--all` are combined deliberately rather than run as separate steps. `tlmgr`'s documented behavior is that when both are given together, it updates its own infrastructure first (`texlive.infra`, `texlive-scripts`, etc.) and, if that succeeds, automatically restarts itself to finish updating every other package. Running `--self` alone first and `--all` second by hand accomplishes the same thing, but the combined form is simpler and is the same sequence TLU runs internally when it detects a pending infrastructure update.

### Manually choose a mirror

```bash
./tlmgr-safe-update.sh --choose
```

Tests every mirror in the list (not just until the first success), prints a numbered table of the ones currently reachable, and lets you pick one to set as the new default — independent of whether the current one is working. No update is run; this only changes which mirror future calls
use.

## How the mirror test works

```bash
curl -fsS --max-time 8 --head "<mirror-url>/tlpkg/texlive.tlpdb.sha512"
```

A successful, non-empty response means the mirror is reachable and serving real TeX Live content. This is intentionally cheap — it doesn't attempt to parse or validate the database itself, just confirm the mirror answers for a file that should always be present alongside `texlive.tlpdb`.

### Mirror list

Since I reside in Israel the closest repos are in Germany (YMMV and you likely will have to edit this list). The list is defined at the top of the script (`REPOS=(...)`), in priority order:
1. GWDG
2. FAU
3. Erlangen
4. cicku.me (DE)
5. RRZE Erlangen
6. TU Chemnitz, then the
7. [CTAN multiplexor](https://mirrors.ctan.org/systems/texlive/tlnet) as a
last resort, since it auto-routes to *some* working mirror but with less
predictable latency than a pinned one. 

All were chosen for consistently fast connectivity from Israel and current "ok" status on
[CTAN mirmon](https://ctan.org/mirrors/mirmon) at time of writing; edit the array directly to add, remove, or reorder mirrors.

### State file

`~/.tlmgr_repo_current` holds the URL of the last confirmed-working mirror. It's plain text, one line, safe to inspect or edit by hand if needed:

```bash
cat ~/.tlmgr_repo_current
```

## Authorship and License

### Attribution

Nearly all the code and documentation in this repo were originally written by a Claude LLM under my design and architecture guidance. Subsequently, I edit and test everything.

The `plist` and `launchd` script were copied from another Claude generated repo and modified by me.

### License

This repo is under an MIT License. Do with it what you will.

### References used by Claude

- [TeX Live: Acquiring TeX Live](https://tug.org/texlive/acquire.html) — official guidance on repository/mirror configuration, including the required path suffix.
- [tlmgr manual](https://tug.org/texlive/doc/tlmgr.html) — full documentation of `tlmgr` options, including `update --self`/`--all` behavior.
- [CTAN mirmon](https://ctan.org/mirrors/mirmon) — live sync and reachability status for all registered CTAN mirrors.
- [TeX Live Utility (TLU) source and issues](https://github.com/amaxwell/tlutility) — the macOS GUI this script replaces for routine update checks.
