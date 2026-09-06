# drvNVMe NVMe-to-SCSI Kernel Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an i386 DriverKit `IOSCSIController` that exposes QEMU NVMe namespace 1 as a bootable 512-byte SCSI disk at target 0/LUN 0.

**Architecture:** A standalone `drvNVMe` bundle owns PCI/MMIO, one depth-16 admin queue pair, one depth-16 I/O queue pair, a serialized CID-0 request worker, and a 128 KiB low-memory bounce arena. Dependency-light C helpers encode NVMe commands, parse completions and Identify data, translate the required SCSI CDBs, and make recovery decisions; the Objective-C controller connects those helpers to DriverKit and the existing `SCSIDisk` frontend.

**Tech Stack:** C89, Objective-C, NeXT/Apple DriverKit, `IOSCSIController`, i386 PCI, NVMe 1.4 mandatory commands, ProjectBuilder `pb_makefiles`/`gnumake`, standalone C tests, QEMU NVMe emulation, and disposable FFS disk images.

---

## Constraints and verification commands

- Start implementation in a dedicated worktree; the current checkout contains unrelated generated files and VM experiments.
- Match QEMU PCI ID `1b36:0010`, encoded in `Default.table` as `0x00101b36`, and verify PCI class tuple `01:08:02` in `+probe:`.
- Publish only NSID 1 as SCSI target 0/LUN 0.
- Allocate depth-16 admin and I/O queues but keep only CID 0 active.
- Keep all controller-visible addresses below 4 GiB and reject any allocation whose physical layout cannot be proven.
- Copy through one preallocated, page-aligned 128 KiB bounce arena; do not DMA directly into SCSI client memory.
- Accept only an active 512-byte LBA format with zero metadata and no enabled protection information.
- Cap visible capacity at `UINT_MAX` (`0xffffffff`) blocks and validate request ends using subtraction, not overflowing addition.
- Poll admin completions only during attach/recovery; use the legacy shared PCI interrupt for normal I/O.
- Leave existing kernel and SCSI sources unchanged unless an observed root-discovery failure forces a design revision.
- Never run integration I/O against the source image. Copy it into `vm/work/nvme-*` first.

Portable test command in the Rhapsody/Unix build environment:

```sh
cd src/drivers-i386/scsi/drvNVMe/tests
gnumake clean all check
```

Expected: `nvme_command_test`, `nvme_scsi_test`, and `nvme_state_test` each print `all tests passed`.

Driver build and staging command:

```sh
sh vm/build-i386-nvme.sh
```

Expected: `vm/install/drvNVMe/NVMe.config/Default.table` and `NVMe_reloc` exist, `file` identifies `NVMe_reloc` as i386 Mach-O, and the build log contains no new warnings from `NVMe*` files.

Integration launcher:

```sh
sh vm/run-qemu-nvme.sh vm/images/rhapsody-helper.raw vm/images/rhapsody-nvme-root.raw
```

Expected: QEMU starts with one `-device nvme,serial=RHAPSODY01,drive=nvme0`, the kernel logs one controller and NSID 1, and root mounts from `sd0a`.

## File map

- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeRegs.h`: NVMe register offsets, masks, opcodes, status values, and byte-array queue entry types.
- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.h/.c`: little-endian accessors; command builders; completion, CAP, Identify, doorbell, and PRP parsers/builders.
- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.h/.m`: dependency-light SCSI CDB parsing, synthetic replies, operation descriptions, and NVMe-status-to-sense mapping.
- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`: DriverKit-side queue, namespace, active-request, controller, and recovery state.
- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h/.m`: PCI probe, MMIO, DMA arena, attach, queues, worker, interrupt completion, SCSI exported methods, and reset.
- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/{Default.table,DriverInfo,PB.project,Makefile*}`: DriverKit bundle metadata and build definition.
- `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/{PB.project,Makefile*,Load_Commands.sect}`: kernel-server link definition.
- `src/drivers-i386/scsi/drvNVMe/{Makefile,Makefile.preamble,dpkg/control}`: aggregate/package build files.
- `src/drivers-i386/scsi/drvNVMe/tests/Makefile`: portable test compilation and `check` target.
- `src/drivers-i386/scsi/drvNVMe/tests/nvme_command_test.c`: register, queue entry, Identify, PRP, capacity, and completion tests.
- `src/drivers-i386/scsi/drvNVMe/tests/nvme_scsi_test.c`: CDB, synthetic response, range, and status/sense tests.
- `src/drivers-i386/scsi/drvNVMe/tests/nvme_state_test.c`: queue wrapping, phase, timeout, completion arbitration, and recovery state tests.
- `vm/build-i386-nvme.sh`: guest-side driver build and deterministic staging.
- `vm/run-qemu-nvme.sh`: host-side disposable NVMe-root launch command.
- `docs/drivers/drvNVMe-testing.md`: exact build, boot, boundary-I/O, rejection, and fault-injection procedure with results table.

### Task 1: Add tested NVMe layouts and command builders

