# dropQbsd v0.4.0 -- Release Notes

**Release date:** 2026-11-22

## Overview

v0.4.0 is the first release that can be installed and updated without
following a manual. It is also the first where the conductor account is
identified by something other than its name.

Four things define it:

1. **Semi-automatic install and update** -- `install.sh` and `update.sh`
   replace the manual procedure as the recommended path.
2. **GECOS role markers** -- a domain account is recognised by a marker in
   its GECOS field, not by its name. The conductor can be called anything.
3. **`qattach`** -- a GUI flow for moving a file from one domain into
   another domain's `~/Downloads`.
4. **Session model** -- `[session] wm` in `local.conf`, `libexec/session`,
   and `dropQbsd.desktop`. The WM is not hardcoded in the stubs;
   `startxfce4` is the default, `xfce4-session` remains valid.

Alongside them: `qinspect` and `qprompt`, a three-level documentation set
(`QUICKSTART.md`, `INSTALL.md`, `INSTALL_MANUAL.md`), and a colour
convention that is now uniform across terminals, `mc`, `xfe`, the
`qmenu` headers and the OSD indicator.

OpenBSD remains the reference platform; FreeBSD remains fully supported.

## Highlights

### Installer and updater

- **`install.sh`** -- idempotent, non-destructive semi-automatic
  installer. Creates the `drop` group and the four domain users (the
  conductor is added to `wheel` for `su`, not for `doas`), the directory
  tree, the configuration, the firewall, the cron jobs and the desktop
  integration. It does **not** set passwords, and it does **not**
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
- **Directory tree.** `/home/drop` with `userweb_export` and
  `usermail_export` (`2770 root:drop`) and `_quarantine`
  (`750 root:wheel`); `Downloads` in every domain home; `usermail/.mail`;
  `userdoc/Sync` (`2770`); `~/.cache/dropqbsd` (user:user 700) in every
  domain home;`/opt/dropQbsd/libexec/session`;
  `/usr/local/share/xsessions/dropQbsd.desktop`;
  `/opt/dropQbsd/VERSION`; `templates/integrity_setup`.
- **Per-home files.** `~/.profile`, `~/.xprofile`, `~/.xinitrc`,
  `~/.xbindkeysrc`, the GTK2 theme and the Xfe seeds (`xferc`/`xfwrc`)
  are created if absent, never overwritten, and reported if the shipped
  version differs. The Xfe **scripts** (`xfqcp`, `xfqimport`, `xfqmv`)
  are code, not seeds: they are copied into `~/.config/xfe/scripts/` and
  kept current, like the nnn plugins. The `.xprofile`/`.xinitrc`/`.xsession`
  stubs end with `exec .../libexec/session`; the WM is in `[session] wm`,
  not in the stub. The updater compares the `# dropQbsd-stub` marker,
  not the bytes; per-home stubs are not overwritten when the marker matches.
  On FreeBSD `.xsession` is never installed.
- **`doas.conf` path.** `/etc/doas.conf` on OpenBSD,
  `/usr/local/etc/doas.conf` on FreeBSD. The installer writes to the
  platform path; the template is `permit nopass root`.
- **Cron merge.** The dropQbsd block is wrapped in `# BEGIN dropQbsd` /
  `# END dropQbsd` and replaced as a block, so repeated runs do not
  duplicate entries and do not disturb the rest of root's crontab.
- **Checklist.** Verifies the drop-zone layout (`%Mp%Lp` for the 2770
  directories), `Downloads`, the conductor in `wheel`, `run_app_impl`
  0700, `doas.conf` at its platform path, VERSION, libexec/session,
  dropQbsd.desktop, CONDUCTOR_USER in /etc/dropQbsd/profile,
  the [session] wm command, the [locale]/[keyboard]/[session] sections,
  PF tables, cron, and filelist coverage. Optional packages are reported
  but do not fail the install.
- **`VERSION`.** The installer records `/opt/dropQbsd/VERSION`;
  `write_version` fails if the repository file is missing or empty.
  `final_checklist` and `update_checklist` verify it.
- **Per-user groups.** `create_one_user` creates `pw groupadd`/`groupadd`
  and uses `-g <user>`; `-L <user>` applies the `login.conf` class.
  `add_to_group_safe` excludes the primary group; `create_users` creates
  the group for existing accounts.
