# i386 Large Memory Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let i386 machines with more than 1GB of RAM boot correctly, and actually use up to ~1.75GB of it.

**Architecture:** Two phases. Phase 1 keeps the existing 1GB kernel linear window, fixes the E820 sizing bugs, plumbs a physical memory map through `kernBootStruct`, and clamps usable memory to what the kernel address space can hold — so a 4GB machine boots and uses 816MB instead of reporting 0MB and corrupting memory. Phase 2 moves the segmented split from 3G/1G to 2G/2G, which raises the same clamp to 1776MB with no structural change to the page directory. The phases are separate commits so the split stays independently revertable.

**Tech Stack:** C (gcc 2.x era, no C99), i386 assembly, `gnumake` with the Rhapsody `pb_makefiles` toolchain. Host-side tooling is Python 3.13 stdlib (`unittest`), run from inside `vm/`.

**Spec:** `docs/superpowers/specs/2026-07-25-i386-large-memory-design.md`

This plan replaces `docs/superpowers/plans/2026-07-25-i386-large-memory.md`, which was deleted in the same commit that added this file. See "What changed from the previous plan" at the end for why.

## Global Constraints

- **This is a 1999 toolchain.** No `_Static_assert`, no C99 declarations-after-statements, no `long long` in kernel code. Declare all locals at the top of a block. Compile-time assertions use `typedef char name[(cond) ? 1 : -1];`.
- **No host C compiler.** `gcc`, `cc` and `clang` are all absent from this Windows host. Every C change compiles on the Rhapsody build environment, which sees this repo as its source root.
- **`kernBootStruct.h` exists in two hand-kept i386 copies** whose layout must stay byte-for-byte identical:
  - `src/boot-2/i386/libsa/kernBootStruct.h`
  - `src/kernel-7/machdep/i386/kernBootStruct.h`

  The kernel copy contains a second, dead `#if 0` struct near the top (line 92). Do not edit that one; the live struct is the one after `#else`, whose `_reserved` is at line 201.
- **`KERNBOOTSTRUCT` lives at the fixed address `0x11000`** and is read by drivers. Its total size must not change.
- **Image slack**, measured with `rhap_image.py slack` on `golden.img`:
  - `/mach_kernel` — 1459520 used, 1460224 writable, **704 bytes spare**. A rebuilt kernel always needs `graft-kernel.py`, never `rhap_inject.py put`.
  - `/usr/standalone/i386/boot` — 39616 used, 39936 writable, **320 bytes spare**. The booter must stay under 39936 bytes or `put` refuses it.
- **Never run `fsck` on an image with a grafted file**, and a grafted inode will not survive a normal multi-user boot. See `vm/README.md` "Things that are not obvious".
- **Only `vm/work/test.img` may be written.** `graft-kernel.py` and `rhap_inject.py` both enforce this via `rhap_inject.check_target`, which matches that exact path and nothing else under `vm/work`.
- **The ppc side is out of scope.** `src/boot-2/ppc/ppcMac/libsa/kernBootStruct.h` and `src/kernel-7/machdep/ppc/` have their own copies and are not touched.
- Commit messages: short, human-readable, subsystem-prefixed (`boot: `, `kernel: `, `vm: `), one to two lines, describing what the change does rather than listing files. **No metadata, no trailers, no co-author lines** (CLAUDE.md §5).
- Surgical changes only (CLAUDE.md §3). Every changed line traces to this plan. Do not reformat or improve adjacent code.
- **Git Bash mangles absolute guest paths.** Any command passing a path like `/usr/standalone/i386/boot` to a Python tool needs `MSYS_NO_PATHCONV=1` in front, or MSYS rewrites it into a Windows path and the tool reports a bogus `FileNotFoundError`. The commands below already carry it where needed.

## Verified Before Writing This Plan

These were measured against the current tree and `golden.img`. They are recorded so nobody re-derives them, and so a surprise during execution is recognised as a *change* rather than a discovery.

**The Phase 2 gate is already closed — it passes.** Shrinking user address space to 2GB was the one design risk that could have invalidated the approach. Both halves were checked:

| Check | Result |
| --- | --- |
| 182 Mach-O dylibs/frameworks under `/usr/lib`, `/System/Library` | **0** reach `0x80000000`. Highest is `Printing.framework` at `0x64B0CE28` (~1.6GB). |
| 472 executables under `/bin`, `/usr/bin`, `/sbin`, `/usr/sbin` | **0** carry a non-zero `esp` in `LC_UNIXTHREAD`; all inherit the kernel default. Highest `__TEXT` end is `/usr/bin/emacs` at `0x000F0000`. |

The `esp` half matters because `pcb.c:1151` reads `*user_stack = state->esp ? state->esp : VM_MAX_ADDRESS;` — a binary with a 3GB stack pointer baked in would fault immediately under a 2GB split. None do.

**Sizing constants**, all re-confirmed present and unchanged:

| Constant | Value | Source |
| --- | --- | --- |
| kernel MI `page_size` | 8192 (`2 * I386_PGBYTES`) | `i386_init.c:143` |
| `MAXBSIZE` | 8192 | `bsd/sys/param.h:184` |
| `MAXPHYS` | 65536 | `bsd/i386/param.h:58` |
| `zone_map_size_min` / `max` | 12MB / 128MB | `kern/zalloc.c:156-157` |
| zone map size | `mem_size / 8` | `kern/zalloc.c:1416` |
| `pmap_bootstrap` reserve base | 64MB | `pmap.c:411` |

**Expected reported memory**, computed from those constants. Clamped values are exact because the clamp lands on a 16MB boundary (see Task 2); unclamped values track the detected size.

| `--mem` | Phase 1 (1GB budget) | Phase 2 (2GB budget) |
| --- | --- | --- |
| 768 | 768 MB, full | 768 MB, full |
| 1536 | **816 MB, clamped** | **1536 MB, full** |
| 2048 | 816 MB, clamped | 1776 MB, clamped |
| 4096 | 816 MB, clamped | 1776 MB, clamped |

`-m 1536` is the headline: 816MB before Phase 2, 1536MB after.

**Current tooling** (all tracked, all confirmed present):

