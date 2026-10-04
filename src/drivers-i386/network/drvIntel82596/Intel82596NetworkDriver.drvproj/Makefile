NAME = Intel82596NetworkDriver
PROJECTVERSION = 2.6
PROJECT_TYPE = Driver
LANGUAGE = English
LOCAL_RESOURCES = Localizable.strings EEFlash32.strings EM932.strings EM945.strings IntelPRO10PCI.strings DriverHelp
GLOBAL_RESOURCES = Default.table EEFlash32.table EM932.table EM945.table IntelPRO10PCI.table
CLASSES =
HFILES =
TOOLS = Intel82596NetworkDriver.lksproj
OTHERSRCS = Makefile Makefile.preamble DriverInfo
MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = driver.make
NEXTSTEP_INSTALLDIR = $(NEXT_ROOT)/private/Drivers
BUNDLE_EXTENSION = config
include $(MAKEFILEDIR)/platform.make
-include Makefile.preamble
include $(MAKEFILEDIR)/$(MAKEFILE)
-include Makefile.postamble
-include Makefile.dependencies
