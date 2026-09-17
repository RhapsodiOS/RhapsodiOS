# IA32 UEFI Boot Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot the RhapsodiOS i386 kernel from IA32 UEFI firmware under QEMU, reading `/mach_kernel` from the real UFS root and linking boot drivers with `sarld`, until `vfs_mountroot()` succeeds.

**Architecture:** A 32-bit (IA32) UEFI application in a new host-built project, `src/bootefi-1/`. Being IA32 means no long-mode downgrade and `sarld` can be called directly. The loader reuses `boot2`'s UFS reader, Mach-O loader, config parser and driver logic verbatim from `src/boot-2/`, replacing only the BIOS-shaped backends (disk, console, memory sizing) with EFI ones. Handoff reproduces `startprog()`: flat GDT, paging off, `lret` to selector `0x28`.

**Tech Stack:** C (gnu89), Homebrew LLVM (`clang` targeting `i386-unknown-windows`, `lld-link`), IA32 OVMF, QEMU (`qemu-system-i386`), Python 3 `unittest` for host tooling tests, `mtools` for FAT image construction.

**Spec:** `docs/superpowers/specs/2026-09-17-uefi-bootloader-design.md`

## Global Constraints

- Target is QEMU plus IA32 OVMF only. Real UEFI hardware is not a goal.
- `src/boot-2/` must keep building with the old Rhapsody toolchain. Any edit to a reused file must stay valid gnu89 C accepted by the 1999 compiler. Prefer zero edits.
- Reused sources are compiled **in place** from `../boot-2/`. Never copy them into `src/bootefi-1/`.
- `src/bootefi-1` is host-built with clang and `lld-link`. Do **not** add it to `src/Manifest`; that file lists projects built on the Rhapsody guest.
- Reserved physical ranges, exactly: `0x000000`–`0x003000`, `0x011000`–`0x020000`,
  `0x030000`–`0x0A0000`, `0x100000`–`0x700000`. The first covers `disk.c`'s sector
  cache `intbuf`, pinned at `BIOS_ADDR` (`0xC00`); the spec's table omits it because
  the spec did not yet account for compiling `disk.c` unchanged.
- Handoff selectors, exactly: data `0x20`, code `0x28`, stack `esp = 0xFFF0`.
- `numIDEs` in `KERNBOOTSTRUCT` must be non-zero, or `sys.c` rejects every `hd(...)` open.
- Boot testing uses temporary disk image copies, never the source image (CLAUDE.md §6).
- Commit messages start with a subsystem prefix (`bootefi: `, `vm: `, `docs: `), one to two lines, no metadata (CLAUDE.md §5).

## File Structure

| File | Responsibility |
|---|---|
| `vm/build_uefi_image.py` | Build a hybrid MBR disk: FAT16 ESP + the Rhapsody partition |
| `vm/test_build_uefi_image.py` | Tests for the above |
| `vm/run-q35-uefi.sh` | Boot the hybrid image under QEMU with IA32 OVMF |
| `src/bootefi-1/Makefile` | Host build of `BOOTIA32.EFI` and the spike |
| `src/bootefi-1/efi.h` | Minimal hand-written UEFI type and protocol declarations |
| `src/bootefi-1/efi_console.c` | `printf`/`error`/`verbose`/`message`/`getc` over EFI text protocols |
| `src/bootefi-1/efi_memory.c` | Fixed-address reservation, `convmem`/`extmem`, `malloc`/`free` |
| `src/bootefi-1/efi_disk.c` | `Biosread`/`devopen`/`devread` over `EFI_BLOCK_IO_PROTOCOL` |
| `src/bootefi-1/efi_main.c` | Entry point, boot prompt, orchestration |
| `src/bootefi-1/handoff.c` | Bootstruct finalization and the call into the trampoline |
| `src/bootefi-1/handoff.S` | `ExitBootServices` aftermath: paging off, GDT, `lret` |
| `src/bootefi-1/spike_memmap.c` | Phase 0 go/no-go probe (kept as a diagnostic target) |
| `src/bootefi-1/tests/Makefile` | Host build of the UFS reader test |
| `src/bootefi-1/tests/host_devread.c` | POSIX file-backed `ebiosread` and BIOS stubs for the host test |
| `src/bootefi-1/tests/ufs_host_test.c` | Extracts a file from a disk image via the reused reader |
| `src/bootefi-1/tests/test_ufs_host.py` | Compares that output against `rhap_image.py` |

---

### Task 1: Hybrid MBR image builder

Builds the disk the loader will boot from. Pure host work, fully testable, and a
prerequisite for every OVMF test that follows.

**Files:**
- Create: `vm/build_uefi_image.py`
- Create: `vm/test_build_uefi_image.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `build_uefi_image.build(rhapsody_image, efi_app, out_path, esp_mb=16)` returning `None`, raising `RuntimeError` on failure. Also a CLI: `python3 vm/build_uefi_image.py RHAPSODY_IMAGE EFI_APP OUT_PATH`.

**Background.** The output disk uses an **MBR** partition table, not GPT, so that
`read_label()` in `src/boot-2/i386/libsaio/disk.c` keeps finding the Rhapsody
partition by scanning for `systid == FDISK_NEXTNAME` (`0xA7`). Partition 1 is an
EFI System Partition (`systid 0xEF`, FAT16) holding `/EFI/BOOT/BOOTIA32.EFI`.
Partition 2 is the byte-for-byte copy of the existing Rhapsody image. UEFI
supports MBR ESPs, so OVMF will find and launch the app.

MBR partition entries are 16 bytes at offset 446, in this order: boot flag (1),
CHS start (3), system id (1), CHS end (3), LBA start (4, little endian), sector
count (4, little endian). CHS fields are irrelevant to UEFI and to `read_label`,
which uses `relsect` (the LBA start); fill them with `0xFE 0xFF 0xFF`, the
conventional "out of CHS range" marker. The signature `0x55AA` goes at offset
510.

FAT16 formatting uses `mtools` (`mformat`, `mmd`, `mcopy`). If those binaries are
absent, raise `RuntimeError` with an actionable message rather than producing a
broken image.

- [ ] **Step 1: Write the failing tests**

Create `vm/test_build_uefi_image.py`:

```python
import os
import shutil
import struct
import subprocess
import tempfile
import unittest

import build_uefi_image

HERE = os.path.dirname(os.path.abspath(__file__))

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF


def _have_mtools():
    return all(shutil.which(t) for t in ("mformat", "mmd", "mcopy"))


def _part(mbr, n):
    """Unpack MBR partition entry n as (systid, lba_start, nsectors)."""
    off = MBR_PART_OFFSET + n * 16
    entry = mbr[off:off + 16]
    systid = entry[4]
    lba, count = struct.unpack("<II", entry[8:16])
    return systid, lba, count


