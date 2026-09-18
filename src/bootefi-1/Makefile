# Host-built IA32 UEFI loader.  Not part of the Rhapsody guest build, and
# deliberately not listed in src/Manifest.

# Homebrew ships lld as a SEPARATE formula from llvm, and the prefix differs
# between Apple Silicon (/opt/homebrew) and Intel (/usr/local).  Resolve both
# from PATH by default; override either variable to pin a specific install.
CC       ?= clang
LINK     ?= lld-link

BUILD    := BUILD
BOOT2    := ../boot-2/i386
KERNEL7  := ../kernel-7
CCTOOLS  := ../cctools-2/include

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
          -I$(KERNEL7) -I$(KERNEL7)/bsd -I$(CCTOOLS) -Ivendor_includes \
          -include bootefi_memory_override.h

# sys.c's own `#define BIG_ENDIAN_INTEL_FS __LITTLE_ENDIAN__` is always true
# on i386 (clang predefines __LITTLE_ENDIAN__=1 for this target) and
# byte-swaps every superblock/inode/directory read as though it might be
# PPC-written media.  golden.img's UFS payload is genuinely little-endian on
# disk (only its NeXT disk label is big-endian, swapped unconditionally and
# separately in disk.c/ufs_byteorder.c).  Overriding __LITTLE_ENDIAN__ to 0
# for sys.c's translation unit ALONE disables just that mistaken payload
# swap; Task 4's host test proved this exact override byte-perfect against
# the same image.  Do not apply it build-wide.
SYS_CFLAGS := $(CFLAGS) -D__LITTLE_ENDIAN__=0

LDFLAGS := /machine:x86 /subsystem:efi_application /nodefaultlib /entry:efi_main \
           /base:0x08000000 /fixed

BOOT2_SRCS := $(BOOT2)/libsaio/disk.c \
              $(BOOT2)/libsaio/ufs_byteorder.c \
              $(BOOT2)/libsaio/cache.c \
              $(BOOT2)/libsaio/load.c \
              $(BOOT2)/libsa/sprintf.c \
              $(BOOT2)/libsa/prf.c \
              $(BOOT2)/libsa/string1.c \
              $(BOOT2)/libsa/memcpy.c \
              $(BOOT2)/libsa/getsegbyname.c
# libsa/memset.c is NOT included: its unconditional `simple_char_set`
# inline asm (invalid "&c" input constraint under clang) and lvalue-cast
# assignments (`UNS(dst) += ...`) do not compile under any modern compiler
# flag short of editing the file, which src/boot-2 forbids. bzero() (which
# load.c's LC_SEGMENT handling and efi_main.c's load_kernel() both call)
# is instead implemented directly in efi_memory.c.

EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_memory.c $(BOOT2_SRCS)

EFI_OBJS := $(patsubst %.c,$(BUILD)/%.obj,$(notdir $(EFI_SRCS))) \
            $(BUILD)/sys.obj

VPATH := $(BOOT2)/libsaio:$(BOOT2)/libsa

all: $(BUILD)/BOOTIA32.EFI

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/sys.obj: $(BOOT2)/libsaio/sys.c | $(BUILD)
	$(CC) $(SYS_CFLAGS) -c -o $@ $<

$(BUILD)/%.obj: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/BOOTIA32.EFI: $(EFI_OBJS)
	$(LINK) $(LDFLAGS) /out:$@ $(EFI_OBJS)

spike: $(BUILD)/SPIKE.EFI

$(BUILD)/SPIKE.EFI: $(BUILD)/spike_memmap.obj
	$(LINK) $(LDFLAGS) /out:$@ $(BUILD)/spike_memmap.obj

clean:
	rm -rf $(BUILD)

.PHONY: all clean spike
