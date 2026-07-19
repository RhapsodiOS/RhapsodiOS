NAME = drvEtherLink3

export NEXT_ROOT

SRCROOT = .

INSTALLDIR = $(DSTROOT)/private/Drivers

BUNDLE = $(NAME).config

all: $(BUNDLE)

$(BUNDLE):
	cd EtherLink3.drvproj && $(MAKE)

clean:
	cd EtherLink3.drvproj && $(MAKE) clean

install: $(BUNDLE)
	cd EtherLink3.drvproj && $(MAKE) install DSTROOT=$(DSTROOT)

installhdrs:

installsrc:
	tar cf - . | (cd $(SRCROOT); tar xfBp -)
