# dropQbsd — Installation

This guide covers **OpenBSD** (reference platform) and **FreeBSD**.

Where the procedure is identical on both systems, it is written once. Where it
differs, a two-column table is used — **OpenBSD on the left, FreeBSD on the
right** — with each system's procedure under its own column.

If a section has no such table, the procedure is the same on both platforms.

---

## Prerequisites

**Operating system:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| 7.5 or newer | 14.0 or newer |

**Core functionality:** everything is in the base system, except the Korn Shell
on FreeBSD.

| OpenBSD | FreeBSD |
| ------- | ------- |
| `ksh` is in base (`/bin/ksh`) | Install `mksh`: `pkg install mksh` |

**Optional components** — install only what you need:

| Component | Packages |
| --------- | -------- |
| `file_bridge` | `tmux`, `nnn` |
| `indicator_de` | `dzen2`, `xdotool` |
| `site_menu` | `zenity`, `pass`, `xclip` |
| `Syncthing` (userdoc) | `syncthing` |
| Integrity verification | `signify` — base on OpenBSD, `pkg install signify` on FreeBSD |

Install packages:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add <package>` | `pkg install <package>` |

---

## 1. Create Users and Group

Run as root.

```sh
groupadd drop

useradd -m -G drop userweb
useradd -m -G drop usermail
useradd -m -G drop userdoc
```

Create the conductor if missing, or add it to the `drop` group if it already
exists:

```sh
useradd -m -G drop user 2>/dev/null || usermod -G drop user
```

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

user:\
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

Rebuild the login database:

```sh
cap_mkdb /etc/login.conf
```

---

## 2. Create Directory Structure

Run as root.

```sh
mkdir -p /opt/dropQbsd/{admin,bin,keys,libexec,sbin,src,templates,examples}
mkdir -p /home/drop/userweb_export
mkdir -p /home/drop/usermail_export
mkdir -p /home/drop/_quarantine

