# PPC MacRISC Platform Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot later New World PowerPC G3 and G4 Macs to a userspace shell through a validated, capability-driven MacRISC platform path while preserving existing Yosemite and Sawtooth behavior.

**Architecture:** Pure C89 helpers decode bounded Open Firmware properties and build a fixed-size `PEMacRISCPlatform` descriptor. A thin DeviceTree adapter fills that descriptor, and a new `macrisc` family consumes it for I/O publication, firmware clock/cache data, DBDMA, BAT, MPIC, and optional PMU/VIA cascade setup. Existing exact model paths remain unchanged; PowerPC 970/U3 machines fail before MMIO.

**Tech Stack:** ANSI C89, Objective-C DriverKit compatibility call sites, Darwin DeviceTree APIs, PowerPC BAT/OpenPIC interfaces, Project Builder makefiles, host C tests, Rhapsody PPC kernel build, physical Open Firmware hardware.

---

## File structure

- `powermac/macrisc_discovery.{c,h}`: allocation-free property decoding, classification, descriptor construction, validation, resource publication, and clock conversion.
- `powermac/macrisc_dt.{c,h}`: thin DeviceTree traversal, global validated descriptor, and bounded diagnostics.
- `powermac/families/macrisc.{c,h}`: `powermac_init_t`, runtime MPIC/DBDMA tables, BAT mappings, and CPU-0-only policy.
- `powermac/chips/mpic.{c,h}`: explicit feature-control, cascade, destination, and source-count policy shared by legacy and MacRISC families.
- `tests/macrisc_discovery_test.c`: string lists, cells, ranges, CPU/chipset classification, model catalog, and malformed inputs.
- `tests/macrisc_platform_test.c`: fake DeviceTree capture, optional resources, DBDMA, clocks, CPU publication, PMU topology, and table construction.
- Existing `identify_machine.c`, shared PowerMac headers, PMU sources, and Core99 NVRAM call sites receive only the integration changes named below.

## Invariants for every task

- Host code compiles with `-std=c89 -pedantic -Wall -Wextra -Werror`.
- Early boot performs no allocation and never modifies firmware property bytes.
- A model prefix alone never accepts a machine.
- `PowerMac3,1`, `PowerMac3,2`, `PowerMac3,3`, `PowerMac5,1`, and `PowerBook2,1` keep their current Sawtooth route.
- PowerPC 970 PVRs and U3 hosts are rejected.
- Only CPU 0 is advertised or targeted by interrupts.
- Missing MESH, floppy, audio, Ethernet, or ATA1 is valid.
- Physical tests use temporary or dedicated disks.

Before Task 1, invoke `superpowers:using-git-worktrees` and create a dedicated
`codex/ppc-macrisc-platform` worktree. The current `qemu-debug-loop` worktree
contains unrelated user changes and must not be used for implementation.

### Task 1: Add bounded property decoding

**Files:**
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h`
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c`
- Create: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/Makefile.host`

- [ ] **Step 1: Establish the baseline**

Run:

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host clean
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
```

Expected: the existing four host programs build and exit 0. If the Windows host lacks the toolchain, run the same commands inside the configured build guest.

- [ ] **Step 2: Write the failing decoder test**

Create `macrisc_discovery_test.c` with this harness and cases:

```c
#include <stdio.h>
#include "../powermac/macrisc_discovery.h"

static int failures;
#define CHECK(x) do { if (!(x)) { \
    printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); failures++; \
} } while (0)

static PEProperty prop(const unsigned char *p, unsigned int n)
{
    PEProperty value;
    value.bytes = p;
    value.size = n;
    return value;
}

static void test_strings(void)
{
    static const unsigned char list[] =
        "PowerBook3,4\0MacRISC2\0Power Macintosh\0";
    static const unsigned char bad[] = { 'M', 'a', 'c' };
    CHECK(PEPropertyHasString(prop(list, sizeof(list)), "MacRISC2"));
    CHECK(!PEPropertyHasString(prop(list, sizeof(list)), "MacRISC"));
    CHECK(!PEPropertyHasString(prop(bad, sizeof(bad)), "Mac"));
}

static void test_cells(void)
{
    static const unsigned char one[] = { 0x80, 0, 0, 0 };
    static const unsigned char two[] = { 0, 0, 0, 0, 0x80, 0, 0, 0 };
    unsigned int value;
    CHECK(PEReadCell32(prop(one, 4), 0, &value));
    CHECK(value == 0x80000000U);
    CHECK(PEReadAddress32(prop(two, 8), 2, &value));
    CHECK(value == 0x80000000U);
    CHECK(!PEReadAddress32(prop(two, 8), 1, &value));
    CHECK(!PEReadCell32(prop(one, 3), 0, &value));
}

int main(void)
{
    test_strings();
    test_cells();
    if (failures) return 1;
    printf("MacRISC discovery tests passed\n");
    return 0;
}
```

