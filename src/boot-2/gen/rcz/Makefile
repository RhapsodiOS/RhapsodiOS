
DIR = rcz
include ../MakePaths.dir

UTILDIR = ../util
LIBSADIR = ../libsa
USRBIN = $(DSTROOT)/usr/bin
INSTALLDIR = $(DSTROOT)/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/standalone

DEBUG = -O
# rcz is installed into the product as /usr/bin/rcz, so it has to be built for
# the architectures being built rather than for whatever the build host is.
# The arch-specific subdirectories name their own -arch, so the top-level
# Makefile strips it out of RC_CFLAGS before anything down here sees it; take
# it from RC_ARCHS instead.  Empty RC_ARCHS still builds for the host.
RCZ_ARCHFLAGS = $(patsubst %,-arch %,$(RC_ARCHS))
CFLAGS	= $(DEBUG) $(MORECPP) $(RC_CFLAGS) $(RCZ_ARCHFLAGS) -g -Wmost -Wno-precomp
DEFINES=
CONFIG = hd
INC = -I. -I$(SYMROOT) -I$(UTILDIR) -I$(LIBSADIR)
MAKE = /bin/gnumake
ifneq "" "$(wildcard /bin/mkdirs)"
  MKDIRS = /bin/mkdirs
else
  MKDIRS = /bin/mkdir -p
endif
AS = as
LD = ld
# LIBS= -lc_static
LIBS=

VPATH = $(OBJROOT):$(SYMROOT)

SFILES =
CFILES = 
HFILES = 
EXPORTED_HFILES =
INSTALLED_HFILES =
OTHERFILES = Makefile
ALLSRC =  $(SFILES) $(CFILES) \
	$(HFILES) $(OTHERFILES)
DIRS_NEEDED = $(OBJROOT) $(SYMROOT) $(USRBIN)

RCZ_OBJS = rcz.o rcz_compress_mem.o rcz_decompress_mem.o

all: $(DIRS_NEEDED) rcz

rcz: $(USRBIN) $(RCZ_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(DEFINES) -o $(USRBIN)/$@ $(RCZ_OBJS)
	strip -x -u $(USRBIN)/$@

clean::
	rm -rf $(USRBIN)/rcz

include ../MakeInc.dir

# dependencies
-include $(OBJROOT)/Makedep
