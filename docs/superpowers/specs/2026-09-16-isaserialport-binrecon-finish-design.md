# Finish drvISASerialPort under binrecon

Drive `drvISASerialPort` to function-level byte identity with Apple's shipped
`ISASerialPort_reloc`, finishing the July reconstruction and raising its done
bar from "algorithms match, ledger honest" to `raw_equal` / `masked_equal`.

This continues
[2026-07-26-isaserialport-binary-reconstruction-design.md](2026-07-26-isaserialport-binary-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/input/drvISASerialPort/reconstruction/`. The July report pass,
Load Commands, `GLOBAL_RESOURCES`, `"Version" = "5.00"`, two-ivar `Port` layout,
`ISASerialPortInternal.h`, and `ISASerialPortFlow.c` stay. This spec does not
reopen Ghidra, `normalize.py`, or any other driver.

## Motivation

The July spec stopped at control-flow reconstruction. Task 3 inverted the ivars
(`__OBJC,__instance_vars` is 28 bytes) and extracted TU 4. TUs 3 and 2 still live
in `ISASerialPort.m`. Forty-one ledger entries are still `unexamined`. The
`_Chip` table is still absent. `src/drivers-i386/README` still says the driver
"needs compiled and then tested". The guest harness named in the July plan,
`vm/build-i386-input-recon.sh`, is not in this worktree.

Done means every paired function matches or has an exhausted experiment list,
the driver compiles on the Rhapsody guest, and the README line is updated. It
does not mean QEMU talks to COM1.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current guest `ISASerialPort_reloc`, or when that
function's named experiment list is empty and the leftover is recorded in
`src/drivers-i386/input/drvISASerialPort/reconstruction/divergences.md` with the
`binrecon function --name` dump and an explicit *accept* disposition.

A translation unit is done when every paired function in it meets that bar. The
campaign is done when every paired function in the driver does, unpaired
leftovers are only `__udivdi3`, `__umoddi3`,
`+[ISASerialPortKernelServerInstance kernelServerInstance]`, and
`+[ISASerialPortVersion driverKitVersionForISASerialPort]`, and no function
remains `unexamined`.

`cfg_equal` is not a pass signal. Status may stay `different` because of
`cfg differs` or `instruction layout differs`. The flags that count are
`raw_equal` and `masked_equal`.

`nextEvent` (6400) and `release` (5448) are already `assembly-matched`. Do not
rewrite their bodies. Confirm they remain equal after later rebuilds.

## 2. Current evidence (do not rediscover)

Reference: 67328 bytes, SHA-256
`4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932`.
`BINRECON_REFERENCE` is
`C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc`.
Profile: `tools/binrecon/profiles/isaserialport.json` (IDA 9.2 + angr 9.3.0,
Ghidra off). Analyzer output: `tools/binrecon/out/isaserialport/` (gitignored).

| Property | Reference | Ours after Task 3 |
|---|---|---|
| `__TEXT,__text` | 24412 | last measured 24980 before Task 3; remeasure on the Phase 0 `_reloc` |
| `__OBJC,__instance_vars` | 28 | 28 |
| `__OBJC,__module_info` | 32 | 32 |
| `Port` at object offset | 296 | header declares 296; Task 3 rebuild was 264 because the superclass was still `IODevice` |
| `port` pointer offset | 600 | header declares 600; Task 3 rebuild was 568 |
| `instance_size` | 604 | Task 3 rebuild 572 |
| Exported `__text` | 11 | 11, same names |
| Ledger | — | 2 `assembly-matched`, 2 `signature-confirmed` (flow/watch), 2 glue `intentional-mismatch`, 41 `unexamined` |

`ISASerialPort.h` now says `@interface ISASerialPort : IODirectDevice`. Phase 0
must prove the rebuilt `instance_size` is 604. If it is still 572, the
`IODirectDevice` import is not actually linking and TU 1 does not start until
that is fixed.

The eleven exported signatures are already declared in `ISASerialPortInternal.h`
as `Port *` / `Queue *`. Ten TU 1 locals still have a leading underscore the
reference does not (`activatePort`, `deactivatePort`, `executeEvent`, both
interrupt handlers, `PCMCIA_yanked`, four timeout handlers). Drop that
underscore in TU 1 so the compiler emits the reference names as `local`. The
two libgcc substitutes stay unpaired; `static` on them is allowed so the
compiler emits `__udivdi3` / `__umoddi3`, but their bodies are not ground
against libgcc.

`_Chip` is nine 20-byte rows at `__DATA,__data`+0. Decode is in
`divergences.md` §4.2. Indices: 0 Auto/Unknown, 1 8250, 2 16450 / 8250A or
16450, 3 16450 / 16C1450, 4 16450 / 16550 with defective FIFO, 5 16550 /
16550AF/C/CF, 6 16550 / 16C1550, 7 16650 / ST16C650, 8 82510. Invented
`CHIP_16750` / `CHIP_16950` names and `chipCapTable` / `chipTypeNames` die in
TU 2. `_msr_state_lut` is the 16-byte DSR/DCD swap at `__DATA,__data`+180, not
the identity table still in `ISASerialPort.m`.

Apple bugs reproduced, not fixed: `identifyChip` rung 7 reads MCR without
writing it; `requestEvent` 0x27 uses `RX.Size - TX.Count`; `executeEvent:data:`
0x0B validates against RX then stores into TX.

Filenames `ISASerialPortChip.c`, `ISASerialPortQueue.c`, `ISASerialPortFlow.c`
are ours. Only `ISASerialPort.m` is recovered from `__OBJC,__module_info`.

## 3. Architecture

Four translation units, smallest first, each with an algorithm pass then a
shape pass. Do not open the next unit until the current one meets §1.

```
TU 4  ISASerialPortFlow.c     already extracted
TU 3  ISASerialPortQueue.c    still inside ISASerialPort.m
TU 2  ISASerialPortChip.c     still inside ISASerialPort.m
TU 1  ISASerialPort.m         class + local C
```

**Phase 0 — harness and baseline.** Recreate `vm/build-i386-input-recon.sh`
modelled on `vm/build-i386-scsi.sh` (POSIX Bourne, no `set -e` on predicates,
CR stripped from Makefiles). The only required arm is `drvISASerialPort`. Sync
only this driver, guest-build, copy `ISASerialPort_reloc` to
`out/i386/drvISASerialPort/`. Record SHA-256, section sizes, nlist linkage,
`instance_size`, `__DATA,__bss` size, and `binrecon function --list` in
`reconstruction/function-worklist.md`. Prove `IODirectDevice` (604). Fix it
here if it fails; every later offset claim depends on it.

**Per unit after Phase 0.**

1. Algorithm pass: apply the already-written `divergences.md` findings for
   that unit so signatures, tables, constants, and control flow match. Extract
   the `.c` file if it does not exist yet. Guest rebuild after the extract and
   after each finding cluster that can change codegen.
2. Shape pass: write a short named experiment list for every remaining
   paired function in that unit into `function-worklist.md`. One experiment,
   one guest rebuild, one `--name` dump. Keep a shape experiment only if
   `raw_equal`/`masked_equal` becomes true, or `differing` strictly decreases,
   and no closed function regresses. Otherwise revert, mark tried, continue.
   Algorithm-pass findings stay even when shape does not match. Stop that
   function on match or empty list (accept with dump + reviewer).

`binrecon function` uses the existing name-paired `masked_equal` path in
`tools/binrecon/binrecon/compare.py`. No comparator changes. Do not re-enable
Ghidra. Do not re-run `binrecon analyze` on the reference unless the committed
consensus is missing; the reference binary has not changed.

## 4. Components

| Piece | Job |
|---|---|
| `ISASerialPortInternal.h` | `Port` / `Queue`, eleven externs, `Chip` row type, `_Chip` / `_msr_state_lut` declarations. No `@interface`. No `RX_enqueueLongEvent` body. |
| `ISASerialPortEnqueue.h` | `static RX_enqueueLongEvent` definition. Included only by TUs 1, 3, and 4. Name is ours. |
| `ISASerialPort.h` | Two ivars, `IODirectDevice` subclass, `PortDevices` conformance (TU 1). |
| `ISASerialPortFlow.c` | `flowMachine`, `watchState`. Finding 75 lock is the remaining algorithm work. |
| `ISASerialPortQueue.c` | `TX_enqueueEvent`, `RX_dequeueEvent`, `RX_dequeueData`, `validateRingBufferSize`, `freeRingBuffer`, `allocateRingBuffer`, plus its `static RX_enqueueLongEvent` copy. |
| `ISASerialPortChip.c` | `_Chip[9]`, `_msr_state_lut`, `identifyChip`, `initChip`, `programChip`. |
| `ISASerialPort.m` | Class methods and TU 1 locals. Must not keep chip, queue, or flow bodies after their extract. |
| lksproj `Makefile` | `CLASSES = ISASerialPort.m`. `CFILES` grows `ISASerialPortQueue.c` then `ISASerialPortChip.c`. `HFILES` adds `ISASerialPortEnqueue.h`. `.c` not `.m` so `__OBJC,__module_info` stays 32. |
| `Default.table` | Diff against the reference, ignore `"Driver Version"`. July already aligned keys; a residual blank line is the only allowed table edit. Do not invent Instance keys the reference file does not ship. |
| `Load_Commands.sect` | Already 164 bytes, SHA-256 `78FEAAD1…`. Do not retouch. |
| `reconstruction/` | `ledger.json` is status of record; `source-map.json` relines when a body moves; `divergences.md` holds findings and accepts; `function-worklist.md` is the ranked grind list. |
| `vm/build-i386-input-recon.sh` | Guest `gnumake RC_ARCHS=i386`, stage `_reloc` under `/build/out/i386/drvISASerialPort/`. |
| Guest sync | `vm/sync-src.ps1 -Path drivers-i386/input/drvISASerialPort` only. Never `-All`. |

`RX_enqueueLongEvent` is one `static` emitted three times (TUs 1, 3, 4), not
three implementations. Put the definition in `ISASerialPortEnqueue.h`, included only by
`ISASerialPort.m`, `ISASerialPortQueue.c`, and `ISASerialPortFlow.c` — not in
`ISASerialPortInternal.h`, because `ISASerialPortChip.c` must import `Port`
without emitting a fourth copy. Signature is `void (Port *, unsigned char
event, unsigned int data)`.

## 5. Data flow

Every source or makefile change in the open unit:

1. Edit only that unit's files, plus `ISASerialPortInternal.h` when a
   signature, `Chip` type, or `Port` field is required for the extract.
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/input/drvISASerialPort`.
3. Guest: `tr -d '\r' < vm/build-i386-input-recon.sh` then
   `sh vm/build-i386-input-recon.sh drvISASerialPort`. Copy
   `ISASerialPort_reloc` to host `out/i386/drvISASerialPort/` (gitignored).
4. Host: `parity_check.py` (report, not gate), nlist linkage for the eleven
   externs, section sizes vs the previous baseline, `load_source_map`,
   `binrecon function --list` / `--name` against `BINRECON_REFERENCE`.
   Python is `./.venv-binrecon/Scripts/python.exe` with
   `PYTHONPATH=tools/binrecon`.
5. Advance ledger one rung at a time
   (`unexamined` → `signature-confirmed` → `control-flow-confirmed` →
   `assembly-matched`). `assembly-matched` requires a current `_reloc`
   instruction-stream read. `unexamined` → `intentional-mismatch` is
   forbidden; go through `signature-confirmed` first.

This session runs every guest rebuild, including per-experiment ones.

### 5.1 TU 4 algorithm leftovers

`flowMachine` already takes `Port *` and uses `State & 0x40000000`. Shape-grind
it; do not rewrite the algorithm unless `--name` shows a real control-flow miss.

`watchState` still uses `IOEnterCriticalSection` / `IOExitCriticalSection` and
`continue` on the outer loop (Finding 75). Replace that with the reference's
`xchg` test-and-set, retrying the spin label, not the outer `do`. Returns
`-714` / `-703` already match. Cleanup already funnels all exits through
`WatchStateMask = 0` and `thread_wakeup_prim`. Include
`ISASerialPortEnqueue.h` from this file so TU 4 emits its unused
`RX_enqueueLongEvent` copy.

### 5.2 TU 3 algorithm leftovers

Extract verbatim except: drop `static` on the six exports, move
`RX_enqueueLongEvent` into `ISASerialPortEnqueue.h`, `#import
"ISASerialPortInternal.h"`. Then apply
Findings 53–65: `allocateRingBuffer` returns BOOL (1/0) not `IO_R_SUCCESS`;
`AllocSize` and `AllocBase` are distinct fields; `freeRingBuffer` frees
`AllocBase`/`AllocSize` and does not clear `Size`; `validateRingBufferSize`
takes `(requestedSize, Queue *)`; `TX_enqueueEvent` stores `(unsigned short)data`
in the second cell; `RX_dequeueData` returns `-702` not `-727`; hardware-flow
bit is `0x10`; flow-control tests are exclusive chains; `FlowControl` is 32-bit.

### 5.3 TU 2 algorithm leftovers

Write `_Chip` and `_msr_state_lut` as external non-`const` `__DATA,__data`
objects from §4.2 / §4.3. Rewrite `identifyChip` from Finding 43 (zero `call`
instructions, no `IODelay`; 0x80 returns index 4 immediately; 0xC0 runs rungs 6
and 7; rung 7's missing MCR write stays). `initChip` is `void`, seven field
inits, `Type == 0` early-out, no `IODelay`. `programChip` is `void`; parity
half-bit adjustment adds 2 when `TX_Parity == 1` else 4; FIFO trigger loop may
drive `n` negative; FCR switch is types 4–7 only; 64-bit helpers are implicit
`/` `%` on `unsigned long long`, not four-argument calls. Per-function size
gate: `identifyChip` rebuilt extent against the reference's 684 bytes.

### 5.4 TU 1 algorithm leftovers

Rename the ten underscored TU 1 locals. Conform to `PortDevices`. Read
configuration through `[[deviceDescription configTable] valueForStringKey:]`
with the reference key names (Finding 81). Dispatch timeout and
`getHandler:...` through `_Chip[Type].IntHandler`. Apply Findings 8–42 and
67–92 as written. Call sites of `__udivdi3` / `__umoddi3` become ordinary
64-bit arithmetic (Finding 95). Rewrite the helper bodies with 32-bit `div`
only so they do not recurse (Finding 94); then leave them unpaired.

`probe:` must not `[instance free]` after `registerDevice`. `executeEvent:data:`
must not discard `_executeEvent`'s return.

### 5.5 Shape-pass experiment lists

Source-shape only. Written into `function-worklist.md` when that unit's
algorithm pass closes, before the first shape rebuild. One item per rebuild.

Allowed: statement order, local vs expression, signedness of *locals*, loop
shape, `if` vs `else if` chains, operand-reversed `cmp`, declaration order of
existing locals.

Forbidden: padding ivars; reordering `Port` fields; unifying FIFO and NonFIFO
handlers; changing `_Chip` indices; "fixing" the Apple bugs in §2; repeating a
reverted experiment; inventing temporaries whose only purpose is to pick a
register after the list is already empty.

## 6. Error handling

| Failure | Response |
|---|---|
| Guest `gnumake` fails or produces no `_reloc` | Stop. Keep the log. Do not advance the unit or the ledger. |
| Guest unreachable | Host-only text (worklist notes) may continue. Nothing that claims `masked_equal` may. |
| `__OBJC,__module_info` grows past 32 | A `.m` slipped into `CFILES`. Undo the extract. |
| `instance_size` ≠ 604 after Phase 0 | Superclass still wrong. Fix before any TU work. |
| Experiment regresses a closed function | Revert before the next experiment. |
| Experiment does not improve, no regression | Revert, mark tried, continue the list. |
| List empty, still not equal | Accept with `--name` dump, reason, reviewer. |
| `__DATA,__bss` is 36 not 48 after TUs 2–4 exist | Record which hypothesis in `divergences.md` §4.4 won. Do not force a dummy `outb` in TU 4 to chase 48 unless TU 4 actually includes `ioPorts.h` in the reference's sense. Prefer matching the reference size if a real include produces it; do not invent a fourth unused static by hand. |
| `binrecon analyze` exits 1 | Expected for a reference-only profile. Gate is `complete: true`. |
| Stale `tools/binrecon/out/isaserialport/` | Never treat an older run as evidence for a new `_reloc`. |
| Another agent commits | Re-check `--list` against the current `_reloc` hash before claiming a unit closed. |

Linkage is the rebuilt nlist via `binrecon.macho.read_macho`, never IDA's
`binding` field and never `parity_check.py` name counts.

## 7. Testing

No QEMU boot, no COM1 traffic test, no hardware UART test.

**Phase 0.** Harness exists and `sh -n` is clean. Guest build exits 0 and
stages `ISASerialPort_reloc`. `instance_size` is 604. `Load_Commands.sect` in
the binary is 164 bytes. Worklist records the `--list` baseline.

**Per unit close.**

1. Guest build exits 0.
2. Eleven exported `__text` symbols are `external`. TU 1 C functions are
   `local`.
3. `parity_check.py`: a missing reference string or symbol is a finding; an
   extra unstripped symbol of ours is not.
4. `__OBJC,__instance_vars` = 28, `__OBJC,__module_info` = 32.
5. `load_source_map` prints `source map OK`.
6. Every paired function in this unit is `raw_equal`, `masked_equal`, or an
   exhausted-list accept.

**Campaign close.** Unpaired leftovers are only the four names in §1.
`Default.table` differs from the reference only in `"Driver Version"`.
`src/drivers-i386/README` input line for `drvISASerialPort` matches the sibling
wording: compiles; reconstructed against the reference binary, fixes applied,
not yet tested. Do not write `complete`.

## 8. Excluded

- QEMU, boot, and hardware testing
- Every other driver, `src/kernel-7`, `tools/binrecon` analyzer/comparator
  changes, `normalize.py`, re-enabling Ghidra
- Obtaining or cross-building an i386 `libcc.a`
- Hand-writing Kernel Server glue
- `Unload_Commands.sect`
- Byte identity of `__udivdi3` / `__umoddi3` against libgcc, and of
  `_VERS_STRING` / `_VERS_NUM` contents
- Changing Apple's recovered bugs listed in §2
- Syncing all of `src/` to the shared guest

## 9. Commit conventions

Messages start with `drvISASerialPort:` or `drivers-i386:` (harness and README),
one or two lines, no metadata trailers. Stage only this campaign's files.
Never commit reference binaries, rebuilt `_reloc` files, or
`tools/binrecon/out/`.
