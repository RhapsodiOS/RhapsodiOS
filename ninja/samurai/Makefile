.POSIX:
.PHONY: all install clean

# Compatible with GNU make 3.74 (Rhapsody gnumake): no ?=, no ifeq, no
# tab-continued variable lists.

OS=posix
PREFIX=/usr/local
BINDIR=$(PREFIX)/bin
MANDIR=$(PREFIX)/share/man

# Rhapsody cc is pre-C99 and ignores gcc's -include. Put compat/ on the
# include path so #include <stdint.h> etc. resolve to stubs that pull in
# compat.h (same shims as Windows -FIcompat.h).
ALL_CFLAGS=$(CFLAGS) -Wall -DSAMU_COMPAT -DNO_POSIX_SPAWN -Icompat
LDLIBS=
OBJ=build.o deps.o env.o graph.o htab.o log.o parse.o samu.o scan.o tool.o tree.o util.o os-$(OS).o compat-posix.o
HDR=arg.h build.h deps.h env.h graph.h htab.h log.h os.h parse.h scan.h tool.h tree.h util.h compat.h

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
