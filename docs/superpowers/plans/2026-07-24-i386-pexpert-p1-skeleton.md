# i386 Platform Expert — Phase 1: Skeleton and Link — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `src/drivers-i386/bus/drvPExpert` as a Kernel Server producing `pexperti386.o`, link it into the i386 kernel, and move the four smallest platform files into it — with the kernel still booting to login identically.

**Architecture:** Mirror `src/drivers-ppc/bus/drvPExpert` exactly: an Aggregate project with one `Kernel Server` tool subproject named `i386`, plus `chips/` and `families/` Component subprojects. The product is a single relocatable linked into `mach_kernel` via the already-architecture-neutral `LIBPEXPERT` machinery. Phase 1 moves only `io_prim.c`, `bios.c`, `bios_asm.s` and `i386_init.c`; nothing is split or restructured yet.

**Tech Stack:** C (NeXT `cc`, `-static -DKERNEL -D_KERNEL`), NeXT `pb_makefiles` (`kernelserver.make`, `subproj.make`, `aggregate.make`), GNU make (`gnumake`) on a Rhapsody DR2 guest, QEMU for boot verification.

## Global Constraints

- **Design spec:** `docs/specs/2026-07-24-i386-platform-expert-design.md`. Read it before starting.
- **The verification loop for this phase is build + boot + diff, not unit tests.** No kernel unit-test harness exists. Real unit tests arrive in Phase 3 for the pure table parsers. Do not invent a kernel test framework.
- **Move discipline:** files move with content changes restricted to `#include`/`#import` lines and the one documented `uxpr.h` fix. Every commit that moves a file must be reviewable with `git diff -M`.
- **No driver source changes.** Driver-visible headers keep their current install paths and contents.
- **Commit messages** start with `pexpert: ` (or `docs: ` for doc-only), describe behavior, one to two lines, no metadata. Per CLAUDE.md §5.
- **All boot testing uses a throwaway copy of `vm/rhapsody.vmdk`,** never the original. Per CLAUDE.md §6.
- Builds run on the Rhapsody guest. Sync with `powershell -File vm\rhap-vm.ps1 sync`; run commands with `powershell -File vm\rhap-vm.ps1 ssh "<cmd>"`. Remote tree root is `/build/source`.
- Kernel build command is `cd /build/source/src/kernel-7 && gnumake kernels`; output is `BUILD/RELEASE_I386/mach_kernel`.

---

### Task 1: Capture the pre-change baseline

Nothing in this plan can be verified without an oracle. This task creates it and changes no source.

**Files:**
- Create: `vm/baseline/README.md`
- Create (untracked build artifacts, do not commit): `vm/baseline/mach_kernel.nm`, `vm/baseline/console.txt`

**Interfaces:**
- Produces: `vm/baseline/mach_kernel.nm` — sorted global symbol list of the pre-change kernel, used as the comparison target by every later task in Phases 1 and 2.

- [ ] **Step 1: Sync the current tree to the guest and build the kernel unmodified**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake kernels"
```

Expected: build completes and `BUILD/RELEASE_I386/mach_kernel` exists.

- [ ] **Step 2: Capture the baseline symbol table**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7/BUILD/RELEASE_I386 && nm -g mach_kernel | sort" > vm/baseline/mach_kernel.nm
```

Expected: a non-empty sorted file. Sanity-check that it contains `_i386_init`, `_intr_initialize`, `_splx` and `_bios32`.

- [ ] **Step 3: Boot the baseline kernel in QEMU on a throwaway image and capture console output**

Copy `vm/rhapsody.vmdk` to `vm/scratch-p1.vmdk` first. Install the freshly built `mach_kernel` onto that image, boot with `start-vm.cmd` pointed at the copy, and capture the full console transcript to `vm/baseline/console.txt` up to and including the login prompt.

Expected: reaches a login prompt. **If it does not, stop — this plan cannot proceed without a working baseline.** Record the failure and escalate rather than continuing.

- [ ] **Step 4: Write the baseline README**

Create `vm/baseline/README.md`:

```markdown
# i386 PExpert verification baseline

Captured before Phase 1 of the i386 platform expert work
(docs/specs/2026-07-24-i386-platform-expert-design.md).

- `mach_kernel.nm` — `nm -g mach_kernel | sort` of the unmodified RELEASE_I386
  kernel. Every phase compares against this; the global symbol set should change
  only by deliberate additions.
- `console.txt` — full boot console transcript to the login prompt.

Both files are build artifacts and are gitignored. Regenerate by following
Task 1 of docs/plans/2026-07-24-i386-pexpert-p1-skeleton.md.
```

- [ ] **Step 5: Gitignore the artifacts and commit the README**

Append to `.gitignore`:

```
vm/baseline/*.nm
vm/baseline/console.txt
vm/scratch-*.vmdk
```

```bash
git add .gitignore vm/baseline/README.md
git commit -m "pexpert: document the i386 boot/symbol verification baseline"
```

---

### Task 2: Create the drvPExpert project skeleton

Build `pexperti386.o` from one file with no dependencies (`io_prim.c`), proving the project type, the makefile wiring and the product name before anything harder moves.

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/Makefile`
- Create: `src/drivers-i386/bus/drvPExpert/PB.project`
- Create: `src/drivers-i386/bus/drvPExpert/dpkg/control`
- Create: `src/drivers-i386/bus/drvPExpert/i386/Makefile`
- Create: `src/drivers-i386/bus/drvPExpert/i386/Makefile.preamble`
- Create: `src/drivers-i386/bus/drvPExpert/i386/Makefile.postamble`
- Create: `src/drivers-i386/bus/drvPExpert/i386/PB.project`
- Create: `src/drivers-i386/bus/drvPExpert/i386/Load_Commands.sect`
- Create: `src/drivers-i386/bus/drvPExpert/i386/README`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/Makefile`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/Makefile.preamble`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/PB.project`
- Create: `src/drivers-i386/bus/drvPExpert/i386/families/Makefile`
- Create: `src/drivers-i386/bus/drvPExpert/i386/families/Makefile.preamble`
- Create: `src/drivers-i386/bus/drvPExpert/i386/families/PB.project`
- Move: `src/kernel-7/machdep/i386/io_prim.c` → `src/drivers-i386/bus/drvPExpert/i386/io_prim.c`

**Interfaces:**
- Produces: `pexperti386.o`, installed to `/usr/local/lib`, containing `_linw` and `_loutw`.

- [ ] **Step 1: Create the aggregate project Makefile**

`src/drivers-i386/bus/drvPExpert/Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = PExpert

PROJECTVERSION = 2.7
PROJECT_TYPE = Aggregate
LANGUAGE = English

TOOLS = i386

OTHERSRCS = Makefile

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = aggregate.make
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

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

- [ ] **Step 2: Create the aggregate PB.project**

`src/drivers-i386/bus/drvPExpert/PB.project`:

```
{
    DYNAMIC_CODE_GEN = YES; 
    FILESTABLE = {HEADERSEARCH = (); OTHER_SOURCES = (Makefile); SUBPROJECTS = (i386); }; 
    LANGUAGE = English; 
    LOCALIZABLE_FILES = {}; 
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles"; 
    NEXTSTEP_BUILDTOOL = /bin/gnumake; 
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac; 
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc; 
    PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make; 
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac"; 
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc"; 
    PROJECTNAME = PExpert; 
    PROJECTTYPE = Aggregate; 
    PROJECTVERSION = 2.7; 
    WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make; 
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe"; 
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc"; 
}
```

- [ ] **Step 3: Create the package control file**

`src/drivers-i386/bus/drvPExpert/dpkg/control`:

```
Package: drvpexpert
Maintainer: RhapsodiOS Developers <https://github.com/RhapsodiOS/RhapsodiOS>
Vendor: RhapsodiOS
Version: 1
Description: i386 Platform Expert
Build-Depends: build-base, drivertools, kernload
```

Deliberately identical in shape to `src/drivers-ppc/bus/drvPExpert/dpkg/control`. Do **not** add `kernel-hdrs`: `build-base` expands to `basedeps[]` (`src/rbuild-1/builder.c:440-441`), which already contains it, and `set_add()` dedupes.

Keeping this dependency list free of anything kernel-produced is load-bearing, not incidental. Phase 3 makes the PExpert the owner and installer of `pexpert_i386.h`, which works only because drvPExpert never depends on the kernel. See "Header ownership" in the Phase 3 plan.

The package name matches the ppc project deliberately: only one architecture's platform expert is ever built into a given repository, so `src/kernel-7/dpkg/control`'s existing `Build-Depends: … drvpexpert …` needs no change.

- [ ] **Step 4: Move io_prim.c into the project**

```bash
git mv src/kernel-7/machdep/i386/io_prim.c src/drivers-i386/bus/drvPExpert/i386/io_prim.c
```

Do not edit its contents. It imports only `<machdep/i386/io_inline.h>`, which the project reaches via `HEADER_PATHS`.

- [ ] **Step 5: Create the kernel-server subproject Makefile**

`src/drivers-i386/bus/drvPExpert/i386/Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = i386

