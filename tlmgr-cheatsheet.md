# tlmgr Command Reference

Quick reference for managing TeX Live packages entirely via CLI, bypassing TeX Live Utility (TLU).

## Everyday commands

```bash
# Search for a package (name, description, and file contents)
tlmgr search --global <keyword>

# Search only among already-installed packages
tlmgr search <keyword>

# Get details on a package before installing
tlmgr info <package-name>

# Install a package
sudo tlmgr install <package-name>

# Remove a package
sudo tlmgr remove <package-name>

# List packages with updates available (no changes made)
tlmgr update --list

# Update everything, infrastructure included, in one call.
# tlmgr updates itself first and, if that succeeds, automatically restarts
# to finish the rest — this is the same sequence TeX Live Utility runs
# under the hood, so there's no need to run --self and --all separately.
sudo tlmgr update --self --all
```

## Checking / changing the repository

```bash
# Show the currently configured repository
tlmgr option repository

# Set a new default repository (persists across runs)
sudo tlmgr option repository <URL>

# Use a repository for a single command only, without changing the default
tlmgr update --list --repository <URL>
```

## Quick repo test before updating

This checks that a mirror is reachable and serving a real TeX Live database,
without downloading the whole ~20MB `texlive.tlpdb`. It just HEAD-requests the
small `.sha512` checksum file that sits next to it.

```bash
curl -fsS --max-time 8 --head "<URL>/tlpkg/texlive.tlpdb.sha512"
```

- No output and exit code `0` → mirror is alive and serving TeX Live content.
- Non-zero exit code → mirror is down, blocked, or misconfigured; try another.

Example:

```bash
curl -fsS --max-time 8 --head "https://ftp.gwdg.de/pub/ctan/systems/texlive/tlnet/tlpkg/texlive.tlpdb.sha512" \
  && echo "OK" || echo "FAILED"
```

## Known-good mirrors (Germany-focused, fastest from Israel)

Always include the full `/systems/texlive/tlnet` (and any mirror-specific
prefix like `/pub/ctan/` or `/ctan/`) path — a bare hostname will fail.

| Mirror | Full repository URL |
|---|---|
| GWDG Göttingen | `https://ftp.gwdg.de/pub/ctan/systems/texlive/tlnet` |
| FAU Erlangen (ctan) | `https://ftp.fau.de/ctan/systems/texlive/tlnet` |
| RRZE Erlangen | `https://ftp.rrze.uni-erlangen.de/ctan/systems/texlive/tlnet` |
| cicku.me (DE node) | `https://de.mirrors.cicku.me/ctan/systems/texlive/tlnet` |
| TU Chemnitz | `https://ftp.tu-chemnitz.de/pub/tex/systems/texlive/tlnet` |
| CTAN multiplexor (auto-select, fallback) | `https://mirrors.ctan.org/systems/texlive/tlnet` (alias: `ctan`) |

The multiplexor (`ctan`) auto-picks a geographically nearby mirror each time,
so it's a reasonable last-resort fallback, but a pinned German mirror is
usually faster and more predictable for you specifically.

## Full mirror status

Live sync/reachability status for every CTAN mirror: https://ctan.org/mirrors/mirmon

## Companion script

`tlmgr-safe-update.sh` wraps the above into three modes:

- `./tlmgr-safe-update.sh` — dry run (`tlmgr update --list`), tests the
  current repo first and offers a tested fallback if it's down.
- `./tlmgr-safe-update.sh --update` — real update
  (`sudo tlmgr update --self --all`), same repo check first.
- `./tlmgr-safe-update.sh --choose` — tests *every* known mirror, shows a
  numbered list of the ones that respond, and lets you deliberately set
  any of them as the new default. Useful for moving back "up" to a
  preferred mirror (e.g. GWDG) after having fallen back to a lower-choice
  one, rather than only ever accepting the first automatic fallback found.

The active repository is tracked in `~/.tlmgr_repo_current`.
