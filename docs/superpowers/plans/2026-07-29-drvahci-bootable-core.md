# drvAHCI Bootable Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot RhapsodiOS/i386 from a QEMU q35 AHCI SATA disk and detect, mount, and read an AHCI ATAPI CD while preserving drvEIDE and one collision-free `hd0` through `hd31` namespace.

**Architecture:** A standalone `drvAHCI` DriverKit bundle owns PCI/MMIO, one slot-0 DMA command path per implemented port, SATA `IODisk` children, and ATAPI `IOSCSIController` children. Dependency-free C modules build AHCI structures and validate HBA state transitions. A kernel-resident ATA disk registry owns majors 3/15 and allocates global `hd` units to both EIDE and AHCI.

**Tech Stack:** C89, Objective-C, NeXT/Apple DriverKit, i386 Mach/BSD kernel, AHCI 1.3.1, ATA/ATAPI packet commands, ProjectBuilder `pb_makefiles`/`gnumake`, standalone C tests, QEMU q35/ICH9, disposable raw and ISO images.

---

## Constraints and verification commands

- Perform implementation in a dedicated worktree because this checkout contains unrelated changes.
- Keep `drvEIDE` controller, task-file, timing, DMA, retry, and recovery behavior unchanged.
- Use `AHCIController : IODirectDevice`; `IOPCIDirectDevice` supplies PCI methods as an Objective-C category.
- Use all 32 `PI` bits, slot 0 only, one active command per port, and independent progress between ports.
- Keep command DMA addresses below 4 GiB and program every upper address register as zero.
- Publish only 512-byte logical-sector disks and cap visible capacity at `0xffffffff` sectors.
- Keep all hardware waits bounded by the named design timeouts.
- Never modify a reference disk image in-place; copy it into `vm/work/ahci-*` before each emulator test.

Portable suite command in the Rhapsody/Unix build environment:

```sh
cd src/drivers-i386/ide/drvAHCI/tests
gnumake clean all check
```

Expected: `ahci_command_test`, `ahci_state_test`, `ata_hd_registry_test`, and `ata_hd_root_test` each print `all tests passed`.

Kernel and driver build command:

```sh
sh vm/build-i386-kernel-ahci.sh
```

Expected: the i386 kernel, `EIDE.config/Default.table`, `AHCI.config/Default.table`, `EIDE_reloc`, and `AHCI_reloc` are staged under `vm/install` with no new compiler warnings.

## File map

- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIRegs.h`: register offsets, masks, DMA layouts, and compile-time size checks.
- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCICommand.h/.c`: pure builders for command headers, FISes, capacity, and PRDTs.
- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIState.h/.c`: pure PI iteration, link classification, interrupt/error decoding, and deadline-independent recovery decisions.
- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.h/.m`: PCI match, ABAR map, ownership handoff, HBA lifecycle, interrupt dispatch.
- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.h/.m`: DMA arena, port engine, slot-0 submission, timeout arbitration, and recovery.
- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.h/.m` and `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDiskInternal.h/.m`: `IODisk` frontend, request pool, worker, ATA identify/read/write/flush.
- `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIATAPI.h/.m`: `IOSCSIController` frontend and SCSI-to-packet translation.
- `src/kernel-7/bsd/dev/ata_hd_registry_core.h/.c`: dependency-free 32-slot allocation/lifecycle core.
- `src/kernel-7/bsd/dev/ata_hd_registry.h/.m`: kernel registry lock, device switches, raw buffers, and transport dispatch.
- `src/kernel-7/machdep/i386/ata_hd_root.h/.c`: dependency-free `hd0` through `hd31` parser.
- `src/drivers-i386/ide/drvAHCI/tests/*`: portable unit tests and Makefile.
- `vm/build-i386-kernel-ahci.sh`: reproducible build/staging entry point.
- `vm/run-q35-ahci.sh`: disposable q35 integration launcher.

