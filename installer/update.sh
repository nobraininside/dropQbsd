#!/bin/sh
# ==========================================================
#  dropQbsd -- update.sh
#
#  Updates an existing dropQbsd installation to the repository
#  version. NOT an installer, and NOT a major-release upgrade:
#  it brings the installation to the current repository version
#  by replacing project-owned files and preserving the
#  operator's configuration. Format changes between versions
#  are handled by lib/migrate.
#
#  Design principles:
#    - Preserve-first: the operator's config is backed up and
#      never written. local.conf is the only operator-owned
#      file; everything else is project-owned or merged.
#    - Replace-only-if-changed: a file whose content is
#      identical to the repo's is left alone. cmp, not mtime.
#    - Versioned: reads the installed version from
#      /opt/dropQbsd/VERSION and the target from the repo's
#      VERSION. Refuses to guess if the installed version is
#      unknown (use --from <version>).
#    - No automatic rollback: on failure the updater stops and
#      tells the operator how to restore from the backup. A
#      destructive auto-restore is more dangerous than the
#      error it tries to undo.
#    - Dry-run: --dry-run prints the plan without executing.
#    - Logged: /var/log/dropQbsd/update.log
#
#  ORDER (mirrors the installer, with preserve first):
#    1  version      read installed vs repo version
#    2  preserve     back up operator-owned and merged files
#    3  replace      project-owned files (only if changed)
#    4  merge        login.conf, newsyslog.conf (append new)
#    5  migrate      format changes between versions
#    6  users/dirs   idempotent (no-op if already correct)
#    7  examples     desktop integration + per-home files
#                    (only if changed)
#    8  compile      rebuild run_app
#    9  logins       cap_mkdb
#    10 firewall     regenerate + repopulate
#    11 integrity    re-sign (NEVER regenerate the key)
#    12 cron         merge crontab
#    13 checklist    verify
#    14 version      write the new VERSION
#
#  Usage:
#    chmod +x update.sh
#    doas ./update.sh [--dry-run] [--from <version>] [--help]
#
#  Sourced modules live in lib/ (same directory as the
#  installer's modules; the updater reuses them).
# ==========================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for mod in common detect version ownership preserve replace merge \
           migrate users dirs files compile logins firewall \
           integrity examples cron checklist; do
    . "${SCRIPT_DIR}/lib/${mod}"
done

# Write to a separate log: common defaults LOG_FILE to
# install.log, which belongs to install.sh. The updater must
# not append to the installer's log.
LOG_FILE="${LOG_DIR}/update.log"

parse_args_update "$@"

# Resolve the conductor account name. On an existing dropQbsd system
# this is always the account carrying the dropQbsd_conductor GECOS
# marker (rename-proof). A collision with a foreign 'conductor' account
# cannot occur here: the marker identifies the real conductor.
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
files_init
init_log

# Pre-flight: markers before anything is written.
verify_all_markers

banner_update

step "1/14   Read versions"
read_versions
check_version

step "2/14   Preserve operator-owned and merged files"
preserve_all

step "3/14   Replace project-owned files (only if changed)"
replace_all

step "4/14   Merge appended files (login.conf, newsyslog.conf)"
merge_all

step "5/14   Migrate format changes"
migrate_all

step "6/14   Ensure users and directories"
create_group
create_users
create_directories

step "7/14   Refresh desktop integration and per-home files"
install_examples
install_user_dotfiles

step "8/14   Rebuild the run_app gate"
compile_run_app

step "9/14   Rebuild the login database"
setup_login_conf

step "10/14  Regenerate and apply the firewall"
setup_firewall

step "11/14  Re-sign the integrity manifest"
update_integrity

step "12/14  Refresh cron jobs"
install_cron

step "13/14  Verify the update"
update_checklist

step "14/14  Record the new version"
write_version

print_update_notes
