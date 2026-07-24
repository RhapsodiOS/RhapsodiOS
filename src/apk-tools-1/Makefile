# RhapsodiOS project wrapper for apk-tools. The upstream source lives in
# apk-tools/ and uses DESTDIR/SBINDIR; map the standard DSTROOT-based targets
# onto it. rbuild invokes `make -C <srcroot> install DSTROOT=...`.
SUBDIR = apk-tools

all:
	cd $(SUBDIR) && $(MAKE) all

install:
	cd $(SUBDIR) && $(MAKE) install DESTDIR=$(DSTROOT)

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	cd $(SUBDIR) && $(MAKE) clean

.PHONY: all install installhdrs installsrc clean
