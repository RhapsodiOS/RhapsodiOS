################################################################################
# This is a top level makefile that will build all of the RhapsodiOS repository.
#
# The projects are listed, one per line, in the PROJECTS file.
#
# This makefile attempts to build all the projects in that file, matching
# the way they are built at Apple as closely as possible.

DSTROOT ?= /tmp/rhapsody/dst
OBJROOT ?= /tmp/rhapsody/obj
SYMROOT ?= /tmp/rhapsody/sym
SRCROOT ?= /tmp/rhapsody/src

RC_RELEASE ?= Rhapsody
RC_ARCHS ?= ppc i386
RC_OS ?= teflon

PROJECTDIRS = $(shell cat PROJECTS)
KERNELPROJECTS = kernel-7 machkit-1 driverkit-3 kernload-1 driverTools-1 boot-2

buildworld: $(PROJECTDIRS)

buildkernel: $(KERNELPROJECTS)

installkernel:
	@echo "Installing mach_kernel from $(DSTROOT) to /"
	sudo cp -p "$(DSTROOT)/mach_kernel" /

$(PROJECTDIRS) $(KERNELPROJECTS): _prep
	@mkdir -p "$(OBJROOT)/$@"
	@mkdir -p "$(SYMROOT)/$@"
	@mkdir -p "$(SRCROOT)/$@"
	@echo "Building $@ with make"
	@cd "$@" && \
	$(MAKE) DSTROOT="$(DSTROOT)" OBJROOT="$(OBJROOT)/$@" SYMROOT="$(SYMROOT)/$@" SRCROOT="$(SRCROOT)/$@" RC_ARCHS="$(RC_ARCHS)" RC_OS=$(RC_OS) installsrc && \
	cd "$(SRCROOT)/$@" && \
	$(MAKE) DSTROOT="$(DSTROOT)" OBJROOT="$(OBJROOT)/$@" SYMROOT="$(SYMROOT)/$@" SRCROOT="$(SRCROOT)/$@" RC_ARCHS="$(RC_ARCHS)" RC_OS=$(RC_OS) install

_prep:
	@mkdir -p "$(DSTROOT)"
	@mkdir -p "$(OBJROOT)"
	@mkdir -p "$(SYMROOT)"

clean:
	rm -rf "$(OBJROOT)" "$(SYMROOT)" "$(SRCROOT)"
realclean:
	rm -rf "$(DSTROOT)" "$(OBJROOT)" "$(SYMROOT)" "$(SRCROOT)"