PROJECTVERSION = 2.7
PROJECT_TYPE = Kernel Server
LANGUAGE = English

HFILES =

CFILES = io_prim.c

SUBPROJECTS = chips families

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble\
            Load_Commands.sect README

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = kernelserver.make
NEXTSTEP_INSTALLDIR = /usr/local/lib
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

HEADER_PATHS = -I$(KERNEL_HEADERS)/machdep
NEXTSTEP_PB_CFLAGS = -Wno-format -DDRIVER_PRIVATE -DKERNEL_PRIVATE

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

`-DKERNEL_PRIVATE` is required because `machdep/i386/bios.h` guards its entire contents on it; Task 4 depends on this.

- [ ] **Step 6: Create the preamble, postamble, Load_Commands.sect and README**

`src/drivers-i386/bus/drvPExpert/i386/Makefile.preamble`:

```make
INCLUDED_ARCHS = i386
PRODUCT = $(PRODUCT_DIR)/pexpert$(NAME).o
USE_OBJC_KSINSTANCE = NO
STRIP_ON_INSTALL = NO
```

`src/drivers-i386/bus/drvPExpert/i386/Makefile.postamble`:

```make
PROJTYPE_CFLAGS = $(ARCH_PROJTYPE_FLAGS) -static -DKERNEL -D_KERNEL \
		  -DKERNEL_SERVER_INSTANCE=$(NAME)_instance
```

`src/drivers-i386/bus/drvPExpert/i386/Load_Commands.sect`:

```
# 
# This loadable kernel driver does not use a Mig-generated interface,
# so no handler or server interface is specified.
#
# This driver must be wired down.
WIRE
```

`src/drivers-i386/bus/drvPExpert/i386/README`:

```
i386 platform expert.

See docs/specs/2026-07-24-i386-platform-expert-design.md for the design and the
kernel/PExpert boundary rule: the PExpert owns boot sequencing and hardware that
is a property of the board; the kernel keeps mechanisms that are properties of
the instruction set.

-> Code general to all i386 platforms:
	i386_init.c		pexpert_i386.h
	identify_machine.c
	mem_init.c
	interrupt.c		intr_internal.h
	rtclock.c
	dma_buf.c
	bios.c			bios_asm.s
	apm.c			apm.h
	io_prim.c
	bootinfo.c		pnpbios.c	pnp_resource.c

-> Code specific to a platform generation {atpc, pcipc, acpipc}:
	families/atpc.c		families/atpc.h
	families/pcipc.c	families/pcipc.h
	families/acpipc.c	families/acpipc.h

-> Code that drives a specific chip:
	chips/i8259.c		chips/i8254.c	chips/i8237.c
	chips/mc146818.c	chips/pcicfg.c	chips/bios32.c
	chips/isapnp.c		chips/eisa.c
```

- [ ] **Step 7: Create the kernel-server PB.project**

`src/drivers-i386/bus/drvPExpert/i386/PB.project`:

```
{
    DYNAMIC_CODE_GEN = NO; 
    FILESTABLE = {
        HEADERSEARCH = ("$(KERNEL_HEADERS)/machdep"); 
        H_FILES = (); 
        OTHER_LINKED = (io_prim.c); 
        OTHER_SOURCES = (Makefile.preamble, Makefile, Makefile.postamble, Load_Commands.sect, README); 
        PRECOMPILED_HEADERS = (); 
        PROJECT_HEADERS = (); 
        PUBLIC_HEADERS = (); 
        SUBPROJECTS = (chips, families); 
    }; 
    LANGUAGE = English; 
    LOCALIZABLE_FILES = {}; 
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles"; 
    NEXTSTEP_BUILDTOOL = /bin/gnumake; 
    NEXTSTEP_COMPILEROPTIONS = "-Wno-format -DDRIVER_PRIVATE -DKERNEL_PRIVATE"; 
    NEXTSTEP_INSTALLDIR = /usr/local/lib; 
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac; 
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc; 
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac"; 
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc"; 
    PROJECTNAME = i386; 
    PROJECTTYPE = "Kernel Server"; 
    PROJECTVERSION = 2.7; 
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe"; 
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc"; 
}
```

- [ ] **Step 8: Create the empty chips and families subprojects**

`src/drivers-i386/bus/drvPExpert/i386/chips/Makefile`:

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = chips

PROJECTVERSION = 2.7
PROJECT_TYPE = Component
LANGUAGE = English

HFILES =

CFILES =

OTHERSRCS = Makefile Makefile.preamble

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = subproj.make
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

HEADER_PATHS = -I.. -I$(KERNEL_HEADERS)/machdep
NEXTSTEP_PB_CFLAGS = -static -DKERNEL -D_KERNEL -DKERNEL_PRIVATE -finline -fno-keep-inline-functions

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

`src/drivers-i386/bus/drvPExpert/i386/chips/Makefile.preamble`:

```make
INCLUDED_ARCHS = i386
CODE_GEN_STYLE = STATIC
```

`src/drivers-i386/bus/drvPExpert/i386/chips/PB.project`:

```
{
    DYNAMIC_CODE_GEN = YES; 
    FILESTABLE = {
        HEADERSEARCH = (.., "$(KERNEL_HEADERS)/machdep"); 
        H_FILES = (); 
        OTHER_LINKED = (); 
        OTHER_SOURCES = (Makefile, Makefile.preamble); 
    }; 
    LANGUAGE = English; 
    LOCALIZABLE_FILES = {}; 
    MAKEFILEDIR = "$(MAKEFILEPATH)/pb_makefiles"; 
    NEXTSTEP_BUILDTOOL = /bin/gnumake; 
    NEXTSTEP_COMPILEROPTIONS = "-static -DKERNEL -D_KERNEL -DKERNEL_PRIVATE -finline -fno-keep-inline-functions"; 
    NEXTSTEP_JAVA_COMPILER = /usr/bin/javac; 
    NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc; 
    PDO_UNIX_BUILDTOOL = $NEXT_ROOT/Developer/bin/make; 
    PDO_UNIX_JAVA_COMPILER = "$(NEXTDEV_BIN)/javac"; 
    PDO_UNIX_OBJCPLUS_COMPILER = "$(NEXTDEV_BIN)/gcc"; 
    PROJECTNAME = chips; 
    PROJECTTYPE = Component; 
    PROJECTVERSION = 2.7; 
    WINDOWS_BUILDTOOL = $NEXT_ROOT/Developer/Executables/make; 
    WINDOWS_JAVA_COMPILER = "$(JDKBINDIR)/javac.exe"; 
    WINDOWS_OBJCPLUS_COMPILER = "$(DEVDIR)/gcc"; 
}
```

Create `families/Makefile`, `families/Makefile.preamble` and `families/PB.project` identically, substituting `families` for `chips` in `NAME` and `PROJECTNAME`.

- [ ] **Step 9: Build the project on the guest**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && gnumake"
```

Expected: builds cleanly and produces `pexperti386.o`.

**If `chips` or `families` fail because they contain no source files,** add a single placeholder-free stub instead of leaving them empty: create `chips/chips_stub.c` containing `int i386_pexpert_chips_present = 1;` and list it in `CFILES` and `OTHER_LINKED`. Do the same for `families`. Task 5 of Phase 2 and Task 2 of Phase 3 remove these stubs as real files land.

- [ ] **Step 10: Verify the product name and contents**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && find . -name 'pexperti386.o' -exec nm -g {} \;"
```

Expected: output includes `_linw` and `_loutw`.

