# SnowFoxOS v4 — foxdock
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c11
PKGS     = x11 imlib2
PKG_CFLAGS := $(shell pkg-config --cflags $(PKGS))
PKG_LIBS   := $(shell pkg-config --libs   $(PKGS))
LDFLAGS ?=

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin

SRC = src/main.c src/config.c src/launcher.c src/draw.c src/palette.c
OBJ = $(SRC:.c=.o)

.PHONY: all clean install uninstall

all: foxdock

foxdock: $(OBJ)
	$(CC) $(CFLAGS) $(OBJ) -o $@ $(PKG_LIBS) $(LDFLAGS)

src/%.o: src/%.c
	$(CC) $(CFLAGS) $(PKG_CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJ) foxdock

install: foxdock
	install -d -m 0755 $(DESTDIR)$(BINDIR)
	install -m 0755 foxdock $(DESTDIR)$(BINDIR)/foxdock

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/foxdock