### Task 1: Build the command-layout test harness

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIRegs.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCICommand.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCICommand.c`
- Create: `src/drivers-i386/ide/drvAHCI/tests/ahci_command_test.c`
- Create: `src/drivers-i386/ide/drvAHCI/tests/Makefile`

- [ ] **Step 1: Write failing structure and Register H2D FIS tests**

Define fixed-width local types without compiler bitfields. Add compile assertions for a 32-byte command header and 16-byte PRD. Test exact bytes for IDENTIFY and PACKET FISes:

```c
typedef struct {
    unsigned short flags, prdtl;
    unsigned int prdbc, ctba, ctbau, reserved[4];
} AHCICommandHeader;
typedef struct {
    unsigned int dba, dbau, reserved, dbc_ioc;
} AHCIPRDTEntry;

CHECK(sizeof(AHCICommandHeader) == 32);
CHECK(sizeof(AHCIPRDTEntry) == 16);
CHECK(fis[0] == 0x27 && fis[1] == 0x80);
CHECK(fis[2] == 0xec && fis[15] == 0x00);
```

- [ ] **Step 2: Run the suite and verify RED**

Expected: undefined `AHCIBuildIdentifyFIS` and `AHCIBuildPacketFIS`.

- [ ] **Step 3: Implement byte-addressed FIS builders**

Expose and implement:

```c
void AHCIBuildIdentifyFIS(unsigned char fis[20], unsigned char packet);
int AHCIBuildDMAFIS(unsigned char fis[20], unsigned int lba,
                    unsigned int sectors, unsigned char write,
                    unsigned char lba48);
void AHCIBuildFlushFIS(unsigned char fis[20], unsigned char lba48);
void AHCIBuildPacketFIS(unsigned char fis[20]);
```

Zero all 20 bytes first, set FIS type `0x27`, command bit `0x80`, and leave NIEN clear. Return an error for zero sectors, more than 256 sectors, or an LBA28 request whose ending LBA exceeds `0x0fffffff`.

- [ ] **Step 4: Verify GREEN and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIRegs.h \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCICommand.* \
        src/drivers-i386/ide/drvAHCI/tests
git commit -m "drvAHCI: add tested command layouts"
```

### Task 2: Complete DMA, capacity, and PRDT builders

**Files:** modify `AHCICommand.h`, `AHCICommand.c`, and `ahci_command_test.c`.

- [ ] **Step 1: Add boundary and fragmentation tests**

Cover READ DMA `0xc8`, WRITE DMA `0xca`, READ DMA EXT `0x25`, WRITE DMA EXT `0x35`, FLUSH `0xe7/0xea`, LBA `0x0fffffff`, a two-sector crossing request, 256-sector count encoding, PRD coalescing, DBC=`bytes-1`, final-entry IOC, 32-entry exhaustion, zero length, overflow, and a segment ending above `0xffffffff`.

```c
typedef struct { unsigned int address, length; } AHCISegment;
CHECK(AHCIBuildPRDT(prd, 32, seg, 2, 8192) == 1);
CHECK((prd[0].dbc_ioc & 0x003fffffU) == 8191U);
CHECK((prd[0].dbc_ioc & 0x80000000U) != 0);
```

- [ ] **Step 2: Verify RED**

Expected: undefined `AHCIParseIdentify`, `AHCISelectDMACommand`, `AHCIBuildPRDT`, and `AHCIInitCommandHeader`.

- [ ] **Step 3: Implement exact pure APIs**

```c
typedef struct {
    unsigned int sectors;
    unsigned char lba48, clamped, logicalSectorIs512;
} AHCICapacity;
int AHCIParseIdentify(const unsigned short id[256], AHCICapacity *out);
int AHCISelectDMACommand(unsigned int lba, unsigned int sectors,
                         unsigned char write, unsigned char lba48,
                         unsigned char *command, unsigned char *useLba48);
int AHCIBuildPRDT(AHCIPRDTEntry *prd, unsigned int maxPrds,
                  const AHCISegment *segments, unsigned int segmentCount,
                  unsigned int transferBytes);
void AHCIInitCommandHeader(AHCICommandHeader *header, unsigned int tablePA,
                           unsigned int prdtCount, unsigned char write,
                           unsigned char atapi);
```

