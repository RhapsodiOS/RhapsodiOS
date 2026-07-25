# Binary reconstruction of Intel824X0PCI and Intel82365PCMCIA

Reconstruct `Intel824X0PCI` and `Intel82365PCMCIA` against Apple's shipped i386
driver binaries, using the `tools/binrecon` toolchain. Each driver gets a report
pass that maps every reference function to our source and records the
divergences, followed by a separate fix pass.

This continues
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md),
which covered `drvPCIBus`, `drvPCMCIABus`, and `drvEISABus` and explicitly
deferred `PCIC.config` (§1.2). The tooling that effort built — reference-only
profiles, the `binrecon source-map` subcommand, the `reconstruction/` artifact
layout, the `ledger-v1` vocabulary — is in place and proven on three drivers and
is reused unchanged here.

## Motivation

`src/drivers-i386/README` marks `Intel824X0PCI` as "complete" and
`Intel82365PCMCIA` as "needs compiled and then tested". Neither has been checked
against the binary Apple shipped. Scoping this work read the reference symbol and
string tables directly, before any analyzer run, and found that both claims are
wrong in the same way: the driver-entry method of each is an invention rather
than a reconstruction (§2.2), and `Intel824X0PCI` additionally cannot load at all
because of a one-character typo in its config table (§2.4).

## 1. Scope

### 1.1 Targets

