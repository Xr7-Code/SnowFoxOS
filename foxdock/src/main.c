/* ============================================================
 *  SnowFoxOS v4 — foxdock
 *  Vertical icon dock at the left edge, Xlib + Imlib2 only.
 * ============================================================ */
#define _POSIX_C_SOURCE 200809L
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "config.h"
#include "palette.h"
#include "draw.h"
#include "launcher.h"

#define DOCK_WIDTH_DEFAULT 64
#define FALLBACK_PALETTE "/etc/snowfox/palette.conf"

static volatile sig_atomic_t g_reload   = 0;
static volatile sig_atomic_t g_quit     = 0;
static volatile sig_atomic_t g_repaint  = 0;

static void on_sighup(int sig)  { (void)sig; g_reload  = 1; }
static void on_sigterm(int sig) { (void)sig; g_quit    = 1; }
static void on_sigint(int sig)  { (void)sig; g_quit    = 1; }
static void on_expose(int sig)  { (void)sig; g_repaint = 1; }

static char *palette_path(void) {
    static char buf[1024];
    const char *home = getenv("HOME");
    if (home) {
        snprintf(buf, sizeof(buf), "%s/.config/snowfox/palette.conf", home);
        struct stat st;
        if (stat(buf, &st) == 0) return buf;
    }
    snprintf(buf, sizeof(buf), "%s", FALLBACK_PALETTE);
    return buf;
}

static char *dock_conf_path(void) {
    static char buf[1024];
    const char *home = getenv("HOME");
    if (home) {
        snprintf(buf, sizeof(buf), "%s/.config/foxdock/dock.conf", home);
        return buf;
    }
    return NULL;
}

int main(void) {
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "foxdock: cannot open display\n");
        return 1;
    }
    int screen = DefaultScreen(dpy);
    int width  = DOCK_WIDTH_DEFAULT;

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_sighup;  sigaction(SIGHUP,  &sa, NULL);
    sa.sa_handler = on_sigterm; sigaction(SIGTERM, &sa, NULL);
    sa.sa_handler = on_sigint;  sigaction(SIGINT,  &sa, NULL);
    sa.sa_handler = on_expose;  sigaction(SIGUSR1, &sa, NULL);

    DockConfig cfg = {0};
    const char *conf = dock_conf_path();
    config_load(conf, &cfg);
    int height = cfg.padding * 2 + cfg.n_entries * (cfg.icon_size + cfg.padding);
    if (height < 200) height = 200;

    Palette pal;
    if (palette_load_full(palette_path()) != 0) {
        fprintf(stderr, "foxdock: palette not found, using defaults\n");
    }
    palette_to_pixels(dpy, screen, &pal);

    XSetWindowAttributes attrs;
    attrs.override_redirect = True;
    attrs.background_pixel  = pal.bg;
    attrs.event_mask = ExposureMask | ButtonPressMask |
                       EnterWindowMask | LeaveWindowMask | PointerMotionMask;
    Window win = XCreateWindow(dpy, DefaultRootWindow(dpy),
                               0, 0, (unsigned)width, (unsigned)height, 0,
                               CopyFromParent, InputOutput, CopyFromParent,
                               CWOverrideRedirect | CWBackPixel | CWEventMask,
                               &attrs);
    XStoreName(dpy, win, "FoxDock");

    /* _NET_WM_STRUT_PARTIAL: reserve space on the left edge */
    long strut[12] = {0};
    strut[0]  = width;   /* left */
    strut[4]  = 0;       /* left_start_y */
    strut[5]  = (long)DisplayHeight(dpy, screen) - 1; /* left_end_y */
    Atom strut_atom = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
    XChangeProperty(dpy, win, strut_atom, XA_CARDINAL, 32,
                    PropModeReplace, (unsigned char *)strut, 12);

    XMapWindow(dpy, win);

    DockDraw draw;
    draw_init(&draw, dpy, win, width, height,
              cfg.icon_size, cfg.padding, &pal);
    draw_repaint(&draw, &cfg);

    int hover = -1;
    int running = 1;
    while (running) {
        while (XPending(dpy)) {
            XEvent ev;
            XNextEvent(dpy, &ev);
            if (ev.type == Expose && ev.xexpose.count == 0) {
                draw_repaint(&draw, &cfg);
            } else if (ev.type == ButtonPress && ev.xbutton.button == Button1) {
                int y = ev.xbutton.y;
                int idx = (y - cfg.padding) / (cfg.icon_size + cfg.padding);
                if (idx >= 0 && idx < cfg.n_entries) {
                    launcher_run(cfg.entries[idx].exec, idx);
                }
            } else if (ev.type == MotionNotify || ev.type == EnterNotify) {
                int y = ev.xmotion.y;
                int idx = (y - cfg.padding) / (cfg.icon_size + cfg.padding);
                if (idx >= 0 && idx < cfg.n_entries && idx != hover) {
                    hover = idx;
                    draw.hover_index = hover;
                    draw_repaint(&draw, &cfg);
                }
            } else if (ev.type == LeaveNotify) {
                if (hover != -1) {
                    hover = -1;
                    draw.hover_index = -1;
                    draw_repaint(&draw, &cfg);
                }
            }
        }

        if (g_reload) {
            g_reload = 0;
            Palette new_pal;
            if (palette_load_full(palette_path()) == 0
                && palette_to_pixels(dpy, screen, &new_pal) == 0) {
                pal = new_pal;
                draw.pal = pal;
                XSetWindowBackground(dpy, win, pal.bg);
                XClearWindow(dpy, win);
                draw_repaint(&draw, &cfg);
            }
        }
        if (g_repaint) { g_repaint = 0; draw_repaint(&draw, &cfg); }
        if (g_quit)    { running = 0; }

        usleep(50000); /* 50 ms poll */
    }

    draw_cleanup(&draw);
    config_free(&cfg);
    XDestroyWindow(dpy, win);
    XCloseDisplay(dpy);
    return 0;
}
