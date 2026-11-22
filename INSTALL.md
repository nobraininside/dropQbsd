# dropQbsd -- Installation (semi-automatic procedure)

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

**What is in the base system.** On OpenBSD, `ksh`, `doas`, `signify`,
`tmux`, `pf`, `xrandr` and the base window managers (`cwm`, `fvwm`,
`twm`) are part of the base install. On FreeBSD, the base has `sh`,
`pf` (as a kernel module), `pfctl`, `file`, `stat`, `sha256`, `tar`,
`head`, `grep`, `sed`, `awk`; `ksh`, `doas`, `signify`, `tmux`,
`xrandr` and all of X11 are packages.

| Package | Platform | Enables | If missing |
|---------|----------|---------|------------|
| `doas` | FreeBSD (base on OpenBSD) | root access for the installer and the documented commands | use `su`, or `pkg install doas` |
| `mksh` | FreeBSD (base on OpenBSD) | the Korn shell the wrapper runs | no dropQbsd script runs |
| `tmux` | FreeBSD (base on OpenBSD) | `Qfile` | `Qfile` does not work |
| `nnn` | both | `Qfile` | `Qfile` does not work |
| `dzen2`, `xdotool` | both | `Indicator` | `Indicator` does not work |
| `password-store`, `xbindkeys`, `xclip`, `yad` | both | `Qmenu`, `Qsite` | `Qmenu` and `Qsite` do not work |
| `Xdialog` | both (`xdialog` on FreeBSD) | `Qattach` | `Qattach` does not work |
| `signify` | FreeBSD (base on OpenBSD) | Integrity verification | Integrity not available |
| `syncthing` | both | LAN file sync for `userdoc` | dropQbsd still works; only `userdoc` loses sync |
| `xrandr` | FreeBSD (base on OpenBSD) | DPI pinned to 96 at session start | fonts far too large on high-density panels |
| a window manager | FreeBSD (OpenBSD base: `cwm`, `fvwm`, `twm`) | graphical session | no graphical session |

`doas` and `mksh` are prerequisites, not optional features. The other
rows are optional: a missing package disables one command, not the
system. `signify`, `syncthing`, `xrandr` and a window manager are
different: their absence does not break dropQbsd's core.

On OpenBSD:

```sh
doas pkg_add nnn dzen2 xdotool yad xbindkeys password-store xclip syncthing Xdialog
```

On FreeBSD, `doas` and `mksh` are packages, not base. Install them first
as root:

```sh
su -
pkg install doas mksh
cat > /usr/local/etc/doas.conf <<'EOF'
permit :wheel
permit nopass root
EOF
exit
```

Then:

```sh
doas pkg install -y nnn tmux dzen2 xdotool yad xbindkeys password-store xclip syncthing xdialog xrandr
```

Add `signify` to the FreeBSD list only if you want integrity
verification.

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

**The gate refuses every invoker but the conductor.** `run_app.c` captures the caller's
real uid with `getuid()` before `setuid(0)` and passes it as the first argument;
`run_app_impl` validates it and compares it with the uid resolved from the `dropQbsd_conductor`
GECOS marker. A system with no marked conductor cannot run the gate; the installer and updater
both refuse to proceed without the marker.

---

## 1. Run the installer

From the repository's `installer/` directory, as root:

```sh
chmod +x install.sh
./install.sh --dry-run
./install.sh
```

### Options

| Flag | Meaning |
|------|---------|
| `--dry-run` | Print the plan without executing anything. |
| `--skip-backup` | Skip the backup step (you must back up manually). |
| `--help` | Show usage. |

**Always run `--dry-run` first** on a new machine. As root:

```sh
./install.sh --dry-run
```
Warnings in a dry run are expected: missing users, home directories,
examples/apps, configuration files, PF tables, or cron entries are
created by the real install. They are not failures.

The installer is idempotent and non-destructive of **system
configuration**: it never touches `local.conf`, the signing keys, or
operator-owned files. It **does** overwrite per-user dotfiles
(`~/.exrc`, `~/.config/mc/ini`, `~/.config/nnn/plugins/` and the files
listed in INSTALL_MANUAL.md 10.1) when installing the desktop
integration -- each overwritten file is backed up first as `.bak.<timestamp>`.

