#
# Makefile for BusLogicFP_reloc
#

NAME = BusLogicFP_reloc

PROJECTVERSION = 1.0
LANGUAGE = English

CLASSES = BusLogicFPSCSI.m FlashPoint.c

HFILES = BusLogicFPSCSI.h FlashPoint.h

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble \
            Load_Commands.sect Makefile.driver_preamble

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = tool.make
SOURCEMODE = 444

LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
