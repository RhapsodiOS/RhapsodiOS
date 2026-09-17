# Finish drvPS2Keyboard under binrecon

Drive `drvPS2Keyboard` to function-level byte identity with Apple's shipped
`PS2Keyboard_reloc`, raising the done bar from Task 8's control-flow and
section parity to `raw_equal` / `masked_equal`.

This continues
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/input/drvPS2Keyboard/reconstruction/`. Task 8's layout,
protocol, string, symbol, and `Loaded Server` fixes stay. This spec does not
reopen Ghidra, `normalize.py`, `src/kernel-7`, or any other driver.

## Motivation

The July report and fix passes closed every named divergence. Class layouts,
protocols, `_exported_funcs` membership, and string/symbol sets match the
reference. `src/drivers-i386/README` already says the driver "compiles;
reconstructed against the reference binary, fixes applied, not yet tested."

What remains is instruction shape. Thirty-nine of forty-seven mapped functions
are `control-flow-confirmed` because Task 8 never compared the rebuilt
instruction stream. `__TEXT,__text` is 4652 bytes against Apple's 4952. The
guest harness named in the July plan, `vm/build-i386-input-recon.sh`, is not in
this worktree.

Done means every paired function matches or is accepted as compiler-shaped, the
driver compiles on the Rhapsody guest, and the README line names the new
counts. It does not mean QEMU types keys.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current guest `PS2Keyboard_reloc`, or when the
leftover is recorded in
`src/drivers-i386/input/drvPS2Keyboard/reconstruction/divergences.md` with the
`binrecon function --name` dump and an explicit *accept* disposition
(compiler-shaped: register allocation or instruction scheduling).

The campaign is done when every paired function in the driver meets that bar,
unpaired leftovers are only
`+[PS2KeyboardKernelServerInstance kernelServerInstance]` and
`+[PS2KeyboardVersion driverKitVersionForPS2Keyboard]`, no hand-written
function remains `unexamined`, and `parity_check.py` `missing_strings` /
`missing_symbols` stay 0.

`cfg_equal` is not a pass signal. Status may stay `different` because of
`cfg differs` or `instruction layout differs`. The flags that count are
`raw_equal` and `masked_equal`.

`__TEXT,__text` need not hit 4952. That 300-byte gap is codegen (guest `cc`
versus Apple's March 1998 build), not missing logic. Do not grind envelope
size.

Hardware testing stays out. The README line remains that the driver is not yet
tested on hardware.

The eight Task 8 `assembly-matched` functions are a regression gate, not a
rewrite target:

`-[PS2Controller getHandler:level:argument:forInterrupt:]` (1388),
`-[PS2Controller setLEDs:]` (1472), `_clearOutputBuffer` (1960),
`+[PS2Keyboard deviceStyle]` (2404), `-[PS2Keyboard interfaceId]` (4340),
`-[PS2Keyboard handlerId]` (4356), `-[PS2Keyboard setAlphaLockFeedback:]`
(4372), `-[PS2Keyboard relinquishOwnership:]` (4632).

Confirm they remain equal after later rebuilds. Do not rewrite their bodies.

## 2. Current evidence (do not rediscover)

Reference: `PS2Keyboard_reloc`, 43460 bytes, SHA-256
`AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A`.
`BINRECON_REFERENCE` is
`C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Keyboard.config\PS2Keyboard_reloc`.
Profile: `tools/binrecon/profiles/ps2keyboard.json` (IDA 9.2 + angr 9.3.0,
Ghidra off). Analyzer output: `tools/binrecon/out/ps2keyboard/` (gitignored).

Task 8 rebuilt (unstripped) was 157640 bytes. Remeasure on the Phase 1 `_reloc`.

| Property | Reference | Ours after Task 8 |
|---|---|---|
| `__TEXT,__text` | 4952 | 4652 |
| `__TEXT,__cstring` | 466 | 466 |
| `__DATA,__data` | 248 | 248 |
| `__DATA,__bss` | 96 | 96 |
| `__OBJC,__class` | 160 | 160 |
| `__OBJC,__instance_vars` | 140 | 140 |
| `__OBJC,__protocol` | 60 | 60 |
| `__OBJC,__meth_var_types` | 242 | 242 |
| `Loaded Server,Load Commands` | 164 | 164 |
| `Loaded Server,Unload Commands` | 102 | 102 |
| `PS2Controller instance_size` | 308 | 308 |
| `PS2Keyboard instance_size` | 548 | 548 |
| Ledger | — | 8 `assembly-matched`, 39 `control-flow-confirmed`, 2 glue `intentional-mismatch`, 0 `unexamined` |
| `missing_strings` / `missing_symbols` | — | 0 / 0 |

`PS2Controller` and `PS2Keyboard` are siblings (`IODirectDevice` and `IODevice`),
not an inheritance chain. Layout is already byte-identical. There is no layout
pass.

`_PS2Keyboard_VERS_STRING` / `_VERS_NUM` live in the reference `__TEXT,__const`
and are emitted by NeXT `vers_string` machinery. No driver in this tree
produces them. Leave them absent. Do not edit `driverTools` or
`kernelserver.make`.

The 39 `control-flow-confirmed` functions are the grind set. Experiment lists
are written after Phase 1 `--list`, not guessed here.

## 3. Architecture

This is a reconstruction campaign on one loadable driver, not a new subsystem.
Whole-driver cheapest-first: layout is already closed, and name-paired
`masked_equal` ignores relocated immediates and envelope padding, so neither
class-then-class nor address-order walking is required.

**Phase 0 — harness.** Recreate `vm/build-i386-input-recon.sh` modelled on
`vm/build-i386-scsi.sh` and `vm/build-i386-video-recon.sh` (POSIX Bourne, no
`set -e` on predicates, CR stripped from Makefiles, `gnumake RC_ARCHS=i386
INCLUDED_ARCHS=i386`, gate on `_reloc` presence). Stage under
`/build/out/i386/drvPS2Keyboard/PS2Keyboard.config/`. The required arm is
`drvPS2Keyboard`. If the file already exists with another driver's arm (a
sibling campaign may have added `drvISASerialPort`), add the PS2Keyboard arm
rather than deleting theirs. Do not restore the five-driver dispatcher. Do not
remove the driver from `src/rbuild-1/kernel-drivers-blacklist.json`.

**Phase 1 — baseline.** This session syncs only this driver, guest-builds,
copies `PS2Keyboard_reloc` to host `out/i386/drvPS2Keyboard/PS2Keyboard.config/`, runs
`parity_check.py`, IDA-analyzes the rebuilt binary, and writes
`reconstruction/function-worklist.md` with both SHA-256s, remaining counts, and
a reachability note. Reuse published reference analysis if `complete: true` and
the SHA is `AB413CA3…`. If the cheapest rows are already compiler-shaped, still
record that and accept rather than inventing rewrites.

**Phase 2 — cheapest-first.** Across both translation units, take the lowest
`differing` row that is still source-shaped. One experiment, one guest rebuild,
`--name` on the new published comparison. A shared cause is one edit cluster.
Matched functions are a regression gate. When a function's cheapest leftover is
compiler-shaped, accept it and move on. Do not reorder statements or invent
temporaries to chase gcc 2.x.

**Phase 3 — close.** Refresh the worklist, advance the ledger, update
`divergences.md` and the README line (still not hardware-tested).

`binrecon function` uses the existing name-paired `masked_equal` path in
`tools/binrecon/binrecon/compare.py`. No comparator changes. Do not re-enable
Ghidra. Do not re-run `binrecon analyze` on the reference unless the committed
consensus is missing.

## 4. Components

| Piece | Job |
|---|---|
| `vm/build-i386-input-recon.sh` | Guest harness. Stage `_reloc` under `/build/out/i386/drvPS2Keyboard/PS2Keyboard.config/`. |
| `vm/sync-src.ps1 -Path drivers-i386/input/drvPS2Keyboard` | Host → guest. Never `-All`. |
| `PS2Controller.m` / `PS2Keyboard.m` | The only files whose bodies get instruction-shape edits. |
| `PS2Controller.h` / `PS2Keyboard.h` | Layout already matches. Touch only if a typed rewrite is required for instruction shape (for example moving a `static`). No ivar, protocol, or `instance_size` changes. |
| `reconstruction/function-worklist.md` | New. Baseline after Phase 1; refreshed at campaign close. Ranked remaining rows and both SHA-256s. |
| `reconstruction/divergences.md` | Accepts live here. Task 8 resolutions stay. |
| `reconstruction/ledger.json` | Status of record. `assembly-matched` on `masked_equal`; `intentional-mismatch` for accepted compiler leftovers (reason + reviewer required). |
| `reconstruction/source-map.json` | Relined when bodies move. Partition stays 47 mapped / 2 unmapped. |
| `tools/binrecon/profiles/ps2keyboard.json` | Unchanged. IDA on the rebuilt `_reloc` for `function --list`. Ghidra stays disabled. |
| `binrecon function` | `--list` is the ranked worklist; `--name` is the instruction dump. Reads published output only. |
| `tools/binrecon/parity_check.py` | Regression gate: `missing_strings` and `missing_symbols` stay 0. Extra unstripped symbols are not findings. |
| `src/drivers-i386/README` | Update the drvPS2Keyboard line to the new bar; keep "not yet tested." |

**Do not touch:** `Default.table`, `Load_Commands.sect`, `Unload_Commands.sect`,
Makefiles, `dpkg/`, `src/kernel-7`, sibling input drivers, `compare.py`,
`kernel-drivers-blacklist.json`.

## 5. Data flow

Paths:

- `BINRECON_REFERENCE` =
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Keyboard.config\PS2Keyboard_reloc`
- `BINRECON_REBUILT` =
  `D:\RhapsodiOS\out\i386\drvPS2Keyboard\PS2Keyboard.config\PS2Keyboard_reloc`
