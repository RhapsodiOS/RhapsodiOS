# i386 Large Memory Support

Date: 2026-07-25

Raise the i386 physical memory ceiling in two phases: first make machines with
any amount of RAM boot correctly under the existing 1GB kernel window, then
widen that window to 2GB so more than 1GB is actually usable.

## Problem

### The hard wall

`mach/i386/vm_param.h` sets `VM_MAX_ADDRESS = 0xC0000000` and
`VM_MAX_KERNEL_ADDRESS = 0x40000000`, and `machdep/i386/pmap.h` defines
`KERNEL_LINEAR_BASE = VM_MAX_ADDRESS`. This is a segmented 3G/1G split: user
CS/DS are based at 0 with a 3GB limit, kernel CS/DS are based at 3GB with a
**1GB limit** (`machdep/i386/gdt.c`).

`pmap_bootstrap()` maps all physical memory V==P into that window starting at
kernel VA 0, then reserves further VA on top of it for kmem:

    64MB base + zone_map_sizer() + buffer_map_sizer()

where `zone_map_sizer()` is `mem_size/8` clamped to 12–128MB, and
`buffer_map_sizer()` is `nbuf * MAXBSIZE + niobuf * MAXPHYS` with
`MAXBSIZE = 8192` and `MAXPHYS = 64K`.

The real constraint is therefore:

    RAM + 64MB + zone + buffer <= 1GB

which puts the practical ceiling at 823MB. Past that, `pmap_map()` walks
`pmap_pd_entry()` off the end of the single kernel page-directory page and
silently corrupts whatever allocation follows it. The failure surfaces later as
an unrelated crash.

### Three bugs stacked on top

1. **Overflow.** `machdep/i386/i386_init.c` computes
   `end_of_memory = KB(extmem)` in `unsigned int`. A 4GB machine reports
   `extmem = 4194304`; multiplied by 1024 this overflows to **0**, so
   `mem_size` and `last_addr` both become 0.

2. **Sum, not top.** `getMemoryMap()` in `boot-2/i386/libsaio/biosfn.c` returns
   the *sum* of E820 RAM entries below 4GB, not the top of contiguous low RAM.
   On any machine with a PCI MMIO hole below 4GB, the kernel then maps
   `0 .. sum` V==P straight across the MMIO hole.

3. **Map discarded.** The full E820 map is read into a stack array in
   `sizememory()` (`boot-2/i386/boot2/sizememory.c`) and thrown away. Only a
   single KB scalar reaches the kernel via `kernBootStruct->extmem`, so the
   kernel can never learn about holes. `mem_region[2]` exists but `num_regions`
   is hardcoded to 1.

## Approach

Two sequenced phases. Phase 1 stands on its own and is independent of the
outcome of Phase 2's pre-flight check.

Alternatives considered and rejected:

- **Full 4GB support.** Requires abandoning the V==P direct map for a windowed
  or temporary mapping scheme, touching `pmap_phys_to_kern`, DMA, driverkit,
  and every caller that assumes kernel VA equals physical address. Large,
  invasive, high regression risk for a machine class this OS will rarely meet.
- **Clamp only, no split.** Phase 1 alone. Safe but never uses more than
  816MB, which does not meet the goal.
- **Split only, no clamp.** Moves the wall from 823MB to 1784MB without fixing
  the overflow, the E820 sum, or the silent corruption past the wall. A 4GB
  machine would still fail, just differently.

## Phase 1: Survive large memory

Goal: a machine with any amount of RAM boots and runs correctly, using as much
as the current 1GB kernel window safely allows. No VA layout change.

### 1a. Booter: compute the right number

`getMemoryMap()` changes from "sum of all E820 RAM below 4GB" to reporting
**the top of the contiguous RAM run starting at 1MB**.

Anchoring at 1MB rather than 0 is deliberate: E820 always reports the legacy
hole at `0x9FC00–0x100000`, so a run anchored at 0 would stop at 640K.
Conventional memory below 640K remains the business of `memsize(0)` and
`convmem`.

E820 entries are not guaranteed sorted, so the scan is repeat-until-stable
rather than a single pass:

    top = 0x100000
    repeat
        changed = false
        for each entry of type E820_RAM
            if entry.base <= top and entry.end > top
                top = entry.end; changed = true
    until not changed

Bounded by the entry count (at most 32 passes over at most 32 entries), so a
few hundred integer comparisons at worst.

`sizememory()` keeps returning KB-above-1MB for the boot prompt and the
`MIN_EXT_MEM_KB` check in `boot.c`, but now hands its map array to the boot
struct instead of dropping it on the stack.

### 1b. kernBootStruct: carry the map

`KERNBOOTSTRUCT` lives at the fixed address `0x11000` and is shared with
drivers, so it is changed once, carving out of the unused `_reserved[7500]`
while preserving the total size. Fields after the reservation (`video`,
`pciInfo`, `eisaConfigFunctions`, `eisaSlotInfo`, `config`) do not shift, so
existing drivers keep working.

```c
#define BOOT_MEMMAP_MAX 32

typedef struct {
    unsigned int base;      /* clamped below 4GB */
    unsigned int end;       /* exclusive, clamped to 0xFFFFF000 */
    unsigned int type;      /* raw E820 type; kernel only acts on type 1 */
} boot_mem_range_t;         /* 12 bytes */

    /* ... replacing the head of _reserved: */
    int               memMapCount;                 /* 0 = no map, use extmem */
    boot_mem_range_t  memMap[BOOT_MEMMAP_MAX];     /* 384 bytes */
    char              _reserved[7500 - 4 - 384];
```

The fields are deliberately **32-bit `base`/`end`, not the 64-bit E820 pair**.
The kernel is 32-bit and can never address memory above 4GB, so the booter does
all the 64-bit clamping while it still has `long long` values in hand. This
also sidesteps `long long` alignment differences between the booter's and the
kernel's compilers.

Storing `end` rather than `length` avoids a wrap landmine: a range ending
exactly at 4GB would compute `base + length == 0` in 32-bit arithmetic. `end`
is clamped to `0xFFFFF000` instead, giving up the top 4KB of the address space,
where RAM never lives. Entries lying wholly above 4GB are dropped.

`_reserved[7500]` is confirmed unused: the only reference in the tree is a
`sizeof` print in `boot-2/i386/boot2/test.c`.

The struct is defined in two hand-kept copies that must stay identical:

- `src/boot-2/i386/libsa/kernBootStruct.h`
- `src/kernel-7/machdep/i386/kernBootStruct.h`

Drift between them silently corrupts the handoff, so both get a compile-time
size assertion of the form `typedef char assert_x[(cond) ? 1 : -1];` pinning
`sizeof(boot_mem_range_t)` and the offset of the field following `_reserved`.
`_Static_assert` is not available in this toolchain.

### 1c. Kernel: fix the overflow, then clamp to the VA budget

In `size_memory()` (`machdep/i386/i386_init.c`), `end_of_memory` is chosen as:

1. `maxmem` if the boot argument is set, else
2. the contiguous top from `memMap` if `memMapCount` is nonzero, else
3. legacy `KB(extmem)`.

All three go through a **saturating** KB-to-bytes conversion — if the KB value
exceeds `0xFFFFFFFF / 1024`, the result saturates to `0xFFFFF000` rather than
wrapping. This kills the `4194304 * 1024 -> 0` overflow.

The clamp below then applies to whichever of the three was chosen, `maxmem`
included, so a bad `maxmem=` boot argument cannot walk past the window either.

Then the clamp. Because `VM_MIN_KERNEL_ADDRESS` is 0 and physical memory is
mapped V==P, `end_of_memory` *is* the amount of kernel VA the direct map
consumes; the reservations sit directly above it. Kernel VA must hold both.
Both reservations depend on `mem_size`, which is what we are solving for, so
the relationship is circular.

