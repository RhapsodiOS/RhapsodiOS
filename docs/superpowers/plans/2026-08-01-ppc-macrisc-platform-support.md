# PPC MacRISC Platform Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot later New World PowerPC G3 and G4 Macs to a userspace shell through a validated, capability-driven MacRISC platform path while preserving existing Yosemite and Sawtooth behavior.

**Architecture:** Pure C89 helpers decode bounded Open Firmware properties and build a fixed-size `PEMacRISCPlatform` descriptor. A thin DeviceTree adapter fills that descriptor, and a new `macrisc` family consumes it for I/O publication, firmware clock/cache data, DBDMA, BAT, MPIC, and optional PMU/VIA cascade setup. Existing exact model paths remain unchanged; PowerPC 970/U3 machines fail before MMIO.

**Tech Stack:** ANSI C89, Objective-C DriverKit compatibility call sites, Darwin DeviceTree APIs, PowerPC BAT/OpenPIC interfaces, Project Builder makefiles, host C tests, Rhapsody PPC kernel build, physical Open Firmware hardware.

---

## Audit (2026-09-26)

This plan was checked against the current tree before implementation. Every
task was kept, but the items below were corrected in place; each correction
carries an **Audit** note where it applies.

- Pangea and Intrepid Mac-IO nodes advertise `compatible = "Keylargo"` just
  like KeyLargo; the three are told apart by the `device-id` property (0x22,
  0x25, 0x3e). The classifier and every fixture now key on `device-id`
  (Tasks 2, 3, 4, 10).
- The OpenPIC on every KeyLargo-family Mac-IO is the
  `interrupt-controller@40000` child of `mac-io`, at `macIO.base + 0x40000`,
  not at `0xf4000000`. The existing `MPIC_*` macros use `int_cntlr_base_phys`
  as an absolute physical address, so the descriptor publishes the translated
  absolute base (Tasks 3, 6, 8).
- The accepted PVR list is spelled out, including 750FX/750GX (later G3
  iBooks) and 7447A/7448 (later PowerBooks, Mac mini) (Task 2).
- `configure_platform()` already publishes only `machine_slot[0]` and
  `avail_cpus = 1`, and the PPC kernel is a uniprocessor configuration, so
  there is no slot array to clear (Task 6).
- The legacy nanosecond pair is `numerator = 4000`, `denominator = bus MHz`,
  and the 53c96 driver multiplies by it; the descriptor path keeps that scale
  instead of publishing `1e9 / timebase`. The host flags reject `long long`,
  so the 8.24 fraction is computed by shift-subtract (Task 6).
  `derive_from_of()` in `clock_speed.c` is an existing, currently dead,
  firmware-clock path.
- `MPIC_CASCADE` (0x20 stored unswapped, bit 29 of the OpenPIC global
  configuration register) is the 8259 pass-through disable bit, unrelated to
  the VIA cascade. It stays set on every Mac; the VIA cascade source comes
  from the VIA node (Tasks 7, 8).
- The PMU driver contract is two interrupts: entry 0 is the VIA cascade child
  identity, entry 1 is the raw VIA MPIC source (47 on via-pmu machines). The
  earlier draft reduced this to one entry, which would disable the PMU. The
  MacRISC path publishes both through `PEEditDTEntry` (Task 9).
- `PEEditDTEntry`'s Sawtooth-only AGP bridge and USB filtering quirks are
  UniNorth/Core99 behaviour and move to `IsCore99()` (Task 9).
- `powermac_io_info` also needs `via_base_phys`, `floppy_base_phys` and
  `dma_base_phys`; the descriptor and the published-I/O struct gained those
  fields (Tasks 3, 6).
- `mpic_enable_irq`/`mpic_disable_irq` already bound their source; only the
  acknowledge loop in `mpic_interrupt()` is unbounded (Task 7).
- Build and validation steps reference the scripts that exist and the
  configured `RemoteRoot` rather than a fixed `/build/source`; the evidence
  record moves to `docs/boot/` beside `boot-ppc.md` (Tasks 11, 12).
- The worktree instruction that referenced another session's checkout was
  removed.

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
- `PowerMac2,1` keeps its current Yosemite (`gestaltCHRP_Version1`) route; this plan does not re-home it.
- PowerPC 970 PVRs and U3 hosts are rejected.
- Only CPU 0 is advertised or targeted by interrupts.
- Missing MESH, floppy, audio, Ethernet, or ATA1 is valid.
- Physical tests use temporary or dedicated disks.

