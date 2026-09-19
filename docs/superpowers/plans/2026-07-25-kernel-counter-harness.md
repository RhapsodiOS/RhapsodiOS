# Kernel Counter Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a kernel counter harness to `src/kernel-7`, capture a committed baseline, then land only the optimizations a counter can confirm.

**Architecture:** A flat counter struct in `kern/kcounters.c`, read out as text through the existing `CTL_MACHDEP` sysctl node by a new `kcstat` tool. Instrumentation goes in at exactly the sites later tasks change. A baseline is captured and committed before any optimization commit; four of the six optimizations are gated on what that baseline shows and may be dropped.

**Tech Stack:** K&R C (gcc 2.7.2-era, `cc-791`), NeXT `pb_makefiles` for userland tools, `doconf`-driven kernel config, QEMU/TCG guest.

Design spec: [`docs/superpowers/specs/2026-07-25-kernel-counter-harness-design.md`](../specs/2026-07-25-kernel-counter-harness-design.md)

## Global Constraints

- **K&R style function definitions** in kernel C — parameters declared on separate lines, matching surrounding code. Do not convert existing code to ANSI prototypes.
- **No `snprintf`** in this kernel. `sprintf` exists but is unbounded; the formatter must bound its own writes explicitly.
- **Counters are compiled unconditionally** — not behind `MACH_COUNTERS`, `DEBUG`, or `DIAGNOSTIC`. Release-build numbers are the point.
- **Do not modify `bsd/sys/sysctl.h`.** It is an exported header; shipping a changed copy that installed guest binaries were not built against is the hazard being avoided. MIB sub-ids live in `kern/kcounters.h`, and `kcstat` carries matching literals with a comment.
- **Commit messages** start with the subsystem: `kernel: `, `kalloc: `, `zalloc: `, `pmap: `, `system_cmds: `. One to two lines. No metadata, no trailers, no `Co-Authored-By`.
- **Measurements run in single-user mode.** Three runs, median reported.
- **Task 6 (baseline) must be committed before Tasks 7–12.** A baseline from a tree that already contains an optimization is not a baseline.
- **Tasks 7, 9, 10, 12 are gated.** If the stated baseline condition is not met, mark the task dropped in this plan with a one-line reason and move on. Dropping a gated task is a success, not a failure.

## Verification model

This kernel has no unit test framework, and there is no way to add one that runs in-kernel. The test cycle for every task is therefore:

1. **Build:** `make kernels` from `src/kernel-7` in the guest, or `make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD` for a single arch.
2. **Boot:** install the kernel and boot the QEMU guest.
3. **Observe:** `kcstat` output, or a static check on generated assembly.

Changing `conf/files` or `conf/files.i386` makes `doconf` re-run automatically — the build-directory `Makefile` depends on them (`conf/Makefile:352`).

**Use a throwaway disk image for every boot test.** Another agent may be debugging a different boot concurrently.

## File Structure

**Create:**

| Path | Responsibility |
|---|---|
| `src/kernel-7/kern/kcounters.h` | Counter struct, `KC_INC`/`KC_ADD`, MIB sub-ids, buffer size |
| `src/kernel-7/kern/kcounters.c` | Counter storage, bounded text formatter, reset |
| `src/Commands/system_cmds/kcstat.tproj/` | `kcstat` tool (`kcstat.c`, `Makefile`, `PB.project`, preamble, postamble) |
| `tools/kperf/vfs-alloc.sh` | Allocator/VFS workload plus checksum integrity check |
| `tools/kperf/fork-cow.c` | fork/exec plus mmap write-fault workload |
| `tools/kperf/fork-cow.sh` | Driver for the above |
| `tools/kperf/README.md` | How to run a measurement |
| `docs/kernel/perf-baseline.md` | Committed counter dumps, appended per task |

**Modify:**

| Path | Change |
|---|---|
| `src/kernel-7/conf/files` | Register `kern/kcounters.c` |
| `src/kernel-7/machdep/i386/i386_init.c:688-703` | Implement `cpu_sysctl` |
| `src/kernel-7/machdep/ppc/machdep.c` | Add `cpu_sysctl` (currently missing tree-wide) |
| `src/kernel-7/machdep/i386/pmap.c:172-190` | TLB counters (T3), then threshold (T10) |
| `src/kernel-7/kern/kalloc.c` | kalloc counters (T4), lookup table (T8), page zone (T9) |
| `src/kernel-7/kern/zalloc.c` | Zone counters (T5), reclaim (T11), `doing_alloc` (T12) |
| `src/kernel-7/conf/MASTER.i386:82`, `MASTER.ppc:82` | Frame pointers (T7, gated) |
| `src/Commands/system_cmds/Makefile:19-27` | Add `kcstat.tproj` to `TOOLS` |

---

## Task 1: Counter core

Storage and formatter, no call sites and no readout yet. Deliverable: a kernel that still builds and boots with the new file compiled in.

**Files:**
- Create: `src/kernel-7/kern/kcounters.h`
- Create: `src/kernel-7/kern/kcounters.c`
- Modify: `src/kernel-7/conf/files` (after line 434, `kern/counters.c`)
- Modify: `src/kernel-7/kern/kalloc.c:119` (compile-time size assertion only)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct kcounters` with the exact field names listed below, and `extern struct kcounters kc;`
  - `#define KC_INC(f) (kc.f++)` and `#define KC_ADD(f, n) (kc.f += (n))`
  - `int kcounters_format(char *buf, int len)` — writes NUL-terminated `name value\n` lines, returns bytes written excluding the NUL, never writes past `buf + len - 1`
  - `void kcounters_reset(void)`
  - `#define KC_NKSIZE 16`, `#define KCOUNTERS_BUFSIZE 2048`
  - `#define CPU_KCOUNTERS 1`, `#define CPU_KCOUNTERS_RESET 2`

- [ ] **Step 1: Create the header**

Create `src/kernel-7/kern/kcounters.h`:

```c
/*
 * Kernel hot-path counters.
 *
 * Compiled unconditionally, not behind MACH_COUNTERS: the whole point is to
 * get numbers out of a release build.  An unconditional increment is free
 * relative to the work already being done at every one of these sites.
 *
 * Each counter exists to confirm or refute one specific change.  Do not add
 * counters here speculatively -- that is how instrumentation becomes clutter.
 */

#ifndef	_KERN_KCOUNTERS_H_
#define	_KERN_KCOUNTERS_H_

/*
 * Must match NKSIZE in kern/kalloc.c.  kalloc.c asserts this at compile time.
 */
#define	KC_NKSIZE		16

#define	KCOUNTERS_BUFSIZE	2048

/*
 * CTL_MACHDEP sub-ids for the readout.
 *
 * Deliberately NOT added to <sys/sysctl.h>: that header is exported, and
 * shipping a changed copy that installed guest binaries were not compiled
 * against is a real hazard.  kcstat(8) carries matching literals with a
 * comment pointing back here.
 */
#define	CPU_KCOUNTERS		1
#define	CPU_KCOUNTERS_RESET	2

struct kcounters {
	/* i386 TLB -- machdep/i386/pmap.c pmap_update_tlbs() */
	unsigned long	tlb_flush_full;
	unsigned long	tlb_flush_single;
	unsigned long	tlb_invlpg_pages;
	unsigned long	tlb_full_pages;

	/* kalloc -- kern/kalloc.c */
	unsigned long	kalloc_calls;
	unsigned long	kfree_calls;
	unsigned long	kalloc_oversize;
	unsigned long	kalloc_oversize_page;
	unsigned long	kalloc_zone_hits[KC_NKSIZE];

	/* zones -- kern/zalloc.c */
	unsigned long	zone_expansions;
	unsigned long	zone_space_failures;
	unsigned long	zone_reclaims;
	unsigned long	zone_reclaim_pages;
	unsigned long	zone_expand_races;
};

extern struct kcounters	kc;

#define	KC_INC(f)	(kc.f++)
#define	KC_ADD(f, n)	(kc.f += (n))

extern int	kcounters_format(char *buf, int len);
extern void	kcounters_reset(void);

#endif	/* _KERN_KCOUNTERS_H_ */
```

- [ ] **Step 2: Create the implementation**

Create `src/kernel-7/kern/kcounters.c`:

```c
/*
 * Kernel hot-path counters.  See kern/kcounters.h for why these exist.
 */

#include <kern/kcounters.h>

struct kcounters	kc;

/*
 * Append "name value\n" to p, writing nothing at or past end.
 *
 * Hand-rolled rather than sprintf: sprintf here is unbounded, and a buffer
 * overrun in the instrumentation of a stability change would be an ugly way
 * to learn that lesson.
 */
static char *
kc_append(p, end, name, val)
	char		*p;
	char		*end;
	char		*name;
	unsigned long	val;
{
	char	digits[24];
	int	n = 0;
	char	*s;

	for (s = name; *s != '\0'; s++) {
		if (p >= end)
			return (p);
		*p++ = *s;
	}

	if (p >= end)
		return (p);
	*p++ = ' ';

	if (val == 0)
		digits[n++] = '0';
	else
		while (val != 0 && n < sizeof(digits)) {
			digits[n++] = '0' + (int)(val % 10);
			val /= 10;
		}

	while (n > 0) {
		if (p >= end)
			return (p);
		*p++ = digits[--n];
	}

	if (p >= end)
		return (p);
	*p++ = '\n';

	return (p);
}

/*
 * Render the counters as "name value" lines.  Text rather than a struct so
 * that the reader needs no shared layout and adding a counter never breaks it.
 */
int
kcounters_format(buf, len)
	char	*buf;
	int	len;
{
	char	*p = buf;
	char	*end;
	char	name[32];
	int	i;

	if (len < 1)
		return (0);

	end = buf + len - 1;		/* leave room for the NUL */

#define	KC_EMIT(f)	p = kc_append(p, end, "f", kc.f)

	KC_EMIT(tlb_flush_full);
	KC_EMIT(tlb_flush_single);
	KC_EMIT(tlb_invlpg_pages);
	KC_EMIT(tlb_full_pages);

	KC_EMIT(kalloc_calls);
	KC_EMIT(kfree_calls);
	KC_EMIT(kalloc_oversize);
	KC_EMIT(kalloc_oversize_page);

	for (i = 0; i < KC_NKSIZE; i++) {
		sprintf(name, "kalloc_zone_hits.%d", i);
		p = kc_append(p, end, name, kc.kalloc_zone_hits[i]);
	}

	KC_EMIT(zone_expansions);
	KC_EMIT(zone_space_failures);
	KC_EMIT(zone_reclaims);
	KC_EMIT(zone_reclaim_pages);
	KC_EMIT(zone_expand_races);

#undef	KC_EMIT

	*p = '\0';
	return (p - buf);
}

void
kcounters_reset()
{
	bzero((char *)&kc, sizeof(kc));
}
```

**Note on `KC_EMIT`:** this kernel is built with `-traditional-cpp` (`conf/Makefile.i386:49`), where `"f"` inside a macro body stringizes the parameter — the pre-ANSI behaviour. If the build emits the literal string `f` for every counter name instead of the field name, replace the macro with `#f` and rebuild; if *that* fails, drop the macro and write 13 explicit `kc_append(p, end, "tlb_flush_full", kc.tlb_flush_full)` calls. Verify the actual names in Step 6 output before moving on — this is the one construct in this task most likely to misbehave.

- [ ] **Step 3: Register the file in the build**

In `src/kernel-7/conf/files`, immediately after line 434 (`kern/counters.c standard`), add:

```
kern/kcounters.c			standard
```

- [ ] **Step 4: Assert the size table agreement**

In `src/kernel-7/kern/kalloc.c`, the `NKSIZE` define is at line 119. Add the include near the other `kern/` includes at the top of the file (alongside `#include <kern/kalloc.h>`):

```c
#include <kern/kcounters.h>
```

Then immediately after the `#define NKSIZE 16` line, add:

```c
#if	NKSIZE != KC_NKSIZE
#error	"NKSIZE and KC_NKSIZE disagree -- see kern/kcounters.h"
#endif
```

- [ ] **Step 5: Build**

Run, from `src/kernel-7` in the guest:

```bash
make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: `doconf` re-runs because `conf/files` changed, `kcounters.o` is compiled, link succeeds. If `bzero` is reported implicitly declared, that is a warning in this era's gcc and is acceptable; the symbol resolves at link time.

- [ ] **Step 6: Boot the new kernel on a throwaway image**

Install the kernel to a **copy** of the guest disk image and boot it. Expected: boots to multi-user with no new panics or warnings. Nothing reads the counters yet — this step only proves the new object file is harmless.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/kern/kcounters.h src/kernel-7/kern/kcounters.c \
        src/kernel-7/conf/files src/kernel-7/kern/kalloc.c
git commit -m "kernel: add hot-path counter storage and text formatter"
```

---

## Task 2: Sysctl readout and `kcstat`

The readout and its reader are one deliverable — neither is testable without the other.

**Files:**
- Modify: `src/kernel-7/machdep/i386/i386_init.c:688-703`
- Modify: `src/kernel-7/machdep/ppc/machdep.c` (append at end of file)
- Create: `src/Commands/system_cmds/kcstat.tproj/kcstat.c`
- Create: `src/Commands/system_cmds/kcstat.tproj/Makefile`
- Create: `src/Commands/system_cmds/kcstat.tproj/PB.project`
- Create: `src/Commands/system_cmds/kcstat.tproj/Makefile.preamble`
- Create: `src/Commands/system_cmds/kcstat.tproj/Makefile.postamble`
- Modify: `src/Commands/system_cmds/Makefile:19-27`

**Interfaces:**
- Consumes: `kcounters_format`, `kcounters_reset`, `CPU_KCOUNTERS`, `CPU_KCOUNTERS_RESET`, `KCOUNTERS_BUFSIZE` from Task 1.
- Produces: `kcstat` at `/usr/bin/kcstat`; plain dump with no arguments, reset with `-z`.

- [ ] **Step 1: Replace the i386 `cpu_sysctl` stub**

In `src/kernel-7/machdep/i386/i386_init.c`, add to the includes near line 49:

```c
#include <sys/sysctl.h>
#include <kern/kcounters.h>
```

Then replace the whole function body at lines 688–703:

```c
/* i386 specific sysctl calls */
int
cpu_sysctl(name, namelen, oldp, oldlenp, newp, newlen, p)
	int *name;
	u_int namelen;
	void *oldp;
	size_t *oldlenp;
	void *newp;
	size_t newlen;
	struct proc *p;
{
	static char	kcbuf[KCOUNTERS_BUFSIZE];

	if (namelen != 1)
		return (ENOTDIR);

	switch (name[0]) {

	case CPU_KCOUNTERS:
		(void) kcounters_format(kcbuf, sizeof(kcbuf));
		return (sysctl_rdstring(oldp, oldlenp, newp, kcbuf));

	case CPU_KCOUNTERS_RESET:
		if (newp == NULL)
			return (EINVAL);
		kcounters_reset();
		*oldlenp = 0;
		return (0);

	default:
		return (EOPNOTSUPP);
	}
}
```

`kcbuf` is `static`, not automatic: 2 KB on a kernel stack of this vintage is not safe. Writes already require root — `__sysctl` calls `suser()` whenever `new != NULL` (`bsd/kern/kern_sysctl.c:172`).

If `#include <sys/sysctl.h>` drags in headers that will not compile in this machdep file, drop the include and declare the one function you need locally instead:

```c
extern int sysctl_rdstring();
```

- [ ] **Step 2: Add the missing ppc `cpu_sysctl`**

`cpu_sysctl` is declared `extern` at `bsd/kern/kern_sysctl.c:101` and defined only for i386 — there is no ppc definition anywhere in the tree. Append to `src/kernel-7/machdep/ppc/machdep.c`:

```c
#include <sys/errno.h>
#include <sys/sysctl.h>
#include <kern/kcounters.h>

/* ppc specific sysctl calls */
int
cpu_sysctl(name, namelen, oldp, oldlenp, newp, newlen, p)
	int *name;
	u_int namelen;
	void *oldp;
	size_t *oldlenp;
	void *newp;
	size_t newlen;
	struct proc *p;
{
	static char	kcbuf[KCOUNTERS_BUFSIZE];

	if (namelen != 1)
		return (ENOTDIR);

	switch (name[0]) {

	case CPU_KCOUNTERS:
		(void) kcounters_format(kcbuf, sizeof(kcbuf));
		return (sysctl_rdstring(oldp, oldlenp, newp, kcbuf));

	case CPU_KCOUNTERS_RESET:
		if (newp == NULL)
			return (EINVAL);
		kcounters_reset();
		*oldlenp = 0;
		return (0);

	default:
		return (EOPNOTSUPP);
	}
}
```

Identical body by design: `CTL_MACHDEP` must behave the same on both arches. The TLB counters simply stay zero on ppc, which already invalidates per-VA with `tlbie` and has no full-flush heuristic to measure.

If `sys/errno.h` or `sys/sysctl.h` is already included in this file, do not add it twice.

- [ ] **Step 3: Write the tool**

Create `src/Commands/system_cmds/kcstat.tproj/kcstat.c`:

```c
/*
 * kcstat -- print the kernel hot-path counters.
 *
 * Usage:
 *	kcstat		dump counters
 *	kcstat -z	reset counters to zero (requires root)
 *
 * The MIB sub-ids below are deliberately literals rather than a shared
 * header: src/kernel-7/kern/kcounters.h defines CPU_KCOUNTERS = 1 and
 * CPU_KCOUNTERS_RESET = 2, but it is a kernel header and the guest's
 * installed /usr/include does not carry it.  Keep these two in sync by hand.
 */

#include <sys/types.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define	CPU_KCOUNTERS		1	/* kern/kcounters.h */
#define	CPU_KCOUNTERS_RESET	2	/* kern/kcounters.h */

#define	KCBUFSIZE		2048

int
main(argc, argv)
	int	argc;
	char	**argv;
{
	int	mib[2];
	char	buf[KCBUFSIZE];
	size_t	len;
	int	zero = 0;

	mib[0] = CTL_MACHDEP;

	if (argc == 2 && strcmp(argv[1], "-z") == 0) {
		mib[1] = CPU_KCOUNTERS_RESET;
		len = 0;
		if (sysctl(mib, 2, NULL, &len, &zero, sizeof(zero)) < 0) {
			perror("kcstat: reset");
			exit(1);
		}
		exit(0);
	}

	if (argc != 1) {
		fprintf(stderr, "usage: kcstat [-z]\n");
		exit(2);
	}

	mib[1] = CPU_KCOUNTERS;
	len = sizeof(buf);
	if (sysctl(mib, 2, buf, &len, NULL, 0) < 0) {
		perror("kcstat");
		exit(1);
	}

	fputs(buf, stdout);
	exit(0);
}
```

