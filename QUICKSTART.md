# dropQbsd Quickstart

This is the **installer-based** path to a working system,
not the full manual. It gets you to immediate operability. 
Complete it with [INSTALL.md](./INSTALL.md)(post-install checks, 4)
and read [INSTALL_MANUAL.md](./INSTALL_MANUAL.md)for a full
understanding of the system and of every step.

**How to read the blocks**

- All commands are run as **root**, except the wheel check marked **as your login account**.
- Use `su -` to become root. Your normal login account must be in `wheel`: BSD `su` to root is restricted to `wheel`, and this is what lets you open a terminal in your graphical session, run `su -`, and start the installer.
- This quickstart does **not** use `doas`. If you prefer `doas`, follow [INSTALL.md](./INSTALL.md).

**What this installs**

This quickstart installs the optional packages used by the
dropQbsd tools. If you want a minimal install, or want to choose
packages individually, follow [INSTALL.md](./INSTALL.md) or
[INSTALL_MANUAL.md](./INSTALL_MANUAL.md) instead. 
`Xdialog` is installed in a separate step because it can block;
skip it if you do not need `Qattach`. 
A browser (`qutebrowser`) is installed for Qsite. If you skip it,
Qsite will show the no-browser popup and tell you to install one
with `Pkg`.

**The installer is idempotent**

If it stops, read the error, fix the reported problem, and run `./install.sh` again.
It will not duplicate users, groups, cron entries, or configuration.

------

## OpenBSD

`ksh`, `doas`, `signify`, `tmux`, `pf`, `xrandr` and the base window managers
(`cwm`, `fvwm`, `twm`) are in the base system.

### Before you start

#### Login account

Your login account must be in `wheel`. Check as your login account:

```sh
id -Gn "$(id -un)" | tr ' ' '\n' | grep wheel
```

If it prints nothing, log in as `root` on the console (or use an admin
account already in `wheel`) and run, using the login name printed by
`id -un`:

```sh
usermod -G "$(id -Gn <your-login> | tr ' ' ',')",wheel <your-login>
```

Log out and back in so the group change applies. Then use `su -` to
become root for the rest.

#### Graphical session

This quickstart does not install a window manager or desktop environment.
Set `[session] wm` in `/etc/dropQbsd/local.conf` to the WM/DE you actually
use:

    startxfce4
    mate-session
    cwm
    twm
    i3

If you want XFCE (optional), as root:

```sh
pkg_add xfce xfce-extras
rcctl enable messagebus
rcctl start messagebus
```

Then set, in `/etc/dropQbsd/local.conf`:

```ini
[session]
wm = startxfce4
```

With dropQbsd, do not create ~/.xsession with `exec startxfce4`.
The installer's ~/.xsession ends with:

```sh
exec /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/session
```

Set `[session] wm = startxfce4` in /etc/dropQbsd/local.conf.
libexec/session reads that value and execs startxfce4.

### I. Packages

As root:

```sh
pkg_add mc xfe nnn dzen2 xdotool yad xbindkeys password-store xclip syncthing qutebrowser
```

### Optional: Xdialog (may block)

As root:

```sh
pkg_add Xdialog
```

`Xdialog` can block or prompt. Install it separately so a failure does not
abort the main package install. If you do not need `Qattach`, skip it;
`Qattach` will not work without it.

### II. Installer

As root:

```sh
cd /path/to/dropQbsd/installer
chmod +x install.sh
./install.sh --dry-run
./install.sh
```

### During the install: integrity prompt

The installer asks:

    Configure script integrity with signify? (yes/no)

Answer **yes**.

On a fresh install it will ask for a passphrase three times:

- twice to create the encrypted private key (`/root/dropQbsd.sec`),
- once to sign the script manifest.

Keep the passphrase elsewhere. `Verify` and cron use only the public key
and never ask for it. The signature covers the dropQbsd scripts and
`/etc/dropQbsd` configuration, not OS packages.

If a key already exists, answer **no** to "Regenerate the key pair?"
to keep the existing trust anchor.

------

## FreeBSD

`ksh`, `doas`, `signify`, `tmux`, `xrandr` and all of X11 are packages;
`pf` is a kernel module.

### Before you start

#### Login account

Your login account must be in `wheel`. Check as your login account:

```sh
id -Gn "$(id -un)" | tr ' ' '\n' | grep wheel
```

If it prints nothing, you need root access another way: log in as `root`
on the console (or use an admin account already in `wheel`) and run,
using the login name printed by `id -un`:

```sh
pw groupmod wheel -m <your-login>
```

Log out and back in so the group change applies. Then use `su -` to
become root for the rest.


#### Graphical session

This quickstart does not install a window manager or desktop environment.
Set `[session] wm` in `/etc/dropQbsd/local.conf` to the WM/DE you actually
use:

    startxfce4
    mate-session
    cwm
    twm
    i3

If you want XFCE (optional), as root:

```sh
pkg install -y xfce lightdm lightdm-gtk-greeter
sysrc dbus_enable=YES
sysrc lightdm_enable=YES
service dbus start
service lightdm start
```

Then set, in `/etc/dropQbsd/local.conf`:

```ini
[session]
wm = startxfce4
```

On FreeBSD, never create `~/.xsession`: LightDM/SDDM use `~/.xprofile`,
`startx` uses `~/.xinitrc`. Set `[session] wm = startxfce4` in `local.conf`.

