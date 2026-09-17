# Host-built IA32 UEFI loader.  Not part of the Rhapsody guest build, and
# deliberately not listed in src/Manifest.

# Homebrew ships lld as a SEPARATE formula from llvm, and the prefix differs
# between Apple Silicon (/opt/homebrew) and Intel (/usr/local).  Resolve both
# from PATH by default; override either variable to pin a specific install.
CC       ?= clang
LINK     ?= lld-link

BUILD    := BUILD
BOOT2    := ../boot-2/i386

CFLAGS := -target i386-unknown-windows -std=gnu89 -ffreestanding \
          -fno-stack-protector -fshort-wchar -Wall -Os \
          -I. -I$(BOOT2)/libsaio -I$(BOOT2)/libsa \
          -include bootefi_memory_override.h

LDFLAGS := /machine:x86 /subsystem:efi_application /nodefaultlib /entry:efi_main

# Spike-only: force the image to a high fixed base with no relocation table,
# so firmware must either load it there or refuse outright (used to get a
# clean answer on whether our own image collides with the kernel range).
# The VM has 256 MiB (0x10000000) of RAM total, so 0x10000000 itself is the
# first byte *past* populated RAM, not a usable base. The Task 3 spike found
# the allocator already using space near 0x0E2A5000-0x0E3A5000 (~227-228 MiB)
# by the time it ran, so pick something well clear of both that zone and the
# low ranges under test: 0x08000000 (128 MiB).
SPIKE_LDFLAGS := $(LDFLAGS) /base:0x08000000 /fixed

EFI_OBJS := $(BUILD)/efi_main.obj

all: $(BUILD)/BOOTIA32.EFI

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.obj: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/BOOTIA32.EFI: $(EFI_OBJS)
	$(LINK) $(LDFLAGS) /out:$@ $(EFI_OBJS)

spike: $(BUILD)/SPIKE.EFI

$(BUILD)/SPIKE.EFI: $(BUILD)/spike_memmap.obj
	$(LINK) $(SPIKE_LDFLAGS) /out:$@ $(BUILD)/spike_memmap.obj

clean:
	rm -rf $(BUILD)

.PHONY: all clean spike
