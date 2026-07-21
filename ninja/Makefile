##
# Makefile for the ninja/samurai build orchestration.
#
# This builds the vendored samurai build tool (samu), the `rhap-build`
# command, (re)generates the top-level build.ninja, and hands off to samu
# to build the tree.
#
#   make            # build samu + rhap-build and generate ../build.ninja
#   make world      # generate, then `samu buildworld`
#   make kernel     # generate, then `samu buildkernel`
#   make samu       # just build the vendored samurai build tool
#   make clean      # remove rhap-build and clean samurai
#
# Override any of the staging locations / target settings on the command line:
#   make world DSTROOT=/build/dst RC_ARCHS=i386
#
# To use an external samu instead of the vendored one:
#   make world SAMU=/usr/local/bin/samu
##

CC       = cc
CFLAGS   = -O -Wall

# Absolute path to vendored samu so it survives `cd ..` when running builds.
# $(CURDIR) needs GNU make >= 3.77; $(shell pwd) works on Rhapsody gnumake 3.74.
SAMU     = $(shell pwd)/samurai/samu

# Staging locations (shared DSTROOT; per-project obj/sym/src bases).
# Plain = (not ?=): GNU make 3.74 has no ?=; CLI overrides still win.
DSTROOT  = /tmp/rhapsody/dst
OBJROOT  = /tmp/rhapsody/obj
SYMROOT  = /tmp/rhapsody/sym
SRCBASE  = /tmp/rhapsody/src
TOOLROOT = $(DSTROOT)
RC_ARCHS = ppc i386
RC_OS    = teflon

GENFLAGS = --srcroot "src" \
	   --dstroot "$(DSTROOT)" --objroot "$(OBJROOT)" \
	   --symroot "$(SYMROOT)" --srcbase "$(SRCBASE)" \
	   --toolroot "$(TOOLROOT)" \
	   --rc-archs "$(RC_ARCHS)" --rc-os "$(RC_OS)" \
	   --wrapper ninja/buildproj.sh

all: samu rhap-build generate

RHAP_SRCS = rhap-build.c generate.c mkapk.c index.c util.c

rhap-build: $(RHAP_SRCS)
	$(CC) $(CFLAGS) -o $@ $(RHAP_SRCS)

# Build the vendored samurai (samu) build tool using its own Makefile.
samu:
	$(MAKE) -C samurai

# Generate ../build.ninja from the repo root so that project paths and the
# wrapper path (ninja/buildproj.sh) are relative to where samu is run.
generate: rhap-build
	cd .. && ninja/rhap-build generate $(GENFLAGS)

world: samu
	cd .. && SAMU="$(SAMU)" ninja/rhap-build build buildworld

kernel: samu
	cd .. && SAMU="$(SAMU)" ninja/rhap-build build buildkernel

clean:
	rm -f rhap-build genninja
	-$(MAKE) -C samurai clean

.PHONY: all samu generate world kernel clean rhap-build
