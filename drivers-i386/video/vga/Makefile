#
# Makefile for VGA Driver
#

NAME = VGA

PROJECTVERSION = 1.0
LANGUAGE = English

SUBPROJECTS = VGA_reloc.tproj

INSTALLDIR = $(DSTROOT)/usr/Devices/$(NAME).config

INSTALL_AS_USER = root
INSTALL_AS_GROUP = wheel

SRCROOT = .
OBJROOT = .
SYMROOT = .

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = bundle.make

GLOBAL_RESOURCES = Default.table Display.modes

OTHER_RESOURCES = VGA_psdrvr/VGA.ppd

WINDOWS_RESOURCES =

BUNDLE_EXTENSION = config

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
