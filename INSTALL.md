# dropQbsd — Installation

---

## Prerequisites

- OpenBSD 7.5 or newer
- **Core functionality**: no additional packages — everything is in the base system
- **Optional components** (install only what you need):
  - `indicator_xfce4`: `dzen2`, `xdotool`
  - `file_bridge`: `tmux`, `nnn`
  - `site_menu`: `zenity`, `pass`, `xclip` (plus a browser)

---

## 1. Create Users and Group

```sh
# groupadd drop

# useradd -m -G drop userweb
# useradd -m -G drop usermail
# useradd -m -G drop userdoc
```
Conductor user — create if missing, add to drop group if existing
```sh
# useradd -m -G drop user 2>/dev/null || usermod -G drop user
```

### Resource Limits (`/etc/login.conf`)

Append these classes to `/etc/login.conf` to prevent resource exhaustion
under heavy load. `userdoc` needs high open files for Syncthing; `usermail`
needs extra memory and file descriptors for compressing and moving large
mail archives (40+ GB); `userweb` gets generous limits for multiple
browser tabs and disposable tmpfs sessions.

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

After editing, rebuild the login database:

```sh
# cap_mkdb /etc/login.conf
```

---

## 2. Create Directory Structure

```sh
# mkdir -p /opt/dropQbsd/{admin,bin,keys,libexec,src}
# mkdir -p /home/drop/userweb_export
# mkdir -p /home/drop/usermail_export
# mkdir -p /home/drop/_quarantine

# chown root:drop /home/drop /home/drop/userweb_export /home/drop/usermail_export
# chmod 2770 /home/drop    # SGID (2770) forces the 'drop' group on all files placed here
# chmod 2770 /home/drop/userweb_export /home/drop/usermail_export
# chmod 750 /home/drop/_quarantine
# chmod 700 /opt/dropQbsd/keys
```

---

## 3. Install Scripts

Copy the repository directories to `/opt/dropQbsd/`:

```sh
# cp -r admin bin libexec src /opt/dropQbsd/
```

Set permissions:

```sh
# chmod 755 /opt/dropQbsd/bin/*
# chmod 755 /opt/dropQbsd/libexec/*
# chmod 700 /opt/dropQbsd/admin/*
# chown -R root:wheel /opt/dropQbsd
```

---

## 4. Build the `run_app` Blind Gate

This is the core of dropQbsd's privilege model. `run_app` is split into three files:

| File | Purpose |
|------|---------|
| `src/run_app_wrapper.c` | C source — 9 lines, compiled once |
| `bin/run_app` | Compiled setuid binary — the immutable gate `user` invokes |
| `libexec/run_app_impl` | ksh script — all the logic, editable without recompilation |

**Verify the impl script shebang:**

```sh
# head -1 /opt/dropQbsd/libexec/run_app_impl   # must be #!/bin/ksh
```

**Compile statically and set the setuid bit:**

```sh
# cc -static -o /opt/dropQbsd/bin/run_app /opt/dropQbsd/src/run_app_wrapper.c
# chown root:wheel /opt/dropQbsd/bin/run_app
# chmod 4755 /opt/dropQbsd/bin/run_app          # setuid root
# chown root:wheel /opt/dropQbsd/libexec/run_app_impl
# chmod 755 /opt/dropQbsd/libexec/run_app_impl
```

**Verify:**

```sh
# From user:
$ /opt/dropQbsd/bin/xterm_userdoc
```

---

## 5. Configure doas.conf

Minimal — `user` gets no `doas` access at all:

```sh
# cp templates/doas.conf /etc/doas.conf
# chmod 440 /etc/doas.conf
```

---

## 6. Install System Configuration Files

Before installing, back up (or remove) any local dotfiles that would
override the system-wide configuration:

```sh
# mv ~/.profile   ~/.profile.bak
# mv ~/.kshrc     ~/.kshrc.bak
# mv ~/.shrc      ~/.shrc.bak
```

