##
# Makefile for ParallelPort driver
##

NAME = ParallelPort
BUNDLE_EXTENSION = config

OBJC_FILES = ParallelPortDriver.m
HEADER_FILES = ParallelPortDriver.h ParallelPortRegs.h ParallelPortTypes.h

OTHER_RESOURCES = ParallelPort.table
INSTALL_BIN_DIR = /System/Library/Drivers

# Command line tools
TOOLS = InstallPPDev RemovePPDev
TOOL_OBJC_FILES = InstallPPDev.m RemovePPDev.m
TOOL_INSTALL_DIR = /usr/local/bin

MAKEFILEDIR = $(NEXT_ROOT)/NextDeveloper/Makefiles/app
MAKEFILE = bundle.make

include $(MAKEFILEDIR)/$(MAKEFILE)

# Build command line tools
all: bundle tools

tools: $(TOOLS)

InstallPPDev: InstallPPDev.m
	$(CC) $(CFLAGS) -o InstallPPDev InstallPPDev.m \
		-framework Foundation -framework DriverKit $(LIBS)

RemovePPDev: RemovePPDev.m
	$(CC) $(CFLAGS) -o RemovePPDev RemovePPDev.m \
		-framework Foundation -framework DriverKit $(LIBS)

install-tools: tools
	$(MKDIRS) $(DSTROOT)$(TOOL_INSTALL_DIR)
	$(INSTALL) -c -m 755 InstallPPDev $(DSTROOT)$(TOOL_INSTALL_DIR)
	$(INSTALL) -c -m 755 RemovePPDev $(DSTROOT)$(TOOL_INSTALL_DIR)

install: install-bundle install-tools

clean: clean-bundle clean-tools

clean-tools:
	$(RM) -f $(TOOLS) *.o
