# i386 Platform Expert — Phase 2: Extraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the remaining board-level hardware code — ISA DMA, APM, the system clock, and the interrupt subsystem — out of `machdep/i386` into the platform expert, introducing an interrupt-controller vtable and widening the IRQ mask so an IOAPIC can drop in later.

**Architecture:** Each subsystem moves in a self-contained task ordered by ascending risk: DMA, APM, clock, then interrupts. Interrupts are split across **three separate commits** — verbatim move, then controller extraction, then mask widening — so a bisect can distinguish a policy regression from a chip regression from a width regression.

**Tech Stack:** Same as Phase 1. C, NeXT `pb_makefiles`, `gnumake` on a Rhapsody DR2 guest, QEMU boot verification.

## Global Constraints

- **Design spec:** `docs/specs/2026-07-24-i386-platform-expert-design.md`.
- **Phase 1 must be complete.** `vm/baseline/mach_kernel.nm` and `vm/baseline/console.txt` must exist and the kernel must boot with `pexperti386.o` linked in.
- **The verification loop is build + symbol diff + boot, not unit tests.** No kernel unit-test harness exists; real unit tests arrive in Phase 3.
- **Move discipline:** except where a step shows the exact edit, moved files keep their contents. Every move commit must read cleanly under `git diff -M`.
- **`intr_exported.h` must stay byte-identical.** It is the driver-facing contract; three bus drivers import it (`EISAKernBus.m:40`, `EISAKernBusInterrupt.m:34`, `PCMCIAKernBus.m:45`). If a step would change it, stop and escalate.
- **Every new `.c` file must be added in three places:** `CFILES` in the owning `Makefile`, `OTHER_LINKED` in the owning `PB.project`, and — for `chips/` files — nowhere in `files.i386`.
- **Commit messages** start with `pexpert: `, describe behavior, one to two lines, no metadata.
- **All boot testing uses a throwaway copy of `vm/rhapsody.vmdk`.**
- Build: `powershell -File vm/rhap-vm.ps1 sync` then `... ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && gnumake install DSTROOT=/"` then `... ssh "cd /build/source/src/kernel-7 && gnumake kernels"`.

## Scope correction inherited from the spec

The design spec lists `chips/mc146818.{c,h}` as coming out of `machine_clock.c`. **It does not exist there.** `machine_clock.c` accesses only the 8254 PIT via `machdep/i386/timer.h` and `timer_inline.h` (ports `0x40`–`0x43`). The MC146818 CMOS RTC lives in `src/kernel-7/bsd/dev/i386/rtc.c` (ports `0x70`/`0x71`), which is a BSD character device with `conf.c` entries and is outside this phase's scope. Task 3 produces `chips/i8254` only. Moving the CMOS RTC into the platform expert is deferred and recorded in the Phase 2 exit criteria as follow-up work.

---

### Task 1: Move the ISA DMA controller

Lowest-risk subsystem: `dma.c` is self-contained and its callers reach it through `dma_exported.h`, which does not move.

