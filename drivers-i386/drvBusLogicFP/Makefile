#
# Makefile for BusLogic FlashPoint SCSI Driver
#

NAME = BusLogicFP

PROJECTVERSION = 1.0
LANGUAGE = English

LOCAL_RESOURCES =

GLOBAL_RESOURCES = Default.table

TOOLS = BusLogicFP_reloc.tproj

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = bundle.make
INSTALLDIR = /usr/Devices
INSTALLFLAGS = -c -s -m 755
SOURCEMODE = 444

LIBS = -lIndexing_s
PROF_LIBS = -lIndexing_s

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
