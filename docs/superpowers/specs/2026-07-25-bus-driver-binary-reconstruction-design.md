# Binary reconstruction of the i386 bus drivers

Reconstruct `drvPCIBus`, `drvPCMCIABus`, and `drvEISABus` against Apple's shipped
i386 driver binaries, using the `tools/binrecon` toolchain. Each driver gets a
report pass that maps every reference function to our source and records the
divergences, followed by a separate fix pass.

## Motivation

`src/drivers-i386/README` marks `drvEISABus` as "crashing, needs debugging" and
`drvPCMCIABus` as "needs compiled and then tested". Neither has been checked
against the binaries Apple shipped. A symbol-level cross-check done while
scoping this work already found that our `drvEISABus` PnP BIOS layer is
architecturally different from the reference (§2.3), which is a plausible cause
of the crash.

## 1. Scope

### 1.1 Targets

The reconstruction targets the `_reloc` preload executables under
`C:\Users\raynorpat\Downloads\test\Drivers\i386`:

| Driver | Reference binary | Size | Defined syms | ObjC methods |
| --- | --- | --- | --- | --- |
| drvPCIBus | `PCIBus.config/PCIBus_reloc` | 41360 | 39 | 21 |
| drvPCMCIABus | `PCMCIABus.config/PCMCIABus_reloc` | 92192 | 97 | 65 |
| drvEISABus | `EISABus.config/EISABus_reloc` | 100752 | 209 | 144 |

The binaries retain full symbol tables, so address-to-name resolution is exact
rather than inferred. Total function count across all three is roughly 260.

### 1.2 Out of scope

The `DYLDLINK` bundles that sit beside each `_reloc` (`PCIBus`, `PCMCIABus`,
`EISABus`) are user-space AppKit inspector bundles, not kernel driver code.
`EISABus` contains `EISABusInspector`, whose `.m` is absent from our tree — only
`EISABusInspector.nib` is checked in. Reconstructing the inspectors is not part
of this work.

`PCIC.config` (Intel82365PCMCIA) is also not in scope.

No boot testing, no QEMU run, and no binrecon comparison of a rebuilt artifact
against the reference. Verification of the fix passes is a guest compile check
only (§4.2).

### 1.3 Retiring the prior run

`tools/binrecon/out/eisabus/` holds a run whose `run-summary.json` reports
`exact-image` acceptance passed. It is not evidence.
`EISABus.rebuilt-baseline/EISABus_reloc` is byte-identical to the reference
`EISABus_reloc` (both `8f252af66cd49a8e03b51e57e90cb613d0b9dc1602263f4b7b6393e483977b23`),
so the run compared the reference against a copy of itself. Its ledger also
points at `\\10.10.1.20\Tech\...\src\drivers\x86\bus\drvEISABus\`, a network
share and a pre-`src/` tree layout.

`drvEISABus` is re-run from scratch under a new profile in Phase 3. The old
output directory is deleted, not reused.

## 2. Findings that shaped this design

These come from scoping and are recorded so the plan can be checked against
them.

### 2.1 binrecon already supports reference-only runs

`binrecon/runner.py` guards every rebuilt-dependent step behind
`rebuilt is not None`, selects `artifact_names = ("reference",)` when there is
no rebuilt artifact, skips comparison, and its summary validator accepts
`rebuilt_sha256: None`. The only obstacles are `schema/profile-v1.json`, which
lists `rebuilt` in `required`, and `profile.py:47`, which loads it
unconditionally.

Satisfying the schema by pointing `rebuilt` at the reference is what produced
the false pass in §1.3 and is prohibited by this design.

### 2.2 Generated output is committed to Git

`tools/binrecon/out/` is not covered by `.gitignore`, contrary to the README's
guarantee that generated evidence stays outside Git. 46 files from the eisabus
run are tracked, including a 1.2 MB IDA `.i64` database and two stale
`.binrecon-run.lock` files.

### 2.3 drvEISABus's PnP BIOS layer differs architecturally

The reference defines a `PnPArgStack` class
(`-[PnPArgStack initWithData:Selector:]`, `-[PnPArgStack pushFarPtr:]`),
`-[PnPBios releaseSegments]`, and a `_call_bios` real-mode thunk with named
register-save globals (`save_es`, `save_eax`, `save_ecx`, `save_edx`,
`save_flag`, `new_eax`, `new_edx`, `save_seg`, `save_addr`, `targ_addr`).

None of these exist anywhere in `src/drivers-i386/bus`. Our
`EISABus.lksproj/bios.c` is an independent rewrite whose own comment describes
it as matching the Linux kernel, using GCC inline `__asm__` in place of the
reference's thunk. For a driver whose purpose is calling 16-bit BIOS code, a
substituted calling convention is a strong crash candidate.

### 2.4 drvPCMCIABus is missing two parsers

`_parseIDTable` and `_parseTable` are defined in the reference and absent from
our source under any name.

### 2.5 Most other residue is build-generated

`+[<Name>BusKernelServerInstance kernelServerInstance]`,
`+[<Name>BusVersion driverKitVersionFor<Name>Bus]`, `_<Name>Bus_VERS_NUM`,
`_<Name>Bus_VERS_STRING`, and `_<Name>Bus_instance` appear in all three
binaries. They are emitted by the Kernel Server project type and `Load_Commands.sect`,
not written by hand, and are expected to be absent from source.

## 3. Artifact layout

### 3.1 Committed

Per driver, a `reconstruction/` directory beside the sources:

```
src/drivers-i386/bus/drvPCIBus/reconstruction/
    source-map.json      # source-map-v1, complete function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings
```

Also committed: one profile per driver at
`tools/binrecon/profiles/{pcibus,pcmciabus,eisabus}.json`, and a per-driver
summary at `docs/drivers/drv<Name>-issues.md` following the format of the
existing `docs/drivers/drvEIDE-issues.md`.

### 3.2 Not committed

Reference binaries (already external to the repo), rebuilt artifacts staged
under `out/i386/`, and all analyzer output under `tools/binrecon/out/`. The
`.i64` databases, `.log` files, and `.lock` files are machine- and
run-specific. The durable, reviewable evidence is the source map, the ledger,
and the divergence document, all of which are text.

Phase 0 adds `tools/binrecon/out/` to `.gitignore` and runs `git rm --cached`
on the 46 files described in §2.2.

## 4. The two passes

### 4.1 Report pass

Runs per driver, needs no VM.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/<driver>.json`
   produces IDA, Ghidra, and angr analyses plus `consensus-reference.json`
   under the gitignored `tools/binrecon/out/<driver>/`.

2. **Map.** Build `source-map.json` anchored on the Mach-O symbol table.
   Symbols give address-to-name directly; name-to-`source_path`/`source_line`
   resolves by locating the `@implementation` method or C function definition.
   Every reference function lands in exactly one bucket:

   - `mapped` — resolved to a file and line.
   - `unmapped` — build-generated glue (§2.5), compiler-emitted statics
     (`_xxx.N`, `_errorstrings.N`, `_protocols.N`), or code genuinely absent
     from our tree (§2.3, §2.4).
   - `boundary_disputed` — analyzers disagree on function extent.
   - `duplicate_candidates` — a name resolves to two or more plausible sites.

3. **Diff.** Decompile every `mapped` function and compare against our source,
   batched by source file. The comparison covers control-flow shape, literal
   constants, I/O port addresses, struct field offsets, and call targets.

4. **Report.** Write `divergences.md` with the reference decompilation beside
   our source for each finding, and assign each function a `ledger-v1` status.
   The ledger records parity confidence, not a repair queue; its vocabulary is
   `unexamined`, `signature-confirmed`, `control-flow-confirmed`,
   `assembly-matched`, and `intentional-mismatch`. A function that matches gets
   the strongest status the evidence supports. A function that diverges stays
   `unexamined` and gets an entry in `divergences.md`; the fix-or-accept
   decision is made there, and the ledger is updated to reflect the outcome.
   `rebuilt_sha256` is `null` throughout, which `ledger-v1` permits.

**Done when** `load_source_map(path, reference_analysis=..., repo_root=...)`
passes — it enforces the complete function partition, names, full function
sizes, and source-line bounds — every `unmapped` entry has a stated reason
class in `divergences.md`, and no function remains without a ledger entry.

### 4.2 Fix pass

Runs per driver, after that driver's report pass is committed, as a separate
phase with its own commits.

**Disposition.** Every finding in `divergences.md` is resolved one of two ways.
Either the source is changed to match the reference, after which the function's
ledger status advances to the level the new evidence supports, or the divergence
is accepted and the ledger status becomes `intentional-mismatch` with a reason
and a reviewer — the ledger CLI requires both. Accepted by default:
build-generated glue, compiler-emitted statics, and anything whose reference
form depends on Apple's toolchain rather than on our source.