**Files:**
- Move: `src/kernel-7/machdep/i386/dma.c` → `src/drivers-i386/bus/drvPExpert/i386/chips/i8237.c`
- Move: `src/kernel-7/machdep/i386/dma_buf.c` → `src/drivers-i386/bus/drvPExpert/i386/dma_buf.c`
- Move: `src/kernel-7/machdep/i386/dma_internal.h` → `src/drivers-i386/bus/drvPExpert/i386/chips/i8237.h`
- Move: `src/kernel-7/machdep/i386/dma_buf_internal.h` → `src/drivers-i386/bus/drvPExpert/i386/dma_buf_internal.h`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/Makefile`, `PB.project`, `chips/Makefile`, `chips/PB.project`
- Modify: `src/kernel-7/conf/files.i386` (remove two lines)

`machdep/i386/dma.h`, `dma_exported.h` and `dma_inline.h` **stay in the kernel tree** — they are contract headers reached via `HEADER_PATHS`.

**Interfaces:**
- Produces, in `pexperti386.o`: `_dma_initialize`, `_dma_assign_chan`, `_dma_deassign_chan`, `_dma_mask_chan`, `_dma_unmask_chan`, `_dma_chan_xfer_mode`, `_dma_chan_autoinit`, `_dma_chan_adrs_dir`, `_dma_chan_xfer_dir`, `_dma_xfer_chan`, `_dma_xfer`, `_dma_xfer_done`, `_dma_xfer_abort`, `_dma_xfer_width`.

- [ ] **Step 1: Move the four files**

```bash
git mv src/kernel-7/machdep/i386/dma.c src/drivers-i386/bus/drvPExpert/i386/chips/i8237.c
git mv src/kernel-7/machdep/i386/dma_internal.h src/drivers-i386/bus/drvPExpert/i386/chips/i8237.h
git mv src/kernel-7/machdep/i386/dma_buf.c src/drivers-i386/bus/drvPExpert/i386/dma_buf.c
git mv src/kernel-7/machdep/i386/dma_buf_internal.h src/drivers-i386/bus/drvPExpert/i386/dma_buf_internal.h
```

- [ ] **Step 2: Fix the two renamed includes**

In `chips/i8237.c`, change

```c
#import <machdep/i386/dma_internal.h>
```

to

```c
#import "i8237.h"
```

In `dma_buf.c`, change

```c
#import <machdep/i386/dma_buf_internal.h>
```

to

```c
#import "dma_buf_internal.h"
```

If either file also imports the other's old internal header, apply the same substitution. Leave every `<machdep/i386/…>` include that refers to a header still in the kernel tree exactly as it is.

- [ ] **Step 3: Register the files in the build**

In `src/drivers-i386/bus/drvPExpert/i386/Makefile`, change `CFILES` to:

```make
CFILES = bios.c dma_buf.c i386_init.c io_prim.c
```

and `HFILES` to:

```make
HFILES = dma_buf_internal.h
```

In `PB.project`, change `OTHER_LINKED` to include `dma_buf.c` and `H_FILES` to `(dma_buf_internal.h)`.

In `chips/Makefile`, change:

```make
HFILES = i8237.h

CFILES = i8237.c
```

and remove the `chips_stub.c` entry if Phase 1 Task 2 Step 9 created one; delete `chips/chips_stub.c`.

In `chips/PB.project`, set `H_FILES = (i8237.h); OTHER_LINKED = (i8237.c);`.

- [ ] **Step 4: Drop the two entries from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete:

```
machdep/i386/dma.c		standard
machdep/i386/dma_buf.c		standard
```

- [ ] **Step 5: Build and diff symbols**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && gnumake install DSTROOT=/"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake kernels"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7/BUILD/RELEASE_I386 && nm -g mach_kernel | sort" > vm/scratch-p2.nm
diff vm/baseline/mach_kernel.nm vm/scratch-p2.nm
```

Expected: no differences.

- [ ] **Step 6: Boot gate**

Install onto a fresh throwaway image and boot. Expected: login prompt; console matches `vm/baseline/console.txt`. Floppy and any ISA sound device exercise DMA; if the guest has neither, note in the commit that DMA is link-verified but not exercised.

- [ ] **Step 7: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert src/kernel-7/machdep/i386 src/kernel-7/conf/files.i386
git commit -m "pexpert: move the 8237 ISA DMA controller into the platform expert"
```

---

### Task 2: Move APM

**Files:**
- Move: `src/kernel-7/machdep/i386/APM_i386.c` → `src/drivers-i386/bus/drvPExpert/i386/apm.c`
- Move: `src/kernel-7/machdep/i386/APM_BIOS.h` → `src/drivers-i386/bus/drvPExpert/i386/apm.h`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/Makefile`, `PB.project`
- Modify: `src/kernel-7/conf/files.i386` (remove one line)

**Interfaces:**
- Consumes: `_bios32` from Phase 1 Task 4.

- [ ] **Step 1: Move both files**

```bash
git mv src/kernel-7/machdep/i386/APM_i386.c src/drivers-i386/bus/drvPExpert/i386/apm.c
git mv src/kernel-7/machdep/i386/APM_BIOS.h src/drivers-i386/bus/drvPExpert/i386/apm.h
```

- [ ] **Step 2: Fix the renamed include**

In `apm.c`, change

```c
#import <machdep/i386/APM_BIOS.h>
```

to

```c
#import "apm.h"
```

If any other file in the tree imports `<machdep/i386/APM_BIOS.h>`, find it with

