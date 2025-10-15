##
# Makefile for BeepDriver (PC Speaker Beep Driver)
##

NAME = BeepDriver
BUNDLE_EXTENSION = config

OBJC_FILES = BeepDriver.m
HEADER_FILES = BeepDriver.h BeepTypes.h PCSpeakerRegs.h

OTHER_RESOURCES = Beep.table
INSTALL_BIN_DIR = /System/Library/Drivers

# Export symbols for kernel linking
EXPORT_SYMBOLS = YES

# Compiler flags
CFLAGS += -DKERNEL -DDRIVER_PRIVATE -D__APPLE__ -D__NeXT__

# Linker flags for driver bundle
LDFLAGS += -nostdlib -r

MAKEFILEDIR = $(NEXT_ROOT)/NextDeveloper/Makefiles/app
MAKEFILE = bundle.make

include $(MAKEFILEDIR)/$(MAKEFILE)