Do the work on a dedicated branch or worktree that contains no unrelated
changes, so every commit below stays bisectable.

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
    /* Real MacRISC2/3 roots list the plain "MacRISC" member as well. */
    static const unsigned char list[] =
        "PowerBook3,4\0MacRISC2\0MacRISC\0Power Macintosh\0";
    static const unsigned char bad[] = { 'M', 'a', 'c' };
    CHECK(PEPropertyHasString(prop(list, sizeof(list)), "MacRISC2"));
    CHECK(PEPropertyHasString(prop(list, sizeof(list)), "MacRISC"));
    CHECK(!PEPropertyHasString(prop(list, sizeof(list)), "MacRIS"));
    CHECK(!PEPropertyHasString(prop(list, sizeof(list)), "Power"));
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

> **Audit:** `chips/keylargo_discovery.h` already carries a `{bytes,size}`
> property view (`PEKeyLargoProperty`), a byte-wise cell reader and a range
> check as header-only `static` functions. `macrisc_discovery` is a compiled
> module, so it defines `PEProperty` with the same two-field layout rather
> than including that header (its unused statics would fail `-Werror`). Keep
> the two layouts identical and do not add a third copy.

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

> **Audit:** KeyLargo, Pangea and Intrepid all present `compatible =
> "Keylargo"` (lower-case `l`) on the `mac-io` node; Apple's AppleKeyLargo
> and Linux `pmac_feature.c` tell them apart by `device-id` (0x22 KeyLargo,
> 0x25 Pangea, 0x3e Intrepid). K2 is `K2-Keylargo` (0x41) and Shasta is 0x4f.
> The host bridge is the `uni-n` node with `compatible = "uni-north"`; G5
> machines have a `u3` or `u4` node instead. Rows now carry the `device-id`.

Use these representative rows (`model`, PVR, `uni-n` compatible, `mac-io`
compatible, `mac-io` `device-id`, expected accept):

```c
static const ModelCase cases[] = {
    { "PowerMac2,2",  0x00080000U, "uni-north", "Keylargo", 0x22, 1 },
    { "PowerMac4,2",  0x80010000U, "uni-north", "Keylargo", 0x25, 1 },
    { "PowerMac6,3",  0x80020000U, "uni-north", "Keylargo", 0x3e, 1 },
    { "PowerBook4,3", 0x70000000U, "uni-north", "Keylargo", 0x25, 1 },
    { "PowerBook3,4", 0x80010000U, "uni-north", "Keylargo", 0x22, 1 },
    { "PowerMac10,1", 0x80030000U, "uni-north", "Keylargo", 0x3e, 1 },
    { "RackMac1,1",   0x80010000U, "uni-north", "Keylargo", 0x22, 1 },
    { "PowerMac7,2",  0x00390000U, "u3", "K2-Keylargo", 0x41, 0 },
    { "PowerMac3,9",  0x80010000U, "bandit", "Keylargo", 0x22, 0 },
    { "PowerBook9,8", 0x80010000U, "uni-north", "Keylargo", 0x41, 0 },
    { "Unknown1,1",   0x80010000U, "uni-north", "Keylargo", 0x22, 0 }
};
```

`Unknown1,1` fails only because its model is outside the `PowerMac`,
`PowerBook` and `RackMac` series; `PowerBook9,8` fails only on the K2
`device-id`. Also assert an unlisted `PowerBook9,9` with G4, UniNorth,
`MacRISC2`, and a `Keylargo` Mac-IO with `device-id` 0x3e returns
`kPEMacRISCCompatibleUnlisted`, and that a root whose `compatible` lists
`MacRISC4` is rejected even with an acceptable PVR.

- [ ] **Step 2: Verify compilation fails, then define types**

Add:

```c
#define PE_MACRISC_MODEL_MAX 64
#define PE_MACRISC_MAX_CPUS 4
#define PE_MACRISC_MAX_SOURCES 64
#define PE_MACRISC_MAX_CASCADE 7

typedef enum { kPECPUUnknown, kPECPU750, kPECPU7400, kPECPU7410,
    kPECPU745x, kPECPU970 } PECPUFamily;
typedef enum { kPEMacIOUnknown, kPEMacIOKeyLargo,
    kPEMacIOPangea, kPEMacIOIntrepid, kPEMacIOK2 } PEMacIOFamily;
typedef enum { kPEMacRISCNotMatched, kPEMacRISCSupported,
    kPEMacRISCCompatibleUnlisted, kPEMacRISCMalformed,
    kPEMacRISCUnsupportedCPU, kPEMacRISCUnsupportedHost,
    kPEMacRISCUnsupportedMacIO } PEMacRISCStatus;

typedef struct {
    PEProperty model, rootCompatible, hostCompatible, macIOCompatible;
    PEProperty macIODeviceID;   /* mac-io "device-id", one cell */
    unsigned int pvr;
} PEMacRISCIdentityInput;

PEMacRISCStatus PEMacRISCClassify(const PEMacRISCIdentityInput *input,
    PECPUFamily *cpu, PEMacIOFamily *macIO,
    char model[PE_MACRISC_MODEL_MAX]);
```

