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
          -I. -I$(BOOT2)/libsaio -I$(BOOT2)/libsa

LDFLAGS := /machine:x86 /subsystem:efi_application /nodefaultlib /entry:efi_main

EFI_OBJS := $(BUILD)/efi_main.obj

all: $(BUILD)/BOOTIA32.EFI

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.obj: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/BOOTIA32.EFI: $(EFI_OBJS)
	$(LINK) $(LDFLAGS) /out:$@ $(EFI_OBJS)

clean:
	rm -rf $(BUILD)

.PHONY: all clean
