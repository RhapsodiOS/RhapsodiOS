BUILD := BUILD
BOOT2 := ../../boot-2/i386
KERNEL7 := ../../kernel-7

# GNU make predefines CC=cc (origin "default"), which ?= would leave in place;
# this host has no cc.  An explicit CC=... on the command line or in the
# environment still wins.
ifeq ($(origin CC),default)
CC := clang
endif

COMMON_FLAGS := -std=gnu89 -g -O0 -Wno-implicit-int \
          -Wno-implicit-function-declaration -Wno-return-type \
          -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 \
          -D__ARCHITECTURE__=\"i386\" \
          -include host_bios_addr.h \
          -I. -Ihost_includes -I$(BOOT2)/libsaio -I$(BOOT2)/libsa -I$(BOOT2)/util \
          -idirafter $(KERNEL7) -idirafter $(KERNEL7)/bsd

# boot2's own sources (and the driver that calls into them) declare their
# own open/read/close/lseek (saio_internal.h) that would otherwise collide
# at link time with libSystem's real ones -- rename them.  (__i386__, needed
# by <architecture/byte_order.h> and <mach/i386/simple_lock.h> since we're
# building this 1999 i386-only code natively as x86_64, is scoped locally
# inside the host_includes/ shims for those two headers instead of defined
# here -- see host_includes/architecture/byte_order.h for why.)
BOOT2_CFLAGS := $(COMMON_FLAGS) \
          -Dopen=sa_open -Dread=sa_read -Dclose=sa_close -Dlseek=sa_lseek

# host_devread.c makes the one real open(2)/pread(2) on the image file, so
# it must NOT get the open/read/close/lseek renaming -- applying it here
# would also rename <fcntl.h>/<unistd.h>'s own declarations of open/read/
# close, silently aliasing our calls onto the wrong symbols.  It also must
# NOT get -D__i386__=1: the host SDK's <sys/cdefs.h> uses __i386__ to decide
# whether open/pread/fwrite need the legacy $UNIX2003 symbol-versioned
# aliases, which exist only for real 32-bit binaries -- forcing __i386__
# while actually linking the 64-bit libSystem produces undefined symbols
# for _open$UNIX2003 etc.  host_devread.c doesn't include anything that
# needs __i386__ anyway (no byte_order.h / simple_lock.h in its chain).
HOST_CFLAGS := $(COMMON_FLAGS)

BOOT2_OBJS := $(BUILD)/ufs_host_test.o \
        $(BUILD)/disk.o \
        $(BUILD)/sys.o \
        $(BUILD)/ufs_byteorder.o \
        $(BUILD)/cache.o

all: $(BUILD)/ufs_host_test $(BUILD)/efi_pci_acpi_test

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/host_devread.o: host_devread.c | $(BUILD)
	$(CC) $(HOST_CFLAGS) -c -o $@ $<

$(BUILD)/ufs_host_test.o: ufs_host_test.c | $(BUILD)
	$(CC) $(BOOT2_CFLAGS) -c -o $@ $<

$(BUILD)/disk.o: $(BOOT2)/libsaio/disk.c | $(BUILD)
	$(CC) $(BOOT2_CFLAGS) -c -o $@ $<

$(BUILD)/sys.o: $(BOOT2)/libsaio/sys.c | $(BUILD)
	$(CC) $(BOOT2_CFLAGS) -c -o $@ $<

$(BUILD)/ufs_byteorder.o: $(BOOT2)/libsaio/ufs_byteorder.c | $(BUILD)
	$(CC) $(BOOT2_CFLAGS) -c -o $@ $<

$(BUILD)/cache.o: $(BOOT2)/libsaio/cache.c | $(BUILD)
	$(CC) $(BOOT2_CFLAGS) -c -o $@ $<

$(BUILD)/ufs_host_test: $(BOOT2_OBJS) $(BUILD)/host_devread.o
	$(CC) $(BOOT2_CFLAGS) -o $@ $(BOOT2_OBJS) $(BUILD)/host_devread.o

# The ACPI parser is pure C with no boot-2 or EFI dependencies, so it is
# built with plain strict flags rather than COMMON_FLAGS' boot-2 include
# paths and host_bios_addr.h force-include.
ACPI_TEST_CFLAGS := -std=gnu89 -g -O0 -Wall -Werror -I..

$(BUILD)/efi_pci_acpi_test: efi_pci_acpi_test.c ../efi_pci_acpi.c \
		../efi_pci_acpi.h | $(BUILD)
	$(CC) $(ACPI_TEST_CFLAGS) -o $@ efi_pci_acpi_test.c ../efi_pci_acpi.c

test-acpi: $(BUILD)/efi_pci_acpi_test
	$(BUILD)/efi_pci_acpi_test

clean:
	rm -rf $(BUILD)

.PHONY: all clean test-acpi