Add this exact make target and include it in `test` and `clean`:

```make
macrisc_discovery_test: macrisc_discovery_test.c \
    ../powermac/macrisc_discovery.c
	$(HOST_CC) $(HOST_CFLAGS) -DMACRISC_HOST_TEST -I../powermac \
	    -o $@ macrisc_discovery_test.c ../powermac/macrisc_discovery.c
```

- [ ] **Step 3: Verify the red state**

Run the new make target. Expected: compilation fails because the new header and functions are absent.

- [ ] **Step 4: Implement the decoder API**

Use this public header section:

```c
typedef struct {
    const unsigned char *bytes;
    unsigned int size;
} PEProperty;

int PEPropertyHasString(PEProperty property, const char *expected);
int PEReadCell32(PEProperty property, unsigned int index,
    unsigned int *value);
int PEReadAddress32(PEProperty property, unsigned int cells,
    unsigned int *value);
int PEReadRange32(PEProperty property, unsigned int childCells,
    unsigned int parentCells, unsigned int sizeCells, unsigned int entry,
    unsigned int *child, unsigned int *parent, unsigned int *length);
```

Implement byte-wise big-endian reads. Accept one or two address cells, require a zero high cell for 32-bit output, reject null outputs, truncated entries, zero range lengths, unsupported cell counts, and `parent + length` overflow. Compare string-list members only within `property.size` and require a terminating NUL.

- [ ] **Step 5: Add range/error cases and verify green**

Add one-cell and two-cell range tests plus truncation, nonzero high-cell, zero-length, and overflow failures. Run the full host suite. Expected: all five programs pass.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c src/drivers-ppc/bus/drvPExpert/tests/Makefile.host
git commit -m "drvPExpert: add bounded MacRISC property decoding"
```

### Task 2: Classify CPU, host bridge, Mac-IO, and model family

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c`

- [ ] **Step 1: Add a failing table-driven classifier test**

Use these representative rows:

```c
static const ModelCase cases[] = {
    { "PowerMac2,2",  0x00080000U, "uni-north", "KeyLargo", 1 },
    { "PowerMac4,2",  0x000c0000U, "uni-north", "Pangea", 1 },
    { "PowerMac6,3",  0x80030000U, "uni-north", "Intrepid", 1 },
    { "PowerBook3,4", 0x80010000U, "uni-north", "KeyLargo", 1 },
    { "RackMac1,1",   0x80010000U, "uni-north", "KeyLargo", 1 },
    { "PowerMac7,2",  0x00390000U, "u3", "K2-KeyLargo", 0 },
    { "PowerMac3,9",  0x80010000U, "bandit", "KeyLargo", 0 },
    { "Unknown1,1",   0x80010000U, "uni-north", "KeyLargo", 0 }
};
```

Also assert an unlisted `PowerBook9,9` with G4, UniNorth, `MacRISC2`, and Intrepid returns `kPEMacRISCCompatibleUnlisted`.

- [ ] **Step 2: Verify compilation fails, then define types**

Add:

```c
#define PE_MACRISC_MODEL_MAX 64
#define PE_MACRISC_MAX_CPUS 4
#define PE_MACRISC_MAX_SOURCES 64
#define PE_MACRISC_MAX_CASCADE 7

typedef enum { kPECPUUnknown, kPECPU750, kPECPU7400, kPECPU7410,
    kPECPU744x, kPECPU745x, kPECPU970 } PECPUFamily;
typedef enum { kPEMacIOUnknown, kPEMacIOKeyLargo,
    kPEMacIOPangea, kPEMacIOIntrepid } PEMacIOFamily;
typedef enum { kPEMacRISCNotMatched, kPEMacRISCSupported,
    kPEMacRISCCompatibleUnlisted, kPEMacRISCMalformed,
    kPEMacRISCUnsupportedCPU, kPEMacRISCUnsupportedHost,
    kPEMacRISCUnsupportedMacIO } PEMacRISCStatus;

typedef struct {
    PEProperty model, rootCompatible, hostCompatible, macIOCompatible;
    unsigned int pvr;
} PEMacRISCIdentityInput;

PEMacRISCStatus PEMacRISCClassify(const PEMacRISCIdentityInput *input,
    PECPUFamily *cpu, PEMacIOFamily *macIO,
    char model[PE_MACRISC_MODEL_MAX]);
```

