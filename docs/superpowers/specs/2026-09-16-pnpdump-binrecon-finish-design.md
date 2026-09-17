# Finish PnPDump under binrecon

Drive the i386 `PnPDump` tool in `drvEISABus` to function-level byte identity
with Apple's shipped `PnPDump`, and drive every **shared** PnP class method
to the same bar on `EISABus_reloc` as well. Guest-compile both Mach-Os on
the Rhapsody box; package once with `rbuild` at close.

This continues
[2026-07-25-bus-driver-binary-reconstruction-design.md](2026-07-25-bus-driver-binary-reconstruction-design.md)
and the committed reloc artifacts under
`src/drivers-i386/bus/drvEISABus/reconstruction/`. Those artifacts cover
`EISABus_reloc` only. This spec does not reopen kernel-only reloc symbols,
Ghidra on the tool, `normalize.py`, `src/kernel-7`, or any other driver.

## Motivation

`PnPDump.tproj` is the remaining `rbuild` blocker for `drvEISABus`. The
kernel server already produces `EISABus_reloc`; the tool fails to compile
because `R.m` is a ~2600-line Ghidra dump with an `unsigned int id` that
collides under `-ObjC` (`illegal cast, missing ')' after 'id'`).
`dumpConfig.m` is a cleaner rewrite of `main` that is not in `MFILES`.
Existing `reconstruction/` ledgers, source-maps, and divergences do not
mention `PnPDump`.

Apple ships the tool next to the reloc at
`EISABus.config/PnPDump`. Done means that binary matches at
function-level `raw_equal` / `masked_equal` (or recorded compiler-shaped
accepts), every method that exists in both Mach-Os meets the same bar on
the reloc, the guest `gnumake` harness produces both artifacts, and
`rbuild buildpackage` of `drvEISABus` either exits 0 or has its failure
recorded as a packaging-gate miss. It does not mean walking Plug and Play
hardware.

## 1. Done bar

A paired **tool** function is done when `raw_equal` or `masked_equal` is
true on a comparison produced from the current guest `PnPDump`, or when
the leftover is recorded in
`src/drivers-i386/bus/drvEISABus/reconstruction/pnpdump/divergences.md`
with the `binrecon function --name` dump and an explicit *accept*
disposition (compiler-shaped: register allocation or instruction
scheduling).

A **shared class method** is done only when that bar holds on **both**
`PnPDump` and `EISABus_reloc`. A one-sided win is reverted. The accept
text, if any, cites both `--name` dumps.