It is resolved with a small **pure estimator** that mirrors the `zone_map_sizer`
and `buffer_map_sizer` formulas without touching their memoized globals.
Calling the real sizers this early would set `bufpages`, `nbuf` and `niobuf`,
which `startup_early()` consumes later, so the estimator must not call them.
The estimator rounds up wherever it is inexact.

Since the reserve is monotonic in memory size, a descending loop converges:

```c
if (!fits(end_of_memory, BUDGET)) {
    end_of_memory &= ~(CLAMP_STEP - 1);	/* round down first */

    while (!fits(end_of_memory, BUDGET))
	end_of_memory -= CLAMP_STEP;
}
```

Two details in that loop are load-bearing.

**The fit test subtracts on the budget side.** Written as
`end_of_memory + kmem_va_estimate(end_of_memory) > BUDGET`, the sum wraps in 32
bits once `end_of_memory` is near 4GB — exactly the case the clamp exists to
handle. `fits(m, b)` is therefore `m <= b && kmem_va_estimate(m) <= b - m`.

**The round-down happens before stepping, and only when clamping.** Stepping
down by 16MB preserves the detected size's residue modulo 16MB, so a saturated
`0xFFFFF000` detection would settle on `0x32FFF000` while a clean 2GB detection
settles on `0x33000000` — 4096 bytes apart, from the same budget. Rounding to a
step boundary first makes the clamped result a function of the budget alone, so
every over-budget machine reports an identical figure. It is inside the `if` so
that a machine which already fits keeps its exact size rather than losing up to
16MB to the rounding.

**The step is unsigned.** The snippet above is illustrative; the real loop
needs a `end_of_memory < CLAMP_STEP` guard before each `-=`, or a small enough
budget would wrap it to near 4GB. That branch is unreachable with a 1GB or
larger window — the estimate at 16MB of RAM is only ~79MB — but it is cheap and
the loop is not obviously terminating without it.

The rounding costs a little headroom: the true ceiling under a 1GB budget is
823.64MB (`0x337A3000`), and the clamp gives back 816MB. Roughly 8MB is the
price of a figure that is identical across every over-budget machine and can be
asserted exactly in a test, which is worth more than the memory.

`BUDGET` is `VM_MAX_KERNEL_ADDRESS - VM_MIN_KERNEL_ADDRESS`. Starting from 4GB
at 16MB steps is at most ~256 iterations of pure integer arithmetic, negligible
at boot. Reading `BUDGET` from the symbol rather than a literal means Phase 2
retargets the clamp for free.

The estimator carries a comment naming `zone_map_sizer()` and
`buffer_map_sizer()` as the functions it must track.

### 1d. Turn the failure mode into a panic

Independent of the clamp, `pmap_map()` in `machdep/i386/pmap.c` gets a guard
that panics if `virt` would reach `VM_MAX_KERNEL_ADDRESS`.

Today, overrunning that boundary walks `pmap_pd_entry()` off the end of the
single kernel page-directory page and scribbles on the following allocation — a
silent corruption that surfaces as an unrelated crash much later. The guard
converts it into an immediate, legible panic, and is what keeps the estimator
honest if it ever drifts out of sync with the real sizers.

This guard is worth having regardless of the rest of the change.

### 1e. Reporting

The raw detected size and the clamped size are stashed in globals and printed
alongside the existing `physical memory = %d.%d%d megabytes.` line in
`machdep/i386/unix_startup.c`. Printing from `size_memory()` itself is avoided
because console state is still early there.

That line already reaches the serial debug console, so the QEMU matrix is
readable without adding new plumbing.

### Phase 1 files touched