- Kernel build: `cd src/kernel-7/conf && gnumake I386 OBJROOT=../BUILD SYMROOT=../BUILD`, output at `src/kernel-7/BUILD/RELEASE_I386/mach_kernel`. This is the invocation `vm/build-i386-kernel-ahci.sh` uses.
- `vm/graft-kernel.py SRC_IMAGE KERNEL_FILE OUT_IMAGE` — copies the source image and grafts the kernel in one step, using a 23MB PDF donor. Replaces the old reset-then-graft dance.
- `vm/rhap_inject.py <image> put <path> <local-file>` — in-place overwrite, never allocates.
- `vm/qemu-shot.py IMAGE OUTDIR --at S --keys STR` — headless boot, serial log at `OUTDIR/serial.log`.
- `src/boot-2/i386/MakeInc.dir:19-27` forwards `OBJROOT`/`SYMROOT`/`DSTROOT`/`SRCROOT` into `install_i386`, so command-line roots propagate. `boot2/Makefile` already fails the build above `MAXBOOTSIZE` (45056).

**Not yet present:** `qemu-shot.py` hardcodes `-m 128` with no override (Task 1 adds it), and there is no booter build script (Task 4 adds one).

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `vm/build-i386-boot.sh` | Build and stage the i386 booter, mirroring `build-i386-kernel-ahci.sh` conventions |

**Modified:**

| Path | Change |
| --- | --- |
| `vm/qemu-shot.py:191,194,221,238,315,321` | `--mem` option so the boot matrix can vary guest RAM |
| `vm/test_qemu_shot.py` | Test for the `--mem` plumbing |
| `src/kernel-7/machdep/i386/pmap.c:263` | Panic in `pmap_map()` when the kernel window would be overrun |
| `src/kernel-7/machdep/i386/i386_init.c:92-94,433-468` | Reporting globals, saturating KB conversion, kmem estimator, clamp, memory-map consumption |
| `src/kernel-7/machdep/i386/unix_startup.c:232` | Report the detected-vs-clamped size |
| `src/kernel-7/machdep/i386/kernBootStruct.h:179,201` | `boot_mem_range_t`, `memMapCount`, `memMap`, size assertions |
| `src/boot-2/i386/libsa/kernBootStruct.h:138,160` | Identical mirror of the above |
| `src/boot-2/i386/libsaio/saio_internal.h:25,43-51` | Boot-struct import; `getMemoryMap()` signature |
| `src/boot-2/i386/libsaio/biosfn.c:97-160` | `getMemoryMap()` returns the contiguous top, sets `bb.es`, emits 32-bit ranges |
| `src/boot-2/i386/boot2/sizememory.c:24-65` | Populate `kernBootStruct->memMap`, use the new return value |
| `src/kernel-7/mach/i386/vm_param.h:66,69` | Phase 2: `VM_MAX_ADDRESS`, `VM_MAX_KERNEL_ADDRESS` |
| `src/kernel-7/bsd/i386/vmparam.h:46` | Phase 2: `USRSTACK` |

Nothing is deleted by these tasks. The superseded plan was removed in the same commit that added this one.

---

## Task 1: Vary guest RAM from the capture harness

`qemu-shot.py` hardcodes `-m 128`. Without this every size in the matrix would silently boot the same 128MB guest, so it comes before any code change.

**Files:**
- Modify: `vm/qemu-shot.py:191,194,221,238,315,321`
- Test: `vm/test_qemu_shot.py`

**Interfaces:**
- Consumes: nothing
- Produces: `build_qemu_args(image, qmp_port, trace, serial_log, mem="128")` and a `--mem` CLI flag. `mem` has a default so the existing 4-positional call at `test_qemu_shot.py:102` keeps working.

- [ ] **Step 1: Write the failing test**

Add to `vm/test_qemu_shot.py`, in the same class as `test_snapshot_and_serial_log_are_present`:

```python
    def test_mem_defaults_to_128(self):
        args = qemu_shot.build_qemu_args("work/test.img", 1234, False, "out/serial.log")
        self.assertIn("-m", args)
        self.assertEqual(args[args.index("-m") + 1], "128")

    def test_mem_is_overridable(self):
        args = qemu_shot.build_qemu_args(
            "work/test.img", 1234, False, "out/serial.log", mem="4096")
        self.assertEqual(args[args.index("-m") + 1], "4096")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd D:/RhapsodiOS/vm && python -m unittest test_qemu_shot -v
```

Expected: `test_mem_is_overridable` FAILS with `TypeError: build_qemu_args() takes 4 positional arguments but 5 were given`. `test_mem_defaults_to_128` passes already.

- [ ] **Step 3: Add the parameter**

In `vm/qemu-shot.py`, line 191 and the `-m` entry at line 194:

```python
def build_qemu_args(image, qmp_port, trace, serial_log, mem="128"):
    args = [
        "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
        "-m", str(mem), "-k", "en-us",
```

Line 221:

```python
def run(image, outdir, at_points, keys, keys_at, trace, mem="128"):
```

Line 238:

```python
    qemu_args = build_qemu_args(image, qmp_port, trace, serial_log, mem)
```

Next to the other `add_argument` calls around line 315:

```python
    p.add_argument("--mem", default="128",
                   help="guest RAM passed to qemu -m (default 128)")
```

Line 321:

```python
    run(args.image, args.outdir, at_points, args.keys, args.keys_at,
        args.trace, args.mem)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd D:/RhapsodiOS/vm && python -m unittest test_qemu_shot -v
```

Expected: `OK`, no previously-passing test regressed.

- [ ] **Step 5: Commit**

```bash
cd D:/RhapsodiOS && git add vm/qemu-shot.py vm/test_qemu_shot.py
git commit -m "vm: let qemu-shot.py set guest RAM with --mem"
```

---

## Task 2: Clamp physical memory to the kernel address space

The change that makes a >1GB machine boot. It is verifiable against the **stock, unmodified booter**, because the existing `extmem` path already reports ~2GB at `-m 2048` and already overflows to 0 at `-m 4096`.

The `pmap_map()` guard ships in the same task: a reviewer would take both or neither, and the guard is what catches the estimator drifting out of sync with the real sizers later.

**Files:**
- Modify: `src/kernel-7/machdep/i386/pmap.c:263`
- Modify: `src/kernel-7/machdep/i386/i386_init.c:92-94,433-468`
- Modify: `src/kernel-7/machdep/i386/unix_startup.c:232`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `vm_size_t mem_size_detected;` — raw detected size in bytes, before clamping
  - `vm_size_t mem_size_budget;` — the kernel linear window the clamp targeted
  - `boolean_t mem_size_clamped;` — TRUE when `mem_size != mem_size_detected`

  All three are globals in `i386_init.c`, declared `extern` in `unix_startup.c`. The budget is exported rather than recomputed at the reporting site because `unix_startup.c` imports `<mach/mach_types.h>` and `<vm/vm_kern.h>`, neither of which demonstrably reaches `mach/i386/vm_param.h` — so `VM_MAX_KERNEL_ADDRESS` may not be in scope there. Task 4 reads none of them; Task 5 changes only the value the budget takes.

