# PCI enumeration in the UEFI loader

## Goal

Make `"Auto Detect IDs"` work under the UEFI loader, so PCI drivers receive a
`"Location"` key and can reach their device's config space. Today the loader
stubs out PCI enumeration entirely, which silently breaks every PCI driver in
the tree. The AHCI driver is where this first became visible.

**Done when:** booting the UEFI loader under QEMU q35 with the AHCI driver
installed, `AHCIController` probes successfully and the kernel mounts root from
the SATA disk instead of failing with `errno = 6`.

## The defect

`AHCIController` never probes under the UEFI loader. The failure chain, in
order:

1. **The loader never enumerates PCI.** `src/bootefi-1/efi_main.c:47` defines
   `void *PCISlotInfo;` as a plain stub, with a comment stating the loader "has
   no EISA/PCI auto-detect". `src/bootefi-1/efi_memory.c:350` likewise leaves
   `kernBootStruct.pciInfo` zeroed.
2. **No driver matches its PCI IDs.** `src/boot-2/i386/libsaio/drivers.c:392`
   walks `for (slot = PCISlotInfo; slot && slot->pid; slot++)`. With
   `PCISlotInfo` NULL the loop body never runs, so `testIDs()` is never called
   and `detected` stays `NO`.
3. **The driver is still loaded, but with no location.** The `!detected`
   fallback at `drivers.c:409` calls `_set_dinfo(..., locationTag = NULL)`, so
   the `"Location" = "Dev:%d Func:%d Bus:%d"` key (`drivers.c:353`) is absent
   from the config table handed to the kernel.
4. **The device description is invalid.**
   `src/driverkit-3/libDriver/pci/IOPCIDeviceDescription.m:78` sets
   `private->valid` only if `[thePCIBus configAddress:...]` succeeds, which
   requires that `"Location"` key. It fails, so `valid = NO`.
5. **Every config-space read fails.** `getPCIdevice:function:bus:` returns
   `IO_R_NO_DEVICE` (`IOPCIDeviceDescription.m:108`), so every
   `getPCIConfigData:` in `IOPCIDirectDevice.m` fails.
6. **The driver gives up without a word.**
   `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m:116`
   is the first such read. It fails, and the method does `[self free]; return
   nil;` with no log. All nineteen bail-out paths in
   `initFromDeviceDescription` (lines 93–296) are silent this way.

### Two observations in the boot log that corroborate this

Neither is a separate defect in the probe path:

- **`probe:` did run.** `AHCIController.m:78` calls
  `ata_hd_devsw_init([AHCIDisk class], ...)`, which messages `AHCIDisk` and
  fires its `+initialize`, which calls `[IODevice registerClass:self]`
  (`src/driverkit-3/libDriver/IODevice.m:180`). That is the only path by which
  `AHCIDisk` enters `classList`. Once there, being `IO_IndirectDevice` with no
  `+requiredProtocols`, it makes `connectToIndirectDevices` log
  `Loaded class AHCIDisk returns nil for +requiredProtocols` on every
  subsequent `registerDevice` (`IODevice.m:1532`). Log noise, not a cause.
- **`ENODEV` → `ENXIO` is expected progress.** `ata_hd_devsw_init` succeeded and
  installed block major 3, so the device node exists; there is simply no disk
  behind it.

## Approach

The loader asks firmware for the PCI bus range, then reuses `boot-2`'s existing
scanner to walk it.

`src/boot-2/i386/libsaio/pci.c` already has a BIOS-free path:
`PCI_Bus_Init()` falls through to `testMethod1()`, which probes CF8/CFC with
raw port I/O. UEFI does not trap port I/O on x86, so that code works unchanged
under the loader. The only thing it cannot obtain without the PCI BIOS is
`maxBusNum`, which `boot-2` fills via `ReadPCIBusInfo()` (INT 1Ah) at
`src/boot-2/i386/boot2/boot.c:389`.

So the loader supplies that one value from `EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL`
and calls `PCI_Bus_Init()` as `boot-2` does.

### Why not enumerate through firmware entirely

Two alternatives were considered and rejected:

- Walking PCI through the root bridge's own `Pci.Read()` accessors.
- Harvesting `EFI_PCI_IO_PROTOCOL` handles and calling `GetLocation()`.

