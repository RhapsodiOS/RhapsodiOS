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
	$(INSTALL_DIRECTORY) $(DSTROOT)$(SHAREDIR)/doc/pico
	$(INSTALL_PROGRAM)   $(BuildDirectory)/pico/pico $(DSTROOT)$(USRBINDIR)
	$(INSTALL_FILE) -c   $(Sources)/doc/pico.1       $(DSTROOT)$(MANDIR)/man1
	$(INSTALL_FILE) -c   $(Sources)/CPYRIGHT         $(DSTROOT)$(SHAREDIR)/doc/pico
	$(INSTALL_FILE) -c   $(Sources)/LOCAL-CHANGES    $(DSTROOT)$(SHAREDIR)/doc/pico

build:: shadow_source
	$(_v) $(MAKE) -C $(BuildDirectory)/pico -f makefile.rhp \
	      EXTRACFLAGS="$(CFLAGS)" EXTRALDFLAGS="$(LDFLAGS)" pico
