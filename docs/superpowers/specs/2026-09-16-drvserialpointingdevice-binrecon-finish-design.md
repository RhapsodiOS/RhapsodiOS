# Finish drvSerialPointingDevice under binrecon

Drive `drvSerialPointingDevice` to function-level instruction-stream identity
with Apple's shipped i386 `SerialPointingDevice_reloc`, then guest-build and
measure. The report pass and fix pass already closed the `PCPointer`
hierarchy, ivar layout, method encodings, strings, linkage, protocol
handlers, and `Loaded Server` sections. This pass wires version objects
locally and chases `raw_equal` / `masked_equal` on whatever remains.

This continues
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/input/drvSerialPointingDevice/reconstruction/`. That spec's
rule that a rebuilt `_reloc` is not fed to binrecon is **superseded for this
driver only**. Sibling input drivers, `src/kernel-7`, and `driverTools` stay
out of scope.

## Motivation

`src/drivers-i386/README` currently says this driver "compiles; reconstructed
against the reference binary, fixes applied, not yet tested." July closed
every named source divergence (Findings 1–16). What remains:

- Eleven of sixteen hand-written functions are still
  `control-flow-confirmed` because the fix pass never compared the rebuilt
  instruction stream. Five rows were claimed `assembly-matched` against
  source versus the reference IDA listing, not against a guest `_reloc`.
- `__TEXT,__const` is absent. Apple emits
  `_SerialPointingDevice_VERS_STRING` (160 bytes) and
  `_SerialPointingDevice_VERS_NUM` (10 bytes) via `vers_string`. Cirrus and
  the PS2Mouse finish showed that a driver-local
  `OTHER_GENERATED_OFILES += $(VERS_OFILE)` produces those symbols. The
  Kernel Server `Makefile` already `-include`s `Makefile.postamble` and
  names it in `OTHERSRCS`; the file itself is missing.
- `vm/build-i386-input-recon.sh` was deleted in `d529b15f1` (unrelated
  rbuild work). Guest builds of this driver have no harness in the current
  tree.
- Ledger `rebuilt_sha256` is still `null`.

Done means those gaps are closed or proven unreachable from source shape,
not that QEMU moves a pointer.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current guest `SerialPointingDevice_reloc`, or
when the leftover is recorded in
`src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md`
with the `binrecon function --name` dump and an explicit *accept*
disposition (compiler-shaped: register allocation or instruction
scheduling).

The campaign is done when every paired hand-written function meets that bar,
unpaired leftovers are only the two build-generated glue methods
(`+[SerialPointingDeviceKernelServerInstance kernelServerInstance]`,
`+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]`),
`__TEXT,__const` contains `_SerialPointingDevice_VERS_STRING` and
`_SerialPointingDevice_VERS_NUM`, `parity_check.py` reports
`missing_strings` 0 and `missing_symbols` 0, and `ledger.json`
`rebuilt_sha256` is the last kept `_reloc`.

`cfg_equal` is not a pass signal. Status may remain `different` because of
`cfg differs` or `instruction layout differs`. The flags that count are
`raw_equal` and `masked_equal`.

`__TEXT,__text` need not hit 4468. Envelope size is codegen (guest `cc`
versus Apple's build), not missing logic. Do not grind envelope size.

Hardware testing stays out. The README line remains that the driver is not
yet tested on a real serial mouse.

The five July `assembly-matched` methods are a *candidate* regression gate,
not an assumed one. Phase 1 decides which of them actually show
`masked_equal` on the current `_reloc`. Those that do become the regression
set. Those that do not join the grind set. Do not rewrite a body that
already matches.

## 2. Current evidence (do not rediscover)

These claims are already proven in
`src/drivers-i386/input/drvSerialPointingDevice/reconstruction/divergences.md`.
This finish pass treats them as given.

Reference: `SerialPointingDevice_reloc`, 39928 bytes, SHA-256
`59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`.
`BINRECON_REFERENCE` is
`C:\Users\raynorpat\Downloads\test\Drivers\i386\SerialPointingDevice.config\SerialPointingDevice_reloc`.
Profile: `tools/binrecon/profiles/serialpointingdevice.json` (IDA 9.2 + angr
9.3.0, Ghidra off because `normalize.py` aborts on relocation operand
metadata). Analyzer output: `tools/binrecon/out/serialpointingdevice/`
(gitignored).

The last guest rebuild in the fix pass was 112072 bytes unstripped, with
`missing_strings` 0, `extra_strings` 0, `missing_symbols` 0, and 21 extra
unstripped stabs. Remeasure on the Phase 1 `_reloc`.

| Function | Addr | Ref size (IDA) | Ledger |
|---|---|---|---|
| `_mainLoop` | 0 | 26 | `control-flow-confirmed` |
| `-[SerialPointingDevice mouseInit:]` | 28 | 880 | `control-flow-confirmed` |
| `-[SerialPointingDevice free]` | 908 | 105 | `control-flow-confirmed` |
| `-[SerialPointingDevice getResolution]` | 1016 | 16 | `assembly-matched` (source vs IDA) |
| `-[SerialPointingDevice setEventTarget:]` | 1032 | 72 | `control-flow-confirmed` |
| `-[SerialPointingDevice getIntValues:forParameter:count:]` | 1104 | 93 | `control-flow-confirmed` |
| `-[SerialPointingDevice setIntValues:forParameter:count:]` | 1200 | 263 | `control-flow-confirmed` |
| `-[SerialPointingDevice mainLoop:]` | 1464 | 305 | `control-flow-confirmed` |
| `-[SerialPointingDevice getByte:sleep:]` | 1772 | 103 | `control-flow-confirmed` |
| `-[SerialPointingDevice detect]` | 1876 | 1379 | `control-flow-confirmed` |
| `-[SerialPointingDevice MSProtocol]` | 3256 | 442 | `control-flow-confirmed` |
| `-[SerialPointingDevice MPlusProtocol]` | 3700 | 22 | `assembly-matched` (source vs IDA) |
| `-[SerialPointingDevice FiveBProtocol]` | 3724 | 598 | `control-flow-confirmed` |
| `-[SerialPointingDevice MMProtocol]` | 4324 | 40 | `assembly-matched` (source vs IDA) |
| `-[SerialPointingDevice RBProtocol]` | 4364 | 40 | `assembly-matched` (source vs IDA) |
| `-[SerialPointingDevice UnknownProtocol]` | 4404 | 40 | `assembly-matched` (source vs IDA) |
| `+[SerialPointingDeviceKernelServerInstance kernelServerInstance]` | 4444 | 12 | glue `intentional-mismatch` |
| `+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]` | 4456 | 12 | glue `intentional-mismatch` |

IDA is authoritative for extents. Symbol-gap sizes include inter-function
`nop` padding and are not the comparison extent. IDA and angr agreed on all
18 addresses and sizes; angr's extra fragment functions are padding. Ghidra
was never a third vote.

`SerialPointingDevice : PCPointer` with `instance_size` 356 and six ivars at
0x144–0x158 already matches. `__OBJC,__inst_meth` name/type-encoding set
already matches. `_mainLoop`, `_mouseTypeList`, and `_protocolList` are
external; `_active` is local. `Default.table` already diffs clean ignoring
`"Driver Version"`. `Load_Commands.sect` is 164 bytes.
`Unload_Commands.sect` is 102 bytes. None of that is reopened.

A prior rebuilt `setIntValues:` was 312 bytes against Apple's 263. That gap
is ordinary codegen elsewhere in the body, already recorded in the ledger.
Do not add dummy spills to chase 263.

July listed three equivalent-codegen notes that are **not** findings:
`MSProtocol`'s extra `maskedByte` local, the unreachable `default:` in
`MSProtocol`, and `detect`'s `resolution` local used only by a verbose log.
Do not rewrite them unless Phase 1 `--name` shows they are the cheapest
source-shaped gap.

## 3. Architecture

This is a reconstruction campaign on one loadable Kernel Server, not a new
subsystem. `SerialPointingDevice` already subclasses `PCPointer`. The
in-kernel `src/kernel-7` `PCPointer` headers are a different tree and are
not this driver.

One translation unit: `SerialPointingDevice.m`. Layout is already closed.
Name-paired `masked_equal` ignores relocated immediates and envelope
padding, so we walk cheapest remaining `differing` row, not address order.

The loop is: edit one site → sync only this driver → guest `gnumake` → copy
`SerialPointingDevice_reloc` back to gitignored
`out/i386/drvSerialPointingDevice/SerialPointingDevice.config/` →
IDA-analyze the rebuild → `binrecon function --list`.

Phases, in order:

**Phase 0 — harness.** If `vm/build-i386-input-recon.sh` is missing, create
it modelled on `vm/build-i386-scsi.sh` and `vm/build-i386-video-recon.sh`
(POSIX Bourne, no `set -e` on predicates, CR stripped from Makefiles,
`gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`, gate on `_reloc` presence).
The required arm is `drvSerialPointingDevice`. If a sibling campaign already
put a harness there, keep their arms and add this one. Do not restore the
five-driver dispatcher. Do not remove the driver from
`src/rbuild-1/kernel-drivers-blacklist.json`.

**Phase 1 — baseline.** This session syncs only this driver, guest-builds
with no source edits, copies `SerialPointingDevice_reloc` to host
`out/i386/drvSerialPointingDevice/SerialPointingDevice.config/`, runs
`parity_check.py`, IDA-analyzes the rebuilt binary, and writes
`reconstruction/function-worklist.md` with both SHA-256s, remaining counts,
and a reachability note. Reuse published reference analysis if
`complete: true` and the SHA is `59C0C95C…`. The five July
`assembly-matched` rows become the regression gate only if they actually
show `masked_equal` on this `_reloc`; otherwise they join the grind set.

**Phase 2 — version objects.** Create the missing Kernel Server
`Makefile.postamble` with `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. Gate:
`__TEXT,__const` contains `_SerialPointingDevice_VERS_STRING` and
`_SerialPointingDevice_VERS_NUM`. Do not match the 160-byte string (host and
timestamp). Do not edit `driverTools` or guest-installed makefiles. The
Driver-project MH_BUNDLE is not a gate. This stays even if `__text` extents
do not close.

