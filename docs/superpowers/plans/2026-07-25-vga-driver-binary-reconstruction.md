# VGA Display Driver Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Phases 0 through 2 of the VGA reconstruction — MH_BUNDLE support in binrecon, the `drvVGA` project restructure, a working boot-test gate, the corrected config tables and resources, and a committed source map, divergence document and parity ledger for both `VGA_reloc` and `VGA_psdrvr`.

**Architecture:** Both of our VGA sources are inventions with zero symbol or string overlap with Apple's binaries, so this is a rewrite effort rather than a parity-fix effort. This plan produces everything the rewrite needs and nothing of the rewrite itself: the tooling, the buildable project structure, the proven verification gate, and the complete decompilation evidence. See "Phase 3 boundary" below.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` (angr 9.3.0, jsonschema 4.26.0, pytest 9.1.1), IDA Professional 9.2 (`idat.exe`), Ghidra 12.1 headless on Java 21, Objective-C for Rhapsody DriverKit, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest, QEMU via `vm/qemu-shot.py`.

**Spec:** [2026-07-25-vga-driver-binary-reconstruction-design.md](../specs/2026-07-25-vga-driver-binary-reconstruction-design.md)

## Phase 3 boundary

The spec's Phase 3a and 3b — rewriting `VGA_psdrvr`'s 19 functions and `VGA_reloc`'s 28, including the 10496-byte `_emu486` — are **not** in this plan, and this is a scope decision rather than an omission.

Phase 3's tasks are parameterized on Phase 2's output. The spec's §3.1 states that Apple's translation-unit boundaries, and therefore our source file names, are decided in the report pass from the `__DATA` static ordering. A rewrite task cannot name the file it writes, cite the disassembly it transcribes, or state the function signature it produces until `divergences.md` exists. Writing those tasks now would mean writing placeholders, which is a plan failure.

Once Task 12 lands, write `docs/superpowers/plans/2026-07-25-vga-psdrvr-rewrite.md` and then `…-vga-reloc-rewrite.md` against the committed evidence, one function group per task.

## Global Constraints

Every task's requirements implicitly include this section.

- **Never commit reference binaries, rebuilt artifacts, or analyzer output.** `tools/binrecon/out/` is excluded by `.gitignore:17`. Rebuilt binaries stage to `out/i386/` and stay untracked.
- **Run all `binrecon` commands from the repository root `D:\RhapsodiOS`** with `PYTHONPATH=tools/binrecon`. Analyzer executable paths in profiles are resolved by the host process, so a different cwd breaks them.
- **The Python interpreter is `.venv-binrecon/Scripts/python.exe`.** Not `python`, not `py`.
- **`${BINRECON_REFERENCE}` is the only variable expanded in profile artifact paths.** Export it per shell session; an unset variable is an error.
- **`"Driver Version"` is out of every comparison.** Apple's build emits it and so does ours.
- **Commit messages start with the subsystem**, e.g. `drivers-i386: `, `binrecon: `, `vm: `. One to two lines describing what the change does, not which files moved. No metadata, no `Co-Authored-By`, no `Generated with` trailer.
- **Never advance a ledger status without evidence.** `assembly-matched` means the full disassembly was read instruction by instruction. `control-flow-confirmed` means block shape and call targets were checked but not every instruction. Claiming the stronger status without doing the work is the worst failure mode in this plan. Every function in this plan ends at `unexamined` or `intentional-mismatch`, because none is rewritten yet.
- **Surgical changes only.** `src/driverkit-3`, `src/kernel-7` and the other ten drivers in `src/drivers-i386/video` are out of bounds (spec §1.4).
- **`out/` and `tools/binrecon/out/` already exist.** Do not `mkdir` them.
- **Git Bash mangles absolute POSIX paths passed to Python scripts.** Prefix such commands with `MSYS_NO_PATHCONV=1`, as the `rhap_image.py` invocations below do.

### Reference binaries

External to the repo, under `C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config`:

| Binary | Mach-O type | Size | `__text` | Symbols | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `VGA_reloc` | MH_PRELOAD | 71112 | 18048 | 30 | `489D86652B8718237052F10A551FC6615B4B045F6614DCB790CFB73272C15B96` |
| `VGA_psdrvr` | MH_BUNDLE | 26584 | 7057 | 22 | `E785BA22F1121EAAE140A2340C5068AE1FC23EBC3309F02E7705D8775E47C1F4` |

The SHA-256 in each committed `source-map.json` and `ledger.json` must match its row exactly. `load_source_map` enforces this.

### Guest build host

A separate Rhapsody PPC machine. Connection details are in `vm/vm.conf` (`Host`, `Password`, `RemoteRoot=/build/source`). Reach it with `plink`/`pscp` from `C:\Program Files\PuTTY\`.

Sync **only** `src/drivers-i386/video/drvVGA`. Do not use `vm/rhap-vm.ps1 sync`; it uploads all of `src/` and would carry a concurrent session's uncommitted work onto the shared build host.

The guest's root shell is `tcsh` and its `/bin/sh` is a 1999 Bourne shell: **no `2>&1` inside a remote command string, and no nested double quotes.** Redirect on the local side. Windows checkouts carry CRLF and Rhapsody's `gnumake` treats CR as part of target names, so strip CR from every uploaded `Makefile*` and `*.sh` before building.

---

### Task 1: Teach binrecon's Mach-O reader MH_BUNDLE

`read_macho` accepts only MH_OBJECT and MH_PRELOAD, so it raises `MachOFormatError: unsupported Mach-O file type 8` on `VGA_psdrvr`, blocking `validate`, `analyze`, `source-map` and `parity_check.py` for half this effort (spec §2.8).

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py:12-14` (constants), `tools/binrecon/binrecon/macho.py:131-134` (the gate)
- Modify: `tools/binrecon/tests/macho_fixture.py:5-7` (constants)
- Test: `tools/binrecon/tests/test_macho.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `binrecon.macho.MH_BUNDLE == 8`, and `read_macho(path)` returning a valid `analysis-v1` document for an MH_BUNDLE input. Tasks 2, 8 and 11 depend on this.

- [ ] **Step 1: Add the fixture constant**

In `tools/binrecon/tests/macho_fixture.py`, beside the existing `MH_OBJECT` and `MH_PRELOAD`:

```python
MH_OBJECT = 1
MH_PRELOAD = 5
MH_BUNDLE = 8
```

`build_macho_fixture` already takes `file_type` as a keyword argument, so nothing else in the fixture changes.

- [ ] **Step 2: Write the failing test**

In `tools/binrecon/tests/test_macho.py`, add `MH_BUNDLE` to the `from macho_fixture import (...)` list, then add this test immediately after `test_reads_preloaded_i386_image_with_zero_based_section_addresses`:

```python
def test_reads_bundle_file_type(tmp_path):
    path = write_fixture(tmp_path, build_macho_fixture(file_type=MH_BUNDLE))

    analysis = read_macho(path)

    validate_document("analysis-v1", analysis)
    assert analysis["extensions"]["macho"]["header"]["file_type"] == MH_BUNDLE
    assert [section["name"] for section in analysis["sections"]] == [
        "__TEXT,__text",
        "__DATA,__data",
    ]
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon:tools/binrecon/tests ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py::test_reads_bundle_file_type -v
```

Expected: FAIL with `MachOFormatError: unsupported Mach-O file type 8; expected MH_OBJECT or MH_PRELOAD`.

- [ ] **Step 4: Make the change**

In `tools/binrecon/binrecon/macho.py`, add the constant beside the other two:

```python
MH_OBJECT = 1
MH_PRELOAD = 5
MH_BUNDLE = 8
```

and widen the gate:

```python
    if file_type not in (MH_OBJECT, MH_PRELOAD, MH_BUNDLE):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; "
            "expected MH_OBJECT, MH_PRELOAD or MH_BUNDLE"
        )
