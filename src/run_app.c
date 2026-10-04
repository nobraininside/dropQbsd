#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

int main(int argc, char *argv[]) {
    char **wrapper_args;
    char uid_str[16];

    if (argc < 3) {
        fprintf(stderr, "Usage: %s <target_user> <app> [app_args...]\n", argv[0]);
        return 1;
    }

    /*
     * Capture the invoking user's real uid BEFORE dropping it.
     * setuid(0) zeroes ruid -- required so that `su -l` does not
     * prompt for a password. The conductor's identity is passed
     * to run_app_impl as an argument instead.
     */
    snprintf(uid_str, sizeof(uid_str), "%u", (unsigned)getuid());

    if (setuid(0) != 0) {
        perror("dropQbsd: setuid(0) failed");
        return 1;
    }

    wrapper_args = malloc((argc + 3) * sizeof(*wrapper_args));
    if (wrapper_args == NULL) {
        perror("dropQbsd: malloc failed");
        return 1;
    }

    wrapper_args[0] = "/opt/dropQbsd/libexec/wrapper";
    wrapper_args[1] = "/opt/dropQbsd/libexec/run_app_impl";
    wrapper_args[2] = uid_str;

    for (int i = 1; i < argc; i++) {
        wrapper_args[i + 2] = argv[i];
    }
    wrapper_args[argc + 2] = NULL;

    execv(wrapper_args[0], wrapper_args);
    perror("dropQbsd: execv failed");
    return 1;
}


