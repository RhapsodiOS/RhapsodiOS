##
# Makefile for OpenSSH
##
# Wilfredo Sanchez, wsanchez@apple.com
##

# Project info
Project               = openssh
ProjectName           = OpenSSH
UserType              = Administrator
ToolType              = Services
Extra_CC_Flags        = -Wno-precomp
Extra_LD_Flags        = -L.
# The system zlib is 1.1.3, which configure refuses unless told otherwise.
Extra_Configure_Flags = --sysconfdir="/etc" --with-privsep-user=sshd --with-privsep-path=/var/empty --without-zlib-version-check
Extra_Install_Flags   = sysconfdir="$(DSTROOT)$(ETCDIR)"
GnuAfterInstall       = remove-manpages

# It's a GNU Source project
include $(MAKEFILEPATH)/CoreOS/ReleaseControl/GNUSource.make

# Plain "install" also makes host keys and runs sshd -t at package time.
Install_Target = install-nokeys

remove-manpages:
	$(_v) $(RM) -r "$(DSTROOT)$(MANDIR)"