```

Nothing else in `macho.py` changes. `LC_LOAD_DYLIB` and `LC_DYSYMTAB` already fall through to `unparsed_load_commands` the way `LC_UNIXTHREAD`'s unknown thread flavor does for `VGA_reloc`, and bundle sections carry `nreloc = 0`, so `_read_relocations` yields nothing.

- [ ] **Step 5: Run the whole Mach-O suite**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon:tools/binrecon/tests ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -v
```

Expected: all PASS. In particular `test_rejects_unsupported_header_identity[12-2-file type]` must still pass — it patches the file type to `MH_OBJECT + 1` (2, MH_EXECUTE), which stays rejected, and matches on the substring `file type`, which the new message retains.

- [ ] **Step 6: Read the real bundle**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
d = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'))
print(d['input']['sha256'])
print(len([s for s in d['symbols'] if s['section'] == '__TEXT,__text']), 'text symbols')
print([s['name'] for s in d['sections']])
"
```

Expected: `E785BA22F1121EAAE140A2340C5068AE1FC23EBC3309F02E7705D8775E47C1F4`, `22 text symbols`, and a section list including `__TEXT,__text`, `__TEXT,__cstring`, `__TEXT,__picsymbol_stub`, `__TEXT,__const`, `__DATA,__data`, `__DATA,__dyld`, `__DATA,__la_symbol_ptr`, `__DATA,__nl_symbol_ptr`, `__DATA,__bss`, `__DATA,__common`.

- [ ] **Step 7: Run the full binrecon suite for regressions**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon:tools/binrecon/tests ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: no new failures relative to the state before Step 4.

- [ ] **Step 8: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/macho_fixture.py tools/binrecon/tests/test_macho.py && git commit -m "binrecon: read MH_BUNDLE images so user-space driver bundles can be analyzed"
```

---

### Task 2: Add the two reference-only profiles

**Files:**
- Create: `tools/binrecon/profiles/vga-reloc.json`
- Create: `tools/binrecon/profiles/vga-psdrvr.json`

**Interfaces:**
- Consumes: `MH_BUNDLE` support from Task 1.
- Produces: profile paths `tools/binrecon/profiles/vga-reloc.json` and `tools/binrecon/profiles/vga-psdrvr.json`, with `output_dir` `../out/vga-reloc` and `../out/vga-psdrvr`. Tasks 7, 8, 10 and 11 use them.

- [ ] **Step 1: Write `tools/binrecon/profiles/vga-reloc.json`**

```json
{
  "schema_version": "profile-v1",
  "name": "drvVGA VGA_reloc reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": true,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/vga-reloc"
}
```

- [ ] **Step 2: Write `tools/binrecon/profiles/vga-psdrvr.json`**

Identical except for two fields:

```json
  "name": "drvVGA VGA_psdrvr reconstruction",
```

```json
  "output_dir": "../out/vga-psdrvr"
```

Keep all three analyzers enabled. If angr or Ghidra fails on the bundle, Task 8 disables the failing one there, with the reason recorded — do not pre-emptively disable either now.

- [ ] **Step 3: Validate both**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/vga-reloc.json
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'
./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/vga-psdrvr.json
```

Expected: each prints the resolved absolute path, size and SHA-256 for its reference and nothing for a rebuilt artifact. The SHA-256 values must match the Global Constraints table exactly. The psdrvr run is the first proof that Task 1 works end to end.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/profiles/vga-reloc.json tools/binrecon/profiles/vga-psdrvr.json && git commit -m "binrecon: add reference-only profiles for VGA_reloc and VGA_psdrvr"
```

---

### Task 3: Prove the boot-test gate against the stock driver

The spec's largest stated risk is that the gating boot test of Phase 3 may not be reachable at all. Settle it now, against the *stock* `VGA.config` already inside the guest image, so the rewrite inherits a known-working gate and a known expected output rather than discovering the problem after 47 functions are written.

The guest image's `/private/Drivers/i386/VGA.config` holds byte-identical copies of both reference binaries — `VGA_reloc` at 71112 bytes and `VGA_psdrvr` at 26584 — so a successful boot here is a recording of what Apple's driver prints, which is exactly the Phase 3 target.

**Files:**
- Create: `vm/shots-vga-stock/` (untracked output; `vm/shots-*/` is gitignored)
- Create: `docs/drivers/drvVGA-boot-gate.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `docs/drivers/drvVGA-boot-gate.md`, recording the exact `set-key` and `qemu-shot.py` invocations that put the VGA driver on screen and the serial lines it produces. Phase 3's verification cites this file.

- [ ] **Step 1: Confirm what the image ships**

```bash
cd /d/RhapsodiOS/vm && MSYS_NO_PATHCONV=1 python rhap_image.py golden.img ls /private/Drivers/i386/VGA.config
MSYS_NO_PATHCONV=1 python rhap_image.py golden.img slack /private/Drivers/i386/VGA.config/VGA_reloc
MSYS_NO_PATHCONV=1 python rhap_image.py golden.img cat /private/Drivers/i386/System.config/Instance0.table
```

Expected: `VGA_reloc`, `VGA_psdrvr`, `VGA`, `Default.table`, `SVGABIOS.table` and `English.lproj`; `71112 71680 568` from `slack`; and an `Instance0.table` whose `"Active Drivers"` line reads `"CirrusLogicGD5434DisplayDriver BusMouse NE2K"`.

Which drivers load is decided by that key, not by what is present in `/private/Drivers/i386` (`vm/README.md`, "Things that are not obvious").

- [ ] **Step 2: Reset the working image**

```bash
cd /d/RhapsodiOS/vm && cmd //c reset-image.cmd
```

Expected: `work\test.img` recreated from `golden.img`. Only `vm/work/test.img` may be booted or written; `rhap_inject.py` and `qemu-shot.py` both refuse any other path.

- [ ] **Step 3: Make VGA the active display driver**

```bash
cd /d/RhapsodiOS/vm && MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img set-key /private/Drivers/i386/System.config/Instance0.table "Active Drivers" "VGA BusMouse NE2K"
MSYS_NO_PATHCONV=1 python rhap_image.py work/test.img cat /private/Drivers/i386/System.config/Instance0.table
```

Expected: the `cat` shows `"Active Drivers" = "VGA BusMouse NE2K";`. The new value is 17 characters against the old 43, so it fits the existing allocation and `set-key` cannot be refused for size here.

- [ ] **Step 4: Boot and capture**

```bash
cd /d/RhapsodiOS/vm && python qemu-shot.py work/test.img shots-vga-stock --at 20,45,75 --keys "mach_kernel -v
"
```

The trailing newline inside `--keys` is required: typing at the boot prompt cancels the 10-second auto-boot, so a command line without an explicit Return sits at the prompt forever.

Expected: `shots-vga-stock/shot-20s.png`, `shot-45s.png`, `shot-75s.png` and `shots-vga-stock/serial.log`.

- [ ] **Step 5: Read the gate out of the serial log**

```bash
cd /d/RhapsodiOS/vm && grep -n "VGADisplay\|IOVGADisplay\|vidBIOS\|Mode Selected" shots-vga-stock/serial.log
```

Expected: `VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)`. That string is in the reference's `__cstring` and is the Phase 3 gate.

If it does not appear, do not proceed to Step 6 and do not paper over it. Diagnose with the screenshots and the full `serial.log`, and record the outcome in Step 6's document either way — a gate that cannot be reached is a finding that changes Phase 3's verification, and the spec's §6 anticipates it becoming a Phase 0 item.

- [ ] **Step 6: Record the procedure**

Write `docs/drivers/drvVGA-boot-gate.md` containing: the three commands from Steps 2 through 4 verbatim; the `"Active Drivers"` value before and after; every `VGADisplay`-prefixed line the run produced, quoted exactly; and a short statement of what was and was not observed. If Step 5 found nothing, state that plainly along with what the screenshots showed, and note that Phase 3's gating verification is blocked until it is resolved.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS && git add docs/drivers/drvVGA-boot-gate.md && git commit -m "vm: record the boot-test gate for the VGA display driver"
```

