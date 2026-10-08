CC ?= cc
CFLAGS ?= -O2 -Wall
all: ext2_io partition_info
ext2_io: ext2_io.c
	$(CC) $(CFLAGS) -I../../kernel-7/bsd ext2_io.c -o $@
partition_info: partition_info.c ../../kernel-7/bsd/dev/disk.h
	$(CC) $(CFLAGS) -I../../kernel-7/bsd partition_info.c -o $@
legacy_io: legacy_io.c
	$(CC) $(CFLAGS) legacy_io.c -o $@
clean:
	rm -f ext2_io partition_info legacy_io

# Private compile-time paths exercise production common and command code.
TEST_DIR = $(shell pwd)/.tool-tests
HEADERS = $(NEXT_ROOT)/System/Library/Frameworks/System.framework/Versions/B/Headers
TOOL_CPPFLAGS = -I$(HEADERS)/bsd -I$(HEADERS)/bsd/ext2fs -I$(HEADERS) -I../common
TOOL_PATHS = -DEXT2_MKE2FS='"$(TEST_DIR)/fake"' -DEXT2_E2FSCK='"$(TEST_DIR)/fake"' -DEXT2_NEWFS='"$(TEST_DIR)/fake"' -DEXT2_FSCK='"$(TEST_DIR)/fake"' -DEXT2_MOUNT='"$(TEST_DIR)/fake"' -DEXT2_UMOUNT='"$(TEST_DIR)/fake"' -DEXT2_DEVICE_DIRECTORY='"$(TEST_DIR)"' -DEXT2_FS_DIRECTORY='"$(TEST_DIR)"'
TOOL_COMMON = $(TEST_DIR)/common.o $(TEST_DIR)/disk.o $(TEST_DIR)/bswap.o $(TEST_DIR)/provider.o
check-tools: build-tools-test
	$(TEST_DIR)/tool_test
build-tools-test: ../common/ext2_tool.c ../common/ext2_disk.c ../common/ext2fs_bswap.c ../ext2_newfs/newfs_ext2fs.c ../ext2_fsck/fsck_ext2fs.c ../ext2_util/ext2fs.util_main.c
	mkdir -p $(TEST_DIR)
	$(CC) $(CFLAGS) tool_fake.c -o $(TEST_DIR)/fake
	echo '#include "$(shell pwd)/tool_overrides.h"' > $(TEST_DIR)/common-test.c
	echo '#include "$(shell pwd)/../common/ext2_tool.c"' >> $(TEST_DIR)/common-test.c
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) -c $(TEST_DIR)/common-test.c -o $(TEST_DIR)/common.o
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) -c ../common/ext2_disk.c -o $(TEST_DIR)/disk.o
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) -c ../common/ext2fs_bswap.c -o $(TEST_DIR)/bswap.o
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) -c tool_provider.c -o $(TEST_DIR)/provider.o
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) $(TOOL_PATHS) ../ext2_newfs/newfs_ext2fs.c $(TOOL_COMMON) -o $(TEST_DIR)/newfs_ext2fs
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) $(TOOL_PATHS) ../ext2_fsck/fsck_ext2fs.c $(TOOL_COMMON) -o $(TEST_DIR)/fsck_ext2fs
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) $(TOOL_PATHS) ../ext2_util/ext2fs.util_main.c $(TOOL_COMMON) -o $(TEST_DIR)/ext2fs.util
	$(CC) $(CFLAGS) $(TOOL_CPPFLAGS) -DTEST_DIR='"$(TEST_DIR)"' tool_test.c $(TOOL_COMMON) -o $(TEST_DIR)/tool_test

# VENDOR_SOURCE and VENDOR_OBJECTS identify an actual configured vendor build.
check-vendor-io:
	/bin/sh ./run-vendor-io.sh "$(VENDOR_SOURCE)" "$(VENDOR_OBJECTS)" "$(TEST_DIR)/vendor-io" $(VENDOR_IO_ACTION)
check-configure-order:
	/bin/sh ./run-configure-order.sh ../ext2_tools/build-tools.sh "$(VENDOR_SOURCE)" "$(TEST_DIR)/configure-order"
check-checksum-partition:
	/bin/sh ./run-checksum-partition.sh ./checksum-partition.sh "$(TEST_DIR)/checksum-partition"

# Native Objective-C: exact discovery implementation, private exposed devices.
DISCOVERY_SOURCE = $(shell pwd)/../../Commands/diskdev_cmds/autodiskmount.tproj/DiskVolume.m
DISCOVERY_HEADER = $(shell pwd)/../../Commands/diskdev_cmds/autodiskmount.tproj/DiskVolume.h
DISCOVERY_DIR = $(TEST_DIR)/discovery
check-discovery: build-discovery-test
	$(TEST_DIR)/discovery_test
build-discovery-test:
	mkdir -p $(TEST_DIR)
	$(CC) $(CFLAGS) -DDISCOVERY_SOURCE='"$(DISCOVERY_SOURCE)"' -DDISCOVERY_DIRECTORY='"$(DISCOVERY_DIR)"' discovery_test.m -o $(TEST_DIR)/discovery_test
build-discovery-native:
	mkdir -p $(TEST_DIR)
	$(CC) $(CFLAGS) -DDISCOVERY_HEADER='"$(DISCOVERY_HEADER)"' discovery_native.m $(DISCOVERY_SOURCE) -lDriver -o $(TEST_DIR)/discovery-native
	$(CC) $(CFLAGS) discovery_media.c -o $(TEST_DIR)/discovery-media
