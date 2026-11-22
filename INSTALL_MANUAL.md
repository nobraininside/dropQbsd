# dropQbsd -- Installation (manual procedure)

> **This is the manual, step-by-step procedure.** For the
> recommended path -- the semi-automatic installer and updater --
> see [INSTALL.md](INSTALL.md).

This guide covers **OpenBSD** (reference platform) and **FreeBSD**.

Where the procedure is identical on both systems, it is written once. Where it
differs, a two-column table is used -- **OpenBSD on the left, FreeBSD on the
right** -- with each system's procedure under its own column.

If a section has no such table, the procedure is the same on both platforms.

**Text encoding convention.** Prose and code comments use ASCII only: `--`
for em dash, `>` for arrow. Status tables use Unicode check marks (`✅` /
`❌`) for visual scanning. The split is deliberate -- prose is copied and
typed, tables are read.

---

## Prerequisites

**Operating system:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| 7.5 or newer | 14.0 or newer |

**Core functionality.** The installer needs a Korn shell and root
access:

| Component | OpenBSD | FreeBSD |
| --------- | ------- | ------- |
| Korn shell | `ksh` in base (`/bin/ksh`) | `mksh` package (`pkg install mksh`) |
| Root access | `doas` in base (`/usr/bin/doas`) | `doas` package (`pkg install doas`), or `su` |
| Firewall | `pf` in base | `pf` kernel module + `pfctl` in base (`kldload pf`) |

On FreeBSD, `doas` is a package and reads `/usr/local/etc/doas.conf`.
Install it as root and create the file:

```sh
su -
pkg install doas
cat > /usr/local/etc/doas.conf <<'EOF'
permit :wheel
permit nopass root
EOF
exit
```

`permit :wheel` lets your admin account use `doas`; `permit nopass
root` is the line the dropQbsd template carries. The installer
replaces the file with the template; your rule is backed up in
`/var/backups/dropQbsd_<ts>/` and can be re-added afterwards. If you
prefer not to install `doas`, use `su` for the root steps.

Everything else is optional. On FreeBSD, `signify`, `tmux`, `xrandr`
and all of X11 are packages; on OpenBSD they are in base.

**Optional utilities** -- install only what you need:

| Utility | OpenBSD | FreeBSD |
| ------- | ------- | ------- |
| `indicator_de` | `dzen2`, `xdotool` | `dzen2`, `xdotool` |
| `qattach` | `Xdialog` | `xdialog` |
| `qfile` | `nnn` (`tmux` is in base) | `nnn`, `tmux` |
| `qmenu` (conductor menu) | `yad`, `xbindkeys` | `yad`, `xbindkeys` |
| `qsite` | `yad`, `password-store`, `xclip` | `yad`, `password-store`, `xclip` |
| `Syncthing` (userdoc) | `syncthing` | `syncthing` |
| Integrity verification | `signify` (base) | `signify` (package) |
| graphical session | a window manager (`cwm`, `fvwm`, `twm` are in base; `xfce`, `i3`, ... are packages) | a window manager (`xfce`, `twm`, `i3`, ... are packages) |

`xrandr` is not a utility dependency. The session files run
`xrandr --dpi 96` before the window manager starts. It is in base on
OpenBSD and `pkg install xrandr` on FreeBSD.

Install packages:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add <package>` | `pkg install <package>` |

---

## 1. Create Users and Group

### Conductor account name

The conductor is the only dropQbsd account that is rename-proof. It is
identified by its GECOS marker (`dropQbsd_conductor`), not by its name.
The default name is `conductor`; a different name may be chosen at install
time (see "Collision handling" below).

**Set the variable once at the top of this procedure.** All commands that
refer to the conductor use `$CONDUCTOR_USER`, so they work unchanged
whether the conductor is named `conductor` or anything else:

```sh
CONDUCTOR_USER="${CONDUCTOR_USER:-$(awk -F: '$5 == "dropQbsd_conductor" { print $1; exit }' /etc/passwd)}"
CONDUCTOR_USER="${CONDUCTOR_USER:-conductor}"
```

If you chose a non-default name at install time, you may skip this by
exporting the name first:

```sh
export CONDUCTOR_USER=myconductor
```

### Collision handling

If an account named `conductor` already exists at install time (a foreign
personal account, without the dropQbsd GECOS marker), the installer fails
and asks you to set a different name:

```sh
CONDUCTOR_USER=myconductor doas ./install.sh
```

Use the same name for the manual procedure: export it before running the
commands in this manual.

**The gate enforces the marker at runtime.** `run_app_impl` resolves
the `dropQbsd_conductor` GECOS marker to a uid and compares it with
the real uid the gate captured before `setuid(0)`. Exactly one account may
carry the marker; zero or more than one stops the gate (see §4).

### Procedure

Run as root:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `groupadd drop` | `pw groupadd drop` |

Then run: 

```sh
# ------------------------------------------------------------------
# The four domain users. Each is created with a dropQbsd GECOS marker
# identifying its role. If an account already exists:
#   - with the correct marker: re-use it (upgrade/re-install)
#   - WITHOUT the correct marker: refuse
# Never merge a pre-existing personal account into a domain role.
# ------------------------------------------------------------------

# add_to_group_safe: append a secondary group WITHOUT replacing the
# existing list. BOTH OpenBSD `usermod -G` and FreeBSD `pw usermod -G`
# REPLACE the secondary groups: calling them with only "drop" would
# silently drop any other membership the account already has.
add_to_group_safe() {
    local u="$1" g="$2" cur new
    cur="$(id -Gn "$u" 2>/dev/null | tr ' ' ',')"
    case ",${cur}," in
        *",${g},"*) return 0 ;;
    esac
    new="${cur:+${cur},}${g}"
    case "$(uname -s)" in
        FreeBSD) pw usermod "$u" -G "$new" ;;
        OpenBSD) usermod -G "$new" "$u" ;;
        *) echo "ERROR: unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
}

# create_one_user: the only OS-specific step.
#   FreeBSD: `pw useradd` takes the secondary group with `-G`, and `mksh` is
#            under `/usr/local/bin` (the base system has no `/bin/ksh`).
#   OpenBSD: useradd has NO `-G`, and `/bin/ksh` is in the base system, so
#            the group is added afterwards with `add_to_group_safe`.
#
# `create_one_user` creates a per-user group on both platforms:
# `pw groupadd <user>` on FreeBSD, `groupadd <user>` on OpenBSD, then
# `pw useradd -g <user>` / `useradd -g <user>`. This keeps `chown
# user:user` and `enforce_home` deterministic.
#
# `add_to_group_safe` excludes the primary group before
# `pw usermod -G`/`usermod -G`; `create_users` creates the per-user group
# even for existing accounts.
create_one_user() {
    acct="$1"; gecos="$2"
    case "$(uname -s)" in
    FreeBSD)
        if ! getent group "$acct" >/dev/null 2>&1; then
            pw groupadd "$acct"
        fi
        pw useradd "$acct" -m -g "$acct" -G drop -L "$acct" \
            -s /usr/local/bin/mksh -c "$gecos"
        ;;
    OpenBSD)
        if ! getent group "$acct" >/dev/null 2>&1; then
            groupadd "$acct"
        fi
        useradd -m -g "$acct" -L "$acct" -s /bin/ksh -c "$gecos" "$acct"
        add_to_group_safe "$acct" drop
        ;;
    *)
        echo "ERROR: unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
    esac
}

create_or_verify_domain() {
    local acct="$1" gecos="$2"
    if ! id "$acct" >/dev/null 2>&1; then
        create_one_user "$acct" "$gecos"
        echo "OK: created domain account '$acct'"
    # Exact match, and a real exit status: awk exits 0 even when no
    # line matches, so a bare '$5 ~ m' accepts any existing account.
    elif getent passwd "$acct" | awk -F: -v m="$gecos" \
        '$5 == m { found = 1 } END { exit !found }'; then
        add_to_group_safe "$acct" drop
        echo "OK: existing dropQbsd account '$acct' (upgrade/re-install)"
    else
        echo "ERROR: account '$acct' already exists and is not a dropQbsd" >&2
        echo "  '$gecos' account." >&2
        echo "  Resolve the conflict (rename/empty the account, or install" >&2
        echo "  on a dedicated system) and re-run the installer." >&2
        exit 1
    fi
}

create_or_verify_domain "$CONDUCTOR_USER" "dropQbsd_conductor"
create_or_verify_domain userdoc  "dropQbsd_userdoc"
create_or_verify_domain usermail "dropQbsd_usermail"
create_or_verify_domain userweb  "dropQbsd_userweb"
# The conductor must be able to `su -` to root: xterm_root runs
# `su -` inside the terminal, and BSD `su` to root is restricted to
# the wheel group. This is NOT a doas grant: doas.conf stays
# 'permit nopass root', and the root password is still required.
add_to_group_safe "$CONDUCTOR_USER" wheel
```

**Never merge a pre-existing account into a domain role.** A conductor
or domain account must be empty: it only directs domains, it does not
hold data (data belongs in `userdoc`). A pre-existing `$CONDUCTOR_USER` with
personal files would be a personal account wearing a conductor role: it would
hold private data inside a zero-network account that is supposed to be empty,
breaking the model. dropQbsd marks each role with a GECOS field
(`dropQbsd_conductor`, `dropQbsd_userdoc`, `dropQbsd_usermail`,
`dropQbsd_userweb`); an account without the correct marker is treated as
a foreign personal account, and the install refuses to proceed. The
`create_or_verify_domain` helper is reused by the installer and shown
here for the manual procedure; the upgrade (`update.sh`) applies the
same check and refuses to update on an unmarked system.

**Marking an existing dropQbsd system.** Systems installed from a version
before the GECOS marker was introduced do not carry it. To mark an
existing, working dropQbsd installation, run once as root:

```sh
usermod -c "dropQbsd_conductor"  "$CONDUCTOR_USER"
usermod -c "dropQbsd_userdoc"    userdoc
usermod -c "dropQbsd_usermail"   usermail
usermod -c "dropQbsd_userweb"    userweb
```

`usermod -c` changes only the GECOS field; it does not touch UID, home,
groups, or data, and can be run with the users logged in. Verify with
`getent passwd "$CONDUCTOR_USER" userdoc usermail userweb` -- each line must show its marker in the fifth field.

### Root access and `wheel`

The conductor is added to `wheel` so `Xtroot` can run `su -`. If your
login account is not in `wheel`, `su -` will fail. Log in as `root` on
the console (or use an admin account already in `wheel`) and run:

- FreeBSD: `pw groupmod wheel -m <login>`
- OpenBSD: `usermod -G "$(id -Gn <login> | tr ' ' ',')",wheel <login>`

Log out and back in so the group change applies.

### Resource Limits

Append these classes to `/etc/login.conf` to prevent resource exhaustion under
heavy load. `userdoc` needs high open files for Syncthing; `usermail` needs
extra memory and file descriptors for compressing large mail archives (40+ GB);
`userweb` gets generous limits for multiple browser tabs and disposable tmpfs
sessions.

```sh
userdoc:\
    :openfiles-cur=32768:\
    :openfiles-max=32768:\
    :tc=daemon:

usermail:\
    :openfiles-cur=32768:\
    :openfiles-max=32768:\
    :datasize-cur=2048M:\
    :datasize-max=4096M:\
    :memoryuse=2048M:\
    :vmemoryuse=4096M:\
    :stacksize-cur=128M:\
    :stacksize-max=128M:\
    :memorylocked-max=256M:\
    :maxproc-cur=256:\
    :maxproc-max=512:\
    :tc=default:

userweb:\
    :openfiles-cur=8192:\
    :openfiles-max=16384:\
    :datasize-cur=1024M:\
    :datasize-max=2048M:\
    :memoryuse=1024M:\
    :vmemoryuse=2048M:\
    :maxproc-cur=256:\
    :maxproc-max=512:\
    :tc=default:

conductor:\
    :openfiles-cur=4096:\
    :openfiles-max=8192:\
    :datasize-cur=512M:\
    :datasize-max=1G:\
    :stacksize-cur=8M:\
    :stacksize-max=64M:\
    :memoryuse-cur=512M:\
    :memoryuse-max=1G:\
    :tc=default:
```
**The class name follows the conductor account name**

For the class to apply, `create_one_user` must pass `-L <account>` to
`pw useradd` (FreeBSD) or `useradd` (OpenBSD). Without `-L`, the account
uses the `default` class and these limits are not enforced.

The `login.conf_append` block names the conductor class `conductor`.
If `CONDUCTOR_USER` is renamed, generate the class with the same name,
or the account will fall back to `default`.

Rebuild the login database:

```sh
cap_mkdb /etc/login.conf
```

---

## 2. Create Directory Structure

Run as root:

```sh
mkdir -p /opt/dropQbsd/{admin,bin,keys,libexec,sbin,src,templates,examples}
mkdir -p /home/drop/userweb_export
mkdir -p /home/drop/usermail_export
mkdir -p /home/drop/_quarantine

chown root:drop /home/drop /home/drop/userweb_export /home/drop/usermail_export
chmod 2770 /home/drop
chmod 2770 /home/drop/userweb_export /home/drop/usermail_export
chmod 750 /home/drop/_quarantine
chown root:wheel /home/drop/_quarantine
chmod 700 /opt/dropQbsd/keys
# Default [sync] directories and Downloads in every domain home.
for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
    h="$(awk -F: -v u="$u" '$1 == u {print $6; exit}' /etc/passwd)"
    [ -n "$h" ] && [ -d "$h" ] || continue
    mkdir -p "$h/.cache/dropqbsd"
    chown -R "$u":"$u" "$h/.cache"
    chmod 700 "$h/.cache" "$h/.cache/dropqbsd"
done
mkdir -p /home/userweb/www /home/usermail/.mail /home/userdoc/Sync
chown userweb:userweb /home/userweb/www
chown usermail:usermail /home/usermail/.mail
chown userdoc:userdoc /home/userdoc/Sync
chmod 700 /home/userweb/www /home/usermail/.mail
chmod 2700 /home/userdoc/Sync
# Qsite cache directory: pre-create it as the user so a root-run
# Qsite cannot leave it root:wheel.
for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
   h="$(awk -F: -v u="$u" '$1 == u {print $6; exit}' /etc/passwd)"
   [ -n "$h" ] && [ -d "$h" ] || continue
   mkdir -p "$h/.cache/dropqbsd"
   chown -R "$u":"$u" "$h/.cache"
   chmod 700 "$h/.cache" "$h/.cache/dropqbsd"
