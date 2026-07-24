# i386 CPU Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permanently restore real CPUID-based CPU detection in the i386 kernel by fixing the fat-slice subtype grading bug that made it unbootable, removing the two `#if 0` blocks and the forced `CPU_SUBTYPE_586` override.

**Architecture:** Two independent changes. First, `machdep/i386/kern_machdep.c` gets a rewritten `grade_cpu_subtype()` / `check_cpu_subtype()` pair whose preference order is driven by the *binary's* subtype rather than the host's, mirroring `NXFindBestFatArch()` in cctools. Second, `machdep/i386/i386_init.c` gets working CPUID detection whose result is split two ways: a conservative clamped value for `machine_slot[0].cpu_subtype` (which prebuilt Rhapsody DR2 `dyld` consumes) and a full descriptive string for `cpu_model` (which only `hw.model` reads).

**Tech Stack:** C (K&R / gnu89 dialect, Apple GCC 2.7.x era), i386 inline assembly in GNU `asm volatile` form, Mach 2.5 / 4.4BSD kernel. Host-side test harness built with `clang -std=gnu89` and GNU make.

## Global Constraints

- Target dialect is pre-C89 K&R as used by the surrounding files. Existing functions use old-style parameter declarations; match them. Do not add prototypes to files that lack them.
- `panic()` is NOT usable from `machine_configure()`. It takes `panic_lock` (initialized later by `panic_init()`), dereferences `current_thread()->pcb`, and calls `boot()`. Reject unsupported CPUs with `asm volatile("hlt")` in a loop, matching the existing `is486_or_higher()` rejection.
- Never publish a `cpu_subtype` above `CPU_SUBTYPE_PENTPRO` = `CPU_SUBTYPE_INTEL(6, 1)` = 22. Prebuilt DR2 `dyld` and `libsys` cannot be patched and their arch tables stop at `CPU_SUBTYPE_PENTII_M5`.
- `cpu_model` is `char cpu_model[65]`. The CPUID brand string is 48 bytes plus NUL. Do not overflow it.
- Floating-point emulation is not built in this tree (`fp_emul` is `optional` in `conf/files.i386` with no config enabling it), so `FP_EMUL` is 0 and a CPU without an FPU leaves `cpu_config.fpu_type` at `FPU_NONE`.
- `ebx` is reserved by the PIC ABI. Any `cpuid` inline asm must save and restore it around the instruction rather than naming it as a clobber or an operand.
- Commit messages: short, human-readable, subsystem prefix (`kernel: `), one to two lines, describing behavior not files. No trailing metadata, no `Co-Authored-By`.
- All VM boot testing runs against a **temporary copy** of the disk image so it cannot collide with another debugging session.

## Reference

Approved spec: [`docs/superpowers/specs/2026-07-24-i386-cpu-detection-design.md`](../specs/2026-07-24-i386-cpu-detection-design.md)

## Background: the bug being fixed

`grade_cpu_subtype()` switches on the *host* subtype. Host values outside the
explicit `386`/`486`/`486SX`/`586` cases reach a `default:` arm that returns
`15 - host_family - binary_family` — a missing-parens slip for
`15 - (host_family - binary_family)`.

On a family-15 host every grade goes negative. `fatfile_getarch()` in
`kern/mach_fat.c` starts at `best_grade = 0` and only accepts
`grade > best_grade`, so it selects nothing and returns `LOAD_BADARCH`. Every fat
binary fails to exec, `init` included.

Family 15 is the base CPUID family of the Pentium 4 and of every AMD processor
from K8 through Zen, which report base family `0xF` with the real family in the
extended field. Task 1's harness reproduces this from the real source file.

## File Structure

| File | Responsibility |
|---|---|
| `tools/cpusubtype-test/harness.c` | **Create.** Host-side assertions over the real grading table. |
| `tools/cpusubtype-test/Makefile` | **Create.** Build and run the harness. |
| `tools/cpusubtype-test/README.md` | **Create.** Why the tool exists and what the stubs are for. |
| `tools/cpusubtype-test/stub/mach/machine/vm_types.h` | **Create.** Stands in for the real header, which `#error`s off `__i386__`. |
| `tools/cpusubtype-test/stub/mach/machine/boolean.h` | **Create.** Same. |
| `src/kernel-7/machdep/i386/kern_machdep.c` | **Modify.** Replace both grading functions. |
| `src/kernel-7/machdep/i386/i386_init.c` | **Modify.** CPUID plumbing, clamp, `cpu_model`, FPU gate. |

The harness lives under `tools/` because that directory is already the tracked
home for host-side development tools with their own tests (`tools/binrecon`).
Committing it rather than leaving it in a scratch directory is deliberate: this
bug sat latent for 27 years, and the grading table is pure integer arithmetic
that a host can check in under a second.

