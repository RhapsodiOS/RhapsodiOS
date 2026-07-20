PRODUCT_NAME = local.nidb
PRODUCT = $(SYMROOT)/$(PRODUCT_NAME)
NIDIR = $(DSTROOT)/private/etc/netinfo/

all: $(PRODUCT)
	@echo -n ""

$(PRODUCT): $(SYMROOT) $(SYMROOT)/make_local
	@rm -rf $@
	CWD=`pwd`; cd ${SYMROOT}; SYMROOT=`pwd`; cd $$CWD; 		\
	$(SYMROOT)/make_local $@ $(DSTROOT)/usr/sbin/netinfod $(DSTROOT)/usr/bin/niutil $(DSTROOT)/usr/bin/niload

clean actual_clean really_clean:
	@rm -rf $(PRODUCT) $(SYMROOT)/make_local

install: all
	-mkdirs $(NIDIR)/$(PRODUCT_NAME)
	chmod 755 $(NIDIR)
	cd $(PRODUCT); for i in *; do \
		install -m 640 $$i $(NIDIR)/$(PRODUCT_NAME); \
	done 
	chown -R root.operator $(NIDIR)

installsrc: $(SRCROOT)$(SRCPATH)
	cp Makefile make_local.sh $(SRCROOT)$(SRCPATH)

$(SYMROOT)/make_local: make_local.sh
	cp $? $@
	chmod +x $@

$(SRCROOT)$(SRCPATH) $(SYMROOT):
	-mkdirs $@

installhdrs_recursively:

installhdrs:

