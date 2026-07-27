# VGA_psdrvr Rewrite Implementation Plan (Phase 3a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace our invented `VGAPSDriver.c` with a reconstruction of Apple's `VGA_psdrvr` — 34 compiled function bodies in one C translation unit — and fix the build so it links as MH_BUNDLE like Apple's rather than MH_EXECUTE.

**Architecture:** The report pass established that Apple's binary is a single C translation unit with no Objective-C and no assembly, spanning `__text` `0x70301F58`–`0x70303AC4`. It has three internal layers — a device-vector layer, a cursor layer and a VGA hardware layer — that the linker evidence proves were compiled together. This plan rewrites them bottom-up: hardware first (no dependencies), then cursor, then device, then verification.

**Tech Stack:** C for Rhapsody DriverKit user space, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest, `tools/binrecon` (Python 3.12 in `.venv-binrecon`) for parity checking.

**Spec:** [2026-07-25-vga-driver-binary-reconstruction-design.md](../specs/2026-07-25-vga-driver-binary-reconstruction-design.md)

**Evidence:** [`src/drivers-i386/video/drvVGA/reconstruction/divergences.md`](../../../src/drivers-i386/video/drvVGA/reconstruction/divergences.md). Its `## VGA_psdrvr` section carries findings 1 through 53; findings 3 through 36 are the 34 bodies this plan writes. Its `### What Phase 3a has to reproduce, in one place` is the acceptance summary. Its `## Shared contract` section governs everything the kernel half also touches.

## Global Constraints

Every task's requirements implicitly include this section.

- **The reference is the specification.** Every function is written from its numbered finding in `divergences.md`. Where a finding records a defect or an oddity in Apple's code, reproduce it verbatim — the named ones are `_VGAShieldCursor` clearing `shielded` before `_VGACheckShield`, the blitters' two-word-per-scan-line `save` stride that runs 64 bytes past the region the driver requests, the stale `r` in `_VGAStart`'s `os_malloc` failure message, and `outb`'s dummy operand being an automatic rather than `driverkit`'s `static int`. Fixing a reference bug is a defect in this work, not an improvement.
- **One translation unit.** All 34 bodies go in `VGAPSDriver.c`. The single-file conclusion is a deduction from `__data` interleaving and `__text` layout, recorded in `### Where Apple's translation-unit boundaries fall`. Splitting the file changes the `__data` layout and is visible in the artifact, so do not split it without raising it first.
- **Nineteen exported function symbols and seven exported `__common` globals, nothing more.** Every one of the 16 statics must be `static`. `_Start` and `_VGAStart` are two names on one body.
- **`src/driverkit-3` and `src/kernel-7` are out of bounds**, as is every other driver. `IOVGAShared.h` is checked in unchanged and is the header this file includes; if the reconstruction seems to need a change there, raise it rather than making it.
- **Run all `binrecon` commands from the repository root `D:\RhapsodiOS`** with `PYTHONPATH=tools/binrecon`. The interpreter is `.venv-binrecon/Scripts/python.exe`.
- **Never commit reference binaries, analyzer output, or rebuilt artifacts.** `tools/binrecon/out/` and `out/` are gitignored.
- **Commit messages start with `drvVGA: ` and are one to two lines total.** No metadata, no `Co-Authored-By` trailer, no `Generated with` trailer.
- **Several sessions share this working tree and its git index.** Run `git status` before staging, stage only your own files by explicit path, never `git add -A`, and confirm with `git show --stat` afterwards that your commit contains only what you intended. Two commits in the previous phase were swept into unrelated sessions' commits; if it happens, say so rather than reporting a clean outcome.
- **Ledger discipline.** As each function is written, advance its entry in `src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json` to the status the evidence supports: `signature-confirmed`, `control-flow-confirmed`, or `assembly-matched`. `assembly-matched` means the full disassembly was read instruction by instruction against the written source. Claiming a status the work does not support is the worst failure mode available here. The 2 dyld routines and 17 PIC stubs stay `intentional-mismatch`.

### The reference