- [ ] **Step 3: Implement capability-first classification**

Match PVR families by their high 16 bits. Accept 750/G3 and 7400/7410/744x/745x families. Classify `0x0039`, `0x003c`, and `0x0044` as 970 and reject them before model acceptance. Require UniNorth, a `MacRISC` generation root string, and KeyLargo/Pangea/Intrepid. Copy at most 63 model bytes after finding its terminator.

- [ ] **Step 4: Run all tests and commit**

Expected: all host tests pass; exact Sawtooth model behavior is unchanged.

```powershell
git add src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c
git commit -m "drvPExpert: classify later MacRISC platforms"
```

### Task 3: Build the validated fixed-size descriptor

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c`

- [ ] **Step 1: Add failing descriptor tests**

Create KeyLargo, Pangea, and Intrepid fixtures. Assert Mac-IO `0x80000000/0x80000`, MPIC `0xf4000000`, 64 sources, two discovered CPUs with boot CPU 0, and firmware CPU/bus/timebase clocks. Remove MESH, floppy, audio, Ethernet, and ATA1 one at a time and assert the descriptor stays valid with each resource absent. Add failures for missing Mac-IO/MPIC/CPU, source count 0 or 65, zero clocks, range overflow, and cascade width 8.

- [ ] **Step 2: Define the descriptor contract**

Add:

```c
typedef struct { int present; unsigned int base, length; } PEResource;
typedef struct {
    int curio, mesh, floppy, ethernetTx, ethernetRx;
    int sccATx, sccARx, sccBTx, sccBRx;
    int audioOut, audioIn, ata0, ata1;
} PEDBDMAChannels;
typedef enum { kPEPlatformValid, kPEPlatformMissingMacIO,
    kPEPlatformMissingMPIC, kPEPlatformBadMPICCount,
    kPEPlatformMissingCPU, kPEPlatformBadClock,
    kPEPlatformBadCascade, kPEPlatformBadRange } PEPlatformError;

typedef struct {
    char model[PE_MACRISC_MODEL_MAX];
    int listedModel;
    PECPUFamily cpuFamily;
    PEMacIOFamily macIOFamily;
    unsigned int cpuCount, bootCPU, pvr;
    unsigned int cpuClockHz, busClockHz, timebaseHz;
    unsigned int dcacheSize, dcacheBlockSize, icacheSize, l2CacheSize;
    int cachesUnified;
    PEResource macIO, mpic, serial, mesh, audio, ethernet;
    PEResource nvramAddress, nvramData, ata0, ata1;
    PEDBDMAChannels dbdma;
    unsigned int mpicSources;
    int hasPMU, hasCUDA, hasCascade;
    unsigned int cascadeSource, cascadeWidth;
    unsigned int pmuInterrupts[2], pmuInterruptCount;
} PEMacRISCPlatform;

void PEMacRISCPlatformInit(PEMacRISCPlatform *platform);
PEPlatformError PEMacRISCValidate(const PEMacRISCPlatform *platform);
int PEMacRISCSetResource(PEResource *resource, unsigned int base,
    unsigned int length);
int PEMacRISCSetDBDMA(PEDBDMAChannels *channels, const char *role,
    unsigned int channel);
```

- [ ] **Step 3: Implement validation and setters**

Initialize every DBDMA field to `-1`. Require valid Mac-IO/MPIC ranges, `1..64` primary sources, `1..4` CPUs, nonzero clocks, nonwrapping ranges, and a cascade source below `mpicSources` with width at most 7. Reject DBDMA channels above 31 and conflicting duplicate roles. Unknown roles return false without modifying state.

- [ ] **Step 4: Run all host tests and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c
git commit -m "drvPExpert: validate MacRISC platform descriptors"
```

### Task 4: Capture relevant DeviceTree state without mutation

**Files:**
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.h`
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.c`
- Create: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/Makefile.host`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/Makefile`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/PB.project`

- [ ] **Step 1: Write a failing fake-tree capture test**

Define this shared traversal seam in `macrisc_dt.h`:

```c
typedef void *PEFirmwareNode;
typedef struct {
    void *context;
    PEFirmwareNode (*root)(void *context);
    PEFirmwareNode (*firstChild)(void *context, PEFirmwareNode node);
    PEFirmwareNode (*nextSibling)(void *context, PEFirmwareNode node);
    PEProperty (*property)(void *context, PEFirmwareNode node,
        const char *name);
} PEMacRISCFirmware;

