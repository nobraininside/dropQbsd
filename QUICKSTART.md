# dropQbsd Quickstart

For dropQbsd 0.4.0. Last reviewed: 2026-11-28.

This is the **installer-based** path to a working system, not the full
manual. It gets you to immediate operability. Complete it with
[INSTALL.md](./INSTALL.md) for the post-install checks (section 4), and read
[INSTALL_MANUAL.md](./INSTALL_MANUAL.md) for a full understanding of the
system and of every step.

**How to read the blocks**

- All commands are run as **root**, except the wheel check marked
  **as your login account**.
- Use `su -` to become root. Your normal login account must be in `wheel`:
  BSD `su` to root is restricted to `wheel`, and this is what lets you open
  a terminal in your graphical session, run `su -`, and start the installer.
- **Aliases that call `admin/` are root-only.** `Gen`, `Sign`, `Pkg`,
  `Patch`, `Update` and `Upgrade` live in `/opt/dropQbsd/admin/`, mode
  `0700`: run them as root. The `sbin/` and `libexec/` aliases (`Qcp`,
  `Qfile`, `Verify`, ...) work for the conductor.
- This quickstart does **not** use `doas`. If you prefer `doas`, follow
  [INSTALL.md](./INSTALL.md).

**What this installs**

This quickstart installs the optional packages used by the dropQbsd tools.
If you want a minimal install, or want to choose packages individually,
follow [INSTALL.md](./INSTALL.md) or [INSTALL_MANUAL.md](./INSTALL_MANUAL.md)
instead.

`Xdialog` is installed in a separate step because it can block; skip it if
you do not need `Qattach`.

A browser (`qutebrowser`) is installed for Qsite. If you skip it, Qsite will
show the no-browser popup and tell you to install one with `Pkg`.

**The installer is idempotent**

If it stops, read the error, fix the reported problem, and run
`./install.sh` again. It will not duplicate users, groups, cron entries, or
configuration.

---

## Before you start

### Login account

Your login account must be in `wheel`. Check, **as your login account**:

```sh
id -Gn "$(id -un)" | tr ' ' '\n' | grep wheel
```

If it prints nothing, log in as `root` on the console (or use an admin
account already in `wheel`) and run the command for your platform, using
the login name printed by `id -un`.

OpenBSD:

```sh
usermod -G "$(id -Gn <your-login> | tr ' ' ',')",wheel <your-login>
```

FreeBSD:

```sh
pw groupmod wheel -m <your-login>
```

Log out and back in so the group change applies. Then use `su -` to become
root for the rest of this quickstart.

### Graphical session

This quickstart does not install a window manager or desktop environment.
If you do not already have a graphical session, install one **before**
running the installer.

**OpenBSD** (optional, XFCE; `xenodm` is the default display manager):

```sh
pkg_add xfce xfce-extras
rcctl enable messagebus
rcctl start messagebus
```

**FreeBSD** (optional, XFCE with LightDM):

```sh
pkg install -y xfce lightdm lightdm-gtk-greeter
sysrc dbus_enable=YES
sysrc lightdm_enable=YES
service dbus start
service lightdm start
```

When the installer has finished, set `[session] wm` in
`/etc/dropQbsd/local.conf` to the WM/DE you use -- see *Edit `local.conf`*
below. The installer seeds that file; it does not exist before the install.

**FreeBSD only: never create `~/.xsession`.** SDDM reads it and waits for it
to exit, so the graphical session freezes at login (LightDM ignores it). Use
`~/.xprofile` for LightDM/SDDM and `~/.xinitrc` for `startx`.

---

## 1. Packages

**OpenBSD**, as root -- `ksh`, `doas`, `signify`, `tmux`, `pf`, `xrandr`,
`setxkbmap` and the base window managers (`cwm`, `fvwm`, `twm`) are in the
base system:

```sh
pkg_add mc xfe nnn dzen2 xdotool yad xbindkeys password-store xclip syncthing qutebrowser
```

**FreeBSD**, as root -- `mksh` (the Korn shell every dropQbsd script runs),
`doas`, `signify`, `tmux`, `xrandr`, `setxkbmap` and all of X11 are
packages; `pf` is a kernel module. Load `pf`, then install the shell:

```sh
kldload pf 2>/dev/null || true
sysrc pf_enable=YES
pkg install -y doas mksh
```

`doas` is installed for your own use **after** the quickstart: nothing here
runs through it, and the installer replaces `doas.conf` with its own
template. Restoring your `permit :wheel` rule afterwards is covered in
*Set passwords* below.

```sh
pkg install -y mc xfe nnn tmux dzen2 xdotool yad xbindkeys password-store signify xclip syncthing xrandr setxkbmap qutebrowser
```

