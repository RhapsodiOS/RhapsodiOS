# Finish drvPS2Mouse under binrecon

Drive `drvPS2Mouse` to function-level instruction-stream identity with Apple's
shipped i386 `PS2Mouse_reloc`, then guest-build and measure. The report pass
and fix pass already closed the class hierarchy, config keys, strings, Loaded
Server sections, and the two parameter methods. This pass reverses the two
accepted source-level leftovers, wires version objects locally, and chases
`raw_equal` / `masked_equal` on whatever remains.

This continues
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/input/drvPS2Mouse/reconstruction/`. That spec's rule that a
rebuilt `_reloc` is not fed to binrecon is **superseded for this driver only**.
Sibling input drivers, `src/kernel-7`, and `driverTools` stay out of scope.

## Motivation

`src/drivers-i386/README` currently says this driver "compiles; reconstructed
against the reference binary, fixes applied, not yet tested." `divergences.md`
already names the leftover work:

- Finding 13: `controllerFunctions` null guards the reference does not have.
  Today that is three `== NULL` early returns (`_PS2MouseIntHandler`,
  `isMousePresent`, `resetMouse`) plus the `!= NULL` wrappers in
  `initWithController:` (the `reserved[3]` drain and the 8042 command-byte
  block). The reference loads `_func_list` and dereferences it with no test.
  These guards are the only remaining source-level `__TEXT,__text` excess
  (the last measured rebuild was 1856 bytes against Apple's 1804).
- Finding 14: `_PS2MouseIntHandler` is declared `unsigned int` and returns 0.
  The reference is `void` and never writes `eax`.
- `__TEXT,__const` is absent. Apple emits `_PS2Mouse_VERS_STRING` (160 bytes)
  and `_PS2Mouse_VERS_NUM` (10 bytes) via `vers_string`. Cirrus already showed
  that a driver-local `OTHER_GENERATED_OFILES += $(VERS_OFILE)` produces those
  symbols.
- `vm/build-i386-input-recon.sh` was deleted in `d529b15f1` (unrelated rbuild
  work). Guest builds of this driver have no harness in the current tree.
- Ledger `rebuilt_sha256` is still `null`. Most functions were compared
  against source, not against a rebuilt instruction stream. Only
  `getIntValues:` and `setIntValues:` were re-read against a rebuilt `_reloc`.

Done means those gaps are closed or proven unreachable from source shape, not
that QEMU moves a pointer.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current `PS2Mouse_reloc`, or when the leftover is
recorded in
`src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md` with the
`binrecon function --name` dump and an explicit *accept* disposition.

The campaign is done when every paired hand-written function meets that bar,
unpaired leftovers are only the two build-generated glue methods
(`+[PS2MouseKernelServerInstance kernelServerInstance]`,
`+[PS2MouseVersion driverKitVersionForPS2Mouse]`), `__TEXT,__const` contains
`_PS2Mouse_VERS_STRING` and `_PS2Mouse_VERS_NUM`, `parity_check.py` reports
`missing_strings` 0 and `missing_symbols` 0, and `ledger.json`
`rebuilt_sha256` is the last kept `_reloc`.

`cfg_equal` is not a signal. Status may remain `different` because of
`cfg differs` or `instruction layout differs`. The flags that count are
`raw_equal` and `masked_equal`.

Hardware testing stays out. The README line remains that the driver is not
yet tested on a real mouse.

## 2. Architecture

This is a reconstruction campaign, not a new subsystem. `PS2Mouse` already
subclasses `PCPointer`. The in-kernel `src/kernel-7` `PS2Mouse` is a different
class and is not this driver.

The loop is: edit one site → sync only this driver → guest `gnumake` → copy
`PS2Mouse_reloc` back to gitignored `out/i386/drvPS2Mouse/` → IDA-analyze the
rebuild → `binrecon function --list`.

Phases, in order:

**Phase 0 — harness.** If `vm/build-i386-input-recon.sh` is missing, restore
it as it existed immediately before `d529b15f1` (content from `1b1b68b93`,
including the `drvISASerialPort` case). If a sibling campaign already put a
harness there, keep their file and add a `drvPS2Mouse` arm rather than
replacing it. This campaign only *runs* `drvPS2Mouse`. Add a `rebuilt` key
to `tools/binrecon/profiles/ps2mouse.json` and disable Ghidra and angr for
analyze. `output_dir` stays `../out/ps2mouse`. Committed `reconstruction/`
artifacts remain the human-reviewed record. Gitignored analyzer JSON under
`tools/binrecon/out/ps2mouse/` will be overwritten by IDA-only analyze; do
not treat leftover Ghidra/angr files as current.

**Phase 1 — baseline.** Guest-build the current tree with no source edits.
Write `reconstruction/function-worklist.md` from `binrecon function --list`.
This is the regression snapshot.

**Phase 2 — drop Finding 13 guards.** Remove every `controllerFunctions ==
NULL` early return and every `controllerFunctions != NULL` / per-slot
`!= NULL` guard, including the wrappers in `initWithController:`. After the
edit, `_func_list` is loaded and called with no test, matching the
reference. This stays even if extents do not close; it is a correctness
reconstruction, not an experiment. Finding 13's acceptance is reversed.

**Phase 3 — void handler.** Declare `_PS2MouseIntHandler` `void` and drop the
`return 0` exits. Finding 14's handler-return acceptance is reversed. The
`mouseInit:` half of Finding 14 is already fixed and is not reopened.

**Phase 4 — version objects.** Create the Kernel Server
`Makefile.postamble` with `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. Gate:
`__TEXT,__const` contains `_PS2Mouse_VERS_STRING` and `_PS2Mouse_VERS_NUM`.
Do not match the 160-byte string (host and timestamp). Do not edit
`driverTools` or guest-installed makefiles. The Driver-project MH_BUNDLE is
not a gate.

