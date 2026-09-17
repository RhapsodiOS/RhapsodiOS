# Finish drvPCFloppy under binrecon

Drive `drvPCFloppy` to function-level byte identity with Apple's shipped
`Floppy_reloc`, with class layout as a required step, using binrecon as the
measurement.

This continues
[2026-09-07-floppy-function-parity-design.md](2026-09-07-floppy-function-parity-design.md)
and supersedes that spec's unspecified sub-pieces 1–6. Sub-piece 0's tooling
(`floppy.json` IDA-only, `binrecon function`) stays. Its unbuilt rebuild becomes
Phase 1 here.

The metadata reconstruction
([2026-07-25-drvpcfloppy-binary-reconstruction-design.md](2026-07-25-drvpcfloppy-binary-reconstruction-design.md))
is already closed: strings, imports, and hand-written symbols match. This spec
does not reopen that work. It does not replace
[2026-09-07-floppy-invented-symbol-removal-design.md](2026-09-07-floppy-invented-symbol-removal-design.md);
that piece's source is committed and its guest-build gate is absorbed into
Phase 1.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current `Floppy_reloc`, or when the leftover is
recorded in `src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md`
with the `binrecon function --name` dump and an explicit *accept* disposition.

A class is done when every function in it meets that bar. The campaign is done
when every paired function in the driver does, unpaired leftovers are only the
known build-generated set (`__udivdi3`, `+[FloppyKernelServerInstance
kernelServerInstance]`, `+[FloppyVersion driverKitVersionForFloppy]`), and
symbol / string / import counts have not regressed from the metadata-complete
baseline (`missing_symbols` remains `__udivdi3` only).

`cfg_equal` is not a signal for name-paired functions. Status may remain
`different` because of `cfg differs` or `instruction layout differs`. The flags
that count are `raw_equal` and `masked_equal`.

Hardware testing stays out. The README line remains that the driver is not yet
tested on hardware.

## 2. Architecture

This is a reconstruction campaign, not a new subsystem. The inheritance tree
sets the order:

```
IODevice
├── IODiskNEW
│     ├── IOFloppyDisk
│     └── IOLogicalDiskNEW
│           └── IODiskPartitionNEW
├── IODriveNEW
│     └── IOFloppyDrive (+ volCheckSupport)
└── FloppyController : IODirectDevice   (separate tree)
```

**Phase 0 — measurement.** Fix binrecon's relocation-masking gap so functions
that differ only by relocated addresses report `masked_equal`. Prove it with
unit tests and, when published floppy output exists, with `binrecon function
--list`. No driver source changes.

**Phase 1 — baseline.** The user builds on the Rhapsody guest (first compile of
the invented-symbol work). Re-run IDA analysis, write
`reconstruction/function-worklist.md`, and judge reachability from the cheapest
rows. If those rows are already compiler-shaped, later phases still run —
layout gaps can hide behind that — but function grinding on a class stops as
soon as *that class's* remainder is unreachable.

**Phases 2–N — classes.** Shared layout pass and one rebuild for `IODiskNEW` /
`IODriveNEW` / `IOLogicalDiskNEW`, then function parity `IODiskNEW` →
`IODriveNEW` → `IOLogicalDiskNEW` with no extra layout rebuild between those
three. After that, each remaining unit is layout → rebuild → cheapest-first
functions:

1. `IODiskPartitionNEW`
2. `IOFloppyDisk`
3. `IOFloppyDrive` (instance size 424 vs Apple 444; `lastAccess` belongs at
   `+368`, not at the end of the class)
4. `FloppyController` (after the drive; not in the inheritance chain)
5. BSD helpers (`_HandleBsdOpen`, `_HandleBsdClose`, `_HandleBsdRead`,
   `_HandleBsdWrite`, `_fakeStrategySuccess`) — no ObjC instance layout; skip
   the layout step

A class stops when its cheapest remaining diffs are register allocation or
instruction scheduling. Accept those with disassembly evidence and move on. Do
not reorder statements or invent temporaries to chase gcc 2.x shape.

