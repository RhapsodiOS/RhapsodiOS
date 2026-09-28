#
# Makefile for driverLoader.
#
# Built after libDriver: each CPU slice links the libDriver.A.dylib that
# libDriver's lipoize step has just made, plus libkernload, and the slices
# are lipo'd together.  Apple's copies are not stripped, so neither is this.
#
MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
include $(MAKEFILEDIR)/platform.make

PROGRAM=	driverLoader
BINDIR=		/usr/sbin
MANDIR=		/usr/share/man/man8
MFILES=		driverLoader.m kl_com.m
HFILES=		kl_com.h
MANPAGES=	driverLoader.8
SOURCEFILES=	Makefile $(MFILES) $(HFILES) $(MANPAGES)

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
CFLAGS= -g -O2 $(ARCHLESS_RC_CFLAGS) -Wformat -Wno-precomp -I.. \
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
	    for f in $(MFILES); do \
		o=$(OBJROOT)/$$m/`basename $$f .m`.o; \
		echo $(CC) -arch $$m $(CFLAGS) -c $$f -o $$o; \
		$(CC) -arch $$m $(CFLAGS) -c $$f -o $$o || exit 1; \
	    done; \
	    echo $(CC) -arch $$m -o $(OBJROOT)/$$m/$(PROGRAM) \
		$(OBJROOT)/$$m/driverLoader.o $(OBJROOT)/$$m/kl_com.o $(LIBS); \
	    $(CC) -arch $$m -o $(OBJROOT)/$$m/$(PROGRAM) \
		$(OBJROOT)/$$m/driverLoader.o $(OBJROOT)/$$m/kl_com.o \
		$(LIBS) || exit 1; \
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
