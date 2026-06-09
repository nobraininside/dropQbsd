# dropQbsd

> Compartmentalization without virtualization. Just Unix, done right.

---

## What is this?

Take the core insight of Qubes OS — security through compartmentalization — and strip away the hypervisor. **dropQbsd** uses native OpenBSD user separation instead of heavy virtualization.

No multi-gigabyte VM images. No Xen. No moving parts you can't audit in an afternoon.

Each domain — web, mail, documents — runs as a dedicated user. They share nothing except a single policed exchange directory. A handful of ksh scripts, a solid `pf.conf`, and standard Unix permissions do the rest.

**Ten minutes to install. Rebuildable in thirty. Zero lock-in.**

---

## Architecture

### The Four Domains

| User | Role | Network |
|------|------|---------|
| `user` | Conductor — orchestrates, imports/exports, administers | Minimal (updates only) |
| `userweb` | Web browser — isolated from mail and LAN | HTTP/HTTPS only |
| `usermail` | Email client — isolated from web | Mail servers only |
| `userdoc` | Documents, sync, LAN storage — no direct internet | LAN + Syncthing |

All belong to the `drop` group. Home directories are `chmod 700` — no cross-domain snooping.

### The Drop Zone (`/home/drop`)

The **only bridge** between domains. A shared directory with strict rules:

- Files in transit: `440` (read-only for owner and group)
- Directories in transit: `570` (group can traverse and create sentinels)
- Export directories: SGID `2770`, owned by `root:drop`

No domain can delete another domain's files. No domain can modify files once placed. A cron job (`enforce_drop`) runs every 60 seconds, correcting permissions, quarantining violations, and cleaning abandoned artifacts.

**Import workflow:**

1. `qmv` moves a file into `/home/drop`, sets group to `drop`, permissions to `440`
2. `qcp` copies a file into `/home/drop` without deleting the original
3. `qimport` (run by `user`) copies the file out and leaves a `.imported` sentinel
4. `enforce_drop` sees the sentinel, deletes both it and the original — cleanup is automatic, nobody needs delete permissions

### The Conductor

`user` launches graphical apps inside any domain without switching users:

```sh
doas /usr/local/bin/dropQbsd/run_app userweb qutebrowser --temp-basedir
```

`run_app` copies the X11 cookie, creates an isolated runtime directory, and launches the app via `doas -u`. Works with any window manager. No Xephyr nesting. No special display manager configuration.

Disposable mode mounts a tmpfs in RAM for the app's home directory. When the app exits, the tmpfs is unmounted and everything is destroyed. Nothing survives. Ideal for browsers and untrusted files.
```sh
doas /usr/local/bin/dropQbsd/run_app --disposable userweb qutebrowser --temp-basedir
doas /usr/local/bin/dropQbsd/run_app --disposable 1G userweb chromium https://example.com
```
### Site Menu (Password Manager Integration)

`site_menu` reads a list of sites from `~/.config/dropQbsd/sites.conf` and presents a dropdown menu. Selecting a site copies the password to clipboard via `pass` and opens the site in a disposable browser.

Example `sites.conf`:
```sh
# Label|URL|pass_entry (optional)
Bank (my_user_id)|https://bank.example.com|finance/bank
ERP (my_user_id)|https://enterprise_resource.com|work/erp
Linkedin (my_user_id)|https://linkedin.com|social/linkedin
```

If the GPG passphrase has expired, a warning dialog appears telling the user to re-enter it in a terminal. The clipboard is automatically cleared after 10 seconds.

Requires: zenity, pass, xclip.

### Network Isolation

`pf.conf` enforces strict per-domain rules:

- **Default deny** — nothing gets out unless explicitly allowed
- userweb reaches ports 80/443 only
- usermail reaches only IPs in the <mailserver> table, only on mail ports
- userdoc reaches LAN subnets and Syncthing ports only
- Root has no permanent web access — only IPs in the <updates> table, populated on-demand

