# Makefile for sound processing utilities

INSTALL_DIR = $(DSTROOT)
#MANDIR = /usr/local/man/man1
MANDIR = $(INSTALL_DIR)

#sources
CFILES = cb.c atc.c atd.c
HFILES = atc.h  hfft.h datatype.h fraction.h
USRCS = atc_globals.c static_utilities.c hfft.c
SRCS = $(CFILES) $(HFILES) $(USRCS) quantization.c unquantization.c
#products
PRODUCTS = $(CFILES:.c=)
MANPAGES =
INSTALLED_TOOLS =
INSTALLED_SCRIPTS =
INSTALLED_SOURCES =

BASE_CFLAGS = -g
CFLAGS = $(BASE_CFLAGS) -O
OPT_CFLAGS = $(BASE_CFLAGS) -O2
DEBUG_CFLAGS = $(BASE_CFLAGS) -DDEBUG
PROFILE_CFLAGS = $(BASE_CFLAGS) -pg -O -DPROFILE

INSTALLED_BINARIES = $(PRODUCTS) $(INSTALLED_TOOLS)
OFILES = $(CFILES:.c=.o)
#TESTLIB = /l/sl/libsound_g.a
TESTLIB =

debug:
	$(MAKE) all "CFLAGS = $(DEBUG_CFLAGS)"

all: $(PRODUCTS)

opt:
	$(MAKE) all "CFLAGS = $(OPT_CFLAGS)"

profile:
	make clean
	$(MAKE) all "CFLAGS = $(PROFILE_CFLAGS)"
	test phs
	gprof -E mcount atd gmon.out > profile.full
	open profile.full

atc: atc.c $(USRCS) cb.h cb quantization.c $(HFILES)
	$(CC) $(CFLAGS) -DTEST_PROGRAM -o atc atc.c $(TESTLIB)

atd: atd.c $(USRCS) cb.h cb unquantization.c $(HFILES)
	$(CC) $(CFLAGS) -DTEST_PROGRAM -o atd atd.c $(TESTLIB)

cb: cb.c atc.h
	$(CC) $(CFLAGS) cb.c -o cb

cb.h: cb 
	cb

lean:
	/bin/rm -f $(OFILES) *.mb *.dat *~ \
		*2.snd *3.snd *3d.snd profile.full gmon.out *.atc

clean: lean
	/bin/rm -f $(PRODUCTS) cb.h *.m *.hex

TAGS tags::
	etags -t $(SRCS)

installsrc:
	mkdirs -m 755 $(SRCROOT)
	cp $(SRCS) Makefile $(SRCROOT)
	chmod 444 $(SRCROOT)/*

# creates products and installs them. Installs man pages also.
install: $(INSTALL_DIR) $(MANDIR) $(INSTALLED_BINARIES)
	install -q -c -s -m 755 $(INSTALLED_BINARIES) $(INSTALL_DIR)
#	install -q -c -m 644 $(MANPAGES) $(MANDIR)

installme: /me/bin
	$(MAKE) install "DSTROOT = /me/bin"

$(INSTALL_DIR): $(DSTROOT)
	mkdir $@

i.snd:
	ln ../snd/i.snd .

e5 e5.snd:
	playscore -w e5s.snd ../scores/Examp5.score
	tomono e5s.snd e5m.snd
	-sndtrim e5m.snd e5.snd
	-/bin/rm e5s.snd e5m.snd

phs phs.snd:
	playscore -w phss.snd Phase.score
	tomono phss.snd phsm.snd
	sndtrim phsm.snd phs.snd
	-/bin/rm phss.snd phsm.snd

thresh t t.snd:
	playscore -w ts.snd ../scores/Thresh.score
	tomono ts.snd tm.snd
	sndtrim tm.snd t.snd
	-/bin/rm ts.snd tm.snd

atc atd: $(TESTLIB)

bag:
	bag $(SRCS) > atc.bag

d: playtest compresstest


playtest:
	(cd ..; make playtest)