The `_reloc` preload executables under
`C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Driver | Reference binary | File size | `__text` | Functions |
| --- | --- | --- | --- | --- |
| Intel824X0PCI | `Intel824X0.config/Intel824X0_reloc` | 28376 | 548 | 4 |
| Intel82365PCMCIA | `PCIC.config/PCIC_reloc` | 38700 | 7548 | 82 |

Both retain full symbol tables, so address-to-name resolution is exact rather
than inferred. Of Intel824X0's 4 functions, 2 are build-generated glue, leaving 2
hand-written.

### 1.2 Added to scope beyond the prior spec

The driver config tables — `Intel824X0.drvproj/Default.table` and
`PCIC.drvproj/PCI.table` — are compared against the reference copies. They are
checked-in source, not build output, and §2.4 shows that a one-character error
there silently disables an otherwise correct driver. The prior spec was
function-only and did not look at them.

`"Driver Version"` is emitted by Apple's build and stays out of the comparison.

### 1.3 Out of scope

The `DYLDLINK` bundles beside each `_reloc` (`Intel824X0`, `PCIC`) are user-space
inspector bundles, not kernel driver code.

No boot testing, no QEMU run, and no binrecon comparison of a rebuilt artifact
against the reference. Verification of the fix passes is defined in §4.2.

These two directories are not renamed to the `drv*` convention their siblings
use. That is unrelated churn.

## 2. Findings that shaped this design

All of these come from reading the reference Mach-O symbol and string tables
during scoping, before any analyzer run. They are recorded so the plan can be
checked against them.

### 2.1 `PCIC_PCI` is absent from our tree

The reference defines `-[PCIC_PCI initFromDeviceDescription:]` at address 0, with
an accompanying `.objc_class_name_PCIC_PCI`. Its log string,
`PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)`, identifies it as the
PCI-attached bridge variant of `PCIC`.

`PCIC.drvproj/PCI.table` in our tree already names `PCIC_PCI` as its
`"Driver Name"`, and its `"Auto Detect IDs" = "0x11001013"` is the Cirrus Logic
PD6832. But no such class exists anywhere in `PCIC.lksproj`. The class must be
written from the reference disassembly.

### 2.2 Both `initFromDeviceDescription:` implementations are invented

The reference `__TEXT,__cstring` sections do not contain our source's log
strings, and our source does not contain theirs.

`Intel824X0` identifies different silicon than our source claims. The reference
strings are `Intel 82424ZX Host-Bridge`, `Intel 82434%cX Host-Bridge (step A-%d)`,
`%s: Detected `, `%s: Disabling PCI-to-Memory write posting.`, and
`%s: PCI-to-Memory write posting disabled by BIOS.`. The `%cX` selects between
82434LX and 82434NX — a distinction our source has no notion of. Our source's
comments and messages call the same two device IDs "82440FX (Natoma)" and
"82443FX (Orion)", and decode a "C-%d stepping" where the reference decodes
"step A-%d". Device IDs 0x0483 and 0x04A3 are in fact the 82424ZX and the
82434LX/NX. Not one of our source's seven `IOLog` format strings appears in the
reference.

`PCIC` shows the same pattern more narrowly. The reference has three log strings
in this method — `PCIC: No device at base address 0x%04x`,
`PCIC: couldn't enable interrupts`, `PCIC: couldn't start IO thread` — of which
our source has the last two. Our source has six more that the reference does not
(`No I/O port range specified`, `Hardware validation failed at port 0x%x`,
`Failed to create socket list`, `Failed to create window list`,
`Failed to create any sockets`, `Initialized at port 0x%x, IRQ %d, %d sockets%s`),
which implies invented control flow, not merely invented logging.

This is the bulk of the fix work in both drivers.

### 2.3 File placement diverges in PCIC

Reference link order places `setMemoryWindow` (address 6620) and `setIoWindow`
(7084) between `-[PCICWindow set16Bit:]` (6324) and
`-[PCICWindow(Attributes) canUse8Bit]` (7316), so both belong to `PCICWindow.m`.
Our source defines them in `PCIC.m`, declares them `extern` in `PCICWindow.m`,
and prototypes them in `PCICInternal.h`.

The fix pass moves them into `PCICWindow.m` and drops the extern declarations and
prototypes. This restores Apple's file boundaries so our link order matches,
which keeps any future address-based re-mapping of this driver honest.

### 2.4 The Intel824X0 auto-detect key is misspelled

Our `Intel824X0.drvproj/Default.table` reads `"Auto Detect_IDs"`; the reference
reads `"Auto Detect IDs"`. A driver whose auto-detect key does not match is never
selected, so `Intel824X0PCI` cannot load today regardless of its code.

Both tables also drop a `"Version"` line the reference carries: `"5.01"` for
`Intel824X0/Default.table`, `"5.00"` for `PCIC/PCI.table`.

### 2.5 The drvPCMCIABus underscore divergence recurs

The reference's C function symbols are `_socketIsValid`, `_checkForCirrusChip`,
`_setStatusChangeInterrupt`, `_FindEmptyMemoryRange`, `_setWindow`,
`_MapAttributeMemory`, `_setMemoryWindow`, and `_setIoWindow` — that is, C source
names without a leading underscore. Our source writes `_socketIsValid` and so on
in C, which the compiler renders one underscore deeper.

This is the same divergence found in `drvPCMCIABus`, where commit b27e22b8
resolved it by renaming our source to match Apple's. That precedent is followed
here.

One of the eight also diverges in linkage. All are `local` in the reference
except `_MapAttributeMemory`, which is `external`; our `PCICDebug.m` declares it
`static`. The linkage is fixed alongside the rename, since both are properties of
the same declaration.

### 2.6 `_socketIsValid` is defined twice in the reference

At 1488 and again at 2816. Our source has a single definition in `PCIC.m` plus an
`extern` in `PCICSocket.m`.

The first copy is unambiguous: it sits between `-[PCIC setPowerManagement:]`
(1476) and `_checkForCirrusChip` (1564), so it is the tail of `PCIC.m` — the same
place our source puts it. The second is ambiguous. It sits between
`-[PCIC(Internal) writeRegister:socket:value:]` (2748) and
`-[PCICSocket initWithAdapter:socketNumber:]` (2892), so it is either the tail of
`PCICInternal.m` or the head of `PCICSocket.m`, and link order alone cannot
decide. The report pass resolves it from the disassembly; until it does, the
entry belongs in `duplicate_candidates` rather than being guessed.

### 2.7 `PCICDebug.m` is in good shape

Its three log strings — `BIOS at %x, length %x`, `No BIOS at %x`,
`buffer: logical %x, physical %x` — match the reference exactly, as does
`PCIC: readAttributeMemory: not ready`. Expected to come out mostly
`assembly-matched`.

### 2.8 The build-generated residue is the same as before

`+[<Name>KernelServerInstance kernelServerInstance]` and
`+[<Name>Version driverKitVersionFor<Name>]` appear in both binaries. They are
emitted by the Kernel Server project type and `Load_Commands.sect`, not written
by hand, and are expected to be absent from source.

## 3. Artifact layout

### 3.1 Committed

Per driver, a `reconstruction/` directory beside the sources:

```
src/drivers-i386/bus/Intel824X0PCI/reconstruction/
    source-map.json      # source-map-v1, complete function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings, including table divergences
