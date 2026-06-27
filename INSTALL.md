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
# usermod -G drop user
```

---

## 2. Create Directory Structure

```sh
# mkdir -p /usr/local/bin/dropQbsd/admin
# mkdir -p /home/drop/userweb_export
# mkdir -p /home/drop/usermail_export
# mkdir -p /home/drop/_quarantine
# mkdir -p /etc/tables

# chown root:drop /home/drop /home/drop/userweb_export /home/drop/usermail_export
# chmod 770 /home/drop
# chmod 2770 /home/drop/userweb_export /home/drop/usermail_export
# chmod 750 /home/drop/_quarantine
# chmod 755 /etc/tables
```

---

## 3. Install Scripts

Copy the `scripts/` directory from the repository to `/usr/local/bin/dropQbsd/`:

```sh
# cp -r scripts /usr/local/bin/dropQbsd
```

Set permissions:

```sh
# chmod 755 /usr/local/bin/dropQbsd/qmv
# chmod 755 /usr/local/bin/dropQbsd/qcp
# chmod 755 /usr/local/bin/dropQbsd/qimport
# chmod 755 /usr/local/bin/dropQbsd/run_app_impl
# chmod 755 /usr/local/bin/dropQbsd/site_menu
# chmod 755 /usr/local/bin/dropQbsd/export_sites_to_Drop.sh
# chmod 755 /usr/local/bin/dropQbsd/export_mail_to_drop
# chmod 755 /usr/local/bin/dropQbsd/pull_sites_from_drop
# chmod 755 /usr/local/bin/dropQbsd/pull_mail_from_Drop
# chmod 700 /usr/local/bin/dropQbsd/admin/*
# chown -R root:wheel /usr/local/bin/dropQbsd
```

---

## 4. Build the `run_app` Blind Gate

This is the core of dropQbsd's privilege model. `run_app` is split into three files:

| File | Purpose |
|------|---------|
| `run_app_wrapper.c` | C source — 10 lines, compiled once |
| `run_app` | Compiled setuid binary — the immutable gate `user` invokes |
| `run_app_impl` | ksh script — all the logic, editable without recompilation |

**Create the wrapper source:**

```sh
cat > /usr/local/bin/dropQbsd/run_app_wrapper.c << 'EOF'
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (setuid(0) != 0)
        _exit(1);
    execv("/usr/local/bin/dropQbsd/run_app_impl", argv);
    _exit(1);
}
EOF
```

**Verify the impl script shebang:**

```sh
# head -1 /usr/local/bin/dropQbsd/run_app_impl   # must be #!/bin/ksh
```

**Compile statically and set the setuid bit:**

```sh
# doas cc -static -o /usr/local/bin/dropQbsd/run_app \
    /usr/local/bin/dropQbsd/run_app_wrapper.c

# doas chown root:wheel /usr/local/bin/dropQbsd/run_app
# doas chmod 4755 /usr/local/bin/dropQbsd/run_app          # setuid root
# doas chown root:wheel /usr/local/bin/dropQbsd/run_app_impl
# doas chmod 755 /usr/local/bin/dropQbsd/run_app_impl
```

**Verify:**

```sh
# From user:
$ /usr/local/bin/dropQbsd/run_app userdoc xterm
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

```sh
# cp etc/pf.conf /etc/pf.conf
# cp etc/profile /etc/profile
```

Review the locale settings in `/etc/profile` — the example uses Italian regional formats. Adjust to your region or set all to `en_US.UTF-8`.

---

## 7. Configure PF Tables

### Mail Server IPs

Create `/etc/tables/mailserver_hosts` with your mail server hostnames, one per line:

```sh
# Example /etc/tables/mailserver_hosts
mail.example.com
imap.example.com
smtp.example.com
```

```sh
# chmod 644 /etc/tables/mailserver_hosts
```

### Services IPs

Create `/etc/tables/services_hosts` with static IPs and hostnames (prefix hostnames with `@`):