---

### Task 4: Restructure the project to drvVGA

`src/drivers-i386/video/vga` is the only driver in `video/` still on the flat legacy layout. On `tool.make` the Kernel Server project type never runs, so no `Loaded Server` sections are emitted and `VGA_psdrvr` is never built at all (spec §2.6).

Sources move unchanged. This task alters build scaffolding only — not one line of C or Objective-C — so that Task 5's baseline build measures today's code in tomorrow's structure.

**Files:**
- Move: `src/drivers-i386/video/vga/` → `src/drivers-i386/video/drvVGA/`
- Move: `VGA_reloc.tproj/{VGA.h,VGA.m,VGAConfigTable.m,VGAModes.c,VGAModes.h,VGASetMode.m,Load_Commands.sect}` → `drvVGA/VGA.drvproj/VGA.lksproj/`
- Move: `VGA_psdrvr/{VGAPSDriver.c,VGAPSDriver.h}` → `drvVGA/VGA.drvproj/VGA_psdrvr.tproj/`
- Move: `Default.table`, `SVGABIOS.table`, `English.lproj/` → `drvVGA/VGA.drvproj/`
- Delete: `Display.modes`
- Create: `drvVGA/{Makefile,Makefile.preamble,Makefile.postamble}`, `drvVGA/VGA.drvproj/{Makefile,Makefile.preamble,Makefile.postamble,DriverInfo}`, `drvVGA/VGA.drvproj/VGA.lksproj/{Makefile,Makefile.preamble,Makefile.postamble}`, `drvVGA/VGA.drvproj/VGA_psdrvr.tproj/{Makefile,Makefile.preamble,Makefile.postamble}`
- Modify: `src/drivers-i386/README`

**Interfaces:**
- Consumes: nothing.
- Produces: the paths every later task uses —
  `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/` (kernel sources, `NAME = VGA`, builds `VGA_reloc`),
  `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/` (bundle sources, `NAME = VGA_psdrvr`),
  `src/drivers-i386/video/drvVGA/VGA.drvproj/{Default.table,SVGABIOS.table}`,
  `src/drivers-i386/video/drvVGA/reconstruction/`.

- [ ] **Step 1: Move the tree with git mv**

```bash
cd /d/RhapsodiOS/src/drivers-i386/video
git mv vga drvVGA
cd drvVGA
mkdir -p VGA.drvproj/VGA.lksproj VGA.drvproj/VGA_psdrvr.tproj reconstruction
git mv VGA_reloc.tproj/VGA.h VGA_reloc.tproj/VGA.m VGA_reloc.tproj/VGAConfigTable.m VGA_reloc.tproj/VGAModes.c VGA_reloc.tproj/VGAModes.h VGA_reloc.tproj/VGASetMode.m VGA_reloc.tproj/Load_Commands.sect VGA.drvproj/VGA.lksproj/
git mv VGA_psdrvr/VGAPSDriver.c VGA_psdrvr/VGAPSDriver.h VGA.drvproj/VGA_psdrvr.tproj/
git mv Default.table SVGABIOS.table English.lproj VGA.drvproj/
git rm Display.modes
git rm VGA_reloc.tproj/Makefile VGA_reloc.tproj/Makefile.preamble VGA_reloc.tproj/Makefile.postamble
git rm VGA_psdrvr/Makefile VGA_psdrvr/Makefile.preamble VGA_psdrvr/Makefile.postamble
```

`Display.modes` goes because Apple's `VGA.config` contains none (spec §2.5). The four old Makefiles go because Tasks 4.2 through 4.5 replace them.

- [ ] **Step 2: Write `drvVGA/Makefile` (Aggregate)**

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = VGA

PROJECTVERSION = 2.6
PROJECT_TYPE = Aggregate
LANGUAGE = English

LOCAL_RESOURCES = Localizable.strings

GLOBAL_RESOURCES = Default.table

TOOLS = VGA.drvproj

OTHERSRCS = Makefile Makefile.postamble Makefile.preamble

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = aggregate.make
SOURCEMODE = 444

BUNDLE_EXTENSION = config

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

`drvVGA/Makefile.preamble`:

```make
INSTALL_EXAMPLE = YES

LOCALMAKEFILEDIR = /LocalDeveloper/Makefiles/driverkit
LOCALMAKEFILE = Makefile.local_preamble
-include $(LOCALMAKEFILEDIR)/$(LOCALMAKEFILE)

BUNDLE_EXTENSION = config
```

`drvVGA/Makefile.postamble`:

```make
-include $(LOCALMAKEFILEDIR)/Makefile.local_postamble
include /NextDeveloper/Makefiles/driverkit/Makefile.bundle_postamble
```

- [ ] **Step 3: Write `drvVGA/VGA.drvproj/Makefile` (Driver)**

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = VGA

PROJECTVERSION = 2.6
PROJECT_TYPE = Driver
LANGUAGE = English

GLOBAL_RESOURCES = Default.table SVGABIOS.table

LOCAL_RESOURCES = Localizable.strings SVGABIOS.strings

TOOLS = VGA.lksproj VGA_psdrvr.tproj

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble DriverInfo

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = driver.make
NEXTSTEP_INSTALLDIR = $(NEXT_ROOT)/private/Drivers
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)
BUNDLE_EXTENSION = config

FRAMEWORK_PATHS = -F$(SYSTEM_LIBRARY_DIR)/PrivateFrameworks\
                  -F/System/Library/PrivateFrameworks

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

`TOOLS` naming both subprojects is what builds `VGA_psdrvr` for the first time. `SVGABIOS.strings` is listed now and created in Task 6; until then the resource is simply absent, which does not fail the build.

Create empty `drvVGA/VGA.drvproj/Makefile.preamble` and `drvVGA/VGA.drvproj/Makefile.postamble` — `drvS3Generic` has both empty at this level, and the `-include` lines require nothing of them.

`drvVGA/VGA.drvproj/DriverInfo`:

```
#
# used by geninfo: DRIVER_NAME is the names which appears on the
# installer window
#
DRIVER_NAME="VGA"
DEFAULT_DRIVER_VERSION="5.01";
```

`5.01` is the `"Version"` both reference tables carry.

- [ ] **Step 4: Write `drvVGA/VGA.drvproj/VGA.lksproj/Makefile` (Kernel Server)**

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = VGA

PROJECTVERSION = 2.6
PROJECT_TYPE = Kernel Server
LANGUAGE = English

CLASSES = VGA.m VGAConfigTable.m VGASetMode.m

CFILES = VGAModes.c

HFILES = VGA.h VGAModes.h

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble Load_Commands.sect

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = kernelserver.make
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

`NAME = VGA` under `kernelserver.make` is what produces `VGA_reloc`, matching Apple's filename. Create empty `Makefile.preamble` and `Makefile.postamble` beside it.

