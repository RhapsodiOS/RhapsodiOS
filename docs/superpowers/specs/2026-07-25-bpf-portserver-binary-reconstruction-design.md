# Binary reconstruction of drvBPF and drvPortServer

Reconstruct `drvBPF` and `drvPortServer` against Apple's shipped i386 driver
binaries, using the `tools/binrecon` toolchain. Each driver gets a report pass
that maps every reference function to our source and records the divergences,
followed by a separate fix pass.

## Motivation

Neither driver appears in `src/drivers-i386/README`, and neither lives under
`src/drivers-i386/` — both sit at the top of `src/` as `src/drvBPF` and
`src/drvPortServer`. Neither has been built or checked against the binaries
Apple shipped.

Scoping already found that `src/drvPortServer/.../PortServer.m` contains two
literal NUL bytes where `'\0'` was intended (§2.2), which means the driver
cannot compile as committed. It also found that our `bpf.c` is a later vintage
of Apple's own source than the shipped binary, differing structurally rather
than in details (§2.1).

## 1. Scope

### 1.1 Targets

The reconstruction targets the `_reloc` preload executables under
`C:\Users\raynorpat\Downloads\test\Drivers\i386`. Counts are symbols attributed
to `__TEXT,__text`, undefined imports excluded.

| Driver | Reference binary | Type | Size | SHA-256 | Functions |
| --- | --- | --- | --- | --- | --- |
| drvBPF | `BPF.config/BPF_reloc` | MH_PRELOAD i386 | 32020 | `56DF84EDC7D77C0799A036C21BE43D833A926BCAA6DA48512DF99CEE7A1B86DB` | 30 |
| drvPortServer | `PortServer.config/PortServer_reloc` | MH_PRELOAD i386 | 69112 | `D724803154872B1D8199BE0426EAC4FDBE499C56FB81CCF07D5706916FF9B949` | 113 |

143 functions in total. Both binaries retain full symbol tables, so
address-to-name resolution is exact rather than inferred.

The source under reconstruction:

| Reference class or module | Functions | Our source |
| --- | --- | --- |
| `BPF` | 3 | `src/drvBPF/BPF.drvproj/BPF.lksproj/BPF.m` |
| BPF C layer | 21 | `.../BPF.lksproj/bpf.c` |
| BPF filter | 4 | `.../BPF.lksproj/bpf_filter.c` |
| drvBPF glue | 2 | none, by design (§1.3) |
| `AppleIOPSSafeCondLock` | 21 | `src/drvPortServer/PortServer.drvproj/PortServer.lksproj/AppleIOPSSafeCondLock.m` |
| `IOPortSession` (+`Private`) | 23 | `.../PortServer.lksproj/IOPortSession.m` |
| `PDPseudo` | 15 | `.../PortServer.lksproj/PDPseudo.m` |
| `PortServer` | 12 | `.../PortServer.lksproj/PortServer.m` |
| `IOPortSession(IOPortSessionKern)` | 14 | `.../PortServer.lksproj/IOPortSessionKern.m` |
| `ttyiops` C layer | 25 | `.../PortServer.lksproj/ttyiops.m` |
| drvPortServer glue | 2 | none, by design (§1.3) |
| libgcc `__divdi3` | 1 | none, by design (§1.3) |

The `PortServer` row counts the three `_portServer*` C entry points alongside
the nine class and instance methods. The `AppleIOPSSafeCondLock` row counts the
eight `_AIOPSSCL_*` C wrappers alongside its thirteen methods.

### 1.2 Out of scope

**The DYLDLINK bundles.** `BPF.config/BPF` (16672 bytes) and
`PortServer.config/PortServer` (16688 bytes) are MH_BUNDLE images with eight
symbols each: `__mh_bundle_header`, `dyld_stub_binding_helper`,
`__dyld_func_lookup`, `_<Name>_VERS_STRING`, `_<Name>_VERS_NUM`,
`dyld__mh_bundle_header`, `dyld_lazy_symbol_binding_entry_point`, and
`dyld_func_lookup_pointer`. Neither contains an inspector class or any
hand-written code. There is nothing to reconstruct.

**The user-space programs.** `BPF.config/PostLoad` (37292 bytes) and
`PortServer.config/pdservd` (37840 bytes) are MH_EXECUTE — Mach-O file type 2,
which `binrecon/macho.py` rejects with `unsupported Mach-O file type 2;
expected MH_OBJECT, MH_PRELOAD or MH_BUNDLE`. Covering them means teaching the
reader MH_EXECUTE, in the shape of commit `e4bd1501` which added MH_BUNDLE, and
then deciding how to treat the crt and libc residue in a statically linked 1999
executable. That is a separate spec. `src/drvBPF/.../PostLoad.tproj/PostLoad.m`
and `src/drvPortServer/pdservd.tproj/` are not touched by this work.

