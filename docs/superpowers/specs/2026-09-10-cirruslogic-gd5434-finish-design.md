# Finish reconstruction of drvCirrusLogicGD5434

Close the remaining reconstruction gaps in `drvCirrusLogicGD5434` against
Apple's shipped i386 `CirrusLogicGD5434DisplayDriver_reloc`. The invented class
is already gone; the `_reloc` already builds. This pass applies the diagnosed
`strcmp` fix, wires version objects locally, then chases instruction-stream
parity on the four unmatched functions until each matches or its experiment
list is empty.

This continues
[2026-07-26-cirrus-thinkpad-display-reconstruction-design.md](2026-07-26-cirrus-thinkpad-display-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/`. ThinkPad, VGA,
`driverTools`, and other drivers are out of scope.

## Motivation

`src/drivers-i386/README` currently says this driver "builds and links against
the reference binary, 17/21 functions byte-identical, no version bundle emitted
yet; not yet tested." `divergences.md` already names the leftover work:

- `determineConfiguration` still uses `strncmp(..., "PCI", 4)` where Apple
  wrote `strcmp`, so gcc 2.x emits `call _strncmp` instead of `repe cmpsb`.
- The guest build never links `$(VERS_OFILE)`, so
  `_CirrusLogicGD5434DisplayDriver_VERS_STRING` / `_VERS_NUM` and the 16728-byte
  MH_BUNDLE are missing.
- Four functions still differ in gcc 2.x shape: `determineConfiguration`,
  `setMode:`, `setPendingDisplayMode:`, `setPCIConfiguration`.
- Two `chipType` experiments (unsigned ivar, `switch`) already failed and must
  not be repeated.

Done means those gaps are closed or proven unreachable from source shape, not
that QEMU boots a CL-GD5434.

## 1. Scope

### 1.1 Target

| Property | Value |
| --- | --- |
| Binary | `CirrusLogicGD5434DisplayDriver_reloc` |
| Size | 41992 |
| SHA-256 | `7DA038CCEA1CDE68B6CF2ACF4D12EE5056E7F0248ADD34D451FB96EA79C13D0D` |
| Profile | `tools/binrecon/profiles/cirruslogic-gd5434.json` |
| `__text` | 4388 bytes, 21 functions (19 hand-written, 2 glue) |

`BINRECON_REFERENCE` is:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\CirrusLogicGD5434DisplayDriver.config\CirrusLogicGD5434DisplayDriver_reloc
```

Current rebuilt baseline (from `divergences.md`): 17 of 21 functions
byte-identical under 32-bit relocation masking. Ledger: 15
`assembly-matched`, 3 `control-flow-confirmed`, 1 `signature-confirmed`, 2
`unexamined` (glue).

### 1.2 In scope

1. Replace the `"PCI"` `strncmp(..., 4)` with `strcmp` in
   `CirrusLogicGD5434DisplayDriver.m`.
2. Cirrus-local `OTHER_GENERATED_OFILES += $(VERS_OFILE)` in both Kernel Server
   and Driver-project `Makefile.postamble` files so the `_reloc` carries
   `_VERS_STRING` / `_VERS_NUM` and `driver.make` emits the MH_BUNDLE
   `CirrusLogicGD5434DisplayDriver`.
3. Source-shape experiment lists for the four unmatched functions, one
   experiment and one guest rebuild at a time.
4. Honest ledger, `divergences.md`, `source-map.json` line numbers, and README
   updates.

### 1.3 Out of scope

- ThinkPad, VGA, any other driver, `src/kernel-7`, `tools/binrecon` analyzers.
- Editing `src/driverTools-1` or guest-installed `kernelserver.make.preamble` /
  `driver.make.preamble`.
- Compiler flags beyond the existing `NEXTSTEP_PB_CFLAGS = -Wno-format`.
- Repeating the unsigned-`chipType` ivar change or the `switch` rewrite.
- Hand-writing the glue at 4364 and 4376.
- Changing `__TEXT,__const` order. The ProgramDAC-before-main inversion is
  documented and not recoverable from source.
- Byte identity of `_VERS_STRING` / `_VERS_NUM` contents (host and timestamp).
- QEMU, boot, or hardware test.
- Re-enabling Ghidra or angr. Their disablements stay as recorded.
- `binrecon compare` of a rebuilt artifact against the reference.

## 2. Current evidence (do not rediscover)

These claims are already proven in
`src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md`.
The finish pass treats them as given.

| Function | Addr | Ref size | Rebuilt | Status | What still differs |
| --- | --- | --- | --- | --- | --- |
| `determineConfiguration` | 892 | 768 | 712 | `signature-confirmed` | `call _strncmp` vs `repe cmpsb`; `jg` vs `ja` on `chipType` |
| `setPCIConfiguration` | 1692 | 584 | 612 | `control-flow-confirmed` | error block inline vs out of line; `range[3]` vs config-space frame order; 12 branches vs 11 |
| `setMode:` | 2276 | 1020 | 1008 | `control-flow-confirmed` | indexed loops vs walking pointer; same 67 `in`/`out` |
| `setPendingDisplayMode:` | 3388 | 140 | 140 | `control-flow-confirmed` | operand-reversed `cmp`; one fewer callee-saved |

`chipType` is encoded `'i'` in `__OBJC,__instance_vars`. Declaring it
`unsigned int` would emit `'I'` and break a matching section. A `switch` on
`chipType` emitted an extra `test ecx,ecx / jl`. Both attempts were reverted.

The `"PCI"` `repe cmpsb` uses count 4 (`strlen("PCI")+1`). Across Apple's i386
drivers that count always tracks `strlen(literal)+1`, which is gcc 2.x
`BUILT_IN_STRCMP`, not `strncmp`.

`__TEXT,__const` addresses differ because `_gamma8` / `_gamma16` precede
`_vgaMode` in the reference and follow it in the rebuild. Instruction-stream
comparisons mask 32-bit relocation operands. Const addresses are not a
pass/fail signal.

## 3. Architecture

Two closeable gaps, then four instruction-stream campaigns, always in that
order. After every source or makefile change: sync only this driver, guest
build, copy the `_reloc` back, compare.

1. `strcmp` in `determineConfiguration`. This stays even if the extent gap
   does not close; it is a correctness reconstruction, not an experiment.
2. Kernel Server `Makefile.postamble` wires `VERS_OFILE` into the `_reloc`.
3. Driver-project `Makefile.postamble` (created) wires `VERS_OFILE` into the
   MH_BUNDLE. Existence of the symbols and the bundle is the gate; 1998
   bytes are not.
4. For each leftover function, run its written list. One experiment, rebuild,
   masked instruction-stream diff. Match ends the campaign. Empty list with no
   match is unreachable.

The 17 already-identical functions are a regression gate. Glue stays
generated. No QEMU.

## 4. Components

### 4.1 `CirrusLogicGD5434DisplayDriver.m`

Only translation unit edited for instruction shape. `ProgramDAC.m` and the
header stay put.

First committed edit:

```
    if (strcmp([[[self deviceDescription] configTable]
		valueForStringKey:"Bus Type"], "PCI") == 0)
```

replacing `strncmp(..., "PCI", 4)`. No extra include; gcc 2.x predeclares
the builtin.

Later edits are confined to the four method bodies and only as listed in §7.

### 4.2 Two Cirrus `Makefile.postamble` files

Kernel Server (exists, empty):

`src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Makefile.postamble`

```
OTHER_GENERATED_OFILES += $(VERS_OFILE)
```

Driver project (does not exist today; `Makefile` already `-include`s it):

`src/drivers-i386/video/drvCirrusLogicGD5434/CirrusLogicGD5434.drvproj/Makefile.postamble`

Same one line. `common.make` expands `LOCAL_OFILES` with recursive `=`, so
the postamble addition is visible at link time. Do not set `VERSIONING_SYSTEM`
unless the guest fails to generate `$(NAME)_vers.c`; the default is
`next-sgs`.

If after both local wires the bundle or symbols are still missing, record
whether `$(NAME)_vers.c` / `.o` were generated and whether they appear on the
`kl_ld` / bundle link line. Do not then edit `driverTools`.

### 4.3 Reconstruction records

After each successful rebuild: `divergences.md`, `ledger.json`,
`source-map.json` if line numbers moved, `src/drivers-i386/README`, and
`docs/drivers/video-reconstruction.md` Cirrus paragraph. Profile and
`vm/build-i386-video-recon.sh` stay as they are except the missing-bundle
warning should go quiet once the bundle exists.

### 4.4 Comparison helper (host-side, uncommitted)

Instruction-stream comparison uses `binrecon.macho.read_macho` to extract
`__TEXT,__text` bytes and zero every 4-byte i386 relocation operand that
falls inside the function extent, then compares the masked slices. The helper
lives in the worktree as a throwaway script; it is not committed. Extent
starts are the symbol addresses in the binary under test, not the reference
addresses, because sizes differ.

## 5. Data flow

1. Edit one site.
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/video/drvCirrusLogicGD5434`.
   Do not `-All`.
3. Guest: `vm/build-i386-video-recon.sh drvCirrusLogicGD5434`. Copy
   `CirrusLogicGD5434DisplayDriver_reloc` (and the version bundle after step 3)
   from `/build/out/i386/drvCirrusLogicGD5434/` to host `out/i386/` (gitignored).
4. Compare against the reference:
   - `parity_check.py`: 0 missing strings, 0 missing `__text` symbols.
   - Masked instruction-stream diff of all 19 hand-written functions.
   - After version wiring: `_VERS_STRING` and `_VERS_NUM` exist in
     `__TEXT,__const`; the MH_BUNDLE exists beside the `_reloc`.
5. If any of the 17 previously identical functions differ, revert and record
   failed-with-regression. If the campaign target matches, stop that campaign
   and advance the ledger. If it does not, revert unless the edit is the
   `strcmp` fix or a postamble line, which stay.
6. Record the outcome in `divergences.md` before the next edit.

## 6. Error handling

- Failed guest build: stop. Fix or revert. Do not advance the ledger.
- Regression of any of the 17: revert, record, continue the list.
- Non-match, no regression: revert, mark tried, continue.
- Unsigned-`chipType` ivar or `switch` (including a form that would emit
  `test`/`jl`): skip and say why.
- Guest unreachable: do not invent instruction-stream results. Leave the
  campaign open and wait.
- Version artifacts still missing after both local wires: record guest
  evidence. Existence stays unmet. Do not edit shared project types.

Unstripped extras in `parity_check.py` are not failures. `binrecon analyze` is
not re-run.

## 7. Experiment lists

Source-shape only. One item per rebuild. A match ends the row. Empty list
without a match is unreachable.

### 7.1 `determineConfiguration` (addr 892)

After `strcmp` is committed. Remaining target: `chipType` loaded into `ecx`
and compared unsigned (`cmp ecx, 1 / ja`, `cmp ecx, 4 / ja`).

Forbidden: change the ivar type; `switch`.

1. `unsigned int kind = chipType;` then `if (kind <= 1)` / `else if (kind <= 4)`.
2. `if ((unsigned)chipType <= 1)` / `else if ((unsigned)chipType <= 4)`.
3. `if (chipType <= 1u)` / `else if (chipType <= 4u)`.
4. `unsigned int kind = (unsigned int)chipType;` then the same `if` chain.
5. `int kind = chipType;` then the same `if` chain (signed local, one load).
6. Predicate polarity equivalent for 0–4: `if (chipType > 1)` assigns the
   GD5446 table, `else` the GD5434 table.
7. Two sequential `if`s instead of `if` / `else if`.

`strcmp` should drop the call-target list from 8 to 7. That alone may move
the ledger from `signature-confirmed` to `control-flow-confirmed`.
`assembly-matched` waits until this list matches or is exhausted.

### 7.2 `setMode:` (addr 2276)

Register-write order is load-bearing and must not be rearranged. The four
indexed loops are SR01–SR04, CR00–CR18, AR00–AR14, GR00–GR08.

1. Convert all four loops to walking pointers (`unsigned char *p = mode->seq`
   and `*p++` in place of `mode->seq[i-1]`, similarly for `crtc`, `attr`,
   `gfx`).
2. Same walking pointers with `while` instead of `for`.
3. Indexed `while` loops (no walking pointer).
4. Walking pointers declared at the top of the function (declaration order)
   and reused by the four loops in turn.
5. One walking pointer declared immediately before each loop (current
   locals first, pointers later).

### 7.3 `setPendingDisplayMode:` (addr 3388)

Current test: `if (modeTable[mode].memorySize > installedVRAMBytes)`.

1. Reverse operands: `if (installedVRAMBytes < modeTable[mode].memorySize)`.
2. `unsigned int needed = modeTable[mode].memorySize;` then
   `if (needed > installedVRAMBytes)`.
3. Same `needed` local declared at the top of the function.
4. `if (!(modeTable[mode].memorySize <= installedVRAMBytes))`.
5. Combine 1 and 2: `needed` plus reversed compare.

### 7.4 `setPCIConfiguration` (addr 1692)

Current locals: `IOPCIConfigSpace configSpace;` then `IORange range[3];`.
Error path is `if (rangeCount != 3) { IOLog; return NO; }` inline.

1. Declare `IORange range[3]` before `IOPCIConfigSpace configSpace`.
2. `if (rangeCount == 3) { success path } else { IOLog; return NO; }`.
3. After the `!= 3` check, `while` instead of `for` on both range-copy loops.
4. Invert only the first loop to `while`; leave the second as `for`.
5. Put the `Incorrect number of address ranges` `IOLog` after the success
   `return`s so gcc can sink it (equivalent early-return vs trailing error).

## 8. Testing

No QEMU, no boot, no hardware. Verification is the guest `_reloc` plus host
checks.

**After `strcmp`:** `parity_check.py` still 0 missing. Call-target list of
`determineConfiguration` is 7, not 8 (no `_strncmp`). Ledger may become
`control-flow-confirmed` if remaining control flow matches; not
`assembly-matched` until §7.1 matches.

**After postambles:** rebuilt `__TEXT,__const` contains
`_CirrusLogicGD5434DisplayDriver_VERS_STRING` and `_VERS_NUM`.
`CirrusLogicGD5434DisplayDriver.config/CirrusLogicGD5434DisplayDriver` exists.
`vm/build-i386-video-recon.sh` no longer prints
`WARNING: no CirrusLogicGD5434DisplayDriver version bundle produced`. Glue at
4364/4376 still present and still unmapped.

**After each experiment rebuild:** the 17 `assembly-matched` (plus identical
glue) functions remain byte-identical under relocation masking. The campaign
function is compared the same way. Match → `assembly-matched`. Exhausted
list → leave `control-flow-confirmed` or `signature-confirmed`, with the list
and why each item failed.

**Final:** README and `docs/drivers/video-reconstruction.md` state the new
counts, that the version bundle is present, and name any remaining unreachable
functions. Ledger `rebuilt_sha256` is the last kept `_reloc`.

## 9. Success criteria

- `strcmp` is in source for the `"Bus Type"` test.
- Version symbols exist in the `_reloc`; the MH_BUNDLE exists.
- Each of the four functions is `assembly-matched` or recorded unreachable
  with its exhausted list.
- The 17 previously identical functions still match.
- Glue is still generated, not hand-written.
- No shared makefile or other-driver edits.