- **Home ownership.** `install_examples_for` chowns `~/.config`,
  `~/.local`, and `~/.cache`; `create_working_dirs` pre-creates
  `~/.cache/dropqbsd`.
- **Session files.** `install_files` calls `install_session_desktop`,
  which seeds `/usr/local/share/xsessions/dropQbsd.desktop`.
  `templates/filelist_for_etc` lists `libexec/session` and
  `templates/integrity_setup`.
- **Optional packages.** `optional_packages_list` uses three columns and
  `pkg info -q` on FreeBSD; `password-store pass`, `xdialog Xdialog`,
  `setxkbmap setxkbmap`.
- **Enforcers.** `enforce_drop`/`enforce_sync` use `GRACE_MIN=2`;
  the tests sleep 150 seconds; `enforce_home` has no grace period.


### Session model

- `[session] wm` in `/etc/dropQbsd/local.conf` is the single WM/DE choice.
- `libexec/session` reads it via `profile_for_etc` (`DROPQBSD_WM`), sets
  `HOME`/`PATH`, applies `setxkbmap`, sources `~/.xprofile`, checks that
  the WM exists, then `exec`s it.
- `/usr/local/share/xsessions/dropQbsd.desktop` runs `libexec/session`.
  `~/.xinitrc` and `~/.xsession` call it too.
- LightDM sources `~/.profile` and `~/.xprofile`; startx/xenodm use
  `~/.xinitrc`/`~/.xsession`. `~/.xsession` is never installed on FreeBSD.
- `startxfce4` is the default; `xfce4-session` remains a valid value in
  `[session] wm`.

### Locale and keyboard

- `[locale]` sets `LANG`/`LC_*`.
- `[keyboard] layout` is applied by `libexec/session` with `setxkbmap`.
- `profile_for_etc` sets `XDG_CONFIG_DIRS`, `XDG_DATA_DIRS`, and a safe
  `XDG_RUNTIME_DIR`; `CONDUCTOR_USER` is resolved from the GECOS marker.
- XFCE users should also set the layout in `xfce4-keyboard-settings`;
  XFCE can override `setxkbmap`.

### Integrity

- `templates/integrity_setup` is the single copy-paste block.
- On a fresh install `signify -G -e` asks for the passphrase twice, and
  `Sign` asks once; `Verify` and cron never ask.
- `Regenerate the key pair?` -- answer **no** to keep the trust anchor.
- If `signify` is missing, the installer prints the block and skips signing.

### Qsite

- `sites.conf` missing -> popup with `mkdir`/`cp` commands.
- No supported browser -> popup with `Pkg qutebrowser` and the full
  `pkg_tru_fwall` path.
- `~/.cache/dropqbsd` root-owned -> popup with `chown`.
- Qsite run as root -> popup and exit; it must run as the conductor.
- `pass`/`xclip` missing -> popup instead of silent `return 0`.

### Version

- The installer records `/opt/dropQbsd/VERSION`; `write_version` fails if
  the repository `VERSION` is missing or empty.
- There is no `SESSION` file.

### Packages

- `setxkbmap` added for `[keyboard]`.
- `qutebrowser` installed by the quickstart; `ungoogled-chromium` and
  `librewolf` remain alternatives.
- `Xdialog` installed separately; it can block.
- OpenBSD XFCE: `pkg_add xfce xfce-extras`; `messagebus`.
- FreeBSD XFCE: `pkg install xfce lightdm lightdm-gtk-greeter`;
  `dbus_enable=YES`.

### GECOS role markers -- the conductor is rename-proof

- Every domain account carries a role marker in the fifth field of
  `/etc/passwd`: `dropQbsd_conductor`, `dropQbsd_userdoc`,
  `dropQbsd_usermail`, `dropQbsd_userweb`.
- The conductor is resolved **from its marker, not its name**. The gate
  requires exactly one marker; the installer and updater refuse zero or
  duplicates; the runtime scripts use the same exact match, with a
  `conductor` fallback only for pre-marker systems.
- A pre-existing account without the marker is **refused, never merged**.
  A personal login that happens to be called `conductor` cannot silently
  acquire drop-zone and domain access; the installer stops and says what
  to do.
