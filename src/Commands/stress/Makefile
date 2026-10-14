# RhapsodiOS project Makefile for the system stress suite. rbuild runs
# `make install` with DSTROOT and RC_CFLAGS. Objects are built next to their
# sources because rbuild copies the source tree. GNU make 3.74: pattern rules
# only, no $(call), no target-specific variables.
LIBOBJS = lib/rng.o lib/pattern.o lib/report.o
CC      = cc
CFLAGS  = -O -Wall $(RC_CFLAGS) -Ilib

all: lib/libstress.a

lib/libstress.a: $(LIBOBJS)
	rm -f $@
	ar cr $@ $(LIBOBJS)
	ranlib $@

lib/%.o: lib/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

lib/t_lib: lib/t_lib.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ lib/t_lib.o lib/libstress.a

check: lib/t_lib
	lib/t_lib

install: all

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -f lib/*.o lib/libstress.a lib/t_lib

.PHONY: all check install installhdrs installsrc clean