`Unload_Commands.sect` is **not** listed in `OTHERSRCS` yet; Task 6 creates the file and adds the word, because `kernelserver.make` emits that section purely from the filename appearing in `OTHERSRCS`.

- [ ] **Step 5: Write `drvVGA/VGA.drvproj/VGA_psdrvr.tproj/Makefile` (bundle)**

```make
#
# Generated by the NeXT Project Builder.
#
# NOTE: Do NOT change this file -- Project Builder maintains it.
#
# Put all of your customizations in files called Makefile.preamble
# and Makefile.postamble (both optional), and Makefile will include them.
#

NAME = VGA_psdrvr

PROJECTVERSION = 2.6
PROJECT_TYPE = Bundle
LANGUAGE = English

CFILES = VGAPSDriver.c

HFILES = VGAPSDriver.h

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = bundle.make
BUNDLE_EXTENSION =
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
```

The old `VGA_psdrvr/Makefile.postamble` installed a `VGA.ppd` that does not exist in this repository and has no counterpart in Apple's `VGA.config` (spec §2.2); it is not carried over. Create empty `Makefile.preamble` and `Makefile.postamble`.

Apple's `VGA_psdrvr` is an MH_BUNDLE with no `.config` wrapper, hence the empty `BUNDLE_EXTENSION`. If `bundle.make` in the guest's `pb_makefiles` produces a wrapper directory anyway, record the observed output in Task 5's build note and leave the fix to that task — do not guess a different project type here.

- [ ] **Step 6: Update the README**

In `src/drivers-i386/README`, replace the `vga` line in the `video` section with:

```
 * drvVGA - reconstruction in progress
```

- [ ] **Step 7: Verify the tree**

```bash
cd /d/RhapsodiOS && find src/drivers-i386/video/drvVGA -type f | sort
git status --short src/drivers-i386/video
```

Expected: exactly the files this task lists, no `VGA_reloc.tproj` or `VGA_psdrvr` directory remaining, no `Display.modes`, and `git status` showing renames (`R`) rather than delete-plus-add for all seven source files, both tables and the `English.lproj` contents.

- [ ] **Step 8: Verify no source content changed**

```bash
cd /d/RhapsodiOS && git diff --cached -M --stat -- src/drivers-i386/video/drvVGA src/drivers-i386/video/vga
```

Both the old and the new path must be in the pathspec. Restricting it to `drvVGA` alone leaves git unable to pair the deleted old paths with the added new ones, so it reports every file as a pure addition and the check silently proves nothing.

Expected: every `.m`, `.c`, `.h`, `.table`, `.strings`, `.rtf` and `.sect` entry shows a pure rename with `0` insertions and `0` deletions. Any content change here is a defect — Task 6 is where content changes.

- [ ] **Step 9: Commit**

```bash
cd /d/RhapsodiOS && git add -A src/drivers-i386/video/drvVGA src/drivers-i386/README && git commit -m "drivers-i386: restructure the VGA driver into drvVGA with drvproj and lksproj subprojects"
```

---

### Task 5: Write the build harness and establish the baseline

The driver has never been built in this tree. A pre-existing failure must not be attributable to later work.

**Files:**
- Create: `vm/build-i386-vga.sh`
- Create: `docs/drivers/drvVGA-baseline-build.md`

**Interfaces:**
- Consumes: the project paths from Task 4.
- Produces: `vm/build-i386-vga.sh`, invoked in the guest as `sh /build/source/vm/build-i386-vga.sh`, staging to `/build/out/i386/drvVGA/VGA.config/`. Phase 3's verification uses it unchanged.

- [ ] **Step 1: Write `vm/build-i386-vga.sh`**

```sh
#!/bin/sh
# Build the VGA display driver under reconstruction; stage VGA.config.
# Accept the run when both VGA_reloc and VGA_psdrvr exist, even if a
# packaging rule later in the makefile exits nonzero.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
SRC=/build/source/src/drivers-i386/video/drvVGA
PROJ=$SRC/VGA.drvproj
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

if [ ! -f "$SRC/Makefile" ]; then
	echo "MISSING $SRC/Makefile" >&2
	exit 1
fi

echo "======== build VGA (drvVGA) ========"
cd "$SRC"
find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
while read f; do
	tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
done

gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
ec=$?
echo "make exit=$ec for VGA"

reloc=`find "$SRC" -name VGA_reloc -type f 2>/dev/null | head -1`
psdrvr=`find "$SRC" -name VGA_psdrvr -type f 2>/dev/null | head -1`

fail=0
if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
	echo "FAILED: no VGA_reloc" >&2
	fail=1
fi
if [ -z "$psdrvr" ] || [ ! -f "$psdrvr" ]; then
	echo "FAILED: no VGA_psdrvr" >&2
	fail=1
fi
if [ $fail -ne 0 ]; then
	find "$SRC" \( -name '*reloc*' -o -name '*psdrvr*' -o -name '*.config' \) 2>/dev/null | head -40 >&2 || true
	echo "=== vga done fail=1 ==="
	exit 1
fi

file "$reloc"
file "$psdrvr"

dst="$OUT/drvVGA/VGA.config"
rm -rf "$dst"
mkdir -p "$dst"
cp -p "$reloc" "$dst/"
cp -p "$psdrvr" "$dst/"
for f in "$PROJ"/*.table; do
	[ -f "$f" ] || continue
	cp -p "$f" "$dst/"
done
if [ -f "$PROJ/DriverInfo" ]; then
	cp -p "$PROJ/DriverInfo" "$dst/"
fi
if [ -d "$PROJ/English.lproj" ]; then
	cp -rp "$PROJ/English.lproj" "$dst/"
fi
vgabundle=`find "$SRC" -name VGA -type f 2>/dev/null | head -1`
if [ -n "$vgabundle" ] && [ -f "$vgabundle" ]; then
	cp -p "$vgabundle" "$dst/"
	echo "staged version bundle VGA"
fi

cat > "$OUT/drvVGA/README.txt" <<EOF
i386 VGA (drvVGA)
-----------------
VGA_reloc is the i386 loadable kernel server (kl_ld).
VGA_psdrvr is the user-space Window Server bundle.
make exit status was: $ec
EOF

echo "staged $dst"
ls -la "$dst"
echo "=== vga done fail=0 ==="
exit 0
```

`set -e` is deliberately not used: Rhapsody's 1999 Bourne `/bin/sh` applies it to any function returning nonzero, including one called from an `if` condition.

- [ ] **Step 2: Sync to the guest**

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" src/drivers-i386/video/drvVGA root@$HOST:/build/source/src/drivers-i386/video/
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" vm/build-i386-vga.sh root@$HOST:/build/source/vm/
```

- [ ] **Step 3: Build**

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'tr -d "\r" < /build/source/vm/build-i386-vga.sh > /tmp/br && mv /tmp/br /build/source/vm/build-i386-vga.sh; sh /build/source/vm/build-i386-vga.sh' > /tmp/vga-build.log 2>&1
echo "EXIT=$?"
tail -20 /tmp/vga-build.log
```

Expected on success: `EXIT=0` and a final line `=== vga done fail=0 ===`, with `ls -la` above it showing `VGA_reloc`, `VGA_psdrvr`, `Default.table`, `SVGABIOS.table`, `DriverInfo` and `English.lproj`.

Our build is unstripped, so both binaries will be substantially larger than Apple's 71112 and 26584 bytes. That is expected and is not a failure.

- [ ] **Step 4: Copy the staged artifacts back to the host**