```bash
grep -rn "APM_BIOS.h" src/kernel-7 src/drivers-i386
```

and stop if there are consumers outside the moved file — an external consumer means the header is a contract header and must stay in `machdep/i386` instead.

- [ ] **Step 3: Register in the build**

`Makefile`: `CFILES = apm.c bios.c dma_buf.c i386_init.c io_prim.c`, `HFILES = apm.h dma_buf_internal.h`.
`PB.project`: add `apm.c` to `OTHER_LINKED` and `apm.h` to `H_FILES`.

- [ ] **Step 4: Drop from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete:

```
machdep/i386/APM_i386.c		standard
```

- [ ] **Step 5: Build, diff symbols, boot gate**

Same commands as Task 1 Steps 5-6. Expected: no symbol differences; boots to login.

- [ ] **Step 6: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert src/kernel-7/machdep/i386 src/kernel-7/conf/files.i386
git commit -m "pexpert: move APM support into the platform expert"
```

---

### Task 3: Split the system clock

`machine_clock.c` mixes the machine-independent clock interface (`clock_get_counter`, `timer_set_deadline`, `us_spin`, `hardclock_init`) with 8254 register access reached through `timer_inline.h`. The interface half becomes `rtclock.c`; the register half becomes `chips/i8254.c`.

**Files:**
- Move: `src/kernel-7/machdep/i386/machine_clock.c` → `src/drivers-i386/bus/drvPExpert/i386/rtclock.c`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/i8254.c`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/i8254.h`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/rtclock.c` (replace direct `timer_inline.h` use with `i8254.h` calls)
- Modify: `src/kernel-7/conf/files.i386` (remove one line)

`machdep/i386/timer.h` and `timer_inline.h` **stay in the kernel tree**; `chips/i8254.c` includes them.

**Interfaces:**
- Produces, in `chips/i8254.h`:
  - `void i8254_set_mode(int counter, int mode, int rw);`
  - `void i8254_write_count(int counter, timer_cnt_val_t count);`
  - `timer_cnt_val_t i8254_read_count(int counter);`
  - `void i8254_latch(int counter);`
- Produces, unchanged, in `rtclock.c`: `_system_timer_dispatch`, `_hardclock_init`, `_us_spin`, `_us_spin_calibrate`, `_machine_clock_init`, `_clock_get_counter`, `_clock_set_counter`, `_clock_adjust_counter`, `_clock_map_counter`, `_timer_set_expire_func`, `_timer_set_deadline`, `_event_get`.

- [ ] **Step 1: Move the file**

```bash
git mv src/kernel-7/machdep/i386/machine_clock.c src/drivers-i386/bus/drvPExpert/i386/rtclock.c
```

- [ ] **Step 2: Create the 8254 chip header**

`src/drivers-i386/bus/drvPExpert/i386/chips/i8254.h`:

```c
/*
 * Intel 8254 programmable interval timer.
 *
 * Register-level access only.  Clock policy lives in rtclock.c.
 */

#ifndef _I8254_H_
#define _I8254_H_

#import <machdep/i386/timer.h>

extern void            i8254_set_mode(int counter, int mode, int rw);
extern void            i8254_write_count(int counter, timer_cnt_val_t count);
extern timer_cnt_val_t i8254_read_count(int counter);
extern void            i8254_latch(int counter);

#endif /* _I8254_H_ */
```

- [ ] **Step 3: Create the 8254 chip implementation**

`src/drivers-i386/bus/drvPExpert/i386/chips/i8254.c`:

```c
/*
 * Intel 8254 programmable interval timer.
 *
 * Extracted from machdep/i386/machine_clock.c; the register access here is
 * unchanged, only relocated behind a named interface so a different timebase
 * can replace it without touching clock policy.
 */

#define DEFINE_INLINE_FUNCTIONS

#import <machdep/i386/timer_inline.h>

#import "i8254.h"

void
i8254_set_mode(int counter, int mode, int rw)
{
    timer_ctl_reg_t	reg = (timer_ctl_reg_t) { 0 };

    reg.sc   = counter;
    reg.mode = mode;
    reg.rw   = rw;

    timer_set_ctl(reg);
}

void
i8254_write_count(int counter, timer_cnt_val_t count)
{
    timer_write(counter, count);
}

timer_cnt_val_t
i8254_read_count(int counter)
{
    return (timer_read(counter));
}

void
i8254_latch(int counter)
{
    timer_latch(counter);
}
```