- Guest stage = `/build/out/i386/drvPS2Keyboard/PS2Keyboard.config/`
- Guest source = `/build/source/src/drivers-i386/input/drvPS2Keyboard/`

`sync-src.ps1` does not upload `vm/`. Copy the harness with the OpenSSH path in
`vm/SSH CONNECTION.md` (not PuTTY `pscp`), CR-strip it on the guest, then
invoke it. Python on the host is `./.venv-binrecon/Scripts/python.exe` with
`PYTHONPATH=tools/binrecon`.

This session runs every guest rebuild, including per-experiment ones.

### 5.1 Phase 1 (once)

1. Copy `vm/build-i386-input-recon.sh` to the guest.
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/input/drvPS2Keyboard`.
3. `sh /build/source/vm/build-i386-input-recon.sh drvPS2Keyboard`. Copy
   `PS2Keyboard_reloc` back to the host path above.
4. `parity_check.py`: `missing_strings` 0, `missing_symbols` 0.
5. `binrecon validate --profile tools/binrecon/profiles/ps2keyboard.json`.
   IDA `analyze` on the reference if published output is missing or the SHA
   differs; IDA `analyze` on the rebuilt.
6. `binrecon function --list`. Write `function-worklist.md` with both SHA-256s,
   remaining counts, and whether the cheapest rows are source-shaped or already
   compiler-shaped.

`normalized-functions=FAIL` is expected until the campaign closes. A
reference-only profile may still exit 1; the gate is `complete: true`.

### 5.2 Phase 2 (each experiment)

1. Edit one site in `PS2Controller.m` or `PS2Keyboard.m`.
2. Sync only this driver. Rebuild. Copy `_reloc` back.
3. `parity_check.py` must still be clean.
4. Fresh IDA analyze of the rebuilt binary only.
5. `--name` on the campaign target against the new published comparison.
   `--list` to watch the regression set (every previously `masked_equal` /
   `raw_equal` row, including the eight Task 8 matches).
6. Match → keep the edit, advance that ledger row, next cheapest. Miss without
   regression → revert, mark tried. Regression of a closed function → revert,
   record, continue.
7. Record the outcome in `divergences.md` before the next edit.

Closed functions do not reopen to improve them. A later edit that only changes
gcc scheduling on a closed function is a regression and is reverted.

### 5.3 Allowed and forbidden shape edits

Source-shape only. Written into `function-worklist.md` after Phase 1, before
the first shape rebuild. One item per rebuild.

Allowed: statement order, local vs expression, signedness of *locals*, loop
shape, `if` vs `else if` chains, operand-reversed `cmp`, declaration order of
existing locals.

Forbidden: padding ivars; changing `PS2Controller` / `PS2Keyboard` instance
layout; renaming ivars or protocols; restoring `NXLock`; putting queue state
back into ivars; inventing temporaries whose only purpose is to pick a
register after the list is already empty; repeating a reverted experiment;
chasing `__text` envelope size.

## 6. Error handling

| Failure | Response |
|---|---|
| Guest unreachable or SSH crypto fails | Stop. Do not invent instruction-stream results. Leave the campaign open. |
| Phase 1 build fails | Unexpected: Task 8 already compiled this tree. Stop, report the log, fix only what it names. Do not start function edits. |
| Later rebuild fails | Revert the last experiment (or fix a typo it introduced). Do not advance the ledger. |
| `parity_check.py` `missing_strings` or `missing_symbols` non-zero | Revert. That is a Task 8 regression, not a shape win. |
| IDA analyze / normalize fails | Report the artifact, analyzer, and instruction. Do not disable IDA, re-enable Ghidra, or hand-edit published JSON. |
| Cheapest remaining row is compiler-shaped | Accept with the `--name` dump. Do not reorder statements, invent temporaries, or chase register allocation. |
| An edit regresses a previously identical function | Revert before the next experiment. |
| New unpaired functions after a rebuild | Layout or linkage finding. Stop grinding shape; diagnose names/bindings. |
| `__text` stays ~300 bytes short after all accepts | Expected. Record sizes. Not a failure. |
| `_PS2Keyboard_VERS_STRING` / `_VERS_NUM` still absent | Same as Task 8. Do not edit `driverTools` or `kernelserver.make`. |
| Another agent commits | Re-check `--list` against the current `_reloc` SHA before claiming a function closed. |
| Reference SHA no longer `AB413CA3…` | Stop. Wrong binary. |
| Stale `tools/binrecon/out/ps2keyboard/` | Never treat an older run as evidence for a new `_reloc`. |

Linkage claims, when needed, are the rebuilt nlist via
`binrecon.macho.read_macho`, never IDA's `binding` field and never
`parity_check.py` name counts alone.

## 7. Testing

There is no driver unit-test framework. Verification is the guest `_reloc` plus
host binrecon. No QEMU, no boot, no hardware. `compare.py` is not edited.

If something under `tools/binrecon` is touched despite §3, existing
`tools/binrecon/tests` must stay green
(`./.venv-binrecon/Scripts/python.exe`, `PYTHONPATH=tools/binrecon`). This
campaign does not plan that.

**Phase 1.** Harness `sh -n` is clean. Guest build stages `PS2Keyboard_reloc`.
`parity_check.py` reports `missing_strings` 0 and `missing_symbols` 0.
`binrecon validate` prints the reference identity `AB413CA3…`.
`function --list` produces a ranked worklist. Both SHA-256s are in
`function-worklist.md`. `PS2Controller` `instance_size` stays 308;
`PS2Keyboard` stays 548.

**Each experiment.** Same parity gate. `--name` on the campaign target against
the new published rebuilt analysis. Previously identical rows stay identical.
Claimed win → ledger `assembly-matched`. Accept → `--name` dump in
`divergences.md` plus `intentional-mismatch` with reason and reviewer.

**Campaign close.** `--list`: unpaired only the two glue methods in §1. Every
other hand-written row is identical, `masked_equal`, or accepted. Ledger has no
`unexamined` hand-written function. `rebuilt_sha256` is the last kept `_reloc`.
README names the new counts and still says not tested on hardware. Do not
write `complete`.

## 8. Excluded

- QEMU, boot, and hardware keyboard testing
- Every other driver, `src/kernel-7`, `tools/binrecon` analyzer/comparator
  changes, `normalize.py`, re-enabling Ghidra
- Hand-writing Kernel Server glue
- Byte identity of `_VERS_STRING` / `_VERS_NUM` contents
- Removing the driver from `kernel-drivers-blacklist.json`
- Restoring the five-driver input-recon dispatcher
- Syncing all of `src/` to the shared guest
- Repeating Task 8's layout, protocol, string, or symbol work

## 9. Commit conventions

Driver commits: `drvPS2Keyboard: `, one to two lines, behaviour not file lists.
Harness and README: `drivers-i386: `. No metadata, no trailers, no
`Co-Authored-By`. Stage by explicit path. Never `git add -A`. Never commit
reference binaries, rebuilt `_reloc` files, or `tools/binrecon/out/`.