done 
```

The `2770` mode (SGID) on `/home/drop` forces the `drop` group on all files
placed there -- this is what makes the drop zone policed by construction rather
than by convention.

`~/.cache/dropqbsd` is created as `user:user 700`; this is where `Qsite`
writes `qsite.err`, `qsite_cache`, and `qsite_state`.

---

## 3. Install Scripts

Copy the repository contents to `/opt/dropQbsd/`:

```sh
mkdir -p /opt/dropQbsd/bin
cp -r admin libexec sbin src templates examples /opt/dropQbsd/
```

Set ownership and permissions:

```sh
chown -R root:wheel /opt/dropQbsd
chmod 755 /opt/dropQbsd/bin/*
chmod 755 /opt/dropQbsd/sbin/*
chmod 755 /opt/dropQbsd/libexec/*
chmod 700 /opt/dropQbsd/libexec/run_app_impl
chmod 700 /opt/dropQbsd/admin/*
```

**Create the log directory.** Every dropQbsd script writes to
`/var/log/dropQbsd/`; the directory must exist before the first
cron cycle, with permissions that keep the logs private to root:

```sh
mkdir -p /var/log/dropQbsd
chown root:wheel /var/log/dropQbsd
chmod 750 /var/log/dropQbsd
```

The directory starts empty. Each log file appears the first time
its script runs -- the enforcers and `verify_integrity` via cron
within minutes, `ensure_updates_table` and the update logs on
first use of the corresponding alias.

**Note:** scripts in `sbin/` and `libexec/` carry **no shebang**. They are
executed through `libexec/wrapper`, which selects the correct shell for the
platform. Do not add shebangs -- it would break portability.

### 3.1 Session entry

```sh
mkdir -p /usr/local/share/xsessions
cp templates/dropQbsd.desktop /usr/local/share/xsessions/dropQbsd.desktop
chown root:wheel /usr/local/share/xsessions/dropQbsd.desktop
chmod 644 /usr/local/share/xsessions/dropQbsd.desktop
```

`libexec/session` is copied by `cp -r libexec`; the existing
`chmod 755 /opt/dropQbsd/libexec/*` sets it executable.
```

---

## 4. Build the `run_app` gate

This is the core of dropQbsd's privilege model. `run_app` is split into
three files:

| File | Purpose |
| ---- | ------- |
| `src/run_app.c` | C source -- compiled once |
| `bin/run_app` | Compiled setuid binary -- the immutable gate the conductor invokes |
| `libexec/run_app_impl` | Script -- all the logic, editable without recompilation |

**Conductor actions.** `run_app` can invoke named actions from
`sbin/`, allowed by `/etc/dropQbsd/conductor.conf`. Each receives
its argument plus the resolved display and X11 cookie. The only
shipped action is `qattach`.

**The invoker check.** `run_app_impl` refuses any invoker that is not the conductor:
the gate passes the caller's real uid (captured before `setuid(0)`) as the first argument,
and `run_app_impl` compares it with the uid resolved from the `dropQbsd_conductor`
GECOS marker. No marker, no gate -- the installer and updater enforce the same rule.

The `wrapper` (`libexec/wrapper`) is a separate component: it selects
the Korn shell and sanitizes the environment for every dropQbsd script.
It is not part of the `run_app` chain.

### Build with the helper script (recommended)

```sh
/opt/dropQbsd/admin/build_run_app
```

This script:

1. Compiles `src/run_app.c` with `cc -static`;
2. Sets ownership to `root:wheel`;
3. Sets mode to `4755` (the setuid bit).

**Why use it instead of compiling by hand:** every compilation creates
a *new* file, and a new file has the compiler's default mode -- the
setuid bit is lost. Forgetting `chmod 4755` produces a binary that
looks correct but fails at runtime with:

```sh
dropQbsd: setuid(0) failed: Operation not permitted
```

`build_run_app` re-applies ownership and mode on every run, so the
step cannot be forgotten.

### Build by hand (equivalent)

```sh
cc -static -o /opt/dropQbsd/bin/run_app /opt/dropQbsd/src/run_app.c
chown root:wheel /opt/dropQbsd/bin/run_app
chmod 4755 /opt/dropQbsd/bin/run_app
```

### The `-static` flag is mandatory

A dynamically linked setuid binary is exposed to `LD_PRELOAD`-style
injection before `main()` runs. The static build removes that class
of attack entirely -- the kernel's setuid protections are a second
line of defence, not the first.

Verify the result is static:

```sh
readelf -d /opt/dropQbsd/bin/run_app | grep NEEDED
```
No output means no dynamic dependencies: the binary is static.

### Verify

```sh
ls -l /opt/dropQbsd/bin/run_app
```

The mode must show `-rwsr-xr-x` -- the `s` is the setuid bit. Without
It, the gate does not escalate and domain applications will not launch.
`run_app_impl` must be `0700 root:wheel`: no local user executes it
directly; only the gate, as root, does.

---

## 5. Install System Configuration Files

dropQbsd relies on a single, coherent environment across all users.
Everything lives under /etc/dropQbsd/; the files in the home
directories are two-line stubs that point to the single entry point.

### 5.1 Back up conflicting dotfiles

Before installing, back up any local dotfiles that would override
the system-wide configuration. Run as root:

```sh
ts=$(date +%Y%m%d_%H%M%S)
for h in /root "/home/$CONDUCTOR_USER" /home/userdoc /home/usermail /home/userweb; do
    for f in .profile .shrc .kshrc .xsession .xinitrc .cshrc .login .xprofile; do
        [ -f "$h/$f" ] && mv "$h/$f" "$h/$f.bak.$ts"
    done
done
```

### 5.2 Global configuration (all logic lives here)

```sh
mkdir -p /etc/dropQbsd
chmod 755 /etc/dropQbsd
cp templates/profile_for_etc  /etc/dropQbsd/profile
cp templates/kshrc_for_etc    /etc/dropQbsd/kshrc
cp templates/alias_for_etc    /etc/dropQbsd/alias
cp templates/conductor.conf_for_etc /etc/dropQbsd/conductor.conf
cp templates/attach.conf_for_etc    /etc/dropQbsd/attach.conf
chown root:wheel /etc/dropQbsd/profile /etc/dropQbsd/kshrc /etc/dropQbsd/alias /etc/dropQbsd/conductor.conf /etc/dropQbsd/attach.conf
chmod 644        /etc/dropQbsd/profile /etc/dropQbsd/kshrc /etc/dropQbsd/alias /etc/dropQbsd/conductor.conf /etc/dropQbsd/attach.conf
```

### 5.3 Per-user stubs (pointers only)

The stubs are one-line pointers to `/etc/dropQbsd/kshrc`. Which ones to
install depends on the platform:

| File | OpenBSD | FreeBSD |
| ---- | ------- | ------- |
| `~/.profile`  | **always** (login shells: tty, su -, ssh) | **always** |
| `~/.xprofile` | **yes** (SDDM / LightDM, if used) | **yes** (SDDM) |
| `~/.xsession` | **yes** (xenodm, the default DM) | **NO** -- see warning below |
| `~/.xinitrc`  | only if you use `startx` instead of xenodm | **yes** (startx) |

**WARNING -- never install `~/.xsession` on FreeBSD.** SDDM reads
`~/.xsession` and waits for it to exit; the `exec startxfce4`
line never returns, so the graphical session freezes at login.
On FreeBSD use `~/.xprofile` (for SDDM) or `~/.xinitrc` (for
`startx`).

**Install (OpenBSD):**

```sh
for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
    cp templates/profile_for_home  /home/$u/.profile
    cp templates/xprofile_for_home /home/$u/.xprofile
    cp templates/xsession_for_home /home/$u/.xsession
    chown $u:$u /home/$u/.profile /home/$u/.xprofile /home/$u/.xsession
    chmod 644   /home/$u/.profile /home/$u/.xprofile /home/$u/.xsession
done

# root
for f in profile xprofile xsession; do
    cp templates/${f}_for_home /root/.$f
    chown root:wheel /root/.$f
    chmod 644 /root/.$f
done
```

**Install (FreeBSD):**

```sh
for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
    cp templates/profile_for_home  /home/$u/.profile
    cp templates/xprofile_for_home /home/$u/.xprofile
    cp templates/xinitrc_for_home  /home/$u/.xinitrc
    chown $u:$u /home/$u/.profile /home/$u/.xprofile /home/$u/.xinitrc
    chmod 644   /home/$u/.profile /home/$u/.xprofile /home/$u/.xinitrc
done

# root
for f in profile xprofile xinitrc; do
    cp templates/${f}_for_home /root/.$f
    chown root:wheel /root/.$f
    chmod 644 /root/.$f
done
```

**Coverage map:**

| Session type | File read | OpenBSD | FreeBSD |
|---|---|---|---|
| Text login (`tty`) | `~/.profile` | yes | yes |
| `su -` / `ssh` | `~/.profile` | yes | yes |
| xenodm | `~/.xsession` | yes | n/a |
| LightDM | `~/.profile` + `~/.xprofile` | if used | yes |
| SDDM (DE session) | `~/.xprofile` | if used | yes |
| SDDM “User Session” | `~/.xinitrc` | n/a | yes |
| `startx` | `~/.xinitrc` | if used | yes |
| Terminal in session | `$ENV` | yes | yes |


On OpenBSD/xenodm, do not create ~/.xsession with `exec startxfce4`.
The installer's ~/.xsession ends with:

```sh
exec /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/session
```

Set `[session] wm = startxfce4` in /etc/dropQbsd/local.conf.
libexec/session reads that value and execs startxfce4.

On FreeBSD, ~/.xsession is never installed; use ~/.xprofile and ~/.xinitrc.

`$ENV` is set by `/etc/dropQbsd/kshrc` itself, so every interactive
child shell sources the chain automatically.

Each stub starts with a marker line, `# dropQbsd-stub: <version>`.
The updater compares the `# dropQbsd-stub` marker, not the bytes. The
stubs may contain operator additions; the WM is no longer in the stub:
it is `[session] wm` in `/etc/dropQbsd/local.conf`. When you
change the project-owned part of a stub, update its marker -- that is
what tells an existing installation the shipped version has moved on.

LightDM sources `~/.profile` and `~/.xprofile` before the session.
startx and xenodm do not read `~/.xprofile`; they use `~/.xinitrc`
and `~/.xsession`. `libexec/session` sources `~/.xprofile` as a hook,
so the indicator/xbindkeys also start when the DM does not source it.

**The domain indicator is started from all three session files**
(`~/.xprofile`, `~/.xsession`, `~/.xinitrc`). Whichever one the
session manager reads, the indicator starts. If more than one is
read in the same session, the indicator's uid-keyed lock prevents a
double start -- the second instance finds the lock and exits.

The conductor's `~/.xbindkeysrc` is not a stub: see 5.4.

**No modification to /etc/profile is required.**


### 5.4 The conductor menu hotkey

`xbindkeys` is started only by the conductor (`$CONDUCTOR_USER`): the
session files guard it with `if [ "$(id -un)" = "$CONDUCTOR_USER" ]`, and
start one instance per session. Domains never run `xbindkeys` and cannot
launch the conductor menu.

Its configuration, `~/.xbindkeysrc`, maps **`Mod4+q`** to the `qmenu`
launcher. The file is **operator-owned**: created if absent, never
overwritten, and reported by an update if the shipped version differs.
It is not part of the integrity filelist. (Unlike `local.conf`, which is
never written at all.)

**`Mod4` is the Super key, and where that key sits depends on the
keyboard:**

- **PC keyboard** -- the key with the Windows logo, two positions to the
  left of the space bar.
- **Apple keyboard** -- **Command**, immediately left of the space bar,
  where a PC keyboard has Alt. The Apple key sitting where a PC has the
  Windows key is **Option**, and X reports it as `Alt` (Mod1).

On a Mac keyboard, then, the key *next to the space bar* opens the menu
while the key a PC user would reach for as "Super" does nothing. That is
not a dropQbsd configuration issue: it is where the two vendors put the
modifier.

**A hotkey that does nothing is usually the wrong key, not the wrong
configuration.** Check the key before the file:

```sh
xbindkeys -k         # press the combination: prints the modifier mask
xev -event keyboard  # press one key: prints keysym and keycode
```

`Mod4` is mask `0x40`; `Alt`/Option is Mod1, `0x08`. A key that reports
`Alt_L` will never trigger `Mod4+q`.

### 5.5 Adjust the desktop launcher

The last line of `~/.xinitrc` and `~/.xsession` is:

```sh
exec /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/libexec/session
```

The WM is not hardcoded there. Set `[session] wm` in
`/etc/dropQbsd/local.conf`; `libexec/session` reads that value. This is
the same on OpenBSD and FreeBSD.

### 5.6 Xdialog theme (GTK2)

Each domain home that runs pickers gets a `~/.gtkrc-2.0`, so
Xdialog dialogs in `Qattach` show the per-domain colour:

userdoc  -> copy examples/apps/gtk/gtkrc.userdoc.rc  -> ~userdoc/.gtkrc-2.0
usermail -> copy examples/apps/gtk/gtkrc.usermail.rc -> ~usermail/.gtkrc-2.0
userweb  -> copy examples/apps/gtk/gtkrc.userweb.rc  -> ~userweb/.gtkrc-2.0

Install only if absent; never overwrite.

```sh
install_domain_theme() {
    d="$1"; src="examples/apps/gtk/gtkrc.$d"; dst="/home/$d/.gtkrc-2.0"
    [ -f "$src" ] || return
    [ -e "$dst" ] && { echo "exists: $dst"; return; }
    cp "$src" "$dst"
    chown "$d" "$dst"
    chmod 644 "$dst"
}
```
---

## 6. Create the dropQbsd Configuration Directory

dropQbsd uses a **declarative firewall policy** instead of a hand-written
`pf.conf`. These files describe your security posture -- the policy (`domains.conf`),
your site configuration (`local.conf`), and the interfaces that constrain what the
project ships.

| File | Purpose | Source |
| ---- | ------- | ------ |
| `attach.conf` | qattach direction matrix (SRC:DST per line) | `templates/attach.conf_for_etc` |
| `conductor.conf` | Conductor actions the gate may run as root | `templates/conductor.conf_for_etc` |
| `domains.conf` | Portable policy (identical on every install) | `templates/domains.conf_for_etc` |
| `/etc/doas.conf` (OpenBSD) / `/usr/local/etc/doas.conf` (FreeBSD) | Privilege-escalation policy (one line: `permit nopass root`) | `templates/doas.conf_for_etc` || `local.conf` | Your local config (subnet, mail, services) | `examples/system/local.conf.example` |
| `schema` | Valid domains for this product | `templates/schema_for_etc` |

`schema` is consumed by `gen_fwall`; `run_app_impl` carries the same three names in `is_domain()`.
Adding a domain means editing both.

Run as root:

```sh
cp templates/attach.conf_for_etc    /etc/dropQbsd/attach.conf
cp templates/conductor.conf_for_etc /etc/dropQbsd/conductor.conf
cp templates/domains.conf_for_etc /etc/dropQbsd/domains.conf
cp templates/schema_for_etc /etc/dropQbsd/schema
cp examples/system/local.conf.example /etc/dropQbsd/local.conf

chmod 644 /etc/dropQbsd/attach.conf /etc/dropQbsd/conductor.conf /etc/dropQbsd/domains.conf /etc/dropQbsd/schema /etc/dropQbsd/local.conf
chown root:wheel /etc/dropQbsd/attach.conf /etc/dropQbsd/conductor.conf /etc/dropQbsd/domains.conf /etc/dropQbsd/schema /etc/dropQbsd/local.conf

# Directory mode is enforced here too, for parity with 5.2
# (idempotent; harmless if already correct).
chmod 755 /etc/dropQbsd

# DOAS_CONF is OS-specific: /etc/doas.conf on OpenBSD,
# /usr/local/etc/doas.conf on FreeBSD.
case "$(uname -s)" in
FreeBSD) DOAS_CONF="/usr/local/etc/doas.conf" ;;
*)       DOAS_CONF="/etc/doas.conf" ;;
esac
export DOAS_CONF
cp templates/doas.conf_for_etc "$DOAS_CONF"
chown root:wheel "$DOAS_CONF"
chmod 644 "$DOAS_CONF"
```

The template is `permit nopass root`. It replaces the `permit :wheel`
rule created in Prerequisites. The installer/updater backs the old
file up; re-add your rule from the backup if you need `doas` after
the install.

### Edit local.conf

Open `/etc/dropQbsd/local.conf` and fill in your values. The file is heavily
commented -- read it carefully. Summary of the sections:

- **`[network] lan`** -- your LAN subnet (REQUIRED). Used by `userdoc` and by
  any rule targeting `@lan`.
- **`[updates] mirrors`** -- Fastly CDN blocks for OpenBSD mirrors. Do not edit
  unless the mirror provider changes.
- **`[mailserver] hosts`** -- your mail server hostnames (optional). Resolved
  via `userweb` DNS by `update_mailserver_table`.
- **`[services] hosts`** -- external services `userweb` must reach beyond ports
  80/443 (optional). Static IPs written as-is; hostnames prefixed with `@`.
- **`[extra.*] allow`** -- your personal exceptions (optional). You may only
  **add** `allow` rules here; the base security posture in `domains.conf` is
  not modifiable.
- **`[sync]`** (archive directories):
	- `dst`      -- import destination (default `/home/userdoc/Sync`)
	- `www_src`  -- web export source (default `/home/userweb/www`)
	- `mail_src` -- mail export source (default `/home/usermail/.mail`)
  **`[sync]` directory behavior.** The import destination (`dst`) is created
  automatically if missing. The export sources (`www_src`, `mail_src`) are
  NOT created: a missing export source is a hard error for the export scripts
  (there is no data to export). Create the export directories yourself -- or
  let the application (browser, mail client) create them on first use:
```sh
  mkdir -p /home/userweb/www
  mkdir -p /home/usermail/.mail
```
- **`[locale]`** and **`[keyboard]`** are read by `templates/profile_for_etc`;
  **`[session]`** wm is parsed by `profile_for_etc` into `DROPQBSD_WM`, and
  `libexec/session` execs that value.
  Set `lang` and `layout` to values that exist on the system (`locale -a`,
  `setxkbmap -query`). In LightDM/SDDM select the `dropQbsd` session; if
  you select the DE session, `[session] wm` is not used. On XFCE, also set
  the layout in `xfce4-keyboard-settings`.
- `[qmenu]` is read by `Qmenu`. Modify the default menu as needed, adding
  or removing entries. Add missing programs with Pkg <program> or remove
  the corresponding entry. 

`gen_fwall` reads only `[network]`, `[mailserver]`, `[services]`,
`[updates]`, and `[extra.*]`. `[locale]`, `[keyboard]`, and `[session]`
do not affect the firewall.

**Do not edit `domains.conf`.** It is the portable policy, identical on every
installation. Personal needs go in `[extra.*]` sections of `local.conf`.

#### Example `local.conf`

```ini
# Network: REQUIRED. The LAN subnet (not your single IP).
[network]
lan = 192.168.1.0/24

# Mirror blocks for updates (do not edit unless the provider changes).
[updates]
mirrors = ...

# Mail servers for the <mailserver> table (optional).
[mailserver]
hosts = mx.example.com

# External services for userweb beyond ports 80/443 (optional).
# Static IPs are written as-is; hostnames are prefixed with @
# (resolved via userweb DNS).
[services]
hosts = 198.51.100.10 @myhost.xyz

# Archive directories (optional; defaults shown).
[sync]
dst      = /home/userdoc/Sync
www_src  = /home/userweb/www
mail_src = /home/usermail/.mail

# Operator's exceptions (optional). You may ONLY add allow rules.
# Format: tcp:PORT@lan, tcp:PORT@internet, udp:PORT@any, ...
[extra.myexception]
allow = tcp:8443@lan

[locale]
lang = en_US.UTF-8

[keyboard]
layout = us

[session]
wm = startxfce4

# Conductor menu entries (read by qmenu, ignored by gen_fwall).
[qmenu]
CONDUCTOR
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/qsite | Qsite
...

### How PF Tables Work

dropQbsd uses three PF tables to manage network access without exposing
provider IPs in the firewall rules:

| Table | Config source | Update script | Purpose |
| ----- | ------------- | ------------- | ------- |
| `<mailserver>` | `[mailserver] hosts` | `update_mailserver_table` | Mail server IPs for `usermail` |
| `<services>` | `[services] hosts` | `update_services_table` | External services for `userweb` |
| `<updates>` | `[updates] mirrors` | `ensure_updates_table` | Mirror IPs for system updates |

All three scripts read from `local.conf`. There is no separate table
configuration file.

**Adding a hostname (resolved automatically):** add it to `[services]` in
`local.conf`, prefixed with `@`:

```
[services]
hosts = 198.51.100.10 @myhost.xyz
```

Hostnames prefixed with `@` are resolved via `userweb` DNS each time the
table-update script runs. All three table scripts run **every 15 minutes via
cron**, so IPs stay current without manual intervention. A `pfctl -f` reload
empties every persistent table; the cron repopulates them within 15 minutes,
so run `Gen` + `pfctl -f` and let the cron refill the tables — or repopulate
them by hand (see §7) if you need mail/web back before the next cycle.

---

## 7. Generate the Firewall

Instead of copying a static `pf.conf`, generate it from the policy:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `Gen openbsd` | `Gen freebsd` |

This reads `domains.conf`, `local.conf`, and `schema` from `/etc/dropQbsd/` and
writes `/etc/pf.conf`.

**Verify syntax (without applying):**

```sh
pfctl -nf /etc/pf.conf
```

`pfctl -nf` checks the syntax **without** loading the rules. If it reports
errors, fix your policy files and regenerate. Do not apply a broken ruleset -- a
firewall that fails to load leaves you without protection.

**Apply:**

```sh
pfctl -f /etc/pf.conf
```

**Populate the PF tables:**

```sh
Upmailserver
Upservices
Enupdates
```

These scripts read from `local.conf`, resolve hostnames via `userweb` DNS, and
populate the tables. Root never touches the network directly.

**Ordering:** `gen_fwall` emits the table definitions (`table <mailserver>
persist`, etc.) into `pf.conf`, so the tables exist -- empty -- when `pfctl -f`
loads the ruleset. The `update_*` scripts then fill them. The order (generate >
verify > apply > populate) is intentional.

**Regenerating after policy changes:** any time you edit `domains.conf` or
`local.conf`:

```sh
Gen openbsd
pfctl -nf /etc/pf.conf
pfctl -f /etc/pf.conf
```

The firewall is always derived from the policy. There is no hand-written
`pf.conf` to keep in sync.

**Backup.** Each `Gen` run backs up the previous valid `/etc/pf.conf` to
`/etc/pf.conf.bak.<timestamp>` before replacing it, but only if the current
ruleset passes `pfctl -nf`. A corrupted ruleset is never preserved as a
restore point. To restore after a bad generation:

```sh
cp /etc/pf.conf.bak.<timestamp> /etc/pf.conf
pfctl -f /etc/pf.conf
```

**Unknown sections.** `gen_fwall` ignores sections of `local.conf` it does
not use (e.g. `[qmenu]`). Adding a config-only section never requires a
`gen_fwall` change; only a section that must produce firewall rules does.

---

## 8. Configure Cron

All cron jobs run as root. Jobs that need to act on behalf of a domain user use
`su -l <user> -c` to switch to that user's environment. There is no per-user
crontab -- everything is managed centrally in root's crontab for auditability.

### Merge the crontab entries

`examples/system/crontab.example` contains the dropQbsd entries to **add** to
root's existing crontab. The merge is idempotent -- every dropQbsd line contains
the string `dropQbsd`:

```sh
crontab -l | grep -v dropQbsd > /tmp/crontab.merge
cat examples/system/crontab.example >> /tmp/crontab.merge
crontab /tmp/crontab.merge
rm /tmp/crontab.merge
```

Verify:

```sh
crontab -l | grep dropQbsd
```

**NOTE:** `crontab(1)` **replaces** the whole table -- it does not append. Never
paste into `crontab -e` over pre-existing entries unless you edit in place.

### Jobs NOT in the crontab (by design)

**`<updates>` table lifecycle.** All three table scripts (`ensure_updates_table`,
`update_mailserver_table`, `update_services_table`) run **every 15 minutes via cron**.
On top of that, the update scripts (`patch_tru_fwall`, `pkg_tru_fwall`, `update_tru_fwall`,
`upgrade_tru_fwall`) repopulate `<updates>` on entry (before opening the network window)
and -- by default (`FLUSH_ON_EXIT=1`) -- **flush it on exit**, so the table is **empty at rest**:
the mirror IPs are only reachable while an update is actually running (least privilege).
`<mailserver>` and `<services>` are NOT flushed by the update scripts: they are repopulated
after any `pfctl -f` and remain populated for daily mail/web use. After a `pfctl -f` reload,
all three tables are repopulated by the `*/15` cron (or by hand, see 7).

The list of jobs NOT in the crontab is therefore: **`root_snapshot`** (on demand, from
`qcontrol`, press `a`).

### Export/import race safety (by construction)

All export scripts publish archives atomically: they write a `*.tar.gz.tmp`
file inside the drop zone and rename it when complete. Import scripts only ever
match `*.tar.gz`. A partial archive is therefore invisible to imports.

If an export runs long, that slot's import finds nothing and exits 0; the next
run imports the complete archive. **This is expected behavior, not a failure.**

Orphaned `.tmp` files are removed by the exporters' own rotation (6 hours).

**Do not widen the import globs or remove the `.tmp` step** -- this is a
load-bearing convention across all four export/import scripts.

### Lock files

The enforcers that can overlap use an atomic `mkdir` lock to prevent concurrent runs
(`enforce_drop` and `enforce_sync`; `enforce_home` is a simple stat + fix and takes
no lock). The lock directories live in `/var/run/` and are cleared on reboot.

The enforcers' locks carry a TTL (15 min: `LOCK_TTL=900`). A slow
cycle on a large Sync tree can take minutes; the TTL is a guard
against an orphaned lock, not a performance target. If a lock is
older than the TTL and the owning process is still alive, the next
run reclaims it; investigate the process before doing it by hand.

### Enforcer rules

1. **No silent exits.** An enforcer may exit silently ONLY when there is
   nothing to do, or when another instance holds the lock. Where a lock
   is used (`enforce_drop`, `enforce_sync`), it is acquired via atomic `mkdir`
   with a TTL: an orphaned lock (owner killed mid-cycle) is reclaimed by age
   instead of blocking every future run forever. The TTL is deliberately
   generous -- a cycle takes seconds, so a lock older than a few minutes is
   garbage, never a running cycle.

2. **Count what you fix, fix what you count.** Every fix command uses the same
   filter as its counter, so no action can happen without its log line (and
   vice versa).

3. **Numeric identity in integer tests.** stat(1) `-f %g` and
   `-f %u` return the NUMERIC gid/uid on both OpenBSD and FreeBSD.
   Integer comparisons (`-ne`) therefore work directly on the
   values. Do NOT use `%G`/`%U`: on OpenBSD `%G` is a strftime
   date format, and on FreeBSD `%U` is not defined at all.

4. **Skips must own their names.** An enforcer may exempt only items the
   system itself creates (`_quarantine`, `*_export`). No hardcoded filenames.

---

## 9. Verification Checklist

After installation, verify each domain can perform its function:

- `conductor`: can `Qmv`/`Qcp`/`Qimport` files, can `Run` into domains
- `userdoc`: access LAN storage, Syncthing syncs, cannot reach internet
- `usermail`: send/receive email, cannot browse the web
- `userweb`: browse the web, cannot reach LAN IPs
- `Endrop` running in cron -- verify via the runbook below (lock-watch test), an empty log is normal
- `Enhome` running in cron -- verify via the runbook below (lock-watch test), an empty log is normal
- `Ensync` running in cron -- verify via the runbook below (lock-watch test), an empty log is normal
- `Qcontrol` shows domain status and drop zone contents
- `Qattach` opens the picker and imports into the destination's Downloads (requires Xdialog)
- `Upmailserver` populates `<mailserver>` table
- `Upservices` populates `<services>` table

### Verifying the enforcers (runbook)

Each test exercises one branch. Expected output is shown after each command.
All drop-zone test files age out on their own (30 min); remove Sync test files
manually.

The enforcers skip files younger than `GRACE_MIN=2` minutes.
`enforce_home` has no grace period and fixes immediately.
`enforce_drop`/`enforce_sync` need `sleep 150` after creating the test
file. If a manual run exits immediately, cron holds the lock; wait for
`/var/run/enforce_drop.lock` or `/var/run/enforce_sync.lock` to
disappear and retry.

**What the enforce_drop tests exercise.** The three cases are distinct:
- a file with an **old mtime** is deleted as `abandoned` at the first
  cycle, before any mode/GID check;
- a **young** file with the wrong mode is fixed (`chmod 440`/`570`);
- a **young** file with the wrong GID is quarantined, whatever its mode.
Use `touch` to reset the mtime; otherwise the file is treated as stale
and never reaches the mode or GID branch.

```sh
# --- enforce_drop: cron is running (watch for ~1 minute) ------
while true; do
    ls -d /var/run/enforce_drop.lock 2>/dev/null && break
    sleep 1
