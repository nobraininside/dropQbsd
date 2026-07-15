# dropQbsd — Installation

---

## Prerequisites

- OpenBSD (any supported release)
- No additional packages required for core functionality — everything is in the base system

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
---

## 2. Create Directory Structure

```sh
# mkdir -p /opt/dropQbsd/{bin,libexec,admin,src,tables}
# mkdir -p /home/drop/userweb_export
# mkdir -p /home/drop/usermail_export
# mkdir -p /home/drop/_quarantine
# mkdir -p /etc/tables    # populated by dropQbsd admin scripts and manual config

# chown root:drop /home/drop /home/drop/userweb_export /home/drop/usermail_export
# chmod 2770 /home/drop    # SGID (2770) forces the 'drop' group on all files placed here
# chmod 2770 /home/drop/userweb_export /home/drop/usermail_export
# chmod 750 /home/drop/_quarantine
# chmod 755 /etc/tables
```

---

## 3. Install Scripts

Copy the repository directories to `/opt/dropQbsd/`:

```sh
# cp -r bin libexec admin src /opt/dropQbsd/
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
| `src/run_app_wrapper.c` | C source — 10 lines, compiled once |
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
# cp etc/doas.conf /etc/doas.conf
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
# cp etc/pf.conf /etc/pf.conf
# cp etc/profile /etc/profile
# cp etc/kshrc /etc/kshrc
# cp etc/xsession /etc/xsession

# for u in user userweb usermail userdoc; do
    cp /etc/xsession /home/$u/.xsession
    chown $u:$u /home/$u/.xsession
done
# cp /etc/xsession /root/.xsession
# chown root:wheel /root/.xsession
```

Review the locale settings in `/etc/profile` — the example uses English for system messages and Italian for time, monetary, and numeric formats. Adjust to your region or set all to `en_US.UTF-8`. The global shell aliases and per-user prompts are configured in `/etc/kshrc`.

The `.xsession` file loads the system-wide environment and launches the desktop. Review the window manager line — the example uses XFCE. Adjust to your preferred WM (cwm, fvwm, etc.).

---

## 7. Configure PF Tables

### Mail Server IPs

Copy the example table files from the repository and edit them with your
own providers:

```sh
# cp examples/tables/mailserver_hosts /etc/tables/
# cp examples/tables/services_hosts /etc/tables/
# chmod 644 /etc/tables/mailserver_hosts
# chmod 644 /etc/tables/services_hosts
```

Edit each file:

- **`/etc/tables/mailserver_hosts`** — mail server hostnames, used by `usermail`
- **`/etc/tables/services_hosts`** — external service IPs/hostnames, used by `userweb` (prefix hostnames with `@`)

Example `/etc/tables/mailserver_hosts`:

```sh
mail.example.com
imap.example.com
smtp.example.com
```

Example `/etc/tables/services_hosts`:

```sh
# Static IPs:
198.51.100.10          # cPanel hosting
# Hostnames (resolved each run via userweb DNS):
@ssh.github.com        # GitHub SSH over 443
```

### Updates IPs (auto-generated)

```sh
# touch /etc/tables/updates_ips
# chmod 644 /etc/tables/updates_ips
```

### How PF Tables Work

dropQbsd uses three PF tables to manage network access without exposing provider IPs in the firewall rules:

| Table | Config file | Update script | Purpose |
|-------|-------------|---------------|---------|
| `<mailserver>` | `/etc/tables/mailserver_hosts` | `update_mailserver_table` | Mail server IPs for `usermail` |
| `<services>` | `/etc/tables/services_hosts` | `update_services_table` | External services (SSH, cPanel, GitHub) for `userweb` |
| `<updates>` | `/etc/tables/updates_ips` | `ensure_updates_table` | OpenBSD mirror IPs for system updates |

**Adding an IP to a table:**

```sh
# One-time (persists until reboot or manual flush):
# pfctl -t services -T add 198.51.100.10

# Permanent (add to config file, survives reboot):
# echo '198.51.100.10' >> /etc/tables/services_hosts
# /opt/dropQbsd/libexec/update_services_table
```

**Adding a hostname (resolved automatically):**

```sh
# echo '@myhost.xyz' >> /etc/tables/services_hosts
# /opt/dropQbsd/libexec/update_services_table
```