- Markers can be added to an existing installation without touching UID,
  home, groups or data (`usermod -c`). This is the one upgrade step a
  0.3.0 system must perform by hand -- see *Upgrade notes*.

### `qattach` -- GUI file attach

- A **new conductor action**: moves a file from a source domain into a
  destination domain's `~/Downloads`, for the blocking case -- attaching
  a file to a mail, or filling an upload form.
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
- **Hardening.** Symlinks in the selected tree are rejected; the picker
  and the import receive the staged path as an argument, not interpolated
  into `su -c`; `chgrp`, `chmod` and `chown` use `-h`, so a link that
  slips through cannot change its target; the destination's `~/Downloads`
  is created if missing; `is_valid_domain` uses the exact GECOS match.

### New tools: `qinspect` and `qprompt`

- **`qinspect`** shows what a file in the drop zone *is*, without
  importing it: metadata, type, hash, a truncated text preview or an
  archive listing, and a two-axis verdict. **CONTENT** is LOW / MEDIUM /
  HIGH, based on type and contents. **TRANSIT** is OK / WARN / BLOCK,
  from `enforce_drop`'s rules: mtime, GID, mode. The final verdict is
  `IMPORT`, `IMPORT WITH CAUTION` or `DO NOT IMPORT`; exit code 0/1/2
  makes it scriptable. Anti-masking is the point: a filename that says
  `.pdf` over an ELF binary raises HIGH, and so does a double extension.
- **`qprompt`** drives any dropQbsd command from a prompt loop in the
  current terminal, which is what makes a non-interactive tool like
  `qinspect` usable from a desktop launcher. It wraps the target through
  the sanitized environment and falls back to plain system commands.

### Documentation restructure

- **`QUICKSTART.md`** -- the three-step installer path, with the
  platform-specific prerequisites and the manual steps after the install.
- **`INSTALL.md`** is the semi-automatic install: installer, manual
  steps, post-install checks, updater.
- **`INSTALL_MANUAL.md`** is the full step-by-step procedure.
- The prerequisites now separate what is in the base system from what is
  a package: on OpenBSD `ksh`, `doas`, `signify`, `tmux`, `pf`, `xrandr`
  and the base window managers are in base; on FreeBSD `ksh`, `doas`,
  `signify`, `tmux`, `xrandr` and X11 are packages, and `pf` is a kernel
  module.
- `[network] lan` is documented as the LAN subnet used by `userdoc` and
  by any rule targeting `@lan`, with the per-platform command to find it.
- Disposable sessions documented (10.3): `Run --disposable <size>`,
  500 MB default, downloads bridged to the real `~/Downloads`.
- Xfe per-domain colour seeds documented; the Xfe scripts are installed
  per-home.

The docs now cover `[locale]`, `[keyboard]`, and `[session]` in
`local.conf`; `VERSION` (no `SESSION`); `templates/integrity_setup`;
Qsite `sites.conf`/browser/cache; `GRACE_MIN=2` and `sleep 150`;
the `dropQbsd` session; `startxfce4`; and the OpenBSD `xenodm` /
FreeBSD `lightdm` split.

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
- **`qcontrol`**: yellow for the file/dir type labels, red for `WARN`;
  the domain colours stay reserved for the domain lines.

### Naming and policy clarification

- **`q*` prefix standardised** across scripts and documentation. Aliases
  whose names changed are listed under *Upgrade notes*.
- **`<updates>` table lifecycle made explicit**: populated every 15
  minutes by `ensure_updates_table` and again on entry of each update
  script, then **flushed on exit** (`FLUSH_ON_EXIT=1`), so the mirror IPs
  are reachable only while an update is running. `<mailserver>` and
  `<services>` stay populated for daily use.
- **Drop zone risk model documented**: `2770 root:drop` lets any member
  of `drop` remove or replace a file in transit. That is accepted by
  design -- the members of `drop` are the same operator in different
  compartments -- and mitigated by `qcp` copying rather than moving, by
  transit permissions of 440, and by inspection before import. A stricter
  model (staging directories 570, exports written by root) is on the
  roadmap.