- [ ] **Step 11: Commit**

```bash
git add src/drivers-i386/bus/drvPExpert
git add src/kernel-7/machdep/i386/io_prim.c
git commit -m "pexpert: add i386 platform expert project skeleton

Builds pexperti386.o from io_prim.c; chips/ and families/ subprojects are
present but empty."
```

---

### Task 3: Wire the kernel link and the build manifest

**Files:**
- Modify: `src/kernel-7/conf/MASTER.i386` (add a `makeoptions` line beside the existing `RELOC`/`SYMADDR` block)
- Modify: `src/kernel-7/conf/Makefile.i386:70` (the `LDOBJS_SUFFIX` line)
- Modify: `src/kernel-7/conf/files.i386` (remove the `machdep/i386/io_prim.c` line)
- Modify: `src/Manifest`

**Interfaces:**
- Consumes: `pexperti386.o` from Task 2.
- Produces: a `mach_kernel` whose `_linw`/`_loutw` resolve from `pexperti386.o`.

- [ ] **Step 1: Add the LIBPEXPERT makeoption**

In `src/kernel-7/conf/MASTER.i386`, immediately after the existing line

```
makeoptions	SYMADDR = "00780000"				# <intel>
```

add:

```
makeoptions	LIBPEXPERT = "pexperti386.o"			# <intel>
```

This mirrors `src/kernel-7/conf/MASTER.ppc:88`.

- [ ] **Step 2: Append the platform expert to the link line**

In `src/kernel-7/conf/Makefile.i386`, change

```make
LDOBJS_SUFFIX= $(LIBDRIVER_SOURCE)/$(LIBDRIVER) $(LIBOBJC_SOURCE)/$(LIBOBJC)
```

to

```make
LDOBJS_SUFFIX= $(LIBDRIVER_SOURCE)/$(LIBDRIVER) $(LIBOBJC_SOURCE)/$(LIBOBJC) $(LIBPEXPERT_SOURCE)/$(LIBPEXPERT)
```

`LIBPEXPERT_SOURCE` is already defined architecture-neutrally at `src/kernel-7/conf/Makefile.template:195`; do not touch the template.

- [ ] **Step 3: Drop io_prim.c from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete the line:

```
machdep/i386/io_prim.c		standard
```

- [ ] **Step 4: Add both platform experts to the build manifest**

rbuild builds in **Manifest order** and resolves each `Build-Depends` entry to an already-built package file in the repository, hard-failing with "unable to find dependency" if it is absent (`src/rbuild-1/builder.c:521-528`). Order therefore matters for correctness, not tidiness.

`drvpexpert` Build-Depends `kernload`, and `kernel` Build-Depends `drvpexpert`, so the required order is **kernload → drvPExpert → kernel-7**. Today `kernload-1` sits at `src/Manifest:45`, *after* `kernel-7` at line 44 — latent only because drvPExpert is not currently built at all.

Move the `kernload-1` line ahead of `kernel-7`, then add the two platform experts between them:

```
dir     kernload-1            all
dir     drivers-i386/bus/drvPExpert  all
dir     drivers-ppc/bus/drvPExpert   all
dir     kernel-7              all
```

The manifest is otherwise alphabetical; this is a deliberate, commented exception. Add a comment line above the block:

```
# Build order, not alphabetical: kernload -> drvPExpert -> kernel-7.
# kernel Build-Depends drvpexpert; drvpexpert Build-Depends kernload.
```

The ppc entry is included deliberately: the i386 link would otherwise be the only consumer of a build path ppc also needs, and no platform expert has ever been built in-tree on either architecture.

- [ ] **Step 5: Verify rbuild accepts the nested manifest paths**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src && rbuild missing Manifest /tmp/nonexistent-dst"
```

Expected: both `drivers-i386/bus/drvPExpert` and `drivers-ppc/bus/drvPExpert` are listed as missing, with no "unknown source type" or path error.

**If rbuild rejects the nested path,** the `dir` handler at `src/rbuild-1/builder.c:610` and `src/rbuild-1/builder.c:968` assigns `SRCDIR = srcname` verbatim, so the failure will be a missing-directory error from `rsync`. In that case, confirm rbuild's working directory is `src/`; do not change rbuild.

- [ ] **Step 6: Install the platform expert and build the kernel**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && gnumake install DSTROOT=/"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake kernels"
```