- [ ] **Step 1: Capture the broken baseline**

`work/test.img` may be in any state from earlier work, so reset it to a clean copy of `golden.img` first — this run must use the **stock** kernel, so nothing is grafted.

```bash
cd D:/RhapsodiOS/vm && cmd //c reset-image.cmd && python qemu-shot.py work/test.img shots-t2-base-4g --at 45,90 --mem 4096 --keys "mach_kernel -v\n"
```

Expected: the run does **not** reach a login. If it gets as far as the memory report, `shots-t2-base-4g/serial.log` shows `physical memory = 0.00 megabytes.`

This is the failing test. Do not proceed until it is captured and confirmed broken.

- [ ] **Step 2: Add the pmap_map guard**

In `src/kernel-7/machdep/i386/pmap.c`, as the first statement inside the `while (start < end)` loop at line 263:

```c
    while (start < end) {
	if (virt >= VM_MAX_KERNEL_ADDRESS)
	    panic("pmap_map: kernel address space exhausted at virt 0x%x "
		  "(phys 0x%x, end 0x%x)", virt, start, end);

	pte = pmap_pt_entry(kernel_pmap, virt);
	if (pte == PT_ENTRY_NULL) {
	    pmap_kernel_pt_alloc(virt);
	    pte = pmap_pt_entry(kernel_pmap, virt);
	}
```

The check is at the top of the loop, before `virt` is used, so the final post-increment leaving `virt == VM_MAX_KERNEL_ADDRESS` is still a legal return for `*virt_end`.

Without this, overrunning the window walks `pmap_pd_entry()` off the end of the single kernel page-directory page and scribbles on the next allocation — a silent corruption that surfaces as an unrelated crash much later.

- [ ] **Step 3: Add the reporting globals**

In `src/kernel-7/machdep/i386/i386_init.c`, after the existing `extmem` declaration at line 94:

```c
/* parameters passed from bootstrap loader */
unsigned int cnvmem = 0;	/* must be in .data section */
unsigned int extmem = 0;	/* extended memory in KB */

/* memory sizing results, reported by unix_startup.c */
vm_size_t	mem_size_detected = 0;	/* before clamping */
vm_size_t	mem_size_budget = 0;	/* kernel linear window */
boolean_t	mem_size_clamped = FALSE;
```

- [ ] **Step 4: Add the conversion, estimator and fit test**

In `src/kernel-7/machdep/i386/i386_init.c`, immediately before `size_memory()` at line 433:

```c
/*
 * Kernel virtual address consumed by the kmem reservations that
 * pmap_bootstrap() makes on top of the V == P direct map.  This must track:
 *
 *	kern/zalloc.c			zone_map_sizer()
 *	machdep/i386/unix_startup.c	buffer_map_sizer()
 *
 * plus the literal base size in machdep/i386/pmap.c's pmap_bootstrap().
 *
 * The real sizers cannot be called from here: they memoize their results
 * into bufpages/nbuf/niobuf, which startup_early() consumes later, so
 * calling them this early would corrupt the buffer cache configuration.
 * This estimate rounds up wherever it is inexact.
 */
#define EST_KMEM_BASE	(64 * 1024 * 1024)	/* pmap_bootstrap base size */
#define EST_ZONE_MIN	(12 * 1024 * 1024)	/* zone_map_size_min */
#define EST_ZONE_MAX	(128 * 1024 * 1024)	/* zone_map_size_max */
#define EST_MAXBSIZE	8192			/* bsd/sys/param.h MAXBSIZE */
#define EST_MAXPHYS	(64 * 1024)		/* bsd/i386/param.h MAXPHYS */
#define CLAMP_STEP	(16 * 1024 * 1024)
#define ADDR_CEILING	0xFFFFF000		/* page-aligned below 4GB */

static
vm_size_t
kmem_va_estimate(
    vm_size_t	memsz
)
{
    vm_size_t	zone, bufpages, nbuf, niobuf;

    zone = memsz / 8;
    if (zone < EST_ZONE_MIN)
	zone = EST_ZONE_MIN;
    else if (zone > EST_ZONE_MAX)
	zone = EST_ZONE_MAX;

    bufpages = (memsz / 50) / page_size;
    nbuf = (bufpages < 16 ? 16 : bufpages) + 64;

    niobuf = bufpages / (EST_MAXPHYS / page_size);
    if (niobuf > 1024)
	niobuf = 1024;
    if (niobuf < 32)
	niobuf = 32;

    return (EST_KMEM_BASE + zone
	    + (nbuf * EST_MAXBSIZE) + (niobuf * EST_MAXPHYS));
}

/*
 * Does this much physical memory, plus the kernel VA reserved above it,
 * fit the kernel's linear window?  The subtraction is on the budget side
 * so the sum can never wrap.
 */
static
boolean_t
kmem_va_fits(
    vm_size_t	memsz,
    vm_size_t	budget
)
{
    return (memsz <= budget && kmem_va_estimate(memsz) <= budget - memsz);
}

/*
 * Convert a KB count to bytes, saturating rather than wrapping.  A 4GB
 * machine reports 4194304 KB, which times 1024 is 0 in 32 bits.
 */
static
vm_offset_t
kb_to_bytes(
    unsigned int	kb
)
{
    if (kb > (ADDR_CEILING / 1024))
	return ((vm_offset_t) ADDR_CEILING);

    return ((vm_offset_t) kb * 1024);
}
```

`page_size` is set to `2 * I386_PGBYTES` at line 143, before `size_memory()` is called at line 153, so it is valid here.

- [ ] **Step 5: Rewrite size_memory()**

Replace `size_memory()` in `src/kernel-7/machdep/i386/i386_init.c` (lines 433-468) with:

```c
static
void
size_memory(void)
{
    KERNBOOTSTRUCT	*kernBootStruct = (KERNBOOTSTRUCT *)KERNSTRUCT_ADDR;
    vm_offset_t		end_of_image, end_of_memory;
    vm_size_t		budget;
    int			i;
#define KB(x)		((x)*1024)

    end_of_image = getlastaddr();

    for (i=0; i < kernBootStruct->numBootDrivers; i++)
        end_of_image += kernBootStruct->driverConfig[i].size;

    if (maxmem)
        end_of_memory = kb_to_bytes((unsigned int) maxmem);
    else
        end_of_memory = kb_to_bytes(extmem);

    mem_size_detected = end_of_memory;

    /*
     * Physical memory is mapped V == P starting at kernel VA 0, and
     * pmap_bootstrap() reserves further kernel VA directly above it.
     * Both have to fit the kernel's linear window, so give back whatever
     * does not.
     */
    budget = VM_MAX_KERNEL_ADDRESS - VM_MIN_KERNEL_ADDRESS;
    mem_size_budget = budget;

    if (!kmem_va_fits(end_of_memory, budget)) {
	/*
	 * Round down to a step boundary before stepping, so the clamped
	 * result depends only on the budget and not on how much memory
	 * happened to be detected.  Without this a saturated 0xFFFFF000
	 * lands 4KB below where a clean 2GB detection lands.
	 */
	end_of_memory &= ~(CLAMP_STEP - 1);

	while (!kmem_va_fits(end_of_memory, budget)) {
	    if (end_of_memory < CLAMP_STEP) {
		end_of_memory = 0;
		break;
	    }
	    end_of_memory -= CLAMP_STEP;
	}
    }

    mem_size_clamped = (end_of_memory != mem_size_detected);

    /*
     * This is the Mach notion of
     * how much physical memory the
     * machine contains.
     */

    mem_size = end_of_memory;

    first_addr0 = round_page(kernBootStruct->first_addr0);
    last_addr0 = trunc_page(KB(cnvmem));

    first_addr = round_page(end_of_image);
    last_addr = trunc_page(end_of_memory);
#undef	KB
}
```

The old comment claiming `mem_size` is "only used for informational purposes" is dropped because it was never true — `mem_size` feeds both `zone_map_sizer()` and `buffer_map_sizer()`, which is exactly why clamping it is the right lever.

- [ ] **Step 6: Report the clamp**

In `src/kernel-7/machdep/i386/unix_startup.c`, add the externs near the top with the other declarations:

```c
extern vm_size_t	mem_size_detected;
extern vm_size_t	mem_size_budget;
extern boolean_t	mem_size_clamped;
```

and extend the report at line 232:

```c
#define MEG	(1024*1024)
    printf("physical memory = %d.%d%d megabytes.\n",
	mem_size/MEG,
	((mem_size%MEG)*10)/MEG,
	((mem_size%(MEG/10))*100)/MEG);

    if (mem_size_clamped)
	printf("physical memory clamped from %d MB to %d MB "
	       "(kernel address space holds %d MB).\n",
	       mem_size_detected/MEG, mem_size/MEG, mem_size_budget/MEG);
```

The new line prints whole megabytes only. The existing fractional expression above it is unreliable — `((v % (MEG/10)) * 100) / MEG` renders an exact 1776MB as `1776.01` — but fixing that is not this change's business, so every check below reads the **integer** part.

- [ ] **Step 7: Build the kernel**

```bash
cd D:/RhapsodiOS/src/kernel-7 && rm -rf BUILD/RELEASE_I386 BUILD/config.RELEASE_I386 BUILD/config.RELEASE_I386.old conf/RELEASE_I386 conf/RELEASE_I386.old
cd D:/RhapsodiOS/src/kernel-7/conf && gnumake I386 OBJROOT=../BUILD SYMROOT=../BUILD
```

Expected: a fresh `src/kernel-7/BUILD/RELEASE_I386/mach_kernel`.

- [ ] **Step 8: Run the boot matrix**

```bash
cd D:/RhapsodiOS/vm && for M in 768 2048 4096; do python graft-kernel.py golden.img ../src/kernel-7/BUILD/RELEASE_I386/mach_kernel work/test.img && python qemu-shot.py work/test.img shots-t2-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
grep -h "physical memory" shots-t2-*/serial.log```

Expected — read the **integer** megabyte figure:

| `--mem` | `physical memory =` | clamp line |
| --- | --- | --- |
| 768 | 766–768 MB | absent |
| 2048 | **816** MB | present, `clamped from 2048 MB to 816 MB` |
| 4096 | **816** MB | present |

The 768 figure is a small range, not an exact value, because the stock booter still reports the E820 *sum* minus 1MB and the exact total depends on QEMU's map. Task 4 makes it exact.

The two clamped figures must be **exactly 816 and identical to each other** — that is what the round-down-before-stepping in Step 5 buys. If they differ by a few KB, the `end_of_memory &= ~(CLAMP_STEP - 1)` line is missing or misplaced.

Also required: all three runs reach a login, and no run panics with `pmap_map: kernel address space exhausted`.

- [ ] **Step 9: Commit**

```bash
cd D:/RhapsodiOS && git add src/kernel-7/machdep/i386/pmap.c src/kernel-7/machdep/i386/i386_init.c src/kernel-7/machdep/i386/unix_startup.c
git commit -m "kernel: clamp physical memory to the kernel address space

Also stop KB(extmem) wrapping to zero on a 4GB machine, and panic in
pmap_map rather than walking off the end of the kernel page directory."
```

---

## Task 3: Carry a physical memory map in kernBootStruct

Layout-only. Nothing writes or reads the new fields yet, so this task is gated by the compiler and the assertions rather than by a boot — Task 4 is what exercises it.

**Files:**
- Modify: `src/kernel-7/machdep/i386/kernBootStruct.h:179,201`
- Modify: `src/boot-2/i386/libsa/kernBootStruct.h:138,160`

**Interfaces:**
- Consumes: nothing
- Produces, identically in both copies:
  - `#define BOOT_MEMMAP_MAX 32`
  - `#define BOOT_MEM_RAM 1`
  - `typedef struct { unsigned int base; unsigned int end; unsigned int type; } boot_mem_range_t;`
  - `KERNBOOTSTRUCT.memMapCount` (`int`) and `KERNBOOTSTRUCT.memMap` (`boot_mem_range_t[BOOT_MEMMAP_MAX]`)

  Task 4's booter half writes these; its kernel half reads them.

- [ ] **Step 1: Confirm `_reserved` is unused**

```bash
cd D:/RhapsodiOS && grep -rn "_reserved" --include=*.c --include=*.m --include=*.h src/boot-2/i386 src/kernel-7/machdep/i386
```

Expected: only the two struct declarations, the dead `#if 0` one at `kernBootStruct.h:92`, and a `sizeof` print in `src/boot-2/i386/boot2/test.c`. Anything else reading or writing `_reserved` means the carve-out is unsafe — stop.

- [ ] **Step 2: Add the type and fields to the kernel copy**

In `src/kernel-7/machdep/i386/kernBootStruct.h`, in the **live** struct after the `#else` at line 99 — not the dead `#if 0` block — insert above `typedef struct { short version; ...` at line 179:

```c
/*
 * Physical memory ranges handed over by the booter, derived from the BIOS
 * INT 0x15 E820h map.  Clamped to 32 bits: the kernel cannot address memory
 * above 4GB, so the booter drops ranges lying wholly above it and clips any
 * range that crosses it.  "end" is exclusive.
 */
#define BOOT_MEMMAP_MAX	32
#define BOOT_MEM_RAM	1		/* E820 type 1: usable RAM */

typedef struct {
    unsigned int	base;
    unsigned int	end;		/* exclusive, <= 0xFFFFF000 */
    unsigned int	type;		/* raw E820 type */
} boot_mem_range_t;
```

Replace `char   _reserved[7500];` at line 201 with:

```c
    int			memMapCount;	/* 0 == no map, fall back to extmem */
    boot_mem_range_t	memMap[BOOT_MEMMAP_MAX];
    char   _reserved[7500 - 4 - (BOOT_MEMMAP_MAX * 12)];
```

Immediately after the closing `} KERNBOOTSTRUCT;` and before `#define KERNSTRUCT_ADDR`, add:

```c
/*
 * The booter and the kernel keep separate copies of this file and must agree
 * byte for byte.  KERNBOOTSTRUCT is also read by drivers at a fixed address,
 * so its total size must not change.  These fail to compile if either drifts.
 */
typedef char __kbs_range_size[(sizeof (boot_mem_range_t) == 12) ? 1 : -1];
typedef char __kbs_reserved_size[
	(sizeof (((KERNBOOTSTRUCT *)0)->_reserved) == 7112) ? 1 : -1];
```

`7112` is `7500 - 4 - 384`. With the 12-byte range assertion this pins the carved block at its original 7500 bytes, so `video`, `pciInfo`, `eisaSlotInfo` and `config` do not move.

- [ ] **Step 3: Mirror into the booter copy**

Apply the identical edits to `src/boot-2/i386/libsa/kernBootStruct.h`: the same type block above its struct at line 138, the same three replacement lines at its `char _reserved[7500];` on line 160, and the same two assertions after its `} KERNBOOTSTRUCT;`.

- [ ] **Step 4: Verify the two copies agree**

```bash
cd D:/RhapsodiOS && diff <(sed -n '/BOOT_MEMMAP_MAX/,/__kbs_reserved_size/p' src/boot-2/i386/libsa/kernBootStruct.h) <(sed -n '/BOOT_MEMMAP_MAX/,/__kbs_reserved_size/p' src/kernel-7/machdep/i386/kernBootStruct.h)
```

Expected: no output. Any difference here is the exact bug this task exists to prevent.

- [ ] **Step 5: Build the kernel to exercise the assertions**

```bash
cd D:/RhapsodiOS/src/kernel-7 && rm -rf BUILD/RELEASE_I386 BUILD/config.RELEASE_I386 BUILD/config.RELEASE_I386.old conf/RELEASE_I386 conf/RELEASE_I386.old
cd D:/RhapsodiOS/src/kernel-7/conf && gnumake I386 OBJROOT=../BUILD SYMROOT=../BUILD
```

Expected: a clean build. An error like `size of array __kbs_reserved_size is negative` means the arithmetic in Step 2 is wrong — recompute it rather than adjusting the assertion to match.

- [ ] **Step 6: Commit**

```bash
cd D:/RhapsodiOS && git add src/kernel-7/machdep/i386/kernBootStruct.h src/boot-2/i386/libsa/kernBootStruct.h
git commit -m "boot: reserve a physical memory map in kernBootStruct

Carved out of the unused _reserved block so the struct size and every
field after it are unchanged.  Compile-time assertions pin the layout."
```

---

## Task 4: Plumb the E820 map from booter to kernel

The booter and kernel halves ship together because neither is independently observable: a booter writing a field nothing reads, and a kernel reading a field nothing writes, both look like no-ops. Together they change the reported size, which is the evidence.

Three separate bugs in `getMemoryMap()` get fixed here. It returns the *sum* of RAM rather than a usable top; it relies on whatever `bb.es` a previous BIOS caller left behind; and it discards the map.

**Files:**
- Create: `vm/build-i386-boot.sh`
- Modify: `src/boot-2/i386/libsaio/saio_internal.h:25,43-51`
- Modify: `src/boot-2/i386/libsaio/biosfn.c:97-160`
- Modify: `src/boot-2/i386/boot2/sizememory.c:24-65`
- Modify: `src/kernel-7/machdep/i386/i386_init.c` (`size_memory()` selection, plus a new helper)

**Interfaces:**
- Consumes: `boot_mem_range_t`, `BOOT_MEMMAP_MAX`, `BOOT_MEM_RAM`, `KERNBOOTSTRUCT.memMap`, `KERNBOOTSTRUCT.memMapCount` (Task 3); `kb_to_bytes()` and the clamp (Task 2)
- Produces: `unsigned long getMemoryMap(boot_mem_range_t *map, int maxEntries, int *numEntries)` — **returns a byte address**, the top of the contiguous RAM run starting at 1MB, or 0 if the BIOS has no E820 map or reports no RAM adjoining 1MB. This is a contract change: it previously returned a KB total. `sizememory()` is its only caller.

- [ ] **Step 1: Write the booter build script**

Create `vm/build-i386-boot.sh`, following `build-i386-kernel-ahci.sh` conventions:

```sh
#!/bin/sh
# Build and stage the i386 booter (/usr/standalone/i386/boot).

set -eu

script_path=$0
case "$script_path" in
    */*) script_dir_part=${script_path%/*} ;;
    *) script_dir_part=. ;;
esac
script_dir=`CDPATH= cd "$script_dir_part" && pwd -P`
repo_root=`CDPATH= cd "$script_dir/.." && pwd -P`
source_root=${BOOT_SOURCE_ROOT:-$repo_root}
install_dir=${BOOT_INSTALL_DIR:-$repo_root/vm/install}
make_cmd=${BOOT_MAKE:-gnumake}

die()
{
    echo "build-i386-boot: $*" >&2
    exit 1
}

source_root=`CDPATH= cd "$source_root" && pwd -P` ||
    die "source root not found: $source_root"
expected_install=$source_root/vm/install
[ "$install_dir" = "$expected_install" ] ||
    die "staging directory must be exactly $expected_install"

boot_dir=$source_root/src/boot-2/i386
[ -d "$boot_dir" ] || die "missing source directory: $boot_dir"
command -v "$make_cmd" >/dev/null 2>&1 ||
    die "required target build tool not found: $make_cmd"

obj=$source_root/src/boot-2/obj/i386
sym=$source_root/src/boot-2/sym/i386
dst=$source_root/src/boot-2/dst/i386

echo "== i386 booter =="
rm -rf "$obj" "$sym" "$dst"
(cd "$boot_dir" && "$make_cmd" install \
    "OBJROOT=$obj" "SYMROOT=$sym" "DSTROOT=$dst" "SRCROOT=$obj/src") ||
    die "booter build failed"

boot=$dst/usr/standalone/i386/boot
[ -f "$boot" ] || die "missing build output: $boot"

size=`wc -c < "$boot"`
echo "booter size: $size bytes"
# boot2/Makefile already fails the build above MAXBOOTSIZE (45056).  This is
# the tighter, image-specific limit: /usr/standalone/i386/boot on golden.img
# has 39936 bytes of writable fragments and rhap_inject's put path never
# allocates, so a larger booter cannot be injected.
if [ "$size" -gt 39936 ]; then
    die "booter is $size bytes; /usr/standalone/i386/boot holds at most 39936"
fi

mkdir -p "$install_dir"
cp -p "$boot" "$install_dir/boot"
echo "staged $install_dir/boot"
```

