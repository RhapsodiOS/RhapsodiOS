# i386 platform expert design

## Problem

On ppc, platform knowledge lives in one place. `src/drivers-ppc/bus/drvPExpert`
is a `PROJECT_TYPE = Kernel Server` that builds a single relocatable,
`pexpertpowermac.o`, installed to `/usr/local/lib` and linked into the kernel
through `makeoptions LIBPEXPERT` (`src/kernel-7/conf/MASTER.ppc:88`,
`src/kernel-7/conf/Makefile.ppc:77`). It owns `ppc_init()` — the first C
function `start.s` calls — and dispatches through a `powermac_init_t` vtable
into `families/` (motherboard families: gossamer, yosemite, sawtooth,
powersurge) which wire up `chips/` (I/O ASICs: grand_central, heathrow,
keylargo, mpic, ohare).

On i386 the equivalent knowledge is smeared across three layers that overlap and
disagree.

**Layer 1 — the kernel.** `src/kernel-7/machdep/i386` carries ~4,100 lines of
platform code compiled `standard` into every configuration
(`src/kernel-7/conf/files.i386`): `i386_init.c` (703), `intr.c` (716, the 8259
pair), `dma.c` (642, the 8237 pair), `machine_clock.c` (438, the 8254 and CMOS
RTC), `APM_i386.c` (290), `dma_buf.c` (173), `bios.c` (120) and `io_prim.c`
(60). None of it is separable from the kernel today.

**Layer 2 — the booter.** `src/boot-2/i386` already enumerates EISA slots and
functions into `KERNBOOTSTRUCT` and probes the PCI configuration mechanism into
`PCI_bus_info_t` (`boot2/boot.c:347-371` calling `ReadEISASlotInfo`,
`ReadEISAFuncInfo`, `ReadPCIBusInfo`, `PCI_Bus_Init`; `libsaio/pci.c`
`testMethod1`, `testMethod2`). It also calls E820 and then discards the map,
collapsing it to a scalar `extmem` (`boot2/sizememory.c`).

**Layer 3 — the DriverKit bus drivers.** `src/drivers-i386/bus/drvEISABus` is
8,886 lines and re-does layer 2's work in the kernel: `eisa.c:289,328`
(`getEISASlotInfo`, `getEISAFunctionInfo`) reads the booter's output back out of
hardcoded physical addresses `EISA_SLOT_DATA_ADDR` / `EISA_CONFIG_DATA_ADDR`;
`bios.c:56,189,257,279` implements the ISA PnP LFSR isolation protocol
(`readIsolationBit`, `computeChecksum`, `isolateCard`) and a second real-mode
BIOS thunk (`call_pnp_bios`); and `EISAKernBus+PlugAndPlay.m:74-94` contains a
*third* copy of raw PnP port access as inline `outb` to `0x279`/`0xa79`. The PnP
resource-data tag format is parsed independently by `PnPResources.m`,
`PnPDeviceResources.m`, `pnpIRQ.m`, `pnpDMA.m`, `pnpIOPort.m` and `pnpMemory.m`
— 2,530 lines of Objective-C over one wire format. `drvPCIBus` carries its own
`pci.c` config-cycle implementation, duplicating the booter's.

Compounding this, **no platform expert is built in-tree on either
architecture.** Neither `drivers-ppc` nor `drivers-i386` appears in
`src/Manifest`; only `kernel-7` does. `drvPExpert/powermac/README` says "needs
compiled and then tested." Meanwhile `src/kernel-7/dpkg/control` already carries
`Build-Depends: … drvpexpert …` unconditionally, so the package graph is already
shaped for this and is simply not yet true.

The header story shows where the ppc design goes wrong if copied literally:
`src/kernel-7/machdep/ppc/powermac.h` and
`src/drivers-ppc/bus/drvPExpert/powermac/powermac.h` are two copies of one
header that **have already drifted** — 22 differing lines, with
`POWERMAC_CLASS_SAWTOOTH 9 /* Core99 */` present only in the kernel copy.

Goal: give i386 a platform expert structurally parallel to ppc's, collapse the
three discovery layers into one, and leave a base that later work (APIC, SMP,
ACPI-driven routing) can be built on without further archaeology.

## Constraints and decisions

- **Structurally parallel to ppc.** Same project type, same `chips/` +
  `families/` shape, same vtable dispatch, same link mechanism. A two-arch OS
  with few maintainers benefits more from one mental model than from a locally
  optimal x86-specific design.
- **`families/` means platform *generation*, not motherboard model.** x86 has no
  enumerable board set; the premise of the PC architecture is that hardware is
  discovered from firmware tables. A one-file-per-board `families/` would be
  fiction. Three families: `atpc`, `pcipc`, `acpipc`.
- **Discovery selects the family; the family does not gate discovery.**
  Discovery runs first and unconditionally, publishing everything it finds.
  Family selection then reads those results.
- **Hypervisor identity is a property, not a family.** A QEMU guest has both PCI
  and ACPI; making "hypervisor" a family would force a false either/or against
  `acpipc` and discard the firmware tables. It is detected, published, and — for
  now — acted on nowhere, because no quirk is yet known.
- **No header duplication.** Every header has exactly one owner. This is a
  deliberate departure from ppc, whose duplicated `powermac.h` has already
  drifted.
- **No driver source changes as a consequence of the move.** Driver-visible
  headers keep their current install paths and contents. This is the
  compatibility promise the extraction rests on.
- **No AML interpreter, ever.** MP tables, `$PIR`, `$PnP` and the ACPI *static*
  tables (RSDP/RSDT/XSDT/MADT/FADT/HPET) are plain structure parsing. That is the
  whole of the ACPI scope.
- **Verification is boot-to-login on a throwaway QEMU image** at every phase
  boundary, diffed against a baseline captured before any change.

## Project shape and build integration

`src/drivers-i386/bus/drvPExpert/`, mirroring the ppc project:

```
drvPExpert/
  Makefile  PB.project        PROJECT_TYPE = Aggregate,  TOOLS = i386
  dpkg/control                Package: drvpexpert
  i386/
    Makefile  PB.project      PROJECT_TYPE = Kernel Server
    Makefile.preamble         INCLUDED_ARCHS = i386
                              PRODUCT = $(PRODUCT_DIR)/pexpert$(NAME).o
                              NEXTSTEP_INSTALLDIR = /usr/local/lib
                              STRIP_ON_INSTALL = NO
                              USE_OBJC_KSINSTANCE = NO
    chips/                    subproject
    families/                 subproject
```

`NAME = i386` yields `pexperti386.o`.

The package keeps the name **`drvpexpert`**, deliberately: only one
architecture's platform expert is ever built into a given repository, so
`src/kernel-7/dpkg/control` needs no change — its existing dependency starts
being satisfied instead of aspirational.

Kernel link, two lines:

- `src/kernel-7/conf/MASTER.i386`: `makeoptions LIBPEXPERT = "pexperti386.o"` under `# <intel>`
- `src/kernel-7/conf/Makefile.i386`: append `$(LIBPEXPERT_SOURCE)/$(LIBPEXPERT)` to `LDOBJS_SUFFIX`

`LIBPEXPERT_SOURCE` is already architecture-neutral
(`src/kernel-7/conf/Makefile.template:195`), so the shared template is untouched.

`src/Manifest` gains **both** platform experts ahead of `kernel-7`:
`drivers-i386/bus/drvPExpert` and `drivers-ppc/bus/drvPExpert`. rbuild's `dir`
handler sets `SRCDIR = srcname` and rsyncs from it
(`src/rbuild-1/builder.c:610`, `src/rbuild-1/builder.c:968`), so a nested
relative path is expected to work when rbuild runs from `src/`; the
implementation plan verifies this rather than assuming it. The ppc entry is in
scope because the i386 link would otherwise be the only consumer of a build path
ppc also needs.

## The kernel/PExpert boundary

**The PExpert owns boot sequencing and hardware that is a property of the board.
The kernel keeps mechanisms that are properties of the instruction set.**

Moving out of `src/kernel-7/machdep/i386`:

| From | To | Note |
|---|---|---|
| `i386_init.c` | `i386_init.c` + `identify_machine.c` + `mem_init.c` | split: sequencing / CPUID and `cpu_model` / `size_memory`, `alloc_cnvmem`, `mem_region[]`, msgbuf placement |
| `intr.c`, `intr.h`, `intr_internal.h`, `intr_inline.h` | `interrupt.c` + `chips/i8259.{c,h}` | ipl and dispatch policy stays generic; register access becomes a chip |
| `dma.c`, `dma_buf.c`, `dma*.h` | `chips/i8237.{c,h}` + `dma_buf.c` | the 8237 is a chip; the buffer allocator is platform policy |
| `machine_clock.c` | `rtclock.c` + `chips/i8254.{c,h}` | clock policy separated from PIT register access |
| `bios.c`, `bios_asm.s` | `bios.c`, `bios_asm.s` | real-mode call thunk is a firmware service. Not to be confused with `drvEISABus`'s unrelated `bios.c`, which is deleted in P4 |
| `APM_i386.c`, `APM_BIOS.h` | `apm.c`, `apm.h` | firmware service |
| `io_prim.c` | `io_prim.c` | |

Staying in the kernel untouched: `pmap.c`, `gdt.c`, `idt.c`, `ldt.c`,
`dbl_fault.c`, `trap.c`, `pcb.c`, `start.s`, `locore.s`, `catch.c`,
`fault_copy.c`, `in_cksum.c`, `checksum_16.c`, `kern_machdep.c`, `machdep.c`,
`machdep_call.c`, `sys_machdep.c`, `unix_signal.c`, `unix_startup.c`,
`vm_machdep.c`, `swapgeneric.m`, `kdp_machdep.c`, `miniMonMachdep.c`, `fp_*`,
`pc_support/`, `fp_emul/`, `libc/`.

`start.s` keeps calling `_i386_init`; the symbol resolves into `pexperti386.o`
instead. As on ppc, the PExpert sequences and calls back into kernel mechanisms
(`pmap_bootstrap`, `locate_gdt`, `locate_idt`, `idt_copy`, `dbf_init`,
`setup_main`), which do not move.

### Headers

- **Contract headers** — `intr_exported.h`, `dma_exported.h`, `io_inline.h`, and
  the new `pexpert_i386.h` — live in `src/kernel-7/machdep/i386` and are
  installed by the existing `i386_installhdrs` rule. The PExpert consumes them
  via `HEADER_PATHS = -I$(KERNEL_HEADERS)/machdep`, exactly as the ppc project
  already does.
- **Private headers** — `intr_internal.h`, `chips/*.h`, `families/*.h` — live in
  the PExpert only and are installed nowhere.

Net effect: one owner per header, existing driver-visible headers unchanged in
path and content, and no third-party driver source changes as a consequence of
the move.

## The platform interface

### `i386_init_t`

```c
typedef struct i386_init {
    const char             *name;              /* "PC/AT", "PCI PC", "ACPI PC" */
    void                  (*configure_machine)(void);
    void                  (*initialize_interrupts)(void);
    void                  (*initialize_rtclock)(void);
    void                  (*initialize_processors)(void);
    const pci_config_ops_t *pci_config;        /* NULL when the platform has no PCI */
} i386_init_t;

extern i386_init_t *i386_init_p;
```

`powermac_init_t`'s `machine_initialize_network` slot is dropped: on ppc it
exists purely for kgdb over ethernet, and i386 has no such path. `pci_config` is
the data-pointer slot, structurally equivalent to ppc's
`powermac_dbdma_channels`.

Families are plain struct literals reusing shared function pointers, exactly as
`families/gossamer.c` reuses `heathrow_interrupt_initialize` and `rtc_init`. No
inheritance machinery.

| Family | Selected when | Interrupts | PCI config |
|---|---|---|---|
| `atpc.c` | no PCI config mechanism responds | 8259 pair | `NULL` |
| `pcipc.c` | PCI present, no ACPI RSDP | 8259 pair | mechanism #1 / #2 / BIOS32 |
| `acpipc.c` | PCI present and ACPI RSDP found | 8259 pair (APIC lands here later) | mechanism #1 / #2 / BIOS32 |

EISA presence is a discovered property, not a family: EISA changes what is
enumerable, not how interrupts or clocks work. `atpc` covers ISA and EISA alike.

### `chips/`

Silicon only, no platform policy.

- `i8259.{c,h}` — the PIC pair
- `i8254.{c,h}` — the PIT
- `i8237.{c,h}` — the ISA DMA controller pair
- `pcicfg.{c,h}` — PCI configuration mechanisms #1 and #2
- `bios32.{c,h}` — BIOS32 service directory and the PCI BIOS entry
- `isapnp.{c,h}` — the ISA Plug and Play protocol: initiation key, LFSR
  checksum, isolation bit read, `isolateCard`, CSN assignment, relocatable
  read-port selection, logical-device select, configuration register access.
  One implementation, replacing both `drvEISABus/bios.c`'s copy and the inline
  asm in `EISAKernBus+PlugAndPlay.m`.
