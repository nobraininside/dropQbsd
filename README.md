# dropQbsd

*dropQbsd — Compartmentalization made simple*

Take an excellent idea — security by compartmentalization, as developed by Qubes OS — and strip away the hypervisor. **dropQbsd relies on native OpenBSD user separation instead of heavy virtualization**. Same security. Low resources. No multi-gigabyte VM images. No complex Xen setups. Just a few rules, a solid pf.conf, and a handful of scripts. That's it.

**dropQbsd is a framework that turns a standard OpenBSD machine into a rock-solid compartmentalized operating system**. Each domain — web, mail, LAN, work — runs as a separate user. They share nothing except a single controlled exchange directory policed by automated scripts that block malware propagation while allowing seamless file sharing.

Ten minutes to install. Uninstall if you're bored. Reinstall if something breaks. No hypervisor, no lock-in, no magic. Just Unix, done right.

## How it works

**Each domain (web browsing, email, LAN, general work) runs as a dedicated user — userweb, usermail, userlan, user**. These users share no files, no home directories, no network namespaces beyond what pf allows. They are isolated at the OS level, not inside virtual machines.

**The main user (user) acts as the conductor**: it can launch graphical applications inside any domain without switching users, without a root password, and without leaving its own desktop session. A single script (run_app) handles X11 authentication forwarding and process execution via doas. This works with any window manager — no custom DE integration required, no Xephyr nesting, no special display manager configuration.

**The only bridge between domains is /home/drop — a policed exchange directory**. Files deposited there are automatically checked, their permissions corrected, and unauthorized files quarantined. Importing a file leaves a sentinel behind; a cron job handles cleanup. Malware that compromises one domain cannot propagate through the exchange because it cannot write to files it doesn't own, cannot delete files deposited by others, and cannot escape the permissions cage enforced every 60 seconds.

## What you get

- **Compartmentalization without virtualization**. Same security model as Qubes, zero overhead.
- **Disposable browsers**. Launch any browser with a temporary profile as any domain user with a single command.
- **Automated archival**. Email and work directories are compressed and pulled across domains on schedule, with integrity verification and retention policies.
- **Quarantine**. Files that violate policy are isolated with an explanation, not silently accepted.
- **Reinstallable in minutes**. The whole framework is a few ksh scripts and some pf rules. No databases, no daemons, no state you can't reconstruct.

## Philosophy

dropQbsd is not a distribution. It's a configuration. It doesn't fork OpenBSD — it sits on top of it, using tools that have been battle-tested for decades. The goal is not to add layers of abstraction but to remove them: if Unix users and permissions already provide isolation, why add a hypervisor? If cron and find can police a shared directory, why run a service?
**Complexity is the enemy of security. dropQbsd keeps it simple**, auditable, and boring — exactly what you want from a security tool.



## Install
...

## Script
...

## License