PEMacRISCStatus PEMacRISCCapture(const PEMacRISCFirmware *firmware,
    PEMacRISCPlatform *platform, PEPlatformError *error);
PEMacRISCStatus PEMacRISCDiscoverDeviceTree(PEPlatformError *error);
const PEMacRISCPlatform *PEMacRISCGetPlatform(void);
void PEMacRISCPrintFailure(PEMacRISCStatus status, PEPlatformError error);
```

Build a static tree containing root, `/cpus`, two CPUs, UniNorth, Mac-IO,
OpenPIC, PMU, ATA0, serial, and DBDMA children. Assert capture recognizes
`RackMac1,1`, counts two CPUs, resolves child registers, and leaves a saved
copy of every property byte unchanged.

- [ ] **Step 2: Run and verify the link failure**

Add a `macrisc_platform_test` target using `-DMACRISC_HOST_TEST` and both new C files. Expected: the test fails to link `PEMacRISCCapture`.

- [ ] **Step 3: Implement bounded depth-first capture**

Use a 16-entry traversal stack. Inspect only `name`, `device_type`, `model`,
`compatible`, `reg`, `assigned-addresses`, `ranges`, address/size cell counts,
both interrupt properties, CPU version, three clock properties, and cache
properties. Translate child registers through parent ranges using the Task 1
helpers. Count CPUs but retain boot CPU properties as authoritative. Prefer a
well-formed `AAPL,interrupts`, otherwise use `interrupts`.

Return `kPEMacRISCMalformed` on depth overflow, truncated data, conflicting
duplicate resources, or validation failure. Never cast property bytes to an
integer pointer.

- [ ] **Step 4: Add the kernel DeviceTree transport**

Under `#ifndef MACRISC_HOST_TEST`, adapt `DTLookupEntry`, entry iterators, and
`DTGetProperty` to the traversal seam. Store one static validated descriptor;
`PEMacRISCGetPlatform` returns null until capture succeeds completely.

- [ ] **Step 5: Update project metadata and verify**

Append `macrisc_discovery.c macrisc_dt.c` to powermac `CFILES` and add their
headers/sources to `PB.project`. Run the full host suite. Expected: fake-tree,
mutation, depth, range, and malformed-property cases pass.

- [ ] **Step 6: Commit**

```powershell
git add src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.h src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.c src/drivers-ppc/bus/drvPExpert/powermac/Makefile src/drivers-ppc/bus/drvPExpert/powermac/PB.project src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c src/drivers-ppc/bus/drvPExpert/tests/Makefile.host
git commit -m "drvPExpert: capture MacRISC device tree state"
```

### Task 5: Select MacRISC without regressing current routes

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/powermac.h`
- Modify: `src/kernel-7/machdep/ppc/powermac.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/powermac_gestalt.h`
- Modify: `src/kernel-7/machdep/ppc/powermac_gestalt.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c`

- [ ] **Step 1: Add failing route-selection tests**

Add:

```c
typedef enum { kPERouteLegacy, kPERouteSawtooth,
    kPERouteMacRISC, kPERouteUnsupported } PEPlatformRoute;
PEPlatformRoute PEMacRISCSelectRoute(const char *model,
    PEMacRISCStatus status);
```

Assert the five preserved identifiers select Sawtooth, supported later
fixtures select MacRISC, classic identifiers select legacy, and G5/malformed
later fixtures select unsupported.

- [ ] **Step 2: Implement exact route policy**

Use exact equality for the five preserved identifiers. Return MacRISC only
for `kPEMacRISCSupported` or `kPEMacRISCCompatibleUnlisted`. Do not accept a
`PowerMac`, `PowerBook`, or `RackMac` prefix by itself.

- [ ] **Step 3: Add shared class and gestalt values**

Add to both copies of `powermac.h`:

```c
#define POWERMAC_CLASS_MACRISC 10
#define IsMacRISC() (powermac_info.class == POWERMAC_CLASS_MACRISC)
#define IsCore99() (IsSawtooth() || IsMacRISC())
```

Add `gestaltMacRISC = 1001` beside `gestaltSawtooth = 1000` in both gestalt
headers.

- [ ] **Step 4: Integrate discovery into machine identification**

Keep every current legacy comparison. After the five Sawtooth comparisons,
call:

```c
status = PEMacRISCDiscoverDeviceTree(&platformError);
if (status == kPEMacRISCSupported ||
    status == kPEMacRISCCompatibleUnlisted)
    return gestaltMacRISC;