Parse words 60-61 and 100-103 without requiring 64-bit runtime arithmetic: any nonzero word 102/103 clamps to `0xffffffff`; otherwise combine words 100/101. Validate IDENTIFY word 106 logical-sector metadata and reject non-512 logical sectors.

- [ ] **Step 4: Verify GREEN and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCICommand.* \
        src/drivers-i386/ide/drvAHCI/tests/ahci_command_test.c
git commit -m "drvAHCI: build ATA and PRDT commands"
```

### Task 3: Add tested HBA/port state decisions

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIState.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIState.c`
- Create: `src/drivers-i386/ide/drvAHCI/tests/ahci_state_test.c`
- Modify: `src/drivers-i386/ide/drvAHCI/tests/Makefile`

- [ ] **Step 1: Write failing state-table tests**

Test sparse `PI` masks (`0x80000001`), rejection of bits above `CAP.NP`, SATA signature `0x00000101`, ATAPI signature `0xeb140101`, present/active `SSTS`, completion only after `CI & 1` clears, fatal interrupt classification, link removal, and local-reset versus HBA-reset escalation.

- [ ] **Step 2: Verify RED**

Expected: undefined state helpers.

- [ ] **Step 3: Implement pure decisions**

```c
typedef enum { AHCI_DEVICE_NONE, AHCI_DEVICE_SATA,
    AHCI_DEVICE_ATAPI, AHCI_DEVICE_UNSUPPORTED } AHCIDeviceKind;
typedef enum { AHCI_RECOVERY_NONE, AHCI_RECOVERY_PORT,
    AHCI_RECOVERY_HBA, AHCI_RECOVERY_OFFLINE } AHCIRecovery;
int AHCIPIValid(unsigned int cap, unsigned int pi);
int AHCINextPort(unsigned int pi, int previous);
AHCIDeviceKind AHCIClassifyPort(unsigned int ssts, unsigned int sig);
int AHCICommandCompleted(unsigned int ci, unsigned int portIS);
AHCIRecovery AHCIRecoveryFor(unsigned int portIS, unsigned int serr,
                             unsigned char engineStopped,
                             unsigned char hbaResetAlreadyTried);
```

Keep register writes and delays out of this module; it returns decisions consumed by `AHCIController` and `AHCIPort`.

- [ ] **Step 4: Verify GREEN and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIState.* \
        src/drivers-i386/ide/drvAHCI/tests
git commit -m "drvAHCI: test HBA state decisions"
```

### Task 4: Implement the shared 32-unit registry core and root parser

**Files:**
- Create: `src/kernel-7/bsd/dev/ata_hd_registry_core.h`
- Create: `src/kernel-7/bsd/dev/ata_hd_registry_core.c`
- Create: `src/kernel-7/machdep/i386/ata_hd_root.h`
- Create: `src/kernel-7/machdep/i386/ata_hd_root.c`
- Create: `src/drivers-i386/ide/drvAHCI/tests/ata_hd_registry_test.c`
- Create: `src/drivers-i386/ide/drvAHCI/tests/ata_hd_root_test.c`
- Modify: `src/drivers-i386/ide/drvAHCI/tests/Makefile`

- [ ] **Step 1: Write failing registry tests**

Test lowest-free allocation, duplicate-owner rejection, all 32 slots, exhaustion, lookup, open counts per partition, refusal to remove an open disk, removal/reuse, and mixed mock EIDE/AHCI owners.

```c
ATAHDRegistryCore core;
ATAHDRegistryCoreInit(&core);
CHECK(ATAHDRegistryAllocate(&core, &eide0) == 0);
CHECK(ATAHDRegistryAllocate(&core, &ahci0) == 1);
CHECK(ATAHDRegistryRemove(&core, 0) == ATA_HD_BUSY);
```

- [ ] **Step 2: Write failing root-name tests**

Accept `hd0a`, `hd9h`, `hd10a`, `hd31h`, and a missing partition defaulting to `a`. Reject `hd32a`, negative/three-digit units, trailing text, and partitions outside `a`-`h`.

- [ ] **Step 3: Implement dependency-free cores**

```c
#define ATA_HD_UNITS 32
#define ATA_HD_PARTITIONS 8
int ATAHDRegistryAllocate(ATAHDRegistryCore *, void *owner);
int ATAHDRegistryOpen(ATAHDRegistryCore *, unsigned int unit,
                      unsigned int partition);