Every later host-side check reads them from `out/i386/`, which is untracked.

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
mkdir -p out/i386/drvVGA
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" root@$HOST:/build/out/i386/drvVGA/VGA.config out/i386/drvVGA/
ls -la out/i386/drvVGA/VGA.config
```

Expected: `VGA_reloc` and `VGA_psdrvr` present on the host, both larger than Apple's 71112 and 26584 bytes because our build is unstripped.

- [ ] **Step 5: Record the baseline parity numbers**

This is not a gate — it is the number the rewrite has to improve, and it is also the first exercise of Task 1's MH_BUNDLE support through `parity_check.py` rather than through `read_macho` directly.

```bash
cd /d/RhapsodiOS
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_reloc" \
  out/i386/drvVGA/VGA.config/VGA_reloc
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_psdrvr" \
  out/i386/drvVGA/VGA.config/VGA_psdrvr
```

Each prints `missing_strings`, `missing_symbols`, `extra_strings`, `extra_symbols` with counts and exits 1 when either `missing_` list is non-empty. Exit 1 is the expected outcome for both: our sources share no string or symbol with Apple's, so essentially every reference string and symbol is missing. Record the four counts per binary.

If the psdrvr invocation raises `MachOFormatError`, Task 1 is incomplete — `parity_check.py` calls `read_macho` twice per binary.

- [ ] **Step 6: Record the baseline**

Write `docs/drivers/drvVGA-baseline-build.md` with: the exact commands from Steps 2 and 3; `EXIT`; the `make exit=` line; the sizes of both staged binaries; the four parity counts per binary from Step 5; and every compiler warning or error, quoted. If `bundle.make` produced a wrapper directory around `VGA_psdrvr` rather than a bare file (Task 4 Step 5), record what it produced and what the harness found.

- [ ] **Step 7: If the baseline fails, repair it in its own commit**

A build failure here is pre-existing breakage, not a divergence. Fix it, commit that fix separately with a message naming the compile error, then re-run Steps 2 through 6 and record the passing baseline. Do not fold a build repair into any later task.

- [ ] **Step 8: Commit**

```bash
cd /d/RhapsodiOS && git add vm/build-i386-vga.sh docs/drivers/drvVGA-baseline-build.md && git commit -m "vm: add the drvVGA build harness and record its baseline"
```

---

### Task 6: Table and resource pass

Every fix here rests on a diff of our checked-in file against Apple's checked-in file, which is stronger evidence than a decompilation, so no ledger entry authorises them (spec §4.2). This is the complete list; nothing else changes.

The spec's §4.2 item 5 — deleting `Display.modes`, which Apple's `VGA.config` does not contain — landed in Task 4 Step 1 instead, because it is a file removal that the restructure had to resolve anyway. It is not repeated here.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/Default.table`
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/SVGABIOS.table`
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/English.lproj/Localizable.strings`
- Create: `src/drivers-i386/video/drvVGA/VGA.drvproj/English.lproj/SVGABIOS.strings`
- Create: `src/drivers-i386/video/drvVGA/VGA.drvproj/English.lproj/Help/VGA.rtfd/TXT.rtf`
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/Load_Commands.sect`
- Create: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/Unload_Commands.sect`
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/Makefile` (one word in `OTHERSRCS`)

**Interfaces:**
- Consumes: the paths from Task 4.
- Produces: config tables that differ from Apple's only in `"Driver Version"`, and a `.lksproj` that emits a 164-byte `Loaded Server,Load Commands` and a 67-byte `Loaded Server,Unload Commands`.

- [ ] **Step 1: Fix `Default.table`**

Two edits, nothing else:

```
"I/O Ports" = "0x3b4-0x3b5 0x3b8-0x3bb 0x3c0-0x3cf 0x3d4-0x3dc 0x46E8-0x46E9";
```

```
"Display Mode" = "Height: 480 Width: 640 Refresh: 60Hz ColorSpace: BW:2";
```

`0x3d4-0x3d6` becomes `0x3d4-0x3dc`; `BW.2` becomes `BW:2`.

- [ ] **Step 2: Fix `SVGABIOS.table`**

The same two edits with `Height: 600 Width: 800`, plus two keys the file lacks entirely. Insert them immediately after the `"Display Mode"` line, which is where Apple's copy has them:

```
"Display Mode" = "Height: 600 Width: 800 Refresh: 60Hz ColorSpace: BW:2";
"SVGA Mode" = "Yes";
"SVGA VESA BIOS Mode" = "0x6a";
```

`SVGA Mode`, `Yes` and `SVGA VESA BIOS Mode` are all literals in the reference's `__cstring`, so the driver reads both keys by name; without them this table cannot select an SVGA mode at all.

- [ ] **Step 3: Replace `English.lproj/Localizable.strings`**

Entire new content, replacing the invented keys:

```
"VGA" = "Default VGA";
"Long Name" = "Default VGA Adapter";
```

- [ ] **Step 4: Create `English.lproj/SVGABIOS.strings`**

```
"VGA" = "Generic SVGA";
"Long Name" = "Generic SVGA Adapter";
```

- [ ] **Step 5: Create the Help stub**

`Default.table` names `"Help File" = "VGA.rtfd"` and we ship no such file. Create `English.lproj/Help/VGA.rtfd/TXT.rtf`:

```rtf
{\rtf1\ansi{\fonttbl\f0\fswiss Helvetica;}
\pard\f0\fs24 VGA display driver.\
\
This is a placeholder. Apple's shipped Help text is not reproduced here; see
reconstruction/divergences.md.\
}
```

Reproducing Apple's Help text is not reconstruction (spec §4.2). `English.lproj/Info.rtf` is left alone and recorded as a divergence in Task 9.

- [ ] **Step 6: Fix `Load_Commands.sect`**

Our file is 163 bytes; Apple's section is 164. The single difference is a trailing space on the first line. Replace the file with exactly:

```
# 
# This loadable kernel driver does not use a Mig-generated interface,
# so no handler or server interface is specified.
#
# This driver must be wired down.
WIRE
```

The first line is `#` followed by one space. Verify:

```bash
cd /d/RhapsodiOS && wc -c src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/Load_Commands.sect
```

Expected: `164`.

- [ ] **Step 7: Create `Unload_Commands.sect`**

Apple's section is 67 bytes:

```
# Termination

#CALL		stub_terminate		0
#CALL		stub_terminate		1


```

The indentation is tabs, and the file ends with two blank lines after the second `#CALL`. Verify:

```bash
cd /d/RhapsodiOS && wc -c src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/Unload_Commands.sect
```

Expected: `67`. If it differs, adjust the trailing blank lines — `kernelserver.make` copies the file verbatim, so the byte count is the whole specification.

- [ ] **Step 8: Name the new section file in the Makefile**

`kernelserver.make` emits each `Loaded Server` section purely from whether a filename appears in `OTHERSRCS`. In `VGA.lksproj/Makefile`:

```make
OTHERSRCS = Makefile.preamble Makefile Makefile.postamble Load_Commands.sect\
            Unload_Commands.sect
```

- [ ] **Step 9: Verify the tables against the reference**

```bash
cd /d/RhapsodiOS && for t in Default SVGABIOS; do
  echo "=== $t.table ==="
  diff <(grep -v '"Driver Version"' "src/drivers-i386/video/drvVGA/VGA.drvproj/$t.table") \
       <(grep -v '"Driver Version"' "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/$t.table")
done
```

Expected: no output for either, apart from whitespace where Apple's copy runs `"Help File"` and `"Server Name"` together on one line. If that line-joining is the only difference, record it in Task 9 and leave our formatting readable — it changes no key or value.

- [ ] **Step 10: Verify the strings files byte for byte**