```sh
# Example /etc/tables/services_hosts
# Static IPs:
198.51.100.10          # cPanel hosting
# Hostnames (resolved each run via userweb DNS):
@ssh.github.com        # GitHub SSH over 443
```

```sh
# chmod 644 /etc/tables/services_hosts
```

### Updates IPs (auto-generated)

```sh
# touch /etc/tables/updates_ips
# chmod 644 /etc/tables/updates_ips
```

Sì, va documentato. Aggiungo una sezione in INSTALL.md, dopo "Configure PF Tables" e prima di "Reload the Firewall":


### How PF Tables Work

dropQbsd uses three PF tables to manage network access without exposing
provider IPs in the firewall rules:

| Table | Config file | Update script | Purpose |
|-------|-------------|---------------|---------|
| `<mailserver>` | `/etc/tables/mailserver_hosts` | `update_mailserver_table` | Mail server IPs for `usermail` |
| `<services>` | `/etc/tables/services_hosts` | `update_services_table` | External services (SSH, cPanel, GitHub) for `userweb` |
| `<updates>` | `/etc/tables/updates_ips` | `ensure_updates_table` | OpenBSD mirror IPs for system updates |

**Adding an IP to a table:**

```sh
# One-time (persists until reboot or manual flush):
doas pfctl -t services -T add 198.51.100.10

# Permanent (add to config file, survives reboot):
echo '198.51.100.10' | doas tee -a /etc/tables/services_hosts
doas /usr/local/bin/dropQbsd/admin/update_services_table
```

**Adding a hostname (resolved automatically):**

```sh
echo '@difesadigitale.xyz' | doas tee -a /etc/tables/services_hosts
doas /usr/local/bin/dropQbsd/admin/update_services_table
```

Hostnames prefixed with `@` are resolved via `userweb` DNS each time the update script runs (every 5 minutes via cron). This keeps IPs current without manual intervention.

---

## 8. Reload the Firewall

```sh
# pfctl -f /etc/pf.conf
```

Populate the services table with your static IPs:

```sh
# pfctl -t services -T add 198.51.100.10
```

Run the mail server table update:

```sh
# /usr/local/bin/dropQbsd/admin/update_mailserver_table
```

---

## 9. Configure Cron (root)

```sh
* * * * * /usr/local/bin/dropQbsd/admin/enforce_drop
* * * * * /usr/local/bin/dropQbsd/admin/enforce_sync
*/15 * * * * /usr/local/bin/dropQbsd/admin/update_mailserver_table
*/5 * * * * /usr/local/bin/dropQbsd/admin/update_services_table
*/5 * * * * /usr/local/bin/dropQbsd/admin/verify_integrity
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

## Optional Components

These are not required for dropQbsd to function. Install only what you need.

---

### Syncthing — LAN File Synchronization

Set up Syncthing for `userdoc` with the Sync directory at `/home/userdoc/Sync`. The `enforce_sync` script maintains correct permissions automatically.

**Installation:**

```sh
# /usr/local/bin/dropQbsd/admin/pkg_add_via_pf syncthing
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
$ /usr/local/bin/dropQbsd/run_app userdoc /usr/local/bin/qutebrowser --temp-basedir http://127.0.0.1:8384
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
# /usr/local/bin/dropQbsd/admin/pkg_add_via_pf zenity pass xclip
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
$ /usr/local/bin/dropQbsd/site_menu
```

The site opens in a disposable browser (tmpfs-backed). Nothing survives after the browser closes.

---

### Integrity Verification

dropQbsd can cryptographically verify that critical scripts have not been tampered with, using OpenBSD's built-in `signify(1)`.

**Setup:**

```sh
# Generate key pair (keep the .sec key offline)
signify -G -n -p /etc/tables/dropQbsd.pub -s /root/dropQbsd.sec

# Sign the critical scripts
sha256 /usr/local/bin/dropQbsd/run_app_impl \
       /usr/local/bin/dropQbsd/qmv \
       /usr/local/bin/dropQbsd/qcp \
       /usr/local/bin/dropQbsd/qimport \
       /usr/local/bin/dropQbsd/admin/enforce_drop \
       /usr/local/bin/dropQbsd/admin/enforce_sync \
    | signify -S -s /root/dropQbsd.sec -m - \
        -x /etc/tables/dropQbsd_scripts.sha256.sig

