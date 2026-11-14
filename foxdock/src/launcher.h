#ifndef FOXDOCK_LAUNCHER_H
#define FOXDOCK_LAUNCHER_H

/* Fork+exec an entry safely. Double-click guard via a per-entry
 * last-launch timestamp. */
int launcher_run(const char *exec_cmd, int slot_index);

#endif