**Build and boot verification.** No guest build, no QEMU boot, and no binrecon
comparison of a rebuilt artifact against the reference. Every run is
reference-only, with `rebuilt_sha256` null throughout. §4.2 states what
verification the fix pass does have.

**Relocating the sources.** `src/drvBPF` and `src/drvPortServer` stay where they
are. Moving them under `src/drivers-i386/` is unrelated to reconstruction.

### 1.3 Expected residue

These are `unmapped` by design and are not defects:

- `+[BPFKernelServerInstance kernelServerInstance]`,
  `+[BPFVersion driverKitVersionForBPF]`, and the PortServer equivalents. Emitted
  by the Kernel Server project type and `Load_Commands.sect`.
- `_BPF_VERS_STRING`, `_BPF_VERS_NUM`, `_BPF_instance`, and the PortServer
  equivalents. Same origin.
- Compiler-emitted statics: `_dst.112` in BPF, `_protocols.102` in PortServer.
- libgcc in PortServer: `__divdi3` and its `___clz_tab` table.

## 2. Findings that shaped this design

These come from scoping and are recorded so the plan can be checked against
them. They seed `divergences.md`; the report pass confirms and extends them.

### 2.1 Our bpf.c is a later vintage than the shipped binary

`src/drvBPF/BPF.drvproj/BPF.lksproj/bpf.c` is authentic K&R-style Apple and BSD
source, but its header reads `Copyright (c) 1998-2000` where the rest of the
driver reads 1999. It defines `bpf_timeout`, `bpf_sleep`, `bpf_wakeup`,
`bpfselect`, and `bpf_alloc`. None of the five exists in `BPF_reloc`, which
instead imports `_tsleep`, `_wakeup`, `_selrecord`, and `_selwakeup` directly.
Static functions are not the explanation: `_reset_d` and `_catchpacket` are
static in our source and both carry symbols in the reference.

This is a structural difference, not a set of line edits, and it is the largest
single item in drvBPF.

**Decision: align to the 1999 binary.** The fix pass reshapes `bpf.c` to the
shipped structure — the sleep, wakeup, and timeout wrappers are removed and the
callers call `tsleep`, `wakeup`, `selrecord`, and `selwakeup` directly, and
`bpf_alloc` and `bpfselect` go away. Keeping the newer official source and
recording the delta as `intentional-mismatch` was considered and rejected: the
point of the exercise is a source tree that corresponds to the binary Apple
shipped.

`src/kernel-7/bsd/net/bpf.c` is a 180-line stub and is not a source for this
work.

### 2.2 PortServer.m does not compile

`src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.m` contains
two literal NUL bytes, at file offsets 5972 and 6685, where `'\0'` was intended.
The first reads:

```
if (device_name == NULL || *device_name == '<NUL>') {
```

`file(1)` classifies the source as `data` and `grep` treats it as binary. This
predates the reconstruction and blocks any build of the driver. It is repaired
as its own commit ahead of the divergence fixes, not folded into them.

### 2.3 AppleIOPSSafeCondLock has duplicate IMP caches

The reference defines exactly eight IMP globals: `_IMP_interuptable`,
`_IMP_condition`, `_IMP_setCondition`, `_IMP_unlock`, `_IMP_unlockWith`,
`_IMP_lock`, `_IMP_lockTry`, and `_IMP_lockWhen`, all in `__DATA,__bss`.

Our `AppleIOPSSafeCondLock.m` declares two complete parallel sets: `_IMP_*` at
lines 18–25 and `IMP_*` at lines 529–536. Which set the C wrappers read is a
report-pass question, and the answer determines whether the second set is dead
or whether the two sets split the work.

### 2.4 iopsServerIoctlCommand:data: has the wrong method kind

The reference defines
`+[IOPortSession(IOPortSessionKern) iopsServerIoctlCommand:data:]`, a class
method. Ours is an instance method, declared at `IOPortSessionKern.h:155` and
defined at `IOPortSessionKern.m:776`. The other thirteen
`IOPortSessionKern` entries match the reference's class/instance split.

### 2.5 Two PortServer globals are absent from source

`_dtrDownDelay`, a `__TEXT,__const` constant, and `_ttyiops_devsw`, a
`__DATA,__data` devsw structure, are both defined in `PortServer_reloc` and
appear in no file under `src/drvPortServer`.