**Phase 3 — cheapest-first.** Remaining unmatched hand-written functions, one
written experiment per rebuild. Stop a function when the cheapest leftover
is register allocation or stack spill. Glue stays generated. Do not chase
the three July “not findings” unless `--name` shows they are the cheapest
source-shaped gap.

**Phase 4 — close.** Refresh the worklist, advance the ledger, update
`divergences.md` and the README line (still not hardware-tested).

`binrecon function` uses the existing name-paired `masked_equal` path in
`tools/binrecon/binrecon/compare.py`. No comparator changes. Do not
re-enable Ghidra or angr. Do not re-run `binrecon analyze` on the reference
unless the committed consensus is missing.

## 4. Components

| Piece | Job |
|---|---|
| `SerialPointingDevice.m` | Only translation unit whose bodies get instruction-shape edits. |
| `SerialPointingDevice.h` | Layout already matches (`PCPointer` + six ivars, instance size 356). Touch only if a typed rewrite is required for instruction shape (for example moving a `static`). No ivar or superclass churn. |
| Kernel Server `Makefile.postamble` | Created at `SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/Makefile.postamble`. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. The generated `Makefile` already `-include`s it and already names it in `OTHERSRCS`. |
| `vm/build-i386-input-recon.sh` | Restored if missing; otherwise keep sibling arms and add `drvSerialPointingDevice`. This campaign only *runs* that arm. Stages `/build/out/i386/drvSerialPointingDevice/SerialPointingDevice.config/SerialPointingDevice_reloc`. |
| `tools/binrecon/profiles/serialpointingdevice.json` | Adds `"rebuilt": { "path": "${BINRECON_REBUILT}" }`. IDA stays on. Ghidra and angr `enabled: false` for this campaign's analyze. `output_dir` stays `../out/serialpointingdevice`. |
| `reconstruction/function-worklist.md` | Created after Phase 1; refreshed when a diagnosed gap closes or a function is accepted. Ranked remaining rows and both SHA-256s. |
| `reconstruction/divergences.md` | July Findings 1–16 stay. VERS gap closed here. Exhausted experiment lists and accepts live here. |
| `reconstruction/ledger.json` | Status of record. `assembly-matched` on `masked_equal`; `intentional-mismatch` for accepted compiler leftovers (reason + reviewer required) and the two glue methods. `rebuilt_sha256` set from the last kept `_reloc`. |
| `reconstruction/source-map.json` | Line numbers only, when bodies move. Partition stays 16 mapped / 2 unmapped. |
| `tools/binrecon/parity_check.py` | Regression gate: `missing_strings` and `missing_symbols` stay 0. Extra unstripped locals are not findings. |
| `src/drivers-i386/README` | Status line updated at the end; still not hardware-tested. |

