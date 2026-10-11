##
# Makefile for OpenSSL
##

# Project info
Project         = openssl
ProjectName     = OpenSSL
UserType        = Developer
ToolType        = Libraries
Configure       = $(Sources)/config
Extra_CC_Flags  = -Wno-precomp

# config is kinda like configure
include $(MAKEFILEPATH)/CoreOS/ReleaseControl/GNUSource.make

GnuNoConfigure = YES
GnuNoBuild     = YES
GnuNoInstall   = YES

Configure_Flags = --prefix=/usr --openssldir=/System/Library/OpenSSL
Environment     = AR="$(SRCROOT)/ar.sh r" \
		  PERL='/usr/bin/perl' \
		  INCLUDEDIR="$(USRDIR)/local/include/openssl" \
		  MANDIR="$(MANDIR)"

Install_Target  = install

Version      := $(shell $(GREP) 'VERSION=' $(Sources)/Makefile | $(SED) 's/VERSION=//')
FileVersion  := $(shell echo $(Version) | $(SED) 's/[a-z].*//')
VersionFlags := -compatibility_version $(FileVersion) -current_version $(shell echo $(Version) | sed 's/[a-z]//g')
CC_Shlib      = $(CC) $(CC_Archs) -dynamiclib $(VersionFlags) -all_load

configure::
	$(_v) set -e; \
	for arch in $(RC_ARCHS); do \
		rm -rf "$(OBJROOT)/$$arch"; \
		mkdir -p "$(OBJROOT)/$$arch"; \
		$(CP) -R "$(Sources)/." "$(OBJROOT)/$$arch"; \
		(cd "$(OBJROOT)/$$arch" && ./Configure $(Configure_Flags) rhapsody-$$arch-cc); \
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
	$(CP) -R "$(OBJROOT)/dst-$$first/." "$(DSTROOT)"; \
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
	   [ -f "$(OBJROOT)/dst-i386/usr/include/openssl/opensslconf.h" ] && \
	   ! cmp -s "$(OBJROOT)/dst-ppc/usr/include/openssl/opensslconf.h" "$(OBJROOT)/dst-i386/usr/include/openssl/opensslconf.h"; then \
		awk 'NR == FNR { ppc[FNR] = $$0; ppc_lines = FNR; next } \
		     { if (FNR > ppc_lines) exit 1; \
		       if (ppc[FNR] == $$0) print; \
		       else { print "#if defined(__ppc__)"; print ppc[FNR]; print "#elif defined(__i386__)"; print; print "#endif"; } } \
		     END { if (FNR != ppc_lines) exit 1 }' \
			"$(OBJROOT)/dst-ppc/usr/include/openssl/opensslconf.h" \
			"$(OBJROOT)/dst-i386/usr/include/openssl/opensslconf.h" \
			> "$(DSTROOT)$(USRDIR)/local/include/openssl/opensslconf.h.new"; \
		mv "$(DSTROOT)$(USRDIR)/local/include/openssl/opensslconf.h.new" "$(DSTROOT)$(USRDIR)/local/include/openssl/opensslconf.h"; \
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
