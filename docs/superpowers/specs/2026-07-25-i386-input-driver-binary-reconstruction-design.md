# Binary reconstruction of the i386 input drivers

Reconstruct `drvPS2Mouse`, `drvSerialPointingDevice`, `drvPS2Keyboard`,
`drvPCParallel`, and `drvBusMouse` against Apple's shipped i386 driver binaries,
using the `tools/binrecon` toolchain. Each driver gets a report pass that maps
every reference function to our source and records the divergences, followed by a
separate fix pass.

This continues
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md)
and
[2026-07-25-intel-bus-driver-binary-reconstruction-design.md](2026-07-25-intel-bus-driver-binary-reconstruction-design.md).
Everything those efforts built — reference-only profiles, the
`binrecon source-map` subcommand, the `load_source_map` semantic loader, the
`reconstruction/` artifact layout, the `ledger-v1` vocabulary,
`tools/binrecon/parity_check.py`, and `vm/build-i386-bus-drivers.sh` as a build
harness model — is in place and is reused unchanged.

## Motivation

`src/drivers-i386/README` marks all six i386 input drivers "needs compiled and
then tested". None has been checked against the binary Apple shipped. Scoping
this work read the reference symbol, string, and config-table data directly,
before any analyzer run, and found two drivers that cannot work at all because
they read a config key or device name that does not exist (§2.1, §2.2), one whose
logic is an invention rather than a reconstruction (§2.3), one with a mislabelled
mouse-type table (§2.4), and one missing both its `PB.project` files (§2.7).

Unlike the Intel effort, every reference function has a name-level counterpart in
our tree. Nothing is missing wholesale. This is a parity and divergence effort,
not a write-the-missing-class effort.

## 1. Scope

### 1.1 Targets

The `_reloc` preload executables under
`C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Driver | Reference binary | File size | `__text` | Functions | Hand-written |
| --- | --- | --- | --- | --- | --- |
| drvPS2Mouse | `PS2Mouse.config/PS2Mouse_reloc` | 30204 | 1804 | 13 | 11 |
| drvSerialPointingDevice | `SerialPointingDevice.config/SerialPointingDevice_reloc` | 39928 | 4468 | 18 | 16 |
| drvPS2Keyboard | `PS2Keyboard.config/PS2Keyboard_reloc` | 43460 | 4952 | 49 | 47 |
| drvPCParallel | `ParallelPort.config/ParallelPort_reloc` | 45312 | 7416 | 75 | 73 |
| drvBusMouse | `BusMouse.config/BusMouse_reloc` | 29796 | 1592 | 13 | 11 |

168 functions, of which 158 are hand-written; the remaining 10 are the two
build-generated glue methods per driver described in §2.8. All five retain full
symbol tables, so address-to-name resolution is exact rather than inferred.

### 1.2 Config tables are in scope

Each driver's `Default.table` is compared against the reference copy, as in the
Intel spec. They are checked-in source, not build output, and §2.1 and §2.2 show
that a single wrong key silently disables an otherwise plausible driver.

`"Driver Version"` is emitted by Apple's build and stays out of the comparison.

### 1.3 Out of scope

**ISASerialPort.** Its reference is 24412 bytes of `__text` across 45 functions
and roughly four translation units against our single 5305-line file, its config
keys and chip identification table diverge wholesale, and our source hand-writes
`__udivdi3`/`__umoddi3` where the reference links libgcc. It gets its own spec.

`InstallPPDev` and `RemovePPDev` beside `ParallelPort_reloc` are user-space
tools. Unlike the Intel spec's DYLDLINK inspector bundles they are built from our
tree and named in `Default.table` as `"Pre-Load"` and `"Post-Load"`, so they are
compiled during drvPCParallel's fix pass and excluded only from the
function-level comparison.

No boot testing, no QEMU run, and no binrecon comparison of a rebuilt artifact
against the reference. Verification of the fix passes is defined in §4.3.

`src/kernel-7` is untouched, including the second in-kernel `PS2Mouse.m` and
`PCPointer.h` that the drivers subclass.

## 2. Findings that shaped this design

All of these come from reading the reference Mach-O symbol table, `__cstring`
section, `__DATA` symbols, and `Default.table` during scoping, before any
analyzer run. They are recorded so the plan can be checked against them.

### 2.1 drvPS2Mouse cannot load

`PS2Mouse.m:512` calls `IOGetObjectForDeviceName("PS2KeyboardController", …)`.
`PS2Controller.m:182-183` registers itself with `setName:"PS2Controller"` and
`setDeviceKind:"PS2Controller"`, and the reference's only such string is
`PS2Controller` — its log string is
`initPointer: Can't find PS2Controller (%s)`. The lookup can never succeed, so
`PS2Mouse` cannot initialise regardless of the rest of its code. This is the same
class of one-string load blocker as `Intel824X0`'s `"Auto Detect_IDs"` typo.