- [ ] **Step 2: Prove the script on unmodified source**

Run it before changing any C, so a failure is attributable to the script rather than to the code changes:

```bash
cd D:/RhapsodiOS && sh vm/build-i386-boot.sh
```

Expected: `== i386 booter ==`, a `booter size:` line near 39616, and a `staged` line. Record that size — it is the budget for the rest of this task, with only 320 bytes of headroom.

- [ ] **Step 3: Change the getMemoryMap declaration**

`saio_internal.h` imports only `saio_types.h`, so `boot_mem_range_t` is not in scope there. Add the boot-struct import next to it at line 25:

```c
#define SAIO_INTERNAL 1
#import "saio_types.h"
#import <kernBootStruct.h>
```

Then replace the `e820_entry_t` block and the `getMemoryMap` declaration at lines 43-51 with:

```c
/* Raw entry returned by the INT 0x15, E820h BIOS call */
typedef struct {
    unsigned long long base;
    unsigned long long length;
    unsigned long type;
    unsigned long acpi_extended;
} __attribute__((packed)) e820_entry_t;

/*
 * Fills "map" with up to maxEntries ranges clamped to 32 bits and returns
 * the top of the contiguous RAM run starting at 1MB, or 0 if the BIOS has
 * no E820 map.  See biosfn.c.
 */
extern unsigned long getMemoryMap(boot_mem_range_t *map, int maxEntries,
				  int *numEntries);
extern unsigned long getExtendedMemoryE801(void);
```

`e820_entry_t` stays — it is still the shape the BIOS writes. Only the handoff type changes.

- [ ] **Step 4: Rewrite getMemoryMap**

In `src/boot-2/i386/libsaio/biosfn.c`, replace `getMemoryMap()` (lines 102-160), keeping the `E820_*` defines above it:

```c
#define E820_ADDR_MAX	0xFFFFF000	/* page-aligned below 4GB */

/*
 * Read the BIOS INT 0x15, E820h memory map.
 *
 * Fills "map" with up to maxEntries ranges clamped to 32 bits, and returns
 * the top of the contiguous run of usable RAM starting at 1MB - the highest
 * address the kernel can map V == P without crossing a hole.  Returns 0 if
 * the BIOS has no E820 map or reports no RAM adjoining 1MB.
 *
 * The run is anchored at 1MB rather than 0 deliberately: E820 always reports
 * the legacy hole at 0x9FC00-0x100000, so a run anchored at 0 would stop at
 * 640K.  Conventional memory is handled by memsize(0).
 */
unsigned long getMemoryMap(boot_mem_range_t *map, int maxEntries, int *numEntries)
{
    unsigned long	continuation = 0;
    unsigned long	top;
    int			count = 0;
    int			changed, i;
    e820_entry_t	entry;

    if (!map || !numEntries || maxEntries < 1) {
        return 0;
    }

    *numEntries = 0;

    do {
	bzero((char *)&entry, sizeof(entry));

        bb.intno = 0x15;
        bb.eax.rx = 0xE820;
        bb.edx.rx = 0x534D4150;  /* 'SMAP' signature */
        bb.ebx.rx = continuation;
        bb.ecx.rx = sizeof(entry);

	/*
	 * The BIOS writes the entry through ES:DI.  boot2 runs its stack just
	 * below 64K (STACK_ADDR), so &entry is reachable with ES == 0 - but
	 * "bb" is a shared global that vbe.c and get_diskinfo() leave their
	 * own segment in, so ES is set here rather than inherited.
	 */
	bb.es = 0;
        bb.edi.rr = ((unsigned)&entry & 0xffff);

        bios(&bb);

        if (bb.flags.cf || bb.eax.rx != 0x534D4150) {
            break;
        }

	if (count < maxEntries && entry.length > 0) {
	    unsigned long long ebase = entry.base;
	    unsigned long long eend  = entry.base + entry.length;

	    /* Drop ranges wholly above 4GB; clip any that cross it. */
	    if (ebase < 0x100000000ULL) {
		if (eend > (unsigned long long)E820_ADDR_MAX)
		    eend = (unsigned long long)E820_ADDR_MAX;

		if (eend > ebase) {
		    map[count].base = (unsigned int)ebase;
		    map[count].end  = (unsigned int)eend;
		    map[count].type = (unsigned int)entry.type;
		    count++;
		}
	    }
        }

        continuation = bb.ebx.rx;

    } while (continuation != 0 && count < maxEntries);

    *numEntries = count;

    /*
     * Top of the contiguous RAM run starting at 1MB.  E820 entries are not
     * guaranteed sorted, so repeat until stable rather than making one pass.
     */
    top = EXTENDED_ADDR;
    changed = 1;
    while (changed) {
	changed = 0;
	for (i = 0; i < count; i++) {
	    if (map[i].type != BOOT_MEM_RAM)
		continue;
	    if (map[i].base <= top && map[i].end > top) {
		top = map[i].end;
		changed = 1;
	    }
	}
    }

    return (top > EXTENDED_ADDR) ? top : 0;
}
```

`biosfn.c` already imports `memory.h` (for `EXTENDED_ADDR`, `0x100000`) and `kernBootStruct.h` at lines 31-32, so no new includes are needed here.

- [ ] **Step 5: Update sizememory()**

In `src/boot-2/i386/boot2/sizememory.c`, extend the imports at line 24:

```c
#import <mach/i386/vm_types.h>
#import "libsaio.h"
#import <kernBootStruct.h>
#import <memory.h>
```

Update the comment block so it describes what the function now does:

```c
/*
 * Memory detection using BIOS INT 0x15 with multiple fallback methods:
 * 1. E820h - full memory map; also handed to the kernel in kernBootStruct
 * 2. E801h - extended memory size (up to 4GB)
 * 3. INT 88h - legacy extended memory size (up to 64MB)
 *
 * Returns extended memory size in KB (memory above 1MB)
 */
```

and replace the E820 block at lines 51-65 with:

```c
    /* Method 1: E820h memory map, which also hands the kernel the map */
    {
    	unsigned long top;
    	int numEntries = 0;

    	top = getMemoryMap(kernBootStruct->memMap, BOOT_MEMMAP_MAX,
    			   &numEntries);
    	kernBootStruct->memMapCount = numEntries;

    	if (top > EXTENDED_ADDR) {
    	    extmem_kb = (top - EXTENDED_ADDR) / 1024;
    	    printf("%dK", (int)(extmem_kb + 1024));
    	    return extmem_kb;
    	}
    }
```

`getKernBootStruct()` bzeros the whole struct before calling `sizememory()`, so `memMapCount` is already 0 on the fallback paths.

- [ ] **Step 6: Consume the map in the kernel**

In `src/kernel-7/machdep/i386/i386_init.c`, after `kb_to_bytes()`:

```c
#define EXT_BASE	0x100000	/* extended memory starts at 1MB */

/*
 * Top of the contiguous run of usable RAM starting at 1MB, from the map the
 * booter handed over.  Mirrors the scan in libsaio/biosfn.c's getMemoryMap:
 * entries are not guaranteed sorted, so repeat until stable.  Returns
 * EXT_BASE when no RAM adjoins 1MB.
 */
static
vm_offset_t
memmap_contiguous_top(
    KERNBOOTSTRUCT *	kbp
)
{
    vm_offset_t		top = EXT_BASE;
    int			changed = 1;
    int			i;

    while (changed) {
	changed = 0;
	for (i = 0; i < kbp->memMapCount; i++) {
	    if (kbp->memMap[i].type != BOOT_MEM_RAM)
		continue;
	    if (kbp->memMap[i].base <= top && kbp->memMap[i].end > top) {
		top = kbp->memMap[i].end;
		changed = 1;
	    }
	}
    }

    return (top);
}
```

Then in `size_memory()`, replace the selection written in Task 2 Step 5:

```c
    if (maxmem)
        end_of_memory = kb_to_bytes((unsigned int) maxmem);
    else
        end_of_memory = kb_to_bytes(extmem);
```

with:

```c
    if (maxmem) {
        end_of_memory = kb_to_bytes((unsigned int) maxmem);
    }
    else {
	vm_offset_t	top = 0;

	if (kernBootStruct->memMapCount > 0)
	    top = memmap_contiguous_top(kernBootStruct);

	if (top > EXT_BASE)
	    end_of_memory = top;
	else
	    end_of_memory = kb_to_bytes(extmem);
    }
```

`memmap_contiguous_top()` is called once and its result reused, so a full map is scanned only once.

- [ ] **Step 7: Build both**

```bash
cd D:/RhapsodiOS && sh vm/build-i386-boot.sh
cd D:/RhapsodiOS/src/kernel-7 && rm -rf BUILD/RELEASE_I386 BUILD/config.RELEASE_I386 BUILD/config.RELEASE_I386.old conf/RELEASE_I386 conf/RELEASE_I386.old
cd D:/RhapsodiOS/src/kernel-7/conf && gnumake I386 OBJROOT=../BUILD SYMROOT=../BUILD
```

Expected: the booter stages and stays under 39936 bytes; the kernel builds clean. If the booter now exceeds 39936 the script fails with a clear message — shrink the code rather than switching to a graft, because grafting the booter leaves the image unbootable after any `fsck`.

- [ ] **Step 8: Run the Phase 1 exit matrix**

```bash
cd D:/RhapsodiOS/vm && for M in 768 2048 4096; do python graft-kernel.py golden.img ../src/kernel-7/BUILD/RELEASE_I386/mach_kernel work/test.img && MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img put /usr/standalone/i386/boot install/boot && python qemu-shot.py work/test.img shots-t4-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
grep -h "Sizing memory\|physical memory" shots-t4-*/serial.log
```

Expected — the Phase 1 exit criteria:

| `--mem` | `Sizing memory...` | `physical memory =` | clamp line |
| --- | --- | --- | --- |
| 768 | `786432K` | **768** MB | absent |
| 2048 | `2097152K` | **816** MB | present |
| 4096 | contiguous top below the PCI hole, **not** a 4GB sum | **816** MB | present |

The 768 figure is exact now where Task 2 could only give a range, because the kernel takes the contiguous top directly instead of the sum minus 1MB. `786432K` is 768MB expressed as KB above 1MB, plus the 1MB the print adds back.

At `-m 4096` the `Sizing memory...` value must be the contiguous top below QEMU's PCI hole (roughly 3.5GB in KB), not ~4GB. A ~4GB value means the scan is still summing.

All three runs reach a login, and no run panics with `pmap_map: kernel address space exhausted`.

This step is the first to exercise the `bb.es` fix. If E820 was previously returning garbage, the `Sizing memory...` value will change noticeably from Task 2's runs — that is the signal to read, not a regression.

- [ ] **Step 9: Commit**

Two commits, because the booter and the kernel are separate subsystems:

```bash
cd D:/RhapsodiOS && git add vm/build-i386-boot.sh src/boot-2/i386/libsaio/biosfn.c src/boot-2/i386/libsaio/saio_internal.h src/boot-2/i386/boot2/sizememory.c
git commit -m "boot: report the contiguous memory top instead of the E820 sum

Summing every E820 RAM range ignored the PCI hole below 4GB.  Also set
ES explicitly for the E820 call and pass the map to the kernel."
```

```bash
cd D:/RhapsodiOS && git add src/kernel-7/machdep/i386/i386_init.c
git commit -m "kernel: size memory from the booter's map when it is present

Falls back to extmem when the BIOS has no E820 map."
```

---

## Task 5: Move the split to 2G/2G

Three constants. The page-directory arithmetic works out with no structural change: `KERNEL_LINEAR_BASE / I386_SECTBYTES` becomes `0x80000000 / 4MB` = 512, so the kernel owns `pd[512..1023]` and `pmap_enable_pg()`'s double-map lands in `pd[0..511]` — adjacent, no overlap. Segment limits encode exactly: `page_limit(0x80000000)` is `0x7FFFF000`, a 20-bit field of `0x7FFFF` with page granularity.