### 2.6 Four bodies are unimplemented

Three `TODO` markers sit on unimplemented method bodies in
`AppleIOPSSafeCondLock.m`, one of them `unlockWith:`, and one in `ttyiops.m`.
`AppleIOPSSafeCondLock.m:485` separately annotates a deliberate return-type
deviation from what it calls the original.

### 2.7 Coverage is otherwise strong

All 25 functions in the ttyiops layer resolve to a definition in `ttyiops.m` —
the 23 `_ttyiops_*` entries plus `_tiotors232` and `_rs232totio`. Every
`IOPortSession` and
`IOPortSessionKern` method except §2.4 resolves. `bpf_filter.c` defines exactly
the four functions the reference has: `m_xword`, `m_xhalf`, `bpf_filter`, and
`bpf_validate`. The bulk of the work is instruction-level comparison, not
locating missing code.

## 3. Artifact layout

### 3.1 Committed

Per driver, a `reconstruction/` directory beside the sources, matching the
layout `drvPCParallel` and `Intel82365PCMCIA` already use:

```
src/drvBPF/reconstruction/
    source-map.json      # source-map-v1, complete function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings
src/drvPortServer/reconstruction/
    source-map.json
    ledger.json
    divergences.md
```

Also committed: `tools/binrecon/profiles/bpf.json` and
`tools/binrecon/profiles/portserver.json`, and the `src/drivers-i386/README`
status lines described in §6.

### 3.2 Profiles

Both profiles are copied from `pcmciabus.json`, which is the current convention:
all three analyzers enabled — IDA 9.2 at
`C:/Program Files/IDA Professional 9.2/idat.exe`, Ghidra 12.1 at
`D:/ghidra/support/analyzeHeadless.bat`, angr 9.3.0 via
`.venv-binrecon/Scripts/python.exe` — with 900-second timeouts,
`comparison.acceptance` of `normalized-functions`, and `output_dir` of
`../out/bpf` and `../out/portserver`.

Both are reference-only: no `rebuilt` key. `profile-v1.json` and `profile.py`
have permitted this since the bus-driver work, so no toolchain change is needed.
Pointing `rebuilt` at the reference to satisfy a schema is prohibited — it is
what produced the false `exact-image` pass recorded in the bus-driver design.

`BINRECON_REFERENCE` is per shell session:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\BPF.config\BPF_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\PortServer.config\PortServer_reloc
```

### 3.3 Not committed

Reference binaries, which are already external to the repository, and all
analyzer output under `tools/binrecon/out/{bpf,portserver}/`. That directory is
already gitignored at `.gitignore:19`. The `.i64` databases, logs, and lock
files are machine- and run-specific. The durable, reviewable evidence is the
source map, the ledger, and the divergence document, all of which are text.

This is the first reconstruction in the repository that needs no change to
`binrecon` itself.

## 4. The two passes

### 4.1 Report pass

Runs per driver, needs no VM.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/<driver>.json`
   produces IDA, Ghidra, and angr analyses plus `consensus-reference.json` under
   the gitignored `tools/binrecon/out/<driver>/`.

2. **Map.** Build `source-map.json` anchored on the Mach-O symbol table. Symbols
   give address-to-name directly; name-to-`source_path`/`source_line` resolves by
   locating the `@implementation` method or C function definition. Every
   reference function lands in exactly one bucket:

   - `mapped` — resolved to a file and line.
   - `unmapped` — the residue of §1.3, or code genuinely absent from our tree
     (§2.5).
   - `boundary_disputed` — analyzers disagree on function extent.
   - `duplicate_candidates` — a name resolves to two or more plausible sites.
     §2.3 is a candidate for this bucket.

3. **Diff.** Decompile every `mapped` function and compare against our source,
   batched by source file. The comparison covers control-flow shape, literal
   constants, struct field offsets, and call targets. ObjC metadata is read
   directly out of the `__OBJC` sections — `__class`, `__meta_class`,
   `__instance_vars`, `__inst_meth`, `__cls_meth`, `__cat_cls_meth`,
   `__cat_inst_meth`, `__meth_var_types`, `__message_refs`, `__cls_refs`,
   `__class_names`, `__module_info` — not inferred from the decompilation.

4. **Report.** Write `divergences.md` with the reference decompilation beside our
   source for each finding, and assign each function a `ledger-v1` status. The
   ledger records parity confidence, not a repair queue; its vocabulary is
   `unexamined`, `signature-confirmed`, `control-flow-confirmed`,
   `assembly-matched`, and `intentional-mismatch`. A function that matches gets
   the strongest status the evidence supports. A function that diverges stays
   `unexamined` and gets an entry in `divergences.md`; the fix-or-accept decision
   is made there. `rebuilt_sha256` is null throughout, which `ledger-v1` permits.

