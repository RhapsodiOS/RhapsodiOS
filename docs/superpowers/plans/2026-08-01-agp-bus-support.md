# AGP Bus Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared AGP 1.0/2.0 service to DriverKit and the kernel, backed by Apple UniNorth on PPC and Intel 440BX on i386, and usable by both kernel and user DriverKit clients.

**Architecture:** Allocation-free C89 helpers implement capability negotiation, handles, range allocation, and backend transaction rules under host tests. A kernel Objective-C broker owns sessions, wired `IOMemoryDescriptor` objects, GART state, rollback, and task-death cleanup; kernel and user `IOAGPDevice` facades call it directly or through typed MIG routines. Thin architecture adapters connect the broker to UniNorth's device-tree PCI path and 440BX's `PCIKernBus` configuration service.

**Tech Stack:** ANSI C89, Objective-C DriverKit, Mach/MIG RPC, Mach VM and port-death notification, PCI AGP 1.0/2.0 capabilities, UniNorth and Intel 440BX configuration registers, Project Builder/gnumake, host C tests, Rhapsody ppc/i386 builds, real Sawtooth and 440BX hardware.

**Spec:** `docs/superpowers/specs/2026-08-01-agp-bus-support-design.md`

---

## File structure

### New public/private DriverKit API

- `src/driverkit-3/driverkit/IOAGPTypes.h`: fixed-width flags, states, status, and opaque handles shared by both architectures and RPC.
- `src/driverkit-3/driverkit/IOAGPDevice.h`: public facade lifecycle and `IODirectDevice` convenience category.
- `src/driverkit-3/driverkit/IOAGPDevicePrivate.h`: broker/backend entry points and kernel-only structures.
- `src/driverkit-3/libDriver/Kernel/IOAGPDevice.m`: direct kernel facade.
- `src/driverkit-3/libDriver/User/IOAGPDevice.m`: user proxy and memory-range marshaling.

### Shared kernel implementation

- `src/kernel-7/driverkit/agp_core.{c,h}`: bounded PCI capability walk, conservative command negotiation, state transitions, counters, and generation-tagged handle validation.
- `src/kernel-7/driverkit/agp_range.{c,h}`: fixed-capacity page-range allocator.
- `src/kernel-7/driverkit/agp_mapping.{c,h}`: host-testable wire, page-staging, PTE-write, flush, and rollback transaction.
- `src/kernel-7/driverkit/IOAGPBroker.{h,m}`: sessions, locks, wired descriptors, GART allocation, transactions, teardown, faults, and registry.
- `src/kernel-7/driverkit/IOAGPBackend.h`: backend callback contract.
- `src/kernel-7/driverkit/IOAGPUserServer.{h,m}`: typed RPC endpoints and task-port death tracking.

### Architecture backends

- `src/kernel-7/driverkit/i386/agp_440bx.{c,h}`: host-testable 440BX identification, size table, PTE encoding, and register sequence.
- `src/driverkit-3/libDriver/i386/IOIntel440BXAGP.m`: `PCIKernBus` adapter and backend registration.
- `src/kernel-7/driverkit/ppc/agp_uninorth.{c,h}`: host-testable UniNorth identification, size table, little-endian PTE encoding, and register sequence.
- `src/driverkit-3/libDriver/ppc/IOUniNorthAGP.m`: device-tree/`IOMacRiscPCIBridge` adapter and backend registration.

### Tests and diagnostics

- `src/kernel-7/driverkit/tests/Makefile.host`: strict C89 host suite.
- `src/kernel-7/driverkit/tests/agp_core_test.c`: capabilities, negotiation, handles, and state.
- `src/kernel-7/driverkit/tests/agp_range_test.c`: range allocation and stale-handle coverage.
- `src/kernel-7/driverkit/tests/agp_transaction_test.c`: fake backend, failure injection, rollback, and teardown.
- `src/kernel-7/driverkit/tests/agp_440bx_test.c`: 440BX register/PTE fixtures.
- `src/kernel-7/driverkit/tests/agp_uninorth_test.c`: UniNorth register/PTE fixtures.
- `src/driverkit-3/tests/agptest.m`: user facade lifecycle and death-cleanup utility.
- `src/kernel-7/driverkit/AGPTest.m`: debug-only kernel harness.

## Invariants for every task

- Start implementation in a dedicated worktree. Before Task 1, invoke `superpowers:using-git-worktrees` and create `codex/agp-bus-support`; do not implement on the current dirty `qemu-debug-loop` worktree.
- Host code compiles with `-std=c89 -pedantic -Wall -Wextra -Werror` and performs no allocation through libc.
- All public fields and MIG scalars are fixed-width 32-bit values. Zero is never a valid handle.
- AGP is dormant until a client explicitly creates a space.
- No backend accesses i386 PCI ports directly; it must use `PCIKernBus`.
- No client supplies physical addresses. The broker derives them only from a successfully wired, task-owned `IOMemoryDescriptor`.
- Fast writes and 4x are always cleared. Choose 2x if mutual, otherwise 1x. SBA is enabled only if mutual.
- Every hardware mutation is serialized by the bridge lock and has an explicit rollback path.
- Stage only files named by the current task. Never use `git add -A` or `git commit -a`.
- Real-hardware work uses temporary/dedicated disks, as required by `CLAUDE.md`.

## Primary hardware references

- Apple API semantics: `https://github.com/apple-oss-distributions/IOPCIFamily/blob/main/IOKit/pci/IOAGPDevice.h`
- UniNorth GART constants/sequences: `https://github.com/torvalds/linux/blob/master/arch/powerpc/include/asm/uninorth.h` and `drivers/char/agp/uninorth-agp.c`
- Intel generic/440BX GART constants/sequences: `https://github.com/torvalds/linux/blob/master/drivers/char/agp/intel-agp.h` and `intel-agp.c`