Hostnames prefixed with `@` are resolved via `userweb` DNS each time the update script runs (every 5 minutes via cron). This keeps IPs current without manual intervention.

---

## 8. Reload the Firewall and populate tables

```sh
# pfctl -f /etc/pf.conf
```

Populate the services and mailserver tables::

```sh
# /opt/dropQbsd/libexec/update_services_table
# /opt/dropQbsd/libexec/update_mailserver_table
```

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

### Syncthing — LAN File Synchronization

Set up Syncthing for `userdoc` with the Sync directory at `/home/userdoc/Sync`. The `enforce_sync` script maintains correct permissions automatically.

**Installation:**

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf syncthing
```

**Service setup:**

```sh
# cp examples/rc.d/syncthing_userdoc /etc/rc.d/
# chmod 555 /etc/rc.d/syncthing_userdoc
# rcctl enable syncthing_userdoc
# rcctl start syncthing_userdoc
```

**Firewall:**

Add these rules to `/etc/pf.conf`:

```sh
# Syncthing — incoming from LAN
pass in quick on egress proto tcp from 192.168.0.0/16 to any port 22000
pass in quick on egress proto udp from 192.168.0.0/16 to any port 21027

# Syncthing — outgoing to LAN
pass out quick on egress proto tcp from any to any port 22000 user userdoc flags S/SA
pass out quick on egress proto udp from any to any port 21027 user userdoc
```

Reload:

```sh
# pfctl -f /etc/pf.conf
```

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

### Site Menu + Password Manager

For daily use we recommend **KeePassXC** — it runs in its own domain, keeps the password database isolated, and works with any browser.

For a smoother, more integrated experience, dropQbsd includes `site_menu`: a dropdown launcher that reads site entries from a config file, copies passwords to the clipboard via `pass(1)`, and opens sites in a disposable browser. The clipboard is automatically cleared after 15 seconds.

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
$ cp examples/sites.conf ~/.config/dropQbsd/sites.conf
```

Edit `~/.config/dropQbsd/sites.conf` with your own sites. Format:

```sh
# Label|URL|pass_entry (optional)
Bank (your_user_id)|https://bank.example.com|finance/bank
ERP (your_user_id)|https://erp.example.com|work/erp
```

**Store passwords:**

```sh
$ pass insert finance/bank
$ pass insert work/erp
```

**Launch:**

```sh
$ /opt/dropQbsd/bin/site_menu
```

The site opens in a disposable browser (tmpfs-backed). Nothing survives after the browser closes.

---

### Integrity Verification

dropQbsd can cryptographically verify that critical scripts have not been tampered with, using OpenBSD's built-in `signify(1)`.

**Setup:**

Generate a key pair (keep the .sec key offline):

```sh
# signify -G -n -p /opt/dropQbsd/tables/dropQbsd.pub -s /root/dropQbsd.sec
```

Sign the critical scripts

```sh
# sha256 /opt/dropQbsd/libexec/run_app_impl \
         /opt/dropQbsd/bin/qmv \
         /opt/dropQbsd/bin/qcp \
         /opt/dropQbsd/bin/qimport \
         /opt/dropQbsd/libexec/enforce_drop \
         /opt/dropQbsd/libexec/enforce_sync \
    | signify -S -s /root/dropQbsd.sec -m - \
        -x /opt/dropQbsd/tables/dropQbsd_scripts.sha256.sig
```

Remove the private key — keep it offline

```sh
# rm /root/dropQbsd.sec
```

The `verify_integrity` cron job (installed in step 9) checks these scripts every 5 minutes and logs any modifications via `logger`.

To verify manually:

```sh
# /opt/dropQbsd/libexec/verify_integrity
```

---

### Desktop Environment

dropQbsd works with any window manager. Two recommendations:

- **XFCE** — full desktop environment, familiar for users migrating from Windows/macOS. Lightweight by modern standards, well-supported on OpenBSD. Install: `/opt/dropQbsd/admin/pkg_add_via_pf xfce xfce-extras`
- **cwm** — OpenBSD's native stacking window manager. Minimal, keyboard-driven, zero dependencies beyond the base system. For a purer OpenBSD experience. Already installed — no packages needed.

