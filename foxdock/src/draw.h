#ifndef DRAW_H
#define DRAW_H

#include <X11/Xlib.h>
#include "config.h"
#include "palette.h"

typedef struct {
    Display *dpy;
    int      screen;
    Window   win;
    int      width;
    int      height;
    int      icon_size;
    int      padding;
    int      hover_index;
    int      active_index;
    GC       gc;
    Palette  pal;
} DockDraw;

void draw_init(DockDraw *d, Display *dpy, Window win, int width, int height,
               int icon_size, int padding, const Palette *pal);
void draw_repaint(DockDraw *d, const DockConfig *cfg);
void draw_tooltip(DockDraw *d, const DockConfig *cfg, int idx, int parent_y);
void draw_tooltip_hide(DockDraw *d);
void draw_cleanup(DockDraw *d);

#endif
