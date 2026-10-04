# dropQbsd v0.3.0 — Release Notes

**Release date:** 2026-10-04

## Overview

v0.3.0 is the first release with **stable FreeBSD support**. The port
required a full audit of every component, with structural fixes across
the board. The system runs on OpenBSD (reference platform) and FreeBSD
(tested on real hardware) from a single codebase.

## Highlights

### FreeBSD port
- **Single codebase** for OpenBSD and FreeBSD. No forks, no per-OS
  patches.
- **`libexec/wrapper`** selects the shell at runtime (`/bin/ksh` on
  OpenBSD, `mksh` on FreeBSD) and is the environment-sanitization
  layer.
- **`gen_fwall`** emits `pf.conf` for both platforms (the only gap:
  `egress` on OpenBSD vs `route get default` on FreeBSD).
- **`syncthing_userdoc`**: two rc.d templates (`_openbsd`, `_freebsd`),
  installed under the same service name on both platforms.

### Security
- **`run_app`** now passes the conductor's UID (`INVOKE_UID`) as an
  argument instead of deriving it from `id -ru` — portable and robust.
- **`wrapper`** sanitizes the environment on all platforms (hardcoded
  PATH, `HOME`/`USER`/`LOGNAME` unset).
- **`enforce_drop`** corrects group ownership (not just permissions)
  and skips `.staging.*` directories created by `qcp`/`qmv`.

### Firewall
- **`grant_dns`** no longer uses `pfctl -f -` (which replaced the whole
  ruleset). It builds a temporary file with the DNS/HTTP rules
  **prepended** to `/etc/pf.conf`, so a `block ... quick` rule cannot
  shadow them.
- **No interface qualifier** in the temporary rules: the default
  route's interface may not match every flow (IPv6, aliases).
- **Syntax check** (`pfctl -nf`) before applying the temporary ruleset.
- **Tables are repopulated** after every `pfctl -f`: `persist` keeps
  the table *defined*, not its *entries*, so `<updates>`,
  `<mailserver>`, and `<services>` are refilled immediately (otherwise
  `usermail` and `userweb` would stay offline until their next cron
  cycle).
- **`pkg upgrade -y`** on FreeBSD (avoids the interactive prompt).
- **`freebsd-update --not-tty`** (no tty inside command substitution).
- **`IFACE="egress"`** on OpenBSD (was empty).
- **Concurrency check**: the update scripts refuse to start if another
  patch/package operation is already running (checked *before* opening
  the network window).

### Interface
- **`indicator_de`**: recognizes `user` and `root` in `find_owner`;
  `xterm_*` set `-T "<domain>"` so the window title is explicit.
- **`site_menu`**: rebuilds `HOME` from `/etc/passwd`; uses
  `~/.cache/dropQbsd/` instead of `/tmp`.
- **`control_panel`**: guard for `COLS < 8`; removed dead `rm -f`.

### Drop zone
- **`qcp`/`qmv`/`qimport`**: refuse to overwrite an existing entry;
  verify both files and directories; do not modify the source
  permissions.
- **`nnn` plugins** (`nnnqcp`, `nnnqmv`, `nnnqimport`): loop over all
  selected files; errors logged to `~/.cache/dropQbsd/nnn_plugins.log`.
- **Xfe scripts** (`xfqcp`, `xfqmv`, `xfqimport`): same structure as
  the nnn plugins.

### System updates

- **`Upgrade RELEASE`** now handles the multi-phase nature of FreeBSD
  release upgrades explicitly:
  - **OpenBSD**: `sysupgrade` (auto-reboot).
  - **FreeBSD (traditional base)**: `freebsd-update upgrade -r RELEASE`
    is phase 1 of 3. The script prints the post-reboot steps
    (`freebsd-update install`, then `pkg upgrade -y`) and leaves a
    marker so the login notice reminds the operator.
  - **FreeBSD (PkgBase)**: `pkg upgrade -y -r RELEASE` prepares the
    upgrade; after reboot, `pkg upgrade -y` syncs the rest.
- **Pending-reboot marker**: `/var/log/dropQbsd/upgrade_pending` is
  written when an upgrade is prepared but not finished. The login
  notice (from `/etc/dropQbsd/profile`) reads it and reminds whoever
  logs in next. The marker is removed manually after the post-reboot
  steps.
- **`RELEASE` is now mandatory** on FreeBSD: `Upgrade` without an
  argument exits with a usage message.
- **Concurrency check**: all four update scripts refuse to start if
  another instance of the same tool is already running.
- **`upgrade_tru_fwall`**: the upgrade command is no longer run inside
  `$()`. `freebsd-update upgrade` asks release decisions a human must
  make, and `sysupgrade` inherits the tty — capturing the output broke
  both.

### Documentation
- README and INSTALL aligned with the code.
- Session-stub table per platform (`.xsession` **only** on OpenBSD,
  `.xinitrc` **only** on FreeBSD).
- New "Site Menu" chapter in the README.
- Note on `file_bridge`'s global F1–F5 bindings.

## Fixes

- **`.xsession` on FreeBSD**: caused SDDM to freeze. Must not be
  installed on FreeBSD (see INSTALL §6.3).
- **`tmpfs` on FreeBSD**: `nodev` is not supported; removed from the
  FreeBSD branch of `mount_tmpfs`.
- **`ensure_updates_table`**: awk bug in the FreeBSD branch
  (`updates\/` → `updates\]`).
- **`update_mailserver_table`**: `exit 1` on an empty section caused
  a mail to root every 15 minutes. Now `exit 0`.
- **`update_services_table`**: shebang removed (convention for
  `sbin/`/`libexec/`).
- **`verify_integrity`**: `| log` did not pass arguments; now
  `OUT=$(...)` + `log "$OUT"`.
- **`log()` skips empty messages**: tools like `pkg_delete -a` emit a
  bare newline when there is nothing to do, which produced
  timestamp-only log lines.
- **`cleanup()` is idempotent**: a `CLEANED` guard prevents double
  execution on signal + exit.

## Upgrade notes

If you are upgrading from a v0.3.0 pre-release:

1. **Regenerate the `verify_integrity` signature** (scripts changed):
   ```sh
   cd /opt/dropQbsd
   sha256 $(cat /etc/dropQbsd/filelist) | \
       signify -S -e -s /root/dropQbsd.sec -m - \
           -x keys/dropQbsd_scripts.sha256.sig
   ```
2. **Regenerate the firewall** (`Gen openbsd` / `Gen freebsd`).
3. **On FreeBSD**: remove `~/.xsession` if installed.
4. **On FreeBSD**: add `pkgmir.geo.freebsd.org` to `[updates] hosts`
   in `local.conf`.

## Known limitations

- **X11 input isolation**: not solved (X11 limitation). The
  desktop/server pairing (roadmap) will address it.
- **Kernel exploits**: all domains share one kernel.
- **NetBSD**: not supported (`npf` does not filter by user).
- **`file_bridge` F1–F5**: bindings are global to the tmux server.

## Testing

Tested on real hardware: OpenBSD laptop, OpenBSD desktop, FreeBSD
desktop.