**Files:**
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeRegs.h`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.h`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.c`
- Create: `src/drivers-i386/scsi/drvNVMe/tests/nvme_command_test.c`
- Create: `src/drivers-i386/scsi/drvNVMe/tests/Makefile`

- [ ] **Step 1: Write failing layout and admin-command tests**

Use byte arrays instead of compiler bitfields so host and historical compilers produce identical layouts. Test exact entry sizes and bytes for Identify Controller, Identify Namespace, Set Features / Number of Queues, Create I/O CQ, and Create I/O SQ:

```c
typedef struct { unsigned char bytes[64]; } NVMeSubmission;
typedef struct { unsigned char bytes[16]; } NVMeCompletion;

CHECK(sizeof(NVMeSubmission) == 64);
CHECK(sizeof(NVMeCompletion) == 16);
CHECK(NVMeBuildIdentify(&cmd, 0, 0, 1, 0x00123000U) == 0);
CHECK(cmd.bytes[0] == NVME_ADMIN_IDENTIFY);
CHECK(NVMeGetLE32(cmd.bytes + 4) == 0U);       /* NSID */
CHECK(NVMeGetLE32(cmd.bytes + 24) == 0x00123000U); /* PRP1 */
CHECK(NVMeGetLE32(cmd.bytes + 40) == 1U);      /* CNS controller */
```

The test Makefile builds with `-std=c89 -Wall -Wextra -Werror` where supported and compiles `NVMeCommand.c` directly from the lksproj directory.

- [ ] **Step 2: Run the command test and verify RED**

```sh
cd src/drivers-i386/scsi/drvNVMe/tests
gnumake nvme_command_test
```

Expected: compilation fails because `NVMeRegs.h`, `NVMeCommand.h`, and the named builder functions do not exist yet.

- [ ] **Step 3: Implement the exact dependency-free command API**

Define constants and these functions, zeroing every command before assigning defined fields:

```c
void NVMePutLE16(unsigned char *p, unsigned int value);
void NVMePutLE32(unsigned char *p, unsigned int value);
unsigned int NVMeGetLE16(const unsigned char *p);
unsigned int NVMeGetLE32(const unsigned char *p);

int NVMeBuildIdentify(NVMeSubmission *cmd, unsigned int cid,
                      unsigned int nsid, unsigned int cns,
                      unsigned int dataPA);
int NVMeBuildSetNumberQueues(NVMeSubmission *cmd, unsigned int cid);
int NVMeBuildCreateIOCQ(NVMeSubmission *cmd, unsigned int cid,
                        unsigned int queuePA, unsigned int irqVector);
int NVMeBuildCreateIOSQ(NVMeSubmission *cmd, unsigned int cid,
                        unsigned int queuePA);
```

Use queue ID 1 and queue size field 15 for both I/O queues. Set physically contiguous and interrupt-enabled bits on Create CQ; bind Create SQ to CQ 1 with medium priority. Reject CID values above 15 and non-page-aligned queue/data addresses.

- [ ] **Step 4: Verify GREEN and commit**

```sh
gnumake clean all check
git add src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeRegs.h \
        src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.* \
        src/drivers-i386/scsi/drvNVMe/tests
git commit -m "drvNVMe: add tested command layouts"
```

Expected: `nvme_command_test: all tests passed`.

### Task 2: Complete I/O, PRP, Identify, and completion helpers

**Files:**
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeRegs.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_command_test.c`

- [ ] **Step 1: Add failing tests for I/O and boundary parsing**

Cover Read, Write, Flush, 1/2/3/32-page PRP layouts, 128 KiB, overlarge length, non-page-aligned PRP-list address, CAP timeout/page-size/doorbell parsing, completion phase/status/CID/SQ fields, Identify Controller strings/MDTS, and Identify Namespace formats:

```c
CHECK(NVMeBuildRW(&cmd, 0, 1, 0xffffffffU, 256, 0,
                  0x00200000U, 0x00100000U) == 0);
CHECK(cmd.bytes[0] == NVME_NVM_READ);
CHECK(NVMeGetLE32(cmd.bytes + 40) == 0xffffffffU);
CHECK(NVMeGetLE32(cmd.bytes + 44) == 0U);
CHECK((NVMeGetLE32(cmd.bytes + 48) & 0xffffU) == 255U);
CHECK(NVMeBuildPRPs(0x00200000U, 0x00100000U, 131072U,
                    prpList, 32, &prp1, &prp2) == 0);
CHECK(prp1 == 0x00200000U && prp2 == 0x00100000U);
CHECK(prpList[0] == 0x00201000U && prpList[30] == 0x0021f000U);
```

Include namespace cases for inactive `NSZE=0`, FLBAS index outside NLBAF, `LBADS=12`, nonzero metadata size, enabled DPS, and a native size whose upper word forces visible clamping.

- [ ] **Step 2: Run the suite and verify RED**

Expected: undefined `NVMeBuildRW`, `NVMeBuildFlush`, `NVMeBuildPRPs`, `NVMeParseCAP`, `NVMeParseCompletion`, `NVMeParseIdentifyController`, and `NVMeParseIdentifyNamespace`.

