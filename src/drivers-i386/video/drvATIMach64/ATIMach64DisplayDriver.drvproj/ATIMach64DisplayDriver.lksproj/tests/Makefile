CC = cc
DRIVERKIT = ../../../../../../driverkit-3
KERNEL = ../../../../../../kernel-7
ARCHITECTURE = ../../../../../../architecture-1
CFLAGS ?= -O0 -g -I$(DRIVERKIT)
ARCH_FLAGS ?= -m32
ROOT = ../../../../../../../
LKS = ..
BUILD = build

.PHONY: check-abi check-data check-bios-segments check-bios-services check-mapping check-lifecycle check-dac clean

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/test_abi: test_abi.c | $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -o $@ test_abi.c

$(BUILD)/test_data: test_data.c mock_runtime.c $(LKS)/ATIData.c | $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -I$(LKS) -o $@ test_data.c mock_runtime.c $(LKS)/ATIData.c

$(BUILD)/test_bios_segments: test_bios_segments.m $(LKS)/ATI_BIOS.m $(LKS)/ATIbios16.c mock_runtime.c | $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -I$(LKS) -I$(KERNEL) -I$(ARCHITECTURE) -o $@ test_bios_segments.m $(LKS)/ATI_BIOS.m $(LKS)/ATIbios16.c mock_runtime.c

check-abi: $(BUILD)/test_abi
	./$(BUILD)/test_abi

check-data: $(BUILD)/test_data
	./$(BUILD)/test_data

check-bios-segments: $(BUILD)/test_bios_segments
	./$(BUILD)/test_bios_segments

check-bios-services check-mapping check-lifecycle check-dac:
	@echo "This check is added by its implementation task."
	exit 1

clean:
	rm -rf $(BUILD)