**Before writing this, open `src/kernel-7/machdep/i386/timer.h` and confirm the `timer_ctl_reg_t` field names are `sc`, `mode` and `rw`.** If they differ, use the actual names — the struct is a bitfield describing the 8254 control word and the field order matters. Confirm likewise that `timer_set_ctl`, `timer_write`, `timer_read` and `timer_latch` are the inline names in `timer_inline.h`.

- [ ] **Step 4: Route rtclock.c through the chip interface**

In `rtclock.c`, remove

```c
#import <machdep/i386/timer_inline.h>
```

and add

```c
#import "chips/i8254.h"
```

Then replace each direct register call. There are five sites, at the original `machine_clock.c` line numbers shown:

- line 172, in `us_spin_calibrate()`: `timer_set_ctl(reg);` → `i8254_set_mode(TIMER_CNT0_SEL, TIMER_SWTRIGMODE, TIMER_CTL_RW_BOTH);` and delete the now-unused local `reg` construction above it.
- line 175: `timer_write(TIMER_CNT0_SEL, TIMER_COUNT_MAX);` → `i8254_write_count(TIMER_CNT0_SEL, TIMER_COUNT_MAX);`
- line 179: `timer_latch(TIMER_CNT0_SEL); leftover = timer_read(TIMER_CNT0_SEL);` → `i8254_latch(TIMER_CNT0_SEL); leftover = i8254_read_count(TIMER_CNT0_SEL);`
- line 230, in `machine_clock_init()`: `timer_set_ctl(reg);` → `i8254_set_mode(TIMER_CNT0_SEL, TIMER_NDIVMODE, TIMER_CTL_RW_BOTH);` and delete the local `reg` construction above it.
- the `timer_write` immediately following line 230 that loads the divisor from `system_timer_constant()` → `i8254_write_count(TIMER_CNT0_SEL, <same argument>);`

**Read the surrounding code before each substitution.** The `reg` values built at lines 168 and 226 encode the mode and read/write fields being passed above; if the actual mode constants differ from `TIMER_SWTRIGMODE` and `TIMER_NDIVMODE`, pass what the original code set. Preserving the exact programmed mode matters more than matching the constant names used here.

- [ ] **Step 5: Register in the build**

`Makefile`: `CFILES = apm.c bios.c dma_buf.c i386_init.c io_prim.c rtclock.c`.
`PB.project`: add `rtclock.c` to `OTHER_LINKED`.
`chips/Makefile`: `HFILES = i8237.h i8254.h`, `CFILES = i8237.c i8254.c`.
`chips/PB.project`: `H_FILES = (i8237.h, i8254.h); OTHER_LINKED = (i8237.c, i8254.c);`.

- [ ] **Step 6: Drop from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete:

```
machdep/i386/machine_clock.c	standard
```

- [ ] **Step 7: Build, diff symbols, boot gate**

Expected: no symbol differences.

Boot gate is stricter here than in Tasks 1-2: **a mis-programmed 8254 shows up as a wrong clock rate, not a hang.** After reaching the login prompt, confirm the clock advances at real time by running `date`, waiting 60 seconds by an external clock, and running `date` again. Expected: 60 ± 2 seconds elapsed. A large drift means the mode or divisor changed in Step 4.

- [ ] **Step 8: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert src/kernel-7/machdep/i386 src/kernel-7/conf/files.i386
git commit -m "pexpert: move the system clock into the platform expert