- [ ] **Step 3: Implement the typed parser/builder contracts**

Expose exact result types:

```c
typedef struct {
    unsigned int timeoutMs, doorbellStride, mqes;
    unsigned char supportsNVM, supports4K;
} NVMeCapabilities;

typedef struct {
    unsigned int result, sqHead, sqID, cid, status;
    unsigned char phase;
} NVMeCompletionInfo;

typedef struct {
    unsigned int nativeBlocksLow, nativeBlocksHigh, visibleBlocks;
    unsigned int logicalBlockSize;
    unsigned char clamped, active, writeProtected;
} NVMeNamespaceInfo;

typedef struct {
    char model[41], serial[21], firmware[9];
    unsigned int mdtsBytes;
    unsigned char volatileWriteCache;
} NVMeControllerInfo;

int NVMeBuildRW(NVMeSubmission *cmd, unsigned int cid, unsigned int nsid,
                unsigned int lba, unsigned int blocks, unsigned char write,
                unsigned int prp1, unsigned int prp2);
int NVMeBuildFlush(NVMeSubmission *cmd, unsigned int cid, unsigned int nsid);
int NVMeBuildPRPs(unsigned int dataPA, unsigned int listPA,
                  unsigned int length, unsigned int *list,
                  unsigned int listEntries, unsigned int *prp1,
                  unsigned int *prp2);
int NVMeParseCAP(unsigned int capLow, unsigned int capHigh,
                 NVMeCapabilities *out);
void NVMeParseCompletion(const NVMeCompletion *entry,
                         NVMeCompletionInfo *out);
int NVMeParseIdentifyController(const unsigned char data[4096],
                                NVMeControllerInfo *out);
int NVMeParseIdentifyNamespace(const unsigned char data[4096],
                               NVMeNamespaceInfo *out);
```

Calculate `timeoutMs = CAP.TO * 500`, clamped to named 500 ms and 30 s bounds. Require MPSMIN <= 0 <= MPSMAX, CSS bit 0, MQES >= 15, and a doorbell stride whose computed queue-1 doorbells fit BAR0. Parse 64-bit capacities as two 32-bit halves; set `visibleBlocks=0xffffffffU` whenever the high half is nonzero or the low half exceeds that ceiling.

- [ ] **Step 4: Verify GREEN and commit**

```sh
gnumake clean all check
git add src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeRegs.h \
        src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.* \
        src/drivers-i386/scsi/drvNVMe/tests/nvme_command_test.c
git commit -m "drvNVMe: build I/O and PRP commands"
```

### Task 3: Add tested SCSI translation and sense mapping

**Files:**
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.h`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.m`
- Create: `src/drivers-i386/scsi/drvNVMe/tests/nvme_scsi_test.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/Makefile`

- [ ] **Step 1: Write failing CDB and synthetic-response tests**

Compile `NVMeSCSI.m` as C in the portable test. Cover TEST UNIT READY, INQUIRY allocation truncation, REQUEST SENSE clearing, READ CAPACITY big-endian fields, MODE SENSE(6), START STOP, PREVENT/ALLOW, READ/WRITE(6), READ/WRITE(10), SYNCHRONIZE CACHE(10), invalid targets/LUNs, direction mismatch, reserved bits, last-LBA success, one-block overflow, and all status-to-sense categories.

```c
unsigned char read6[6] = { 0x08, 0x1f, 0xff, 0xff, 0x00, 0x00 };
CHECK(NVMeSCSIParse(read6, 6, 1, 131072, 0x00200000U, &op, &sense) == 0);
CHECK(op.kind == NVME_SCSI_READ);
CHECK(op.lba == 0x001fffffU && op.blocks == 256U);
CHECK(op.bytes == 131072U);
CHECK(NVMeSCSIMapStatus(NVME_SCT_GENERIC, NVME_SC_LBA_RANGE,
                        &sense) == NVME_SCSI_CHECK);
CHECK(sense.key == NVME_SENSE_ILLEGAL_REQUEST);
```

- [ ] **Step 2: Run the SCSI test and verify RED**

Expected: compilation fails because the translator API is undefined.

- [ ] **Step 3: Implement the dependency-light translator**

Define transport-neutral outputs so the `.m` file does not import DriverKit in its tested section:

```c
typedef enum {
    NVME_SCSI_SOFTWARE, NVME_SCSI_READ, NVME_SCSI_WRITE, NVME_SCSI_FLUSH
} NVMeSCSIOperationKind;

typedef struct {
    NVMeSCSIOperationKind kind;
    unsigned int lba, blocks, bytes, replyLength;
    unsigned char reply[96];
} NVMeSCSIOperation;

typedef struct { unsigned char key, asc, ascq; } NVMeSense;

typedef enum { NVME_SCSI_GOOD, NVME_SCSI_CHECK, NVME_SCSI_TRANSPORT_ERROR }
    NVMeSCSIResult;

#define NVME_SENSE_NOT_READY        0x02
#define NVME_SENSE_MEDIUM_ERROR     0x03
#define NVME_SENSE_HARDWARE_ERROR   0x04
#define NVME_SENSE_ILLEGAL_REQUEST  0x05
#define NVME_SENSE_DATA_PROTECT     0x07
#define NVME_SENSE_ABORTED_COMMAND  0x0b

int NVMeSCSIParse(const unsigned char *cdb, unsigned int cdbLength,
                  unsigned char readDirection, unsigned int maxTransfer,
                  unsigned int visibleBlocks, NVMeSCSIOperation *out,
                  NVMeSense *sense);
int NVMeSCSIMapStatus(unsigned int sct, unsigned int sc, NVMeSense *sense);
unsigned int NVMeSCSIBuildInquiry(unsigned char *dst, unsigned int limit,
                                  const NVMeControllerInfo *controller);
unsigned int NVMeSCSIBuildReadCapacity(unsigned char *dst, unsigned int limit,
                                       unsigned int visibleBlocks);
unsigned int NVMeSCSIBuildSense(unsigned char *dst, unsigned int limit,
                                const NVMeSense *sense);
```

Use subtraction for range validation: reject when `lba >= visibleBlocks` or `blocks > visibleBlocks - lba`. Return ILLEGAL REQUEST for unsupported opcodes/fields, NOT READY for offline namespace, DATA PROTECT for write protection, MEDIUM ERROR for media failures, HARDWARE ERROR for internal/data-transfer errors, and ABORTED COMMAND for abort statuses.

- [ ] **Step 4: Verify GREEN and commit**

```sh
gnumake clean all check
git add src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.* \
        src/drivers-i386/scsi/drvNVMe/tests
git commit -m "drvNVMe: translate SCSI disk commands"
```

### Task 4: Scaffold a loadable DriverKit bundle

**Files:**
- Create: `src/drivers-i386/scsi/drvNVMe/Makefile`
- Create: `src/drivers-i386/scsi/drvNVMe/Makefile.preamble`
- Create: `src/drivers-i386/scsi/drvNVMe/dpkg/control`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/Makefile`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/Makefile.preamble`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/Makefile.postamble`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/PB.project`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/Default.table`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/DriverInfo`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/English.lproj/Localizable.strings`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/Makefile`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/Makefile.preamble`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/Makefile.postamble`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/PB.project`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/Load_Commands.sect`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h`
- Create: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.m`
- Create: `vm/build-i386-nvme.sh`

- [ ] **Step 1: Reproduce the period SCSI driver build shape**

Use `drvBusLogic` as the structural reference, changing only names and source lists. The kernel-server Makefile must declare:

```make
NAME = NVMe
PROJECT_TYPE = Kernel Server
CLASSES = NVMeController.m NVMeSCSI.m
CFILES = NVMeCommand.c
HFILES = NVMeRegs.h NVMeCommand.h NVMeSCSI.h NVMeTypes.h NVMeController.h
OTHER_CFLAGS = -g -Wall -Wno-format
```

Keep the standard `__TEXT` load command shape and install the bundle under `$(NEXT_ROOT)/private/Drivers`.

- [ ] **Step 2: Add exact PCI metadata**

Write `Default.table` with:

```text
"Title" = "QEMU NVMe Controller";
"Bus Type" = "PCI";
"Family" = "SCSI";
"Auto Detect IDs" = "0x00101b36";
"Instance" = "0";
"Driver Name" = "NVMeSCSIController";
"DMA Channels" = "";
"IRQ Levels" = "";
"I/O Ports" = "";
"Memory Maps" = "";
"Share IRQ Levels" = "YES";
"Boot Driver";
```

The `dpkg/control` package name is `drvnvme` with the same build dependencies as `drvbuslogic`.

- [ ] **Step 3: Add a minimal controller class and verify the first build**

Declare the exported DriverKit surface:

```objc
@interface NVMeSCSIController : IOSCSIController
+ (BOOL)probe:deviceDescription;
- initFromDeviceDescription:deviceDescription;
- (unsigned)maxTransfer;
- (int)numberOfTargets;
- (sc_status_t)executeRequest:(IOSCSIRequest *)request
                         buffer:(void *)buffer
                         client:(vm_task_t)client;
- (sc_status_t)resetSCSIBus;
- (void)interruptOccurred;
@end
```

Return 128 KiB from `maxTransfer`, 1 from `numberOfTargets`, and `SR_IOST_INVALID` from request/reset methods until later tasks. Build before adding hardware access.

- [ ] **Step 4: Add the first fail-fast build/staging entry point**

Base `vm/build-i386-nvme.sh` on the environment and artifact-staging shape in
`vm/build-i386-kernel-eide.sh`, but build only this bundle:

```sh
SRC=/build/source/src/drivers-i386/scsi/drvNVMe
OUT=/build/out/i386
DST=/tmp/nvme-dst
test -d "$SRC" || exit 1
cd "$SRC" || exit 1
gnumake clean all install DSTROOT="$DST" || exit 1
test -f NVMe.config/NVMe_reloc || exit 1
```