### Archival Pipeline

usermail → export_mail_to_drop → usermail_export → pull_mail_from_Drop → userdoc (3 backups)
userweb  → export_sites_to_Drop → userweb_export  → pull_sites_from_drop  → userdoc (3 backups)


Export files are `root:drop 440` — no domain user can modify them. Only `root` (via `enforce_drop`) can delete them. Integrity verified at each step.

### What You Get
- Compartmentalization without virtualization. Same security model as Qubes, zero overhead.
- Disposable browsers. tmpfs-backed, nothing survives exit. No persistent profiles.
- Site launcher with password integration. One click to open a site with password auto-copied, clipboard auto-cleared.
- Automated archival. Email and websites compressed, verified, pulled across domains on schedule.
- Quarantine with audit trail. Policy violations are isolated with an explanation ticket, not silently accepted.
- Root web access on-demand. ensure_updates_table populates the PF table, `pkg_add_via_pf` and `syspatch_via_pf` do their job. No telemetry. No background phoning home.
- Reinstallable in 30 minutes. No databases, no daemons, no state you can't reconstruct from scripts and `/etc`.

### Security Model
#### What dropQbsd Protects Against
- Malware propagation between domains. A compromised browser cannot read your email or access your documents.
- Network pivoting. A compromised web domain cannot reach your mail server or LAN.
- Persistent browser compromise. Disposable tmpfs profiles mean the attacker starts from zero each session.
- Accidental data leakage. Files can only move through the drop zone, which is policed every 60 seconds.
- Silent policy violations. Quarantine catches and explains every non-conforming file.
#### What dropQbsd Does NOT Protect Against
X11 input isolation. X11 uses a single shared cookie (MIT-MAGIC-COOKIE-1) for all clients on a display. Any compromised domain can keylog all other domains' keystrokes, capture screenshots, and snoop clipboard contents. This is a fundamental X11 limitation — not a dropQbsd bug.
#### Mitigations in place:
- Disposable browsers (tmpfs-backed) — compromise doesn't persist
- Per-session cookies via xenodm — stolen cookie expires at logout
- XTEST disabled where possible — blocks xinput test and xdotool

**Conductor compromise**. user can launch apps in any domain via doas run_app. If user is compromised, all domains are compromised — the conductor holds the keys. `pf` blocks user from browsing the web, but a local exploit or a malicious file executed as user is game over. Keep user minimal: no untrusted binaries, inspect files before importing.

**Kernel-level attacks**. All domains share one kernel. A kernel exploit in one domain compromises everything. This is the tradeoff for avoiding virtualization.