# Remove the private key — keep it offline
rm /root/dropQbsd.sec
```

The `verify_integrity` cron job (installed in step 9) checks these scripts every 5 minutes and logs any modifications via `logger`.

To verify manually:

```sh
# /usr/local/bin/dropQbsd/admin/verify_integrity
```

---

### Desktop Environment

dropQbsd works with any window manager. Two recommendations:

- **XFCE** — full desktop environment, familiar for users migrating from Windows/macOS. Lightweight by modern standards, well-supported on OpenBSD. Install: `/usr/local/bin/dropQbsd/admin/pkg_add_via_pf xfce xfce-extras`
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

### File Managers

We recommend two file managers, both lightweight and OpenBSD-native:

- **Xfe** (X File Explorer) — graphical, dual-pane, familiar interface
- **Midnight Commander (`mc`)** — terminal-based, fast, ideal for remote sessions

Each domain user should use a distinct color scheme for immediate visual
feedback about which domain you're working in. Example templates with
coordinated colors are provided in `examples/`:

| Domain | Xfe background | mc skin |
|--------|---------------|---------|
| `userweb` | Blue | `examples/mc/userweb.ini` |
| `usermail` | Orchid | `examples/mc/usermail.ini` |
| `userdoc` | Green | `examples/mc/userdoc.ini` |

Install in each domain:

```sh
# /usr/local/bin/dropQbsd/admin/pkg_add_via_pf xfe mc

Launch via run_app:
$ /usr/local/bin/dropQbsd/run_app userdoc xfe /home/userdoc
$ /usr/local/bin/dropQbsd/run_app userdoc mc
```

Xfe configuration files live in `~/.config/xfe/` inside each domain's home.
Copy the example color schemes from `examples/xfe/`` and adjust to taste.

---

## Directory Structure Reference

After a full installation, your system will have:

```
/etc/
├── pf.conf                    # Firewall rules (from etc/pf.conf)
├── doas.conf                  # Privilege escalation (from etc/doas.conf)
├── profile                    # Shell profile (from etc/profile)
├── tables/
│   ├── mailserver_hosts       # Mail server hostnames
│   ├── services_hosts         # Service IPs and hostnames
│   └── updates_ips            # Fastly CDN blocks (auto-generated)

/usr/local/bin/dropQbsd/
├── run_app                    # setuid blind gate (compiled)
├── run_app_impl               # Launch logic (ksh)
├── run_app_wrapper.c          # C source (reference)
├── qmv                        # Move files into drop zone
├── qcp                        # Copy files into drop zone
├── qimport                    # Import files from drop zone
├── site_menu                  # Password manager launcher
├── export_sites_to_Drop.sh    # Website archival
├── export_mail_to_drop        # Mail archival
├── pull_sites_from_drop       # Website import
├── pull_mail_from_Drop        # Mail import
└── admin/
    ├── enforce_drop           # Drop zone policing
    ├── enforce_sync           # Sync directory sanitization
    ├── ensure_updates_table   # Populate <updates> PF table
    ├── pkg_add_via_pf         # Package management
    ├── syspatch_via_pf        # Security patches
    ├── sysupgrade_via_pf      # Major release upgrade
    ├── update_openbsd_via_pf  # Full system update
    ├── update_mailserver_table # Mail server PF table
    ├── update_services_table  # Services PF table
    └── verify_integrity       # Script integrity check

/home/
├── drop/                      # Exchange zone (root:drop, 770)
│   ├── userweb_export/        # Website archives (SGID 2770)
│   ├── usermail_export/       # Mail archives (SGID 2770)
│   └── _quarantine/           # Policy violations
├── user/                      # Conductor home
├── userweb/                   # Browser domain home (700)
├── usermail/                  # Email domain home (700)
└── userdoc/                   # Document domain home (700)
    └── Sync/                  # Syncthing root (optional)
```
