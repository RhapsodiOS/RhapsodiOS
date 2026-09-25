##
# Makefile for ca-certificates
##

# Project info
Project  = ca-certificates
UserType = Administration
ToolType = Commands

include $(MAKEFILEPATH)/CoreOS/ReleaseControl/Common.make

OPENSSLDIR = $(NSLIBRARYDIR)/OpenSSL
SSLDIR     = $(ETCDIR)/ssl
DOCDIR     = $(SHAREDIR)/doc/$(Project)

install::
	$(INSTALL_DIRECTORY) $(DSTROOT)$(OPENSSLDIR)/certs
	$(INSTALL_DIRECTORY) $(DSTROOT)$(SSLDIR)
	$(INSTALL_DIRECTORY) $(DSTROOT)$(DOCDIR)
	$(_v) for pem in $(Sources)/certs/*.pem; do \
	        $(INSTALL_FILE) -c $$pem $(DSTROOT)$(OPENSSLDIR)/certs || exit 1; \
	      done
	$(CAT) $(Sources)/certs/*.pem > $(DSTROOT)$(OPENSSLDIR)/cert.pem
	$(CHMOD) $(Install_File_Mode) $(DSTROOT)$(OPENSSLDIR)/cert.pem
	$(LN) -fs ../cert.pem $(DSTROOT)$(OPENSSLDIR)/certs/ca-certificates.crt
	$(LN) -fs $(OPENSSLDIR)/certs $(DSTROOT)$(SSLDIR)/certs
	$(LN) -fs $(OPENSSLDIR)/cert.pem $(DSTROOT)$(SSLDIR)/cert.pem
	$(INSTALL_FILE) -c $(Sources)/SOURCE $(DSTROOT)$(DOCDIR)
