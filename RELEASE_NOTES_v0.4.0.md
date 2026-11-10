# dropQbsd v0.4.0 -- Release Notes

**Release date:** 2026-11-09

## Overview

v0.4.0 is the first release that can be installed and updated without
following a manual. It is also the first where the conductor account is
identified by something other than its name.

Three things define it:

1. **Semi-automatic install and update** -- `install.sh` and `update.sh`
   replace the manual procedure as the recommended path.
2. **GECOS role markers** -- a domain account is recognised by a marker in
   its GECOS field, not by its name. The conductor can be called anything.
3. **`qattach`** -- a GUI flow for moving a file from one domain into
   another domain's `~/Downloads`.

Alongside them: `qinspect` and `qprompt`, the documentation split into a
quick-start and a full manual, and a colour convention that is now
uniform across terminals, `mc`, `xfe`, the `qmenu` headers and the OSD
indicator.

OpenBSD remains the reference platform; FreeBSD remains fully supported.

## Highlights

### Installer and updater

- **`install.sh`** -- idempotent, non-destructive semi-automatic
  installer. Creates the `drop` group and the four domain users, the
  directory tree, the configuration, the firewall, the cron jobs and the
  desktop integration. It does **not** set passwords, and it does **not**
  overwrite `local.conf`: on a re-run the file is seeded once and left
  alone. Supports `--dry-run`, `--skip-backup`, `--help`.
- **`update.sh`** -- updater for an existing installation. Preserves
  `local.conf`, the single operator-owned file, and never writes it.
  Replaces only project-owned files whose content actually changed (a
  byte comparison, not a timestamp), backs up every file it overwrites
  into one versioned directory, and never deletes or renames anything:
  files no longer in the repository are reported for the operator to
  review. Supports `--dry-run`, `--from <version>`, `--help`.
- Both run from the repository's `installer/` directory and are
  source-tree only: neither is copied to `/opt/dropQbsd/`.
- Neither installs packages. The installer has no network policy yet, and
  silently installing packages during a security install would be the
  wrong first act.

### GECOS role markers -- the conductor is rename-proof

- Every domain account carries a role marker in the fifth field of
  `/etc/passwd`: `dropQbsd_conductor`, `dropQbsd_userdoc`,
  `dropQbsd_usermail`, `dropQbsd_userweb`.
- The conductor is resolved **from its marker, not its name**. The
  installer, the updater, the enforcers and every runtime script resolve
  the same account the same way, so `CONDUCTOR_USER` may be `conductor`,
  `user`, or anything else.
- A pre-existing account without the marker is **refused, never merged**.
  A personal login that happens to be called `conductor` cannot silently
  acquire drop-zone and domain access; the installer stops and says what
  to do.
- Markers can be added to an existing installation without touching UID,
  home, groups or data (`usermod -c`). This is the one upgrade step a
  0.3.0 system must perform by hand -- see *Upgrade notes*.

### `qattach` -- GUI file attach

- A **new conductor action**: moves a file from a source domain into a
  destination domain's `~/Downloads`, for the blocking case -- attaching a
  file to a mail, or filling an upload form.
