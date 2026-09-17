# IA32 UEFI boot loader for the i386 kernel

## Goal

Boot the RhapsodiOS i386 kernel from UEFI firmware instead of the legacy
`boot0`/`boot1`/`boot2` BIOS chain. The loader reads `/mach_kernel` from the
real UFS root, links the boot drivers with `sarld`, and hands control to the
kernel in the state the kernel already expects.

**Done when:** under QEMU with IA32 OVMF, the loader boots the kernel and
`vfs_mountroot()` succeeds. Userland startup beyond that point is out of scope.

## Scope

Target is QEMU plus IA32 OVMF only. Real UEFI hardware is not a goal; the
design may rely on QEMU's VGA device still decoding legacy VGA ports and
memory.

The loader is built as a **32-bit (IA32) UEFI application**. This is the
central decision and it removes two hard problems at once: no long-mode
downgrade is required, and `sarld` — 32-bit code the loader must call through
a function pointer — can be invoked directly, as `boot2` does today.

### Boundary on firmware services

The loader uses UEFI for disk access, memory discovery and console I/O. The
kernel receives none of it. It still gets a BIOS-shaped `KERNBOOTSTRUCT` and
still needs its own DriverKit driver for whatever holds the root filesystem.
UEFI does not widen what the kernel can mount, and there is no field in
`KERNBOOTSTRUCT` through which a GOP framebuffer could reach the kernel's VGA
console.

## Constraints from the existing tree

These are the facts the design has to satisfy. Each is source-anchored.

- **Handoff is legacy 32-bit.** `startprog()` sets `ds`/`es` to selector
  `0x20`, pushes selector `0x28` and the entry offset, and executes `lret`
  (`src/boot-2/i386/libsaio/asm.s` `_startprog`). The kernel documents that it
  arrives in protected mode with paging turned off
  (`src/kernel-7/machdep/i386/start.s` `_start`).
- **The kernel takes no register inputs.** `_start` calls `gdt_init` and
  `idt_init` and far-jumps to its own GDT immediately. It needs only correct
  processor mode and a valid stack.
- **The bootstruct lives at a fixed physical address.** `KERNSTRUCT_ADDR` is
  `0x11000` (`src/kernel-7/machdep/i386/kernBootStruct.h`).
- **Boot drivers are linked at boot time for their final address.**
  `linkDriver()` passes `daddr = kaddr + ksize` to `sarld` as both the
  destination and the address the image is relocated for
  (`src/boot-2/i386/libsaio/load.c` `linkDriver()`). Nothing can be staged at
  one address and moved to another afterwards.
- **The kernel consumes driver images as linked Mach-O headers.**
  `bootDriverInit()` reads `driverConfig[i].address`, zeroes `__bss`, and calls
  `objc_registerModule()` (`src/kernel-7/driverkit/i386/autoconf_i386.m`).
- **The disk interface is two functions.** `sys.c` reaches storage only through
  `devopen(name, io)` and `devread(io)` (`src/boot-2/i386/libsaio/disk.c`).
- **`sarld` has its own heap at a fixed address.** It statically links
  `libsa`, whose `zalloc.c` initializes its arena at `ZALLOC_ADDR` on first use
  (`src/boot-2/i386/libsa/zalloc.c`).

## Architecture

A new project, `src/bootefi-1/`, holds only EFI-specific code. Its Makefile
compiles the reused `libsaio` and `libsa` sources **in place** from
`../boot-2/`. There is no fork and no copies.

Those files are gnu89-era C that clang accepts with `-std=gnu89
-ffreestanding`. Any edit they turn out to need must remain buildable by the
old Rhapsody toolchain, so `src/boot-2` continues to build unchanged.

### Components

| Component | Origin | Responsibility |
|---|---|---|
| `efi_main.c` | new | Entry point, protocol handles, `boot:` prompt, orchestration |
| `efi_disk.c` | new | `ebiosread` over `EFI_BLOCK_IO_PROTOCOL`, plus the BIOS-layer symbols `disk.c` calls; `biosdev` to handle map |
| `efi_console.c` | new | `putchar`/`getc`/`printf` backend over `SIMPLE_TEXT_INPUT`/`OUTPUT` |
| `efi_memory.c` | new | EFI memory map to `convmem`/`extmem`; fixed-address reservation; `malloc`/`free` over `AllocatePool` |
| `efi.h` | new | Minimal hand-written UEFI headers |
| `handoff.c`, `handoff.S` | new | Post-`ExitBootServices` trampoline |
| `sys.c` | reused | UFS reader, path parsing, `open`/`read` |
| `ufs_byteorder.c` | reused | UFS byte-order handling |
| `load.c` | reused | Mach-O loading, `loadStandaloneLinker`, `linkDriver` |
| `stringTable.c` | reused | Config table parsing |
| `drivers.c` | reused | Driver discovery and selection |
| `table.c` | reused | The GDT, as pure data |