Splits 8254 register access into chips/i8254 behind a named interface."
```

---

### Task 4: Move the interrupt subsystem verbatim

**First of three interrupt commits.** This one moves the file and changes nothing else, so that a later bisect can attribute any regression to the controller split or the mask widening rather than to relocation.

Note what is moving: besides the `intr_*` API, `intr.c` defines the entire **spl family** — `splx`, `spln`, `ipltospl`, `curipl`, `set_ipl`, `set_masked_ipl`, `lower_ipl`, `lower_masked_ipl` and the macro-generated `spl<name>` functions. These are called throughout the kernel via `machspl.h`. After this task they resolve from `pexperti386.o`. That is expected and is the single largest symbol relocation in the project.

**Files:**
- Move: `src/kernel-7/machdep/i386/intr.c` → `src/drivers-i386/bus/drvPExpert/i386/interrupt.c`
- Move: `src/kernel-7/machdep/i386/intr.h` → `src/drivers-i386/bus/drvPExpert/i386/chips/i8259.h`
- Move: `src/kernel-7/machdep/i386/intr_inline.h` → `src/drivers-i386/bus/drvPExpert/i386/chips/i8259_inline.h`
- Move: `src/kernel-7/machdep/i386/intr_internal.h` → `src/drivers-i386/bus/drvPExpert/i386/intr_internal.h`
- Modify: `src/kernel-7/conf/files.i386` (remove one line)

`machdep/i386/intr_exported.h` **stays and does not change.**

- [ ] **Step 1: Confirm no external consumer of the private headers**

```bash
grep -rn "intr_internal.h\|intr_inline.h\|machdep/i386/intr.h" src/kernel-7 src/drivers-i386 src/drivers-ppc
```

Expected: matches only inside `machdep/i386` (in the files being moved) — plus `machdep/i386/machdep.c` and `machdep/i386/kdp_machdep.c`, which import `intr_exported.h` only. If any file outside the move set imports a private header, stop and escalate: the header is a contract header and the plan's boundary is wrong.

- [ ] **Step 2: Move the four files**

```bash
git mv src/kernel-7/machdep/i386/intr.c src/drivers-i386/bus/drvPExpert/i386/interrupt.c
git mv src/kernel-7/machdep/i386/intr.h src/drivers-i386/bus/drvPExpert/i386/chips/i8259.h
git mv src/kernel-7/machdep/i386/intr_inline.h src/drivers-i386/bus/drvPExpert/i386/chips/i8259_inline.h
git mv src/kernel-7/machdep/i386/intr_internal.h src/drivers-i386/bus/drvPExpert/i386/intr_internal.h
```

- [ ] **Step 3: Fix the renamed includes**

In `interrupt.c`, change

```c
#import <machdep/i386/intr_internal.h>
#import <machdep/i386/intr_inline.h>
```

to

```c
#import "intr_internal.h"
#import "chips/i8259_inline.h"
```

Leave `#import <machdep/i386/intr_exported.h>` and `#import <machdep/i386/cpu_inline.h>` unchanged.

In `chips/i8259_inline.h`, change any `#import <machdep/i386/intr.h>` to `#import "i8259.h"`, and any `#import <machdep/i386/intr_internal.h>` to `#import "../intr_internal.h"`.

In `intr_internal.h`, change any `#import <machdep/i386/intr.h>` to `#import "chips/i8259.h"`.

- [ ] **Step 4: Register in the build**

`Makefile`: `CFILES = apm.c bios.c dma_buf.c i386_init.c interrupt.c io_prim.c rtclock.c`, `HFILES = apm.h dma_buf_internal.h intr_internal.h`.
`PB.project`: add `interrupt.c` to `OTHER_LINKED`, `intr_internal.h` to `H_FILES`.
`chips/Makefile`: `HFILES = i8237.h i8254.h i8259.h i8259_inline.h`.
`chips/PB.project`: add both headers to `H_FILES`.

- [ ] **Step 5: Drop from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete:

```
machdep/i386/intr.c		standard
```

- [ ] **Step 6: Build, diff symbols**

Expected: no differences. Confirm explicitly that `_splx`, `_spln`, `_curipl`, `_intr_initialize` and `_intr_register_irq` are all still globally defined:

```bash
powershell -File vm/rhap-vm.ps1 ssh "nm -g /build/source/src/kernel-7/BUILD/RELEASE_I386/mach_kernel | grep -E '_(splx|spln|curipl|intr_initialize|intr_register_irq)$'"
```

- [ ] **Step 7: Boot gate**

Install onto a fresh throwaway image and boot. Expected: login prompt; console matches baseline. Then exercise interrupts under load: `ping` the guest continuously from the host for 60 seconds while running a disk-heavy command (`find / -type f | wc -l`) on the guest. Expected: no lost console, no watchdog, ping loss under 1%.

- [ ] **Step 8: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert src/kernel-7/machdep/i386 src/kernel-7/conf/files.i386
git commit -m "pexpert: move the interrupt subsystem into the platform expert

