# drvPCFloppy: driving the driver to function-level parity

Bring `drvPCFloppy`'s functions to byte-identity with Apple's shipped
`Floppy_reloc`, or to a recorded and justified divergence, using binrecon as the
measurement.

This design covers the campaign's shape and specifies its first sub-piece. The
remaining sub-pieces get their own specs when their turn comes, written against
measurements rather than against today's numbers.

## 1. Where this starts

A binrecon run against the driver produced its first real comparison. It needed
two things that did not exist before: the name-based function pairing added
earlier, without which only one of 230 functions paired at all, and error
context in binrecon's normalizer, without which two analyzer failures were
untraceable.

| | |
| --- | --- |
| Functions compared | 230 |
| Paired (222 by name, 1 by offset) | 223 |
| — of those, byte-identical (`raw_equal`) | 49 |
| — of those, genuinely differing | 174 |
| Unpaired: ours only (`missing-reference`) | 5 |
| Unpaired: reference only (`missing-rebuilt`) | 2 |

**All 223 paired functions carry the status `different`, including the 49 that
are byte-identical.** That is not a contradiction: `cfg differs` fires on 222 of
them because basic blocks are keyed by address, and two independently laid-out
binaries never agree on those. As with the kernel, `cfg_equal` carries no
information for name-paired functions. **`raw_equal` and `masked_equal` are the
signals that mean anything here**, and the campaign's target is the 174 for which
they are false.

**Only one function paired by offset**, so the two binaries share almost no
layout. Name pairing is what makes this driver comparable at all.

**`masked_equal` equals `raw_equal` exactly, at 49.** Both analyses carry ~3,100
relocations, so masking has material to work with — unlike the linked kernel,
where there were none. The equality therefore is not a broken mask: it means **no
function differs only by relocated addresses.** Every one of the 174 differs
substantively, reported as `instruction shape differs` or `cfg differs`. Byte
identity is a well-defined target here.

### 1.1 These numbers are stale, and known to be

The analysed binary is from 2026-07-26. It predates nine committed but unbuilt
changes, and an earlier pass that aligned four classes' ivars to the reference.