- `eisa.{c,h}` — EISA slot and function ID ports, compressed EISA ID encode and
  decode (`EISAParseID`, `EISAMatchIDs`, `testSlotForID`)

### The interrupt controller split

`interrupt.c` retains every piece of policy that exists today — `dispatch_table[]`,
`ipl_mask[]`, `defer_table[]`, `current_ipl` / `masked_ipl`, and the deferred
interrupt logic — and reaches hardware only through:

```c
typedef struct intr_controller {
    const char *name;
    int         nirq;
    void      (*init)(void);
    void      (*set_mask)(intr_irq_mask_t mask);
    void      (*set_trigger)(intr_irq_mask_t level_mask);
    void      (*eoi)(int irq);
    boolean_t (*is_spurious)(int irq);
} intr_controller_t;
```

`intr_irq_mask_t` widens from `unsigned short :16` to `unsigned int`, because the
16-bit mask is precisely what would block a 24-pin IOAPIC later. `INTR_NIRQ`
becomes `intr_controller_p->nirq` at loop bounds and a compile-time
`INTR_NIRQ_MAX 32` where it sizes arrays. `INTR_SLAVE_IRQ 2` moves into
`chips/i8259.c`, where it belongs — it is an 8259 fact, not a platform fact.

All of this is confined to private headers. `intr_exported.h` stays
byte-identical. Verified: the only consumers outside `machdep/i386` import
`intr_exported.h` alone and never `intr_internal.h`, `INTR_NIRQ`,
`intr_irq_mask_t` or `INTR_SLAVE_IRQ` —
`src/drivers-i386/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj/EISAKernBus.m:40`,
`.../EISAKernBusInterrupt.m:34`,
`src/drivers-i386/bus/drvPCMCIABus/PCMCIABus.drvproj/PCMCIABus.lksproj/PCMCIAKernBus.m:45`.

An `ioapic.c` becomes a drop-in later with no change to policy.

### `pexpert_i386.h`

```c
#define I386_CLASS_ATPC   1
#define I386_CLASS_PCIPC  2
#define I386_CLASS_ACPIPC 3

#define I386_HV_NONE   0
#define I386_HV_VMWARE 1
#define I386_HV_VBOX   2
#define I386_HV_QEMU   3
#define I386_HV_HYPERV 4

typedef struct i386_platform_info {
    int          class;
    int          hypervisor;
    char         cpu_vendor[13];
    char         cpu_model[64];
    unsigned int cpu_family, cpu_model_id, cpu_stepping;
    unsigned int cpu_feature_edx, cpu_feature_ecx;
    unsigned int tsc_hz;                /* 0 if no TSC */
} i386_platform_info_t;

typedef struct i386_firmware_info {
    void *mp_fps, *mp_config;           /* MP spec, NULL if absent */
    void *pir_table;                    /* $PIR, NULL if absent */
    void *pnp_bios;                     /* $PnP, NULL if absent */
    void *acpi_rsdp, *acpi_rsdt, *acpi_xsdt;
    void *acpi_madt, *acpi_fadt, *acpi_hpet;
    void *bios32, *pci_bios;
    int   pci_config_mechanism;         /* 0 none, 1, 2 */
    int   pci_last_bus;
    int   eisa_present;
    int   eisa_slots;
} i386_firmware_info_t;

extern i386_platform_info_t  i386_platform_info;
extern i386_firmware_info_t  i386_firmware_info;
```

Every pointer is to a **PExpert-owned copy, not to firmware memory**. Tables are
found and copied into a static 8 KB arena during early init, while low memory is
still plainly reachable and before `pmap_bootstrap` runs — mirroring how ppc runs
`identify_machine1()` before VM init. This sidesteps mapping and lifetime
problems entirely. On arena overflow the table is published as `NULL` and the
overflow is reported on the console; a silently half-parsed MADT is a
week-long bug.

Consumption is by plain C symbols exported from the linked kernel image — the
same mechanism by which `drvPCIBus` already calls `intr_register_irq`. No IPC and
no property-list plumbing is introduced.

## Discovery

`i386_identify()`, all before `pmap_bootstrap`, all copying into the arena:

```
1. CPUID          -> cpu vendor/family/model/features; hypervisor leaf 0x40000000
2. bootinfo       -> EISA slots, PCI_bus_info_t from KERNBOOTSTRUCT
3. PCI config     -> confirm mechanism #1/#2 (trust the booter, verify); BIOS32 -> PCI BIOS
4. firmware scan  -> MP FPS, $PIR, $PnP, ACPI RSDP -> RSDT/XSDT -> MADT/FADT/HPET
5. ISA PnP        -> initiation key, isolate cards, assign CSNs, cache serial IDs
6. select family  -> atpc | pcipc | acpipc; publish i386_init_p
```

Step 5's placement is deliberate. ISA PnP isolation must run exactly once, and
running it in the PExpert makes that structural. Today it runs whenever
`drvEISABus` happens to load, which is why re-probing is a hazard.

Supporting modules at the top level of the PExpert:

- `bootinfo.{c,h}` — reads `KERNBOOTSTRUCT`'s `eisaSlotInfo`, the
  `EISA_func_info_t` array and `PCI_bus_info_t`, copying them into the arena.
  This replaces `drvEISABus`'s reads at hardcoded `EISA_SLOT_DATA_ADDR` /
  `EISA_CONFIG_DATA_ADDR`, an implicit booter-to-driver contract that nothing
  currently documents or versions.
- `pnpbios.{c,h}` — the `$PnP` firmware service: entry-point scan in
  `0xF0000`–`0xFFFFF`, `call_pnp_bios`, device-node enumeration. Built on the
  PExpert's real-mode thunk, so there is one thunk instead of two.
- `pnp_resource.{c,h}` — the PnP resource-data tag parser (IRQ, DMA, IO, memory
  and dependent-function descriptors). One parser shared by ISA PnP cards, PnP
  BIOS device nodes and EISA function data; these are the same tag format,
  parsed today by 2,530 lines of Objective-C across six files.

All boot-struct data is treated as **advisory**: re-verified by probe where cheap
(the PCI mechanism), published as absent where not (EISA). If the booter's
`EISA_SUPPORT` is compiled out, the fields are zero and must not be mistaken for
"no EISA hardware."

## PCI configuration service

```c
typedef struct pci_config_ops {
    const char *name;                   /* "mechanism 1", "mechanism 2", "BIOS32" */
    int  (*read)(int bus, int dev, int fn, int off, int size, unsigned int *val);
    int  (*write)(int bus, int dev, int fn, int off, int size, unsigned int val);
    int         last_bus;
} pci_config_ops_t;
```

Backed by `chips/pcicfg.c` for mechanisms #1 and #2, or by the BIOS32-reached PCI
BIOS. Public wrappers `pexpert_pci_config_read()` and
`pexpert_pci_config_write()` are what bus drivers call.

## Bus driver rehosting

The rule that decides every case: **if it pokes a port or decodes a firmware
structure, it is PExpert. If it is an `IODeviceDescription`, a resource
reservation, or a probe/match decision, it is the bus driver.**

- **`drvPCIBus`** — replace the mechanism probes and configuration cycles in
  `PCIKernBusPrivate.m:62-158` with `pexpert_pci_config_*`. `pci.c` is
  *location-string* parsing (`PCIParsePrefix`, `PCIParseKeys`), which is driver
  policy and stays; `PCIResourceDriver` unchanged.
- **`drvEISABus`** — delete `eisa.c` and `bios.c`, and the inline asm in
  `EISAKernBus+PlugAndPlay.m` / `EISAKernBus+PlugAndPlayPrivate.m`. The `pnp*`
  and `PnPResource*` classes become thin DriverKit wrappers over structured
  results from `pnp_resource.c` rather than parsers in their own right. This is
  expected to be the bulk of the line reduction.
- **`drvPCMCIABus` / `Intel82365PCMCIA`** — the 82365 is a socket controller, but
  it is optional hardware discovered by probe, not board-level. It stays a
  driver; only its IRQ and window resource requests re-route through the
  PExpert. This is a re-point rather than a move, and delivers the least of the
  three.
- **`Intel824X0PCI`** — keeps its identity as a host-bridge driver but stops
  carrying private config-cycle code.

## Phasing

| | Scope | Boot gate |
|---|---|---|
| **P1** Skeleton and link | Project, `chips/` + `families/` directories, dpkg control, `MASTER.i386` / `Makefile.i386` wiring, Manifest entries for both architectures. Moves `i386_init.c` **whole** (its CPUID identification and memory-sizing code still inline), plus `io_prim.c`, `bios.c`, `bios_asm.s` | i386 kernel links against `pexperti386.o` and boots to login identically |
| **P2** Extraction | `interrupt.c` + `chips/i8259` (controller vtable, mask widening), `rtclock.c` + `chips/i8254`, `chips/i8237` + `dma_buf.c`, `apm.c` | Boot to login; console diff against baseline; interrupt-heavy load (disk and network) exercised |
| **P3** Discovery | Splits `identify_machine.c` and `mem_init.c` out of P1's `i386_init.c`; adds `bootinfo.c`, the firmware scan, `chips/isapnp`, `chips/eisa`, `chips/pcicfg`, `chips/bios32`, `pnp_resource.c`, `pnpbios.c`, `families/`, `pexpert_i386.h`, and the PCI config service | Boot plus a PExpert property dump matching known-good QEMU expectations; parser unit tests green |
| **P4** Bus rehosting | `drvPCIBus`, `drvEISABus`, `drvPCMCIABus`, `Intel824X0PCI` | Boot with NE2000-PCI networking up and SSH reachable |

Each phase gets its own implementation plan under `docs/plans/`.

## Verification

**Baseline first.** Before any change: build today's i386 kernel, boot it in
QEMU against a *copy* of `vm/rhapsody.vmdk` (CLAUDE.md §6), and capture full
console output plus the driver listing. Every later phase diffs against that
artifact. Without it the plan has no oracle.

**Boot to login at every phase boundary**, always on a throwaway image.

**Host-side unit tests, P3 only.** The table parsers are pure buffer-to-struct
functions and are the one part of this genuinely testable off-target: PnP
resource tags, EISA compressed-ID decode, ACPI RSDP and RSDT checksums, MP FPS
checksum, `$PIR` checksum. Built as a host tool following the existing C89
harness pattern in `src/rbuild-1/tests/test.h`. Everything else is verified by
booting.

**Symbol diff.** `nm mach_kernel` before and after each phase; the
globally-defined symbol set should change only by deliberate additions. This is
what catches a `static` accidentally dropped or gained while shuffling files.

**Move discipline for P1 and P2.** Files move with content changes restricted to
`#include` lines and the controller indirection, so `git diff -M` stays readable
and a reviewer can confirm by inspection that nothing else changed.

`docs/boot/boot-i386.md` is updated in P1 and P3, since the traced boot path
changes.

## Risks

1. **The interrupt policy/chip split changes EOI ordering or timing.** Highest
   consequence in the plan. `interrupt.c` stays textually identical to `intr.c`
   apart from calls through `intr_controller_p`, and the mask widening lands as a
   *separate commit* from the split so a bisect can distinguish them.
2. **ISA PnP isolation moves from driver-load time to early boot,** changing when
   cards receive CSNs. QEMU has no ISA PnP cards, so the available harness
   **cannot test this** — a real gap, not a hypothetical one. Discovery step 5 is
   gated behind a boot argument defaulting to observed behavior, and requires
   real-hardware validation before it is trusted.
3. **The 8 KB arena may be too small** for a real machine's MADT plus `$PIR` plus
   PnP node set. It is a single tunable constant; overflow is reported on the
   console and the affected table published as `NULL` rather than truncated.
4. **No platform expert has ever been built in-tree, on either architecture.** P1
   may surface `kernelserver.make` or kernload problems. P1 therefore builds
   *both* platform experts, so ppc breakage surfaces now rather than the next
   time someone touches ppc.
5. **The booter-to-PExpert contract is undocumented.** Mitigated by treating all
   boot-struct data as advisory, per the Discovery section.

## Out of scope

- **E820 memory map plumbing.** The booter's discarded map stays discarded and
  the fabricated single `mem_region` stays. Deliberately deferred.
- **APIC, IOAPIC, SMP.** The MP and MADT tables are discovered and published
  only; nothing acts on them.
- **An ACPI AML interpreter.** Static tables only, permanently.
- **`pmap`, descriptor tables, FPU, traps** — these stay in the kernel.
- **Console and video drivers** — `bsd/dev/i386/VGAConsole.c`,
  `bsd/dev/i386/FBConsole.c` and everything under `src/drivers-i386/video` are
  unchanged.