### I. Packages

As root:

```sh
kldload pf
sysrc pf_enable=YES
pkg install -y doas mksh
cat > /usr/local/etc/doas.conf <<'EOF'
permit :wheel
permit nopass root
EOF
```

`permit :wheel` is optional: it lets your login account use `doas`
outside this quickstart. The quickstart itself uses `su -`.
`permit nopass root` is the line the installer's template carries.

The installer replaces `doas.conf` with `permit nopass root`; re-add
`permit :wheel` from the backup if you want `doas` for your login.

As root:

```sh
pkg install -y mc xfe nnn tmux dzen2 xdotool yad xbindkeys password-store signify xclip syncthing xrandr setxkbmap qutebrowser
```

### Optional: Xdialog (may block)

As root:

```sh
pkg install -y xdialog
```

`xdialog` can block or prompt. Install it separately so a failure does not abort the main package install. If you do not need `Qattach`, skip it; `Qattach` will not work without it.

### II. Installer

As root:

```sh
cd /path/to/dropQbsd/installer
chmod +x install.sh
./install.sh --dry-run
./install.sh
```

### During the install: integrity prompt

The installer asks:

    Configure script integrity with signify? (yes/no)

Answer **yes**.

On a fresh install it will ask for a passphrase three times:

- twice to create the encrypted private key (`/root/dropQbsd.sec`),
- once to sign the script manifest.

Keep the passphrase elsewhere. `Verify` and cron use only the public key
and never ask for it. The signature covers the dropQbsd scripts and
`/etc/dropQbsd` configuration, not FreeBSD packages.

If a key already exists, answer **no** to "Regenerate the key pair?"
to keep the existing trust anchor.

------

## If the installer stops

The installer is idempotent. If it stops at any step, read the error,
fix the reported problem, and run `./install.sh` again. It will not
duplicate users, groups, cron entries, or configuration.

If the installer stopped **after creating the dropQbsd users because
an optional package is missing**, the firewall may already be active
and root has no direct network access. As root, in a POSIX shell:

```sh
. /etc/dropQbsd/alias
Pkg <package>
```

Then re-run `./install.sh`. Without the alias:

```sh
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/admin/pkg_tru_fwall <package>
```

------

## III. Manual steps (OpenBSD & FreeBSD)

### III.a Set passwords

The installer replaces `/etc/doas.conf` (OpenBSD) or `/usr/local/etc/doas.conf`
(FreeBSD) with `permit nopass root`. If you use `doas` for your login, re-add
your `permit :wheel` rule from the backup:

- OpenBSD: `/var/backups/dropQbsd_<ts>/etc_doas.conf`
- FreeBSD: `/var/backups/dropQbsd_<ts>/usr_local_etc_doas.conf`

The quickstart itself uses `su -`, so this does not block the remaining steps.

As root:

```sh
passwd conductor # or the conductor name you chose
passwd userdoc
passwd usermail
passwd userweb
```

### III.b Edit local.conf

`[network] lan` is the LAN subnet used by `userdoc` (file sharing, Syncthing)
and by any rule targeting `@lan`.

Find the interface's inet.

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
Set `[locale] lang` and `[keyboard] layout` to your system values:
see `locale -a` and `setxkbmap -query`.

If you use XFCE, also set the layout in `xfce4-keyboard-settings`;
XFCE can override `setxkbmap` at session start. `[keyboard]` and
`libexec/session` cover the other WMs.

Set `[session] wm` to the window manager or desktop environment you
actually use: `startxfce4`, `mate-session`, `cwm`, `twm`, `i3`, etc.
The quickstart does not install a window manager; it assumes you already
have a graphical session. A wrong value means the graphical session will
not start.

In LightDM/SDDM, select the **dropQbsd** session. If you select the
desktop environment session (e.g. XFCE), `[session] wm` is not used:
the DE starts directly. The `~/.xprofile` hook still runs.

### III.c Regenerate the firewall

As root, OpenBSD:

```sh
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/admin/gen_fwall openbsd
pfctl -nf /etc/pf.conf && pfctl -f /etc/pf.conf
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_mailserver_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_services_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/ensure_updates_table
```

As root, FreeBSD:

```sh
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/admin/gen_fwall freebsd
pfctl -nf /etc/pf.conf && pfctl -f /etc/pf.conf
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_mailserver_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/update_services_table
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/ensure_updates_table
```

### III.d Qsite

On first start, Qsite looks for `~/.config/dropQbsd/sites.conf`.
If it is missing, Qsite shows a popup with the commands:

```sh
mkdir -p ~/.config/dropQbsd
cp /opt/dropQbsd/examples/system/sites.conf.example ~/.config/dropQbsd/sites.conf
```

If no supported browser is installed, Qsite shows the no-browser
popup. Install one through the dropQbsd package window:

```sh
Pkg qutebrowser
```
------

## Next

- Post-install checks: [INSTALL.md](./INSTALL.md) 4. The enforcers
  skip files younger than `GRACE_MIN=2` minutes; the drop/sync tests
  sleep 150 seconds. `enforce_home` has no grace period and fixes 
  immediately.
- Full manual: [INSTALL_MANUAL.md](./INSTALL_MANUAL.md).