Out of bounds: `Default.table`, `Load_Commands.sect`,
`Unload_Commands.sect`, `Makefile` / `Makefile.preamble`, `dpkg/`,
`src/kernel-7` (`PCPointer.h` / `PCPointer.m`), sibling input drivers,
`src/driverTools-1`, guest-installed `kernelserver.make`, `compare.py`,
`kernel-drivers-blacklist.json`, compiler flags beyond the existing
`-Wno-format -DDRIVER_PRIVATE`, hand-written glue, QEMU, boot, hardware.
Do not split `SerialPointingDevice.m` into extra translation units. Do not
re-enable Ghidra or angr.

`BINRECON_REFERENCE` is:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\SerialPointingDevice.config\SerialPointingDevice_reloc
```

`BINRECON_REBUILT` is the host-staged copy:

```
out/i386/drvSerialPointingDevice/SerialPointingDevice.config/SerialPointingDevice_reloc
```

## 5. Data flow

1. Host edits one allowed site (`SerialPointingDevice.m`, the new
   `Makefile.postamble`, the harness, or the profile).
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/input/drvSerialPointingDevice`.
   When the harness is the change, also sync `vm/build-i386-input-recon.sh`.
   Never `-All`.
3. Guest: `sh /build/source/vm/build-i386-input-recon.sh drvSerialPointingDevice`.
   Copy
   `/build/out/i386/drvSerialPointingDevice/SerialPointingDevice.config/SerialPointingDevice_reloc`
   to host `out/i386/drvSerialPointingDevice/SerialPointingDevice.config/`
   (gitignored). Strip CR from the harness if the guest's `/bin/sh` is the
   1999 Bourne shell, same as the video recon scripts.
