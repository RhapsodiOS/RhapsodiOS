#
# Makefile for driverDetect.
#
# Built like driverLoader, after libDriver: each CPU slice links the
# libDriver.A.dylib that libDriver's lipoize step has just made, plus
# libkernload, and the slices are lipo'd together.  kl_com.m comes from
# ../driverLoader.
#
MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
include $(MAKEFILEDIR)/platform.make

PROGRAM=	driverDetect
BINDIR=		/usr/sbin
MANDIR=		/usr/share/man/man8
CFILES=		driverDetect.c match.c
MFILES=		../driverLoader/kl_com.m
HFILES=		match.h
MANPAGES=	driverDetect.8
SOURCEFILES=	Makefile $(CFILES) $(HFILES) $(MANPAGES)

ifneq "" "$(wildcard /bin/mkdirs)"
  MKDIRS = /bin/mkdirs
else
  MKDIRS = /bin/mkdir -p
endif

OBJROOT= .
SYMROOT= .
MACHINE_LIST= ppc i386
LIBDRIVER= $(SYMROOT)/../libDriver/syms/libDriver.A.dylib

HEADER_ROOT=$(HDRROOT)
ifeq "$(HEADER_ROOT)" ""
HEADER_ROOT=$(NEXT_ROOT)
endif
SYSTEM_FW= $(HEADER_ROOT)$(SYSTEM_LIBRARY_DIR)/Frameworks/System.framework/Versions/B

ARCHFULL_RC_CFLAGS = $(foreach X, $(RC_ARCHS),$(addprefix -arch , $(X)))
ARCHLESS_RC_CFLAGS = $(filter-out $(ARCHFULL_RC_CFLAGS), $(RC_CFLAGS))

CC= cc
CFLAGS= -g -O $(ARCHLESS_RC_CFLAGS) -Wformat -Wno-precomp -I.. \
	-I../driverLoader \
	-I$(SYSTEM_FW)/PrivateHeaders -I$(SYSTEM_FW)/Headers \
	-I$(SYSTEM_FW)/PrivateHeaders/bsd -I$(SYSTEM_FW)/Headers/bsd
LIBS= $(LIBDRIVER) -lkernload

all: $(SYMROOT)/$(PROGRAM)

$(SYMROOT)/$(PROGRAM): ALWAYS
	@if [ -n "$(RC_ARCHS)" ]; then machines="$(RC_ARCHS)"; \
	else machines="$(MACHINE_LIST)"; fi; \
	$(MKDIRS) $(SYMROOT) || exit 1; \
	slices=""; \
	for m in $$machines; do \
	    $(MKDIRS) $(OBJROOT)/$$m || exit 1; \
	    objs=""; \
	    for f in $(CFILES) $(MFILES); do \
		o=$(OBJROOT)/$$m/`basename $$f | sed 's/\.[cm]$$//'`.o; \
		echo $(CC) -arch $$m $(CFLAGS) -c $$f -o $$o; \
		$(CC) -arch $$m $(CFLAGS) -c $$f -o $$o || exit 1; \
		objs="$$objs $$o"; \
	    done; \
	    echo $(CC) -arch $$m -o $(OBJROOT)/$$m/$(PROGRAM) $$objs $(LIBS); \
	    $(CC) -arch $$m -o $(OBJROOT)/$$m/$(PROGRAM) $$objs \
		$(LIBS) || exit 1; \
	    echo strip -S $(OBJROOT)/$$m/$(PROGRAM); \
	    strip -S $(OBJROOT)/$$m/$(PROGRAM) || exit 1; \
	    slices="$$slices $(OBJROOT)/$$m/$(PROGRAM)"; \
	done; \
	echo lipo -create -o $@ $$slices; \
	lipo -create -o $@ $$slices

install: DSTROOT all install_only

install_only: DSTROOT
	$(MKDIRS) $(DSTROOT)$(BINDIR) $(DSTROOT)$(MANDIR)
	install -c -m 555 $(SYMROOT)/$(PROGRAM) $(DSTROOT)$(BINDIR)/$(PROGRAM)
	install -c -m 444 $(MANPAGES) $(DSTROOT)$(MANDIR)/$(MANPAGES)

installhdrs debug kern tags:

installsrc: SRCROOT
	$(MKDIRS) $(SRCROOT)
	gnutar cf - $(SOURCEFILES) | (cd $(SRCROOT); gnutar xpf -)

clean:
	rm -rf ppc i386 $(PROGRAM) *~

SRCROOT DSTROOT:
	@if [ -n "${$@}" ]; then exit 0; else echo Must define $@; exit 1; fi

ALWAYS:
