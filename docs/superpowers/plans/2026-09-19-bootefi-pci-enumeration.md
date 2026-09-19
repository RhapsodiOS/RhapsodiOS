# UEFI Loader PCI Enumeration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `"Auto Detect IDs"` work under the UEFI loader so PCI drivers receive a `"Location"` key, letting `AHCIController` reach its device's config space and the kernel mount root from a SATA disk.

**Architecture:** The loader asks `EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL` for the PCI bus range, writes it into `kernBootStruct->pciInfo`, and calls `boot-2`'s existing `PCI_Bus_Init()` — which scans CF8/CFC with raw port I/O and fills `PCISlotInfo`. The scanner is reused unchanged so the loader and the kernel (which reaches config space through CF8/CFC unconditionally) agree on addressing. The one genuinely new piece, parsing the ACPI resource descriptor chain, is a pure function with no EFI types, host-tested.

**Tech Stack:** C (gnu89), clang cross-targeting `i386-unknown-windows`, `lld-link` for the EFI application; Objective-C (DriverKit) for the AHCI driver; QEMU q35 with IA32 OVMF for boot verification.

**Spec:** `docs/superpowers/specs/2026-09-19-bootefi-pci-enumeration-design.md`

## Global Constraints

- Target is QEMU plus IA32 OVMF only. Real UEFI hardware is not a goal.
- `src/boot-2` sources are reused as-is wherever possible. The one edit to `src/boot-2` in this plan (Task 2) fixes a memory-safety bug, not style.
- Commit messages: short, one to two lines, prefixed with the subsystem (`bootefi: `, `boot: `, `drvAHCI: `). Describe behaviour, not files. **No metadata, no trailers, no Co-Authored-By** (`CLAUDE.md` §5).
- Boot testing writes only to `vm/work/`. `vm/run-q35-uefi.sh` copies the source image there itself and refuses a destination elsewhere. Another session is debugging this same driver concurrently (`CLAUDE.md` §6).
- All work happens in the `bootefi-pci-enumeration` worktree, on that branch.

## Task Dependency Order

Tasks 1–4 are independent of one another and may run in parallel. Task 5 requires Tasks 1 and 2. Task 6 requires Task 5. Task 7 requires everything.

---

### Task 1: ACPI bus-range parser

The only new logic in the loader. Pure: byte buffer in, integer out, no EFI types, no firmware.

**Files:**
- Create: `src/bootefi-1/efi_pci_acpi.h`
- Create: `src/bootefi-1/efi_pci_acpi.c`
- Create: `src/bootefi-1/tests/efi_pci_acpi_test.c`
- Modify: `src/bootefi-1/tests/Makefile`

**Interfaces:**
- Consumes: nothing.
- Produces: `int efi_pci_bus_range_max(const unsigned char *resources, unsigned int maxlen)` — returns 0–255, or `EFI_PCI_BUS_RANGE_NONE` (-1). Task 5 calls this.

- [ ] **Step 1: Write the header**

Create `src/bootefi-1/efi_pci_acpi.h`:

```c
/* Parsing for the ACPI 2.0 resource descriptor chain that
 * EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL.Configuration() returns.  Deliberately
 * free of EFI types so it can be host-tested without firmware. */
#ifndef _BOOTEFI_EFI_PCI_ACPI_H_
#define _BOOTEFI_EFI_PCI_ACPI_H_

/* Returned when the chain carries no usable bus-number range.  Distinct from
 * a valid maximum of 0, which a single-bus machine legitimately reports. */
#define EFI_PCI_BUS_RANGE_NONE (-1)

/* Report the highest bus number the chain's bus-number descriptor claims.
 * Reads at most maxlen bytes.  Returns 0..255, or EFI_PCI_BUS_RANGE_NONE if
 * the chain has no bus-number descriptor, is malformed, or is truncated. */
int efi_pci_bus_range_max(const unsigned char *resources, unsigned int maxlen);

#endif /* _BOOTEFI_EFI_PCI_ACPI_H_ */
```

- [ ] **Step 2: Write the failing test**

Create `src/bootefi-1/tests/efi_pci_acpi_test.c`:

```c
/* Host test for the UEFI loader's ACPI bus-range parser.  Pure byte buffers:
 * no firmware, no EFI types, no boot-2 headers. */
#include <stdio.h>
#include <string.h>

#include "efi_pci_acpi.h"

#define DESC_LEN 46
#define END_LEN   2

static int failures;

static void check(const char *name, int got, int want)
{
    if (got != want) {
        printf("FAIL %s: got %d want %d\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

/* One QWORD Address Space Descriptor: tag 0x8a, 2-byte payload length 0x2b,
 * ResType at +3, AddrRangeMin at +14, AddrRangeMax at +22 (both 8 bytes,
 * little-endian).  ACPI 2.0. */
static unsigned int put_desc(unsigned char *buf, unsigned char restype,
                             unsigned long long min, unsigned long long max)
{
    unsigned int i;

    memset(buf, 0, DESC_LEN);
    buf[0] = 0x8a;
    buf[1] = 0x2b;
    buf[2] = 0x00;
    buf[3] = restype;
    for (i = 0; i < 8; i++)
        buf[14 + i] = (unsigned char)(min >> (8 * i));
    for (i = 0; i < 8; i++)
        buf[22 + i] = (unsigned char)(max >> (8 * i));
    return DESC_LEN;
}

static unsigned int put_end(unsigned char *buf)
{
    buf[0] = 0x79;
    buf[1] = 0x00;
    return END_LEN;
}

int main(void)
{
    unsigned char buf[256];
    unsigned int n;

    /* Bus descriptor first in the chain. */
    n = put_desc(buf, 2, 0, 255);
    n += put_end(buf + n);
    check("bus_only", efi_pci_bus_range_max(buf, n), 255);

    /* Memory (0) and I/O (1) descriptors ahead of the bus descriptor. */
    n = put_desc(buf, 0, 0xc0000000ULL, 0xdfffffffULL);
    n += put_desc(buf + n, 1, 0, 0xffff);
    n += put_desc(buf + n, 2, 0, 63);
    n += put_end(buf + n);
    check("bus_after_mem_and_io", efi_pci_bus_range_max(buf, n), 63);

    /* A single-bus machine reports max 0 -- not the sentinel. */
    n = put_desc(buf, 2, 0, 0);
    n += put_end(buf + n);
    check("single_bus_is_zero", efi_pci_bus_range_max(buf, n), 0);

    /* No bus descriptor at all. */
    n = put_desc(buf, 0, 0, 0xffff);
    n += put_end(buf + n);
    check("no_bus_descriptor", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* Truncated mid-descriptor: the payload runs past maxlen. */
    n = put_desc(buf, 2, 0, 255);
    check("truncated_descriptor", efi_pci_bus_range_max(buf, n - 10),
          EFI_PCI_BUS_RANGE_NONE);

    /* No end tag and no bus descriptor: the walk must stop at maxlen. */
    n = put_desc(buf, 0, 0, 0xffff);
    check("no_end_tag", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* An unrecognised tag byte aborts rather than being walked past. */
    n = put_desc(buf, 2, 0, 255);
    buf[0] = 0x47;
    check("unknown_tag", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* A range maximum too wide for a PCI bus number is not usable. */
    n = put_desc(buf, 2, 0, 0x1ffULL);
    n += put_end(buf + n);
    check("bus_max_too_wide", efi_pci_bus_range_max(buf, n),
          EFI_PCI_BUS_RANGE_NONE);

    /* A null chain. */
    check("null_chain", efi_pci_bus_range_max(0, 64),
          EFI_PCI_BUS_RANGE_NONE);

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
```

- [ ] **Step 3: Add the test to the tests Makefile**

In `src/bootefi-1/tests/Makefile`, change the `all` target and append a rule. The existing line is:

```make
all: $(BUILD)/ufs_host_test
```

Replace it with:

```make
all: $(BUILD)/ufs_host_test $(BUILD)/efi_pci_acpi_test
```

Then add, immediately before the `clean:` target:

```make
# The ACPI parser is pure C with no boot-2 or EFI dependencies, so it is
# built with plain strict flags rather than COMMON_FLAGS' boot-2 include
# paths and host_bios_addr.h force-include.
ACPI_TEST_CFLAGS := -std=gnu89 -g -O0 -Wall -Werror -I..

$(BUILD)/efi_pci_acpi_test: efi_pci_acpi_test.c ../efi_pci_acpi.c \
		../efi_pci_acpi.h | $(BUILD)
	$(CC) $(ACPI_TEST_CFLAGS) -o $@ efi_pci_acpi_test.c ../efi_pci_acpi.c

test-acpi: $(BUILD)/efi_pci_acpi_test
	$(BUILD)/efi_pci_acpi_test
```

And add `test-acpi` to the `.PHONY` line, which currently reads `.PHONY: all clean`:

```make
.PHONY: all clean test-acpi
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `make -C src/bootefi-1/tests test-acpi`

Expected: FAIL at the compile step — `efi_pci_acpi.c` does not exist yet, so make reports `No rule to make target '../efi_pci_acpi.c'`.

- [ ] **Step 5: Write the implementation**

Create `src/bootefi-1/efi_pci_acpi.c`:

```c
/* See efi_pci_acpi.h.  Parsed byte-wise rather than through a packed struct:
 * the descriptor's 8-byte fields are unaligned, and byte access keeps this
 * free of compiler-specific packing pragmas and host-testable as plain C. */
#include "efi_pci_acpi.h"

/* ACPI 2.0 tag bytes. */
#define ACPI_QWORD_ADDRESS_SPACE_DESC 0x8a
#define ACPI_END_TAG                  0x79

/* Tag byte plus a 2-byte count of the bytes that follow it. */
#define ACPI_DESC_HEADER_LEN 3

/* Offsets from the tag byte. */
#define ACPI_RES_TYPE_OFFSET      3
#define ACPI_ADDR_RANGE_MAX_OFF  22

/* Smallest payload that still contains all 8 bytes of AddrRangeMax.  The
 * standard QWORD descriptor declares 0x2b; this only rejects short ones. */
#define ACPI_MIN_PAYLOAD_LEN \
	(ACPI_ADDR_RANGE_MAX_OFF + 8 - ACPI_DESC_HEADER_LEN)