Both duplicate `scanBus()` and diverge from `boot-2`. More importantly, the
kernel reaches PCI config space through CF8/CFC unconditionally
(`IOPCIDirectDevice.m`), so a firmware-mediated addressing path in the loader
introduces a second source of truth that firmware could resolve differently
from the kernel. Having the loader and the kernel use the same mechanism is
what keeps this class of bug from recurring.

### Resulting data flow

```
EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL->Configuration()
  -> ACPI bus-range descriptor -> maxBusNum
    -> kernBootStruct->pciInfo -> PCI_Bus_Init() -> scanBus() over CF8/CFC
      -> PCISlotInfo[] -> set_dinfo()/testIDs() -> "Location" = "Dev:31 Func:2 Bus:0"
        -> KernDeviceDescription -> IOPCIDeviceDescription (valid = YES)
          -> getPCIdevice: -> getPCIConfigData: -> AHCIController probes
```

Every step after the second already works. Only the first two are new.

## Components

### New: `src/bootefi-1/efi_pci.c`

Two functions, split so the parsing is testable without firmware.

**`efi_pci_bus_range(const void *resources)`** — pure. Walks the ACPI 2.0
resource descriptor chain returned by `Configuration()` and returns the bus
range maximum.

- Each QWORD Address Space Descriptor begins with tag byte `0x8A` followed by a
  2-byte length; the descriptor carrying bus numbers has `ResType == 2`, and
  its `AddrRangeMax` is the value wanted.
- The chain ends at the End Tag, `0x79`.
- `Configuration()` returns a bare pointer with no total length, so the walk is
  bounded by an explicit maximum descriptor count and stops on any tag it does
  not recognise.
- Returns a distinct not-found sentinel when the chain is malformed, ends
  without a bus descriptor, or exceeds the iteration bound. The sentinel is
  distinguishable from a valid range maximum of 0, since a single-bus machine
  legitimately reports `AddrRangeMax == 0`.

**`efi_pci_init(void)`** — EFI plumbing, following the `LocateHandle` /
`AllocatePool` / `HandleProtocol` shape already used by `efi_disk_init()` in
`src/bootefi-1/efi_disk.c:64`.

- Locates every `EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL` handle, calls
  `Configuration()` on each, and takes the maximum bus range across all of
  them. `scanBus()` supports only a single contiguous `0..maxBusNum`, so a
  multi-root-bridge machine is covered by scanning up to the highest bus any
  bridge claims.
- Writes `kernBootStruct->pciInfo` with `BIOSPresent = 0` and the derived
  `maxBusNum`; version fields stay zero, since no PCI BIOS reported them.
- Calls `PCI_Bus_Init(&kernBootStruct->pciInfo)`, which sets `PCISlotInfo`.
- Returns the number of slots found, for the loader's progress line.

### Changed files

| File | Change |
|---|---|
| `src/bootefi-1/efi_main.c:47` | Delete the `void *PCISlotInfo;` stub. Once `pci.c` links, its `_pci_slot_info_t *PCISlotInfo` is the real definition; leaving both is a duplicate symbol, or a silent type-mismatched merge under `-fcommon`. Correct the comment above it, which asserts the loader has no PCI auto-detect. Add a `pci devices: %d` progress line calling `efi_pci_init()` after `efi_init_bootstruct()` and before `loadSystemConfig()` — `set_dinfo()` reads `PCISlotInfo` during `loadBootDrivers()`. |
| `src/bootefi-1/efi.h` | Add `EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL_GUID` and the protocol struct, in the file's existing minimal hand-rolled style. |
| `src/bootefi-1/Makefile:50` | Add `$(BOOT2)/libsaio/pci.c` to `BOOT2_SRCS` and `efi_pci.c` to `EFI_SRCS`. `VPATH` already covers `libsaio`. |
| `src/boot-2/i386/libsaio/pci.c:116-117` | `malloc(sizeof(_pci_slot_info_t) * nslots + 1)` allocates one spare byte, then `pci.c:119-120` writes an 8-byte terminator at `slot_array[nslots]`. `_pci_slot_info_t` is 20 bytes (`pci.h:29-34`), so this overflows the allocation by 7 bytes. Change to `* (nslots + 1)`. Pre-existing, but dormant only because nothing under UEFI calls this today; enabling the scan makes it live. |
| `AHCIController.m:93-296` | Give each of the nineteen `[self free]; return nil;` paths in `initFromDeviceDescription` a distinct `IOLog("AHCI: ...")`, matching the `IOLog("AHCI: ...")` style already in the file. |
| `AHCIController.h`, `AHCIDisk.m` | Declare `@protocol AHCIControllerPublic`, adopt it on `AHCIController`, and return it from a new `+[AHCIDisk requiredProtocols]`. |