int ATAHDRegistryClose(ATAHDRegistryCore *, unsigned int unit,
                       unsigned int partition);
int ATAHDRegistryRemove(ATAHDRegistryCore *, unsigned int unit);
int ATAHDParseRoot(const char *name, unsigned int *unit,
                   unsigned int *partition);
```

Use fixed arrays and subtraction/range checks; do not allocate memory in either core.

- [ ] **Step 4: Verify GREEN and commit**

```sh
git add src/kernel-7/bsd/dev/ata_hd_registry_core.* \
        src/kernel-7/machdep/i386/ata_hd_root.* \
        src/drivers-i386/ide/drvAHCI/tests
git commit -m "kernel: add tested ATA disk registry core"
```

### Task 5: Move majors 3/15 into the kernel registry

**Files:**
- Create: `src/kernel-7/bsd/dev/ata_hd_registry.h`
- Create: `src/kernel-7/bsd/dev/ata_hd_registry.m`
- Modify: `src/kernel-7/conf/files.i386`
- Modify: `src/kernel-7/machdep/i386/swapgeneric.m`

- [ ] **Step 1: Compile the new files with unresolved wrapper APIs**

Register both core sources and the Objective-C wrapper in `files.i386`; make `swapgeneric.m` call `ATAHDParseRoot`. Build and verify RED on missing wrapper declarations/definitions before changing EIDE.

- [ ] **Step 2: Define the transport-neutral API**

```objc
typedef IOReturn (*ata_hd_ioctl_fn)(id disk, dev_t dev,
                                    unsigned int cmd, caddr_t data,
                                    int flag, struct proc *proc);
BOOL ata_hd_devsw_init(Class diskClass,
                       IODeviceDescription *deviceDescription);
int ata_hd_register(id disk, ata_hd_ioctl_fn transportIoctl,
                    IODevAndIdInfo **mapOut);
IOReturn ata_hd_unregister(unsigned int unit);
IODevAndIdInfo *ata_hd_lookup(dev_t dev);
```

The wrapper owns one lock, 32 `IODevAndIdInfo` objects, 32 raw `struct buf` objects, and the only device-switch installation calls for block major 3 and character major 15. `ata_hd_devsw_init` uses the first disk class's inherited `addToCdevswFromDescription:` and `addToBdevswFromDescription:` methods, records the configured majors, and makes later calls idempotent only when they request the same majors. Its open/close/read/write/strategy/size/generic-ioctl callbacks validate unit and partition before dispatching to the registered `IODisk`.

- [ ] **Step 3: Preserve transport-specific ioctls**

Dispatch `DKIOC*` generically. Call the optional transport callback for EIDE diagnostic requests; return the existing unsupported error when an AHCI disk has no callback.

- [ ] **Step 4: Build the kernel and commit**

```sh
git add src/kernel-7/bsd/dev/ata_hd_registry.* \
        src/kernel-7/bsd/dev/ata_hd_registry_core.* \
        src/kernel-7/machdep/i386/ata_hd_root.* \
        src/kernel-7/machdep/i386/swapgeneric.m src/kernel-7/conf/files.i386