- [ ] **Step 4: Create the project files**

Create `src/Commands/system_cmds/kcstat.tproj/Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = kcstat

PROJECTVERSION = 2.8
PROJECT_TYPE = Tool

CFILES = kcstat.c

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble


MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = tool.make
NEXTSTEP_INSTALLDIR = /usr/bin
LIBS = 
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)


NEXTSTEP_PB_CFLAGS = -DNeXT_MOD


NEXTSTEP_BUILD_OUTPUT_DIR = /tmp/$(USER)/BUILD

NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc
WINDOWS_OBJCPLUS_COMPILER = $(DEVDIR)/gcc
PDO_UNIX_OBJCPLUS_COMPILER = $(NEXTDEV_BIN)/gcc
NEXTSTEP_JAVA_COMPILER = /usr/bin/javac
WINDOWS_JAVA_COMPILER = $(JDKBINDIR)/javac.exe
PDO_UNIX_JAVA_COMPILER = $(NEXTDEV_BIN)/javac

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

Create `src/Commands/system_cmds/kcstat.tproj/PB.project`:

```
{
    DYNAMIC_CODE_GEN = YES; 
    FILESTABLE = {
        FRAMEWORKS = (); 
        OTHER_LINKED = (kcstat.c); 
        OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble); 
    }; 
    LANGUAGE = English; 
    LOCALIZABLE_FILES = {}; 
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles"; 
    NEXTSTEP_BUILDDIR = "/tmp/$(USER)/BUILD"; 
    NEXTSTEP_BUILDTOOL = /bin/gnumake; 
    NEXTSTEP_COMPILEROPTIONS = "-DNeXT_MOD"; 
    NEXTSTEP_INSTALLDIR = /usr/bin; 
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac; 
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc; 
    PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make; 
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac"; 
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc"; 
    PROJECTNAME = kcstat; 
    PROJECTTYPE = Tool; 
    PROJECTVERSION = 2.8; 
    WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make; 
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe"; 
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc"; 
}
```

For the two remaining files, copy the boilerplate templates verbatim — they are unmodified NeXT templates and contain nothing project-specific:

```bash
cd src/Commands/system_cmds
cp vm_stat.tproj/Makefile.preamble  kcstat.tproj/Makefile.preamble
cp vm_stat.tproj/Makefile.postamble kcstat.tproj/Makefile.postamble
```

- [ ] **Step 5: Register the tool**

In `src/Commands/system_cmds/Makefile`, the `TOOLS` assignment spans lines 19–27 and currently ends with `zprint.tproj`. Add `kcstat.tproj` to it — put it on the `iostat.tproj kgmon.tproj ktrace.tproj login.tproj` line so the continuation lines stay under 80 columns:

```make
TOOLS = ac.tproj accton.tproj arch.tproj at.tproj atrun.tproj\
        chkpasswd.tproj chpass.tproj dmesg.tproj fbalert.tproj\
        fbshow.tproj getty.tproj halt.tproj hostinfo.tproj init.tproj\
        iostat.tproj kcstat.tproj kgmon.tproj ktrace.tproj login.tproj\
        mach_init.tproj mach_swapon.tproj makekey.tproj mkfile.tproj\
        nvram.tproj passwd.tproj pwd_mkdb.tproj reboot.tproj\
        shutdown.tproj swapon.tproj sync.tproj sysctl.tproj top.tproj\
        update.tproj vipw.tproj zic.tproj zdump.tproj vm_stat.tproj\
        zprint.tproj
```

- [ ] **Step 6: Build kernel and tool**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

```bash
cd src/Commands/system_cmds/kcstat.tproj && make
```

Expected: both succeed.

- [ ] **Step 7: Verify the readout end to end**

Install the kernel to a throwaway image, boot, install `kcstat`, then:

```bash
kcstat
```

Expected: 29 lines of `name value`. All values are zero except that nothing is instrumented yet, so **every** value should be `0`. Confirm the *names* are correct and distinct — specifically that they read `tlb_flush_full`, `kalloc_calls`, `kalloc_zone_hits.0` … `kalloc_zone_hits.15`, `zone_expand_races`, and not the literal string `f` repeated. If they are wrong, apply the `KC_EMIT` fallback from Task 1 Step 2.

Then check reset works and is privileged:

```bash
kcstat -z
```

Expected as root: silent success, exit 0. Expected as a normal user: `kcstat: reset: Operation not permitted`.

- [ ] **Step 8: Commit**

```bash
git add src/kernel-7/machdep/i386/i386_init.c src/kernel-7/machdep/ppc/machdep.c \
        src/Commands/system_cmds/kcstat.tproj src/Commands/system_cmds/Makefile
git commit -m "kernel: expose hot-path counters via CTL_MACHDEP and add kcstat"
```

---

## Task 3: TLB instrumentation (i386)

**Files:**
- Modify: `src/kernel-7/machdep/i386/pmap.c:172-190`

**Interfaces:**
- Consumes: `KC_INC`, `KC_ADD` from Task 1.
- Produces: populated `tlb_flush_full`, `tlb_flush_single`, `tlb_invlpg_pages`, `tlb_full_pages`.

- [ ] **Step 1: Establish what the counters must show**

Before changing anything, note the assertion this task has to satisfy: after a boot plus any real work, `tlb_flush_full` and `tlb_full_pages` must both be non-zero, and `tlb_full_pages` must be strictly greater than `tlb_flush_full` (every full-flush range is more than one page, by the existing `end - start > PAGE_SIZE` test). If `tlb_full_pages <= tlb_flush_full`, the accounting is wrong.

- [ ] **Step 2: Add the include**

In `src/kernel-7/machdep/i386/pmap.c`, add alongside the existing `kern/` includes:

```c
#include <kern/kcounters.h>
```

- [ ] **Step 3: Instrument `pmap_update_tlbs`**

Replace lines 172–190 of `src/kernel-7/machdep/i386/pmap.c`:

```c
static inline
void
pmap_update_tlbs(
    pmap_t		pmap,
    vm_offset_t		start,
    vm_offset_t		end
)
{
    if (pmap == kernel_pmap || pmap->cpus_using) {
	tlb_stat.total++;
	if (end - start > PAGE_SIZE) {
	    KC_INC(tlb_flush_full);
	    KC_ADD(tlb_full_pages, (end - start) / I386_PGBYTES);
	    flush_tlb();
	}
	else {
	    for (; start < end; start += I386_PGBYTES) {
		invlpg(start, pmap == kernel_pmap);
		KC_INC(tlb_invlpg_pages);
	    }

	    KC_INC(tlb_flush_single);
	    tlb_stat.single++;
	}
    }
}
```

Two things to keep straight. `tlb_stat` is left alone — it is write-only dead instrumentation, and removing it is not this task's job. And `tlb_full_pages` divides by `I386_PGBYTES` to match the units of the `invlpg` loop, so the two page counts are directly comparable; a range is never zero pages here because the branch requires `end - start > PAGE_SIZE`.

- [ ] **Step 4: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success.

- [ ] **Step 5: Verify against Step 1's assertion**

Boot a throwaway image, then:

```bash
kcstat
```

Expected: `tlb_flush_full` non-zero, `tlb_full_pages` non-zero and strictly greater than `tlb_flush_full`. `tlb_flush_single` and `tlb_invlpg_pages` may be zero or non-zero — single-page ranges are legitimately rare, and that in itself is the signal Task 10 is gated on.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/machdep/i386/pmap.c
git commit -m "pmap: count TLB flush kind and pages invalidated on i386"
```

---

## Task 4: kalloc instrumentation

**Files:**
- Modify: `src/kernel-7/kern/kalloc.c` (`kalloc` and `kfree`)

**Interfaces:**
- Consumes: `KC_INC` from Task 1 (include already added in Task 1 Step 4).
- Produces: populated `kalloc_calls`, `kfree_calls`, `kalloc_oversize`, `kalloc_oversize_page`, `kalloc_zone_hits[]`.

Instrument only `kalloc` and `kfree`. `kalloc_noblock`, `kget`, and `kalloc_zone` are left uninstrumented on purpose: Task 8's exactness check compares the histogram before and after a change to all five, and a histogram fed by only the two hot entry points is a *narrower* but still perfectly valid invariant. Counting all five would work too; what matters is that the set is identical across Tasks 4 and 8.

- [ ] **Step 1: Establish what the counters must show**

The assertion: `kalloc_calls` must be non-zero after boot, and the sum of `kalloc_zone_hits[0..15]` plus `kalloc_oversize` must equal `kalloc_calls` exactly. Every call takes exactly one of those paths. If the identity does not hold, the instrumentation is misplaced.

Also: `kalloc_oversize_page` must be less than or equal to `kalloc_oversize`, since it is a subset.

- [ ] **Step 2: Instrument `kalloc`**

In `src/kernel-7/kern/kalloc.c`, replace the body of `kalloc` (the second of the two identical-looking functions, following `kalloc_noblock`):