Both work with `run_app` without additional configuration. Launch apps in any domain from the same desktop — `run_app` handles the X11 cookie forwarding transparently.

**Color scheme convention:**

| User | Role | Suggested theme color |
|------|------|-----------------------|
| `user` | Conductor | Dark grey |
| `userweb` | Web browser | Red |
| `usermail` | Email | Blue |
| `userdoc` | Documents | Green |

Set the theme per user via XFCE Settings → Appearance. This gives immediate visual feedback about which domain you're working in.

---

### File Managers

We recommend two file managers, both lightweight and OpenBSD-native:

- **Xfe** (X File Explorer) — graphical, dual-pane, familiar interface
- **Midnight Commander (`mc`)** — terminal-based, fast, ideal for remote sessions

Each domain user should use a distinct color scheme for immediate visual feedback about which domain you're working in. Example templates with coordinated colors are provided in `examples/`:

| Domain | Xfe background | mc skin |
|--------|---------------|---------|
| `userweb` | Blue | `examples/mc/userweb.ini` |
| `usermail` | Orchid | `examples/mc/usermail.ini` |
| `userdoc` | Green | `examples/mc/userdoc.ini` |

Install in each domain:

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf xfe mc
```

Launch via `run_app`:

```sh
$ /opt/dropQbsd/bin/run_app userdoc xfe /home/userdoc
$ /opt/dropQbsd/bin/run_app userdoc mc
```

Xfe configuration files live in `~/.config/xfe/` inside each domain's home. Copy the example color schemes from `examples/xfe/` and adjust to taste.

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

```
/etc/
├── doas.conf                  # Privilege escalation (from etc/doas.conf)
├── kshrc                      # Interactive shell config (from etc/kshrc)
├── pf.conf                    # Firewall rules (from etc/pf.conf)
├── profile                    # Shell profile (from etc/profile)
├── xsession                   # (from etc/xsession)
└── tables/
    ├── mailserver_hosts       # Mail server hostnames
    ├── services_hosts         # Service IPs and hostnames
    └── updates_ips            # Fastly CDN blocks (auto-generated)

/opt/dropQbsd/
├── bin/                       # User-facing commands
│   ├── run_app                # setuid blind gate (compiled)
│   ├── qmv                    # Move files into drop zone
│   ├── qcp                    # Copy files into drop zone
│   ├── qimport                # Import files from drop zone
│   ├── site_menu              # Password manager launcher
│   ├── xterm_root             # Launch xterm with root color scheme
│   ├── xterm_userdoc          # Launch xterm with userdoc color scheme
│   ├── xterm_usermail         # Launch xterm with usermail color scheme
│   └── xterm_userweb          # Launch xterm with userweb color scheme
├── libexec/                   # Internal logic (cron, export/pull, enforcement)
│   ├── enforce_drop           # Drop zone policing
│   ├── enforce_sync           # Sync directory sanitization
│   ├── ensure_updates_table   # Populate <updates> PF table
│   ├── export_www_to_drop     # www archival
│   ├── export_mail_to_drop    # Mail archival
│   ├── pull_www_from_drop     # www import
│   ├── pull_mail_from_drop    # Mail import
│   ├── run_app_impl           # Launch logic (ksh)
│   ├── update_mailserver_table # Mail server PF table
│   ├── update_services_table  # Services PF table
│   └── verify_integrity       # Script integrity check
├── admin/                     # System administration tools
│   ├── pkg_add_via_pf         # Package management
│   ├── syspatch_via_pf        # Security patches
│   ├── sysupgrade_via_pf      # Major release upgrade
│   └── update_openbsd_via_pf  # Full system update
├── src/
│   └── run_app_wrapper.c      # C source (reference)
└── tables/                    # Integrity verification keys

/home/
├── drop/                      # Exchange zone (root:drop, 2770)
│   ├── usermail_export/       # Mail archives (SGID 2770)
│   ├── userweb_export/        # www archives (SGID 2770)
│   └── _quarantine/           # Policy violations
├── user/                      # Conductor home
└── userdoc/                   # Document domain home (700)
│   └── Sync/                  # Syncthing root (optional)
├── usermail/                  # Email domain home (700)
└── userweb/                   # Browser domain home (700)
```