git commit -m "kernel: own shared hd device namespace"
```

### Task 6: Migrate drvEIDE to the shared registry

**Files:**
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeKernel.h`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeKernel.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDisk.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDiskInternal.h`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDiskInternal.m`
- Modify: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/PostLoad.tproj/PostLoad.m`

- [ ] **Step 1: Add a failing EIDE registration regression**

Extend the registry mock test with an EIDE transport ioctl callback and assert that only its allocated unit invokes it. Build drvEIDE before migration to capture the expected duplicate devsw ownership failure when linked with the new registry.

- [ ] **Step 2: Replace private allocation**

Delete `IdeIdMap[4]`, the private raw buffers, `diskUnit`, `switchTableInited`, and EIDE's devsw installation. In `IdeDisk` initialization:

```objc
char devName[16];
if (!ata_hd_devsw_init(self, deviceDescription)) return nil;
unit = ata_hd_register(self, IdeDiskTransportIoctl, &devAndIdInfo);
if (unit < 0) return nil;
sprintf(devName, "hd%d", unit);
[self setUnit:unit];
[self setName:devName];
```

Keep the EIDE diagnostic ioctl body in `IdeKernel.m` behind `IdeDiskTransportIoctl`; do not alter hardware selectors.

- [ ] **Step 3: Make node publication idempotent for 32 units**

Update `PostLoad` to create `hd0`-`hd31` and `rhd0`-`rhd31` with eight partition minors each only when absent. Preserve majors 3 and 15.

- [ ] **Step 4: Run unit/build/i440fx regression and commit**

Boot a disposable copy of the existing i440fx image, confirm root remains `hd0a`, read/write/sync succeeds, and EIDE diagnostic ioctls still dispatch.

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeKernel.* \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDisk* \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/PostLoad.tproj/PostLoad.m
git commit -m "drvEIDE: use shared hd registry"
```

### Task 7: Scaffold the standalone AHCI bundle

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/Makefile`
- Create: `src/drivers-i386/ide/drvAHCI/Makefile.preamble`
- Create: `src/drivers-i386/ide/drvAHCI/PB.project`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/Makefile`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/Makefile.preamble`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PB.project`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/Default.table`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/DriverInfo`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/Makefile`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/Makefile.preamble`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/PB.project`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/Load_Commands.sect`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PostLoad.tproj/Makefile`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PostLoad.tproj/Makefile.preamble`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PostLoad.tproj/PB.project`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PostLoad.tproj/PostLoad.m`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/English.lproj/Localizable.strings`

- [ ] **Step 1: Copy only the period build shape from drvEIDE**

Create a new `AHCI` project/bundle with unique product, class, config, and load symbols. List `AHCICommand.c` and `AHCIState.c` as C sources. Do not copy EIDE Objective-C classes or PCI tables.

- [ ] **Step 2: Add the mandatory q35 match**

Set the config to probe Intel `8086:2922`; production probe must also verify class/subclass/prog-if `01:06:01`, so the vendor/device table alone cannot claim a non-AHCI function.

- [ ] **Step 3: Add a minimal loadable controller**

Declare:

```objc
@interface AHCIController : IODirectDevice
- (BOOL)probe:(IODeviceDescription *)description;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)interruptOccurred;
@end
```

Return attach failure after logging PCI identity until Task 8 supplies ABAR/HBA initialization.

- [ ] **Step 4: Build/load-check and commit**

```sh
git add src/drivers-i386/ide/drvAHCI
git commit -m "drvAHCI: scaffold standalone driver bundle"
```

### Task 8: Attach PCI, map ABAR, and initialize the HBA

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIShared.h`
- Modify: `AHCIRegs.h`, `PB.project`, and the AHCI link-project Makefile.

- [ ] **Step 1: Extend fake-state tests for initialization ordering**

Represent observed transitions as an event array and assert: PCI command enable; BOHC handoff; AE; HR with one-second deadline; AE reassert; global IE clear; stale IS clear; `PI` validation; port construction; per-port IE; global IE last.

- [ ] **Step 2: Implement PCI and BAR5 validation**

