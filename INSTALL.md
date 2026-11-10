# dropQbsd -- Install

dropQbsd runs on **OpenBSD** (7.5+) and **FreeBSD** (14.0+).
This file covers the **recommended path**: the semi-automatic
installer, followed by a short list of manual steps and
post-install checks. It also covers updating an existing
installation.

If you prefer to install everything by hand, or you want to
understand every step before running it, see
[INSTALL_MANUAL.md](INSTALL_MANUAL.md).

---

## Prerequisites

- A fresh **OpenBSD 7.5+** (reference platform) or **FreeBSD 14.0+**
  installation.
- **1 GB RAM** minimum (2 GB recommended for daily use).
- Root access (`doas` or `su`).
- **Korn shell:**
  - OpenBSD: `/bin/ksh` (base system).
  - FreeBSD: `mksh` — `pkg install mksh`.

### Optional packages

Install these **before** running the installer, if you want the
corresponding features. The installer installs no packages: it has
no network policy yet, and silently installing packages during a
security install is not acceptable. If you prefer to install them
**after**, or step by step, follow
[INSTALL_MANUAL.md](./INSTALL_MANUAL.md).

| Package | Enables | If missing |
|---------|---------|------------|
| `tmux`, `nnn` | `Qfile` (qfile) | `Qfile` does not work |
| `dzen2`, `xdotool` | `Indicator` (domain indicator) | `Indicator` does not work |
| `yad`, `xbindkeys`, `pass`, `xclip` | `Qmenu` (conductor menu), `Qsite` (qsite) | `Qmenu` and `Qsite` do not work |
| `Xdialog` | `Qattach` (attach a file to a mail/upload) | `Qattach` does not work |
| `signify` | Integrity verification (`Sign`/`Verify`) | Integrity not available |
| `syncthing` | LAN file sync for `userdoc` | **dropQbsd still works**; only `userdoc` loses sync |
| a window manager | XFCE, cwm, twm, i3, ... | no graphical session |

Four of the seven rows are functional dependencies of a command. If the package is missing,
that command does not work; everything else is unaffected. **`signify`, `syncthing`, and a
window manager are different**: they are optional (`signify` for integrity verification, `syncthing`
for one domain, userdoc, and a window manager only for a graphical session), and their absence
does not affect dropQbsd's core.

On OpenBSD:

```sh
doas pkg_add tmux nnn dzen2 xdotool yad xbindkeys pass xclip syncthing Xdialog
```

On FreeBSD:

```sh
doas pkg install tmux nnn dzen2 xdotool yad xbindkeys pass xclip syncthing xdialog
```

**A pre-existing account that collides with the conductor name stops the
installer.** The conductor defaults to the account name `conductor`
(rename-proof: recognized by the `dropQbsd_conductor` GECOS marker, not by
name). If an account named `conductor` already exists on your system (for
example, your personal login), the installer **fails with a clear message**
rather than guessing or prompting. Set a different name and re-run:

```sh
CONDUCTOR_USER=myconductor doas ./install.sh
```

The GECOS marker stays `dropQbsd_conductor` regardless of the account name.
A conductor account must be empty: it only directs domains, it does not hold
data (data belongs in `userdoc`).

---

## 1. Run the installer

From the repository's `installer/` directory, as root:

```sh
chmod +x install.sh
doas ./install.sh
```

### Options

| Flag | Meaning |
|------|---------|
| `--dry-run` | Print the plan without executing anything. |
| `--skip-backup` | Skip the backup step (you must back up manually). |
| `--help` | Show usage. |

**Always run `--dry-run` first** on a new machine:

```sh
doas ./install.sh --dry-run
```

The installer is idempotent and non-destructive of **system
configuration**: it never touches `local.conf`, the signing keys, or
operator-owned files. It **does** overwrite per-user dotfiles
(`~/.exrc`, `~/.config/mc/ini`, `~/.config/nnn/plugins/`) when
installing the desktop integration -- each overwritten file is backed up
first as `.bak.<timestamp>`.

**Source-tree only.** The installer runs from the repository's
`installer/` directory; it is not itself copied to
`/opt/dropQbsd/`. The repository root is the *source*;
`/opt/dropQbsd` is the *destination*.