class TestBuildUefiImage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        # A stand-in Rhapsody partition: 4 MB of recognisable bytes.
        self.rhapsody = os.path.join(self.tmp, "rhapsody.img")
        with open(self.rhapsody, "wb") as f:
            f.write(b"RHAP" * (4 * 1024 * 1024 // 4))
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(b"MZ" + b"\0" * 1022)
        self.out = os.path.join(self.tmp, "hybrid.img")

    @unittest.skipUnless(_have_mtools(), "mtools not installed")
    def test_mbr_has_esp_and_rhapsody_partitions(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=16)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(mbr[510:512], b"\x55\xaa")
        self.assertEqual(_part(mbr, 0)[0], EFI_SYSTEM)
        self.assertEqual(_part(mbr, 1)[0], FDISK_NEXTNAME)

    @unittest.skipUnless(_have_mtools(), "mtools not installed")
    def test_rhapsody_partition_is_copied_verbatim_at_its_lba(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=16)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
            _, lba, count = _part(mbr, 1)
            f.seek(lba * SECTOR)
            head = f.read(16)
        self.assertEqual(head, b"RHAP" * 4)
        self.assertEqual(count, 4 * 1024 * 1024 // SECTOR)

    @unittest.skipUnless(_have_mtools(), "mtools not installed")
    def test_esp_contains_the_efi_app_at_the_removable_media_path(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=16)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        _, lba, _ = _part(mbr, 0)
        listing = subprocess.check_output(
            ["mdir", "-i", "%s@@%d" % (self.out, lba * SECTOR), "::/EFI/BOOT"],
            stderr=subprocess.STDOUT).decode()
        self.assertIn("BOOTIA32", listing)

    def test_missing_rhapsody_image_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(os.path.join(self.tmp, "nope.img"),
                                   self.efi, self.out, esp_mb=16)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests and verify they fail**

```bash
cd vm && python3 -m unittest test_build_uefi_image -v
```

Expected: `ModuleNotFoundError: No module named 'build_uefi_image'`.

- [ ] **Step 3: Write the implementation**

Create `vm/build_uefi_image.py`:

```python
"""Build a hybrid MBR disk: a FAT16 EFI System Partition holding the UEFI
loader, followed by an existing Rhapsody partition copied verbatim.

MBR rather than GPT, so read_label() in boot-2's disk.c keeps finding the
Rhapsody partition by its 0xA7 system id.
"""

import os
import shutil
import struct
import subprocess
import sys

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
ESP_LBA = 2048  # 1 MB in, the conventional alignment
CHS_OUT_OF_RANGE = b"\xfe\xff\xff"

MTOOLS = ("mformat", "mmd", "mcopy")


def _require_mtools():
    missing = [t for t in MTOOLS if shutil.which(t) is None]
    if missing:
        raise RuntimeError(
            "missing mtools binaries: %s (install mtools, e.g. "
            "'brew install mtools' or 'apt-get install mtools')"
            % ", ".join(missing))


def _part_entry(systid, lba_start, nsectors):
    return (b"\x00" + CHS_OUT_OF_RANGE + bytes([systid]) + CHS_OUT_OF_RANGE
            + struct.pack("<II", lba_start, nsectors))


def _run(argv):
    proc = subprocess.run(argv, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        raise RuntimeError("%s failed: %s"
                           % (argv[0], proc.stdout.decode(errors="replace")))


def build(rhapsody_image, efi_app, out_path, esp_mb=16):
    """Write a hybrid MBR disk to out_path."""
    for path in (rhapsody_image, efi_app):
        if not os.path.exists(path):
            raise RuntimeError("no such file: %s" % path)
    _require_mtools()

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    rhapsody_bytes = os.path.getsize(rhapsody_image)
    if rhapsody_bytes % SECTOR:
        raise RuntimeError("%s is not a whole number of %d-byte sectors"
                           % (rhapsody_image, SECTOR))
    rhapsody_sectors = rhapsody_bytes // SECTOR
    rhapsody_lba = ESP_LBA + esp_sectors
    total_sectors = rhapsody_lba + rhapsody_sectors

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        entries = (_part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors)
                   + _part_entry(FDISK_NEXTNAME, rhapsody_lba,
                                 rhapsody_sectors))
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(rhapsody_lba * SECTOR)
        with open(rhapsody_image, "rb") as src:
            shutil.copyfileobj(src, out, length=1024 * 1024)

    at = "%s@@%d" % (out_path, ESP_LBA * SECTOR)
    _run(["mformat", "-i", at, "-F", "-v", "RHAPEFI", "::"])
    _run(["mmd", "-i", at, "::/EFI"])
    _run(["mmd", "-i", at, "::/EFI/BOOT"])
    _run(["mcopy", "-i", at, efi_app, "::/EFI/BOOT/BOOTIA32.EFI"])


def main(argv):
    if len(argv) not in (4, 5):
        sys.stderr.write(
            "usage: %s RHAPSODY_IMAGE EFI_APP OUT_PATH [ESP_MB]\n" % argv[0])
        return 2
    esp_mb = int(argv[4]) if len(argv) == 5 else 16
    build(argv[1], argv[2], argv[3], esp_mb=esp_mb)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd vm && python3 -m unittest test_build_uefi_image -v
```

Expected: PASS (or skips, if `mtools` is absent — install it first; the skips
hide real failures).

- [ ] **Step 5: Commit**

```bash
git add vm/build_uefi_image.py vm/test_build_uefi_image.py
git commit -m "vm: build hybrid MBR images with an ESP for the UEFI loader"
```

---

### Task 2: Toolchain, minimal EFI headers, and a booting hello-world

Proves the whole build and test loop end to end before any loader logic exists.

**Files:**
- Create: `src/bootefi-1/Makefile`
- Create: `src/bootefi-1/efi.h`
- Create: `src/bootefi-1/efi_main.c`
- Create: `vm/run-q35-uefi.sh`

**Interfaces:**
- Consumes: `build_uefi_image.build(...)` from Task 1.
- Produces: `src/bootefi-1/BUILD/BOOTIA32.EFI`; `efi.h` declaring `EFI_STATUS`, `EFI_HANDLE`, `EFI_SYSTEM_TABLE`, `EFI_BOOT_SERVICES`, `EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL`, `EFI_SIMPLE_TEXT_INPUT_PROTOCOL`, `EFI_BLOCK_IO_PROTOCOL`, `EFI_MEMORY_DESCRIPTOR`; and the globals `EFI_SYSTEM_TABLE *gST`, `EFI_BOOT_SERVICES *gBS`, `EFI_HANDLE gImageHandle`.

**Setup prerequisites.** Both are one-time and must be done before Step 1.

1. `brew install llvm qemu mtools`. Xcode's clang does not ship `lld-link`;
   Homebrew LLVM installs it at `/opt/homebrew/opt/llvm/bin/lld-link`.
2. Obtain IA32 OVMF. It is rarely prebuilt. Either extract `OVMF32_CODE.fd`
   and `OVMF32_VARS.fd` from a Linux `edk2-ovmf-ia32` package, or build it:
   ```bash
   git clone --depth 1 https://github.com/tianocore/edk2
   cd edk2 && git submodule update --init --depth 1
   make -C BaseTools
   . edksetup.sh
   build -a IA32 -t CLANGDWARF -p OvmfPkg/OvmfPkgIa32.dsc
   ```
   Place the results at `vm/firmware/OVMF32_CODE.fd` and
   `vm/firmware/OVMF32_VARS.fd`. `vm/firmware/` is gitignored build output;
   do not commit the firmware.

- [ ] **Step 1: Write the minimal EFI headers**

Create `src/bootefi-1/efi.h`. IA32 UEFI uses cdecl, so no calling-convention
attributes are needed. Only the members actually used are declared; unused
slots are `void *` placeholders so the structure offsets stay correct.

```c
/* Minimal IA32 UEFI declarations.  Only what the loader touches. */
#ifndef _BOOTEFI_EFI_H_
#define _BOOTEFI_EFI_H_

typedef unsigned char       UINT8;
typedef unsigned short      UINT16;
typedef unsigned int        UINT32;
typedef unsigned long long  UINT64;
typedef int                 INT32;
typedef UINT32              UINTN;      /* IA32: pointer-sized */
typedef UINT16              CHAR16;
typedef UINTN               EFI_STATUS;
typedef void *              EFI_HANDLE;
typedef UINT64              EFI_PHYSICAL_ADDRESS;
typedef UINT64              EFI_VIRTUAL_ADDRESS;
typedef UINT8               BOOLEAN;

#define EFI_SUCCESS             0
#define EFI_ERROR(s)            (((INT32)(s)) < 0 || (s) != EFI_SUCCESS)
#define EFI_BUFFER_TOO_SMALL    ((EFI_STATUS)0x80000005)

typedef struct { UINT32 d1; UINT16 d2, d3; UINT8 d4[8]; } EFI_GUID;

#define EFI_BLOCK_IO_PROTOCOL_GUID \
  {0x964e5b21,0x6459,0x11d2,{0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b}}

/* Memory types and allocation */
typedef enum { AllocateAnyPages, AllocateMaxAddress, AllocateAddress }
        EFI_ALLOCATE_TYPE;
typedef enum {
    EfiReservedMemoryType, EfiLoaderCode, EfiLoaderData,
    EfiBootServicesCode, EfiBootServicesData, EfiRuntimeServicesCode,
    EfiRuntimeServicesData, EfiConventionalMemory, EfiUnusableMemory,
    EfiACPIReclaimMemory, EfiACPIMemoryNVS, EfiMemoryMappedIO,
    EfiMemoryMappedIOPortSpace, EfiPalCode, EfiPersistentMemory,
    EfiMaxMemoryType
} EFI_MEMORY_TYPE;

typedef struct {
    UINT32                  Type;
    UINT32                  Pad;
    EFI_PHYSICAL_ADDRESS    PhysicalStart;
    EFI_VIRTUAL_ADDRESS     VirtualStart;
    UINT64                  NumberOfPages;
    UINT64                  Attribute;
} EFI_MEMORY_DESCRIPTOR;

/* Text protocols */
typedef struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL
        EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
    void       *Reset;
    EFI_STATUS (*OutputString)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *, CHAR16 *);
    void       *TestString;
    void       *QueryMode;
    void       *SetMode;
    void       *SetAttribute;
    EFI_STATUS (*ClearScreen)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *);
    void       *SetCursorPosition;
    void       *EnableCursor;
    void       *Mode;
};

typedef struct { UINT16 ScanCode; CHAR16 UnicodeChar; } EFI_INPUT_KEY;
typedef struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL
        EFI_SIMPLE_TEXT_INPUT_PROTOCOL;
struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL {
    void       *Reset;
    EFI_STATUS (*ReadKeyStroke)(EFI_SIMPLE_TEXT_INPUT_PROTOCOL *,
                                EFI_INPUT_KEY *);
    void       *WaitForKey;
};

/* Block I/O */
typedef struct {
    UINT32   MediaId;
    BOOLEAN  RemovableMedia;
    BOOLEAN  MediaPresent;
    BOOLEAN  LogicalPartition;
    BOOLEAN  ReadOnly;
    BOOLEAN  WriteCaching;
    UINT32   BlockSize;
    UINT32   IoAlign;
    UINT64   LastBlock;
} EFI_BLOCK_IO_MEDIA;

typedef struct _EFI_BLOCK_IO_PROTOCOL EFI_BLOCK_IO_PROTOCOL;
struct _EFI_BLOCK_IO_PROTOCOL {
    UINT64              Revision;
    EFI_BLOCK_IO_MEDIA *Media;
    void               *Reset;
    EFI_STATUS        (*ReadBlocks)(EFI_BLOCK_IO_PROTOCOL *, UINT32 MediaId,
                                    UINT64 Lba, UINTN BufferSize,
                                    void *Buffer);
    void               *WriteBlocks;
    void               *FlushBlocks;
};

/* Boot services.  Unused slots are placeholders that keep the offsets right. */
typedef struct {
    char        Hdr[24];
    void       *RaiseTPL;
    void       *RestoreTPL;
    EFI_STATUS (*AllocatePages)(EFI_ALLOCATE_TYPE, EFI_MEMORY_TYPE,
                                UINTN Pages, EFI_PHYSICAL_ADDRESS *);
    EFI_STATUS (*FreePages)(EFI_PHYSICAL_ADDRESS, UINTN Pages);
    EFI_STATUS (*GetMemoryMap)(UINTN *MapSize, EFI_MEMORY_DESCRIPTOR *Map,
                               UINTN *MapKey, UINTN *DescriptorSize,
                               UINT32 *DescriptorVersion);
    EFI_STATUS (*AllocatePool)(EFI_MEMORY_TYPE, UINTN Size, void **Buffer);
    EFI_STATUS (*FreePool)(void *Buffer);
    void       *CreateEvent;
    void       *SetTimer;
    EFI_STATUS (*WaitForEvent)(UINTN, void **, UINTN *);
    void       *SignalEvent;
    void       *CloseEvent;
    void       *CheckEvent;
    void       *InstallProtocolInterface;
    void       *ReinstallProtocolInterface;
    void       *UninstallProtocolInterface;
    EFI_STATUS (*HandleProtocol)(EFI_HANDLE, EFI_GUID *, void **);
    void       *Reserved;
    void       *RegisterProtocolNotify;
    EFI_STATUS (*LocateHandle)(UINT32 SearchType, EFI_GUID *, void *,
                               UINTN *BufferSize, EFI_HANDLE *);
    void       *LocateDevicePath;
    void       *InstallConfigurationTable;
    void       *LoadImage;
    void       *StartImage;
    void       *Exit;
    void       *UnloadImage;
    EFI_STATUS (*ExitBootServices)(EFI_HANDLE, UINTN MapKey);
    void       *GetNextMonotonicCount;
    EFI_STATUS (*Stall)(UINTN Microseconds);
    EFI_STATUS (*SetWatchdogTimer)(UINTN, UINT64, UINTN, CHAR16 *);
} EFI_BOOT_SERVICES;

#define ByProtocol 2

typedef struct {
    char                             Hdr[24];
    CHAR16                          *FirmwareVendor;
    UINT32                           FirmwareRevision;
    EFI_HANDLE                       ConsoleInHandle;
    EFI_SIMPLE_TEXT_INPUT_PROTOCOL  *ConIn;
    EFI_HANDLE                       ConsoleOutHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOut;
    EFI_HANDLE                       StandardErrorHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *StdErr;
    void                            *RuntimeServices;
    EFI_BOOT_SERVICES               *BootServices;
} EFI_SYSTEM_TABLE;

extern EFI_SYSTEM_TABLE  *gST;
extern EFI_BOOT_SERVICES *gBS;
extern EFI_HANDLE         gImageHandle;

#endif /* _BOOTEFI_EFI_H_ */
```

- [ ] **Step 2: Write the hello-world entry point**

Create `src/bootefi-1/efi_main.c`:

```c
#include "efi.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    gImageHandle = image;
    gST = systab;
    gBS = systab->BootServices;

    gST->ConOut->ClearScreen(gST->ConOut);
    gST->ConOut->OutputString(gST->ConOut,
        (CHAR16 *)L"RhapsodiOS UEFI loader\r\n");

    for (;;)
        ;
    return EFI_SUCCESS;
}
```

- [ ] **Step 3: Write the Makefile**

Create `src/bootefi-1/Makefile`. This project is host-built and is deliberately
absent from `src/Manifest`.

```make
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
```

- [ ] **Step 4: Build and verify the PE image**

```bash
make -C src/bootefi-1
```

Expected: `src/bootefi-1/BUILD/BOOTIA32.EFI` exists. Confirm it is a 32-bit EFI
application:

```bash
xxd -s 0 -l 2 src/bootefi-1/BUILD/BOOTIA32.EFI
```

Expected: `4d5a` (`MZ`).

- [ ] **Step 5: Write the QEMU runner**

Create `vm/run-q35-uefi.sh`, matching the structure of `run-q35-ahci.sh` —
`#!/bin/sh`, `set -eu`, the `script_dir` resolution, work copies in `vm/work`,
serial to `vm/logs`.

```sh
#!/bin/sh
# Boot a hybrid UEFI image under QEMU with IA32 OVMF.  The source image is
# only copied; every writable disk lives in vm/work.  COM1 is recorded in
# vm/logs/uefi-serial.log.

set -eu

script_path=$0
case "$script_path" in
    */*) script_dir_part=${script_path%/*} ;;
    *) script_dir_part=. ;;
esac
script_dir=`CDPATH= cd "$script_dir_part" && pwd -P`
repo_root=`CDPATH= cd "$script_dir/.." && pwd -P`
work_root=$repo_root/vm/work
logs_dir=$repo_root/vm/logs
firmware_dir=${UEFI_FIRMWARE_DIR:-$repo_root/vm/firmware}
serial_log=$logs_dir/uefi-serial.log
qemu=${UEFI_QEMU:-qemu-system-i386}
code_fd=$firmware_dir/OVMF32_CODE.fd
vars_fd=$firmware_dir/OVMF32_VARS.fd

die()
{
    echo "run-q35-uefi: $*" >&2
    exit 1
}

usage()
{
    echo "usage: $0 SOURCE_HYBRID_IMAGE vm/work/IMAGE" >&2
    exit 2
}

[ $# -eq 2 ] || usage
src_image=$1
dst_image=$2

[ -f "$src_image" ] || die "no such image: $src_image"
[ -f "$code_fd" ] || die "missing firmware: $code_fd"
[ -f "$vars_fd" ] || die "missing firmware: $vars_fd"

case "$dst_image" in
    "$work_root"/*) ;;
    *) die "destination must be under $work_root" ;;
esac

mkdir -p "$work_root" "$logs_dir"
cp "$src_image" "$dst_image"
vars_copy=$work_root/OVMF32_VARS.fd
cp "$vars_fd" "$vars_copy"

exec "$qemu" \
    -machine q35 \
    -m 256 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$code_fd" \
    -drive if=pflash,format=raw,unit=1,format=raw,file="$vars_copy" \
    -drive id=disk0,file="$dst_image",format=raw,if=none \
    -device ich9-ahci,id=ahci \
    -device ide-hd,drive=disk0,bus=ahci.0 \
    -serial "file:$serial_log" \
    -display none \
    -vga std
```

Then `chmod +x vm/run-q35-uefi.sh`.

- [ ] **Step 6: Boot it and verify the banner**

```bash
python3 vm/build_uefi_image.py vm/work/rhapsody.img src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/hybrid.img
```

(Substitute your existing Rhapsody root image for the first argument.) Then:

```bash
sh vm/run-q35-uefi.sh vm/work/hybrid.img vm/work/hybrid-run.img
```

Expected: the script runs with `-display none`, so watch `vm/logs/uefi-serial.log`
instead of a display — stock OVMF's console splitter includes the serial port
in ConOut, so `RhapsodiOS UEFI loader` and the spin loop should appear there.
Kill QEMU with Ctrl-C. If the serial log shows nothing, first check whether the
firmware's ConOut actually includes serial. If OVMF drops to its shell instead,
the ESP or the `/EFI/BOOT/BOOTIA32.EFI` path is wrong — re-check Task 1's `mdir`
test.

- [ ] **Step 7: Commit**

```bash
git add src/bootefi-1/Makefile src/bootefi-1/efi.h src/bootefi-1/efi_main.c vm/run-q35-uefi.sh
git commit -m "bootefi: IA32 UEFI application skeleton and QEMU runner"
```

---

### Task 3: Memory reservation spike (phase 0 go/no-go)

The one experiment that can invalidate the design. Keep it separate and keep it
cheap.

**Files:**
- Create: `src/bootefi-1/spike_memmap.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: `efi.h` and the globals from Task 2.
- Produces: a `spike` make target building `BUILD/SPIKE.EFI`. No source that later tasks depend on.

- [ ] **Step 1: Write the spike**

Create `src/bootefi-1/spike_memmap.c`. It prints the EFI memory map, then tries
each reservation. `printf` does not exist yet, so it writes CHAR16 directly.

```c
/* Phase 0 go/no-go: can the firmware give us boot2's fixed low addresses?
 * Build with `make spike`; this is a diagnostic, not part of the loader. */
#include "efi.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

static void puts16(CHAR16 *s)
{
    gST->ConOut->OutputString(gST->ConOut, s);
}

static void puthex(UINT64 v)
{
    CHAR16 buf[19];
    int i;

    buf[0] = L'0'; buf[1] = L'x';
    for (i = 0; i < 16; i++) {
        int nib = (int)((v >> ((15 - i) * 4)) & 0xF);
        buf[2 + i] = (CHAR16)(nib < 10 ? L'0' + nib : L'a' + nib - 10);
    }
    buf[18] = 0;
    puts16(buf);
}

struct range { UINT64 start; UINT64 end; CHAR16 *name; };

static struct range ranges[] = {
    { 0x000000, 0x003000, L"intbuf (BIOS_ADDR)" },
    { 0x011000, 0x020000, L"bootstruct" },
    { 0x030000, 0x0A0000, L"sarld" },
    { 0x100000, 0x700000, L"kernel+drivers+heaps" },
    { 0, 0, 0 }
};

static void dump_map(void)
{
    UINTN size = 0, key, dsize;
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    EFI_STATUS st;
    UINTN off;

    gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
    size += 4 * dsize;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&map)))
        return;
    st = gBS->GetMemoryMap(&size, map, &key, &dsize, &dver);
    if (EFI_ERROR(st)) {
        puts16(L"GetMemoryMap failed\r\n");
        return;
    }
    for (off = 0; off < size; off += dsize) {
        EFI_MEMORY_DESCRIPTOR *d =
            (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
        if (d->PhysicalStart >= 0x800000)
            continue;               /* only the region we care about */
        puts16(L"  type "); puthex(d->Type);
        puts16(L" start "); puthex(d->PhysicalStart);
        puts16(L" pages "); puthex(d->NumberOfPages);
        puts16(L"\r\n");
    }
}

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    struct range *r;

    gImageHandle = image;
    gST = systab;
    gBS = systab->BootServices;

    gST->ConOut->ClearScreen(gST->ConOut);
    puts16(L"Memory map below 8M:\r\n");
    dump_map();

    puts16(L"Reservations:\r\n");
    for (r = ranges; r->name; r++) {
        EFI_PHYSICAL_ADDRESS addr = r->start;
        UINTN pages = (UINTN)((r->end - r->start) / 4096);
        EFI_STATUS st = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                           pages, &addr);
        puts16(L"  "); puts16(r->name); puts16(L" ");
        puts16(EFI_ERROR(st) ? L"REFUSED " : L"granted ");
        puthex(st);
        puts16(L"\r\n");
    }

    for (;;)
        ;
    return EFI_SUCCESS;
}
```

- [ ] **Step 2: Add the spike target to the Makefile**

In `src/bootefi-1/Makefile`, after the `$(BUILD)/BOOTIA32.EFI` rule, add:

```make
spike: $(BUILD)/SPIKE.EFI

