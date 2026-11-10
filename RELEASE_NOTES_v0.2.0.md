# dropQbsd v0.2.0 — Release Notes

**Release date:** 2026-08-17

This release replaces the hand-written `pf.conf` with a declarative
firewall policy, and lays the groundwork for BSD portability.

## Highlights

### Declarative firewall policy
- `gen_firewall` — generates `pf.conf` from a policy instead of
  editing firewall rules by hand.
- `domains.conf` — the portable policy (identical on every install).
- `local.conf` — your local config (subnet, mail, services) — the
  single source of truth.
- `schema` — the valid domains for this product.
- Policy describes intent; the backend handles syntax.

### BSD family positioning
- Born on OpenBSD, now targeting the BSD family.
- FreeBSD support in testing (both use `pf`).
- NetBSD on the roadmap (requires adapting isolation to `npf`).

### Configuration reorganized
- `/etc/dropQbsd/` — new config directory (policy + local config +
  schema).
- `templates/` — files to copy as-is (no editing needed).
- `examples/` — files to copy and personalize.
- `/etc/tables/` removed — table configs now live in `local.conf`.

### Policy model
- Default deny, allowlist approach.
- `deny` always beats `allow` (order-independent).
- `deny = internet` filters allows (leaves only specific targets).
- `deny = any` annihilates all allows.
- `allow_in` emits inbound rules (for services like Syncthing).
- `[extra.*]` sections in `local.conf` for personal exceptions —
  without weakening the base posture.

## What's included

- Four domains: `user`, `userweb`, `usermail`, `userdoc`
- Declarative firewall policy (`gen_firewall`, `domains.conf` +
  `local.conf`)
- PF-based network isolation per domain
- Drop zone (`/home/drop`) with automated enforcement (cron every
  60s)
- 4-quadrant tmux file bridge (`nnn` per domain + control panel)
- Disposable browser sessions (tmpfs-backed)
- Site menu with `pass` password manager integration
- Archival pipeline (email + websites → `userdoc`)
- Quarantine system for policy violations
- Integrity verification (extended to policy files)

## Requirements

- OpenBSD 7.5+ (FreeBSD in testing)
- 1 GB RAM minimum (~300 MB base + ~500 MB tmpfs per disposable
  browser)
- Verified on 4 GB hardware; 2 GB recommended for comfortable daily
  use

## Installation

Manual for now. Clone the repo, copy scripts to `/opt/dropQbsd/`,
create users, create `/etc/dropQbsd/`, fill in `local.conf`, run
`gen_firewall`, add cron jobs. See INSTALL.md for full
instructions.