4. Host: set both `BINRECON_*` variables. Run
   `binrecon analyze --profile tools/binrecon/profiles/serialpointingdevice.json`
   (IDA only). Then `binrecon function --list` and, for the open function,
   `--name`. Analyze may exit 1 until `normalized-functions` acceptance
   passes; that is expected during the campaign. The gate is that
   `tools/binrecon/out/serialpointingdevice/published/` contains
   `analysis-reference-ida.json`, `analysis-rebuilt-ida.json`, and
   `comparison-ida.json`. Reuse published reference analysis if
   `complete: true` and the SHA is `59C0C95C…`. Do not treat leftover
   Ghidra/angr published files as current.
5. Also run `tools/binrecon/parity_check.py` against `__TEXT,__cstring` and
   `__TEXT,__text` symbol names. A missing reference string or symbol is a
   finding. Extra unstripped locals are not.
6. After Phase 2, confirm `__TEXT,__const` contains the two `vers_string`
   symbols. Contents may differ.
7. Record the outcome in `divergences.md` before the next edit. Advance the
   ledger only on a kept rebuild.

Analyzer output under `tools/binrecon/out/serialpointingdevice/` stays
uncommitted. Never commit the reference binary or a rebuilt `_reloc`.

## 6. Error handling

- Guest build fails: stop. Fix or revert. Do not advance the ledger or
  invent section sizes.
- Guest unreachable: leave the campaign open. Do not claim
  instruction-stream results from an old `_reloc`.
- Any Phase 1 `masked_equal` / `raw_equal` row loses `masked_equal`: revert,
  record as failed-with-regression, continue the list.
- `VERS_OFILE` is a diagnosed reconstruction, not an experiment: keep the
  postamble even if `__text` extents do not close. If the two symbols are
  still missing after the local postamble, record whether
  `SerialPointingDevice_vers.c` / `.o` were generated and whether they
  appear on the `kl_ld` line. Existence stays unmet. Do not edit shared
  project types.
- Experiment non-match with no regression: revert, mark tried, next item.
- Experiment list empty and leftover is register allocation or stack spill:
  accept as `intentional-mismatch` with the `binrecon function --name` dump
  and a reviewer. Do not add dummy locals or reorder statements to chase
  gcc 2.7.