Verbatim relocation; the spl family now resolves from pexperti386.o."
```

---

### Task 5: Extract the 8259 behind a controller vtable

**Second of three interrupt commits.** Policy stays in `interrupt.c`; register access moves to `chips/i8259.c` behind `intr_controller_t`.

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/i8259.c`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/intr_internal.h` (add `intr_controller_t`, move `INTR_SLAVE_IRQ` out)
- Modify: `src/drivers-i386/bus/drvPExpert/i386/chips/i8259.h` (gain `INTR_SLAVE_IRQ` and the controller export)
- Modify: `src/drivers-i386/bus/drvPExpert/i386/interrupt.c` (route hardware access through the vtable)

**Interfaces:**
- Produces, in `intr_internal.h`:

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

extern const intr_controller_t *intr_controller_p;
```

- Produces, in `chips/i8259.h`: `extern const intr_controller_t i8259_controller;`

- [ ] **Step 1: Add the controller type to intr_internal.h**

Append to `src/drivers-i386/bus/drvPExpert/i386/intr_internal.h`, before the closing guard, the `intr_controller_t` definition and `intr_controller_p` declaration exactly as written in the Interfaces block above.

In the same file, **delete** the line

```c
#define INTR_SLAVE_IRQ		2	// IRQ of slave
```

and every macro that depends on it — `INTR_MASK_SLAVE`, `INTR_MASK_ALL`, `INTR_MASK_NONE`. These are 8259 facts. Keep `INTR_NIRQ`, `intr_irq_mask_t` and `INTR_MASK_IRQ(x)` where they are; the widening happens in Task 6.

- [ ] **Step 2: Move the 8259 constants into the chip header**

Add to `src/drivers-i386/bus/drvPExpert/i386/chips/i8259.h`, before the closing guard:

```c
#import "../intr_internal.h"

#define INTR_SLAVE_IRQ		2	/* IRQ the slave PIC cascades on */
#define INTR_MASK_SLAVE		INTR_MASK_IRQ(INTR_SLAVE_IRQ)
#define INTR_MASK_ALL		((unsigned short) (-1 & ~INTR_MASK_SLAVE))
#define INTR_MASK_NONE		((unsigned short) (0  & ~INTR_MASK_SLAVE))

extern const intr_controller_t i8259_controller;
```

- [ ] **Step 3: Create chips/i8259.c**

Move into this new file, cut verbatim from `interpt.c`: the `send_eoi`, `set_elcr` and `set_irq_mask` static inline functions, and the eight `MASTER_ICW*` / `SLAVE_ICW*` macro definitions. Wrap them in the controller:

```c
/*
 * Intel 8259A programmable interrupt controller pair.
 *
 * Register access and initialisation only.  The ipl policy, dispatch table and
 * deferred-interrupt logic stay in interrupt.c.
 */

#define DEFINE_INLINE_FUNCTIONS

#import <mach/mach_types.h>
#import <machdep/i386/cpu_inline.h>

#import "i8259.h"
#import "i8259_inline.h"

/* --- cut verbatim from interrupt.c: send_eoi, set_elcr, set_irq_mask --- */
/* --- cut verbatim from interrupt.c: MASTER_ICW1..4, SLAVE_ICW1..4    --- */

static intr_irq_mask_t	current_elcr;

static void
i8259_init(void)
{
    initialize_master(MASTER_ICW1, MASTER_ICW2, MASTER_ICW3, MASTER_ICW4);
    initialize_slave (SLAVE_ICW1,  SLAVE_ICW2,  SLAVE_ICW3,  SLAVE_ICW4);
}

static void
i8259_set_mask(intr_irq_mask_t mask)
{
    set_irq_mask(mask);
}

static void
i8259_set_trigger(intr_irq_mask_t level_mask)
{
    set_elcr(level_mask);
}

static void
i8259_eoi(int irq)
{
    send_eoi();
}

static boolean_t
i8259_is_spurious(int irq)
{
    if (irq == 7)
	return ((get_master_isr() & (1 << 7)) == 0);
    if (irq == 15)
	return ((get_slave_isr() & (1 << 7)) == 0);
    return (FALSE);
}

const intr_controller_t i8259_controller = {
    "8259A",
    INTR_NIRQ,
    i8259_init,
    i8259_set_mask,
    i8259_set_trigger,
    i8259_eoi,
    i8259_is_spurious,
};
```