Use `IOPCIDirectDevice` category methods to read vendor/device, class tuple, PCI command, and BAR5 at `0x24`. Reject I/O BARs and zero/all-one addresses. Install a `0x1100` memory range, call `[self mapMemoryRange:0 to:&abar findSpace:YES cache:IO_CacheOff]`, and use volatile 32-bit accessors with the platform I/O barrier.

- [ ] **Step 3: Implement bounded global initialization**

Add named constants for 25 ms/2 s BOHC, 1 s HBA reset, and 500 ms engine stops. Validate VS/CAP/CAP2/PI with `AHCIPIValid`. Allocate no port resources until the controller passes handoff and reset.

- [ ] **Step 4: Build, inspect q35 attach logs, and commit**

Expected log includes `8086:2922`, AHCI version, CAP/CAP2, and PI; no port child attaches yet.

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj
git commit -m "drvAHCI: initialize q35 HBA"
```

### Task 9: Allocate and start every implemented port

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.m`
- Modify: `AHCIController.m`, `AHCIShared.h`, `PB.project`, and Makefile.

- [ ] **Step 1: Add arena/layout and sparse-PI tests**

Test offsets/alignment for 1 KiB command list, 256-byte RFIS, 128-byte command table, and 32 PRDs. Assert port 31 is created for `PI=0x80000000` and holes are skipped.

- [ ] **Step 2: Implement one low-memory arena per PI bit**

Allocate an over-sized `IOMallocLow` block, align its usable physical base to 1 KiB, zero it, translate each region with `IOPhysicalFromVirtual`, and reject noncontiguous, misaligned, wrapping, or non-32-bit addresses before writing CLB/FB/CTBA; keep raw allocation metadata for cleanup.

- [ ] **Step 3: Implement the engine sequence**

Clear ST/wait CR, clear FRE/wait FR, program bases, W1C PxIS/PxSERR, set POD/SUD only when advertised, preserve firmware SPD, set FRE/wait FR, then ST/wait CR. Require `SSTS.DET=3` and active IPM; assert COMRESET for at least 1 ms only when recovery is needed.

- [ ] **Step 4: Classify and log devices without publishing them**

Use `AHCIClassifyPort`; record SATA/ATAPI/unsupported/empty. Enable fatal/error/link-change interrupts but leave normal command issue disabled until Task 10.

- [ ] **Step 5: Build/q35 probe and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.* \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIShared.h
git commit -m "drvAHCI: initialize implemented ports"
```

### Task 10: Submit slot-0 commands with interrupt/timeout arbitration

**Files:** modify `AHCIPort.h/.m`, `AHCIController.m`, `AHCIShared.h`, `AHCIState.h/.c`, and `ahci_state_test.c`.

- [ ] **Step 1: Write the failing completion-race tests**

Model generation-tagged states `IDLE`, `PENDING`, `COMPLETE`, `TIMED_OUT`. Assert interrupt-first and timer-first races complete a request exactly once; stale timer callbacks cannot complete a later generation; spurious IRQs wake nobody.

- [ ] **Step 2: Add the per-port request contract**

```objc
- (IOReturn)executeATA:(unsigned char)command
                   fis:(const unsigned char *)fis
                packet:(const unsigned char *)packet
               buffer:(void *)buffer
                length:(unsigned int)length
                 write:(BOOL)write
               timeout:(unsigned int)seconds
           transferred:(unsigned int *)actual;
