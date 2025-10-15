#
# Makefile for PPCSerialPort driver
# PowerPC Zilog 8530 SCC Serial Port Driver
#

NAME = PPCSerialPort

BUNDLE_EXTENSION = config
BUNDLE_REGION = English

# Source files
MFILES = PPCSerialPort.m \
         PPCSerialHW.m

HFILES = PPCSerialPort.h \
         PPCSerialTypes.h \
         PPCSerialRegs.h

# Install location
INSTALL_DIR = $(DSTROOT)/System/Library/Drivers

# Compiler flags
CFLAGS = -O -g -Wall -Wno-import -arch ppc
LDFLAGS = -nostdlib

# Include DriverKit framework
FRAMEWORKS = -framework DriverKit

# Include directories
INCLUDES = -I. -I$(NEXT_ROOT)/System/Library/Frameworks/DriverKit.framework/Headers

# Library directories
LIBS = -L/lib -ldriver

# Default target
all: $(NAME).config

# Build the driver bundle
$(NAME).config: $(MFILES) $(HFILES)
	@echo "Building $(NAME) driver..."
	$(CC) $(CFLAGS) $(INCLUDES) -o $(NAME) $(MFILES) $(FRAMEWORKS) $(LDFLAGS) $(LIBS)
	@echo "Creating driver bundle..."
	@mkdir -p $(NAME).config/$(BUNDLE_REGION).lproj
	@cp $(NAME) $(NAME).config/
	@cp $(NAME)_reloc $(NAME).config/ 2>/dev/null || true
	@cp $(NAME).table $(NAME).config/$(BUNDLE_REGION).lproj/ 2>/dev/null || true
	@echo "Driver bundle created: $(NAME).config"

# Install target
install: $(NAME).config
	@echo "Installing $(NAME) driver..."
	@mkdir -p $(INSTALL_DIR)
	@cp -R $(NAME).config $(INSTALL_DIR)/
	@echo "Installation complete"

# Clean target
clean:
	@echo "Cleaning $(NAME)..."
	@rm -rf $(NAME) $(NAME).config $(NAME)_reloc *.o
	@echo "Clean complete"

# Help target
help:
	@echo "Makefile for PPCSerialPort driver"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build the driver (default)"
	@echo "  install  - Install the driver to $(INSTALL_DIR)"
	@echo "  clean    - Remove build artifacts"
	@echo "  help     - Display this help message"
	@echo ""
	@echo "Supported Hardware:"
	@echo "  - PowerMac Zilog 8530 SCC (Serial Communications Controller)"
	@echo "  - Modem Port and Printer Port on PowerMac systems"
	@echo "  - Supports AppleTalk SDLC mode"

.PHONY: all install clean help