```

Also committed: one reference-only profile per driver at
`tools/binrecon/profiles/{intel824x0,intel82365pcmcia}.json`, copied from the
existing `pcmciabus.json` with `output_dir` set to `../out/intel824x0` and
`../out/intel82365pcmcia`.

### 3.2 Not committed

Reference binaries (already external to the repo), rebuilt artifacts staged under
`out/i386/`, and all analyzer output under `tools/binrecon/out/`, which
`.gitignore:17` already excludes. The `.i64` databases, `.log` files, and `.lock`
files are machine- and run-specific. The durable, reviewable evidence is the
source map, the ledger, and the divergence document, all of which are text.

### 3.3 Reference paths

`BINRECON_REFERENCE` is per-shell-session. The values are:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\Intel824X0.config\Intel824X0_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\PCIC.config\PCIC_reloc
```

### 3.4 Deviation from the prior spec

That spec's §7 listed a `docs/drivers/drv<Name>-issues.md` per driver, but only
`drvEIDE-issues.md` exists — the three bus drivers never received one, and
`divergences.md` carried the findings instead. This design drops the separate
issues document rather than reintroduce a duplicate of `divergences.md`. The
`src/drivers-i386/README` status lines are still updated (Phase 5).

## 4. The two passes

### 4.1 Report pass

