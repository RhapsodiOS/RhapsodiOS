# VGA_reloc Rewrite Implementation Plan (Phase 3b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace our invented `VGA` class with a reconstruction of Apple's `VGA_reloc` — 36 hand-written bodies across three source files, one of which is hand-written i386 assembly.

**Architecture:** The report pass proved this binary has four translation units, and `__OBJC,__module_info` names three of them outright: `IOVGADisplay.m` (the class, its `(VESAMode)` category and nine C helpers), `VGA_instance.m` (build-generated, never hand-written), and `vidBIOS.m` (the real-mode BIOS-call class). The fourth is `_emu486`, an 8088-byte 8086 interpreter that is hand-written assembly rather than compiled C, so it is transcribed as a `.s` file rather than reconstructed. This plan writes the C first, bottom-up, and the assembly last.

**Tech Stack:** Objective-C and C for Rhapsody DriverKit kernel space, i386 assembly, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest, `tools/binrecon` for parity checking.

**Spec:** [2026-07-25-vga-driver-binary-reconstruction-design.md](../specs/2026-07-25-vga-driver-binary-reconstruction-design.md)

**Evidence:** [`src/drivers-i386/video/drvVGA/reconstruction/divergences.md`](../../../src/drivers-i386/video/drvVGA/reconstruction/divergences.md). Its `## VGA_reloc` section carries the per-function findings and four subsections this plan leans on by name: `### Where Apple's translation-unit boundaries fall`, `### The four classes in __OBJC,__class`, `### What vidBIOS is for`, and `### _emu486`. Its `## Shared contract` section governs everything the Window Server half also touches, and `## Phase 3a result` records what that half established.

**Precedent:** Phase 3a rewrote the other half of this driver, `VGA_psdrvr`, and reached `missing_strings 0` and `missing_symbols 0` with 34 of 34 bodies at `assembly-matched`. Its plan is [2026-07-26-vga-psdrvr-rewrite.md](2026-07-26-vga-psdrvr-rewrite.md). Follow its shape.

## Global Constraints

Every task's requirements implicitly include this section.

- **The reference is the specification.** Every body is written from its numbered finding. Where a finding's prose and its disassembly disagree, **the disassembly wins** — Phase 3a found nine such cases and corrected them, and this section of the document has had less use than that one, so expect more. Report each rather than silently working around it.
- **Reproduce Apple's defects, do not fix them.** The named ones in this binary are `+[IOVGADisplay probe:]` returning YES unconditionally without testing `initFromDeviceDescription:`'s result; `-[IOVGADisplay setBrightness:token:]` logging its error without guarding the call that follows; `-[IOVGADisplay(VESAMode) didBootWithDefaultConfig]` being dead code; a one-byte error in `_emu486`'s condition-code table where `setno` (`0f 91`) stands at file offset 18165 in the slot that wants `setnp` (`0f 9b`); and the blitters' bank divisor of `0x10000 / (width >> 4)` giving 1638 where the arithmetically correct figure — and the Window Server half's — is 819. That last one is latent at 640×480 because the bank switch is dead below 1638 lines. Fixing any of them is a defect in this work.
- **Four translation units, three of them files you write.** `IOVGADisplay.m`, `vidBIOS.m` and `emu486.s`. `VGA_instance.m` is emitted by the Kernel Server project type and must **not** be hand-written; its two methods, `+[VGAKernelServerInstance kernelServerInstance]` and `+[VGAVersion driverKitVersionForVGA]`, stay `intentional-mismatch` in the ledger.
- **`src/driverkit-3` and `src/kernel-7` are out of bounds.** `IOVGADisplay.h`, `IOVGADisplayPrivate.h` and `IOVGAShared.h` are NeXT's own headers for this exact driver, checked in unchanged; `IOVGADisplayPrivate.h` carries the ET4000 constants, the `colr_mode` variable and the `vga_reg_out` register macros the reference was compiled against. Use them to name what you see rather than inventing terminology. If the reconstruction seems to need a change in any of them, raise it rather than making it.
- **Run all `binrecon` commands from the repository root `D:\RhapsodiOS`** with `PYTHONPATH=tools/binrecon`. The interpreter is `.venv-binrecon/Scripts/python.exe`.
- **Never commit reference binaries, analyzer output, or rebuilt artifacts.** `tools/binrecon/out/` and `out/` are gitignored.
- **Commit messages start with `drvVGA: ` and are one to two lines total.** No metadata, no `Co-Authored-By` trailer, no `Generated with` trailer.
- **Several sessions share this working tree and its git index.** Run `git status` before staging, stage only your own files by explicit path, never `git add -A`, and confirm with `git show --stat` afterwards. Three changes in earlier phases were swept into unrelated sessions' commits; if it happens, say so rather than reporting a clean outcome.
- **Ledger discipline.** As each body is written, advance its entry in `src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/ledger.json` to the status the evidence supports. **`assembly-matched` means the full disassembly was read instruction by instruction against what you wrote.** A lower honest status is always better than a higher unearned one. Refresh `source_line` on earlier entries when your insertions make them stale.

