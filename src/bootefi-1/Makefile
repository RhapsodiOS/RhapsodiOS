# Host-built IA32 UEFI loader.  Not part of the Rhapsody guest build, and
# deliberately not listed in src/Manifest.

LLVM_BIN ?= /opt/homebrew/opt/llvm/bin
CC       := $(LLVM_BIN)/clang
LINK     := $(LLVM_BIN)/lld-link

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