`PS2Mouse.m:328` reads `[configTable valueForStringKey:"SkipDetection"]` where
the reference reads `Force Detection`. The shipped `Default.table` supplies
`"Force Detection" = "No"`, so the key our code asks for is absent from the table
it is handed, and the value therefore always parses as `NO`.

Whether the consuming test also has to invert is **not** determinable from the
strings. `PS2Mouse.m:414` reads `if (!skipDetection) { …presence check… }`, so
`SkipDetection = Yes` bypasses the check and lets the driver attach anyway. If
`Force Detection = Yes` means "attach even though detection failed", it is the
same operation under a different name and no inversion is needed; if it means
"run the check that would otherwise be skipped", the sense is opposite. Settling
this needs the disassembly of `-[PS2Mouse readConfigTable:]` (684) and
`-[PS2Mouse initWithController:]` (332), so the key rename happens in the table
pass and the sense question is resolved in drvPS2Mouse's report pass.

### 2.2 drvPCParallel never reads its minor device number key

`IOParallelPort.m:100` logs
`Nonzero Minor Device Number - only one dev this version`, matching the reference
byte for byte. But the value it tests does not come from the config table: lines
95 through 99 take the last character of `[deviceDescription name]` and `strcmp`
it against `"0"`. The reference reads the `Minor Device Number` key — it is in
`__cstring` alongside `0` — and `Default.table` supplies
`"Minor Device Number" = "0"`. The same name-derived value also feeds the
`sprintf(nameBuffer, "%s%s", "pp", minorDevStr)` at line 149, whose `pp` and
`%s%s` literals both match the reference, so the table read has to supply both
uses.

`IOParallelPort.m:158` separately reads `"Location"` and passes it to
`setLocation:`. That is not part of this finding: the reference `Default.table`
carries `"Location" = "System Baseboard"`. The reference's `__cstring` has no
`Location` entry, which suggests it does not read that key, but whether it calls
`setLocation:` by some other route is a report-pass question, not a table-pass
one.

### 2.3 drvBusMouse's logic is invented

Not one of the reference's ten `__TEXT,__cstring` entries appears in our source,
and not one of ours appears in the reference. The reference logs
`Bus Mouse : No bus mouse installed.` and
`Bus Mouse : configured IRQ (%d) doesn't equal actual IRQ (%d)`; ours logs
`BusMouse: Bus mouse not detected (signature mismatch)` and
`BusMouse: IRQ mismatch - config: %d, detected: %d`. A fully disjoint string set
implies invented control flow, not merely invented wording — the same signature
the Intel spec found in both `initFromDeviceDescription:` implementations.

All 11 hand-written functions — `_GetIRQFromBoard`, `_MouseIntHandler`,
`_BusMouseThread`, and the eight `BusMouse` methods — are rewritten from the
reference disassembly.

### 2.4 drvSerialPointingDevice has a table bug and four linkage divergences

The reference's `_mouseTypeList` is six `char *` at `__DATA,__data:8192` holding
`C`, `W3`, `W`, `V3`, `M`, `UNKNOWN`. Our `mouseTypeNames`
(`SerialPointingDevice.m:41`) has `M` in the slot the reference gives `W`, so one
mouse type is misnamed and `-[SerialPointingDevice detect]` has no notion of it.
`protocolList` matches the reference exactly.

The reference exports `_mouseTypeList` (8192), `_protocolList` (8216), `_active`
(8240) and `_mainLoop` (`__text:0`) as `external`. Our source declares all four
`static`. This is the same static-versus-external divergence commit b27e22b8
resolved in `drvPCMCIABus` by renaming our source to match Apple's; that
precedent is followed here.

Our source also emits two log strings the reference does not —
`%s: MSProtocol started` and `%s: FiveBProtocol started` — and drops one space
from the reference's `%s: No resolution in config table.  Defaulting to %d`.

