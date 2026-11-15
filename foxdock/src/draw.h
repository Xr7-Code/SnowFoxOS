#ifndef FOXDOCK_DRAW_H
#define FOXDOCK_DRAW_H

#include <X11/Xlib.h>
#include "palette.h"
#include "config.h"

typedef struct {
    Display *dpy;
    int      screen;
    Window   win;
    GC       gc;
    int      width;
    int      height;
    int      icon_size;
    int      padding;
    int      hover_index;
    int      active_index;
    Palette  pal;
} DockDraw;

void draw_init(DockDraw *d, Display *dpy, Window win, int width, int height,
               int icon_size, int padding, const Palette *pal);
void draw_repaint(DockDraw *d, const DockConfig *cfg);
void draw_cleanup(DockDraw *d);

#endif