```bash
cd /d/RhapsodiOS && for s in Localizable SVGABIOS; do
  diff "src/drivers-i386/video/drvVGA/VGA.drvproj/English.lproj/$s.strings" \
       "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/English.lproj/$s.strings" && echo "$s.strings OK"
done
```

Expected: `Localizable.strings OK` and `SVGABIOS.strings OK`.

- [ ] **Step 11: Rebuild and confirm the section sizes**

Re-run Task 5 Steps 2 through 4 — sync, build, copy back — then check the built sections on the host:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
d = read_macho(Path('out/i386/drvVGA/VGA.config/VGA_reloc'))
for s in d['sections']:
    if s['name'].startswith('Loaded Server'):
        print(s['name'], s['size'])
"
```

Expected: `Loaded Server,Load Commands 164` and `Loaded Server,Unload Commands 67`. `Server Name`, `Instance Var` and `Server Version` also appear; record their sizes for Task 9 and compare against the reference's 3, 12 and 1.

If the built `Load Commands` is not 164, the `.sect` file did not reach the linker; check `OTHERSRCS` before changing the file.

- [ ] **Step 12: Commit**

```bash
cd /d/RhapsodiOS && git add -A src/drivers-i386/video/drvVGA && git commit -m "drvVGA: correct the config tables, localized strings and loadable-server sections against Apple's"
```

---

### Task 7: Report pass — analyze and map VGA_reloc

**Files:**
- Create: `src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/source-map.json`
- Output (untracked): `tools/binrecon/out/vga-reloc/`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/vga-reloc.json` from Task 2.
- Produces: `tools/binrecon/out/vga-reloc/published/analysis-reference-ida.json` (IDA is authoritative for the function partition) and a `source-map-v1` document that `load_source_map` accepts. Tasks 9 and 10 read both.

- [ ] **Step 1: Analyze**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon analyze \
  --profile tools/binrecon/profiles/vga-reloc.json \
  --output tools/binrecon/out/vga-reloc/run-summary.json
```

**Expected: exit 1, and that is success here.** `analyze` returns 0 only when the profile's acceptance level passes, and `normalized-functions` acceptance compares a reference against a *rebuilt* artifact. This is a reference-only profile, so acceptance can never pass and the last line always reads `normalized-functions=FAIL`. Do not add a `rebuilt` key to make it go away.

- [ ] **Step 2: Gate on the summary, not the exit code**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/vga-reloc/run-summary.json'))
assert d['complete'] is True, d
assert d['consensus']['reference'] is not None, d
print('complete:', d['complete'], 'sha:', d['reference_sha256'])
"
ls tools/binrecon/out/vga-reloc/published/
```

Expected: `complete: True`, the SHA-256 `489D86652B8718237052F10A551FC6615B4B045F6614DCB790CFB73272C15B96`, and four files — `analysis-reference-ida.json`, `-ghidra.json`, `-angr.json`, `consensus-reference.json`.

A run that writes `complete: false` and no reference consensus is a genuine failure. Do not reuse an earlier run's output as evidence.

Two adapter behaviours are automatic and are not errors: Ghidra first tries its Mach-O loader and falls back to deterministic raw i386 import when that loader rejects a legacy input, and angr's `CFGFast` records unresolved indirect control flow as CFG errors. Neither means a function is absent.

If Ghidra aborts normalization with `Ghidra relocation operand metadata is ambiguous` (`normalize.py:432`), set `analyzers.ghidra.enabled` to `false` in `tools/binrecon/profiles/vga-reloc.json`, re-run, and record the reduced analyzer set as a stated limitation of this binary's evidence in Task 9. Three input drivers already run two analyzers for exactly this reason. Do not re-enable it to "fix" the run.

- [ ] **Step 3: Build the source map**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/vga-reloc/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj \
  --repo-root . \
  --output src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/source-map.json
```

`source_sites` globs `*.m` and `*.c` in `--source-dir` non-recursively, which covers all four current kernel sources.

- [ ] **Step 4: Hand-resolve the residue**

Every one of the 30 reference functions must land in exactly one of `mapped`, `unmapped`, `boundary_disputed`, `duplicate_candidates`. Entries within each bucket must be sorted by `(address, reference_names)`; `validate_source_map_semantics` rejects any other order.

For this binary the expected outcome is that **all 30 land in `unmapped`**: 28 because our source has no counterpart for them (spec §2.1), and `+[VGAKernelServerInstance kernelServerInstance]` and `+[VGAVersion driverKitVersionForVGA]` because the Kernel Server project type generates them (spec §2.9).

A function the tool places in `mapped` is a false positive from a coincidental name match and must be moved to `unmapped` — our `VGA` class shares no method name with Apple's `IOVGADisplay`, so any match is spurious. Record any such case in Task 9.

Data symbols outside `__TEXT,__text` do not appear in the source map at all.

- [ ] **Step 5: Validate the source map**

```bash
cd /d/RhapsodiOS && cat > /tmp/check_map.py <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, 'tools/binrecon')
from binrecon.schema import load_json, load_source_map
name, binary = sys.argv[1], sys.argv[2]
analysis = load_json(Path(f'tools/binrecon/out/{name}/published/analysis-reference-ida.json'))
load_source_map(
    Path(f'src/drivers-i386/video/drvVGA/reconstruction/{binary}/source-map.json'),
    reference_analysis=analysis,
    repo_root=Path.cwd(),
)
print('source map OK')
PY
./.venv-binrecon/Scripts/python.exe /tmp/check_map.py vga-reloc VGA_reloc
```

Expected: `source map OK`. Any `SemanticValidationError` names the exact failure — a missing address, a wrong size, a source line outside the function, a partition gap. Fix the map; do not weaken the check.

- [ ] **Step 6: Confirm the count**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/source-map.json'))
total = sum(len(m[k]) for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed'))
print({k: len(m[k]) for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed')}, 'total', total)
assert total == 30, total
"
```

Expected: `total 30`.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/source-map.json && git commit -m "drvVGA: add the VGA_reloc source map"
```

---

### Task 8: Report pass — analyze and map VGA_psdrvr

**Files:**
- Create: `src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json`
- Output (untracked): `tools/binrecon/out/vga-psdrvr/`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/vga-psdrvr.json` from Task 2, MH_BUNDLE support from Task 1.
- Produces: `tools/binrecon/out/vga-psdrvr/published/analysis-reference-ida.json` and a validated `source-map-v1` document. Tasks 9 and 11 read both.

- [ ] **Step 1: Analyze**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'
./.venv-binrecon/Scripts/python.exe -m binrecon analyze \
  --profile tools/binrecon/profiles/vga-psdrvr.json \
  --output tools/binrecon/out/vga-psdrvr/run-summary.json
```

Exit 1 is expected, for the same reason as Task 7 Step 1.

- [ ] **Step 2: Gate on the summary**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/vga-psdrvr/run-summary.json'))
assert d['complete'] is True, d
assert d['consensus']['reference'] is not None, d
print('complete:', d['complete'], 'sha:', d['reference_sha256'], 'analyzers:', [a['name'] for a in d['analyzers']])
"
ls tools/binrecon/out/vga-psdrvr/published/
```

Expected: `complete: True` and the SHA-256 `E785BA22F1121EAAE140A2340C5068AE1FC23EBC3309F02E7705D8775E47C1F4`.

**This is the first MH_BUNDLE ever put through the pipeline, and the spec names angr as the likely casualty.** angr's CLE has not been exercised on a 1992-vintage 32-bit i386 bundle whose `__TEXT` is prebound at `0x70320000`. If angr fails or times out, set `analyzers.angr.enabled` to `false` in `tools/binrecon/profiles/vga-psdrvr.json`, re-run, and record in Task 9 that this binary's consensus rests on two analyzers and why. The same applies to Ghidra. Do not proceed on a `complete: false` run.

