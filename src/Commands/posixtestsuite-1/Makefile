# RhapsodiOS project Makefile for the Open POSIX Test Suite 1.5.2. The
# upstream tree in posixtestsuite/ is unmodified; tests are compiled on the
# machine that runs them, by ./run. GNU make 3.74: pattern rules only, no
# $(call), no target-specific variables.
CC     = cc
CFLAGS = -O -Wall $(RC_CFLAGS)
DEST   = $(DSTROOT)/usr/local/posixtestsuite

all:

install: all
	mkdir -p $(DEST)
	rm -rf $(DEST)/posixtestsuite
	cp -R posixtestsuite $(DEST)/
	install -m 755 run ptimeout $(DEST)/
	install -m 644 baseline README $(DEST)/

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -rf Report

.PHONY: all install installhdrs installsrc clean