- `parity_check.py` missing a reference string or `__text` symbol: defect in
  the last edit; revert or fix before continuing.
- Ghidra/angr stay disabled. Do not treat their absence as a new analyzer
  disagreement. Do not re-enable them to work around `normalize.py`.

## 7. Experiment lists

Source-shape only. One item per rebuild. A match ends the row. Empty list
without a match is unreachable. Write the lists from the Phase 1 worklist;
do not invent them here. The notes below are load-bearing constraints and
optional starters, not a license to skip measurement.

### 7.1 Load-bearing (do not reorder)

These already match Apple's algorithm. Shape experiments may retarget a
local or a store order; they must not change the control they encode.

- `detect`: four-iteration baud sweep (`baudRate` 1200, 2400, 4800, 9600
  sending `executeEvent:0x33` at 2400, 4800, 9600, 19200); `M` / `M3` /
  `*?` → `mouseType` 1–4; Mouse Systems `C` at slot 5.
- `getByte:sleep:`: `do` / `while (active)` — one dequeue always happens
  before `_active` is consulted.
- `MSProtocol`: three-byte packet, 40 ms unsigned 64-bit gate, no `IOLog`.
- `FiveBProtocol`: `lastTimeStamp` updates on case 2 only, not case 4; same
  40 ms gate; no `IOLog`.
- `mouseInit:`: `[portDevice acquire:nil]`; `PCPatoi`; `BOOL` polarity
  (YES success, NO failure).

### 7.2 Optional starters if `--name` shows a source-shaped gap

1. `MSProtocol`: fold `maskedByte` so the high bit is masked in place, as
   the reference does (`and [ebp+var_1], 7Fh`).
2. `MSProtocol`: let `default:` fall through with the incremented
   `byteIndex` rather than forcing 0. The default is dead either way; only
   chase it if it is the cheapest remaining difference.
3. `detect`: compute `byte & 0x3F` inline in the verbose `*?` log instead
   of the `resolution` local.

### 7.3 `-[SerialPointingDevice setIntValues:forParameter:count:]`

List is empty unless `--name` shows a *source-level* difference. The
312-versus-263 gap from a prior rebuild is codegen. Do not add stack spills
by hand.

### 7.4 Glue

`kernelServerInstance` and `driverKitVersionForSerialPointingDevice` stay
generated. No experiments.

## 8. Testing

No QEMU, no boot, no serial mouse. Verification is the guest `_reloc` plus
host checks.

**Phase 1 baseline.** Harness `fail=0`, a staged `_reloc`, worklist written.
Record file size, `__TEXT,__text` size, `parity_check.py` counts, and
per-function `raw_equal` / `masked_equal`. The five July
`assembly-matched` rows are confirmed or demoted here, not assumed.

**After `VERS_OFILE`.** `__TEXT,__const` exists and names
`_SerialPointingDevice_VERS_STRING` and `_SerialPointingDevice_VERS_NUM`.
Contents may differ. `__text` identity of every previously matching
hand-written function must not regress. `missing_strings` /
`missing_symbols` stay 0.

**After each experiment rebuild.** `binrecon function --list` is the
worklist. Match → ledger `assembly-matched`. Exhausted list → leave
`control-flow-confirmed` or `intentional-mismatch` with the dump in
`divergences.md`.

**Final.** README names the new `masked_equal` counts, that the version
objects exist, and that the driver is still untested on hardware. Ledger
`rebuilt_sha256` is the last kept `_reloc`. Glue remains the two generated
methods only.

## 9. Success criteria

- `vm/build-i386-input-recon.sh` is in the tree and
  `sh … drvSerialPointingDevice` stages a `_reloc`.
- `_SerialPointingDevice_VERS_STRING` and `_SerialPointingDevice_VERS_NUM`
  exist in the `_reloc`.
- Each of the 16 hand-written functions is `assembly-matched` or recorded
  unreachable with its exhausted list.
- Previously matching methods still have `masked_equal`.
- Glue is still generated, not hand-written.
- `missing_strings` 0, `missing_symbols` 0.
- No shared makefile or other-driver edits beyond ensuring
  `vm/build-i386-input-recon.sh` has a working `drvSerialPointingDevice`
  arm.
