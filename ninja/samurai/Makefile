.POSIX:
.PHONY: all install clean

# Compatible with GNU make 3.74 (Rhapsody gnumake): no ?=, no tab-continued
# variable lists (tabs look like recipes to 3.74).

OS=posix
PREFIX=/usr/local
BINDIR=$(PREFIX)/bin
MANDIR=$(PREFIX)/share/man
ALL_CFLAGS=$(CFLAGS) -std=c99 -Wall -Wextra -Wshadow -Wmissing-prototypes -Wpedantic -Wno-unused-parameter
# librt is Linux-only; Darwin/Rhapsody have clock_gettime in libc.
# On Linux: gnumake LDLIBS=-lrt
LDLIBS=
OBJ=build.o deps.o env.o graph.o htab.o log.o parse.o samu.o scan.o tool.o tree.o util.o os-$(OS).o
HDR=arg.h build.h deps.h env.h graph.h htab.h log.h os.h parse.h scan.h tool.h tree.h util.h

all: samu

.c.o:
	$(CC) $(ALL_CFLAGS) -c -o $@ $<

samu: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LDLIBS)

$(OBJ): $(HDR)

install: samu samu.1
	mkdir -p $(DESTDIR)$(BINDIR)
	cp samu $(DESTDIR)$(BINDIR)/
	mkdir -p $(DESTDIR)$(MANDIR)/man1
	cp samu.1 $(DESTDIR)$(MANDIR)/man1/

clean:
	rm -f samu $(OBJ)