dropQbsd relies on a single, coherent environment across all users —
local dotfiles will break domain isolation.

```sh
# cp templates/profile /etc/profile
# cp templates/kshrc /etc/kshrc
# cp templates/xsession /etc/xsession

# for u in user userweb usermail userdoc; do
    cp /etc/xsession /home/$u/.xsession
    chown $u:$u /home/$u/.xsession
done
# cp /etc/xsession /root/.xsession
# chown root:wheel /root/.xsession
```

Review the locale settings in `/etc/profile` — the example uses English
for system messages and Italian for time, monetary, and numeric formats.
Adjust to your region or set all to `en_US.UTF-8`. The global shell
aliases and per-user prompts are configured in `/etc/kshrc`.

The `.xsession` file loads the system-wide environment and launches the
desktop. The conductor (`user`) runs XFCE with `indicator_xfce4`; all
other domains run cwm with `indicator_cwm`. Adjust to your preferred WM.

---

## 7. Create the dropQbsd Configuration Directory

dropQbsd v0.2.0 uses a **declarative firewall policy** instead of a
hand-written `pf.conf`. Three files describe your security posture:

| File | Purpose | Source |
|------|---------|--------|
| `domains.conf` | Portable policy (identical on every install) | `templates/domains.conf` |
| `local.conf` | Your local config (subnet, mail, services) | `examples/system/local.conf.example` |
| `schema` | Valid domains for this product | `templates/schema` |

```sh
# mkdir -p /etc/dropQbsd

# cp templates/domains.conf /etc/dropQbsd/domains.conf
# cp templates/schema /etc/dropQbsd/schema
# cp examples/system/local.conf.example /etc/dropQbsd/local.conf

# chmod 644 /etc/dropQbsd/domains.conf /etc/dropQbsd/schema /etc/dropQbsd/local.conf
# chown root:wheel /etc/dropQbsd/domains.conf /etc/dropQbsd/schema /etc/dropQbsd/local.conf
```

### Edit local.conf

Open `/etc/dropQbsd/local.conf` and fill in your values. The file is
heavily commented — read it carefully. Summary of the sections:

- **`[network] lan`** — your LAN subnet (REQUIRED). Used by `userdoc`
  and by any rule targeting `@lan`.
- **`[updates] mirrors`** — Fastly CDN blocks for OpenBSD mirrors.
  Do NOT edit unless OpenBSD changes CDN provider.
- **`[mailserver] hosts`** — your mail server hostnames (optional).
  Resolved via `userweb` DNS by `update_mailserver_table`.
- **`[services] hosts`** — external services `userweb` must reach beyond
  ports 80/443 (optional). Static IPs written as-is; hostnames prefixed
  with `@`.
- **`[extra.*] allow`** — your personal exceptions (optional). You may
  only ADD `allow` rules here; the base security posture in
  `domains.conf` is not modifiable.

**Do NOT edit `domains.conf`.** It is the portable policy, identical on
every installation. Personal needs go in `[extra.*]` sections of
`local.conf`.

### How PF Tables Work

dropQbsd uses three PF tables to manage network access without exposing
provider IPs in the firewall rules:

| Table | Config source | Update script | Purpose |
|-------|---------------|---------------|---------|
| `<mailserver>` | `[mailserver] hosts` | `update_mailserver_table` | Mail server IPs for `usermail` |
| `<services>` | `[services] hosts` | `update_services_table` | External services for `userweb` |
| `<updates>` | `[updates] mirrors` | `ensure_updates_table` | OpenBSD mirror IPs for system updates |

All three scripts read from `local.conf` — there is no separate table
configuration file anymore.

**Adding a hostname (resolved automatically):**

Add it to the `[services]` section of `local.conf`, prefixed with `@`:

```
[services]
hosts = 198.51.100.10 @myhost.xyz
```

Hostnames prefixed with `@` are resolved via `userweb` DNS each time the
update script runs (every 5 minutes via cron). This keeps IPs current
without manual intervention.

---

