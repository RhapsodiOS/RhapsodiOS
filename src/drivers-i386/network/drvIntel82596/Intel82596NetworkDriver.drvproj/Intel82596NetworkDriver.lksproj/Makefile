NAME = Intel82596NetworkDriver
PROJECTVERSION = 2.7
PROJECT_TYPE = Kernel Server
LANGUAGE = English
CLASSES = Intel82596.m Intel82596Buf.m CogentEMaster.m IntelEEFlash32.m IntelPRO10PCI.m
CFILES =
HFILES = Intel82596.h Intel82596Private.h Intel82596Buf.h Intel82596Layout.h CogentEMaster.h IntelEEFlash32.h IntelPRO10PCI.h
OTHERSRCS = Load_Commands.sect Makefile Makefile.preamble
MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = kernelserver.make
NEXTSTEP_INSTALLDIR = $(NEXT_ROOT)/private/Drivers
include $(MAKEFILEDIR)/platform.make
-include Makefile.preamble
include $(MAKEFILEDIR)/$(MAKEFILE)
-include Makefile.dependencies