- `src/boot-2/i386/libsaio/biosfn.c` — contiguous-top scan
- `src/boot-2/i386/libsaio/saio_internal.h` — signature change
- `src/boot-2/i386/boot2/sizememory.c` — pass the map through
- `src/boot-2/i386/libsaio/bootstruct.c` — populate the new fields
- `src/boot-2/i386/libsa/kernBootStruct.h` — struct change + assertions
- `src/kernel-7/machdep/i386/kernBootStruct.h` — mirror of the above
- `src/kernel-7/machdep/i386/i386_init.c` — saturating conversion, map
  consumption, estimator, clamp loop, reporting globals
- `src/kernel-7/machdep/i386/pmap.c` — `pmap_map()` bounds panic
- `src/kernel-7/machdep/i386/unix_startup.c` — report the clamp

### Phase 1 success criteria

QEMU boots to userland at 256M, 768M, 1G, 1.5G, 2G and 4G, on a throwaway disk
image. Specifically:

- At 256M and 768M, reported physical memory matches the `-m` value.
- At 1G, 1.5G, 2G and 4G, physical memory clamps to the *same* value below 1GB
  in all four runs, and the boot output reports both the detected and the
  clamped size.
- The new `pmap_map()` guard does not panic at any size.
- 4G in particular no longer reports 0MB.

The clamped value is **816MB**, computed from the constants in 1c. Rounding to
a step boundary before stepping (see 1c) is what makes it a specific number
rather than a range: without it the figure would vary with the detected size.

## Phase 2: 2G/2G split

Goal: raise the ceiling from 816MB to 1776MB by giving the kernel a 2GB linear
window.

### 2a. Pre-flight check (gate) — measured, passes

Processes lose 1GB of VA in this phase. Nothing in-tree was ever endangered —
the highest fixed load address is driverkit at `0x66700000`, with libSystem at
`0x41300000` and dyld at `0x41100000`. The exposure was the **binary** Rhapsody
distribution: AppKit, Foundation and friends ship prebound at fixed addresses
and are not built from this tree.

This was measured against `golden.img` on 2026-09-20, reading the Mach-O load
commands directly out of the image rather than via `otool`. **Both halves
pass:**

| Check | Result |
| --- | --- |
| 182 dylibs/frameworks under `/usr/lib`, `/System/Library` | **0** reach `0x80000000`. Highest is `Printing.framework` at `0x64B0CE28` (~1.6GB). |
| 472 executables under `/bin`, `/usr/bin`, `/sbin`, `/usr/sbin` | **0** carry a non-zero `esp` in `LC_UNIXTHREAD`; all inherit the kernel default. Highest `__TEXT` end is `/usr/bin/emacs` at `0x000F0000`. |

The second row was not in the original version of this check and matters more
than the first. `pcb.c:1151` reads
`*user_stack = state->esp ? state->esp : VM_MAX_ADDRESS;` — a binary carrying a
3GB stack pointer in its `LC_UNIXTHREAD` would keep it verbatim and fault
immediately under a 2GB segment limit, whatever its `__TEXT` address. Scanning
segments alone would have missed that entirely.

The gate is therefore closed and Phase 2 is viable. It should be re-run if the
test image is ever replaced with one carrying different prebound binaries; if
anything then sits at or above `0x80000000`, Phase 2 stops and the approach is
reconsidered, with Phase 1 delivered either way.

### 2b. The constants

Three definitions move in lockstep:

| Symbol | File | Now | After |
|---|---|---|---|
| `VM_MAX_ADDRESS` | `mach/i386/vm_param.h` | `0xc0000000` | `0x80000000` |
| `VM_MAX_KERNEL_ADDRESS` | `mach/i386/vm_param.h` | `0x40000000` | `0x80000000` |
| `USRSTACK` | `bsd/i386/vmparam.h` | `0xc0000000` | `0x80000000` |

`KERNEL_LINEAR_BASE` is already defined as `VM_MAX_ADDRESS` and follows
automatically. `USRSTACK` is an independent hardcoded duplicate and must move
with the others.