## 3. The masking gap (Phase 0)

Sub-piece 0 found eight functions whose normalized instruction streams already
match (`differing == 0`) while both `raw_equal` and `masked_equal` are false.
Examples: `+[FloppyKernelServerInstance kernelServerInstance]`, `-[IODiskNEW
eject]`, `-[IODiskNEW lockLogicalDisks]`, `-[IODiskPartitionNEW
setBlockDeviceOpen:]`.

Offset-paired functions already mask correctly
(`test_relocation_field_difference_is_not_code_difference`). Name-paired
functions do not, because `_compare_function_range` only zeros a relocation
field when both sides share the same portable relocation semantics at the same
relative offset. Independently linked binaries never do: the same `call
_page_size` has different target offsets, so the field is left unmasked and the
immediates fail the comparison. Envelope-size mismatch on name-paired
functions takes the same `_unequal_range_result` path and also forces
`masked_equal` false even when the instruction streams match.

**Required behaviour.** For name-paired functions, `masked_equal` is computed
from the concatenated per-instruction bytes after each side's relocation
fields are zeroed independently. Envelope padding and absolute addresses are
not part of that equality. Offset-paired functions keep the current envelope
comparison, including unlisted gap bytes.

If two name-paired functions have identical mnemonics and normalized operands
and differ only in relocated immediates, `masked_equal` is true and `raw_equal`
is false. Truly different instruction shape stays not equal.

Do not re-enable angr or Ghidra. Do not add a floppy-specific compare path;
the comparator change is general.

## 4. Components

| Piece | Job |
|---|---|
| `tools/binrecon/binrecon/compare.py` | Relocation-neutral equality. Phase 0 changes only this and its tests. |
| `binrecon function` | `--list` is the ranked worklist; `--name` is the instruction diff. Reads published output only. |
| `tools/binrecon/profiles/floppy.json` | IDA-only. Unchanged except if a path comment in `name` needs no edit. |
| Guest build | The user runs it. Agents never compile. Every claimed byte identity waits on a new `Floppy_reloc` and a fresh `binrecon analyze`. |
| `reconstruction/function-worklist.md` | Baseline after Phase 1; refreshed when a class closes. |
| `reconstruction/divergences.md` | Accepts live here. |
| `reconstruction/ledger.json` | Per-function status of record. |
| `reconstruction/source-map.json` | Function → file/line; line numbers update when bodies move. |
| `reconstruction/analyzer-notes.md` | Why IDA only. Unchanged. |

Driver source, by owner. Layout and function edits touch only the class
currently open:

- Base group: `IODiskNew.[hm]`, `IODriveNEW.[hm]`, `IOLogicalDiskNEW.[hm]`,
  and `kernelDiskMethodsNEW.[hm]` with the base that owns the method
- `IODiskPartitionNEW.[hm]`
- `IOFloppyDisk` plus `Geometry.m`, `Request.m`, `Thread.m`, `Support.m`
- `IOFloppyDrive` plus `FloppyDriveInt.m`, `FloppyDriveInt2.m`, `VolCheck.m`
- `FloppyController` plus `FloppyCnt.m`, `FloppyCntIo.m`, `FloppyCmds.m`,
  `FloppyArch.m`
- BSD: `Bsd.m` / `Bsd.h`

No adjacent cleanup. Stage only this campaign's files. Another agent commits
to this repository.

## 5. Data flow

1. Phase 0 unit tests fail, comparator changes, tests pass. `--list` on
   published floppy output, if present, shows the eight rows as `masked-eq` or
   `identical`. If they do not, Phase 0 is not done.
2. User builds. Host runs `binrecon validate`, `analyze` (IDA, ~10 minutes),
   `function --list`. Record SHA-256 of both binaries, the summary line,
   per-class remaining counts, whether the four deleted invented symbols are
   gone, and the reachability judgement, in `function-worklist.md`.