## 8. Generate the Firewall

Instead of copying a static `pf.conf`, generate it from the policy:

```sh
# /opt/dropQbsd/libexec/gen_firewall openbsd
```

This reads `domains.conf` + `local.conf` + `schema` from
`/etc/dropQbsd/` and writes `/etc/pf.conf`.

### Verify Syntax (without applying)

```sh
# pfctl -nf /etc/pf.conf
```

`pfctl -nf` checks the syntax WITHOUT loading the rules. If it reports
errors, fix your policy files and regenerate. Do NOT apply a broken
ruleset — a firewall that fails to load leaves you without protection.

### Apply

```sh
# pfctl -f /etc/pf.conf
```

### Populate the PF Tables

Populate the `<mailserver>`, `<services>`, and `<updates>` tables from
`local.conf`:

```sh
# /opt/dropQbsd/libexec/update_mailserver_table
# /opt/dropQbsd/libexec/update_services_table
# /opt/dropQbsd/libexec/ensure_updates_table
```

These scripts read from `local.conf` (see section 7). They resolve
hostnames via `userweb` DNS and populate the tables. Root never touches
the network directly.

**Note on ordering:** `gen_firewall` emits the table definitions
(`table <mailserver> persist`, etc.) into `pf.conf`, so the tables exist
— empty — at the moment `pfctl -f` loads the ruleset. The
`update_*_table` scripts then fill them. This order (generate → verify →
apply → populate) is intentional: the firewall loads with empty tables
(blocking nothing by table membership), then the tables are populated
with the resolved IPs.

### Adding an IP to a table

**One-time** (persists until reboot or manual flush):

```sh
# pfctl -t services -T add 198.51.100.10
```

**Permanent** (survives reboot — add to config, then reload):

```sh
# Add the IP/hostname to the [services] section of local.conf
# then run:
# /opt/dropQbsd/libexec/update_services_table
```

### Regenerating after policy changes

Any time you edit `domains.conf` or `local.conf`, regenerate and reload:

```sh
# /opt/dropQbsd/libexec/gen_firewall openbsd
# pfctl -nf /etc/pf.conf   # verify first
# pfctl -f /etc/pf.conf    # then apply
```

The firewall is always derived from the policy — there is no separate
hand-written `pf.conf` to keep in sync.


---

## 9. Configure Cron (root)

All cron jobs run as root. Jobs that need to act on behalf of a domain user use `su -l <user> -c` to switch to that user's environment. There is no per-user crontab — everything is managed centrally in root's crontab for auditability and simplicity.

```sh
# dropQbsd — root crontab
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/opt/dropQbsd/bin
SHELL=/bin/sh
HOME=/root

# --- OpenBSD system maintenance ---
0       *       *       *       *       /usr/bin/newsyslog
30      1       *       *       *       /bin/sh /etc/daily
30      3       *       *       6       /bin/sh /etc/weekly
30      5       1       *       *       /bin/sh /etc/monthly

# --- dropQbsd: drop zone and sync enforcement ---
*       *       *       *       *       /opt/dropQbsd/libexec/enforce_drop
*       *       *       *       *       /opt/dropQbsd/libexec/enforce_sync

# --- dropQbsd: PF table updates ---
*/15    *       *       *       *       /opt/dropQbsd/libexec/update_mailserver_table
*/5     *       *       *       *       /opt/dropQbsd/libexec/update_services_table

# --- dropQbsd: integrity verification ---
*/5     *       *       *       *       /opt/dropQbsd/libexec/verify_integrity


# --- dropQbsd: mail archival (daily at 20:10) ---
# Mail export runs at 20:10. On large mailboxes (40+ GB) compression
# can take 90+ minutes. Pull runs at 23:00 with a 6-hour cleanup
# timeout — safe even for the largest archives.
10      20      *       *       *       su -l usermail -c /opt/dropQbsd/libexec/export_mail_to_drop > /dev/null 2>&1

# --- dropQbsd: mail pull (daily at 23:10, after export completes) ---
10       23      *       *       *       su -l userdoc -c /opt/dropQbsd/libexec/pull_mail_from_drop > /dev/null 2>&1

# --- dropQbsd: www archival (every 2 hours, 8:00–20:00) ---
0       8,10,12,14,16,18,20 * * *     su -l userweb -c /opt/dropQbsd/libexec/export_www_to_drop > /dev/null 2>&1

# --- dropQbsd: www pull (15 min after each export) ---
15      8,10,12,14,16,18,20 * * *     su -l userdoc -c /opt/dropQbsd/libexec/pull_www_from_drop > /dev/null 2>&1
```