- [ ] **Step 3: Implement capability-first classification**

Match PVR families by their high 16 bits, from this table and nothing else:

| PVR high half | Family | Machines |
|---|---|---|
| `0x0008` | `kPECPU750` (750, 750CX/CXe/L) | Sawtooth-era G3, iMac/iBook G3 |
| `0x7000`, `0x7002` | `kPECPU750` (750FX, 750GX) | `PowerBook4,3` and later G3 iBooks |
| `0x000c` | `kPECPU7400` | early G4 |
| `0x800c` | `kPECPU7410` | Cube, Titanium PowerBooks |
| `0x8000`..`0x8004` | `kPECPU745x` (7450, 7455/7445, 7457/7447, 7447A, 7448) | later G4 |
| `0x0039`, `0x003c`, `0x0044` | `kPECPU970` | G5, rejected |

`0x8002` is shared by the 7447 and 7457, so there is no separate 744x
family. Reject 970 before model acceptance. Require a `uni-n` node whose
`compatible` contains `uni-north`; a root that carries a `MacRISC`,
`MacRISC2` or `MacRISC3` member and no `MacRISC4` member; and a `mac-io`
node whose `compatible` contains `Keylargo` and whose `device-id` is 0x22,
0x25 or 0x3e (KeyLargo, Pangea, Intrepid). Any other `device-id` (0x41 K2,
0x4f Shasta) is `kPEMacRISCUnsupportedMacIO`. A model that does not start
with `PowerMac`, `PowerBook` or `RackMac` is `kPEMacRISCNotMatched`; one that
does, but is not in the catalog, is `kPEMacRISCCompatibleUnlisted` once every
capability check passes. Copy at most 63 model bytes after finding its
terminator.

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

Create KeyLargo, Pangea, and Intrepid fixtures (same `Keylargo` compatible,
`device-id` 0x22/0x25/0x3e). Assert Mac-IO `0x80000000/0x80000`, MPIC
`0x80040000/0x40000` (the `interrupt-controller@40000` child of Mac-IO,
translated to an absolute address), 64 sources, two discovered CPUs with boot
CPU 0, a VIA resource from the `via-pmu` or `via-cuda` child, and firmware
CPU/bus/timebase clocks. Remove MESH, floppy, audio, Ethernet, and ATA1 one at
a time and assert the descriptor stays valid with each resource absent. Add
failures for missing Mac-IO/MPIC/CPU, missing VIA when a PMU or CUDA node is
present, source count 0 or 65, zero clocks, range overflow, and cascade width 8.

> **Audit:** the existing `MPIC_*` macros in `chips/mpic.h` add register
> offsets to `powermac_io_info.int_cntlr_base_phys` and use the sum directly
> as an address, and `io_base_virt` is only ever set equal to `io_base_phys`,
> so every published base must be an absolute physical address under the
> identity mapping.

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
    PEResource macIO, mpic, via, serial, mesh, floppy, audio, ethernet;
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

Initialize every DBDMA field to `-1`. Require valid Mac-IO/MPIC ranges, the
MPIC range inside the Mac-IO range, a VIA range whenever `hasPMU` or
`hasCUDA` is set (`mpic_interrupt_initialize` clears the VIA1 registers
unconditionally and the PMU/CUDA drivers read `via_base_phys`), `1..64`
primary sources, `1..4` CPUs, nonzero clocks with `timebaseHz` below `2^31`,
nonwrapping ranges, and a cascade source below `mpicSources` with width at
most 7. Reject DBDMA channels above 31 and conflicting duplicate roles.
Unknown roles return false without modifying state.