/* ResType 2 is bus-number space. */
#define ACPI_RES_TYPE_BUS 2

int efi_pci_bus_range_max(const unsigned char *resources, unsigned int maxlen)
{
	unsigned int offset = 0;

	if (resources == 0)
		return EFI_PCI_BUS_RANGE_NONE;

	/* offset advances by at least ACPI_MIN_PAYLOAD_LEN each pass, so the
	 * maxlen bound terminates the walk; no separate iteration cap needed. */
	while (offset < maxlen) {
		unsigned int payload;

		if (resources[offset] == ACPI_END_TAG)
			return EFI_PCI_BUS_RANGE_NONE;
		if (resources[offset] != ACPI_QWORD_ADDRESS_SPACE_DESC)
			return EFI_PCI_BUS_RANGE_NONE;
		if (offset + ACPI_DESC_HEADER_LEN > maxlen)
			return EFI_PCI_BUS_RANGE_NONE;

		payload = (unsigned int)resources[offset + 1] |
			  ((unsigned int)resources[offset + 2] << 8);
		if (payload < ACPI_MIN_PAYLOAD_LEN)
			return EFI_PCI_BUS_RANGE_NONE;
		if (offset + ACPI_DESC_HEADER_LEN + payload > maxlen)
			return EFI_PCI_BUS_RANGE_NONE;

		if (resources[offset + ACPI_RES_TYPE_OFFSET] ==
		    ACPI_RES_TYPE_BUS) {
			unsigned int i;

			/* Only the low byte can be a PCI bus number.  Anything
			 * wider means this is not a range we can hand to
			 * scanBus(), whose maxBusNum is an unsigned char. */
			for (i = 1; i < 8; i++) {
				if (resources[offset +
					      ACPI_ADDR_RANGE_MAX_OFF + i] != 0)
					return EFI_PCI_BUS_RANGE_NONE;
			}
			return (int)resources[offset + ACPI_ADDR_RANGE_MAX_OFF];
		}

		offset += ACPI_DESC_HEADER_LEN + payload;
	}

	return EFI_PCI_BUS_RANGE_NONE;
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `make -C src/bootefi-1/tests test-acpi`

Expected: nine `ok` lines then `all passed`, exit status 0.

- [ ] **Step 7: Commit**

```bash
git add src/bootefi-1/efi_pci_acpi.h src/bootefi-1/efi_pci_acpi.c \
        src/bootefi-1/tests/efi_pci_acpi_test.c src/bootefi-1/tests/Makefile
git commit -m "bootefi: parse the ACPI bus-number range from a root bridge"
```

---

### Task 2: Fix the slot-array allocation overflow

`PCI_Bus_Init` allocates one spare byte for a terminator that is 20 bytes wide. This is **not** dormant: `src/boot-2/i386/boot2/boot.c:390` calls `PCI_Bus_Init()` unconditionally and `pci.o` is in `libsaio/Makefile:34`, so it has been overflowing on every legacy BIOS boot. Task 5 adds a second caller under UEFI.

**Files:**
- Modify: `src/boot-2/i386/libsaio/pci.c:116-117`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing new. Task 5 depends on this being correct.

- [ ] **Step 1: Confirm the defect**

Run: `sed -n '115,121p' src/boot-2/i386/libsaio/pci.c`

Expected output:

```
    nslots = scanBus(maxBusNum, maxDevNum, method, NULL);
    slot_array = (_pci_slot_info_t *)
	malloc(sizeof(_pci_slot_info_t) * nslots +1);
    (void)scanBus(maxBusNum, maxDevNum, method, slot_array);
    slot_array[nslots].pid = 0x00;
    slot_array[nslots].sid = 0x00;
    PCISlotInfo = slot_array;
```

`_pci_slot_info_t` is five words — 20 bytes on i386 (`src/boot-2/i386/libsaio/pci.h:29-34`). The allocation provides `20 * nslots + 1` bytes; the two writes at `slot_array[nslots]` touch bytes `20 * nslots` through `20 * nslots + 7`. Seven bytes past the end.

- [ ] **Step 2: Apply the fix**

In `src/boot-2/i386/libsaio/pci.c`, change:

```c
    slot_array = (_pci_slot_info_t *)
	malloc(sizeof(_pci_slot_info_t) * nslots +1);
```

to:

```c
    slot_array = (_pci_slot_info_t *)
	malloc(sizeof(_pci_slot_info_t) * (nslots + 1));
```

- [ ] **Step 3: Verify the arithmetic**

Run: `sed -n '116,120p' src/boot-2/i386/libsaio/pci.c`

Expected: the allocation now reads `* (nslots + 1)`, giving `20 * (nslots + 1)` bytes, so the 8-byte terminator at index `nslots` lands inside a full 20-byte slot.

There is no unit test for this. `pci.c` has no host-test harness, and the correctness is in the allocation arithmetic, which the step above checks directly. Task 5's boot test exercises the fixed path for real.

- [ ] **Step 4: Commit**

```bash
git add src/boot-2/i386/libsaio/pci.c
git commit -m "boot: size the PCI slot array for its terminator entry

The old expression added one byte, not one slot, so writing the
terminating zero entry ran seven bytes past the allocation."
```

---

### Task 3: Log AHCIController's initialisation failures

Nineteen bail-out paths return nil with no output. This is why the original failure produced zero diagnostics.

**Files:**
- Modify: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m:93-296`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. Behaviour is unchanged; only logging is added.

- [ ] **Step 1: Locate every silent bail-out**

Run:

```bash
awk 'NR>=93 {if (/^}/) exit; if (/return nil;/) print NR": "$0}' \
    src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m
```

Expected: nineteen line numbers between 93 and 296, the first at 125.

- [ ] **Step 2: Add a distinct log to each**

Every one of the nineteen sites currently looks like:

```objc
        [self free];
        return nil;
```

Insert an `IOLog` line immediately **before** each `[self free]`, matching the
file's existing `IOLog("AHCI: ...\n")` style (see `+probe:`). The first one
becomes:

```objc
        IOLog("AHCI: PCI identity or class register is not ICH9-AHCI.\n");
        [self free];
        return nil;
```

Work down the list. Line numbers are as the file stands before any edit, so
**apply them bottom-up** — editing from line 125 downward shifts every later
number by one per insertion.

| `return nil;` at | Condition that failed | Message |
|---|---|---|
| 125 | PCI ID read, ID != ICH9-AHCI, class read, or class code | `PCI identity or class register is not ICH9-AHCI.` |
| 134 | BAR5 read or `AHCIPCIValidateBAR5` | `BAR5 is missing or not a usable ABAR.` |
| 141 | PCI command register read | `cannot read the PCI command register.` |
| 148 | `AHCIPCIPlanCommand` | `cannot plan the PCI command register update.` |
| 157 | `setPCIConfigData` enabling bus master / MMIO | `cannot enable PCI memory space and bus mastering.` |
| 166 | command readback read or `AHCIPCIValidateCommandReadback` | `PCI command register did not hold the enabled bits.` |
| 173 | interrupt config register read | `cannot read the PCI interrupt register.` |
| 180 | `AHCIPCIInterruptLine` or `setInterruptList` | `no usable PCI interrupt line.` |
| 188 | `setMemoryRangeList` | `cannot register the ABAR memory range.` |
| 193 | `[super initFromDeviceDescription:]` | `IODirectDevice initialisation failed.` |
| 198 | `NXLock` allocation | `cannot allocate the recovery lock.` |
| 208 | `mapMemoryRange` | `cannot map the ABAR into kernel space.` |
| 213 | ABAR address zero or misaligned | `mapped ABAR address is null or misaligned.` |
| 224 | `AHCIHBAInitialize` | `HBA reset and initialisation failed.` |
| 231 | implemented-port count zero or out of range | `HBA reports no usable implemented ports.` |
| 240 | `AHCIPort` allocation | `cannot allocate a port object.` |
| 256 | `portCount != implementedCount` | `port count disagrees with the implemented mask.` |
| 260 | `startIOThread` | `cannot start the I/O thread.` |
| 265 | `enableAllInterrupts` | `cannot enable controller interrupts.` |

Every message is prefixed `AHCI: ` and ends with `\n`, e.g.
`IOLog("AHCI: cannot start the I/O thread.\n");`.

Do not change any condition, any control flow, or the `[self free]; return
nil;` pair itself. This task adds nineteen lines and alters none.

- [ ] **Step 3: Verify every site is covered and nothing else changed**

Run:

```bash
awk 'NR>=93 {if (/^}/) exit; if (/return nil;/) print NR}' \
    src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m | wc -l
grep -c 'IOLog("AHCI: ' \
    src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m
```

Expected: nineteen bail-out sites, and an `IOLog` count of at least twenty (nineteen new plus the pre-existing one in `+probe:`).

Then run `git diff` and confirm every changed hunk is a pure insertion of an `IOLog` line. Any deleted or modified line other than that is a mistake — revert it.

- [ ] **Step 4: Check for duplicate messages**

Run:

```bash
grep -o 'IOLog("AHCI: [^"]*"' \
    src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m \
    | sort | uniq -d
```

Expected: no output. Any duplicate defeats the purpose and must be reworded.

- [ ] **Step 5: Run the portable AHCI tests**

Run: `make -C src/drivers-i386/ide/drvAHCI/tests test`

Expected: all tests pass. They do not cover `AHCIController.m` (which is Objective-C and not in the host harness), so this is a regression check that nothing else broke, not a test of the change.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.m
git commit -m "drvAHCI: say why controller initialisation failed

Every bail-out in initFromDeviceDescription returned nil silently, so a
failed probe produced no output at all."
```

---

### Task 4: Give AHCIDisk a real required protocol

`AHCIDisk` is `IO_IndirectDevice` but inherits `IODevice`'s `+requiredProtocols`, which returns NULL. `connectToIndirectDevices` logs a complaint on every `registerDevice` as a result.

**Files:**
- Modify: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.h`
- Modify: `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.m`

**Interfaces:**
- Consumes: nothing.
- Produces: `@protocol AHCIControllerPublic`, adopted by `AHCIController`. Nothing else in this plan consumes it.

- [ ] **Step 1: Read the precedent**

Run: `sed -n '82,100p' src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj/IdeDisk.m`

Expected: `IdeDisk` declares a file-scope `static Protocol *protocols[]` holding `@protocol(IdeControllerPublic)` and `nil`, returns it from `+requiredProtocols`, and returns `IO_IndirectDevice` from `+deviceStyle`. Mirror this shape exactly.

- [ ] **Step 2: Declare the protocol on the controller**

In `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.h`, immediately above the `@interface AHCIController : IODirectDevice` line (currently line 13), add:

```objc
/* Marker protocol so AHCIDisk, an IO_IndirectDevice, can name what it needs
 * from its provider -- mirroring IdeControllerPublic in drvEIDE.  Disks are
 * published directly by +[AHCIDisk publishForPort:deviceDescription:], so
 * DriverKit's indirect-device auto-connect never has work to do here; this
 * exists so +requiredProtocols can return something true. */
@protocol AHCIControllerPublic
@end
```

Then change the interface line to adopt it:

```objc
@interface AHCIController : IODirectDevice <AHCIControllerPublic>
```

- [ ] **Step 3: Implement +requiredProtocols on the disk**

In `src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.m`, immediately above the existing `+ (IODeviceStyle)deviceStyle` method (currently at line 82), add:

```objc
static Protocol *protocols[] = {
    @protocol(AHCIControllerPublic),
    nil
};

+ (Protocol **)requiredProtocols
{
    return protocols;
}
```

`AHCIDisk.m` already imports `AHCIController.h` transitively; if the build reports `AHCIControllerPublic` undeclared, add `#import "AHCIController.h"` to `AHCIDisk.m`'s imports rather than redeclaring the protocol.

- [ ] **Step 4: Verify the shape matches the precedent**

Run:

```bash
grep -n "requiredProtocols\|deviceStyle\|AHCIControllerPublic" \
    src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.m \
    src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.h
```

Expected: `AHCIDisk.m` shows `+requiredProtocols` returning `protocols` and `+deviceStyle` returning `IO_IndirectDevice`; `AHCIController.h` shows the `@protocol` declaration and the interface adopting it.

`AHCIDisk` deliberately does **not** gain a `+probe:`. `IODevice`'s default returns `NO` (`src/driverkit-3/libDriver/IODevice.m:216`), so the auto-connect path declines and publication stays with `publishForPort:`. Adding one would change how disks are published, which is out of scope.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIController.h \
        src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj/AHCIDisk.m
git commit -m "drvAHCI: declare what AHCIDisk requires of its controller

AHCIDisk is an indirect device with no +requiredProtocols, so DriverKit
logged a complaint about it on every device registration."
```

---

### Task 5: Wire PCI enumeration into the loader, with the derived range printed but not yet used

The EFI protocol struct is the highest-risk edit in this plan: `Configuration` sits eighteenth in the member list, and a miscount calls the wrong function pointer — a hang or fault, not a compile error. So this task derives the range and prints it while still passing the 0–255 fallback to `PCI_Bus_Init()`. Task 6 switches over only after a boot confirms the layout.

**Requires:** Tasks 1 and 2.

**Files:**
- Modify: `src/bootefi-1/efi.h`
- Create: `src/bootefi-1/efi_pci.c`
- Modify: `src/bootefi-1/efi_main.c:40-47`, and around line 103
- Modify: `src/bootefi-1/Makefile:50-74`

**Interfaces:**
- Consumes: `efi_pci_bus_range_max()` and `EFI_PCI_BUS_RANGE_NONE` from Task 1; the corrected allocation from Task 2.
- Produces: `int efi_pci_init(void)` — returns the number of PCI slots found, zero on failure. Sets the global `PCISlotInfo` (defined in `src/boot-2/i386/libsaio/pci.c`).

- [ ] **Step 1: Add the protocol declarations to efi.h**

In `src/bootefi-1/efi.h`, immediately after the `EFI_BLOCK_IO_PROTOCOL_GUID` definition (currently lines 24–25), add:

```c
#define EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL_GUID \
  {0x2f707ebb,0x4a1a,0x11d4,{0x9a,0x38,0x00,0x90,0x27,0x3f,0xc1,0x4d}}
```

Then, immediately after the `EFI_BLOCK_IO_PROTOCOL` struct (currently ending line 97), add:

```c
/* PCI root bridge I/O.  Only Configuration() is called; every earlier member
 * is a placeholder that keeps the offsets right, in the same style as
 * EFI_BOOT_SERVICES above.  The ordering is the UEFI spec's, and the three
 * access sub-structures (Mem, Io, Pci) are each two function pointers
 * expanded inline here -- seventeen pointer slots precede Configuration. */
typedef struct _EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL
        EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL;
struct _EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL {
    EFI_HANDLE  ParentHandle;       /*  1 */
    void       *PollMem;            /*  2 */
    void       *PollIo;             /*  3 */
    void       *MemRead;            /*  4 */
    void       *MemWrite;           /*  5 */
    void       *IoRead;             /*  6 */
    void       *IoWrite;            /*  7 */
    void       *PciRead;            /*  8 */
    void       *PciWrite;           /*  9 */
    void       *CopyMem;            /* 10 */
    void       *Map;                /* 11 */
    void       *Unmap;              /* 12 */
    void       *AllocateBuffer;     /* 13 */
    void       *FreeBuffer;         /* 14 */
    void       *Flush;              /* 15 */
    void       *GetAttributes;      /* 16 */
    void       *SetAttributes;      /* 17 */
    EFI_STATUS (*Configuration)(EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL *,
                                void **Resources);
    UINT32      SegmentNumber;
};
```

- [ ] **Step 2: Write the enumeration source**

Create `src/bootefi-1/efi_pci.c`:

```c
/* PCI enumeration for the UEFI loader.
 *
 * boot-2's boot.c gets the bus range from the PCI BIOS (ReadPCIBusInfo, INT
 * 1Ah) and hands it to PCI_Bus_Init(), which scans CF8/CFC and fills
 * PCISlotInfo -- the table drivers.c/set_dinfo() matches "Auto Detect IDs"
 * against to produce each driver's "Location" key.  There is no PCI BIOS
 * under UEFI, so only the range comes from firmware here; the scan itself is
 * boot-2's, unchanged, so the loader and the kernel agree on addressing (the
 * kernel reaches config space through CF8/CFC unconditionally -- see
 * src/driverkit-3/libDriver/pci/IOPCIDirectDevice.m).
 */
#include "efi.h"
#include "efi_pci_acpi.h"

#include "kernBootStruct.h"
#include "pci.h"

/* Defined in src/boot-2/i386/libsaio/pci.c.  boot2/boot.c declares this
 * returning void; it actually returns the slot array, which is what we need
 * to know whether the scan produced anything. */
extern _pci_slot_info_t *PCI_Bus_Init(PCI_bus_info_t *info);

extern int printf(const char *, ...);

static EFI_GUID gPciRootBridgeIoGuid = EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL_GUID;

/* Configuration() returns a bare pointer with no length, so bound the walk.
 * A root bridge's descriptor chain is a handful of 46-byte descriptors. */
#define ACPI_RESOURCE_SCAN_LIMIT 1024

/* Highest bus number any root bridge claims, or EFI_PCI_BUS_RANGE_NONE.
 * scanBus() takes a single contiguous 0..maxBusNum, so a machine with
 * several root bridges is covered by scanning up to the highest of them. */
static int derive_bus_max(void)
{
    EFI_HANDLE *handles = 0;
    UINTN size = 0, i;
    EFI_STATUS st;
    int best = EFI_PCI_BUS_RANGE_NONE;

    st = gBS->LocateHandle(ByProtocol, &gPciRootBridgeIoGuid, 0, &size, 0);
    if (st != EFI_BUFFER_TOO_SMALL)
        return EFI_PCI_BUS_RANGE_NONE;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&handles)))
        return EFI_PCI_BUS_RANGE_NONE;
    if (EFI_ERROR(gBS->LocateHandle(ByProtocol, &gPciRootBridgeIoGuid, 0,
                                    &size, handles))) {
        gBS->FreePool(handles);
        return EFI_PCI_BUS_RANGE_NONE;
    }

    for (i = 0; i < size / sizeof(EFI_HANDLE); i++) {
        EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL *rb = 0;
        void *resources = 0;
        int max;

        if (EFI_ERROR(gBS->HandleProtocol(handles[i], &gPciRootBridgeIoGuid,
                                          (void **)&rb)))
            continue;
        if (EFI_ERROR(rb->Configuration(rb, &resources)))
            continue;
        max = efi_pci_bus_range_max((const unsigned char *)resources,
                                    ACPI_RESOURCE_SCAN_LIMIT);
        if (max > best)
            best = max;
    }

    gBS->FreePool(handles);
    return best;
}