Everything else in this driver matches, including the reference's own typo
`SerialPorintingDevice: Main thread terminated.`

### 2.5 drvPS2Keyboard is in good shape

Two log strings diverge, and both are behavioural claims rather than wording. The
reference says `PS2Keyboard kbdInit: no Interface ID; use default` and
`PS2Keyboard kbdInit: no Handler ID; use default`; ours says
`no Interface key in config table` and `no Handler ID key in config table`.
"Use default" states that the driver continues; our wording does not.

Fourteen C functions are `external` in the reference with names carrying no extra
underscore: `keyboardDataPresent`, `getKeyboardData`, `getKeyboardDataIfPresent`,
`getMouseData`, `getMouseDataIfPresent`, `clearOutputBuffer`,
`sendControllerData`, `resendControllerData`, `sendControllerCommand`,
`sendMouseCommand`, `disableMouse`, `enableMouse`, `NewStealKeyboardEvent`, and
`scancodeToKeyEvent`. Our source writes them one underscore deeper. This is the
§2.5-of-the-Intel-spec pattern; the same precedent applies.

`_exported_funcs` at `__DATA,__data:8192` is the table those functions are
published through, and its layout has to match for the mouse driver to reach
them. It is 32 bytes — eight pointers — so it publishes a subset of the fourteen.
Which eight, and in what order, is a report-pass question.

### 2.6 Four tables are missing `"Version"`

`5.01` for drvBusMouse, drvSerialPointingDevice and drvPCParallel; `5.00` for
drvPS2Mouse. drvPS2Keyboard already carries it. Every other line in all five
tables matches the reference.

drvPS2Keyboard is also the only one of the five carrying a verbatim copy of
Apple's `"Driver Version"` build stamp in checked-in source. That line is out of
the comparison (§1.2) and our build regenerates it, so it is recorded in
`divergences.md` and left alone rather than widening the diff.

### 2.7 drvPCParallel is missing both its `PB.project` files

The project lacks the `PB.project` for `PCParallelPort.drvproj` and for
`PCParallelPort.lksproj` that every other driver in the tree has. Both are added.
Nothing else in the build system is touched.

An earlier draft of this section claimed `PCParallelPort.lksproj/Makefile:20`
named a `Load_Commands.sect` that did not exist, and concluded from that the
driver could not build. The premise was wrong — the file has been present and
tracked since `3a0ab68f`, carrying the `WIRE` content the Makefile's `OTHERSRCS`
expects — but the conclusion happens to be right for an unrelated reason.

A baseline build on the Rhapsody guest confirms drvPCParallel does not compile:

```
IOParallelPortKern.h:110: parse error before `portObject'
IOParallelPortKern.h:99: previous declaration of `seltrue'
  conflicting with bsd/sys/systm.h:136
gnumake: *** [all@PCParallelPort.drvproj] Error 2
```

Repairing that is an explicit, separately committed step ahead of drvPCParallel's
divergence fixes, per §4.3's "baseline first" rule.

The same baseline run established the other four: drvBusMouse, drvPS2Keyboard,
drvPS2Mouse and drvSerialPointingDevice all compile and stage a `_reloc` today.
`drvISASerialPort`, which is out of scope, also fails.

### 2.7a The `Loaded Server` section gaps are closed

An earlier draft of this spec put both of the following out of scope and recorded
them as findings only. Evidence from drvPS2Mouse's fix pass changed that: closing
them costs one file and one word per driver, and produces exact section parity.
Both are now in scope.

`src/driverTools-1/KernelServerProjectType/kernelserver.make` emits each section
purely from whether a filename appears in the project's `OTHERSRCS`:

```make
LOAD_SECTION   = Load_Commands.sect
UNLOAD_SECTION = Unload_Commands.sect
...
ifneq "" "$(filter $(LOAD_SECTION), $(OTHERSRCS))"
    KL_LDFLAGS_LOAD_COMMANDS = -l $(LOAD_SECTION)
endif
ifneq "" "$(filter $(UNLOAD_SECTION), $(OTHERSRCS))"
    KL_LDFLAGS_UNLOAD_COMMANDS = -u $(UNLOAD_SECTION)
endif
```

