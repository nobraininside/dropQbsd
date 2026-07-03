# dropQbsd

![Status](https://img.shields.io/badge/status-beta-orange)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![License](https://img.shields.io/badge/license-ISC-green)

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
| `user` | Conductor — orchestrates, imports/exports, administers | None (no direct network access) |
| `userweb` | Web browser — isolated from mail and LAN | HTTP/HTTPS only |
| `usermail` | Email client — isolated from web | Mail servers only |
| `userdoc` | Documents, sync, LAN storage — no direct internet | LAN + Syncthing |

All belong to the `drop` group. Home directories are `chmod 700` — no cross-domain snooping.

### The Drop Zone (`/home/drop`)

The **only bridge** between domains. A shared directory with strict rules:

- `/home/drop` is `770 root:drop` — all domains in the `drop` group can read and place files
- Files in transit: `440` (read-only for owner and group)
- Directories in transit: `570` (group can traverse)
- Export directories: SGID `2770`, owned by `root:drop`

No domain can modify files once placed (enforced by 440 permissions). Cleanup is handled by `enforce_drop` on its regular cycle. A cron job (`enforce_drop`) runs every 60 seconds, correcting permissions, quarantining violations, and cleaning abandoned artifacts.

**Import workflow:**

1. `qmv` moves a file into `/home/drop` via an atomic staging directory. Permissions are locked before the file is visible to other domains.
2. `qcp` copies a file into `/home/drop` without deleting the original.
3. `qimport` copies the file out into `~/Downloads`.
4. `enforce_drop` removes abandoned files after 30 minutes. No sentinels, no domain write access to the drop zone — cleanup is purely time-based.

### The Conductor — `run_app` Architecture

`user` launches graphical apps inside any domain without switching users. The mechanism is a three-file split designed to eliminate the attack surface of privilege escalation:

| File | Type | Role |
|------|------|------|
| `bin/run_app` | Compiled binary (setuid root) | Immutable gate — 10 lines of C, no logic, no attack surface |
| `libexec/run_app_impl` | ksh script | All the logic — maintainable without recompilation |
| `src/run_app_wrapper.c` | C source | Kept for reference; only needed if OpenBSD ABI breaks |

**How it works:**

1. `user` invokes `run_app` — the **only** file `user` ever touches directly
2. `run_app` calls `setuid(0)`, escalates to root, then `execv` transforms into `run_app_impl` passing all arguments through
3. `run_app_impl` (now running as root) locates the X11 cookie from xenodm's auth directory, creates an isolated runtime directory (or tmpfs in disposable mode), sets `HOME`, `DISPLAY`, `XAUTHORITY`, `XDG_RUNTIME_DIR`, and launches the application via `su -l`

The binary is the **blind gate**: it can do exactly one thing — call `run_app_impl`. No parsing, no branching, no logic. Immutable after compilation. If you need to add a domain, change paths, or tweak cleanup behavior, you edit `run_app_impl` — a plain ksh script. No recompilation. The attack surface stays frozen at 10 lines of C.

**`doas.conf` is minimal** — only `permit nopass root`. `user` has no `doas` access at all. The compartmentalization is sealed: `user` cannot escalate to root through any path except the blind gate, and the blind gate can only launch domain applications.

**Disposable mode** mounts a tmpfs in RAM for the app's home directory. When the app exits, the tmpfs is unmounted and everything is destroyed. Nothing survives. Ideal for browsers and untrusted files.

```sh
$ /opt/dropQbsd/bin/run_app --disposable userweb qutebrowser --temp-basedir
$ /opt/dropQbsd/bin/run_app --disposable 1G userweb chromium https://example.com
```

Downloads made in disposable mode are bridged to the real `/home/$USER/Downloads` via symlink — files survive browser exit.

### Network Isolation

`pf.conf` enforces strict per-domain rules:

- **Default deny** — nothing gets out unless explicitly allowed
- `userweb` reaches ports 80/443 only, blocked from LAN and localhost
- `usermail` reaches only IPs in the `<mailserver>` table, only on mail ports
- `userdoc` reaches LAN subnets and Syncthing ports only
- Root has no permanent network access — only IPs in the `<updates>` table, populated on-demand

Service IPs and mail server IPs are managed dynamically via PF tables, populated from configuration files in `/etc/tables/`. No provider IPs are exposed in the public repository.

### Archival Pipeline

```
usermail → export_mail_to_drop → usermail_export → pull_mail_from_drop → userdoc (1 backup)
userweb  → export_www_to_drop  → userweb_export  → pull_www_from_drop  → userdoc (3 backups)
```

Export files are `root:drop 440` — no domain user can modify them. Integrity verified at each step.

### What You Get

- **Compartmentalization without virtualization.** Same security model as Qubes, zero overhead.
- **Blind-gate privilege escalation.** `run_app` is a 10-line setuid binary that can only call `run_app_impl`. Logic stays in auditable ksh. Attack surface is frozen.
- **Disposable browsers.** tmpfs-backed, nothing survives exit. No persistent profiles. Downloads survive via symlink bridge.
- **Automated archival.** Email and websites compressed, verified, pulled across domains on schedule.
- **Quarantine with audit trail.** Policy violations are isolated with an explanation ticket, not silently accepted.
- **Root web access on-demand.** `ensure_updates_table` populates the PF table, `pkg_add_via_pf` and `syspatch_via_pf` do their job. No telemetry. No background phoning home.
- **Reinstallable in 30 minutes.** No databases, no daemons, no state you can't reconstruct from scripts and `/etc`.
- **Integrity verification.** Critical scripts are checksummed and verified via `signify(1)` on a cron schedule.
- **Dynamic PF tables.** Mail server and service IPs are managed via `/etc/tables/` — no provider details in the repository.

### Optional Components

dropQbsd is fully functional with just the base system. Several optional components are available for a smoother experience — see [INSTALL.md](INSTALL.md) for setup instructions:

- **Syncthing** — LAN file synchronization for the document domain
- **Site Menu + pass** — password manager integration with one-click site launching
- **Integrity verification** — cryptographic checksums via `signify(1)`
- **Color schemes** — coordinated skins for Midnight Commander, Xfe, Thunar and related editors per domain

---

### Security Model

#### What dropQbsd Protects Against

- **Malware propagation between domains.** A compromised browser cannot read your email or access your documents.
- **Network pivoting.** A compromised web domain cannot reach your mail server or LAN. RFC 1918 addresses are explicitly blocked for `userweb`.
- **Persistent browser compromise.** Disposable tmpfs profiles mean the attacker starts from zero each session.
- **Accidental data leakage.** Files can only move through the drop zone, which is policed every 60 seconds.
- **Silent policy violations.** Quarantine catches and explains every non-conforming file.
- **Privilege escalation via `doas`.** `user` has no `doas` access. The only path to root is the blind-gate `run_app` binary, which can only launch domain applications.

#### What dropQbsd Does NOT Protect Against

**X11 input isolation.** X11 uses a single shared cookie (MIT-MAGIC-COOKIE-1) for all clients on a display. Any compromised domain can keylog all other domains' keystrokes, capture screenshots, and snoop clipboard contents. This is a fundamental X11 limitation — not a dropQbsd bug.

**Mitigations in place:**
- Disposable browsers (tmpfs-backed) — compromise doesn't persist
- Per-session cookies via xenodm — stolen cookie expires at logout
- XTEST disabled where possible — blocks xinput test and xdotool

**Conductor compromise.** `user` can launch apps in any domain via `run_app`. If `user` is compromised, all domains are compromised — the conductor holds the keys. `pf` blocks `user` from browsing the web, but a local exploit or a malicious file executed as `user` is game over. Keep `user` minimal: no untrusted binaries, inspect files before importing.

**Kernel-level attacks.** All domains share one kernel. A kernel exploit in one domain compromises everything. This is the tradeoff for avoiding virtualization.

#### dropQbsd vs Qubes OS

| | DROPQBSD | QUBES OS |
| -- | ---------- | -------- |
| Isolation mechanism | Unix users + permissions | Xen hypervisor + VMs |
| RAM baseline | 512 MB | 8 GB |
| Input isolation | None (shared X11 cookie) | Full (separate X servers) |
| Kernel isolation | None (shared kernel) | Full (separate VM kernels) |
| Disk usage | ~2 GB (OpenBSD base) | 30+ GB (VM images) |
| Install time | 10 minutes | 1-2 hours |
| Rebuild from scratch | 30 minutes | Hours/days |
| Complexity | ~500 lines of ksh + 10 lines of C | Xen, Qubes tools, GUI stack |
| Privilege model | Blind-gate setuid binary, no doas for user | Dom0/Qubes Manager |
| Threat model | Malware, network attacks, data leaks | Targeted state actors, kernel exploits |

**Choose dropQbsd** if you want compartmentalization without the weight of virtualization. **Choose Qubes OS** if your threat model includes kernel exploits or targeted input sniffing.

---

## Daily Usage

### Moving Files Between Domains

**Copy a file into the drop zone (original stays in place):**

```sh
$ /opt/dropQbsd/bin/qcp ~/document.pdf
```

**Move a file into the drop zone (original is deleted):**

```sh
$ /opt/dropQbsd/bin/qmv ~/document.pdf
```

**Import from the drop zone into ~/Downloads:**

```sh
$ /opt/dropQbsd/bin/qimport /home/drop/document.pdf
```

### Launching Apps in Domains (as `user`)

**Disposable browser (tmpfs-backed, nothing survives):**

```sh
$ /opt/dropQbsd/bin/run_app --disposable userweb /usr/local/bin/qutebrowser --temp-basedir
```

**Tip:** Each browser needs a different flag for temporary profiles:
- Qutebrowser: `--temp-basedir`
- Chromium / Ungoogled-chromium: `--temp-profile`
- Firefox: `--private-window` (no persistent profile in private mode)

Disposable mode already destroys everything on exit — these flags add an
extra layer by preventing the browser from writing to disk at all during
the session.

**Disposable browser with custom tmpfs size (for heavy sessions):**

```sh
$ /opt/dropQbsd/bin/run_app --disposable 1G userweb /usr/local/bin/qutebrowser --temp-basedir
```

**Open a site from the site menu (password auto-copied):**

```sh
$ /opt/dropQbsd/bin/site_menu
```

**Mail client in its isolated domain:**

```sh
$ /opt/dropQbsd/bin/run_app usermail /usr/local/bin/claws-mail
```

**File manager for documents:**

```sh
$ /opt/dropQbsd/bin/run_app userdoc /usr/local/bin/thunar /home/userdoc
```

Aliases for common commands are provided in `/etc/profile` and available
to all users:
```sh
alias run='/opt/dropQbsd/bin/run_app'
alias runweb='/opt/dropQbsd/bin/run_app --disposable userweb /usr/local/bin/qutebrowser --temp-basedir'
alias runmail='/opt/dropQbsd/bin/run_app usermail /usr/local/bin/claws-mail'
alias rundoc='/opt/dropQbsd/bin/run_app userdoc /usr/local/bin/thunar /home/userdoc'
```

Note: no `doas` prefix — `run_app` is setuid root, so `user` invokes it directly. Commands in `/opt/dropQbsd/bin/` are available to all users via PATH.

### Archiving

Export and pull operations are automated via root's crontab. To run them manually:

**Export www (as userweb):**

```sh
$ /opt/dropQbsd/libexec/export_www_to_drop
```

**Export mail (as usermail):**

```sh
$ /opt/dropQbsd/libexec/export_mail_to_drop
```

**Pull into document storage (as userdoc):**

```sh
$ /opt/dropQbsd/libexec/pull_www_from_drop
$ /opt/dropQbsd/libexec/pull_mail_from_drop
```

### System Updates

All update commands are run as root. Root has no permanent network access —
the `<updates>` PF table is populated on demand by each script.

**Full update (patches + firmware + packages + orphan cleanup):**

```sh
# /opt/dropQbsd/admin/update_openbsd_via_pf
```

**Security patches only:**

```sh
# /opt/dropQbsd/admin/syspatch_via_pf
```

**Install a specific package:**

```sh
# /opt/dropQbsd/admin/pkg_add_via_pf firefox
```

**Major release upgrade:**

```sh
# /opt/dropQbsd/admin/sysupgrade_via_pf
```

### Monitoring

**Check quarantine:**

```sh
$ ls -la /home/drop/_quarantine/
$ cat /home/drop/_quarantine/*.txt
```

**Logs:**

```sh
$ tail /var/log/dropQbsd_drop.log
$ tail /var/log/dropQbsd_sync.log
$ tail /var/log/system_update_pf.log
```

**Live PF traffic:**

```sh
# tcpdump -n -e -ttt -i pflog0
```

**Integrity verification:**

```sh
# /opt/dropQbsd/libexec/verify_integrity
```

---

## Scripts Reference

### Core Workflow

| Script | Run by | Purpose |
| ------ | ------ | ------- |
| `qmv` | Any user | Move file/directory into `/home/drop` via atomic staging, set group and permissions |
| `qcp` | Any user | Copy file/directory into `/home/drop` without deleting the original |
| `qimport` | Any user | Copy from drop zone to `~/Downloads` |
| `run_app` | user (setuid root) | Blind-gate binary. Escalates to root, execs `run_app_impl`. The only privileged entry point `user` can touch. |
| `run_app_impl` | root (via `run_app`) | ksh script with all launch logic — X11 cookie, runtime dir, tmpfs, `su -l`. Editable without recompilation. |
| `run_app_wrapper.c` | — (source only) | 10-line C source. Kept for reference; only needed if OpenBSD ABI breaks. |


### Export/Import Pipeline

These scripts are run automatically by root's crontab on a schedule.
They can also be run manually by their respective domain users.

| Script | Domain | Purpose |
| ------ | ------ | ------- |
| `export_www_to_drop` | userweb | Compress `~/www` into `userweb_export`, verify integrity |
| `export_mail_to_drop` | usermail | Compress mail into `usermail_export` |
| `pull_www_from_drop` | userdoc | Import latest site archive, verify, keep 3 backups |
| `pull_mail_from_drop` | userdoc | Import latest mail archive, verify, keep 1 backup |

### Enforcement (cron)

| Script | Run by | Frequency | Purpose |
| ------ | ------ | --------- | ------- |
| `enforce_drop` | root | Every minute | Fix permissions, quarantine violations, clean abandoned files, rate-limit monitoring |
| `enforce_sync` | root | Every minute | Fix owner/group/permissions in Sync directory |

### PF Table Management (cron)

| Script | Run by | Purpose |
| ------ | ------ | ------- |
| `update_mailserver_table` | root | Resolve mail server hostnames via `userweb` DNS, populate `<mailserver>` table |
| `update_services_table` | root | Populate `<services>` table from `/etc/tables/services_hosts` (static IPs and hostnames) |

### System Updates (root only)

All update commands are run as root. Root has no permanent network access —
the `<updates>` PF table is populated on demand by each script.

| Script | Run by | Purpose |
| ------ | ------ | ------- |
| `ensure_updates_table` | root | Populate PF `<updates>` table with Fastly CDN blocks and custom mirrors |
| `pkg_add_via_pf` | root | Install/update packages through restrictive PF; flushes `<updates>` on exit |
| `syspatch_via_pf` | root | Apply security patches through restrictive PF |
| `sysupgrade_via_pf` | root | Upgrade to next OpenBSD release through restrictive PF (reboots) |
| `update_openbsd_via_pf` | root | Full update: syspatch + fw_update + pkg_add -u + pkg_delete -a |

### Integrity

| Script | Run by | Purpose |
| ------ | ------ | ------- |
| `verify_integrity` | root (cron) | Verify SHA256 checksums of critical scripts via `signify(1)` |

### Recovery

The entire system state is in a few places:

- **Scripts** in `/opt/dropQbsd/`
- **Users and groups** in `/etc/passwd`, `/etc/group`
- **PF rules** in `/etc/pf.conf`
- **PF table configs** in `/etc/tables/`
- **Cron jobs** in `/var/cron/tabs/root`

**To rebuild from scratch:**

- Install OpenBSD
- Copy the scripts to `/opt/dropQbsd/`
- Run the user/group creation commands
- Compile the `run_app` blind gate and set the setuid bit
- Copy `pf.conf` and reload
- Populate `/etc/tables/` with your provider IPs
- Add cron jobs

Thirty minutes. No databases to restore. No daemon state to reconstruct.

---

## Philosophy

**dropQbsd** is not a distribution. It's a configuration. It doesn't fork OpenBSD — it sits on top, using tools battle-tested for decades.

The goal is not to add layers of abstraction but to remove them. If Unix users and permissions already provide isolation, why add a hypervisor? If `cron` and `find` can police a shared directory, why run a daemon? If `ksh` and `pfctl` can manage network access for updates, why build a package manager wrapper? If a 10-line setuid C binary can gate privilege escalation, why give `user` a `doas` ticket to the whole system?

**Complexity is the enemy of security**. dropQbsd keeps it simple, auditable, and boring — exactly what you want from a security tool.

---

## A Message to Privacy Professionals

**GDPR compliance is not a paperwork exercise.** If your organization processes personal data on Windows or macOS, you are running telemetry engines that phone home thousands of times per day — to Microsoft, to Apple, to third-party "partners" you never signed a data processing agreement with. You can draft privacy policies until your fingers bleed. The operating system undermines every word.

**Accountability**, the cornerstone of GDPR, rests on two pillars:

1. **Privacy by design** (Art. 25) — data protection must be built into the system, not bolted on after the fact.
2. **Staff training** (Art. 39) — personnel must be educated on secure data handling.

Mainstream operating systems fail both. They are closed-source, unauditable, laden with telemetry, and so complex (hundreds of millions of lines of code) that vulnerabilities are inevitable — the defect rate is a mathematical certainty, not a bug to be patched.

### The Alternative

**OpenBSD** is the only operating system in the world that undergoes continuous, funded, line-by-line security auditing. It ships with zero telemetry. Its code base is small enough to be understood. It is privacy by design — not as a marketing slogan, but as an engineering fact.

**dropQbsd** layers Qubes-style compartmentalization on top of OpenBSD without virtualization. Web browsing, email, and document storage run in separate security domains. A compromised browser cannot read your email. A compromised mail client cannot reach your file server. This is not a policy — it is enforced by Unix permissions and a strict firewall, policed every 60 seconds.

### What This Means for Your Organization

| | MAINSTREAM STACK | DROPQBSD ON OPENBSD |
| -- | -- | -- |
| **Telemetry** | Thousands of daily callbacks | Zero |
| **Auditability** | Closed source, trust us | Fully auditable, ~500 lines of ksh + 10 lines of C |
| **Licensing cost** | Windows/Mac + Office + AV licenses | \$0 |
| **Hardware lifecycle** | 5-7 years (forced obsolescence) | 10+ years (runs on 512 MB RAM) |
| **Antivirus** | Mandatory, reactive, expensive | Unnecessary — compartmentalization prevents propagation |
| **Privacy by design** | Impossible (closed source) | Inherent |
| **Staff training** | "Don't click phishing links" | Learning a security-conscious OS — real education |

### The Accountability Argument

When your organization adopts dropQbsd, you satisfy GDPR accountability in a way that no policy document ever could:

- **Privacy by design is not a claim — it is the architecture.** The system cannot exfiltrate data because it has no telemetry. Malware cannot propagate because domains are isolated.
- **Staff training is not a checkbox webinar — it is the daily act** of using an operating system that requires and rewards security awareness. Your employees become security-conscious by necessity, not by decree.

The budget shifts from remediating breaches and renewing licenses to training personnel — exactly where GDPR intended it.

### A Challenge to DPOs and Security Consultants

If you advise clients on GDPR compliance while deploying them on Windows, macOS, or even some mainstream Linux distributions, ask yourself: have you implemented privacy by design, or have you implemented privacy by document? Can you audit the operating system your client entrusts with personal data? Do you know what telemetry leaves the building at 3 AM?¹

If the answer to any of these is no, the paperwork is a fig leaf.

dropQbsd offers a different path: an auditable, telemetry-free, compartmentalized operating system that costs nothing to license, runs on hardware you already own, and turns compliance from a legal fiction into an engineering reality.

**Security is simplicity. Privacy is auditable. Accountability is provable. Anything less is a gamble dressed in legalese.**

¹ Yes, literally at 3 AM. Windows telemetry runs on a schedule that includes early-morning hours. It transmits hardware diagnostics, usage patterns, installed applications, and in some configurations, the content
of documents and browsing history — all without explicit consent beyond the click-through EULA. macOS does the same via `rapportd`, `trustd`, and Transparencyd. Ubuntu collects system information via `ubuntu-report`
and snap telemetry. None of these can be fully disabled without breaking functionality or voiding support agreements. OpenBSD ships with none of this. Zero.

## Roadmap

- [x] Desktop standalone — four domains, PF isolation, drop zone
- [x] Disposable browser sessions (tmpfs-backed)
- [x] Site menu with password manager integration
- [x] Archival pipeline (email + websites → userdoc)
- [ ] Install script (`install.sh`)
- [ ] OpenBSD ports tree submission
---

## Status ##

dropQbsd is in active development. It works, it's used daily, but expect sharp edges. Contributions, bug reports, and real-world testing are welcome — open an issue or send a patch.

## Further reading ##

[dropQbsd — Compartmentalization without virtualization](https://blog.nicolabaudo.fr/dropqbsd-compartmentalization-without-virtualization/)
— the architectural rationale, design decisions, and why Unix separation beats hypervisors for most threat models.

## License ##

ISC. See [LICENSE](/nobraininside/dropQbsd/blob/main/LICENSE).

