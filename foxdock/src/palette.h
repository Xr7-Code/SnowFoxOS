/* ============================================================
 *  SnowFoxOS v4 — foxdock: palette loader
 *  Reads ~/.config/snowfox/palette.conf, live-reload via SIGHUP.
 * ============================================================ */
#ifndef FOXDOCK_PALETTE_H
#define FOXDOCK_PALETTE_H

#include <X11/Xlib.h>

typedef struct {
    int           dark;
    unsigned long bg, bg2, fg, fg_dim;
    unsigned long accent, accent2, accent3;
    unsigned long status_green, status_yellow, status_red, status_orange;
} Palette;

int palette_reload(Display *dpy, int screen, const char *path, Palette *out);

#endif