```

Translate resident buffer pages into `AHCISegment[32]`, build the PRDT, clear stale state, schedule a generation-tagged `IOScheduleFunc`, execute the barrier, and set only `PxCI` bit 0 while holding the port condition lock.

- [ ] **Step 3: Dispatch shared interrupts**

`AHCIController -interruptOccurred` snapshots global IS and dispatches only `IS & PI`. The port snapshots PxIS/PxTFD/PxSERR/PxCI/PRDBC and received FIS before W1C acknowledgement. It marks success only when CI bit 0 is clear and no classified error exists.

- [ ] **Step 4: Implement bounded recovery**

On error/timeout: mask port IRQs; stop ST/CR and FRE/FR; clear errors; COMRESET; reprogram bases; restart; re-identify. Escalate under one controller recovery lock only when the engine cannot stop or an HBA-wide fatal error is decoded. Try one HBA reset and leave the controller offline after failure.

- [ ] **Step 5: Verify tests/build and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.* \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIState.* \
        src/drivers-i386/ide/drvAHCI/tests/ahci_state_test.c
git commit -m "drvAHCI: execute bounded slot zero commands"
```

### Task 11: Publish SATA disks and bootable `hd` I/O

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.m`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDiskInternal.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDiskInternal.m`
- Modify: `AHCIPort.m`, `PB.project`, and Makefile.

- [ ] **Step 1: Add identify/request boundary tests**

Assert 512-byte LBA28 media, LBA48 media capped at `0xffffffff`, rejection of 4Kn, zero-length rejection, overflow-safe last-sector clipping, 128 KiB/256-sector segmentation, and EXT selection when a segment crosses `0x10000000`.

- [ ] **Step 2: Identify before publication**

Issue `0xec` into a 512-byte low-memory buffer with a 10-second timeout; parse capacity/model/serial/firmware; reject unsupported logical sector sizes. Publish only after successful re-identification.

- [ ] **Step 3: Implement the IODisk worker**

Follow drvEIDE's preallocated request-pool and async completion shape under unique AHCI class/type names. Split at 256 sectors, validate `block < capacity` and `count <= capacity - block`, select LBA28/LBA48, and submit reads/writes with 10-second timeouts.

- [ ] **Step 4: Register globally and flush writes**

Call `ata_hd_register(self, 0, &devAndIdInfo)` and use the returned unit for `hdN`. Implement synchronize/cache-flush using `0xe7` or `0xea` with a 30-second timeout. Never install devsw entries from the bundle.

- [ ] **Step 5: Build, perform raw q35 read/write, and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk* \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.m
git commit -m "drvAHCI: publish SATA disks"
```

### Task 12: Publish the AHCI ATAPI SCSI frontend

**Files:**
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIATAPI.h`
- Create: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIATAPI.m`
- Modify: `AHCIPort.m`, `AHCICommand.h/.c`, `ahci_command_test.c`, `PB.project`, and Makefile.

- [ ] **Step 1: Add packet-construction tests**

Assert command `0xa0`, header ATAPI flag, 12/16-byte ACMD copy with zero-fill, byte-count registers, data direction, zero-data TEST UNIT READY, 2048-byte READ(10), and rejection above 128 KiB.

- [ ] **Step 2: Identify and publish ATAPI**

Issue `0xa1`; create one `AHCIATAPIController : IOSCSIController` at target 0/LUN 0 only after success. Do not consume an `hd` unit.

- [ ] **Step 3: Adapt the existing translation behavior under unique names**

Support INQUIRY, TEST UNIT READY, REQUEST SENSE, READ CAPACITY, READ(10), MODE SENSE, START STOP UNIT, and PREVENT/ALLOW MEDIUM REMOVAL. Pass the original CDB as ACMD, use the inherited SCSI completion/status conventions, and give packet commands 30-second timeouts.

- [ ] **Step 4: Handle removal cleanly**

Translate not-ready/unit-attention sense, fail active I/O once on link/media removal, mark the child offline where appropriate, and contain link-change interrupts without runtime child creation.

- [ ] **Step 5: Build, mount a disposable ISO, and commit**

```sh
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIATAPI.* \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIPort.m \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCICommand.* \
        src/drivers-i386/ide/drvAHCI/tests/ahci_command_test.c