The installer writes `/opt/dropQbsd/VERSION` and installs
`/usr/local/share/xsessions/dropQbsd.desktop` and
`/opt/dropQbsd/libexec/session`.  All three are checked by final_checklist.

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
    users (`$CONDUCTOR_USER`, `userdoc`, `usermail`, `userweb`), each
    marked with a dropQbsd GECOS role marker. **Passwords are not set.**
    **A domain account is never merged**: if it exists with the
    correct marker it is reused (upgrade/re-install); if it exists
    without the marker, the installer refuses to proceed and exits.
    The conductor is also added to the `wheel` group, so `Xtroot` can
    `su -` to root with the root password. This is not a `doas` grant:
    `doas.conf` has no conductor rule.
    On FreeBSD, `create_one_user` in `installer/lib/users`, called by
    `install.sh`/`update.sh`” creates a per-user group and uses
    `pw useradd -g <user> -G drop`. On OpenBSD, `useradd -g <user>` plus
    `usermod -G drop`. add_to_group_safe excludes the primary group before
    `pw usermod -G`, and create_users creates the per-user group even for
    existing accounts. This keeps chown user:user and enforce_home
    deterministic.
3.  **Directories** -- creates the tree and applies the permission
    model (SGID drop zone, 700 homes, 750 config dirs). Creates
    `/home/drop` and its subdirectories: `userweb_export` and
    `usermail_export` (`2770 root:drop`), `_quarantine` (`750 root:wheel`),
    and `Downloads` in every domain home. Also creates the default
    `[sync]` directories: `userdoc/Sync`, `userweb/www`, `usermail/.mail`.
    For every domain user, pre-create ~/.cache/dropqbsd as user:user 700.
    This is the Qsite cache directory; pre-creating it prevents a root-run
    Qsite from leaving it root:wheel.
4.  **Configuration** -- copies policy, scripts and dotfiles under
    `/etc/dropQbsd/` (including `conductor.conf` and `attach.conf`)
    and the doas policy to its platform path (`/etc/doas.conf` on
    OpenBSD, `/usr/local/etc/doas.conf` on FreeBSD). `relocate_conflicting_dotfiles` 
    executed by `install.sh`/`update.sh` in `installer/lib/files`
    moves pre-existing `.profile`, `.xprofile`, `.xsession`, `.xinitrc` aside
    before the stubs are installed. The stubs are installed by `install_dotfile`
    from `installer/lib/files`; on FreeBSD `.xsession` is never installed. 
    `install_files` calls `install_session_desktop` (in `installer/lib/files`),
    which seeds `/usr/local/share/xsessions/dropQbsd.desktop`
    (Exec=wrapper session).
5.  **Desktop integration** -- installs the per-domain working
    environment from [INSTALL_MANUAL.md 10.1-10.6](INSTALL_MANUAL.md):
    mc skins and user menu (F2: qcp/qmv/qimport), nnn plugins,
    vi config, and the GTK theme. The independent utilities
    (10.7-10.15 -- control panel, domain indicator, conductor menu
    `qmenu` + `xbindkeys`, site menu, Syncthing, VLC) are **not**
    installed; add them as needed. Per-home stubs and `~/.xbindkeysrc`
    are installed if absent, and never overwritten. `install_examples_for`
    from `installer/lib/examples` chowns the parent `~/.config`, `~/.local` 
    and `~/.cache` to the account, then the leaf directories. Without
    the parent chown, `~/.config` and `~/.local` can remain root:conductor
    and break GLib/XFCE and Qsite.
6.  **`run_app` build** -- delegates to `admin/build_run_app`,
    which enforces `-static`, `chown root:wheel`, `chmod 4755`,
    and verifies the result. The same step sets `run_app_impl` to 
   `0700 root:wheel`: the gate is the only entry point, and no domain
   account may execute the implementation directly.
7.  **`login.conf`** -- appends the per-user resource classes and
    rebuilds the login database with `cap_mkdb`.
8.  **Firewall** -- generates `pf.conf` from the policy, applies
    it, and populates the three PF tables.
9. **Integrity (Sign)** -- optionally configures `signify` and signs the
    manifest via `admin/sign_filelist`. The installer asks whether to
    configure script integrity. If you answer yes and no key exists, it
    generates an **encrypted** key pair: `signify -G -e` asks for a
    passphrase twice (set and confirm), and `Sign` then asks for the same
    passphrase once to sign the manifest. On a fresh install that is three
    passphrase prompts in total. If a key already exists, the installer
    first asks whether to regenerate it: answer **no** to keep the current
    trust anchor, **yes** only if you intend to invalidate every prior
    signature. The signature covers the dropQbsd scripts and
    `/etc/dropQbsd` configuration, not OS packages. If `signify` is not
    installed, the installer prints `templates/integrity_setup` and skips
    signing; install it and run `Sign`.
