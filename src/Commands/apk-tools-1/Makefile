# RhapsodiOS project Makefile for apk-tools. rbuild runs `make install` with
# DSTROOT and RC_CFLAGS (the target CPUs and platform defines). The vendored
# kbuild-style Make.rules needs GNU make 3.80 ($(call), $(if)), newer than the
# target's 3.74, so build apk directly from apk-tools/src. Rhapsody's libc has
# no getopt_long, so compat/ carries GNU getopt (from bison-1).
SRC     = apk-tools/src
COMPAT  = compat
VERSION = 2.0_pre12
OBJS    = state.o database.o package.o archive.o version.o io.o url.o \
          gunzip.o blob.o hash.o md5.o apk.o add.o del.o update.o info.o \
          search.o ver.o index.o fetch.o audit.o getopt.o getopt1.o
CC      = cc
CFLAGS  = -O -Wall $(RC_CFLAGS) -I$(COMPAT) -I$(SRC)

all: $(SRC)/apk

$(SRC)/apk: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS) -lz

%.o: $(SRC)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: $(COMPAT)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

apk.o: $(SRC)/apk.c
	$(CC) $(CFLAGS) -DAPK_VERSION=\"$(VERSION)\" -c $(SRC)/apk.c -o $@

install: $(SRC)/apk
	install -d $(DSTROOT)/sbin $(DSTROOT)/usr/share/doc/apk
	install -m 755 $(SRC)/apk $(DSTROOT)/sbin/apk
	install -m 644 apk-tools/README $(DSTROOT)/usr/share/doc/apk

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -f $(OBJS) $(SRC)/apk

.PHONY: all install installhdrs installsrc clean
