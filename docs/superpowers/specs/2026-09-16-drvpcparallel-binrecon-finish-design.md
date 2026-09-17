# Finish drvPCParallel under binrecon

Drive `drvPCParallel` to function-level instruction-stream identity with
Apple's shipped `ParallelPort_reloc`, then reconstruct `RemovePPDev` and
`InstallPPDev` against the executables in the same `ParallelPort.config`.
Raise the done bar from Task 10's control-flow and section parity to
`raw_equal` / `masked_equal`. Guest-build all three artifacts on the
Rhapsody box.

This continues
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/input/drvPCParallel/reconstruction/`. Task 10's layout,
strings, `cdevsw`, Loaded Server, and named findings stay except where this
spec explicitly reopens them. This spec does not reopen Ghidra,
`normalize.py`, `src/kernel-7`, or any other driver.

## Motivation

The July report and fix passes closed every named divergence that Task 10
was allowed to close. `IOParallelPort` is an `IODirectDevice`, the 27 ivars
land at Apple's offsets, `__cstring` matches, `__inst_meth` is 752 bytes,
and `src/drivers-i386/README` already says the driver "compiles;
reconstructed against the reference binary, fixes applied, not yet tested."

What remains:

- Instruction shape. Eighteen of seventy-three mapped functions are
  `control-flow-confirmed` because Task 10 never compared the rebuilt
  instruction stream. `ledger.json` `rebuilt_sha256` is still `null`.
- Three Task 10 accepts that this campaign reopens: Finding 53
  (`initDevice` / `probeForController` control byte from uninitialized
  stack) and `_strobeChar`'s count-before-device order.
- `_ParallelPort_VERS_STRING` / `_ParallelPort_VERS_NUM` are absent. Task 10
  recorded that as a guest-tooling gap. A local `OTHER_GENERATED_OFILES +=
  $(VERS_OFILE)` is enough; Cirrus and PS/2 Mouse already showed it.
- `InstallPPDev` and `RemovePPDev` were dropped from `TOOLS` because they
  need i386 crt and libDriver the PPC cross-host did not provide. They were
  never function-compared. Apple ships both next to the reloc
  (`InstallPPDev` 37364 bytes, `RemovePPDev` 17272 bytes). This campaign
  restores them and reconstructs their bodies.
- `vm/build-i386-input-recon.sh` is not in this worktree.

Done means every paired reloc function matches or is accepted as
compiler-shaped, both tools meet the same bar, the three artifacts compile
on the Rhapsody guest, and the README line names the new counts. It does
not mean QEMU talks to a printer.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current guest artifact, or when the leftover
is recorded in
`src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md` with
the `binrecon function --name` dump and an explicit *accept* disposition
(compiler-shaped: register allocation or instruction scheduling).

The **reloc** is done when every paired hand-written function meets that
bar, unpaired leftovers are only
`+[ParallelPortKernelServerInstance kernelServerInstance]` and
`+[ParallelPortVersion driverKitVersionForParallelPort]`,
`__TEXT,__const` contains `_ParallelPort_VERS_STRING` and
`_ParallelPort_VERS_NUM`, `parity_check.py` `missing_strings` /
`missing_symbols` stay 0, and `ledger.json` `rebuilt_sha256` is the last
kept `_reloc`.

The **tools** are done when every paired function in `RemovePPDev` and in
`InstallPPDev` meets that bar. LibDriver / libc imports stay unpaired.
`IODeviceMaster` methods are unpaired if they come from `-lDriver`; they
are paired if Phase 3 keeps a local translation unit because the reference
nlist defines them.

The **campaign** is done when the reloc is done, both tools are done, and
the README line is updated. `physbuf` / `setPhysbuf:` `__meth_var_types`
encoding (`^vi[3l]` vs Apple's `^vllll`) is noted in `divergences.md` and
**does not count against close**. Do not edit `src/kernel-7/bsd/sys/buf.h`.

`cfg_equal` is not a pass signal. Status may stay `different` because of
`cfg differs` or `instruction layout differs`. The flags that count are
`raw_equal` and `masked_equal`.

Hardware testing stays out. The README line remains that the driver is not
yet tested on a printer.

The fifty Task 10 `assembly-matched` functions are a regression gate, not a
rewrite target. Confirm they remain equal after later rebuilds. Do not
rewrite their bodies.

## 2. Current evidence (do not rediscover)

Reference reloc: `ParallelPort_reloc`, 45312 bytes, SHA-256
`D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2`.
`BINRECON_REFERENCE` is
`C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\ParallelPort_reloc`.
The same directory holds `InstallPPDev` (37364) and `RemovePPDev` (17272).
Profile: `tools/binrecon/profiles/parallelport.json` (IDA 9.2 + angr 9.3.0,
Ghidra off). Analyzer output: `tools/binrecon/out/parallelport/`
(gitignored).

Task 10 rebuilt (unstripped) was 165556 bytes, `gnumake` exit 0,
`missing_strings` 0, `missing_symbols` 0. Remeasure on the Phase 1 `_reloc`.

| Property | Reference | Ours after Task 10 |
|---|---|---|
| `__TEXT,__cstring` | 476 (15 strings) | identical set |
| `__OBJC,__class` | 120 | 120 |
| `__OBJC,__inst_meth` | 752 (62 methods) | 752 |
| `__OBJC,__instance_vars` | 328 (27 ivars) | 328, offsets `0x128`–`0x190` |
| `__OBJC,__message_refs` | 256 | 256 |
| `__OBJC,__meth_var_types` | 713 | 715 (`physbuf` encoding) |
| `Loaded Server,Load Commands` | 164 | 164 |
| `Unload Commands` | absent | absent |
| `IOParallelPort instance_size` | 404 | 404 |
| Ledger | — | 50 `assembly-matched`, 18 `control-flow-confirmed`, 7 `intentional-mismatch`, 0 `unexamined` |
| `missing_strings` / `missing_symbols` | — | 0 / 0 |
| `rebuilt_sha256` | — | `null` |

The 18 `control-flow-confirmed` functions are the grind set. Experiment
lists are written after Phase 1 `--list`, not guessed here:

| Function | Addr | Ref size |
|---|---|---|
| `-[IOParallelPort _waitForDevice:isReady:]` | 0 | 112 |
| `-[IOParallelPort initFromDeviceDescription:]` | 456 | 996 |
| `-[IOParallelPort free]` | 1740 | 237 |
| `-[IOParallelPort getIntValues:forParameter:count:]` | 1980 | 163 |
| `-[IOParallelPort setMinPhys:]` | 2900 | 105 |
| `-[IOParallelPort setBlockSize:]` | 3024 | 105 |
| `-[IOParallelPort writeToPort]` | 3212 | 265 |
| `-[IOParallelPort msgTypeToIOReturn:]` | 3492 | 197 |
| `-[IOParallelPort cmdBufAlloc]` | 3780 | 73 |
| `-[IOParallelPort cmdBufExec:]` | 3896 | 143 |
| `-[IOParallelPort waitForCmdBuf]` | 4040 | 141 |
| `_IOParallelPortThread` | 4512 | 728 |
| `_IOParallelPortInterruptHandler` | 5240 | 279 |
| `_ppopen` | 5520 | 132 |
| `_ppread` | 5692 | 134 |
| `_ppwrite` | 5828 | 424 |
| `_ppstrategy` | 6304 | 404 |
| `_ppioctl` | 6708 | 683 |

Reopened Task 10 accepts (grind until `masked_equal` or compiler-shaped):

| Function | Addr | Why it was accepted | What this campaign does |
|---|---|---|---|
| `-[IOParallelPort initDevice]` | 112 | Finding 53: control byte from uninitialized stack | Declare an uninitialized local; `and`/`or` that slot, not the register read-back |
| `-[IOParallelPort probeForController]` | 1452 | Same Finding 53 | Same reconstruction |
| `__strobeChar` | 4232 | Count tested before the device pointer is loaded | Load device + registers first, then test the byte count |

`physbuf` / `setPhysbuf:` (2372, 2388) stay `intentional-mismatch` for the
`struct buf` encoding only. Their instruction streams already matched Task
10. Do not grind them. Do not edit `buf.h`.

`Default.table` already diffs clean ignoring `"Driver Version"`.
`Load_Commands.sect` is 164 bytes. Neither is reopened.

`Default.table` maps `"Pre-Load" = "RemovePPDev"` and
`"Post-Load" = "InstallPPDev"`. The tproj folders are inverted relative to
those names: `PostLoad.tproj` builds `RemovePPDev`, `PreLoad.tproj` builds
`InstallPPDev`. Do not swap them.

`_ParallelPort_VERS_STRING` / `_VERS_NUM` live in the reference
`__TEXT,__const` and are emitted by NeXT `vers_string` machinery. This
campaign adds them locally via `VERS_OFILE`. Do not edit `driverTools` or
`kernelserver.make`. Do not match the 160-byte string (host and timestamp).

The 2180-line `PreLoad.tproj/IODeviceMaster.m` is invented Mach IPC, not
DriverKit. Phase 3 deletes it on the `-lDriver` path, or replaces it with
a driverkit / EISA `PnPDump`-shaped TU if the reference nlist defines
`IODeviceMaster` / `_IOGetCharValues`. It does not survive either way.

## 3. Architecture

This is a reconstruction campaign on one loadable driver package, not a
new subsystem. Three artifacts, in order: `ParallelPort_reloc`, then
`RemovePPDev`, then `InstallPPDev`. Whole-driver cheapest-first on the
reloc: layout is already closed, and name-paired `masked_equal` ignores
relocated immediates and envelope padding.

**Phase 0 — harness.** Recreate `vm/build-i386-input-recon.sh` modelled on
`vm/build-i386-scsi.sh` and `vm/build-i386-video-recon.sh` (POSIX Bourne, no
`set -e` on predicates, CR stripped from Makefiles, `gnumake RC_ARCHS=i386
INCLUDED_ARCHS=i386`, gate on artifact presence). Stage under
`/build/out/i386/drvPCParallel/`. The required arm is `drvPCParallel`. If
the file already exists with another driver's arm, add this arm rather
than deleting theirs. Do not restore a five-driver dispatcher. Do not
remove the driver from `src/rbuild-1/kernel-drivers-blacklist.json`.

Restore `.drvproj/Makefile` `TOOLS` to
`PCParallelPort.lksproj PostLoad.tproj PreLoad.tproj`. `PB.project`
already lists those three.

**Phase 1 — baseline.** This session syncs only this driver, guest-builds,
copies `ParallelPort_reloc`, `InstallPPDev`, and `RemovePPDev` to host
`out/i386/drvPCParallel/ParallelPort.config/`, runs `parity_check.py` on
the reloc, IDA-analyzes the rebuilt reloc, and writes
`reconstruction/function-worklist.md` with both reloc SHA-256s, remaining
counts, and a reachability note. Reuse published reference analysis if
`complete: true` and the SHA is `D188A4D9…`. Record tool file sizes and
Mach-O types; do not open their bodies yet. If the tools fail to link
(missing i386 crt / libDriver), the reloc baseline still proceeds and
Phase 3 waits.

**Phase 2 — reloc grind.** First: Kernel Server `Makefile.postamble` with
`OTHER_GENERATED_OFILES += $(VERS_OFILE)`. Gate: `__TEXT,__const` contains
the two `vers_string` symbols.

Then cheapest-first across both translation units, including the three
reopened rows. One experiment, one guest rebuild, `--name` on the new
published comparison. A shared cause is one edit cluster. Matched
functions are a regression gate. When a function's cheapest leftover is
compiler-shaped, accept it and move on. Do not reorder statements or
invent temporaries to chase gcc 2.x.

Finding 53's accept is reversed: declare an uninitialized local and
`and`/`or` it the way Apple did, so bits 6–7 are leftover stack. If gcc
2.x zero-fills anyway, keep the uninitialized local (that is the
reconstruction) and accept the leftover as compiler-shaped rather than
injecting dummy stack junk. `_strobeChar` loads the device pointer and
registers before testing the byte count; a nil device with leftover count
faults like Apple.

**Phase 3 — tools.** After the reloc meets §1, IDA-analyze reference
`InstallPPDev` / `RemovePPDev`. Decide `InstallPPDev`'s `IODeviceMaster`
from the reference nlist via `binrecon.macho.read_macho` (binding +
section, not IDA `binding`): `-lDriver` unless that nlist defines
`IODeviceMaster` / MIG stubs (`_IOGetCharValues` and friends). Convert
both tproj Makefiles to PB `tool.make`. Reconstruct `RemovePPDev.c` first
(smaller), then `InstallPPDev.m`, to the same `raw_equal` / `masked_equal`
bar.

**Phase 4 — close.** Refresh the worklist, advance the ledgers, update
`divergences.md` and the README line (still not hardware-tested).

`binrecon function` uses the existing name-paired `masked_equal` path in
`tools/binrecon/binrecon/compare.py`. No comparator changes. Do not
re-enable Ghidra. Do not re-run `binrecon analyze` on the reference reloc
unless the committed consensus is missing.

## 4. Components

| Piece | Job |
|---|---|
| `IOParallelPort.m` / `IOParallelPort.h` | Reloc shape edits. Finding 53 lives here. Layout already matches. Touch the header only if a typed rewrite is required for instruction shape. No ivar, protocol, or `instance_size` changes. |
| `IOParallelPortKern.m` / `IOParallelPortKern.h` | Reloc shape edits. `_strobeChar` load-then-test, plus the remaining `control-flow-confirmed` C entry points. |
| Kernel Server `Makefile.postamble` | Created at `PCParallelPort.lksproj/Makefile.postamble`. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. `Makefile` already `-include`s it. |
| `.drvproj/Makefile` `TOOLS` | Restored to `PCParallelPort.lksproj PostLoad.tproj PreLoad.tproj`. |
| `PreLoad.tproj` | `InstallPPDev`. Phase 3 only. Default: drop local `IODeviceMaster.m` / `.h`, `#import <driverkit/IODeviceMaster.h>`, `LIBS = -lDriver`, PB `tool.make`. Alternate: local TU modelled on `src/driverkit-3/libDriver/User/IODeviceMaster.m` / EISA `PnPDump`, only if the reference nlist defines those symbols. |
| `PostLoad.tproj` | `RemovePPDev.c`. Phase 3 only. PB `tool.make`. No libDriver. |
| `vm/build-i386-input-recon.sh` | Guest harness. Stage `ParallelPort_reloc`, `InstallPPDev`, `RemovePPDev` under `/build/out/i386/drvPCParallel/`. |
| `vm/sync-src.ps1 -Path drivers-i386/input/drvPCParallel` | Host → guest. Never `-All`. |
| `tools/binrecon/profiles/parallelport.json` | Reloc profile. Add `"rebuilt": { "path": "${BINRECON_REBUILT}" }`. IDA on; Ghidra stays off. Rebuilt analyze is IDA-only. |
| `tools/binrecon/profiles/installppdev.json` | Phase 3. `output_dir` `../out/installppdev`. Ghidra off until proven. |
| `tools/binrecon/profiles/removeppdev.json` | Phase 3. `output_dir` `../out/removeppdev`. Ghidra off until proven. |
| `reconstruction/function-worklist.md` | New. Baseline after Phase 1; refreshed at reloc close and after each tool. Ranked remaining rows and SHA-256s. |
| `reconstruction/divergences.md` | Finding 53 / `_strobeChar` accepts reversed when those edits land; VERS gap closed; tool findings and exhausted lists live here. `physbuf` encoding stays a noted non-closer. |
| `reconstruction/ledger.json` | Reloc status of record. `assembly-matched` on `masked_equal`; `intentional-mismatch` for accepted compiler leftovers (reason + reviewer required). |
| `reconstruction/installppdev-ledger.json` | Phase 3. Tool status of record. Do not mix with reloc rows. |
| `reconstruction/removeppdev-ledger.json` | Phase 3. Same. |
| `reconstruction/installppdev-source-map.json` | Phase 3. Tool function → file/line. |
| `reconstruction/removeppdev-source-map.json` | Phase 3. Same. |
| `reconstruction/source-map.json` | Reloc. Relined when bodies move. Partition stays 73 mapped / 2 unmapped. |
| `binrecon function` | `--list` is the ranked worklist; `--name` is the instruction dump. Reads published output only. |
| `tools/binrecon/parity_check.py` | Reloc regression gate: `missing_strings` and `missing_symbols` stay 0. Extra unstripped symbols are not findings. |
| `src/drivers-i386/README` | Update the drvPCParallel line to the new bar; keep "not yet tested." |

