# Private GNU builds inside the Project Builder aggregate.
SRCROOT ?= ..
OBJROOT ?= ../build
DSTROOT ?= ../dst
RC_ARCHS ?= i386 ppc
MAKE = /bin/gnumake

.PHONY: all build install installhdrs prebuild clean mostlyclean depend
all build install:
	/bin/sh build-tools.sh "$(SRCROOT)/e2fsprogs" "$(OBJROOT)/ext2_tools" "$(DSTROOT)" "$(RC_ARCHS)"

installhdrs prebuild depend:

clean mostlyclean:
	@echo 'Private objects are replaced by each build; no installed headers.'