done && echo "OK: cycle observed"
```

```sh
# --- enforce_drop: permission enforcement (wait > 2 min) ------
touch /home/drop/t_perm.txt
chmod 600 /home/drop/t_perm.txt
chgrp drop /home/drop/t_perm.txt
sleep 150
stat -f '%Mp%Lp %N' /home/drop/t_perm.txt
# 0440 /home/drop/t_perm.txt
tail -1 /var/log/dropQbsd/enforce_drop.log
# abandoned=0 quarantined=0 perms_fixed=1
```

```sh
# --- enforce_drop: quarantine (non-root, wrong GID) ------------
touch /home/drop/t_quar.txt
chown userdoc:wheel /home/drop/t_quar.txt
sleep 150
ls /home/drop/_quarantine/
# t_quar.txt_<pid>   t_quar.txt_<pid>.txt
# The ticket must show NUMERIC gid/uid (Expected GID: <n>).
```

```sh
# --- enforce_drop: atomic publish is untouchable ---------------
touch /home/drop/userweb_export/www_t.tar.gz.tmp
chmod 600 /home/drop/userweb_export/www_t.tar.gz.tmp
sleep 150
stat -f '%Mp%Lp %N' /home/drop/userweb_export/www_t.tar.gz.tmp
# 0600 ... -- must NOT be 440. Remove it manually afterwards.
```

```sh
# --- enforce_home: cron is running (watch for ~1 minute) ------
while true; do
    tail -1 /var/log/dropQbsd/enforce_home.log 2>/dev/null | grep -q "cycle complete" && break
    sleep 1