`C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr`, MH_BUNDLE, 26584 bytes, SHA-256 `E785BA22F1121EAAE140A2340C5068AE1FC23EBC3309F02E7705D8775E47C1F4`, `__text` 7057 bytes. Analyzed by IDA alone — angr crashes on CFG recovery and Ghidra's relocation metadata is unusable — with the Mach-O symbol table as independent corroboration of the partition.

### The guest build host

A separate Rhapsody PPC machine; connection details in `vm/vm.conf` (`Host`, `Password`, `RemoteRoot=/build/source`). Reach it with `plink`/`pscp` from `C:\Program Files\PuTTY\`. Sync **only** `src/drivers-i386/video/drvVGA`; never `vm/rhap-vm.ps1 sync`, which uploads all of `src/`. The guest's root shell is `tcsh` and its `/bin/sh` is a 1999 Bourne shell: no `2>&1` inside a remote command string, no nested double quotes, and strip CR from uploaded files. Build with `sh /build/source/vm/build-i386-vga.sh`; stage back to `out/i386/drvVGA/`.

### The three layers

| Layer | Findings | Bodies | `__text` range |
| --- | --- | --- | --- |
| VGA hardware | 27–36 | 10 | `0x7030302C`–`0x70303AC4` |
| Cursor | 15–26 | 12 | `0x70302708`–`0x70303028` |
| Device vector | 3–14 | 12 | `0x70301F58`–`0x70302704` |

---

### Task 1: Link the bundle as MH_BUNDLE

Our build links `VGA_psdrvr` as MH_EXECUTE (file type 2) where Apple's is MH_BUNDLE (file type 8), because no `-bundle` reaches the link line. `parity_check.py` calls `read_macho`, which accepts MH_OBJECT, MH_PRELOAD and MH_BUNDLE but not MH_EXECUTE, so it cannot read our build at all — every later task's parity check depends on this.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/Makefile.preamble`

**Interfaces:**
- Consumes: nothing.
- Produces: a built `VGA_psdrvr` whose Mach-O file type is 8, readable by `binrecon.macho.read_macho` and therefore by `parity_check.py`. Every later task's verification uses it.

- [ ] **Step 1: Find how this `bundle.make` passes link flags**

On the guest, read `$(MAKEFILEPATH)/pb_makefiles/bundle.make` and the common makefiles it includes, and find the variable that reaches the final `cc`/`ld` invocation — `OTHER_LDFLAGS`, `LDFLAGS` and `OTHER_CFLAGS` are the candidates in this vintage. Do not guess: the previous phase's `BUNDLE_EXTENSION =` guess did not have the effect it looked like it would.

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'grep -n "LDFLAGS\|bundle\|MH_BUNDLE" $(ls -d /NextDeveloper/Makefiles/pb_makefiles 2>/dev/null || echo /System/Developer/Makefiles/pb_makefiles)/bundle.make' > /tmp/bundlemake.txt 2>&1
cat /tmp/bundlemake.txt
```

Record what you find. If `bundle.make` already intends to pass `-bundle` and something suppresses it, say so — that changes the fix.

- [ ] **Step 2: Add the flag**

In `VGA_psdrvr.tproj/Makefile.preamble`, which is currently empty, set whichever variable Step 1 identified. The most likely form is:

```make
OTHER_LDFLAGS = -bundle
```

Change only `Makefile.preamble`. `Makefile` is Project Builder-maintained and `BUNDLE_EXTENSION =` there stays as it is.

- [ ] **Step 3: Rebuild on the guest**

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" src/drivers-i386/video/drvVGA root@$HOST:/build/source/src/drivers-i386/video/
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'sh /build/source/vm/build-i386-vga.sh' > /tmp/vga-build.log 2>&1
echo "EXIT=$?"; tail -20 /tmp/vga-build.log
mkdir -p out/i386/drvVGA
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" root@$HOST:/build/out/i386/drvVGA/VGA.config out/i386/drvVGA/
```

Expected: `=== vga done fail=0 ===`, and the link line in the log now carries `-bundle`.

