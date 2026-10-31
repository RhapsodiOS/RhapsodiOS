CC = cc
DRIVERKIT = ../../../../../../driverkit-3
KERNEL = ../../../../../../kernel-7
ARCHITECTURE = ../../../../../../architecture-1
CFLAGS ?= -O0 -g -I$(DRIVERKIT)
ARCH_FLAGS ?= -m32
ROOT = ../../../../../../../
LKS = ..
BUILD = build

.PHONY: check-abi check-data check-bios-segments check-bios-services check-mapping check-lifecycle check-init-mapping check-dac clean

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/test_abi: test_abi.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -o $@ test_abi.c

$(BUILD)/test_data: test_data.c mock_runtime.c $(LKS)/ATIData.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -I$(LKS) -o $@ test_data.c mock_runtime.c $(LKS)/ATIData.c

$(BUILD)/test_bios_segments: test_bios_segments.m $(LKS)/ATI_BIOS.m $(LKS)/ATIbios16.c mock_runtime.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -DATI_BIOS_TEST -I$(LKS) -I$(KERNEL) -I$(ARCHITECTURE) -o $@ test_bios_segments.m $(LKS)/ATI_BIOS.m $(LKS)/ATIbios16.c mock_runtime.c

$(BUILD)/test_dac: test_dac.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -DATI_BIOS_TEST -DATI_DAC_TEST -I$(LKS) -I$(KERNEL) -I$(ARCHITECTURE) -o $@ test_dac.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c

$(BUILD)/test_mapping: test_mapping.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -DATI_BIOS_TEST -DATI_DAC_TEST -I$(LKS) -I$(KERNEL) -I$(ARCHITECTURE) -o $@ test_mapping.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c

$(BUILD)/test_lifecycle: test_lifecycle.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -DATI_BIOS_TEST -DATI_DAC_TEST -I$(LKS) -I$(KERNEL) -I$(ARCHITECTURE) -o $@ test_lifecycle.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c

$(BUILD)/test_init_mapping: test_init_mapping.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c $(BUILD)
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -DATI_BIOS_TEST -DATI_DAC_TEST -I$(LKS) -I$(KERNEL) -I$(ARCHITECTURE) -o $@ test_init_mapping.m mock_driverkit.m $(LKS)/ATIMach64DisplayDriver.m $(LKS)/ATIPrivate.m $(LKS)/ATI_BIOS.m $(LKS)/ProgramDAC.m $(LKS)/ATIData.c $(LKS)/ATIbios16.c mock_runtime.c

check-abi: $(BUILD)/test_abi
	./$(BUILD)/test_abi

check-data: $(BUILD)/test_data
	./$(BUILD)/test_data

check-bios-segments: $(BUILD)/test_bios_segments
	./$(BUILD)/test_bios_segments

check-bios-services: check-bios-segments

check-dac: $(BUILD)/test_dac
	./$(BUILD)/test_dac

check-mapping: $(BUILD)/test_mapping
	./$(BUILD)/test_mapping

check-lifecycle: $(BUILD)/test_lifecycle
	./$(BUILD)/test_lifecycle

check-init-mapping: $(BUILD)/test_init_mapping
	./$(BUILD)/test_init_mapping

clean:
	rm -rf $(BUILD)
