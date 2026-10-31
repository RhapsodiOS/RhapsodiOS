CC = cc
CFLAGS = -g -DPROCESSVIEWER_TEST -I.. -I.
ARCH_FLAGS =
FRAMEWORKS = -framework AppKit -framework Foundation
PRODUCTS = abi process process-types table controller inspector arguments-live process-live
SOURCES = ../Process.m ../ProcessType.m ../ProcessTableView.m \
	../UserIdCache.m ../ProcessControl.m ../Inspector.m test_support.m

.PHONY: all clean check-headers
all: check-headers $(PRODUCTS)

check-headers:
	python check_abi_headers.py

abi: abi.m $(SOURCES)
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ abi.m $(SOURCES) $(FRAMEWORKS)

abi-i386: abi_i386.m ../Process.m ../ProcessType.m ../ProcessTableView.m \
	../UserIdCache.m ../ProcessControl.m ../Inspector.m test_support.m
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ abi_i386.m ../Process.m ../ProcessType.m \
		../ProcessTableView.m ../UserIdCache.m ../ProcessControl.m ../Inspector.m \
		test_support.m $(FRAMEWORKS)

process: process.m $(SOURCES)
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ process.m $(SOURCES) $(FRAMEWORKS)

process-types: process_types.m ../ProcessType.m test_support.m
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ process_types.m ../ProcessType.m test_support.m $(FRAMEWORKS)

table: table.m $(SOURCES)
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ table.m $(SOURCES) $(FRAMEWORKS)

controller: controller.m ../Process.m ../ProcessType.m ../UserIdCache.m ../ProcessControl.m test_support.m
	$(CC) $(ARCH_FLAGS) -DPV_TEST_CONTROLLER_IMPLEMENTATION $(CFLAGS) -o $@ controller.m ../Process.m ../ProcessType.m ../UserIdCache.m ../ProcessControl.m test_support.m $(FRAMEWORKS)

inspector: inspector.m ../Inspector.m test_support.m
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ inspector.m ../Inspector.m test_support.m $(FRAMEWORKS)

arguments-live: arguments_live.m ../Process.m ../UserIdCache.m
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ arguments_live.m ../Process.m ../UserIdCache.m $(FRAMEWORKS)
	./$@ contains=a=b "argument with spaces" trailing
	./$@

process-live: process_live.m ../Process.m ../UserIdCache.m test_support.m
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o $@ process_live.m ../Process.m ../UserIdCache.m test_support.m $(FRAMEWORKS)
	./$@

clean:
	rm -f $(PRODUCTS) abi-i386