### The reference

`C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc`, MH_PRELOAD, 71112 bytes, SHA-256 `489D86652B8718237052F10A551FC6615B4B045F6614DCB790CFB73272C15B96`, `__text` 18048 bytes. Analyzed by IDA and Ghidra; angr is disabled in this profile after producing a phantom function overlapping `_emu486`. The committed source map holds 38 entries.

The parity baseline, measured in Phase 2 against the invented sources: `missing_strings` 29, `missing_symbols` 28, `extra_strings` 19, `extra_symbols` 34. Our build is unstripped by deliberate decision, so extras are reported and never gated; drive the **missing** counts to zero.

### The guest build host

A separate Rhapsody PPC machine; connection details in `vm/vm.conf`. Reach it with `plink`/`pscp` from `C:\Program Files\PuTTY\`. Sync **only** `src/drivers-i386/video/drvVGA`; never `vm/rhap-vm.ps1 sync`, which uploads all of `src/`. The guest's root shell is `tcsh` and its `/bin/sh` is a 1999 Bourne shell: no `2>&1` inside a remote command string, no nested double quotes. Build with `sh /build/source/vm/build-i386-vga.sh`; stage back to `out/i386/drvVGA/`. The build currently succeeds and emits all five `Loaded Server` sections at Apple's exact byte counts — 3, 164, 67, 12, 1 — and that must stay true.

### The 36 bodies

| File | Findings | Bodies | `__text` |
| --- | --- | --- | --- |
| `IOVGADisplay.m` | the 27 entries from address 0 to 6368 | 27 | 0–6371 |
| `vidBIOS.m` | the 6 `-[vidBIOS …]` entries | 6 | 6396–7551 |
| `emu486.s` | `_emu486` plus the two standalone fragments at 15640 and 15721 | 3 | 7552–18048 |

`VGA_instance.m`'s two methods at 6372 and 6384 are generated and are not written.

---

### Task 1: Project scaffolding and assembly support

The `.lksproj` still names our invented sources, and **no driver in this tree has ever built an assembly file**, so how `kernelserver.make` handles a `.s` is an open question that must be settled before Task 7 depends on it.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/Makefile`
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/PB.project`
- Delete: `VGA.m`, `VGAConfigTable.m`, `VGASetMode.m`, `VGAModes.c`, `VGA.h`, `VGAModes.h`
- Create: `IOVGADisplay.m`, `vidBIOS.m`, `emu486.s`, and whatever private header the two `.m` files share

**Interfaces:**
- Consumes: nothing.
- Produces: a `.lksproj` whose `CLASSES` names `IOVGADisplay.m` and `vidBIOS.m`, whose source list carries `emu486.s`, and a build that assembles and links it. Every later task adds bodies to those files.

- [ ] **Step 1: Find how this `pb_makefiles` builds a `.s`**

On the guest, read `$(MAKEFILEPATH)/pb_makefiles/common.make`, `rules.make` and `kernelserver.make` for the variable that carries assembly sources — `SFILES` and `OTHERSRCS` are the candidates in this vintage — and for the rule that turns `.s` into `.o`.

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'grep -n "SFILES\|\.s\b\|ASFLAGS" /NextDeveloper/Makefiles/pb_makefiles/common.make /NextDeveloper/Makefiles/pb_makefiles/rules.make /NextDeveloper/Makefiles/pb_makefiles/kernelserver.make' > /tmp/sfiles.txt 2>&1
cat /tmp/sfiles.txt
```

Record what you find. Phase 3a's Task 1 discovered that `bundle.make`'s own flag logic was defeated by include ordering, so do not assume a documented variable actually reaches the rule — verify by building.

