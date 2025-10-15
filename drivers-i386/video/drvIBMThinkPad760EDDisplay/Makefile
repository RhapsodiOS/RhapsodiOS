NAME = IBMThinkPad760EDDisplayDriver

DRIVERKIT = YES

DRIVER_INSTALL_DIR = $(SYSTEM_LIBRARY_DIR)/Drivers

OBJCFILES = IBMThinkPad760EDDisplayDriver.m \
            IBMThinkPad760EDDisplayDriverKernelServerInstance.m

HFILES = IBMThinkPad760EDDisplayDriver.h \
         IBMThinkPad760EDDisplayDriverKernelServerInstance.h

INSTALL_BIN_DIR = .

INSTALL_HDR_DIR = .

MAKEFILEDIR = /NextDeveloper/Makefiles/CoreOS
-include Makefile.preamble
include $(MAKEFILEDIR)/kernel-driver.make
-include Makefile.postamble
-include Makefile.dependencies

PRODUCT = $(NAME).config
DSTROOT = /

PRODUCT_DIR = $(DSTROOT)$(DRIVER_INSTALL_DIR)/$(PRODUCT)

install: all
	$(MKDIRS) $(PRODUCT_DIR)
	install -c -m 644 $(NAME)_reloc $(PRODUCT_DIR)
	install -c -m 644 Default.table $(PRODUCT_DIR)
	install -c -m 644 Instance*.table $(PRODUCT_DIR) 2>/dev/null || true