**Phase 5 — cheapest-first grinding.** Remaining unmatched hand-written
functions, one written experiment per rebuild. Stop a function when the
cheapest leftover is register allocation or stack spill. Glue stays
generated.

The three methods already claimed `assembly-matched` (`getHandler:…`,
`getResolution`, `getIntValues:…`) are a regression gate: if any of them
lose `masked_equal` after an edit, revert.

## 3. Current evidence (do not rediscover)

These claims are already proven in
`src/drivers-i386/input/drvPS2Mouse/reconstruction/divergences.md`. This
finish pass treats them as given.

| Function | Addr | Ref size (IDA) | Ledger | What still differs |
|---|---|---|---|---|
| `-[PS2Mouse mouseInit:]` | 0 | 179 | `control-flow-confirmed` | rebuilt stream not re-compared |
| `-[PS2Mouse isMousePresent]` | 180 | 109 | `intentional-mismatch` | Finding 13 null guard |
| `-[PS2Mouse resetMouse]` | 292 | 37 | `intentional-mismatch` | Finding 13 null guard |
| `-[PS2Mouse initWithController:]` | 332 | 350 | `intentional-mismatch` | Finding 13 six per-slot guards |
| `-[PS2Mouse readConfigTable:]` | 684 | 214 | `control-flow-confirmed` | rebuilt stream not re-compared |
| `_PS2MouseIntHandler` | 900 | 525 | `intentional-mismatch` | Finding 13 guard; Finding 14 `unsigned int` / `return 0` |
| `-[PS2Mouse interruptOccurred]` | 1428 | 50 | `control-flow-confirmed` | rebuilt stream not re-compared |
| `-[PS2Mouse getHandler:level:argument:forInterrupt:]` | 1480 | 39 | `assembly-matched` | regression gate |
| `-[PS2Mouse getResolution]` | 1520 | 16 | `assembly-matched` | regression gate |
| `-[PS2Mouse getIntValues:forParameter:count:]` | 1536 | 93 | `assembly-matched` | regression gate |
| `-[PS2Mouse setIntValues:forParameter:count:]` | 1632 | 146 | `intentional-mismatch` | gcc hoist/spill; ours 136 vs Apple 148 |
| `+[PS2MouseKernelServerInstance kernelServerInstance]` | 1780 | 12 | `intentional-mismatch` | generated glue |
| `+[PS2MouseVersion driverKitVersionForPS2Mouse]` | 1792 | 12 | `intentional-mismatch` | generated glue |

Reference SHA-256:
`4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E`.
Reference file size 30204. IDA is authoritative for extents; symbol-gap
sizes include inter-function `nop` padding and are not the comparison
extent.

`Default.table` already diffs clean ignoring `"Driver Version"`.
`Load_Commands.sect` is 164 bytes. `Unload_Commands.sect` is 102 bytes.
Neither is reopened. `Force Detection` sense is already settled: `Yes`
skips `isMousePresent` and attaches. Do not invert it.

`setIntValues:` being 12 bytes smaller is a code-generation difference
with no source-level counterpart. drvBusMouse's verified method lands on
the same 136. Phase 5 does not add dummy spills to chase 148.

## 4. Components

