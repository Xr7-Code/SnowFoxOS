/* ============================================================
 *  SnowFoxOS v4 — foxdock: configuration
 * ============================================================ */
#ifndef FOXDOCK_CONFIG_H
#define FOXDOCK_CONFIG_H

typedef struct {
    char *name;
    char *icon;
    char *exec;
} DockEntry;

typedef struct {
    int         icon_size;
    int         padding;
    DockEntry  *entries;
    int         n_entries;
} DockConfig;

int  config_load(const char *path, DockConfig *out);
void config_free(DockConfig *cfg);

#endif
