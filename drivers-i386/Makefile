#
# Master Makefile for i386 Drivers
# Copyright (c) 2025 RhapsodiOS Project
#
# This makefile builds all i386-specific drivers
#

# List of driver subdirectories
SUBDIRS = drvAdaptec1542B \
          drvAMDPCSCSIDriver \
          drvEIDE \
          drvIntelAC97Sound \
          drvMatroxMGA \
          drvNE2k \
          drvS3Generic \
          drvSB8Sound \
          drvSB16Sound \
          drvSB128Sound \
          drvSMC16 \
          drvVMXNet

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
	@echo "Cleaning all i386 drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Cleaning $$dir..."; \
		cd $$dir && $(MAKE) clean && cd ..; \
	done
	@echo "Clean complete"

# Install all drivers
install:
	@echo "Installing all i386 drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Installing $$dir..."; \
		cd $$dir && $(MAKE) install && cd ..; \
	done
	@echo "Install complete"

# Installsrc - copy sources to SRCROOT
installsrc:
	@echo "Installing sources for all i386 drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Installing sources for $$dir..."; \
		cd $$dir && $(MAKE) installsrc && cd ..; \
	done
	@echo "Installsrc complete"

# Installhdrs - install headers
installhdrs:
	@echo "Installing headers for all i386 drivers..."
	@for dir in $(SUBDIRS); do \
		echo "Installing headers for $$dir..."; \
		cd $$dir && $(MAKE) installhdrs && cd ..; \
	done
	@echo "Installhdrs complete"

# Declare phony targets
.PHONY: all clean install installsrc installhdrs $(SUBDIRS)