---

### Task 1: Fix fat-slice subtype grading

The grading logic depends on nothing but integers and the `CPU_SUBTYPE_*` macros,
so it can be compiled and asserted on the development host. This task is a real
red-green cycle.

**Files:**
- Create: `tools/cpusubtype-test/harness.c`
- Create: `tools/cpusubtype-test/Makefile`
- Create: `tools/cpusubtype-test/README.md`
- Create: `tools/cpusubtype-test/stub/mach/machine/vm_types.h`
- Create: `tools/cpusubtype-test/stub/mach/machine/boolean.h`
- Modify: `src/kernel-7/machdep/i386/kern_machdep.c:45-173` (everything after the
  license header and HISTORY block)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `int grade_cpu_subtype(cpu_subtype_t)` returning 0 for unacceptable
  and 1–6 for acceptable, higher being preferred; `int check_cpu_subtype(cpu_subtype_t)`
  returning non-zero when acceptable. Callers are `kern/mach_fat.c:150` and
  `kern/mach_loader.c:219`; neither changes.

- [ ] **Step 1: Create the stub headers**

The real `mach/machine/vm_types.h` and `mach/machine/boolean.h` dispatch on
`__i386__` / `__ppc__` and `#error` on anything else, so they cannot be included
on a modern development host. These two stubs supply only the typedefs the
grading code needs. Everything else — including the `CPU_SUBTYPE_*` macros
actually under test — comes from the real kernel tree.

`tools/cpusubtype-test/stub/mach/machine/vm_types.h`:

```c
/*
 * Host-side stand-in for <mach/machine/vm_types.h>, which dispatches on
 * __i386__ and #errors on a modern development host.  Only the typedefs
 * mach/machine.h needs are provided.
 */
#ifndef _STUB_MACH_MACHINE_VM_TYPES_H_
#define _STUB_MACH_MACHINE_VM_TYPES_H_

typedef int		integer_t;
typedef unsigned int	natural_t;
typedef unsigned int	vm_offset_t;
typedef unsigned int	vm_size_t;

#endif /* _STUB_MACH_MACHINE_VM_TYPES_H_ */
```

`tools/cpusubtype-test/stub/mach/machine/boolean.h`:

```c
/*
 * Host-side stand-in for <mach/machine/boolean.h>.  See vm_types.h.
 */
#ifndef _STUB_MACH_MACHINE_BOOLEAN_H_
#define _STUB_MACH_MACHINE_BOOLEAN_H_

typedef int	boolean_t;

#endif /* _STUB_MACH_MACHINE_BOOLEAN_H_ */
```

- [ ] **Step 2: Create the harness**

`tools/cpusubtype-test/harness.c`. This `#include`s the real kernel source file
so it tests shipping code, not a copy.