| Piece | Job |
|---|---|
| `PS2Mouse.m` | Only translation unit edited for guards, handler type, and later experiment-list shape. |
| `PS2Mouse.h` | Not touched. The interrupt handler is `static` in the `.m` and is not declared in the header. No ivar or superclass churn. |
| Kernel Server `Makefile.postamble` | Created at `PS2Mouse.drvproj/PS2Mouse.lksproj/Makefile.postamble`. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. `Makefile` already `-include`s it. |
| `vm/build-i386-input-recon.sh` | Restored if missing; otherwise keep a sibling harness and add the `drvPS2Mouse` arm. This campaign only *runs* `drvPS2Mouse`. |
| `tools/binrecon/profiles/ps2mouse.json` | Adds `"rebuilt": { "path": "${BINRECON_REBUILT}" }`; IDA stays on; Ghidra and angr `enabled: false`. |
| `reconstruction/function-worklist.md` | Created after Phase 1; refreshed when a diagnosed gap closes or a function is accepted. |
| `reconstruction/divergences.md` | Finding 13/14 acceptances reversed when those edits land; VERS gap closed; exhausted experiment lists live here. |
| `reconstruction/ledger.json` | Status of record. `rebuilt_sha256` set from the last kept `_reloc`. |
| `reconstruction/source-map.json` | Line numbers only, when bodies move. |
| `src/drivers-i386/README` | Status line updated at the end. |

Out of bounds: `src/kernel-7`, other input drivers, `src/driverTools-1`,
guest-installed `kernelserver.make`, compiler flags beyond the existing
`-Wno-format -DDRIVER_PRIVATE`, hand-written glue, QEMU, boot, hardware.
Do not strip unused `PS2_CMD_*` macros. Do not re-enable Ghidra or angr.

`BINRECON_REFERENCE` is:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Mouse.config\PS2Mouse_reloc
```

`BINRECON_REBUILT` is the host-staged copy:

```
out/i386/drvPS2Mouse/PS2Mouse.config/PS2Mouse_reloc
```

## 5. Data flow

1. Host edits one allowed site.
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/input/drvPS2Mouse`.
   When the restored harness is the change, also sync `vm/build-i386-input-recon.sh`.
   Never `-All`.
3. Guest: `sh /build/source/vm/build-i386-input-recon.sh drvPS2Mouse`. Copy
   `/build/out/i386/drvPS2Mouse/PS2Mouse.config/PS2Mouse_reloc` to host
   `out/i386/drvPS2Mouse/` (gitignored). Strip CR from the harness if the
   guest's `/bin/sh` is the 1999 Bourne shell, same as the video recon
   scripts.
4. Host: set both `BINRECON_*` variables. Run
   `binrecon analyze --profile tools/binrecon/profiles/ps2mouse.json`
   (IDA only). Then `binrecon function --list` and, for the open function,
   `--name`. Analyze may exit 1 until `normalized-functions` acceptance
   passes; that is expected during the campaign. The gate is that
   `tools/binrecon/out/ps2mouse/published/` contains
   `analysis-reference-ida.json`, `analysis-rebuilt-ida.json`, and
   `comparison-ida.json`. Do not treat leftover Ghidra/angr published files
   as current.
5. Also run `tools/binrecon/parity_check.py` against `__TEXT,__cstring` and
   `__TEXT,__text` symbol names. A missing reference string or symbol is a
   finding. Extra unstripped locals are not.
6. After Phase 4, confirm `__TEXT,__const` contains the two `vers_string`
   symbols.
7. Record the outcome in `divergences.md` before the next edit. Advance the
   ledger only on a kept rebuild.

Analyzer output under `tools/binrecon/out/ps2mouse/` stays uncommitted.
Never commit the reference binary or a rebuilt `_reloc`.

## 6. Error handling

- Guest build fails: stop. Fix or revert. Do not advance the ledger or invent
  section sizes.
- Guest unreachable: leave the campaign open. Do not claim instruction-stream
  results from an old `_reloc`.
- Any of `getHandler:…`, `getResolution`, `getIntValues:…` lose
  `masked_equal`: revert, record as failed-with-regression, continue the
  list.
- Diagnosed edits (drop guards, `void` handler, `VERS_OFILE` line): keep even
  if extents do not close. They are reconstructions, not experiments.
- Experiment non-match with no regression: revert, mark tried, next item.
- Experiment list empty and leftover is register allocation or stack spill:
  accept as `intentional-mismatch` with the `binrecon function --name` dump
  and a reviewer. Do not add dummy locals or reorder statements to chase
  gcc 2.7.
