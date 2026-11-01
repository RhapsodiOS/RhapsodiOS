NAME = drvEtherExpress16

export NEXT_ROOT

SRCROOT = .

INSTALLDIR = $(DSTROOT)/private/Drivers

BUNDLE = $(NAME).config

all: $(BUNDLE)

$(BUNDLE):
	cd EtherExpress16.drvproj && $(MAKE)

clean:
	cd EtherExpress16.drvproj && $(MAKE) clean

install: $(BUNDLE)
	cd EtherExpress16.drvproj && $(MAKE) install DSTROOT=$(DSTROOT)

installhdrs:

installsrc:
	tar cf - . | (cd $(SRCROOT); tar xfBp -)
