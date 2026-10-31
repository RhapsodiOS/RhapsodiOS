
DIR = boot1
include ../MakePaths.dir

INSTALLDIR = $(DSTROOT)/usr/standalone/i386
DIRS_NEEDED = $(OBJROOT) $(SYMROOT)

FOREIGNNEXT = boot1

NASM = $(SYMROOT)/nasm

VERSIONED_FILES = boot1
VERS = `vers_string -f 5.0 | tr - .`
NEW_VERS = Rhapsody boot1 v$(VERS)

all: $(DIRS_NEEDED) $(VERSIONED_FILES)

boot1: boot1.s Makefile $(NASM)
	$(NASM) -dBOOTDEV=HDISK  -dVERS="'$(NEW_VERS)'" boot1.s -o $(SYMROOT)/$@

install_i386:: all $(INSTALLDIR)
	cp $(SYMROOT)/boot1 $(INSTALLDIR)/
	cd $(INSTALLDIR); chmod u+w $(FOREIGNNEXT)

include ../MakeInc.dir
