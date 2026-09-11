# drvEIDE LBA28/LBA48 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve drvEIDE's CHS/LBA28 behavior while adding tested LBA48 reads and writes through the 32-bit DriverKit sector limit.

**Architecture:** A dependency-free C module parses IDENTIFY capacity, builds CHS/LBA28/LBA48 taskfiles, converts legacy commands to EXT commands, and produces ordered register writes. The Objective-C controller uses it for PIO, multiple-sector, DMA, and read-verify commands without duplicating existing transfer, retry, or recovery loops.

**Tech Stack:** C89, Objective-C, NeXT/Apple DriverKit, ATA taskfile I/O, ProjectBuilder `pb_makefiles`/`gnumake`, standalone C tests, QEMU disposable sparse disks.

---

## Constraints and commands

- Work in a clean dedicated worktree; this checkout has unrelated changes.
- Keep `ideRegsVal_t`, `ideIoReq_t`, and `ideDriveInfo_t` binary layouts unchanged.
- Keep the 256-sector transfer maximum and the existing CHS/ATAPI paths.
- Use EXT commands only when an end-exclusive request crosses `0x10000000`.
- Publish at most `0xffffffff` sectors, one 512-byte sector short of 2 TiB.
- Use disposable images for every emulator write test.

Standalone test command, from the repository root in the Rhapsody/Unix build environment:

```sh
cc -ansi -pedantic -Wall -Werror \
  -Isrc/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj \
  src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IDEAddressing.c \
  src/drivers-i386/ide/drvEIDE/tests/ide_addressing_test.c \
  -o /tmp/ide_addressing_test && /tmp/ide_addressing_test
```

Expected: `ide_addressing_test: all tests passed`.

Driver build command under the period toolchain on a case-sensitive filesystem:

```sh
cd src/drivers-i386/ide/drvEIDE && make
```

Expected: `EIDE_reloc` compiles and links for i386.

## File map

- `IDEAddressing.h/.c`: pure IDENTIFY parsing, bounds checks, taskfile construction, EXT opcode mapping, and ordered register-write descriptions.
- `tests/ide_addressing_test.c`: capacity, boundary, count, opcode, rejection, and write-order tests.
- `ata_extern.h`: EXT constants and names for IDENTIFY words 92-103; public sizes stay fixed.
- `IdeCnt.h`, `IdeCntInit.m`: per-drive addressable sectors/LBA48 state and initialization.
- `IdeCntCmds.h/.m`: taskfile-to-port bridge and PIO/multiple/read-verify issue.
- `IdeBMIDE.h/.m`: use the selected taskfile and EXT DMA opcode.
- `IdeDiskInternal.m`: overflow-safe clipping and unsigned segmentation.
- `PB.project`, `EIDE.lksproj/Makefile`: register the new pure module.

### Task 1: Parse IDENTIFY capacities

**Files:**
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IDEAddressing.h`
- Create: `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IDEAddressing.c`
- Create: `src/drivers-i386/ide/drvEIDE/tests/ide_addressing_test.c`

- [ ] **Step 1: Write the failing capacity tests**

Create `IDEAddressing.h`:

```c
#ifndef _IDE_ADDRESSING_H_
#define _IDE_ADDRESSING_H_
#define IDE_IDENTIFY_WORDS 256
#define IDE_IDENTIFY_CAPABILITIES 49
#define IDE_IDENTIFY_LBA28_LOW 60
#define IDE_IDENTIFY_LBA28_HIGH 61
#define IDE_IDENTIFY_COMMAND_SET_ENABLED_2 86
#define IDE_CAP_LBA 0x0200
#define IDE_CAP_LBA48 0x0400
#define IDE_LBA28_SECTORS 0x10000000UL
#define IDE_MAX_ADDRESSABLE_SECTORS 0xffffffffUL
typedef struct {
    unsigned int sectors, lba28Sectors;
    unsigned char lbaSupported, lba48Supported, clamped;
} ideCapacity_t;
void IDEParseIdentifyCapacity(const unsigned short identify[256],
                              ideCapacity_t *capacity);