$(BUILD)/SPIKE.EFI: $(BUILD)/spike_memmap.obj
	$(LINK) $(LDFLAGS) /out:$@ $(BUILD)/spike_memmap.obj
```

and add `spike` to the `.PHONY` line:

```make
.PHONY: all clean spike
```

- [ ] **Step 3: Build and run the spike**

```bash
make -C src/bootefi-1 spike
python3 vm/build_uefi_image.py vm/work/rhapsody.img src/bootefi-1/BUILD/SPIKE.EFI vm/work/spike.img
sh vm/run-q35-uefi.sh vm/work/spike.img vm/work/spike-run.img
```

Expected: four lines reading `granted 0x0000000000000000`.

The `intbuf` range starts at physical 0, which firmware often reserves for
null-pointer detection. If **only** that range is refused, the contingency is
narrow and does not block the project: drop `static` from `read_label()` in
`src/boot-2/i386/libsaio/disk.c`, declare it in `saio_static.h`, and have the
backends supply their own `Biosread` and sector buffer instead of compiling
`disk.c` whole. That edit is valid 1999 C and keeps the old toolchain building.
Record which applies before starting Task 4, because Tasks 4 and 5 both depend
on the answer.

- [ ] **Step 4: Record the outcome**

If all four are granted, note it and continue to Task 4.

**If any range is REFUSED, stop and escalate.** Do not work around it in this
task. The spec's fallback — stage all files in memory before
`ExitBootServices`, then place and link afterwards — is a design change that
reorders Tasks 6 through 8, and it needs a design decision before any code is
written. Report which range was refused and which memory-map entry covers it.

- [ ] **Step 5: Commit**

```bash
git add src/bootefi-1/spike_memmap.c src/bootefi-1/Makefile
git commit -m "bootefi: add a spike that probes the fixed low-memory reservations"
```

---

### Task 4: Host test for the reused UFS reader

Compiles the largest reused component on the host and proves it reads real
Rhapsody filesystems, with no EFI and no QEMU in the loop. This also flushes out
gnu89 compile problems early, where they are cheap to diagnose.

**Files:**
- Create: `src/bootefi-1/tests/Makefile`
- Create: `src/bootefi-1/tests/host_devread.c`
- Create: `src/bootefi-1/tests/host_bios_addr.h`
- Create: `src/bootefi-1/tests/ufs_host_test.c`
- Create: `src/bootefi-1/tests/test_ufs_host.py`

**Interfaces:**
- Consumes: `src/boot-2/i386/libsaio/{sys.c,ufs_byteorder.c,disk.c}` and `src/boot-2/i386/libsa/` helpers.
- Produces: a host binary `src/bootefi-1/tests/BUILD/ufs_host_test` with the CLI `ufs_host_test IMAGE DEVSPEC PATH`, writing the file's bytes to stdout. Also establishes the backend contract Task 5's EFI version must satisfy: `int ebiosread(int biosdev, int secno, int nsecs)` reading into `disk.c`'s `intbuf`, plus `uses_ebios[]`, `biosread()`, `get_diskinfo()` and `turnOffFloppy()`.

**Background, revised.** `Biosread()` already has a flat-LBA path: when
`uses_ebios[biosdev - 0x80]` is set it calls `ebiosread(biosdev, secno, nsecs)`
to read `nsecs` sectors into the cache buffer `intbuf`
([disk.c:210](src/boot-2/i386/libsaio/disk.c:210)). That is exactly the shape a
non-BIOS backend wants. So `disk.c` compiles **unchanged** in both the host test
and the EFI app, and the backend supplies only the handful of symbols `disk.c`
expects from the BIOS layer:

| Symbol | Backend provides |
|---|---|
| `int ebiosread(int biosdev, int secno, int nsecs)` | The actual sector read into `intbuf` |
| `int biosread(int dev, int cyl, int head, int sec, int nsecs)` | Unreachable; return `-1` |
| `unsigned char uses_ebios[]` | All ones, forcing the LBA path |
| `long get_diskinfo(int biosdev)` | Non-zero fake geometry so `devopen()` proceeds |
| `void turnOffFloppy(void)` | No-op |

`intbuf` is `static char * const intbuf = (char *)ptov(BIOS_ADDR)` — physical
`0xC00`. On the host that address is not writable, so the host build defines
`BIOS_ADDR` to a normal buffer. Because `memory.h` defines it unconditionally,
the host `Makefile` passes `-include host_bios_addr.h`, which `#undef`s and
redefines it *after* `memory.h` is pulled in by the backend's own include order.
Confirm the definition actually took effect in Step 6; if it did not, fall back
to the `read_label` de-static edit recorded in Task 3.