#### dropQbsd vs Qubes OS
|    |	DROPQBSD	| QUBES OS |
| -- | ---------- | -------- |
|Isolation mechanism | Unix users + permissions	| Xen hypervisor + VMs |
|RAM baseline |	512 MB |8 GB |
|Input isolation|	None (shared X11 cookie)|	Full (separate X servers)|
|Kernel isolation|	None (shared kernel|	Full (separate VM kernels)|
|Disk usage|	~2 GB (OpenBSD base)|	30+ GB (VM images)|
|Install time|	10 minutes|	1-2 hours|
|Rebuild from scratch|	30 minutes|	Hours/days|
|Complexity|	~500 lines of ksh|	Xen, Qubes tools, GUI stack|
|Threat model|	Malware, network attacks, data leaks|	Targeted state actors, kernel exploits|

**Choose dropQbsd** if you want compartmentalization without the weight of virtualization. **Choose Qubes OS** if your threat model includes kernel exploits or targeted input sniffing.

## Installation
### Prerequisites
- OpenBSD (any supported release)
- No additional packages required — everything is in the base system
### 1. Create Users and Group
```sh
groupadd drop

useradd -m -G drop userweb
useradd -m -G drop usermail
useradd -m -G drop userdoc
usermod -G drop user
```
### 2. Create Directory Structure
```sh
mkdir -p /usr/local/bin/dropQbsd/admin
mkdir -p /home/drop/userweb_export
mkdir -p /home/drop/usermail_export
mkdir -p /home/drop/_quarantine

chown root:drop /home/drop /home/drop/userweb_export /home/drop/usermail_export
chmod 750 /home/drop
chmod 2770 /home/drop/userweb_export /home/drop/usermail_export
chmod 750 /home/drop/_quarantine
```
### 3. Install Scripts

Copy the scripts/ directory from the repository to /usr/local/bin/dropQbsd/:
```sh
cp -r scripts /usr/local/bin/dropQbsd
```

#### Set permissions:
```sh
chmod 755 /usr/local/bin/dropQbsd/qmv
chmod 755 /usr/local/bin/dropQbsd/qcp
chmod 755 /usr/local/bin/dropQbsd/qimport
chmod 755 /usr/local/bin/dropQbsd/run_app
chmod 755 /usr/local/bin/dropQbsd/site_menu
chmod 755 /usr/local/bin/dropQbsd/export_sites_to_Drop.sh
chmod 755 /usr/local/bin/dropQbsd/export_mail_to_drop
chmod 755 /usr/local/bin/dropQbsd/pull_sites_from_drop
chmod 755 /usr/local/bin/dropQbsd/pull_mail_from_Drop
chmod 700 /usr/local/bin/dropQbsd/admin/*
chown -R root:wheel /usr/local/bin/dropQbsd
```
### 4. Install System Configuration Files
```sh
cp etc/pf.conf /etc/pf.conf
cp etc/doas.conf /etc/doas.conf
cp etc/profile /etc/profile
```

Create `/etc/mailserver_ips` with your mail server IPs (one per line). `/etc/pkg_mirror_ips` is auto-generated on first update if missing.

Review the locale settings in `/etc/profile` before applying — the example uses Italian regional formats. Adjust to your region or set all to en_US.UTF-8.

Reload the firewall:
```sh
pfctl -f /etc/pf.conf
```
### 5. Configure Cron (root)
```sh
* * * * * /usr/local/bin/dropQbsd/admin/enforce_drop
* * * * * /usr/local/bin/dropQbsd/admin/enforce_sync
```

Both scripts use an atomic mkdir lock to prevent overlapping runs.

### 6. Syncthing (optional)

Set up Syncthing for userdoc with the Sync directory at `/home/userdoc/Sync`. The `enforce_sync` script maintains correct permissions automatically.

### 7. Optional Configurations

Example configuration files for Thunar custom actions, Midnight Commander templates, and more are provided in the `examples/` directory.

## Daily Usage
### Moving Files Between Domains
**Copy a file into the drop zone (original stays in place)**
```sh
qcp ~/document.pdf
```

**Move a file into the drop zone (original is deleted)**
```sh
qmv ~/document.pdf
```
**Import from the drop zone into ~/Downloads**
```sh
qimport document.pdf
```

### Launching Apps in Domains
**Disposable browser (tmpfs-backed, nothing survives)**
```sh
doas /usr/local/bin/dropQbsd/run_app --disposable userweb /usr/local/bin/qutebrowser --temp-basedir
```

**Disposable browser with custom tmpfs size (for heavy sessions)**
```sh
doas /usr/local/bin/dropQbsd/run_app --disposable 1G userweb /usr/local/bin/qutebrowser --temp-basedir
```
**Open a site from the site menu (password auto-copied)**
```sh
/usr/local/bin/dropQbsd/site_menu
```

**Mail client in its isolated domain**
```sh
doas /usr/local/bin/dropQbsd/run_app usermail /usr/local/bin/claws-mail
```

**File manager for documents**
```sh
doas /usr/local/bin/dropQbsd/run_app userdoc /usr/local/bin/thunar /home/userdoc
```

**Tip**: Add these aliases to `~/.profile`:
```sh
alias run='doas /usr/local/bin/dropQbsd/run_app'
alias runweb='doas /usr/local/bin/dropQbsd/run_app --disposable userweb /usr/local/bin/qutebrowser --temp-basedir'
```
### Archiving
**Export websites (as userweb)**
```sh
export_sites_to_Drop.sh
```
**Export mail (as usermail)**
```sh
export_mail_to_drop
```
**Pull into document storage (as userdoc)**
```sh
pull_sites_from_drop
pull_mail_from_Drop
```
### System Updates
**Full update (patches + firmware + packages + orphan cleanup)**
```sh
doas update_openbsd_via_pf
```
**Security patches only**
```sh
doas syspatch_via_pf
```
**Install a specific package**
```sh
doas pkg_add_via_pf firefox
```
**Major release upgrade**
```sh
doas sysupgrade_via_pf
```
### Monitoring
**Check quarantine**
```sh
ls -la /home/drop/_quarantine/
cat /home/drop/_quarantine/*.txt
```
**Logs**
```sh
tail /var/log/dropQbsd_drop.log
tail /var/log/dropQbsd_sync.log
tail /var/log/system_update_pf.log
```
**Live PF traffic**
```sh
doas tcpdump -n -e -ttt -i pflog0
```

## Scripts Reference

### Core Workflow
| SCRIPT | RUN BY | PURPOSE |
| ------ | ------ | ------- |
| qmv	| Any user |	Move file/directory into /home/drop, set group and permissions |
| qcp	| Any user |	Copy file/directory into /home/drop without deleting the original |
| qimport |	user |	Copy from drop zone to ~/Downloads, create .imported sentinel |
| run_app | user | (via doas)	Launch graphical app as another domain user with X11 forwarding. --disposable mounts a tmpfs |
| site_menu |	user |	Dropdown menu of sites with pass integration, opens in disposable browser |

### Export/Import Pipeline
| SCRIPT | RUN BY	| PURPOSE |
| ------ | ------ | ------- |
| export_sites_to_Drop |	userweb |	Compress websites into userweb_export, verify integrity | 
| export_mail_to_drop |	usermail |	Compress mail into usermail_export |
| pull_sites_from_drop |	userdoc|	Import latest site archive, verify, keep 3 backups |
| pull_mail_from_Drop |	userdoc|	Import latest mail archive, verify, keep 3 backups |

### Enforcement (cron)
| SCRIPT	| RUN BY	| FREQUENCY	| PURPOSE |
|------|------|---------| -- |
| enforce_drop |	root |	Every minute |	Process sentinels, fix permissions, quarantine violations, clean abandoned files |
| enforce_sync |	root |	Every minute |	Fix owner/group/permissions in Sync directory |

### System Updates (root only)
| SCRIPT	| PURPOSE |
| ------- | ------- |
| ensure_updates_table |	Populate PF <updates> table with Fastly CDN blocks and custom mirrors |
| pkg_add_via_pf |	Install/update packages through restrictive PF |
| syspatch_via_pf |	Apply security patches through restrictive PF |
| sysupgrade_via_pf |	Upgrade to next OpenBSD release through restrictive PF (reboots) |
| update_openbsd_via_pf |	Full update: syspatch + fw_update + pkg_add -u + pkg_delete -a |

### Recovery

The entire system state is in four places:

- **Scripts** in `/usr/local/bin/dropQbsd/`
- **Users and groups** in `/etc/passwd`, `/etc/group`
- **PF rules** in `/etc/pf.conf`
- **Cron jobs** in `/var/cron/tabs/root`

### To rebuild from scratch:

- Install OpenBSD
- Copy the scripts
- Run the user/group creation commands
- Copy `pf.conf` and reload
- Add cron jobs

Thirty minutes. No databases to restore. No daemon state to reconstruct.

# Philosophy

dropQbsd is not a distribution. It's a configuration. It doesn't fork OpenBSD — it sits on top, using tools battle-tested for decades.

The goal is not to add layers of abstraction but to remove them. If Unix users and permissions already provide isolation, why add a hypervisor? If cron and find can police a shared directory, why run a daemon? If ksh and pfctl can manage network access for updates, why build a package manager wrapper?

Complexity is the enemy of security. dropQbsd keeps it simple, auditable, and boring — exactly what you want from a security tool.

# A Message to Privacy Professionals

**GDPR compliance is not a paperwork exercise**. If your organization processes personal data on Windows or macOS, you are running telemetry engines that phone home thousands of times per day — to Microsoft, to Apple, to third-party "partners" you never signed a data processing agreement with. You can draft privacy policies until your fingers bleed. The operating system undermines every word.

**Accountability**, the cornerstone of GDPR, rests on two pillars:

1. **Privacy by design** (Art. 25) — data protection must be built into the system, not bolted on after the fact.
2. **Staff training** (Art. 39) — personnel must be educated on secure data handling.

Mainstream operating systems fail both. They are closed-source, unauditable, laden with telemetry, and so complex (hundreds of millions of lines of code) that vulnerabilities are inevitable — the defect rate is a mathematical certainty, not a bug to be patched.

## The Alternative

**OpenBSD** is the only operating system in the world that undergoes continuous, funded, line-by-line security auditing. It ships with zero telemetry. Its code base is small enough to be understood. It is privacy by design — not as a marketing slogan, but as an engineering fact.

**dropQbsd** layers Qubes-style compartmentalization on top of OpenBSD without virtualization. Web browsing, email, and document storage run in separate security domains. A compromised browser cannot read your email. A compromised mail client cannot reach your file server. This is not a policy — it is enforced by Unix permissions and a strict firewall, policed every 60 seconds.

### What This Means for Your Organization
|	MAINSTREAM STACK |	DROPQBSD ON OPENBSD |
| **Telemetry** | Thousands of daily callbacks	| Zero |
| **Auditability**	| Closed source, trust us |	Fully auditable, ~500 lines of glue |
| **Licensing cost**	| Windows/Mac + Office + AV licenses	| $0 |
| **Hardware lifecycle** | 5-7 years (forced obsolescence) |	10+ years (runs on 512 MB RAM) |
| **Antivirus** |	Mandatory, reactive, expensive|	Unnecessary — compartmentalization prevents propagation |
| **Privacy by design** |	Impossible (closed source) |	Inherent |
| **Staff training**	| "Don't click phishing links" |	Learning a security-conscious OS — real education |

### The Accountability Argument

When your organization adopts dropQbsd, you satisfy GDPR accountability in a way that no policy document ever could:

Privacy by design is not a claim — it is the architecture. The system cannot exfiltrate data because it has no telemetry. Malware cannot propagate because domains are isolated.
Staff training is not a checkbox webinar — it is the daily act of using an operating system that requires and rewards security awareness. Your employees become security-conscious by necessity, not by decree.

The budget shifts from remediating breaches and renewing licenses to training personnel — exactly where GDPR intended it.

### A Challenge to DPOs and Security Consultants

If you advise clients on GDPR compliance while deploying them on Windows, ask yourself: have you implemented privacy by design, or have you implemented privacy by document? Can you audit the operating system your client entrusts with personal data? Do you know what telemetry leaves the building at 3 AM?

If the answer to any of these is no, the paperwork is a fig leaf.

dropQbsd offers a different path: an auditable, telemetry-free, compartmentalized operating system that costs nothing to license, runs on hardware you already own, and turns compliance from a legal fiction into an engineering reality.

**Security is simplicity. Privacy is auditable. Accountability is provable. Anything less is a gamble dressed in legalese.**

## License

ISC. See (LICENSE)[https://github.com/nobraininside/dropQbsd/blob/main/LICENSE].