```c
vm_offset_t kalloc(size)
	vm_size_t size;
{
	register int zindex = 0;
	register vm_size_t allocsize;
	vm_offset_t addr;

	KC_INC(kalloc_calls);

	/* compute the size of the block that we will actually allocate */
	allocsize = size;
	if (size <= k_zone_maxsize) {
		allocsize = k_zone_elemsize[0];
		zindex = 0;
		while (allocsize < size) {
			allocsize = k_zone_elemsize[++zindex];
		}
	}

	/*
	 * If our size is still small enough, check the queue for that size
	 * and allocate.
	 */

	if (allocsize <= k_zone_maxsize) {
		KC_INC(kalloc_zone_hits[zindex]);
		addr = zalloc(k_zone[zindex]);
#if DIAGNOSTIC
#if ZALLOC0
		(void) memset((void *)addr, 0, (size_t) size);
#endif
#endif
	} else {
		KC_INC(kalloc_oversize);
		if (allocsize <= PAGE_SIZE)
			KC_INC(kalloc_oversize_page);
		if (kmem_alloc_wired(kalloc_map, &addr, allocsize)
							!= KERN_SUCCESS)
			addr = 0;
	}
	return(addr);
}
```

- [ ] **Step 3: Instrument `kfree`**

Add a single counter at the top of `kfree` in the same file:

```c
void 
kfree(data, size)
	vm_offset_t data;
	vm_size_t size;
{
	register int zindex = 0;
	register vm_size_t freesize;

	KC_INC(kfree_calls);

	freesize = size;
```

Leave the rest of `kfree` unchanged.

- [ ] **Step 4: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success.

- [ ] **Step 5: Verify the identity from Step 1**

Boot a throwaway image, then:

```bash
kcstat
```

Sum `kalloc_zone_hits.0` through `kalloc_zone_hits.15`, add `kalloc_oversize`, and confirm the total equals `kalloc_calls` exactly. Confirm `kalloc_oversize_page <= kalloc_oversize`.

Note which of `kalloc_zone_hits.12` through `.15` are non-zero: they must all be **zero**, because `kalloc_init` only creates zones for indices 0–11 (it breaks at 4096, `kern/kalloc.c:121`). A non-zero count in 12–15 means `zindex` ran past the created zones, which would be a live bug worth stopping for.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/kern/kalloc.c
git commit -m "kalloc: count allocations per zone index and oversize fallbacks"
```

---

## Task 5: Zone instrumentation

**Files:**
- Modify: `src/kernel-7/kern/zalloc.c` (`zalloc_canblock` around lines 1496–1560; `host_zone_collect` around line 2036)

**Interfaces:**
- Consumes: `KC_INC`, `KC_ADD` from Task 1.
- Produces: populated `zone_expansions`, `zone_space_failures`, `zone_reclaims`, `zone_reclaim_pages`, `zone_expand_races`. Also introduces the file-static `zone_expand_depth`, used again by Task 12.

- [ ] **Step 1: Establish what the counters must show**

The assertion: after a boot plus the workloads, `zone_expansions` is expected to be non-zero (zones grow during normal operation) while `zone_space_failures` must be **zero** — a non-zero value on a healthy system would mean the machine is already hitting the panic path.

`zone_expand_races` is the observation this task exists for, and it has no expected value. Whatever it reads is the answer, and it decides Task 12.

- [ ] **Step 2: Add the include and the depth counter**

In `src/kernel-7/kern/zalloc.c`, add alongside the existing `kern/` includes:

```c
#include <kern/kcounters.h>
```

Then, near the other file-scope declarations (by `zone_map_size_min` at line 156), add:

```c
/*
 * Non-pageable zone expansion drops the zone lock and can block in
 * zget_space() without setting doing_alloc, so two allocators can expand the
 * same zone.  This depth counter exists to establish whether that actually
 * happens before anyone changes the locking.  See kcounters.h.
 */
