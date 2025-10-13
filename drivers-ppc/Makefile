#
# Master Makefile for PowerPC Drivers
# Copyright (c) 2025 RhapsodiOS Project
#
# This makefile builds all PowerPC-specific drivers
#

# List of driver subdirectories
SUBDIRS = drvPExpert \
		  drvPPCAwacs \
          drvPPCBurgundy \
          drvPPCGem \
          drvPPCGNic \
          drvPPCSerialPort

# Default target - build all drivers
all: $(SUBDIRS)

# Build each driver
$(SUBDIRS):
	@echo "Building $@..."
	@cd $@ && $(MAKE) all
	@echo "Finished building $@"
	@echo ""

# Clean all drivers
clean:
	@echo "Cleaning all PowerPC drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Cleaning $$dir..."; \
		cd $$dir && $(MAKE) clean && cd ..; \
	done
	@echo "Clean complete"

# Install all drivers
install:
	@echo "Installing all PowerPC drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Installing $$dir..."; \
		cd $$dir && $(MAKE) install && cd ..; \
	done
	@echo "Install complete"

# Installsrc - copy sources to SRCROOT
installsrc:
	@echo "Installing sources for all PowerPC drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Installing sources for $$dir..."; \
		cd $$dir && $(MAKE) installsrc && cd ..; \
	done
	@echo "Installsrc complete"

# Installhdrs - install headers
installhdrs:
	@echo "Installing headers for all PowerPC drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Installing headers for $$dir..."; \
		cd $$dir && $(MAKE) installhdrs && cd ..; \
	done
	@echo "Installhdrs complete"

# Declare phony targets
.PHONY: all clean install installsrc installhdrs $(SUBDIRS)
