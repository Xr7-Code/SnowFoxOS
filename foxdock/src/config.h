/* ============================================================
 *  SnowFoxOS v4 — foxdock: configuration
 *  Parses ~/.config/foxdock/dock.conf and scans .desktop files.
 * ============================================================ */
#ifndef FOXDOCK_CONFIG_H
#define FOXDOCK_CONFIG_H

typedef struct {
    char *name;      /* display name */
    char *icon;      /* icon name or absolute path */
    char *exec;      /* command to fork+exec */
} DockEntry;

typedef struct {
    int         icon_size;   /* 32 or 48 */
    int         padding;     /* inner padding */
    DockEntry  *entries;
    int         n_entries;
} DockConfig;

/* Load dock.conf; falls back to auto-scan if file is empty/missing.
 * Returns 0 on success, -1 on fatal error. */
int  config_load(const char *path, DockConfig *out);

/* Free all entries. */
void config_free(DockConfig *cfg);

#endif