```c
/*
 * Host-side regression test for i386 fat-slice subtype grading.
 *
 * Compiles the real machdep/i386/kern_machdep.c and asserts the grading
 * table.  grade_cpu_subtype() is pure integer arithmetic over the
 * CPU_SUBTYPE_* macros, so it needs no target hardware to verify.
 */
#include <stdio.h>
#include <machdep/i386/kern_machdep.c>

struct machine_slot machine_slot[1];

static int failures, checks;

static void
expect(const char *host, const char *slice, int got, int want)
{
	checks++;
	if (got != want) {
		printf("FAIL  host=%-9s slice=%-11s got %2d  want %2d\n",
		    host, slice, got, want);
		failures++;
	}
}

/* check_cpu_subtype() must never disagree with grade_cpu_subtype(). */
static void
expect_consistent(const char *host, const char *slice, cpu_subtype_t st)
{
	checks++;
	if ((check_cpu_subtype(st) != 0) != (grade_cpu_subtype(st) != 0)) {
		printf("FAIL  host=%-9s slice=%-11s check=%d grade=%d disagree\n",
		    host, slice, check_cpu_subtype(st), grade_cpu_subtype(st));
		failures++;
	}
}

#define HOST(name, st)	(host = (name), machine_slot[0].cpu_subtype = (st))
#define G(slice, st, want)	do {				\
		expect(host, slice, grade_cpu_subtype(st), want);\
		expect_consistent(host, slice, st);		\
	} while (0)

int
main(void)
{
	const char *host;

	/*
	 * The bug this whole change exists for: AMD K8 through Zen and the
	 * Pentium 4 all report base CPUID family 0xf.  Every grade must be
	 * positive, because fatfile_getarch() starts at best_grade = 0.
	 */
	HOST("family15", CPU_SUBTYPE_INTEL(15, 0));
	G("i386_ALL", CPU_SUBTYPE_I386_ALL, 3);
	G("486",      CPU_SUBTYPE_486,      4);
	G("586",      CPU_SUBTYPE_586,      5);
	G("486SX",    CPU_SUBTYPE_486SX,    2);

	/* Clamp ceiling: what family 6 and above actually reports. */
	HOST("PENTPRO", CPU_SUBTYPE_PENTPRO);
	G("PENTPRO",   CPU_SUBTYPE_PENTPRO,   6);	/* exact match wins */
	G("586",       CPU_SUBTYPE_586,       5);
	G("486",       CPU_SUBTYPE_486,       4);
	G("i386_ALL",  CPU_SUBTYPE_I386_ALL,  3);
	G("486SX",     CPU_SUBTYPE_486SX,     2);
	G("PENTII_M3", CPU_SUBTYPE_PENTII_M3, 1);	/* same family, other model */

	HOST("586", CPU_SUBTYPE_586);
	G("586",      CPU_SUBTYPE_586,      6);		/* exact beats rank 5 */
	G("486",      CPU_SUBTYPE_486,      4);
	G("i386_ALL", CPU_SUBTYPE_I386_ALL, 3);
	G("486SX",    CPU_SUBTYPE_486SX,    2);
	G("PENTPRO",  CPU_SUBTYPE_PENTPRO,  0);		/* newer family */

	HOST("486", CPU_SUBTYPE_486);
	G("486",      CPU_SUBTYPE_486,      6);
	G("i386_ALL", CPU_SUBTYPE_I386_ALL, 3);
	G("486SX",    CPU_SUBTYPE_486SX,    2);
	G("586",      CPU_SUBTYPE_586,      0);		/* newer family */
	G("PENTPRO",  CPU_SUBTYPE_PENTPRO,  0);		/* newer family */

	printf("\n%s  (%d check%s, %d failure%s)\n",
	    failures ? "FAILED" : "PASSED",
	    checks, checks == 1 ? "" : "s",
	    failures, failures == 1 ? "" : "s");
	return failures != 0;
}
```

- [ ] **Step 3: Create the Makefile**

`tools/cpusubtype-test/Makefile`. `-DKERNEL` is required because
`mach/machine.h` guards the `machine_slot[]` extern behind it. `-w` suppresses
warnings from 1990s K&R code that a modern compiler dislikes but compiles fine.

```make
# Host-side regression test for i386 fat-slice subtype grading.
# See README.md.

KERNEL	= ../../src/kernel-7
CFLAGS	= -std=gnu89 -w -DKERNEL -I stub -I $(KERNEL)

all: run

harness: harness.c
	$(CC) $(CFLAGS) -o $@ $<

run: harness
	./harness

clean:
	rm -f harness

.PHONY: all run clean
```

- [ ] **Step 4: Create the README**

`tools/cpusubtype-test/README.md`:

```markdown
# cpusubtype-test

Host-side regression test for i386 fat-slice subtype grading in
`src/kernel-7/machdep/i386/kern_machdep.c`.

    make

`grade_cpu_subtype()` and `check_cpu_subtype()` decide which slice of a fat
Mach-O the kernel will exec. They are pure integer arithmetic over the
`CPU_SUBTYPE_*` macros in `mach/machine.h`, so they can be verified on the
development host with no target hardware.

`harness.c` `#include`s the real kernel source file rather than a copy, so what
is tested is what ships.

`stub/` holds stand-ins for `mach/machine/vm_types.h` and
`mach/machine/boolean.h`. The real versions dispatch on `__i386__` / `__ppc__`
and `#error` on anything else. The stubs supply only the typedefs
`mach/machine.h` needs; the macros under test come from the real tree.

## Why this exists

