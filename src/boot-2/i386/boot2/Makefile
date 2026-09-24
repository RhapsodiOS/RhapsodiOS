
#	Makefile for i386 boot program
#	define FLOPPY and SMALL using DEFINES macro as necessary

DIR = boot2
include ../MakePaths.dir

DEBUG = -O2
CFLAGS	= $(RC_CFLAGS) $(DEBUG) $(MORECPP) -arch i386 -g -Wmost -Wno-precomp \
    -munaligned-text -DSAIO_INTERNAL_USER -static
DEFINES=
CONFIG = hd
SYMDIR = $(SYMROOT)
LIBSADIR = ../libsa
LIBSAIODIR = ../libsaio
UTILDIR = ../util
INC = -I. -I.. -I$(SYMDIR) -I$(LIBSADIR) -I$(LIBSAIODIR) -I$(UTILDIR)
MAKE = /bin/gnumake
ifneq "" "$(wildcard /bin/mkdirs)"
  MKDIRS = /bin/mkdirs
else
  MKDIRS = /bin/mkdir -p
endif
AS = as
LD = ld
# LIBS= -lc_static
LIBS=$(SYMROOT)/libsaio.a $(SYMROOT)/libsa.a $(SYMROOT)/librcz.a 

OTHER_FILES =

INSTALLDIR = $(DSTROOT)/usr/standalone/i386
VPATH = $(OBJROOT):$(SYMROOT)

# The ordering is important;
# boot2.o should be first.
OBJS = boot2.o boot.o \
	graphics.o prompt.o bitmaps.o \
	sizememory.o
# button.o browser.o scrollbar.o == NOTYET	

UTILDIR = ../util
SFILES = boot2.s
CFILES = boot.c load.c stringTable.c graphics.c browser.c \
	 button.c scrollbar.c prompt.c sizememory.c
HFILES = boot.h
OTHERFILES = Makefile machOconv.c README
ALLSRC = $(FOREIGNSRC) $(FOREIGNBIN) $(SFILES) $(CFILES) \
	$(HFILES) $(OTHERFILES)
DIRS_NEEDED = $(OBJROOT) $(SYMROOT)
BOOT2ADDR = 3000
# boot1 loads boot2 from raw sectors and reads exactly LOADSZ of them, so that
# is the real ceiling.  Read it out of boot1.s rather than keeping a second
# copy here that can drift out of step with it.
BOOT1SRC = ../boot1/boot1.s

all: $(DIRS_NEEDED) boot

boot: machOconv $(OBJS) $(LIBS)
	$(LD) -static -preload -segaddr __TEXT $(BOOT2ADDR) -segalign 10 \
		-o $(SYMROOT)/boot.sys $(OBJS) $(LIBS) $(NEXT_ROOT)/usr/lib/libcc.a
	machOconv $(SYMROOT)/boot.sys $(SYMROOT)/boot
	size $(SYMROOT)/boot.sys
	ls -l $(SYMROOT)/boot
	@( max=`gawk '/^LOADSZ/ { print $$3 * 512 }' $(BOOT1SRC)` ; \
	  if [ -z "$$max" ] ;\
	  then \
	    echo "Cannot read LOADSZ from $(BOOT1SRC)" ;\
	    rm $(SYMROOT)/boot ;\
	    exit 1;\
	  fi ;\
	  size=`ls -l $(SYMROOT)/boot | gawk '{ print $$5}'` ; \
	  if expr "$$size" ">" "$$max" > /dev/null ;\
	  then \
	    echo "Booter executable is $$size bytes; boot1 reads only $$max" ;\
	    rm $(SYMROOT)/boot ;\
	    exit 1;\
	  fi ;\
	  spare=`expr $$max - $$size` ; \
	  echo "booter $$size bytes of $$max, $$spare to spare" )
	

prompt.o: vers.h
vers.h:
	echo "#define I386BOOT_VERSION \"`vers_string -f 5.0`\"" | \
	  tr - . > $(SYMROOT)/vers.h

install_i386:: all $(INSTALLDIR)
	cp $(SYMROOT)/boot $(OTHER_FILES) $(INSTALLDIR)
	cd $(INSTALLDIR); chmod u+w boot $(OTHER_FILES)

clean::
	rm -f $(SYMROOT)/boot.sys $(SYMROOT)/boot

include ../MakeInc.dir

#dependencies
-include $(OBJROOT)/Makedep