`serial` is the `escc-legacy` child (the layout the existing serial driver
expects; today's code hard-codes its `0x12000` offset). `nvramAddress` is the
absolute base of the `nvram,flash` node (two 8 KB banks; the Core99 helpers
in `PowerSurgeMB.m` add `0x2000` for the second bank) and `nvramData` is
absent on flash-NVRAM machines.

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
`compatible`, `device-id`, `reg`, `assigned-addresses`, `AAPL,address`,
`ranges`, address/size cell counts, both interrupt properties, CPU version,
three clock properties, and cache properties. Prefer a well-formed
`AAPL,address` (the existing `get_io_base_addr()` and KeyLargo discovery
already trust it), otherwise translate child registers through parent
`ranges`/`assigned-addresses` using the Task 1 helpers. Count CPUs but retain
boot CPU properties as authoritative. Prefer a well-formed `AAPL,interrupts`,
otherwise use `interrupts`, and keep the second `interrupts` cell (sense) for
Task 8.

Return `kPEMacRISCMalformed` on depth overflow, truncated data, conflicting
duplicate resources, or validation failure. Never cast property bytes to an
integer pointer.

- [ ] **Step 4: Add the kernel DeviceTree transport**

Under `#ifndef MACRISC_HOST_TEST`, adapt `DTLookupEntry(0, "/", ...)`,
`DTCreateEntryIterator`/`DTIterateEntries`/`DTEnterEntry`/`DTExitEntry`/
`DTDisposeEntryIterator`, and `DTGetProperty` (all in
`machdep/ppc/DeviceTree.h`) to the traversal seam. Store one static validated
descriptor; `PEMacRISCGetPlatform` returns null until capture succeeds
completely.

- [ ] **Step 5: Update project metadata and verify**

Append `macrisc_discovery.c macrisc_dt.c` to powermac `CFILES`, their headers
to `HFILES`, and both to `PB.project` (`OTHER_LINKED` and `H_FILES`; the
existing `H_FILES` list is missing the comma after `proc_reg.h`, so add it
when inserting). Run the full host suite. Expected: fake-tree, mutation,
depth, range, and malformed-property cases pass.

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

`get_machine_id()` compares the first root `compatible` member against the
legacy, Yosemite (`iMac`, `PowerMac1,1`, `PowerMac1,2`, `PowerMac2,1`,
`PowerBook1,1`) and Sawtooth identifiers and panics
(`"Unsupported machine"`) in its final `else`. Keep every current comparison
and replace only that final `else` with:

```c
status = PEMacRISCDiscoverDeviceTree(&platformError);
if (status == kPEMacRISCSupported ||
    status == kPEMacRISCCompatibleUnlisted)
    return gestaltMacRISC;
PEMacRISCPrintFailure(status, platformError);
panic("Unsupported MacRISC platform\n");
```

Add the new `identify_machine1` switch case (class, `io_size` from the
descriptor, `powermac_init_p`). Copy `cpu_model` from the validated
descriptor's bounded model. Today `get_machine_id()` rewrites `/` and space
to `-` inside the firmware `compatible` bytes and then `strcpy`s them into
`cpu_model[65]`; remove the in-place rewrite and bound the copy. No listed
identifier contains either character, so only the displayed name of an
unknown machine changes.

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
    unsigned int ioBase, ioSize, interruptBase, dmaBase, viaBase;
    unsigned int serialBase, meshBase, floppyBase, audioBase, ethernetBase;
    unsigned int nvramAddress, nvramData, ata0Base, ata1Base;
} PEMacRISCPublishedIO;

int PEMacRISCPublish(const PEMacRISCPlatform *platform,
    PEMacRISCPublishedIO *published);
int PEMacRISCComputeClockConversion(const PEMacRISCPlatform *platform,
    unsigned int *numerator, unsigned int *denominator,
    unsigned int *period824);
```

Assert absent resources publish as zero rather than `macIO.base`, that
`dmaBase` is `macIO.base + 0x8000` (`DBDMA_REGMAP()` adds `channel << 8` to
`PCI_DMA_BASE_PHYS`, and KeyLargo-family channel 0 sits at Mac-IO offset
`0x8000`), and that `viaBase` is the VIA resource. Assert a 100 MHz bus with
a 25,000,000 Hz timebase yields `numerator == 4000`, `denominator == 100`,
and `period824 == 0x28000000` (40 ns); a 33,333,333 Hz timebase yields a
nonzero fractional part; zero frequency and an 8.24 whole-part overflow fail.

- [ ] **Step 2: Implement pure publication and clock conversion**

Copy absolute bases only when `present` is true. Keep the legacy scale of the
nanosecond pair (`identify_machine2` publishes `4000` over the bus frequency
in MHz, and `drvPPC53c96/Timestamp.c` multiplies by it) and derive the 8.24
decrementer period from the firmware timebase:

```c
if (platform->busClockHz < 1000000U || platform->timebaseHz == 0 ||
    platform->timebaseHz > 0x7fffffffU) return 0;