10. **Integrity verification (Verify)** -- runs one verification pass
    through `verify_integrity_setup` and reads the result from
    `/var/log/dropQbsd/verify_integrity.log`. Verification is public-key
    only: `Verify` and the `verify_integrity` cron job never ask for the
    passphrase. If no public key exists, integrity was not configured and
    the check is skipped. If the last log line is not `OK - all files
    verified`, the installer fails.
11. **Cron** -- merges the dropQbsd entries into root's crontab.
    The `verify_integrity` entry is installed only if a signature
    exists.
12. **Version** -- records the installed version in
    `/opt/dropQbsd/VERSION`.
13. **Checklist** -- verifies users and their dropQbsd GECOS markers,
    the setuid bit on `run_app`, mode 700 on `run_app_impl`, `doas.conf`,
    `pf.conf` unless the firewall was deferred, `local.conf`, `kshrc`,
    the log directory, the wrapper, `VERSION`, `libexec/session`,
    `/usr/local/share/xsessions/dropQbsd.desktop`, `CONDUCTOR_USER` in
    `/etc/dropQbsd/profile`, the `[session] wm` command, the PF tables,
    the cron entries, the `local.conf` sections, and the integrity
    filelist coverage. Optional packages are reported but do not fail the
    install.
14. **Manual steps** -- prints what remains.

**Integrity verification needs a decision, not a manual step.** The
installer asks whether to configure `signify`. If you answer yes and no
key exists, it generates an **encrypted** key pair: `signify -G -e` asks
for a passphrase twice (set and confirm), and `Sign` then asks for the
same passphrase once to sign the manifest. On a fresh install that is
three passphrase prompts in total. If a key already exists, the installer
first asks whether to regenerate it: answer **no** to keep the current
trust anchor, **yes** only if you intend to invalidate every prior
signature. Verification is public-key only, so `Verify` and the
`verify_integrity` cron job never ask for the passphrase. If `signify` is
not installed, the installer prints the setup commands and skips signing;
install it and run `Sign` and `Verify`. The commands below remain the
reference for three cases: an **offline** key, **replacing** a key, or
configuring integrity **after** the install.

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
chmod 644 /etc/dropQbsd/filelist
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
passwd conductor        # or the conductor name you chose
passwd userdoc
passwd usermail
passwd userweb
```
The installer replaces `doas.conf` with `permit nopass root`; re-add
`permit :wheel` from the backup if you want `doas` for your login.

### 3.2 Edit `local.conf`

Edit `/etc/dropQbsd/local.conf` with your LAN subnet, mail
servers, and any extra services. The file is heavily commented;
read it before editing.

The **`[network] lan`** value is **required**. It is the LAN subnet
used by `userdoc` (file sharing, Syncthing) and by any rule targeting
`@lan` in the policy. Use the subnet, not your single IP:

```sh
CORRECT: 192.168.1.0/24
WRONG:   192.168.1.42
```

Find it with:

```sh
# OpenBSD
ifconfig egress | grep inet
#   inet 192.168.1.42  ->  subnet is 192.168.1.0/24

# FreeBSD
ifconfig "$(route -n get default | awk '/interface:/{print $2}')" | grep inet
```

Example:

```text
inet 192.168.1.42 netmask 0xffffff00 broadcast 192.168.1.255
```

The subnet is the network address from the IP and netmask: `192.168.1.0/24`.

Edit `/etc/dropQbsd/local.conf` as root:

```sh
vi /etc/dropQbsd/local.conf
```

```ini
[network]
lan = 192.168.1.0/24

[locale]
lang = en_US.UTF-8

[keyboard]
layout = us