#endif
```

Create a `CHECK`-based harness matching `via_timing_test.c`. Add `test_capacity`:

```c
static void test_capacity(void)
{
    unsigned short id[256];
    ideCapacity_t c;
    memset(id, 0, sizeof(id));
    id[49] = IDE_CAP_LBA; id[60] = 0x5678; id[61] = 0x0123;
    IDEParseIdentifyCapacity(id, &c);
    CHECK(c.lbaSupported == 1 && c.lba48Supported == 0);
    CHECK(c.lba28Sectors == 0x01235678UL && c.sectors == 0x01235678UL);
    id[86] = IDE_CAP_LBA48;
    id[100] = 0x5678; id[101] = 0x1234;
    IDEParseIdentifyCapacity(id, &c);
    CHECK(c.lba48Supported == 1 && c.sectors == 0x12345678UL);
    id[102] = 1;
    IDEParseIdentifyCapacity(id, &c);
    CHECK(c.sectors == 0xffffffffUL && c.clamped == 1);
    id[100] = id[101] = id[102] = id[103] = 0;
    IDEParseIdentifyCapacity(id, &c);
    CHECK(c.lba48Supported == 0 && c.sectors == c.lba28Sectors);
    memset(id, 0, sizeof(id));
    IDEParseIdentifyCapacity(id, &c);
    CHECK(c.sectors == 0 && c.lbaSupported == 0);
}
```

`main` calls the test, exits nonzero on failures, and prints the expected success line otherwise.

- [ ] **Step 2: Run the test and verify RED**

Expected: undefined `IDEParseIdentifyCapacity`.

- [ ] **Step 3: Implement the parser**

```c
#include <string.h>
#include "IDEAddressing.h"
void IDEParseIdentifyCapacity(const unsigned short id[256], ideCapacity_t *c)
{
    unsigned int lba28, low;
    memset(c, 0, sizeof(*c));
    c->lbaSupported = (id[49] & IDE_CAP_LBA) != 0;
    lba28 = (unsigned int)id[60] | ((unsigned int)id[61] << 16);
    if (lba28 > IDE_LBA28_SECTORS) lba28 = IDE_LBA28_SECTORS;
    if (c->lbaSupported) c->lba28Sectors = lba28;
    low = (unsigned int)id[100] | ((unsigned int)id[101] << 16);
    if ((id[86] & IDE_CAP_LBA48) && (low || id[102] || id[103])) {
        c->lba48Supported = 1;
        if (id[102] || id[103]) {
            c->sectors = IDE_MAX_ADDRESSABLE_SECTORS;
            c->clamped = 1;
        } else c->sectors = low;
    } else c->sectors = c->lba28Sectors;
}
```

- [ ] **Step 4: Run the test and verify GREEN**

- [ ] **Step 5: Commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IDEAddressing.* \
        src/drivers-i386/ide/drvEIDE/tests/ide_addressing_test.c
git commit -m "drvEIDE: parse LBA identify capacities"
```

### Task 2: Build and serialize taskfiles

**Files:** modify `IDEAddressing.h`, `IDEAddressing.c`, and `ide_addressing_test.c`.

- [ ] **Step 1: Add taskfile declarations and failing tests**

Add to the header:

```c
#define IDE_ADDRESS_CHS 0
#define IDE_ADDRESS_LBA 1
#define IDE_ADDRESS_OK 0
#define IDE_ADDRESS_INVALID 1
#define IDE_ADDRESS_UNSUPPORTED 2
typedef struct {
    unsigned char features, sectorCount, lbaLow, lbaMid, lbaHigh, deviceHead;
    unsigned char featuresHigh, sectorCountHigh;
    unsigned char lbaLowHigh, lbaMidHigh, lbaHighHigh, useLBA48;
} ideTaskfile_t;
typedef enum { IDE_TASK_DEVICE, IDE_TASK_FEATURES, IDE_TASK_COUNT,
    IDE_TASK_LBA_LOW, IDE_TASK_LBA_MID, IDE_TASK_LBA_HIGH } ideTaskRegister_t;
typedef struct { ideTaskRegister_t reg; unsigned char value; } ideTaskWrite_t;
int IDEBuildTaskfile(ideTaskfile_t *, unsigned char mode, unsigned char drive,
    unsigned int block, unsigned int count, unsigned int capacity,
    unsigned char lba48, unsigned int heads, unsigned int sectorsPerTrack);
unsigned int IDEExtendedCommand(unsigned int command);
unsigned int IDETaskfileWriteSequence(const ideTaskfile_t *, ideTaskWrite_t[11]);
```

Add assertions for:

```c
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 0x0fffffffUL, 1,
    0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
CHECK(tf.useLBA48 == 0 && tf.deviceHead == 0xef);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 1, 0x0fffffffUL, 2,
    0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
CHECK(tf.useLBA48 == 1 && tf.deviceHead == 0xf0 && tf.lbaLowHigh == 0x0f);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 0x10000000UL, 256,
    0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
CHECK(tf.sectorCount == 0 && tf.sectorCountHigh == 1);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 1, 256,
    0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_OK);
CHECK(tf.useLBA48 == 0 && tf.sectorCount == 0);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_CHS, 0, 63, 1,
    100000, 0, 16, 63) == IDE_ADDRESS_OK);
CHECK(tf.lbaLow == 1 && tf.deviceHead == 0xa1);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 0x10000000UL, 1,
    0xffffffffUL, 0, 0, 0) == IDE_ADDRESS_UNSUPPORTED);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 0, 0,
    100, 1, 0, 0) == IDE_ADDRESS_INVALID);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 99, 2,
    100, 1, 0, 0) == IDE_ADDRESS_INVALID);
CHECK(IDEBuildTaskfile(&tf, IDE_ADDRESS_LBA, 0, 0xfffffffeUL, 2,
    0xffffffffUL, 1, 0, 0) == IDE_ADDRESS_INVALID);
```

Also assert all mappings: `20->24`, `30->34`, `c4->29`, `c5->39`, `c8->25`, `ca->35`, `40->42`, and `70->0`. For block `0x12345678`, count 256, assert the 11-write LBA48 sequence is device; high features/count/LBA `12,00,00`; low features/count/LBA `78,56,34`.

- [ ] **Step 2: Run the test and verify RED**

- [ ] **Step 3: Implement bounds and taskfile construction**

Implement `IDEBuildTaskfile` with subtraction-based validation and this exact body after its declarations:

```c
if (!tf || !count || count > 256 || !capacity ||
    block >= capacity || count > capacity - block) return IDE_ADDRESS_INVALID;
memset(tf, 0, sizeof(*tf));
tf->sectorCount = (unsigned char)count;
tf->deviceHead = (unsigned char)(0xa0 | (drive ? 0x10 : 0));
if (mode == IDE_ADDRESS_CHS) {
    unsigned int track, cylinder, head;
    if (!heads || heads > 16 || !sectorsPerTrack) return IDE_ADDRESS_INVALID;
    track = block / sectorsPerTrack;
    cylinder = track / heads;
    head = track % heads;
    if (cylinder > 0xffff) return IDE_ADDRESS_INVALID;
    tf->lbaLow = (unsigned char)(block % sectorsPerTrack + 1);
    tf->lbaMid = (unsigned char)cylinder;
    tf->lbaHigh = (unsigned char)(cylinder >> 8);
    tf->deviceHead |= (unsigned char)head;
    return IDE_ADDRESS_OK;
}
if (mode != IDE_ADDRESS_LBA) return IDE_ADDRESS_INVALID;
tf->deviceHead |= 0x40;
if (block > 0x0fffffffUL || count - 1 > 0x0fffffffUL - block) {
    if (!lba48) return IDE_ADDRESS_UNSUPPORTED;
    tf->useLBA48 = 1;
    tf->sectorCountHigh = (unsigned char)(count >> 8);
    tf->lbaLowHigh = (unsigned char)(block >> 24);
} else tf->deviceHead |= (unsigned char)(block >> 24);
tf->lbaLow = (unsigned char)block;
tf->lbaMid = (unsigned char)(block >> 8);
tf->lbaHigh = (unsigned char)(block >> 16);
return IDE_ADDRESS_OK;
```

- [ ] **Step 4: Implement command mapping and write order**

Implement the mapping exactly:

```c
unsigned int IDEExtendedCommand(unsigned int command)
{
    switch (command) {
    case 0x20: return 0x24;
    case 0x30: return 0x34;
    case 0xc4: return 0x29;
    case 0xc5: return 0x39;
    case 0xc8: return 0x25;
    case 0xca: return 0x35;
    case 0x40: return 0x42;
    default: return 0;
    }
}
```

Implement `IDETaskfileWriteSequence` with a local `unsigned int n = 0` and this order:

```text
legacy: DEVICE, LBA_LOW, COUNT, LBA_MID, LBA_HIGH
LBA48:  DEVICE,
        FEATURES(high), COUNT(high), LBA_LOW(high), LBA_MID(high), LBA_HIGH(high),
        FEATURES(low),  COUNT(low),  LBA_LOW(low),  LBA_MID(low),  LBA_HIGH(low)
```