**`Load_Commands.sect`.** drvPS2Keyboard, drvPS2Mouse and drvSerialPointingDevice
lacked one, so their `Loaded Server,Load Commands` section could not match
Apple's 164 bytes. drvPS2Mouse's fix pass added it and reached 164 exactly. The
other two get the same treatment in their fix passes. drvBusMouse, drvPCParallel
and drvISASerialPort already have the file.

**`Unload_Commands.sect`.** The reference binaries for BusMouse, PS2Keyboard,
PS2Mouse and SerialPointingDevice each carry a 102-byte
`Loaded Server,Unload Commands` section that nothing in this repository produces.
All four get one, with the reference content:

```
# 
# This loadable kernel driver is not unloadable. (I think) this file
# is still necessary.
#
```

followed by the reference's trailing blank lines to reach exactly 102 bytes.
ISASerialPort and ParallelPort have no such section in their references and must
not gain one.

The three already-reconstructed bus drivers also lack `Unload_Commands.sect`.
Retrofitting them is deliberately **not** part of this effort — it belongs to
whichever effort revisits those drivers — so the tree is knowingly left
inconsistent on this point until then.

### 2.8 The build-generated residue is the same as before

`+[<Name>KernelServerInstance kernelServerInstance]` and
`+[<Name>Version driverKitVersionFor<Name>]` appear in all five binaries, as do
the `_xxx.86`/`_xxx.89`/`_xxx.92` `__DATA,__bss` statics (`_xxx.102`/`.105`/`.108`
in ParallelPort) and the `_<Name>_VERS_STRING`, `_<Name>_VERS_NUM` and
`_<Name>_instance` data symbols. They are emitted by the Kernel Server project
type and `Load_Commands.sect`, not written by hand, and are expected to be absent
from source. Only the two glue methods carry function bodies and therefore appear
in the source map's `unmapped` bucket; the rest are data symbols outside
`__TEXT,__text` and do not appear there at all, per the drvPCIBus precedent.

## 3. Artifact layout

### 3.1 Committed

Per driver, a `reconstruction/` directory beside the sources:

```
src/drivers-i386/input/drvPS2Mouse/reconstruction/
    source-map.json      # source-map-v1, complete function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings, including table divergences
```

Also committed: one reference-only profile per driver at
`tools/binrecon/profiles/{ps2mouse,serialpointingdevice,ps2keyboard,parallelport,busmouse}.json`,
copied from the existing `pcmciabus.json` with `output_dir` set to
`../out/<driver>`; and `vm/build-i386-input-recon.sh`, modelled on the
committed `vm/build-i386-bus-drivers.sh`.

### 3.2 Not committed

Reference binaries (already external to the repo), rebuilt artifacts staged under
`out/i386/`, and all analyzer output under `tools/binrecon/out/`, which
`.gitignore:17` already excludes. The `.i64` databases, `.log` files and `.lock`
files are machine- and run-specific. The durable, reviewable evidence is the
source map, the ledger and the divergence document, all of which are text.

### 3.3 Reference paths

`BINRECON_REFERENCE` is per-shell-session. The values are:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Mouse.config\PS2Mouse_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\SerialPointingDevice.config\SerialPointingDevice_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Keyboard.config\PS2Keyboard_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\ParallelPort_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\BusMouse.config\BusMouse_reloc
```

## 4. The three kinds of pass

### 4.1 Table pass

Runs once, covering all five drivers, before any report pass. This is a
deliberate carve-out from the standing discipline that fixes touch only what the
ledger flags. It is justified because every fix in it rests on evidence stronger
than a decompilation: either a direct diff of our checked-in `Default.table`
against Apple's checked-in `Default.table`, or a contradiction internal to our
own tree. No analyzer run is needed and no ledger entry is required to authorise
them.

The complete list:

1. `PS2KeyboardController` → `PS2Controller` in `PS2Mouse.m:512` (§2.1).
2. `"SkipDetection"` → `"Force Detection"` in `PS2Mouse.m:328`, key name only.
   The sense of the consuming test at `PS2Mouse.m:414` is left as it is and
   resolved in drvPS2Mouse's report pass (§2.1).
3. `IOParallelPort.m:95-99` reads `"Minor Device Number"` from the config table,
   defaulting to `"0"`, instead of deriving the value from the device name suffix
   (§2.2). The `"Location"` read at line 158 is not touched.
4. The four missing `"Version"` lines (§2.6).
5. drvPCParallel's two `PB.project` files (§2.7).

Nothing else. Every other finding in §2 waits for its driver's report pass.

*Verify:* `binrecon validate --profile …` prints each reference identity with no
rebuilt artifact; `PS2KeyboardController` and `SkipDetection` appear nowhere in
the five drivers; `IOParallelPort.m` reads `"Minor Device Number"`; each
`Default.table` differs from the reference only in `"Driver Version"`.

### 4.2 Report pass

Runs per driver, needs no VM.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/<driver>.json`
   produces IDA 9.2, Ghidra 12.1 and angr 9.3.0 analyses plus
   `consensus-reference.json` under the gitignored `tools/binrecon/out/<driver>/`.