- [ ] **Step 4: Verify the file type**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
import glob
p = glob.glob('out/i386/drvVGA/VGA.config/**/VGA_psdrvr', recursive=True)[0]
d = read_macho(Path(p))
print(p, 'file_type', d['extensions']['macho']['header']['file_type'])
assert d['extensions']['macho']['header']['file_type'] == 8, 'not MH_BUNDLE'
print('MH_BUNDLE OK')
"
```

Expected: `file_type 8` and `MH_BUNDLE OK`. A `MachOFormatError` here means the link is still producing MH_EXECUTE.

Note where the binary actually landed. The previous phase observed `bundle.make` wrapping the output in a `VGA_psdrvr.bundle/` directory despite an empty `BUNDLE_EXTENSION`; record the path rather than assuming it.

- [ ] **Step 5: Prove parity_check.py can now read it**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_psdrvr" \
  $(ls out/i386/drvVGA/VGA.config/VGA_psdrvr out/i386/drvVGA/VGA.config/VGA_psdrvr.bundle/VGA_psdrvr 2>/dev/null | head -1)
```

Expected: it runs to completion and prints four counts, exiting 1 because our source is still the invented one and nearly every reference string and symbol is missing. Record the four counts — that is the baseline this plan has to drive toward zero on the `missing_` side.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/Makefile.preamble && git commit -m "drvVGA: link VGA_psdrvr as a bundle so it matches Apple's Mach-O file type"
```

---

### Task 2: The file skeleton, globals and static data

Everything the 34 bodies reference: the seven exported globals, the two `__const` cursor objects, the five VGA register tables, the two runtime-built `__bss` tables, and the `__data` tables including the 21-slot vector table. Writing these first means each later task adds only function bodies.

**Files:**
- Rewrite: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c`
- Rewrite: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.h`

**Interfaces:**
- Consumes: Task 1's build.
- Produces: the file every later task appends bodies to; the seven globals `vga_width`, `vga_height`, `vga_rowbytes`, `vga_bpl`, `vgaBounds`, `vgaAddress`, `vgaVirtualAddress` with the types finding `### The seven __DATA,__common globals` establishes; forward declarations for all 34 bodies; the `__const` tables from findings 27 through 36; and the vector table and `__bm*` class table from `### The driver vector table at 0x70304018`.

- [ ] **Step 1: Read the evidence**

`### The seven __DATA,__common globals` for the globals' types and first writers. `### The driver vector table at 0x70304018` for the 21 slots, which three are null, and which body fills each. `### The four __bm* symbols are not cursor blitters` for the five-entry class table — they are undefined external *data*, the Window Server's imaging-machine class objects, selected by a clamped depth index, and must be declared `extern`, not called. Findings 27 through 36 for the five register tables and the two `__bss` tables.

- [ ] **Step 2: Write the header**

`VGAPSDriver.h` declares only what is exported: the 19 function symbols and the 7 globals. Our current header declares an invented printing API — `VGAPSInit`, `VGAPSBeginPage`, `VGAPSRenderImage` and the rest — and none of it survives.

- [ ] **Step 3: Write the file's data and declarations**

Include `<driverkit/IOVGAShared.h>` for `VGAShmem_t` and the cursor structures. Declare the seven globals so they land in `__common` as the reference has them — a tentative definition, `int vga_width;` with no initializer, not `static` and not initialized. Declare the four `__bm*` as `extern`. Define the five `__const` register tables, the 16×16 `Bounds`, the 17-entry mask table, the two `__bss` tables, and the two `__data` tables. Forward-declare all 34 bodies, the 16 statics as `static`.

The 34 bodies are stubs at this point. Each returns whatever its finding says it returns and does nothing else, so the file compiles and links.

- [ ] **Step 4: Build and check the symbol set**

Run Task 1 Steps 3 through 5. Then:

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
import glob
ref = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'))
ours = read_macho(Path(glob.glob('out/i386/drvVGA/VGA.config/**/VGA_psdrvr', recursive=True)[0]))
def ext(d, sect):
    return {s['name'] for s in d['symbols'] if s['section'] == sect and s['binding'] == 'external'}
for sect in ('__TEXT,__text', '__DATA,__common'):
    r, o = ext(ref, sect), ext(ours, sect)
    print(sect, 'missing:', sorted(r - o), 'extra:', sorted(o - r))
"
```

Expected: `__DATA,__common` clean — all seven globals present, nothing extra. `__TEXT,__text` missing nothing; extras are acceptable at this stage only if they are compiler or linker artifacts, and any extra that is one of our own invented names is a defect.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.h && git commit -m "drvVGA: replace the invented psdrvr API with the reference's data layout and declarations"
```