PEMacRISCPrintFailure(status, platformError);
panic("Unsupported MacRISC platform\n");
```

Add the new gestalt switch case and class. Copy `cpu_model` from the validated
descriptor. Remove writes into the root `compatible` property; if legacy
display formatting still needs slash/space substitution, transform only the
bounded local copy.

- [ ] **Step 5: Verify and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/powermac.h src/kernel-7/machdep/ppc/powermac.h src/drivers-ppc/bus/drvPExpert/powermac/powermac_gestalt.h src/kernel-7/machdep/ppc/powermac_gestalt.h src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c
git commit -m "drvPExpert: select validated MacRISC machines"
```

### Task 6: Publish optional resources and firmware clock/cache data

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/powermac_init.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c`

- [ ] **Step 1: Add failing publication and timebase tests**

Define:

```c
typedef struct {
    unsigned int ioBase, ioSize, interruptBase;
    unsigned int serialBase, meshBase, audioBase, ethernetBase;
    unsigned int nvramAddress, nvramData, ata0Base, ata1Base;
} PEMacRISCPublishedIO;

int PEMacRISCPublish(const PEMacRISCPlatform *platform,
    PEMacRISCPublishedIO *published);
int PEMacRISCComputeClockConversion(const PEMacRISCPlatform *platform,
    unsigned int *numerator, unsigned int *denominator,
    unsigned int *period824);
```

Assert absent resources publish as zero rather than `macIO.base`. Assert a
33,250,000 Hz timebase yields nonzero conversion values; zero frequency and
8.24 whole-part overflow fail.

- [ ] **Step 2: Implement pure publication and clock conversion**

Copy absolute bases only when `present` is true. Use 64-bit intermediate
arithmetic:

```c
*numerator = 1000000000U;
*denominator = platform->timebaseHz;
whole = 1000000000U / platform->timebaseHz;
fraction = ((unsigned long long)(1000000000U % platform->timebaseHz)
    << 24) / platform->timebaseHz;
if (whole > 255U) return 0;
*period824 = (whole << 24) | (unsigned int)fraction;
```

- [ ] **Step 3: Use the descriptor in `identify_machine1/2`**

For MacRISC, set I/O size from the descriptor. In `identify_machine2`, fill
every `powermac_io_info` field from `PEMacRISCPublish`. Keep the old getter
sequence unchanged for other classes. Do not calculate `io_base + 0` for
absent hardware.

Populate `powermac_machine_info` from firmware fields. Skip
`DetermineClockSpeeds` and `InitBacksideL2` for MacRISC and use the validated
timebase conversion. Retain both legacy calls unchanged.

- [ ] **Step 4: Advertise only CPU 0**

Clear `machine_slot[1..NCPUS-1]`, then publish slot 0. Leave G4 processors as
`CPU_SUBTYPE_POWERPC_ALL` because this ABI has no G4 subtype. Assert a
two-CPU descriptor still produces one available CPU.

- [ ] **Step 5: Verify and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.h src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c src/drivers-ppc/bus/drvPExpert/powermac/powermac_init.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c
git commit -m "drvPExpert: publish MacRISC firmware resources"
```

### Task 7: Make MPIC platform policy explicit

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/mpic.h`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/chips/mpic.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/mpic_direct_test.c`

- [ ] **Step 1: Add failing policy tests**

Define:

```c
typedef struct {
    int useFeatureControl;
    int enableCascadeMode;
    unsigned int destinationMask;
    unsigned int sourceCount;
} PEMPICConfiguration;

int PEMPICValidateConfiguration(const PEMPICConfiguration *configuration);
void PEMPICSetConfiguration(const PEMPICConfiguration *configuration);
int PEMPICSourceInRange(unsigned int source, unsigned int count);
```

Test valid source counts 1 and 64, invalid 0 and 65, valid destination mask 1,
invalid mask 0 or bits above the low four CPUs, independent cascade/feature
control flags, source 63 in range, and source 64 out of range.

- [ ] **Step 2: Implement policy with legacy defaults**

Initialize private state to `{ 1, 1, 1, 64 }`. In initialization, touch
`FM_MPIC_CTRL` only when requested, set or clear `MPIC_CASCADE` according to
policy, validate `sourceCount == nmpic_interrupts`, and write the configured
destination mask.

- [ ] **Step 3: Bound interrupt acknowledge**

