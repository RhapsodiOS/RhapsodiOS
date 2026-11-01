NAME = drvEtherLinkXL

export NEXT_ROOT

SRCROOT = .

INSTALLDIR = $(DSTROOT)/private/Drivers

BUNDLE = $(NAME).config

all: $(BUNDLE)

$(BUNDLE):
	cd EtherLinkXL.drvproj && $(MAKE)

clean:
	cd EtherLinkXL.drvproj && $(MAKE) clean

install: $(BUNDLE)
	cd EtherLinkXL.drvproj && $(MAKE) install DSTROOT=$(DSTROOT)

installhdrs:

installsrc:
	tar cf - . | (cd $(SRCROOT); tar xfBp -)
