#define _POSIX_C_SOURCE 200809L
#include "draw.h"

#include <Imlib2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Simple tooltip window (single, reused) */
static Window tip_win = 0;
static GC     tip_gc  = 0;

void draw_init(DockDraw *d, Display *dpy, Window win, int width, int height,
               int icon_size, int padding, const Palette *pal) {
    memset(d, 0, sizeof(*d));
    d->dpy = dpy;
    d->screen = DefaultScreen(dpy);
    d->win = win;
    d->width = width;
    d->height = height;
    d->icon_size = icon_size;
    d->padding = padding;
    d->hover_index = -1;
    d->active_index = -1;
    d->pal = *pal;
    d->gc = XCreateGC(dpy, win, 0, NULL);
}

static void draw_background(DockDraw *d) {
    XSetForeground(d->dpy, d->gc, d->pal.bg);
    XFillRectangle(d->dpy, d->win, d->gc, 0, 0,
                   (unsigned)d->width, (unsigned)d->height);
}

static int resolve_icon_path(const char *icon, char *out, size_t outsz) {
    /* Absolute path wins */
    if (icon && icon[0] == '/') {
        snprintf(out, outsz, "%s", icon);
        return 0;
    }
    /* Try common theme locations */
    const char *roots[] = {
        "/usr/share/icons/hicolor/48x48/apps",
        "/usr/share/icons/hicolor/32x32/apps",
        "/usr/share/icons/Papirus-Dark/48x48/apps",
        "/usr/share/icons/Papirus-Dark/32x32/apps",
        "/usr/share/pixmaps",
        NULL
    };
    const char *exts[] = { ".png", ".svg", ".xpm", NULL };
    for (int r = 0; roots[r]; r++) {
        for (int e = 0; exts[e]; e++) {
            snprintf(out, outsz, "%s/%s%s", roots[r], icon, exts[e]);
            FILE *f = fopen(out, "r");
            if (f) { fclose(f); return 0; }
        }
    }
    return -1;
}

static void draw_icon(DockDraw *d, const DockEntry *e, int idx, int y) {
    int x = d->padding;
    int size = d->icon_size;

    /* Background square per icon: invert on hover (plan §4) */
    unsigned long tile_bg    = (idx == d->hover_index) ? d->pal.accent : d->pal.bg;
    unsigned long tile_fg    = (idx == d->hover_index) ? d->pal.bg     : d->pal.fg;

    XSetForeground(d->dpy, d->gc, tile_bg);
    XFillRectangle(d->dpy, d->win, d->gc, x, y, (unsigned)size, (unsigned)size);

    /* Load icon via Imlib2 into a pixmap, scaled to fit. */
    char path[1024];
    if (resolve_icon_path(e->icon, path, sizeof(path)) == 0) {
        imlib_context_set_display(d->dpy);
        imlib_context_set_visual(DefaultVisual(d->dpy, d->screen));
        imlib_context_set_colormap(DefaultColormap(d->dpy, d->screen));
        Imlib_Image img = imlib_load_image(path);
        if (img) {
            imlib_context_set_image(img);
            imlib_render_image_on_drawable_at_size(x, y, size, size);
            imlib_free_image();
        } else {
            /* Fallback: fill square with foreground colour */
            XSetForeground(d->dpy, d->gc, tile_fg);
            XDrawRectangle(d->dpy, d->win, d->gc, x + 2, y + 2,
                           (unsigned)(size - 4), (unsigned)(size - 4));
        }
    } else {
        XSetForeground(d->dpy, d->gc, tile_fg);
        XDrawRectangle(d->dpy, d->win, d->gc, x + 2, y + 2,
                       (unsigned)(size - 4), (unsigned)(size - 4));
    }
}

void draw_repaint(DockDraw *d, const DockConfig *cfg) {
    draw_background(d);
    int y = d->padding;
    for (int i = 0; i < cfg->n_entries; i++) {
        draw_icon(d, &cfg->entries[i], i, y);
        y += d->icon_size + d->padding;
        if (y + d->icon_size > d->height) break;
    }
    XFlush(d->dpy);
}

static void draw_tooltip(DockDraw *d, const char *text, int x, int y) {
    if (!tip_win) {
        XSetWindowAttributes attrs;
        attrs.override_redirect = True;
        attrs.background_pixel  = d->pal.bg2;
        tip_win = XCreateWindow(d->dpy, DefaultRootWindow(d->dpy),
                                x, y, 200, 24, 0,
                                CopyFromParent, InputOutput, CopyFromParent,
                                CWOverrideRedirect | CWBackPixel, &attrs);
        tip_gc = XCreateGC(d->dpy, tip_win, 0, NULL);
        XSetForeground(d->dpy, tip_gc, d->pal.fg);
    }
    XSetForeground(d->dpy, tip_gc, d->pal.fg);
    XDrawString(d->dpy, tip_win, tip_gc, 4, 16, text, (int)strlen(text));
    XMapRaised(d->dpy, tip_win);
}

void draw_cleanup(DockDraw *d) {
    if (d->gc) { XFreeGC(d->dpy, d->gc); d->gc = 0; }
    if (tip_gc) { XFreeGC(d->dpy, tip_gc); tip_gc = 0; }
    if (tip_win) { XDestroyWindow(d->dpy, tip_win); tip_win = 0; }
}