git commit -m "drvAHCI: add ATAPI optical support"
```

### Task 13: Add reproducible build and disposable q35 launchers

**Files:**
- Create: `vm/build-i386-kernel-ahci.sh`
- Create: `vm/run-q35-ahci.sh`
- Modify: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PostLoad.tproj/PostLoad.m`
- Modify: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/Default.table`
- Modify: `docs/superpowers/specs/2026-07-29-drvahci-bootable-core-design.md` only if implementation evidence requires a factual correction.

- [ ] **Step 1: Make build staging fail fast**

Base the script on the existing EIDE kernel build flow. Run portable tests first, then build kernel, EIDE, and AHCI, and stage exact artifacts into `vm/install`. Check each output exists and reject stale timestamps.

- [ ] **Step 2: Make q35 inputs disposable**

Require source root image, working-image path under `vm/work`, and optional ISO. Refuse to run when source and working paths resolve identically. Copy/create the working disk before launching QEMU with q35, ICH9 AHCI, SATA disk on port 0, optional second disk on another port, and ATAPI CD.

- [ ] **Step 3: Document exact root arguments and debug knobs**

Pass `hd0a` through the repository's existing kernel/root mechanism. Add AHCI debug logging without enabling it by default. Document where serial logs and disposable images land.

- [ ] **Step 4: Dry-run scripts, build, and commit**

```sh
sh -n vm/build-i386-kernel-ahci.sh vm/run-q35-ahci.sh
sh vm/build-i386-kernel-ahci.sh
git add vm/build-i386-kernel-ahci.sh vm/run-q35-ahci.sh \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/PostLoad.tproj/PostLoad.m \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/Default.table
git commit -m "vm: add q35 AHCI build and launch flow"
```

### Task 14: Prove boot, ATAPI, concurrency, and regressions

**Files:** verification only unless a check exposes a defect.

- [ ] **Step 1: Run all portable tests and complete builds**

Run `gnumake clean all check`, kernel build, drvEIDE build, and drvAHCI build. Record compiler/linker output and reject implicit declarations, packed-layout warnings, pointer truncation, or unresolved symbols in new files.

- [ ] **Step 2: Boot q35 from AHCI `hd0a`**

Use a disposable root copy. Confirm ICH9 attach, port 0 identify, global `hd0`, root mount, test-file write/read/hash, sync, reboot, and clean remount.

- [ ] **Step 3: Exercise live LBA48**

Attach a disposable sparse disk with test data beyond sector `0x10000000`. Read/write/hash sectors immediately below, crossing, and above the boundary. Confirm logs show `0x25/0x35` only for crossing/above segments.

- [ ] **Step 4: Detect, mount, and read ATAPI media**

Attach a temporary ISO containing known hashed files. Confirm SCSI CD publication, mount, exact hashes, clean eject, and bounded failure on a removal during read without panic or interrupt storm.

- [ ] **Step 5: Prove per-port progress and sparse PI handling**

Run simultaneous hashed I/O on two SATA ports while reading the CD. Confirm each port advances independently. Exercise an empty/non-contiguous layout including the highest emulator-exposable port and confirm no register access for PI holes.

- [ ] **Step 6: Re-run i440fx EIDE and mixed namespace tests**

Boot the existing EIDE image from a disposable copy. Then, where QEMU permits both controllers, attach EIDE and AHCI disks and confirm unique `hd` units, correct major 3/15 dispatch, concurrent I/O, EIDE diagnostic ioctl routing, and AHCI unsupported response.

- [ ] **Step 7: Audit bounds, cleanup, and diff**

```sh
git diff --check HEAD~13..HEAD
git status --short
```

Review every wait loop for a named deadline, every W1C register acknowledgement, every DMA allocation/free path, and every publication failure unwind. Confirm no reference image was changed and only planned source/docs/scripts are staged.

- [ ] **Step 8: Request code review and report acceptance evidence**

Use `superpowers:requesting-code-review`. Report each acceptance criterion separately: q35 root boot, SATA read/write/flush, live LBA48, ATAPI mount/read/removal, concurrent ports, all 32 PI/unit logic, EIDE boot, and mixed collision-free namespace.