- **Drop zone lifecycle**: `enforce_drop` decides by mtime, not by
  arrival. A file with an mtime older than 30 minutes is deleted as
  abandoned at the first cycle, whatever its mode or GID; a younger file
  with the wrong GID is quarantined; a younger file with the wrong mode is
  fixed to 440 (file) or 570 (directory).
- **Enforcer locks**: `enforce_drop` and `enforce_sync` carry the PID in
  the lock. A live process is never reclaimed; a dead PID is reclaimed at
  any age; a lock without a PID uses the 15-minute TTL.

## Fixes

Problems present in 0.3.0 and corrected here.

- **`indicator_de` OSD.** `-p 1.5` (a float) made some `dzen2` builds
  fail silently; now `-p 1`. The domain colour is the **background** with
  white text -- dark text on black was illegible. The single-instance
  lock gained an age TTL, so a `SIGKILL`ed run is reclaimed instead of
  blocking the indicator forever. The conductor resolution now uses the
  exact GECOS match, with the `conductor` fallback only for pre-marker
  systems.
- **Fonts far too large on high-density panels.** X derived the DPI from
  the monitor's reported physical size and nothing pinned it. The session
  files now run `xrandr --dpi 96` before the window manager starts.
- **`xterm_root` blocked the calling terminal.** It used `exec xterm`,
  unlike the other four `xterm_*` scripts, which detach with
  `nohup ... &`: the alias returned only when the root window was closed.
  All five now behave the same way. `xterm_root` also runs
  `su -l root -c "env ... $KSH"` with `ENV=/etc/dropQbsd/kshrc`, so the
  root shell sources the dropQbsd chain; `su -s` is not used, because it
  is root-only on OpenBSD.
- **Xfe templates.** `tetxcursor` -> `textcursor`. `highlightcolor` and
  `listbackcolor` unified, which removes zebra striping. The manual
  install uses the guarded `[ -e ... ] || cp` form instead of `cp -n`,
  which is not portable.
- **Colour tables corrected** to the dark convention, with the real
  values from the mc skins and the OSD indicator.
- **Optional-package table** now separates base-system tools from
  packages: it lists `doas` and `mksh` (FreeBSD prerequisites), `signify`,
  `tmux` and `xrandr` (FreeBSD packages; base on OpenBSD) and a window
  manager. Four rows are functional dependencies of a command; the table
  says so.
- **`[updates]` in `local.conf.example`** clarified: one section only --
  `mirrors` for OpenBSD, `hosts` for FreeBSD.
- **`run_app` / `run_app_impl`.** `run_app_impl` is 0700. The gate
  captures the caller's real uid with `getuid()` before `setuid(0)` and
  passes it as an argument; `run_app_impl` refuses any invoker but the
  conductor (exact GECOS match, exactly one). The gate drops
  supplementary groups and sets gid 0 before uid 0, so files created by
  root-owned scripts carry `wheel`, not the caller's group.
- **`enforce_drop` / `enforce_sync`.** PID in the lock: a live enforcer
  is not reclaimed; a dead PID is reclaimed at any age; a lock without a
  PID uses the TTL. `_quarantine` is `root:wheel 750`; the ticket is
  `root:wheel 640`.
- **`enforce_home`.** Logs `cycle complete: fixed=N` and per-property
  lines; no lock (stat + fix, idempotent).
- **`qattach`.** Symlink rejection; `su -c ... -- "$STAGED"`;
  `chgrp -h` / `chmod -h` / `chown -h`; `Downloads` guard; exact
  `is_valid_domain`.
- **`qcontrol`.** Dotfiles and dotfolders in the drop zone; `n_files` and
  `n_dirs` counted separately; the 60-minute window applied to both the
  list and the count; the header right-aligned by the actual length of
  the key hints; type labels yellow, `WARN` red.
- **`qfile`.** The terminal is resized to 3/4 of the screen; qcontrol
  starts one second late, after the resize, so it does not redraw on
  every SIGWINCH.
- **`qinspect`.** Two-axis verdict (CONTENT + TRANSIT); exit code 0/1/2
  is the final verdict.
- **`lib/cron`.** The dropQbsd block is replaced via `# BEGIN` / `# END`
  markers; fixed a double-append that could install the example twice and
  drop the rest of root's crontab.