Do not add a legacy Features write; preserve the old path.

Use this implementation so the tested order and production order are identical:

```c
#define IDE_PUT(reg_, value_) do { \
    writes[n].reg = (reg_); writes[n].value = (value_); ++n; \
} while (0)
unsigned int IDETaskfileWriteSequence(const ideTaskfile_t *tf,
                                      ideTaskWrite_t writes[11])
{
    unsigned int n = 0;
    IDE_PUT(IDE_TASK_DEVICE, tf->deviceHead);
    if (tf->useLBA48) {
        IDE_PUT(IDE_TASK_FEATURES, tf->featuresHigh);
        IDE_PUT(IDE_TASK_COUNT, tf->sectorCountHigh);
        IDE_PUT(IDE_TASK_LBA_LOW, tf->lbaLowHigh);
        IDE_PUT(IDE_TASK_LBA_MID, tf->lbaMidHigh);
        IDE_PUT(IDE_TASK_LBA_HIGH, tf->lbaHighHigh);
        IDE_PUT(IDE_TASK_FEATURES, tf->features);
        IDE_PUT(IDE_TASK_COUNT, tf->sectorCount);
        IDE_PUT(IDE_TASK_LBA_LOW, tf->lbaLow);
    } else {
        IDE_PUT(IDE_TASK_LBA_LOW, tf->lbaLow);
        IDE_PUT(IDE_TASK_COUNT, tf->sectorCount);
    }
    IDE_PUT(IDE_TASK_LBA_MID, tf->lbaMid);
    IDE_PUT(IDE_TASK_LBA_HIGH, tf->lbaHigh);
    return n;
}
#undef IDE_PUT
```

- [ ] **Step 5: Run tests and commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IDEAddressing.* \
        src/drivers-i386/ide/drvEIDE/tests/ide_addressing_test.c
git commit -m "drvEIDE: build tested LBA taskfiles"
```

### Task 3: Integrate IDENTIFY state without ABI changes

**Files:** modify `ata_extern.h`, `IdeCnt.h`, `IdeCntInit.m`, `Makefile`, and `PB.project` under `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj`.

- [ ] **Step 1: Add a 512-byte compile assertion**

After `ideIdentifyInfo_t` under `DRIVER_PRIVATE`:

```c
typedef char ideIdentifyInfo_must_be_512_bytes[
    sizeof(ideIdentifyInfo_t) == 512 ? 1 : -1];
```

Build once before renaming fields; expected: assertion passes.

- [ ] **Step 2: Name words 100-103 and EXT opcodes**

Replace `reserved_92_126[35]` with exactly:

```c
unsigned short reserved_92_99[8];
unsigned short userAddressableSectors48[4];
unsigned short reserved_104_126[23];
```

Add exactly:

```c
#define IDE_CAP_LBA48_ENABLED   0x0400
#define IDE_READ_EXT            0x24
#define IDE_READ_DMA_EXT        0x25
#define IDE_READ_MULTIPLE_EXT   0x29
#define IDE_WRITE_EXT           0x34
#define IDE_WRITE_DMA_EXT       0x35
#define IDE_WRITE_MULTIPLE_EXT  0x39
#define IDE_READ_VERIFY_EXT     0x42
```

- [ ] **Step 3: Store parsed drive state**

Add private `driveInfo_t` fields:

```c
unsigned int addressableSectors;
BOOL lba48Supported;
```

Declare `ideCapacity_t capacity;` with the method locals. After successful IDENTIFY in `setATADriveCapabilities:withBIOSInfo:`:

```objc
IDEParseIdentifyCapacity((const unsigned short *)infoPtr, &capacity);
_drives[unit].lba48Supported = capacity.lba48Supported ? YES : NO;
_drives[unit].addressableSectors = capacity.sectors;
if (capacity.clamped)
    IOLog("%s: Drive %d: capacity limited to 0xffffffff sectors\n",
          [self name], unit);
```

For DriverKit versions newer than 410, use nonzero parsed LBA capacity instead of the old words 60-61 comparison. Preserve the existing `<= 410` byte-size compatibility branch. When IDENTIFY is unavailable or CHS is selected, initialize `addressableSectors` from the CHS sector product.

- [ ] **Step 4: Register the module**

Set `CFILES = VIATiming.c IDEAddressing.c`, add the header to `HFILES`, and add both files to the corresponding `PB.project` lists.

- [ ] **Step 5: Run standalone tests, build, and commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/ata_extern.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCnt.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntInit.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/Makefile \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/PB.project
git commit -m "drvEIDE: detect LBA48 disk capacity"
```