/* Fill PCISlotInfo.  Returns the number of devices found. */
int efi_pci_init(void)
{
    PCI_bus_info_t *info = &kernBootStruct->pciInfo;
    _pci_slot_info_t *slot;
    int derived, count = 0;

    derived = derive_bus_max();
    if (derived == EFI_PCI_BUS_RANGE_NONE) {
        printf("pci: no EFI bus range; scanning 0-255\n");
        derived = 255;
    } else {
        printf("pci: EFI reports bus range max %d\n", derived);
    }

    /* STAGED: the derived value is printed but not used until a boot has
     * confirmed efi.h's EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL member layout.
     * Removed in the follow-up commit. */
    derived = 255;

    /* No PCI BIOS reported these; PCI_Bus_Init() then probes for the config
     * method itself rather than trusting the BIOS flags. */
    info->BIOSPresent = 0;
    info->maxBusNum = (unsigned char)derived;

    if (PCI_Bus_Init(info) == 0)
        return 0;
    for (slot = PCISlotInfo; slot && slot->pid; slot++)
        count++;
    return count;
}
```

- [ ] **Step 3: Remove the stub and call the initialiser in efi_main.c**

In `src/bootefi-1/efi_main.c`, the comment and stubs at lines 40–46 currently read:

```c
/* boot2/boot.c globals that drivers.c/stringTable.c reference as extern.
 * boot.c itself is not part of this build (it is boot2's own main loop);
 * reproduced as plain data here since nothing sets either one -- this
 * loader has no EISA/PCI auto-detect or installer driver-family UI, so
 * both stay in their "none configured" state. */