Stage the full `NVMe.config` at `$OUT/drvNVMe/NVMe.config` and preserve the
build log. Then build and inspect:

```sh
cd src/drivers-i386/scsi/drvNVMe
gnumake clean all DSTROOT=/tmp/nvme-dst
file NVMe.config/NVMe_reloc
nm -u NVMe.config/NVMe_reloc
git add src/drivers-i386/scsi/drvNVMe
git add vm/build-i386-nvme.sh
git commit -m "drvNVMe: scaffold DriverKit bundle"
```

Expected: an i386 relocatable kernel server with DriverKit/Objective-C unresolved imports only.

### Task 5: Attach PCI, map BAR0, and initialize the admin queue

**Files:**
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.m`
- Create: `src/drivers-i386/scsi/drvNVMe/tests/nvme_state_test.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/Makefile`
- Create: `vm/run-qemu-nvme.sh`

- [ ] **Step 1: Write failing initialization-state tests**

Test `EN=1,RDY=1` requires disable/wait before programming queues, `CSTS.CFS=1` fails immediately, and the pure state decision never permits queue programming while RDY is set:

```c
typedef enum {
    NVME_INIT_FAIL, NVME_INIT_DISABLE, NVME_INIT_WAIT_DISABLED,
    NVME_INIT_PROGRAM_QUEUES, NVME_INIT_ENABLE, NVME_INIT_WAIT_READY,
    NVME_INIT_READY
} NVMeInitAction;

CHECK(NVMeNextInitAction(NVME_CC_EN, NVME_CSTS_RDY, 0) ==
      NVME_INIT_DISABLE);
CHECK(NVMeNextInitAction(0, NVME_CSTS_RDY, 0) ==
      NVME_INIT_WAIT_DISABLED);
CHECK(NVMeNextInitAction(0, NVME_CSTS_CFS, 0) == NVME_INIT_FAIL);
```

- [ ] **Step 2: Implement strict PCI probing**

In `+probe:`, use `getPCIConfigSpace:withDeviceDescription:`; require vendor/device `1b36:0010`, class `0x01`, subclass `0x08`, programming interface `0x02`, BAR0 memory space, and a valid interrupt line. Enable PCI command memory and bus-master bits, derive a memory range from BAR0, assign it to the device description, instantiate the controller, and call `registerDevice` only after complete attach.

- [ ] **Step 3: Allocate and validate one low-memory arena**

Use `IOMallocLow` for an arena sized and overallocated to align these subranges:

```c
#define NVME_PAGE_SIZE       4096U
#define NVME_QUEUE_DEPTH     16U
#define NVME_BOUNCE_SIZE     (128U * 1024U)
#define NVME_ADMIN_SQ_SIZE   (NVME_QUEUE_DEPTH * 64U)
#define NVME_ADMIN_CQ_SIZE   (NVME_QUEUE_DEPTH * 16U)
#define NVME_IO_SQ_SIZE      (NVME_QUEUE_DEPTH * 64U)
#define NVME_IO_CQ_SIZE      (NVME_QUEUE_DEPTH * 16U)
```

Place each queue, PRP list, Identify buffer, and bounce buffer at a page boundary. Call `IOPhysicalFromVirtual(IOVmTaskSelf(), ...)` for every page, require sequential physical addresses within each contiguous region, and retain the original allocation base/size for exact `IOFreeLow` cleanup.

- [ ] **Step 4: Map MMIO and enable the admin queue**

Implement `NVMeNextInitAction` in `NVMeCommand.c`. Use `mapMemoryRange:0:to:findSpace:cache:` with cache disabled, validate CAP/VS through `NVMeParseCAP`, disable an active controller, zero the admin queues, program AQA/ASQ/ACQ, set CC.CSS=0, MPS=0, AMS=0, IOSQES=6, IOCQES=4, and wait for RDY. Use `IOSleep(1)` in deadline loops and fail immediately on CFS.

- [ ] **Step 5: Verify tests/build, inspect attach logs, and commit**

Create the first launcher before using it. Require helper and root image paths,
copy both to a timestamped `vm/work/nvme-*` directory, and add exactly one QEMU
NVMe function:

```sh
test $# -eq 2 || { echo "usage: $0 helper.raw nvme-root.raw" >&2; exit 2; }
-drive file="$work/helper.raw",if=ide,format=raw \
-drive file="$work/root.raw",if=none,id=nvme0,format=raw \
-device nvme,serial=RHAPSODY01,drive=nvme0
```

Reuse the known-working i386 machine, CPU, display, and serial arguments from
the repository VM workflow. Capture serial output in the new work directory.

```sh
gnumake -C src/drivers-i386/scsi/drvNVMe/tests clean all check
sh vm/build-i386-nvme.sh
sh vm/run-qemu-nvme.sh vm/images/rhapsody-helper.raw vm/images/rhapsody-nvme-root.raw
git add src/drivers-i386/scsi/drvNVMe
git add vm/run-qemu-nvme.sh
git commit -m "drvNVMe: initialize admin queue"
```

Expected QEMU log stops after `drvNVMe: admin queue ready` without registering a SCSI disk yet.

### Task 6: Identify controller/namespace and create the I/O queues

**Files:**
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.m`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_command_test.c`

- [ ] **Step 1: Add failing admin-queue phase and identity tests**

Test submission tail wrap, CQ phase wrap, wrong CID/SQ rejection, Set Features returning fewer than one queue, trimmed model/serial/firmware strings, inactive namespace, 4 Kn, nonzero metadata, DPS enabled, capacity zero, and >2 TiB clamping.

- [ ] **Step 2: Add the polled admin submission primitive**

Implement a single CID-0 function with no allocation:

```objc
- (int)submitAdmin:(const NVMeSubmission *)command
             result:(NVMeCompletionInfo *)completion
          timeoutMs:(unsigned int)timeoutMs;