**Discipline.** Fixes touch only code the ledger flags. No adjacent cleanup, no
refactoring of code that is not divergent.

**Verification.** A new `vm/build-i386-bus-drivers.sh`, modeled on
`vm/build-i386-kernel-eide.sh`, runs `gnumake clean` then
`gnumake DSTROOT=/tmp/<name>-dst install` per driver and stages the resulting
`<Name>.config` to `out/i386/<driver>/`. All three drivers use the same
Aggregate → `.drvproj` → `.lksproj` structure as drvEIDE, so one script covers
them.

Compile-clean means the build exits 0 and produces `<Name>_reloc`. Warnings are
captured to a log and reviewed, but do not gate. The rebuilt `_reloc` is staged
but is not fed to binrecon.

**Baseline first.** Each driver is built before any source edits, so a
pre-existing failure cannot be misattributed to our changes. `drvPCMCIABus` is
marked "needs compiled and then tested" and may never have been built. If the
baseline build fails, repairing that breakage is an explicit, separately
committed step ahead of the divergence fixes.

## 5. Failure modes

**Analyzer disagreement is preserved, not resolved by majority.** IDA and Ghidra
function discovery are claims, not truth. Conflicting boundaries go to
`boundary_disputed` for human resolution.

**Ghidra rejecting legacy Mach-O input** falls back to deterministic raw i386
import using parsed sections. Java 21 and Ghidra 12.1 remain mandatory.

**angr `CFGFast` misses on indirect control flow** are recorded as CFG errors.
They are never read as "function absent."

**A failed or timed-out run** yields `complete: false` and cannot report passing
acceptance. The runner already refuses to accept leftover output from an earlier
run as evidence.

**An ambiguous symbol** resolving to two plausible source sites goes to
`duplicate_candidates` rather than being guessed.

**`BINRECON_REFERENCE` is per-shell-session.** The implementation plan records
the exact value for each driver.

**The Rhapsody guest may be unavailable.** All three report passes still deliver
in full; only the fix passes block.

## 6. Sequencing

Ascending size order. `drvPCIBus` is the cheapest driver and the one the README
already marks complete, so it calibrates the profile, the source-map
conventions, and the residue policy for about 15% of the total effort before
those conventions reach the harder drivers.

**Phase 0 — tooling.** Create `.venv-binrecon` on Python 3.12 with the pinned
dependencies. Add `tools/binrecon/out/` to `.gitignore` and `git rm --cached`
the tracked output. Make `rebuilt` optional in `profile-v1.json` and in
`profile.py`. Write the three profiles.

*Verify:* `pytest tools/binrecon/tests -q` still passes, and
`binrecon validate --profile tools/binrecon/profiles/pcibus.json` prints the
reference identity with no rebuilt artifact.

**Phase 1 — drvPCIBus** (39 symbols). Report pass, then fix pass.

*Verify:* `source-map.json` validates against the reference analysis; guest
build produces `PCIBus_reloc`.

**Phase 2 — drvPCMCIABus** (97 symbols). Report pass, then fix pass. Expected to
surface `_parseIDTable` and `_parseTable` (§2.4). Baseline build may fail; if so,
repair it as a separate committed step first.

*Verify:* `source-map.json` validates; guest build produces `PCMCIABus_reloc`.

**Phase 3 — drvEISABus** (209 symbols). Report pass, then a go/no-go decision on
the fix pass.

The `drvEISABus` gap is not a set of line edits. Reconstructing `PnPArgStack`
and the `_call_bios` thunk with its register-save globals (§2.3) is closer to
new implementation than to fixing divergences, and it is the change most likely
to resolve the crash. This design deliberately does not commit to absorbing it.
After the report pass measures its true size, the fix pass either proceeds here
or splits into its own spec.

*Verify:* `source-map.json` validates; the go/no-go decision is recorded in
`docs/drivers/drvEISABus-issues.md`.

## 7. Deliverables

Per driver:

- `src/drivers-i386/bus/drv<Name>/reconstruction/source-map.json`
- `src/drivers-i386/bus/drv<Name>/reconstruction/ledger.json`
- `src/drivers-i386/bus/drv<Name>/reconstruction/divergences.md`
- `docs/drivers/drv<Name>-issues.md`
- `tools/binrecon/profiles/<driver>.json`

Repository-wide:

- `tools/binrecon/out/` gitignored and untracked
- Reference-only mode in `profile-v1.json` and `profile.py`
- `vm/build-i386-bus-drivers.sh`
- `src/drivers-i386/README` status lines updated for the three drivers