char *LoadableFamilies;
void *PCISlotInfo;
```

Replace that whole block with:

```c
/* boot2/boot.c global that drivers.c/stringTable.c references as extern.
 * boot.c itself is not part of this build (it is boot2's own main loop);
 * reproduced as plain data here since nothing sets it -- this loader has no
 * installer driver-family UI, so it stays "none configured".  PCISlotInfo is
 * no longer stubbed here: efi_pci.c fills it through boot-2's own pci.c,
 * which owns the definition. */
char *LoadableFamilies;

extern int efi_pci_init(void);
```

Then, immediately after the `efi_init_bootstruct();` call (currently line 103) and before the `load_kernel(...)` call, add:

```c
    /* Must run before loadBootDrivers() below: set_dinfo() in boot-2's
     * drivers.c reads PCISlotInfo to match "Auto Detect IDs" and emit each
     * driver's "Location" key.  It also needs kernBootStruct zeroed first,
     * which efi_init_bootstruct() has just done. */
    printf("pci devices: %d\n", efi_pci_init());
```

- [ ] **Step 4: Add the new sources to the loader build**

In `src/bootefi-1/Makefile`, add `pci.c` to the boot-2 source list. The block currently ends:

```make
              $(BOOT2)/libsa/bsearch.c \
              $(BOOT2)/libsa/qsort.c \
              $(BOOT2)/libsa/strtol.c
