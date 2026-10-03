CC = cc
DRIVERKIT = ../../../../../../driverkit-3
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

check-abi: $(BUILD)/test_abi
	./$(BUILD)/test_abi

check-data: $(BUILD)/test_data
	./$(BUILD)/test_data

check-bios-segments check-bios-services check-mapping check-lifecycle check-dac: check-data

clean:
	rm -rf $(BUILD)