If no variable carries assembly sources, the fallback is `Makefile.preamble` adding the object explicitly, as Phase 3a did for `bundle1.o`. Report which route you took.

- [ ] **Step 2: Rewrite the source lists**

```make
CLASSES = IOVGADisplay.m vidBIOS.m

HFILES = IOVGADisplayReloc.h
```

with `emu486.s` named through whatever Step 1 established. `Load_Commands.sect` and `Unload_Commands.sect` stay in `OTHERSRCS` exactly as they are — they produce two of the five `Loaded Server` sections at Apple's byte counts and must not be disturbed. Update `PB.project` to agree with the `Makefile`, as the two must match.

The private header holds what `IOVGADisplay.m` and `vidBIOS.m` share. Do not name it `VGA.h`; that was our invention's name.

- [ ] **Step 3: Delete the invented sources**

`git rm` the six files. Their content has no counterpart in the reference — the report pass established that the two share no string, symbol or class name — so nothing is carried across.

- [ ] **Step 4: Write minimal compilable stubs**

`IOVGADisplay.m` declares `@interface IOVGADisplay : IODisplay` per `driverkit/IOVGADisplay.h` with its `(VESAMode)` category, `vidBIOS.m` declares `@interface vidBIOS : Object`, and `emu486.s` declares a global `_emu486` that returns immediately. Enough to build, nothing more.

- [ ] **Step 5: Build**

Sync and build per the Global Constraints. Expected: `=== vga done fail=0 ===`, a `VGA_reloc` on disk, and the assembly file genuinely assembled — confirm by checking that `_emu486` appears in the built binary's `__TEXT,__text` symbols:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
d = read_macho(Path('out/i386/drvVGA/VGA.config/VGA_reloc'))
names = {s['name'] for s in d['symbols'] if s['section'] == '__TEXT,__text'}
print('_emu486 present:', '_emu486' in names)
for s in d['sections']:
    if s['name'].startswith('Loaded Server'):
        print(s['name'], s['size'])
"
```

Expected: `_emu486 present: True`, and the five `Loaded Server` sections still at 3, 164, 67, 12, 1. If the assembly did not assemble, `_emu486` will be absent — that is the whole point of this step, so do not proceed on a build that merely exits 0.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add -- src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj && git commit -m "drvVGA: name the reference's source files in the lksproj and build an assembly unit"
```

---

### Task 2: Class declarations, statics and constant data

Everything the 33 C bodies reference, so each later task adds only function bodies.

**Files:**
- Modify: `IOVGADisplay.m`, `vidBIOS.m`, and the shared private header

**Interfaces:**
- Consumes: Task 1's scaffolding.
- Produces: the four classes `__OBJC,__class`'s 160 bytes account for, the file-scope statics, the `__TEXT,__const` tables, and stubs for all 33 C bodies. Tasks 3 through 6 replace stubs only.

- [ ] **Step 1: Read the evidence**

`### The four classes in __OBJC,__class` for the class inventory. `### Where Apple's translation-unit boundaries fall` for which statics belong to which file — the argument turns on `_xxx.100`/`.103`/`.106` being the `static int` inside `outb`/`outw`/`outl` in the checked-in `driverkit/i386/ioPorts.h`, one triple per translation unit that includes it, with exactly one in the binary. `### What vidBIOS is for` for that class's shape.

The statics to place: `_svga_bios_mode`, `_vesaMode`, `_colr_mode`, `_curr_read_plane`, `_curr_write_plane`, `_curr_read_segment`, `_curr_write_segment`, `_mask_array.128`, `_ports.168`, `_vramBuf.125`, `_vramBuf.129`, `_bios`, `_nextVGAUnit`, `_nameBuf`, and the `_xxx.100`/`.103`/`.106` triple. Four of them — `_colr_mode`, `_curr_read_plane`, `_curr_write_plane`, `_curr_read_segment`, `_curr_write_segment` — are **external** in the reference, not static, so declare them accordingly.

`_mask_array.128` is 17 entries of 4 bytes, terminating at `0x00000000`. An earlier draft attributed 92 further bytes to it from gap-derived sizing; those are `_emu486`'s state block and belong to Task 7.

- [ ] **Step 2: Write the declarations and data, with stubs**