```

Change it to:

```make
              $(BOOT2)/libsa/bsearch.c \
              $(BOOT2)/libsa/qsort.c \
              $(BOOT2)/libsa/strtol.c \
              $(BOOT2)/libsaio/pci.c
```

Then add the two loader sources. The line currently reads:

```make
EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_memory.c efi_vga.c handoff.c $(BOOT2_SRCS)
```

Change it to:

```make
EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_memory.c efi_vga.c \
            efi_pci.c efi_pci_acpi.c handoff.c $(BOOT2_SRCS)
```

`VPATH` already covers `$(BOOT2)/libsaio`, so `pci.c` needs no new rule.

- [ ] **Step 5: Build the loader**

Run: `make -C src/bootefi-1`

Expected: a clean build producing `src/bootefi-1/BUILD/BOOTIA32.EFI`.

If the link reports a duplicate `_PCISlotInfo`, the stub in `efi_main.c` was not fully removed — Step 3 is incomplete. If `pci.c` fails to compile on `io_inline.h` or `PCI.h` includes, add the needed `-I` to `CFLAGS` rather than editing anything under `src/boot-2`.

- [ ] **Step 6: Build the ESP and boot**

The Rhapsody media must already have the AHCI driver installed — that is what `vm/build-i386-kernel-ahci.sh` stages into `vm/install`. Set `RHAPSODY_AHCI_IMAGE` to that image before running:

```bash
python3 vm/build_uefi_image.py --esp-only \
    src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/esp.img