Expected: `/usr/local/lib/pexperti386.o` exists, and the kernel links without an undefined-symbol error for `_linw` or `_loutw`.

- [ ] **Step 7: Diff the symbol table against the baseline**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7/BUILD/RELEASE_I386 && nm -g mach_kernel | sort" > vm/scratch-p1.nm
diff vm/baseline/mach_kernel.nm vm/scratch-p1.nm
```

Expected: **no differences.** `_linw` and `_loutw` are still globally defined; only the object file providing them changed.

- [ ] **Step 8: Boot gate**

Install the new kernel onto a fresh copy of `vm/rhapsody.vmdk` and boot it. Expected: reaches a login prompt; console output matches `vm/baseline/console.txt`.

- [ ] **Step 9: Commit**

```bash
git add src/kernel-7/conf/MASTER.i386 src/kernel-7/conf/Makefile.i386 \
        src/kernel-7/conf/files.i386 src/Manifest
git commit -m "pexpert: link pexperti386.o into the i386 kernel

Adds LIBPEXPERT wiring for i386 and builds both platform experts from the
manifest for the first time."
```

---

### Task 4: Move the real-mode BIOS thunk

**Files:**
- Move: `src/kernel-7/machdep/i386/bios.c` → `src/drivers-i386/bus/drvPExpert/i386/bios.c`
- Move: `src/kernel-7/machdep/i386/bios_asm.s` → `src/drivers-i386/bus/drvPExpert/i386/bios_asm.s`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/Makefile` (`CFILES`, `OTHERLINKED`, `OTHERLINKEDOFILES`)
- Modify: `src/drivers-i386/bus/drvPExpert/i386/PB.project` (`OTHER_LINKED`)
- Modify: `src/kernel-7/conf/files.i386` (remove two lines)

`src/kernel-7/machdep/i386/bios.h` **stays in the kernel tree** — it is a contract header, and its contents are guarded by `#ifdef KERNEL_PRIVATE`, which the project's `-DKERNEL_PRIVATE` satisfies.

**Interfaces:**
- Consumes: the project skeleton from Task 2.
- Produces: `_bios32(biosBuf_t *)` defined in `pexperti386.o`. `bios_asm.s` provides `ENTRY(_bios32)`'s underlying assembly routine.

- [ ] **Step 1: Move both files**

```bash
git mv src/kernel-7/machdep/i386/bios.c src/drivers-i386/bus/drvPExpert/i386/bios.c
git mv src/kernel-7/machdep/i386/bios_asm.s src/drivers-i386/bus/drvPExpert/i386/bios_asm.s
```

Do not edit their contents. `bios.c` imports `<machdep/i386/bios.h>` and `<machdep/i386/seg.h>`, both reached via `HEADER_PATHS`.

- [ ] **Step 2: Add them to the project Makefile**

In `src/drivers-i386/bus/drvPExpert/i386/Makefile`, change

```make
CFILES = io_prim.c
```

to

```make
CFILES = bios.c io_prim.c

OTHERLINKED = bios_asm.s

OTHERLINKEDOFILES = bios_asm.o
```

This mirrors how the ppc project carries `clock_speed_asm.s`.

- [ ] **Step 3: Add them to PB.project**

In `src/drivers-i386/bus/drvPExpert/i386/PB.project`, change

```
        OTHER_LINKED = (io_prim.c); 
```

to

```
        OTHER_LINKED = (bios.c, io_prim.c, bios_asm.s); 
```

- [ ] **Step 4: Drop them from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete these two lines:

```
machdep/i386/bios_asm.s		standard
machdep/i386/bios.c		standard
```

- [ ] **Step 5: Build and verify the symbol moved**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && gnumake install DSTROOT=/"
powershell -File vm/rhap-vm.ps1 ssh "nm -g /usr/local/lib/pexperti386.o | grep bios32"
```

Expected: `_bios32` appears as a defined text symbol (`T`).

- [ ] **Step 6: Rebuild the kernel and diff symbols**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake kernels"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7/BUILD/RELEASE_I386 && nm -g mach_kernel | sort" > vm/scratch-p1.nm
diff vm/baseline/mach_kernel.nm vm/scratch-p1.nm
```