done && echo "OK: cycle observed"
```

```sh
# --- enforce_home: home mode enforcement (wait > 2 min) --------
chmod 755 /home/userdoc
sleep 150
stat -f '%Lp %N' /home/userdoc
# 700 /home/userdoc
grep 'fixed mode: /home/userdoc' /var/log/dropQbsd/enforce_home.log | tail -1
# fixed mode: /home/userdoc (was 755)
```

```sh
# --- enforce_home: home owner/group enforcement ----------------
chown userdoc:wheel /home/usermail
chmod 755 /home/usermail
sleep 150
stat -f '%Lp %Su:%Sg %N' /home/usermail
# 700 usermail:usermail /home/usermail
grep -E 'fixed (mode|owner|group): /home/usermail' \
    /var/log/dropQbsd/enforce_home.log | tail -3
# fixed mode: /home/usermail (was 755)
# fixed owner: /home/usermail (was userdoc)
# fixed group: /home/usermail (was wheel)
```

```sh
# --- enforce_home: cycle count (after 2a/2b) -------------------
grep 'cycle complete: fixed=[1-9]' /var/log/dropQbsd/enforce_home.log | tail -1
# cycle complete: fixed=3
```

```sh
# --- enforce_home: /root is not touched (root:wheel 700) -------
stat -f '%Lp %Su:%Sg %N' /root
# 700 root:wheel /root
# (enforce_home enforces this; a violation is fixed the same way)
```

```sh
# --- enforce_sync: owner + permission enforcement --------------
touch /home/userdoc/Sync/t_test.txt
chmod 600 /home/userdoc/Sync/t_test.txt
chown root:wheel /home/userdoc/Sync/t_test.txt
sleep 150
ls -l /home/userdoc/Sync/t_test.txt
# -rw-rw---- 1 userdoc userdoc ...
tail -1 /var/log/dropQbsd/enforce_sync.log
# fixed: 1 file, 0 dir, 1 owner/group
```

```sh
# --- all three: no orphaned locks -------------------------------
# Only enforce_drop and enforce_sync use locks; enforce_home does
# not (it is a simple stat + fix, no lock needed).
for l in /var/run/enforce_drop.lock /var/run/enforce_sync.lock; do
    [ -d "$l" ] && echo "lock: $l"
done
# A lock persisting over several checks = blocked enforcer:
# reclaim it (rmdir) and investigate what killed the cycle.
```

---

## 10. Desktop Integration and Utilities

This section has two parts.

**10.1 -- 10.6: the working environment.** Colors, editor, file
managers, Qfile, and **disposable sessions**. These are technically
optional, but they are what make dropQbsd usable in production. In a
compartmentalized system, the first problem is not isolation -- it is
knowing *where you are*. The per-domain color scheme (terminals, `mc`,
`xfe`, `nnn`) and the OSD indicator answer that question at a glance.
Without them, the domain model is correct but unusable: you cannot
tell `userweb` from `usermail` without reading the prompt. Install
these first. **Disposable sessions** (`Run --disposable`) are grouped
here because they are a daily-use essential, not a convenience.

**10.7 -- 10.15: utilities.** Independent utilities, listed
alphabetically. Some are important (`Integrity Verification`), some
are conveniences (`Qsite`, `Qattach`), some are situational
(`Syncthing`, `VLC`). Install only what you need.

### 10.1 Application Examples -- Bulk Install

The `examples/` tree ships ready-made configuration for the file
manager, the nnn plugins, and the vi editor. This block installs
all of it with the correct ownership and permissions. It is the
concrete counterpart of sections 10.2 -- 10.6.

The conductor menu (`qmenu`) is configured separately: it reads its
application list from the `[qmenu]` section of `local.conf` (see
10.4), not from `examples/`.

**WARNING -- this block overwrites existing per-user configuration.**
It replaces `~/.exrc`, `~/.config/mc/ini`, and
`~/.config/nnn/plugins/`. The block backs these up first, appending
`.bak.<timestamp>`, but the originals are still replaced. On a fresh
install this is harmless.

**Where to run this from.** The commands below assume `examples/`
lives in `/opt/dropQbsd/`, i.e. that section 3 (Install Scripts) has
already been run:

```sh
mkdir -p /opt/dropQbsd/bin
cp -r admin libexec sbin src templates examples /opt/dropQbsd/
```
If you have not run section 3 yet, do it first. Alternatively, run
this block from the directory where you cloned the repository --
`examples/` is present there too -- by replacing the first line with
a `cd` to that directory.

The opening `cd /opt/dropQbsd` is guarded: if the directory or
`examples/` is missing, the block stops with an error instead of
silently copying nothing.

**Run as root:**

```sh
cd /opt/dropQbsd || { echo "ERROR: /opt/dropQbsd not found -- run section 3 first." >&2; exit 1; }
[ -d examples ] || { echo "ERROR: examples/ not found in /opt/dropQbsd." >&2; exit 1; }

# ------------------------------------------------------------------
# Per-account examples (conductor, root, userdoc, usermail, userweb).
# root's home is /root; the others are under /home. The group for
# root is wheel (BSD convention); for the domains it is the user's
# own group.
# ------------------------------------------------------------------
for u in root "$CONDUCTOR_USER" userdoc usermail userweb; do

    # Resolve the home directory and the owning group.
    if [ "$u" = "root" ]; then
        h=/root
        grp=wheel
        role="root"
    else
        h="/home/$u"
        grp="$u"
        role="$(role_of "$u")"
    fi

    # --- Back up existing per-user config before overwriting -----
    ts=$(date +%Y%m%d_%H%M%S)
    for f in "$h/.exrc" "$h/.config/mc/ini" "$h/.gtkrc-2.0"; do
        [ -f "$f" ] && cp -p "$f" "$f.bak.$ts"
    done
    [ -d "$h/.config/nnn/plugins" ] && \
        cp -Rp "$h/.config/nnn/plugins" "$h/.config/nnn/plugins.bak.$ts"

    # --- Midnight Commander: skins + preconfigured ini ----------
    mkdir -p "$h/.local/share/mc/skins" "$h/.config/mc"
    chown "$u":"$grp" "${h}/.config" "$h/.local"
    cp -R examples/apps/mc/skins/. "$h/.local/share/mc/skins/"
    cp "examples/apps/mc/ini.${role}" "$h/.config/mc/ini"
    cp examples/apps/mc/menu_for_any "$h/.config/mc/menu"
    chown -R "$u:$grp" "$h/.local/share/mc/skins" "$h/.config/mc"
    find "$h/.local/share/mc/skins" -type d -exec chmod 755 {} +
    find "$h/.local/share/mc/skins" -type f -exec chmod 644 {} +
    chmod 644 "$h/.config/mc/ini"
    chmod 644 "$h/.config/mc/menu"
    for d in "${h}/.config" "$h/.local" "$h/.cache"; do
        [ -d "$d" ] && chown -R "$u":"$grp" "$d"
    done
    # `~/.config`, `~/.local` and `~/.cache` must belong to the account.
    # Without the parent chown, `~/.config` and `~/.local` can remain
    # `root:conductor` and break GLib/XFCE and Qsite.

    # --- nnn plugins ----------------------------------------------
    mkdir -p "$h/.config/nnn/plugins"
    cp -R examples/apps/nnn/plugins/. "$h/.config/nnn/plugins/"
    chown -R "$u:$grp" "$h/.config/nnn/plugins"
    find "$h/.config/nnn/plugins" -type d -exec chmod 755 {} +
    find "$h/.config/nnn/plugins" -type f -exec chmod 755 {} +

    # --- vi configuration -----------------------------------------
    cp examples/apps/vi/exrc "$h/.exrc"
    chown "$u:$grp" "$h/.exrc"
    chmod 644 "$h/.exrc"

done

# ------------------------------------------------------------------
# Xdialog theme (GTK2) -- per-domain, operator-owned.
# ------------------------------------------------------------------
# The conductor gets the black theme for colour coherence
# across its dialogs, even though it runs no Qattach pickers itself.
# Root runs no pickers and gets no theme. The theme is operator-owned:
# created if absent, never overwritten; an update reports it if the
# shipped version differs.
#
# GTK2 loads ~/.gtkrc-2.0 automatically when Xdialog runs as that
# domain, so the picker shows the domain colour. The conductor and
# root run no pickers, so they get none.
#
# DIFFERENT from the block above: the theme is installed ONLY IF
# ABSENT and NEVER overwritten -- it is operator-owned (the user
# may customise the colour). The mc/vi/nnn files above are
# overwritten; the GTK theme is not.
role_of() {
    case "$1" in
        userdoc|usermail|userweb) echo "$1" ;;
        *) echo "conductor" ;;
    esac
}

for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
    role="$(role_of "$u")"
    r="examples/apps/gtk/gtkrc.${role}.rc"
    d="/home/$u/.gtkrc-2.0"
    if [ ! -f "$r" ]; then
        echo "WARN: no theme template for role '$role' (account '$u'): $r"
        continue
    fi
    if [ -e "$d" ]; then
        echo "WARN: exists, not overwriting (operator-owned): $d"
        continue
    fi
    cp "$r" "$d"
    chown "$u:$u" "$d"
    chmod 644 "$d"
    echo "installed theme: $u -> $d"
done

# ------------------------------------------------------------------
# Xfe templates -- per-domain, used as installation seeds.
# ------------------------------------------------------------------
# Xfe rewrites its config file on exit, so these templates are NOT
# live files: they seed each domain's first launch. The system-wide
# defaults come from /usr/local/share/xfe/xferc (and xfwrc); the
# per-domain template overrides only the colour keys. Install only
# if absent; never overwrite (the live file is operator-owned
# after Xfe rewrites it).
# ------------------------------------------------------------------
for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
    role="$(role_of "$u")"
    for f in xferc xfwrc; do
        src="examples/apps/xfe/${f}.${role}"
        if [ ! -f "$src" ]; then
            echo "WARN: no $f template for role '$role' (account '$u'): $src"
            continue
        fi
        # Xfe reads xferc from ~/.config/xfe/xferc (XDG) or ~/.xfe/xferc.
        # Use the XDG path; create it if missing.
        d="/home/$u/.config/xfe"
        [ -d "$d" ] || mkdir -p "$d"
        dst="$d/$f"
        if [ -e "$dst" ]; then
            echo "WARN: exists, not overwriting (operator-owned): $dst"
            continue
        fi
        cp "$src" "$dst"
        chown "$u:$u" "$dst"
        chmod 644 "$dst"
        echo "installed Xfe seed: $u -> $dst"
    done
done

# Xfe custom actions: xfqcp, xfqimport, xfqmv. Code, not seeds:
# install and keep current, like the nnn plugins.
for u in "$CONDUCTOR_USER" userdoc usermail userweb; do
    h="/home/$u"
    [ -d "$h" ] || continue
    ts=$(date +%Y%m%d_%H%M%S)
    [ -d "$h/.config/xfe/scripts" ] && \
        cp -Rp "$h/.config/xfe/scripts" "$h/.config/xfe/scripts.bak.$ts"
    mkdir -p "$h/.config/xfe/scripts"
    cp -R examples/apps/xfe/scripts/. "$h/.config/xfe/scripts/"
    chown -R "$u:$u" "$h/.config/xfe/scripts"
    find "$h/.config/xfe/scripts" -type d -exec chmod 755 {} +
    find "$h/.config/xfe/scripts" -type f -name 'xf*' -exec chmod 755 {} +
done