sh vm/run-q35-uefi.sh "$RHAPSODY_AHCI_IMAGE" vm/work/esp.img \
    vm/work/uefi-pci-test.img
```

`run-q35-uefi.sh` copies the source image to `vm/work/` itself and refuses any destination outside it, which satisfies the isolation requirement in `CLAUDE.md` §6.

- [ ] **Step 7: Confirm the protocol struct layout is right**

Run: `grep "^pci" vm/logs/uefi-serial.log`

Expected, on QEMU q35, both lines:

```
pci: EFI reports bus range max 255
pci devices: N
```

with N greater than zero.

**This step is the whole point of the task.** Judge the result:

- A plausible range (0–255) plus a non-zero device count means the member ordering in `efi.h` is correct. Proceed to Task 6.
- `pci: no EFI bus range; scanning 0-255` means `LocateHandle`, `HandleProtocol` or `Configuration` failed. The struct layout is unproven — do **not** proceed to Task 6. Diagnose first.
- A hang or reset at this point means `Configuration` called the wrong function pointer. Recount the seventeen placeholder slots in Step 1 against the UEFI spec.
- `pci devices: 0` with a plausible range means `PCI_Bus_Init` found no config method, which is a separate problem from the struct layout.

- [ ] **Step 8: Commit**

```bash
git add src/bootefi-1/efi.h src/bootefi-1/efi_pci.c src/bootefi-1/efi_main.c \
        src/bootefi-1/Makefile
git commit -m "bootefi: scan PCI so drivers get a Location key

Derives the bus range from EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL and reports it,
but still scans 0-255 until a boot confirms the protocol struct layout."
```

---

### Task 6: Use the derived bus range

**Requires:** Task 5, including a boot that printed a plausible range.

**Files:**
- Modify: `src/bootefi-1/efi_pci.c`

**Interfaces:**
- Consumes: `efi_pci_init()` from Task 5.
- Produces: nothing new.

- [ ] **Step 1: Remove the staging override**

In `src/bootefi-1/efi_pci.c`, delete these four lines from `efi_pci_init()`:

```c
    /* STAGED: the derived value is printed but not used until a boot has
     * confirmed efi.h's EFI_PCI_ROOT_BRIDGE_IO_PROTOCOL member layout.
     * Removed in the follow-up commit. */
    derived = 255;