Runs per driver, needs no VM.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/<driver>.json`
   produces IDA 9.2, Ghidra 12.1, and angr 9.3.0 analyses plus
   `consensus-reference.json` under the gitignored `tools/binrecon/out/<driver>/`.

2. **Map.** `binrecon source-map --reference-analysis … --binary … --source-dir …
   --repo-root … --output …` anchored on the Mach-O symbol table, then
   hand-resolve the residue. Every reference function lands in exactly one
   bucket:

   - `mapped` — resolved to a file and line.
   - `unmapped` — build-generated glue (§2.8) or code genuinely absent from our
     tree (§2.1).
   - `boundary_disputed` — analyzers disagree on function extent.
   - `duplicate_candidates` — a name resolves to two or more plausible sites
     (§2.6).

3. **Diff.** Decompile every `mapped` function and compare against our source,
   batched by source file. The comparison covers control-flow shape, literal
   constants, I/O port addresses, struct field offsets, and call targets.

4. **Compare tables.** Diff `Default.table` and `PCI.table` against the reference
   copies, ignoring `"Driver Version"`.

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

### 4.2 Fix pass

Runs per driver, after that driver's report pass is committed, as a separate
phase with its own commits.

**Disposition.** Every finding in `divergences.md` is resolved one of two ways.
Either the source is changed to match the reference, after which the function's
ledger status advances to the level the new evidence supports, or the divergence
is accepted and the ledger status becomes `intentional-mismatch` with a reason and
a reviewer — the ledger CLI requires both. Accepted by default: build-generated
glue, compiler-emitted statics, and anything whose reference form depends on
Apple's toolchain rather than on our source.

**Discipline.** Fixes touch only code the ledger flags. The one deliberate
exception is the §2.3 cross-file move, which is approved as part of this design.
No other adjacent cleanup, no refactoring of code that is not divergent.

**Verification.** Three checks per driver, each against the rebuilt `_reloc`:

1. **Compiles.** `vm/build-i386-bus-drivers.sh` gains a
   `build_one Intel824X0 Intel824X0PCI Intel824X0.drvproj` line and a
   `build_one PCIC Intel82365PCMCIA PCIC.drvproj` line, plus the two new paths in
   its closing summary. The check is exit 0 and a `_reloc` on disk. Warnings are
   captured to a log and reviewed, but do not gate.

2. **String parity.** Compare the rebuilt `__TEXT,__cstring` set against the
   reference's. This is the check that would have caught §2.2 immediately, and it
   costs nothing.

3. **Symbol parity.** Compare the rebuilt `__TEXT,__text` symbol names against the
   reference's. Catches the §2.5 underscore group and confirms `PCIC_PCI` landed.

Checks 2 and 3 run four times — two drivers, baseline and post-fix — so they get
a small committed script, `tools/binrecon/parity_check.py`, built on
`binrecon.macho.read_macho`, rather than a repeated shell heredoc.

Checks 2 and 3 are reported, not gated: our build is unstripped and will carry
extras. A reference string or symbol missing from our build is a finding; an
extra one of ours is not automatically a finding.

The rebuilt `_reloc` is staged to `out/i386/<driver>/` but is not fed to binrecon
as a comparison artifact.

**Baseline first.** Each driver is built before any source edits, so a
pre-existing failure cannot be misattributed to our changes. `Intel82365PCMCIA`
is marked "needs compiled and then tested" and may never have been built. If the
baseline build fails, repairing that breakage is an explicit, separately
committed step ahead of the divergence fixes.

## 5. Failure modes

**`PCIC_PCI` may not be implementable from the decompilation.** It is a single
method, and its behavior is constrained by its log string and by `PCI.table`'s
`"Auto Detect IDs" = "0x11001013"` (Cirrus Logic PD6832). If the reference
decompilation is nonetheless too incomplete to implement from, the report pass
records a go/no-go in `divergences.md` and the class splits into its own spec —
the pattern the prior spec used for `drvEISABus`'s `PnPArgStack`. This is the
single largest risk in the effort.

**Rewriting `initFromDeviceDescription:` from strings and disassembly can
overfit.** The reference is 460 bytes for `Intel824X0`; a rebuilt function
materially larger means we invented structure again. Function size against the
reference is the check.

**Analyzer disagreement is preserved, not resolved by majority.** IDA and Ghidra
function discovery are claims, not truth. Conflicting boundaries go to
`boundary_disputed` for human resolution.

**Ghidra rejecting legacy Mach-O input** falls back to deterministic raw i386
import using parsed sections. Java 21 and Ghidra 12.1 remain mandatory.

**angr `CFGFast` misses on indirect control flow** are recorded as CFG errors.
They are never read as "function absent".

**A failed or timed-out run** yields `complete: false` and cannot report passing
acceptance. The runner refuses to accept leftover output from an earlier run as
evidence.

**The second `_socketIsValid` cannot be placed by link order alone** (§2.6). It
must be resolved from the disassembly; absent that it belongs in
`duplicate_candidates` rather than being guessed.

**The Rhapsody guest may be unavailable.** Both report passes still deliver in
full; only the fix passes block.

## 6. Sequencing

Ascending size order, one driver carried all the way through before the next
starts. `Intel824X0PCI` is 2 hand-written functions, so it calibrates the
profile, the source-map conventions, and the table-comparison policy cheaply, and
resolves the false "complete" README claim early.

**Phase 0 — tooling.** Write the two profiles. Add the two `build_one` lines and
the two summary paths to `vm/build-i386-bus-drivers.sh`.

*Verify:* `binrecon validate --profile tools/binrecon/profiles/intel824x0.json`
and the `intel82365pcmcia` equivalent each print the reference identity with no
rebuilt artifact.

**Phase 1 — Intel824X0PCI report pass** (4 functions). Report pass per §4.1.

*Verify:* `load_source_map` passes against the reference analysis.

**Phase 2 — Intel824X0PCI fix pass.** Rewrite `initFromDeviceDescription:`
against the 82424ZX and 82434LX/NX reality (§2.2). Fix `"Auto Detect_IDs"` and
add the missing `"Version"` (§2.4).

*Verify:* the three §4.2 checks.

**Phase 3 — Intel82365PCMCIA report pass** (82 functions). Report pass per §4.1.

*Verify:* `load_source_map` passes against the reference analysis.

**Phase 4 — Intel82365PCMCIA fix pass.** Write `PCIC_PCI` (§2.1). Rewrite
`-[PCIC initFromDeviceDescription:]` (§2.2). Move `setMemoryWindow` and
`setIoWindow` into `PCICWindow.m` (§2.3). Rename the underscore group (§2.5). Add
the missing `"Version"` to `PCI.table` (§2.4).

*Verify:* the three §4.2 checks.

**Phase 5 — README.** Update the `Intel824X0PCI` and `Intel82365PCMCIA` status
lines in `src/drivers-i386/README` to the reconstructed wording the other bus
drivers use.

## 7. Deliverables

Per driver:

- `src/drivers-i386/bus/<Driver>/reconstruction/source-map.json`
- `src/drivers-i386/bus/<Driver>/reconstruction/ledger.json`
- `src/drivers-i386/bus/<Driver>/reconstruction/divergences.md`
- `tools/binrecon/profiles/<driver>.json`

Repository-wide:

- `tools/binrecon/parity_check.py`, the string and symbol parity checker
- `vm/build-i386-bus-drivers.sh` extended to both drivers
- `src/drivers-i386/README` status lines updated for both drivers