- [ ] **Step 1: Write the host disk backend**

Create `src/bootefi-1/tests/host_devread.c`:

```c
/* POSIX file-backed replacement for the BIOS layer under boot2's disk.c.
 * disk.c itself is compiled unchanged; we supply only what it calls. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BPS 512

static int image_fd = -1;

/* disk.c indexes this by (biosdev - 0x80) to choose the LBA path. */
unsigned char uses_ebios[8] = {1, 1, 1, 1, 1, 1, 1, 1};

int host_open_image(const char *path)
{
    image_fd = open(path, O_RDONLY);
    return image_fd;
}

extern char *intbuf_storage;

/* Read nsecs sectors starting at secno into disk.c's cache buffer. */
int ebiosread(int biosdev, int secno, int nsecs)
{
    extern char *biosbuf;
    ssize_t want = (ssize_t)nsecs * BPS;
    ssize_t n = pread(image_fd, intbuf_storage, want, (off_t)secno * BPS);

    if (n < 0)
        return -1;
    if (n < want)                       /* short read past end: zero-fill */
        memset(intbuf_storage + n, 0, want - n);
    return 0;
}

/* The CHS path is unreachable because uses_ebios is always set. */
int biosread(int dev, int cyl, int head, int sec, int nsecs)
{
    return -1;
}

/* devopen() only checks this for non-zero; the geometry feeds the CHS path. */
long get_diskinfo(int biosdev)
{
    return 0x3F | (0x0F << 8);
}

void turnOffFloppy(void) { }
void diskActivityHook(void) { }
void spinActivityIndicator(void) { }
void clearActivityIndicator(void) { }

void sleep(int seconds) { }

void error(const char *fmt, ...) { }
void verbose(const char *fmt, ...) { }
```

- [ ] **Step 2: Point `intbuf` at real host memory**

Create `src/bootefi-1/tests/host_bios_addr.h`:

```c
/* disk.c pins its sector cache at physical BIOS_ADDR (0xC00), which the host
 * cannot write.  Redirect it at a real buffer.  memory.h defines BIOS_ADDR
 * unconditionally, so undef first. */
#ifndef _HOST_BIOS_ADDR_H_
#define _HOST_BIOS_ADDR_H_

extern char *intbuf_storage;

#include "memory.h"
#undef  BIOS_ADDR
#undef  ptov
#define BIOS_ADDR   0
#define ptov(p)     (intbuf_storage)

#endif
```

and define the buffer in `host_devread.c`, above the includes that pull in
`memory.h`:

```c
static char intbuf_backing[16 * 512];
char *intbuf_storage = intbuf_backing;
```

Size it to at least `BIOS_LEN` (`0x2400`, 9 KB) so `N_CACHE_SECS` reads fit.

- [ ] **Step 3: Write the test driver**

Create `src/bootefi-1/tests/ufs_host_test.c`:

```c
/* Extract one file from a Rhapsody disk image using boot2's own UFS reader.
 * usage: ufs_host_test IMAGE DEVSPEC PATH   e.g. ... hybrid.img 'hd(0,a)' /mach_kernel */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "saio.h"

extern int host_fd;

/* boot2's sys.c reads kernBootStruct for the default device and numIDEs. */
#include "kernBootStruct.h"
static KERNBOOTSTRUCT host_bootstruct;
KERNBOOTSTRUCT *kernBootStruct = &host_bootstruct;

int main(int argc, char **argv)
{
    char spec[256], buf[65536];
    int fd, n;

    if (argc != 4) {
        fprintf(stderr, "usage: %s IMAGE DEVSPEC PATH\n", argv[0]);
        return 2;
    }
    host_fd = open(argv[1], O_RDONLY);
    if (host_fd < 0) {
        perror(argv[1]);
        return 1;
    }
    /* hd() opens are rejected outright when numIDEs is zero (sys.c). */
    kernBootStruct->numIDEs = 1;

    snprintf(spec, sizeof(spec), "%s%s", argv[2], argv[3]);
    fd = open(spec, 0);
    if (fd < 0) {
        fprintf(stderr, "open(%s) failed\n", spec);
        return 1;
    }
    while ((n = read(fd, buf, sizeof(buf))) > 0)
        fwrite(buf, 1, n, stdout);
    close(fd);
    return 0;
}
```

Because `sys.c` defines `open`, `read` and `close`, the host build must not let
them collide with libc. Compile with `-Dopen=sa_open -Dread=sa_read
-Dclose=sa_close -Dlseek=sa_lseek` applied to **all** sources, and use the
`sa_` names in `ufs_host_test.c`'s calls to the reader while using the real
`open(2)` for the image via a separately compiled helper in
`host_devread.c` (`host_open_image(const char *path)`). Adjust the two call
sites accordingly:

```c
    host_open_image(argv[1]);   /* real open(2), inside host_devread.c */
    ...
    fd = sa_open(spec, 0);
    while ((n = sa_read(fd, buf, sizeof(buf))) > 0)
    ...
    sa_close(fd);
```

and add to `host_devread.c`:

```c
int host_open_image(const char *path)
{
    host_fd = open(path, O_RDONLY);
    return host_fd;
}
```

- [ ] **Step 4: Write the tests Makefile**

Create `src/bootefi-1/tests/Makefile`:

```make
BUILD := BUILD
BOOT2 := ../../boot-2/i386

CC     ?= clang
CFLAGS := -m32 -std=gnu89 -g -O0 -Wno-implicit-int \
          -Wno-implicit-function-declaration -Wno-return-type \
          -Dopen=sa_open -Dread=sa_read -Dclose=sa_close -Dlseek=sa_lseek \
          -include host_bios_addr.h \
          -I. -I$(BOOT2)/libsaio -I$(BOOT2)/libsa

SRCS := ufs_host_test.c host_devread.c \
        $(BOOT2)/libsaio/disk.c \
        $(BOOT2)/libsaio/sys.c \
        $(BOOT2)/libsaio/ufs_byteorder.c

all: $(BUILD)/ufs_host_test

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/ufs_host_test: $(SRCS) | $(BUILD)
	$(CC) $(CFLAGS) -o $@ $(SRCS)

clean:
	rm -rf $(BUILD)

.PHONY: all clean
```

- [ ] **Step 5: Write the failing Python test**

Create `src/bootefi-1/tests/test_ufs_host.py`:

```python
"""The reused boot2 UFS reader must extract the same bytes as rhap_image.py."""
import hashlib
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "vm"))

BINARY = os.path.join(HERE, "BUILD", "ufs_host_test")
IMAGE = os.environ.get("RHAPSODY_IMAGE",
                       os.path.join(REPO, "vm", "work", "rhapsody.img"))


def _ready():
    return os.path.exists(BINARY) and os.path.exists(IMAGE)


class TestHostUfsReader(unittest.TestCase):
    @unittest.skipUnless(_ready(), "build the binary and supply RHAPSODY_IMAGE")
    def test_mach_kernel_matches_rhap_image(self):
        import rhap_image

        with rhap_image.Image(IMAGE) as img:
            ino = img.resolve("/mach_kernel")
            self.assertIsNotNone(ino, "/mach_kernel missing from the image")
            expected = img.read_file(ino)

        got = subprocess.check_output(
            [BINARY, IMAGE, "hd(0,a)", "/mach_kernel"])

        self.assertEqual(hashlib.sha256(got).hexdigest(),
                         hashlib.sha256(expected).hexdigest())
        self.assertEqual(len(got), len(expected))

    @unittest.skipUnless(_ready(), "build the binary and supply RHAPSODY_IMAGE")
    def test_missing_file_is_an_error(self):
        proc = subprocess.run([BINARY, IMAGE, "hd(0,a)", "/no/such/file"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 6: Build and run until green**

```bash
make -C src/bootefi-1/tests
python3 -m unittest discover -s src/bootefi-1/tests -p 'test_*.py' -v
```

Expected: both tests PASS. Getting here will take iteration — the reused C is
from 1999 and the compile errors are the point of this task. Fix them in
`host_devread.c` and in compiler flags. Only edit `src/boot-2` if there is no
alternative, and re-verify the old build still works if you do.

- [ ] **Step 7: Commit**

```bash
git add src/bootefi-1/tests
git commit -m "bootefi: host test proving boot2's UFS reader extracts mach_kernel"
```

---

### Task 5: EFI console and disk backends

Wires the reused reader into the EFI application. At the end of this task the
loader reads the kernel off the real UFS root and reports its Mach-O header.

**Files:**
- Create: `src/bootefi-1/efi_console.c`
- Create: `src/bootefi-1/efi_disk.c`
- Create: `src/bootefi-1/efi_memory.c`
- Modify: `src/bootefi-1/efi_main.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: `efi.h` globals from Task 2; the `Biosread` contract from Task 4.
- Produces:
  - `void printf(const char *fmt, ...)`, `void error(const char *fmt, ...)`, `void verbose(const char *fmt, ...)`, `void message(char *str, int n)`, `void localPrintf(const char *fmt, ...)`, `int getc(void)`, `void putchar(int c)`, `void flushdev(void)`, `void spinActivityIndicator(void)`, `void clearActivityIndicator(void)`, `void sleep(int seconds)`
  - `int efi_disk_init(void)`, `int efi_disk_count(void)`, `int ebiosread(int biosdev, int secno, int nsecs)`; `devopen`, `devread`, `devflush` and `read_label` come from the unchanged `disk.c`
  - `void *malloc(int size)`, `void free(char *p)` (in `efi_memory.c`, added here)

**Background.** `biosdev` values arrive from `sys.c` as `0x80 + unit` for `hd`
and `sd`, and `0x00 + unit` for `fd` ([saio.h:113](src/boot-2/i386/libsaio/saio.h:113)).
The EFI backend enumerates whole-disk `EFI_BLOCK_IO_PROTOCOL` handles — those
with `Media->LogicalPartition == 0` — and maps `0x80 + n` to the nth. That count
is also what `numIDEs` must be set to, via `efi_disk_count()`.

As in Task 4, `disk.c` is compiled unchanged and this task supplies only the
BIOS-layer symbols it calls. Unlike the host build, no `BIOS_ADDR` redirection
is needed: `intbuf` at `0xC00` is real memory here, covered by the
`0x000000`–`0x003000` reservation.

- [ ] **Step 1: Write the console backend**

Create `src/bootefi-1/efi_console.c`. It provides a small `vprintf` over
`OutputString`, converting to CHAR16 and expanding `\n` to CRLF.