```

Nothing else changes. The `derived` value computed above now reaches `info->maxBusNum`.

- [ ] **Step 2: Verify the override is gone**

Run: `grep -n "STAGED\|derived = 255" src/bootefi-1/efi_pci.c`

Expected: no output. The only remaining assignment of 255 is inside the `EFI_PCI_BUS_RANGE_NONE` fallback branch, which reads `derived = 255;` on its own line — if that is what matched, check by eye that the match is the fallback and not the override.

- [ ] **Step 3: Rebuild and boot**

```bash
make -C src/bootefi-1
python3 vm/build_uefi_image.py --esp-only \
    src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/esp.img
sh vm/run-q35-uefi.sh "$RHAPSODY_AHCI_IMAGE" vm/work/esp.img \
    vm/work/uefi-pci-test.img
```

- [ ] **Step 4: Confirm the device count is unchanged**

Run: `grep "^pci" vm/logs/uefi-serial.log`

Expected: the same `pci devices: N` count as Task 5 Step 7. A lower count means the derived range is narrower than the real topology and the fallback was masking it — investigate before continuing.

- [ ] **Step 5: Commit**

```bash
git add src/bootefi-1/efi_pci.c
git commit -m "bootefi: scan only the bus range firmware reports"
```

---

### Task 7: End-to-end verification

**Requires:** all previous tasks.

**Files:**
- Modify: `vm/run-q35-uefi.sh:1-9`

**Interfaces:**
- Consumes: everything.
- Produces: nothing.

- [ ] **Step 1: Build everything and boot**

```bash
make -C src/bootefi-1/tests test-acpi
make -C src/drivers-i386/ide/drvAHCI/tests test
make -C src/bootefi-1
python3 vm/build_uefi_image.py --esp-only \
    src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/esp.img
sh vm/run-q35-uefi.sh "$RHAPSODY_AHCI_IMAGE" vm/work/esp.img \
    vm/work/uefi-pci-final.img
```

- [ ] **Step 2: Walk the four success criteria in order**

Each one that fails localises the problem to a different link in the chain, so check them in sequence and stop at the first failure.

Run: `grep "^pci" vm/logs/uefi-serial.log`

1. `pci devices: N` with N greater than zero — the loader enumerated PCI.

Run: `grep -i "ahci\|Location" vm/logs/uefi-kernel.log`

2. No `configureDriver:` complaint about `AHCIController`, meaning the config table carried a `Location` key.
3. No `AHCI:` failure line from Task 3's logging — the controller initialised. If one appears, it now names exactly which check failed; that is the diagnosis, not a dead end.
4. No `Loaded class AHCIDisk returns nil for +requiredProtocols` — Task 4 landed.

Run: `grep -i "root on\|mount root\|errno" vm/logs/uefi-kernel.log`

5. `root on hd0a` present, and `cannot mount root, errno = 6` absent.

- [ ] **Step 3: Correct the run script's header**

`vm/run-q35-uefi.sh` lines 1–9 currently state that the kernel cannot find its disk here, that the media has no AHCI driver, and that the script is not useful for root-mount testing. With this work landed and AHCI-bearing media that is no longer true. Replace the misleading sentence:

```sh
# The Rhapsody KERNEL cannot find its disk here -- there is no
# legacy IDE at port 0x1f0 on q35, and the media has no AHCI driver -- so
# this is useful for checking the loader itself, not for kernel-level work
# such as root-mount testing.
```

with:

```sh
# There is no legacy IDE at port 0x1f0 on q35, so the kernel reaches its
# disk only through the AHCI driver.  Given media with that driver
# installed, this runner does exercise root-mount; with media without it,
# the kernel still will not find a disk and only the loader is under test.
```

- [ ] **Step 4: Commit**

```bash
git add vm/run-q35-uefi.sh
git commit -m "vm: the q35 UEFI runner can test root-mount with AHCI media"
```

- [ ] **Step 5: Report the outcome**

State plainly which of the five checks in Step 2 passed, quoting the matching log lines. If any failed, say so with the output rather than reporting the task complete.

---

## Notes for the implementer

**The `efi.h` struct is the one thing likely to go wrong.** Everything else in this plan is either pure C with tests or a one-line change. If Task 5 Step 7 does not print a plausible range, do not paper over it by leaving the fallback in place and moving on — the fallback would make the boot work while leaving the firmware query silently broken, which is the same class of defect this whole plan exists to fix.

**Task 3's line numbers are pre-edit.** Apply them bottom-up, or every number after the first insertion is off by one. If a condition in the file does not match what the table says failed there, trust the file and reword the message — the table was written against the tree at `e822b5c9a`.

**If a boot test cannot run** because `RHAPSODY_AHCI_IMAGE` is unavailable, say so and stop rather than marking Tasks 5–7 complete. The host tests in Tasks 1–4 stand on their own; the boot-dependent claims do not.
