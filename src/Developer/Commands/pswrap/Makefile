##
# Package wrapper for the Project Builder pswrap tool.
##

Project  = pswrap
UserType = Developer
ToolType = Commands

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/Common.make

build::
	$(MAKE) -C $(Sources)/pswrap.tproj SRCROOT=$(Sources)/pswrap.tproj all

installhdrs::
	$(MAKE) -C $(Sources)/pswrap.tproj SRCROOT=$(Sources)/pswrap.tproj installhdrs

install::
	$(MAKE) -C $(Sources)/pswrap.tproj SRCROOT=$(Sources)/pswrap.tproj install
	$(INSTALL_DIRECTORY) $(DSTROOT)$(MANDIR)/man1
	$(INSTALL_FILE) -c $(Sources)/pswrap.tproj/pswrap.1 $(DSTROOT)$(MANDIR)/man1