2. **Map.** `binrecon source-map --reference-analysis … --binary … --source-dir …
   --repo-root … --output …` anchored on the Mach-O symbol table, then
   hand-resolve the residue. Every reference function lands in exactly one
   bucket:

   - `mapped` — resolved to a file and line.
   - `unmapped` — build-generated glue (§2.8).
   - `boundary_disputed` — analyzers disagree on function extent.
   - `duplicate_candidates` — a name resolves to two or more plausible sites.

3. **Diff.** Decompile every `mapped` function and compare against our source,
   batched by source file. The comparison covers control-flow shape, literal
   constants, I/O port addresses, struct field offsets, and call targets.

4. **Compare tables.** Diff `Default.table` against the reference copy, ignoring
   `"Driver Version"`. After the table pass this is expected to be clean for all
   five; a residual difference is a table-pass defect, not a new finding.

5. **Report.** Write `divergences.md` with the reference decompilation beside our
   source for each finding, and assign each function a `ledger-v1` status. The
   ledger records parity confidence, not a repair queue; its vocabulary is
   `unexamined`, `signature-confirmed`, `control-flow-confirmed`,
   `assembly-matched`, and `intentional-mismatch`. A function that matches gets
   the strongest status the evidence supports. A function that diverges stays
   `unexamined` and gets an entry in `divergences.md`, per the convention
   established by the drvPCIBus pass. `rebuilt_sha256` is `null` throughout,
   which `ledger-v1` permits.

**Done when** `load_source_map(path, reference_analysis=…, repo_root=…)` passes —
it enforces the complete function partition, names, full function sizes, and
source-line bounds — every `unmapped` entry has a stated reason class in
`divergences.md`, and no function remains without a ledger entry.

### 4.3 Fix pass

Runs per driver, after that driver's report pass is committed, as a separate
phase with its own commits.

**Disposition.** Every finding in `divergences.md` is resolved one of two ways.
Either the source is changed to match the reference, after which the function's
ledger status advances to the level the new evidence supports, or the divergence
is accepted and the ledger status becomes `intentional-mismatch` with a reason
and a reviewer — the ledger CLI requires both. Accepted by default:
build-generated glue, compiler-emitted statics, and anything whose reference form
depends on Apple's toolchain rather than on our source.

**Discipline.** Fixes touch only code the ledger flags. Two approved exceptions:
the §2.4 and §2.5 `static` → `external` linkage changes, which are properties of
declarations the ledger already flags rather than separate findings; and
drvBusMouse's wholesale rewrite (§2.3), approved as a unit rather than
finding-by-finding. No other adjacent cleanup, no refactoring of code that is not
divergent.

**Verification.** Three checks per driver, each against the rebuilt `_reloc`:

1. **Compiles.** `vm/build-i386-input-recon.sh` exits 0 and a `_reloc` lands on
   disk. For drvPCParallel, `InstallPPDev` and `RemovePPDev` must also build.
   Warnings are captured to a log and reviewed, but do not gate.

2. **String parity.** `tools/binrecon/parity_check.py` against the reference's
   `__TEXT,__cstring` set. This is the check that would have caught §2.1 through
   §2.5 immediately, and it costs nothing. It reads `__cstring` only, so string
   literals the compiler routes to `__OBJC` sections — selector names, class
   names — cannot produce false positives.

3. **Symbol parity.** `parity_check.py` against the reference's `__TEXT,__text`
   symbol names. Catches the §2.4 and §2.5 linkage and underscore groups.

Checks 2 and 3 are reported, not gated: our build is unstripped and will carry
extras. A reference string or symbol missing from our build is a finding; an
extra one of ours is not automatically a finding.

