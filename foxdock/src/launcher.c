#define _POSIX_C_SOURCE 200809L
#include "launcher.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/prctl.h>

#define MAX_SLOTS    32
#define DEBOUNCE_MS  500

static long last_ms[MAX_SLOTS];

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

int launcher_run(const char *exec_cmd, int slot_index) {
    if (!exec_cmd || slot_index < 0 || slot_index >= MAX_SLOTS) return -1;
    long t = now_ms();
    if (last_ms[slot_index] && (t - last_ms[slot_index]) < DEBOUNCE_MS) {
        return 0;
    }
    last_ms[slot_index] = t;

    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        pid_t pid2 = fork();
        if (pid2 < 0) _exit(127);
        if (pid2 > 0) _exit(0);
        prctl(PR_SET_PDEATHSIG, 0);
        setsid();
        execl("/bin/sh", "sh", "-c", exec_cmd, (char *)NULL);
        _exit(127);
    }
    waitpid(pid, NULL, 0);
    return 0;
}