---

## 2. What the installer does

In order:

1.  **Backup** -- copies the files it will touch to
    `/var/backups/dropQbsd_<timestamp>/`. Passive: it never
    restores automatically.
2.  **Users** -- creates the `drop` group and the four domain
    users (`$CONDUCTOR_USER`, `userdoc`, `usermail`, `userweb`), each marked
    with a dropQbsd GECOS role marker. **Passwords are not set.**
    **A domain account is never merged**: if it exists with the
    correct marker it is reused (upgrade/re-install); if it exists
    without the marker, the installer refuses to proceed and exits.
3.  **Directories** -- creates the tree and applies the permission
    model (SGID drop zone, 700 homes, 750 config dirs).
4.  **Configuration** -- copies policy, scripts and dotfiles under
    `/etc/dropQbsd/` (including `conductor.conf` and `attach.conf`)
    and `/opt/dropQbsd/`.
5.  **Desktop integration** -- installs the per-domain working
    environment from [INSTALL_MANUAL.md 10.1-10.6](INSTALL_MANUAL.md):
    mc skins and user menu (F2: qcp/qmv/qimport), nnn plugins,
    vi config, and the GTK theme. The independent utilities
    (10.7-10.15 -- control panel, domain indicator, conductor menu
    `qmenu` + `xbindkeys`, site menu, Syncthing, VLC) are **not**
    installed; add them as needed.
6.  **`run_app` build** -- delegates to `admin/build_run_app`,
    which enforces `-static`, `chown root:wheel`, `chmod 4755`,
    and verifies the result.
7.  **`login.conf`** -- appends the per-user resource classes and
    rebuilds the login database with `cap_mkdb`.
8.  **Firewall** -- generates `pf.conf` from the policy, applies
    it, and populates the three PF tables.
9.  **Integrity (Sign)** -- optionally configures `signify`:
    generates an encrypted key pair (if absent) and signs the
    manifest via `admin/sign_filelist`.
10. **Integrity verification (Verify)** -- runs one verification
    pass and reads the result from the log.
    During verification, the installer checks that the integrity
    filelist covers every shipped file and that every listed file
    exists. It stops if a shipped file is uncovered.
11. **Cron** -- merges the dropQbsd entries into root's crontab.
    The `verify_integrity` entry is installed only if a signature
    exists.
12. **Version** -- records the installed version in
    `/opt/dropQbsd/VERSION`.
13. **Checklist** -- verifies users, files, the setuid bit, the
    loaded firewall, the PF tables and the cron entries.
14. **Manual steps** -- prints what remains.

**Integrity verification needs a decision, not a manual step.** The
installer asks whether to configure `signify`. If you answer yes and no
key exists, it generates an **encrypted** key pair (asking a passphrase)
and signs the manifest. The commands below remain the reference for
three cases: an **offline** key, **replacing** a key, or configuring
integrity **after** the install.

```sh
cd /opt/dropQbsd
rm -f /root/dropQbsd.sec \
      /opt/dropQbsd/keys/dropQbsd.pub \
      /opt/dropQbsd/keys/dropQbsd_scripts.sha256.sig
signify -G -e -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
```

This creates an **encrypted** key pair (passphrase) -- the
recommended option. For the offline-key alternative (no
passphrase, key kept on removable media), see
[INSTALL_MANUAL.md 10.8](INSTALL_MANUAL.md). Then install the
filelist, sign the manifest, and verify it worked:

```sh
cp templates/filelist_for_etc /etc/dropQbsd/filelist
chown root:wheel /etc/dropQbsd/filelist
hmod 644 /etc/dropQbsd/filelist
Sign
Verify
```

Do this **before** enabling the `verify_integrity` cron job;
otherwise cron logs `SETUP INCOMPLETE` every 5 minutes.

---

## 3. Manual steps after the installer

The installer prints these at the end. They are not optional.

### 3.1 Set passwords

```sh
passwd "$CONDUCTOR_USER"
passwd userdoc
passwd usermail
passwd userweb
```

### 3.2 Edit `local.conf`

Edit `/etc/dropQbsd/local.conf` with your LAN subnet, mail
servers, and any extra services. The file is heavily commented;
read it before editing.