`libsa` contributes its freestanding helpers as well: `string1.c`, `string2.c`,
`memcpy.c`, `memset.c`, `sprintf.c`, `strtol.c`, `bsearch.c`, `qsort.c`,
`getsegbyname.c` and `mach.c`.

### Support routines the reused code expects

`load.c` and `drivers.c` call into the booter's diagnostic and progress
routines. `efi_console.c` supplies them: `printf`, `error`, `verbose`,
`message`, `localPrintf`, `spinActivityIndicator` and
`clearActivityIndicator`. The activity-indicator pair are no-ops in text mode.

### Deliberately excluded

`graphics.c`, `browser.c`, `bitmaps.c`, `localize.c`, `vbe.c`, `bios.s`,
`sizememory.c`, `boot0`, `boot1`. Also excluded are `libsa`'s `zalloc.c`,
because the loader's allocator is `AllocatePool`-backed, and `prf.c`, because
`efi_console.c` replaces it. `sarld` retains its own statically linked copy of
`zalloc.c`, which is why `ZALLOC_ADDR` still has to be reserved. The loader
runs in text mode only:
`graphicsMode` is `TEXT_MODE` and `boot_video` is zeroed. The kernel's console
reprograms the VGA hardware itself (`src/kernel-7/bsd/dev/i386/BasicConsole.c`
`BasicAllocateConsole()`), so it needs nothing from the loader there.

### The disk seam

`efi_disk.c` supplies `ebiosread` as a `BLOCK_IO->ReadBlocks` call and keeps
everything above it, `Biosread` included.

### Filesystem byte order

`sys.c` defines `BIG_ENDIAN_INTEL_FS` as `__LITTLE_ENDIAN__`, which is always true
on i386, and that gates the superblock, inode and directory-block swaps. It must be
**off** for this target, so `sys.c`'s translation unit alone is compiled with
`-D__LITTLE_ENDIAN__=0`.

This is not a bug introduced here. The source is the Darwin 0.3 drop, which was
PPC-oriented, and Apple's UFS was big-endian on every architecture. Authentic
Rhapsody DR2 Intel media, from the NeXT lineage, is little-endian: the original
guest disk's superblock magic is stored as `54 19 01 00`, little-endian `0x011954`.
The two eras of the codebase disagree, and our target is the older one.

The flag is scoped to `sys.c` rather than applied build-wide, because other headers
in that translation unit may also consult `__LITTLE_ENDIAN__` for struct layout. `read_label`'s MBR and Rhapsody disklabel walk, the UFS
superblock and inode logic in `sys.c`, and `hd(0,a)/mach_kernel` path parsing
all come across untouched.

## Memory placement

Because `sarld` relocates each driver for the address it will run at, every
image must sit at its final physical address before linking begins. The
loader's **first** action, before any other allocation, is
`AllocatePages(AllocateAddress)` over three ranges:

| Range | Size | Holds |
|---|---|---|
| `0x011000`–`0x0A0000` | 596K | `KERNBOOTSTRUCT`, `disk.c`'s sector cache, `sarld` |
| `0x100000`–`0x700000` | 6M | Kernel, linked drivers, `sarld` scratch heap, `libsa` arena |

**These two ranges are measured, not assumed.** The phase 0 spike ran under IA32 OVMF
and both were granted with `EFI_SUCCESS`. Getting there required two corrections to the
original four-range plan, both driven by what the firmware actually did.

