#!/bin/sh
# ==========================================================
#  dropQbsd -- install.sh
#
#  Semi-automatic installer for dropQbsd on OpenBSD and
#  FreeBSD. Follows INSTALL_MANUAL.md as the specification.
#
#  Design principles:
#    - Idempotent: safe to re-run; state is checked before
#      any action is taken.
#    - Non-destructive: no rm -rf, no userdel. On failure the
#      script stops and reports; recovery is the operator's.
#    - Verifiable: every critical action has a post-check.
#    - Dry-run: --dry-run prints the plan without executing.
#    - Fail-fast: the first real error stops the run.
#    - Logged: everything goes to /var/log/dropQbsd/install.log
#
#  ORDER (mirrors INSTALL_MANUAL.md; update.sh follows the same
#  sequence, with preserve-first in place of backup-first):
#    1  backup      back up every file the installer will touch
#    2  users       the drop group and four domain accounts,
#                   each marked with its GECOS role. No passwords.
#    3  dirs        the directory tree and the permission model
#    4  config      /etc/dropQbsd, /opt/dropQbsd, and the per-home
#                   shell stubs plus the conductor binding
#    5  examples    desktop integration: mc, nnn, vi, GTK2, Xfe
#    6  compile     rebuild run_app: static, root:wheel, mode 4755
#    7  logins      append the resource classes, rebuild login.db
#    8  firewall    generate, syntax-check, apply, populate tables
#    9  integrity   generate the key pair if absent, sign manifest
#   10  verify      one verification pass, result read from the log
#   11  cron        merge the dropQbsd entries into root's crontab
#   12  version     record the installed version
#   13  checklist   verify users, files, setuid, firewall, cron
#   14  manual      print the steps that remain
#
#  Integrity before cron. Sign (9) and Verify (10) MUST run before
#  install_cron (11): the verify_integrity job is only meaningful
#  once a signature exists, and installing it earlier makes cron
#  log SETUP INCOMPLETE every five minutes. install_cron therefore
#  conditions that entry on the signature actually existing.
#
#  Naming: install.sh and update.sh are the only files with a .sh
#  extension -- the two executable entry points. The modules under
#  lib/ carry no extension: they are sourced, never executed,
#  matching the dropQbsd convention.
#
#  Usage:
#    chmod +x install.sh
#    doas ./install.sh [--dry-run] [--skip-backup] [--help]
#
#  NetBSD is rejected up front: gen_fwall refuses to emit a
#  partial ruleset because npf(7) lacks per-user filtering.
# ==========================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source the modules. No extension: they are not executable.
# Constants live in common (sourced first), so every later
# module can rely on them regardless of order.
for mod in common detect version backup users dirs files compile \
           logins firewall integrity examples cron checklist; do
    . "${SCRIPT_DIR}/lib/${mod}"
done

# parse_args sets DRY_RUN and SKIP_BACKUP as globals; it is the
# single source of truth for both.
parse_args "$@"

# Resolve the conductor account name. In --dry-run, show a conflict
# placeholder instead of failing; a real install fails hard on a
# collision (see resolve_conductor_name in lib/common).
if [ "$DRY_RUN" = "true" ]; then
    CONDUCTOR_USER="$(resolve_conductor_name 2>/dev/null)" \
        || CONDUCTOR_USER="<CONFLICT: set CONDUCTOR_USER=<name>>"
else
    CONDUCTOR_USER="$(resolve_conductor_name)" || exit 1
fi

# USER_LIST must follow the FINAL conductor name. common sets it at
# sourcing time, before this block re-resolves the account; when the
# two differ (a collision under --dry-run) the plan would name the
# wrong account.
USER_LIST="$CONDUCTOR_USER userdoc usermail userweb"

check_root
check_os
resolve_repo_root
init_log

banner

step "1/14   Back up files the installer will touch"
backup_all

step "2/14   Create group and domain users (no passwords)"
create_group
create_users

step "3/14   Create directories and set permissions"
create_directories

step "4/14   Install configuration, scripts and dotfiles"
install_files
set_script_perms
install_user_dotfiles

step "5/14   Install desktop integration (mc, nnn, vi)"
install_examples

step "6/14   Build the run_app gate (setuid, static)"
compile_run_app

step "7/14   Configure login.conf and rebuild the database"
setup_login_conf

step "8/14   Generate and apply the firewall"
setup_firewall

step "9/14   Configure script integrity (Sign)"
setup_integrity

step "10/14  Verify script integrity (Verify)"
verify_integrity_setup

step "11/14  Install cron jobs"
install_cron

step "12/14  Record the installed version" 
write_version

step "13/14  Verify the installation" 
final_checklist

step "14/14  Remaining manual actions"
print_manual_steps