# ------------------------------------------------------------------
# Conductor menu (qmenu) + xbindkeys -- conductor only
# (`$CONDUCTOR_USER`, rename-proof).
# Operator-owned: created if absent by both the installer and the
# updater, never overwritten. An update reports the file if the shipped
# version differs from the one installed.
# ------------------------------------------------------------------
if [ ! -e "/home/$CONDUCTOR_USER/.xbindkeysrc" ]; then
    cp templates/xbindkeys_for_conductor "/home/$CONDUCTOR_USER/.xbindkeysrc"
    chown "$CONDUCTOR_USER:$CONDUCTOR_USER" "/home/$CONDUCTOR_USER/.xbindkeysrc"
    chmod 644 "/home/$CONDUCTOR_USER/.xbindkeysrc"
    echo "installed xbindkeysrc: $CONDUCTOR_USER -> /home/$CONDUCTOR_USER/.xbindkeysrc"
fi
# qmenu itself is a project script under /opt/dropQbsd/sbin/ --
# installed by the installer/updater with the other scripts
```

**Notes:**

- **This block overwrites existing per-user configuration.** It
  replaces `~/.exrc`, `~/.config/mc/ini`, and
  `~/.config/nnn/plugins/`. The block backs these up first,
  appending `.bak.<timestamp>`, but the originals are still replaced.
  **Two exceptions, both operator-owned:** the GTK theme
  (`~/.gtkrc-2.0`) and the conductor's `~/.xbindkeysrc`. They are
  created if absent, never overwritten, and reported by an update if
  the shipped version differs. On a fresh install this is harmless.
- **nnn plugins are installed for every account, including `root`.**
  They are mandatory for `qfile` (10.5) and useful standalone:
  `;c` / `;m` / `;i` call `qcp` / `qmv` / `qimport`, which work from
  any shell.
- **The conductor menu (`qmenu`) and `xbindkeys` are conductor-only.**
  Only the conductor (`$CONDUCTOR_USER`) runs the YAD conductor menu
  (`Mod4+q` -- see 5.4 for the key mapping and what to check if it does
  nothing). Domains never run `xbindkeys` and cannot launch it.
- **`chown` uses the account's own group** -- the account's own group
  for the domains, `wheel` for `root` -- not the `drop` group. These
  are per-user dotfiles, not shared artifacts.
- **The mc skins encode the domain color** (see the color table in
  10.2). They are not cosmetic. The matching `ini.<account>`
  file is copied to `~/.config/mc/ini`, so the domain's skin is
  selected automatically from the first `mc` launch -- no manual
  step in `Options > Appearance` is required.
- **Each account has two mc files:** a **skin** under
  `~/.local/share/mc/skins/<domain>.ini` (the colors), and a
  **configuration** `~/.config/mc/ini` that selects it. The
  `ini.<account>` files in `examples/apps/mc/` are the
  configurations -- they contain `[Midnight-Commander]` and a
  `[skin]` section naming the domain's skin. They are not skins
  themselves.
- **The Xdialog theme is per-domain and operator-owned.**
  `userdoc`, `usermail`, `userweb` and the conductor
  (`$CONDUCTOR_USER`) get one, from `examples/apps/gtk/gtkrc.<role>`
  to `~/.gtkrc-2.0`. The conductor's theme is black, for colour
  coherence. Root runs no pickers and gets none. GTK2 loads
  `~/.gtkrc-2.0` automatically when Xdialog runs as that domain, so the
  picker shows the domain colour. The theme is created if absent and
  never overwritten, so customising the colour is safe; an update
  reports it if the shipped version differs.
- **The Xfe templates are per-domain and operator-owned.** Each domain
  home gets a seed (`xferc`/`xfwrc`) from `examples/apps/xfe/`, installed
  only if absent. Xfe rewrites the file on exit, so the seed is not a live
  file -- after the first launch the live file is the operator's. The `$CONDUCTOR_USER`
  (conductor) seed uses the black theme, matching the mc skin and the GTK theme.
- **The Xfe scripts are per-domain and project-owned.** Each domain home
  gets `xfqcp`, `xfqimport` and `xfqmv` from `examples/apps/xfe/scripts`.
  They are code, not seeds: the block copies them on every run, so an
  update keeps them current. Do not customise them in place -- a local
  edit is overwritten, like the nnn plugins.

### 10.2 Desktop Environment

dropQbsd works with any window manager. Two examples:

- **XFCE** -- full desktop environment, familiar for users migrating
  from Windows/macOS. Install with `Pkg xfce xfce-extras`.
- **MATE** -- another full desktop environment. Install with
  `Pkg mate`.
- **cwm** -- OpenBSD's native stacking window manager. Minimal,
  keyboard-driven, zero dependencies beyond the base system.

Any window manager works with `Run` without additional configuration;
the three above are simply common choices.

**Color scheme convention.** In a compartmentalized system, the color is
functional: it tells you which domain you are in. The same colors are used
by the terminals (`xterm_*`), and `mc`, `nnn`, `xfe` (via the skins installed in 10.1).

| User | Role | Suggested theme color |
| ---- | ---- | --------------------- |
| `$CONDUCTOR_USER` | Conductor | Black |
| `root` | System | Dark red |
| `userdoc` | Documents | Dark green |
| `usermail` | Email | Dark orchid |
| `userweb` | Web browser | Dark blue |

**On tiling window managers** (`i3`, `dwm`, `spectrwm`) and the base
window managers (`cwm` on OpenBSD, `twm` on FreeBSD), the OSD
indicator is redundant, and the **conductor menu (`qmenu`) is the only
application launcher** -- bind it with `xbindkeys` (`Mod4+q`). Domain
differentiation is provided entirely by the color schemes of terminals,
`mc`, `nnn` and `xfe` launchers. On these environments the color
convention is not a suggestion -- it is the only domain signal available.

XFCE on OpenBSD needs `pkg_add xfce xfce-extras`; `rcctl enable messagebus`,
`rcctl start messagebus`.
XFCE on FreeBSD needs `pkg install xfce`; `sysrc dbus_enable=YES`.
Use `[session] wm = startxfce4`; `startxfce4` sets the XFCE environment
before `xfce4-session`. The dropQbsd session entry (dropQbsd.desktop)
and the `.xinitrc`/`.xsession` stubs call `libexec/session`, not `startxfce4`
directly.

### 10.3 Disposable sessions

`Run` can launch an application in a disposable tmpfs-backed
session. Everything written to the runtime directory is destroyed
when the application exits.

```sh
Run --disposable userweb qutebrowser --temp-basedir
Run --disposable 1G userweb ungoogled-chromium --temp-profile https://example.com
```

The tmpfs defaults to **500 MB**. A size may be given explicitly
after `--disposable` (`1G`, `512M`, ...). Downloads made in
disposable mode are bridged to the real
`/home/$TARGET_USER/Downloads` via symlink, so files survive the
browser exit.

**Browser flags for temporary profiles:**

| Browser | Flag |
|---------|------|
| Chromium / Ungoogled-chromium | `--temp-profile` |
| Firefox | `--private-window` |
| Librewolf | `--temp-profile --private-window` |
| Qutebrowser | `--temp-basedir` |


### 10.4 Editor and Application Menu

**vi -- editor configuration:**

```sh
cp examples/apps/vi/exrc ~/.exrc
```

Provides key bindings for nvi (OpenBSD base system vi): toggle visible
whitespace, tab width control, paste mode, quick save/quit.

This is installed for every domain by the bulk block in 10.1. The
command above is the manual equivalent for a single user.

**Conductor menu -- `qmenu` + `xbindkeys`.** The conductor menu is a
single YAD window listing the applications for every domain, grouped
under coloured headers (conductor, root, userdoc, usermail, userweb).
The entries are declared in the `[qmenu]` section of `local.conf`, one
command per line:

```
USERDOC
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/xterm_userdoc | Xterm (userdoc)
```

The header lines (`CONDUCTOR`, `ROOT`, `USERDOC`, `USERMAIL`, `USERWEB`)
are not selectable -- they only start a coloured section. Display names
must be **unique across all domains**: they are used to resolve the
command, so `qmenu` warns and refuses to start on duplicates.

**Display-name constraints.** The display name (the part after `|`)
may contain several words but must **not** contain `--` or `&`.
These characters are interpreted by `qmenu`'s `eval` (or by YAD) as
syntax, not text: `--` is the "end of options" marker and `&` is the
shell background operator -- either silently breaks the entry.

**Security note.** `qmenu` executes each entry's command with `eval`.
This is safe because the `[qmenu]` section lives in `local.conf` -- the
operator-owned file -- and the operator already has root. Do not put
the `[qmenu]` entries in a file any domain user can write.

**Installation:** install `qmenu` (project script, via `sbin/`) and
`xbindkeys`, and create the conductor's `~/.xbindkeysrc`:

| OpenBSD | FreeBSD |
| ------- | ------- |

```sh
cp templates/xbindkeys_for_conductor "/home/$CONDUCTOR_USER/.xbindkeysrc"
chown "$CONDUCTOR_USER:$CONDUCTOR_USER" "/home/$CONDUCTOR_USER/.xbindkeysrc"
chmod 644 "/home/$CONDUCTOR_USER/.xbindkeysrc"
```

The `.xbindkeysrc` is **operator-owned**: created if absent, never overwritten;
an update reports it if the shipped version differs.

**Launch:** `Qmenu`, or **`Mod4+q`** via `xbindkeys`. If the key does
nothing, see 5.4 before touching the file.

### 10.5 Qfile (tmux + nnn)

The four-quadrant file manager is the interactive way to move files between
domains. It depends on the `nnn` plugins installed by the bulk block
in 10.1 -- without them, `;c` / `;m` / `;i` do nothing.

Install requirements:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add nnn tmux` | `pkg install nnn tmux` |

The `nnn` color schemes are installed by the bulk block in 10.1. The
manual equivalent for a single software install:

```sh
cd /opt/dropQbsd
for d in userdoc usermail userweb; do
    mkdir -p /home/$d/.config/nnn/plugins
    cp examples/apps/nnn/plugins/* /home/$d/.config/nnn/plugins/
    chmod +x /home/$d/.config/nnn/plugins/*
    chown -R $d:$d /home/$d/.config/nnn
done
```

`nnn` is also usable standalone as a file manager (see File Managers).
`tmux` is required only for the four-quadrant Qfile.

Launch from the conductor:

```sh
Qfile
```

**Keys:** `F1`-`F4` jump to a quadrant, `F5` closes the session.

**Plugin keys** (inside a domain quadrant):

| Key | Action |
| --- | ------ |
| `Space` | Select file(s) |
| `;c` | Copy selected files to /home/drop (nnnqcp) |
| `;m` | Move selected files to /home/drop (nnnqmv) |
| `;i` | Import selected files from /home/drop (nnnqimport) |

**Note on F1-F5:** the bindings are installed in tmux's root key
table, so they are global to the tmux server. While qfile
is running, F1-F5 are captured in every tmux session on the
machine. This is intentional: qfile is designed to be the
only tmux session in use.

Plugin errors are appended to `~/.cache/dropQbsd/nnn_plugins.log`
in the domain's home (e.g. `/home/userdoc/.cache/dropQbsd/nnn_plugins.log`).

#### Launching Qfile from a Desktop Launcher

If you create a desktop launcher (XFCE, MATE, ...) for qfile
the command must go through the wrapper:

/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/xterm_conductor \
     /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/qfile

The inner wrapper is required: qfile has no shebang (dropQbsd
convention for sbin/ and libexec/ scripts), so it cannot be exec'd
directly by xterm.

### 10.6 File Managers

Three recommendations, all lightweight:

- **nnn** -- terminal-based, minimal, keyboard-driven. Already
  installed for `qfile` (10.5). The natural choice for scripted
  and keyboard-heavy workflows.
- **Xfe** -- graphical, dual-pane. For when you want a GUI.
- **Midnight Commander (`mc`)** -- terminal-based, dual-pane. Classic,
  with a menu-driven interface. Its per-domain skins are installed by
  the bulk block in 10.1 and encode the domain color.

Install requirements:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add xfe mc` | `pkg install xfe mc` |

The `mc` color schemes are installed by the bulk block in 10.1. The
manual equivalent for a single domain:

```sh
d=userdoc
mkdir -p /home/$d/.local/share/mc/skins
cp -R examples/apps/mc/skins/. /home/$d/.local/share/mc/skins/
chown -R $d:$d /home/$d/.local/share/mc/skins
find /home/$d/.local/share/mc/skins -type d -exec chmod 755 {} +
find /home/$d/.local/share/mc/skins -type f -exec chmod 644 {} +
```

Launch via `Run`:

```sh
Run userdoc xfe /home/userdoc
Run userdoc mc
```

**User menu (F2 shortcuts).** `mc` is configured with a user menu
that binds `F2` to the dropQbsd file operations: `qcp`, `qmv`,
`qimport`. It is installed by the bulk block (10.1) as
`~/.config/mc/menu` from `examples/apps/mc/menu_for_any`.

#### Xfe per-domain colour seeds

Xfe is configured per-domain. Each domain home carries a seed
template that overrides only the colour keys; everything else
falls back to the system-wide `/usr/local/share/xfe/xferc`
(and `xfwrc`).

**Template names follow the role, not the account.** For the three
fixed domains the role equals the account name, so their templates are
`xferc.userdoc`, `xferc.usermail`, `xferc.userweb` (and the same for
`xfwrc`). The conductor is rename-proof: its role is always
`conductor`, so its template has the **fixed** name
`xferc.conductor` (and `xfwrc.conductor`) regardless of the account
name. This is the same mapping `role_of` applies in the bulk block
(10.1).

**Important:** Xfe rewrites its config file on exit. The template
is an *installation seed*, not a live file -- copy it into place
before the first launch, then let Xfe own the file.

Install for a single domain (`userdoc` shown):

```sh
d=userdoc
mkdir -p "/home/$d/.config/xfe"
[ -e "/home/$d/.config/xfe/xferc" ] || cp "examples/apps/xfe/xferc.$d" "/home/$d/.config/xfe/xferc"
[ -e "/home/$d/.config/xfe/xfwrc" ] || cp "examples/apps/xfe/xfwrc.$d" "/home/$d/.config/xfe/xfwrc"
chown -R "$d:$d" "/home/$d/.config/xfe"
chmod 644 "/home/$d/.config/xfe/xferc" "/home/$d/.config/xfe/xfwrc"
```

The conductor gets the black seed -- fixed template name, because the
conductor's role does not follow the account name:

```sh
d="$CONDUCTOR_USER"
mkdir -p "/home/$d/.config/xfe"
[ -e "/home/$d/.config/xfe/xferc" ] || cp "examples/apps/xfe/xferc.conductor" "/home/$d/.config/xfe/xferc"
[ -e "/home/$d/.config/xfe/xfwrc" ] || cp "examples/apps/xfe/xfwrc.conductor" "/home/$d/.config/xfe/xfwrc"
chown -R "$d:$d" "/home/$d/.config/xfe"
chmod 644 "/home/$d/.config/xfe/xferc" "/home/$d/.config/xfe/xfwrc"
```

The guarded `[ -e ... ] || cp` form means an existing live file is never
overwritten -- consistent with the bulk block and the GTK theme policy
(operator-owned, created if absent, never overwritten). No divergence is
reported here: Xfe rewrites its config on exit, so after the first launch
the live file is expected to differ from the seed.

### 10.7 -- 10.15: Utilities

The rest of this section covers the **independent utilities**: optional
helpers that are not part of the working environment (10.1-10.5).
Install only what you need.


### 10.7 Indicator DE

For XFCE and other desktop environments, install the domain indicator dependencies:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add dzen2 xdotool` | `pkg install dzen2 xdotool` |