**Page 0 is withheld.** OVMF reserves physical page 0 for null-pointer detection even
though its memory map reports the page as conventional. Probing at page granularity
showed page 0 refused while `0x1000` and `0x2000` were granted individually — so page 0
alone is the obstacle. `disk.c`'s sector cache `intbuf` sits at `BIOS_ADDR` (`0xC00`),
inside it. Rather than fight the firmware or fork `disk.c`, the loader redefines
`BIOS_ADDR` to `0x20000` through an `-include` prologue
(`src/bootefi-1/bootefi_memory_override.h`) that includes `memory.h` and then
`#undef`/`#define`s it. It stays a compile-time constant, so `disk.c`'s
`static char * const intbuf` initializer still compiles, and `src/boot-2` needs no edit.
`0x20000` is `EISA_CONFIG_ADDR`, which is safe here only because the loader excludes
`boot.c` — boot2's sole consumer of that region. If `boot.c` is ever added to this
build, the address must move.

**The loader's own image blocked the kernel range.** Firmware first loaded the EFI
application at `0x400000`, inside `0x100000`–`0x700000`, which is why that range was
refused. A per-megabyte probe confirmed nothing else obstructed it: every other
megabyte was granted. Since firmware chooses the load address, the loader is linked
with `/base:0x08000000 /fixed`. A PE image with no relocation table must be loaded at
its `ImageBase` or not at all, which forces firmware out of the way. `0x08000000` is
128MB, chosen against the harness's `-m 256`; that dependency is real and a smaller VM
would need a different base.

The second range runs to `0x700000` rather than `0x600000` because `sarld`'s statically
linked `libsa` allocator initializes its arena at `ZALLOC_ADDR`.

The loader's own `malloc`/`free` are backed by `AllocatePool`/`FreePool`, not
by `boot2`'s `ZALLOC_ADDR` heap. Nothing is allocated after
`ExitBootServices`.

## Handoff sequence

Being an IA32 application, the loader is already in flat 32-bit protected mode,
so there is no mode downgrade. After `ExitBootServices`:

1. `SetWatchdogTimer(0, ...)`, then `ExitBootServices(imageHandle, mapKey)`
2. `cli`
3. Clear `CR0.PG` if set. UEFI permits identity-mapped paging on IA32; the
   kernel requires paging off.
4. `lgdt` a copy of `Gdt` from `table.c`, used verbatim. Selector `0x20` is
   flat data and `0x28` is flat code, which is what `startprog` assumes.
5. Load `ds`, `es`, `fs`, `gs`, `ss` with `0x20`; set `esp` to `STACK_ADDR`
   (`0xFFF0`)
6. `push 0x28`, `push entry`, `lret`

The GDT and the trampoline live inside the loader image, allocated as
`EfiLoaderCode`, which nothing overwrites.

## Bootstruct synthesis

The loader reproduces `getKernBootStruct()`
(`src/boot-2/i386/libsaio/bootstruct.c`) with EFI-derived values where the BIOS
sources are gone.

| Field | Source |
|---|---|
| `convmem`, `extmem` | Walked from the EFI memory map. Conventional memory is capped at 640K; extended memory is contiguous KB above 1MB. |
| `magicCookie` | `KERNBOOTMAGIC` |
| `configEnd` | `config`, as in the BIOS path |
| `first_addr0` | `0`, matching the BIOS path when no EISA config is present |
| `kernDev` | Synthesized with `boot2`'s encoding so `setconf()` matches its generic `hd`/`sd` prefixes |
| `rootdev` | From the boot string, e.g. `rootdev=hd0a` |
| `diskInfo[4]` | Zeroed. This is BIOS CHS geometry with no EFI equivalent. |
| `numIDEs` | Count of EFI block devices mapped as `hd`. It **cannot** be zero: `sys.c`'s device parser rejects every `hd(...)` open when `numIDEs == 0`, which would break the loader's own file access before the kernel sees the field. |
| `graphicsMode` | `TEXT_MODE` |
| `boot_video`, `pciInfo`, `eisaSlotInfo`, `eisaConfigFunctions`, `apm_config` | Zeroed |
| `kaddr`, `ksize`, `rld_entry`, `driverConfig`, `numBootDrivers` | Filled by the reused `load.c` and `drivers.c` |

## Build

No EDK2 and no gnu-efi. `efi.h` is hand-written, roughly 300 lines covering the
system table, boot services, `SIMPLE_TEXT_INPUT`/`OUTPUT`, `BLOCK_IO`,
`LOADED_IMAGE` and the memory types. IA32 UEFI uses cdecl, so no
calling-convention attributes are needed.

```
clang -target i386-unknown-windows -ffreestanding -std=gnu89 \
      -fno-stack-protector -c ...
lld-link /machine:x86 /subsystem:efi_application /entry:efi_main ...
```

