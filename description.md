# tlmgr-safe-update

A small wrapper around `tlmgr` that tests a TeX Live mirror before using it,
falls back to a tested alternative if the configured one is down, and lets
you deliberately switch mirrors on demand.

## Motivation

This started with TeX Live Utility (TLU), the macOS GUI for `tlmgr`, failing
repeatedly with:

```
tlmgr: TLPDB::from_file could not get texlive.tlpdb from: <mirror>/tlpkg/texlive-catalogue-only.tlpdb
Maybe the repository setting should be changed.
```

Two separate problems were tangled together in that error, worth separating
out because they have different fixes:

1. **A malformed repository URL.** A specific mirror hostname without its
   required path suffix (e.g. `https://gwdg.de` instead of
   `https://ftp.gwdg.de/pub/ctan/systems/texlive/tlnet`) will always fail,
   regardless of whether the mirror itself is healthy. `tlmgr`'s own
   documentation on repository selection is explicit that the full CTAN
   path has to be included — see [TeX Live: Acquiring TeX
   Live](https://tug.org/texlive/acquire.html) and the `tlmgr` section of
   the [TeX Live manual](https://tug.org/texlive/doc/tlmgr.html).

2. **A TLU-specific bug**, unrelated to mirror health, where TLU requests
   `texlive-catalogue-only.tlpdb` — a file that isn't part of the standard
   CTAN `tlnet` mirror layout (confirmed by checking multiple current
   mirrors' `tlpkg/` directory listings, which only contain
   `texlive.tlpdb` and its checksum/signature files). This surfaced after
   an infrastructure update and reproduces across every mirror tried, which
   is what pointed to it being a client-side issue rather than a mirror
   sync problem. TLU is maintained by Adam Maxwell; its source and issue
   tracker are at [github.com/amaxwell/tlutility](https://github.com/amaxwell/tlutility).

Working around problem 2 meant moving to the CLI full-time. Problem 1 is
easy to avoid once you know it, but it raised a real question: **how do you
know a mirror is actually up before you commit to a slow, multi-minute
update against it?** Especially relevant here since the fastest, most
reliable mirrors (German ones, in this case) aren't necessarily the ones
`tlmgr`'s automatic mirror selection picks, and manually chosen mirrors can
occasionally be out of sync — CTAN's own mirror documentation
acknowledges this: mirrors "are not perfectly synchronized" (see
[CTAN mirmon](https://ctan.org/mirrors/mirmon), which tracks live
sync/reachability status for every registered mirror).

This script exists to make mirror selection a quick, tested, explicit step
rather than something you find out went wrong ten minutes into an update.

## What it does

- Tests whichever mirror is currently configured with a lightweight
  request (a `HEAD` request for the small `.sha512` checksum file, not the
  full ~20MB database) before running anything.
- If that mirror fails, tests a hardcoded list of known-good mirrors in
  order and offers to switch to the first one that responds.
- Records the active mirror in `~/.tlmgr_repo_current`, so the next run
  knows what was last confirmed working without re-deriving it from
  `tlmgr` each time.
- Gives you a manual override to test *all* known mirrors at once and pick
  one explicitly — useful for moving back to a preferred mirror after
  having fallen back to a lower-priority one.