Include `driverkit/IOVGADisplay.h`, `IOVGADisplayPrivate.h` and `IOVGAShared.h`. Use `IOVGADisplayPrivate.h`'s existing `vga_reg_out`/`vga_acr_out` macros and ET4000 constants rather than writing new ones — the reference was compiled against them.

`outb` here **does** use `driverkit/i386/ioPorts.h`'s `static int`, unlike the Window Server half: this binary emits `lock inc dword ptr [0x60bc]` against the bundle's `lock inc dword ptr [ebp-4]`. That difference is what pins the translation-unit argument, so getting it right matters beyond correctness.

- [ ] **Step 3: Build and check the symbol set**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
ref = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc'))
ours = read_macho(Path('out/i386/drvVGA/VGA.config/VGA_reloc'))
def names(d, sect, binding=None):
    return {s['name'] for s in d['symbols'] if s['section'] == sect and (binding is None or s['binding'] == binding)}
for sect in ('__TEXT,__text', '__DATA,__data'):
    r, o = names(ref, sect, 'external'), names(ours, sect, 'external')
    print(sect, 'missing:', sorted(r - o), 'extra:', sorted(o - r))
"
```

Expected: `__DATA,__data` clean — the five external data symbols present, nothing extra.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add -- src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj && git commit -m "drvVGA: declare the reference's classes, statics and constant tables"
```

---

### Task 3: The nine C helpers

The plane and segment selects, the two packed↔planar converters, `_SetET4000Brightness` and `_find_parameter`. They touch only hardware registers and file statics, so they depend on nothing else.

**Files:** `IOVGADisplay.m`, `VGA_reloc/ledger.json`

**Interfaces:**
- Consumes: Task 2's statics and tables.
- Produces: `_select_read_segment`, `_select_write_segment`, `_select_read_plane`, `_select_write_plane`, `_vga_read_bpp4planar_to_bpp2packed32`, `_vga_write_bpp2packed32_to_bpp4planar`, `_SetET4000Brightness`, `_find_parameter`, all external. Tasks 4 and 5 call into them.

- [ ] **Step 1: Write the nine bodies from their findings**

The Window Server half's counterparts are already written and were verified against these — `### Phase 3a result` records which. Cross-check as you go: `_select_read_plane` and `_select_write_plane` have direct counterparts in `VGAPSDriver.c`, and a divergence between the two halves is a finding, not something to resolve silently.

Note the correction Phase 3a established: only `out` carries the dummy `lock incl`, never `in`. The kernel half's dummy is `driverkit`'s `static int` rather than an automatic.

- [ ] **Step 2: Build, check parity, advance the ledger for these nine**

Verify the ledger with `binrecon ledger --profile tools/binrecon/profiles/vga-reloc.json --ledger src/drivers-i386/video/drvVGA/reconstruction/VGA_reloc/ledger.json`, with `BINRECON_REFERENCE` exported to the `VGA_reloc` path. Expected: validates, still 38 entries.

- [ ] **Step 3: Commit** — source, then ledger, two commits.

---

### Task 4: The cursor layer

`_VGADisplayCursor`, `_VGARemoveCursor`, and the three `IOVGADisplay` cursor methods `hideCursor:`, `moveCursor:frame:token:` and `showCursor:frame:token:`.

**Files:** `IOVGADisplay.m`, `VGA_reloc/ledger.json`

**Interfaces:**
- Consumes: Task 3's plane and segment selects; Task 2's `_vramBuf.125` and `_vramBuf.129`.
- Produces: the two blitters as external symbols and the three methods.

- [ ] **Step 1: Read `## Shared contract` §1 and §3 first**

They give the `VGAShmem_t` field offsets both halves agree on, confirmed against this binary's own size check of `0x1448` = 5192 in `-[IOVGADisplay _registerWithED]`, and the cursor state machine. This is the kernel side of that contract.

- [ ] **Step 2: Write the five bodies**

Four behaviours to reproduce exactly:

**Lock discipline.** This side uses `ev_try_lock` and `ev_unlock` and never `ev_lock` — the opposite of the Window Server half. When the lock is held, this side silently does nothing. Substituting a blocking lock would change behaviour under contention.

**The `save` stride.** `_VGADisplayCursor` writes two words per scan line into `cursor.bw.save`, which `IOVGAShared.h` declares as 16 unsigned ints, so it writes 128 bytes into 64. `_VGARemoveCursor` reads the same stride and does not write. The Window Server half does the same, symmetrically. Reproduce the arithmetic.