---

### Task 3: The VGA hardware layer

Findings 27 through 36, ten bodies, `__text` `0x7030302C`–`0x70303AC4`: `_set_colormap`, `sub_703030F0`, `sub_70303144`, `_get_addr_range`, `_fill_64K_plane`, `_vga_at_mode12_bpp2_to_bpp4`, `_read_bpp4planar_to_bpp2packed`, `_write_bpp2packed_to_bpp4planar`, `sub_70303844`, `_VGASetStdRegs`.

This layer touches only hardware registers and the two conversion tables, so it depends on nothing else and is written first.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c`
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json`

**Interfaces:**
- Consumes: Task 2's tables and declarations.
- Produces: `_set_colormap`, `_get_addr_range`, `_fill_64K_plane`, `_vga_at_mode12_bpp2_to_bpp4`, `_read_bpp4planar_to_bpp2packed`, `_write_bpp2packed_to_bpp4planar` and `_VGASetStdRegs` as exported symbols; `sub_703030F0` (read-plane select), `sub_70303144` (write-plane select) and `sub_70303844` (conversion-table builder) as statics. Task 4's blitters and Task 5's device layer call into these.

- [ ] **Step 1: Write the ten bodies from findings 27 through 36**

Each finding carries the disassembly and a behavioural description. Reproduce control-flow shape, literal constants, I/O port addresses and call targets.

Two things this layer must get right, both recorded in the findings. `_fill_64K_plane` saves and restores the sequencer map mask but never sets it, and writes 128000 bytes rather than 65536; the 128 KB mapping covers the whole write, so the excess lands in the `0xB0000` window rather than in planar memory. That is what clears planes 2 and 3, and it is behaviour to reproduce, not a bug to fix. And `outb`'s dummy operand is an automatic here, not `driverkit`'s `static int` — this bundle emits `lock inc dword ptr [ebp-4]` where `VGA_reloc` emits `lock inc dword ptr [0x60bc]`, so do not include `driverkit/i386/ioPorts.h` for it.

- [ ] **Step 2: Build**

Run Task 1 Steps 3 and 4. Expected: `=== vga done fail=0 ===` and file type 8.

- [ ] **Step 3: Check parity movement**

Run Task 1 Step 5. Expected: `missing_symbols` has dropped by the seven exported names this task adds. Record the four counts.

- [ ] **Step 4: Advance the ledger for these ten**

For each, set the status the evidence supports and fill `source_path` and `source_line`. Use `assembly-matched` only where you read the full disassembly instruction by instruction against what you wrote. Verify:

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'
./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/vga-psdrvr.json \
  --ledger src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json
```

Expected: validates, still 53 entries.

- [ ] **Step 5: Commit**

Two commits: the source, then the ledger.

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c && git commit -m "drvVGA: reconstruct the psdrvr's VGA hardware layer"
git add src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json && git commit -m "drvVGA: advance the psdrvr ledger for the hardware layer"
```

---

### Task 4: The cursor layer

Findings 15 through 26, twelve bodies, `__text` `0x70302708`–`0x70303028`: the three `Sys` primitives, `_VGACheckShield`, `_VGASetCursor`, the six public entry points, and the two blitters `sub_70302BEC` (draw) and `sub_70302E48` (erase).

This is the half of the shared contract the Window Server owns, so `## Shared contract` §1 and §3 govern it as much as the per-function findings do.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c`
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json`

**Interfaces:**
- Consumes: Task 2's `VGAShmem_t` usage and `__const` cursor objects; Task 3's plane-select statics.
- Produces: `_VGASysHideCursor`, `_VGASysShowCursor`, `_VGACheckShield`, `_VGASetCursor`, `_VGAHideCursor`, `_VGAShowCursor`, `_VGAObscureCursor`, `_VGARevealCursor`, `_VGAShieldCursor`, `_VGAUnshieldCursor` as exported symbols, and the two blitters as statics. Task 5's `_VGAStart` installs several of these in the vector table.

- [ ] **Step 1: Read the shared contract first**