All scripts use an atomic `mkdir` lock to prevent overlapping runs. The lock directories live in `/var/run/` and are cleared on reboot. If a script is killed mid-run, remove its lock manually:

```sh
# rmdir /var/run/enforce_drop.lock
# rmdir /var/run/enforce_sync.lock
```

---

## 10. Verification Checklist

After installation, verify each domain can perform its function:

- [ ] `userweb`: browse the web, cannot reach LAN IPs
- [ ] `usermail`: send/receive email, cannot browse the web
- [ ] `userdoc`: access LAN storage, Syncthing syncs, cannot reach internet
- [ ] `user`: can `qmv`/`qcp`/`qimport` files, can `run_app` into domains
- [ ] `enforce_drop`: running in cron, check `/var/log/dropQbsd_drop.log`
- [ ] `enforce_sync`: running in cron, check `/var/log/dropQbsd_sync.log`
- [ ] `update_mailserver_table`: populates `<mailserver>` table
- [ ] `update_services_table`: populates `<services>` table

---

## 11. Optional Components

These are not required for dropQbsd to function. Install only what you need.

---

### Control Panel

No extra packages needed (base system only). Run as `user`:

```sh
control_panel
```

Requires `/opt/dropQbsd/libexec/root_snapshot` for privileged data.

---

### Desktop Environment

dropQbsd works with any window manager. Two recommendations:

- **XFCE** — full desktop environment, familiar for users migrating from Windows/macOS. Lightweight by modern standards, well-supported on OpenBSD. Install: `/opt/dropQbsd/admin/pkg_add_via_pf xfce xfce-extras`
- **cwm** — OpenBSD's native stacking window manager. Minimal, keyboard-driven, zero dependencies beyond the base system. For a purer OpenBSD experience. Already installed — no packages needed.

Both work with `run_app` without additional configuration. Launch apps in any domain from the same desktop — `run_app` handles the X11 cookie forwarding transparently.

**Color scheme convention:**

| User | Role | Suggested theme color |
|------|------|-----------------------|
| `user` | Conductor | Black / Dark grey |
| `userdoc` | Documents | Dark green |
| `usermail` | Email | Dark orchid |
| `userweb` | Web browser | Dark blue |
| `root` | System | Dark red |

Set the theme per user via XFCE Settings → Appearance. This gives immediate visual feedback about which domain you're working in.

---

### Domain Indicator (XFCE / Desktop Environments)

```sh
doas pkg_add dzen2 xdotool
```

Add to `/home/user/.xsession` before the WM line:

```sh
/opt/dropQbsd/bin/indicator_xfce4 &
```

### Domain Indicator (cwm / Minimal WMs)

No extra packages needed. Add to `/home/user/.xsession`:

```sh
/opt/dropQbsd/bin/indicator_cwm &
```

---

### Editor and Application Menu

Example configuration files are provided in `examples/` for a smoother daily workflow.

**vi — editor configuration:**

```sh
$ cp examples/system/exrc ~/.exrc
```