- `VERS_OFILE` still missing after the local postamble: record whether
  `PS2Mouse_vers.c` / `.o` were generated and whether they appear on the
  `kl_ld` line. Existence stays unmet. Do not edit shared project types.
- `parity_check.py` missing a reference string or `__text` symbol: defect in
  the last edit; revert or fix before continuing.
- Ghidra/angr stay disabled. Do not treat their absence as a new analyzer
  disagreement.

## 7. Experiment lists

Source-shape only. One item per rebuild. A match ends the row. Empty list
without a match is unreachable. Rewrite from the Phase 1 worklist if ranking
differs; these are starters, not a license to skip measurement.

### 7.1 Closed by Phases 2–3

`isMousePresent`, `resetMouse`, `initWithController:`, `_PS2MouseIntHandler`.
If `--name` still differs after those edits, the next experiment is the
cheapest remaining instruction from that dump, not a new invention. The
packet state machine in `_PS2MouseIntHandler` is load-bearing: do not
reorder resync, timeout, or `seqBeingProcessed` / `seqInProgress` branches.

### 7.2 `-[PS2Mouse mouseInit:]` (addr 0)

Reference initializes exactly six locations, in this order:
`seqInProgress`, `seqBeingProcessed`, `indexInSequence`,
`summedEvent.deltaY`, `summedEvent.deltaX`, `resolution = 0x96`.

1. Match that store order exactly if the current source differs.
2. Write the two `BOOL` flags as `0` rather than `NO`.
3. Write resolution as `150` rather than `0x96`.

### 7.3 `-[PS2Mouse readConfigTable:]` (addr 684)

1. Declaration order of `forceDetectionStr` / `invertedStr` / `resolutionStr`
   matching the reference's stack slots.
2. Parse `Force Detection` / `Inverted` with the reference's
   NULL-or-not-`y`/`Y` shape if `--name` shows a different branch layout.
   Do not invert the stored sense.

### 7.4 `-[PS2Mouse interruptOccurred]` (addr 1428)

1. How `currentEvent` is passed to `dispatchPointerEvent:` (address of the
   static vs a local copy). Finding 6 already requires the static.

### 7.5 `-[PS2Mouse setIntValues:forParameter:count:]` (addr 1632)

List is empty unless `--name` shows a *source-level* difference. The 12-byte
gap from gcc hoisting `parameterArray` and keeping the compare count as an
immediate is accepted. Do not add stack spills by hand.

### 7.6 Regression only

`getHandler:…`, `getResolution`, `getIntValues:…`. No experiments.

## 8. Testing

No QEMU, no boot, no hardware. Verification is the guest `_reloc` plus host
checks.

**Phase 1 baseline.** Harness `fail=0`, a staged `_reloc`, worklist written.
Record size, `parity_check.py` counts, and per-function `raw_equal` /
`masked_equal`.

**After dropping the null guards.** `__TEXT,__text` should move toward 1804.
`isMousePresent`, `resetMouse`, `initWithController:`, and
`_PS2MouseIntHandler` should shrink. Missing strings/symbols stay 0. The
three already-matched methods stay `masked_equal`.

**After `void` handler.** Handler epilogue should no longer write `eax`.
DriverKit still discards the return; this is metadata plus epilogue shape.
IDA extent is the comparison extent.

**After `VERS_OFILE`.** `__TEXT,__const` exists and names the two
`vers_string` symbols. Contents may differ. `__text` identity of the 11
hand-written functions must not regress.

**After each experiment rebuild.** `binrecon function --list` is the
worklist. Match → `assembly-matched`. Exhausted list → leave
`control-flow-confirmed` or `intentional-mismatch` with the dump.

**Final.** README names the new `masked_equal` counts, that the version
objects exist, and that the driver is still untested on hardware. Ledger
`rebuilt_sha256` is the last kept `_reloc`.

## 9. Success criteria

- `vm/build-i386-input-recon.sh` is back in the tree and
  `sh … drvPS2Mouse` stages a `_reloc`.
- Finding 13 guards are gone from `PS2Mouse.m`.
- `_PS2MouseIntHandler` is `void`.
- `_PS2Mouse_VERS_STRING` and `_PS2Mouse_VERS_NUM` exist in the `_reloc`.
- Each of the 11 hand-written functions is `assembly-matched` or recorded
  unreachable with its exhausted list.
- The three previously `assembly-matched` methods still have `masked_equal`.
- Glue is still generated, not hand-written.
- `missing_strings` 0, `missing_symbols` 0.
- No shared makefile or other-driver edits beyond ensuring
  `vm/build-i386-input-recon.sh` has a working `drvPS2Mouse` arm.
