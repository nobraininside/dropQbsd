# dropQbsd v0.1.0 — Release Notes

**Release date:** 2026-07-03

First public release.

## What's included

- Four domains: `user`, `userweb`, `usermail`, `userdoc`
- PF-based network isolation per domain
- Drop zone (`/home/drop`) with automated enforcement (cron every
  60s)
- 4-quadrant tmux file bridge (`nnn` per domain + control panel)
- Disposable browser sessions (tmpfs-backed)
- Site menu with `pass` password manager integration
- Archival pipeline (email + websites → `userdoc`)
- Quarantine system for policy violations

## Requirements

- OpenBSD 7.5+
- 1 GB RAM minimum (~300 MB base + ~500 MB tmpfs per disposable
  browser)
- Verified on 4 GB hardware; 2 GB recommended for comfortable daily
  use

## Installation

Manual for now. Clone the repo, copy scripts to `/opt/dropQbsd/`,
create users, load `pf.conf`, add cron jobs. See README for full
instructions.