Kernel-only reloc symbols (`EISAKernBus*`, `EISAResourceDriver`,
`PnPBios`, `PnPArgStack`, `bios.c`, `eisa.c`, and any other name that
Apple's `PnPDump` nlist does not define) keep their current
`reconstruction/ledger.json` statuses. This spec does not reopen them.

The campaign is done when:

- every paired PnPDump function meets the tool bar
- every name that appears in both nlists meets the dual bar
- no hand-written tool function remains `unexamined`
- `parity_check.py` `missing_strings` / `missing_symbols` are 0 on both
  pairs (extra unstripped symbols are not findings)
- `rbuild buildpackage` of `drvEISABus` has been attempted once on the
  guest after the last kept rebuild

`cfg_equal` is not a pass signal. `__TEXT,__text` need not match Apple's
byte count. Do not grind envelope size.

Hardware testing stays out. The README line remains that the driver is
not yet retested.

## 2. Current evidence (do not rediscover)

| Property | Value |
|---|---|
| Apple `PnPDump` | `C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump` |
| Size | 59260 bytes |
| Mach-O | i386 `MH_EXECUTE` (`CE FA ED FE`, `cputype` 7, `filetype` 2) |
| SHA-256 | `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772` |
| Apple `EISABus_reloc` | `C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\EISABus_reloc` |
| Reloc SHA-256 | `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23` |
| Reloc size | 100752 bytes (stripped reference) |

`R.m` is listed in `PnPDump.tproj` `MFILES` / `PB.project` `CLASSES` with
`IODeviceMaster.m` and `NXLock.m`. It concatenates Ghidra-shaped stubs of
nine PnP classes (`PnPDependentResources`, `PnPDeviceResources`,
`PnPLogicalDevice`, `PnPResource`, `PnPResources`, `pnpDMA`, `pnpIOPort`,
`pnpIRQ`, `pnpMemory`), userland `IOMalloc` / `IOLog` / callout stubs, and
`main` at line 2491. Those class bodies are **not** the lksproj sources
(they use padding ivars such as `char pad[20]`). This campaign compiles
the lksproj files instead and deletes `R.m`.

Guest `rbuild` of `drvEISABus` already produced `EISABus_reloc` via
`kl_ld`, then failed in `PnPDump` at `R.m:255` / `R.m:470` (`id`).
`dumpConfig.m` is unused. `EISABus.drvproj/Makefile` `TOOLS` lists
`PnPDump.tproj`; `EISABus.drvproj/PB.project` `SUBPROJECTS` lists only
`EISABus.lksproj`.

Reloc reconstruction: 149 mapped, mostly `unexamined` or
`control-flow-confirmed`. That is frozen except for shared-method rows
this campaign actually edits.

Analyzer output lives under `tools/binrecon/out/` (gitignored). There is
no `pnpdump.json` yet. `eisabus.json` has IDA 9.2, Ghidra 12.1, and angr
9.3.0 enabled and no `rebuilt.path`.

## 3. Architecture

Two Mach-Os, one shared class source set, two binrecon profiles.
PnPDump-led: Apple's tool nlist is the layout authority for the split.
IDA 9.2 + angr 9.3.0 (Ghidra off) on that binary decide which of the nine
class files the tool actually contains, whether `IOMalloc` / `IOLog` /
callouts are local, and the `main` shape.

**Phase 0 — harness.** Add `vm/build-i386-bus-recon.sh` modelled on
`vm/build-i386-video-recon.sh`: POSIX Bourne, no `local`, no bashisms, CR
stripped from Makefiles, `gnumake RC_ARCHS=i386 INCLUDED_ARCHS=i386`.
Build `EISABus.drvproj` (the Driver project whose `TOOLS` are the kernel
server **and** `PnPDump.tproj`). Do not `cd` into the lksproj and stop
there; that skips the tool. Gate on presence of both staged binaries, not
on `gnumake`'s exit code. Stage under
`/build/out/i386/drvEISABus/EISABus.config/`. Sync only
`drivers-i386/bus/drvEISABus`. Never `sync-src.ps1 -All`. Do not remove
the driver from `src/rbuild-1/kernel-drivers-blacklist.json`.

**Phase 1 — nlist, split, first dual rebuild.** Analyze Apple's `PnPDump`.
Write `PnPDump.m` from `R.m`'s `main`. Point `MFILES` at the nlist-selected
lksproj class `.m` files via `../EISABus.lksproj/`. Keep
`IODeviceMaster.m` / `NXLock.m`. Add `IOStubs.m` only if the nlist defines
those helpers locally. Delete `R.m`. Leave `dumpConfig.m` out of `MFILES`.
Fix the `id` collision as part of deleting `R.m`, not as a rewrite of the
Ghidra class stubs. Guest-build both Mach-Os, copy them back, `parity_check.py`
each pair, IDA-analyze both rebuilt files, write
`reconstruction/pnpdump/function-worklist.md`.

**Phase 2 — cheapest-first dual match.** Shared methods: one experiment in
the shared `.m`, one guest rebuild, `--name` on **both** profiles. Keep
the edit only if both sides move toward identity, or record one
compiler-shaped accept that applies to both. Tool-only functions (`main`,
MIG wrappers, stubs) match against PnPDump alone. Previously matched
functions are a regression gate.

The same `.m` compiled into a kernel server (`-DDRIVER_PRIVATE`, kernel
headers) and a userland tool (`-Wno-format`, libDriver / libc) is an
expected source of compiler-shaped leftovers. That is not a reason to
copy the class files. Do not invent `-D` flags to chase identity.

**Phase 3 — close.** Refresh both ledgers. Run `rbuild buildpackage --arch
i386 --dir src/drivers-i386/bus/drvEISABus /build/repo /build/built` once.
Update `src/drivers-i386/README` (still not hardware-tested).

`binrecon function` uses the existing name-paired `masked_equal` path in
`tools/binrecon/binrecon/compare.py`. No comparator changes. Do not
enable Ghidra on the tool profile. Do not change whether Ghidra is on in
`eisabus.json`. Do not re-run `binrecon analyze` on a reference unless
published output is missing or the SHA differs.

## 4. Components

| Piece | Job |
|---|---|
| `PnPDump.tproj/PnPDump.m` | New. `main` and tool-only helpers extracted from `R.m`. Instruction-shape target for the tool entry path. |
| `IODeviceMaster.m` / `NXLock.m` | Stay. Edited only if Apple's nlist still defines those symbols here. |
| `PnPDump.tproj/IOStubs.m` | Created only after the nlist shows local `IOMalloc` / `IOLog` / callouts. Otherwise those come from libDriver / libc and this file does not exist. |
| Nine lksproj class `.m` files | Shared compile inputs, nlist-confirmed: `PnPDependentResources.m`, `PnPDeviceResources.m`, `PnPLogicalDevice.m`, `PnPResource.m`, `PnPResources.m`, `pnpDMA.m`, `pnpIOPort.m`, `pnpIRQ.m`, `pnpMemory.m`. Dual-target instruction edits live here. Matching headers only if a typed rewrite is required. No ivar / `instance_size` changes unless Apple's class records force it, and then both binaries are re-compared. |
| `PnPDump.tproj` `Makefile` / `PB.project` | `MFILES` / `CLASSES` become the shared class files plus PnPDump-only TUs. `OTHER_CFLAGS` / `OTHER_INCLUDES` must reach `../EISABus.lksproj` headers. `LIBS` only if the nlist requires libDriver and the symbols are not local. |
| `EISABus.drvproj/PB.project` | Add `PnPDump.tproj` to `SUBPROJECTS` so it matches `Makefile` `TOOLS`. |
| `R.m` | Deleted once `PnPDump.m` exists. |
| `dumpConfig.m` | Reading aid only. Never `MFILES`. |
| Kernel-only lksproj files | Untouched: `EISAKernBus*`, `EISAResourceDriver`, `PnPBios`, `PnPArgStack`, `bios.c`, `eisa.c`. |
| `vm/build-i386-bus-recon.sh` | Guest `gnumake` harness. Stages `EISABus_reloc` and `PnPDump`. |
| `tools/binrecon/profiles/pnpdump.json` | New. IDA 9.2 + angr, Ghidra off. `output_dir` `../out/pnpdump`. `rebuilt.path` `${BINRECON_REBUILT}`. |
| `tools/binrecon/profiles/eisabus.json` | Keep analyzers as they are. Add `rebuilt.path` `${BINRECON_REBUILT}` so `--list` can load both sides. |
| `reconstruction/` | Reloc ledger, source-map, divergences. Shared-method status updates only. |
| `reconstruction/pnpdump/` | New tool ledger, source-map, divergences, function-worklist. |
| `src/drivers-i386/README` | Close-out line; still not hardware-tested. |

**Do not touch:** `Default.table`, `Load_Commands.sect`, `dpkg/`,
`src/kernel-7`, sibling drivers, `compare.py`, `normalize.py`,
`driverTools`, `kernel-drivers-blacklist.json`.

If Apple's `PnPDump` nlist does not contain one of the nine classes, that
file is not a shared compile input and is not a dual-target. If it defines
a class this spec called kernel-only, stop and amend the spec before
sharing more files.

## 5. Data flow

Paths (worktree root = `<repo>`):

**Tool**

- `BINRECON_REFERENCE` =
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump`
- `BINRECON_REBUILT` =
  `<repo>\out\i386\drvEISABus\EISABus.config\PnPDump`

**Reloc** (separate shell; same env var names, different values)

- `BINRECON_REFERENCE` =
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\EISABus_reloc`
- `BINRECON_REBUILT` =
  `<repo>\out\i386\drvEISABus\EISABus.config\EISABus_reloc`

Guest source: `/build/source/src/drivers-i386/bus/drvEISABus/`
Guest stage: `/build/out/i386/drvEISABus/EISABus.config/`

`sync-src.ps1` does not upload `vm/`. Copy the harness with the OpenSSH
path in `vm/SSH CONNECTION.md` (not PuTTY `pscp`), CR-strip it on the
guest, then invoke it. Python on the host is
`./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.

Set `BINRECON_*` per profile invocation. Never point the tool profile at
the reloc or the reverse. Wrong SHA → stop.

This session runs every guest rebuild, including per-experiment ones.

### 5.1 Phase 0 (once)

1. Write `vm/build-i386-bus-recon.sh`.
2. Copy it to the guest.
3. `powershell -File vm/sync-src.ps1 -Path drivers-i386/bus/drvEISABus`.
4. `sh /build/source/vm/build-i386-bus-recon.sh`. Before the split, a
   missing `PnPDump` because `R.m` failed to compile is the baseline, not
   a pass. `EISABus_reloc` may already exist; record that. After the
   split, both artifacts must stage.

### 5.2 Phase 1 (once after the split)

1. `binrecon validate` / `analyze` Apple's `PnPDump` with `pnpdump.json`.
   Gate: SHA `006DC6BB…`, `complete: true`. Record the nlist, class list,
   and whether stubs are local.
2. Reuse published `eisabus` reference analysis if `complete: true` and
   SHA `8F252AF6…`. Otherwise re-analyze the reloc reference only.
3. Split and wire as in §3 / §4. No instruction-shape edits yet.
4. Sync, rebuild, copy both Mach-Os back via the binary-safe `tar` path
   (not a PowerShell 5 pipe).
5. `parity_check.py` on each pair.
6. IDA-analyze both rebuilt files. `--list` both profiles.
7. Write `reconstruction/pnpdump/function-worklist.md` with both rebuilt
   SHA-256s, remaining counts, the shared-name set, and whether the
   cheapest rows are source-shaped or already compiler-shaped.

`normalized-functions=FAIL` is expected until the campaign closes. A
reference-only analyze may exit 1; the gate is `complete: true`.

### 5.3 Phase 2 (each experiment)

1. Edit one site in a shared class `.m`, or in a PnPDump-only TU for
   tool-only functions.
2. Sync only this driver. Rebuild. Copy both Mach-Os back.
3. `parity_check.py` must still be clean on both pairs.
4. Fresh IDA analyze of each **rebuilt** binary (not the references).
5. `--name` on the campaign target in the relevant profile(s). Shared
   methods require both. `--list` to watch the regression set.
6. Dual match → keep, advance both ledgers, next cheapest. Tool-only
   match → keep, advance the PnPDump ledger. Miss without regression →
   revert, mark tried. Regression of a closed function or a one-sided
   shared-method win → revert, record, continue.
7. Record the outcome in the appropriate `divergences.md` before the next
   edit.

Closed functions do not reopen to improve them. A later edit that only
changes gcc scheduling on a closed function is a regression and is
reverted.

### 5.4 Allowed and forbidden shape edits

Source-shape only. Written into the PnPDump worklist after Phase 1,
before the first shape rebuild. One item per rebuild.

Allowed: statement order, local vs expression, signedness of *locals*,
loop shape, `if` vs `else if` chains, operand-reversed `cmp`, declaration
order of existing locals.

Forbidden: padding ivars "to match Ghidra"; copying `R.m`'s `pad[20]`
stubs into lksproj files; putting `dumpConfig.m` in `MFILES`; inventing
temporaries whose only purpose is to pick a register after the list is
already empty; repeating a reverted experiment; chasing `__text` envelope
size; editing kernel-only files to make the tool link.

### 5.5 Phase 3 (once)

1. Refresh `reconstruction/pnpdump/function-worklist.md` and both ledgers.
2. `rbuild buildpackage --arch i386 --dir
   src/drivers-i386/bus/drvEISABus /build/repo /build/built`.
3. README line names both binaries and the new counts; still not
   retested on hardware.

## 6. Error handling

| Failure | Response |
|---|---|
| Apple `PnPDump` SHA is not `006DC6BB…` | Stop. Wrong binary. |
| Apple `EISABus_reloc` SHA is not `8F252AF6…` | Stop. Wrong binary. |
| Guest unreachable or SSH crypto fails | Stop. Do not invent instruction-stream results. |
| Copied file is not a Mach-O | Re-copy via `tar`. Do not pipe binaries through PowerShell 5. |
| nlist drops one of the nine classes | That file is not shared. Do not dual-target it. |
| nlist adds a class this spec called kernel-only | Stop. Amend the spec before sharing more files. |
| Phase 1 build still fails after deleting `R.m` | Fix only what the log names (includes, `LIBS`, `id`). Do not start function-shape edits. |
| Later rebuild fails | Revert the last experiment (or fix a typo it introduced). Do not advance either ledger. |
| `parity_check.py` `missing_strings` / `missing_symbols` non-zero | Revert. Not a shape win. |
| Shared-method edit matches one binary and regresses the other | Revert. Record both `--name` dumps. |
| Cheapest remaining row is compiler-shaped on both (or on the tool only, for tool-only functions) | Accept with dumps. Do not invent temporaries or chase register allocation. |
| IDA analyze / normalize fails | Report the artifact, analyzer, and instruction. Do not disable IDA, enable Ghidra on `pnpdump.json`, or hand-edit published JSON. |
| A compile appears to require a kernel-only file edit | Stop. Out of spec. |
| New unpaired functions after a rebuild | Layout or linkage finding. Stop grinding shape; diagnose names/bindings. |
| `__text` size disagrees after all accepts | Expected. Record sizes. Not a failure. |
| Close `rbuild` fails on `drivertools` / APK extract | Record the failing line and the two staged Mach-Os. Reconstruction may still close; do not call packaging done. |
| Another agent commits | Re-check `--list` against the current rebuilt SHAs before claiming a function closed. |
| Stale `tools/binrecon/out/pnpdump/` or `out/eisabus/` | Never treat an older run as evidence for a new rebuilt file. |

Linkage claims, when needed, are the rebuilt nlist via
`binrecon.macho.read_macho`, never IDA's `binding` field and never
`parity_check.py` name counts alone.

Do not invent instruction diffs. Every source-shape edit comes from
`binrecon function --name` of a named function. If the dump is not in
hand, stop.

## 7. Testing

There is no unit-test framework for this tool. Verification is the guest
Mach-Os plus host binrecon. No QEMU, no boot, no PnP hardware.
`compare.py` is not edited.

If something under `tools/binrecon` is touched despite §3, existing
`tools/binrecon/tests` must stay green
(`./.venv-binrecon/Scripts/python.exe`, `PYTHONPATH=tools/binrecon`).
This campaign does not plan that.

**Phase 0.** Harness `sh -n` is clean. After the split, the guest build
stages both `EISABus_reloc` and `PnPDump`.

**Phase 1.** `binrecon validate` prints the tool identity `006DC6BB…`.
`--list` produces a ranked PnPDump worklist. Shared names are listed
explicitly. Both rebuilt SHA-256s are in `function-worklist.md`.

**Each experiment.** Same parity gate on both pairs. Shared `--name` on
both profiles against the new published rebuilt analyses. Previously
identical rows stay identical. Claimed dual win → both ledgers
`assembly-matched`. Accept → both `--name` dumps in divergences plus
`intentional-mismatch` with reason and reviewer.

**Campaign close.** PnPDump `--list`: every hand-written row is identical,
`masked_equal`, or accepted. Shared reloc methods that exist in both
nlists meet the same bar. Kernel-only reloc statuses are unchanged except
a note that they were not reopened. `rebuilt_sha256` in each ledger is
the last kept artifact. README names the new counts and still says not
retested. Do not write `complete` on the driver. `rbuild` attempted once
per §5.5.

## 8. Excluded

- QEMU, boot, and Plug and Play hardware testing
- Whole-reloc `raw_equal` for kernel-only symbols
- Copying lksproj class files into `PnPDump.tproj`
- Compiling `dumpConfig.m`
- Keeping `R.m` after `PnPDump.m` exists
- Turning Ghidra on for `pnpdump.json`, or off for `eisabus.json`
- `compare.py`, `normalize.py`, `src/kernel-7`, `driverTools`
- Removing `drvEISABus` from `kernel-drivers-blacklist.json`
- Syncing all of `src/` to the shared guest
- `rbuild` of `Intel824X0PCI` or `drvPCIBus` (already measured elsewhere)
- Repeating the reloc campaign's PnP BIOS / GDT / `bios.c` work

## 9. Commit conventions

Driver and reconstruction commits: `drvEISABus: `, one to two lines,
behaviour not file lists. Harness and README: `drivers-i386: `. Profile:
`binrecon: `. Spec: `docs: `. No metadata, no trailers, no
`Co-Authored-By`. Stage by explicit path. Never `git add -A`. Never
commit reference binaries, rebuilt `PnPDump` / `_reloc` files, or
`tools/binrecon/out/`.
