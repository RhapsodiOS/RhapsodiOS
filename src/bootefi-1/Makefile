# Host-built IA32 UEFI loader.  Not part of the Rhapsody guest build, and
# deliberately not listed in src/Manifest.

# Homebrew ships lld as a SEPARATE formula from llvm, and the prefix differs
# between Apple Silicon (/opt/homebrew) and Intel (/usr/local).  Resolve both
# from PATH by default; override either variable to pin a specific install.
# GNU make predefines CC=cc (origin "default"), which ?= would leave in place;
# this host has no cc.  An explicit CC=... on the command line or in the
# environment still wins.
ifeq ($(origin CC),default)
CC := clang
endif
LINK     ?= lld-link

# Boot string passed to the kernel; override to change kernel flags (e.g.
# append -s for single-user) without editing efi_memory.c's default.
BOOTEFI_BOOT_STRING ?= "rootdev=hd0a -v"

BUILD    := BUILD
BOOT2    := ../boot-2/i386
KERNEL7  := ../kernel-7
CCTOOLS  := ../cctools-2/include

# vendor_includes/architecture, vendor_includes/driverkit and
# vendor_includes/objc/objc.h are symlinks.  A checkout without symlink
# support (Windows with core.symlinks=false) turns them into small text
# files naming their targets, so copy the real directories/file under
# BUILD/ and search there too.  A real symlink makes the wildcard match and
# none of this applies (VENDOR_STAGE_INCLUDE stays empty, CFLAGS unchanged).
# VENDOR_STAGE_INCLUDE is placed in CFLAGS immediately before -Ivendor_includes
# and nowhere earlier: it must be searched before vendor_includes/objc/objc.h,
# which "exists" as a real file at that path -- just with the wrong
# (placeholder) content -- and would otherwise shadow the staged copy; but it
# must not outrank -I$(CCTOOLS) or -I$(KERNEL7), which ship their own copies
# of some of the same headers (architecture/i386/frame.h, fpu.h;
# driverkit/i386/PCMCIA.h) that a real Mac checkout (real symlinks) actually
# uses instead of vendor_includes'.
VENDOR_STAGE := $(BUILD)/vendor_includes
VENDOR_STAGE_INCLUDE :=
ifeq ($(wildcard vendor_includes/architecture/.),)
VENDOR_STAGE_INCLUDE := -I$(VENDOR_STAGE)
STAGED_VENDOR := $(VENDOR_STAGE)/architecture $(VENDOR_STAGE)/driverkit \
                 $(VENDOR_STAGE)/objc/objc.h
endif

# vendor_includes/architecture is a symlink to ../architecture-1, so
# <architecture/byte_order.h> resolves without editing anything under
# src/boot-2 or renaming src/architecture-1.  -I$(KERNEL7) and
# -I$(KERNEL7)/bsd resolve disk.c/sys.c's <bsd/...>, <ufs/...> and
# <machine/...> includes the same way the assembled Rhapsody SDK once did
# (this checkout has only the raw project trees, not that installed tree).
CFLAGS := -target i386-unknown-windows -std=gnu89 -ffreestanding \
          -fno-stack-protector -fshort-wchar -Wall -Os \
          -fno-ms-extensions \
          -Wno-implicit-int -Wno-implicit-function-declaration \
          -D__ARCHITECTURE__=\"i386\" -D_KERNEL -DDONT_USE_ASM \
          -I. -I$(BOOT2)/libsaio -I$(BOOT2)/libsa -I$(BOOT2)/util \
          -I$(KERNEL7) -I$(KERNEL7)/bsd -I$(KERNEL7)/bsd/include \
          -I$(CCTOOLS) $(VENDOR_STAGE_INCLUDE) -Ivendor_includes \
          -include bootefi_memory_override.h \
          -DBOOTEFI_BOOT_STRING='$(BOOTEFI_BOOT_STRING)' \
          -Wno-error=incompatible-function-pointer-types \
          -Wno-error=int-conversion -Wno-error=incompatible-pointer-types

LDFLAGS := /machine:x86 /subsystem:efi_application /nodefaultlib /entry:efi_main \
           /base:0x08000000 /fixed /safeseh:no

BOOT2_SRCS := $(BOOT2)/libsaio/disk.c \
              $(BOOT2)/libsaio/ufs_byteorder.c \
              $(BOOT2)/libsaio/cache.c \
              $(BOOT2)/libsaio/load.c \
              $(BOOT2)/libsa/sprintf.c \
              $(BOOT2)/libsa/prf.c \
              $(BOOT2)/libsa/string1.c \
              $(BOOT2)/libsa/memcpy.c \
              $(BOOT2)/libsa/getsegbyname.c \
              $(BOOT2)/libsaio/table.c \
              $(BOOT2)/libsaio/drivers.c \
              $(BOOT2)/libsaio/stringTable.c \
              $(BOOT2)/libsaio/choose.c \
              $(BOOT2)/libsaio/localize.c \
              $(BOOT2)/libsa/bsearch.c \
              $(BOOT2)/libsa/qsort.c \
              $(BOOT2)/libsa/strtol.c \
              $(BOOT2)/libsaio/sys.c
# libsa/memset.c is NOT included: its unconditional `simple_char_set`
# inline asm (invalid "&c" input constraint under clang) and lvalue-cast
# assignments (`UNS(dst) += ...`) do not compile under any modern compiler
# flag short of editing the file, which src/boot-2 forbids. bzero() (which
# load.c's LC_SEGMENT handling and efi_main.c's load_kernel() both call)
# is instead implemented directly in efi_memory.c.

EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_disk_select.c \
            efi_bootargs.c efi_memory.c efi_vga.c efi_pci.c handoff.c \
            $(BOOT2_SRCS)

EFI_OBJS := $(patsubst %.c,$(BUILD)/%.obj,$(notdir $(EFI_SRCS))) \
            $(BUILD)/handoff_tramp.obj

VPATH := $(BOOT2)/libsaio:$(BOOT2)/libsa

all: $(BUILD)/BOOTIA32.EFI

$(BUILD):
	mkdir -p $(BUILD)

$(VENDOR_STAGE)/architecture: | $(BUILD)
	mkdir -p $(VENDOR_STAGE)
	cp -R ../architecture-1 $@

$(VENDOR_STAGE)/driverkit: | $(BUILD)
	mkdir -p $(VENDOR_STAGE)
	cp -R ../driverkit-3/driverkit $@

$(VENDOR_STAGE)/objc/objc.h: | $(BUILD)
	mkdir -p $(VENDOR_STAGE)/objc
	cp ../objc-1/objc.h $@

$(BUILD)/%.obj: %.c | $(BUILD) $(STAGED_VENDOR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/handoff_tramp.obj: handoff.S | $(BUILD) $(STAGED_VENDOR)
	$(CC) $(CFLAGS) -c -o $@ handoff.S

$(BUILD)/BOOTIA32.EFI: $(EFI_OBJS)
	$(LINK) $(LDFLAGS) /out:$@ $(EFI_OBJS)

clean:
	rm -rf $(BUILD)

.PHONY: all clean
