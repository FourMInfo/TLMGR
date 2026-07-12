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

## Companion script

`tlmgr-safe-update.sh` wraps the above into three modes:

- `./tlmgr-safe-update.sh` — dry run (`tlmgr update --list`), tests the
  current repo first and offers a tested fallback if it's down.
- `./tlmgr-safe-update.sh --update` — real update
  (`sudo tlmgr update --self --all`), same repo check first.
- `./tlmgr-safe-update.sh --choose` — interactive only: tests *every*
  known mirror, shows a numbered list of the ones that respond, and lets
  you deliberately set any of them as the new default. Useful for moving
  back "up" to a preferred mirror (e.g. GWDG) after having fallen back to
  a lower-choice one.

The active repository is tracked in `~/.tlmgr_repo_current`.

### Logging and rotation

Every run writes a timestamped log to `~/Code/FourM/Logs/tlmgr_update_<timestamp>.log`
(directory created automatically if missing). Interactive runs still print
to the terminal as usual — the log is a mirror of that output, not a
replacement. After each run, logs older than the most recent 30 are
pruned automatically.

### Unattended (launchd/cron) runs

The script detects whether it has a controlling terminal (`[[ -t 0 ]]`)
and adjusts automatically — no separate flag needed:

- **No confirmation prompts.** If the current mirror is down, it switches
  to the first working fallback and logs the decision instead of asking.
- **`--choose` refuses to run** without a terminal, since it depends on
  interactive selection.
- **`sudo` runs as `sudo -n`.** If passwordless sudo isn't configured for
  `tlmgr`, the run fails immediately with an actionable log message
  instead of hanging on a password prompt no one is there to answer.

For unattended `--update` runs to work at all, passwordless sudo has to
be configured once, scoped to just the `tlmgr` binary:

```bash
sudo visudo -f /etc/sudoers.d/tlmgr-nopasswd
```

Add a line like:

```
yourusername ALL=(root) NOPASSWD: /Library/TeX/texbin/tlmgr
```

(Confirm the path with `command -v tlmgr` first — it matches your setup
if you've been using the CLI already.)

## Full mirror status

Live sync/reachability status for every CTAN mirror: https://ctan.org/mirrors/mirmon
