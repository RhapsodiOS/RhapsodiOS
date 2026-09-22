##
# Makefile for pico
##

# Project info
Project  = pico
UserType = Administration
ToolType = Commands

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/Common.make

install::
	$(INSTALL_DIRECTORY) $(DSTROOT)$(USRBINDIR)
	$(INSTALL_DIRECTORY) $(DSTROOT)$(MANDIR)/man1
	$(INSTALL_PROGRAM)   $(BuildDirectory)/pico/pico $(DSTROOT)$(USRBINDIR)
	$(INSTALL_FILE)      $(Sources)/doc/pico.1       $(DSTROOT)$(MANDIR)/man1

build:: shadow_source
	$(_v) $(MAKE) -C $(BuildDirectory)/pico -f makefile.rhp \
	      EXTRACFLAGS="$(CFLAGS)" EXTRALDFLAGS="$(LDFLAGS)" pico