**Done when** `load_source_map(path, reference_analysis=..., repo_root=...)`
passes — it enforces the complete function partition, names, full function
sizes, and source-line bounds — every `unmapped` entry has a stated reason class
in `divergences.md`, and no function remains without a ledger entry.

### 4.2 Fix pass

Runs per driver, after that driver's report pass is committed, as a separate
phase with its own commits.

**Disposition.** Every finding in `divergences.md` is resolved one of two ways.
Either the source is changed to match the reference, after which the function's
ledger status advances to the level the new evidence supports, or the divergence
is accepted and the ledger status becomes `intentional-mismatch` with a reason
and a reviewer — the ledger CLI requires both. Accepted by default: the residue
of §1.3, and anything whose reference form depends on Apple's toolchain rather
than on our source.

**Discipline.** Fixes touch only code the ledger flags. No adjacent cleanup, no
refactoring of code that is not divergent. The one exception is §2.2, which is a
pre-existing compile blocker repaired in its own commit ahead of the divergence
fixes.

**Verification.** There is no compile gate, because no guest build is in scope
(§1.2). Instead, each fixed function is re-read against the reference
disassembly and its ledger status advanced only to the level that re-read
supports, and `source-map.json` is re-validated against the reference analysis
after the edits. This is the discipline the `drvPCParallel` and
`Intel82365PCMCIA` fix passes used. A function whose repair cannot be confirmed
by re-reading stays `unexamined` with its finding intact.

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

**The `bpf.c` realignment growing past a line-edit job.** §2.1 commits to
reshaping `bpf.c` toward the 1999 binary, but the report pass is what measures
how many of the 21 `bpf.c` functions the delta actually touches. If the realignment
turns out to require restructuring most of the file rather than removing the
five absent functions and rerouting their callers, the drvBPF fix pass records
that measurement in `divergences.md` and the realignment splits into its own
spec. The rest of the drvBPF fix pass — `BPF.m` and `bpf_filter.c` — proceeds
either way.

## 6. Sequencing

Ascending size. `drvBPF` at 30 functions calibrates the profile, the source-map
conventions, and the residue policy for about a fifth of the total effort before
those conventions reach `drvPortServer` at 113. The calibration is imperfect —
drvBPF is mostly C where drvPortServer is mostly Objective-C with an IMP-cache
idiom — so the residue policy is the part expected to transfer, not the diffing
technique.

**Phase 0 — profiles.** Write `tools/binrecon/profiles/bpf.json` and
`portserver.json`.

*Verify:* `binrecon validate --profile tools/binrecon/profiles/bpf.json` and the
same for `portserver.json` each print the reference identity from §1.1 with no
rebuilt artifact, and `pytest tools/binrecon/tests -q` still passes.

**Phase 1 — drvBPF report pass** (30 functions).

*Verify:* `load_source_map` passes against the reference analysis; every
`unmapped` entry has a stated reason; every function has a ledger entry.

**Phase 2 — drvBPF fix pass.** Includes the §2.1 realignment, subject to the
go/no-go in §5.

*Verify:* every finding in `divergences.md` is either repaired with an advanced
ledger status or marked `intentional-mismatch` with reason and reviewer;
`source-map.json` re-validates.

**Phase 3 — drvPortServer report pass** (113 functions). Expected to surface
§2.3 through §2.6 in detail.

*Verify:* same as Phase 1.

**Phase 4 — drvPortServer fix pass.** The §2.2 NUL-byte repair lands first, in
its own commit.

*Verify:* same as Phase 2, plus `file(1)` no longer reports `PortServer.m` as
`data`.

**Phase 5 — README.** Add a section to `src/drivers-i386/README` for the two
top-level `src/drv*` drivers, with a status line for each reflecting the
outcome of Phases 2 and 4.

*Verify:* both drivers appear with a status line consistent with their ledgers.

## 7. Deliverables

Per driver:

- `src/drv<Name>/reconstruction/source-map.json`
- `src/drv<Name>/reconstruction/ledger.json`
- `src/drv<Name>/reconstruction/divergences.md`
- `tools/binrecon/profiles/<driver>.json`

Repository-wide:

- `src/drivers-i386/README` gains status lines for `drvBPF` and `drvPortServer`
- `PortServer.m` compiles as text again (§2.2)