The original `grade_cpu_subtype()` computed
`15 - host_family - binary_family`, a missing-parens slip for
`15 - (host_family - binary_family)`. On a host in family 15 — the base CPUID
family of the Pentium 4 and of every AMD processor from K8 through Zen — every
grade went negative. `fatfile_getarch()` starts at `best_grade = 0` and only
accepts `grade > best_grade`, so it selected nothing and returned
`LOAD_BADARCH`, and no binary could exec. Apple shipped the code only on
family 4/5/6 parts, so it stayed latent from 1999.
```

- [ ] **Step 5: Run the harness to verify it fails**

```bash
cd tools/cpusubtype-test && make
```

Expected: build succeeds, then 15 failures out of 40 checks and a non-zero exit.
The first four lines must be:

```
FAIL  host=family15  slice=i386_ALL    got -3  want  3
FAIL  host=family15  slice=486         got -4  want  4
FAIL  host=family15  slice=586         got -5  want  5
FAIL  host=family15  slice=486SX       got  0  want  2
```

Those negative grades are the bug. Do not proceed until you have seen them.

- [ ] **Step 6: Rewrite the grading functions**

In `src/kernel-7/machdep/i386/kern_machdep.c`, leave lines 1–44 — the Apple
license header, the NeXT copyright, and the HISTORY block — completely
untouched. Replace everything from line 45 to the end of the file with:

```c
/*
 * Routine: grade_cpu_subtype()
 *
 * Function:
 *	Return a relative preference for cpu_subtypes in fat executable files.
 *	The higher the grade, the higher the preference.
 *	A grade of 0 means not acceptable.
 *
 * This code should match the CPU_TYPE_I386 case of NXFindBestFatArch() in
 * arch.c in the cctools project.  After an exact match, the order is 586,
 * 486, i386_ALL, 486SX, then any other Intel subtype.  A slice built for a
 * newer family than we are is never acceptable.
 *
 * Note this deliberately does not switch on ms->cpu_subtype the way the
 * original did.  That switch fell through to an arithmetic default case
 * returning 15 - family(host) - family(slice), which goes negative for hosts
 * in family 12 and above -- including every AMD from K8 on, whose base CPUID
 * family is 0xf.  fatfile_getarch() starts at best_grade = 0 and only accepts
 * grade > best_grade, so on those machines no slice was ever selected and
 * nothing could exec.
 */

int
grade_cpu_subtype (cpu_subtype)
	cpu_subtype_t cpu_subtype;
{
	struct machine_slot *ms = &machine_slot[cpu_number()];

	if (cpu_subtype == ms->cpu_subtype)
		return 6;

	if (CPU_SUBTYPE_INTEL_FAMILY(cpu_subtype) >
	    CPU_SUBTYPE_INTEL_FAMILY(ms->cpu_subtype))
		return 0;

	switch (cpu_subtype) {
	    case CPU_SUBTYPE_586:		/* == CPU_SUBTYPE_PENT */
		return 5;
	    case CPU_SUBTYPE_486:
		return 4;
	    case CPU_SUBTYPE_I386_ALL:		/* == CPU_SUBTYPE_386 */
		return 3;
	    case CPU_SUBTYPE_486SX:
		return 2;
	}

	/*
	 * A model-specific subtype in our own family or older, e.g. a
	 * PENTII_M3 slice on a Pentium Pro.  Acceptable but least preferred,
	 * matching the lowest-family/lowest-model tier in cctools.
	 */
	return 1;
}

int
check_cpu_subtype (cpu_subtype)
	cpu_subtype_t cpu_subtype;
{
	/*
	 * Derived from grade_cpu_subtype() rather than duplicating its
	 * table, so the two cannot disagree.  A slice that grade accepts
	 * but check rejects would be chosen by fatfile_getarch() and then
	 * refused by load_machfile().
	 */
	return (grade_cpu_subtype(cpu_subtype) != 0);
}
```

Note that `CPU_SUBTYPE_586`, `CPU_SUBTYPE_PENT` and `CPU_SUBTYPE_INTEL(5, 0)`
are all the value 5, and `CPU_SUBTYPE_I386_ALL` and `CPU_SUBTYPE_386` are both
3. Each value appears exactly once as a case label; adding the aliases as
separate labels is a duplicate-case compile error.

- [ ] **Step 7: Run the harness to verify it passes**

```bash
cd tools/cpusubtype-test && make
```

Expected: `PASSED  (40 checks, 0 failures)` and exit 0.

- [ ] **Step 8: Commit**

```bash
git add tools/cpusubtype-test src/kernel-7/machdep/i386/kern_machdep.c
git commit -m "kernel: fix i386 fat slice grading rejecting every binary on AMD

grade_cpu_subtype() returned negative grades for hosts in family 12 and up, so
fatfile_getarch() selected no slice and nothing could exec."
```

---

### Task 2: Restore working CPUID plumbing

Adds the CPUID machinery to `i386_init.c` and fixes the EFLAGS handling, while
leaving `machine_configure()`'s forced override in place. The kernel keeps
booting exactly as it does today, so this task can be reviewed and rejected on
its own without a boot risk.

There is no host-side test for this task: it executes the `cpuid` instruction
and manipulates EFLAGS, neither of which can be exercised off-target. Its gate
is that the kernel compiles. Behavior is verified in Task 3.

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c:227-330` (replace
  `is486_or_higher()`, the `cpuid_t` struct, `cpuid()`, and `get_cpuid()`)

**Interfaces:**
- Consumes: `eflags()` and `set_eflags()` from `machdep/i386/cpu_inline.h`;
  `static int subtype` at `i386_init.c:59`, set by the `subtype=` boot argument
  via the `kernargs` table at `i386_init.c:68`.