```

Copy the command to `adminSQ[tail]`, execute the I/O ordering primitive, advance/ring the admin SQ tail, poll `adminCQ[head]` until phase matches, validate SQ ID 0 and CID 0, advance/ring the CQ head, toggle phase on wrap, and return decoded status.

- [ ] **Step 3: Identify and validate the fixed namespace**

Issue Identify Controller into the 4 KiB Identify buffer, Set Features / Number of Queues, then Identify NSID 1. Require at least one returned SQ/CQ pair and `NVMeParseIdentifyNamespace` success. Store native/visible capacity and identity strings; log exactly one truncation warning when clamped.

- [ ] **Step 4: Create queue pair 1 and register SCSI**

Zero I/O queues, set expected CQ phase to 1, issue Create I/O CQ then Create I/O SQ, and enable the legacy interrupt only after both succeed. Reserve no synthetic host target because the controller reports only the real target 0. Call `registerDevice` last.

- [ ] **Step 5: Build/probe and commit**

```sh
gnumake -C src/drivers-i386/scsi/drvNVMe/tests clean all check
sh vm/build-i386-nvme.sh
git add src/drivers-i386/scsi/drvNVMe
git commit -m "drvNVMe: identify namespace and I/O queues"
```

Expected log includes model, serial, NSID 1, 512-byte blocks, visible capacity, and SCSI target registration.

### Task 7: Implement serialized SCSI software commands and data I/O

**Files:**
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.m`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.m`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_scsi_test.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_state_test.c`

- [ ] **Step 1: Add failing request lifecycle tests**

Model `PENDING -> ACTIVE -> COMPLETE` and assert that a second request remains queued, software commands never ring an I/O doorbell, failed client copy never submits, zero-length READ/WRITE(10) succeeds without submission, and every exit initializes `driverStatus`, `scsiStatus`, `bytesTransferred`, `totalTime`, and `latentTime`.

- [ ] **Step 2: Define the one-request command buffer**

```c
typedef enum { NVME_REQ_PENDING, NVME_REQ_ACTIVE, NVME_REQ_COMPLETE }
    NVMeRequestState;
typedef struct {
    queue_chain_t link;
    IOSCSIRequest *scsi;
    void *buffer;
    vm_task_t client;
    id completionLock;
    NVMeRequestState state;
    unsigned int generation;
} NVMeCommandBuffer;

int NVMeRequestTryActivate(NVMeRequestState *state);
int NVMeRequestTryComplete(NVMeRequestState *state,
                           unsigned int generation,
                           unsigned int expectedGeneration);
```

Implement the two pure transition helpers in `NVMeSCSI.m` and exercise them from
`nvme_state_test.c`. Follow the `drvBusLogic` `executeCmdBuf:` ownership shape:
create an `NXConditionLock`, enqueue under `NXLock`, wake the I/O thread with
its interrupt/message port, wait for COMPLETE, then free only the per-call lock.
The controller owns the active pointer and preallocated hardware state.

- [ ] **Step 3: Complete software CDBs without hardware access**

In the worker, call `NVMeSCSIParse`; use `IOSimpleMemoryDescriptor` with the supplied `client` task to copy INQUIRY, REQUEST SENSE, READ CAPACITY, and MODE SENSE replies. TEST UNIT READY reflects online state. START STOP and PREVENT/ALLOW validate then return GOOD. Cache CHECK CONDITION sense and clear it after REQUEST SENSE.

- [ ] **Step 4: Submit Read, Write, and Flush**

For Write, copy exactly `op.bytes` from the client into the bounce buffer before building PRPs. For Read, copy back only after a successful NVMe completion. Build NVM Read/Write with NSID 1 and CID 0; build Flush with no PRPs. Set defaults to 10 seconds for Read/Write and 30 seconds for Flush when `timeoutLength <= 0`.

- [ ] **Step 5: Verify raw SCSI discovery and commit**

```sh
gnumake -C src/drivers-i386/scsi/drvNVMe/tests clean all check
sh vm/build-i386-nvme.sh
git add src/drivers-i386/scsi/drvNVMe
git commit -m "drvNVMe: execute serialized SCSI I/O"
```