chown root:drop /home/drop /home/drop/userweb_export /home/drop/usermail_export
chmod 2770 /home/drop
chmod 2770 /home/drop/userweb_export /home/drop/usermail_export
chmod 750 /home/drop/_quarantine
chmod 700 /opt/dropQbsd/keys
```

The `2770` mode (SGID) on `/home/drop` forces the `drop` group on all files
placed there — this is what makes the drop zone policed by construction rather
than by convention.

---

## 3. Install Scripts

Copy the repository contents to `/opt/dropQbsd/`:

```sh
cp -r admin bin libexec sbin src templates examples /opt/dropQbsd/
```

Set ownership and permissions:

```sh
chown -R root:wheel /opt/dropQbsd
chmod 755 /opt/dropQbsd/bin/*
chmod 755 /opt/dropQbsd/sbin/*
chmod 755 /opt/dropQbsd/libexec/*
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
its script runs — the enforcers and `verify_integrity` via cron
within minutes, `ensure_updates_table` and the update logs on
first use of the corresponding alias.

**Note:** scripts in `sbin/` and `libexec/` carry **no shebang**. They are
executed through `libexec/wrapper`, which selects the correct shell for the
platform. Do not add shebangs — it would break portability.

---

## 4. Build the `run_app` gate

This is the core of dropQbsd's privilege model. `run_app` is split into
three files:

| File | Purpose |
| ---- | ------- |
| `src/run_app.c` | C source — compiled once |
| `bin/run_app` | Compiled setuid binary — the immutable gate `user` invokes |
| `libexec/run_app_impl` | Script — all the logic, editable without recompilation |

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
a *new* file, and a new file has the compiler's default mode — the
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
of attack entirely — the kernel's setuid protections are a second
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

The mode must show `-rwsr-xr-x` — the `s` is the setuid bit. Without
It, the gate does not escalate and domain applications will not launch.


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
    for h in /root /home/user /home/userweb /home/usermail /home/userdoc; do
        for f in .profile .shrc .kshrc .xsession .xinitrc .cshrc .login .xprofile; do
            [ -f "$h/$f" ] && mv "$h/$f" "$h/$f.bak.$ts"
        done
    done
```

### 5.2 Global configuration (all logic lives here)

```sh
    mkdir -p /etc/dropQbsd
    cp templates/profile_for_etc  /etc/dropQbsd/profile
    cp templates/kshrc_for_etc    /etc/dropQbsd/kshrc
    cp templates/alias_for_etc    /etc/dropQbsd/alias
    chown root:wheel /etc/dropQbsd/profile /etc/dropQbsd/kshrc /etc/dropQbsd/alias
    chmod 644        /etc/dropQbsd/profile /etc/dropQbsd/kshrc /etc/dropQbsd/alias
```

### 5.3 Per-user stubs (pointers only)

The stubs are one-line pointers to `/etc/dropQbsd/kshrc`. Which ones to
install depends on the platform:

| File | OpenBSD | FreeBSD |
| ---- | ------- | ------- |
| `~/.profile`  | **always** (login shells: tty, su -, ssh) | **always** |
| `~/.xprofile` | **yes** (SDDM / LightDM, if used) | **yes** (SDDM) |
| `~/.xsession` | **yes** (xenodm, the default DM) | **NO** — see warning below |
| `~/.xinitrc`  | only if you use `startx` instead of xenodm | **yes** (startx) |

**WARNING — never install `~/.xsession` on FreeBSD.** SDDM reads
`~/.xsession` and waits for it to exit; the `exec xfce4-session`
line never returns, so the graphical session freezes at login.
On FreeBSD use `~/.xprofile` (for SDDM) or `~/.xinitrc` (for
`startx`).

**Install (OpenBSD):**

```sh
for u in user userdoc usermail userweb; do
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
for u in user userdoc usermail userweb; do
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
| ------------ | --------- | ------- | ------- |
| Text login (tty) | `~/.profile` | ✅ | ✅ |
| `su -` / `ssh` | `~/.profile` | ✅ | ✅ |
| xenodm | `~/.xsession` | ✅ | n/a |
| SDDM / LightDM | `~/.xprofile` | if used | ✅ |
| `startx` | `~/.xinitrc` | if used | ✅ |
| Terminal in session | `$ENV` | ✅ | ✅ |

`$ENV` is set by `/etc/dropQbsd/kshrc` itself, so every interactive
child shell sources the chain automatically.

**No modification to /etc/profile is required.**

### 5.4 Adjust the desktop launcher

In `~/.xsession` and `~/.xinitrc`, change the last line to your
window manager or desktop environment:

    exec xfce4-session      # XFCE
    exec cwm                # OpenBSD native WM
    exec twm                # FreeBSD base WM
    exec i3                 # tiling WM

---

## 6. Create the dropQbsd Configuration Directory

dropQbsd uses a **declarative firewall policy** instead of a hand-written
`pf.conf`. Three files describe your security posture:

| File | Purpose | Source |
| ---- | ------- | ------ |
| `domains.conf` | Portable policy (identical on every install) | `templates/domains.conf` |
| `local.conf` | Your local config (subnet, mail, services) | `examples/system/local.conf.example` |
| `schema` | Valid domains for this product | `templates/schema` |

Run as root:

```sh
cp templates/domains.conf /etc/dropQbsd/domains.conf
cp templates/schema_for_etc /etc/dropQbsd/schema
cp examples/system/local.conf.example /etc/dropQbsd/local.conf

chmod 644 /etc/dropQbsd/domains.conf /etc/dropQbsd/schema /etc/dropQbsd/local.conf
chown root:wheel /etc/dropQbsd/domains.conf /etc/dropQbsd/schema /etc/dropQbsd/local.conf
```

### Edit local.conf

Open `/etc/dropQbsd/local.conf` and fill in your values. The file is heavily
commented — read it carefully. Summary of the sections:

- **`[network] lan`** — your LAN subnet (REQUIRED). Used by `userdoc` and by
  any rule targeting `@lan`.
- **`[updates] mirrors`** — Fastly CDN blocks for OpenBSD mirrors. Do not edit
  unless the mirror provider changes.
- **`[mailserver] hosts`** — your mail server hostnames (optional). Resolved
  via `userweb` DNS by `update_mailserver_table`.
- **`[services] hosts`** — external services `userweb` must reach beyond ports
  80/443 (optional). Static IPs written as-is; hostnames prefixed with `@`.
- **`[extra.*] allow`** — your personal exceptions (optional). You may only
  **add** `allow` rules here; the base security posture in `domains.conf` is
  not modifiable.

**Do not edit `domains.conf`.** It is the portable policy, identical on every
installation. Personal needs go in `[extra.*]` sections of `local.conf`.

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

Hostnames prefixed with `@` are resolved via `userweb` DNS each time the update
script runs (every 5 minutes via cron). This keeps IPs current without manual
intervention.

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
errors, fix your policy files and regenerate. Do not apply a broken ruleset — a
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
persist`, etc.) into `pf.conf`, so the tables exist — empty — when `pfctl -f`
loads the ruleset. The `update_*` scripts then fill them. The order (generate →
verify → apply → populate) is intentional.

**Regenerating after policy changes:** any time you edit `domains.conf` or
`local.conf`:

```sh
Gen openbsd
pfctl -nf /etc/pf.conf
pfctl -f /etc/pf.conf
```

The firewall is always derived from the policy. There is no hand-written
`pf.conf` to keep in sync.

---

## 8. Configure Cron

All cron jobs run as root. Jobs that need to act on behalf of a domain user use
`su -l <user> -c` to switch to that user's environment. There is no per-user
crontab — everything is managed centrally in root's crontab for auditability.

### Merge the crontab entries

`examples/system/crontab.example` contains the dropQbsd entries to **add** to
root's existing crontab. The merge is idempotent — every dropQbsd line contains
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

**NOTE:** `crontab(1)` **replaces** the whole table — it does not append. Never
paste into `crontab -e` over pre-existing entries unless you edit in place.

### Jobs NOT in the crontab (by design)

- **`ensure_updates_table`** — invoked by the update scripts (`pkg_tru_fwall`,
  `patch_tru_fwall`) before touching the `<updates>` PF table. Its newsyslog
  entry only covers manual runs.
- **`root_snapshot`** — on demand, from `control_panel` (press `a`).

### Export/import race safety (by construction)

All export scripts publish archives atomically: they write a `*.tar.gz.tmp`
file inside the drop zone and rename it when complete. Import scripts only ever
match `*.tar.gz`. A partial archive is therefore invisible to imports.

If an export runs long, that slot's import finds nothing and exits 0; the next
run imports the complete archive. **This is expected behavior, not a failure.**

Orphaned `.tmp` files are removed by the exporters' own rotation (6 hours).

**Do not widen the import globs or remove the `.tmp` step** — this is a
load-bearing convention across all four export/import scripts.

### Lock files

All scripts use an atomic `mkdir` lock to prevent overlapping runs.
The lock directories live in `/var/run/` and are cleared on reboot.

The enforcers' locks carry a TTL (5 min): if a run is killed
mid-cycle, the next run detects the orphaned lock by age, removes
it, and re-acquires it — a killed cycle costs at most 5 minutes of
skipped runs, not a permanently blocked enforcer. Manual removal
(`rmdir /var/run/enforce_*.lock`) is only a fallback if the reclaim
itself fails (e.g. permissions); `control_panel` surfaces an
orphaned lock as a red entry.

### Enforcer rules

1. **No silent exits.** An enforcer may exit silently ONLY when there is
   nothing to do, or when another instance holds the lock. Locks are acquired
   via atomic `mkdir` with a TTL: an orphaned lock (owner killed mid-cycle)
   is reclaimed by age instead of blocking every future run forever. The TTL
   is deliberately generous — a cycle takes seconds, so a lock older than a
   few minutes is garbage, never a running cycle.

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

- `userweb`: browse the web, cannot reach LAN IPs
- `usermail`: send/receive email, cannot browse the web
- `userdoc`: access LAN storage, Syncthing syncs, cannot reach internet
- `user`: can `Qmv`/`Qcp`/`Qimport` files, can `Run` into domains
- `Endrop` running in cron — verify via the runbook below (lock-watch test), an empty log is normal
- `Ensync` running in cron — verify via the runbook below (lock-watch test), an empty log is normal
- `Update_mailserver` populates `<mailserver>` table
- `Update_services` populates `<services>` table
- `Control` shows domain status and drop zone contents

### Verifying the enforcers (runbook)

Each test exercises one branch. Expected output is shown after each command.
All drop-zone test files age out on their own (30 min); remove Sync test files
manually.

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
# Cycle complete: abandoned=0 quarantined=0 perms_fixed=1
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
# --- enforce_sync: owner + permission enforcement --------------
touch /home/userdoc/Sync/t_test.txt
chmod 600 /home/userdoc/Sync/t_test.txt
chown root:wheel /home/userdoc/Sync/t_test.txt
sleep 120
ls -l /home/userdoc/Sync/t_test.txt
# -rw-rw---- 1 userdoc userdoc ...
tail -1 /var/log/dropQbsd/enforce_sync.log
# ... Fixed in /home/userdoc/Sync: 1 file(s), 0 dir(s), 1 owner/group mismatch(es)
```

```sh
# --- both: no orphaned locks ------------------------------------
ls -d /var/run/enforce_*.lock 2>/dev/null || echo "OK: no locks (idle)"
# A lock persisting over several checks = blocked enforcer:
# reclaim it (rmdir) and investigate what killed the cycle.
```

---

## 10. Optional Components

These are not required for dropQbsd to function. Install only what you need.

### Control Panel

No extra packages needed (base system only). Run as `user`:

```sh
Control
```

Requires `/opt/dropQbsd/libexec/root_snapshot`.

### Desktop Environment

dropQbsd works with any window manager.

- **XFCE** — full desktop environment, familiar for users migrating from
  Windows/macOS. Install with `Pkg xfce xfce-extras`.
- **cwm** — OpenBSD's native stacking window manager. Minimal, keyboard-driven,
  zero dependencies beyond the base system.

Both work with `Run` without additional configuration.

**Color scheme convention:**

| User | Role | Suggested theme color |
| ---- | ---- | --------------------- |
| `user` | Conductor | Black / Dark grey |
| `userdoc` | Documents | Dark green |
| `usermail` | Email | Dark orchid |
| `userweb` | Web browser | Dark blue |
| `root` | System | Dark red |

Set the theme per user via XFCE Settings → Appearance. This gives immediate
visual feedback about which domain you are working in.

### Domain Indicator

For XFCE and other desktop environments, install the indicator dependencies:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add dzen2 xdotool` | `pkg install dzen2 xdotool` |

The indicator is launched automatically by `~/.xprofile` when `user` logs in.

For tiling window managers (`i3`, `dwm`, `spectrwm`) and the base window
managers (`cwm` on OpenBSD, `twm` on FreeBSD), the OSD indicator is not used.
Domain differentiation is provided by the color schemes of terminals, `mc`, and
`xfe` launchers.

### Editor and Application Menu

**vi — editor configuration:**

```sh
cp examples/apps/vi/exrc ~/.exrc
```

Provides key bindings for nvi (OpenBSD base system vi): toggle visible
whitespace, tab width control, paste mode, quick save/quit.

### File Bridge (tmux + nnn)

Install requirements:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add nnn tmux` | `pkg install nnn tmux` |

Install the nnn plugins for each domain:

```sh
cd /opt/dropQbsd
for d in userdoc usermail userweb; do
    mkdir -p /home/$d/.config/nnn/plugins
    cp examples/apps/nnn/plugins/* /home/$d/.config/nnn/plugins/
    chmod +x /home/$d/.config/nnn/plugins/*
    chown -R $d:drop /home/$d/.config/nnn
done
```

Launch from the conductor:

```sh
File
```

**Keys:** `F1`–`F4` jump to a quadrant, `F5` closes the session.

**Plugin keys** (inside a domain quadrant):

| Key | Action |
| --- | ------ |
| `Space` | Select file(s) |
| `;c` | Copy selected files to /home/drop (nnnqcp) |
| `;m` | Move selected files to /home/drop (nnnqmv) |
| `;i` | Import selected files from /home/drop (nnnqimport) |

**Note on F1–F5:** the bindings are installed in tmux's root key
table, so they are global to the tmux server. While file_bridge
is running, F1–F5 are captured in every tmux session on the
machine. This is intentional: file_bridge is designed to be the
only tmux session in use.

Plugin errors are appended to `~/.cache/dropQbsd/nnn_plugins.log`
in the domain's home (e.g. `/home/userdoc/.cache/dropQbsd/nnn_plugins.log`).

#### Launching the File Bridge from a Desktop Launcher

If you create a desktop launcher (XFCE, MATE, ...) for the file
bridge, the command must go through the wrapper:

    /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/xterm_user \
        /opt/dropQbsd/libexec/wrapper /opt/dropQbsd/sbin/file_bridge

The inner wrapper is required: file_bridge has no shebang (dropQbsd
convention for sbin/ and libexec/ scripts), so it cannot be exec'd
directly by xterm.

### File Managers

Two recommendations, both lightweight:

- **Xfe** — graphical, dual-pane
- **Midnight Commander (`mc`)** — terminal-based

Install:

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add xfe mc` | `pkg install xfe mc` |

Copy the example color schemes:

```sh
for d in userdoc usermail userweb; do
    mkdir -p /home/$d/.config/mc
    cp examples/apps/mc/skins/$d.ini /home/$d/.config/mc/ini
    chown -R $d:drop /home/$d/.config/mc
done
```

Launch via `Run`:

```sh
Run userdoc xfe /home/userdoc
Run userdoc mc
```

### Integrity Verification

dropQbsd can cryptographically verify that critical scripts have not been
tampered with, using `signify(1)`.

| OpenBSD | FreeBSD |
| ------- | ------- |
| Included in base system | `pkg install signify` |

**Setup:**

Generate a key pair and sign the critical scripts. The private key must not
sit on the disk in plaintext — two acceptable options are shown below
(option 1 is recommended).

**Option 1 — encrypted key on disk (recommended).** The key is protected by a
passphrase. Cron never needs the private key (verification is public-key
only), so encryption breaks no automation. The passphrase must live only in
your head or in a KeePassXC vault **on another device** — a passphrase stored
next to the key it protects defeats the encryption.

```sh
cd /opt/dropQbsd
rm -f keys/dropQbsd.pub keys/dropQbsd_scripts.sha256.sig
signify -G -e -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
```

**Option 2 — offline key.** Keep the key on removable media, restore it only
for signing, move it away afterwards:

```sh
cd /opt/dropQbsd
rm -f keys/dropQbsd.pub keys/dropQbsd_scripts.sha256.sig
signify -G -n -p keys/dropQbsd.pub -s /root/dropQbsd.sec
chmod 600 /root/dropQbsd.sec
```

Create the file list. Each line is a path relative to `/opt/dropQbsd`, or
absolute for files under `/etc/dropQbsd/`. **Do not add `verify_integrity` to
this list:** it is the trust anchor — the file that checks the others cannot
itself be checked by them. It is protected by the signature over the public
key and by the fact that the private key is not on the disk in plaintext.

```sh
cp templates/filelist_for_etc /etc/dropQbsd/filelist
chown root:wheel /etc/dropQbsd/filelist
chmod 644 /etc/dropQbsd/filelist
```

Sign the files. With **option 1** you will be asked for the passphrase — this
is expected: signing is a rare, interactive event, and the cron job never
needs the private key.

```sh
cd /opt/dropQbsd
sha256 $(cat /etc/dropQbsd/filelist) \
 | signify -S -e -s /root/dropQbsd.sec -m - \
      -x keys/dropQbsd_scripts.sha256.sig
```

With **option 2**, after signing move the private key offline (or delete it):

```sh
mv /root/dropQbsd.sec /path/to/offline/storage/
```

The `verify_integrity` cron job checks the files every 5 minutes and logs to
`/var/log/dropQbsd/verify_integrity.log`. Verification is public-key only
(`signify -V`): no passphrase, no private key, no manual steps.

**Why the private key must not sit in plaintext on this disk:** an attacker
who can read it can re-sign their own tampering — the machine would then be
verifying itself against a signature the attacker made. A plaintext key on
the same disk that `verify_integrity` polices turns the verification into
theater.

**After updating scripts:** if you modify any monitored file,
`verify_integrity` will report a violation. This is expected. Re-generate
the signature (as root):

With **option 1** (passphrase will be asked):

```sh
cd /opt/dropQbsd
sha256 $(cat /etc/dropQbsd/filelist) \
 | signify -S -e -s /root/dropQbsd.sec -m - \
      -x keys/dropQbsd_scripts.sha256.sig
```

With **option 2**, restore the private key first, then sign, then move it
back offline:

```sh
cp /path/to/offline/storage/dropQbsd.sec /root/dropQbsd.sec
cd /opt/dropQbsd
sha256 $(cat /etc/dropQbsd/filelist) \
 | signify -S -n -s /root/dropQbsd.sec -m - \
      -x keys/dropQbsd_scripts.sha256.sig
rm /root/dropQbsd.sec
```

If you no longer have the private key (or the passphrase for an encrypted
key), regenerate the key pair from scratch — with `signify -G -e` for option
1, `signify -G -n` for option 2 — and re-sign. The old signature becomes
invalid; this is by design: the trust anchor is the key, and a lost key means
the chain must be rebuilt.

### Site Menu + Password Manager

For daily use, **KeePassXC** is recommended — it runs in its own domain, keeps
the password database isolated, and works with any browser.

For an integrated experience, dropQbsd includes `site_menu`: a two-phase
dropdown launcher that reads site entries from a config file, copies
credentials to the clipboard via `pass(1)`, and opens sites in a disposable
browser.

**Two-phase login flow:**

1. Select a site → press **Copy ID** → browser opens, user ID copied to
   clipboard, window stays open.
2. The same site is now the only entry shown → press **Copy Password** →
   password copied (30s timer), window closes.

This eliminates the risk of pasting credentials into the wrong site.

**Installation:**

| OpenBSD | FreeBSD |
| ------- | ------- |
| `pkg_add zenity pass xclip` | `pkg install zenity pass xclip` |

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
Site
```

### Syncthing — LAN File Synchronization

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

Settings → Default Folder Path: `/home/userdoc/Sync`.

**Troubleshooting:** if remote devices show as disconnected, verify the remote
device is listening on TCP 22000, and check that `pf.conf` allows incoming TCP
22000 and UDP 21027 from the LAN.

### VLC in userdoc

MIT-SHM (X11 shared memory) is not available across user boundaries. VLC will
decode video but fail to render frames. Force software output:

```sh
mkdir -p /home/userdoc/.config/vlc
printf '[core]\nvout=x11\navcodec-hw=none\n' > /home/userdoc/.config/vlc/vlcrc
chown -R userdoc:drop /home/userdoc/.config
```

For mpv, use `--vo=x11 --hwdec=no`.

---

## 11. Upgrading the OS

System updates are performed through the scripts in
`/opt/dropQbsd/admin/`, using the restrictive firewall. Root has no
permanent network access: the `<updates>` PF table is populated on
demand by each script, and the temporary DNS/HTTP rules are removed
when the operation finishes.

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

The login notice — a snippet in `/etc/dropQbsd/profile`, installed
with the rest of the global configuration — checks for the marker at
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

---

## 12. Directory Structure Reference

After a full installation:

```
/etc/
├── dropQbsd/
│   ├── alias                    # Shell aliases (from templates/)
│   ├── domains.conf             # Portable policy (from templates/)
│   ├── filelist                 # Files monitored by verify_integrity
│   ├── kshrc                    # Single entry point (from templates/)
│   ├── local.conf               # Local config (edited)
│   ├── profile                  # Environment variables (from templates/)
│   └── schema                   # Valid domains (from templates/)
├── doas.conf                    # Privilege escalation (from templates/)
├── newsyslog.conf               # Log rotation (dropQbsd entries appended)
├── pf.conf                      # GENERATED by gen_fwall (do not edit)
└── rc.d/ (OpenBSD)              # or /usr/local/etc/rc.d/ (FreeBSD)
    └── syncthing_userdoc

/opt/dropQbsd/
├── admin/                       # System administration
│   ├── build_run_app            # Compile run_app.c + restore setuid bit
│   ├── gen_fwall                # Generate pf.conf from policy
│   ├── patch_tru_fwall          # Security patches
│   ├── pkg_tru_fwall            # Package management
│   ├── update_tru_fwall         # Full system update
│   └── upgrade_tru_fwall        # Major release upgrade
├── bin/
│   └── run_app                  # setuid gate (compiled)
├── examples/
│   ├── apps/
│   │   ├── mc/skins/            # Midnight Commander color schemes
│   │   ├── nnn/plugins/         # nnn plugins (nnnqcp, nnnqmv, nnnqimport)
│   │   ├── vi/exrc              # nvi configuration
│   │   └── xfe/                 # Xfe config and scripts
│   └── system/
│       ├── crontab.example      # Cron entries to merge
│       ├── local.conf.example   # Local config template
│       └── sites.conf.example   # Site menu config template
├── keys/
│   ├── dropQbsd.pub             # signify public key
│   └── dropQbsd_scripts.sha256.sig
├── libexec/
│   ├── enforce_drop             # Drop zone policing
│   ├── enforce_sync             # Sync directory sanitization
│   ├── ensure_updates_table     # Populate <updates> table
│   ├── export_mail_to_drop      # Mail archival
│   ├── export_www_to_drop       # www archival
│   ├── import_mail_from_drop    # Mail import
│   ├── import_www_from_drop     # www import
│   ├── root_snapshot            # Privileged data for control_panel
│   ├── run_app_impl             # Launch logic
│   ├── update_mailserver_table  # Mail server PF table
│   ├── update_services_table    # Services PF table
│   ├── verify_integrity         # Script integrity check
│   └── wrapper                  # Environment sanitizer + shell selector
├── sbin/
│   ├── control_panel            # ncurses dashboard
│   ├── file_bridge              # tmux 4-quadrant file manager
│   ├── indicator_de             # Domain indicator
│   ├── qcp                      # Copy into drop zone
│   ├── qimport                  # Import from drop zone
│   ├── qmv                      # Move into drop zone
│   ├── site_menu                # Two-phase site launcher
│   ├── xterm_root               # xterm, root color scheme
│   ├── xterm_user               # xterm, conductor color scheme
│   ├── xterm_userdoc            # xterm, userdoc color scheme
│   ├── xterm_usermail           # xterm, usermail color scheme
│   └── xterm_userweb            # xterm, userweb color scheme
├── src/
│   └── run_app.c                # C source (reference)
└── templates/                       # Copy-as-is files
    ├── alias_for_etc
    ├── doas.conf
    ├── domains.conf
    ├── filelist_for_etc
    ├── kshrc_for_etc
    ├── newsyslog_append
    ├── profile_for_etc
    ├── profile_for_home
    ├── rc.d/
    │   ├── syncthing_userdoc.freebsd
    │   └── syncthing_userdoc.openbsd
    ├── schema_for_etc
    ├── xinitrc_for_home
    ├── xprofile_for_home
    └── xsession_for_home

/home/
├── user/                        # Conductor
│   ├── .config/dropQbsd/sites.conf
│   ├── .profile                 # Stub -> /etc/dropQbsd/kshrc
│   ├── .xprofile                # Stub -> /etc/dropQbsd/kshrc
│   ├── .xsession                # Stub + WM launch (xenodm)
│   └── .xinitrc                 # Stub + WM launch (startx)
├── userdoc/                     # Documents (700)
│   ├── .config/
│   ├── Sync/
│   ├── .profile
│   ├── .xprofile
│   ├── .xsession
│   └── .xinitrc
├── usermail/                    # Email (700)
│   ├── .profile
│   ├── .xprofile
│   ├── .xsession
│   └── .xinitrc
└── userweb/                     # Browser (700)
    ├── .profile
    ├── .xprofile
    ├── .xsession
    └── .xinitrc

/root/
├── .profile
├── .xprofile
├── .xsession
└── .xinitrc

/var/log/dropQbsd/
├── enforce_drop.log
├── enforce_sync.log
├── ensure_updates_table.log
├── patch_tru_fwall.log
├── pkg_tru_fwall.log
├── update_mailserver_table.log
├── update_tru_fwall.log
├── upgrade_pending            # Pending-reboot marker (Upgrade)
├── upgrade_tru_fwall.log
└── verify_integrity.log
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
Adding a new OS means extending one `case` statement in `libexec/wrapper` — not
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
user. Per-user network isolation — the foundation of dropQbsd's model — cannot
be expressed in `npf`. `gen_fwall` refuses to generate a partial ruleset rather
than emit a firewall that silently drops per-user isolation.

---

## 14. Environment sanitization

`libexec/wrapper` is the environment-sanitization and shell-selection layer.

It runs with the privileges of its caller:

- **root**, when invoked through `run_app` (which is setuid root) or from cron;
- **the domain user**, when invoked from within a domain.

Because `run_app` escalates to root *before* calling the wrapper, everything
downstream runs with root privileges — so the wrapper sanitizes the
environment before any script sees it:

- `PATH` is hardcoded to system directories. A user-controlled `PATH` in a root
  context is privilege escalation: a fake `awk` earlier in `PATH` means
  arbitrary code as root.
- `IFS`, `LD_LIBRARY_PATH`, `LD_PRELOAD`, `PERL5LIB`, `PYTHONPATH`,
  `CDPATH`, `SHELL`, `HOME`, `LOGNAME`, `USER` are all unset.
- `ENV` is not set here. The Korn shell reads `ENV` only in **interactive**
  mode, and the scripts executed by the wrapper are non-interactive.
  Interactive shells (xterm) get `ENV` from `xterm_user` / `xterm_userdoc`.
- Only `DISPLAY`, `XAUTHORITY`, and `TERM` survive the crossing.

Scripts that need the invoking user's home directory rebuild it from
`/etc/passwd` using the real uid — never from the environment.

---

## 15. License

ISC. See [LICENSE](./LICENSE).