3. Layout step: dump the reference class's instance size and ivar offsets from
   `__OBJC`. Diff against our header. Rewrite that class's ivars so size and
   offsets match. User rebuilds. Instance size must equal Apple's before
   function chasing, or the gap is an accept.
4. Function step: run `--list` and keep the rows whose names belong to the
   open class (no new CLI flag). Cheapest `differing` first. One shared cause
   is one edit cluster. User rebuilds. `--name` confirms each claimed win on
   the *new* published comparison.
5. When the cheapest remaining in that class is compiler-shaped, accept and
   close the class. Refresh the worklist summary. The next class starts from
   that binary.
6. Closed classes reopen only when this change caused a new diff, not to
   improve them. A later superclass layout change that invalidates a closed
   subclass is a process bug: go back to the base.

`BINRECON_REFERENCE` is
`C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc`.
`BINRECON_REBUILT` is
`D:/RhapsodiOS/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc`.
The guest build script is `vm/build-i386-floppy.sh`.

## 6. Error handling

| Failure | Response |
|---|---|
| Guest build fails, especially Phase 1 | Stop. The invented-symbol commits have never compiled. Report the log. Fix only what it names. |
| Analyze / normalize fails | Report the named artifact, analyzer, and instruction. Do not disable IDA, re-enable angr/Ghidra, or hand-edit published JSON. |
| Masking fix does not flip the eight rows | Phase 0 is not done. No driver edits. If published output is too stale to prove the fix, Phase 1's rebuild exists only to re-prove masking. |
| Layout cannot match Apple's instance size | Record offsets, sizes, and why source cannot produce it. Accept. Chase functions with the gap named. Do not insert padding or unused ivars the reference does not have. |
| A function fix regresses another function | Revert or correct before continuing. |
| Cheapest remaining in the open class is compiler-shaped | Accept with the `--name` dump. Do not grind register allocation. |
| Superclass layout would invalidate a closed subclass | Return to the base. Do not patch the subclass to compensate. |
| Another agent commits | Re-check the worklist against the current `Floppy_reloc` hash before claiming a class closed. |
| New unpaired functions after a rebuild | Treat as a layout or linkage finding, not a function-shape finding. |

## 7. Testing

There is no driver unit-test framework. Verification is binrecon plus the guest
build the user runs.

**Phase 0.** New comparator tests cover: name-paired functions with identical
mnemonics and normalized operands whose raw bytes differ only at relocated
immediates must be `masked_equal` and not `raw_equal`; truly different
instruction shape stays not equal; offset-paired envelope comparison including
unlisted gaps is unchanged. Existing suite stays green; judge the delta, not
the absolute count (other agents add tests). Interpreter:
`./.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.

**Phase 1 and every later rebuild.** `binrecon validate --profile
tools/binrecon/profiles/floppy.json`, then `analyze`, then `function --list`.
`normalized-functions=FAIL` remains expected until the campaign closes.

**Per class.** Layout gate: rebuilt instance size equals the reference, or the
gap is an accept. Function gate: `--name` on each claimed win against the new
comparison. An accept requires both the `--name` dump in `divergences.md` and
`intentional-mismatch` plus reason and reviewer in `ledger.json`.

**Campaign close.** `--list`: unpaired only the known build-generated set;
every other row identical, masked-equal, or accepted. `ledger.json` has no
`unexamined` hand-written function.

## 8. Excluded

- Functional floppy testing in QEMU or on hardware
- The other drivers, though they inherit the masking fix
- Fixing the angr and Ghidra adapters
- `__udivdi3` and `kl_ld` glue, which no hand-written source produces
- Repeating the unsigned-`chipType`-style experiments of other drivers:
  compiler-shaped leftovers are accepted, not ground
- The `Floppy` MH_BUNDLE beside `Floppy_reloc`

## 9. Commit conventions

Driver commits: `drvPCFloppy: `, one to two lines, behaviour not file lists.
binrecon commits: `binrecon: `. No metadata, no trailers, no `Co-Authored-By`.
Stage by explicit path. Never `git add -A`.