Expected: `SCSIDisk` issues INQUIRY and READ CAPACITY successfully, publishes `sd0`, and a raw read of the first sector matches the backing image.

### Task 8: Complete interrupt-driven completion and status mapping

**Files:**
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.m`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeSCSI.m`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_command_test.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_scsi_test.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_state_test.c`

- [ ] **Step 1: Write failing completion arbitration tests**

Cover shared interrupt/no matching phase, correct CID 0, wrong CID, wrong SQ ID, impossible SQ head, phase toggle on CQ wrap, late completion from an old generation, exact byte reporting, read-copy suppression on errors, and each generic/media/path status mapping.

- [ ] **Step 2: Implement the bounded interrupt handler**

`-interruptOccurred` checks at most 16 entries, but with one active command accepts exactly one matching completion. For each new entry: snapshot 16 bytes before writing the CQ doorbell, parse it, advance head modulo 16, toggle phase at wrap, ring CQ1 head, and signal the worker. A phase mismatch exits immediately. Wrong CID/SQ/head records a corrupt-completion result and triggers recovery rather than completing GOOD.

- [ ] **Step 3: Finish SCSI completion fields**

On success set:

```c
request->driverStatus = SR_IOST_GOOD;
request->scsiStatus = STAT_GOOD;
request->bytesTransferred = operation.bytes;
request->latentTime = 0;
```

On mapped NVMe error set CHECK CONDITION, populate `senseData` in fixed format, set transferred bytes to zero, and preserve the same sense for REQUEST SENSE. Record `totalTime` from timestamps around worker execution.

- [ ] **Step 4: Verify interrupt I/O and commit**

```sh
gnumake -C src/drivers-i386/scsi/drvNVMe/tests clean all check
sh vm/build-i386-nvme.sh
git add src/drivers-i386/scsi/drvNVMe
git commit -m "drvNVMe: complete interrupt-driven I/O"
```

Expected: repeated raw reads/writes complete by interrupt, the legacy IRQ deasserts after CQ consumption, and shared spurious interrupts do not wake an unrelated request.

### Task 9: Add one-shot timeout and controller recovery

**Files:**
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeTypes.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeController.m`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.h`
- Modify: `src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj/NVMeCommand.c`
- Modify: `src/drivers-i386/scsi/drvNVMe/tests/nvme_state_test.c`

- [ ] **Step 1: Write failing timeout/recovery tests**

Test a completion/timeout race completes once, CFS forces reset, ordinary command status does not reset, malformed CQ forces reset, queued work cannot start during reset, identity changes leave offline, failed RDY clear leaves offline, successful rebuild increments generation, and stale completions cannot satisfy the new generation.

- [ ] **Step 2: Schedule and arbitrate timeouts**

Schedule one callback with `IOScheduleFunc` at submission and cancel it with `IOUnscheduleFunc` after accepted completion. Under the controller lock, allow only the winner to change ACTIVE to COMPLETE/RECOVERING; the loser observes the changed generation/state and exits without touching the request.

- [ ] **Step 3: Implement one bounded recovery transaction**

Expose one serialized method:

```objc
typedef enum {
    NVME_RECOVERY_TIMEOUT, NVME_RECOVERY_FATAL,
    NVME_RECOVERY_BAD_COMPLETION, NVME_RECOVERY_EXPLICIT_RESET
} NVMeRecoveryReason;