*numerator = 4000U;
*denominator = platform->busClockHz / 1000000U;
whole = 1000000000U / platform->timebaseHz;
if (whole > 255U) return 0;
remainder = 1000000000U % platform->timebaseHz;
fraction = 0;
for (bit = 0; bit < 24; bit++) {      /* long division, no long long */
    remainder <<= 1;
    fraction <<= 1;
    if (remainder >= platform->timebaseHz) {
        remainder -= platform->timebaseHz;
        fraction |= 1U;
    }
}
*period824 = (whole << 24) | fraction;
```

> **Audit:** the earlier draft published `1e9 / timebaseHz` unreduced, which
> changes the magnitude of a pair the legacy code publishes reduced, and used
> `unsigned long long`, which `-std=c89 -pedantic -Werror` rejects
> (`-Wlong-long`). The kernel copy of this math in `identify_machine2` may
> keep its `long long` under the 1999 compiler; the shared helper may not.

- [ ] **Step 3: Use the descriptor in `identify_machine1/2`**

For MacRISC, set I/O size from the descriptor. In `identify_machine2`, fill
every `powermac_io_info` field from `PEMacRISCPublish` (including
`via_base_phys`, `dma_base_phys`, `floppy_base_phys`; `scsi_ext_base_phys`
and `io_base2` stay zero). Keep the old getter sequence unchanged for other
classes. Do not calculate `io_base + 0` for absent hardware.

Populate `powermac_machine_info` from firmware fields (`cpu_clock_rate_hz`,
`bus_clock_rate_hz`, `dec_clock_rate_hz` = timebase, caches, `l2_cache_size`
from the `l2-cache` node, `l2_cache_type` = `L2_CACHE_BACKSIDE` when present).
For MacRISC skip `do_clock_test()` (it measures against the VIA timer with a
750-style PLL ratio) and `InitBacksideL2()` (firmware has already programmed
L2CR/L3CR on every New World machine; its `RunCacheTests()` would still run
on 750CX/CXe machines because their PVR is also `0x0008`). Use the validated
clock conversion for `dec_clock_period` and the nanosecond pair. Retain both
legacy calls unchanged for other classes.

> **Audit:** `clock_speed.c` already contains `derive_from_of()`, a firmware
> clock path that is dead behind `if (0 && IsYosemite())`. It reads the same
> two CPU properties and shows the `bus_frac` rounding the rest of
> `powermac_machine_info` expects. Either route `DetermineClockSpeeds()` to
> it for MacRISC or reproduce its rounding; do not add a third convention.

- [ ] **Step 4: Advertise only CPU 0**

> **Audit:** `configure_platform()` in `powermac_init.c` already sets only
> `machine_slot[0]` and `machine_info.avail_cpus = 1`, and the PPC kernel is
> configured uniprocessor (`cpus 1` unless a `multi` option is selected), so
> there is no slot array to clear.

Leave `configure_platform()` alone. G4 processors fall through its `default`
to `CPU_SUBTYPE_POWERPC_ALL` because `mach/machine.h` ends at
`CPU_SUBTYPE_POWERPC_750`; do not add a subtype. The only MacRISC work is to
keep `cpuCount` for the boot log and to build every MPIC destination as CPU 0
(Task 8). Assert in the host test that a two-CPU descriptor still yields a
destination mask of 1 for every source.

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
    int useFeatureControl;     /* touch FM_MPIC_CTRL (Fat Man) */
    int disablePassThrough;    /* OpenPIC global config P bit */
    unsigned int destinationMask;
    unsigned int sourceCount;
} PEMPICConfiguration;

int PEMPICValidateConfiguration(const PEMPICConfiguration *configuration);
void PEMPICSetConfiguration(const PEMPICConfiguration *configuration);
int PEMPICSourceInRange(unsigned int source, unsigned int count);
```

Test valid source counts 1 and 64, invalid 0 and 65, valid destination mask 1,
invalid mask 0 or bits above the low four CPUs, independent pass-through and
feature-control flags, source 63 in range, and source 64 out of range. The
policy functions must live in the pure section of `mpic.c` that
`-DMPIC_DIRECT_HOST_TEST` compiles (before `#ifndef MPIC_DIRECT_HOST_TEST`).

> **Audit:** `MPIC_CASCADE` is `0x20` stored with a plain (non-swapped)
> store, so it lands on bit 29 of the OpenPIC global configuration register:
> the 8259 pass-through disable bit. It has nothing to do with the VIA
> cascade and must stay set on every Mac. The earlier `enableCascadeMode`
> name and its coupling to `hasCascade` in Task 8 were wrong.

