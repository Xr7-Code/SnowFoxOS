#define _POSIX_C_SOURCE 200809L
#include "draw.h"

#include <Imlib2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <X11/Xatom.h>

static Window       tip_win  = 0;
static GC           tip_gc   = 0;
static XFontStruct *tip_font = NULL;
static int          tip_w    = 0;
static int          tip_h    = 0;

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

    imlib_context_set_display(dpy);
    imlib_context_set_visual(DefaultVisual(dpy, d->screen));
    imlib_context_set_colormap(DefaultColormap(dpy, d->screen));
}

static void draw_background(DockDraw *d) {
    XSetForeground(d->dpy, d->gc, d->pal.bg);
    XFillRectangle(d->dpy, d->win, d->gc, 0, 0,
                   (unsigned)d->width, (unsigned)d->height);
}

static int resolve_icon_path(const char *icon, char *out, size_t outsz) {
    if (icon && icon[0] == '/') {
        snprintf(out, outsz, "%s", icon);
        return 0;
    }
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

    unsigned long tile_bg = (idx == d->hover_index) ? d->pal.accent : d->pal.bg;
    unsigned long tile_fg = (idx == d->hover_index) ? d->pal.bg     : d->pal.fg;

    XSetForeground(d->dpy, d->gc, tile_bg);
    XFillRectangle(d->dpy, d->win, d->gc, x, y, (unsigned)size, (unsigned)size);

    char path[1024];
    if (resolve_icon_path(e->icon, path, sizeof(path)) == 0) {
        imlib_context_set_drawable(d->win);
        Imlib_Image img = imlib_load_image(path);
        if (img) {
            imlib_context_set_image(img);
            imlib_render_image_on_drawable_at_size(x, y, size, size);
            imlib_free_image();
        } else {
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

/* Tooltip-Fenster einmalig erzeugen und danach nur noch mappen/unmappen. */
void draw_tooltip(DockDraw *d, const DockConfig *cfg, int idx, int parent_y) {
    if (idx < 0 || idx >= cfg->n_entries) return;
    const char *text = cfg->entries[idx].name;
    if (!text || !*text) text = cfg->entries[idx].exec;
    if (!text || !*text) return;

    fprintf(stderr, "tooltip: idx=%d text='%s' font=%p fg=%#lx bg2=%#lx\n",
            idx, text, (void*)tip_font, d->pal.fg, d->pal.bg2);

    /* --- Fenster + GC einmalig anlegen ------------------------------- */
    if (!tip_win) {
        XSetWindowAttributes attrs;
        attrs.override_redirect = True;
        attrs.background_pixel  = d->pal.bg2;
        attrs.border_pixel      = d->pal.accent;
        attrs.event_mask        = ExposureMask;
        tip_win = XCreateWindow(d->dpy, DefaultRootWindow(d->dpy),
                                0, 0, 1, 1, 1,
                                CopyFromParent, InputOutput, CopyFromParent,
                                CWOverrideRedirect | CWBackPixel |
                                CWBorderPixel | CWEventMask, &attrs);

        XStoreName(d->dpy, tip_win, "FoxDockTooltip");

        Atom type = XInternAtom(d->dpy, "_NET_WM_WINDOW_TYPE", False);
        Atom dock = XInternAtom(d->dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
        XChangeProperty(d->dpy, tip_win, type, XA_ATOM, 32,
                        PropModeReplace, (unsigned char *)&dock, 1);

        tip_gc = XCreateGC(d->dpy, tip_win, 0, NULL);
    }

    /* --- Font laden (einmalig, ausserhalb des if-Blocks!) ------------
     * Wichtig: XSetFont muss NACH dem Laden aufgerufen werden.  Steht der
     * Block im if (!tip_win), wird beim ersten Aufruf kein Font gesetzt,
     * weil tip_font dann noch NULL ist -- und beim zweiten Aufruf wird
     * XSetFont nicht mehr erreicht.  Ergebnis: GC ohne Font, XDrawString
     * zeichnet unsichtbar. */
    if (!tip_font) {
        const char *font_names[] = {
            "6x13", "9x15", "fixed",
            "-*-fixed-*-*-*-*-*-*-*-*-*-*-*-*",
            "-misc-fixed-*-*-*-*-13-*-*-*-*-*-*-*",
            NULL
        };
        for (int i = 0; font_names[i] && !tip_font; i++) {
            tip_font = XLoadQueryFont(d->dpy, font_names[i]);
            if (tip_font) {
                fprintf(stderr, "foxdock: tooltip font '%s' loaded\n", font_names[i]);
            }
        }
        if (tip_font) {
            XSetFont(d->dpy, tip_gc, tip_font->fid);
        } else {
            fprintf(stderr, "foxdock: no usable X font for tooltip\n");
        }
    }

    /* --- Groesse an Text anpassen ------------------------------------ */
    int text_len = (int)strlen(text);
    int text_w   = tip_font ? XTextWidth(tip_font, text, text_len)
                            : text_len * 7;
    int ascent   = tip_font ? tip_font->ascent  : 11;
    int descent  = tip_font ? tip_font->descent : 3;
    int w = text_w + 12;
    int h = ascent + descent + 8;

    fprintf(stderr, "  geometry: text_w=%d ascent=%d descent=%d w=%d h=%d\n",
            text_w, ascent, descent, w, h);

    if (w != tip_w || h != tip_h) {
        XMoveResizeWindow(d->dpy, tip_win, 0, 0, (unsigned)w, (unsigned)h);
        tip_w = w; tip_h = h;
    }

    /* --- Position: rechts neben dem Icon, vertikal zentriert --------- */
    int icon_y = parent_y + d->padding + idx * (d->icon_size + d->padding);
    int x = d->width + 4;
    int y = icon_y + (d->icon_size - h) / 2;
    int scr_h = DisplayHeight(d->dpy, d->screen);
    if (y + h > scr_h) y = scr_h - h;
    if (y < 0) y = 0;
    XMoveWindow(d->dpy, tip_win, x, y);

    fprintf(stderr, "  position: x=%d y=%d icon_y=%d\n", x, y, icon_y);

    /* --- Inhalt zeichnen --------------------------------------------- */
    XSetForeground(d->dpy, tip_gc, d->pal.bg2);
    XFillRectangle(d->dpy, tip_win, tip_gc, 0, 0, (unsigned)w, (unsigned)h);
    XSetForeground(d->dpy, tip_gc, d->pal.fg);
    XDrawString(d->dpy, tip_win, tip_gc, 6, 4 + ascent, text, text_len);

    fprintf(stderr, "  drew at y=%d w=%d h=%d\n", 4 + ascent, w, h);

    XMapRaised(d->dpy, tip_win);
    XRaiseWindow(d->dpy, tip_win);
    XSync(d->dpy, False);
}

void draw_tooltip_hide(DockDraw *d) {
    if (tip_win) {
        XUnmapWindow(d->dpy, tip_win);
        XSync(d->dpy, False);
    }
}

void draw_cleanup(DockDraw *d) {
    if (d->gc) { XFreeGC(d->dpy, d->gc); d->gc = 0; }
    if (tip_gc) { XFreeGC(d->dpy, tip_gc); tip_gc = 0; }
    if (tip_font) { XFreeFont(d->dpy, tip_font); tip_font = NULL; }
    if (tip_win) { XDestroyWindow(d->dpy, tip_win); tip_win = 0; }
}
