# Makefile for sample rate conversion utilities
#
# Modification History:
#	04/23/90/mtm	Created from individual Makefiles
#	06/12/91/jos	Added man pages and install target
#

INSTALL_DIR = $(DSTROOT)
#MANDIR = /usr/local/man/man1
MANDIR = $(INSTALL_DIR)

# PRODUCTS = resample warp windowfilter
PRODUCTS = resample windowfilter
INSTALLED_TOOLS = tosnd toascii tomono sndtrim testscript
INSTALLED_BINARIES = $(PRODUCTS) $(INSTALLED_TOOLS)
INSTALLED_SCRIPTS = testFilter
INSTALLED_SOURCES = testFilter.ma LQFilter.ma HQFilter.ma i.snd test.filter sweep.score
MANPAGES = resample.1 windowfilter.1

CFILES = resample.c resamplesubs.c warp.c windowfilter.c filterkit.c
OFILES = $(CFILES:.c=.o)
HFILES = resample.h filterkit.h stdefs.h
SRCS = $(CFILES) $(HFILES)
BASE_CFLAGS = -Wall -g
CFLAGS = $(BASE_CFLAGS) -O
DEBUG_CFLAGS = $(BASE_CFLAGS)

all: $(PRODUCTS)

debug:
	$(MAKE) all "CFLAGS = $(DEBUG_CFLAGS)"

resample: resample.c stdefs.h resample.h filterkit.h resamplesubs.o \
		libfilterkit.a
	$(CC) $(CFLAGS) resample.c resamplesubs.o libfilterkit.a -lm \
		-o resample

warp: warp.c stdefs.h filterkit.h resample.h libfilterkit.a
	$(CC) $(CFLAGS) warp.c libfilterkit.a -lm -o warp

windowfilter: windowfilter.c stdefs.h resample.h filterkit.h libfilterkit.a
	$(CC) $(CFLAGS) windowfilter.c libfilterkit.a -lm -o windowfilter

libfilterkit.a: filterkit.c stdefs.h resample.h filterkit.h
	$(CC) $(CFLAGS) -c filterkit.c
	ar rc libfilterkit.a filterkit.o
	ranlib libfilterkit.a

clean:
	/bin/rm -f $(OFILES) libfilterkit.a $(PRODUCTS) ir.dat *.mb

TAGS tags:
	etags -t $(CFILES) $(HFILES)

installsrc:
	mkdirs -m 755 $(SRCROOT)
	cp $(SRCS) README Makefile notes $(SRCROOT)
	chmod 444 $(SRCROOT)/*

# creates products and installs them. Installs man pages also.
install: $(INSTALL_DIR) $(MANDIR) $(INSTALLED_BINARIES) $(INSTALLED_SOURCES)
	install -q -c -s -m 755 $(INSTALLED_BINARIES) $(INSTALL_DIR)
	install -q -c -m 644 $(INSTALLED_SOURCES) $(INSTALL_DIR)
	install -q -c -m 755 $(INSTALLED_SCRIPTS) $(INSTALL_DIR)
	install -q -c -m 644 $(MANPAGES) $(MANDIR)
	install -q -c -m 644 Makefile.release $(INSTALL_DIR)/Makefile
	install -q -c -m 644 README.release $(INSTALL_DIR)/README

$(INSTALLED_TOOLS):
	(cd ../tools; make)

$(INSTALL_DIR): $(DSTROOT)
	mkdir $@

i.snd:
	ln -s ../sounds/i.snd .