Provides quality-of-life key bindings for nvi (OpenBSD's base system vi): toggle visible whitespace, tab width control, paste mode to prevent indentation staircasing, and quick save/quit shortcuts. Works out of the
box — no additional packages needed.

**cwm — application menu:**

```sh
$ cp examples/system/cwmrc ~/.cwmr
```

Edit `~/.cwmrc` and uncomment the section matching your role (root, domain user, or conductor). Provides a `Ctrl+/` application menu with domain-aware terminal launchers and commonly used applications. Requires no additional packages — `cwm` is in the base system.

---

### File Bridge (tmux + nnn)

`file_bridge` provides a 4-quadrant tmux session with `nnn` per domain plus `control_panel`. Install requirements:

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf nnn tmux
```
#### nnn Plugins

Each domain needs three nnn plugins for qcp/qmv/qimport. Create the plugin directory and scripts for each domain:

```sh
for d in userdoc usermail userweb; do
    mkdir -p /home/$d/.config/nnn/plugins

    cat > /home/$d/.config/nnn/plugins/qcp << 'EOF'
#!/bin/sh
nohup /opt/dropQbsd/bin/qcp "$@" /home/drop/ >/dev/null 2>&1 &
EOF

    cat > /home/$d/.config/nnn/plugins/qmv << 'EOF'
#!/bin/sh
nohup /opt/dropQbsd/bin/qmv "$@" /home/drop/ >/dev/null 2>&1 &
EOF

    cat > /home/$d/.config/nnn/plugins/qimport << 'EOF'
#!/bin/sh
for f in "$@"; do
    case "$f" in
        /*) nohup /opt/dropQbsd/bin/qimport "$f" >/dev/null 2>&1 & ;;
        *)  nohup /opt/dropQbsd/bin/qimport "/home/drop/$f" >/dev/null 2>&1 & ;;
    esac
done
EOF

    chmod +x /home/$d/.config/nnn/plugins/*
    chown -R $d:drop /home/$d/.config/nnn
done
```
Launch from the conductor:

```sh
$ /opt/dropQbsd/bin/file_bridge
```

---

### File Managers

We recommend two file managers, both lightweight and OpenBSD-native:

- **Xfe** (X File Explorer) — graphical, dual-pane, familiar interface
- **Midnight Commander (`mc`)** — terminal-based, fast, ideal for remote sessions

Each domain user should use a distinct color scheme for immediate visual feedback about which domain you're working in. Example templates with coordinated colors are provided in `examples/`:

| Domain | Xfe background | mc skin |
|--------|---------------|---------|
| `userweb` | Blue | `examples/skins/mc/userweb.ini` |
| `usermail` | Orchid | `examples/skins/mc/usermail.ini` |
| `userdoc` | Green | `examples/skins/mc/userdoc.ini` |

Install in each domain:

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf xfe mc
```

Launch via `run_app`:

```sh
$ /opt/dropQbsd/bin/run_app userdoc xfe /home/userdoc
$ /opt/dropQbsd/bin/run_app userdoc mc
```

Xfe configuration files live in `~/.config/xfe/` inside each domain's home. Copy the example color schemes from `examples/skins/xfe/` and adjust to taste.

---

### Integrity Verification

dropQbsd can cryptographically verify that critical scripts have not been tampered with, using OpenBSD's built-in `signify(1)`. Logs are written to `/var/log/dropQbsd_integrity.log`.

**Setup:**

Generate a key pair and sign the critical scripts (keep the .sec key offline):

```sh
# cd /opt/dropQbsd
# rm -f keys/dropQbsd.pub keys/dropQbsd_scripts.sha256.sig
# signify -G -n -p keys/dropQbsd.pub -s /root/dropQbsd.sec
# sha256 libexec/run_app_impl bin/qmv bin/qcp bin/qimport libexec/enforce_drop libexec/enforce_sync | signify -S -s /root/dropQbsd.sec -m - -x keys/dropQbsd_scripts.sha256.sig
# rm /root/dropQbsd.sec
```
The `verify_integrity` cron job (installed in step 9) checks these scripts every 5 minutes and logs any modifications to `/var/log/dropQbsd_integrity.log`.

To verify manually:

```sh
# /opt/dropQbsd/libexec/verify_integrity
# cat /var/log/dropQbsd_integrity.log
```

#### After Updating Scripts

If you modify any of the monitored scripts (`run_app_impl`, `qmv`, `qcp`, `qimport`, `enforce_drop`, `enforce_sync`), `verify_integrity` will report a signature violation. This is expected. Regenerate the signature:

```sh
# cd /opt/dropQbsd
# sha256 libexec/run_app_impl bin/qmv bin/qcp bin/qimport libexec/enforce_drop libexec/enforce_sync | signify -S -s /root/dropQbsd.sec -m - -x keys/dropQbsd_scripts.sha256.sig
# rm /root/dropQbsd.sec
```

If you no longer have the private key (`/root/dropQbsd.sec`), regenerate the key pair from scratch:

```sh
# cd /opt/dropQbsd
# rm -f keys/dropQbsd.pub keys/dropQbsd_scripts.sha256.sig
# signify -G -n -p keys/dropQbsd.pub -s /root/dropQbsd.sec
# sha256 libexec/run_app_impl bin/qmv bin/qcp bin/qimport libexec/enforce_drop libexec/enforce_sync | signify -S -s /root/dropQbsd.sec -m - -x keys/dropQbsd_scripts.sha256.sig
# rm /root/dropQbsd.sec
```

---

### Log Rotation

All dropQbsd logs should be rotated to prevent unbounded growth. Append the example rules to the existing `/etc/newsyslog.conf` — do **not** replace it, as OpenBSD ships with its own system rotation rules.

```sh
# dropQbsd logs
/var/log/dropQbsd_drop.log        root:wheel   640  7     *     @T00  Z
/var/log/dropQbsd_sync.log        root:wheel   640  7     *     @T00  Z
/var/log/dropQbsd_integrity.log   root:wheel   640  7     *     @T00  Z
/var/log/dropQbsd_updates.log     root:wheel   640  3     100   *     Z
```

`enforce_drop` and `enforce_sync` run every minute — rotate daily, keep 7 archives. `verify_integrity` runs every 5 minutes — same policy. Update logs grow slowly (manual runs only) — rotate at 100 KB, keep 3 archives.

---

### Site Menu + Password Manager

For daily use we recommend **KeePassXC** — it runs in its own domain, keeps the password database isolated, and works with any browser.

For a smoother, more integrated experience, dropQbsd includes `site_menu`: a two-phase dropdown launcher that reads site entries from a config file, copies credentials to the clipboard via `pass(1)`, and opens sites in a disposable browser.

**Two-phase login flow:**

1. Select a site → press **Copy ID** → browser opens, user ID copied to clipboard, window stays open.
2. The same site is now the only entry shown → press **Copy Password** → password copied (30s timer), window closes.

This eliminates the risk of pasting credentials into the wrong site — phase 2 locks the selection so only the waiting site is visible. If the GPG keyring is locked, a warning dialog prompts you to unlock it manually and retry.

**Installation:**

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf zenity pass xclip
```

**Initialize pass:**

```sh
$ pass init your-gpg-key-id
```

**Configure sites:**

```sh
$ mkdir -p ~/.config/dropQbsd
$ cp examples/system/sites.conf ~/.config/dropQbsd/sites.conf
```

Edit `~/.config/dropQbsd/sites.conf` with your own sites. Format:

```sh
# Label|URL|id_entry|pass_entry
Bank |https://bank.example.com|finance/bank_id|finance/bank_pw
ERP |https://erp.example.com|work/erp_id|work/erp_pw
# Sites without a separate ID field:
Forum|https://forum.example.com||web/forum
```

**Store passwords:**

```sh
$ pass insert finance/bank_id
$ pass insert finance/bank_pw
$ pass insert work/erp_id
$ pass insert work/erp_pw
```

**Launch:**

```sh
$ /opt/dropQbsd/bin/site_menu
```

Phase 1: select site, press **Copy ID** — browser opens, ID copied, window stays open. Phase 2: same site pre-selected, press **Copy Password** — password copied (30s timer), window closes. The site runs in a disposable browser (tmpfs-backed). Nothing survives after the browser closes.

---

### Syncthing — LAN File Synchronization

Set up Syncthing for `userdoc` with the Sync directory at `/home/userdoc/Sync`. The `enforce_sync` script maintains correct permissions automatically.

**Installation:**

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf syncthing
```

**Service setup:**

```sh
# cp templates/rc.d/syncthing_userdoc /etc/rc.d/
# chmod 555 /etc/rc.d/syncthing_userdoc
# rcctl enable syncthing_userdoc
# rcctl start syncthing_userdoc
```

**Firewall:**

Syncthing rules are already in the policy (domains.conf declares tcp:22000@lan udp:21027@lan for both allow and allow_in). No manual pf.conf edits are needed. If your local.conf declares your LAN subnet correctly, the rules are generated automatically.

**Configuration:**

```sh
$ /opt/dropQbsd/bin/run_app userdoc /usr/local/bin/qutebrowser --temp-basedir http://127.0.0.1:8384
```

Settings → Default Folder Path: `/home/userdoc/Sync`
Add remote devices by their device ID. Share folders with read/write permissions as needed.

**Troubleshooting:**

If remote devices show as disconnected:

- Verify both devices have Sync Protocol Listen Addresses set to default
- Verify the remote device is listening on TCP 22000: `nc -zv <remote-ip> 22000`
- Delete and re-add the remote device after any hostname or IP changes
- Check that `pf.conf` allows incoming TCP 22000 and UDP 21027 from LAN

---

### VLC in userdoc

MIT-SHM (X11 shared memory) is not available across user boundaries.
VLC will decode video but fail to render frames. Force software output:

```sh
    mkdir -p /home/userdoc/.config/vlc
    printf '[core]\nvout=x11\navcodec-hw=none\n' > /home/userdoc/.config/vlc/vlcrc
    chown -R userdoc:drop /home/userdoc/.config
```

Works for any media player that relies on MIT-SHM or hardware acceleration.
For mpv, use `--vo=x11 --hwdec=no`.

---

## 12. Directory Structure Reference

After a full installation, your system will have:

```sh
/etc/
├── dropQbsd/                    # dropQbsd configuration (NEW in v0.2.0)
│   ├── domains.conf             # Portable policy (from templates/)
│   ├── local.conf               # Local config (from examples/system/, edited)
│   └── schema                   # Valid domains (from templates/)
├── doas.conf                    # Privilege escalation (from templates/)
├── kshrc                        # Interactive shell config (from templates/)
├── newsyslog.conf               # Log rotation rules (dropQbsd entries appended)
├── pf.conf                      # GENERATED by gen_firewall (do not edit)
├── profile                      # Shell profile (from templates/)
└── xsession                     # (from templates/)

/opt/dropQbsd/
├── admin/                       # System administration tools
│   ├── pkg_add_via_pf           # Package management
│   ├── syspatch_via_pf          # Security patches
│   ├── sysupgrade_via_pf        # Major release upgrade
│   └── update_openbsd_via_pf    # Full system update
├── bin/                         # User-facing commands
│   ├── control_panel            # ncurses dashboard
│   ├── file_bridge              # tmux-based 4-quadrant file manager bridge
│   ├── indicator_cwm            # Domain indicator for cwm/i3/dwm
│   ├── indicator_xfce4          # Domain indicator for XFCE/DEs
│   ├── run_app                  # setuid blind gate (compiled)
│   ├── qmv                      # Move files into drop zone
│   ├── qcp                      # Copy files into drop zone
│   ├── qimport                  # Import files from drop zone
│   ├── site_menu                # Two-phase site launcher
│   ├── xterm_root               # xterm with root color scheme
│   ├── xterm_user               # xterm with user color scheme
│   ├── xterm_userdoc            # xterm with userdoc color scheme
│   ├── xterm_usermail           # xterm with usermail color scheme
│   └── xterm_userweb            # xterm with userweb color scheme
├── keys/                        # signify keys and signatures
│   ├── dropQbsd.pub             # signify public key
│   └── dropQbsd_scripts.sha256.sig       # Signed checksums
├── libexec/                     # Internal logic (cron, export/pull, enforcement)
│   ├── enforce_drop             # Drop zone policing
│   ├── enforce_sync             # Sync directory sanitization
│   ├── ensure_updates_table     # Populate <updates> table (from local.conf)
│   ├── export_www_to_drop       # www archival
│   ├── export_mail_to_drop      # Mail archival
│   ├── gen_firewall             # Generate pf.conf from policy (NEW)
│   ├── pull_www_from_drop       # www import
│   ├── pull_mail_from_drop      # Mail import
│   ├── root_snapshot            # Privileged data for control_panel
│   ├── run_app_impl             # Launch logic (ksh)
│   ├── update_mailserver_table  # Mail server PF table (from local.conf)
│   ├── update_services_table    # Services PF table (from local.conf)
│   └── verify_integrity         # Script integrity check
└── src/
    └── run_app_wrapper.c        # C source (reference)

/home/
├── drop/                        # Exchange zone (root:drop, 2770)
│   ├── usermail_export/         # Mail archives (SGID 2770)
│   ├── userweb_export/          # www archives (SGID 2770)
│   └── _quarantine/             # Policy violations
├── user/                        # Conductor home
│   ├── .config/
│   │   └── dropQbsd/
│   │       └── sites.conf       # Site menu configuration
│   └── .xsession                # X session startup
├── userdoc/                     # Document domain home (700)
│   ├── .cwmrc                   # cwm application menu
│   ├── .xsession                # X session startup
│   └── Sync/                    # Syncthing root folder (optional)
├── usermail/                    # Email domain home (700)
│   ├── .cwmrc                   # cwm application menu
│   └── .xsession                # X session startup
└── userweb/                     # Browser domain home (700)
    ├── .cwmrc                   # cwm application menu
    └── .xsession                # X session startup

/root/
├── .cwmrc                       # cwm application menu
└── .xsession                    # X session startup

/var/cron/tabs/
└── root                         # Central crontab -- all jobs run as root

/var/log/
├── dropQbsd_drop.log            # Drop zone enforcement
├── dropQbsd_sync.log            # Sync directory enforcement
├── dropQbsd_integrity.log       # Script integrity verification
└── dropQbsd_updates.log         # System update operations
```

### Repository layout (templates/ vs examples/)

In the repository, files are split by their nature:

```sh
templates/                       # Copy as-is (no editing needed)
├── domains.conf                 # Portable policy -> /etc/dropQbsd/
├── schema                       # Valid domains -> /etc/dropQbsd/
├── doas.conf                    # -> /etc/doas.conf
├── profile                      # -> /etc/profile
├── kshrc                        # -> /etc/kshrc
├── xsession                     # -> /etc/xsession
├── newsyslog.conf               # append -> /etc/newsyslog.conf
└── rc.d/
    └── syncthing_userdoc        # -> /etc/rc.d/

examples/                        # Copy and personalize
├── system/
│   ├── local.conf.example       # -> /etc/dropQbsd/local.conf (EDIT)
│   ├── cwmrc                    # -> ~/.cwmrc (choose role)
│   ├── exrc                     # -> ~/.exrc
│   ├── sites.conf               # -> /home/user/.config/dropQbsd/ (fill in)
│   └── crontab                  # reference for crontab -e
└── skins/                       # Optional color themes
    ├── mc/
    └── xfe/
```

**Key differences from v0.1.0:**

- `/etc/tables/` is **gone** — table configs now live in `local.conf`
- `etc/pf.conf` is **gone** — `pf.conf` is generated by `gen_firewall`
- `/etc/dropQbsd/` is **new** — holds `domains.conf`, `local.conf`, `schema`
- `templates/` and `examples/` are **reorganized** by nature (copy-as-is vs copy-and-edit)