- Produces:
  - `struct cpu_ident { int family; int model; char vendor[13]; char brand[49]; }`
  - `static void cpu_identify(struct cpu_ident *id)` — fills it; `family` is 0
    when CPUID is unavailable, `vendor[0]` and `brand[0]` are `'\0'` when the
    respective string could not be read.
  - `static boolean_t is486_or_higher(void)` — unchanged signature.

  Task 3 calls `cpu_identify()` and reads all four fields.

- [ ] **Step 1: Replace `is486_or_higher()`**

At `i386_init.c:227-252`, replace the whole function. The existing version
returns `FALSE` without restoring EFLAGS, leaving `EFL_AC` set:

```c
static inline
boolean_t
is486_or_higher(void)
{
    unsigned int	efl, efl_saved;

    /* Save original EFLAGS */
    efl_saved = eflags();

    /* Try to set AC flag (386 cannot, 486 and up can) */
    set_eflags(efl_saved | EFL_AC);

    /* Read back to see whether the flag stuck */
    efl = eflags();

    /* Restore original EFLAGS unconditionally */
    set_eflags(efl_saved);

    return ((efl & EFL_AC) != 0);
}
```

- [ ] **Step 2: Replace the CPUID block**

At `i386_init.c:254-330`, delete all of the following and replace with the code
below:

- the `/* This stuff belongs elsewhere ... confidentiality of P5 information */`
  comment — it documents the `cpuid_t` struct being removed, so it goes with it
- `typedef struct _cpuid { ... } cpuid_t;`
- `static cpuid_t cpuid(void)`
- `#define EFL_ID 0x200000`
- `static cpuid_t get_cpuid(void)`

```c
#define EFL_ID		0x200000	/* CPUID present if this bit toggles */

/*
 * Execute CPUID for the given leaf, returning eax, ebx, ecx and edx in
 * regs[0] through regs[3].
 *
 * ebx is reserved by the PIC ABI, so it is saved and restored around the
 * instruction and the results are stored through a pointer.  Naming ebx as
 * an operand or a clobber is what makes the compiler reload it at the wrong
 * moment.  eax is both read and written, hence the matching "0" constraint.
 */
static
void
cpuid(
    unsigned int	leaf,
    unsigned int	*regs
)
{
    unsigned int	discard;

    asm volatile(
	"pushl	%%ebx\n\t"
	"cpuid\n\t"
	"movl	%%eax,0(%%edi)\n\t"
	"movl	%%ebx,4(%%edi)\n\t"
	"movl	%%ecx,8(%%edi)\n\t"
	"movl	%%edx,12(%%edi)\n\t"
	"popl	%%ebx"
	    : "=a" (discard)
	    : "0" (leaf), "D" (regs)
	    : "ecx", "edx", "memory");
}

/*
 * CPUID is present if the ID bit in EFLAGS can be toggled.  Test by flipping
 * it rather than by setting it: setting proves nothing if it is already set.
 */
static
boolean_t
cpuid_present(void)
{
    unsigned int	efl_saved, efl;

    efl_saved = eflags();

    set_eflags(efl_saved ^ EFL_ID);
    efl = eflags();

    set_eflags(efl_saved);

    return (((efl ^ efl_saved) & EFL_ID) != 0);
}

struct cpu_ident {
    int		family;		/* effective family, 0 if CPUID unavailable */
    int		model;		/* effective model */
    char	vendor[13];	/* empty if CPUID unavailable */
    char	brand[49];	/* empty if the extended leaves are absent */
};

static
void
cpu_identify(
    struct cpu_ident	*id
)
{
    unsigned int	regs[4];
    unsigned int	max_basic, max_ext;
    int			base_family, base_model;

    id->family = 0;
    id->model = 0;
    id->vendor[0] = '\0';
    id->brand[0] = '\0';

    if (subtype != 0) {
	/*
	 * Boot argument override, for testing and as a recovery lever:
	 * "subtype=5" reports a Pentium.
	 */
	id->family = CPU_SUBTYPE_INTEL_FAMILY(subtype);
	id->model = CPU_SUBTYPE_INTEL_MODEL(subtype);

	return;
    }

    if (!cpuid_present())
	return;

    cpuid(0, regs);
    max_basic = regs[0];

    bcopy((char *)&regs[1], &id->vendor[0], 4);		/* ebx */
    bcopy((char *)&regs[3], &id->vendor[4], 4);		/* edx */
    bcopy((char *)&regs[2], &id->vendor[8], 4);		/* ecx */
    id->vendor[12] = '\0';

    if (max_basic >= 1) {
	cpuid(1, regs);

	base_family = (regs[0] >> 8) & 0xf;
	base_model = (regs[0] >> 4) & 0xf;

	id->family = base_family;
	id->model = base_model;

	/* Extended family applies only when the base family is 0xf. */
	if (base_family == 0xf)
	    id->family += (regs[0] >> 20) & 0xff;

	/* Extended model applies when the base family is 0xf or 0x6. */
	if (base_family == 0xf || base_family == 0x6)
	    id->model += ((regs[0] >> 16) & 0xf) << 4;
    }

    /*
     * Some processors return the maximum basic leaf here instead of an
     * extended leaf number, so a value below 0x80000004 means the brand
     * string leaves are simply not there.
     */
    cpuid(0x80000000, regs);
    max_ext = regs[0];

    if (max_ext >= 0x80000004) {
	cpuid(0x80000002, regs);
	bcopy((char *)regs, &id->brand[0], 16);
	cpuid(0x80000003, regs);
	bcopy((char *)regs, &id->brand[16], 16);
	cpuid(0x80000004, regs);
	bcopy((char *)regs, &id->brand[32], 16);
	id->brand[48] = '\0';
    }
}
```