```c
#include <stdarg.h>
#include "efi.h"

extern int prf(const char *fmt, va_list ap, void (*putfn)(int), int *arg);

void putchar(int c)
{
    CHAR16 s[3];
    int i = 0;

    if (c == '\n')
        s[i++] = L'\r';
    s[i++] = (CHAR16)c;
    s[i] = 0;
    gST->ConOut->OutputString(gST->ConOut, s);
}

static void vprint(const char *fmt, va_list ap)
{
    char buf[512];
    char *p;

    vsprintf(buf, fmt, ap);         /* libsa/sprintf.c */
    for (p = buf; *p; p++)
        putchar(*p);
}

void printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
}

void localPrintf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
}

int errors;

void error(const char *fmt, ...)
{
    va_list ap;
    errors++;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
}

int gVerboseMode = 1;

void verbose(const char *fmt, ...)
{
    va_list ap;
    if (!gVerboseMode)
        return;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
}

void message(char *str, int n)
{
    printf("%s\n", str);
}

int getc(void)
{
    EFI_INPUT_KEY key;

    for (;;) {
        EFI_STATUS st = gST->ConIn->ReadKeyStroke(gST->ConIn, &key);
        if (!EFI_ERROR(st)) {
            if (key.UnicodeChar)
                return (int)key.UnicodeChar;
        }
        gBS->Stall(1000);
    }
}

void flushdev(void) { }
void spinActivityIndicator(void) { }
void clearActivityIndicator(void) { }
void diskActivityHook(void) { }

void sleep(int seconds)
{
    gBS->Stall((UINTN)seconds * 1000000);
}
```

If `libsa/sprintf.c` does not export `vsprintf` with this signature, check it
and adapt the call — do not invent one. `prf.c` is excluded from the build; only
`sprintf.c` is linked.

- [ ] **Step 2: Write the disk backend**

Same shape as Task 4's host backend: `disk.c` is compiled unchanged and this
file supplies the BIOS-layer symbols it calls. Nothing here reimplements
`devopen`, `devread` or `read_label` — those come from `disk.c` as-is.

Create `src/bootefi-1/efi_disk.c`:

```c
#include "efi.h"

#define BPS             512
#define MAX_DISKS       8
#define FIRST_BIOSDEV   0x80

static EFI_GUID gBlockIoGuid = EFI_BLOCK_IO_PROTOCOL_GUID;
static EFI_BLOCK_IO_PROTOCOL *disks[MAX_DISKS];
static int ndisks;

/* disk.c indexes this by (biosdev - 0x80) to choose the LBA path. */
unsigned char uses_ebios[MAX_DISKS] = {1, 1, 1, 1, 1, 1, 1, 1};

/* Enumerate whole-disk BLOCK_IO handles, skipping partition handles. */
int efi_disk_init(void)
{
    EFI_HANDLE *handles = 0;
    UINTN size = 0, i;
    EFI_STATUS st;

    st = gBS->LocateHandle(ByProtocol, &gBlockIoGuid, 0, &size, 0);
    if (st != EFI_BUFFER_TOO_SMALL)
        return 0;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&handles)))
        return 0;
    if (EFI_ERROR(gBS->LocateHandle(ByProtocol, &gBlockIoGuid, 0, &size,
                                    handles))) {
        gBS->FreePool(handles);
        return 0;
    }

    ndisks = 0;
    for (i = 0; i < size / sizeof(EFI_HANDLE) && ndisks < MAX_DISKS; i++) {
        EFI_BLOCK_IO_PROTOCOL *bio = 0;
        if (EFI_ERROR(gBS->HandleProtocol(handles[i], &gBlockIoGuid,
                                          (void **)&bio)))
            continue;
        if (!bio->Media->MediaPresent || bio->Media->LogicalPartition)
            continue;
        disks[ndisks++] = bio;
    }
    gBS->FreePool(handles);
    return ndisks;
}

int efi_disk_count(void) { return ndisks; }

/* disk.c's Biosread() calls this for every LBA read.  intbuf lives at
 * BIOS_ADDR (0xC00), inside the range reserved in efi_reserve_ranges(). */
int ebiosread(int biosdev, int secno, int nsecs)
{
    extern char *biosbuf;
    EFI_BLOCK_IO_PROTOCOL *bio;
    int idx = biosdev - FIRST_BIOSDEV;
    UINT64 lba;
    UINTN bytes = (UINTN)nsecs * BPS;

    if (idx < 0 || idx >= ndisks)
        return -1;
    bio = disks[idx];
    if (bio->Media->BlockSize != BPS)
        return -1;                      /* 4Kn media is out of scope */
    lba = (UINT64)secno;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId, lba, bytes,
                                  biosbuf)))
        return -1;
    return 0;
}

/* Unreachable: uses_ebios is always set. */
int biosread(int dev, int cyl, int head, int sec, int nsecs)
{
    return -1;
}

/* devopen() only checks this for non-zero. */
long get_diskinfo(int biosdev)
{
    return 0x3F | (0x0F << 8);
}

void turnOffFloppy(void) { }
```

`biosbuf` is `disk.c`'s own global, which `Biosread()` points at `intbuf`
before calling `ebiosread`. Reading into `biosbuf` therefore fills the cache the
rest of `disk.c` expects. Do not declare a second `biosbuf` here.

- [ ] **Step 3: Add `malloc`/`free` to a new `efi_memory.c`**

Create `src/bootefi-1/efi_memory.c`:

```c
#include "efi.h"

void *malloc(int size)
{
    void *p = 0;

    if (size <= 0)
        return 0;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, (UINTN)size, &p)))
        return 0;
    return p;
}

void free(char *p)
{
    if (p)
        gBS->FreePool(p);
}
```

- [ ] **Step 4: Open the kernel from `efi_main.c`**

Replace the body of `efi_main` in `src/bootefi-1/efi_main.c`:

```c
#include "efi.h"
#include <sys/types.h>
#include "saio.h"
#include "kernBootStruct.h"

EFI_SYSTEM_TABLE  *gST;
EFI_BOOT_SERVICES *gBS;
EFI_HANDLE         gImageHandle;

KERNBOOTSTRUCT *kernBootStruct = KERNSTRUCT_ADDR;

extern int efi_disk_init(void);
extern int efi_disk_count(void);

EFI_STATUS
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    int fd, n;
    unsigned char hdr[28];

    gImageHandle = image;
    gST = systab;
    gBS = systab->BootServices;
    gST->ConOut->ClearScreen(gST->ConOut);

    printf("RhapsodiOS UEFI loader\n");
    printf("block devices: %d\n", efi_disk_init());

    /* numIDEs must be non-zero or sys.c rejects every hd() open. */
    kernBootStruct->numIDEs = efi_disk_count();

    fd = open("hd(0,a)/mach_kernel", 0);
    if (fd < 0) {
        printf("open failed\n");
        for (;;) ;
    }
    n = read(fd, (char *)hdr, sizeof(hdr));
    printf("read %d bytes, magic %x %x %x %x\n", n,
           hdr[0], hdr[1], hdr[2], hdr[3]);
    close(fd);

    for (;;)
        ;
    return EFI_SUCCESS;
}
```

Note this writes through `kernBootStruct` at `0x11000`, which is only valid
once that page is reserved. Add the reservation before first use — move the
three `AllocatePages(AllocateAddress)` calls from the spike into
`efi_memory.c` as `int efi_reserve_ranges(void)` returning 0 on success, and
call it immediately after `gBS` is set:

```c
    if (efi_reserve_ranges() != 0) {
        printf("fixed-address reservation failed\n");
        for (;;) ;
    }
```

- [ ] **Step 5: Extend the Makefile**

In `src/bootefi-1/Makefile`, replace the `EFI_OBJS` line:

```make
BOOT2_SRCS := $(BOOT2)/libsaio/disk.c \
              $(BOOT2)/libsaio/sys.c \
              $(BOOT2)/libsaio/ufs_byteorder.c \
              $(BOOT2)/libsa/sprintf.c \
              $(BOOT2)/libsa/string1.c \
              $(BOOT2)/libsa/string2.c \
              $(BOOT2)/libsa/memcpy.c \
              $(BOOT2)/libsa/memset.c \
              $(BOOT2)/libsa/strtol.c

EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_memory.c \
            $(BOOT2_SRCS)

EFI_OBJS := $(patsubst %.c,$(BUILD)/%.obj,$(notdir $(EFI_SRCS)))

VPATH := $(BOOT2)/libsaio:$(BOOT2)/libsa
```

- [ ] **Step 6: Build, boot, and verify**

```bash
make -C src/bootefi-1
python3 vm/build_uefi_image.py vm/work/rhapsody.img src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/hybrid.img
sh vm/run-q35-uefi.sh vm/work/hybrid.img vm/work/hybrid-run.img
```

Expected on the QEMU display:

```
RhapsodiOS UEFI loader
block devices: 1
read 28 bytes, magic ce fa ed fe
```

`cefaedfe` is the Mach-O magic `MH_MAGIC` (`0xfeedface`) in little-endian byte
order. Anything else means the reader found the wrong bytes: check the
partition offset `read_label` computed before suspecting the UFS code, since
Task 4 already proved that path on the host.

- [ ] **Step 7: Commit**

```bash
git add src/bootefi-1
git commit -m "bootefi: read mach_kernel from UFS through EFI block I/O"
```

---

### Task 6: Kernel loading and bootstruct synthesis