The **`[network] lan`** value is **required**. Use the subnet,
not your single IP:

```sh
CORRECT: 192.168.1.0/24
WRONG:   192.168.1.42
```

The **`[sync]`** section sets the archive directories: `dst`
(import destination, default `/home/userdoc/Sync`), `www_src`
(export source, default `/home/userweb/www`), `mail_src`
(default `/home/usermail/.mail`).

**`[sync]` directory behavior.** The import destination (`dst`) is created
automatically if missing. The export sources (`www_src`, `mail_src`) are
NOT created: a missing export source is a hard error for the export scripts
(there is no data to export). Create the export directories yourself —
or let the application (browser, mail client) create them on first use:

```sh
mkdir -p /home/userweb/www
mkdir -p /home/usermail/.mail
```

**`[sync]` is optional.** If omitted, the defaults above are used. Only
`[network] lan` is REQUIRED. A missing `dst` is created; a missing source
is a hard error for the export scripts (there is no data to export), not a
configuration error.

### 3.3 Regenerate the firewall and repopulate the tables

After editing `local.conf`:

```sh
/opt/dropQbsd/libexec/wrapper \
    /opt/dropQbsd/admin/gen_fwall openbsd   # or freebsd

pfctl -nf /etc/pf.conf && pfctl -f /etc/pf.conf

/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_mailserver_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_services_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/ensure_updates_table
```

`pfctl -f` empties **every** persistent table, so repopulating is
mandatory, not cosmetic. Without it, `usermail` and `userweb`
stay offline until their next cron cycle.

---

## 4. Post-install checks

### 4.1 Domains

Each domain must be able to do its job and nothing more:

| Domain | Can | Cannot |
|--------|-----|--------|
| `conductor` | `Qmv`/`Qcp`/`Qimport`, `Run` into domains | -- |
| `userweb` | browse the web | reach LAN IPs |
| `usermail` | send/receive email | browse the web |
| `userdoc` | access LAN storage, Syncthing | reach the internet |

`qmenu` (conductor): press **`Mod4+q`** -- the coloured `qmenu`
window opens. If it does not, verify `yad` and `xbindkeys` are
installed and that `~/.xbindkeysrc` exists in `/home/$CONDUCTOR_USER`.

### 4.2 Enforcers

```sh
tail -f /var/log/dropQbsd/enforce_drop.log
tail -f /var/log/dropQbsd/enforce_home.log
tail -f /var/log/dropQbsd/enforce_sync.log
```

An **empty log is normal**: the enforcers only log when they act.

### 4.3 PF tables

```sh
pfctl -t mailserver -T show
pfctl -t services -T show
pfctl -t updates -T show
```

Each should list the resolved IPs. If empty, re-run the
corresponding `update_*` script (3.3).

### 4.4 Resource limits

```sh
su -l userdoc -c 'ulimit -n'   # expect 32768
```

### 4.5 Firewall loaded

```sh
pfctl -s info | grep -i status
```

Each `Gen` run backs up the previous valid `/etc/pf.conf` to
`/etc/pf.conf.bak.<timestamp>` (only if `pfctl -nf` passes). If a bad
generation cuts your connection, restore the last good ruleset:

```sh
cp /etc/pf.conf.bak.<timestamp> /etc/pf.conf
pfctl -f /etc/pf.conf
```

### 4.6 Control panel

As the conductor:

```sh
Qcontrol
```

Shows compartment status, drop zone contents and system health.
Press `a` to authenticate as root for PF state and logs.

### 4.7 Qattach

If `Xdialog` is installed, verify the attach flow:

```sh
Qattach
```

Three popups appear: pick a file (the picker runs as `userdoc`,
confined to its home), then pick a destination. The file lands in
the destination's `~/Downloads`, as confirmed by the third popup.

If `Xdialog` is missing, `Qattach` reports an error and exits.
Nothing else is affected.

### 4.8 Verify integrity (optional but recommended)

If you did not set up integrity during install -- or if you need
to replace the private key after install -- generate the key pair
and sign the manifest now:

```sh
cd /opt/dropQbsd
rm -f /root/dropQbsd.sec \
      /opt/dropQbsd/keys/dropQbsd.pub \
      /opt/dropQbsd/keys/dropQbsd_scripts.sha256.sig
signify -G -e -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
cp templates/filelist_for_etc /etc/dropQbsd/filelist
chown root:wheel /etc/dropQbsd/filelist
chmod 644 /etc/dropQbsd/filelist
Sign
Verify
```

The `-e` flag creates an **encrypted** key (recommended); for an
offline key, see [INSTALL_MANUAL.md §10.8](INSTALL_MANUAL.md).
If a key already exists from an earlier install, the `rm` lines
clear it first — `signify -G` will not overwrite an existing
key, and leaving a stale one keeps the old signature valid.

---

## 5. FreeBSD: one warning

**Never create `~/.xsession` on FreeBSD.** SDDM reads it and
waits for it to exit; the `exec wm` line never returns, so the
graphical session freezes at login. Use `~/.xprofile` (SDDM) or
`~/.xinitrc` (startx). The installer never creates `~/.xsession`
on FreeBSD.

---

## 6. Updating an existing installation

To update an existing dropQbsd installation to the version in the
repository, use the **updater**:

```sh
chmod +x update.sh
doas ./update.sh
```

### What the updater does

- **Preserves** the operator's configuration. `local.conf` is the
  single operator-owned file; it is never written.
- **Replaces** the project-owned files and directories, but only
  those whose content actually changed.
- **Backs up** every file it overwrites, into a single versioned
  directory (`/var/backups/dropQbsd_update_<timestamp>/`), so any
  file can be restored with one `cp`.
- **Never regenerates the signing key.** If integrity is
  configured, it re-signs the manifest; the trust anchor is
  preserved.
- **Never deletes or renames anything.** Files that are no longer
  in the repository are *reported*, not removed; the operator
  reviews and deletes them by hand.

**The updater verifies the GECOS markers.** Before touching
anything, it checks that every domain account carries its dropQbsd
role marker. If a marker is missing -- a foreign account, or a
pre-marker installation that was never migrated -- the updater
refuses to run. On a pre-marker system, run the migration once
first (see INSTALL_MANUAL.md 1, "Marking an existing dropQbsd
system"), or re-run the installer.

### Options

| Flag | Meaning |
|------|---------|
| `--dry-run` | Print the plan without executing anything. |
| `--from <version>` | Source version, for installations that predate the `VERSION` file. |
| `--help` | Show usage. |

### The update report

The updater prints a report at the end, in three sections:

- **Files overwritten** -- replaced, each backed up in the backup
  directory.
- **Files obsolete** -- project files that are no longer in the
  repository. Usually the old copy of a file that moved; the new
  copy is already installed. **Review and delete by hand.**
- **Files left alone** -- files that are not in the repository and
  are not known project files. They are the operator's; the
  updater did not touch them.

### Restoring a file

Backup names are flat: the path with `/` replaced by `_`. For
example, `/home/userdoc/.exrc` is stored as
`home_userdoc_.exrc`. To restore:

```sh
cp -Rp /var/backups/dropQbsd_update_<timestamp>/home_userdoc_.exrc \
       /home/userdoc/.exrc
```

The updater is **not** the installer. Running the installer on an
existing installation would overwrite `local.conf` with the
example; use the updater instead.

---

## 7. Where things live

| Path | Contents |
|------|----------|
| `/opt/dropQbsd/` | scripts (`admin/`, `bin/`, `libexec/`, `sbin/`, `src/`) |
| `/etc/dropQbsd/` | policy and configuration (`domains.conf`, `local.conf`, `schema`, `attach.conf`, `conductor.conf`, `kshrc`, ...) |
| `/home/drop/` | the drop zone (SGID, group `drop`) |
| `/var/log/dropQbsd/` | logs (`install.log`, `update.log`) |
| `/var/backups/dropQbsd_<ts>/` | installer backup |
| `/var/backups/dropQbsd_update_<ts>/` | updater backup |

---

## 8. Full manual procedure

For the complete step-by-step manual install -- every command, every
file, every permission -- see
**[INSTALL_MANUAL.md](INSTALL_MANUAL.md)**.

It covers the same ground as the installer, at the level of
individual commands, and is the reference for understanding what
the installer does and for troubleshooting.