`bcopy`, `strcpy`, `strlen` and `sprintf` are used without declarations
elsewhere in this file and tree — `strcpy` at the current line 356, `sprintf` in
the block Task 3 removes. Old-style implicit declaration is the established
pattern here; do not add includes for them.

- [ ] **Step 3: Build the kernel**

On the Rhapsody guest, with the source tree synced to `/build/source`:

```bash
darwin-buildpackage --dir --target all /build/source/kernel-7 /build/repo /build/built
```

Expected: compiles to completion with no errors. `cpu_identify()` and
`cpuid_present()` are not called yet, so expect "defined but not used" warnings
for them — that is correct at this point and resolves in Task 3.

Do not boot this kernel. `machine_configure()` still forces the override, so
behavior is unchanged from today; the point of this step is only that the new
code compiles under the target's 1990s GCC, which is stricter about inline asm
constraints than any modern compiler.

- [ ] **Step 4: Commit**

```bash
git add src/kernel-7/machdep/i386/i386_init.c
git commit -m "kernel: add working i386 CPUID plumbing and fix EFLAGS handling

Replaces the struct-returning cpuid() with a four-register wrapper, toggles the
ID flag to detect CPUID, and restores EFLAGS on every path."
```

---

### Task 3: Report the real CPU

Rewrites `machine_configure()` to use `cpu_identify()`, removes both `#if 0`
blocks and the forced override, and publishes a clamped subtype plus a
descriptive model string. This is the task that changes boot behavior.

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c` — the whole of
  `machine_configure()` (currently lines 335-426 before Task 2's edits shift them)

**Interfaces:**
- Consumes: `cpu_identify()` and `struct cpu_ident` from Task 2;
  `grade_cpu_subtype()` from Task 1 indirectly, via `kern/mach_fat.c`.
- Produces: `machine_slot[0].cpu_subtype` (never above `CPU_SUBTYPE_PENTPRO`),
  `cpu_model[]` and `machine[]`. Read by `kern/host.c:151`,
  `kern/processor.c:461`, and `bsd/kern/kern_sysctl.c:398` as `hw.model`.

- [ ] **Step 1: Replace `machine_configure()`**

Replace everything from the `char cpu_model[65];` declaration through the closing
brace of `machine_configure()` — currently `i386_init.c:332-426`, before Task 2's
edits shift the numbers. That range deliberately **includes** the `cpu_model` and
`machine` declarations, which sit just above the function; the block below
restates them, so replacing only the function body would leave them declared
twice.

Both `#if 0` blocks and the `raynorpat: force a 586/Pentium CPU type` override go
away in this replacement.

```c
char cpu_model[65];
char machine[65];

static
void
machine_configure(void)
{
    struct cpu_ident	id;
    char		*cp;
    int			len;

    while (!is486_or_higher())
	asm volatile("hlt");

    enable_cache();

    fp_configure();

    machine_slot[0].is_cpu = TRUE;
    machine_slot[0].running = TRUE;

    /* we are running on an i386-based architecture */
    machine_slot[0].cpu_type = CPU_TYPE_I386;
    (void) strcpy(machine, "i386");

    cpu_identify(&id);

    /*
     * Report a subtype the Rhapsody userland understands.  dyld and libsys
     * are prebuilt and their arch tables stop at PENTII_M5, so everything
     * from family 6 up is reported as a Pentium Pro.  The real identity of
     * the processor goes into cpu_model, which is only ever read as text
     * through the hw.model sysctl and so cannot break a loader.
     *
     * Anything below family 5 is reported as a 486: real hardware never
     * gets here, since is486_or_higher() halts above, but the subtype=
     * boot argument can assert any family.
     */
    if (id.family >= 6)
	machine_slot[0].cpu_subtype = CPU_SUBTYPE_PENTPRO;
    else if (id.family == 5)
	machine_slot[0].cpu_subtype = CPU_SUBTYPE_586;
    else
	machine_slot[0].cpu_subtype = CPU_SUBTYPE_486;

    if (id.brand[0] != '\0') {
	/* Intel pads the brand string on the left and blank-fills it. */
	cp = id.brand;
	while (*cp == ' ')
	    cp++;

	(void) strcpy(cpu_model, cp);

	len = strlen(cpu_model);
	while (len > 0 && cpu_model[len - 1] == ' ')
	    cpu_model[--len] = '\0';
    }
    else if (id.vendor[0] != '\0') {
	(void) sprintf(cpu_model, "%s family %d model %d",
	    id.vendor, id.family, id.model);
    }
    else {
	(void) sprintf(cpu_model, "i86 family %d model %d",
	    id.family, id.model);
    }
}
```

