/* ============================================================
 *  SnowFoxOS v4 — foxdock: configuration implementation
 * ============================================================ */
#define _POSIX_C_SOURCE 200809L
#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <dirent.h>

static char *xstrdup(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *p = malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

static void trim(char *s) {
    char *p = s;
    while (*p && isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n-1])) s[--n] = '\0';
}

static void add_entry(DockConfig *cfg, const char *name, const char *icon, const char *exec) {
    DockEntry *grown = realloc(cfg->entries, sizeof(DockEntry) * (size_t)(cfg->n_entries + 1));
    if (!grown) return;
    cfg->entries = grown;
    DockEntry *e = &cfg->entries[cfg->n_entries++];
    e->name = xstrdup(name);
    e->icon = xstrdup(icon);
    e->exec = xstrdup(exec);
}

/* ---- minimal .desktop parser (Name/Icon/Exec/NoDisplay) ---- */
static void parse_desktop_file(const char *path, DockConfig *cfg) {
    FILE *f = fopen(path, "r");
    if (!f) return;

    char name[256] = {0}, icon[256] = {0}, exec[512] = {0};
    int  nodisplay = 0;
    int  in_entry   = 0;
    char line[512];

    while (fgets(line, sizeof(line), f)) {
        trim(line);
        if (!*line || line[0] == '#') continue;
        if (line[0] == '[') {
            in_entry = (!strcmp(line, "[Desktop Entry]"));
            continue;
        }
        if (!in_entry) continue;
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        const char *key = line;
        const char *val = eq + 1;
        if      (!strcmp(key, "Name"))       snprintf(name, sizeof(name), "%s", val);
        else if (!strcmp(key, "Icon"))       snprintf(icon, sizeof(icon), "%s", val);
        else if (!strcmp(key, "Exec"))       snprintf(exec, sizeof(exec), "%s", val);
        else if (!strcmp(key, "NoDisplay") && !strcmp(val, "true")) nodisplay = 1;
    }
    fclose(f);

    if (nodisplay || !name[0] || !exec[0]) return;

    /* Strip %u/%f/%U/%F field codes from Exec */
    char cleaned[512];
    size_t j = 0;
    for (size_t i = 0; exec[i] && j + 1 < sizeof(cleaned); i++) {
        if (exec[i] == '%' && exec[i+1]) { i++; continue; }
        cleaned[j++] = exec[i];
    }
    cleaned[j] = '\0';
    trim(cleaned);

    add_entry(cfg, name, icon[0] ? icon : "application-x-executable", cleaned);
}

static int compare_entries(const void *a, const void *b) {
    const DockEntry *ea = a;
    const DockEntry *eb = b;
    return strcmp(ea->name ? ea->name : "", eb->name ? eb->name : "");
}

int config_load(const char *path, DockConfig *cfg) {
    memset(cfg, 0, sizeof(*cfg));
    cfg->icon_size = 32;
    cfg->padding   = 6;

    /* 1. Try the explicit dock.conf */
    FILE *f = fopen(path, "r");
    if (f) {
        char line[1024];
        while (fgets(line, sizeof(line), f)) {
            trim(line);
            if (!*line || line[0] == '#') continue;

            /* Optional header keys: icon_size=NN / padding=NN */
            if (!strncmp(line, "icon_size=", 10)) {
                cfg->icon_size = atoi(line + 10);
                continue;
            }
            if (!strncmp(line, "padding=", 8)) {
                cfg->padding = atoi(line + 8);
                continue;
            }

            /* name;icon;exec */
            char *p1 = strchr(line, ';');
            if (!p1) continue;
            *p1 = '\0';
            char *p2 = strchr(p1 + 1, ';');
            if (!p2) continue;
            *p2 = '\0';
            add_entry(cfg, line, p1 + 1, p2 + 1);
        }
        fclose(f);
    }

    /* 2. If no entries, auto-scan /usr/share/applications */
    if (cfg->n_entries == 0) {
        DIR *d = opendir("/usr/share/applications");
        if (d) {
            struct dirent *de;
            while ((de = readdir(d))) {
                size_t n = strlen(de->d_name);
                if (n > 8 && !strcmp(de->d_name + n - 8, ".desktop")) {
                    char full[1024];
                    snprintf(full, sizeof(full), "/usr/share/applications/%s", de->d_name);
                    parse_desktop_file(full, cfg);
                }
            }
            closedir(d);
        }
    }

    if (cfg->n_entries > 1 && cfg->entries) {
        qsort(cfg->entries, (size_t)cfg->n_entries, sizeof(DockEntry), compare_entries);
    }
    return 0;
}

void config_free(DockConfig *cfg) {
    if (!cfg) return;
    for (int i = 0; i < cfg->n_entries; i++) {
        free(cfg->entries[i].name);
        free(cfg->entries[i].icon);
        free(cfg->entries[i].exec);
    }
    free(cfg->entries);
    memset(cfg, 0, sizeof(*cfg));
}
