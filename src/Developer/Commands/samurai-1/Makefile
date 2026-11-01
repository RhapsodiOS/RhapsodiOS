# RhapsodiOS command/package wrapper for Samurai.
CC=cc
CFLAGS=-O -Wall

all: build

build:
	$(MAKE) -C samurai CC="$(CC)" CFLAGS="$(CFLAGS) $(RC_CFLAGS)" LDFLAGS="$(LDFLAGS)" all

install: build
	install -d $(DSTROOT)/usr/bin $(DSTROOT)/usr/share/man/man1 $(DSTROOT)/usr/share/doc/samurai
	install -c -m 755 samurai/samu $(DSTROOT)/usr/bin/samu
	install -c -m 644 samurai/samu.1 $(DSTROOT)/usr/share/man/man1/samu.1
	install -c -m 644 samurai/LICENSE PROVENANCE.md $(DSTROOT)/usr/share/doc/samurai

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

test: build
	$(MAKE) -C samurai CC="$(CC)" CFLAGS="$(CFLAGS) $(RC_CFLAGS)" LDFLAGS="$(LDFLAGS)" test
	sh samurai/test.sh
	sh tests/port.sh
	MAKE=$(MAKE) sh tests/install.sh

clean:
	$(MAKE) -C samurai clean

.PHONY: all build install installhdrs installsrc test clean