Before indexing `mpic_interrupts[irq]`, require `irq < nmpic_interrupts`.
Treat `0xff` and any out-of-range vector as no pending interrupt. Preserve EOI
ordering for valid sources.

- [ ] **Step 4: Verify and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/chips/mpic.h src/drivers-ppc/bus/drvPExpert/powermac/chips/mpic.c src/drivers-ppc/bus/drvPExpert/tests/mpic_direct_test.c
git commit -m "drvPExpert: make MPIC platform policy explicit"
```

### Task 8: Add the MacRISC family initializer

**Files:**
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/families/macrisc.h`
- Create: `src/drivers-ppc/bus/drvPExpert/powermac/families/macrisc.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/families/Makefile`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/families/PB.project`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c`

- [ ] **Step 1: Write failing MPIC-table and DBDMA tests**

Expose these host-safe builders:

```c
int PEMacRISCBuildMPIC(const PEMacRISCPlatform *platform,
    struct powermac_interrupt interrupts[PE_MACRISC_MAX_SOURCES],
    unsigned long mapping[PE_MACRISC_MAX_SOURCES * 2]);
int PEMacRISCBuildDBDMA(const PEDBDMAChannels *source,
    powermac_dbdma_channels_t *destination);
```

Assert all 64 vectors equal their source, destinations equal CPU-0 mask 1,
known DMA sources are edge/active-high, known devices are level/active-low,
unknown valid sources are level/active-low with direct logical identities,
and absent DBDMA roles remain `-1`.

- [ ] **Step 2: Add the family entry points**

Define:

```c
powermac_init_t macrisc_init = {
    configure_macrisc,
    mpic_interrupt_initialize,
    NO_ENTRY,
    macrisc_initialize_bats,
    rtc_init,
    &macrisc_dbdma_channels
};
```

Use fixed storage for 64 primary interrupts, 7 cascade children, and 128
mapping words. Clear handler, level, and argument fields; initialize all
logical device fields to `-1` before applying discovered roles.

- [ ] **Step 3: Configure runtime state from the validated descriptor**

Revalidate the global descriptor, build both tables, assign the existing
MPIC globals and counts, and set:

```c
configuration.useFeatureControl = 0;
configuration.enableCascadeMode = platform->hasCascade;
configuration.destinationMask = 1;
configuration.sourceCount = platform->mpicSources;
PEMPICSetConfiguration(&configuration);
```

Set `powermac_info.viaIRQ` from the descriptor, never `0x5a`. Initialize
KeyLargo services only on compatible Mac-IO; optional audio I2C failure must
not block boot.

- [ ] **Step 4: Map discovered early-I/O segments**

Map the 256 MB segment containing Mac-IO and, if different, the segment
containing MPIC. A zero `PEMapSegment` result is fatal only when
`PEResidentAddress` also reports the range unmapped. Do not copy Sawtooth's
unconditional segment pair.

- [ ] **Step 5: Add build metadata and connect `macrisc_init`**

Add both family files to `families/Makefile` and `families/PB.project`.
Include `families/macrisc.h` in `identify_machine.c` and assign the initializer
in the `gestaltMacRISC` case.

- [ ] **Step 6: Verify and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/families/macrisc.h src/drivers-ppc/bus/drvPExpert/powermac/families/macrisc.c src/drivers-ppc/bus/drvPExpert/powermac/families/Makefile src/drivers-ppc/bus/drvPExpert/powermac/families/PB.project src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c
git commit -m "drvPExpert: add the MacRISC platform family"
```

### Task 9: Preserve Core99 NVRAM and firmware PMU interrupts

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c`
- Modify: `src/kernel-7/bsd/dev/ppc/PowerSurgeMB.m`
- Modify: `src/drivers-ppc/input/drvPPCPMU/PPCPMU.drvproj/PPCPMU.lksproj/pmu.m`
- Modify: `src/kernel-7/bsd/dev/ppc/drvPMU/pmu.m`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c`

- [ ] **Step 1: Add failing PMU-list policy tests**

Add:

```c
unsigned int PEMacRISCPMUInterruptList(const PEMacRISCPlatform *platform,
    unsigned int output[2]);