- [ ] **Step 2: Implement policy with legacy defaults**

Initialize private state to `{ 1, 1, 1, 64 }`. In initialization, touch
`FM_MPIC_CTRL` only when requested, set `MPIC_CASCADE` when
`disablePassThrough` is set, validate `sourceCount == nmpic_interrupts`, and
check that every table destination equals the configured mask (the mask is
baked into the mapping table by Task 8, not rewritten here).

> **Audit:** `FM_MPIC_CTRL` is `POWERMAC_IO(mem_cntlr_base_phys + 0x160)`.
> On Sawtooth `get_mem_cntlr_base_addr()` finds neither `hammerhead` nor
> `fatman` and returns 0, so the legacy default performs a read-modify-write
> of physical `0x160`, inside the exception-vector page. The `{ 1, ... }`
> default preserves that for Sawtooth because this plan promises not to
> change its behaviour; the Cube control boot in Task 12 is the place to
> confirm whether `configure_sawtooth` can pass `useFeatureControl = 0` as a
> separate, hardware-verified commit.

- [ ] **Step 3: Bound interrupt acknowledge**

`mpic_enable_irq()` and `mpic_disable_irq()` already reject sources outside
`nmpic_interrupts`; only the acknowledge loop in `mpic_interrupt()` indexes
`MPIC_INT_CFG + irq * 0x20` and `mpic_interrupts[irq]` with the raw vector.
There, require `irq < nmpic_interrupts` before the `ACTIVE` read. Treat
`0xff` and any out-of-range vector as no pending interrupt. Preserve EOI
ordering for valid sources. Leave the spurious vector at `0x31` (source 49);
with the bound in place a spurious acknowledge on a 64-source table falls
through the `ACTIVE` test as it does today.

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
and sense/polarity follow the second `interrupts` cell captured in Task 4,
decoded the way Darwin's AppleMPIC and Linux `mpic_host_xlate` do:

| sense cell | table flags |
|---|---|
| 0 | `EDGE \| ACT_HI` (DBDMA channels) |
| 1 | `LVL \| ACT_LOW` (devices) |
| 2 | `LVL \| ACT_HI` |
| 3 | `EDGE \| ACT_LOW` |
| absent | `LVL \| ACT_LOW` |

Sources without a device keep direct logical identities
(`PMAC_DEV_MPIC_DIRECT_BASE + source`), and absent DBDMA roles remain `-1`.

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

`macrisc_initialize_bats` takes the `boot_args *` that
`machine_initialize_processors` passes (declare it with the parameter; the
Sawtooth version relies on an old-style declaration). Use fixed storage for 64
primary interrupts, 7 cascade children (same layout as
`sawtooth_via1_interrupts`), and 128 mapping words. Clear handler, level, and
argument fields; initialize all logical device fields to `-1` before applying
discovered roles.

- [ ] **Step 3: Configure runtime state from the validated descriptor**

Revalidate the global descriptor, build both tables, assign the existing
MPIC globals and counts, and set:

```c
configuration.useFeatureControl = 0;
configuration.disablePassThrough = 1;
configuration.destinationMask = 1;
configuration.sourceCount = platform->mpicSources;
PEMPICSetConfiguration(&configuration);
```

The VIA cascade is the VIA's own MPIC source taken from the `via-cuda` or
`via-pmu` node (25 on Cuda desktops, 47 on PMU machines), never the fixed
`0x19`: set `mpic_via_cascade` from `platform->cascadeSource` and install
`mpic_via1_interrupt` on that slot only when `hasCascade` is set.
`powermac_info.viaIRQ` follows the formula the other families use,
`(platform->mpicSources + 2) ^ 0x18` (Sawtooth's literal `0x5a` is
`(64 + 2) ^ 0x18`, the cascade child `PMAC_DEV_VIA1` in DriverKit's XOR
form). Initialize KeyLargo services only on compatible Mac-IO
(`PEKeyLargoInitialize()` already tolerates Pangea and Intrepid because it
matches `device_type = mac-io` and compares the published base and size);
its audio I2C failure must not block boot.

- [ ] **Step 4: Map discovered early-I/O segments**

Map the 256 MB segment containing Mac-IO (the MPIC is inside it). Do not
copy Sawtooth's unconditional segment pair: `initialize_bats()` has already
installed BAT0 for the first 256 MB of RAM and used `PEMapSegment` for
`0xf0000000` and the boot framebuffer segment before the family hook runs,
and only three BATs (`availableBATs = 0xE`) exist, so the Mac-IO segment is
the last one available. `PEMapSegment` returns the address when the segment
is already resident and 0 only on failure, so a zero result is fatal; there
is no separate `PEResidentAddress` check to make.

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