If **IDA** fails, stop and escalate: IDA is authoritative for the function partition and there is no fallback.

- [ ] **Step 3: Build the source map**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/vga-psdrvr/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj \
  --repo-root . \
  --output src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json
```

- [ ] **Step 4: Hand-resolve the residue**

All 22 symbols land in `unmapped`: 19 because our `VGAPSDriver.c` has no counterpart for any of them (spec §2.2), and `__mh_bundle_header`, `dyld_stub_binding_helper` and `__dyld_func_lookup` because the linker generates them (spec §2.9).

Two shapes specific to this binary need care:

- `_Start` is a zero-size alias of `_VGAStart` at the same address. If the map carries them as one entry with two `reference_names`, that is correct and preferred. If IDA reports them as separate entries and one has size 0, resolve to a single entry naming both — a zero-size entry violates the schema's `size` minimum of 1.
- `__mh_bundle_header` sits at the `__TEXT` segment base `0x70320000`, *before* the `__text` section start at offset 7988. Record its real extent, not the gap to the next symbol.

- [ ] **Step 5: Validate the source map**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe /tmp/check_map.py vga-psdrvr VGA_psdrvr
```

Expected: `source map OK`. `/tmp/check_map.py` is the script written in Task 7 Step 5; recreate it from that step if the shell has been restarted.