The indicator is launched automatically from the session file when
the conductor logs in -- `~/.xprofile` under SDDM/LightDM, `~/.xsession`
under xenodm (OpenBSD), `~/.xinitrc` under startx. It waits for the
window manager to publish a real `_NET_ACTIVE_WINDOW` before
starting, so it works with any EWMH-compliant WM (XFCE, MATE, ...).

The indicator's single-instance lock is keyed by uid and lives in
`${XDG_RUNTIME_DIR:-/tmp}` -- **not** in `/var/run/`, which is
root-only and would make the lock fail for the non-root domain user.

For tiling window managers (`i3`, `dwm`, `spectrwm`) and the base window
managers (`cwm` on OpenBSD, `twm` on FreeBSD), the OSD indicator is not used.
Domain differentiation is provided by the color schemes of terminals, `mc`, and
`xfe` launchers.

### 10.8 Integrity Verification

dropQbsd can cryptographically verify that critical scripts have not been
tampered with, using `signify(1)`.

| OpenBSD | FreeBSD |
| ------- | ------- |
| Included in base system | `pkg install signify` |

**Setup:**

Generate a key pair and sign the critical scripts. The private key must not
sit on the disk in plaintext -- two acceptable options are shown below
(option 1 is recommended).

**Option 1 -- encrypted key on disk (recommended).** The key is protected by a
passphrase. Cron never needs the private key (verification is public-key
only), so encryption breaks no automation. The passphrase must live only in
your head or in a KeePassXC vault **on another device** -- a passphrase stored
next to the key it protects defeats the encryption.

```sh
cd /opt/dropQbsd
rm -f keys/dropQbsd.pub keys/dropQbsd_scripts.sha256.sig
signify -G -e -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
```

**Option 2 -- offline key.** Keep the key on removable media, restore it only
for signing, move it away afterwards:

```sh
cd /opt/dropQbsd
rm -f keys/dropQbsd.pub keys/dropQbsd_scripts.sha256.sig
signify -G -n -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
```

Create the file list. Each line is a path relative to `/opt/dropQbsd`, or
absolute for files under `/etc/dropQbsd/`. Comments (`#`) and blank lines
are allowed and ignored by both `Sign` and `Verify`. **Do not add
`verify_integrity` to this list:** it is the trust anchor -- the file that
checks the others cannot itself be checked by them. It is protected by the
signature over the public key and by the private-key policy above.

```sh
cp templates/filelist_for_etc /etc/dropQbsd/filelist
chown root:wheel /etc/dropQbsd/filelist
chmod 644 /etc/dropQbsd/filelist
```

**Sign the manifest.** `Sign` reads `/etc/dropQbsd/filelist`, skips comments
and blank lines, hashes every listed file in filelist order, and writes the
detached signature. It is the only supported way to produce the signature:
the helper and `verify_integrity` share the same filter and the same order,
so the signature and the verification cannot diverge.

With **option 1** you will be asked for the passphrase -- this is expected:
signing is a rare, interactive event, and the cron job never needs the
private key.

```sh
Sign
```

With **option 2**, restore the private key first, then sign, then move it
back offline:

```sh
cp /path/to/offline/storage/dropQbsd.sec /root/dropQbsd.sec
Sign
rm /root/dropQbsd.sec
```

**Verify it worked:**

```sh
Verify
```

Expected output on the terminal and in the log:

```
2026-10-07 15:54:33: OK - all files verified
```

**Order matters.** `Sign` must run before the `verify_integrity` cron job
is added. On a fresh install the signature file
(`keys/dropQbsd_scripts.sha256.sig`) does not exist yet, and
`verify_integrity` exits with `SETUP INCOMPLETE` if it is missing. The
sequence is:

1. Generate the key pair (`signify -G`)
2. Install the filelist (`cp templates/filelist_for_etc ...`)
3. Sign the manifest (`Sign`)
4. Verify it works (`Verify`)
5. Add the cron job

The `verify_integrity` cron job checks the files every 5 minutes and logs to
`/var/log/dropQbsd/verify_integrity.log`. Verification is public-key only
(`signify -V`): no passphrase, no private key, no manual steps.

**Why the private key must not sit in plaintext on this disk:** an attacker
who can read it can re-sign their own tampering -- the machine would then be
verifying itself against a signature the attacker made. A plaintext key on
the same disk that `verify_integrity` polices turns the verification into
theater.

**`Sign` and `Verify` must use the same filter and the same order.** Both
read `/etc/dropQbsd/filelist`, skip comments and blank lines, and hash the
files in filelist order. The helper exists so the filter lives in one place
for the signing path; `verify_integrity` mirrors it for the verification
path. If you modify either script, verify the two filters are identical
(see Shell portability rules, "Two copies of the same logic will diverge").

If `signify` is missing or integrity was not configured during install,
the installer prints `templates/integrity_setup`. The same commands are
in that file; run them as root, then `Sign` and `Verify`.

On a fresh install `signify -G -e` asks for the passphrase twice (set
and confirm), and `Sign` asks for it once. `Verify` and the
`verify_integrity` cron job use only the public key and never ask for
the passphrase. If a key exists, answer **no** to "Regenerate the key
pair?" to keep the trust anchor.

**After updating scripts:** if you modify any monitored file,
`verify_integrity` will report a violation. This is expected. Re-sign the
manifest.

This includes the **configuration files** under `/etc/dropQbsd/`
(`conductor.conf`, `attach.conf`, `domains.conf`, `schema`, `filelist`):
they are monitored like the scripts. Adding a conductor action to
`conductor.conf` (see 10.9) or a direction to `attach.conf` requires a
re-sign before `verify_integrity` will pass. Both files are **project-owned**:
a local edit is backed up but restored to the shipped version by the next
update. They are narrow on purpose -- `attach.conf` keeps `qattach` on
the trusted-to-exposed direction only, and `conductor.conf` is the allowlist
of root-runnable actions.

#### Post update procedure

```sh
Sign
```

With **option 2**, restore the private key first, then sign, then move it
back offline:

```sh
cp /path/to/offline/storage/dropQbsd.sec /root/dropQbsd.sec
Sign
rm /root/dropQbsd.sec
```

If you no longer have the private key (or the passphrase for an
encrypted key) -- or if you simply need to replace the key --
regenerate the key pair from scratch. Remove the old key first:
`signify -G` will not overwrite an existing key, and a stale key
keeps the old signature valid.

```sh
cd /opt/dropQbsd
rm -f /root/dropQbsd.sec \
      /opt/dropQbsd/keys/dropQbsd.pub \
      /opt/dropQbsd/keys/dropQbsd_scripts.sha256.sig
```

Then regenerate, with `signify -G -e` for option 1 (encrypted
key on disk) or `signify -G -n` for option 2 (offline key), and
re-sign:

```sh
signify -G -e -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
```

(option 2: `signify -G -n ...` instead)

The old signature becomes invalid once the manifest is re-signed
with the new key; this is by design: the trust anchor is the
key, and a lost key means the chain must be rebuilt.

**Aliases:**

| Alias    | Script                       | Purpose                                              |
| -------- | ---------------------------- | ---------------------------------------------------- |
| `Sign`   | `admin/sign_filelist`        | Sign the integrity manifest                          |
| `Verify` | `libexec/verify_integrity`   | Verify monitored files against the signed manifest   |

### 10.9 Qattach -- GUI File Attach

`qattach` moves a file from a source domain into the Downloads of a
destination domain, for the blocking case: attaching a file while
composing a mail or filling an upload form.

**Installation:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add Xdialog` | `pkg install xdialog` |

`Xdialog` can block or prompt; install it separately. Without it,
`Qattach` does not work.

The installer creates `~/Downloads` in every domain home. If the
directory is missing, `qattach` creates it before importing.

**Configuration:** the direction matrix in `/etc/dropQbsd/attach.conf`,
one `SRC:DST` per line:

```
userdoc:usermail
userdoc:userweb
```

The default is deliberately minimal: from the trusted source
(`userdoc`) toward the exposed domains. The reverse directions carry
untrusted data into the trusted archive and are handled with
`qcp` + `qimport`.

**The conductor action** is declared in `/etc/dropQbsd/conductor.conf`:

```
qattach
```

This file lists the scripts the blind gate (`run_app`) may run as
root. It is signed: adding an action requires re-signing the manifest
(`Sign`). `attach.conf` is signed the same way; changing its direction
matrix also requires a re-sign.

**Invocation.** `qattach` runs exclusively through the `run_app` gate
(`Qattach`, or `run_app qattach <source>`), which supplies the display and
X11 cookie. Invoking it via the plain `wrapper` works only if the script
falls back to the environment's `$DISPLAY`/`$XAUTHORITY`; the supported
path is the gate.

**Note on the name.** `qattach` (lower-case) is the **conductor
action** -- the script name registered in `conductor.conf`. `Qattach`
(capital) is the **alias** that launches it, per the project rule
that aliases start with a capital letter. The alias fixes the source
domain to `userdoc`:

```sh
alias Qattach="/opt/dropQbsd/bin/run_app qattach userdoc"
```

**Launch:**

```sh
Qattach
```

The picker opens as `userdoc` (per the alias), showing only that
domain's home, and the destination is chosen from attach.conf.

The flow uses **three popups**: pick a file (the picker runs as `userdoc`,
per the alias, confined to its home -- other domains' homes, mode 700,
are invisible to it), pick the destination (from `attach.conf`), then confirm
the file landing in the destination's `~/Downloads`. The file is staged in the
drop zone under a unique name (`<basename>.<pid>.<timestamp>.qattach`),
then imported.

**Requirements:** `Xdialog`. The binary is `Xdialog` on OpenBSD and
`xdialog` on FreeBSD; `qattach` resolves the name at runtime.

### 10.10 Qcontrol

No extra packages needed (base system only). Run as the conductor:

```sh
Qcontrol
```

An ncurses dashboard showing compartment status, drop zone contents, and system
health.

**What you see:**

- **Domains** -- which compartments are active and what process is running in each
- **Drop zone** -- files awaiting import (newer than 60 minutes), with the
  file/quarantine totals in the section header, plus permissions and quarantine status
- **System** -- PF state, load average, free space on /home, tmpfs usage, enforcement
  logs, integrity verification (requires root authentication)

**Keys:**

| Key | Action                                                              |
| --- | ------------------------------------------------------------------- |
| `q` | Quit                                                                |
| `a` | Authenticate as root (shows PF state, logs, integrity)              |
| `r` | Refresh root snapshot (re-authenticates)                            |

**Privilege model:** root data is time-boxed. The snapshot expires after 5
minutes, and every refresh re-authenticates. The snapshot is written by
`root_snapshot` (running as root) into `/var/run/dropQbsd/` with `root:drop
0640`; the owner is verified before the panel trusts it, and the lines are
sanitized (ESC stripped) before printing.

### 10.11 Qinspect -- Inspect a drop-zone file before importing

`qinspect` shows what a file in the drop zone is, WITHOUT importing it.
It is the concrete tool for the "inspect before importing" rule: it gives
metadata, type, hash, a truncated text preview (or an archive listing),
and a plain-language risk verdict so even a non-technical operator can
decide.

**Safety:** it never executes, extracts, or opens the file in an
application that could run code. It reads metadata, hashes, type, and
lists archive contents only.

```sh
Qinspect /home/drop/foo.tar.gz
Qinspect file1              # bare name: looked up in /home/drop
Qinspect                    # NOT interactive -- needs a file argument
```

**Risk verdict.** The verdict has two axes:

| Axis | Values | Meaning |
|------|--------|---------|
| CONTENT | LOW / MEDIUM / HIGH | executable, archive, macro document, double extension, type/name mismatch |
| TRANSIT | OK / WARN / BLOCK | mtime, GID, mode: what `enforce_drop` will do |

- **CONTENT LOW / TRANSIT OK** -- `IMPORT`.
- **CONTENT LOW / TRANSIT WARN** -- `IMPORT WITH CAUTION`: the mode will
  be fixed by `enforce_drop`.
- **CONTENT LOW / TRANSIT BLOCK** -- `DO NOT IMPORT`: wrong GID or
  stale; `enforce_drop` will quarantine or delete it before any import.
- **CONTENT HIGH** -- `DO NOT IMPORT`, regardless of transit.

Exit code: 0 import, 1 caution, 2 do not import.

**Anti-masking.** A filename saying `.pdf` whose real type is an
executable raises HIGH. Double extensions (`file.pdf.exe`) do too.
The verdict is designed so a non-technical operator can act on it
without knowing what a file signature is.

**Content signals that raise the risk:**

- Executable / script / ELF / shared object.
- Documents with macros (Word, Excel, OLE).
- **Double extension** (`file.pdf.exe`, `doc.txt.sh`) -- a masking trick.
- **Extension/type mismatch** (the name says `.pdf` but the real type is an
  executable) -- the strongest sign of a disguised file.
- Archive contents containing executables (list shows them).
- Binary data where a text file was expected.

**Transit signals** (from `enforce_drop`'s rules):

- **Wrong GID** (not `drop`, and not root-owned) -- BLOCK: the file will
  be quarantined.
- **mtime older than 30 minutes** -- BLOCK: the file will be deleted as
  abandoned.
- **Mode other than 0440** -- WARN: the file will be fixed to 0440.

**Interactive use.** `qinspect` itself is non-interactive. To run it
from a prompt or a desktop launcher, use `qprompt` (10.12).

**Requirements:** base system tools (`file`, `stat`, `sha256`, `tar`, `head`).
No additional packages.

### 10.12 Qprompt -- run a dropQbsd command from a prompt

`qprompt` runs any dropQbsd command with a prompt loop, in the current
terminal. It is the generic way to drive a dropQbsd command interactively,
from a terminal or from a graphical launcher (MATE, Thunar, ...) that is
not preconfigured with the shell chain.

```sh
Qprompt qinspect     # prompts for a file, then inspects it
Qprompt qimport      # prompts for a file, then imports it
Qprompt qcp          # prompts for a file, then copies it
Qprompt ls           # system commands work too (run directly)
```

dropQbsd commands are resolved in `sbin/`, `libexec/`, `admin/` and are
always run through the wrapper (sanitized environment, correct shell).
Plain system commands (e.g. `ls`) are accepted as a fallback and run
directly.

**The wrapper is implicit.** `qprompt` wraps the dropQbsd command
internally: when you write `Qprompt qinspect`, the command is run as
`wrapper qinspect`. Do NOT add an explicit third wrapper in a launcher
line — `qprompt` would receive `wrapper` as the command name and fail.
A launcher line that opens a terminal and runs `wrapper qprompt qinspect`
already gives `qinspect` its (implicit) wrapper through `qprompt`.

**Arguments.** `qprompt` prompts for ONE argument, which is appended to
the command line. Fixed arguments (a destination directory, a flag) must
be given on the `qprompt` command line itself -- they are **not** asked
in the prompt window:

```sh
Qprompt qimport ~/Documents     # prompts only for the file
```

**From a desktop launcher.** Bind a launcher action to a normal terminal
(not `xterm_conductor`) running the prompt:

```
<terminal> -e /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/qprompt qinspect
```

For a `[qmenu]` entry (which already opens a conductor terminal):

```
/opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/xterm_conductor /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/qprompt qinspect | Qinspect
```

The terminal's own stdin (its pty) feeds `qprompt`; do not use
`xterm_conductor`-with-a-command for this, as its `</dev/null` stdin
is meant for opening a shell, not an interactive prompt.

### 10.13 Qsite + Password Manager

For daily use, **KeePassXC** is recommended -- it runs in its own domain, keeps
the password database isolated, and works with any browser.

For an integrated experience, dropQbsd includes `qsite`: a two-phase
dropdown launcher that reads site entries from a config file, copies
credentials to the clipboard via `pass(1)`, and opens sites in a disposable
browser.

**Two-phase login flow:**

1. Select a site > press **Copy ID** > browser opens, user ID copied to
   clipboard, window stays open.
2. The same site is now the only entry shown > press **Copy Password** >
   password copied (30s timer), window closes.

This eliminates the risk of pasting credentials into the wrong site.

The browser is chosen by fallback at runtime: **ungoogled-chromium**
first, then **librewolf**, then **qutebrowser** -- the first whose
binary exists is used, always with a disposable temporary profile
(`--temp-profile` / `--temp-basedir`).

**Installation:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add yad pass xclip` | `pkg install yad pass xclip` |