Assert a platform with a PMU or CUDA node returns exactly two entries in
DriverKit's XOR form: `output[0]` is the VIA cascade child
(`(mpicSources + 2) ^ 0x18`) and `output[1]` is the VIA's firmware MPIC
source `^ 0x18`; a platform without either returns zero; a VIA source above
63 returns zero; no source is invented.

> **Audit:** both `pmu.m` copies (byte-identical) build a two-entry list:
> entry 0 is whatever `identify_via_irq()` wrote into the node (the cascade
> child), entry 1 is the raw VIA line, hard-coded as `47 ^ 0x18` on Sawtooth.
> The earlier draft passed the firmware list through unchanged, which after
> `identify_via_irq()` is one entry and would leave the PMU without its
> interrupt.

- [ ] **Step 2: Preserve MacRISC firmware lists in both PMU source copies**

In `PEEditDTEntry`, for the `via-pmu` and `via-cuda` node names on a MacRISC
machine, publish `AAPL,interrupts` as the two-entry list from
`PEMacRISCPMUInterruptList` (static storage, same XOR representation the
tree already uses). Then, after reading the DriverKit list in both `pmu.m`
copies, use:

```objc
if (IsMacRISC()) {
    /* PExpert published both entries: cascade child, raw VIA source. */
    if ([deviceDescription numInterrupts] != 2) {
        [self free];
        return nil;
    }
    newIRQs[0] = oldIRQs[0];
    newIRQs[1] = oldIRQs[1];
} else if (IsSawtooth()) {
    /* unchanged */
} else {
    /* unchanged */
}
[deviceDescription setInterruptList:newIRQs num:2];
```

Never use fixed source 47 for MacRISC. `identify_via_irq()` may still
rewrite the node in place; the `PEEditDTEntry` list is what DriverKit reads.

- [ ] **Step 3: Apply Core99 NVRAM rules**

Change only Core99 conditionals in `InitNVRAMPartitions` (`identify_machine.c`)
and `cuda_restart`, `ReadNVRAM`, and `WriteNVRAM` (`PowerSurgeMB.m`) from
`IsSawtooth()` to `IsCore99()`. Keep the underlying access and partition code
unchanged; `InitCore99NVRAM()` reads the two 8 KB banks at
`PCI_NVRAM_ADDR_PHYS` and `+0x2000`, so the MacRISC descriptor must publish
the absolute `nvram,flash` base (Task 3), which reaches physical memory
through the identity mapping and the `0xf0000000` BAT.

Also change the two `powermac_info.class == POWERMAC_CLASS_SAWTOOTH` tests at
the top of `PEEditDTEntry` to `IsCore99()`: the AGP bridge class-code rewrite
(`pci-bridge` compatible) is what lets DriverKit see devices behind the
UniNorth AGP bridge, and the USB filter keeps DriverKit to the first HID
device. Both are UniNorth properties, not Sawtooth ones.

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
must come from CPU/host capability checks. Pair each positive row with the
Mac-IO `device-id` its generation ships (0x22 KeyLargo, 0x25 Pangea, 0x3e
Intrepid) and a PVR from the Task 2 table. Check `PowerBook2,3` and
`PowerBook6,6` against Apple's identifier list before keeping them; a wrong
catalog entry only mislabels the boot log, because unlisted compatible
machines are accepted anyway.

- [ ] **Step 2: Demonstrate red then green catalog behavior**

Run the discovery test before extending the catalog and record at least one
expected failure. Expand only the table, not per-model branches, then rerun.

- [ ] **Step 3: Add bounded diagnostics**

Print one line containing bounded model, status, CPU, Mac-IO (named from the
`device-id` mapping), and validation error. Constant lookup functions use
`unknown` fallbacks. Required forms:

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

> **Audit:** two remote workflows exist. `vm/rhap-vm.ps1` (PuTTY,
> `RemoteRoot` default `/build/source`) drives the historical Rhapsody build
> guest; `vm/sync-src.ps1` and `vm/build-src.ps1 -KernelDrivers` (OpenSSH,
> `RemoteRoot` `/build`, tree at `/build/src`) drive the PPC build box, whose
> bootstrap `docs/build/xserve-bootstrap.md` records as blocked. Use whichever
> host currently builds the PPC kernel: sync with that workflow's sync
> command, run the shell lines below through its `ssh` command, and
> substitute its configured `RemoteRoot` for `$ROOT`. Do not hard-code
> `/build/source`.