Four of the five `missing-reference` entries — `isAnyOtherOpen`, `_queueEmpty`,
`_dequeueOperation` and `_appendOperationToQueue` — are functions we export and
Apple does not, and all four are **already deleted in unbuilt source**. They will
simply disappear. What remains unpaired after the rebuild should be three
entries: `-[IODriveNEW lastReadyState]` (ours only), `-[IODriveNEW
incrementWriteErrors]` (Apple's only) — the two together suggesting a method-set
mismatch on that one class — and `__udivdi3`, a libgcc routine Apple's build
pulls in and ours does not.

Every count above will move. Sub-piece 0 exists to replace them.

## 2. Scope and completion

**This supersedes the previously scoped Pieces B and C.** Those were cut from an
ivar audit; this is cut from binrecon evidence, and they become two sub-pieces
among eight.

**A class is done when every function in it is byte-identical — raw or masked —
or its remaining difference is recorded in `divergences.md` with the disassembly
evidence and an explicit *accept* disposition.** This is the convention that
closed `drvPCMCIABus` and `Intel82365PCMCIA`. It terminates, and it leaves a
record a later reader can audit.

### 2.1 Decomposition

One sub-piece per class, ordered by the class hierarchy, because a base class's
layout propagates into its subclasses and re-doing subclass work after a base
moves is waste.

| # | Sub-piece | Functions (stale) |
| --- | --- | --- |
| 0 | Re-baseline and `binrecon function` tooling | — |
| 1 | `IODiskNEW`, `IODriveNEW`, `IOLogicalDiskNEW` | 28 |
| 2 | `IODiskPartitionNEW` | 21 |
| 3 | `IOFloppyDisk` | 37 |
| 4 | `IOFloppyDrive` | 35 |
| 5 | `FloppyController` | 26 |
| 6 | `_HandleBsdOpen`, `_HandleBsdClose`, `_HandleBsdRead`, `_HandleBsdWrite`, `_fakeStrategySuccess` | 5 |

The three base classes are grouped because they are small, they share the same
already-applied ivar alignment, and splitting them would triple the build cycles
for 28 functions.

**Only sub-piece 0 is specified here.** Writing all eight now would be
speculation against numbers we know are wrong.

## 3. Sub-piece 0

Three deliverables. **No driver source changes.**

### 3.1 Rebuild and re-baseline

The user builds; binrecon is re-run and its output published. This also closes
the outstanding build gate from the invented-symbol piece, so the two are one
event rather than two.

### 3.2 Repair the committed profile

`tools/binrecon/profiles/floppy.json` enables angr and Ghidra alongside IDA.
Both fail on this driver, for unrelated reasons, and both are now diagnosable:

- **angr mis-decodes.** At `0x27` it reports a one-byte `lodsd` where a
  four-byte PC-relative relocation sits — it began decoding inside a
  `call`/`jmp rel32` that starts at `0x26`.
- **Ghidra cannot attribute relocations to operands.** At `0x3ab8` in the
  *reference*, a relocation targeting `_page_size` sits in an operand Ghidra
  renders as bare `dword ptr [0x00000000]`, so binrecon's textual owner-matching
  finds no candidate.

Neither is a defect in the driver. The profile becomes IDA-only, with a comment
recording both failures so the next person does not re-derive them. Fixing
either adapter is out of scope.

### 3.3 `binrecon function`

A query over already-published output. The published analyses carry per-function
`instructions` with `address`, `bytes`, `mnemonic`, `operands`,
`normalized_operands` and `relocations`, so this needs **no new disassembly** and
answers instantly. That is what makes 174 functions tractable: the campaign will
look at individual functions hundreds of times, and no look may cost a
thirteen-minute analyzer run.

Two modes:

```
binrecon function --profile PROFILE --list
binrecon function --profile PROFILE --name '+[IOFloppyDisk driveNumberOfDrive:]'
```

**`--list`** emits the worklist: every paired function with its status, its
reasons, and its count of differing instructions, **sorted by that count
ascending.**

That ordering is the design's main lever. Cheapest-first means each build cycle
closes the most functions, and it surfaces systemic causes early — six functions
differing by the same single instruction is one fix, not six.

**`--name`** prints reference against rebuilt instruction-for-instruction,
aligned, with differences marked, and the function's comparison verdict and
reasons above them. Name matching pairs Objective-C methods and plain C
functions alike, since the five `HandleBsd*` functions need it too.

It lives in binrecon with unit tests, not in the driver directory: eighteen other
drivers in this tree have reference binaries, and this is the third one where the
question has come up.

### 3.4 Done when

The build passes, the profile runs clean, `--list` produces a ranked worklist
over a current binary, and `--name` reproduces a known function's two sequences.
Sub-piece 1's spec is then written against that worklist.

## 4. Risks

**The first build has never happened.** Nine commits from the invented-symbol
piece, plus inheritance changes across four drivers, have never been compiled.
The first build may fail for reasons unrelated to this campaign, and nothing
starts until it passes. Largest unknown here.

**The baseline may not survive contact, and the plan's shape with it.** If the
174 move substantially, the eight sub-pieces may need re-cutting. Section 2.1's
table is provisional by construction.

**Some differences may be unreachable from source** — register allocation,
instruction scheduling, compiler version. Accept-with-evidence handles
individual cases. If most of the 174 prove unreachable, the campaign's value
collapses, and the worklist is the early read: if the *cheapest* functions differ
by register choice rather than logic, stop and re-scope rather than grind through
eight sub-pieces.

**Two classes may partly evaporate.** `IOFloppyDisk` and `IOFloppyDrive` both had
real defects fixed in unbuilt source — a wrong superclass and a memory
corruption — so some of their 72 combined differences should resolve on their
own.

**Another agent commits to this driver**, and has landed work mid-range during
this work already. Sub-pieces stage files explicitly and re-check the baseline
when foreign commits appear.

## 5. Excluded

- **Hardware and functional testing.** This is a static parity campaign; a
  byte-identical driver is not a tested one.
- **The other eighteen drivers**, though the tooling serves them.
- **Fixing the angr and Ghidra adapters.** Recorded, not repaired.
- **The two Minor findings parked from the invented-symbol piece** —
  `Bsd.m`'s raw queue appends and the `(id *)&queue` casts. They fold into
  whichever sub-piece owns their file.

## 6. Testing

The new subcommand gets unit tests in binrecon's suite, which stands at 905
passing and 4 skipped. The driver itself has no test framework; its verification
is the binrecon comparison described above.