### Task 4: Issue PIO, multiple, and read-verify EXT commands

**Files:** modify `IdeCntCmds.h`, `IdeCntCmds.m`, and `tests/ide_addressing_test.c`.

- [ ] **Step 1: Add the legacy-sequence regression**

Assert a low-LBA taskfile returns five writes in historical order—device, LBA low, count, LBA mid, LBA high—with no Features entry. Run tests; expected: pass before driver integration.

- [ ] **Step 2: Add private controller bridges**

Declare and implement:

```objc
- (ide_return_t)buildTaskfile:(ideTaskfile_t *)taskfile
    block:(unsigned int)block count:(unsigned int)count drive:(unsigned int)drive;
- (void)writeTaskfile:(const ideTaskfile_t *)taskfile
    errorRegisters:(ideRegsVal_t *)errorRegisters;
```

The builder maps the drive's CHS/LBA mode and calls:

```objc
return IDEBuildTaskfile(taskfile,
    _drives[drive].addressMode == ADDRESS_MODE_CHS ?
        IDE_ADDRESS_CHS : IDE_ADDRESS_LBA,
    (unsigned char)drive, block, count,
    _drives[drive].addressableSectors,
    _drives[drive].lba48Supported ? 1 : 0,
    _drives[drive].ideInfo.heads,
    _drives[drive].ideInfo.sectors_per_trk);
```

The writer obtains `ideTaskWrite_t writes[11]`, loops over the returned count,
and maps each logical register with this switch before calling `outb(port,
writes[i].value)`:

```objc
switch (writes[i].reg) {
case IDE_TASK_DEVICE:   port = _ideRegsAddrs.drHead; break;
case IDE_TASK_FEATURES: port = _ideRegsAddrs.features; break;
case IDE_TASK_COUNT:    port = _ideRegsAddrs.sectCnt; break;
case IDE_TASK_LBA_LOW:  port = _ideRegsAddrs.sectNum; break;
case IDE_TASK_LBA_MID:  port = _ideRegsAddrs.cylLow; break;
case IDE_TASK_LBA_HIGH: port = _ideRegsAddrs.cylHigh; break;
default: return;
}
```

Before the loop, zero `errorRegisters` and copy `sectorCount`, `lbaLow`,
`lbaMid`, `lbaHigh`, and `deviceHead` into its corresponding legacy fields.
The writer never writes the command port. Import `IdeCntCmds.h` from
`IdeBMIDE.m` so the later BMIDE category sees these private selectors.

- [ ] **Step 3: Select EXT opcodes per retry**

After existing DMA/multiple requalification, build the taskfile and derive a local `command`:

```objc
command = ideIoReq->cmd;
if (taskfile.useLBA48 && (command = IDEExtendedCommand(command)) == 0) {
    ideIoReq->status = IDER_REJECT;
    break;
}
```

Never store the EXT opcode back into `ideIoReq->cmd`; retries must continue to recognize the base command.

- [ ] **Step 4: Replace repeated address writes**

Change internal address-bearing selectors to accept `const ideTaskfile_t *`, `ideRegsVal_t *`, and selected `command`. Replace only their address-register writes with:

```objc
[self writeTaskfile:taskfile errorRegisters:errorRegisters];
[self enableInterrupts];
outb(_ideRegsAddrs.command, command);
```

Use `command` for interrupt waits/logging. Preserve IDENTIFY's existing non-address setup and every data loop. Reject LBA48 SEEK because no EXT counterpart exists.

- [ ] **Step 5: Run tests/build and commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntCmds.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntCmds.m \
        src/drivers-i386/ide/drvEIDE/tests/ide_addressing_test.c
git commit -m "drvEIDE: issue LBA48 PIO commands"
```

### Task 5: Issue DMA EXT commands

**Files:** modify `IdeBMIDE.h`, `IdeBMIDE.m`, and `IdeCntCmds.m`.

- [ ] **Step 1: Verify pure DMA mappings above the boundary**

Build at block `0x10000000`; assert `useLBA48`, `c8->25`, and `ca->35`. Run the standalone suite.

- [ ] **Step 2: Pass selected state to DMA**

Change the private selector to:

```objc
- (ide_return_t)performDMA:(ideIoReq_t *)ideIoReq
    taskfile:(const ideTaskfile_t *)taskfile command:(unsigned int)command;