Use those sources as behavioral references. Do not copy implementation text; write RhapsodiOS-native code from the documented register facts and sequences.

### Task 1: Define the public ABI and conservative AGP negotiation

**Files:**
- Create: `src/driverkit-3/driverkit/IOAGPTypes.h`
- Create: `src/driverkit-3/driverkit/IOAGPDevice.h`
- Create: `src/kernel-7/driverkit/agp_core.h`
- Create: `src/kernel-7/driverkit/agp_core.c`
- Create: `src/kernel-7/driverkit/tests/agp_core_test.c`
- Create: `src/kernel-7/driverkit/tests/Makefile.host`
- Modify: `src/driverkit-3/driverkit/Makefile`

- [ ] **Step 1: Write the failing negotiation tests**

Create `agp_core_test.c` with a local `CHECK` macro and these exact cases:

```c
static void test_conservative_command(void)
{
    AGPCapability host = { 0x20000000U | AGP_RATE_1X | AGP_RATE_2X |
        AGP_RATE_4X | AGP_SBA | AGP_FAST_WRITE };
    AGPCapability master = { 0x10000000U | AGP_RATE_1X | AGP_RATE_2X |
        AGP_RATE_4X | AGP_SBA | AGP_FAST_WRITE };
    unsigned int command = 0;

    CHECK(AGPNegotiate(&host, &master, &command) == IO_R_SUCCESS);
    CHECK((command & AGP_ENABLE) != 0);
    CHECK((command & AGP_RATE_MASK) == AGP_RATE_2X);
    CHECK((command & AGP_SBA) != 0);
    CHECK((command & (AGP_RATE_4X | AGP_FAST_WRITE)) == 0);
    CHECK((command & AGP_REQUEST_QUEUE_MASK) == 0x10000000U);
}

static void test_one_x_fallback_and_no_common_rate(void)
{
    AGPCapability host = { AGP_RATE_1X | AGP_RATE_2X | AGP_SBA };
    AGPCapability master = { AGP_RATE_1X };
    unsigned int command;
    CHECK(AGPNegotiate(&host, &master, &command) == IO_R_SUCCESS);
    CHECK((command & AGP_RATE_MASK) == AGP_RATE_1X);
    host.status = AGP_RATE_2X;
    CHECK(AGPNegotiate(&host, &master, &command) == IO_R_UNSUPPORTED);
}
```

Add capability-walk fixtures for a valid linked list, a missing AGP capability, an unaligned pointer, an offset below `0x40`, an offset above `0xfc`, a cycle, and more than 48 hops.

- [ ] **Step 2: Add the strict host target and verify red**

```make
HOST_CC ?= cc
HOST_CFLAGS ?= -std=c89 -pedantic -Wall -Wextra -Werror

agp_core_test: agp_core_test.c ../agp_core.c
	$(HOST_CC) $(HOST_CFLAGS) -DAGP_HOST_TEST -I.. \
	    -I../../../driverkit-3/driverkit -o $@ agp_core_test.c ../agp_core.c

test: agp_core_test
	./agp_core_test

clean:
	rm -f agp_core_test
```

Run `gnumake -C src/kernel-7/driverkit/tests -f Makefile.host agp_core_test`. Expected: FAIL because the headers and functions do not exist.

- [ ] **Step 3: Define the fixed ABI**

`IOAGPTypes.h` must define these names and values:

```c
typedef unsigned int IOAGPSession;
typedef unsigned int IOAGPRange;
typedef unsigned int IOAGPMapping;

#define IO_AGP_INVALID_HANDLE       0U
#define IO_AGP_PAGE_SIZE            4096U
#define IO_AGP_MAX_LOGICAL_RANGES   256U

#define AGP_RATE_1X                 0x00000001U
#define AGP_RATE_2X                 0x00000002U
#define AGP_RATE_4X                 0x00000004U
#define AGP_FAST_WRITE              0x00000010U
#define AGP_SBA                     0x00000200U
#define AGP_ENABLE                  0x00000100U
#define AGP_RATE_MASK               0x00000007U
#define AGP_REQUEST_QUEUE_MASK      0xff000000U
#define IO_AGP_GART_INVALIDATE      0x00000001U

typedef enum {
    IOAGPStateReady = 1,
    IOAGPStateOwned = 2,
    IOAGPStateEnabled = 3,
    IOAGPStateFaulted = 4
} IOAGPState;
```

Define `IOAGPStatus` with `state`, `command`, `apertureBase`, `apertureLength`, the seven counters from the spec, `lastFault`, and eight reserved words.