Expected: no differences.

- [ ] **Step 7: Boot gate**

Install onto a fresh throwaway image and boot. Expected: login prompt; console matches baseline.

- [ ] **Step 8: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert src/kernel-7/machdep/i386 src/kernel-7/conf/files.i386
git commit -m "pexpert: move the i386 real-mode BIOS thunk into the platform expert"
```

---

### Task 5: Move i386_init.c

The largest move in this phase and the one with a real gotcha. `i386_init.c:51-52` imports `"uxpr.h"` and `"xpr_debug.h"` — headers **generated by the kernel config process into the kernel build directory.** The platform expert builds separately and cannot see them.

**Files:**
- Move: `src/kernel-7/machdep/i386/i386_init.c` → `src/drivers-i386/bus/drvPExpert/i386/i386_init.c`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/i386_init.c:51-52,141-144` (remove the generated-header imports and the block they guard)
- Modify: `src/drivers-i386/bus/drvPExpert/i386/Makefile` (`CFILES`)
- Modify: `src/drivers-i386/bus/drvPExpert/i386/PB.project` (`OTHER_LINKED`)
- Modify: `src/kernel-7/conf/files.i386` (remove one line)

**Interfaces:**
- Produces, all now defined in `pexperti386.o`: `_i386_init`, `_getargs`, `_isargsep`, `_argstrcpy`, `_getval`, `_alloc_cnvmem`, `_alloc_pages`, `_bios_extdata_addr`, `_cpu_sysctl`, and the globals `_master_cpu`, `_cpu_config`, `_mem_region`, `_num_regions`, `_mem_size`, `_virtual_avail`, `_virtual_end`, `_cnvmem`, `_extmem`, `_boot_file`, `_cpu_model`, `_machine`, `_page_size` consumers.

- [ ] **Step 1: Move the file**

```bash
git mv src/kernel-7/machdep/i386/i386_init.c src/drivers-i386/bus/drvPExpert/i386/i386_init.c
```

- [ ] **Step 2: Remove the generated-header imports**

In `src/drivers-i386/bus/drvPExpert/i386/i386_init.c`, delete these two lines (currently 51-52):

```c
#import "uxpr.h"
#import "xpr_debug.h"
```

- [ ] **Step 3: Remove the block they guard and record why**

Replace this block in `i386_init()` (currently lines 140-144):

```c
    // Enable DDM tracing
#if	UXPR && XPR_DEBUG
	IOInitDDM(512);
#endif	UXPR && XPR_DEBUG
```

with:

```c
    /*
     * DDM tracing (IOInitDDM) was conditional on the kernel-config-generated
     * UXPR and XPR_DEBUG headers, which are not visible from the platform
     * expert build.  Both are required to be set; RELEASE_I386 sets UXPR but
     * not XPR_DEBUG, so this was already inactive in the shipping
     * configuration.  DEBUG_I386 loses DDM tracing until the platform expert
     * grows its own debug configuration.
     */
```

This is the one deliberate behavior change in Phase 1. It affects `DEBUG_I386` only. `IOInitDDM` is defined at `src/kernel-7/driverkit/ddm.c:100` and had exactly one caller.

- [ ] **Step 4: Add to the project Makefile and PB.project**

In `Makefile`, change `CFILES` to:

```make
CFILES = bios.c i386_init.c io_prim.c
```

In `PB.project`, change `OTHER_LINKED` to:

```
        OTHER_LINKED = (bios.c, i386_init.c, io_prim.c, bios_asm.s); 
```

- [ ] **Step 5: Drop it from the kernel file list**

In `src/kernel-7/conf/files.i386`, delete the line:

```
machdep/i386/i386_init.c	standard
```

