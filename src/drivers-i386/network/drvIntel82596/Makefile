# Aggregate for the Intel 82596 DriverKit driver.
NAME = Intel82596NetworkDriver
PROJECTVERSION = 2.6
PROJECT_TYPE = Aggregate
LANGUAGE = English
BUNDLES = Intel82596NetworkDriver.drvproj
OTHERSRCS = Makefile Makefile.preamble PB.project
MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = aggregate.make
include $(MAKEFILEDIR)/platform.make
-include Makefile.preamble
include $(MAKEFILEDIR)/$(MAKEFILE)
-include Makefile.dependencies
