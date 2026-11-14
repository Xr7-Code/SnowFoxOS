/* ============================================================
 *  SnowFoxOS v4 — foxdock: palette loader
 *  Reads ~/.config/snowfox/palette.conf, live-reload via SIGHUP.
 * ============================================================ */
#ifndef FOXDOCK_PALETTE_H
#define FOXDOCK_PALETTE_H

#include <X11/Xlib.h>

typedef struct {
    int      dark;       /* 1 if dark theme, 0 otherwise */
    unsigned long bg;    /* pixel value */
    unsigned long bg2;
    unsigned long fg;
    unsigned long fg_dim;
    unsigned long accent;
    unsigned long accent2;
    unsigned long accent3;
    unsigned long status_green;
    unsigned long status_yellow;
    unsigned long status_red;
    unsigned long status_orange;
} Palette;

/* Load palette from path. Returns 0 on success, -1 on failure.
 * Values are stored as #RRGGBB strings first and converted to
 * pixel values via XAllocColor by palette_to_pixels(). */
int  palette_load(const char *path, Palette *out);

/* Convert string colors to X pixel values for the given display/colormap. */
int  palette_to_pixels(Display *dpy, int screen, Palette *p);

#endif