- **`lib/dirs`.** The drop-zone subdirectories, `Downloads`,
  `usermail/.mail`, `userdoc/Sync` (2770).
- **`lib/users`.** The conductor is added to `wheel` for `su` (not
  `doas`).
- **`lib/examples`.** The Xfe scripts are installed per-home and kept
  current.
- **`lib/checklist`.** `%Mp%Lp` for the 2770 directories;
  `check_drop_layout`; `doas.conf` at the platform path.
- **`doas.conf`.** The installer writes to the platform path
  (`/etc/doas.conf` on OpenBSD, `/usr/local/etc/doas.conf` on FreeBSD);
  the FreeBSD `doas` package is a prerequisite.
- **`install.sh --dry-run`.** `add_to_group_safe` now tolerates a
  non-existent user (`id -gn ... || true`); the dry run reaches the end.
- **`.cache` loop.** The final `chown` loop no longer fails when
  `~/.cache` does not exist; the directory is pre-created.
- **Qsite.** `sites.conf`/browser/cache/root popups; `[[`/`local`
  replaced; `tr '!'` removed; `build_menu` fixed.
- **`startxfce4`.** The session fallback and checklist fallbacks use
  `startxfce4`; `xfce4-session` remains valid.
- **`integrity_setup`.** Renamed from `integrity_setup.txt`;
  `setup_integrity`, `print_manual_steps`, and `sign_filelist` print the
  same block.
- **`VERSION`.** `write_version` fails if the repository file is missing;
  `final_checklist` checks it.
- **`[locale]`/`[keyboard]`/`[session]`.** Added to `local.conf.example`;
  `profile_for_etc` parses them.
- **Qsite cache.** `~/.cache/dropqbsd` pre-created as `user:user 700`.
- **`setxkbmap`.** Added to the optional packages and the session.
- **`GRACE_MIN=2`.** Enforcer tests now sleep 150 seconds.

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
usermod -c "dropQbsd_conductor" "$CONDUCTOR_USER"
usermod -c "dropQbsd_userdoc" userdoc
usermod -c "dropQbsd_usermail" usermail
usermod -c "dropQbsd_userweb" userweb
```

```sh
# FreeBSD
pw usermod "$CONDUCTOR_USER" -c "dropQbsd_conductor"
pw usermod userdoc -c "dropQbsd_userdoc"
pw usermod usermail -c "dropQbsd_usermail"
pw usermod userweb -c "dropQbsd_userweb"
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

### 3. Add the new local.conf sections

`update.sh` never edits `local.conf`. Add by hand:

```ini
[locale]
lang = en_US.UTF-8

[keyboard]
layout = us

[session]
wm = startxfce4
```

`check_local_conf_sections` reports missing sections. In LightDM/SDDM
select the `dropQbsd` session; on OpenBSD xenodm uses `~/.xsession`.

### 4. Per-home stubs

The updater does not overwrite `.profile`, `.xprofile`, `.xinitrc`, or
`.xsession` when the `# dropQbsd-stub` marker matches. To adopt the new
stubs, bump the marker or merge by hand. On FreeBSD never create
`~/.xsession`; use `~/.xprofile` and `~/.xinitrc`.

### 5. Qsite

`Qsite` now uses `~/.cache/dropqbsd` and shows popups for missing
`sites.conf`, missing browser, and root-owned cache. Install a browser
with `Pkg qutebrowser`; create `sites.conf` from
`examples/system/sites.conf.example`.

### 6. XFCE

On OpenBSD: `pkg_add xfce xfce-extras`; `rcctl enable messagebus`;
`rcctl start messagebus`. On FreeBSD: `pkg install xfce`;
`sysrc dbus_enable=YES`. Set `[session] wm = startxfce4`.

### What the updater does on its own

No manual steps are needed for any of these. They are listed so you know
what to expect, and how to confirm it worked:

| step | what happens | confirm with |
|------|--------------|--------------|
| firewall | `gen_fwall`, `pfctl -nf`, `pfctl -f`, then the three tables repopulated | `pfctl -s info`, `pfctl -t mailserver -T show` |
| `run_app` | rebuilt: static, `root:wheel`, mode 4755; `run_app_impl` set to 0700; the gate drops supplementary groups and sets gid 0 | `ls -l /opt/dropQbsd/bin/run_app` -> `-rwsr-xr-x`; `ls -l /opt/dropQbsd/libexec/run_app_impl` -> `-rwx------` |
| integrity | manifest re-signed (the passphrase may be asked) | `Verify` |
| cron | the `# BEGIN` / `# END` block replaced in root's crontab | `crontab -l \| grep dropQbsd` |
| directories | `/home/drop` subdirectories, `Downloads`, `usermail/.mail`, `userdoc/Sync` created | `ls -ld /home/drop/_quarantine /home/drop/userweb_export /home/drop/usermail_export` |
| Xfe scripts | copied into `~/.config/xfe/scripts/` | `ls -l /home/*/.config/xfe/scripts/` |
| `doas.conf` | written to the platform path, template `permit nopass root` | `cat /etc/doas.conf` or `cat /usr/local/etc/doas.conf` |
| `libexec/session` | replaced when changed | `ls -l /opt/dropQbsd/libexec/session` |
| `dropQbsd.desktop` | seeded if absent | `ls -l /usr/local/share/xsessions/dropQbsd.desktop` |
| `VERSION` | written | `cat /opt/dropQbsd/VERSION` |
| `~/.cache/dropqbsd` | pre-created | `ls -ld /home/*/.cache/dropqbsd` |
| per-user groups | created | `id -gn conductor` |

If the passphrase is not at hand, the update completes, but
`verify_integrity` will report a violation until you run `Sign`.

### After the update

```sh
Verify   # OK - all files verified
Qcontrol # domains, drop zone, PF state, logs
Qsite    # first run: sites.conf popup, browser popup
setxkbmap -query
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
- **`doas` and `mksh` are packages, not base.** `doas` reads
  `/usr/local/etc/doas.conf`; `mksh` is the Korn shell the wrapper runs.
  The installer writes `/usr/local/etc/doas.conf` with `permit nopass
  root`; your `permit :wheel` is backed up as
  `usr_local_etc_doas.conf`. Use `su -` for the root steps, or re-add
  your rule from the backup.
- **`pf` is a kernel module.** `kldload pf` and `sysrc pf_enable=YES`
  before running the installer; `check_pf` stops the install if `/dev/pf`
  is missing.

## Known limitations

- **X11 input isolation**: not solved. A compromised domain can keylog
  the others. The paired desktop/server configuration (roadmap)
  addresses it.
- **Kernel exploits**: all domains share one kernel.
- **NetBSD**: not supported -- `npf` does not filter per user.
- **`qfile` F1-F5**: the bindings are global to the tmux server, not
  scoped to the file bridge session.
- **No packages installed**: the installer has no network policy yet.
  `doas` and `mksh` are prerequisites on FreeBSD; optional packages must
  be installed before, or manually after.
- **The updater never deletes**: obsolete files are reported and must be
  removed by hand, from a directory it prints.
- **`dzen2`**: some builds emit `free(): bogus pointer` at exit, a known
  package bug that happens after render. Harmless; `indicator_de`
  suppresses the core dump with `ulimit -c 0`.
- **`qinspect`'s TRANSIT verdict** reflects `enforce_drop`'s rules at the
  moment of inspection; a file can change state between inspection and
  import.
- OpenBSD has no ZFS and no native FFS snapshots. Use `dump`/`restore`,
  or a hypervisor/SAN snapshot; FreeBSD ZFS uses `bectl`, UFS uses
  `dump` or `mksnap_ffs`.
- "Any display manager" is not promised: supported paths are LightDM,
  SDDM, startx, and xenodm. Other DMs need manual wiring.
- `~/.xsession` is xenodm-only on OpenBSD; it is never installed on
  FreeBSD. XFCE can override `setxkbmap`; set the layout in
  `xfce4-keyboard-settings`.
- Qsite needs one of `ungoogled-chromium`, `librewolf`, or `qutebrowser`.
- `startxfce4` is the default; `xfce4-session` remains valid but does
  not set the XFCE environment the way `startxfce4` does.

## Testing

Tested on real hardware: FreeBSD 15 desktop, OpenBSD 8.0 laptop and
desktop. The installer and updater were also exercised with `--dry-run`.