`set_irq_mask` in the original folds in the file-static `disabled_irq_mask`; that variable is policy and stays in `interrupt.c`. **Change `set_irq_mask` as you move it so it masks exactly the value passed in**, and make `interrupt.c` fold `disabled_irq_mask` into the argument at each call site instead. Do not leave a copy of `disabled_irq_mask` in the chip.

`current_elcr` is the chip's own write-suppression cache and moves with `set_elcr`; delete the original in `interrupt.c`.

**Read the existing phantom-interrupt check in `interrupt.c` before writing `i8259_is_spurious`.** The original logic is at the top of `intr_handler`; reproduce it exactly rather than the sketch above, which assumes but does not verify the standard IRQ7/IRQ15 in-service test.

- [ ] **Step 4: Route interrupt.c through the vtable**

In `interrupt.c`:

- Add `#import "chips/i8259.h"`.
- Add the definition `const intr_controller_t *intr_controller_p = &i8259_controller;`.
- Delete the moved `send_eoi`, `set_elcr`, `set_irq_mask` and `current_elcr`.
- In `intr_initialize()`, replace the two `initialize_master`/`initialize_slave` calls with `(*intr_controller_p->init)();`.
- Replace every remaining `send_eoi()` with `(*intr_controller_p->eoi)(irq)` — pass the IRQ actually in hand at that site.
- Replace every `set_irq_mask(m)` with `(*intr_controller_p->set_mask)(<m with disabled_irq_mask folded in>)`.
- Replace every `set_elcr(m)` with `(*intr_controller_p->set_trigger)(m)`.
- Replace the inline phantom-interrupt test in `intr_handler` with `(*intr_controller_p->is_spurious)(irq)`.
- Replace `INTR_MASK_ALL` and `INTR_MASK_NONE` uses in `intr_initialize()` with the same names, now supplied by `chips/i8259.h`.

Keep `dispatch_table`, `ipl_mask`, `defer_table`, `current_ipl`, `masked_ipl`, `current_irq_mask`, `disabled_irq_mask` and every spl function exactly where they are.

- [ ] **Step 5: Register in the build**

`chips/Makefile`: `CFILES = i8237.c i8254.c i8259.c`.
`chips/PB.project`: add `i8259.c` to `OTHER_LINKED`.

- [ ] **Step 6: Build and diff symbols**

Expected: no differences from baseline. `_i8259_controller` and `_intr_controller_p` are new **but must not appear** in the kernel's global symbol list if declared as shown — `i8259_controller` is `const` and non-static, so it will appear. That is a deliberate addition; record it:

```bash
diff vm/baseline/mach_kernel.nm vm/scratch-p2.nm
```

Expected: exactly two added lines, `_i8259_controller` and `_intr_controller_p`. Any other difference is a regression.

- [ ] **Step 7: Boot gate**

Boot and run the same 60-second ping-plus-disk-load test as Task 4 Step 7. **This is the highest-risk gate in the whole project** — a wrong EOI or mask ordering typically shows as a hang shortly after the first device interrupt, or as one device silently never receiving interrupts. If the guest boots but networking is dead, suspect the `set_mask` `disabled_irq_mask` folding in Step 4.

- [ ] **Step 8: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: put the 8259 behind an interrupt-controller vtable

Interrupt policy stays in interrupt.c; register access moves to chips/i8259."
```

---

### Task 6: Widen the IRQ mask to 32 bits

**Third of three interrupt commits, deliberately separate.** The 16-bit `intr_irq_mask_t` is what would block a 24-pin IOAPIC. Nothing outside the platform expert sees this type.

**Files:**
- Modify: `src/drivers-i386/bus/drvPExpert/i386/intr_internal.h`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/interrupt.c`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/chips/i8259.c`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/chips/i8259.h`

- [ ] **Step 1: Widen the type and add the array bound**

In `intr_internal.h`, change

```c
typedef struct {
    unsigned short	
			mask		:16;
} intr_irq_mask_t;
```

to

```c
typedef struct {
    unsigned int
			mask		:32;
} intr_irq_mask_t;
```

and change

```c
#define INTR_NIRQ		16	// number of IRQs available
```