**Initialize pass:**

```sh
pass init your-gpg-key-id
```

**Configure sites:**

```sh
mkdir -p ~/.config/dropQbsd
cp examples/system/sites.conf.example ~/.config/dropQbsd/sites.conf
```

Edit `~/.config/dropQbsd/sites.conf` with your own sites. Format:

```
# Label|URL|id_entry|pass_entry
Bank |https://bank.example.com|finance/bank_id|finance/bank_pw
ERP |https://erp.example.com|work/erp_id|work/erp_pw
# Sites without a separate ID field:
Forum|https://forum.example.com||web/forum
```

**Store passwords:**

```sh
pass insert finance/bank_id
pass insert finance/bank_pw
```

**Launch:**

```sh
Qsite
```

On first start `Qsite` looks for `~/.config/dropQbsd/sites.conf`. If it
is missing, it shows a popup with the copy commands:

    mkdir -p ~/.config/dropQbsd
    cp /opt/dropQbsd/examples/system/sites.conf.example ~/.config/dropQbsd/sites.conf

If no supported browser is installed, `Qsite` shows the no-browser
popup; install one through the dropQbsd package window, for example
`Pkg qutebrowser`.

`Qsite` uses `~/.cache/dropqbsd`; it must be owned by the conductor.
If it is `root:wheel`, `Qsite` shows the cache-ownership popup with the
`chown` command. Do not run `Qsite` as root; run it from the conductor's
Qmenu/session.

### 10.14 Syncthing -- LAN File Synchronization

Set up Syncthing for `userdoc` with the Sync directory at
`/home/userdoc/Sync`. The `enforce_sync` script maintains correct permissions
automatically.

**Installation:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add syncthing` | `pkg install syncthing` |

**Service setup:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| `cp templates/rc.d/syncthing_userdoc.openbsd /etc/rc.d/syncthing_userdoc` | `cp templates/rc.d/syncthing_userdoc.freebsd /usr/local/etc/rc.d/syncthing_userdoc` |
| `chmod 555 /etc/rc.d/syncthing_userdoc` | `chmod 555 /usr/local/etc/rc.d/syncthing_userdoc` |
| `rcctl enable syncthing_userdoc` | `sysrc syncthing_userdoc_enable=YES` |
| `rcctl start syncthing_userdoc` | `service syncthing_userdoc start` |

**Firewall:** Syncthing rules are already in the policy (`domains.conf`
declares `tcp:22000@lan` and `udp:21027@lan` for both `allow` and `allow_in`).
No manual `pf.conf` edits are needed.

**Configuration:**

```sh
Run userdoc qutebrowser --temp-basedir http://127.0.0.1:8384
```

Settings > Default Folder Path: `/home/userdoc/Sync`.

**Troubleshooting:** if remote devices show as disconnected, verify the remote
device is listening on TCP 22000, and check that `pf.conf` allows incoming TCP
22000 and UDP 21027 from the LAN.

### 10.15 VLC in userdoc

MIT-SHM (X11 shared memory) is not available across user boundaries. VLC will
decode video but fail to render frames. Force software output:

```sh
mkdir -p /home/userdoc/.config/vlc
printf '[core]\nvout=x11\navcodec-hw=none\n' > /home/userdoc/.config/vlc/vlcrc
chown -R userdoc:userdoc /home/userdoc/.config
```

For mpv, use `--vo=x11 --hwdec=no`.

---

## 11. Upgrading the OS

System updates are performed through the scripts in `/opt/dropQbsd/admin/`, using the restrictive firewall.

Root has no permanent network access. The `<updates>` PF table is populated every 15 minutes via cron (and again on entry of each update script), then **flushed on exit** when the operation completes — so the mirror IPs are reachable only while an update is running. Each update script also adds **temporary** DNS/HTTP rules for root (`grant_dns`), which are removed when the operation finishes (`revoke_dns`), restoring the strict ruleset. `<mailserver>` and `<services>` stay populated for daily use.

| Alias     | Script                 | Purpose                                                    |
| --------- | ---------------------- | ---------------------------------------------------------- |
| `Patch`   | `patch_tru_fwall`      | Security patches only                                      |
| `Pkg`     | `pkg_tru_fwall`        | Install or update packages (`Pkg <name>` / `Pkg -u`)       |
| `Update`  | `update_tru_fwall`     | Full update: patches + firmware + packages + orphan cleanup |
| `Upgrade` | `upgrade_tru_fwall`    | Major release upgrade (takes a `RELEASE` argument)         |

All four run through the wrapper and can be invoked by alias or by
full path:

```sh
Patch
Pkg firefox
Pkg -u
Update
Upgrade 16.0-RELEASE
```

### Concurrency

Each script refuses to start if another instance of the same tool is
already running (checked *before* opening the network window). This
prevents the failure mode where two `pkg` processes fight for the
package database lock, or where a doomed run opens the firewall for
nothing.

### Release upgrades (`Upgrade RELEASE`)

`Upgrade` automates the *sequence* of a release upgrade, not the
*moment*:

- **OpenBSD**: `sysupgrade` downloads the release set and reboots
  automatically. Nothing else is required.
- **FreeBSD (traditional base)**: `freebsd-update upgrade -r RELEASE`
  is **phase 1 of 3**. After rebooting, the operator must run:
  ```sh
  freebsd-update install
  # repeat until it reports no more work, then:
  pkg upgrade -y
  ```
- **FreeBSD (PkgBase)**: `pkg upgrade -y -r RELEASE` prepares the
  upgrade. After rebooting, run:
  ```sh
  pkg upgrade -y
  ```

**RELEASE is mandatory on FreeBSD.** `Upgrade` without an argument
exits with a usage message (e.g. `Upgrade 16.0-RELEASE`).

### Pending-reboot marker

When `Upgrade` prepares a release upgrade but cannot complete it (on
FreeBSD, the reboot decision is the operator's), it leaves a marker at
`/var/log/dropQbsd/upgrade_pending`.

The login notice -- a snippet in `/etc/dropQbsd/profile`, installed
with the rest of the global configuration -- checks for the marker at
every login shell and prints a reminder:

```
>>> dropQbsd: release upgrade PENDING -- the reboot has not
>>> been completed with the post-reboot install steps.
dropQbsd release upgrade to 16.0-RELEASE prepared (2026-10-04 15:30:00)
>>> See /var/log/dropQbsd/upgrade_tru_fwall.log for the exact steps.
```

**Remove the marker only after the post-reboot steps are done:**

```sh
rm -f /var/log/dropQbsd/upgrade_pending
```

The marker is written to `/var/log/dropQbsd/` (not directly under
`/var/log/`) so that all dropQbsd state lives in one place.

### Notes

- **Run `Update` first.** `Upgrade` assumes patches and packages are
  current; running it on a stale system may fail or leave the system
  in a mixed state.
- **PkgBase**: verify `/etc/pkg/FreeBSD-base.conf` points to the new
  branch **before** running `Upgrade`.
- **Do not interrupt `Upgrade`.** On OpenBSD, `sysupgrade` reboots
  mid-command; the trap-based cleanup cannot run there, so the
  machine comes back with the strict ruleset already in place (the
  reboot flushes the temporary rules).
- **Firewall deferral.** If `gen_fwall` cannot produce a valid ruleset (e.g.
  `local.conf` is stale or malformed), the installer/updater does NOT abort:
  it warns, skips applying the firewall, continues with the remaining steps,
  and reports the firewall as pending in the final summary. Fix `local.conf`
  and run `Gen` to apply it.

---

## 12. Directory Structure Reference

After a full installation:

```
/etc/
├── dropQbsd/                    # 755 root:wheel (traversable by all domains)
│   ├── alias                    # Shell aliases (from templates/)
│   ├── attach.conf              # qattach direction matrix (from templates/)
│   ├── conductor.conf           # Conductor actions (from templates/)
│   ├── domains.conf             # Portable policy (from templates/)
│   ├── filelist                 # Files monitored by verify_integrity
│   ├── kshrc                    # Single entry point (from templates/)
│   ├── local.conf               # Local config (edited)
│   ├── profile                  # Environment variables (from templates/)
│   └── schema                   # Valid domains (from templates/)
├── doas.conf                    # OpenBSD; FreeBSD: /usr/local/etc/doas.conf
├── newsyslog.conf               # Log rotation (dropQbsd entries appended)
├── pf.conf                      # GENERATED by gen_fwall (do not edit)
└── rc.d/ (OpenBSD)              # or /usr/local/etc/rc.d/ (FreeBSD)
    └── syncthing_userdoc

/opt/dropQbsd/                   # 755 root:wheel (accessed only via run_app/wrapper)
├── admin/                       # System administration
│   ├── build_run_app            # Compile run_app.c + restore setuid bit
│   ├── gen_fwall                # Generate pf.conf from policy
│   ├── patch_tru_fwall          # Security patches
│   ├── pkg_tru_fwall            # Package management
│   ├── sign_filelist            # Sign the integrity manifest
│   ├── update_tru_fwall         # Full system update
│   └── upgrade_tru_fwall        # Major release upgrade
├── bin/
│   └── run_app                  # setuid gate (compiled)
├── examples/
│   ├── apps/
│   │   ├── gtk/                 # Per-domain Xdialog theme
│   │   ├── mc/skins/            # Midnight Commander color schemes
│   │   ├── nnn/plugins/         # nnn plugins (nnnqcp, nnnqmv, nnnqimport)
│   │   ├── vi/exrc              # nvi configuration
│   │   └── xfe/scripts/         # Xfe config and scripts
│   └── system/
│       ├── crontab.example      # Cron entries to merge
│       ├── local.conf.example   # Local config template
│       └── sites.conf.example   # Qsite config template
├── keys/
│   ├── dropQbsd.pub             # signify public key
│   └── dropQbsd_scripts.sha256.sig
├── libexec/
│   ├── enforce_drop             # Drop zone policing
│   ├── enforce_home             # Home and root directories policing
│   ├── enforce_sync             # Sync directory sanitization
│   ├── ensure_updates_table     # Populate <updates> table
│   ├── export_mail_to_drop      # Mail archival
│   ├── export_www_to_drop       # www archival
│   ├── import_mail_from_drop    # Mail import
│   ├── import_www_from_drop     # www import
│   ├── indicator_de             # Domain indicator
│   ├── root_snapshot            # Privileged data for qcontrol
│   ├── run_app_impl             # Launch logic
│   ├── session                  # WM launcher; reads [session] wm
│   ├── update_mailserver_table  # Mail server PF table
│   ├── update_services_table    # Services PF table
│   ├── verify_integrity         # Script integrity check
│   └── wrapper                  # Environment sanitizer + shell selector
├── sbin/
│   ├── qattach                  # GUI file attach between domains
│   ├── qcontrol                 # ncurses dashboard
│   ├── qcp                      # Copy into drop zone
│   ├── qfile                    # tmux 4-quadrant file manager
│   ├── qimport                  # Import from drop zone
│   ├── qinspect                 # Inspect file before import from drop zone
│   ├── qmenu                    # Conductor menu (yad)
│   ├── qmv                      # Move into drop zone
│   ├── qprompt                  # Run a command with a prompt loop
│   ├── qsite                    # Two-phase site launcher
│   ├── xterm_conductor          # xterm, conductor color scheme
│   ├── xterm_root               # xterm, root color scheme
│   ├── xterm_userdoc            # xterm, userdoc color scheme
│   ├── xterm_usermail           # xterm, usermail color scheme
│   └── xterm_userweb            # xterm, userweb color scheme
├── src/
│   └── run_app.c                # C source (reference)
├── templates/                   # Copy-as-is files
│   ├── alias_for_etc
│   ├── attach.conf_for_etc
│   ├── conductor.conf_for_etc
│   ├── doas.conf_for_etc
│   ├── domains.conf_for_etc
│   ├── dropQbsd.desktop         # LightDM/SDDM session entry
│   ├── filelist_for_etc
│   ├── kshrc_for_etc
│   ├── integrity_setup          # copy-paste integrity commands
│   ├── login.conf_append
│   ├── newsyslog_append
│   ├── profile_for_etc
│   ├── profile_for_home
│   ├── rc.d/
│   │   ├── syncthing_userdoc.freebsd
│   │   └── syncthing_userdoc.openbsd
│   ├── schema_for_etc
│   ├── xbindkeys_for_conductor
│   ├── xinitrc_for_home
│   ├── xprofile_for_home
│   └── xsession_for_home
└── VERSION