int	zone_expand_depth = 0;
```

Not `static`: Task 12 may need it from the same file, and file-static would be fine, but leaving it external keeps a debugger able to read it, which is worth more here than the namespace tidiness.

- [ ] **Step 3: Instrument the expansion and failure paths**

In `zalloc_canblock`, the `expandable` branch is at roughly line 1503. Add the counter where `max_size` grows:

```c
				if (zone->expandable) {
					/*
					 * We're willing to overflow certain
					 * zones, but not without complaining.
					 *
					 * This is best used in conjunction
					 * with the collecatable flag. What we
					 * want is an assurance we can get the
					 * memory back, assuming there's no
					 * leak. 
					 */
					KC_INC(zone_expansions);
					zone->max_size += (zone->max_size >> 1);
				} else if (!zone_ignore_overflow) {
```

Then wrap the non-pageable `zget_space` call. Replace the `} else {` block at roughly lines 1543–1553:

```c
			} else {
				zone_expand_depth++;
				if (zone_expand_depth > 1)
					KC_INC(zone_expand_races);

				addr = zget_space(
					zone->free_space,
					zone->elem_size,
					canblock);

				zone_expand_depth--;

				if (addr == 0) {
					KC_INC(zone_space_failures);
					if (!canblock)
						return(0);
					panic("zalloc");
				}
```

Leave the rest of that block — the `lock_zone`, `zone->count++`, `WATERMARK_ZONE`, `unlock_zone`, `return(addr)` sequence — unchanged.

The decrement must happen on **both** exits. The `return(0)` for `!canblock` is after the decrement above, so it is covered; the `panic` path does not matter because the machine is going down.

- [ ] **Step 4: Instrument reclaim**

In `host_zone_collect` (line 2036, inside `#if MACH_DEBUG`), count the run and the pages returned. Replace the page-return loop near the end:

```c
	KC_INC(zone_reclaims);

	/*
	 * Return any reclaimed pages to
	 * the system.
	 */
	while ((cur = pages) != 0) {
		pages = cur->next;
		KC_ADD(zone_reclaim_pages, cur->length / PAGE_SIZE);
		kmem_free(zone_map, (vm_offset_t)cur, cur->length);
	}

	return KERN_SUCCESS;
}
```

Place `KC_INC(zone_reclaims)` after the `if (!collect_zones) return KERN_SUCCESS;` early exit, so it counts real runs only. Read `cur->length` *before* `kmem_free` — after the free the memory is gone.

These two counters stay zero until something calls reclaim, which today is only a userland RPC. Task 11 gives them an in-kernel caller.

**If you are reading this while implementing Task 11:** that task moves this whole loop into a new `zone_reclaim_all()` and carries both counters with it, leaving `host_zone_collect` a thin caller with no counters of its own. That is intentional — the instrumentation follows the code, it is not lost.

- [ ] **Step 5: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success.

- [ ] **Step 6: Verify against Step 1's assertions**

Boot a throwaway image, then:

```bash
kcstat
```

Expected: `zone_space_failures` is `0`. `zone_expansions` is most likely non-zero. `zone_reclaims` and `zone_reclaim_pages` are `0`. Record `zone_expand_races` — do not judge it yet; Task 6 captures it properly under load.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/kern/zalloc.c
git commit -m "zalloc: count zone expansions, space failures, reclaim, and expand races"
```

---

## Task 6: Workloads and committed baseline

**This is the gate. Nothing after it may be committed until this task's baseline is committed.**

**Files:**
- Create: `tools/kperf/vfs-alloc.sh`
- Create: `tools/kperf/fork-cow.c`
- Create: `tools/kperf/fork-cow.sh`
- Create: `tools/kperf/README.md`
- Create: `docs/kernel/perf-baseline.md`

**Interfaces:**
- Consumes: `kcstat` from Task 2; all counters from Tasks 3–5.
- Produces: `docs/kernel/perf-baseline.md` containing a `## Baseline` section with a median counter dump per workload. Tasks 7–12 read their gate conditions from it and append their own sections.

- [ ] **Step 1: Write the VFS/allocator workload**

Create `tools/kperf/vfs-alloc.sh`:

```sh
#!/bin/sh
#
# vfs-alloc -- allocator, zone, and VFS workload for the kernel counter
# harness.  Run in single-user mode.  See tools/kperf/README.md.
#
# Also verifies data integrity: a stale-TLB bug from the pmap flush threshold
# shows up as silent corruption, not a crash, so every run re-reads what it
# wrote and compares checksums.  A counter improvement with a checksum
# mismatch is a bug, not a win.

set -e

SRC=${SRC:-/usr/local/kperf/tree.tar}
WORK=${WORK:-/tmp/kperf.work}
MANIFEST=${MANIFEST:-/usr/local/kperf/tree.manifest}

if [ ! -f "$SRC" ]; then
	echo "vfs-alloc: missing $SRC" >&2
	exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

tar xf "$SRC"

find . -type f -print | sort | while read f; do
	wc -l < "$f" > /dev/null
done

find . -type f -print | sort | xargs sum > sums.actual

if [ -f "$MANIFEST" ]; then
	if cmp -s sums.actual "$MANIFEST"; then
		echo "vfs-alloc: checksums OK"
	else
		echo "vfs-alloc: CHECKSUM MISMATCH -- data corruption" >&2
		diff "$MANIFEST" sums.actual >&2 || true
		exit 2
	fi
else
	cp sums.actual "$MANIFEST"
	echo "vfs-alloc: wrote initial manifest to $MANIFEST"
fi

cd /
rm -rf "$WORK"
echo "vfs-alloc: done"
```

- [ ] **Step 2: Write the fork/COW workload**

Create `tools/kperf/fork-cow.c`:

```c
/*
 * fork-cow -- drive pmap_protect and pmap_remove ranges for the kernel
 * counter harness.
 *
 * Two generators of TLB work: repeated fork/exit, which copy-on-write
 * protects the whole parent address space and then tears the child's down;
 * and repeated write faults into a fresh mapping, which downgrade
 * protections a page at a time.
 *
 * Deliberately fixed-size and argument-free -- a workload whose amount of
 * work varies between runs cannot be a baseline.
 */

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define	FORKS		200
#define	MAP_PAGES	256
#define	MAP_ROUNDS	20

static void
do_forks()
{
	int	i, status;
	pid_t	pid;

	for (i = 0; i < FORKS; i++) {
		pid = fork();
		if (pid < 0) {
			perror("fork-cow: fork");
			exit(1);
		}
		if (pid == 0)
			_exit(0);
		if (waitpid(pid, &status, 0) < 0) {
			perror("fork-cow: waitpid");
			exit(1);
		}
	}
}

static void
do_faults()
{
	int	round, i;
	int	pagesize = getpagesize();
	size_t	len = (size_t)MAP_PAGES * pagesize;
	char	*p;

	for (round = 0; round < MAP_ROUNDS; round++) {
		p = (char *)mmap((caddr_t)0, len, PROT_READ | PROT_WRITE,
				 MAP_ANON | MAP_PRIVATE, -1, (off_t)0);
		if (p == (char *)-1) {
			perror("fork-cow: mmap");
			exit(1);
		}

		for (i = 0; i < MAP_PAGES; i++)
			p[i * pagesize] = (char)i;

		if (munmap((caddr_t)p, len) < 0) {
			perror("fork-cow: munmap");
			exit(1);
		}
	}
}

int
main(argc, argv)
	int	argc;
	char	**argv;
{
	do_forks();
	do_faults();
	printf("fork-cow: done\n");
	exit(0);
}
```

If `MAP_ANON` is unavailable on this vintage, substitute a mapping of `/dev/zero`:

```c
		int fd = open("/dev/zero", O_RDWR);
		p = (char *)mmap((caddr_t)0, len, PROT_READ | PROT_WRITE,
				 MAP_PRIVATE, fd, (off_t)0);
		close(fd);
```

with `#include <fcntl.h>` added. Confirm which form compiles before running a baseline — a workload that does not build blocks Task 10 entirely.

- [ ] **Step 3: Write the driver and README**

Create `tools/kperf/fork-cow.sh`:

```sh
#!/bin/sh
#
# fork-cow driver.  Run in single-user mode.

set -e
BIN=${BIN:-/usr/local/kperf/fork-cow}

if [ ! -x "$BIN" ]; then
	echo "fork-cow.sh: missing $BIN" >&2
	exit 1
fi

"$BIN"
```

Create `tools/kperf/README.md`:

```markdown
# Kernel counter measurement

Counters come from `kcstat(8)`; see
`docs/superpowers/specs/2026-07-25-kernel-counter-harness-design.md`.

## Why single-user mode

Clock ticks, `netinfod`, `inetd`, and the network stack all allocate
independently of the workload. Single-user mode is the largest available lever
on variance. Accepted trade: the measured profile is narrower than a real
running system's.

## Why not wall-clock time

The reference environment is QEMU/TCG. QEMU flushes its own software TLB, so a
full CR3 reload is cheaper relative to real hardware than it should be, and
elapsed time drifts with host load and translation-block caching. Counters are
the metric; time is not.

## Setup, once per guest

    mkdir -p /usr/local/kperf
    # A fixed tree. Any tree works as long as it never changes between runs.
    tar cf /usr/local/kperf/tree.tar -C /usr/share/man man1
    cc -o /usr/local/kperf/fork-cow fork-cow.c

The first `vfs-alloc.sh` run writes `tree.manifest`. Every later run compares
against it. Do not regenerate the manifest to make a mismatch go away — a
mismatch is the corruption check firing.

## One measurement

    kcstat -z
    sh vfs-alloc.sh
    kcstat > /tmp/vfs-alloc.N

Three runs per workload. Report the median per counter.

## Reading a result

Exact criteria — `kalloc_zone_hits.*` equality, `kalloc_oversize` arithmetic —
must match exactly; a near miss is a bug, not noise. Statistical criteria —
flush and expansion counts — need the before/after gap to exceed the observed
run-to-run spread. If it does not, the change did nothing measurable, and that
is the result to record.
```

- [ ] **Step 4: Build and stage the workloads in the guest**

```bash
cd src/Commands/system_cmds/kcstat.tproj && make install
```

```bash
mkdir -p /usr/local/kperf && cc -o /usr/local/kperf/fork-cow tools/kperf/fork-cow.c
```

```bash
tar cf /usr/local/kperf/tree.tar -C /usr/share/man man1
```

Expected: `fork-cow` compiles and `/usr/local/kperf/tree.tar` exists. If `fork-cow.c` fails on `MAP_ANON`, apply the `/dev/zero` variant from Step 2 and commit that version.

- [ ] **Step 5: Capture the baseline**

Boot the Task 5 kernel on a throwaway image, drop to single-user mode, and run each workload three times:

```bash
for i in 1 2 3; do kcstat -z; sh vfs-alloc.sh; kcstat > /tmp/vfs-alloc.$i; done
```

```bash
for i in 1 2 3; do kcstat -z; sh fork-cow.sh; kcstat > /tmp/fork-cow.$i; done
```

Expected: `vfs-alloc.sh` prints `checksums OK` on runs 2 and 3 (run 1 writes the manifest). Every run completes.

- [ ] **Step 6: Record the baseline and the gate decisions**

Create `docs/kernel/perf-baseline.md` with the median dump for each workload, then state each gate decision explicitly:

```markdown
# Kernel counter baseline

Kernel: <git rev of the Task 5 commit>
Guest: QEMU/TCG, single-user mode, median of 3 runs per workload.
Method: tools/kperf/README.md

## Baseline: vfs-alloc

<paste median counter dump>

## Baseline: fork-cow

<paste median counter dump>

## Run-to-run spread

Per counter, the max-minus-min across the three runs. Statistical criteria in
later tasks must clear this to count as an effect.

<table: counter, min, median, max>

## Gate decisions

- **Task 9 (page-sized zone)** — `kalloc_oversize_page` = N.
  Proceed / dropped: <reason>
- **Task 10 (TLB threshold)** — `tlb_flush_full` = N, `tlb_full_pages` = M,
  mean pages per full flush = M/N.
  Proceed / dropped: <reason>
- **Task 12 (doing_alloc race)** — `zone_expand_races` = N.
  Proceed / dropped: <reason>
```

For Task 10, the number that decides it is **`tlb_full_pages / tlb_flush_full`** — the mean range size taking the full-flush path. A mean near 2 means a threshold of 8 converts nearly everything and the task is worth doing. A mean in the hundreds means the flushes are dominated by large ranges that no reasonable threshold captures, and the task is dropped. Write the actual ratio down; do not proceed on a hunch.

- [ ] **Step 7: Commit**

```bash
git add tools/kperf docs/kernel/perf-baseline.md
git commit -m "kernel: add counter workloads and record the measurement baseline"
```

---

## Task 7: Frame pointers in release builds (gated)

**Gate:** this task is gated on a check, not on a baseline counter. Step 1 determines whether it is needed at all.

**Files:**
- Modify: `src/kernel-7/conf/MASTER.i386:82`
- Modify: `src/kernel-7/conf/MASTER.ppc:82`

**Interfaces:** none — build configuration only.

- [ ] **Step 1: Check whether release builds already keep frame pointers**

The premise is that `-O3` omits frame pointers, making release panic backtraces unreliable. **That premise may be false.** gcc of this vintage historically did *not* enable `-fomit-frame-pointer` at any `-O` level on i386, precisely because it broke debugging. If frame pointers are already present, this task is a no-op and must be dropped.

In the guest, compile one representative kernel source to assembly using the exact release flags from `conf/MASTER.i386:82` and `conf/Makefile.i386:49,52`:

```bash
cd src/kernel-7 && cc -static -nostdinc -nostdlib -traditional-cpp -O3 -S -arch i386 -I bsd/include -I . -o /tmp/kalloc.s kern/kalloc.c
```

If the include flags are insufficient, take the exact compile line for `kalloc.o` from the build output in `BUILD/RELEASE_I386/` and add `-S` to it — that is guaranteed correct where a hand-assembled flag list is not.

Then:

```bash
grep -c "pushl %ebp" /tmp/kalloc.s
```

- [ ] **Step 2: Decide**

If the count is greater than zero, frame pointers are already retained at `-O3`. **Drop this task.** Record in `docs/kernel/perf-baseline.md`:

```markdown
## Task 7: frame pointers -- DROPPED

Release `-O3` already emits frame-pointer prologues (`pushl %ebp` found N
times in kern/kalloc.c). `-fno-omit-frame-pointer` would be a no-op.
```

Commit that note and stop. If the count is zero, continue to Step 3.

- [ ] **Step 3: Add the flag**

In `src/kernel-7/conf/MASTER.i386`, change line 82:

```
makeoptions	CCONFIGFLAGS = "-O3 -fno-omit-frame-pointer"	# <!gdb>
```

In `src/kernel-7/conf/MASTER.ppc`, change line 82 identically:

```
makeoptions	CCONFIGFLAGS = "-O3 -fno-omit-frame-pointer"	# <!gdb>
```

- [ ] **Step 4: Rebuild and re-check**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Repeat the Step 1 compile-to-assembly with the new flag added, then:

```bash
grep -c "pushl %ebp" /tmp/kalloc.s
```

Expected: greater than zero, where Step 1 gave zero.

- [ ] **Step 5: Boot**

Boot a throwaway image. Expected: boots to multi-user. This only confirms the flag did not break codegen.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/conf/MASTER.i386 src/kernel-7/conf/MASTER.ppc \
        docs/kernel/perf-baseline.md
git commit -m "kernel: keep frame pointers in release builds for usable panic backtraces"
```

---

## Task 8: kalloc size-to-index lookup table

**Files:**
- Modify: `src/kernel-7/kern/kalloc.c`

**Interfaces:**
- Consumes: `k_zone_elemsize`, `k_zone_maxsize`, `NKSIZE` (existing file scope).
- Produces: `static int kalloc_zindex(vm_size_t size)` — returns the index into `k_zone`/`k_zone_elemsize` for `size`, valid only when `size <= k_zone_maxsize`. Used by Task 9.

- [ ] **Step 1: State the invariant this must preserve**

All five entry points currently linear-scan `k_zone_elemsize[16]` — up to 12 iterations per allocation and per free. Every entry in that table is a multiple of 16, so a table indexed by `(size + 15) >> 4` is **exact**, not an approximation.

The invariant: `kalloc_zone_hits[]` after this change must be **byte-identical** to the Task 6 baseline for both workloads. Not close — identical. Any divergence means the table is not a faithful rewrite, which is a correctness bug.

- [ ] **Step 2: Add the table and helper**

In `src/kernel-7/kern/kalloc.c`, after the `k_zone_elemsize` initializer, add:

```c
/*
 * Maps a request size to its k_zone index without scanning.
 *
 * Every k_zone_elemsize entry is a multiple of 16, so a table with 16-byte
 * granularity is exact rather than approximate.  Indexed by
 * (size + 15) >> 4, covering 0 through k_zone_maxsize; built once by
 * kalloc_init after the zones exist.
 */
#define	KALLOC_INDEX_GRAIN	16
#define	KALLOC_INDEX_MAX	((16384 / KALLOC_INDEX_GRAIN) + 1)

static unsigned char	k_zone_index[KALLOC_INDEX_MAX];
static int		k_zone_index_limit;

static int
kalloc_zindex(size)
	vm_size_t	size;
{
	register int	i = (size + (KALLOC_INDEX_GRAIN - 1)) /
					KALLOC_INDEX_GRAIN;

	if (i >= k_zone_index_limit)
		i = k_zone_index_limit - 1;

	return ((int)k_zone_index[i]);
}
```

`KALLOC_INDEX_MAX` is sized from the largest entry the table could ever need (16384, the last `k_zone_elemsize` value) rather than from `k_zone_maxsize`, which is a runtime value. That costs 1 KB of BSS and means Task 9 does not have to resize anything.

The clamp is defensive against a caller passing a size above `k_zone_maxsize`; such callers take the oversize branch anyway and never use the result.

- [ ] **Step 3: Populate the table in `kalloc_init`**

Replace the body of `kalloc_init`:

```c
void kalloc_init(void)
{
	vm_size_t size;
	register int i;
	register int zindex;
	register int slot;
	
	kalloc_map = kernel_map;

	/*
	 *	Allocate a zone for each size we are going to handle.
	 *	We specify non-paged memory.
	 */
	for (i = 0; i < NKSIZE; i++) {
		if ((size = k_zone_elemsize[i]) >= PAGE_SIZE)
			break;
		sprintf (k_zone_name[i], "kalloc.%d", size);
		k_zone[i] = zinit(size, 1024*1024, PAGE_SIZE,
			FALSE, k_zone_name[i]);
		k_zone_maxsize = size;
	}

	/*
	 *	Build the size-to-index table for the zones that now exist.
	 *	Slot n covers requests of (n-1)*GRAIN+1 .. n*GRAIN bytes;
	 *	slot 0 covers a zero-byte request and maps to the smallest zone.
	 */
	k_zone_index_limit = (k_zone_maxsize / KALLOC_INDEX_GRAIN) + 1;

	zindex = 0;
	for (slot = 0; slot < k_zone_index_limit; slot++) {
		size = (vm_size_t)slot * KALLOC_INDEX_GRAIN;
		while (k_zone_elemsize[zindex] < size)
			zindex++;
		k_zone_index[slot] = (unsigned char)zindex;
	}
}
```

The `while` walks monotonically across the whole loop — total work is `NKSIZE` steps for the entire table, not per slot. It reproduces the original scan's semantics exactly: the original found the first `k_zone_elemsize[zindex] >= size`, and so does this.

- [ ] **Step 4: Replace all five scans**

In each of `kalloc_noblock`, `kalloc`, `kget`, `kfree`, and `kalloc_zone`, replace the scan block with a `kalloc_zindex` call. The pattern, using `kalloc` (which also keeps its Task 4 counters):

```c
vm_offset_t kalloc(size)
	vm_size_t size;
{
	register int zindex = 0;
	register vm_size_t allocsize;
	vm_offset_t addr;

	KC_INC(kalloc_calls);

	/* compute the size of the block that we will actually allocate */
	allocsize = size;
	if (size <= k_zone_maxsize) {
		zindex = kalloc_zindex(size);
		allocsize = k_zone_elemsize[zindex];
	}

	/*
	 * If our size is still small enough, check the queue for that size
	 * and allocate.
	 */

	if (allocsize <= k_zone_maxsize) {
		KC_INC(kalloc_zone_hits[zindex]);
		addr = zalloc(k_zone[zindex]);
#if DIAGNOSTIC
#if ZALLOC0
		(void) memset((void *)addr, 0, (size_t) size);
#endif
#endif
	} else {
		KC_INC(kalloc_oversize);
		if (allocsize <= PAGE_SIZE)
			KC_INC(kalloc_oversize_page);
		if (kmem_alloc_wired(kalloc_map, &addr, allocsize)
							!= KERN_SUCCESS)
			addr = 0;
	}
	return(addr);
}
```

Apply the same three-line substitution in the other four. `kfree` uses `freesize` rather than `allocsize`:

```c
	freesize = size;
	if (size <= k_zone_maxsize) {
		zindex = kalloc_zindex(size);
		freesize = k_zone_elemsize[zindex];
	}
```

Keep `KC_INC(kfree_calls)` at the top of `kfree`, and leave `kget`'s `panic("kget")` and `kalloc_zone`'s `return (0)` untouched.

- [ ] **Step 5: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success, no warning about `kalloc_zindex` being unused.

- [ ] **Step 6: Verify the exactness invariant**

Boot a throwaway image, drop to single-user, and run both workloads three times as in Task 6 Step 5.

Compare `kalloc_zone_hits.0` through `.15`, `kalloc_calls`, `kfree_calls`, `kalloc_oversize`, and `kalloc_oversize_page` against the Task 6 baseline.

Expected: the `kalloc_zone_hits` distribution is identical in shape to the baseline. Absolute counts will differ slightly run to run even in single-user mode, so the check that actually matters is **the set of non-zero indices and their relative proportions**, plus the Task 4 identity still holding exactly:

```
sum(kalloc_zone_hits.0 .. .15) + kalloc_oversize == kalloc_calls
```

If a *new* index becomes non-zero, or a previously non-zero index goes to zero, the table is wrong — stop and fix it before committing. That is the failure this step exists to catch.

- [ ] **Step 7: Record and commit**

Append to `docs/kernel/perf-baseline.md`:

```markdown
## Task 8: kalloc lookup table

Zone-hit distribution before/after, and confirmation that
sum(hits) + oversize == calls still holds.

<table>
```

```bash
git add src/kernel-7/kern/kalloc.c docs/kernel/perf-baseline.md
git commit -m "kalloc: replace the size table scan with an exact lookup table"
```

---

## Task 9: Page-sized zone (gated)

**Gate:** proceed only if `kalloc_oversize_page` in the Task 6 baseline is a meaningful fraction of `kalloc_oversize`. If it is zero or negligible, mark this task dropped with the number and move on.

**Files:**
- Modify: `src/kernel-7/kern/kalloc.c:121`

**Interfaces:**
- Consumes: `kalloc_zindex` from Task 8.
- Produces: `k_zone_maxsize` becomes 4096; `k_zone[12]` exists.

- [ ] **Step 1: Confirm the gate and state the expectation**

Read `kalloc_oversize_page` and `kalloc_oversize` from the baseline. If proceeding, the expectation is precise: `kalloc_oversize_page` drops to **0**, `kalloc_oversize` drops by **exactly** the old `kalloc_oversize_page`, and `kalloc_zone_hits.12` becomes non-zero carrying that same count.

- [ ] **Step 2: Give 4096 a zone**

In `src/kernel-7/kern/kalloc.c`, change line 121 from `>=` to `>`:

```c
		if ((size = k_zone_elemsize[i]) > PAGE_SIZE)
			break;
```

Nothing else changes. `KALLOC_INDEX_MAX` from Task 8 is already sized for 16384, and `k_zone_index_limit` is computed from `k_zone_maxsize` at runtime, so the table grows on its own.

This is mechanically sound: these zones are non-pageable, so elements come individually from `zget_space` rather than `zcram`, making `alloc_size` irrelevant. `zinit` handles `size == PAGE_SIZE` without special-casing (`kern/zalloc.c:670-694`). The existing 3072 zone already proves the path. The win is element reuse in place of a fresh `kmem_alloc_wired` per request.

- [ ] **Step 3: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success.

- [ ] **Step 4: Verify the arithmetic**

Boot a throwaway image, single-user, both workloads three times.

Expected, against the Task 8 numbers:
- `kalloc_oversize_page` == 0
- `kalloc_zone_hits.12` > 0
- `kalloc_oversize` decreased by approximately the previous `kalloc_oversize_page`
- `sum(kalloc_zone_hits.*) + kalloc_oversize == kalloc_calls` still exact

Watch `zone_expansions` too: a new zone drawing 4 KB elements from `zone_map` will grow, and a large jump here is worth noting even though it is not a failure.

- [ ] **Step 5: Record and commit**

Append the before/after table to `docs/kernel/perf-baseline.md` under `## Task 9: page-sized zone`, then:

```bash
git add src/kernel-7/kern/kalloc.c docs/kernel/perf-baseline.md
git commit -m "kalloc: add a page-sized zone so 4K requests stop hitting kmem_alloc_wired"
```

---

## Task 10: TLB flush threshold, i386 (gated)

**Gate:** proceed only if `tlb_full_pages / tlb_flush_full` from the Task 6 baseline is small — a mean full-flush range of roughly 8 pages or fewer. If the mean is large, no reasonable threshold converts those flushes; mark the task dropped with the ratio.

**Files:**
- Modify: `src/kernel-7/machdep/i386/pmap.c:172-190`

**Interfaces:** none exported.

- [ ] **Step 1: Confirm the gate**

Compute the ratio from the baseline and write it down. If proceeding, state the expectation: `tlb_flush_full` falls by more than the run-to-run spread, and `tlb_invlpg_pages` grows by no more than `PMAP_TLB_INVLPG_MAX` times the number of converted flushes.

- [ ] **Step 2: Add the threshold**

Replace the function in `src/kernel-7/machdep/i386/pmap.c`:

```c
/*
 * Ranges of at most this many pages are invalidated one page at a time;
 * anything larger takes a full TLB flush.  A full flush is a CR3 reload,
 * which discards every entry including the kernel's, so converting small
 * ranges to invlpg is worth several invlpg instructions.
 */
#define	PMAP_TLB_INVLPG_MAX	8

static inline
void
pmap_update_tlbs(
    pmap_t		pmap,
    vm_offset_t		start,
    vm_offset_t		end
)
{
    if (pmap == kernel_pmap || pmap->cpus_using) {
	tlb_stat.total++;
	if ((end - start) >
	    (vm_offset_t)(PMAP_TLB_INVLPG_MAX * I386_PGBYTES)) {
	    KC_INC(tlb_flush_full);
	    KC_ADD(tlb_full_pages, (end - start) / I386_PGBYTES);
	    flush_tlb();
	}
	else {
	    for (; start < end; start += I386_PGBYTES) {
		invlpg(start, pmap == kernel_pmap);
		KC_INC(tlb_invlpg_pages);
	    }

	    KC_INC(tlb_flush_single);
	    tlb_stat.single++;
	}
    }
}
```

- [ ] **Step 3: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success.

- [ ] **Step 4: Verify counters *and* data integrity**

Boot a throwaway image, single-user, both workloads three times.

**The checksum comparison in `vfs-alloc.sh` is the load-bearing check here, not the counters.** A missed invalidation produces silent data corruption, not a crash. A run that shows a beautiful counter improvement and a checksum mismatch is a stale-TLB bug, and without the checksum it would ship believed working.

Expected:
- `vfs-alloc: checksums OK` on every run — **any mismatch stops this task immediately**
- `tlb_flush_full` down by more than the baseline spread
- `tlb_flush_single` and `tlb_invlpg_pages` up
- `tlb_invlpg_pages` growth no more than 8 × the drop in `tlb_flush_full`

If the checksums mismatch, revert the change and record the finding. Do not attempt to tune the threshold downward to make the corruption less frequent — a threshold that corrupts at 8 pages and appears not to at 2 is still wrong, and the bug is in the invalidation, not the number.

- [ ] **Step 5: Record and commit**

Append to `docs/kernel/perf-baseline.md` under `## Task 10: TLB flush threshold`, including the checksum result explicitly, then:

```bash
git add src/kernel-7/machdep/i386/pmap.c docs/kernel/perf-baseline.md
git commit -m "pmap: invalidate small ranges with invlpg instead of a full TLB flush"
```

---

## Task 11: In-kernel zone reclaim before panic

**Highest risk in this plan. It has an explicit, pre-authorized retreat — see Step 4.**

**Files:**
- Modify: `src/kernel-7/kern/zalloc.c` (`host_zone_collect` at ~2036; `zalloc_canblock` failure path at ~1547)

**Interfaces:**
- Consumes: `zone_collect`, `zone_free_space_reclaim`, `zget_space_lock`, `all_zones_lock` (existing file scope).
- Produces: `int zone_reclaim_all(void)` — reclaims across all collectable non-pageable zones, returns pages freed. Compiled unconditionally.

- [ ] **Step 1: State the problem and the test**

`zone_collect()` (`kern/zalloc.c:925`) and `zone_free_space_reclaim()` (`kern/zalloc.c:1038`) are compiled unconditionally, but their only caller is `host_zone_collect()` (`kern/zalloc.c:2036`), which sits inside `#if MACH_DEBUG` and is reachable only as a MIG RPC (`mach_debug/mach_debug.defs:222`). Zone reclaim is entirely userland-triggered: nothing in the kernel ever reclaims zone memory, including the path that panics for want of it. The primitives exist; the wiring does not.

The test needs forced exhaustion. Build a **throwaway, uncommitted** kernel with both bounds pinned low — in `src/kernel-7/kern/zalloc.c:156-157`:

```c
vm_size_t	zone_map_size_min = 1 * 1024 * 1024;
vm_size_t	zone_map_size_max = 1 * 1024 * 1024;
```

- [ ] **Step 2: Reproduce the panic first**

Build that pinned kernel from the **current** tree, boot it on a throwaway image, and run `vfs-alloc.sh`.

Expected: `panic("zalloc")`, with `zone_space_failures` having incremented. **Reproducing this panic is what validates the test.** If the machine does not panic, the forcing mechanism is not working and there is nothing to verify a fix against — stop and fix the reproduction before writing any code.

- [ ] **Step 3: Factor out `zone_reclaim_all`**

In `src/kernel-7/kern/zalloc.c`, move the reclaim loop out of `host_zone_collect` to just above it, **outside** the `#if MACH_DEBUG` guard:

```c
/*
 * Reclaim free pages from every collectable non-pageable zone.
 * Returns the number of pages returned to zone_map.
 *
 * The primitives this drives have existed all along, but their only caller
 * was host_zone_collect() -- a MACH_DEBUG-only userland RPC -- so nothing in
 * the kernel ever reclaimed zone memory, including the path that panics for
 * want of it.
 */
int
zone_reclaim_all()
{
    	struct zone_free_space_entry
			*cur, *pages = 0;
	zone_t		z;
	int		max_zones, i;
	int		freed = 0;

	simple_lock(simple_lock_addr(zget_space_lock));

	simple_lock(simple_lock_addr(all_zones_lock));
	max_zones = num_zones;
	z = first_zone;
	simple_unlock(simple_lock_addr(all_zones_lock));

	for (i = 0; i < max_zones; i++) {
		assert(z != ZONE_NULL);
	/* run this at splhigh so that interupt routines that use zones
	   can not interupt while their zone is locked */
		lock_zone(z);

		if (!z->pageable && zone_collectable(z))
		    zone_collect(z);

		unlock_zone(z);		
		simple_lock(simple_lock_addr(all_zones_lock));
		z = z->next_zone;
		simple_unlock(simple_lock_addr(all_zones_lock));
	}

	pages = zone_free_space_reclaim();

	simple_unlock(simple_lock_addr(zget_space_lock));

	/*
	 * Return any reclaimed pages to
	 * the system.
	 */
	while ((cur = pages) != 0) {
		pages = cur->next;
		freed += cur->length / PAGE_SIZE;
		kmem_free(zone_map, (vm_offset_t)cur, cur->length);
	}

	KC_INC(zone_reclaims);
	KC_ADD(zone_reclaim_pages, freed);

	return (freed);
}
```

Then reduce `host_zone_collect` to a caller, preserving its existing argument semantics:

```c
kern_return_t host_zone_collect(
	host_t		host,
	boolean_t	collect_zones,
	boolean_t	reclaim_pages)
{
	if (host == HOST_NULL)
		return KERN_INVALID_HOST;

	if (!collect_zones)
	    return KERN_SUCCESS;

	(void) zone_reclaim_all();

	return KERN_SUCCESS;
}
```

Note the behaviour change this makes explicit: the original called `zone_free_space_reclaim()` only when `reclaim_pages` was true. `zone_reclaim_all` always does both, so `reclaim_pages` is now ignored. That is the right call for the in-kernel path — a caller about to panic wants everything — and the RPC's only consumers are debugging tools. Say so in the commit message.

Declare it in `src/kernel-7/kern/zalloc.h` beside the other externs:

```c
extern int	zone_reclaim_all(void);
```

- [ ] **Step 4: Assess reentrancy before wiring it into `zalloc`**

**This is the decision point.** `zone_reclaim_all` takes `zget_space_lock`, `all_zones_lock`, and per-zone locks. The `zalloc_canblock` failure site sits in an unlocked window — the zone lock was released before `zget_space` — so the zone lock itself is not held. Two things must be established by reading the code:

1. Does `zget_space` hold `zget_space_lock` across its failure return? If it does, calling `zone_reclaim_all` from that path self-deadlocks on a non-recursive simple lock.
2. Can `zone_collect` or `zone_free_space_reclaim` allocate? If either calls `zalloc` or `kalloc`, the retry recurses.

Read `zget_space` (`kern/zalloc.c:1273-1310`), `zone_collect` (`:925`), and `zone_free_space_reclaim` (`:1038`) and answer both in writing.

**If either answer is bad, take the retreat:** do not wire reclaim into `zalloc`. Instead replace the bare `panic("zalloc")` with a diagnostic panic and stop:

```c
				if (addr == 0) {
					KC_INC(zone_space_failures);
					if (!canblock)
						return(0);
					printf("zalloc: zone \"%s\" out of space: cur_size %d max_size %d count %d\n",
						zone->zone_name,
						zone->cur_size,
						zone->max_size,
						zone->count);
					panic("zalloc: zone_map exhausted");
				}
```

That is a real improvement — the current panic names nothing — and it is an acceptable outcome for this task. Record the reason in `docs/kernel/perf-baseline.md`, commit, and skip to Task 12. **Do not force the reclaim call through a deadlock risk to satisfy the plan.**

- [ ] **Step 5: Wire reclaim into the failure path**

Only if Step 4 cleared both questions. In `zalloc_canblock`, replace the failure block:

```c
				if (addr == 0 && canblock && !did_reclaim) {
					/*
					 * Nothing in the kernel reclaims zone
					 * memory on its own.  Try once before
					 * taking the machine down.
					 */
					did_reclaim = TRUE;
					KC_INC(zone_space_failures);
					(void) zone_reclaim_all();
					addr = zget_space(
						zone->free_space,
						zone->elem_size,
						canblock);
				}

				if (addr == 0) {
					if (!canblock)
						return(0);
					printf("zalloc: zone \"%s\" out of space after reclaim\n",
						zone->zone_name);
					panic("zalloc: zone_map exhausted");
				}
```

Declare `did_reclaim` at the top of `zalloc_canblock`:

```c
	boolean_t	did_reclaim = FALSE;
```

`did_reclaim` is what makes this retry-once rather than a loop. Note that `KC_INC(zone_space_failures)` moved into the first-failure branch so it still counts every exhaustion exactly once.

`zone_expand_depth` from Task 5 must still be decremented on these paths — keep the `zone_expand_depth--` from Task 5 Step 3 positioned after the `zget_space` call and before this block.

- [ ] **Step 6: Verify against the reproduction**

Rebuild the pinned-1 MB kernel with the change, boot a throwaway image, run `vfs-alloc.sh`.

Expected: `zone_space_failures >= 1`, `zone_reclaims >= 1`, `zone_reclaim_pages > 0`, and the system makes forward progress where Step 2 panicked. A later panic under continued load is acceptable — the goal is converting an immediate crash into a recoverable stall, not making the machine immune to running out of memory.

Then rebuild with the **normal** `zone_map_size_min`/`max` values restored, boot, and confirm a clean boot to multi-user with `zone_space_failures == 0`.

- [ ] **Step 7: Record and commit**

Append the reentrancy findings and the before/after result to `docs/kernel/perf-baseline.md` under `## Task 11: in-kernel zone reclaim`, then:

```bash
git add src/kernel-7/kern/zalloc.c src/kernel-7/kern/zalloc.h \
        docs/kernel/perf-baseline.md
git commit -m "zalloc: reclaim zone memory in-kernel before panicking on exhaustion

host_zone_collect no longer honors reclaim_pages separately; zone_reclaim_all
always collects and reclaims."
```

Confirm `git status` shows no leftover edit to `zone_map_size_min` or `zone_map_size_max` — those pinned values must never be committed.

---

## Task 12: `doing_alloc` for non-pageable expansion (gated)

**Gate:** proceed only if `zone_expand_races` in the Task 6 baseline is non-zero. If it is zero, the race is theoretical on this uniprocessor kernel; mark the task dropped and leave a comment at the site instead.

**Files:**
- Modify: `src/kernel-7/kern/zalloc.c` (`zalloc_canblock`, non-pageable branch)

**Interfaces:** none exported.

- [ ] **Step 1: Confirm the gate**

Read `zone_expand_races` from the baseline. If zero, add only this comment above the non-pageable branch, commit it, and stop:

```c
			} else {
				/*
				 * NB: unlike the pageable branch above, this
				 * one drops the zone lock and can block in
				 * zget_space() without setting doing_alloc,
				 * so two allocators can expand the same zone.
				 * Measured as zone_expand_races == 0 on this
				 * uniprocessor kernel; left alone rather than
				 * changing locking for a race that does not
				 * occur.  See docs/kernel/perf-baseline.md.
				 */
```

If non-zero, continue.

- [ ] **Step 2: Hold `doing_alloc` across the unlocked window**

The pageable branch sets `zone->doing_alloc = TRUE` before unlocking (`kern/zalloc.c:1526`) and clears it with a wakeup afterward (`:1536-1538`). The non-pageable branch does neither. Make it match — replace the non-pageable block:

```c
			} else {
				zone_expand_depth++;
				if (zone_expand_depth > 1)
					KC_INC(zone_expand_races);

				lock_zone(zone);
				zone->doing_alloc = TRUE;
				unlock_zone(zone);

				addr = zget_space(
					zone->free_space,
					zone->elem_size,
					canblock);

				lock_zone(zone);
				zone->doing_alloc = FALSE;
				thread_wakeup((event_t)&zone->doing_alloc);
				unlock_zone(zone);

				zone_expand_depth--;

				if (addr == 0) {
					if (!canblock)
						return(0);
					printf("zalloc: zone \"%s\" out of space\n",
						zone->zone_name);
					panic("zalloc: zone_map exhausted");
				}

				lock_zone(zone);
				zone->count++;
				zone->cur_size += zone->elem_size;
				WATERMARK_ZONE(zone, addr);
				unlock_zone(zone);
				return(addr);
			}
```

The zone is unlocked on entry to this block (the enclosing code released it before the `if (zone->pageable)` test), which is why `doing_alloc` needs an explicit lock/unlock around each assignment rather than a bare store.

**If Task 11 landed its Step 5 reclaim retry**, that retry lives between `zget_space` and the `addr == 0` check. Keep it there and keep `doing_alloc` held across it — a reclaim is exactly when another allocator should wait rather than start its own expansion. Merge the two edits carefully; they touch adjacent lines.

- [ ] **Step 3: Build**

```bash
cd src/kernel-7 && make ARCH=I386 TYPE=RELEASE all OBJROOT=BUILD SYMROOT=BUILD
```

Expected: success.

- [ ] **Step 4: Verify**

Boot a throwaway image, single-user, both workloads three times.

Expected: `zone_expand_races == 0` across all runs, and `zone_expansions` roughly unchanged from baseline. A large *drop* in `zone_expansions` is a good sign — duplicate expansions were inflating it.

Watch for a boot hang. Setting `doing_alloc` sends other allocators down the `assert_wait`/`thread_block_with_continuation` path at `kern/zalloc.c:1481-1494`; if the wakeup is missed, the machine hangs rather than panicking. If it hangs, the wakeup placement is wrong.

- [ ] **Step 5: Record and commit**

Append to `docs/kernel/perf-baseline.md` under `## Task 12: doing_alloc for non-pageable expansion`, then:

```bash
git add src/kernel-7/kern/zalloc.c docs/kernel/perf-baseline.md
git commit -m "zalloc: hold doing_alloc across non-pageable zone expansion"
```

---

## Completion

The work is done when Tasks 1–6 have landed, and each of Tasks 7–12 has either landed or is recorded as dropped with its number and reason in `docs/kernel/perf-baseline.md`.

**Deferred to its own spec, deliberately out of scope:** `CR4.PGE` global-bit kernel mappings and `PSE` 4 MB pages. Also out of scope: `memcpy`/`memset` rewrites, the `MACH_COUNTERS` config mismatch (`conf/MASTER:121` gates on `<count>` while `conf/files:42` expects an option named `mach_counters`, which nothing declares), and scheduler or IPC work.

**Expect modest results.** Tasks 8 and 9 remove real work from a hot path, but on a uniprocessor kernel of this vintage that is unlikely to be user-visible. Task 10 is the only item with a plausibly noticeable effect, and TCG cannot confirm it. Tasks 7, 11, and 12 buy stability and diagnosability, not speed. Four of the six optimizations can legitimately end as "dropped" — that is the harness doing its job, not the plan failing.