`parity_check.py` compares symbol names as a set, so a name defined more than
once in one binary collapses to a single entry. That is safe for all five drivers
here, each of which has fully distinct `__text` symbol names. It is a real
limitation only for ISASerialPort, which defines one static three times, and that
belongs to the other spec.

**Baseline first.** Each driver is built before any source edits, so a
pre-existing failure cannot be misattributed to our changes. All five are marked
"needs compiled and then tested" and may never have been built. If a baseline
build fails, repairing that breakage is an explicit, separately committed step
ahead of that driver's divergence fixes. drvPCParallel's known scaffolding gap is
the one exception: it is already diagnosed (§2.7) and is fixed in the table pass
instead.

The rebuilt `_reloc` is staged to `out/i386/<driver>/` but is not fed to binrecon
as a comparison artifact.

## 5. Sequencing

Ascending difficulty rather than ascending size, one driver carried all the way
through before the next starts.

**Phase 0 — tooling.** Write the five profiles. Write
`vm/build-i386-input-recon.sh` with a `build_one` line per driver and the five
resulting paths in its closing summary.

*Verify:* `binrecon validate --profile tools/binrecon/profiles/<driver>.json`
prints the reference identity for each of the five with no rebuilt artifact.

**Phase 1 — table pass.** §4.1, all five drivers at once.

*Verify:* the three §4.1 checks.

**Phase 2 — drvPS2Mouse report pass** (11 hand-written functions). Report pass
per §4.2. Establishes the `PCPointer` subclass shape — `mouseInit:`,
`getResolution`, `getIntValues:forParameter:count:`,
`setIntValues:forParameter:count:`,
`getHandler:level:argument:forInterrupt:` — that drvBusMouse reuses.

*Verify:* `load_source_map` passes against the reference analysis.

**Phase 3 — drvPS2Mouse fix pass.** Per §4.3.

*Verify:* the three §4.3 checks.

**Phase 4 — drvSerialPointingDevice report pass** (16 functions).

*Verify:* `load_source_map` passes.

**Phase 5 — drvSerialPointingDevice fix pass.** Fix the `_mouseTypeList` slot,
the four linkage divergences, the two extra log strings, and the dropped space
(§2.4).

*Verify:* the three §4.3 checks.

**Phase 6 — drvPS2Keyboard report pass** (47 functions).

*Verify:* `load_source_map` passes.

**Phase 7 — drvPS2Keyboard fix pass.** Fix the two `kbdInit` strings and the
fourteen-symbol underscore group (§2.5).

*Verify:* the three §4.3 checks.

**Phase 8 — drvPCParallel report pass** (73 functions). The largest in scope,
spanning `IOParallelPort.m` and `IOParallelPortKern.m`. `InstallPPDev` and
`RemovePPDev` are not function-compared (§1.3).

*Verify:* `load_source_map` passes.

**Phase 9 — drvPCParallel fix pass.** Per §4.3.

*Verify:* the three §4.3 checks, including that both user-space tools build.

**Phase 10 — drvBusMouse report pass** (11 functions). The report pass still
runs in full, because the rewrite needs a mapped, sized partition to write
against.

*Verify:* `load_source_map` passes.

**Phase 11 — drvBusMouse fix pass.** Rewrite all 11 hand-written functions
against the reference disassembly (§2.3), informed by Phase 2's worked example of
the shared `PCPointer` method set.

*Verify:* the three §4.3 checks, plus per-function size against the reference
(§6).

**Phase 12 — README.** Update the five `input` status lines in
`src/drivers-i386/README` to the reconstructed wording the bus drivers use.

## 6. Failure modes

**drvBusMouse's rewrite can overfit.** 1592 bytes across 11 functions. A rebuilt
function materially larger than its reference counterpart means we invented
structure again. Per-function size against the reference is the check, as in the
Intel spec.

**The `_mouseTypeList` slot may not be recoverable from the reference alone.** We
know slot 3 holds `W` and that our source has `M` there, but what `W` denotes and
how `detect` reaches it has to come from the disassembly of
`-[SerialPointingDevice detect]` (1876–3256, 1380 bytes). If it does not, the
entry becomes `intentional-mismatch` with the reason recorded rather than a
guess.

