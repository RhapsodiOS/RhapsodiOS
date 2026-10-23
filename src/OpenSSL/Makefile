##
# Makefile for OpenSSL
##

# Project info
Project         = openssl
ProjectName     = OpenSSL
UserType        = Developer
ToolType        = Libraries
Extra_CC_Flags  = -Wno-precomp

# GNUSource.make tests these while it is read, so they come first: each
# arch is configured, built and installed by the rules below instead.
GnuNoConfigure = YES
GnuNoBuild     = YES
GnuNoInstall   = YES

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/GNUSource.make

Configure_Flags = --prefix=/usr --openssldir=/System/Library/OpenSSL
Environment     = AR="$(SRCROOT)/ar.sh r" \
		  PERL='/usr/bin/perl' \
		  INCLUDEDIR="$(USRDIR)/local/include/openssl" \
		  MANDIR="$(MANDIR)" \
		  MANSUFFIX=ssl

Install_Target  = install

Version      := $(shell $(GREP) '^VERSION=' $(Sources)/Makefile | $(SED) 's/VERSION=//')
FileVersion  := $(shell echo $(Version) | $(SED) 's/[a-z].*//')
VersionFlags := -compatibility_version $(FileVersion) -current_version $(shell echo $(Version) | sed 's/[a-z]//g')
CC_Shlib      = $(CC) $(CC_Archs) -dynamiclib $(VersionFlags) -all_load

# Rhapsody's i386 assembler predates MMX and SSE2 ("no such 386 instruction:
# `pxor'"), so i386 builds its assembly without the SSE2 paths. Its cc has no
# '+' asm constraints ("output operand constraint contains `+'" in
# eng_padlock.c), so i386 also leaves out the VIA PadLock engine.
configure::
	$(_v) set -e; \
	for arch in $(RC_ARCHS); do \
		case $$arch in i386) arch_flags="no-sse2 -DOPENSSL_NO_HW_PADLOCK" ;; *) arch_flags= ;; esac; \
		rm -rf "$(OBJROOT)/$$arch"; \
		mkdir -p "$(OBJROOT)/$$arch"; \
		$(CP) -R -P "$(Sources)/." "$(OBJROOT)/$$arch"; \
		(cd "$(OBJROOT)/$$arch" && find . \( -type l -o -type f -size -2 \) -print | while read link; do \
			if [ -h "$$link" ]; then target=`ls -ld "$$link" | sed 's/.* -> //'`; \
			else target=`cat "$$link"`; fi; \
			case "$$target" in openssl-0.9.8zh/*) \
				rm -f "$$link"; \
				ln -s "`echo "$$target" | sed 's|^openssl-0.9.8zh/||'`" "$$link" ;; \
			esac; \
		done); \
		(cd "$(OBJROOT)/$$arch" && ./Configure $(Configure_Flags) $$arch_flags rhapsody-$$arch-cc); \
	done

build:: configure
	$(_v) set -e; \
	for arch in $(RC_ARCHS); do \
		(cd "$(OBJROOT)/$$arch" && $(MAKE) CC="cc -arch $$arch" $(Environment)); \
	done

install:: build
	$(_v) set -e; \
	for arch in $(RC_ARCHS); do \
		(cd "$(OBJROOT)/$$arch" && $(MAKE) install INSTALL_PREFIX="$(OBJROOT)/dst-$$arch" $(Environment)); \
	done; \
	set -- $(RC_ARCHS); first=$$1; \
	$(MKDIR) -p "$(DSTROOT)"; \
	(cd "$(OBJROOT)/dst-$$first" && pax -rw . "$(DSTROOT)"); \
	$(MKDIR) -p "$(DSTROOT)$(USRLIBDIR)" "$(DSTROOT)$(USRBINDIR)"; \
	for lib in libcrypto.a libssl.a; do \
		set --; \
		for arch in $(RC_ARCHS); do set -- "$$@" "$(OBJROOT)/dst-$$arch/usr/lib/$$lib"; done; \
		lipo -create "$$@" -output "$(DSTROOT)$(USRLIBDIR)/$$lib"; \
	done; \
	set --; \
	for arch in $(RC_ARCHS); do set -- "$$@" "$(OBJROOT)/dst-$$arch/usr/bin/openssl"; done; \
	lipo -create "$$@" -output "$(DSTROOT)$(USRBINDIR)/openssl"; \
	if [ -d "$(DSTROOT)$(USRDIR)/include/openssl" ]; then \
		$(MKDIR) -p "$(DSTROOT)$(USRDIR)/local/include"; \
		mv "$(DSTROOT)$(USRDIR)/include/openssl" "$(DSTROOT)$(USRDIR)/local/include/openssl"; \
		rmdir "$(DSTROOT)$(USRDIR)/include" 2>/dev/null || true; \
	fi; \
	if [ -f "$(OBJROOT)/dst-ppc/usr/include/openssl/opensslconf.h" ] && \
	   [ -f "$(OBJROOT)/dst-i386/usr/include/openssl/opensslconf.h" ]; then \
		diff -D __ppc__ "$(OBJROOT)/dst-i386/usr/include/openssl/opensslconf.h" \
			"$(OBJROOT)/dst-ppc/usr/include/openssl/opensslconf.h" \
			> "$(DSTROOT)$(USRDIR)/local/include/openssl/opensslconf.h" || test $$? = 1; \
	fi; \
	$(MAKE) shlibs strip

test:: build
	$(_v) cd "$(OBJROOT)/i386" && $(MAKE) test

shlibs:
	@echo "Building shared libraries..."
	$(_v) $(CC_Shlib) "$(DSTROOT)$(USRLIBDIR)/libcrypto.a" \
		-install_name "$(USRLIBDIR)/libcrypto.$(FileVersion).dylib" \
		-o "$(DSTROOT)$(USRLIBDIR)/libcrypto.$(FileVersion).dylib"
	$(_v) $(CC_Shlib) "$(DSTROOT)$(USRLIBDIR)/libssl.a" \
		"$(DSTROOT)$(USRLIBDIR)/libcrypto.$(FileVersion).dylib" \
		-install_name "$(USRLIBDIR)/libssl.$(FileVersion).dylib" \
		-o "$(DSTROOT)$(USRLIBDIR)/libssl.$(FileVersion).dylib"
	$(_v) for lib in crypto ssl; do \
		$(LN) -fs "lib$${lib}.$(FileVersion).dylib" "$(DSTROOT)$(USRLIBDIR)/lib$${lib}.dylib"; \
		$(RM) "$(DSTROOT)$(USRLIBDIR)/lib$${lib}.a"; \
	      done

# c_rehash in USRBINDIR is a script; openssl is the one executable to strip.
strip:
	$(_v) $(STRIP)    $(DSTROOT)$(USRBINDIR)/openssl
	$(_v) $(STRIP) -S $(shell $(FIND) $(DSTROOT)$(USRLIBDIR) -type f)