**`Xdialog` is a separate step, on both platforms.** It can block or
prompt, so a failure there must not abort the main package install. Skip it
if you do not need `Qattach`; `Qattach` will not work without it.

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add Xdialog` | `pkg install -y xdialog` |

---

## 2. Run the installer

As root:

```sh
cd /path/to/dropQbsd/installer
chmod +x install.sh
./install.sh --dry-run
./install.sh
```

**Warnings in the dry run are expected.** Missing users, home directories,
`examples/`, configuration files, PF tables and cron entries are created by
the real run. They are not failures.

### The integrity prompt

The installer asks:

```text
Configure script integrity with signify? (yes/no)
```

Answer **yes**. On a fresh install it asks for a passphrase three times:
twice to create the encrypted private key (`/root/dropQbsd.sec`), once to
sign the script manifest. Keep the passphrase somewhere other than this
machine. `Verify` and the cron job use only the public key and never ask for
it.

The signature covers the dropQbsd scripts and the `/etc/dropQbsd`
configuration -- not OS packages.

If a key already exists, answer **no** to *"Regenerate the key pair?"* to
keep the existing trust anchor.

---

## If the installer stops

The installer is idempotent: read the error, fix the reported problem, and
run `./install.sh` again. It does not duplicate users, groups, cron entries
or configuration.

The failure mode worth knowing: the installer can stop **after creating the
dropQbsd users but before finishing**, when an optional package is missing.
By then the restrictive firewall may already be loaded, so a plain
`pkg_add` / `pkg install` cannot reach the mirrors. Use the update path,
which opens the temporary network window itself. As root, in `ksh` or `sh`:

```sh
. /etc/dropQbsd/alias
Pkg <package>
```

Without the alias:

```sh
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/admin/pkg_tru_fwall <package>
```

Then re-run `./install.sh`.

---

## Post-install steps

### Set passwords

As root:

```sh
passwd conductor        # or the conductor name you chose
passwd userdoc
passwd usermail
passwd userweb
```

**`doas`, if you use it.** The installer replaces `/etc/doas.conf` (OpenBSD)
or `/usr/local/etc/doas.conf` (FreeBSD) with `permit nopass root`. If you
created a `permit :wheel` rule earlier, it is in the installer's backup:

- OpenBSD: `/var/backups/dropQbsd_<ts>/etc_doas.conf`
- FreeBSD: `/var/backups/dropQbsd_<ts>/usr_local_etc_doas.conf`

Re-add the rule if you want `doas` for your login account. The quickstart
itself uses `su -`, so this does not block any remaining step.

### Edit `local.conf`

As root:

```sh
vi /etc/dropQbsd/local.conf
```

**Edit the keys shown below; do not replace the whole file.** The installer
seeds `local.conf` with `[updates] mirrors`, `[mailserver]`, `[services]`,
`[sync]` and `[qmenu]`. Overwriting the file with this excerpt empties
`[updates]`, and `Pkg`, `Patch`, `Update` and `Upgrade` then have no mirror
blocks to reach.

`[network] lan` is the LAN subnet used by `userdoc` (file sharing,
Syncthing) and by any rule targeting `@lan`. Find the interface's inet.

OpenBSD:

```sh
ifconfig egress | grep inet
```

FreeBSD:

```sh
ifconfig "$(route -n get default | awk '/interface:/{print $2}')" | grep inet
```

Example:

```text
inet 192.168.1.42 netmask 0xffffff00 broadcast 192.168.1.255
```

The subnet is the network address from the IP and netmask: `192.168.1.0/24`.
Use the subnet, not your single IP.

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

Set `[locale] lang` and `[keyboard] layout` to values that exist on your
system (`locale -a`, `setxkbmap -query`).

Set `[session] wm` to the WM/DE you actually use: `startxfce4`,
`mate-session`, `cwm`, `twm`, `i3`. **A wrong value means the graphical
session will not start.** On XFCE, also set the layout in
`xfce4-keyboard-settings`: XFCE can override `setxkbmap` at session start,
while `[keyboard]` and `libexec/session` cover the other window managers.

In LightDM/SDDM, select the **dropQbsd** session. If you select the desktop
environment session (XFCE, MATE, ...), `[session] wm` is not used and the DE
starts directly; the `~/.xprofile` hook still runs.

### Regenerate the firewall

As root. `pfctl -f` empties every persistent table, so the two `update_*`
calls belong to the same operation -- they are not optional.

```sh
GEN=openbsd               # FreeBSD: GEN=freebsd

/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/admin/gen_fwall "$GEN"
pfctl -nf /etc/pf.conf && pfctl -f /etc/pf.conf
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_mailserver_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_services_table
```

`ensure_updates_table` is deliberately absent: `<updates>` is empty at rest and
is populated only by the update scripts, on entry.

### Qsite

On first start, `Qsite` looks for `~/.config/dropQbsd/sites.conf`. If it is
missing, it shows a popup with the commands:

```sh
mkdir -p ~/.config/dropQbsd
cp /opt/dropQbsd/examples/system/sites.conf.example ~/.config/dropQbsd/sites.conf
```

If no supported browser is installed, `Qsite` shows the no-browser popup.
Install one through the root package window (`Pkg` is root-only):

```sh
Pkg qutebrowser
```

---

## Next

- **Post-install checks:** [INSTALL.md](./INSTALL.md), section 4. The
  enforcers skip files younger than `GRACE_MIN=2` minutes, so the drop and
  sync tests sleep 150 seconds; `enforce_home` has no grace period and fixes
  immediately.
- **Full manual:** [INSTALL_MANUAL.md](./INSTALL_MANUAL.md).
