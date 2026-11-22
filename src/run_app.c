#include <grp.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

int
main(int argc, char *argv[])
{
    char **wrapper_args;
    char uid_str[16];

    if (argc < 3) {
        fprintf(stderr,
            "Usage: %s <target_user> <app> [app_args...]\n"
            "       %s <action> <argument>\n",
            argv[0], argv[0]);
        return 1;
    }

    /*
     * Capture the CALLER's real uid BEFORE setuid(0) zeroes it.
     * setuid(0) sets real, effective and saved uid to 0 on both
     * OpenBSD and FreeBSD -- required so that `su -l` does not
     * prompt for a password. The caller's identity is passed to
     * run_app_impl as an argument instead; the conductor check
     * happens there, not here.
     */
    snprintf(uid_str, sizeof(uid_str), "%u", (unsigned)getuid());

    /*
     * The setuid bit changes the effective uid only: without the two
     * calls below, the process keeps the caller's gid, and files
     * created by root-owned scripts inherit the caller's group (e.g.
     * the conductor's 'user' group) instead of wheel. This is how
     * /home/drop/_quarantine ended up root:user.
     *
     * Order: drop supplementary groups, set the gid, then the uid.
     */
    if (setgroups(0, NULL) != 0) {
        perror("dropQbsd: setgroups failed");
        return 1;
    }
    if (setgid(0) != 0) {
        perror("dropQbsd: setgid(0) failed");
        return 1;
    }
    if (setuid(0) != 0) {
        perror("dropQbsd: setuid(0) failed");
        return 1;
    }

    /*
     * wrapper run_app_impl <uid> <original args...>
     *
     * Slots: wrapper, script, uid, argc-1 user args, NULL.
     */
    wrapper_args = malloc((argc + 3) * sizeof(*wrapper_args));
    if (wrapper_args == NULL) {
        perror("dropQbsd: malloc failed");
        return 1;
    }

    wrapper_args[0] = "/opt/dropQbsd/libexec/wrapper";
    wrapper_args[1] = "/opt/dropQbsd/libexec/run_app_impl";
    wrapper_args[2] = uid_str;

    for (int i = 1; i < argc; i++)
        wrapper_args[i + 2] = argv[i];
    wrapper_args[argc + 2] = NULL;

    execv(wrapper_args[0], wrapper_args);
    perror("dropQbsd: execv failed");
    return 1;
}