- [ ] **Step 2: Build the kernel**

```bash
darwin-buildpackage --dir --target all /build/source/kernel-7 /build/repo /build/built
```

Expected: compiles with no errors, and the "defined but not used" warnings from
Task 2 are gone.

- [ ] **Step 3: Prepare a throwaway disk image**

Never boot a test kernel against the working image. On the VM host:

```bash
cp rhapsody.vmdk rhapsody-cputest.vmdk
```

Point the VM at `rhapsody-cputest.vmdk` for every boot in this task. Install the
newly built kernel onto that image.

- [ ] **Step 4: Boot and verify the default path**

Boot the test image and let it come up with no boot arguments.

Expected: the system reaches multi-user and a login prompt. **This is the real
test of the whole change.** It is the first time prebuilt DR2 `dyld` sees a
family-6 host subtype, and the first time an AMD host gets a non-negative slice
grade.

If it does not boot, go to Step 7 before changing any code — that isolates
whether the failure is the clamp ceiling or something else.

Then, logged in:

```bash
sysctl hw.model
```

Expected: the processor's marketing name, e.g. `hw.model: AMD Ryzen 9 7950X
16-Core Processor`. Under QEMU or VMware it will be whatever brand string the
hypervisor advertises. It must not be the literal string `586`, which is what
today's kernel reports.

```bash
sysctl hw.machine
uname -m
```

Expected: both report `i386`.

- [ ] **Step 5: Verify the prebuilt userland accepts the subtype**

```bash
hostinfo
arch
```

Expected: both run and exit cleanly. These route `machine_slot[0].cpu_subtype`
out through `host_info()` into DR2's arch tables, so they are the direct check
that reporting `PENTPRO` did not break the unpatchable userland.

- [ ] **Step 6: Verify both fat and thin binaries exec**

Reaching a login prompt in Step 4 already proves a good deal: the shell, `init`
and every binary in the boot path exec'd. To name the slice explicitly:

```bash
lipo -info /usr/bin/lipo /bin/ls /usr/bin/hostinfo
```

Expected: for each binary, either `Non-fat file: ... is architecture: i386` or
`Architectures in the fat file: ... are: ...` including `i386`. That the command
printed anything at all means `lipo` itself exec'd.

If `lipo` is not installed on the test image, skip this step rather than
installing it — Steps 4 and 5 already exercised the exec path, and a
`LOAD_BADARCH` would have shown up there as a failure to run, not as wrong
output.

- [ ] **Step 7: Verify the clamp rows and the recovery lever**

The `subtype=` boot argument reaches `kernBootStruct->bootString` and is parsed
as `name=value` by `getargs()`, so every row of the clamp table is reachable
without rebuilding. At the `boot: ` prompt, append the argument to the boot line.

For each row below, boot with the argument, confirm the system reaches
multi-user, then run **both**:

```bash
sysctl hw.model
arch
```

| boot argument | expected `hw.model` | reported subtype | exercises |
|---|---|---|---|
| `subtype=4` | `i86 family 4 model 0` | `CPU_SUBTYPE_486` | 486 clamp row |
| `subtype=5` | `i86 family 5 model 0` | `CPU_SUBTYPE_586` | 586 clamp row, **recovery lever** |
| `subtype=6` | `i86 family 6 model 0` | `CPU_SUBTYPE_PENTPRO` | PENTPRO clamp row |
| `subtype=15` | `i86 family 15 model 0` | `CPU_SUBTYPE_PENTPRO` | PENTPRO row via family 15 |

`hw.model` confirms `cpu_identify()` took the override path; `arch` is what
actually confirms the clamp, since it reads `machine_slot[0].cpu_subtype` back
out through `host_info()` and DR2's arch table.

`arch` must print a *different* name for the 486 and 586 rows than for the two
PENTPRO rows, and the same name for `subtype=6` and `subtype=15` — that identical
result across families 6 and 15 is the clamp doing its job. Do not assert exact
spellings: they come from DR2's table, not ours, and `CPU_SUBTYPE_586` and
`CPU_SUBTYPE_PENT` are the same value 5 with two names, so which one prints
depends on that table's row order.

All four rows take the override path in `cpu_identify()`, which reads no CPUID,
so `hw.model` uses the `i86 family N model M` fallback. That is expected, and it
also confirms the fallback string works.

`subtype=5` is the escape hatch: it reproduces today's known-good reported
subtype. If Step 4 failed and `subtype=5` boots, the clamp ceiling is the
problem and the fix is to change `CPU_SUBTYPE_PENTPRO` to `CPU_SUBTYPE_586` in
Step 1's code. Report that back rather than deciding unilaterally.

- [ ] **Step 8: Commit**

```bash
git add src/kernel-7/machdep/i386/i386_init.c
git commit -m "kernel: report the real i386 CPU instead of a hardcoded 586