**Do not touch:** `Default.table`, `Load_Commands.sect`, `src/kernel-7`,
sibling input drivers, `compare.py`, `kernel-drivers-blacklist.json`,
`driverTools`, guest-installed `kernelserver.make`. The `ParallelPort`
MH_BUNDLE beside the reloc is a packaging wrapper and is out of function
comparison.

## 5. Data flow

Paths:

- Reloc reference =
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\ParallelPort.config\ParallelPort_reloc`
- `InstallPPDev` / `RemovePPDev` references live in that same directory
- Reloc rebuilt =
  `D:\RhapsodiOS\out\i386\drvPCParallel\ParallelPort.config\ParallelPort_reloc`
- Tools rebuilt sit beside it
- Guest stage = `/build/out/i386/drvPCParallel/`
- Guest source = `/build/source/src/drivers-i386/input/drvPCParallel/`

`sync-src.ps1` does not upload `vm/`. Copy the harness with the OpenSSH
path in `vm/SSH CONNECTION.md` (not PuTTY `pscp`), CR-strip it on the
guest, then invoke it. Python on the host is
`./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.

This session runs every guest rebuild, including per-experiment ones.

### 5.1 Phase 1 (once)

1. Copy `vm/build-i386-input-recon.sh` to the guest.
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/input/drvPCParallel`.
3. `sh /build/source/vm/build-i386-input-recon.sh drvPCParallel`. Copy
   `ParallelPort_reloc` (and the tools if they linked) back to the host
   path above.
4. Reloc `parity_check.py`: `missing_strings` 0, `missing_symbols` 0.
5. `binrecon validate --profile tools/binrecon/profiles/parallelport.json`.
   IDA `analyze` on the reference if published output is missing or the SHA
   differs; IDA `analyze` on the rebuilt.
6. `binrecon function --list`. Write `function-worklist.md` with both
   reloc SHA-256s, remaining counts, and whether the cheapest rows are
   source-shaped or already compiler-shaped. Record tool sizes.

`normalized-functions=FAIL` is expected until the reloc closes. A
reference-only profile may still exit 1; the gate is `complete: true`.

### 5.2 Phase 2 (each reloc experiment)

1. Edit one site in `IOParallelPort.m` or `IOParallelPortKern.m` (the VERS
   postamble is the one exception: it is a one-shot packaging edit).
2. Sync only this driver. Rebuild. Copy `_reloc` back.
3. `parity_check.py` must still be clean.
4. Fresh IDA analyze of the rebuilt reloc only.
5. `--name` on the campaign target against the new published comparison.
   `--list` to watch the regression set (every previously `masked_equal` /
   `raw_equal` row, including the fifty Task 10 matches).
6. Match → keep the edit, advance that ledger row, next cheapest. Miss
   without regression → revert, mark tried. Regression of a closed
   function → revert, record, continue.
7. Record the outcome in `divergences.md` before the next edit.

Closed functions do not reopen to improve them. A later edit that only
changes gcc scheduling on a closed function is a regression and is
reverted.

### 5.3 Phase 3 (tools, after reloc close)

1. `binrecon.macho.read_macho` on reference `InstallPPDev`. If it does not
   define `IODeviceMaster` / `_IOGetCharValues`, take `-lDriver` and delete
   `PreLoad.tproj/IODeviceMaster.m` and `.h`. If it does, replace that file
   with a driverkit-shaped TU. Do not keep the invented Mach-message copy.
2. Convert both tproj Makefiles to PB `tool.make` (`LIBS = -lDriver` only
   on `InstallPPDev` in the `-lDriver` path).
3. Same edit → sync → rebuild → copy → IDA → `--name` loop.
   `RemovePPDev` first, then `InstallPPDev`.
4. Analyzer output under `tools/binrecon/out/` stays uncommitted.

### 5.4 Allowed and forbidden shape edits

Source-shape only. Written into `function-worklist.md` after Phase 1,
before the first shape rebuild. One item per rebuild.

Allowed: statement order, local vs expression, signedness of *locals*,
loop shape, `if` vs `else if` chains, operand-reversed `cmp`, declaration
order of existing locals, an uninitialized local for Finding 53, restoring
`_strobeChar`'s load-then-test order.

Forbidden: padding ivars; changing `IOParallelPort` instance layout;
renaming ivars or protocols; putting queue state into extra ivars;
inventing temporaries whose only purpose is to pick a register after the
list is already empty; repeating a reverted experiment; chasing `__text`
envelope size; editing `buf.h`; injecting dummy stack values to force
bits 6–7; hand-writing Kernel Server glue; swapping `RemovePPDev` /
`InstallPPDev` across tproj folders.

## 6. Error handling

| Failure | Response |
|---|---|
| Guest unreachable or SSH crypto fails | Stop. Do not invent instruction-stream results. Leave the campaign open. |
| Phase 1 reloc build fails | Unexpected: Task 10 already compiled the Kernel Server. Stop, report the log, fix only what it names. Do not start function edits. |
| Phase 1 tools fail to link (missing i386 crt / libDriver) | Reloc baseline still proceeds. Tools stay open; do not invent `IODeviceMaster`. Record the missing library. Phase 3 does not start until they link. |
| Later reloc rebuild fails | Revert the last experiment (or fix a typo it introduced). Do not advance the ledger. |
| `parity_check.py` `missing_strings` or `missing_symbols` non-zero | Revert. That is a Task 10 regression, not a shape win. Extra unstripped symbols are not findings. |
| IDA analyze / normalize fails | Report the artifact, analyzer, and instruction. Do not re-enable Ghidra or hand-edit published JSON. |
| Cheapest remaining reloc row is compiler-shaped | Accept with the `--name` dump. Do not invent temporaries to pick a register. |
| Finding 53 uninitialized local still yields determinate bits 6–7 | Keep the uninitialized local. If gcc 2.x zero-fills, accept the leftover as compiler-shaped. Do not inject dummy stack junk. |
| `_strobeChar` nil-device path | After the reorder, a nil device with leftover count faults like Apple. That is intended. |
| An edit regresses a previously identical function | Revert before the next experiment. |
| New unpaired functions after a reloc rebuild | Layout or linkage finding. Stop grinding shape; diagnose names/bindings. |
| `VERS_OFILE` missing after the local postamble | Record whether `ParallelPort_vers.c` / `.o` were generated and whether they appear on the `kl_ld` line. Existence stays unmet. Do not edit shared project types. |
| `InstallPPDev` nlist defines `IODeviceMaster` / `_IOGetCharValues` | Take the local-TU path (driverkit / PnPDump), not `-lDriver`. Do not keep the 2180-line invented file either way. |
| `physbuf` `__meth_var_types` still `^vi[3l]` vs `^vllll` | Expected. Not a closer. Do not edit `buf.h`. |
| `__text` envelope stays short of Apple's after all accepts | Expected codegen (guest `cc` vs Apple's March 1998 build). Record sizes. Not a failure. |
| Reference reloc SHA no longer `D188A4D9…` | Stop. Wrong binary. |
| Stale `tools/binrecon/out/parallelport/` | Never treat an older run as evidence for a new `_reloc`. |
| Another agent commits | Re-check `--list` against the current `_reloc` SHA before claiming a function closed. |

Linkage claims, when needed, are the rebuilt nlist via
`binrecon.macho.read_macho`, never IDA's `binding` field and never
`parity_check.py` name counts alone.

The diagnosed reloc edits (VERS line, Finding 53 uninitialized local,
`_strobeChar` reorder) are reconstructions, not experiments: keep them
even if extents do not close.

## 7. Testing

There is no driver unit-test framework. Verification is the guest
artifacts plus host binrecon. No QEMU, no boot, no printer. `compare.py`
is not edited.

If something under `tools/binrecon` is touched despite §3, existing
`tools/binrecon/tests` must stay green
(`./.venv-binrecon/Scripts/python.exe`, `PYTHONPATH=tools/binrecon`). This
campaign does not plan that.

**Phase 1.** Harness `sh -n` is clean. Guest build stages
`ParallelPort_reloc`. `parity_check.py` reports `missing_strings` 0 and
`missing_symbols` 0. `binrecon validate` prints the reloc identity
`D188A4D9…`. `function --list` produces a ranked worklist. Both reloc
SHA-256s are in `function-worklist.md`. `IOParallelPort` `instance_size`
stays 404. Tool binaries are staged, or the missing crt/libDriver is
recorded; their bodies are not yet compared.

**Each reloc experiment.** Same parity gate. `--name` on the campaign
target against the new published rebuilt analysis. Previously identical
rows stay identical. Claimed win → ledger `assembly-matched`. Accept →
`--name` dump in `divergences.md` plus `intentional-mismatch` with reason
and reviewer.

**After `VERS_OFILE`.** `__TEXT,__const` contains `_ParallelPort_VERS_STRING`
and `_ParallelPort_VERS_NUM`. Contents may differ. Hand-written `__text`
identity must not regress.

**After Finding 53 / `_strobeChar` rewrites.** Those three functions are
compared with `--name`. They become `assembly-matched` or recorded
compiler-shaped.

**Reloc close.** `--list`: unpaired only the two glue methods in §1. Every
other hand-written row is identical, `masked_equal`, or accepted
compiler-shaped. `physbuf` encoding is noted and does not block.
`rebuilt_sha256` is the last kept `_reloc`.

**Phase 3.** Reference nlist decides `-lDriver` vs local TU. `RemovePPDev`
then `InstallPPDev` each have a worklist. A tool is closed when every
paired function meets §1 and libDriver/libc imports stay unpaired.

**Campaign close.** README names the new reloc counts, that both tools were
rebuilt and compared, that the version objects exist, and that the driver
is still untested on hardware. Do not write `complete`. Do not un-blacklist
the driver.

## 8. Excluded

- QEMU, boot, and hardware printer testing
- Every other driver, `src/kernel-7`, `tools/binrecon` analyzer/comparator
  changes, `normalize.py`, re-enabling Ghidra
- Hand-writing Kernel Server glue
- Byte identity of `_VERS_STRING` / `_VERS_NUM` contents
- Editing `buf.h` to close the `physbuf` encoding
- The `ParallelPort` MH_BUNDLE wrapper
- Removing the driver from `kernel-drivers-blacklist.json`
- Restoring a five-driver input-recon dispatcher
- Syncing all of `src/` to the shared guest
- Repeating Task 10's layout, protocol, string, or symbol work except the
  three reopened rows in §2

## 9. Commit conventions

Driver commits: `drvPCParallel: `, one to two lines, behaviour not file
lists. Harness, profiles, and README: `drivers-i386: `. Tool-only source:
`drvPCParallel: ` still. No metadata, no trailers, no `Co-Authored-By`.
Stage by explicit path. Never `git add -A`. Never commit reference
binaries, rebuilt `_reloc` / tools, or `tools/binrecon/out/`.