`## Shared contract` §1 gives the exact `VGAShmem_t` field offsets both halves agree on, confirmed against the kernel's own size check of `0x1448` = 5192. §3 gives the cursor state machine and which side owns `cursorSema`.

- [ ] **Step 2: Write the twelve bodies**

Four behaviours this layer must reproduce exactly, each recorded in the findings:

**Lock discipline.** All seven public entry points take `ev_lock`, which blocks; the three `Sys` primitives take no lock at all. This side never calls `ev_try_lock` — that is the kernel half's idiom, and using it here would silently change the contention behaviour.

**`_VGAShieldCursor`'s defect.** It sets `shielded = 0` before calling `_VGACheckShield`, so a non-intersecting re-shield leaves the cursor hidden with `shielded == 0`. `_VGAUnshieldCursor` does not recover it — it touches only `+0x0A` and `+0x0B` and never `cursorShow`. Reproduce both as written.

**The blitters' `save` stride.** Both step two words per scan line, so they access 128 bytes where `IOVGAShared.h` declares `save[16]` — 64. The draw blitter writes; the erase blitter only reads. The excess 64 bytes run past the end of the region the driver itself requested. The kernel half does the same, so it is symmetric. Reproduce the arithmetic as written.

**The blitters mirror the kernel's.** `sub_70302BEC`'s inner loop is instruction-for-instruction the kernel's `_VGADisplayCursor`, and `sub_70302E48`'s is `_VGARemoveCursor`. Cross-check against the `## VGA_reloc` findings for those two, and raise any divergence rather than resolving it yourself.

- [ ] **Step 3: Build, check parity, advance the ledger**

As Task 3 Steps 2 through 4, for these twelve. Expected: `missing_symbols` down by the ten exported names.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c && git commit -m "drvVGA: reconstruct the psdrvr's cursor layer"
git add src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json && git commit -m "drvVGA: advance the psdrvr ledger for the cursor layer"
```

---

### Task 5: The device vector layer and `_VGAStart`

Findings 3 through 14, twelve bodies, `__text` `0x70301F58`–`0x70302704`: the eleven vector-table statics and `_VGAStart`, which is the Window Server's entire entry contract.

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c`
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json`

**Interfaces:**
- Consumes: Task 2's vector table and `__bm*` class table; Tasks 3 and 4's functions, which several vector entries call.
- Produces: `_Start` and `_VGAStart` as two names on one body, and the eleven statics filling their vector slots. This completes the 19 exported function symbols.

- [ ] **Step 1: Write `_VGAStart` from finding 14 and `### _VGAStart: the Window Server's entry contract`**

Its call order is the contract: `_LookupFrameBufferDevicePort`, `__IOLookupByDeviceName`, `__IOGetIntValues`, `__IOMapEISADeviceMemory`, `__IOMapEISADevicePorts`, `_NXRegisterScreen`. Every argument and every arity is recorded, confirmed against the stack adjustments. Its seven `__cstring` failure paths must appear verbatim, including the stale `r` in the `os_malloc` message — the preceding `test ebx,ebx / je` proves the register is zero at the `push`, so Apple prints a value it has just established is null. Seven paths converge at one exit; the framebuffer-open path is separate because its format string takes no `%d`.

`_Start` is a second exported name on the same body, not a wrapper. Emit it so both symbols resolve to one address.

- [ ] **Step 2: Write the eleven vector statics from findings 3 through 13**

Composite-and-flush, offscreen bitmap create/convert/free, screen-device init, `IO_Framebuffer_Register`, and the 7-byte empty stub at slot `+0x50` that is a literal `{ }`. Three slots are null and stay null.

The screen-device and compositing-operation records are the Window Server's own structures and no header for them exists in this tree, so the findings name their fields by offset only and mark that as inference. `_VGAStart`'s argument is demonstrably not the same layout as the vector entries' argument. Where a field's meaning is inference, keep the offset exact and the name descriptive, and do not invent a struct that claims more than the evidence supports.

- [ ] **Step 3: Build, check parity, advance the ledger**

As Task 3 Steps 2 through 4. Expected after this task: `missing_symbols` is empty — all 19 exported function names and all 7 globals present.

