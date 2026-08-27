# Tex Live Manager (TLMGR) Doco and Scripts

## Background

This repo provides documentation and tools to replace the core functionality of TeX Live Utility (TLU). The maintainer of that macOS app has stepped back from the project, and repeated update failures traced back to a TLU-specific bug rather than a mirror problem — see the motivation write-up on study.fourm.info for the full story. In this repo you will find:

1. A cheat-sheet for the CLI `tlmgr` tool, which is the TeX Live CLI utility TLU is built on.
2. A script that replaces the core update functionality of TLU.
3. A macOS `plist` to run the update nightly via `launchd`.
4. A script to install that plist so it runs automatically.

## Setup: `config.sh`

Every script reads its paths from `config.sh`, which is **not** committed — this
is a public repo and those are local paths. Copy the template and edit it once
per machine:

```bash
cp config.sh.example config.sh
$EDITOR config.sh
```

`config.sh.example` documents each key. In short: `LOG_DIR` and `KEEP_LOGS`
control where run logs go and how many are kept, `STATE_FILE` is where the
selected mirror is recorded, and `SCRIPT_DIR` is normally left commented out
because each script derives its own location.

**A missing `config.sh` is a hard error** — the scripts refuse to run without
it, because the file is the contract. A missing individual *key* is not: it
falls back to a documented default and says so, since `config.sh` is carried
between machines by hand and an older copy can predate a new key.

One definition per path is one place to change it, and one place for it to be
wrong.

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

Interactive only. Tests every mirror in the list (not just until the first success), prints a numbered table of the ones currently reachable, and lets you pick one to set as the new default — independent of whether the current one is working. No update is run; this only changes which mirror future calls use.

## How the mirror test works

```bash
curl -fsS --max-time 8 --head "<mirror-url>/tlpkg/texlive.tlpdb.sha512"
```

A successful, non-empty response means the mirror is reachable and serving real TeX Live content. This is intentionally cheap — it doesn't attempt to parse or validate the database itself, just confirms the mirror answers for a file that should always be present alongside `texlive.tlpdb`.

### Mirror list

Since I reside in Israel, the closest reliable mirrors are in Germany — your mileage will vary, and you'll likely want to edit this list for your own location. Defined at the top of the script (`REPOS=(...)`), in priority order:

1. GWDG
2. FAU Erlangen
3. cicku.me (DE)
4. RRZE Erlangen
5. TU Chemnitz
6. [CTAN multiplexor](https://mirrors.ctan.org/systems/texlive/tlnet) — last resort; auto-routes to *some* working mirror, but with less predictable latency than a pinned one.

All were chosen for consistently fast connectivity from Israel and current "ok" status on [CTAN mirmon](https://ctan.org/mirrors/mirmon) at time of writing.

### State file

`~/.tlmgr_repo_current` holds the URL of the last confirmed-working mirror. It's plain text, one line, safe to inspect or edit by hand if needed:

```bash
cat ~/.tlmgr_repo_current
```

## Logging and rotation

Every run writes a timestamped log to `$LOG_DIR/tlmgr_update_<timestamp>.log`, where `LOG_DIR` comes from `config.sh` (the directory is created automatically if missing; if the key is absent the script falls back to `~/Library/Logs/tlmgr` and says so). Interactive runs still print to the terminal as usual — the log is a mirror of that output, not a replacement. After each run, logs older than the most recent `$KEEP_LOGS` are pruned automatically.

## Running unattended via launchd

The script detects whether it has a controlling terminal (`[[ -t 0 ]]`) and adjusts automatically — no separate flag needed:

- **No confirmation prompts.** If the current mirror is down, it switches to the first working fallback and logs the decision instead of asking.
- **`--choose` refuses to run** without a terminal, since it depends on interactive selection.
- **`sudo` runs as `sudo -n`.** If passwordless sudo isn't configured for `tlmgr`, the run fails immediately with an actionable log message instead of hanging on a password prompt no one is there to answer.

### One-time setup: passwordless sudo for tlmgr only

For unattended `--update` runs to work, `sudo` needs to skip the password prompt — but only for this one binary, not blanket root access:

```bash
sudo visudo -f /etc/sudoers.d/tlmgr-nopasswd
```

Add a line like:

```
yourusername ALL=(root) NOPASSWD: /Library/TeX/texbin/tlmgr
```

Confirm the path first with `command -v tlmgr`. The `launchd` job installed by this repo runs as a **LaunchAgent** (`~/Library/LaunchAgents`), which runs as your own user — so this rule, scoped to your username, covers it. (A LaunchDaemon under `/Library/LaunchDaemons` would instead run as root by default, which is a different situation — not what this repo sets up.)

### Installing, and updating an installed job

```bash
./install_tlmgr_script_launchd.sh
```

The plist in this repo ships with a `__TLMGR_SCRIPT__` placeholder rather than a
real path; the installer substitutes the actual location of this checkout. That
is deliberate — an earlier version substituted only the username, leaving
`Code/FourM/TLMGR` baked in, so a clone kept anywhere else would install
cleanly and then run nothing at 1am.

**To update an already-installed job, just run the installer again.** You never
delete anything by hand. Editing the plist — here or the installed copy under
`~/Library/LaunchAgents` — has no effect on its own, because `launchd` holds the
loaded job in memory; a changed file sits inert until the job is booted out and
bootstrapped again, which is what re-running the installer does. It is safe to
run repeatedly, and it must be run on **each machine** that runs the job, since
every machine has its own installed copy.

The installer uses `launchctl bootout` / `bootstrap` rather than the legacy
`unload` / `load` pair, which recent macOS versions handle unreliably — often
failing with a generic I/O error when nothing is wrong. A job originally loaded
with `launchctl load` is booted out by the modern command without special
handling; it is the same job in the same domain either way.

### Why the plist sets `PATH` explicitly

`launchd` jobs run with a minimal default `PATH` that typically excludes `/Library/TeX/texbin` and Homebrew, unlike an interactive shell that picks these up from `.zshrc`/`.bash_profile`. Without it, `tlmgr` (or `curl`) may simply fail to resolve — silently, if `StandardOutPath`/`StandardErrorPath` are pointed at `/dev/null` as they are here (safe to leave that way, since the script does its own logging independently via the mechanism above). The plist sets `PATH` via its `EnvironmentVariables` key; the script also sets it defensively at the top, in case it's ever invoked by something other than this plist.

## Authorship and License

### Attribution

Nearly all the code and documentation in this repo were originally written by a Claude LLM under my design and architecture guidance. Subsequently, I edit and test everything.

The `plist` and `launchd` install script were adapted from another Claude-generated repo and modified by me.

### License

This repo is under an MIT License. Do with it what you will.

### References used by Claude

- [TeX Live: Acquiring TeX Live](https://tug.org/texlive/acquire.html) — official guidance on repository/mirror configuration, including the required path suffix.
- [tlmgr manual](https://tug.org/texlive/doc/tlmgr.html) — full documentation of `tlmgr` options, including `update --self`/`--all` behavior.
- [CTAN mirmon](https://ctan.org/mirrors/mirmon) — live sync and reachability status for all registered CTAN mirrors.
- [TeX Live Utility (TLU) source and issues](https://github.com/amaxwell/tlutility) — the macOS GUI this script replaces for routine update checks.
- [sudoers(5) manual](https://www.sudo.ws/docs/man/sudoers.man/) — syntax for `NOPASSWD` rules and drop-in files under `/etc/sudoers.d/`.
- [launchd.plist(5) manual](https://ss64.com/mac/launchd.plist.html) — `EnvironmentVariables`, `StartCalendarInterval`, and other plist keys used here.