Define the public facade exactly as follows (with the repository's standard imports for `Object`, `IODirectDevice`, `IODeviceDescription`, and `IOMemoryDescriptor`):

```objc
@interface IOAGPDevice : Object
+ (IOAGPDevice *)deviceWithDescription:(IODeviceDescription *)description;
- (IOReturn)acquireAGPSession:(IOAGPSession *)session;
- (IOReturn)releaseAGPSession;
- (IOReturn)createAGPSpace:(unsigned int)options
                   address:(unsigned int *)address
                    length:(unsigned int *)length;
- (IOReturn)destroyAGPSpace;
- (IOReturn)reserveAGPRange:(unsigned int)length
                  alignment:(unsigned int)alignment
                      range:(IOAGPRange *)range
                     offset:(unsigned int *)offset;
- (IOReturn)releaseAGPRange:(IOAGPRange)range;
- (IOReturn)commitAGPMemory:(IOMemoryDescriptor *)memory
                      range:(IOAGPRange)range
                    options:(unsigned int)options
                    mapping:(IOAGPMapping *)mapping;
- (IOReturn)releaseAGPMemory:(IOAGPMapping)mapping;
- (IOReturn)getAGPSpace:(unsigned int *)address
                  length:(unsigned int *)length;
- (IOReturn)getAGPStatus:(IOAGPStatus *)status;
- (IOReturn)resetAGP:(unsigned int)options;
@end

@interface IODirectDevice (IOAGPDirectDevice)
- (IOAGPDevice *)AGPDevice;
@end
```

- [ ] **Step 4: Implement bounded capability parsing and negotiation**

Use this callback boundary in `agp_core.h`:

```c
typedef int (*AGPConfigRead32)(void *context, unsigned int offset,
    unsigned int *value);
typedef struct { unsigned int status; } AGPCapability;

int AGPFindCapability(AGPConfigRead32 read32, void *context,
    unsigned int firstPointer, unsigned int capabilityID,
    unsigned int *capabilityOffset);
int AGPNegotiate(const AGPCapability *host, const AGPCapability *master,
    unsigned int *command);
```

`AGPFindCapability` accepts only aligned offsets `0x40..0xfc`, tracks visited offsets in a 64-bit bitmap indexed by `(offset - 0x40) / 4`, and stops after 48 hops. `AGPNegotiate` takes the minimum encoded request depth, clears 4x and fast-write before selecting the rate, and returns `IO_R_UNSUPPORTED` without modifying `*command` if no 1x/2x rate is mutual.

- [ ] **Step 5: Verify green and header installation**

Run the host suite. Then add `IOAGPTypes.h` and `IOAGPDevice.h` to `PUBLIC_HFILES` in `src/driverkit-3/driverkit/Makefile`. Run `git diff --check`.

- [ ] **Step 6: Commit**

```powershell
git add src/driverkit-3/driverkit/IOAGPTypes.h src/driverkit-3/driverkit/IOAGPDevice.h src/driverkit-3/driverkit/Makefile src/kernel-7/driverkit/agp_core.h src/kernel-7/driverkit/agp_core.c src/kernel-7/driverkit/tests/agp_core_test.c src/kernel-7/driverkit/tests/Makefile.host
git commit -m "driverkit: define AGP ABI and negotiation"
```

### Task 2: Add range allocation and generation-safe handles

**Files:**
- Create: `src/kernel-7/driverkit/agp_range.h`
- Create: `src/kernel-7/driverkit/agp_range.c`
- Modify: `src/kernel-7/driverkit/agp_core.h`
- Modify: `src/kernel-7/driverkit/agp_core.c`
- Create: `src/kernel-7/driverkit/tests/agp_range_test.c`
- Modify: `src/kernel-7/driverkit/tests/Makefile.host`

- [ ] **Step 1: Write failing first-fit and stale-handle tests**

Test a 16-page aperture with reservations `(4 pages, align 1)`, `(2 pages, align 4)`, release/reuse of the first hole, exhaustion, overflow, double release, and release while mapped. Add a handle test that frees slot 3, reallocates slot 3, and proves the old generation is rejected.

```c
CHECK(AGPRangeReserve(&ranges, 4, 1, &h1, &off1) == IO_R_SUCCESS);
CHECK(off1 == 0);
CHECK(AGPRangeReserve(&ranges, 2, 4, &h2, &off2) == IO_R_SUCCESS);
CHECK(off2 == 4);
CHECK(AGPRangeRelease(&ranges, h1) == IO_R_SUCCESS);
CHECK(AGPRangeRelease(&ranges, h1) == IO_R_INVALID_ARG);
```

- [ ] **Step 2: Verify red**

Run `gnumake -C src/kernel-7/driverkit/tests -f Makefile.host agp_range_test`. Expected: missing `agp_range.h`.

- [ ] **Step 3: Implement fixed-capacity first-fit allocation**

Use 256 slots, page units, and no dynamic allocation:

```c
#define AGP_MAX_RANGES 256
typedef struct {
    unsigned int startPage, pageCount, generation;
    unsigned char used, mapped;
} AGPRangeSlot;
typedef struct {
    unsigned int aperturePages;
    AGPRangeSlot slots[AGP_MAX_RANGES];
} AGPRangeAllocator;
```

Encode handles as `(generation << 8) | (slot + 1)`, reserve generation zero, reject multiplication/addition overflow before converting bytes to pages, and sort occupied slots by scanning for the lowest aligned gap instead of maintaining a second list.

- [ ] **Step 4: Add the shared handle table**

Add `AGPHandleTable` to `agp_core` with 256 slots containing `kind`, `generation`, `owner`, and `value`. Implement allocate, lookup, and release with kind/owner checks. Unit-test session/range/mapping kind confusion and generation wrap skipping zero.

- [ ] **Step 5: Run both suites and commit**

```powershell
gnumake -C src/kernel-7/driverkit/tests -f Makefile.host test
git add src/kernel-7/driverkit/agp_range.h src/kernel-7/driverkit/agp_range.c src/kernel-7/driverkit/agp_core.h src/kernel-7/driverkit/agp_core.c src/kernel-7/driverkit/tests/agp_range_test.c src/kernel-7/driverkit/tests/Makefile.host
git commit -m "kernel: add AGP ranges and safe handles"
```

### Task 3: Define the backend contract and transactional state machine

**Files:**
- Create: `src/kernel-7/driverkit/IOAGPBackend.h`
- Create: `src/kernel-7/driverkit/agp_transaction.h`
- Create: `src/kernel-7/driverkit/agp_transaction.c`
- Create: `src/kernel-7/driverkit/tests/agp_transaction_test.c`
- Modify: `src/kernel-7/driverkit/tests/Makefile.host`

- [ ] **Step 1: Write a fake backend with an operation log**

The test backend records `ALLOC_GART`, `PROGRAM`, `WRITE_PTES`, `FLUSH`, `ENABLE_TARGET`, `ENABLE_MASTER`, `DISABLE_MASTER`, `DISABLE_TARGET`, `CLEAR_PTES`, and `FREE_GART`. Inject a failure at each ordinal and assert the exact reverse-order suffix. In particular, a failure after master enable must produce:

```text
DISABLE_MASTER DISABLE_TARGET CLEAR_PTES FLUSH FREE_GART
```

- [ ] **Step 2: Verify red**

Run the transaction target. Expected: missing backend/transaction headers.

- [ ] **Step 3: Define the backend callbacks**

```c
typedef struct IOAGPBackendOps {
    IOReturn (*chooseAperture)(void *, unsigned int, unsigned int *);
    IOReturn (*allocateGART)(void *, unsigned int, void **,
        unsigned int *);
    IOReturn (*freeGART)(void *, void *, unsigned int);
    IOReturn (*programAperture)(void *, unsigned int, unsigned int,
        unsigned int);
    IOReturn (*encodePTE)(void *, unsigned int, unsigned int *);
    IOReturn (*writePTEs)(void *, unsigned int, const unsigned int *,
        unsigned int);
    IOReturn (*clearPTEs)(void *, unsigned int, unsigned int);
    IOReturn (*flushGART)(void *);
    IOReturn (*setTargetCommand)(void *, unsigned int);
    IOReturn (*setMasterCommand)(void *, unsigned int);
    IOReturn (*disableMaster)(void *);
    IOReturn (*disableTarget)(void *);
    IOReturn (*reset)(void *);
    IOReturn (*readStatus)(void *, IOAGPStatus *);
} IOAGPBackendOps;
```

The contract requires idempotent `clearPTEs`, `disableMaster`, and `disableTarget`. `allocateGART` returns both kernel address and physical address, and fails if the allocation is not contiguous or backend-addressable.

- [ ] **Step 4: Implement state transitions and rollback**

`AGPTransactionCreate` moves `Owned -> Enabled` only after GART program, target enable, master enable, and final flush succeed. `AGPTransactionDestroy` always attempts every reverse action, returns the first error, and reports whether safe disable was verified; callers enter `Faulted` when it was not.

- [ ] **Step 5: Run failure injection and commit**

Run all host tests; expected: every injected ordinal returns the original failure and leaves the fake backend disabled with zero live entries.

```powershell
git add src/kernel-7/driverkit/IOAGPBackend.h src/kernel-7/driverkit/agp_transaction.h src/kernel-7/driverkit/agp_transaction.c src/kernel-7/driverkit/tests/agp_transaction_test.c src/kernel-7/driverkit/tests/Makefile.host
git commit -m "kernel: add transactional AGP backend contract"
```

### Task 4: Implement the kernel broker and wired-memory transactions

**Files:**
- Create: `src/kernel-7/driverkit/IOAGPBroker.h`
- Create: `src/kernel-7/driverkit/IOAGPBroker.m`
- Create: `src/kernel-7/driverkit/agp_mapping.h`
- Create: `src/kernel-7/driverkit/agp_mapping.c`
- Create: `src/driverkit-3/driverkit/IOAGPDevicePrivate.h`
- Create: `src/driverkit-3/libDriver/Kernel/IOAGPDevice.m`
- Create: `src/kernel-7/driverkit/tests/agp_broker_contract_test.c`
- Modify: `src/kernel-7/driverkit/tests/Makefile.host`

- [ ] **Step 1: Add a broker contract test around a fake memory provider**

The `agp_mapping` host seam supplies `wire`, `pageAt`, `checkpoint`, and `unwire` callbacks plus the Task 3 backend. Test fragmented pages `0x00123000`, `0x00abc000`, and `0x00045000`, then fail page lookup at index 1 and PTE write after entry 1. Assert zero published mappings, cleared fake GART entries, and exactly one unwind/checkpoint-complete call.

- [ ] **Step 2: Verify red**

Run `agp_broker_contract_test`; expected: missing broker seam.

- [ ] **Step 3: Define broker objects and registry**

`IOAGPBroker` owns one `NXLock`, `AGPRangeAllocator`, `AGPHandleTable`, 256 mapping slots, backend context/ops, state/status, owner task/port, GART address/physical/length, aperture base/length, and negotiated command. Export:

```objc
+ (IOReturn)registerBackend:(const IOAGPBackendOps *)ops
                    context:(void *)context
                     master:(id)master
                     broker:(IOAGPBroker **)broker;
+ (IOAGPBroker *)brokerForMaster:(id)master;
- (IOReturn)acquireForTask:(vm_task_t)task ownerPort:(port_t)port
                    handle:(IOAGPSession *)handle;
- (IOReturn)commitMemory:(IOMemoryDescriptor *)memory
                 session:(IOAGPSession)session range:(IOAGPRange)range
                 options:(unsigned int)options mapping:(IOAGPMapping *)mapping;
- (void)clientPortDied:(port_t)port;
```

Registration rejects a second backend for the same master and never publishes unsupported pairs.

- [ ] **Step 4: Implement commit and release exactly in transaction order**

Implement `AGPMappingCommit()` and `AGPMappingRelease()` in `agp_mapping.c`. Commit must: validate under lock; call the wire callback; enumerate and stage every physical page; call `encodePTE` for all pages before the first write; call `writePTEs`; call `flushGART`; then return a prepared mapping record. The Objective-C broker marks the range mapped and publishes the mapping handle only after that return. Release must clear, flush, checkpoint-complete, unwire, clear the range's mapped flag, then release the handle. Never call the unwire callback while the mapping is still reachable.

- [ ] **Step 5: Add the direct kernel facade**

Implement `IOAGPDevice` as a small object holding `_broker`, `_master`, and `_session`. Every public method forwards to the broker and returns `IO_R_NOT_OPEN` when no session exists. Its `free` method performs `destroyAGPSpace`, releases the session, and then calls `[super free]`.

- [ ] **Step 6: Run tests and commit**

```powershell
gnumake -C src/kernel-7/driverkit/tests -f Makefile.host test
git add src/kernel-7/driverkit/IOAGPBroker.h src/kernel-7/driverkit/IOAGPBroker.m src/kernel-7/driverkit/agp_mapping.h src/kernel-7/driverkit/agp_mapping.c src/driverkit-3/driverkit/IOAGPDevicePrivate.h src/driverkit-3/libDriver/Kernel/IOAGPDevice.m src/kernel-7/driverkit/tests/agp_broker_contract_test.c src/kernel-7/driverkit/tests/Makefile.host
git commit -m "kernel: add the shared AGP broker"
```

### Task 5: Wire the broker and facade into both builds

**Files:**
- Modify: `src/kernel-7/conf/files`
- Modify: `src/driverkit-3/driverkit/Makefile`
- Modify: `src/driverkit-3/libDriver/Makefile`

- [ ] **Step 1: Establish build baselines in the build guest**

Run:

```powershell
powershell -File vm\sync-src.ps1 -Path driverkit-3
powershell -File vm\sync-src.ps1 -Path kernel-7
powershell -File vm\build-src.ps1 -KernelDrivers
```

Expected: the existing driverkit and both configured kernel builds complete before AGP objects are listed. Record unrelated pre-existing failures separately.

- [ ] **Step 2: Add common and architecture object lists**

Add `driverkit/agp_core.c`, `driverkit/agp_range.c`, `driverkit/agp_transaction.c`, `driverkit/agp_mapping.c`, and `driverkit/IOAGPBroker.m` as optional DriverKit files in `conf/files`. Do not list `IOAGPUserServer.m` until Task 6 and do not list architecture backends until Tasks 7 and 9.

Add `IOAGPDevice.m` to `KERNEL_MFILES` only in `libDriver/Makefile`, relying on the existing `Kernel/` mode directory. Task 6 adds the user implementation and `USER_MFILES` entry. Add `IOAGPDevicePrivate.h` to `PRIVATE_HFILES`.

- [ ] **Step 3: Build the shared layer**

Re-sync and run `-KernelDrivers`. Expected: i386 and ppc compile/link with no backend registered, boot behavior unchanged, and no unresolved `IOAGP*` symbols.

- [ ] **Step 4: Commit**

```powershell
git add src/kernel-7/conf/files src/driverkit-3/driverkit/Makefile src/driverkit-3/libDriver/Makefile
git commit -m "build: include the shared AGP service"
```

### Task 6: Add typed user RPC and task-death cleanup

**Files:**
- Modify: `src/driverkit-3/libDriver/driverServer.defs`
- Modify: `src/kernel-7/driverkit/driverServerXXX.h`
- Modify: `src/kernel-7/driverkit/driverServerXXX.m`
- Create: `src/kernel-7/driverkit/IOAGPUserServer.h`
- Create: `src/kernel-7/driverkit/IOAGPUserServer.m`
- Create: `src/driverkit-3/libDriver/User/IOAGPDevice.m`
- Modify: `src/driverkit-3/libDriver/Makefile`
- Modify: `src/kernel-7/conf/files`
- Modify: `src/kernel-7/driverkit/tests/agp_broker_contract_test.c`

- [ ] **Step 1: Add failing cross-task and port-death contract tests**

Create two fake owner ports. Acquire with owner A, verify every operation using owner B returns `IO_R_PRIVILEGE`, deliver simulated death for A, then assert teardown order, `Ready` state, zero wired pages, and successful acquisition by B.

- [ ] **Step 2: Define the MIG wire types and routines**

Append architecture-neutral types after `IOConfigData`:

```mig
type IOAGPHandle = unsigned;
type IOAGPLogicalRange = struct[2] of unsigned;
type IOAGPLogicalRanges = array[*:256] of IOAGPLogicalRange;
type IOAGPStatusData = array[20] of unsigned;
```

Add typed routines `_IOAGPAcquire`, `_IOAGPCreateSpace`, `_IOAGPReserveRange`, `_IOAGPCommit`, `_IOAGPReleaseMapping`, `_IOAGPReleaseRange`, `_IOAGPGetStatus`, `_IOAGPReset`, `_IOAGPDestroySpace`, and `_IOAGPReleaseSession`. Each takes `IODevicePort`, `task_t owner`, and the session handle after acquire. `_IOAGPCommit` takes copied logical ranges and returns one mapping handle.

Append these routines after all existing `driverServer.defs` routines so their new message IDs do not renumber or break the existing DriverKit RPC ABI.

- [ ] **Step 3: Implement strict kernel endpoints**

Resolve the graphics device from `IODevicePort`, find its broker, convert the passed task port/map, copy every logical range, reject zero length, wraparound, more than 256 ranges, and addresses outside the supplied task map, then construct `IOMemoryDescriptor` with `byReference:NO` and `setClient:`. Do not retain the MIG input buffer.

- [ ] **Step 4: Register and handle owner-port death**

Use the existing `port_request_notification()` pattern from `EventDriver.m`: retain the kernel representation of the owner port, request notification on the kernel notification port, and map the notification back to the broker/session. The notification callback must call `[broker clientPortDied:port]`; explicit release cancels the record before dropping the right. Test duplicate death after explicit release as a no-op.

- [ ] **Step 5: Implement the user proxy**

The user `IOAGPDevice` stores the device port, task port, and session. `commitAGPMemory` enumerates `[memory logicalRange:index:]` into a bounded local array, rejects more than 256, and calls `_IOAGPCommit`. It never calls `[memory wireMemory]` in user space; the kernel owns residency. Add `IOAGPDevice.m` to `USER_MFILES`, and add `driverkit/IOAGPUserServer.m` to `conf/files` in this task.

- [ ] **Step 6: Regenerate MIG outputs, test, build, and commit**

Run the host tests, then the driverkit/kernel guest build. Expected: generated client/server prototypes agree on all handle widths for ppc and i386.

```powershell
git add src/driverkit-3/libDriver/driverServer.defs src/kernel-7/driverkit/driverServerXXX.h src/kernel-7/driverkit/driverServerXXX.m src/kernel-7/driverkit/IOAGPUserServer.h src/kernel-7/driverkit/IOAGPUserServer.m src/driverkit-3/libDriver/User/IOAGPDevice.m src/driverkit-3/libDriver/Makefile src/kernel-7/conf/files src/kernel-7/driverkit/tests/agp_broker_contract_test.c
git commit -m "driverkit: expose AGP sessions to user drivers"
```

### Task 7: Add read-only Intel 440BX discovery and fixtures

**Files:**
- Create: `src/kernel-7/driverkit/i386/agp_440bx.h`
- Create: `src/kernel-7/driverkit/i386/agp_440bx.c`
- Create: `src/driverkit-3/libDriver/i386/IOIntel440BXAGP.m`
- Create: `src/kernel-7/driverkit/tests/agp_440bx_test.c`
- Modify: `src/kernel-7/driverkit/tests/Makefile.host`
- Modify: `src/kernel-7/conf/files.i386`
- Modify: `src/driverkit-3/libDriver/Makefile`

- [ ] **Step 1: Write failing ID, aperture, and read-only tests**

Use vendor/device `0x8086:0x7190`, reject `0x7192` and non-Intel IDs, and test the 440BX size table `{256,128,64,32,16,8,4} MiB` with APSIZE values `{0,32,48,56,60,62,63}`. Verify read-only probe writes zero fake registers.

- [ ] **Step 2: Define exact register constants and helpers**

```c
#define AGP_440BX_VENDOR       0x8086U
#define AGP_440BX_DEVICE       0x7190U
#define AGP_440BX_APBASE       0x10U
#define AGP_440BX_NBXCFG       0x50U
#define AGP_440BX_ERRSTS       0x91U
#define AGP_440BX_AGPCTRL      0xb0U
#define AGP_440BX_APSIZE       0xb4U
#define AGP_440BX_ATTBASE      0xb8U
#define AGP_440BX_PTE_VALID    0x00000017U
```

Implement byte/word accesses as aligned `PCIKernBus` dword read-modify-write operations in the Objective-C adapter; the pure C module receives typed read/write callbacks.

- [ ] **Step 3: Implement read-only adapter discovery**

From the graphics master's `IOPCIDeviceDescription`, obtain its BDF. Read bus 0/device 0/function 0 through `PCIKernBus`, require `0x71908086`, walk AGP capabilities on host and master, read APBASE/APSIZE/status, and log one bounded diagnostic. Do not register a backend or write any register yet.

- [ ] **Step 4: Run host tests and boot read-only on 440BX**

Build/install on the real 440BX test disk. Expected log includes host ID, master BDF, capability offsets, APBASE, decoded size, and mutual rate bits. Dump pre/post PCI config and require byte-for-byte equality.

- [ ] **Step 5: Commit**

```powershell
git add src/kernel-7/driverkit/i386/agp_440bx.h src/kernel-7/driverkit/i386/agp_440bx.c src/driverkit-3/libDriver/i386/IOIntel440BXAGP.m src/kernel-7/driverkit/tests/agp_440bx_test.c src/kernel-7/driverkit/tests/Makefile.host src/kernel-7/conf/files.i386 src/driverkit-3/libDriver/Makefile
git commit -m "driverkit: discover Intel 440BX AGP"
```

### Task 8: Enable the Intel 440BX GART backend

**Files:**
- Modify: `src/kernel-7/driverkit/i386/agp_440bx.h`
- Modify: `src/kernel-7/driverkit/i386/agp_440bx.c`
- Modify: `src/driverkit-3/libDriver/i386/IOIntel440BXAGP.m`
- Modify: `src/kernel-7/driverkit/tests/agp_440bx_test.c`

- [ ] **Step 1: Add failing register-sequence and PTE tests**

For physical page `0x12345000`, expect PTE `0x12345017`. For 32 MiB, expect APSIZE `56`. Configure must log writes in this order: `APSIZE`, `ATTBASE`, `AGPCTRL=0x2280`, `NBXCFG` with bit 9 set/bit 10 clear, `ERRSTS+1=7`; flush must write `AGPCTRL=0x2200` then `0x2280`; cleanup must clear NBXCFG bit 9 and restore the saved APSIZE.

- [ ] **Step 2: Implement the pure register sequence**

Reject physical pages above `0xfffff000`, preserve the original APSIZE/NBXCFG for cleanup, derive aperture base from APBASE with reserved bits masked, and never invent an aperture when firmware left APBASE zero. `chooseAperture` selects the largest supported size not exceeding the request.

- [ ] **Step 3: Allocate and program the GART**

Use a physically contiguous wired kernel allocation sized `apertureBytes / 4096 * 4`; zero it; verify its physical range fits 32 bits; pass its physical address to ATTBASE; initialize all entries invalid. Use the broker's staged PTE array and one `wbinvd`/ordering operation before the 440BX two-write TLB flush.

- [ ] **Step 4: Register the backend only after full validation**

Build an `IOAGPBackendOps` table and call `registerBackend` only when host/master capabilities, APBASE, and APSIZE are valid. Enable target then master with the broker-negotiated command; disable master before target during cleanup.

- [ ] **Step 5: Run host, guest-build, and 440BX harness gates**

On real hardware, create a 32 MiB aperture, commit three discontiguous pages, compare diagnostic PTE readback, release, and repeat 1,000 cycles. Wired pages, mappings, and handles must return to baseline after every cycle.

- [ ] **Step 6: Commit**

```powershell
git add src/kernel-7/driverkit/i386/agp_440bx.h src/kernel-7/driverkit/i386/agp_440bx.c src/driverkit-3/libDriver/i386/IOIntel440BXAGP.m src/kernel-7/driverkit/tests/agp_440bx_test.c
git commit -m "driverkit: enable the 440BX AGP GART"
```

### Task 9: Add read-only UniNorth discovery and fixtures

**Files:**
- Create: `src/kernel-7/driverkit/ppc/agp_uninorth.h`
- Create: `src/kernel-7/driverkit/ppc/agp_uninorth.c`
- Create: `src/driverkit-3/libDriver/ppc/IOUniNorthAGP.m`
- Create: `src/kernel-7/driverkit/tests/agp_uninorth_test.c`
- Modify: `src/kernel-7/driverkit/tests/Makefile.host`
- Modify: `src/kernel-7/conf/files.ppc`
- Modify: `src/driverkit-3/libDriver/Makefile`

- [ ] **Step 1: Write failing endian, size, and read-only tests**

Test UniNorth sizes `{256,128,64,32,16,8,4} MiB`, size values `{64,32,16,8,4,2,1}`, and little-endian PTE storage: physical page `0x12345000` becomes logical value `0x12345001` and byte sequence `01 50 34 12` in GART memory on PPC. Verify read-only discovery writes zero fake registers.

- [ ] **Step 2: Define exact UniNorth registers**

```c
#define UNINORTH_GART_BASE       0x8cU
#define UNINORTH_AGP_BASE        0x90U
#define UNINORTH_GART_CTRL       0x94U
#define UNINORTH_INTERNAL_STATUS 0x98U
#define UNINORTH_GART_INVALIDATE 0x00000001U
#define UNINORTH_GART_ENABLE     0x00000100U
#define UNINORTH_GART_2X_RESET   0x00010000U
```

All six registers are PCI configuration-space little-endian even though UniNorth MMIO registers are big-endian.

- [ ] **Step 3: Implement read-only device-tree discovery**

Use existing `IOPCIDevice`/`IOMacRiscPCIBridge` access. Require the Sawtooth family, a `uni-north`/`uni-n` host, a valid device revision, the existing AGP bridge subtree, and an AGP-capable display master. Log host/master capabilities and register values without modifying the device tree or registers. Keep the existing `PEEditDTEntry()` generic bridge compatibility edit.

- [ ] **Step 4: Run host tests and read-only Sawtooth boot**

Build/install on a temporary Sawtooth disk. Capture the device tree and relevant config dwords before and after probe; require no changes and unchanged display boot.

- [ ] **Step 5: Commit**

```powershell
git add src/kernel-7/driverkit/ppc/agp_uninorth.h src/kernel-7/driverkit/ppc/agp_uninorth.c src/driverkit-3/libDriver/ppc/IOUniNorthAGP.m src/kernel-7/driverkit/tests/agp_uninorth_test.c src/kernel-7/driverkit/tests/Makefile.host src/kernel-7/conf/files.ppc src/driverkit-3/libDriver/Makefile
git commit -m "driverkit: discover UniNorth AGP"
```

### Task 10: Enable the UniNorth GART backend

**Files:**
- Modify: `src/kernel-7/driverkit/ppc/agp_uninorth.h`
- Modify: `src/kernel-7/driverkit/ppc/agp_uninorth.c`
- Modify: `src/driverkit-3/libDriver/ppc/IOUniNorthAGP.m`
- Modify: `src/kernel-7/driverkit/tests/agp_uninorth_test.c`

- [ ] **Step 1: Add failing program/invalidate/disable sequence tests**

Configure must write `GART_BASE=(gartPhysical & 0xfffff000)|sizeValue`, `AGP_BASE=0`, and leave traffic disabled. Invalidate on Sawtooth-era revisions must write control values `0x101`, `0x100`, `0x10100`, `0x100`. Disable must wait for idle with a bounded loop, then write `0x101`, `0`, `0x10000`, `0`.

- [ ] **Step 2: Implement little-endian GART storage and cache discipline**

Encode `(physical & 0xfffff000) | 1`, byte-swap only when storing/loading the GART word, checkpoint each mapped data page for bidirectional device access, flush the modified GART cache range, execute the PPC ordering barrier, then invalidate. Reject physical pages above 32 bits.

- [ ] **Step 3: Allocate non-cacheable contiguous GART memory**

Allocate the exact power-of-two GART page count associated with the selected aperture, verify physical contiguity, flush stale cache lines, and map/use the table with cache disabled when the existing PPC VM primitives permit it. If the non-cacheable alias cannot be created, fail `createAGPSpace` rather than using an incoherent table.

- [ ] **Step 4: Enable conservatively and register**

Invalidate before command programming, write target command and verify enable with at most 1,000 readbacks, write the master command, invalidate again, and publish `Enabled`. Clear 4x/fast-write regardless of advertised UniNorth revision.

- [ ] **Step 5: Run host, build, and Sawtooth harness gates**

Create a 32 MiB aperture, commit three discontiguous pages, compare byte-exact PTE readback, release, and repeat 1,000 cycles. Confirm the display still works before and after the harness and that a normal reboot succeeds.

- [ ] **Step 6: Commit**

```powershell
git add src/kernel-7/driverkit/ppc/agp_uninorth.h src/kernel-7/driverkit/ppc/agp_uninorth.c src/driverkit-3/libDriver/ppc/IOUniNorthAGP.m src/kernel-7/driverkit/tests/agp_uninorth_test.c
git commit -m "driverkit: enable the UniNorth AGP GART"
```

### Task 11: Add kernel and user lifecycle harnesses

**Files:**
- Create: `src/kernel-7/driverkit/AGPTest.m`
- Modify: `src/kernel-7/conf/files`
- Create: `src/driverkit-3/tests/agptest.m`
- Modify: `src/driverkit-3/tests/Makefile`

- [ ] **Step 1: Add the debug-only kernel harness**

The harness accepts a device name and aperture size, allocates three wired pages through `IOMemoryDescriptor`, runs acquire/create/reserve/commit/status/release/destroy/release, and prints one result line containing backend, command, aperture, and counter deltas. Guard the file and config entry with `DEBUG`/`AGP_TEST`; release kernels contain no harness entry point.

- [ ] **Step 2: Add the user utility**

`agptest` supports `status`, `cycle <count>`, `hold`, and `die` commands. `cycle 1000` performs complete cycles and compares baseline/final counters. `hold` waits with one live mapping for manual inspection. `die` exits without cleanup so the port-death path is exercised.

- [ ] **Step 3: Add negative cases**

Both harnesses test zero/unaligned lengths, aperture overflow, overlapping reservations, double release, stale mapping/session handles, a second concurrent owner, unsupported requested 4x/fast-write flags, and destroy with a live mapping. Each operation must return the exact `IOReturn` expected by the API.

- [ ] **Step 4: Build and run on both machines**

Run `cycle 1000`, `die`, then `cycle 1` on both. Expected: the post-death cycle acquires successfully, status is `Ready` between cycles, and resource counters balance.

- [ ] **Step 5: Commit**

```powershell
git add src/kernel-7/driverkit/AGPTest.m src/kernel-7/conf/files src/driverkit-3/tests/agptest.m src/driverkit-3/tests/Makefile
git commit -m "driverkit: add AGP lifecycle harnesses"
```

### Task 12: Complete cross-architecture acceptance and documentation

**Files:**
- Modify: `docs/boot/boot-i386.md`
- Modify: `docs/boot/boot-ppc.md`
- Create: `docs/drivers/agp.md`

- [ ] **Step 1: Run the complete deterministic suite**

```powershell
gnumake -C src/kernel-7/driverkit/tests -f Makefile.host clean
gnumake -C src/kernel-7/driverkit/tests -f Makefile.host test
```

Expected: all AGP programs compile under strict C89 and exit 0.

- [ ] **Step 2: Build both architectures from synced sources**

```powershell
powershell -File vm\sync-src.ps1 -Path driverkit-3
powershell -File vm\sync-src.ps1 -Path kernel-7
powershell -File vm\build-src.ps1 -KernelDrivers
```

Expected: driverkit, i386 kernel, PPC kernel, and affected driver projects build with no AGP warnings or unresolved symbols.

- [ ] **Step 3: Run the real-hardware matrix**

On both temporary test disks record: unused-AGP boot; read-only discovery; 2x/1x and SBA readback; fragmented-page PTE match; 1,000 cycles; user death/reacquire; invalid request recovery; post-stress reboot; ordinary PCI/display behavior. A failure on either architecture blocks completion.

- [ ] **Step 4: Document support and the milestone boundary**

`docs/drivers/agp.md` must state supported host bridges, public lifecycle, conservative feature policy, diagnostics, harness commands, fault recovery, and that GPU-initiated AGP traffic awaits a graphics-driver integration. Add the observed boot lines and acceptance result to each architecture boot trace.

- [ ] **Step 5: Verify scope and commit**

Run `git diff --check`, confirm no production graphics driver changed, and confirm the Sawtooth bridge compatibility workaround remains unless separate evidence justified its removal.

```powershell
git add docs/drivers/agp.md docs/boot/boot-i386.md docs/boot/boot-ppc.md
git commit -m "docs: record AGP support and validation"
```

## Final verification gate

- All host tests pass under strict C89.
- DriverKit and kernel build for both ppc and i386.
- With no client, AGP causes no register writes and no PCI/display regression.
- Both real machines negotiate only the approved 1x/2x/SBA feature set.
- GART readback matches fragmented physical-page fixtures exactly.
- Explicit release, task death, injected failure, and repeated cycles leave zero live mappings/ranges/handles and no extra wired pages.
- Faulted hardware rejects new sessions until verified reset or reboot.
- No production graphics driver integration is claimed in this milestone.