- [ ] **Step 4: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.c && git commit -m "drvVGA: reconstruct the psdrvr's device vector layer and VGAStart"
git add src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json && git commit -m "drvVGA: advance the psdrvr ledger for the device layer"
```

---

### Task 6: Phase 3a verification

**Files:**
- Modify: `src/drivers-i386/video/drvVGA/reconstruction/divergences.md` (a `## Phase 3a result` section)

**Interfaces:**
- Consumes: everything from Tasks 1 through 5.
- Produces: the verified end state of this phase, and the record of what Phase 3b inherits.

- [ ] **Step 1: Build cleanly from scratch**

Delete the guest's build tree for this project, re-sync and rebuild, so nothing rests on a stale object. Expected: `=== vga done fail=0 ===` and no compiler errors. Warnings are captured and reviewed but do not gate.

- [ ] **Step 2: String parity**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_psdrvr" \
  $(ls out/i386/drvVGA/VGA.config/VGA_psdrvr out/i386/drvVGA/VGA.config/VGA_psdrvr.bundle/VGA_psdrvr 2>/dev/null | head -1)
```

**`missing_strings` must be empty.** Every one of the reference's 15 `__cstring` entries has a known source in the findings, so a missing string is a function written wrongly, not a toolchain artifact. Extras from our unstripped build are reported, not gated.

- [ ] **Step 3: Symbol parity**

From the same run: **`missing_symbols` must be empty** for `__TEXT,__text`. Extras are reported. Investigate any extra that is not obviously a compiler or linker artifact.

- [ ] **Step 4: Section comparison**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
import glob
ref = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'))
ours = read_macho(Path(glob.glob('out/i386/drvVGA/VGA.config/**/VGA_psdrvr', recursive=True)[0]))
r = {s['name']: s['size'] for s in ref['sections']}
o = {s['name']: s['size'] for s in ours['sections']}
for name in sorted(set(r) | set(o)):
    print('%-28s ref %-8s ours %s' % (name, r.get(name, '-'), o.get(name, '-')))
"
```

Report the table. `__TEXT,__const` should be 444 bytes and `__DATA,__bss` 131072 plus scalars, per the acceptance summary. `__text` will differ because our build is unstripped and the compiler is not Apple's; a large divergence is a finding to investigate, not an automatic failure.

- [ ] **Step 5: Confirm the ledger is complete and honest**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
from collections import Counter
l = json.load(open('src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/ledger.json'))
c = Counter(e['status'] for e in l['entries'])
print(len(l['entries']), 'entries', dict(c))
un = [e['names'] for e in l['entries'] if e['status'] == 'unexamined']
assert not un, un
im = [e for e in l['entries'] if e['status'] == 'intentional-mismatch']
assert all(e['reason'] and e['reviewer'] for e in im)
print('no unexamined entries remain;', len(im), 'intentional-mismatch')
"
```

Expected: 53 entries, none `unexamined`, 19 `intentional-mismatch` (the 2 dyld routines and 17 PIC stubs), and 34 at `signature-confirmed` or stronger.

- [ ] **Step 6: Regenerate the source map against the rewritten source**

The map's `unmapped` entries must now move to `mapped`, since our source finally has counterparts.

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr'
./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/vga-psdrvr/published/analysis-reference-ida.named.merged.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj \
  --repo-root . \
  --output src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json
```

If that analysis document is absent, regenerate it with `tools/binrecon/restore_symbol_aliases.py` followed by `tools/binrecon/filter_contained_fragments.py`, as the report pass did. Validate with `load_source_map` afterwards. Expected: 53 entries still, with the 34 written bodies now `mapped` and the 19 generated entries still `unmapped`.

- [ ] **Step 7: Write the result section and commit**

Append `## Phase 3a result` to `divergences.md`: the final parity counts, the section table, the ledger distribution, which functions reached `assembly-matched` and which stopped at `control-flow-confirmed` and why, and anything Phase 3b inherits. State plainly whether `missing_strings` and `missing_symbols` reached empty, and if either did not, exactly what remains and why.

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvVGA/reconstruction/divergences.md src/drivers-i386/video/drvVGA/reconstruction/VGA_psdrvr/source-map.json && git commit -m "drvVGA: record the Phase 3a result and remap the psdrvr against the rewritten source"
```