The pre-flight gate that would normally open this task is already closed — see "Verified Before Writing This Plan". Step 1 re-runs it only because the image may have changed since.

**Files:**
- Modify: `src/kernel-7/mach/i386/vm_param.h:66,69`
- Modify: `src/kernel-7/bsd/i386/vmparam.h:46`

**Interfaces:**
- Consumes: the clamp from Task 2, which reads its budget from `VM_MAX_KERNEL_ADDRESS` and so retargets itself
- Produces: no new symbols. `KERNEL_LINEAR_BASE` follows `VM_MAX_ADDRESS` automatically via `machdep/i386/pmap.h:84`.

- [ ] **Step 1: Confirm no other hardcoded copy of the constants**

```bash
cd D:/RhapsodiOS && grep -rn "0xc0000000\|0xC0000000" --include=*.c --include=*.h --include=*.s src/kernel-7 | grep -v netinet | grep -v "/ppc/"
```

Expected: exactly two hits — `mach/i386/vm_param.h:66` and `bsd/i386/vmparam.h:46`. A third hit is a hardcoded duplicate that must move with them; add it to this task rather than leaving it behind.

- [ ] **Step 2: Move the constants**

`src/kernel-7/mach/i386/vm_param.h`, lines 65-69:

```c
#define VM_MIN_ADDRESS		((vm_offset_t) 0)
#define VM_MAX_ADDRESS		((vm_offset_t) 0x80000000)

#define VM_MIN_KERNEL_ADDRESS	((vm_offset_t) 0x00000000)
#define VM_MAX_KERNEL_ADDRESS	((vm_offset_t) 0x80000000)
```

`src/kernel-7/bsd/i386/vmparam.h`, line 46:

```c
#define	USRSTACK	0x80000000
```

`USRSTACK` is an independent hardcoded duplicate of `VM_MAX_ADDRESS` and must move with it. Everything else derives from these three and needs no edit: the GDT and LDT descriptors, `task.c`'s user map creation, `pcb.c`'s user stack top, and `genassym.c`'s assembly exports of `_VM_MIN_KERNEL_ADDRESS` and `_KERNEL_LINEAR_BASE`.

- [ ] **Step 3: Build the kernel**

```bash
cd D:/RhapsodiOS/src/kernel-7 && rm -rf BUILD/RELEASE_I386 BUILD/config.RELEASE_I386 BUILD/config.RELEASE_I386.old conf/RELEASE_I386 conf/RELEASE_I386.old
cd D:/RhapsodiOS/src/kernel-7/conf && gnumake I386 OBJROOT=../BUILD SYMROOT=../BUILD
```

Expected: a clean build.

- [ ] **Step 4: Run the Phase 2 exit matrix**

`1536` replaces `2048` here because it is the size that proves the win — it clamped to 816MB in Task 4 and must now report in full.

```bash
cd D:/RhapsodiOS/vm && for M in 768 1536 4096; do python graft-kernel.py golden.img ../src/kernel-7/BUILD/RELEASE_I386/mach_kernel work/test.img && MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img put /usr/standalone/i386/boot install/boot && python qemu-shot.py work/test.img shots-t5-$M --at 45,90 --mem $M --keys "mach_kernel -v\n"; done
grep -h "physical memory" shots-t5-*/serial.log
```

Expected — the Phase 2 exit criteria:

| `--mem` | `physical memory =` | clamp line | vs Task 4 |
| --- | --- | --- | --- |
| 768 | **768** MB | absent | unchanged |
| 1536 | **1536** MB | absent | **was 816 MB** |
| 4096 | **1776** MB | present | was 816 MB |

Every run must still reach a login. This is where a prebound-address collision would surface — as userland failing to start while the kernel itself boots fine. The pre-flight in Step 1 and the "Verified" section say that should not happen; if it does, the split is not viable and this task reverts while Tasks 1-4 stand.

- [ ] **Step 5: Commit**

```bash
cd D:/RhapsodiOS && git add src/kernel-7/mach/i386/vm_param.h src/kernel-7/bsd/i386/vmparam.h
git commit -m "kernel: split the address space 2G/2G instead of 3G/1G

Doubles the kernel linear window, raising usable RAM from 816MB to
1776MB.  Costs each process 1GB of virtual address space."
```

---

## What changed from the previous plan

`docs/superpowers/plans/2026-07-25-i386-large-memory.md` covered the same spec in 10 tasks and 1722 lines. The differences, and why:

**A correctness bug is fixed.** Its clamp loop stepped down by 16MB from the raw detected size without first rounding to a step boundary. A saturated `0xFFFFF000` detection therefore landed on `0x32FFF000` while a clean 2GB detection landed on `0x33000000` — 4096 bytes apart, rendering as `815.90` versus `816.00`. The plan then asserted that every clamped run reports the *same* value, so executing it would have produced a false failure at `-m 4096`. Task 2 Step 5 rounds down before stepping, which is what makes the clamped figures in this plan exact.

**Its Phase 2 pre-flight was incomplete, and is now closed anyway.** It scanned dylib `__TEXT` addresses but never `LC_UNIXTHREAD` esp, which is the field that would actually fault under a shrunken address space. Both are now checked and recorded in "Verified Before Writing This Plan", so an entire task disappears.

**Its tooling assumptions went stale.** It depended eight times on `vm/rebuild-i386-kernel.sh`, which was never tracked in git and no longer exists. It also proposed a `vm/graft.py` that `vm/graft-kernel.py` now provides, and its `vm/scan-dylib-addrs.py` used a `rhap_image` API that does not exist (`RhapImage`, `cat`, string `dtype`).

**It asserted fractional megabytes.** The existing `printf` renders an exact 1776MB as `1776.01`, because `((v % (MEG/10)) * 100) / MEG` is not a correct fractional expression. Every check here reads the integer part, and the new clamp line prints whole megabytes only.

**It was disproportionate.** 14 full QEMU boots under TCG and 8 guest kernel rebuilds, plus a Python module and 20 unit tests modelling roughly 20 lines of integer arithmetic. This plan has 10 boots across 5 working tasks, and the arithmetic is pinned by the expected-value table in "Verified Before Writing This Plan" instead of by a parallel implementation that would need maintaining forever.

**Task boundaries moved** to match what is separately observable. The `pmap_map` guard merged into the clamp task because a reviewer would take both or neither. The booter and kernel map halves merged because neither changes behaviour alone.
