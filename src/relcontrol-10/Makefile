##
# Makefile for relcontrol
#
# The release this system reports, in
# /System/Library/CoreServices/software_version: the version on its first
# line and the build on its second, as Mac OS X Server 1.2.1 shipped it.
# NeXT's relcontrol kept the same file in /private/adm; CDIS's rc.cdrom reads
# it from CoreServices.
##

# Project info
Project  = relcontrol
UserType = Administration
ToolType = Commands

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/Common.make

CORESERVICESDIR = $(NSSYSTEMDIR)/Library/CoreServices

install::
	$(INSTALL_DIRECTORY) $(DSTROOT)$(CORESERVICESDIR)
	$(INSTALL_FILE) -c $(Sources)/software_version $(DSTROOT)$(CORESERVICESDIR)