[session]
wm = startxfce4
```
Set [locale] lang and [keyboard] layout to your system values:
see `locale -a` and `setxkbmap -query`. Set [session] wm to the WM/DE
you actually use. In LightDM/SDDM, select the dropQbsd session; if you
select the DE session, [session] wm is not used and the DE starts
directly. If you use XFCE, also set the layout in
xfce4-keyboard-settings: XFCE can override setxkbmap.

**`[sync]` directory behavior.** The installer creates the three
default directories -- `dst` (`/home/userdoc/Sync`), `www_src`
(`/home/userweb/www`) and `mail_src` (`/home/usermail/.mail`) --
empty. An empty source is fine; a **missing** source is a hard error
for the export scripts. If you change a path in `local.conf`, create
the new directory yourself.

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

The firewall reads only the network-related sections of `local.conf`:
`[network]`, `[mailserver]`, `[services]`, `[updates]`, and `[extra.*]`.
`[locale]`, `[keyboard]`, and `[session]` affect the shell and X session,
not `gen_fwall`.

### 3.4 Verify the enforcers

The enforcers run from cron every minute. `enforce_home` has no grace
period; `enforce_drop` and `enforce_sync` skip files younger than
`GRACE_MIN=2` minutes.

enforce_home:

```sh
chmod 755 /home/userdoc
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/enforce_home
stat -f '%Lp %Su:%Sg %N' /home/userdoc   # 700 userdoc:userdoc
```

enforce_drop:

```sh
touch /home/drop/t_perm.txt
chmod 600 /home/drop/t_perm.txt
chgrp drop /home/drop/t_perm.txt
sleep 150
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/enforce_drop
stat -f '%Lp %N' /home/drop/t_perm.txt   # 440
rm -f /home/drop/t_perm.txt
```

enforce_sync:

```sh
touch /home/userdoc/Sync/t_test.txt
chown root:wheel /home/userdoc/Sync/t_test.txt
sleep 150
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/enforce_sync
stat -f '%Lp %Su:%Sg %N' /home/userdoc/Sync/t_test.txt  # 660 userdoc:userdoc
rm -f /home/userdoc/Sync/t_test.txt
```

An empty log is normal. If a manual run exits immediately, cron holds
the lock: wait for `/var/run/enforce_drop.lock` or
`/var/run/enforce_sync.lock` to disappear and retry.

### 3.5 Qsite

On first start Qsite looks for `~/.config/dropQbsd/sites.conf`. If it
is missing, Qsite shows a popup with the commands:

```sh
mkdir -p ~/.config/dropQbsd
cp /opt/dropQbsd/examples/system/sites.conf.example ~/.config/dropQbsd/sites.conf
```

If no supported browser is installed, Qsite shows the no-browser popup.
Install one through the dropQbsd package window, for example:

```sh
Pkg qutebrowser
```

Qsite uses `~/.cache/dropqbsd`; it must be owned by the conductor. If
it is root-owned, Qsite shows the cache-ownership popup with the
`chown` command.

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

**`Xtroot` runs `su -` to root** inside the terminal. The conductor
must be in `wheel` (the installer adds it) and the root password is
required. `doas` is not involved.

**`Run` is conductor-only.** Every other account invoking `run_app`
gets an error; the check lives in `run_app_impl`, not in the caller's shell.

`qmenu` (conductor): press **`Mod4+q`** -- the coloured `qmenu`
window opens. If it does not, verify `yad` and `xbindkeys` are
installed and that `~/.xbindkeysrc` exists in `/home/$CONDUCTOR_USER`.

### 4.2 Enforcers

```sh
tail -f /var/log/dropQbsd/enforce_drop.log
tail -f /var/log/dropQbsd/enforce_home.log
tail -f /var/log/dropQbsd/enforce_sync.log
```

The enforcers skip files younger than GRACE_MIN=2 minutes.

enforce_home: no grace period; chmod 755 /home/userdoc, run EnHome,
expect 700 userdoc:userdoc.

enforce_drop: create /home/drop/t_perm.txt 0600 group drop, wait 150
seconds, run Endrop, expect 0440.

enforce_sync: create /home/userdoc/Sync/t_test.txt owned root:wheel,
wait 150 seconds, run Ensync, expect 660 userdoc:userdoc.

An empty log is normal; the enforcer logs only when it acts.
If a run exits immediately, cron holds the lock; wait and retry.

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

The installer creates `~/Downloads` in every domain home. If the
directory is missing, `qattach` creates it before importing.

### 4.8 Qsite

- `~/.config/dropQbsd/sites.conf` exists. On first start Qsite shows
  the popup with the copy commands if it is missing.
- A supported browser is installed. If not, Qsite shows the
  no-browser popup and suggests `Pkg qutebrowser`.
- `~/.cache/dropqbsd` is owned by the conductor. If it is root-owned,
  Qsite shows the cache-ownership popup with the `chown` command.
- Qsite runs as the conductor from Qmenu; if it was run as root,
  `~/.cache/dropqbsd` may be root:wheel.

### 4.9 Session

- `/usr/local/share/xsessions/dropQbsd.desktop` exists.
- `/opt/dropQbsd/libexec/session` is executable.
- `command -v` succeeds for the `[session] wm` value.
- In LightDM/SDDM, select **dropQbsd**; if you select the DE session,
  `[session] wm` is not used and the DE starts directly.
- `setxkbmap -query` shows the expected layout. On XFCE, check
  `xfce4-keyboard-settings`.

### 4.10 Verify integrity (optional but recommended)

If you did not configure integrity during install, the installer
printed the same commands from `templates/integrity_setup`. You can
run them from that file or use the block below.

If you need to replace the private key after install -- or if you need
to configure integrity after the install -- generate the key pair and
sign the manifest now:

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

`signify -G -e` asks for the passphrase twice (set and confirm), and
`Sign` asks for it once. `Verify` and the `verify_integrity` cron job
use only the public key and never ask for it.

If a key already exists from an earlier install, the `rm` lines clear
it first -- `signify -G` will not overwrite an existing key, and leaving
a stale one keeps the old signature valid. Answer **no** to
"Regenerate the key pair?" to keep the current trust anchor; answer
**yes** only if you intend to invalidate every prior signature.

If `signify` is missing, install it first (`pkg install signify` on
FreeBSD; it is in base on OpenBSD), then run `Sign` and `Verify`.

---

## 5. FreeBSD: one warning

Never install `~/.xsession` on FreeBSD with SDDM: SDDM reads it and waits
for it to exit, so the graphical session freezes at login. LightDM
ignores `~/.xsession`; on FreeBSD use `~/.xprofile` for LightDM/SDDM and
`~/.xinitrc` for `startx`. `~/.xsession` is for xenodm on OpenBSD only.

---

## 6. Updating an existing installation

To update an existing dropQbsd installation to the version in the
repository, use the **updater**. As root:

```sh
chmod +x update.sh
./update.sh
```

### What the updater does

- **Preserves** the operator's configuration. `local.conf` is the
  single operator-owned file; it is never written.
- **Replaces** the project-owned files and directories, but only
  those whose content actually changed.
- **Backs up** every file it overwrites, into a single versioned
  directory (`/var/backups/dropQbsd_update_<timestamp>/`), so any
  file can be restored with one `cp`.
- **Completes per-home files:** creates what is missing, leaves existing
  ones alone, and reports any that differ from the shipped version.
- **Never regenerates the signing key.** If integrity is
  configured, it re-signs the manifest; the trust anchor is
  preserved.
- **Never deletes or renames anything.** Files that are no longer
  in the repository are *reported*, not removed; the operator
  reviews and deletes them by hand.
- Runs the same directory and user steps, so it creates any missing
  `/home/drop` subdirectory, `Downloads`, `[sync]` default, and adds
  the conductor to `wheel` on an older installation.

**The updater verifies the GECOS markers.** Before touching
anything, it checks that every domain account carries its dropQbsd
role marker. If a marker is missing -- a foreign account, or a
pre-marker installation that was never migrated -- the updater
refuses to run. On a pre-marker system, run the migration once
first (see INSTALL_MANUAL.md 1, "Marking an existing dropQbsd
system"), or re-run the installer.

The updater records /opt/dropQbsd/VERSION. It seeds 
`/usr/local/share/xsessions/dropQbsd.desktop` if absent and
replaces `libexec/session` when changed.

Per-home stubs (.profile, .xprofile, .xinitrc, .xsession) are NOT
overwritten when the # dropQbsd-stub marker matches; they are reported
as diverged only when the shipped marker changes. To adopt the new
stub, bump the marker or merge by hand.

local.conf is operator-owned: the updater never adds [locale],
[keyboard], or [session]. Add them by hand; check_local_conf_sections
will report missing sections.

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

The updater is **not** the installer. The installer does not
overwrite `local.conf`: on a re-run the file is seeded once and left alone.

---

## 7. Where things live

| Path | Contents |
|------|----------|
| `/etc/doas.conf` (OpenBSD) / `/usr/local/etc/doas.conf` (FreeBSD) | privilege policy (one line: `permit nopass root`) |
| `/etc/dropQbsd/` | policy and configuration (`domains.conf`, `local.conf`, `schema`, `attach.conf`, `conductor.conf`, `kshrc`, ...) |
| `/home/drop/` | the drop zone (SGID, group `drop`) |
| `/opt/dropQbsd/` | scripts (`admin/`, `bin/`, `libexec/`, `sbin/`, `src/`) |
| `/opt/dropQbsd/libexec/session` | WM launcher reads [session] wm |
| `/opt/dropQbsd/templates/integrity_setup` | copy-paste integrity commands |
| `/opt/dropQbsd/VERSION` | installed version |
| `/usr/local/share/xsessions/dropQbsd.desktop` | LightDM/SDDM session entry |
| `/var/backups/dropQbsd_<ts>/` | installer backup |
| `/var/backups/dropQbsd_update_<ts>/` | updater backup |
| `/var/log/dropQbsd/` | logs (`install.log`, `update.log`) |

---

## 8. Full manual procedure

For the complete step-by-step manual install -- every command, every
file, every permission -- see
**[INSTALL_MANUAL.md](INSTALL_MANUAL.md)**.

It covers the same ground as the installer, at the level of
individual commands, and is the reference for understanding what
the installer does and for troubleshooting.