- [ ] **Step 1: Sync and build the platform expert on the PPC build host**

```sh
cd $ROOT/src/drivers-ppc/bus/drvPExpert && gnumake clean all install DSTROOT=/
```

Expected: exit 0 and `macrisc_discovery.o`, `macrisc_dt.o`, and family
`macrisc.o` are included in `pexpertpowermac.o`.

- [ ] **Step 2: Build the PPC kernel**

```sh
cd $ROOT/src/kernel-7 && gnumake clean kernels
```

Expected: exit 0 and a newly linked PPC kernel.

- [ ] **Step 3: Inspect symbols and size**

```sh
nm -g $ROOT/src/drivers-ppc/bus/drvPExpert/powermac/pexpertpowermac.o | egrep 'PEMacRISC|macrisc_init|configure_macrisc'
size $ROOT/src/drivers-ppc/bus/drvPExpert/powermac/pexpertpowermac.o
```

Expected: each public symbol appears once, the final kernel has no unresolved
MacRISC symbol, and the object remains within existing link/package limits.

- [ ] **Step 4: Correct only evidenced build defects**

Rerun all host tests after any correction. Stage only directly related files
and commit with `drvPExpert: build later MacRISC support`. If the clean build
needed no correction, do not create an empty commit.

### Task 12: Validate Cube, PowerBook, and Xserve hardware

**Files:**
- Create: `docs/boot/ppc-macrisc-validation.md`

> **Audit:** there is no `docs/hardware/`; boot evidence lives in `docs/boot/`
> beside `boot-ppc.md`, and `docs/build/xserve-bootstrap.md` shows the shape
> of a hardware evidence record. If the dual-processor Xserve is the same
> machine that serves as the PPC build host, booting it from a test disk
> takes the build host offline: finish Task 11's builds first and boot from a
> dedicated disk. If Task 7's `useFeatureControl` question is taken up, the
> Cube control boot is where a Sawtooth `useFeatureControl = 0` build gets
> its evidence.

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
git add docs/boot/ppc-macrisc-validation.md
git commit -m "docs: record MacRISC hardware validation"
```

### Task 13: Final regression and scope audit

**Files:**
- Inspect all files changed by Tasks 1-12.

- [ ] **Step 1: Run clean host and guest verification**

```powershell
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host clean
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host test
```

Then, through the PPC build host's `ssh` command (Task 11), with its
configured `RemoteRoot` as `$ROOT`:

```sh
cd $ROOT/src/drivers-ppc/bus/drvPExpert && gnumake clean all install DSTROOT=/
cd $ROOT/src/kernel-7 && gnumake clean kernels
```

Expected: zero host warnings/failures and both remote builds exit 0.

- [ ] **Step 2: Audit unsafe assumptions**

```powershell
rg -n "PowerMac7|PROCESSOR_VERSION_970|K2-Keylargo|\bu3\b" src/drivers-ppc/bus/drvPExpert
rg -n "\"Pangea\"|\"Intrepid\"|\"KeyLargo\"" src/drivers-ppc/bus/drvPExpert/powermac
rg -n "0x5a|0x19|tmpIRQ = 47|HEATHROW_SIZE|enableCascadeMode" src/drivers-ppc/bus/drvPExpert/powermac src/drivers-ppc/input/drvPPCPMU src/kernel-7/bsd/dev/ppc
rg -n "\(unsigned int \*\).*bytes|bytes.*\(unsigned int \*\)" src/drivers-ppc/bus/drvPExpert/powermac/macrisc_discovery.c src/drivers-ppc/bus/drvPExpert/powermac/macrisc_dt.c
```

Expected: G5 strings occur only in rejection/tests, no code compares a
Mac-IO `compatible` against `Pangea`, `Intrepid` or `KeyLargo` (the
classifier keys on `device-id` and the firmware spelling `Keylargo`), fixed
Sawtooth constants occur only in the Sawtooth family and the legacy `pmu.m`
branch, and property decoders contain no unaligned integer casts.

- [ ] **Step 3: Audit diff and repository state**

```powershell
git diff --check
git status --short
git log --oneline -- src/drivers-ppc/bus/drvPExpert docs/boot/ppc-macrisc-validation.md
```

Expected: no whitespace errors or tracked generated binaries; every changed
file is in the file structure or is an evidenced build correction.

- [ ] **Step 4: Apply completion workflows**

Invoke `superpowers:verification-before-completion`, then
`superpowers:finishing-a-development-branch`. Present integration choices only
after reading fresh host-test, guest-build, and available hardware evidence.
