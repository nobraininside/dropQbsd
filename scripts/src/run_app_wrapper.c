#include <unistd.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (setuid(0) != 0)
        _exit(1);
    execv("/usr/local/bin/dropQbsd/run_app_impl", argv);
    _exit(1);
}