- [ ] **Step 6: Confirm the count**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json'))
print({k: len(m[k]) for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed')})
"
```

Expected: 21 or 22 entries in total, depending on whether `_Start` and `_VGAStart` merged into one. State which in Task 9.

- [ ] **Step 7: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json tools/binrecon/profiles/vga-psdrvr.json && git commit -m "drvVGA: add the VGA_psdrvr source map"
```

Include the profile in this commit only if Step 2 disabled an analyzer in it.

---

### Task 9: divergences.md — header and shared contract

The two binaries share memory. Settling what they agree on, from both sides' evidence, before either is rewritten is the whole reason the report pass covers both first (spec §4.3).

**Files:**
- Create: `src/drivers-i386/video/drvVGA/reconstruction/divergences.md`

**Interfaces:**
- Consumes: both analyses and both source maps from Tasks 7 and 8; the built section sizes from Task 6 Step 11.
- Produces: `divergences.md` with its header, evidence statement, bucket tables, and a `## Shared contract` section that Tasks 10 and 11 extend and the Phase 3 plans implement against.

- [ ] **Step 1: Write the header and evidence statement**

Follow the shape of `src/drivers-i386/bus/drvPCIBus/reconstruction/divergences.md`. Cover both binaries in one document:

- both reference paths, sizes and SHA-256 values from the Global Constraints table;
- the analyzer versions actually used per binary, naming any analyzer disabled in Task 7 or 8 and why;
- the Task 5 baseline build result and the Task 6 rebuilt section sizes, including whether `Load Commands` reached 164 and `Unload Commands` 67;
- a bucket-count table per binary from the two source maps;
- an explicit statement that **no function was examined against our source**, because our source is disjoint — this document records the reference's behaviour and the divergences of the project around it, not a function-by-function diff.

- [ ] **Step 2: Write the `## Shared contract` section**

Three subsections, each written from both binaries' disassembly and from `src/driverkit-3/driverkit/IOVGAShared.h`:

1. **`VGAShmem_t` layout.** The exact field offsets and total size both sides must agree on. The kernel side validates it — the reference's `__cstring` carries `%s: shmem_size > sizeof (VGAShmem_t)(%d<>%d)`. Record the size the reference actually checks against, read out of `-[IOVGADisplay getIntValues:forParameter:count:]` or wherever the check lives, and whether it matches `IOVGAShared.h` as checked in. A mismatch here is the single highest-consequence finding available in this effort.

2. **The `IO_Framebuffer_*` parameter protocol.** For each of `IO_Framebuffer_Map`, `IO_Framebuffer_Unmap`, `IO_Framebuffer_Dimensions`, `IO_Framebuffer_SetDimensions`, `IO_Framebuffer_Register`, `IO_Framebuffer_Unregister` and `IOGetDisplayInfo`: which side sends it, the count it passes, and what the kernel side does with it. All appear in both binaries' `__cstring`; `IOVGAShared.h` declares the sizes.

3. **The cursor state machine.** How `_VGADisplayCursor` and `_VGARemoveCursor` on the kernel side pair with `_VGAShieldCursor`, `_VGAUnshieldCursor`, `_VGAObscureCursor`, `_VGARevealCursor`, `_VGACheckShield` and the `_VGASys*` pair on the Window Server side; which fields of `VGAShmem_t` each reads and writes; and which side owns `cursorSema` through `_ev_lock`/`_ev_try_lock`.

- [ ] **Step 3: Record the project-level divergences**

A `## Project divergences` section for the findings that are not per-function:

- `Display.modes` deleted in Task 4, Apple ships none;
- `English.lproj/Info.rtf` retained though Apple ships none, and the `Help/VGA.rtfd` stub authored in Task 6 in place of Apple's text;
- Apple's `Default.table` and `SVGABIOS.table` run `"Help File"` and `"Server Name"` together on one line where ours are separate, if Task 6 Step 9 confirmed that as the only remaining textual difference;
- the reference's `Loaded Server,Server Version` section holds `2` where our project declares `PROJECTVERSION`; state what our build actually emitted and from which variable;
- the `VGA` version bundle: whether Task 5's build produced one and how it compares to Apple's 16672 bytes;
- any `mapped` false positive moved by hand in Task 7 Step 4 or Task 8 Step 4.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction/divergences.md && git commit -m "drvVGA: record the shared kernel and Window Server contract for the VGA driver"
```

---

### Task 10: divergences.md findings and ledger for VGA_reloc

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/divergences.md`
- Create: `src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/ledger.json`

**Interfaces:**
- Consumes: `tools/binrecon/out/vga-reloc/published/` and the source map from Task 7; the shared contract from Task 9.
- Produces: a `## VGA_reloc` section in `divergences.md` with one numbered finding per reference function, and a `ledger-v1` document with 30 entries. The Phase 3b rewrite plan is written from these two.

- [ ] **Step 1: Decompile every function and write it up**

Add a `## VGA_reloc` section with one numbered entry per function, in address order, matching the §1.1 inventory in the spec. Each entry carries: the symbol, address and size; the decompilation; and a plain-language statement of what the function does and what our rewrite must produce. Batch the work by the translation units the `__DATA` and `__bss` static ordering implies — `_svga_bios_mode`, `_vesaMode`, `_colr_mode`, `_curr_read_plane`, `_curr_write_plane`, `_curr_read_segment`, `_curr_write_segment`, `_mask_array.128`, `_ports.168`, `_vramBuf.125`, `_vramBuf.129`, `_bios`, `_nextVGAUnit`, `_nameBuf` and the `_xxx.100`/`.103`/`.106` triple.

Four questions this section must answer explicitly:

- **What `vidBIOS` is for.** It is an `N_ABS` defined class in this binary with no method body in `__text`, and the binary logs `VGADisplay: vidBIOS failed` (spec §2.4).
- **Where Apple's translation-unit boundaries fall**, and therefore what our source files should be named. This is the input the Phase 3b plan needs most.
- **What `_emu486` is**, at the level of its entry contract, its register block, its error codes and its dispatch structure. A full instruction-level transcription is Phase 3b's job, not this task's, but the interface and the shape must be settled here. State plainly whether the decompilation is transcribable — the spec's §6 anticipates that it might not be, and that judgement belongs here where the evidence is.
- **Which four symbols the `__OBJC,__class` 160 bytes account for**, confirming the class inventory.

- [ ] **Step 2: Write `ledger.json`**

`schema-version` `ledger-v1`, `reference_sha256` `489D86652B8718237052F10A551FC6615B4B045F6614DCB790CFB73272C15B96`, `rebuilt_sha256` `null`. One entry per reference function with `address`, `names`, `size`, `source_path`, `source_line`, `status`, `reason`, `reviewer`, `artifacts` and `analyzer_agreement` (`{analyzers, reasons, status}`).

Statuses at the end of this task:

- `+[VGAKernelServerInstance kernelServerInstance]` and `+[VGAVersion driverKitVersionForVGA]`: `intentional-mismatch`, with a reason naming the Kernel Server project type as their generator and a reviewer. The ledger CLI requires both fields.
- All 28 hand-written functions: `unexamined`, `source_path` and `source_line` `null`, with `analyzer_agreement.reasons` recording what the analyzers agreed on and that no source counterpart exists.

Nothing here may be `signature-confirmed` or stronger. No source has been written.

- [ ] **Step 3: Verify the ledger**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/vga-reloc.json \
  --ledger src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/ledger.json
```

`binrecon ledger` resolves the profile's reference artifact, so `BINRECON_REFERENCE` must still be exported. Expected: the ledger validates and prints its entry count as 30.

- [ ] **Step 4: Confirm every function has an entry**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/source-map.json'))
l = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/ledger.json'))
addrs = {e['address'] for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed') for e in m[k]}
led = {e['address'] for e in l['entries']}
assert addrs == led, sorted(addrs ^ led)
print(len(led), 'entries, all addresses accounted for')
"
```

Expected: `30 entries, all addresses accounted for`.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction && git commit -m "drvVGA: record the VGA_reloc decompilation findings and parity ledger"
```

---

### Task 11: divergences.md findings and ledger for VGA_psdrvr

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/divergences.md`
- Create: `src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json`

**Interfaces:**
- Consumes: `tools/binrecon/out/vga-psdrvr/published/` and the source map from Task 8; the shared contract from Task 9.
- Produces: a `## VGA_psdrvr` section in `divergences.md` and a `ledger-v1` document. The Phase 3a rewrite plan is written from these two, and it runs first, so this task's quality gates the whole rewrite.

- [ ] **Step 1: Decompile every function and write it up**

One numbered entry per function in address order, matching the §1.1 inventory in the spec, each with symbol, address, size, decompilation and a statement of behaviour.

Four things this section must settle:

- **The seven `__DATA,__common` globals** — `_vga_width`, `_vga_height`, `_vga_rowbytes`, `_vga_bpl`, `_vgaBounds`, `_vgaAddress`, `_vgaVirtualAddress` — their types, and which function writes each first.
- **What `_VGAStart` does in order**: it calls `_LookupFrameBufferDevicePort`, `__IOLookupByDeviceName`, `__IOGetIntValues`, `__IOMapEISADeviceMemory`, `__IOMapEISADevicePorts` and `_NXRegisterScreen`, and its `__cstring` gives the failure path for each. Record the call order, the arguments and the error handling, because that sequence is the Window Server's whole entry contract.
- **How the four cursor blitters `__bm12`, `__bm18`, `__bm34`, `__bm38` are selected**, and which of the `VGAShmem_t` cursor union members each corresponds to.
- **Whether `_Start` and `_VGAStart` merged** into one source-map entry (Task 8 Step 6), and what the alias is for.

- [ ] **Step 2: Write `ledger.json`**

`reference_sha256` `E785BA22F1121EAAE140A2340C5068AE1FC23EBC3309F02E7705D8775E47C1F4`, `rebuilt_sha256` `null`, one entry per source-map address.

- `__mh_bundle_header`, `dyld_stub_binding_helper` and `__dyld_func_lookup`: `intentional-mismatch`, reason naming the linker and dyld as their generator, plus a reviewer.
- The 19 hand-written symbols: `unexamined`, `source_path` and `source_line` `null`.

- [ ] **Step 3: Verify the ledger**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'
./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/vga-psdrvr.json \
  --ledger src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json
```

Expected: validates, entry count matching Task 8 Step 6.

- [ ] **Step 4: Confirm every function has an entry**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json'))
l = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json'))
addrs = {e['address'] for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed') for e in m[k]}
led = {e['address'] for e in l['entries']}
assert addrs == led, sorted(addrs ^ led)
print(len(led), 'entries, all addresses accounted for')
"
```

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction && git commit -m "drvVGA: record the VGA_psdrvr decompilation findings and parity ledger"
```

---

### Task 12: Verify the Phase 2 exit criteria

The report pass is done when the evidence is complete and machine-checkable, not when the documents look finished.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/divergences.md` (closing status section)

**Interfaces:**
- Consumes: everything from Tasks 1 through 11.
- Produces: a verified, committed evidence base. The Phase 3a and 3b plans are written next, against it.

- [ ] **Step 1: Re-validate both source maps**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc'
./.venv-binrecon/Scripts/python.exe /tmp/check_map.py vga-reloc VGA_reloc
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'
./.venv-binrecon/Scripts/python.exe /tmp/check_map.py vga-psdrvr VGA_psdrvr
```

Expected: `source map OK` twice.

- [ ] **Step 2: Confirm no unexamined function claims a status it has not earned**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
for b in ('VGA_reloc', 'VGA_psdrvr'):
    l = json.load(open(f'src/drivers-i386/video/drvVGA/reconstruction/{b}/ledger.json'))
    bad = [e['names'] for e in l['entries']
           if e['status'] not in ('unexamined', 'intentional-mismatch')]
    assert not bad, (b, bad)
    mismatch = [e for e in l['entries'] if e['status'] == 'intentional-mismatch']
    assert all(e['reason'] and e['reviewer'] for e in mismatch), b
    print(b, len(l['entries']), 'entries,', len(mismatch), 'intentional-mismatch')
"
```

Expected: `VGA_reloc 30 entries, 2 intentional-mismatch` and `VGA_psdrvr` with 3 intentional-mismatch. No function may be `signature-confirmed` or stronger; nothing is written yet.

- [ ] **Step 3: Confirm the tables still match**

Re-run Task 6 Step 9 and Step 10. Expected: unchanged results. A regression here means a later task edited a table it should not have.

- [ ] **Step 4: Confirm nothing forbidden was committed**

```bash
cd /d/RhapsodiOS && git status --short && git ls-files src/drivers-i386/video/drvVGA | sort
```

Expected: no analyzer output, no `.i64`, no rebuilt binary, and no file under `out/` or `tools/binrecon/out/` in the index. The tracked `drvVGA` list is sources, Makefiles, tables, resources and `reconstruction/`.

- [ ] **Step 5: Write the closing status section**

Append a `## Status` section to `divergences.md` recording: which analyzers ran for each binary and which were disabled with the reason; the Task 5 baseline result; the Task 6 built section sizes; the Task 3 boot-gate outcome; and an explicit statement that every function is `unexamined` or `intentional-mismatch` pending Phase 3.

State any open question the report pass could not answer — particularly if Task 10 Step 1 concluded that `_emu486`'s decompilation is not cleanly transcribable, since the spec's §6 makes that a decision point rather than a blocker to work around.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction/divergences.md && git commit -m "drvVGA: close the VGA report pass with verified source maps and ledgers"
```