Everything downstream derives from these three and needs no edit: the GDT and
LDT descriptors, `task.c`'s user map creation, `pcb.c`'s user stack top, and
`genassym.c`'s assembly exports of `_VM_MIN_KERNEL_ADDRESS` and
`_KERNEL_LINEAR_BASE`.

Segment descriptors encode the new size exactly. `page_limit(size)` is
`i386_round_page(size) - I386_PGBYTES`; for `0x80000000` that is `0x7FFFF000`,
giving a 20-bit limit field of `0x7FFFF` with page granularity. Kernel segment
base `0x80000000` plus limit `0x80000000` is exactly 4GB.

### 2c. Why 2GB and not 3GB

`kernel_pd` is a single page: 1024 PDEs of 4MB each (`I386_SECTBYTES` is
`(I386_PGBYTES / sizeof(pt_entry_t)) * I386_PGBYTES` = 4MB).

`pmap_bootstrap()` sets `kernel_pmap->root = &pd[KERNEL_LINEAR_BASE / 4MB]`,
and `pmap_enable_pg()` double-maps the kernel's PDEs down into `pd[0...]` so
paging can be switched on.

| Split | root index | kernel PDEs | double-map lands in | verdict |
|---|---|---|---|---|
| 3G/1G (today) | 768 | 768–1023 (256) | 0–255 | fits |
| **2G/2G** | **512** | **512–1023 (512)** | **0–511** | **fits exactly** |
| 1G/3G | 256 | 256–1023 (768) | 0–767 | collides with root at 256 |

At 2GB the double-map ends at `pd[511]` and the kernel's root starts at
`pd[512]` — adjacent, no overlap, no structural change. This is a hard
architectural ceiling, not a preference: one more doubling would require
restructuring the page-directory allocation, which is a separate and much
larger project.

### 2d. What Phase 1 already handles

The clamp loop reads `BUDGET` from `VM_MAX_KERNEL_ADDRESS`, so it retargets
itself to 2GB. At that ceiling the reserve is 64MB base + 128MB zone (at its
cap) + ~72MB buffer, about 264MB, landing just under 2GB. The practical ceiling
settles at **1776MB**, and anything above clamps automatically rather than
failing.

The `pmap_map()` panic guard likewise retargets and remains the backstop.

### 2e. Noted, not changed

`kern/kdp.c` computes `(VM_MAX_KERNEL_ADDRESS - VM_MIN_KERNEL_ADDRESS) +
0x50000000` with an unexplained magic constant, and will shift with the new
value. It is remote-debugger region reporting, not boot path. Left alone rather
than changed as a drive-by; flagged here so it is a known consequence rather
than a surprise.

### Phase 2 files touched

- `src/kernel-7/mach/i386/vm_param.h` — two constants
- `src/kernel-7/bsd/i386/vmparam.h` — `USRSTACK`

### Phase 2 success criteria

The pre-flight scan in 2a already passes, so the criteria are the QEMU matrix
at 256M, 768M, 1G, 1.5G, 2G and 4G:

- All sizes boot to userland.
- 256M, 768M, 1G and 1.5G all report their full `-m` value — none of them
  clamp any more. 1.5G is the one that proves the phase: it reported 816MB
  under Phase 1.
- 2G and 4G both clamp to **1776MB**.
- No panic from the `pmap_map()` guard at any size.

## Out of scope

- Multiple `mem_region` entries. The boot struct now carries enough information
  to populate `mem_region[0..1]` and use RAM above a low hole, but
  `num_regions` stays 1. The `vm_resident.c` and `vm_mem_region.c` paths have
  only ever run with one region, and exercising them is a separate change.
- Memory above 4GB, and therefore PAE.
- The ppc side. `boot-2/ppc` and `machdep/ppc` have their own
  `kernBootStruct.h` copies and are untouched.
- `kern/kdp.c`'s magic constant.
