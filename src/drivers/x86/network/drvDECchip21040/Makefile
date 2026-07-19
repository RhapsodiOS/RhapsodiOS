NAME = drvDECchip21040

export NEXT_ROOT

SRCROOT = .

INSTALLDIR = $(DSTROOT)/private/Drivers

BUNDLE = $(NAME).config

all: $(BUNDLE)

$(BUNDLE):
	cd DECchip21040.drvproj && $(MAKE)

clean:
	cd DECchip21040.drvproj && $(MAKE) clean

install: $(BUNDLE)
	cd DECchip21040.drvproj && $(MAKE) install DSTROOT=$(DSTROOT)

installhdrs:

installsrc:
	tar cf - . | (cd $(SRCROOT); tar xfBp -)