/home/
├── <conductor>/                 # Conductor (default: conductor)
│   ├── .config/dropQbsd/sites.conf
│   ├── .xbindkeysrc             # `Mod4+q` -> qmenu (operator-owned)
│   ├── .profile                 # Stub -> /etc/dropQbsd/kshrc
│   ├── .xprofile                # Stub -> /etc/dropQbsd/kshrc
│   ├── .xsession                # Stub + WM launch (xenodm)
│   └── .xinitrc                 # Stub + WM launch (startx)
├── drop/                        # 2770 root:drop, SGID: the only shared bridge
│   ├── _quarantine/             # 750 root:wheel: quarantined items + tickets
│   ├── usermail_export/         # 2770 root:drop: mail archives (export -> import)
│   └── userweb_export/          # 2770 root:drop: www archives (export -> import)
├── userdoc/                     # Documents (700)
│   ├── Downloads/               # qattach import destination
│   ├── Sync/                    # libexec/import_* default destination
│   ├── .config/
│   ├── .profile
│   ├── .xprofile
│   ├── .xsession
│   └── .xinitrc
├── usermail/                    # Email (700)
│   ├── .mail/                   # libexec/export_mail_to_drop default source
│   ├── Downloads/               # qattach import destination
│   ├── .profile
│   ├── .xprofile
│   ├── .xsession
│   └── .xinitrc
└── userweb/                     # Browser (700)
    ├── Downloads/               # qattach import destination
    ├── www/                     # libexec/export_www_to_drop default source
    ├── .profile
    ├── .xprofile
    ├── .xsession
    └── .xinitrc

/root/
├── .profile
├── .xprofile
├── .xsession
└── .xinitrc

/var/log/dropQbsd/               # 750 root:wheel (root-only logs)
├── enforce_drop.log
├── enforce_home.log
├── enforce_sync.log
├── ensure_updates_table.log
├── install.log
├── patch_tru_fwall.log
├── pkg_tru_fwall.log
├── qattach.log
├── run_app_impl.log
├── update.log
├── update_mailserver_table.log
├── update_tru_fwall.log
├── upgrade_pending               # Pending-reboot marker (Upgrade)
├── upgrade_tru_fwall.log
├── verify_integrity.log
└── verify_integrity.log.detail   # raw signify output (on violation)
```

**Note on `/var/log/dropQbsd/`:** the directory starts empty after a
fresh install. Each file appears the first time its script runs (the
enforcers and `verify_integrity` via cron within minutes;
`ensure_updates_table` and the update logs on first use of the
corresponding alias). `upgrade_pending` is the pending-reboot marker
written by `Upgrade` during a FreeBSD release upgrade (see §11).

---

## 13. Portability

dropQbsd runs on OpenBSD and FreeBSD from a **single codebase**. No forks, no
per-OS patches, no duplicated scripts.

The mechanism is a runtime shell selector. `libexec/wrapper` detects the
operating system and executes the target script with the appropriate Korn Shell
variant:

| OS | Shell |
| -- | ----- |
| OpenBSD | `/bin/ksh` (base system) |
| FreeBSD | `/usr/local/bin/mksh` (install with `pkg install mksh`) |

Scripts in `sbin/` and `libexec/` carry **no shebang**. The wrapper decides.
Adding a new OS means extending one `case` statement in `libexec/wrapper` -- not
editing every script.

**Firewall backends** follow the same principle. `gen_fwall` reads a portable
policy (`domains.conf`) and a site configuration (`local.conf`), then emits
`pf.conf` for the target system. The policy describes intent; the backend
translates intent into syntax.

The only portability gap between the OpenBSD and FreeBSD `pf(4)` backends is
interface detection:

| OpenBSD | FreeBSD |
| ------- | ------- |
| Uses the `egress` interface group (provided automatically) | Resolves the physical interface from `route get default` |

**NetBSD is not supported.** `npf(7)` filters by address and interface, not by
user. Per-user network isolation -- the foundation of dropQbsd's model -- cannot
be expressed in `npf`. `gen_fwall` refuses to generate a partial ruleset rather
than emit a firewall that silently drops per-user isolation.

### The domain indicator lock

`indicator_de` takes a single-instance lock keyed by uid, in a
user-writable location:
```sh
LOCK="${XDG_RUNTIME_DIR:-/tmp}/indicator_de.$(id -u).lock"
```

**Do not place this lock in `/var/run/`.** The indicator runs as a
domain user, not root, and `/var/run` is root-only (`drwxr-xr-x`).
`mkdir` there fails with `EACCES`, and the guard
```sh
if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
```
would exit immediately on every start -- the indicator would never
run. The uid in the name is required: each domain is a separate
user, and without it the first domain to start would block the
others.

### Waiting for the window manager

The indicator is launched from the session file in a detached
subshell that polls `_NET_ACTIVE_WINDOW` until a real window id
appears. The atom has **two** fields:
```sh
NET_ACTIVE_WINDOW(WINDOW): window id # 0x2800004, 0x0
```

The second field is always `0x0`. A naive test such as
`grep -q 'window id'` matches even when the first field is `0x0`
(no active window yet), so the indicator would start too early and
poll an empty atom. Test only the **first** field:
```sh
active=$(echo "$atom" | sed 's/.*window id # //' | cut -d',' -f1 | tr -d ' ')
if [ -n "$active" ] && [ "$active" != "0x0" ]; then break; fi
```

---

## 14. Shell portability rules

Scripts in `sbin/` and `libexec/` run under PD KSH (OpenBSD) and
mksh (FreeBSD). Both are Korn shells, but neither is bash. The
following are NOT available and must not be used:

- `disown` (bash/zsh only) -- use a subshell `( cmd & )` to detach
- Bash arrays (`arr=(...)`) -- use positional parameters or a file
- `[[ "$x" =~ ... ]]` -- not portable; use `case` or external tools
- `\#*` inside `[[ ]]` -- does not match `#`; use `case` for globs
- Process substitution `<(...)` -- not in ksh; use temp files
- `pipefail` -- not in PD KSH; write to a temp file to capture exit codes
- `cat -A` (GNU) -- use `cat -v -e -t` (POSIX)
- `df -m` (GNU) -- OpenBSD has no -m; use `df -k` on both
  systems, then divide by 1024 for MB
- Memory filesystems have different device names: OpenBSD
  shows `mfs:NNNNN`, FreeBSD shows `tmpfs`. Match both,
  anchored at the start of the device field:
  `$1 ~ /^(mfs|tmpfs)/`
- Non-ASCII characters in strings passed to GUI tools -- the locale
  may be `C`; use ASCII only in titles and dialog text
- `set -u` with a command substitution that may output empty: in PD KSH and
  mksh, `VAR="$(cmd)"` with an empty result can leave `VAR` **unset**, not
  empty -- a later `[ -z "$VAR" ]` then aborts with "parameter not set".
  Initialize the variable first (`VAR=""`) and assign with an explicit
  `if`/default, or use `VAR="${VAR:-$(cmd)}"`. Never reference a variable
  before it is assigned a value anywhere in the script.
- `sed 'addr,+Np'` (GNU) -- not in BSD sed; use `sed -n '/from/,$p' | head -N`
- `grep 'a\|b'` -- `\|` is not alternation in BRE; use `grep -E 'a|b'`
- `grep -A/-B/-C` -- supported on both, but prefer `sed`/`awk` when the
  output must stay byte-identical across versions
- `sed -i ''` -- OpenBSD takes the backup extension ATTACHED
  (`-i.bak`) and rejects a separate empty argument; FreeBSD takes it
  separate. Avoid `-i` entirely: `sed 'expr' f > t && cp t f`.

Use `case` for pattern matching, POSIX constructs only, and verify
every external command exists in the sanitized `PATH`. Note that a
command existing is not enough: it must accept the flags you pass.
`df -m` is the canonical example -- `df` exists everywhere, but `-m`
is GNU-only.

### Whitespace and path handling

Two rules recur across the codebase. Both come from bugs that were
invisible until a path or a comment hit the edge case.

**Trim before the check.** When skipping comments or blank lines,
strip leading and trailing whitespace FIRST, then test for the
comment marker. An indented comment (`  # note`) must still be
skipped:
```sh
line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
case "$line" in
    ""|\#*) continue ;;
esac
```

The reverse order lets an indented comment through, and a comment
passed to `sha256` or a file operation becomes a missing-file error.

**Use `xargs -0` for path lists.** When a list of paths is
materialised and later consumed by a command, write it NUL-separated
and read it with `xargs -0`:
```sh
printf '%s\0' "$path" >> "$FILE_ARGS"
...
xargs -0 sha256 < "$FILE_ARGS"
```

Plain `xargs` splits on newlines AND spaces, so a path containing a
space becomes two arguments. `xargs -0` splits only on NUL and
passes each path as a single argument.

### Temporary files

Never create a temp file with a predictable name in a
world-writable directory:
```sh
TMP="/tmp/foo.$$"                         # WRONG
TMP=$(mktemp /tmp/foo.XXXXXX) || exit 1   # RIGHT
```

`$$` is the PID, visible via `ps`. A local user can predict the
name, pre-create a symlink to an attacker-chosen path, and the `>`
redirect follows it -- the script (often running as root) then
writes to that path. `mktemp` creates the file atomically
(`O_EXCL`) with an unpredictable name and mode `0600`, so a
pre-existing symlink cannot be followed.

This is why `root_snapshot` writes to `/var/run/dropQbsd/` instead
of `/tmp`, and why `verify_integrity` and `sign_filelist` already
use `mktemp`. Apply the same pattern everywhere a temp file is
needed.

### Two copies of the same logic will diverge

When two scripts must apply the same filter or the same order,
the logic is duplicated. Duplicated logic drifts: one is fixed,
the other is not, and the mismatch is silent until something
fails to verify.

`admin/sign_filelist` and `libexec/verify_integrity` are the
canonical example. Both read `/etc/dropQbsd/filelist`, skip
comments and blank lines, and hash the files in filelist order.
The helper exists so the filter lives in one place for the
signing path; `verify_integrity` mirrors it for the verification
path. If you change one, you must change the other.

The preferred fix for any such pair is to extract the shared
logic into a single helper that both scripts call. Until that
is done, document the coupling explicitly in both files and add
a comment that changing one requires changing the other.

### Checking a module after an edit

Every module under `installer/lib/` is sourced before anything runs, so
a mangled line stops the installer with `file[line]: command: not found`.
`ksh -n` does NOT catch it -- a comment that lost its leading `#` is a
valid command. Source each module in the entry points' context instead:

```sh
for f in installer/lib/*; do
    ksh -n "$f" || echo "SYNTAX: $f"
    ( set -eu; . installer/lib/common; . "$f" ) || echo "SOURCE: $f"
done
```

---

## 15. Environment sanitization

`libexec/wrapper` is the environment-sanitization and shell-selection layer.

It runs with the privileges of its caller:

- **root**, when invoked through `run_app` (which is setuid root) or from cron;
- **the domain user**, when invoked from within a domain.

Because `run_app` escalates to root *before* calling the wrapper, everything
downstream runs with root privileges -- so the wrapper sanitizes the
environment before any script sees it:

- `PATH` is hardcoded to system directories. A user-controlled `PATH` in a root
  context is privilege escalation: a fake `awk` earlier in `PATH` means
  arbitrary code as root.
- `IFS`, `LD_LIBRARY_PATH`, `LD_PRELOAD`, `PERL5LIB`, `PYTHONPATH`,
  `CDPATH`, `SHELL`, `HOME`, `LOGNAME`, `USER` are all unset.
- `ENV` is not set here. The Korn shell reads `ENV` only in **interactive**
  mode, and the scripts executed by the wrapper are non-interactive.
  Interactive shells (xterm) get `ENV` from `xterm_conductor` / `xterm_userdoc`.
- Only `DISPLAY`, `XAUTHORITY`, and `TERM` survive the crossing. The invoking
  uid is not an environment variable: `run_app.c` passes it as the first argument,
  and the wrapper forwards it unchanged.

Scripts that need the X environment (for example `qsite`)
apply safe defaults for `DISPLAY`, `XAUTHORITY`, and `TERM` when a
graphical launcher does not pass them. The wrapper still sanitizes;
the defaults live in the script, not in the wrapper.

Scripts that need the invoking user's home directory rebuild it from
`/etc/passwd` using the real uid -- never from the environment.

Conductor actions receive the resolved X11 cookie and display from
`run_app_impl` as arguments -- they do not guess them. `qattach` is
the reference: it uses the cookie passed by the gate, and creates a
per-domain copy for each popup that runs as a domain.

---

## 16. License

ISC. See [LICENSE](./LICENSE).