to

```c
#define INTR_NIRQ_MAX		32	/* sizes arrays; upper bound on any controller */
#define INTR_NIRQ		16	/* IRQs on the 8259 pair; see i8259_controller.nirq */
```

- [ ] **Step 2: Size the policy arrays by the maximum**

In `interrupt.c`, change

```c
static intr_dispatch_t	dispatch_table[INTR_NIRQ];
```

to

```c
static intr_dispatch_t	dispatch_table[INTR_NIRQ_MAX];
```

- [ ] **Step 3: Bound every loop by the live controller**

In `interrupt.c`, every loop or range check written against `INTR_NIRQ` becomes a check against `intr_controller_p->nirq`. Find them with:

```bash
grep -n "INTR_NIRQ" src/drivers-i386/bus/drvPExpert/i386/interrupt.c
```

The bounds checks in `intr_register_irq`, `intr_unregister_irq`, `intr_enable_irq`, `intr_disable_irq`, `intr_change_ipl` and `intr_change_mode` all read `if (irq < 0 || irq >= INTR_NIRQ)`; change each to `if (irq < 0 || irq >= intr_controller_p->nirq)`.

Leave `INTR_NIRQ` itself defined — `chips/i8259.c` uses it for `i8259_controller.nirq`.

- [ ] **Step 4: Keep the 8259 masks 16-bit**

In `chips/i8259.h`, the `INTR_MASK_ALL` and `INTR_MASK_NONE` casts to `unsigned short` are correct and must stay — the 8259 pair genuinely has 16 inputs, and the master/slave half-splitting union in `set_irq_mask` and `set_elcr` depends on 16-bit halves.

**In `chips/i8259.c`, verify the mask-splitting unions still work.** Both `set_irq_mask` and `set_elcr` declare a union of `intr_irq_mask_t` with two `unsigned short` bitfield structs to extract the master and slave halves. With `intr_irq_mask_t` now 32 bits, that union is no longer half-for-half aligned. Replace the union in each function with explicit shifts:

```c
    set_master_mask((intr_ocw1_t) { (unsigned char)(m & 0xff) });
    set_slave_mask ((intr_ocw1_t) { (unsigned char)((m >> 8) & 0xff) });
```

where `m` is the incoming `mask.mask`. Apply the same shift treatment in `set_elcr` with `set_master_elcr`/`set_slave_elcr`.

This is the substantive change in this task and the reason it is a separate commit.

- [ ] **Step 5: Build and diff symbols**

Expected: same two added symbols as Task 5, nothing further.

- [ ] **Step 6: Boot gate**

Boot and run the 60-second ping-plus-disk-load test. A mistake in Step 4's shift extraction shows as some IRQs permanently masked — most visibly as a dead NIC or dead keyboard — rather than as a hang.

- [ ] **Step 7: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: widen the i386 IRQ mask to 32 bits

Replaces the 16-bit half-splitting unions in the 8259 with explicit shifts so a
wider controller can be added without changing interrupt policy."
```

---

## Phase 2 exit criteria

1. `src/kernel-7/machdep/i386` no longer contains `intr.c`, `intr.h`, `intr_inline.h`, `intr_internal.h`, `dma.c`, `dma_buf.c`, `dma_internal.h`, `dma_buf_internal.h`, `machine_clock.c`, `APM_i386.c` or `APM_BIOS.h`.
2. `machdep/i386/intr_exported.h`, `dma_exported.h`, `dma.h`, `dma_inline.h`, `timer.h`, `timer_inline.h` and `bios.h` are unchanged and still installed.
3. `nm -g mach_kernel | sort` differs from `vm/baseline/mach_kernel.nm` by exactly two added lines: `_i8259_controller` and `_intr_controller_p`.
4. The kernel boots to login, `date` advances at real time, and a 60-second ping-plus-disk-load test shows under 1% packet loss.
5. `intr_irq_mask_t` is 32 bits and no code outside the platform expert references it.

## Deferred out of this phase

- **The MC146818 CMOS RTC** (`src/kernel-7/bsd/dev/i386/rtc.c`) stays a BSD character device. The design spec incorrectly listed it as coming from `machine_clock.c`. Moving it into `chips/mc146818.c` requires also relocating its `conf.c` entries and is its own piece of work.