```

Assert zero, one, and two valid firmware sources return the same counts and
order; any source above 63 returns zero; no source is invented.

- [ ] **Step 2: Preserve MacRISC firmware lists in both PMU source copies**

After reading the DriverKit list, use:

```objc
if (IsMacRISC()) {
    unsigned int count = [deviceDescription numInterrupts];
    if (count == 0 || count > 2) {
        [self free];
        return nil;
    }
    newIRQs[0] = oldIRQs[0];
    if (count == 2) newIRQs[1] = oldIRQs[1];
    [deviceDescription setInterruptList:newIRQs num:count];
} else {
    /* The existing Sawtooth and legacy branches remain unchanged here. */
}
```

Ensure `PEEditDTEntry` exposes the descriptor list using the existing
DriverKit XOR representation. Never use fixed source 47 for MacRISC.

- [ ] **Step 3: Apply Core99 NVRAM rules**

Change only Core99 conditionals in `InitNVRAMPartitions`, `cuda_restart`,
`ReadNVRAM`, and `WriteNVRAM` from `IsSawtooth()` to `IsCore99()`. Keep the
underlying access and partition code unchanged.

- [ ] **Step 4: Verify and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c src/kernel-7/bsd/dev/ppc/PowerSurgeMB.m src/drivers-ppc/input/drvPPCPMU/PPCPMU.drvproj/PPCPMU.lksproj/pmu.m src/kernel-7/bsd/dev/ppc/drvPMU/pmu.m src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c
git commit -m "drivers-ppc: preserve MacRISC Core99 services"
```

### Task 10: Complete model coverage and diagnostics

**Files:**
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c`
- Modify: `src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c`

- [ ] **Step 1: Add the known-model matrix**

Exercise these identifiers with matching G3/G4 and chipset fixtures:

```c
static const char *knownLaterModels[] = {
    "PowerMac2,2", "PowerMac4,1",
    "PowerMac3,4", "PowerMac3,5", "PowerMac3,6",
    "PowerMac4,2", "PowerMac4,4", "PowerMac4,5",
    "PowerMac6,1", "PowerMac6,3", "PowerMac6,4",
    "PowerMac10,1", "PowerMac10,2",
    "PowerBook2,2", "PowerBook2,3",
    "PowerBook3,1", "PowerBook3,2", "PowerBook3,3",
    "PowerBook3,4", "PowerBook3,5",
    "PowerBook4,1", "PowerBook4,2", "PowerBook4,3",
    "PowerBook5,1", "PowerBook5,2", "PowerBook5,3",
    "PowerBook5,4", "PowerBook5,5", "PowerBook5,6",
    "PowerBook5,7", "PowerBook5,8", "PowerBook5,9",
    "PowerBook6,1", "PowerBook6,2", "PowerBook6,3",
    "PowerBook6,4", "PowerBook6,5", "PowerBook6,6",
    "PowerBook6,7", "PowerBook6,8",
    "RackMac1,1", "RackMac1,2"
};
```

Add negative 970/U3 fixtures for `PowerMac7,2`, `PowerMac7,3`, `PowerMac8,1`,
`PowerMac8,2`, `PowerMac9,1`, `PowerMac11,2`, and `RackMac3,1`. Their rejection
must come from CPU/host capability checks.

- [ ] **Step 2: Demonstrate red then green catalog behavior**

Run the discovery test before extending the catalog and record at least one
expected failure. Expand only the table, not per-model branches, then rerun.

- [ ] **Step 3: Add bounded diagnostics**

Print one line containing bounded model, status, CPU, Mac-IO, and validation
error. Constant lookup functions use `unknown` fallbacks. Required forms:

```text
MacRISC: PowerMac7,2 rejected: cpu=970 host=unsupported mac-io=unknown
MacRISC: PowerBook3,4 rejected: malformed MPIC range
MacRISC: PowerBook9,9 accepted as unlisted compatible: cpu=745x mac-io=Intrepid
```

- [ ] **Step 4: Verify and commit**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host clean
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
git add src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_discovery_test.c src/drivers-ppc/bus/drvPExpert/tests/macrisc_platform_test.c
git commit -m "drvPExpert: cover later G3 and G4 model families"
```

### Task 11: Build the PPC platform expert and kernel

**Files:**
- Modify only a file already listed above if the build exposes a directly related omission.

- [ ] **Step 1: Sync and build the platform expert in the guest**

```powershell
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/bus/drvPExpert && gnumake clean all install DSTROOT=/"
```

Expected: exit 0 and `macrisc_discovery.o`, `macrisc_dt.o`, and family
`macrisc.o` are included in `pexpertpowermac.o`.

- [ ] **Step 2: Build the PPC kernel**

```powershell
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake clean kernels"
```

Expected: exit 0 and a newly linked PPC kernel.

- [ ] **Step 3: Inspect symbols and size**