- [ ] **Step 6: Build the platform expert**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert && gnumake install DSTROOT=/"
```

Expected: builds cleanly. Undefined references to kernel symbols (`_pmap_bootstrap`, `_locate_gdt`, `_locate_idt`, `_idt_copy`, `_dbf_init`, `_fp_configure`, `_enable_cache`, `_getlastaddr`, `_vm_set_page_size`, `_machine_slot`) are expected and correct — they resolve at kernel link time.

- [ ] **Step 7: Rebuild the kernel and diff symbols**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake kernels"
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7/BUILD/RELEASE_I386 && nm -g mach_kernel | sort" > vm/scratch-p1.nm
diff vm/baseline/mach_kernel.nm vm/scratch-p1.nm
```

Expected: no differences.

**If the link fails with a duplicate or undefined `_i386_init`,** check ordering: `LDOBJS_SUFFIX` places `pexperti386.o` after the kernel objects, and `start.s` references `_i386_init` from a kernel object. That ordering matches ppc and is expected to work; if it does not, the fix is to move `$(LIBPEXPERT_SOURCE)/$(LIBPEXPERT)` earlier in `LDOBJS_SUFFIX`, not to change `start.s`.

- [ ] **Step 8: Boot gate**

Install onto a fresh throwaway image and boot. Expected: login prompt; console matches `vm/baseline/console.txt`.

This is the phase's real gate — `i386_init()` is the first C function the kernel runs, and it now lives in a separate object.

- [ ] **Step 9: Commit**

```bash
git add -A src/drivers-i386/bus/drvPExpert src/kernel-7/machdep/i386 src/kernel-7/conf/files.i386
git commit -m "pexpert: move i386_init into the platform expert

Drops the DEBUG_I386-only IOInitDDM call, which depended on kernel-config
generated headers the platform expert cannot see."
```

---

### Task 6: Update the boot documentation

`docs/boot/boot-i386.md` traces the boot path with source anchors, and two of those anchors now point at a different project.

**Files:**
- Modify: `docs/boot/boot-i386.md` (the "Architecture entry and early machine setup" and "Mach kernel and virtual-memory initialization" sections)

- [ ] **Step 1: Update the two affected source anchors**

In `docs/boot/boot-i386.md`, every anchor reading `src/kernel-7/machdep/i386/i386_init.c` becomes `src/drivers-i386/bus/drvPExpert/i386/i386_init.c`. There are three such anchors: in the `kernel _start → i386_init` edge description, in the `i386_init()` paragraph under "Architecture entry and early machine setup", and in the `i386 _start → i386_init / pmap_bootstrap` edge under "Mach kernel and virtual-memory initialization".

- [ ] **Step 2: Add a sentence recording the split**

After the `i386_init()` paragraph in "Architecture entry and early machine setup", add:

```markdown
`i386_init()` lives in the i386 platform expert, not the kernel: `start.s` calls `_i386_init`, which resolves into `pexperti386.o`, linked in through `LIBPEXPERT`. The platform expert sequences early boot and calls back into kernel mechanisms (`pmap_bootstrap`, `locate_gdt`, `locate_idt`, `idt_copy`, `dbf_init`), which remain in `machdep/i386`. **Source anchor:** `src/kernel-7/conf/MASTER.i386` `LIBPEXPERT`; `src/kernel-7/conf/Makefile.i386` `LDOBJS_SUFFIX`; `docs/specs/2026-07-24-i386-platform-expert-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/boot/boot-i386.md
git commit -m "docs: retarget i386 boot trace anchors at the platform expert"
```

---

## Phase 1 exit criteria

All must hold before Phase 2 begins:

1. `src/drivers-i386/bus/drvPExpert` builds `pexperti386.o` and installs it to `/usr/local/lib`, and its Manifest entry produces both `drvpexpert` and an (as yet empty) `drvpexpert-hdrs` package — a target of `all` sets both `do_hdr` and `do_bin` (`src/rbuild-1/builder.c:924`).
2. `src/kernel-7` links against it via `LIBPEXPERT`, with `machdep/i386` no longer containing `i386_init.c`, `io_prim.c`, `bios.c` or `bios_asm.s`.
3. `nm -g mach_kernel | sort` is byte-identical to `vm/baseline/mach_kernel.nm`.
4. The kernel boots to a login prompt on a throwaway image, with console output matching `vm/baseline/console.txt`.
5. Both platform experts appear in `src/Manifest` and rbuild resolves their nested paths.
6. `docs/boot/boot-i386.md` anchors are correct.