```

- [ ] **Step 3: Remove legacy reconstruction**

Delete DMA's `logToPhys:` call and address `outb`s. Accept legacy and EXT DMA commands:

```objc
if (command != IDE_READ_DMA && command != IDE_WRITE_DMA &&
    command != IDE_READ_DMA_EXT && command != IDE_WRITE_DMA_EXT)
    return IDER_REJECT;
read = (command == IDE_READ_DMA || command == IDE_READ_DMA_EXT);
```

Use `read` for `bmPrepareDMA`; use the shared writer; issue/wait on `command`. Do not change PRDs, bus-master start/stop, or status interpretation.

- [ ] **Step 4: Run tests/build and commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.h \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeBMIDE.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntCmds.m
git commit -m "drvEIDE: issue LBA48 DMA commands"
```

### Task 6: Harden 32-bit disk bounds and retries

**Files:** modify `IdeDiskInternal.m`, `IdeCntCmds.m`, and `ide_addressing_test.c`.

- [ ] **Step 1: Test the last advertised sector**

Assert block `0xfffffffe`, count one, capacity `0xffffffff` succeeds as LBA48; keep the count-two rejection test.

- [ ] **Step 2: Replace overflow-prone clipping**

In `deviceRwCommon`:

```objc
if (blocksReq == 0) return IO_R_INVALID;
if (deviceBlock >= dev_size) return IO_R_INVALID_ARG;
if (blocksReq > dev_size - deviceBlock)
    blocksReq = dev_size - deviceBlock;
```

- [ ] **Step 3: Keep segmentation unsigned and initialized**

Change `currentBlock`, `currentBlockCnt`, `blocksToGo`, and `blocksMoved` in `ideRwCommon:` to unsigned types. Put `bzero(&ideIoReq, sizeof(ideIoReq));` inside the segment loop before assigning its fields.

- [ ] **Step 4: Rebuild addressing after fallback**

Build the taskfile at the top of every retry after DMA/multiple requalification. On failure log base command, selected command, block, count, and LBA28/LBA48. Confirm recovery never truncates or mutates the logical address.

- [ ] **Step 5: Run tests/build and commit**

```sh
git add src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDiskInternal.m \
        src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeCntCmds.m \
        src/drivers-i386/ide/drvEIDE/tests/ide_addressing_test.c
git commit -m "drvEIDE: harden large-disk request bounds"
```

### Task 7: Full verification

**Files:** verification only unless a check exposes a defect.

- [ ] **Step 1: Run both standalone suites**

Run `ide_addressing_test`, then compile/run `VIATiming.c` with `via_timing_test.c` using the same `-ansi -pedantic -Wall -Werror` flags. Expected: both success lines.

- [ ] **Step 2: Build the complete driver**

Run the period-toolchain driver build. Expected: linked `EIDE_reloc`, no size-assertion, selector, or undefined-symbol failures.

- [ ] **Step 3: Verify ABI sizes**

Record `sizeof(ideIdentifyInfo_t) == 512`. Compare `sizeof(ideRegsVal_t)`, `sizeof(ideIoReq_t)`, and `sizeof(ideDriveInfo_t)` to baseline and reject any change.

- [ ] **Step 4: Boot the disposable small reference disk**

With `_ide_debug`, confirm baseline PIO/multiple/DMA selection, successful root I/O, and no EXT opcode below the boundary.

- [ ] **Step 5: Validate 16 GiB LBA28 I/O**

On a disposable sparse image, write/read distinct 512-byte patterns below and above 8 GiB and near the image end. Confirm byte equality and legacy opcodes.

- [ ] **Step 6: Validate the LBA28/LBA48 boundary**

On a disposable sparse image larger than 128 GiB, write/read patterns at `0x0ffffffe`, `0x0fffffff`, `0x10000000`, and `0x10000001`. Confirm legacy opcodes wholly below, EXT opcodes crossing/above, and exact byte equality.

- [ ] **Step 7: Validate bounds rejection**

Request the advertised sector count and a range crossing `0xffffffff`. Confirm rejection and no taskfile command write.

- [ ] **Step 8: Review and report**

```sh
git diff --check HEAD~6..HEAD
git status --short
```

Confirm only planned files changed. Report unit, build, small-disk, 16 GiB, and boundary-image results separately; state that capacity is capped at `0xffffffff` sectors and filesystems were not changed.