**The bank divisor.** `0x10000 / (width >> 4)` with a signed `idiv`, giving 1638, where the Window Server half computes 819 and 819 is correct. Latent at 640×480 because the bank switch is dead below 1638 lines. Reproduce 1638.

**Register restore.** Both blitters restore the write registers from the saved *read* values — `_curr_write_segment` and `_curr_write_plane` each have exactly one reference in the whole binary, both stores. That is Apple's code and it is reproduced, not corrected.

- [ ] **Step 3: Build, check parity, advance the ledger. Step 4: Commit** — source, then ledger.

---

### Task 5: The IOVGADisplay class and its VESAMode category

The remaining thirteen methods: `_registerWithED`, `generateNameAndUnit:`, `map`, `unmap`, `probe:`, `free`, `initFromDeviceDescription:`, `setBrightness:token:`, `getIntValues:forParameter:count:`, `setIntValues:forParameter:count:`, `allocateConsoleInfo`, and the category's `enterSVGAMode:`, `int10:` and `didBootWithDefaultConfig`.

**Files:** `IOVGADisplay.m`, `VGA_reloc/ledger.json`

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces: the class's full method set. Task 6's `vidBIOS` is what `int10:` calls into.

- [ ] **Step 1: Write the thirteen bodies**

`-[IOVGADisplay getIntValues:forParameter:count:]` and `setIntValues:forParameter:count:` implement the `IO_Framebuffer_*` protocol. Note the correction the report pass recorded: this side implements parameters the Window Server side never sends — the bundle uses only `IO_Framebuffer_Register`, `IO_Framebuffer_SetDimensions`, `IOGetDisplayInfo` and `Set VGA VESA Mode`. Implement what this binary implements, not only what the other half calls.

`_registerWithED` carries the `VGAShmem_t` size check against `0x1448`. `enterSVGAMode:` reads `"SVGA Mode"` and `"SVGA VESA BIOS Mode"` from the config table — the two keys Phase 2 added to `SVGABIOS.table`.

Three Apple defects live here and all three are reproduced: `probe:` returns YES unconditionally, sending `generateNameAndUnit:`, `setUnit:`, `setName:`, `setDeviceKind:` and `registerDevice` to a possibly-nil receiver; `setBrightness:token:` logs its error and then calls `_SetET4000Brightness` anyway on both paths; and `didBootWithDefaultConfig` is dead code, its result never used because `_svga_bios_mode` is zeroed both before and after the call.

- [ ] **Step 2: Build, check parity, advance the ledger. Step 3: Commit** — source, then ledger.

Expected after this task: `missing_strings` is near zero, since most of this binary's `__cstring` belongs to these methods.

---

### Task 6: vidBIOS.m

Six methods: `init`, `free`, `int10:outregs:iorange:ionum:smmport:`, `int10:outregs:iorange:ionum:`, `scratchSegment`, `realToVirtual::`.

**Files:** `vidBIOS.m`, `VGA_reloc/ledger.json`

**Interfaces:**
- Consumes: Task 2's declarations.
- Produces: the class `-[IOVGADisplay(VESAMode) int10:]` calls into, and the caller of `_emu486`.

- [ ] **Step 1: Write the six bodies**

`### What vidBIOS is for` establishes the shape: the class owns the real-mode BIOS call, `realToVirtual::` and `scratchSegment` manage the low-memory window, and the five-argument `int10:` is the call itself with a four-argument convenience wrapper. The spec asks for one thing this task must settle and record: **the exact argument types and the register block layout the two `int10:` methods pass and receive**, since that is `_emu486`'s entry contract and Task 7 depends on it.

The `__cstring` entries for the low-memory failures — `can't allocate low memory region`, `failed to wire down low memory region`, `can't allocate memory region in the lower 1MB`, `can't map lower 1MB` — belong here, as does `VGADisplay: vidBIOS failed`.

- [ ] **Step 2: Build, check parity, advance the ledger. Step 3: Commit** — source, then ledger.

---

### Task 7: emu486.s

`_emu486` and the two standalone fragments at 15640 and 15721. This is the largest single piece of the effort and the only assembly in it.

**Files:** `emu486.s`, `VGA_reloc/ledger.json`