- **Three popups**: pick a file (the picker runs as the source domain,
  confined to its home, so other domains' 700 homes are invisible to it),
  pick the destination, then confirm the file landing in `~/Downloads`.
- **Direction matrix** in `/etc/dropQbsd/attach.conf`, one `SRC:DST` per
  line. The default is deliberately minimal: from the trusted source
  (`userdoc`) toward the exposed domains. The reverse direction carries
  untrusted data into the trusted archive and is handled with
  `qcp` + `qimport`, not with a shortcut.
- **Conductor action** declared in `/etc/dropQbsd/conductor.conf` and
  executed through the blind gate (`run_app`). Both files are
  project-owned: they are the security posture, not personal preference,
  and an update restores the shipped version.
- **Requires `Xdialog`** (`Xdialog` on OpenBSD, `xdialog` on FreeBSD);
  `qattach` resolves the binary name at runtime.

### New tools: `qinspect` and `qprompt`

- **`qinspect`** shows what a file in the drop zone *is*, without
  importing it: metadata, type, hash, a truncated text preview or an
  archive listing, and a plain-language verdict (LOW / MEDIUM / HIGH).
  It never executes, extracts or opens the file in an application that
  could run code. Exit code 0/1/2 makes the verdict scriptable.
  Anti-masking is the point: a filename that says `.pdf` over an ELF
  binary raises HIGH, and so does a double extension.
- **`qprompt`** drives any dropQbsd command from a prompt loop in the
  current terminal, which is what makes a non-interactive tool like
  `qinspect` usable from a desktop launcher. It wraps the target through
  the sanitized environment and falls back to plain system commands.

### Documentation restructure

- **New `INSTALL_MANUAL.md`** -- the full step-by-step procedure:
  users, resource limits, directory tree, `run_app` build,
  configuration, firewall, cron, verification, desktop integration.
- **`INSTALL.md` is now the quick start** -- the installer path, the
  manual steps after it, post-install checks and the updater.
- **Disposable sessions** documented (10.3): `Run --disposable <size>`,
  500 MB default, downloads bridged to the real `~/Downloads`.
- **Xfe per-domain colour seeds** documented (10.1 bulk block, 10.6
  manual): installation seeds, install only if absent, never overwritten.

### Colour convention

- **The conductor is black**, standardised across every surface: mc skin,
  GTK picker theme, Xfe seed and terminal.
- **New conductor GTK2 theme**: `examples/apps/gtk/gtkrc.conductor`.
- **New Xfe seeds for the conductor**: `examples/apps/xfe/xferc.conductor`
  and `xfwrc.conductor` -- fixed names, because the conductor's role does
  not follow its account name.
- **Uniform list background** in the Xfe templates: `highlightcolor` and
  `listbackcolor` set to the same value (black for the conductor), which
  removes the zebra striping that made the per-domain colour ambiguous.

### Naming and policy clarification

- **`q*` prefix standardised** across scripts and documentation, so the
  three documents now name the real files: `qcontrol`, `qfile`, `qsite`,
  `qattach`, `qinspect`, `qprompt`, `xterm_*`. Aliases whose names
  changed are listed under *Upgrade notes*.
- **`<updates>` table lifecycle made explicit**: populated every 15
  minutes by `ensure_updates_table` and again on entry of each update
  script, then **flushed on exit** (`FLUSH_ON_EXIT=1`), so the mirror IPs
  are reachable only while an update is running. `<mailserver>` and
  `<services>` stay populated for daily use.
- **Drop zone risk model documented**: `2770 root:drop` lets any member
  of `drop` remove or replace a file in transit. That is accepted by
  design -- the members of `drop` are the same operator in different
  compartments -- and mitigated by `qcp` copying rather than moving,
  by transit permissions of 440, and by inspection before import. A
  stricter model (staging directories 570, exports written by root) is
  on the roadmap.

## Fixes

Problems present in 0.3.0 and corrected here.

- **`indicator_de` OSD.** `-p 1.5` (a float) made some `dzen2` builds
  fail silently; now `-p 1`. The domain colour is the **background** with
  white text -- dark text on black was illegible. The single-instance
  lock gained an age TTL, so a `SIGKILL`ed run is reclaimed instead of
  blocking the indicator forever.
- **Xfe templates.** `tetxcursor` -> `textcursor`. `highlightcolor` and
  `listbackcolor` unified, which removes zebra striping. The manual
  install uses the guarded `[ -e ... ] || cp` form instead of `cp -n`,
  which is not portable.
- **Colour tables corrected** to the dark convention, with the real
  values from the mc skins and the OSD indicator.
- **Optional-package table** now lists `signify` (FreeBSD) and a window
  manager; four of its seven rows are functional dependencies of a
  command, and the table says so.
- **`[updates]` in `local.conf.example`** clarified: one section only --
  `mirrors` for OpenBSD, `hosts` for FreeBSD.

## Upgrade notes -- from v0.3.0

**Two things block the updater on a 0.3.0 system. Both are checked before
anything is written.**

### 1. Mark the domain accounts

0.3.0 has no GECOS markers, and 0.4.0 identifies a role by the marker,
not by the account name. The updater stops and prints the exact commands
for your platform. You can also run them yourself, once, as root, with
the users logged in:

```sh
# OpenBSD
usermod -c "dropQbsd_conductor"  "$CONDUCTOR_USER"
usermod -c "dropQbsd_userdoc"    userdoc
usermod -c "dropQbsd_usermail"   usermail
usermod -c "dropQbsd_userweb"    userweb
```

```sh
# FreeBSD
pw usermod "$CONDUCTOR_USER" -c "dropQbsd_conductor"
pw usermod userdoc           -c "dropQbsd_userdoc"
pw usermod usermail          -c "dropQbsd_usermail"
pw usermod userweb           -c "dropQbsd_userweb"
```

`usermod -c` changes only the GECOS field: no UID, home, groups or data.

Verify before continuing:

```sh
getent passwd "$CONDUCTOR_USER" userdoc usermail userweb
# the fifth field of each line must show its marker
```

### 2. Pass `--from`

0.3.0 predates `/opt/dropQbsd/VERSION`, so the updater cannot know the
source version and will ask for it:

```sh
cd installer
doas ./update.sh --dry-run
doas ./update.sh --from 0.3.0
```

### What the updater does on its own

No manual steps are needed for any of these. They are listed so you know
what to expect, and how to confirm it worked:

| step | what happens | confirm with |
|------|--------------|--------------|
| firewall | `gen_fwall`, `pfctl -nf`, `pfctl -f`, then the three tables repopulated | `pfctl -s info`, `pfctl -t mailserver -T show` |
| `run_app` | rebuilt: static, `root:wheel`, mode 4755 | `ls -l /opt/dropQbsd/bin/run_app` -> `-rwsr-xr-x` |
| integrity | manifest re-signed (the passphrase may be asked) | `Verify` |
| cron | entries merged into root's crontab | `crontab -l | grep dropQbsd` |

If the passphrase is not at hand, the update completes, but
`verify_integrity` will report a violation until you run `Sign`.

### After the update

```sh
Verify       # OK - all files verified
Qcontrol     # domains, drop zone, PF state, logs
```

### Renamed aliases and script files

0.4.0 standardised the `q*` prefix for commands, and the conductor's
script names now follow its role rather than a hardcoded account name.
Two things to check if a launcher, a script or a `[qmenu]` entry calls an
old name:

- **Aliases.** The file bridge is now `Qfile` (it was `File`), and the
  site menu is `Qsite` (it was `Site`). The complete current list is
  `/etc/dropQbsd/alias`: compare it against what your launchers call.
- **Script files.** A renamed script leaves its old copy behind, because
  the updater never deletes or renames anything. The old file appears at
  the end of the update under *files left alone* -- review it and remove
  it by hand.

### FreeBSD

- **Remove `~/.xsession` if it exists.** SDDM reads it and waits for it
  to exit; the `exec wm` line never returns, so the session freezes at
  login. Use `~/.xprofile` (SDDM) or `~/.xinitrc` (startx).
- **`local.conf`: use one `[updates]` section.** For FreeBSD that means
  `hosts = pkg.FreeBSD.org update.FreeBSD.org`, with the OpenBSD
  `mirrors` section commented out.

## Known limitations

- **X11 input isolation**: not solved. A compromised domain can keylog
  the others. The paired desktop/server configuration (roadmap)
  addresses it.
- **Kernel exploits**: all domains share one kernel.
- **NetBSD**: not supported -- `npf` does not filter per user.
- **`qfile` F1-F5**: the bindings are global to the tmux server, not
  scoped to the file bridge session.
- **No packages installed**: the installer has no network policy yet.
  Optional packages must be installed before, or manually after.
- **The updater never deletes**: obsolete files are reported and must be
  removed by hand, from a directory it prints.
- **`dzen2`**: some builds emit `free(): bogus pointer` at exit, a known
  package bug that happens after render. Harmless; `indicator_de`
  suppresses the core dump with `ulimit -c 0`.

## Testing

Tested on real hardware: OpenBSD laptop, OpenBSD desktop, FreeBSD
desktop.