```powershell
powershell -File vm/rhap-vm.ps1 ssh "nm -g /build/source/src/drivers-ppc/bus/drvPExpert/powermac/pexpertpowermac.o | egrep 'PEMacRISC|macrisc_init|configure_macrisc'"
powershell -File vm/rhap-vm.ps1 ssh "size /build/source/src/drivers-ppc/bus/drvPExpert/powermac/pexpertpowermac.o"
```

Expected: each public symbol appears once, the final kernel has no unresolved
MacRISC symbol, and the object remains within existing link/package limits.

- [ ] **Step 4: Correct only evidenced build defects**

Rerun all host tests after any correction. Stage only directly related files
and commit with `drvPExpert: build later MacRISC support`. If the clean build
needed no correction, do not create an empty commit.

### Task 12: Validate Cube, PowerBook, and Xserve hardware

**Files:**
- Create: `docs/hardware/ppc-macrisc-validation.md`

- [ ] **Step 1: Create the evidence record**

```markdown
# PPC MacRISC Hardware Validation

| Machine | Model | CPU | Mac-IO | Kernel hash | Result |
|---|---|---|---|---|---|
| Cube | PowerMac5,1 | | | | Not run |
| PowerBook G4 | PowerBook3,4 | | | | Not run |
| Xserve G4 DP | RackMac1,1 | | | | Not run |

For each machine record descriptor output, console, root device, shell result,
10-minute clock delta, disk stress, clean shutdown, and first failure line.
```

- [ ] **Step 2: Boot `PowerMac5,1` as the regression control**

Confirm it stays on Sawtooth, reaches a shell, then run:

```sh
date
dd if=/dev/zero of=/private/tmp/macrisc-io-test bs=64k count=256
sync
dd if=/private/tmp/macrisc-io-test of=/dev/null bs=64k
date
rm /private/tmp/macrisc-io-test
sync
```

Expected: no interrupt storm, I/O error, time reversal, or panic; clean reboot
succeeds.

- [ ] **Step 3: Boot `PowerBook3,4`**

Confirm MacRISC/KeyLargo classification, one available CPU, firmware PMU
interrupts, and harmless absence of desktop-only resources. Run the same
disk/time sequence and reboot cleanly.

- [ ] **Step 4: Boot dual-processor `RackMac1,1`**

Confirm two discovered CPUs but one available CPU, MPIC destination mask 1,
no secondary-CPU delivery, stable root-disk I/O, and clean shutdown.

- [ ] **Step 5: Record results and separate external-driver blockers**

Fill every record field. If platform, clock, and interrupt initialization
succeed but console/root storage fails in another driver, record the exact
dependency and create a separate design instead of widening this change.

- [ ] **Step 6: Commit evidence**

```powershell
git add docs/hardware/ppc-macrisc-validation.md
git commit -m "docs: record MacRISC hardware validation"
```

### Task 13: Final regression and scope audit

**Files:**
- Inspect all files changed by Tasks 1-12.

- [ ] **Step 1: Run clean host and guest verification**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host clean
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-ppc/bus/drvPExpert && gnumake clean all install DSTROOT=/"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake clean kernels"
```

Expected: zero host warnings/failures and both guest builds exit 0.

- [ ] **Step 2: Audit unsafe assumptions**

```powershell
rg -n "PowerMac7|PROCESSOR_VERSION_970|K2-KeyLargo|u3" src/drivers-ppc/bus/drvPExpert
rg -n "0x5a|tmpIRQ = 47|HEATHROW_SIZE" src/drivers-ppc/bus/drvPExpert/powermac src/drivers-ppc/input/drvPPCPMU src/kernel-7/bsd/dev/ppc
rg -n "\(unsigned int \*\).*bytes|bytes.*\(unsigned int \*\)" src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.c
```

Expected: G5 strings occur only in rejection/tests, fixed Sawtooth constants
occur only in legacy branches, and property decoders contain no unaligned
integer casts.

- [ ] **Step 3: Audit diff and repository state**

```powershell
git diff --check
git status --short
git log --oneline -- src/drivers-ppc/bus/drvPExpert docs/hardware/ppc-macrisc-validation.md
```

Expected: no whitespace errors or tracked generated binaries; every changed
file is in the file structure or is an evidenced build correction.

- [ ] **Step 4: Apply completion workflows**

Invoke `superpowers:verification-before-completion`, then
`superpowers:finishing-a-development-branch`. Present integration choices only
after reading fresh host-test, guest-build, and available hardware evidence.