**Interfaces:**
- Consumes: Task 6's register block layout, which is this function's entry contract.
- Produces: `_emu486`, external.

- [ ] **Step 1: Read `### _emu486` in full**

It records why this is assembly rather than compiled C — no frame pointer where all other functions have one; a 92-byte all-zero state block in `__DATA,__data` rather than `__bss`, carrying no symbol at all, which is a `.data` plus `.space` signature; `daa`/`das`/`aaa`/`aas` executed with guest flags loaded via `sahf`, which gcc never emits; internal subroutines taking register arguments and popping their own return addresses; and table-driven computed jumps. Seven independent observations, all verified to the byte during review.

It also records the structure: an 8088-byte core, 67 unnamed fragments totalling 1161 bytes that are its per-opcode handlers, of which 34 return to a shared dispatch point at `0x1E20` and the rest jump elsewhere, and roughly 2290 further bytes that no function claims and that are the dispatch tables.

- [ ] **Step 2: Work from a linear disassembly with the jump tables decoded**

**No analyzer's interior boundaries can be trusted here.** IDA gives the core 8088 bytes; Ghidra gives 6931 and then fragments along entirely different lines; angr produced a phantom overlapping function and is disabled for this binary. Produce a linear disassembly of `0x1D80` through the end of `__text` and decode the jump tables — `jpt_1E45`, `off_43B0`, `off_4190` and the condition-code table at `jpt_3D22` are the ones the findings name — rather than trusting any tool's function partition.

- [ ] **Step 3: Transcribe**

This is transcription, not reconstruction: the output is assembly, and the goal is the same instruction stream. Preserve the state block as a `.data` region of 92 zero bytes with no symbol, the entry contract from Task 6, the four error codes, and the computed-jump structure.

**Reproduce the one-byte condition-code table error.** Slot 11 holds `0f 91 c0 c3` — `setno` — at file offset 18165, where the condition order calls for `setnp` (`0f 9b`). All fifteen other slots are correct. `jpt_3D22` at 17984 is `15657 + 4·i` for all sixteen slots, so slot 11 does point there. Transcribing it verbatim is correct; "fixing" it is not.

- [ ] **Step 4: Build and compare**

Beyond parity, compare the assembled `_emu486`'s bytes against the reference's directly. This is the one function where byte-level comparison is both possible and meaningful, because assembly has no compiler between source and output. Report how close it comes and where it differs.

- [ ] **Step 5: Advance the ledger. Step 6: Commit** — source, then ledger.

---

### Task 8: Phase 3b verification

**Files:** `divergences.md`, `VGA_reloc/source-map.json`

- [ ] **Step 1: Clean build from scratch.** Delete the guest's build tree for this project first. Expected: `=== vga done fail=0 ===`, and the five `Loaded Server` sections still at 3, 164, 67, 12, 1.

- [ ] **Step 2: String parity.** `missing_strings` must be empty.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_reloc" \
  out/i386/drvVGA/VGA.config/VGA_reloc
```

- [ ] **Step 3: Symbol parity.** `missing_symbols` must be empty. Extras are reported, never gated — our build is unstripped by deliberate decision.

- [ ] **Step 4: Section comparison**, as Phase 3a's Task 6 did. Report which sections match exactly. `__TEXT,__const` should be 178 bytes and `__DATA,__data` 188.

- [ ] **Step 5: Ledger audit.** 38 entries, none `unexamined`, 2 `intentional-mismatch` — the two `VGA_instance.m` methods — each with a reason and a reviewer, and 36 at `signature-confirmed` or stronger.

- [ ] **Step 6: Regenerate the source map** against the rewritten sources, as Phase 3a's Task 6 did, using `tools/binrecon/filter_contained_fragments.py` over the IDA analysis. Expected: 36 `mapped`, 2 `unmapped`, validating under `load_source_map`.

- [ ] **Step 7: Append `## Phase 3b result` to `divergences.md`** recording the parity counts, the section table, the ledger distribution, how close `emu486.s` came at the byte level, every finding the rewrite disproved, and what remains open. Then commit.

- [ ] **Step 8: Update `src/drivers-i386/README`**, replacing `drvVGA - reconstruction in progress` with the status the evidence supports. Both halves are now reconstructed; the driver has still never been booted, and the QEMU boot gate from Phase 2 is still deferred. Say exactly that rather than calling it complete.
