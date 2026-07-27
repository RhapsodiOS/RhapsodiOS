# Cirrus GD5434 and ThinkPad 760ED Display Driver Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `CirrusLogicGD5434DisplayDriver_reloc` (19 hand-written functions) and the in-scope 6528 bytes of `IBMThinkPad760EDDisplayDriver_reloc` (29 hand-written functions) from Apple's shipped i386 binaries, replacing two invented sources with Apple's file partition, and leaving a committed source map, parity ledger and divergence document for each.

**Architecture:** Two independent tracks. Each runs profile → analyze → report → rewrite → build. Both of our sources share zero symbols with their reference, so every function is written from the disassembly; the source map's `unmapped`→`mapped` movement is the progress metric. The ThinkPad's `vidBIOS.m` and `_emu486` (11652 of its 18204 `__text` bytes) are owned by the drvVGA effort and stay unwritten here, so track B ends at compiled objects rather than a linked binary.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` (angr 9.3.0, jsonschema 4.26.0), IDA Professional 9.2 (`idat.exe`), Ghidra 12.1, Objective-C and i386 assembly for Rhapsody DriverKit, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest.

**Spec:** [2026-07-26-cirrus-thinkpad-display-reconstruction-design.md](../specs/2026-07-26-cirrus-thinkpad-display-reconstruction-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **The repository root for this execution is the worktree**, `/d/RhapsodiOS/.claude/worktrees/cirrus-thinkpad-recon`, on branch `cirrus-thinkpad-recon`. Every `cd /d/RhapsodiOS` in the command examples below means *that* directory, not `D:\RhapsodiOS`. Writing to `D:\RhapsodiOS` modifies another session's checkout — never do it.
- **Never commit reference binaries, rebuilt artifacts, or analyzer output.** `tools/binrecon/out/`, `out/` and `.venv-binrecon/` are all excluded from git. Rebuilt files stage to `out/i386/` and stay untracked.
- **Run every `binrecon` command from the repository root** with `PYTHONPATH=tools/binrecon`. Analyzer executable paths in profiles are resolved by the host process, so another cwd breaks them.
- **Python is `./.venv-binrecon/Scripts/python.exe`.** Not `python`, not `py`. A venv already exists in the worktree with the pinned dependencies installed (Python 3.13.9; the README's 3.12 is stale). Baseline `pytest tools/binrecon/tests` is 713 passed, 4 skipped — rerun it if you touch anything under `tools/binrecon/binrecon/`, though this plan does not.
- **`BINRECON_REFERENCE` must be exported** in any shell running `binrecon validate`, `analyze`, `source-map` or `ledger`. Track A:
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc`
  Track B:
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc`
- **The reference binaries are read-only.** Never modify anything under `C:\Users\raynorpat\Downloads\test`.
- **Reference identities.** Every committed `source-map.json` and `ledger.json` must carry the matching SHA-256; `load_source_map` enforces it.

  | Binary | Size | SHA-256 |
  | --- | --- | --- |
  | `CirrusLogicGD5434DisplayDriver_reloc` | 41992 | `7DA038CCEA1CDE68B6CF2ACF4D12EE5056E7F0248ADD34D451FB96EA79C13D0D` |
  | `IBMThinkPad760EDDisplayDriver_reloc` | 73168 | `47539E03C441BBFD6724EB6778D85BFACD0961B78A8DFA33D56321C938EB5AEC` |

- **`binrecon analyze` exits 1 on a reference-only profile, and that is success.** Acceptance `normalized-functions` compares a reference against a *rebuilt* artifact, which these profiles do not have, so `acceptance.passed` is always `false`. The gate is `"complete": true` in `run-summary.json` plus a written `published/consensus-reference.json`. Piping through `tail` makes `$?` report the pipe's last stage — redirect to a file if you need the exit code.
- **Analyzer output lands in `tools/binrecon/out/<name>/published/`** as `analysis-reference-ida.json`, `analysis-reference-ghidra.json`, `analysis-reference-angr.json` and `consensus-reference.json`.
- **Disabling an analyzer requires a written reason.** Set `enabled: false` in the profile *and* record why in that driver's `divergences.md`, naming the exact error. A disablement without a recorded reason is a defect. Precedent: `profiles/vga-reloc.json` disables angr because its CFGFast misdisassembles six bytes at 7760 inside `_emu486`.
- **Ghidra cannot run from this worktree without a redirected `output_dir`.** Every Ghidra run started here aborts before any analysis with `binrecon: ghidra reference adapter failed: Ghidra failed with exit code 1`, whose real cause is only in the adapter's `.ghidra.log`: `ERROR (HeadlessAnalyzer) Abort due to Headless analyzer error: Path element starting with '.' is not permitted`. Ghidra 12.1 refuses any project path containing a dot-prefixed element; `binrecon` puts its workspace under the profile's `output_dir`, and this checkout is `/d/RhapsodiOS/.claude/worktrees/cirrus-thinkpad-recon`, so the path contains `.claude`. **This is a property of the checkout location, not of the profile or the binary.** Workaround: rerun with `output_dir` pointed at a dot-free path (a scratch directory outside the worktree) to reach Ghidra's real behaviour on the binary; **leave the committed `output_dir` unchanged** — it is correct and works as-is from the main checkout at `D:\RhapsodiOS`. Do not disable Ghidra on the strength of this error: it says nothing about the binary, and a disablement still needs a real, recorded reason.
- **`IBMThinkPad760EDDisplayDriver_reloc` carries `cpu_subtype = 4`** (`CPU_SUBTYPE_486`), the same value that made IDA's loader auto-select the legacy `80486p` processor module for `VGA_reloc`. The `-pmetapc` force committed as `8d8cfd20` is already in the IDA adapter and applies here. `CirrusLogicGD5434DisplayDriver_reloc` is `cpu_subtype = 3`.
- **Resolve every constant to its definition, never to a comment beside it.** The invented sources being replaced carry invented comments; treat none of them as evidence.
- **`parity_check.py` compares symbol NAMES only.** A `static`-versus-`external` change is invisible to it. Verify linkage by reading the rebuilt nlist with `binrecon.macho.read_macho` and checking each symbol's `binding` and `section`.
- **Never claim a ledger status stronger than the work performed.** `assembly-matched` means the rebuilt instruction stream was read against the reference. `control-flow-confirmed` means block shape and call targets were checked but not every instruction. A function written but not yet verified against a rebuilt binary stays `unexamined` or `signature-confirmed`, with the reasoning in `divergences.md`.
- **Commit messages** start with `drvCirrusLogicGD5434: `, `drvIBMThinkPad760EDDisplay: `, `binrecon: ` or `drivers-i386: `, run one to two lines, and describe what the change does rather than listing files. **No metadata, no `Co-Authored-By`, no "Generated with" trailer.**
- **`--reviewer` on every `binrecon ledger` call is `Pat Raynor`** — the repository's git user. Do not invent a different reviewer identity.

### Driving the Rhapsody guest build

Tasks 5 and 10 build on a remote Rhapsody host, not locally. The mechanism is
PuTTY over the host named in `vm/vm.conf`, exactly as
`docs/drivers/drvVGA-baseline-build.md` documents. Push the driver tree and the
script, then run it:

```bash
cd /d/RhapsodiOS/.claude/worktrees/cirrus-thinkpad-recon
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2 | tr -d '\r')
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2 | tr -d '\r')
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" src/drivers-i386/video/<driver-dir> root@$HOST:/build/source/src/drivers-i386/video/
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" vm/build-i386-video-recon.sh root@$HOST:/build/source/vm/
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'tr -d "\r" < /build/source/vm/build-i386-video-recon.sh > /tmp/br && mv /tmp/br /build/source/vm/build-i386-video-recon.sh; sh /build/source/vm/build-i386-video-recon.sh <driver-dir>' > /tmp/video-build.log 2>&1
echo "EXIT=$?"
```

Read the result from `/tmp/video-build.log`. To bring a rebuilt binary back for
`parity_check.py`, `pscp` it from the guest into `out/i386/` on the host, which
is gitignored. **Never print the password**; always read it from `vm/vm.conf`
into a shell variable as above.
- **Do not touch** `src/kernel-7/**`, `src/drivers-i386/video/drvVGA/**`, any other driver, or any binrecon tooling. The four Number9 drivers, both Weitek drivers and `MatroxMGA2064WDisplayDriver` are explicitly excluded.
- **Other sessions commit to this branch concurrently and have swept staged changes into their own commits.** Stage and commit in one shell invocation, promptly. If unrelated changes appear mid-work, leave them alone.

### Reference function partition — Cirrus

21 functions, `__text` 0–4388. Sizes are gaps between consecutive symbol addresses; IDA's extents may run 1–3 bytes shorter where the linker pads with `nop`, which is normal and is not an analyzer disagreement. All 21 are in the symbol table.

| Addr | Size | Symbol | TU |
| --- | --- | --- | --- |
| 0 | 556 | `-[CirrusLogicGD5434DisplayDriver initFromDeviceDescription:]` | 1 |
| 556 | 156 | `-[CirrusLogicGD5434DisplayDriver selectMode]` | 1 |
| 712 | 92 | `-[CirrusLogicGD5434DisplayDriver enterLinearMode]` | 1 |
| 804 | 88 | `-[CirrusLogicGD5434DisplayDriver revertToVGAMode]` | 1 |
| 892 | 768 | `-[CirrusLogicGD5434DisplayDriver determineConfiguration]` | 1 |
| 1660 | 32 | `-[CirrusLogicGD5434DisplayDriver isValidPCIAssignedBaseAddress:]` | 1 |
| 1692 | 584 | `-[CirrusLogicGD5434DisplayDriver setPCIConfiguration]` | 1 |
| 2276 | 1020 | `-[CirrusLogicGD5434DisplayDriver setMode:]` | 1 |
| 3296 | 32 | `-[CirrusLogicGD5434DisplayDriver clearScreen]` | 1 |
| 3328 | 60 | `-[CirrusLogicGD5434DisplayDriver name]` | 1 |
| 3388 | 140 | `-[CirrusLogicGD5434DisplayDriver setPendingDisplayMode:]` | 1 |
| 3528 | 16 | `-[CirrusLogicGD5434DisplayDriver displayModeCount]` | 1 |
| 3544 | 16 | `-[CirrusLogicGD5434DisplayDriver displayModes]` | 1 |
| 3560 | 16 | `-[CirrusLogicGD5434DisplayDriver displayMemorySize]` | 1 |
| 3576 | 12 | `-[CirrusLogicGD5434DisplayDriver ramdacSpeed]` | 1 |
| 3588 | 336 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setTransferTable:count:]` | 2 |
| 3924 | 80 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setBrightness:token:]` | 2 |
| 4004 | 84 | `_SetGammaValue` (local) | 2 |
| 4088 | 276 | `-[CirrusLogicGD5434DisplayDriver(ProgramDAC) setGammaTable]` | 2 |
| 4364 | 12 | `+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]` | glue |
| 4376 | 12 | `+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]` | glue |

TU 1 is `CirrusLogicGD5434DisplayDriver.m`, TU 2 is `ProgramDAC.m`, glue is the build-generated `CirrusLogicGD5434DisplayDriver_instance.m`.

Data symbols the rewrite must reproduce by name:

- `__TEXT,__const`: `_gamma16`, `_gamma8`, `_vgaMode`, `_GD5434_mode_640_8_60`, `_GD5434_mode_640_8_75`, `_GD5434_mode_640_15_60`, `_GD5434_mode_640_15_75`, `_GD5434_mode_640_24_60`, `_GD5434_mode_640_24_75`, `_GD5434_mode_800_8_60`, `_GD5434_mode_800_8_75`, `_GD5434_mode_800_15_60`, `_GD5434_mode_800_15_75`, `_GD5434_mode_800_24_60`, `_GD5434_mode_1024_8_60`, `_GD5434_mode_1024_8_75`, `_GD5434_mode_1024_15_60`, `_GD5434_mode_1024_15_75`, `_GD5434_mode_1152_8_60`, `_GD5434_mode_1152_8_75`, `_GD5434_mode_1152_15_60`, `_GD5434_mode_1280_8_60`, `_GD5434_mode_1280_8_70`, `_GD5434_defaultMode`, `_GD5434_modeTableCount`, `_GD5446_mode_640_15_60`, `_GD5446_mode_640_15_75`, `_GD5446_mode_800_15_60`, `_GD5446_mode_800_15_75`, `_GD5446_mode_1152_8_60`, `_GD5446_mode_1152_8_75`, `_GD5446_mode_1152_15_75`, `_GD5446_mode_1280_8_60`, `_GD5446_mode_1280_8_70`, `_GD5446_defaultMode`, `_GD5446_modeTableCount`
- `__DATA,__data`: `_GD5434_modeTable`, `_GD5446_modeTable`
- `__DATA,__bss`: `_xxx.86`, `_xxx.89`, `_xxx.92` (24 bytes total; gcc's naming for function-scope statics)
- `__DATA,__common`: `_CirrusLogicGD5434DisplayDriver_instance` (from the generated TU)

Undefined imports: `_IOFree`, `_IOLog`, `_IOMalloc`, `_bzero`, `_objc_msgSend`, `_objc_msgSendSuper`, and class references `IODevice`, `IOFrameBufferDisplay`, `Object`.

`__TEXT,__cstring` (571 bytes) — every one of these must appear in the rebuilt binary:

```
%s: Selected mode not supported.\n
%s: Trying default mode.\n
%s: Default mode not supported!\n
%s: Unable to map frame buffer\n
%s: Cirrus Logic CL-GD543X or CL-GD5446 not found\n
Cirrus Logic GD5430
Cirrus Logic GD5434
Cirrus Logic GD5436
Cirrus Logic GD5446
Unknown device
%s: %s detected (%d Bytes)\n
Bus Type
PCI
%s: unsupported PCI hardware.
%s: PCI Dev: %d Func: %d Bus: %d\n
%s: Can't set memory range, using default.\n
%s: Can't set to default range either!\n
%s: Incorrect number of address ranges: %d.\n
CirrusLogicGD5434DisplayDriver
%s: Invalid brightness level `%d'\n
```

### Reference function partition — ThinkPad

38 functions, `__text` 0–18204. In scope: 0–6552.

| Addr | Size | Symbol | TU |
| --- | --- | --- | --- |
| 0 | 56 | `_set555Mode` (local) | 1 |
| 56 | 780 | `-[IBMThinkPad760EDDisplayDriver initFromDeviceDescription:]` | 1 |
| 836 | 128 | `-[IBMThinkPad760EDDisplayDriver updateModeTable]` | 1 |
| 964 | 116 | `-[IBMThinkPad760EDDisplayDriver selectMode]` | 1 |
| 1080 | 104 | `-[IBMThinkPad760EDDisplayDriver defaultMode]` | 1 |
| 1184 | 628 | `-[IBMThinkPad760EDDisplayDriver enterLinearMode]` | 1 |
| 1812 | 216 | `-[IBMThinkPad760EDDisplayDriver revertToVGAMode]` | 1 |
| 2028 | 168 | `-[IBMThinkPad760EDDisplayDriver getModeInfo:]` | 1 |
| 2196 | 396 | `-[IBMThinkPad760EDDisplayDriver determineConfiguration:]` | 1 |
| 2592 | 32 | `-[IBMThinkPad760EDDisplayDriver isValidPCIAssignedBaseAddress:]` | 1 |
| 2624 | 676 | `-[IBMThinkPad760EDDisplayDriver setPCIConfiguration]` | 1 |
| 3300 | 544 | `-[IBMThinkPad760EDDisplayDriver setPendingDisplayMode:]` | 1 |
| 3844 | 84 | `-[IBMThinkPad760EDDisplayDriver getDisplayDeviceState]` | 1 |
| 3928 | 80 | `-[IBMThinkPad760EDDisplayDriver setDisplayDeviceState:]` | 1 |
| 4008 | 168 | `-[IBMThinkPad760EDDisplayDriver unlockRegisters]` | 1 |
| 4176 | 168 | `-[IBMThinkPad760EDDisplayDriver lockRegisters]` | 1 |
| 4344 | 92 | `-[IBMThinkPad760EDDisplayDriver free]` | 1 |
| 4436 | 12 | `-[IBMThinkPad760EDDisplayDriver displayModeCount]` | 1 |
| 4448 | 12 | `-[IBMThinkPad760EDDisplayDriver displayModes]` | 1 |
| 4460 | 16 | `-[IBMThinkPad760EDDisplayDriver displayMemorySize]` | 1 |
| 4476 | 12 | `-[IBMThinkPad760EDDisplayDriver ramdacSpeed]` | 1 |
| 4488 | 72 | `-[IBMThinkPad760EDDisplayDriver readCMOS:]` | 1 |
| 4560 | 1088 | `-[IBMThinkPad760EDDisplayDriver reportSystemConfiguration]` | 1 |
| 5648 | 60 | `-[IBMThinkPad760EDDisplayDriver name]` | 1 |
| 5708 | 336 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setTransferTable:count:]` | 2 |
| 6044 | 80 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setBrightness:token:]` | 2 |
| 6124 | 84 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) SetGammaValueRed:Green:Blue:Level:]` | 2 |
| 6208 | 232 | `-[IBMThinkPad760EDDisplayDriver(TransferTable) setGammaTable]` | 2 |
| 6440 | 88 | `_smapi_asm` (**external**) | 3 |
| 6528 | 12 | `+[IBMThinkPad760EDDisplayDriverKernelServerInstance kernelServerInstance]` | glue |
| 6540 | 12 | `+[IBMThinkPad760EDDisplayDriverVersion driverKitVersionForIBMThinkPad760EDDisplayDriver]` | glue |
| 6552 | 268 | `-[vidBIOS init]` | **deferred** |
| 6820 | 108 | `-[vidBIOS free]` | **deferred** |
| 6928 | 696 | `-[vidBIOS int10:outregs:iorange:ionum:smmport:]` | **deferred** |
| 7624 | 44 | `-[vidBIOS int10:outregs:iorange:ionum:]` | **deferred** |
| 7668 | 16 | `-[vidBIOS scratchSegment]` | **deferred** |
| 7684 | 24 | `-[vidBIOS realToVirtual::]` | **deferred** |
| 7708 | 10496 | `_emu486` (**external**) | **deferred** |

TU 1 is `IBMThinkPad760ED.m`, TU 2 is `TransferTable.m`, TU 3 is the assembly file. The six `vidBIOS` methods carry no symbol-table entry and are recovered from `__OBJC,__inst_meth`, so **`--objc-methods` is mandatory** on this binary's `source-map` run.

Data symbols in scope:

- `__TEXT,__const`: `_gamma8`, `_mode_640_8_60`, `_mode_640_8_75`, `_mode_640_15_60`, `_mode_640_15_75`, `_mode_800_8_60`, `_mode_800_8_75`, `_mode_800_15_60`, `_mode_800_15_75`, `_mode_1024_8_60`, `_mode_1024_8_75`, `_mode_1024_15_60`, `_mode_1024_15_75`, `_mode_1280_8_60`, `_mode_1280_8_75`, `_defaultMode` (external), `_modeTableCount` (external)
- `__DATA,__data`: `_ThinkPad760EDModeTable` (external)
- `__DATA,__bss`: `_xxx.86`, `_xxx.89`, `_xxx.92`, `_xxx.8`, `_xxx.11`, `_xxx.14` (36 bytes). The `.8/.11/.14` group is most likely `vidBIOS.m`'s and therefore deferred; **do not assume this** — attribute each group during the report pass.
- `__DATA,__common`: `_IBMThinkPad760EDDisplayDriver_instance`

Undefined imports: `_IOForkThread`, `_IOFree`, `_IOFreeLow`, `_IOLog`, `_IOMalloc`, `_IOMallocLow`, `_IOMapPhysicalIntoIOTask`, `_IOPhysicalFromVirtual`, `_IOSetThreadPriority`, `_IOSleep`, `_IOUnmapPhysicalFromIOTask`, `_IOVmTaskSelf`, `_bzero`, `_memset`, `_objc_msgSend`, `_objc_msgSendSuper`, `_page_size`. Several of these (`_IOForkThread`, `_IOMallocLow`, `_IOPhysicalFromVirtual`, `_page_size`) are probably `vidBIOS.m`'s; the report pass records which.

`__TEXT,__cstring` is 1416 bytes and includes, among others:

```
%s: vidBIOS alloc failure
%s: Unable to call SMAPI at port 0x%04x\n
%s: Cannot use requested display mode. \nTrying default mode.\n
%s: Error: Unable to map frame buffer\n
%s: Unable to set refresh rate using SMAPI\n
%s: TVGA BIOS SetMode failure (%04x)\n
%s: Vesa BIOS SetMode failure (%04x)\n
%s: Trident Cyber938x not detected - trying anyway\n
%s: Chip ID=0x%02x, Revision=0x%02x\n
%s: Detected Trident Cyber938x (rev 0x%02x)\n
%s: Found %d MB DRAM\n
%s: Error: Unsupported PCI hardware\n
%s: Error: Can't set memory range, using default.\n
%s: Error: Can't set to default range either!\n
%s: Error: Incorrect number of address ranges: %d.\n
%s: System ID = 0x%04x\n
%s: System BIOS revision %01x.%02x\n
%s: System management BIOS revision %01x.%02x\n
%s: SMAPI revision %01x.%02x\n
%s: Video BIOS revision %01x.%02x\n
%s: Slave controller revision %01x.%02x\n
Intel
AMD
Unknown
%s: %s CPU Family %d, Model %d, Stepping %d\n
%s: CPU clock (Int/Ext) = 
%d
?
/%d MHz\n
/? MHz\n
Monochrome STN
Monochrome TFT
Color STN
Color TFT
```

Read the full section from the binary during the report pass rather than trusting this excerpt to be complete.

### Where our sources stand

`src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/`:

- `Makefile` — `NAME = CirrusLogicGD5434` (line 10), `GLOBAL_RESOURCES = Default.table` (16), `LOCAL_RESOURCES = Localizable.strings` (18), `TOOLS = CirrusLogicGD5434.lksproj` (20)
- `CirrusLogicGD5434.lksproj/Makefile` — `NAME = CirrusLogicGD5434` (line 10), `CLASSES = CirrusLogicGD5434DisplayDriver.m` (16), `HFILES = CirrusLogicGD5434DisplayDriver.h` (18)
- `CirrusLogicGD5434.lksproj/CirrusLogicGD5434DisplayDriver.{h,m}` — 157 + 447 lines, invented, subclasses `IOPCIDirectDevice`, zero shared symbols with the reference
- `CirrusLogicGD5434.lksproj/Load_Commands.sect` — **28 bytes; must be 164**
- `Default.table` — hand-approximated, wrong in five keys
- No `Display.modes`, no variant tables, no `Help`

`src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/`:

- `Makefile` — `NAME` correct (line 10), same resource lines at 16/18/20
- `IBMThinkPad760EDDisplayDriver.lksproj/Makefile` — `NAME` correct, `CLASSES = IBMThinkPad760EDDisplayDriver.m`, `HFILES = IBMThinkPad760EDDisplayDriver.h`
- `IBMThinkPad760EDDisplayDriver.lksproj/IBMThinkPad760EDDisplayDriver.{h,m}` — 61 + 305 lines, invented, zero shared symbols
- `IBMThinkPad760EDDisplayDriver.lksproj/Load_Commands.sect` — **28 bytes; must be 164**
- `Default.table` — matches Apple's byte for byte apart from whitespace; verify rather than assume
- No `Display.modes`, no `ThinkPad760.{table,modes}`, no `ThinkPad760.strings`, no `Help`

### The correct Load_Commands.sect

Both references embed the identical 164-byte `Loaded Server,Load Commands` section, SHA-256 `78FEAAD1F976BAF28AFE83EC73EC4393BA16F514FEB3EED3E67609FB29FFED7F`. `src/drivers-i386/video/drvS3Generic/S3GenericDisplayDriver.drvproj/S3GenericDisplayDriver.lksproj/Load_Commands.sect` already hashes to exactly that. Copy it; do not retype it.

Its content, for reference (note the trailing space on line 1 and the trailing newline after `WIRE`):

```
# 
# This loadable kernel driver does not use a Mig-generated interface,
# so no handler or server interface is specified.
#
# This driver must be wired down.
WIRE
```

---

## Task 1: Cirrus profile, project fixes and resources

Everything for track A that needs no disassembly. The `Load_Commands.sect` and `NAME` fixes matter more than they look: with `NAME = CirrusLogicGD5434` the build produces `CirrusLogicGD5434_reloc` inside `CirrusLogicGD5434.config`, so every later "the reloc exists" gate would pass while testing the wrong artifact.

**Files:**
- Create: `tools/binrecon/profiles/cirruslogic-gd5434.json`
- Create: `vm/build-i386-video-recon.sh`
- Modify: `src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/Makefile:10,16,18,20`
- Rename: `.../CirrusLogicGD5434.drvproj/CirrusLogicGD5434.lksproj` → `.../CirrusLogicGD5434DisplayDriver.lksproj`
- Modify: `.../CirrusLogicGD5434DisplayDriver.lksproj/Makefile:10`
- Replace: `.../CirrusLogicGD5434DisplayDriver.lksproj/Load_Commands.sect`
- Replace: `.../CirrusLogicGD5434.drvproj/Default.table`
- Create: `.../CirrusLogicGD5434.drvproj/{Display,TwoMeg,PCIOneMB,PCITwoMB,GD5446_PCIOneMB,GD5446_PCITwoMB}.modes` and the five variant `.table` files
- Create: `.../CirrusLogicGD5434.drvproj/English.lproj/` — five `.strings` files, replaced `Localizable.strings`, and `Help/`

**Interfaces:**
- Consumes: nothing.
- Produces: `tools/binrecon/profiles/cirruslogic-gd5434.json` with `output_dir` `../out/cirruslogic-gd5434`, so analyzer output lands in `tools/binrecon/out/cirruslogic-gd5434/published/`. Also produces `vm/build-i386-video-recon.sh`, invocable as `sh vm/build-i386-video-recon.sh drvCirrusLogicGD5434` and `... drvIBMThinkPad760EDDisplay`.

- [ ] **Step 1: Write the profile**

`tools/binrecon/profiles/cirruslogic-gd5434.json`. All three analyzers enabled — this binary is `cpu_subtype = 3` with no emulator, so all three are expected to run cleanly.

```json
{
  "schema_version": "profile-v1",
  "name": "drvCirrusLogicGD5434 reconstruction",
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
  "output_dir": "../out/cirruslogic-gd5434"
}
```

- [ ] **Step 2: Validate the profile**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc' && ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/cirruslogic-gd5434.json
```

Expected: the resolved absolute path, size **41992**, SHA-256 `7DA038CCEA1CDE68B6CF2ACF4D12EE5056E7F0248ADD34D451FB96EA79C13D0D`, no rebuilt artifact. If the SHA-256 differs, **stop** — the reference on disk is not the one this plan was written against.

- [ ] **Step 3: Rename the lksproj and fix both NAMEs**

```bash
cd /d/RhapsodiOS/src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj && git mv CirrusLogicGD5434.lksproj CirrusLogicGD5434DisplayDriver.lksproj
```

Then in `CirrusLogicGD5434.drvproj/Makefile`, line 10 becomes:

```make
NAME = CirrusLogicGD5434DisplayDriver
```

and line 20 becomes:

```make
TOOLS = CirrusLogicGD5434DisplayDriver.lksproj
```

and in `CirrusLogicGD5434DisplayDriver.lksproj/Makefile`, line 10 becomes:

```make
NAME = CirrusLogicGD5434DisplayDriver
```

The reference's `Loaded Server,Server Name` section contains exactly `CirrusLogicGD5434DisplayDriver`, and `Loaded Server,Instance Var` contains `CirrusLogicGD5434DisplayDriver_instance`, which is what the lksproj `NAME` drives.

- [ ] **Step 4: Install the correct Load_Commands.sect**

```bash
cd /d/RhapsodiOS && cp src/drivers-i386/video/drvS3Generic/S3GenericDisplayDriver.drvproj/S3GenericDisplayDriver.lksproj/Load_Commands.sect src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Load_Commands.sect && sha256sum src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Load_Commands.sect
```

Expected: `78feaad1f976baf28afe83ec73ec4393ba16f514feb3eed3e67609fb29ffed7f`, file size 164.

- [ ] **Step 5: Copy Apple's config tables and resources**

```bash
cd /d/RhapsodiOS && REF='C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config' && DST=src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj && cp "$REF"/*.table "$REF"/*.modes "$DST"/ && rm -rf "$DST/English.lproj" && cp -r "$REF/English.lproj" "$DST/English.lproj" && find "$DST" -type f | sort
```

Expected listing: `Default.table`, `Display.modes`, `DriverInfo`, `GD5446_PCIOneMB.{modes,table}`, `GD5446_PCITwoMB.{modes,table}`, `Makefile`, `Makefile.postamble`, `Makefile.preamble`, `PCIOneMB.{modes,table}`, `PCITwoMB.{modes,table}`, `TwoMeg.{modes,table}`, `English.lproj/Localizable.strings`, `English.lproj/{GD5446_PCIOneMB,GD5446_PCITwoMB,PCIOneMB,PCITwoMB,TwoMeg}.strings`, `English.lproj/Help/TableOfContents.rtf`, `English.lproj/Help/CL_GD5434.rtfd/*` (4 files), `English.lproj/Help/CL_GD5446.rtfd/*` (4 files), plus the lksproj.

Verify `Default.table` now reads `"Memory Maps" = "0x04000000-0x04ffffff 0xa0000-0xbffff 0xc0000-0xcffff";` and `"VGA Memory Maps" = ...` — the invented file had `0x00000000-0x04ffffff` and a nonexistent `"VGA Vendor"` key.

- [ ] **Step 6: Update the resource lists**

`CirrusLogicGD5434.drvproj/Makefile` line 16:

```make
GLOBAL_RESOURCES = Default.table Display.modes TwoMeg.table TwoMeg.modes\
                   PCIOneMB.table PCIOneMB.modes PCITwoMB.table PCITwoMB.modes\
                   GD5446_PCIOneMB.table GD5446_PCIOneMB.modes\
                   GD5446_PCITwoMB.table GD5446_PCITwoMB.modes
```

line 18:

```make
LOCAL_RESOURCES = Localizable.strings TwoMeg.strings PCIOneMB.strings\
                  PCITwoMB.strings GD5446_PCIOneMB.strings GD5446_PCITwoMB.strings\
                  Help
```

`drvS3Generic`'s Makefile is the model for the continuation-line style; match it.

- [ ] **Step 7: Write the build script**

`vm/build-i386-video-recon.sh`. It dispatches through `case` rather than a predicate function: Rhapsody's 1999 Bourne `/bin/sh` applies `set -e` to any function returning nonzero, including one called from an `if` condition, which kills the script. That is also why `set -e` is not used — a driver that fails must set `fail=1` and let the rest run.

The ThinkPad arm is deliberately different: it gates on **object files**, not on a `_reloc`, because its link cannot succeed until drvVGA supplies `vidBIOS.m` and `emu486`.

```sh
#!/bin/sh
# Build the i386 video drivers under reconstruction; stage config bundles.
#
# drvCirrusLogicGD5434 must link: its _reloc is the deliverable.
# drvIBMThinkPad760EDDisplay cannot link yet — vidBIOS.m and _emu486 are
# owned by the drvVGA reconstruction — so its gate is that the three
# in-scope objects compile.

export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin
OUT=/build/out/i386
VIDEO=/build/source/src/drivers-i386/video
mkdir -p "$OUT"

FW=/System/Library/Frameworks/System.framework
if [ ! -L "$FW/PrivateHeaders" ]; then
	echo "WARNING: PrivateHeaders is not a symlink; builds may miss kern headers"
fi

run_make() {
	src="$1"
	if [ ! -f "$src/Makefile" ]; then
		echo "MISSING $src/Makefile" >&2
		MAKE_EC=127
		return 1
	fi
	cd "$src"
	find . -type f \( -name Makefile -o -name 'Makefile.*' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done
	gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386 2>&1
	MAKE_EC=$?
	return 0
}

build_reloc() {
	name="$1"	# CirrusLogicGD5434DisplayDriver
	dir="$2"	# drvCirrusLogicGD5434
	proj="$3"	# CirrusLogicGD5434.drvproj
	src="$VIDEO/$dir"
	echo "======== build $name ($dir) ========"
	run_make "$src" || return 1
	ec=$MAKE_EC
	echo "make exit=$ec for $name"

	reloc=`find "$src" -name "${name}_reloc" -type f 2>/dev/null | head -1`
	if [ -z "$reloc" ] || [ ! -f "$reloc" ]; then
		echo "FAILED: no ${name}_reloc for $name" >&2
		find "$src" \( -name '*reloc*' -o -name '*.config' \) 2>/dev/null | head -40 >&2 || true
		return 1
	fi
	file "$reloc"

	dst="$OUT/$dir/$name.config"
	rm -rf "$dst"
	mkdir -p "$dst"
	cp -p "$reloc" "$dst/"
	bundle=`find "$src" -name "$name" -type f 2>/dev/null | head -1`
	if [ -n "$bundle" ]; then
		cp -p "$bundle" "$dst/"
		echo "staged version bundle $name"
	else
		echo "WARNING: no $name version bundle produced" >&2
	fi
	for f in "$src/$proj"/*.table "$src/$proj"/*.modes; do
		[ -f "$f" ] || continue
		cp -p "$f" "$dst/"
	done
	if [ -d "$src/$proj/English.lproj" ]; then
		cp -rp "$src/$proj/English.lproj" "$dst/"
	fi
	echo "staged $dst"
	ls -la "$dst"
	return 0
}

build_objects() {
	name="$1"	# IBMThinkPad760EDDisplayDriver
	dir="$2"	# drvIBMThinkPad760EDDisplay
	shift 2		# remaining args are the required object basenames
	src="$VIDEO/$dir"
	echo "======== build $name ($dir), objects only ========"
	run_make "$src" || return 1
	ec=$MAKE_EC
	echo "make exit=$ec for $name (a link failure here is expected)"

	miss=0
	for o in $*; do
		found=`find "$src" -name "$o" -type f 2>/dev/null | head -1`
		if [ -z "$found" ]; then
			echo "FAILED: $o was not compiled" >&2
			miss=1
		else
			echo "compiled $found"
		fi
	done
	if [ $miss -ne 0 ]; then
		return 1
	fi
	echo "NOTE: $name does not link until drvVGA supplies vidBIOS.m and emu486."
	return 0
}

if [ $# -eq 0 ]; then
	TARGETS="drvCirrusLogicGD5434 drvIBMThinkPad760EDDisplay"
else
	TARGETS="$*"
fi

fail=0
built=
for d in $TARGETS; do
	case "$d" in
	drvCirrusLogicGD5434)
		build_reloc CirrusLogicGD5434DisplayDriver drvCirrusLogicGD5434 CirrusLogicGD5434.drvproj || fail=1
		;;
	drvIBMThinkPad760EDDisplay)
		build_objects IBMThinkPad760EDDisplayDriver drvIBMThinkPad760EDDisplay \
			IBMThinkPad760ED.o TransferTable.o smapi.o || fail=1
		;;
	*)
		echo "unknown driver: $d" >&2
		fail=1
		continue
		;;
	esac
	built="$built $d"
done

echo "======== summary ========"
for d in $built; do
	find "$OUT/$d" -type f 2>/dev/null | sort || true
done
echo "=== video-recon done fail=$fail built:$built ==="
exit $fail
```

- [ ] **Step 8: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/profiles/cirruslogic-gd5434.json vm/build-i386-video-recon.sh src/drivers-i386/video/drvCirrusLogicGD5434 && git commit -m "drvCirrusLogicGD5434: correct the project name, wire directive and config resources

Add the binrecon profile and the video reconstruction build harness."
```

---

## Task 2: Cirrus report pass

Runs the analyzers, establishes the pre-rewrite source map, and decompiles all 21 functions into a divergence document. Nothing in `.lksproj` is rewritten here.

**Files:**
- Create: `src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md`
- Create: `src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json`
- Create: `src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/ledger.json`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/cirruslogic-gd5434.json` from Task 1.
- Produces: a `divergences.md` whose per-function findings are the sole input to Tasks 3 and 4 — those tasks are written from this document, not from a fresh disassembly. Findings are keyed by reference address so the rewrite can cite them.

- [ ] **Step 1: Run the analyzers**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc' && mkdir -p src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc && ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/cirruslogic-gd5434.json --ledger src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/ledger.json > /tmp/cirrus-analyze.log 2>&1; echo "exit=$?"
```

Expected: `exit=1`, which is success for a reference-only profile (see Global Constraints). Confirm the real gate:

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "import json;d=json.load(open('tools/binrecon/out/cirruslogic-gd5434/run-summary.json'));print('complete',d['complete']);print('consensus',d['consensus']['reference']);print([a['name'] for a in d['analyzers']])"
```

Expected: `complete True`, a `consensus.reference.path` of `published/consensus-reference.json`, and `['IDA', 'Ghidra', 'angr']`.

If `complete` is `False`, read `/tmp/cirrus-analyze.log` for the aborting analyzer, set that analyzer's `enabled` to `false` in the profile, rerun, and record the exact error text in `divergences.md` under an "Evidence" heading — Step 4 requires it.

- [ ] **Step 2: Build the pre-rewrite source map**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/cirruslogic-gd5434/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc" --source-dir src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj --repo-root . --objc-methods --output src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json
```

Then check the partition:

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json'))
for k in ('mapped','unmapped','boundary_disputed','duplicate_candidates'): print(k, len(m[k]))
print('sha', m['reference_sha256'])
print('bytes', sum(e['size'] for k in ('mapped','unmapped','boundary_disputed') for e in m[k]))"
```

Expected: `mapped 5`, `unmapped 16`, `boundary_disputed 0`, `duplicate_candidates 0`, sha `7DA038CCEA1CDE68B6CF2ACF4D12EE5056E7F0248ADD34D451FB96EA79C13D0D`, bytes **`4354`**.

The five mapped entries are at reference addresses **0, 712, 804, 3296 and 3544** — `initFromDeviceDescription:`, `enterLinearMode`, `revertToVGAMode`, `clearScreen` and `displayModes`. The invented `CirrusLogicGD5434DisplayDriver.m` declares those five selector names on a class of the same name, so `source-map` pairs them. **That is a name collision, not evidence of a matching implementation.** The tool matches `-[class selector]` symbols and nothing else; it has no view of what the bodies do, and here they do something else entirely — the invented class subclasses `IOPCIDirectDevice` rather than `IOFrameBufferDisplay` and its bodies are hand-written guesses. Treat all 21 functions as needing reconstruction. Do not "fix" the collision by renaming our invented source, and do not read a nonzero `mapped` as partial parity.

**The 34-byte shortfall against `__text`'s 4388 is expected and is not a finding.** IDA reports true function extents, and the linker pads between functions with `nop` to restore alignment. There are 14 such gaps of 1 to 3 bytes each, after `_selectMode` (553→556), `enterLinearMode` (710→712), `revertToVGAMode` (801→804), `determineConfiguration` (890→892), `isValidPCIAssignedBaseAddress:` (1658→1660), `setPCIConfiguration` (1689→1692), `setMode:` (2275→2276), `name` (3325→3328), `setPendingDisplayMode:` (3387→3388), `setTransferTable:count:` (3585→3588), `setBrightness:token:` (3921→3924), `_SetGammaValue` (4001→4004), `setGammaTable` (4086→4088) and the last glue function (4361→4364). The partition still spans 0 to 4388 with no unclaimed region, which is the property that matters. Confirm that span rather than the byte sum.

If `mapped` holds any address other than those five, another name collided; inspect which and note it in `divergences.md`.

- [ ] **Step 3: Read the full cstring and const sections**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
f=Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc')
data=f.read_bytes(); d=read_macho(f)
for s in d['sections']:
    if s['name'] in ('__TEXT,__cstring',) and s['size']:
        for t in data[s['offset']:s['offset']+s['size']].split(b'\0'):
            if t: print(repr(t))"
```

Expected: the 20 strings listed in this plan's Cirrus partition section. Any string in the binary that is absent from that list must be added to `divergences.md` — the list was transcribed by hand and the binary is authoritative.

- [ ] **Step 4: Write divergences.md**

`src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md`, modelled on `src/drivers-i386/video/drvVGA/reconstruction/divergences.md`. Required contents:

1. A header table: binary, Mach-O type, size, SHA-256, and the `BINRECON_REFERENCE` path.
2. An "Evidence" section: which analyzers ran, whether any was disabled and the verbatim error if so, and a statement that our source is disjoint from Apple's in behaviour — naming the five selectors whose names nevertheless collide, and saying that the collision is nominal and that none of the 21 functions has a counterpart implementation.
3. A "Source-file partition" section giving the three `__OBJC,__module_info` modules and their `__text` ranges (`CirrusLogicGD5434DisplayDriver.m` 0–3588, `ProgramDAC.m` 3588–4364, `CirrusLogicGD5434DisplayDriver_instance.m` 4364–4388), plus the class/category each defines.
4. **One numbered finding per function**, in address order, all 21. Each finding states: address, size, symbol; what the function does; which I/O ports, PCI config registers and DriverKit calls it touches; its callers and callees; which `__const`/`__data` symbols it reads; and every inference marked explicitly as an inference rather than an observation.
5. A "Static storage" section attributing `_xxx.86`, `_xxx.89` and `_xxx.92` each to the function that owns it.
6. A "What is not reconstructed" section naming the two generated glue functions at 4364 and 4376.

- [ ] **Step 5: Verify the document is complete**

```bash
cd /d/RhapsodiOS && grep -c '^### ' src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md && ./.venv-binrecon/Scripts/python.exe -c "
import json,re
m=json.load(open('src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json'))
doc=open('src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md').read()
missing=[e['reference_names'][0] for k in ('mapped','unmapped') for e in m[k] if e['reference_names'][0] not in doc]
print('functions absent from divergences.md:', missing)"
```

Expected: `functions absent from divergences.md: []`. Every reference symbol must be named somewhere in the document.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction && git commit -m "drvCirrusLogicGD5434: decompile the reference and record the parity ledger

Every one of the 21 functions is unmapped: our source shares no symbol with Apple's."
```

---

## Task 3: Cirrus ProgramDAC.m

The smaller translation unit first: 4 functions, 776 bytes, no PCI or mode-table logic. Written entirely from Task 2's findings for addresses 3588, 3924, 4004 and 4088.

**Files:**
- Create: `src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/ProgramDAC.m`
- Modify: `.../CirrusLogicGD5434DisplayDriver.lksproj/Makefile:16`

**Interfaces:**
- Consumes: `divergences.md` findings for 3588–4364; the `CirrusLogicGD5434DisplayDriver` class declared in `CirrusLogicGD5434DisplayDriver.h` (still the invented header at this point — declare the category against it and let Task 4 replace the header).
- Produces: `@implementation CirrusLogicGD5434DisplayDriver (ProgramDAC)` with exactly these four symbols, and no others:
  - `- (void)setTransferTable:(unsigned int *)table count:(int)count`
  - `- (void)setBrightness:(int)level token:(int)token`
  - `static void SetGammaValue(...)` — emitted as `_SetGammaValue`, **local** binding
  - `- (void)setGammaTable`

  Exact parameter types and return types come from the reference's `__OBJC,__meth_var_types` encodings, which Task 2 recorded. Task 4 relies on the category being importable from `CirrusLogicGD5434DisplayDriver.m` without a separate header.

- [ ] **Step 1: Confirm the selector signatures from the binary**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
f=Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc')
data=f.read_bytes(); d=read_macho(f)
for s in d['sections']:
    if s['name']=='__OBJC,__meth_var_types':
        for t in data[s['offset']:s['offset']+s['size']].split(b'\0'):
            if t: print(t.decode())"
```

Expected: type encodings such as `v12@0:4^I8` (void, self, _cmd, pointer-to-unsigned). Match each to its selector before writing a signature; do not guess from the method name.

- [ ] **Step 2: Write ProgramDAC.m**

Write the four functions from the Task 2 findings. Requirements that are not negotiable:

- The file's `@implementation` line is `@implementation CirrusLogicGD5434DisplayDriver (ProgramDAC)` — the category name is recorded in `__OBJC,__category` and appears in the symbol `.objc_category_name_CirrusLogicGD5434DisplayDriver_ProgramDAC`.
- `SetGammaValue` is a file-scope `static` C function, so the emitted symbol is `_SetGammaValue` with **local** binding. Declaring it non-static would change the linkage and silently break parity.
- Definition order in the file must be `setTransferTable:count:`, `setBrightness:token:`, `SetGammaValue`, `setGammaTable`, matching the reference's address order, because the compiler emits in source order and Task 5's parity check reads addresses.
- The brightness error path emits `"%s: Invalid brightness level `%d'\n"` — note the asymmetric backtick-quote pair, which is verbatim from the binary.
- Read `_gamma8` and `_gamma16` by their reference names.

- [ ] **Step 3: Add the file to the build**

`CirrusLogicGD5434DisplayDriver.lksproj/Makefile` line 16:

```make
CLASSES = CirrusLogicGD5434DisplayDriver.m ProgramDAC.m
```

The project will not compile at the end of this task: `ProgramDAC.m`'s category targets ivars that only Task 4's rewritten class declares, while `CirrusLogicGD5434DisplayDriver.m` is still the invented `IOPCIDirectDevice` subclass. That is fine — nothing is built until Task 5. Do **not** paper over it by adding ivars to the invented header.

- [ ] **Step 4: Verify the source map moves**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/cirruslogic-gd5434/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc" --source-dir src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj --repo-root . --objc-methods --output src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json'))
print('mapped', sorted(e['address'] for e in m['mapped']))
print('unmapped', len(m['unmapped']))"
```

Expected: `mapped [0, 712, 804, 3296, 3544, 3588, 3924, 4004, 4088]` and `unmapped 12`. The four new addresses are `ProgramDAC.m`'s; the leading five are Task 2's nominal collisions with the still-invented `CirrusLogicGD5434DisplayDriver.m` and stay put until Task 4 replaces it. If one of 3588, 3924, 4004 or 4088 is missing, the source-map scanner did not find that definition — check the selector spelling against the reference, including empty keywords.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvCirrusLogicGD5434 && git commit -m "drvCirrusLogicGD5434: write ProgramDAC.m from the reference disassembly

Maps the four gamma and brightness functions at 3588-4364."
```

---

## Task 4: Cirrus CirrusLogicGD5434DisplayDriver.m

The main translation unit: 15 functions, 3588 bytes, including the 1020-byte `setMode:` and the 768-byte `determineConfiguration`. Replaces the invented `.h` and `.m` outright.

**Files:**
- Replace: `src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/CirrusLogicGD5434DisplayDriver.m`
- Replace: `.../CirrusLogicGD5434DisplayDriver.lksproj/CirrusLogicGD5434DisplayDriver.h`

**Interfaces:**
- Consumes: `divergences.md` findings for 0–3588; the `ProgramDAC` category from Task 3.
- Produces: `@interface CirrusLogicGD5434DisplayDriver : IOFrameBufferDisplay` with the instance-variable layout the reference's `__OBJC,__instance_vars` records (196 bytes of ivar metadata), and the 15 methods listed in the partition table. The mode-table symbols named in the Global Constraints section are defined here and are what the rebuilt `__const` and `__data` sections are checked against.

- [ ] **Step 1: Read the reference ivar layout**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys,struct; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
f=Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc')
data=f.read_bytes(); d=read_macho(f)
S={s['name']:s for s in d['sections']}
def off(a):
    for s in d['sections']:
        if s['size'] and s['offset'] and s['address']<=a<s['address']+s['size']: return s['offset']+(a-s['address'])
def cs(a):
    o=off(a); return data[o:data.index(b'\0',o)].decode()
iv=S['__OBJC,__instance_vars']; n,=struct.unpack_from('<I',data,iv['offset'])
print('ivar count', n)
for i in range(n):
    nm,ty,ofs=struct.unpack_from('<III',data,iv['offset']+4+12*i)
    print('  %-28s %-12s offset=%d' % (cs(nm), cs(ty), ofs))"
```

Expected: 16 ivars with names, type encodings and offsets. **Reproduce these names and this order exactly** — the ivar list is part of the class's ABI and appears in the rebuilt binary's metadata.

- [ ] **Step 2: Write the header**

`CirrusLogicGD5434DisplayDriver.h`. Superclass is `IOFrameBufferDisplay`, imported from `<driverkit/IOFrameBufferDisplay.h>`. Declare the ivars in the exact order and with the exact names Step 1 printed, and declare the 15 methods. Delete every invented constant from the old header — the `CRTC_*`, `SEQ_*`, `GFX_*`, `ATTR_*` and `DisplayMode` definitions are inventions and none of them is evidence for anything.

- [ ] **Step 3: Write the implementation**

Write the 15 functions in the reference's address order, from the Task 2 findings. Requirements:

- Definition order matches the partition table: `initFromDeviceDescription:`, `selectMode`, `enterLinearMode`, `revertToVGAMode`, `determineConfiguration`, `isValidPCIAssignedBaseAddress:`, `setPCIConfiguration`, `setMode:`, `clearScreen`, `name`, `setPendingDisplayMode:`, `displayModeCount`, `displayModes`, `displayMemorySize`, `ramdacSpeed`.
- Define every `__const` and `__data` symbol named in the Global Constraints Cirrus list, with those exact names — **except `_gamma16` and `_gamma8`, which Task 3 already defined in `ProgramDAC.m`.** Both are `static`, so defining them again here compiles cleanly and silently produces four `__const` objects where the reference has two. Do not redefine them, and do not reference them from this file.
- The rewritten header **must** `#import <driverkit/IOFrameBufferDisplay.h>`. `ProgramDAC.m` includes no DriverKit headers of its own and reaches `IODisplayInfo`, the `IO_*BitsPerPixel` enumerators and `EV_SCREEN_MAX_BRIGHTNESS` transitively through this header. Dropping that import breaks `ProgramDAC.m` in a way whose error messages point at the wrong file.
- The 24 `_GD5434_mode_*` and `_GD5446_mode_*` records are `const`; `_GD5434_modeTable` and `_GD5446_modeTable` are mutable and live in `__DATA,__data`, which means they are non-const file-scope arrays populated at runtime by `determineConfiguration`.
- Every string in Task 2 Step 3's output appears verbatim, including the trailing newlines.
- `setMode:`'s register-write order is load-bearing; write it in the reference's order and do not reorder for readability.
- The class's `name` method returns the string `CirrusLogicGD5434DisplayDriver` found in `__cstring`.

- [ ] **Step 4: Verify the source map is complete**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/cirruslogic-gd5434/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc" --source-dir src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj --repo-root . --objc-methods --output src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/source-map.json'))
print('mapped', len(m['mapped']), 'unmapped', len(m['unmapped']))
print('still unmapped:', [e['reference_names'][0] for e in m['unmapped']])"
```

Expected: `mapped 19 unmapped 2`, and the two remaining are `+[CirrusLogicGD5434DisplayDriverKernelServerInstance kernelServerInstance]` and `+[CirrusLogicGD5434DisplayDriverVersion driverKitVersionForCirrusLogicGD5434DisplayDriver]` — the build-generated glue, which is correct to leave unmapped.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvCirrusLogicGD5434 && git commit -m "drvCirrusLogicGD5434: write the display driver class from the reference disassembly

Replaces the invented IOPCIDirectDevice subclass with Apple's IOFrameBufferDisplay one."
```

---

## Task 5: Cirrus build and parity check

First point at which anything is compiled. Ends track A.

**Files:**
- Modify: `src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md` — add a "Build and parity" section
- Modify: `src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/ledger.json`

**Interfaces:**
- Consumes: the sources from Tasks 3 and 4, `vm/build-i386-video-recon.sh` from Task 1.
- Produces: a linked `CirrusLogicGD5434DisplayDriver_reloc` staged under `/build/out/i386/drvCirrusLogicGD5434/` in the guest, and a ledger whose entries carry a status justified by what was actually verified.

- [ ] **Step 1: Build in the Rhapsody guest**

Run `sh vm/build-i386-video-recon.sh drvCirrusLogicGD5434` in the guest, using the same mechanism the other `vm/build-i386-*.sh` scripts are driven by in this repo.

Expected in the output: `make exit=0 for CirrusLogicGD5434DisplayDriver`, a `file` line identifying the reloc, and `=== video-recon done fail=0 built: drvCirrusLogicGD5434 ===`.

If `gnumake` fails, fix the compile errors and rerun. Do not proceed with a nonzero `fail`.

- [ ] **Step 2: Copy the rebuilt binary to the host and check parity**

Stage the rebuilt `CirrusLogicGD5434DisplayDriver_reloc` to `out/i386/` on the host (untracked), then:

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc" out/i386/CirrusLogicGD5434DisplayDriver_reloc
```

Expected: no reference string and no reference `__TEXT,__text` symbol reported as missing. Extras on our side are expected — our guest builds are unstripped — and are reported, not failures.

Any missing reference symbol is a finding: either a method was misspelled or a function was not written.

- [ ] **Step 3: Check symbol linkage, which parity_check cannot see**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
ref=read_macho(Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver_reloc'))
new=read_macho(Path('out/i386/CirrusLogicGD5434DisplayDriver_reloc'))
def bind(d): return {s['name']:s['binding'] for s in d['symbols'] if s.get('section')}
r,n=bind(ref),bind(new)
diff=[(k,r[k],n.get(k)) for k in r if k in n and r[k]!=n[k]]
print('linkage mismatches:', diff)"
```

Expected: `linkage mismatches: []`. In particular `_SetGammaValue` must be `local` on both sides — a missing `static` in `ProgramDAC.m` shows up only here.

- [ ] **Step 4: Advance the ledger honestly**

For each of the 19 hand-written functions, set a status that matches the work actually done. `parity_check.py` plus a matching symbol name justifies `signature-confirmed` and nothing stronger. `control-flow-confirmed` requires having compared block shape and call targets in the rebuilt binary against the reference. `assembly-matched` requires having read the rebuilt instruction stream against the reference. Use `binrecon ledger` for each transition:

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc' && ./.venv-binrecon/Scripts/python.exe -m binrecon ledger --profile tools/binrecon/profiles/cirruslogic-gd5434.json --ledger src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/CirrusLogicGD5434DisplayDriver_reloc/ledger.json --address 3588 --status signature-confirmed --reason "Rebuilt binary exports -[CirrusLogicGD5434DisplayDriver(ProgramDAC) setTransferTable:count:]; parity_check reports no missing symbol or string. Instruction stream not compared." --reviewer "Pat Raynor" --source-path src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/ProgramDAC.m
```

Repeat per address. Do not batch a status onto functions you did not individually check.

- [ ] **Step 5: Record the outcome in divergences.md**

Add a "Build and parity" section: the guest `make` exit status, the `parity_check.py` result including the count of extras on our side, the linkage check result, and the ledger status distribution with the justification for the strongest status claimed.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvCirrusLogicGD5434 && git commit -m "drvCirrusLogicGD5434: build the reconstruction and record the parity result

Every reference string and text symbol is present in the rebuilt reloc."
```

---

## Task 6: ThinkPad profile, project fixes and resources

Track B's equivalent of Task 1. Independent of Tasks 1–5; may run in parallel.

**Files:**
- Create: `tools/binrecon/profiles/thinkpad760ed.json`
- Replace: `src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/Load_Commands.sect`
- Modify: `.../IBMThinkPad760EDDisplayDriver.drvproj/Makefile:16,18`
- Copy: `.../IBMThinkPad760EDDisplayDriver.drvproj/{Default,ThinkPad760}.table`, `{Display,ThinkPad760}.modes`, `English.lproj/`

**Interfaces:**
- Consumes: `vm/build-i386-video-recon.sh` from Task 1 — its `drvIBMThinkPad760EDDisplay` arm is already written and needs no change.
- Produces: `tools/binrecon/profiles/thinkpad760ed.json` with `output_dir` `../out/thinkpad760ed`.

- [ ] **Step 1: Write the profile**

`tools/binrecon/profiles/thinkpad760ed.json`, identical in shape to Task 1's but with the name and output directory changed:

```json
{
  "schema_version": "profile-v1",
  "name": "drvIBMThinkPad760EDDisplay reconstruction",
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
  "output_dir": "../out/thinkpad760ed"
}
```

angr starts enabled. Expect it to need disabling on this binary — `VGA_reloc`'s `_emu486` broke its CFGFast — but disable it only after observing the failure and recording the error, never pre-emptively.

- [ ] **Step 2: Validate the profile**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc' && ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/thinkpad760ed.json
```

Expected: size **73168**, SHA-256 `47539E03C441BBFD6724EB6778D85BFACD0961B78A8DFA33D56321C938EB5AEC`.

- [ ] **Step 3: Install the correct Load_Commands.sect**

```bash
cd /d/RhapsodiOS && cp src/drivers-i386/video/drvS3Generic/S3GenericDisplayDriver.drvproj/S3GenericDisplayDriver.lksproj/Load_Commands.sect src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/Load_Commands.sect && sha256sum src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/Load_Commands.sect
```

Expected: `78feaad1f976baf28afe83ec73ec4393ba16f514feb3eed3e67609fb29ffed7f`.

- [ ] **Step 4: Copy Apple's config tables and resources**

```bash
cd /d/RhapsodiOS && REF='C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config' && DST=src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj && cp "$REF"/*.table "$REF"/*.modes "$DST"/ && rm -rf "$DST/English.lproj" && cp -r "$REF/English.lproj" "$DST/English.lproj" && git -C . diff --stat -- "$DST/Default.table" && find "$DST" -type f | sort
```

Expected: `Default.table`, `Display.modes`, `DriverInfo`, `Makefile*`, `ThinkPad760.modes`, `ThinkPad760.table`, `English.lproj/Localizable.strings`, `English.lproj/ThinkPad760.strings`, `English.lproj/Help/TableOfContents.rtf`, `English.lproj/Help/ThinkPad560.rtfd/*` (4), `English.lproj/Help/ThinkPad760.rtfd/*` (4).

The `Default.table` diff may be empty or whitespace-only — ours was already close. Record which in the commit message.

- [ ] **Step 5: Update the resource lists**

`IBMThinkPad760EDDisplayDriver.drvproj/Makefile` line 16:

```make
GLOBAL_RESOURCES = Default.table Display.modes ThinkPad760.table ThinkPad760.modes
```

line 18:

```make
LOCAL_RESOURCES = Localizable.strings ThinkPad760.strings Help
```

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/profiles/thinkpad760ed.json src/drivers-i386/video/drvIBMThinkPad760EDDisplay && git commit -m "drvIBMThinkPad760EDDisplay: add the wire directive and Apple's config resources

Add the binrecon profile for the reference reloc."
```

---

## Task 7: ThinkPad report pass

Analyzes the reference and decompiles the 29 in-scope functions. The deferred region is documented but not decompiled.

**Files:**
- Create: `src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/divergences.md`
- Create: `.../reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json`
- Create: `.../reconstruction/IBMThinkPad760EDDisplayDriver_reloc/ledger.json`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/thinkpad760ed.json` from Task 6.
- Produces: `divergences.md` findings keyed by reference address for 0–6552, which are the sole input to Tasks 8 and 9.

- [ ] **Step 1: Run the analyzers**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc' && mkdir -p src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc && ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/thinkpad760ed.json --ledger src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/ledger.json > /tmp/thinkpad-analyze.log 2>&1; echo "exit=$?"
```

Then check the gate:

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "import json;d=json.load(open('tools/binrecon/out/thinkpad760ed/run-summary.json'));print('complete',d['complete']);print([a['name'] for a in d['analyzers']])"
```

Expected: `complete True`. If `complete` is `False`, read `/tmp/thinkpad-analyze.log`. The likely failure is angr's CFGFast inside `_emu486`, matching `VGA_reloc`'s. Disable the failing analyzer in the profile, rerun, and record the verbatim error in `divergences.md`. If IDA fails with a processor-module assertion, confirm the `-pmetapc` force from commit `8d8cfd20` is being applied — this binary is `cpu_subtype = 4`.

- [ ] **Step 2: Build the source map with ObjC method recovery**

`--objc-methods` is mandatory here: the six `vidBIOS` methods carry no symbol-table entry.

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/thinkpad760ed/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc" --source-dir src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj --repo-root . --objc-methods --output src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json'))
for k in ('mapped','unmapped','boundary_disputed','duplicate_candidates'): print(k, len(m[k]))
print('vidBIOS present:', [e['reference_names'][0] for e in m['unmapped'] if 'vidBIOS' in e['reference_names'][0]])"
```

Expected: `mapped` + `unmapped` = 38, `boundary_disputed 0`, `duplicate_candidates 0`, and all six `vidBIOS` methods present in the unmapped list. If the `vidBIOS` methods are absent, `--objc-methods` did not take effect and the partition is incomplete — do not proceed.

**`mapped` will not be 0, and no count is asserted here** because it has not been measured — the ThinkPad reference analysis does not exist until Step 1 of this task runs. The invented `IBMThinkPad760EDDisplayDriver.m` declares a class of the same name as Apple's, so any selector it happens to share maps by name alone. By inspection, its `initFromDeviceDescription:`, `enterLinearMode`, `revertToVGAMode` and `free` match reference symbols at **56, 1184, 1812 and 4344**; its `selectMode:`, `setBrightness:` and `+probe:` do not match the reference's `selectMode`, `setBrightness:token:` and absent `+probe:`. So print the mapped addresses, check the set against that prediction, and record the actual set in `divergences.md`:

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json'))
print('mapped', [(e['address'], e['reference_names'][0]) for e in m['mapped']])"
```

Every mapped entry here is a name collision only — the invented bodies do not implement the reference's behaviour. Treat all 29 in-scope functions as needing reconstruction, and do not rename our invented source to suppress a collision.

- [ ] **Step 3: Read the full cstring section**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
f=Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc')
data=f.read_bytes(); d=read_macho(f)
for s in d['sections']:
    if s['name']=='__TEXT,__cstring':
        for t in data[s['offset']:s['offset']+s['size']].split(b'\0'):
            if t: print(repr(t))"
```

The 1416-byte section is larger than this plan's excerpt. Record every string, and note in `divergences.md` which belong to the deferred `vidBIOS.m` — `"%s: vidBIOS alloc failure"` is emitted by the *driver*, not by `vidBIOS.m`, so attribution has to come from the disassembly's string references, not from the wording.

- [ ] **Step 4: Write divergences.md**

Same structure as Task 2's, with these additions:

1. A "Deferred to drvVGA" section stating: the range 6552–18204, the seven entries and their sizes, that `vidBIOS.m`'s six methods span 1156 bytes here and 1156 bytes in `VGA_reloc` (6396–7551), and that this extent match makes the two copies cross-validating for whoever reconstructs them. Link to `2026-07-25-vga-driver-binary-reconstruction-design.md`.
2. Findings for the 29 in-scope functions only, in address order.
3. A "Static storage" section attributing each of the six `_xxx.NN` symbols to an owning function, and stating which groups belong to the deferred region.
4. An "Undefined imports" section splitting the 17 imports into those referenced by in-scope code and those referenced only by the deferred region.
5. A section on `_smapi_asm`: what register block it passes, which SMAPI functions the callers request, and the three linkage observations from the spec's §2.6.
6. A note that this driver targets a Trident TGUI9660 (`"Auto Detect IDs" = "0x96601023"`) despite its name, and that `Default.table` and `ThinkPad760.table` differ only in `"Title"` and `"Help File"`, serving the 560 and the 760E/760ED from one binary.

- [ ] **Step 5: Verify coverage**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json'))
doc=open('src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/divergences.md').read()
missing=[e['reference_names'][0] for k in ('mapped','unmapped') for e in m[k] if e['reference_names'][0] not in doc]
print('absent from divergences.md:', missing)"
```

Expected: `absent from divergences.md: []` — including the deferred seven, which must be named in the deferral section.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction && git commit -m "drvIBMThinkPad760EDDisplay: decompile the in-scope reference functions

Record the vidBIOS and emu486 deferral and the 1156-byte extent match with VGA_reloc."
```

---

## Task 8: ThinkPad smapi.s and TransferTable.m

The two small translation units: 88 bytes of assembly and 732 bytes of gamma code.

**Files:**
- Create: `src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/smapi.s`
- Create: `.../IBMThinkPad760EDDisplayDriver.lksproj/TransferTable.m`
- Modify: `.../IBMThinkPad760EDDisplayDriver.lksproj/Makefile:16` and add an `SFILES` line

**Interfaces:**
- Consumes: `divergences.md` findings for 5708–6528.
- Produces:
  - `_smapi_asm` with **external** binding, callable from C. Its exact prototype — argument count, types, and whether it returns a status or writes through a pointer — comes from Task 7's finding for address 6440 and from its call sites, and must be declared in `IBMThinkPad760ED.h` so Task 9 can call it.
  - `@implementation IBMThinkPad760EDDisplayDriver (TransferTable)` with four methods: `setTransferTable:count:`, `setBrightness:token:`, `SetGammaValueRed:Green:Blue:Level:`, `setGammaTable`. Note that unlike Cirrus's `ProgramDAC.m`, the gamma helper here is a **method**, not a static C function — there is no `_SetGammaValue` symbol in this binary.

- [ ] **Step 1: Confirm the ThinkPad has no _SetGammaValue**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
d=read_macho(Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc'))
print([s['name'] for s in d['symbols'] if 'Gamma' in s['name'] or 'gamma' in s['name']])"
```

Expected: `_gamma8` and the `SetGammaValueRed:Green:Blue:Level:` method, and **no** `_SetGammaValue`. Writing a static C helper here would add a symbol the reference does not have.

- [ ] **Step 2: Write smapi.s**

Write the 88-byte routine from the Task 7 finding for 6440. Requirements:

- The symbol is `_smapi_asm` and its binding is **external**, so the file declares `.globl _smapi_asm`.
- Match the reference's register usage and calling convention exactly; a SMAPI trap passes and returns values in specific registers and the C caller depends on that contract.
- Follow the assembly-file conventions of the repo's existing i386 `.s` files rather than inventing a style.

- [ ] **Step 3: Write TransferTable.m**

Four methods in the reference's address order: `setTransferTable:count:` (5708), `setBrightness:token:` (6044), `SetGammaValueRed:Green:Blue:Level:` (6124), `setGammaTable` (6208). The category name `TransferTable` is recorded in `__OBJC,__category` and in `.objc_category_name_IBMThinkPad760EDDisplayDriver_TransferTable`. Read `_gamma8` by that name. Brightness runs through SMAPI on this machine — the finding for 6044 says how.

- [ ] **Step 4: Add both files to the build**

`IBMThinkPad760EDDisplayDriver.lksproj/Makefile` line 16:

```make
CLASSES = IBMThinkPad760ED.m TransferTable.m
```

and add, after the `HFILES` line:

```make
SFILES = smapi.s
```

`CLASSES` names `IBMThinkPad760ED.m` before that file exists; Task 9 creates it. If the build is run between tasks it will fail on the missing file, which is expected.

**Deliberate deviation from the spec.** Spec §3.3 says `vidBIOS.m` and the emulator's assembly file should be listed in this Makefile "from the start". Do **not** do that. `gnumake` would try to compile files that do not exist and fail before reaching the link, which would destroy Task 10's gate — the whole point of which is that the three in-scope objects compile and only the *link* fails. Leave them out and let Task 10's `divergences.md` section record what has to be added when drvVGA lands them.

- [ ] **Step 5: Verify the source map moves**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/thinkpad760ed/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc" --source-dir src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj --repo-root . --objc-methods --output src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json'))
print('mapped', sorted(e['address'] for e in m['mapped']))"
```

Expected: **5708, 6044, 6124, 6208 and 6440 are all present in `mapped`** — that is what this step adds. The list will also still carry Task 7 Step 2's name collisions with the invented `IBMThinkPad760EDDisplayDriver.m`, which Task 9 deletes; check for the five addresses above rather than for list equality, and do not assert a total. If 6440 is absent, the scanner did not recognise the assembly definition — record that as a scanner limitation in `divergences.md` rather than renaming the symbol.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvIBMThinkPad760EDDisplay && git commit -m "drvIBMThinkPad760EDDisplay: write the SMAPI trap glue and TransferTable category

Four gamma and brightness methods at 5708-6440 plus the 88-byte _smapi_asm."
```

---

## Task 9: ThinkPad IBMThinkPad760ED.m

The main translation unit: 24 functions, 5708 bytes, including the 1088-byte `reportSystemConfiguration`. Replaces the invented `.h` and `.m`.

**Files:**
- Create: `src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/IBMThinkPad760ED.m`
- Create: `.../IBMThinkPad760EDDisplayDriver.lksproj/IBMThinkPad760ED.h`
- Delete: `.../IBMThinkPad760EDDisplayDriver.lksproj/IBMThinkPad760EDDisplayDriver.{h,m}`
- Modify: `.../IBMThinkPad760EDDisplayDriver.lksproj/Makefile:18`

**Interfaces:**
- Consumes: `divergences.md` findings for 0–5708; `_smapi_asm` declared by Task 8.
- Produces: `@interface IBMThinkPad760EDDisplayDriver : IOFrameBufferDisplay` with the ivar layout from `__OBJC,__instance_vars` (272 bytes of metadata), the 24 methods listed in the partition table, and the `__const`/`__data` symbols named in the Global Constraints ThinkPad list. Declares `vidBIOS` via `@class` — the class is used but its implementation is deferred.

- [ ] **Step 1: Read the reference ivar layout**

```bash
cd /d/RhapsodiOS && ./.venv-binrecon/Scripts/python.exe -c "
import sys,struct; sys.path.insert(0,'tools/binrecon')
from pathlib import Path
from binrecon.macho import read_macho
f=Path('C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc')
data=f.read_bytes(); d=read_macho(f)
S={s['name']:s for s in d['sections']}
def off(a):
    for s in d['sections']:
        if s['size'] and s['offset'] and s['address']<=a<s['address']+s['size']: return s['offset']+(a-s['address'])
def cs(a):
    o=off(a); return data[o:data.index(b'\0',o)].decode()
iv=S['__OBJC,__instance_vars']; n,=struct.unpack_from('<I',data,iv['offset'])
print('ivar count', n)
for i in range(n):
    nm,ty,ofs=struct.unpack_from('<III',data,iv['offset']+4+12*i)
    print('  %-28s %-12s offset=%d' % (cs(nm), cs(ty), ofs))"
```

This prints the ivars for **both** classes' metadata regions if they are adjacent; the `IBMThinkPad760EDDisplayDriver` list is the one whose count matches the class struct's `instance_size`. Reproduce names and order exactly.

- [ ] **Step 2: Write the header**

`IBMThinkPad760ED.h`. Superclass `IOFrameBufferDisplay`. Declare the ivars from Step 1, the 24 methods, `@class vidBIOS;`, and the `_smapi_asm` prototype from Task 8. Do not carry over any constant from the invented `IBMThinkPad760EDDisplayDriver.h`.

- [ ] **Step 3: Write the implementation**

24 functions in address order, starting with the file-static `_set555Mode` at 0. Requirements:

- `_set555Mode` is `static`, so its symbol binding is `local`. It is the first thing in the file because the compiler emits in source order and it sits at address 0.
- Definition order thereafter follows the partition table exactly.
- Define `_gamma8`, the 15 `_mode_*` records, `_defaultMode`, `_modeTableCount` and `_ThinkPad760EDModeTable` by those exact names. `_defaultMode`, `_modeTableCount` and `_ThinkPad760EDModeTable` are **external**; the `_mode_*` records are **local**. Getting this backwards changes the linkage and is invisible to `parity_check.py`.
- Every string from Task 7 Step 3 that the findings attribute to in-scope code appears verbatim, including the embedded newline in `"%s: Cannot use requested display mode. \nTrying default mode.\n"` and the trailing space before it.
- `reportSystemConfiguration` emits its SMAPI and CPU strings in the reference's order; the format-string sequence is observable and must match.
- `unlockRegisters`/`lockRegisters` are 168 bytes each and bracket register access; their port sequences are load-bearing.

- [ ] **Step 4: Remove the invented sources and update HFILES**

```bash
cd /d/RhapsodiOS/src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj && git rm IBMThinkPad760EDDisplayDriver.h IBMThinkPad760EDDisplayDriver.m
```

Then Makefile line 18:

```make
HFILES = IBMThinkPad760ED.h
```

- [ ] **Step 5: Verify the source map**

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/thinkpad760ed/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/IBMThinkPad760EDDisplayDriver.config/IBMThinkPad760EDDisplayDriver_reloc" --source-dir src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj --repo-root . --objc-methods --output src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json && ./.venv-binrecon/Scripts/python.exe -c "
import json
m=json.load(open('src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/source-map.json'))
print('mapped', len(m['mapped']), 'unmapped', len(m['unmapped']))
print('unmapped:', sorted(e['address'] for e in m['unmapped']))"
```

Expected: `mapped 29 unmapped 9`. The nine are the two glue functions at 6528 and 6540 plus the seven deferred entries at 6552, 6820, 6928, 7624, 7668, 7684 and 7708. Any other address in that list is a function that was missed.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add -A src/drivers-i386/video/drvIBMThinkPad760EDDisplay && git commit -m "drvIBMThinkPad760EDDisplay: write the display driver class from the reference disassembly

Replaces the invented source; vidBIOS and emu486 remain deferred to drvVGA."
```

---

## Task 10: ThinkPad compile check

Track B's terminal task. There is no linked binary and no `parity_check.py` run — see the spec's §4.3.

**Files:**
- Modify: `src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/divergences.md`
- Modify: `.../reconstruction/IBMThinkPad760EDDisplayDriver_reloc/ledger.json`

**Interfaces:**
- Consumes: the sources from Tasks 8 and 9, `vm/build-i386-video-recon.sh` from Task 1.
- Produces: three compiled objects in the guest and a ledger recording status no stronger than the evidence supports.

- [ ] **Step 1: Compile in the Rhapsody guest**

Run `sh vm/build-i386-video-recon.sh drvIBMThinkPad760EDDisplay` in the guest.

Expected: `make exit=<nonzero> for IBMThinkPad760EDDisplayDriver (a link failure here is expected)`, three `compiled …` lines for `IBMThinkPad760ED.o`, `TransferTable.o` and `smapi.o`, the `NOTE:` line, and `fail=0`.

A **compile** error in any of the three is a real failure — fix it. A **link** error naming `.objc_class_name_vidBIOS` or `_emu486` is the expected deferral. A link error naming anything else is a real failure: it means a symbol was misspelled or a needed DriverKit import is missing.

- [ ] **Step 2: Record the exact link error**

Capture the linker's unresolved-symbol list verbatim from the build output. Expected: exactly `.objc_class_name_vidBIOS` and `_emu486`, and nothing else.

- [ ] **Step 3: Advance the ledger honestly**

For the 29 in-scope functions, the strongest defensible status is `signature-confirmed` only where a rebuilt binary was inspected — and no rebuilt binary exists for this driver. Compilation alone does not confirm a signature against the reference. Set each entry's status to reflect that, with a reason naming the constraint, for example:

```bash
cd /d/RhapsodiOS && export PYTHONPATH=tools/binrecon && export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\IBMThinkPad760EDDisplayDriver.config\IBMThinkPad760EDDisplayDriver_reloc' && ./.venv-binrecon/Scripts/python.exe -m binrecon ledger --profile tools/binrecon/profiles/thinkpad760ed.json --ledger src/drivers-i386/video/drvIBMThinkPad760EDDisplay/reconstruction/IBMThinkPad760EDDisplayDriver_reloc/ledger.json --address 5708 --status unexamined --reason "Written from the reference disassembly and compiles, but the driver does not link until drvVGA supplies vidBIOS.m and emu486, so no rebuilt binary exists to compare against. Re-status once the link succeeds." --reviewer "Pat Raynor" --source-path src/drivers-i386/video/drvIBMThinkPad760EDDisplay/IBMThinkPad760EDDisplayDriver.drvproj/IBMThinkPad760EDDisplayDriver.lksproj/TransferTable.m
```

Repeat per in-scope address. The seven deferred entries stay `unexamined` with a reason naming the deferral.

- [ ] **Step 4: Record the outcome in divergences.md**

Add a "Build status" section: which objects compiled, the verbatim unresolved-symbol list, the statement that this is the expected terminal state for this effort, and what has to happen for the driver to link — drvVGA lands `vidBIOS.m` and the emulator, this project's `lksproj` Makefile gains them, and then `parity_check.py` becomes runnable for the first time.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/video/drvIBMThinkPad760EDDisplay && git commit -m "drvIBMThinkPad760EDDisplay: compile the reconstruction and record the pending link

The only unresolved symbols are vidBIOS and emu486, which drvVGA owns."
```

---

## Task 11: README status lines

**Files:**
- Modify: `src/drivers-i386/README:63-64`

**Interfaces:**
- Consumes: the outcomes of Tasks 5 and 10.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Update the two lines**

`src/drivers-i386/README` currently reads:

```
 * drvCirrusLogicGD5434
 * drvIBMThinkPad760EDDisplay
```

Replace with wording that matches what was actually achieved. If Task 5 linked and passed parity and Task 10 compiled:

```
 * drvCirrusLogicGD5434 - reconstructed against Apple's binary, needs tested
 * drvIBMThinkPad760EDDisplay - reconstructed; links once drvVGA lands vidBIOS and emu486
```

If either task fell short, describe the real state instead. Match the file's existing phrasing conventions — other entries use "complete" and "needs compiled and then tested".

- [ ] **Step 2: Commit**

```bash
cd /d/RhapsodiOS && git add src/drivers-i386/README && git commit -m "drivers-i386: record the Cirrus GD5434 and ThinkPad 760ED reconstruction status"
```

---

## Task dependency graph

```
Task 1 (Cirrus scaffolding) ─→ Task 2 (report) ─→ Task 3 (ProgramDAC.m) ─→ Task 4 (main .m) ─→ Task 5 (build+parity) ─┐
                             │                                                                                        ├─→ Task 11
Task 6 (ThinkPad scaffolding) ─→ Task 7 (report) ─→ Task 8 (smapi.s + TransferTable.m) ─→ Task 9 (main .m) ─→ Task 10 ─┘
```

Task 6 additionally depends on Task 1, because Task 1 creates `vm/build-i386-video-recon.sh` including the ThinkPad arm. Everything else in track B is independent of track A.