- (BOOL)recoverControllerForReason:(NVMeRecoveryReason)reason;
```

Mask interrupts, reject new work, fail the active request once, clear CC.EN and wait for RDY=0, clear all queues/PRPs and software indices, rebuild the admin queue, repeat Identify Controller/NSID 1, compare identity/capacity/LBA format/metadata/protection fields, recreate CQ1 then SQ1, increment generation, and resume. Any failed step sets `controllerOffline=YES`; no automatic second recovery starts.

- [ ] **Step 4: Route `resetSCSIBus` through recovery**

Return `SR_IOST_GOOD` only when the recovery transaction succeeds. If the controller has already entered the terminal offline state, return `SR_IOST_CHKSV` with NOT READY sense without a new hardware attempt; unload/reboot is required.

- [ ] **Step 5: Verify tests/fault build and commit**

```sh
gnumake -C src/drivers-i386/scsi/drvNVMe/tests clean all check
sh vm/build-i386-nvme.sh NVME_TEST_FAULT=drop-completion
git add src/drivers-i386/scsi/drvNVMe
git commit -m "drvNVMe: recover timed out controller"
```

Expected: the injected request fails once, one reset appears in the log, and later I/O succeeds. With `NVME_TEST_FAULT=fail-recovery`, later commands return NOT READY without repeated resets.

### Task 10: Harden the build/launch workflow and document it

**Files:**
- Modify: `vm/build-i386-nvme.sh`
- Modify: `vm/run-qemu-nvme.sh`
- Create: `docs/drivers/drvNVMe-testing.md`

- [ ] **Step 1: Harden the guest build script**

Retain the fixed variables and explicit artifact checks introduced in Task 4. Add log capture, full `NVMe.config` staging, and failures for a new `NVMe.*warning:` line, an implicit declaration, or an unresolved driver-local symbol:

```sh
SRC=/build/source/src/drivers-i386/scsi/drvNVMe
OUT=/build/out/i386
DST=/tmp/nvme-dst
test -d "$SRC" || exit 1
cd "$SRC" || exit 1
gnumake clean all install DSTROOT="$DST" || exit 1
test -f NVMe.config/NVMe_reloc || exit 1
```

Do not rebuild the kernel because the approved design adds no kernel source.

- [ ] **Step 2: Harden the disposable QEMU launcher**

Require two input paths, create `vm/work/nvme-<timestamp>/`, copy both images, and launch without modifying the originals:

```sh
-drive file="$work/helper.raw",if=ide,format=raw \
-drive file="$work/root.raw",if=none,id=nvme0,format=raw \
-device nvme,serial=RHAPSODY01,drive=nvme0
```

Preserve the repository's working i386 machine/CPU/serial options; add `-no-reboot` and write the serial log into the work directory. Do not add a second namespace or MSI configuration.

- [ ] **Step 3: Document exact installation and root selection**

In `drvNVMe-testing.md`, record where `NVMe.config` is copied in the guest, how it is enabled as a boot driver, the exact kernel root argument selecting `sd0a`, how the helper disk remains non-root, and commands for `disk`, `mount`, `dd`, `cmp`, `sync`, and checksum verification available in the Rhapsody guest.

- [ ] **Step 4: Dry-run, shell-check, and commit**

```sh
sh -n vm/build-i386-nvme.sh
sh -n vm/run-qemu-nvme.sh
sh vm/run-qemu-nvme.sh 2>&1 | grep '^usage:'
git add vm/build-i386-nvme.sh vm/run-qemu-nvme.sh docs/drivers/drvNVMe-testing.md
git commit -m "drvNVMe: add reproducible QEMU workflow"
```

### Task 11: Prove root mount, data integrity, limits, and rejection behavior

**Files:**
- Modify: `docs/drivers/drvNVMe-testing.md`
- Modify only when a test exposes a defect: files under `src/drivers-i386/scsi/drvNVMe/`

- [ ] **Step 1: Run the full portable and build suites**

```sh
gnumake -C src/drivers-i386/scsi/drvNVMe/tests clean all check
sh vm/build-i386-nvme.sh
```

Expected: all three portable tests pass, the bundle builds/stages, and the new source has no warnings, implicit declarations, packed-layout errors, pointer truncation, or driver-local unresolved symbols.

- [ ] **Step 2: Boot with an NVMe root**

Launch disposable helper/root copies. Confirm PCI match `1b36:0010`, class `01:08:02`, admin/I/O queue readiness, NSID 1, 512-byte blocks, target 0/LUN 0, `sd0` publication, and root mounted from `sd0a`. Record the exact serial-log lines in the testing document.

- [ ] **Step 3: Verify persistent read/write correctness**

Create deterministic payloads, write through the mounted filesystem, sync, reboot the disposable VM, remount, and compare checksums. Run raw aligned transfers of 512 bytes, 4096 bytes, a page-crossing length, and 131072 bytes, then compare every output to the source payload.

- [ ] **Step 4: Verify visible boundaries and truncation**

Use a sparse namespace above 2 TiB. Confirm one truncation warning, READ CAPACITY last LBA `0xfffffffe` for `0xffffffff` visible blocks, successful access to the final visible block, and CHECK CONDITION/ILLEGAL REQUEST for any request extending beyond it.

- [ ] **Step 5: Verify namespace rejection matrix**

Run disposable QEMU variants for inactive/absent NSID 1, native 4 Kn, nonzero metadata, and enabled protection information. Each must log its specific reason, avoid `sd0` publication, and leave the controller stable without a reset loop.

- [ ] **Step 6: Verify timeout/fatal recovery**

Run `drop-completion`, forced CFS, and `fail-recovery` test builds. Record that successful recovery performs exactly one reset and restores I/O, while forced recovery failure leaves a stable NOT READY target.

- [ ] **Step 7: Audit scope and commit the evidence**

```sh
git diff --check
rg -n 'MSI|MSI-X|NSID|CID|IOMalloc|IOFree|IOScheduleFunc|IOUnscheduleFunc' \
  src/drivers-i386/scsi/drvNVMe
git status --short
git add docs/drivers/drvNVMe-testing.md
git commit -m "drvNVMe: document boot verification"
```

Confirm only NSID 1 and CID 0 are active, every allocation has a size-matched cleanup, every scheduled timeout has a cancellation/winner path, no existing kernel/SCSI file changed, and all emulator images used were disposable copies.

- [ ] **Step 8: Request code review and report acceptance evidence**

Use `superpowers:requesting-code-review`. The review must check the implementation against every success criterion in the approved design and include portable test output, build artifact paths, root-mount evidence, checksum results, rejection logs, and recovery logs.