### The `efi.h` protocol struct is the risky edit

`Configuration` sits late in `EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL`'s member
ordering, after the `PollMem`/`PollIo` pair, the three `Mem`/`Io`/`Pci` access
sub-structures, `CopyMem`, `Map`/`Unmap`, `AllocateBuffer`/`FreeBuffer`,
`Flush`, and `GetAttributes`/`SetAttributes`. Every preceding member has to
match the UEFI spec exactly. A misordered or missing member calls the wrong
function pointer, which produces a hang or a fault rather than a compile error.

Implementation orders the work so this is confirmed before anything depends on
it. First land `efi_pci_init()` deriving the range and printing it, but passing
the 0–255 fallback to `PCI_Bus_Init()` regardless. Boot once: if the printed
range is plausible (0–255 on QEMU q35), the struct layout is right, and a
second commit switches `PCI_Bus_Init()` over to the derived value. If the
struct is wrong, the failure surfaces on a boot where nothing yet depends on
the answer.

### Why `AHCIDisk` gets a real protocol

`IdeDisk` is the precedent
(`src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDisk.m:84-92`): it
is `IO_IndirectDevice` and returns `@protocol(IdeControllerPublic)`, the
protocol its controller exports. `AHCIController` currently declares no
protocol, so one is added for `AHCIDisk` to require.

This silences the log line without changing how disks are published.
`connectToIndirectDevices` will find that `AHCIController` conforms and call
`[AHCIDisk probe:]`; `AHCIDisk` does not implement `+probe:`, and `IODevice`'s
default returns `NO` (`IODevice.m:216`), so the auto-connect path correctly
declines and publication stays with `+[AHCIDisk publishForPort:deviceDescription:]`.

Returning a protocol nothing conforms to would also silence the log, but would
encode a falsehood to do it.

## Error handling

Each stage degrades rather than failing the boot.

- No root bridge handle, `LocateHandle` failure, `AllocatePool` failure,
  `HandleProtocol` failure, `Configuration()` failure, or no bus descriptor in
  the chain: fall back to scanning buses 0–255 and print a one-line notice. This
  costs milliseconds and is strictly better than the current behaviour of
  finding nothing.
- `PCI_Bus_Init()` returning NULL (neither config method detected): leave
  `PCISlotInfo` NULL. This is exactly today's behaviour, so it introduces no new
  failure mode.
- The `AHCIController` logging changes no behaviour at all; the same paths
  fail the same way, visibly.

## Testing

**Host tests** for `efi_pci_bus_range()` in `src/bootefi-1/tests/`, following
the existing `ufs_host_test.c` convention:

- a well-formed chain whose first descriptor is the bus range;
- a chain with I/O and memory descriptors ahead of the bus descriptor;
- a chain with no bus descriptor, returning the sentinel;
- a chain truncated mid-descriptor, returning the sentinel;
- a chain with no End Tag, hitting the iteration bound and returning the
  sentinel;
- a single-bus machine reporting `AddrRangeMax == 0`, distinguished from the
  sentinel.

**Boot test** under `vm/run-q35-uefi.sh`, on a copied disk image. Another
session is debugging this same driver concurrently, and `CLAUDE.md` §6 requires
temporary images to keep the two isolated.

Success criteria, checked in order — each one failing localises the problem to a
different stage of the chain above:

1. `pci devices: N` with N greater than zero.
2. A `"Location"` key present in AHCI's config table.
3. `AHCIController` probes with no `AHCI:` failure log.
4. `root on hd0a` mounts, and `cannot mount root, errno = 6` is gone.

`vm/run-q35-uefi.sh`'s header comment currently states that the media has no
AHCI driver and that the script is for loader-level testing only. Verification
needs media with the driver installed, so that comment needs correcting as part
of this work.

## Out of scope

- `LoadableFamilies` and EISA auto-detect stay stubbed in `efi_main.c`.
- No change to how `AHCIDisk` instances are published.
- No bridge-aware recursive bus scan; firmware supplies the range.
- Real UEFI hardware. Target is QEMU with IA32 OVMF, consistent with
  `docs/superpowers/specs/2026-09-17-uefi-bootloader-design.md`.
