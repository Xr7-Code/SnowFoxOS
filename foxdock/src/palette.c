/* ============================================================
 *  SnowFoxOS v4 — foxdock: palette loader implementation
 * ============================================================ */
#define _POSIX_C_SOURCE 200809L
#include "palette.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

typedef struct {
    char bg[8], bg2[8], fg[8], fg_dim[8];
    char accent[8], accent2[8], accent3[8];
    char status_green[8], status_yellow[8], status_red[8], status_orange[8];
    int  dark;
} RawPalette;

static void trim(char *s) {
    char *p = s;
    while (*p && isspace((unsigned char)*p)) p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n-1])) s[--n] = '\0';
}

static int copy_color(const char *src, char *dst, size_t dstsz) {
    if (strlen(src) != 7 || src[0] != '#') return -1;
    for (int i = 1; i < 7; i++) {
        if (!isxdigit((unsigned char)src[i])) return -1;
    }
    snprintf(dst, dstsz, "%s", src);
    return 0;
}

static int parse_raw(const char *path, RawPalette *r) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;

    memset(r, 0, sizeof(*r));
    r->dark = 1;
    /* Safe defaults in case some keys are missing */
    copy_color("#2B2F38", r->bg,      sizeof(r->bg));
    copy_color("#343945", r->bg2,     sizeof(r->bg2));
    copy_color("#E5E9F0", r->fg,      sizeof(r->fg));
    copy_color("#8A919E", r->fg_dim,  sizeof(r->fg_dim));
    copy_color("#9B59B6", r->accent,  sizeof(r->accent));
    copy_color("#6C3483", r->accent2, sizeof(r->accent2));
    copy_color("#B07CC6", r->accent3, sizeof(r->accent3));
    copy_color("#7FB069", r->status_green,  sizeof(r->status_green));
    copy_color("#D4B86A", r->status_yellow, sizeof(r->status_yellow));
    copy_color("#C96A6A", r->status_red,    sizeof(r->status_red));
    copy_color("#D4956A", r->status_orange, sizeof(r->status_orange));

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *hash = strchr(line, '#');
        if (hash && hash != line) *hash = '\0';
        trim(line);
        if (!*line) continue;
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = line;
        char *val = eq + 1;
        trim(key); trim(val);

        if      (!strcmp(key, "dark"))          r->dark = (!strcmp(val, "true") ? 1 : 0);
        else if (!strcmp(key, "bg"))            copy_color(val, r->bg,     sizeof(r->bg));
        else if (!strcmp(key, "bg2"))           copy_color(val, r->bg2,    sizeof(r->bg2));
        else if (!strcmp(key, "fg"))            copy_color(val, r->fg,     sizeof(r->fg));
        else if (!strcmp(key, "fg_dim"))        copy_color(val, r->fg_dim, sizeof(r->fg_dim));
        else if (!strcmp(key, "accent"))        copy_color(val, r->accent, sizeof(r->accent));
        else if (!strcmp(key, "accent2"))       copy_color(val, r->accent2,sizeof(r->accent2));
        else if (!strcmp(key, "accent3"))       copy_color(val, r->accent3,sizeof(r->accent3));
        else if (!strcmp(key, "status_green"))  copy_color(val, r->status_green, sizeof(r->status_green));
        else if (!strcmp(key, "status_yellow")) copy_color(val, r->status_yellow,sizeof(r->status_yellow));
        else if (!strcmp(key, "status_red"))    copy_color(val, r->status_red,   sizeof(r->status_red));
        else if (!strcmp(key, "status_orange")) copy_color(val, r->status_orange,sizeof(r->status_orange));
        /* unknown keys ignored for forward-compat */
    }
    fclose(f);
    return 0;
}

static unsigned long hex_to_pixel(Display *dpy, int screen, const char *hex) {
    XColor xc, exact;
    if (!XAllocNamedColor(dpy, DefaultColormap(dpy, screen), hex, &xc, &exact))
        return BlackPixel(dpy, screen);
    return xc.pixel;
}

int palette_reload(Display *dpy, int screen, const char *path, Palette *out) {
    if (!dpy || !out) return -1;
    RawPalette r;
    if (parse_raw(path, &r) != 0) return -1;
    out->dark           = r.dark;
    out->bg             = hex_to_pixel(dpy, screen, r.bg);
    out->bg2            = hex_to_pixel(dpy, screen, r.bg2);
    out->fg             = hex_to_pixel(dpy, screen, r.fg);
    out->fg_dim         = hex_to_pixel(dpy, screen, r.fg_dim);
    out->accent         = hex_to_pixel(dpy, screen, r.accent);
    out->accent2        = hex_to_pixel(dpy, screen, r.accent2);
    out->accent3        = hex_to_pixel(dpy, screen, r.accent3);
    out->status_green   = hex_to_pixel(dpy, screen, r.status_green);
    out->status_yellow  = hex_to_pixel(dpy, screen, r.status_yellow);
    out->status_red     = hex_to_pixel(dpy, screen, r.status_red);
    out->status_orange  = hex_to_pixel(dpy, screen, r.status_orange);
    return 0;
}