**`_exported_funcs` layout may not be inferable.** drvPS2Keyboard publishes eight
of its fourteen exported C functions through a 32-byte table at
`__DATA,__data:8192`. If the report pass cannot establish which eight, or their
order, from the disassembly, the underscore rename (§2.5) still proceeds — it is a
source-name change — but the table layout itself goes to `divergences.md`
unresolved.

**Analyzer disagreement is preserved, not resolved by majority.** IDA and Ghidra
function discovery are claims, not truth. Conflicting boundaries go to
`boundary_disputed` for human resolution.

**Ghidra rejecting legacy Mach-O input** falls back to deterministic raw i386
import using parsed Mach-O sections. Java 21 and Ghidra 12.1 remain mandatory
for the two drivers that still use Ghidra.

**Ghidra normalization fails outright on three of the five drivers, and they run
with two analyzers instead.** `drvSerialPointingDevice`, `drvPS2Keyboard` and
`drvPCParallel` all abort normalization with
`Ghidra relocation operand metadata is ambiguous` (`normalize.py:432`), leaving
`complete: false` and no reference consensus. The cause is specific instruction
forms, not scale: `Intel82365PCMCIA` is larger than `ParallelPort` and normalizes
cleanly with all three. The disambiguation those three fall outside of was added
by commit `d34b04a6` for this same class of problem.

Ghidra is therefore disabled in those three profiles and they run IDA + angr,
which was verified to produce `complete: true` with a valid reference consensus.
`drvPS2Mouse` and `drvBusMouse` keep all three analyzers. Each affected driver's
`divergences.md` states the reduced analyzer set as a limitation of its evidence.

This is a real weakening: the effort's premise is multi-analyzer corroboration
with disagreement preserved rather than voted away. It is tolerable because IDA
is already authoritative for the function partition by the convention drvPCIBus
established, and angr still supplies an independent second opinion — so what is
lost is one corroborating source on three drivers, not the evidence base. Fixing
`normalize.py` is the better answer and belongs to its own effort, because five
already-committed reconstructions depend on that code.

**angr `CFGFast` misses on indirect control flow** are recorded as CFG errors,
never read as "function absent". `IOParallelPortKern.m` dispatches through
`sel_getUid` in at least three places, so expect some in Phase 8.

**A failed or timed-out run** yields `complete: false` and cannot report passing
acceptance. The runner refuses to accept leftover output from an earlier run as
evidence.

**The Rhapsody guest may be unavailable.** The table pass and all five report
passes still deliver in full; only the fix passes block. drvPCParallel's table
pass scaffolding fix is unverifiable without a build, so it ships as a
stated-unverified change if the guest is down.

**A baseline build may fail for reasons unrelated to us.** None of the five has
been built. Repairing that is separately committed, ahead of the divergence fixes
for that driver.

## 7. Deliverables

Per driver — drvPS2Mouse, drvSerialPointingDevice, drvPS2Keyboard, drvPCParallel,
drvBusMouse:

- `src/drivers-i386/input/<driver>/reconstruction/source-map.json`
- `src/drivers-i386/input/<driver>/reconstruction/ledger.json`
- `src/drivers-i386/input/<driver>/reconstruction/divergences.md`
- `tools/binrecon/profiles/<name>.json`, where `<name>` is the lower-cased
  reference server name rather than the `drv` directory name — `ps2mouse`,
  `serialpointingdevice`, `ps2keyboard`, `parallelport`, `busmouse` — matching the
  existing `pcibus.json` / `pcmciabus.json` convention

Repository-wide:

- `vm/build-i386-input-recon.sh`
- `PB.project` for `PCParallelPort.drvproj` and for `PCParallelPort.lksproj`
- `src/drivers-i386/README` status lines updated for all five
- `Load_Commands.sect` for drvPS2Keyboard, drvPS2Mouse and drvSerialPointingDevice,
  each named in its `.lksproj/Makefile` `OTHERSRCS` (§2.7a)
- `Unload_Commands.sect` for drvBusMouse, drvPS2Keyboard, drvPS2Mouse and
  drvSerialPointingDevice, likewise named in `OTHERSRCS` (§2.7a)

Not deliverables: any change to `drvISASerialPort`, any change under
`src/kernel-7`, an `Unload_Commands.sect` for drvPCParallel or drvISASerialPort
(neither reference has that section), a retrofit of `Unload_Commands.sect` onto
the three already-reconstructed bus drivers, and any boot test.