**Files:**
- Modify: `src/bootefi-1/efi_memory.c`
- Modify: `src/bootefi-1/efi_main.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: everything from Task 5.
- Produces: `void efi_sizemem(int *convmem_kb, int *extmem_kb)`; `void efi_init_bootstruct(void)`; and a populated `KERNBOOTSTRUCT` at `0x11000` with `kaddr`, `ksize`, `bootString` and the loaded kernel's entry point in `kernelEntry`.

**Background.** `loadprog(int dev, int fd, struct mach_header *headOut,
entry_t *entry, char **addr, int *size)` is the reused Mach-O loader
([load.c:76](src/boot-2/i386/libsaio/load.c:76)). `execKernel()` in `boot.c`
shows the exact call and the surrounding bookkeeping; reproduce that sequence,
omitting the graphics, prompt and EISA branches. `removeLinkEditSegment(struct
mach_header *)` ([load.c:356](src/boot-2/i386/libsaio/load.c:356)) must be
called on the loaded header before handoff.

- [ ] **Step 1: Add memory sizing to `efi_memory.c`**

```c
/* KERNBOOTSTRUCT wants two scalars, not a map: conventional memory below
 * 640K and contiguous extended memory above 1M, both in KB. */
void efi_sizemem(int *convmem_kb, int *extmem_kb)
{
    UINTN size = 0, key, dsize;
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    UINTN off;
    UINT64 conv_top = 0;
    UINT64 ext_top = 0x100000;

    gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
    size += 4 * dsize;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&map))) {
        *convmem_kb = 640;
        *extmem_kb = 0;
        return;
    }
    if (EFI_ERROR(gBS->GetMemoryMap(&size, map, &key, &dsize, &dver))) {
        gBS->FreePool(map);
        *convmem_kb = 640;
        *extmem_kb = 0;
        return;
    }

    /* Two passes: conventional top below 640K, then grow the extended
     * region as long as usable descriptors remain contiguous. */
    for (off = 0; off < size; off += dsize) {
        EFI_MEMORY_DESCRIPTOR *d =
            (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
        UINT64 start = d->PhysicalStart;
        UINT64 end = start + d->NumberOfPages * 4096;
        if (!efi_usable(d->Type))
            continue;
        if (start < 0xA0000 && end > conv_top)
            conv_top = end > 0xA0000 ? 0xA0000 : end;
    }

    for (;;) {
        UINT64 grew = ext_top;
        for (off = 0; off < size; off += dsize) {
            EFI_MEMORY_DESCRIPTOR *d =
                (EFI_MEMORY_DESCRIPTOR *)((char *)map + off);
            UINT64 start = d->PhysicalStart;
            UINT64 end = start + d->NumberOfPages * 4096;
            if (!efi_usable(d->Type))
                continue;
            if (start <= grew && end > grew)
                grew = end;
        }
        if (grew == ext_top)
            break;
        ext_top = grew;
    }

    gBS->FreePool(map);
    *convmem_kb = (int)(conv_top / 1024);
    *extmem_kb = (int)((ext_top - 0x100000) / 1024);
}
```

Add the helper above it:

```c
/* Memory we reserved ourselves counts as usable: the kernel owns it next. */
static int efi_usable(UINT32 type)
{
    return type == EfiConventionalMemory
        || type == EfiBootServicesCode
        || type == EfiBootServicesData
        || type == EfiLoaderCode
        || type == EfiLoaderData;
}
```

- [ ] **Step 2: Add bootstruct initialization to `efi_memory.c`**

This mirrors `getKernBootStruct()` in
`src/boot-2/i386/libsaio/bootstruct.c`, with EFI sources where the BIOS ones
are gone.

```c
#include <sys/types.h>
#include "saio.h"
#include "kernBootStruct.h"

extern KERNBOOTSTRUCT *kernBootStruct;
extern int efi_disk_count(void);

void efi_init_bootstruct(void)
{
    int conv, ext;

    bzero((char *)kernBootStruct, sizeof(*kernBootStruct));

    efi_sizemem(&conv, &ext);
    kernBootStruct->convmem = conv;
    kernBootStruct->extmem = ext;

    /* Must be non-zero: sys.c rejects hd() opens when this is 0. */
    kernBootStruct->numIDEs = efi_disk_count();

    kernBootStruct->magicCookie = KERNBOOTMAGIC;
    kernBootStruct->configEnd = kernBootStruct->config;
    kernBootStruct->graphicsMode = TEXT_MODE;
    kernBootStruct->first_addr0 = 0;

    /* The kernel's setconf() reads rootdev from here, and -v turns on the
     * verbose output the QEMU checks in later tasks depend on.  kernDev is
     * NOT set here: sys.c's device parser writes it as a side effect of the
     * first successful open(), which happens in load_kernel(). */
    strncpy(kernBootStruct->bootString, "rootdev=hd0a -v",
            BOOT_STRING_LEN - 1);
    /* diskInfo, video, pciInfo, eisaSlotInfo and apm_config stay zeroed:
     * they are BIOS-derived and have no EFI equivalent. */
}
```

- [ ] **Step 3: Load the kernel in `efi_main.c`**

Replace the open/read/close probe from Task 5 with the real load, following
`execKernel()`:

```c
#include <mach-o/loader.h>
#include "load.h"

static entry_t kernelEntry;

static int load_kernel(const char *spec)
{
    static struct mach_header head;
    int fd, ret;

    fd = open((char *)spec, 0);
    if (fd < 0) {
        error("Can't find %s\n", spec);
        return -1;
    }
    strncpy(kernBootStruct->boot_file, spec,
            sizeof(kernBootStruct->boot_file) - 1);

    kernBootStruct->kaddr = kernBootStruct->ksize = 0;
    ret = loadprog(kernBootStruct->kernDev, fd, &head, &kernelEntry,
                   (char **)&kernBootStruct->kaddr, &kernBootStruct->ksize);
    close(fd);
    if (ret != 0) {
        error("loadprog failed: %d\n", ret);
        return -1;
    }

    /* boot2 zeroes the gap so sarld's driver BSS starts clean. */
    bzero((char *)(kernBootStruct->kaddr + kernBootStruct->ksize),
          RLD_MEM_ADDR - (kernBootStruct->kaddr + kernBootStruct->ksize));
    return 0;
}
```

and in `efi_main`, after `efi_disk_init()`:

```c
    efi_init_bootstruct();
    if (load_kernel("hd(0,a)/mach_kernel") != 0)
        for (;;) ;

    printf("kaddr %x ksize %x entry %x\n",
           kernBootStruct->kaddr, kernBootStruct->ksize,
           (unsigned int)kernelEntry);
    printf("convmem %d extmem %d numIDEs %d\n",
           kernBootStruct->convmem, kernBootStruct->extmem,
           kernBootStruct->numIDEs);
```

- [ ] **Step 4: Add `load.c` and `memory.h` to the build**

In `src/bootefi-1/Makefile`, add `$(BOOT2)/libsaio/load.c` and
`$(BOOT2)/libsa/getsegbyname.c` to `BOOT2_SRCS`. `load.c` needs the cctools
Mach-O headers, so extend `CFLAGS` with `-I../cctools-2/include`.

- [ ] **Step 5: Build, boot, and verify against a BIOS reference**

First capture a reference from the working BIOS path:

```bash
sh vm/run-q35-ahci.sh vm/work/rhapsody.img vm/work/ref.img
grep -iE 'kaddr|ksize|conv|ext' vm/logs/ahci-serial.log
```

Then run the UEFI path:

```bash
make -C src/bootefi-1 && \
python3 vm/build_uefi_image.py vm/work/rhapsody.img src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/hybrid.img && \
sh vm/run-q35-uefi.sh vm/work/hybrid.img vm/work/hybrid-run.img
```

Expected: `kaddr 100000`, a non-zero `ksize`, a non-zero `entry`, `convmem 640`,
`extmem` close to the QEMU `-m 256` figure minus 1 MB, and `numIDEs 1`.
`kaddr` must be exactly `0x100000`; anything else means the reservation or the
Mach-O `vmaddr` handling is wrong.

Also add a line printing `bootString` and `kernDev`, and confirm `bootString`
reads `rootdev=hd0a -v` and `kernDev` is non-zero — `kernDev` is written by
`sys.c`'s device parser during `load_kernel()`'s `open()`, so a zero value means
the open took an unexpected path.

- [ ] **Step 6: Commit**

```bash
git add src/bootefi-1
git commit -m "bootefi: load the kernel and synthesise KERNBOOTSTRUCT"
```

---

### Task 7: Handoff — ExitBootServices and the trampoline

At the end of this task the kernel runs. No boot drivers yet, so it will not
mount root; the deliverable is kernel output on the serial console.

**Files:**
- Create: `src/bootefi-1/handoff.S`
- Create: `src/bootefi-1/handoff.c`
- Modify: `src/bootefi-1/efi_main.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: `kernelEntry`, and a populated `KERNBOOTSTRUCT`, from Task 6.
- Produces: `void efi_handoff(unsigned int entry)` — never returns.

**Background.** The kernel takes no register inputs; `_start` calls `gdt_init`
and `idt_init` then far-jumps to its own GDT
([start.s:48](src/kernel-7/machdep/i386/start.s:48)). It needs protected mode
with paging off, a valid stack, and a GDT where `0x20` is flat data and `0x28`
is flat code — exactly `Gdt` in
[table.c](src/boot-2/i386/libsaio/table.c), which is pure data and reusable
verbatim.

- [ ] **Step 1: Write the trampoline**

Create `src/bootefi-1/handoff.S`:

```asm
/* Post-ExitBootServices handoff.  Reproduces boot2's startprog(): flat GDT,
 * paging off, lret to selector 0x28.  Never returns. */
        .text
        .globl  _efi_handoff
        .globl  efi_handoff
_efi_handoff:
efi_handoff:
        movl    4(%esp), %ecx           /* kernel entry */

        cli

        /* Paging off.  UEFI permits identity-mapped paging on IA32; the
         * kernel requires it disabled. */
        movl    %cr0, %eax
        andl    $0x7FFFFFFF, %eax
        movl    %eax, %cr0
        xorl    %eax, %eax
        movl    %eax, %cr3

        lgdt    gdt_desc

        movl    $0x20, %eax
        movw    %ax, %ds
        movw    %ax, %es
        movw    %ax, %fs
        movw    %ax, %gs
        movw    %ax, %ss
        movl    $0xFFF0, %esp

        pushl   $0x28
        pushl   %ecx
        lret

        .data
        .align  4
        .globl  gdt_desc
gdt_desc:
        .word   47                      /* NGDTENT * 8 - 1 */
        .long   0                       /* filled in by efi_handoff_prepare */
```

- [ ] **Step 2: Write the C side**

Create `src/bootefi-1/handoff.c`:

```c
#include "efi.h"

/* boot2's GDT, used verbatim: selector 0x20 is flat data, 0x28 flat code. */
extern struct seg_desc Gdt[];
extern unsigned short gdt_desc_limit;
extern void efi_handoff(unsigned int entry);

struct gdt_descriptor {
    unsigned short limit;
    unsigned long  base;
} __attribute__((packed));

extern struct gdt_descriptor gdt_desc;

void efi_exit_and_start(unsigned int entry)
{
    UINTN size = 0, key, dsize;
    UINT32 dver;
    EFI_MEMORY_DESCRIPTOR *map = 0;
    EFI_STATUS st;
    int tries;

    gdt_desc.base = (unsigned long)Gdt;

    gBS->SetWatchdogTimer(0, 0, 0, 0);

    /* GetMemoryMap can invalidate the key; retry a bounded number of times. */
    for (tries = 0; tries < 8; tries++) {
        size = 0;
        gBS->GetMemoryMap(&size, 0, &key, &dsize, &dver);
        size += 4 * dsize;
        if (map)
            gBS->FreePool(map);
        map = 0;
        if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&map)))
            break;
        if (EFI_ERROR(gBS->GetMemoryMap(&size, map, &key, &dsize, &dver)))
            continue;
        st = gBS->ExitBootServices(gImageHandle, key);
        if (!EFI_ERROR(st))
            efi_handoff(entry);     /* never returns */
    }

    /* Only reached if ExitBootServices never succeeded. */
    printf("ExitBootServices failed\n");
    for (;;)
        ;
}
```

- [ ] **Step 3: Call it from `efi_main.c`**

After the diagnostics printed in Task 6:

```c
    removeLinkEditSegment((struct mach_header *)kernBootStruct->kaddr);
    printf("Starting Rhapsody\n");
    efi_exit_and_start((unsigned int)kernelEntry);
    /* not reached */
```

- [ ] **Step 4: Add the new sources to the build**

In `src/bootefi-1/Makefile`, add `handoff.c` and `$(BOOT2)/libsaio/table.c` to
`EFI_SRCS`, add an assembly rule, and add `$(BUILD)/handoff.obj` to
`EFI_OBJS`:

```make
$(BUILD)/handoff.obj: handoff.S | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ handoff.S
```

- [ ] **Step 5: Build, boot, and verify kernel output**

The kernel's early console is VGA; the serial log is the reliable channel.
`bootString` was set to `rootdev=hd0a -v` in Task 6, so verbose kernel output
should appear on both.

```bash
make -C src/bootefi-1 && \
python3 vm/build_uefi_image.py vm/work/rhapsody.img src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/hybrid.img && \
sh vm/run-q35-uefi.sh vm/work/hybrid.img vm/work/hybrid-run.img
```

Expected: after `Starting Rhapsody`, kernel output appears on the QEMU display.
It will stop short of mounting root, since no boot drivers are loaded — a panic
or a wait at the root-device prompt is the **success** condition for this task,
because it proves the kernel is executing.

Expected failure mode if the handoff is wrong: an immediate triple fault, which
QEMU shows as a reboot loop. If that happens, check in order: `CR0.PG` actually
cleared, `gdt_desc.base` pointing at `Gdt`, and the limit being 47.

- [ ] **Step 6: Commit**

```bash
git add src/bootefi-1
git commit -m "bootefi: exit boot services and hand off to the kernel"
```

---

### Task 8: Boot drivers via sarld

The final task. Loads the standalone linker and links the driver set the way
`execKernel()` does, so the kernel can mount root.

**Files:**
- Modify: `src/bootefi-1/efi_main.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: everything from Task 7.
- Produces: `kernBootStruct->rld_entry`, `numBootDrivers` and `driverConfig[]` populated before handoff.

**Background.** `loadStandaloneLinker(char *linkerPath, sa_rld_t **rld_entry_p)`
is declared in
[saio_static.h:45](src/boot-2/i386/libsaio/saio_static.h:45). `boot2` defaults
the path to `/usr/standalone/i386/sarld`. `loadBootDrivers(BOOL askFirst, int
numberOfPrompts, int installMode)` and `loadOtherConfigs(int useDefaultConfig)`
come from `drivers.c`; the interactive branches are driven by config keys, so
calling `loadBootDrivers(0, 0, 0)` takes the non-prompting path.

`sarld` links each driver **for the address it will run at** — `daddr = kaddr +
ksize` ([load.c:463](src/boot-2/i386/libsaio/load.c:463)) — and its statically
linked `libsa` allocator initialises an arena at `ZALLOC_ADDR`
([zalloc.c:89](src/boot-2/i386/libsa/zalloc.c:89)). Both fall inside the
`0x100000`–`0x700000` reservation, which is why that range extends past
`0x600000`.

- [ ] **Step 1: Load the linker and the drivers**

In `efi_main.c`, between `load_kernel()` and `removeLinkEditSegment()`:

```c
    {
        char *linkerPath = newStringForKey("Linker");
        if (linkerPath == 0)
            linkerPath = "/usr/standalone/i386/sarld";
        if (loadStandaloneLinker(linkerPath,
                                 (sa_rld_t **)&kernBootStruct->rld_entry)
            == -1) {
            error("Couldn't load standalone linker; "
                  "unable to load boot drivers.\n");
        } else {
            loadOtherConfigs(0);
            loadBootDrivers(0, 0, 0);
            printf("boot drivers linked: %d\n",
                   kernBootStruct->numBootDrivers);
        }
    }
```

- [ ] **Step 2: Add the remaining reused sources**

In `src/bootefi-1/Makefile`, add to `BOOT2_SRCS`:

```make
              $(BOOT2)/libsaio/drivers.c \
              $(BOOT2)/libsaio/stringTable.c \
              $(BOOT2)/libsaio/table.c \
              $(BOOT2)/libsa/bsearch.c \
              $(BOOT2)/libsa/qsort.c \
              $(BOOT2)/libsa/mach.c
```

`drivers.c` calls prompting helpers (`askWhetherToLoadMoreDrivers`,
`pickDrivers`, `noDriversMessage`, `askAboutMissingDrivers`). They live in
`drivers.c` itself and route through `getBoolForKey`, so no new stubs should be
needed. If the link reports any missing symbol, add a non-interactive stub to
`efi_console.c` returning the "do not prompt" answer rather than editing
`drivers.c`.

- [ ] **Step 3: Stage the driver files on the test image**

The loader reads `sarld` and the drivers from the UFS root, so the Rhapsody
image needs them present. Build and stage with the existing script:

```bash
sh vm/build-i386-kernel-ahci.sh
```

Confirm the staged paths it prints exist inside the image before booting.

- [ ] **Step 4: Build, boot, and verify root mount**

```bash
make -C src/bootefi-1 && \
python3 vm/build_uefi_image.py vm/work/rhapsody.img src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/hybrid.img && \
sh vm/run-q35-uefi.sh vm/work/hybrid.img vm/work/hybrid-run.img
```

Expected: `boot drivers linked: 2` before handoff, then kernel output that
reaches the root mount. Confirm from the serial log:

```bash
grep -iE 'root|mount|AHCI|EIDE' vm/logs/uefi-serial.log
```

Expected: evidence that `vfs_mountroot()` succeeded and the kernel proceeded
past it — the same lines the BIOS path produces in `vm/logs/ahci-serial.log`.
Compare the two logs directly; they should diverge only in the loader banner.

**This is the done criterion for the project.**

- [ ] **Step 5: Commit**

```bash
git add src/bootefi-1
git commit -m "bootefi: link boot drivers with sarld and reach root mount"
```

- [ ] **Step 6: Document the result**

Add a short section to `docs/boot/boot-i386.md` recording the UEFI entry path
alongside the existing BIOS trace, in the same source-anchored style: the
loader's entry point, the reservation set, and the handoff selectors. Keep it to
the evidence levels that file already uses.

```bash
git add docs/boot/boot-i386.md
git commit -m "docs: record the UEFI loader entry path in the i386 boot trace"
```