This requires Homebrew LLVM for `lld-link`; Xcode's clang does not ship it.
IA32 OVMF (`OVMF32_CODE.fd`) is not commonly packaged as a prebuilt binary and
may need an `OvmfPkgIa32` build from edk2. Both are explicit setup tasks.

## Disk image

A new `vm/build-uefi-image.sh`, separate from `rhap_image.py` and
`ufs_build.py`, produces a hybrid **MBR** disk:

- Partition 1: EFI System (type `0xEF`), FAT32, holding `/EFI/BOOT/BOOTIA32.EFI`
  (`mformat -F`; FAT32 is what the UEFI spec expects on a fixed disk). The ESP
  defaults to **64MB**: a 16MB FAT32 volume has too few clusters to be valid, and
  EDK2's FAT driver silently declines to mount it — it prints nothing and simply
  never binds, and BDS then reports that it cannot boot.
- Partition 2: the existing Rhapsody partition, unchanged

MBR rather than GPT specifically so `read_label`'s fdisk-table walk keeps
working. UEFI supports MBR EFI System Partitions.

`vm/run-q35-uefi.sh` mirrors `run-q35-ahci.sh`: serial logging, QMP key
injection for the `boot:` prompt, and per-run temporary image copies. It passes
`-cpu Nehalem`, without which this OVMF DEBUG build asserts before BDS runs.

Note on qemu: Homebrew's formula does not build on the development host, because
it compiles every target and the ARM board files fail under clang 15. An
i386-only source build (`--target-list=i386-softmmu`) sidesteps that entirely.

## Testing

**Host unit test for the UFS reader.** Compile `sys.c`, `ufs_byteorder.c` and a
POSIX file-backed `devread` into a host binary that extracts `/mach_kernel`
from a disk image, and assert the result matches `vm/ufs_extract.py`'s output.
This exercises the largest reused component with no QEMU in the loop and is the
first test to write.

**Python tests** for `build-uefi-image.sh`, in `vm/tests`, following the
existing `test_ufs_build.py` style.

**QEMU integration:** assert root-mount evidence in the serial log.

## Phases

| # | Work | Verify |
|---|---|---|
| 0 | Spike: EFI app dumps the memory map and attempts the reservations | **DONE.** Both ranges granted, after moving `BIOS_ADDR` off page 0 and linking at a fixed high base |
| 1 | Toolchain, `efi.h`, console, image script | `BOOTIA32.EFI` prints under OVMF; image tests pass |
| 2 | `efi_disk.c`; reuse `sys.c` and `read_label` | Host test extracts `/mach_kernel`; loader prints its Mach-O header |
| 3 | Kernel load and bootstruct synthesis | Field-by-field dump matches a BIOS-boot reference capture |
| 4 | `ExitBootServices` and trampoline, no drivers | Kernel verbose output appears on serial |
| 5 | `sarld`, `drivers.c`, `linkDriver` | AHCI and EIDE link; `vfs_mountroot()` succeeds |

Phase 0 was throwaway by design, and it earned its keep: it found both the
withheld page 0 and the loader's own image sitting in the kernel range, either
of which would have been extremely expensive to diagnose later.

## Risks

1. ~~**Firmware refuses the fixed reservations.**~~ **RESOLVED by phase 0.** Both
   ranges are granted once `BIOS_ADDR` moves off page 0 and the image is linked
   at a fixed high base. The staged-placer fallback is no longer needed. The
   residual risk is narrower: the `/fixed` base `0x08000000` assumes the VM has
   256MB, and `intbuf` at `0x20000` assumes `boot.c` stays out of the build.
2. **IA32 OVMF availability.** May require building `OvmfPkgIa32` from edk2.
3. **VGA console after EFI graphics initialization.** The kernel reprograms the
   VGA registers itself, which should recover the hardware, but this is
   unverified. Serial output is the mitigation, and the existing scripts
   already log it.
4. **`sarld` assumes more of `boot2`'s environment** than the reserved ranges
   cover — `libsa`'s error path in particular. This bites only when a driver
   fails to link.
5. **Zeroed `diskInfo`** may matter to `setconf()`. Cheap to test in phase 3.
   `numIDEs` is separately constrained by the loader's own device parser and is
   set from the EFI block-device count, not zeroed.
6. **1999 C through modern clang.** `-std=gnu89` should carry it; implicit-int
   and K&R prototypes are the likely friction.
