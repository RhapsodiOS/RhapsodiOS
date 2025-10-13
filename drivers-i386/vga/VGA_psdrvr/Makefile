#
# Makefile for VGA PostScript Driver
#

NAME = VGA_psdrvr

PROJECTVERSION = 1.0
LANGUAGE = English

CFILES = VGAPSDriver.c

HFILES = VGAPSDriver.h

OTHER_SRCS = VGA.ppd

PRODUCT = VGA_psdrvr

INSTALLDIR = $(DSTROOT)/usr/lib/PostScript

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = library.make

SOURCEMODE = 444

# Build as a shared library/bundle
LIBRARY_STYLE = BUNDLE

# Export all symbols for PostScript driver interface
EXPORT_SYMBOLS = VGAPSInit VGAPSCleanup VGAPSBeginPage VGAPSEndPage \
                 VGAPSRenderImage VGAPSSetColorSpace VGAPSSetGamma \
                 VGAPSGetDisplayInfo

LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