Drops the if 0'd CPUID path and the forced subtype, clamping the published
subtype at PENTPRO for the prebuilt userland and putting the CPUID brand string
in hw.model."
```

---

### Task 4: Halt on a CPU with no FPU

Floating-point emulation is not built, so a CPU without an FPU currently limps:
`fp_noextension()` throws `EXC_EMULATION` at each process as it reaches its
first floating-point instruction. Fail at boot instead.

Kept separate and last, so that Task 3's boot is already confirmed good before
adding a new halt path — a mistake here bricks the boot.

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c` — `machine_configure()`, right
  after the `fp_configure()` call

**Interfaces:**
- Consumes: `cpu_config.fpu_type` and `FPU_HDW` from `machdep/i386/configure.h`,
  set by `fp_configure()` in `machdep/i386/fp_support.c`.
- Produces: nothing. Terminal path.

- [ ] **Step 1: Add the FPU gate**

In `machine_configure()`, immediately after `fp_configure();` and before
`machine_slot[0].is_cpu = TRUE;`, insert:

```c
    /*
     * Floating point emulation is not built, so a CPU without an FPU cannot
     * run anything: fp_noextension() would throw EXC_EMULATION at every
     * process as it reached its first floating point instruction.  Stop here
     * instead.
     *
     * This is a halt rather than a panic() because panic() cannot run this
     * early -- it takes panic_lock, which panic_init() has not initialized,
     * dereferences current_thread()->pcb, and calls boot().  The rejection of
     * pre-486 CPUs above halts for the same reason.
     */
    while (cpu_config.fpu_type != FPU_HDW)
	asm volatile("hlt");
```

- [ ] **Step 2: Build the kernel**

```bash
darwin-buildpackage --dir --target all /build/source/kernel-7 /build/repo /build/built
```

Expected: compiles with no errors.

- [ ] **Step 3: Verify the gate does not fire on a working CPU**

Boot the throwaway image from Task 3 Step 3 with no boot arguments.

Expected: reaches multi-user exactly as in Task 3 Step 4. Any hang at boot means
the gate is misfiring on a CPU that does have an FPU — `fp_configure()` sets
`FPU_HDW` at `fp_support.c:128`, so check that the gate is placed after the
call, not before.

- [ ] **Step 4: Verify the gate fires when it should**

Boot with the `-f` flag, which sets `RB_NOFP` and forces `fp_configure()` down
its no-FPU path at `fp_support.c:107`:

```
boot: mach_kernel -f
```

Expected: the machine halts during early boot and never reaches a login prompt.
That is the gate working. `-f` existed to exercise the emulator, which is gone,
so it is now a deliberate way to trigger this path — and the only way to test it
without 486SX hardware.

Reboot without `-f` to confirm the system still comes up.

- [ ] **Step 5: Commit**

```bash
git add src/kernel-7/machdep/i386/i386_init.c
git commit -m "kernel: halt at boot on an i386 CPU with no hardware FPU

Floating point emulation is no longer built, so every process would otherwise
die on its first floating point instruction."
```

---

## Post-implementation

Run the host-side harness once more from a clean tree to confirm nothing in
Tasks 2–4 disturbed the grading table:

```bash
cd tools/cpusubtype-test && make clean && make
```

Expected: `PASSED  (40 checks, 0 failures)`.

Then confirm the two markers this whole plan exists to remove are gone:

```bash
grep -n "if 0" src/kernel-7/machdep/i386/i386_init.c
grep -n "force a 586" src/kernel-7/machdep/i386/i386_init.c
```

Expected: no output from either.
