# drvPS2Keyboard divergences

Reference: `PS2Keyboard_reloc`, SHA-256 `AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A`
Analyses: IDA 9.2, angr 9.3.0
Source tree: committed `HEAD` on `qemu-debug-loop`, working tree clean for
`src/drivers-i386/input/drvPS2Keyboard/**` at the start of this pass.

The report pass (Task 7) changed no driver source. **The fix pass (Task 8) resolved every finding
below**; each carries a `**Resolution (Task 8):**` line. Four further divergences the report pass
did not see are recorded as Findings 24-27.

## Line numbers: resolved in the fix pass

Task 8 rewrote both `.m` files and moved two functions between them, so every `source_line` in
`source-map.json` and `ledger.json` from the report pass is stale. Both artifacts were relined as
the fix pass's final step: the map was regenerated to scratch with `binrecon source-map`, its
bucket counts checked against the committed map (47 mapped / 2 unmapped / 0 duplicate_candidates /
0 boundary_disputed both times) and the address sets confirmed identical, then `source_line` and
`source_path` copied across by `address` into both files while the hand-resolved bucket
assignments were kept. All 47 mapped entries moved. `load_source_map` prints `source map OK`.

## Fix pass results

| | Baseline | After the fix |
| --- | --- | --- |
| build | `EXIT=0`, `fail=0` | `EXIT=0`, `fail=0` |
| staged `PS2Keyboard_reloc` | 167248 bytes | 157640 bytes |
| `missing_strings` | 2 | **0** |
| `missing_symbols` | 22 | **0** |
| `extra_strings` | 2 | **0** |
| `extra_symbols` | 97 | **54** |

The reference is 27441 bytes; ours is larger because the guest build is unstripped. The 54
remaining `extra_symbols` are stabs debugging entries and the two file-name symbols, all artefacts
of that; they are not findings.

`missing_symbols` was **22** at baseline, not the thirteen the brief expected, because
`parity_check.py` compares every `__TEXT,__text` symbol name including the locals: the eight
`static` helpers of Finding 5 and `__PS2KeyboardNumKeysDown` were missing for the same
underscore-depth reason as the thirteen externals.

**Every section but one now matches the reference byte for byte**, read back from the rebuilt
`_reloc` with `binrecon.macho.read_macho`:

| Section | Reference | Ours |
| --- | --- | --- |
| `__TEXT,__cstring` | 466 | 466 |
| `__DATA,__data` | 248 | 248 |
| `__DATA,__bss` | 96 | **96** (was 116) |
| `__DATA,__common` | 388 | 388 |
| `__OBJC,__class` | 160 | **160** (four classes, was eight with `NXLock`) |
| `__OBJC,__meta_class` | 160 | 160 |
| `__OBJC,__inst_meth` | 244 | 244 |
| `__OBJC,__cls_meth` | 104 | 104 |
| `__OBJC,__protocol` | 60 | 60 |
| `__OBJC,__class_names` | 202 | 202 |
| `__OBJC,__meth_var_types` | 242 | **242** (was 227) |
| `__OBJC,__meth_var_names` | 816 | 816 |
| `__OBJC,__instance_vars` | 140 | 140 |
| `__OBJC,__module_info` | 48 | 48 |
| `Loaded Server,Server Name` | 11 | 11 |
| `Loaded Server,Load Commands` | 164 | 164 |
| `Loaded Server,Unload Commands` | 102 | **102** (was absent) |
| `Loaded Server,Instance Var` | 20 | 20 |
| `Loaded Server,Server Version` | 1 | 1 |
| `__TEXT,__text` | 4952 | 4652 |
| `__TEXT,__const` | 170 | absent |

`__TEXT,__text` is 300 bytes short of the reference. That is codegen, not a listed divergence:
the two builds are different `cc` installations and the reference was compiled in March 1998.
`__TEXT,__const` holds `_PS2Keyboard_VERS_STRING` and `_PS2Keyboard_VERS_NUM`, emitted by NeXT's
`vers_string` machinery, which no driver in this repository produces — the same item
drvSerialPointingDevice recorded and did not fix.

**Symbol linkage was verified against the rebuilt nlist, not against parity counts**, because
`parity_check.py` compares names only. Reading `binding` and `section` from
`binrecon.macho.read_macho` for both binaries, **every symbol the reference defines now has the
same binding and the same section in ours** except four:

- `_PS2Keyboard_VERS_STRING` and `_PS2Keyboard_VERS_NUM` — the `vers_string` pair above.
- `_event.100` and `_extendCount.101` — ours are `_event.98` and `_extendCount.99`. The `.NNN`
  suffix is a GCC-assigned sequence number for a function-scope static, not a source property;
  the report pass already recorded that exact name parity on these is not achievable.

## `Loaded Server` sections: exact parity

Spec §2.7a. `Unload_Commands.sect` was created in the `.lksproj` directory with the reference's
102 bytes (copied from drvPS2Mouse's, which was verified against its own reference, and asserted
at 102 bytes on write) and added to that `Makefile`'s `OTHERSRCS`. `Load_Commands.sect` was
already present at 164 bytes and is byte-identical to drvPS2Mouse's. All five sections now match.

The rebuild also required `-DDRIVER_PRIVATE` in the `Makefile`'s `NEXTSTEP_PB_CFLAGS`, because
`PCKeyboardDefs.h` and `PCPointer.h` are both guarded by it — see Finding 24. drvPS2Mouse and
drvSerialPointingDevice carry the same flag for the same reason.

## Stated limitation: two analyzers, not three

**Ghidra is disabled in this driver's profile** (`tools/binrecon/profiles/ps2keyboard.json`,
`analyzers.ghidra.enabled: false`). With Ghidra enabled, normalization aborts with
`Ghidra relocation operand metadata is ambiguous`. That is a known binrecon limitation, approved
by the user, and not something this pass works around. The consequences for the evidence here:

- `tools/binrecon/out/ps2keyboard/published/` holds `analysis-reference-ida.json`,
  `analysis-reference-angr.json` and `consensus-reference.json`. There is **no**
  `analysis-reference-ghidra.json`.
- `run-summary.json`'s `analyzers` list has two entries, and every `analyzer_agreement.analyzers`
  in `ledger.json` reads `["IDA", "angr"]`.
- The analyzer-disagreement section below compares **IDA against angr only**. Every partition
  claim in this document rests on two analyzers, not three.

The analyze run was performed and verified by the controller; this pass confirmed the existing
state rather than re-running it. `run-summary.json` reports `complete: true` and
`reference_sha256` `AB413CA3…`, matching the brief. It exits 1 on this reference-only profile
because acceptance needs a rebuilt artifact; the gate is `complete: true`, never the exit code.

## Baseline build

The report pass established no baseline and did not build. **The fix pass established one before
any source edit** (`sh /build/source/vm/build-i386-input-recon.sh drvPS2Keyboard` on the Rhapsody
guest): `EXIT=0`, `fail=0`, staged `PS2Keyboard_reloc` 167248 bytes. That agrees with the plan's
table. The numbers after the fix are in the table above.

## Examination depth

All 49 reference functions were partitioned; **47 are mapped to source, 2 are build-generated
glue.** For every one of the 47 mapped functions the **complete IDA instruction listing was read**
— there is no function in this driver whose body was skimmed. The 19 jump-table case bodies of
`_scancodeToKeyEvent` were additionally verified programmatically by decoding
`jpt_E25` at `__TEXT,__text:3628` and reading each target's store, rather than by eye.

Ledger status in the report pass followed the convention that a function with a `divergences.md`
entry stays `unexamined` however carefully it was read.

**Ledger state after the fix pass (Task 8): 8 `assembly-matched`, 39 `control-flow-confirmed`,
2 `intentional-mismatch`, 0 `unexamined`.**

| Status | Count | Meaning here |
| --- | --- | --- |
| `assembly-matched` | 8 | full listing read instruction by instruction, no divergence found; unchanged by the fix except for call-site renames |
| `control-flow-confirmed` | 39 | carried at least one finding below; the fix pass repaired all of them |
| `intentional-mismatch` | 2 | build-generated Kernel Server glue, not present in source |

The 39 repaired functions are `control-flow-confirmed` rather than `assembly-matched` because
**the fix pass did not disassemble the rebuilt binary and compare it instruction by
instruction.** What it verified directly is the Objective-C metadata (class list, superclasses,
`instance_size`, every ivar name/offset/encoding, every method name and type encoding, and the
protocol conformance of both classes), the string set, every symbol's binding and section read
from the nlist, and every section size. No finding was accepted as an `intentional-mismatch`; the
only two entries carrying that status are the build-generated glue methods, unchanged from the
report pass.

The eight `assembly-matched` functions are `-[PS2Controller getHandler:level:argument:forInterrupt:]`
(1388), `-[PS2Controller setLEDs:]` (1472), `_clearOutputBuffer` (1960), `+[PS2Keyboard deviceStyle]`
(2404), `-[PS2Keyboard interfaceId]` (4340), `-[PS2Keyboard handlerId]` (4356),
`-[PS2Keyboard setAlphaLockFeedback:]` (4372) and `-[PS2Keyboard relinquishOwnership:]` (4632).

## Function partition: sizes

IDA's extents run 0–3 bytes under the symbol-to-symbol gap because the linker pads with `nop`.
Measured across all 49: 15 functions have no padding, 13 have 1 byte, 13 have 2 and 8 have 3.
This is normal and is **not** an analyzer disagreement. The brief's symbol-gap table was used to
identify functions, never to assert sizes.

## Analyzer disagreement: none on the partition

IDA and angr agree **exactly** on all 49 function start addresses and on all 49 sizes. There are
zero size disagreements and zero IDA-only addresses.

angr reports 120 functions to IDA's 49. The 71 extra entries are not a partition dispute:

- 69 are interior addresses of functions IDA had already delimited — branch targets and the
  instruction after a `retn` in the inter-function `nop` padding. Examples: 54 (inside
  `_lock_controller`), 2038 (inside `_sendControllerData`), 3907–4019 (the `_scancodeToKeyEvent`
  jump-table case bodies).
- 2 are not code at all: 5418 and 5578 are `_PS2Keyboard_VERS_STRING` and `_PS2Keyboard_VERS_NUM`
  in `__TEXT,__const`, which angr's recovery mistook for function starts.

angr also splits basic blocks more finely than IDA in 32 of the 49 functions while recording the
same call targets. **IDA is authoritative for the partition**, per the effort's convention, and
the disagreement is recorded rather than resolved.

## Configuration table

`PS2Keyboard.drvproj/Default.table` already matched the reference before Task 2 and is unchanged.

Its `"Driver Version"` line is a verbatim copy of Apple's build stamp:

```
"Driver Version" = "PROGRAM:PS2Keyboard  PROJECT:drvPS2Keyboard-11  DEVELOPER:root  BUILT:Sat Mar 28 22:03:53 PST 1998";
```

That line is **out of the comparison** and is deliberately left alone rather than widening the
diff — a rebuild cannot reproduce a 1998 timestamp, and rewriting it would only add noise.

**Correction to the brief.** The brief states drvPS2Keyboard is the only one of the five drivers
in this effort carrying such a stamp in checked-in source. That is not so:
`src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/Default.table` carries one too
(`BUILT:Sat Mar 28 22:08:58 PST 1998`). Of the five, **two** carry a verbatim stamp —
drvPS2Keyboard and Intel82365PCMCIA — and the other three (Intel824X0PCI, drvPS2Mouse,
drvSerialPointingDevice) do not. Both stamped tables are left alone on the same reasoning.

## Unmapped: build-generated

Two functions have no source and are expected to have none. Both are emitted by the Kernel Server
project type together with `Load_Commands.sect`:

- `+[PS2KeyboardKernelServerInstance kernelServerInstance]` (4928, 12 bytes), typed
  `^^{?}8@8:12`, returns `&_PS2Keyboard_instance` (`__DATA,__common:8920`).
- `+[PS2KeyboardVersion driverKitVersionForPS2Keyboard]` (4940, 12 bytes), typed `i8@8:12`,
  returns the DriverKit version 500.

Both stay `intentional-mismatch` in the ledger. `Load_Commands.sect` is present in
`PS2Keyboard.drvproj/PS2Keyboard.lksproj/`, is named in that directory's `Makefile` `OTHERSRCS`,
and is 164 bytes — matching the reference's `Loaded Server,Load Commands` section byte count of
164. No action needed there; `Unload_Commands.sect` was the gap, and Task 8 closed it.

## File boundary: confirmed, with two functions on the wrong side

The brief's link-order boundary is confirmed. Reference addresses 0–2404 are `PS2Controller`
material and 2404–4952 are `PS2Keyboard` material, and the boundary sits between
`_NewStealKeyboardEvent` (2320) and `+[PS2Keyboard deviceStyle]` (2404).

Of the 47 mapped functions, **45 sit on the side the boundary predicts.** All 25 functions the
map resolved automatically land correctly. Two do not — see Finding 18.

## Summary

| # | Finding | Where |
| --- | --- | --- |
| 1 | `PS2Controller` keeps its state in file-scope globals, not ivars | class + 9 functions |
| 2 | `becomeOwner:` and `desireOwnership:` return `int`, not `BOOL` | 4416, 4828 |
| 3 | `_ownerLock` is never initialized; there is no `NXLock` class | 2760, ownership trio |
| 4 | Thirteen C functions are spelled one underscore too deep, not fourteen | both files |
| 5 | Nine functions are `static` in the reference; `_exported_funcs` is not | both files |
| 6 | `_keyboardDataPresent` ignores the software queue and tests the wrong bits | 484 |
| 7 | `+[PS2Keyboard probe:]` passes a literal `0x910`, not `&_NewStealKeyboardEvent` | 2428 |
| 8 | `EscapeSequence` is 12 words with an inline sequence array | 756, 964, 1100 |
| 9 | `KeySequenceEntry` field 0 is the key count, not `next` — ours is 0 | data |
| 10 | The escape table has two entries, not four | data |
| 11 | `enqueueKeyEvent:` swaps the timestamp words and inverts `goingDown` | 3420 |
| 12 | The NumLock check reads `__kbdBitVector`, not a separate `_keyboardState` | 3520 |
| 13 | `initWithController:` performs no ownership or counter initialization | 2760 |
| 14 | Two `readConfigTable:` log strings differ; behaviour confirmed identical | 2588 |
| 15 | `_sendControllerCommand` does not record `_lastSent` | 2132 |
| 16 | The port counter is `lock inc` on `_xxx.86`; our `LOCK()` is empty | 2004, 2132 |
| 17 | `requiredProtocols` returns a list holding `PS2ControllerExported` | 2416, data |
| 18 | Two functions are in the wrong source file | 484, 2320 |
| 19 | `interruptOccurred` does not dispatch when the event queue is full | 2968 |
| 20 | `PS2Keyboard` ivar names differ and ours has one extra ivar | class |
| 21 | `dispatchKeyboardEvents` calls `bcopy` unconditionally on the else path | 3140 |
| 22 | Data symbols are spelled one-to-two underscores too deep, some misscoped | both files |
| 23 | The access-functions struct is tagged `controller_funcs` | 1428 |
| 24 | Both classes adopt a protocol; ours adopted none | class |
| 25 | The queue heads are 8 bytes, not a full `PS2QueueElement` | data |
| 26 | Ten more data symbols are one underscore too deep | both files |
| 27 | `_register_keyboard_entries` is called one underscore too deep | 2428 |

Findings 1, 2, 3, 8, 9 and 10 are structural and landed together. **All 27 are resolved by
source change; none was accepted as an intentional mismatch.**

---

## Finding 1: `PS2Controller` keeps its state in file-scope globals, not ivars

This is the largest finding in the driver and the form in which the drvPS2Mouse /
drvSerialPointingDevice structural pattern repeats here.

The superclass half of that pattern does **not** repeat. Both classes are parented exactly as our
source declares them:

| Class | Reference superclass | Our superclass | Verdict |
| --- | --- | --- | --- |
| `PS2Controller` | `IODirectDevice` | `IODirectDevice` | matches |
| `PS2Keyboard` | `IODevice` | `IODevice` | matches |

There is no `PCPointer` re-parent to do. The ivar half, however, diverges completely for
`PS2Controller`. From `__OBJC,__class` at 16624 and `__OBJC,__instance_vars` at 18612:

```
PS2Controller   super IODirectDevice   instance_size 308   ivar_count 3
   [296] portSet          'i'
   [300] mouseObject      '@'
   [304] pendingLEDVal    'i'
```

Our `PS2Controller.h:34-43` declares an entirely different set:

```objc
@interface PS2Controller : IODirectDevice
{
    id keyboardObject;
    BOOL manualDataHandling;
    PS2QueueElement keyboardFreeQueue;
    PS2QueueElement keyboardQueue;
    PS2QueueElement keyboardQueueElements[KEYBOARD_QUEUE_SIZE];
}
```

None of those five are ivars in the reference. All of them are **file-scope**, and the symbol
table names them directly:

| Reference symbol | Section | Binding | Address | Our source |
| --- | --- | --- | --- | --- |
| `_keyboardQueue` | `__DATA,__bss` | `local` | 8472 | ivar `keyboardQueue` |
| `_keyboardFreeQueue` | `__DATA,__bss` | `local` | 8480 | ivar `keyboardFreeQueue` |
| `_keyboardObject` | `__DATA,__bss` | `local` | 8488 | ivar `keyboardObject` |
| `_manualDataHandling` | `__DATA,__bss` | `local` | 8492 | ivar `manualDataHandling` |
| `_keyboardQueueElements` | `__DATA,__common` | **`external`** | 8536 (384 bytes) | ivar `keyboardQueueElements[32]` |

384 bytes is 32 elements of 12 bytes, matching `KEYBOARD_QUEUE_SIZE`.

**Four of the five are `static`; `_keyboardQueueElements` is not.** It is `external` in
`__DATA,__common`, which in C is a **non-static tentative definition** — a file-scope array
declared without `static` and without an initializer. Writing `static` would put it in `__bss`
as a `local`, which is the wrong section *and* the wrong binding. This correction was verified
against the reference's nlist directly and supersedes the "all five are file-scope statics"
reading.

Conversely the reference's three real ivars — `portSet`, `mouseObject` and `pendingLEDVal` — do
not exist in our source at all. `portSet` and `pendingLEDVal` are never read or written by any
function in the binary; they are declared and unused. `mouseObject` is likewise unused as an ivar,
because the mouse is tracked through the `__mouse` static instead.

The consequence shows up in nine functions, which reach the state as absolute addresses rather
than through `self`:

```
 732  -[PS2Controller interruptOccurred]        mov  eax, ds:_keyboardObject      ; 8488
1456  -[PS2Controller setKeyboardObject:]       mov  ds:_keyboardObject, eax      ; 8488
1552  -[PS2Controller setManualDataHandling:]   mov  ds:_manualDataHandling, al   ; 8492
1292  _interruptHandler                         cmp  ds:_manualDataHandling, 0    ; 8492
 484  _keyboardDataPresent                      cmp  ds:_keyboardQueue, offset _keyboardQueue
 576  _enqueueKeyboardData                      cmp  ds:_keyboardFreeQueue, offset _keyboardFreeQueue
1608  _getKeyboardData                          cmp  ds:_keyboardQueue, offset _keyboardQueue
 208  -[PS2Controller initFromDeviceDescription:] mov ds:_keyboardFreeQueue, offset _keyboardFreeQueue
1440  -[PS2Controller setMouseObject:]          mov  ds:__mouse, eax              ; 8460
```

Ours indexes off the receiver instead — for example `-[PS2Controller interruptOccurred]` at
`PS2Controller.m:271` sends to the ivar `keyboardObject`.

Because the state is global, three of our functions carry a `___controller` nil check that the
reference does not have and cannot need: `_enqueueKeyboardData` (`PS2Controller.m:477`),
`_getKeyboardData` (`PS2Controller.m:781`) and `interruptHandler` (`PS2Controller.m:535`). The
reference dereferences nothing and tests nothing.

**Task 8** must move all five members out of the `@interface` to file scope with the reference's
names and bindings, drop the three nil checks, and add the reference's three unused ivars so that
`instance_size` comes out at 308. Ours currently computes to roughly 712.

**Resolution (Task 8):** done. `@interface PS2Controller` now declares only `int portSet;`,
`id mouseObject;` and `int pendingLEDVal;`, and the rebuilt binary's `__OBJC,__class` reports
`PS2Controller : IODirectDevice  instance_size 308  ivar_count 3` with those three names at
offsets 296, 300 and 304 — identical to the reference. `keyboardQueue`, `keyboardFreeQueue`,
`keyboardObject` and `manualDataHandling` are file-scope `static` in `PS2Controller.m` and land
`local` in `__DATA,__bss`; `keyboardQueueElements` is a non-static tentative definition and lands
`external` in `__DATA,__common`. All five bindings and sections were read back from the rebuilt
nlist and match. The three `___controller` nil checks in `enqueueKeyboardData`, `getKeyboardData`
and `interruptHandler` are gone, as is the `___controller = self` store in
`initFromDeviceDescription:` that the reference does not have.

## Finding 2: `becomeOwner:` and `desireOwnership:` return `int`, not `BOOL`

The return-type polarity half of the drvPS2Mouse / drvSerialPointingDevice pattern **does** repeat,
on two of the three ownership methods.

Method type encodings from `__OBJC,__inst_meth` at 17048:

| Selector | Reference encoding | Reference return | Our declaration | Verdict |
| --- | --- | --- | --- | --- |
| `becomeOwner:` | `i12@8:12@16` | `int` | `- (BOOL)becomeOwner:` | **diverges** |
| `desireOwnership:` | `i12@8:12@16` | `int` | `- (BOOL)desireOwnership:` | **diverges** |
| `relinquishOwnership:` | `i12@8:12@16` | `int` | `- (int)relinquishOwnership:` | matches |

The disassembly confirms the values. `-[PS2Keyboard becomeOwner:]` keeps its result in `ebx` and
returns it unconverted:

```
4571: BB2BFDFFFF     mov      ebx, 0FFFFFD2Bh        ; -725
4598: 31DB           xor      ebx, ebx               ; 0 on success
4619: 89D8           mov      eax, ebx
```

`-[PS2Keyboard desireOwnership:]` is the same shape at 4878 / 4894 / 4915. There is no `setnz`,
no `test`/`sete`, and no truncation to a byte anywhere in either function.

So the reference's convention is **0 means success, -725 (`0xFFFFFD2B`) means failure**. Ours
inverts it: `PS2Keyboard.m:195` and `PS2Keyboard.m:218` both end `return (result == 0);`, which
yields **1 on success and 0 on failure**. A caller written against the reference and given our
driver reads success as failure and failure as success.

`relinquishOwnership:` already returns the raw `int` (`PS2Keyboard.m:254`) and needs no change.
Its internal logic matches the reference instruction for instruction; it is one of the eight
`assembly-matched` functions.

**Task 8** must change both declarations and both `return` statements, in `PS2Keyboard.h:44-45`
and `PS2Keyboard.m:157/198`. This must land together with Finding 1, because both change the
class's compiled shape.

One further signature divergence, on the same class:

| Selector | Reference | Ours |
| --- | --- | --- |
| `enqueueKeyEvent:goingDown:atTime:` | `v24@8:12i16c20Q24` | `v24@8:12I16c20Q24` |

The reference types `keyCode` as `int` (`i`); ours types it `unsigned int` (`I`). See Finding 11.

**Resolution (Task 8):** done, and the polarity change landed atomically with the signature
change. `becomeOwner:` and `desireOwnership:` are declared `- (IOReturn)` and now `return result;`
directly, so 0 means success and -725 means failure, matching the reference. `IOReturn` is
`typedef int`, so the encoding is `i`. `relinquishOwnership:` was likewise spelled `- (IOReturn)`
for consistency; its encoding is unchanged. `enqueueKeyEvent:goingDown:atTime:` now takes
`(int)keyCode`. Read back from the rebuilt `__OBJC,__inst_meth`, all four encodings are
byte-identical to the reference: `becomeOwner:`, `relinquishOwnership:` and `desireOwnership:` are
`i12@8:12@16` and `enqueueKeyEvent:goingDown:atTime:` is `v24@8:12i16c20Q24`. The `c12@8:12@16` on
`readConfigTable:` was left alone, as instructed — that one is a genuine `BOOL`.

## Finding 3: `_ownerLock` is never initialized, and there is no `NXLock` class

The reference's imports are exactly:

```
.objc_class_name_IODevice          .objc_class_name_IODirectDevice
.objc_class_name_Object            .objc_class_name_PS2Controller
.objc_class_name_PS2Keyboard       .objc_class_name_PS2KeyboardKernelServerInstance
.objc_class_name_PS2KeyboardVersion .objc_class_name_Protocol
```

There is **no `.objc_class_name_NXLock`**, and `__OBJC,__cls_refs` is zero bytes, so no class is
referenced by name anywhere in the binary.

That is not because the reference has no lock ivar. It has one:

```
PS2Keyboard   super IODevice   instance_size 548   ivar_count 8
   [536] _owner         '@'
   [540] _desiredOwner  '@'
   [544] _ownerLock     '@'
```

`_ownerLock` is object-typed and is messaged `lock` and `unlock` in all three ownership methods —
`becomeOwner:` at 4435 and 4607, `relinquishOwnership:` at 4651 and 4700, `desireOwnership:` at
4846 and 4903.

**But it is never assigned.** Every access to `+220h` across the whole binary is a load:

```
4435  mov edx, [esi+220h]     becomeOwner:
4607  mov esi, [esi+220h]     becomeOwner:
4651  mov edx, [ebx+220h]     relinquishOwnership:
4700  mov edx, [ebx+220h]     relinquishOwnership:
4846  mov edx, [esi+220h]     desireOwnership:
4903  mov esi, [esi+220h]     desireOwnership:
```

There is no store to `+220h` in any of the 49 functions, and `-[PS2Keyboard initWithController:]`
(2760) does not touch it. `alloc` zeroes the instance, so **`_ownerLock` is `nil` for the driver's
entire lifetime**, and `[nil lock]` / `[nil unlock]` are no-ops. The locking in Apple's shipped
driver is vestigial: the ivar and the messages are present, the mutual exclusion is not.

Our tree reaches the same net behaviour by a different and much heavier route. `NXLock.m` is a
stub whose methods do nothing:

```objc
@implementation NXLock
- lock { return self; }
- unlock { return self; }
@end
```

and `PS2Keyboard.m:111` really allocates one: `ownerLock = [[NXLock alloc] init];`.

**Disposition.** This is a different order of divergence from an extra local symbol, because
`NXLock.m` compiles four whole classes — `NXLock`, `NXConditionLock`, `NXSpinLock` and
`NXRecursiveLock` — into the driver. The reference's `__OBJC,__class` is 160 bytes, exactly four
40-byte class structures (`PS2Controller`, `PS2Keyboard`, `PS2KeyboardVersion`,
`PS2KeyboardKernelServerInstance`). Ours would emit eight, doubling that section, and would add
matching `__meta_class`, `__inst_meth`, `__class_names` and `__module_info` records. No amount of
symbol-name parity hides that.

The recommendation is therefore: **keep the `_ownerLock` ivar, drop the allocation, and drop
`NXLock` from the driver.** Renaming the ivar to `_ownerLock` (Finding 20) and deleting
`PS2Keyboard.m:111` reproduces the reference's behaviour exactly — a nil lock that swallows
`lock` and `unlock` — without compiling a single extra class. `NXLock.h`/`NXLock.m` would then
come out of `CLASSES`/`HFILES` in the `Makefile` and out of `PB.project`.

That is a judgement call about a file the build-repair effort added deliberately, so Task 8
should confirm it before removing anything. What is **not** a judgement call is that keeping the
allocation is wrong: with a real (if stubbed) object in `_ownerLock`, our binary's class list,
metaclass list and method lists all diverge from the reference's, and the ivar holds a non-nil
pointer where the reference holds nil.

**Resolution (Task 8):** the recommendation was confirmed and taken. The `_ownerLock` ivar stays
at offset 544 and is still messaged `lock` and `unlock` in all three ownership methods; the
`ownerLock = [[NXLock alloc] init];` line is gone, so the ivar is `nil` for the driver's whole
lifetime exactly as in the reference. `NXLock.m` and `NXLock.h` were deleted and removed from the
`Makefile`'s `CLASSES` and `HFILES` (`PB.project` never listed them). The rebuilt
`__OBJC,__class` is **160 bytes — four 40-byte class structures**, matching the reference; before
the fix it was eight classes. `__OBJC,__meta_class` is likewise 160. The compiler warns
"cannot find method" on `lock`/`unlock` now that no class declares them, which is expected: the
receiver is `id`, the message is compiled as an ordinary `objc_msgSend`, and both selectors
appear in `__OBJC,__message_refs` as they do in the reference.

## Finding 4: thirteen C functions are spelled one underscore too deep, not fourteen

Our source spells these functions with a leading underscore that the reference does not have.
The compiler adds one underscore, so a source name `_getKeyboardData` becomes the symbol
`__getKeyboardData`, one deeper than the reference's `_getKeyboardData`.

| Address | Reference symbol | Implied C name | Our source | Our symbol |
| --- | --- | --- | --- | --- |
| 484 | `_keyboardDataPresent` | `keyboardDataPresent` | `_keyboardDataPresent` | `__keyboardDataPresent` |
| 1608 | `_getKeyboardData` | `getKeyboardData` | `_getKeyboardData` | `__getKeyboardData` |
| 1768 | `_getKeyboardDataIfPresent` | `getKeyboardDataIfPresent` | `_getKeyboardDataIfPresent` | `__getKeyboardDataIfPresent` |
| 1824 | `_getMouseData` | `getMouseData` | `_getMouseData` | `__getMouseData` |
| 1892 | `_getMouseDataIfPresent` | `getMouseDataIfPresent` | `_getMouseDataIfPresent` | `__getMouseDataIfPresent` |
| 2004 | `_sendControllerData` | `sendControllerData` | `_sendControllerData` | `__sendControllerData` |
| 2084 | `_resendControllerData` | `resendControllerData` | `_resendControllerData` | `__resendControllerData` |
| 2132 | `_sendControllerCommand` | `sendControllerCommand` | `_sendControllerCommand` | `__sendControllerCommand` |
| 2208 | `_sendMouseCommand` | `sendMouseCommand` | `_sendMouseCommand` | `__sendMouseCommand` |
| 2264 | `_disableMouse` | `disableMouse` | `_disableMouse` | `__disableMouse` |
| 2292 | `_enableMouse` | `enableMouse` | `_enableMouse` | `__enableMouse` |
| 2320 | `_NewStealKeyboardEvent` | `NewStealKeyboardEvent` | `_NewStealKeyboardEvent` | `__NewStealKeyboardEvent` |
| 3520 | `_scancodeToKeyEvent` | `scancodeToKeyEvent` | `_scancodeToKeyEvent` | `__scancodeToKeyEvent` |

**Correction to the brief: that is thirteen, not fourteen.** The brief's table lists
`_clearOutputBuffer` (1960) as a fourteenth, but our source already spells it correctly —
`void clearOutputBuffer(void)` at `PS2Controller.m:376`, declared `void clearOutputBuffer(void);`
at `PS2Controller.h:108`. It is the one member of the group that already matches, which is why it
was the only one of the group the source map resolved automatically. It needs no rename.

**The fifteenth external symbol does need one, in the other direction.** `__PS2KeyboardNumKeysDown`
at 3364 implies the C name `_PS2KeyboardNumKeysDown`, with a genuine single leading underscore in
source. The brief says not to "fix" it, meaning do not strip that underscore to zero — but our
tree is not at one underscore, it is at two:

```
PS2Keyboard.m:447   int __PS2KeyboardNumKeysDown(void)      -> symbol ___PS2KeyboardNumKeysDown
PS2Controller.h:124 int __PS2KeyboardNumKeysDown(void);
PS2Controller.m:914 numKeysDown = __PS2KeyboardNumKeysDown();
```

So it is one underscore too deep like the other thirteen, and must be renamed to
`_PS2KeyboardNumKeysDown` — **to one underscore, not to zero.**

The same one-too-deep spelling also affects six functions that are `static` in the reference and
so do not appear in the fourteen-symbol group: `_lock_controller`, `_unlock_controller`,
`_reallyGetKeyboardData`, `_enqueueKeyboardData`, `_isEscape`, `_resetEscapes`, `_undoEscape` and
`_doEscape` (reference names `lock_controller`, `unlock_controller`, `reallyGetKeyboardData`,
`enqueueKeyboardData`, `isEscape`, `resetEscapes`, `undoEscape`, `doEscape`). `interruptHandler`
(1292) already matches.

Renames must be applied to the definitions, to the declarations in `PS2Controller.h:97-124` and
`PS2Keyboard.m:17-19`, to every call site, and to the `_exported_funcs` initializer at
`PS2Controller.m:130-139`.

**Resolution (Task 8):** all thirteen were renamed, together with the eight `static` helpers of
Finding 5 (`lock_controller`, `unlock_controller`, `reallyGetKeyboardData`, `enqueueKeyboardData`,
`isEscape`, `resetEscapes`, `undoEscape`, `doEscape`) which carry the same one-too-deep spelling
and which `parity_check.py` also reported missing. `__PS2KeyboardNumKeysDown` was renamed to
`_PS2KeyboardNumKeysDown` — **to one leading underscore, not zero** — so it emits the reference's
`__PS2KeyboardNumKeysDown`. `clearOutputBuffer` needed no change. Every declaration, call site and
`exported_funcs` initializer entry was updated; `missing_symbols` went from 22 to 0.

## Finding 5: nine functions are `static` in the reference; `_exported_funcs` is not

`parity_check.py` compares symbol **names** only, so a `static`-versus-`external` linkage
divergence is completely invisible to it. **Task 8 must verify every item in this finding by
reading the rebuilt binary's nlist directly — `nm` output or `read_macho`'s `binding` field — not
by parity counts.** A rebuild can show `missing_symbols` 0 and `extra_symbols` unchanged while
every linkage below is still wrong.

The reference's `__TEXT,__text` has exactly **15 external symbols**; every other text symbol is
`local`.

**Recorded analyzer disagreement.** IDA reports `_lock_controller` at address 0 as `global` and
counts 16 external `__TEXT,__text` symbols; angr reports it `local`. The two analyzers disagree,
and this document elsewhere says to trust the nlist rather than an analyzer's summary, so the
nlist was read directly with `binrecon.macho.read_macho`: `_lock_controller` is **`local`**, and
the external count is **15**. angr is right and IDA is the outlier. The table below and the fix
follow the nlist.

Ours declares nine of those locals with external linkage:

| Address | Symbol | Reference binding | Our storage class | Action |
| --- | --- | --- | --- | --- |
| 0 | `_lock_controller` | `local` | extern (`PS2Controller.m:301`) | add `static` |
| 56 | `_unlock_controller` | `local` | extern (`PS2Controller.m:334`) | add `static` |
| 524 | `_reallyGetKeyboardData` | `local` | extern (`PS2Controller.m:346`) | add `static` |
| 576 | `_enqueueKeyboardData` | `local` | extern (`PS2Controller.m:469`) | add `static` |
| 756 | `_isEscape` | `local` | extern (`PS2Controller.m:842`) | add `static` |
| 964 | `_resetEscapes` | `local` | extern (`PS2Controller.m:996`) | add `static` |
| 1020 | `_undoEscape` | `local` | extern (`PS2Controller.m:950`) | add `static` |
| 1100 | `_doEscape` | `local` | extern (`PS2Controller.m:400`) | add `static` |
| 1292 | `_interruptHandler` | `local` | extern (`PS2Controller.m:528`) | add `static` |

Adding `static` means the matching prototypes in `PS2Controller.h:97-121` must move into
`PS2Controller.m` above their first use, since a `static` function cannot be declared in a header
that other translation units include.

`_interruptHandler` deserves a note: it is taken by address in
`-[PS2Controller getHandler:level:argument:forInterrupt:]` (`mov dword ptr [eax], offset
_interruptHandler` at 1400), which is exactly why it can be `static` and still reach the kernel.

**One divergence runs the other way.** `_exported_funcs` at `__DATA,__data:8192` is **external**
in the reference, but `PS2Controller.m:130` declares it `static PS2ControllerFunctions
_exported_funcs`. That `static` must be removed. It is the only data symbol in the driver whose
linkage is too narrow rather than too wide — apart from `_keyboardQueueElements`, whose common
binding is covered by Finding 1.

**Resolution (Task 8):** all nine helpers are now `static` and their prototypes moved out of
`PS2Controller.h` into a forward-declaration block at the top of `PS2Controller.m`, above their
first use. `exported_funcs` lost its `static`. `interruptHandler` is still taken by address in
`-[PS2Controller getHandler:level:argument:forInterrupt:]`, which is exactly why it can be
`static` and still reach the kernel.

**Verified from the rebuilt nlist, not from parity counts.** Reading `binding` and `section` per
symbol from `binrecon.macho.read_macho`, all nine are `local` in `__TEXT,__text` and
`_exported_funcs` is `external` in `__DATA,__data`, each identical to the reference:

| Symbol | Reference | Ours |
| --- | --- | --- |
| `_lock_controller` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_unlock_controller` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_reallyGetKeyboardData` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_enqueueKeyboardData` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_isEscape` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_resetEscapes` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_undoEscape` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_doEscape` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_interruptHandler` | `local` / `__TEXT,__text` | `local` / `__TEXT,__text` |
| `_exported_funcs` | `external` / `__DATA,__data` | `external` / `__DATA,__data` |

The fifteen external `__TEXT,__text` symbols also all came out `external` in ours, and
`_keyboardQueueElements` came out `external` in `__DATA,__common`.

## Finding 6: `_keyboardDataPresent` ignores the software queue and tests the wrong bits

`_keyboardDataPresent` (484, 37 bytes) is 11 instructions and diverges from ours in both branches.

```
 484: 55             push ebp
 485: 89E5           mov  ebp, esp
 487: 813D...        cmp  ds:_keyboardQueue, offset _keyboardQueue
 497: 750D           jnz  loc_200                 ; queue non-empty -> return 1
 499: BA64000000     mov  edx, 64h
 504: EC             in   al, dx
 505: 83E001         and  eax, 1
 508: 89EC           mov  esp, ebp
 510: 5D             pop  ebp
 511: C3             retn
 512: B801000000     mov  eax, 1                  ; loc_200
 517: 89EC           mov  esp, ebp
 519: 5D             pop  ebp
 520: C3             retn
```

The reference answers **"is there a byte for the keyboard to read"** in two steps: if the software
queue `_keyboardQueue` is not empty (its head does not point at itself), return 1 immediately
without touching the hardware; otherwise read the status register at 0x64 and return bit 0.

Ours (`PS2Keyboard.m:475-485`) does neither correctly:

```c
BOOL _keyboardDataPresent(void)
{
    /* TODO: Implement from decompiled code */
    unsigned char status = inb(0x64);
    return ((status & 0x01) != 0 && (status & 0x20) == 0);
}
```

Two defects, and the `TODO` comment marks it as knowingly unfinished:

1. **The queue is never consulted.** `_enqueueKeyboardData` (576) is the only place interrupt-time
   bytes are parked, and `_getKeyboardData` (1608) drains that queue in preference to the
   hardware. With our version, a byte sitting in `_keyboardQueue` while the hardware buffer is
   empty reports "no data present", so `-[PS2Keyboard interruptOccurred]`'s
   `while (_keyboardDataPresent())` loop exits and the queued scancode is never delivered. Keys
   pressed during an escape-sequence undo (Finding 8) are exactly the bytes that get parked there.
2. **Bit 5 is tested and must not be.** Ours additionally requires `(status & 0x20) == 0`. The
   reference masks with `1` only. Testing the auxiliary-device bit here makes the function
   silently report "no keyboard data" whenever the controller happens to have mouse data pending,
   which is the job of `_getMouseDataIfPresent` (1892), not this function.

Both callers are affected: `-[PS2Keyboard interruptOccurred]` (2976) and
`_getKeyboardDataIfPresent` (1780).

**Resolution (Task 8):** rewritten to the reference's two steps, and the `TODO` is gone:

```c
BOOL keyboardDataPresent(void)
{
    if (keyboardQueue.next != KBD_QUEUE) {
        return 1;
    }

    return (inb(PS2_STATUS_PORT) & 0x01);
}
```

The software queue is consulted first and the `& 0x20` auxiliary-device test is removed. The
function also moved to `PS2Controller.m` (Finding 18), which is what lets it see `keyboardQueue`.

## Finding 7: `+[PS2Keyboard probe:]` passes a literal `0x910`, not `&_NewStealKeyboardEvent`

The reference builds a two-word structure on the stack and hands it to
`_register_keyboard_entries`:

```
2552: C745F800000000  mov  [ebp+var_8], 0
2559: C745FC10090000  mov  [ebp+var_4], offset _NewStealKeyboardEvent
2566: 8D45F8          lea  eax, [ebp+var_8]
2569: 50              push eax
2570: E8F1F5FFFF      call _register_keyboard_entries
```

The second word is a **relocated function pointer** to `_NewStealKeyboardEvent`, whose address
happens to be 2320 — that is, `0x910`. Our source at `PS2Keyboard.m:83-86` took the resolved
address for a numeric constant:

```c
keyboardEntries[0] = 0;
keyboardEntries[1] = 0x910;  /* 2320 decimal */
_register_keyboard_entries(keyboardEntries);
```

The comment `/* 2320 decimal */` records the confusion exactly. As written, our driver hands the
kernel's keyboard layer the integer 2320 as a callback address. In a rebuilt binary
`_NewStealKeyboardEvent` will not be at 2320, and even if it were, a hard-coded address defeats
relocation. The kernel would call into whatever sits at offset 2320 the first time it tried to
steal a keyboard event — in practice, the middle of `_NewStealKeyboardEvent`'s neighbour.

`keyboardEntries` must be typed to hold a function pointer, and the second slot must be
`&NewStealKeyboardEvent` (post-rename, per Finding 4).

This also explains why `_NewStealKeyboardEvent` is external in the reference despite having no
other caller in the driver: its address is published to the kernel here, and the kernel resolves
it by name through `Load_Commands.sect`.

**Resolution (Task 8):** the literal is gone. `keyboardEntries` is now `void *[2]`, slot 0 is
`NULL` (the kernel's `keyboard_reboot` slot) and slot 1 is `(void *)NewStealKeyboardEvent`, so
the linker emits a relocation instead of a constant. `<bsd/dev/i386/kbd_entries.h>` names the
target structure `struct keyboard_entries { int (*keyboard_reboot)(); int
(*steal_keyboard_event)(); }`, which confirms the two-slot shape and which slot is which; the
header itself is `KERNEL_PRIVATE`-guarded and so contributes no declaration to this build. See
also Finding 27 for the callee's name.

## Finding 8: `EscapeSequence` is 12 words with an inline sequence array

Our `EscapeSequence` (`PS2Controller.h:74-94`) declares 19 pointer-sized fields — 76 bytes. The
reference's structure is **48 bytes, 12 words**, and the disassembly pins every field.

Stride, from both loops that walk the table:

```
1007  _resetEscapes    83C230          add edx, 30h        ; 48
1270  _doEscape        83C330          add ebx, 30h        ; 48
```

Field offsets, from `_doEscape`'s callback invocation at 1185-1200 and `_isEscape`'s state
accesses:

| Byte offset | Word | Field | Evidence |
| --- | --- | --- | --- |
| 0–20 | 0–5 | inline array of up to 6 `KeySequenceEntry *`, NULL-terminated | `_isEscape` 796-830 walks `[ebp+var_4]` from `escape` upward in steps of 4 |
| 24 | 6 | `callback` | `1197: mov eax, [ebx+18h]` then `1200: call eax` |
| 28 | 7 | `arg1` | `1193: mov ecx, [ebx+1Ch]` (pushed last, so first parameter) |
| 32 | 8 | `arg2` | `1189: mov ecx, [ebx+20h]` |
| 36 | 9 | `arg3` | `1185: mov ecx, [ebx+24h]` |
| 40 | 10 | `currentSequence` | `768: cmp dword ptr [esi+28h], 0` |
| 44 | 11 | `field11` (matched sequence) | `920: mov [esi+2Ch], ebx` |

Two things follow that our source gets wrong.

**The sequence array is inline, not a pointer.** Our field 0 is `KeySequenceEntry **sequences`, a
pointer to a separate array. The reference stores the sequence pointers directly in words 0–5 of
the escape entry. `_isEscape` at 774 copies `esi` (the escape pointer itself) into the cursor and
then walks it:

```
 774: 8975FC   mov  [ebp+var_4], esi        ; cursor = escape, not *escape
 777: 833E00   cmp  dword ptr [esi], 0      ; first slot
 796: 8B4DFC   mov  ecx, [ebp+var_4]
 799: 8B19     mov  ebx, [ecx]              ; one dereference, not two
 826: 8345FC04 add  [ebp+var_4], 4          ; next slot, in place
```

Our `PS2Controller.m:864` reads `sequenceArray = escape->sequences;` — one dereference too many.

**The loop terminator is the `callback` field, not a separate `terminator`.** Both walkers guard
on byte offset 24:

```
 972  _resetEscapes  cmp ds:off_2078, 0     ; 8312 = _escapes + 24
1010  _resetEscapes  cmp dword ptr [edx+18h], 0
1240  _doEscape      cmp ds:off_2078, 0
1273  _doEscape      cmp dword ptr [ebx+18h], 0
```

Word 6 is `callback`. A table entry with a NULL callback ends the table. Our source instead
declares a `terminator` at word 18 and tests `escapePtr[0x12]` (`PS2Controller.m:1011-1030`) —
which, with a 12-word stride, reads 24 bytes into the **following** entry. Our own file is
internally inconsistent here: `_resetEscapes` strides by `0xc` words (48 bytes, correct) while
indexing a field at word 18 that lies outside a 48-byte entry.

Our fields `field1`–`field5` are the remaining five inline sequence slots, and `field12`–`field17`
plus `terminator` do not exist at all.

**Resolution (Task 8):** `EscapeSequence` is now 48 bytes:

```c
typedef struct _EscapeSequence {
    KeySequenceEntry *sequences[6];     /* Words 0-5: NULL-terminated */
    EscapeCallback callback;            /* Word 6: also the table terminator */
    void *arg1;                         /* Word 7 */
    void *arg2;                         /* Word 8 */
    void *arg3;                         /* Word 9 */
    KeySequenceEntry *currentSequence;  /* Word 10 */
    KeySequenceEntry *matchedSequence;  /* Word 11 */
} EscapeSequence;
```

`isEscape` walks `escape->sequences` in place with a single dereference, and both `doEscape` and
`resetEscapes` terminate on `escapePtr->callback != NULL` rather than on a nonexistent word-18
terminator. `doEscape` no longer guards the callback with a NULL test, because the loop condition
already guarantees it is non-NULL — matching the unconditional `call eax` at 1200. The
`escape == NULL` guards at the top of `isEscape` and `undoEscape`, and the `data == NULL` guard in
`getMouseDataIfPresent`, were removed as the "observations that are not findings" section asks.
The rebuilt `__DATA,__data` is 248 bytes, matching the reference exactly.

## Finding 9: `KeySequenceEntry` field 0 is the key count, not `next`

The four sequence tables are 16 bytes each and are plain data, with no relocations:

```
8224 _lalt_ralt_numlock   3  0   38 00 38 01   45 00 00 00
8240 _ralt_lalt_numlock   3  0   38 01 38 00   45 00 00 00
8256 _lalt_numlock        2  0   38 00 45 00   00 00 00 00
8272 _ralt_numlock        2  0   38 01 45 00   00 00 00 00
```

The layout is `{ int count; int index; unsigned char keys[8]; }`. Word 0 holds **3, 3, 2, 2** —
the number of key pairs in each sequence, matching the `(scancode, extended)` pairs that follow:
`_lalt_ralt_numlock` is Left Alt, Right Alt, Num Lock; `_lalt_numlock` is Left Alt, Num Lock.

`_isEscape` reads word 0 as the length and compares it against the running index:

```
874: FF4304   inc dword ptr [ebx+4]     ; index++
877: 8B4304   mov eax, [ebx+4]
880: 3903     cmp [ebx], eax            ; count vs index
882: 7F42     jg  loc_3B6               ; still short -> not complete
905: 8B03     mov eax, [ebx]
907: 48       dec eax                   ; count - 1
908: 39C2     cmp edx, eax              ; vs __PS2KeyboardNumKeysDown()
```

`_undoEscape` reads it the same way at 1037 (`cmp [esi], ebx`).

Our header declares word 0 as `void *next` (`PS2Controller.h:68`), and although our `_isEscape`
does read it as a length (`PS2Controller.m:904`, `sequenceLength = *(int *)((unsigned char *)currentSeq + 0)`),
**our initializers set it to `NULL`** — `PS2Controller.m:47`, `60`, `73`, `87` all begin
`NULL,  /* next */`.

Every sequence therefore has length 0 in our build. Trace the consequence: on the first matching
key, `index` becomes 1, `cmp [ebx], eax` compares 0 against 1, `jg` is not taken, so the sequence
is declared complete immediately; then `count - 1` is `-1`, which
`__PS2KeyboardNumKeysDown()` can never equal, so `_isEscape` returns 0. **No escape sequence can
ever fire**, and the mini-monitor hotkeys are dead.

The fix is to rename the field to `count` and set it to 2 or 3 to match each table.

**Resolution (Task 8):** field 0 is now `int count`, and the four initializers carry 3, 3, 2 and 2
to match the reference's tables byte for byte. This was a live bug, not parity drift: with
`count == 0` no escape sequence could ever fire and the mini-monitor hotkeys were dead. The four
`_..._seq` structures and the four two-element pointer arrays that pointed at them are gone; the
four 16-byte structures now carry the names the reference gives them (`lalt_ralt_numlock`,
`ralt_lalt_numlock`, `lalt_numlock`, `ralt_numlock`), declared in the reference's data order.

## Finding 10: the escape table has two entries, not four

`_escapes` at `__DATA,__data:8288` is **144 bytes** — three 48-byte entries, of which the third is
all zeros and terminates the table. So the reference defines **two** escape sequences:

| Entry | Inline sequences (words 0–5) | callback | arg1 | arg2 | arg3 |
| --- | --- | --- | --- | --- | --- |
| 0 @8288 | `_lalt_numlock`, `_ralt_numlock` | `_mini_mon` | `"restart"` | `"Restart"` | NULL |
| 1 @8336 | `_lalt_ralt_numlock`, `_ralt_lalt_numlock` | `_mini_mon` | `""` | `"Mini-Monitor"` | NULL |
| 2 @8384 | all zero — terminator | | | | |

Each entry groups **two alternative key sequences** that trigger the same action, which is what
the inline six-slot array in Finding 8 is for.

Our `PS2Controller.m:102-126` declares **five** entries — four singles plus a terminator — at 76
bytes each, 380 bytes total, and distributes the arguments differently:

| Ours | Sequence | callback | arg1 | arg2 | arg3 |
| --- | --- | --- | --- | --- | --- |
| 0 | `_lalt_numlock` | `mini_mon` | `"restart"` | NULL | NULL |
| 1 | `_ralt_numlock` | `mini_mon` | `"Restart"` | NULL | NULL |
| 2 | `_lalt_ralt_numlock` | `mini_mon` | NULL | NULL | NULL |
| 3 | `_ralt_lalt_numlock` | `mini_mon` | `""` | `""` | `"Mini-Monitor"` |

So Left Alt + Num Lock and Right Alt + Num Lock are two separate entries for us and one grouped
entry for the reference; the `"Restart"` string moves from arg1 of entry 1 to arg2 of entry 0; and
entry 3's three arguments `("", "", "Mini-Monitor")` become entry 1's `("", "Mini-Monitor", NULL)`.

The argument order is fixed by the call sequence at 1185-1200, which pushes word 9 first and word
7 last, so word 7 (`arg1`) is `mini_mon`'s first parameter.

There is also a `KeySequenceEntry` indirection to remove: our source declares four
`_..._seq` structures and four two-element pointer arrays that point at them
(`PS2Controller.m:46-97`). The reference has only the four 16-byte structures, named
`_lalt_ralt_numlock`, `_ralt_lalt_numlock`, `_lalt_numlock` and `_ralt_numlock` — the names our
source gives to the *arrays*. There are no `_..._seq` symbols in the reference at all.

**Resolution (Task 8):** `escapes` now has exactly three entries — two live plus an all-zero
terminator — grouping `lalt_numlock`/`ralt_numlock` under `("restart", "Restart", NULL)` and
`lalt_ralt_numlock`/`ralt_lalt_numlock` under `("", "Mini-Monitor", NULL)`, in the reference's
argument order. The rebuilt `_escapes` is 144 bytes and `__DATA,__data` totals 248, both matching
the reference.

## Finding 11: `enqueueKeyEvent:` swaps the timestamp words and inverts `goingDown`

`-[PS2Keyboard enqueueKeyEvent:goingDown:atTime:]` (3420) stores four words into the event slot:

```
3450: 8B5518  mov edx, dword ptr [ebp+arg_10]      ; timestamp low
3453: 8955F0  mov [ebp+var_10], edx
3456: 8B551C  mov edx, dword ptr [ebp+arg_10+4]    ; timestamp high
3459: 8955F4  mov [ebp+var_C], edx
...
3473: 8B4DF0  mov ecx, [ebp+var_10]
3476: 898A10010000  mov [edx+110h], ecx            ; slot +0  <- LOW word
3482: 8B4DF4  mov ecx, [ebp+var_C]
3485: 898A14010000  mov [edx+114h], ecx            ; slot +4  <- HIGH word
3491: 8B4DF8  mov ecx, [ebp+var_8]
3494: 898A18010000  mov [edx+118h], ecx            ; slot +8  <- keyCode
3500: 8B4DFC  mov ecx, [ebp+var_4]
3503: 898A1C010000  mov [edx+11Ch], ecx            ; slot +12 <- goingDown
```

This is a plain little-endian 64-bit store, consistent with the ivar encoding
`[16{?="timeStamp"Q"keyCode"I"goingDown"c}]` — the element type is
`{ unsigned long long timeStamp; unsigned int keyCode; char goingDown; }`, padded to 16 bytes.

Two divergences against `PS2Keyboard.m:345-370`.

**The timestamp words are swapped.** Our `PS2KeyboardEvent` (`PS2Keyboard.h:13-18`) declares
`timestamp_high` first and `timestamp_low` second, and `PS2Keyboard.m:361-362` assigns to match:

```c
eventQueue[index].timestamp_high = (unsigned int)(timestamp >> 32);
eventQueue[index].timestamp_low  = (unsigned int)(timestamp & 0xFFFFFFFF);
```

Our slot +0 therefore receives the **high** word where the reference puts the **low** word. Any
consumer reading the 16-byte record as a `ns_time_t` gets the two halves transposed — timestamps
off by a factor of 2^32. The cleanest fix is to declare the field as a single
`unsigned long long timeStamp` and assign it directly, which also matches the ivar encoding.

**`goingDown` is inverted.** The reference copies the parameter byte straight through: `dl` is
loaded from `arg_C` at 3429, parked in `var_4` at 3447, and stored unmodified at 3503. Ours
computes the opposite at `PS2Keyboard.m:358`:

```c
flags = goingDown ? 0 : 1;  /* 0 = key down, 1 = key up */
```

The reference's fourth word is 1 when the key is going down; ours is 0. The field is named
`goingDown` in the reference's ivar encoding and `flags` in ours, and the comment records the
inverted intent explicitly. Every key-down event our driver enqueues is delivered as a key-up.

Also, per Finding 2, the `keyCode` parameter is `int` in the reference and `unsigned int` in ours.

**Resolution (Task 8):** `PS2KeyboardEvent` is now

```c
typedef struct {
    ns_time_t timeStamp;
    unsigned int keyCode;
    BOOL goingDown;
} PS2KeyboardEvent;
```

so the timestamp is a single 64-bit store — low word first, exactly as the reference does — and
the transposition is gone. `enqueueKeyEvent:` now copies `goingDown` straight through instead of
computing `goingDown ? 0 : 1`, so a key-down event is delivered as a key-down. This too was a live
bug rather than parity drift. The rebuilt ivar encoding reads
`[16{?="timeStamp"Q"keyCode"I"goingDown"c}]`, byte-identical to the reference, which confirms both
the member names and the anonymous-typedef spelling (a tagged struct would have encoded its tag).
`<bsd/dev/i386/PCKeyboardDefs.h>` declares the identical layout as `PCKeyboardEvent`, which is
independent confirmation of the field types.

## Finding 12: the NumLock check reads `__kbdBitVector`, not a separate `_keyboardState`

`_scancodeToKeyEvent` special-cases keycode 0x6F:

```
4186: 833D3C2100006F  cmp  ds:dword_213C, 6Fh          ; _event.keyCode == 0x6F
4193: 7510            jnz  loc_1073
4195: F6055521000080  test ds:byte_2155, 80h           ; 8533
4202: 0F94C0          setz al
4205: 880540210000    mov  ds:byte_2140, al            ; _event.flags
```

Address 8533 falls inside `__kbdBitVector`, which runs 8520–8536. The offset is 13 bytes, and bit
7 of byte 13 is bit **111** of the vector — which is 0x6F, the Num Lock keycode itself. So the
reference is asking "is Num Lock already recorded as down in the key bitmap", and inverting it.

Ours (`PS2Keyboard.m:560-563`) reaches into a different array entirely:

```c
if (keyCode == 0x6F) {
    isKeyDown = (_keyboardState[0x18] & 0x80) == 0;
}
```

`_keyboardState` is a 32-byte file-scope array declared at `PS2Keyboard.m:40` with the comment
"appears to be at a higher offset". It has **no counterpart in the reference's symbol table** —
it is an artifact of the original reconstruction, and it is never written anywhere in our source,
so it stays zero and the test always yields `isKeyDown = 1`.

The correct expression indexes the existing bit vector, and `_keyboardState` should be deleted.

**Resolution (Task 8):** the test now reads the bit vector, and `_keyboardState` is deleted:

```c
isKeyDown = (_kbdBitVector[0x6F >> 5] & (1 << (0x6F & 0x1F))) == 0;
```

`0x6F >> 5` is word 3 and `0x6F & 0x1F` is bit 15, which is byte 13 bit 7 of the vector — the
`test ds:byte_2155, 80h` at 4195.

Everything else in this 818-byte function matches. In particular the extended-scancode
translation is exact: the jump table at `__TEXT,__text:3628` was decoded and all **19** cases map
scancode to keycode identically to `PS2Keyboard.m:519-541`, with no case present in one and absent
in the other:

```
1C->62  1D->60  35->63  37->6E  38->61  45->6F  47->6C  48->64  49->6A  4B->66
4D->67  4F->6D  50->65  51->6B  52->68  53->69  5B->70  5C->71  5D->72
```

The 0xE0 and 0xE1 prefix handling, the `_extendCount` countdown, the `(scancode >> 7) ^ 1`
key-direction computation, the already-down auto-repeat rejection and the bit set/clear (the
reference clears with `mov eax, 0FFFFFFFEh; rol eax, cl; and`, equivalent to `& ~(1 << n)`) all
match instruction for instruction.

## Finding 13: `initWithController:` performs no ownership or counter initialization

`-[PS2Keyboard initWithController:]` (2760, 208 bytes) goes straight from storing the controller
to clearing the output buffer:

```
2797: call _objc_msgSendSuper            ; [super init]
2802: 899E08010000  mov [esi+108h], ebx  ; controller = arg
2808: call _clearOutputBuffer
```

Ours inserts six assignments in between (`PS2Keyboard.m:110-120`):

```c
ownerLock = [[NXLock alloc] init];
keyboardOwner = nil;
desiredOwner = nil;
eventCount = 0;
interfaceID = 0;
handlerID = 0;
```

None of these appear in the reference, which relies on `alloc` having zeroed the instance. The
`ownerLock` allocation is the substantive one and is covered by Finding 3; the other five are
redundant stores that add instructions without changing behaviour, and should come out for parity.

The rest of the method matches: `clearOutputBuffer()`, `_sendControllerCommand(0x20)`,
`_getKeyboardData()`, the command-byte edit, `_sendControllerCommand(0x60)`,
`_sendControllerData(...)`, `[controller setKeyboardObject:self]`,
`[self setAlphaLockFeedback:NO]`, `[self setUnit:0]`, `[self setName:"PCKeyboard0"]`,
`[self setDeviceKind:"PS2Keyboard"]`, `[self registerDevice]`, `return self`.

**Resolution (Task 8):** all six assignments are gone. `initWithController:` now goes straight
from `controller = controllerInstance;` to `clearOutputBuffer();`, relying on `alloc` having
zeroed the instance as the reference does.

## Finding 14: two `readConfigTable:` log strings differ; the behaviour is confirmed identical

| Reference | Ours (`PS2Keyboard.m:389`, `:403`) |
| --- | --- |
| `PS2Keyboard kbdInit: no Interface ID; use default\n` | `PS2Keyboard kbdInit: no Interface key in config table\n` |
| `PS2Keyboard kbdInit: no Handler ID; use default\n` | `PS2Keyboard kbdInit: no Handler ID key in config table\n` |

The brief flags "use default" as a behavioural claim rather than wording, so it was checked
against `-[PS2Keyboard readConfigTable:]` (2588, 170 bytes). **The driver does continue**, in both
cases:

```
2645: 682F140000  push offset aPs2keyboardKbd_0    ; 'no Interface ID; use default'
2650: E8A1F5FFFF  call _IOLog
2655: C7861002000003000000  mov dword ptr [esi+210h], 3   ; interfaceId = 3
2665: EB0D        jmp  loc_A78                     ; fall through to the Handler ID read

2708: 686D140000  push offset aPs2keyboardKbd_1    ; 'no Handler ID; use default'
2713: E862F5FFFF  call _IOLog
2718: C7861402000000000000  mov dword ptr [esi+214h], 0   ; handlerId = 0
2728: EB0E        jmp  loc_AB8
2744: B801000000  mov  eax, 1                      ; return YES
```

Neither branch returns early; both install a default (3 for Interface, 0 for Handler ID) and carry
on to `return YES` at 2744. Our source does exactly the same thing (`PS2Keyboard.m:390`, `:404`,
`:413`), so **only the wording differs** — the behavioural claim is satisfied and no logic change
is needed. The one genuinely early return is the `configTable == nil` case at 2603-2615, which
logs `PS2Keyboard kbdInit: no configuration table\n` (matching ours) and returns 0.

The ivar offsets confirm the class layout: `+210h` is 528 (`interfaceId`) and `+214h` is 532
(`handlerId`).

**Resolution (Task 8):** both strings are set to the reference's exact text and `missing_strings`
dropped to 0 (`extra_strings` likewise, since the old wordings are gone). No logic changed, as the
behavioural check already showed none was needed.

## Finding 15: `_sendControllerCommand` does not record `_lastSent`

`_sendControllerData` (2004) records the byte it sent; `_sendControllerCommand` (2132) does not.

```
_sendControllerData @2004
  2050: BA60000000    mov  edx, 60h
  2055: 88D8          mov  al, bl
  2057: EE            out  dx, al
  2058: F0FF05F8200000 lock inc ds:_xxx.86
  2065: 881D10210000  mov  ds:_lastSent, bl        <- present
  2071: call _unlock_controller

_sendControllerCommand @2132
  2178: BA64000000    mov  edx, 64h
  2183: 88D8          mov  al, bl
  2185: EE            out  dx, al
  2186: F0FF05F8200000 lock inc ds:_xxx.86
  2193: call _unlock_controller                    <- no _lastSent store
```

Our `PS2Controller.m:600` adds one to the command path:

```c
    /* Track the last byte sent */
    _lastSent = command;
```

That line must go. It is not cosmetic: `_lastSent` is what `_resendControllerData` (2084) replays
when the keyboard asks for a resend. In the reference only *data* bytes are replayable, which is
correct for the PS/2 protocol — a controller command written to port 0x64 must never be re-sent as
data to port 0x60. Ours would replay the last command byte through `_sendControllerData`, writing
a command opcode to the data port.

**Resolution (Task 8):** the `lastSent = command;` line was removed from `sendControllerCommand`.
`sendControllerData` keeps its store, so only data bytes are replayable.

## Finding 16: the port counter is `lock inc` on `_xxx.86`; our `LOCK()` is empty

Two related divergences in the same two functions.

**The `lock` prefix is missing.** `PS2Controller.m:23-24` defines both atomicity macros as
nothing:

```c
#define LOCK()
#define UNLOCK()
```

So `PS2Controller.m:595-597` and `:632-634`,

```c
    LOCK();
    _portAccessCount++;
    UNLOCK();
```

compile to a bare non-atomic `inc`, where the reference emits `F0 FF 05 ...` — `lock inc`.

The same emptiness affects the spinlock. `_lock_controller` (0) uses an `xchg`, which is
implicitly atomic on x86:

```
  29: B801000000  mov  eax, 1
  34: 8702        xchg eax, [edx]      ; atomic test-and-set
  36: 83F001      xor  eax, 1
```

and `_unlock_controller` (56) releases with `xchg` too:

```
  67: 31D2        xor  edx, edx
  69: 8710        xchg edx, [eax]
```

Our `PS2Controller.m:321-324` writes the read and the store as two separate statements wrapped in
the empty macros, which compiles to a non-atomic load/store pair. The spinlock does not actually
exclude anything. It should be an `xchg`, either via inline assembly or via a `LOCK()` macro that
expands to `asm volatile("lock")`.

**The counter's name and scope differ.** The reference symbol is `_xxx.86` at `__DATA,__bss:8440`
— GCC's mangling for a static named `xxx`. Ours calls it `_portAccessCount`
(`PS2Controller.m:35`). Both `_sendControllerData` and `_sendControllerCommand` increment the same
one. The reference also has `_xxx.89` (8444) and `_xxx.92` (8448) which nothing in the binary
reads or writes.

Our `_portCountLock` (`PS2Controller.m:36`) has no counterpart in the reference and is never used,
since `LOCK()` is empty. It should be deleted.

### Correction (Task 8): there is no port counter in the reference's source

**The `lock inc ds:_xxx.86` is not driver code at all — it is the tail of `outb()`.**
`driverkit/i386/ioPorts.h` defines the port writers as

```c
static __inline__ void outb(IOEISAPortAddress port, unsigned char data)
{
    static int		xxx;

    asm volatile("outb %2,%1; lock; incl %0"
	: "=m" (xxx)
	: "d" (port), "a" (data), "0" (xxx)
	: "cc");
}
```

and `outw` / `outl` are identical but for the mnemonic. That explains every part of the puzzle at
once: the `lock incl` sits immediately after `out dx, al` in both functions (2057-2058 and
2185-2186) because it is one `asm` statement; both functions touch the *same* `_xxx.86` because
both inline the same `outb`; and `_xxx.89` and `_xxx.92` are `outw`'s and `outl`'s copies, never
read because neither is called. The `.NNN` suffixes are just GCC's numbering for function-scope
statics.

So the reference has **no** `_portAccessCount` and no counter maintenance of its own, and the
report pass's reading of this half of the finding is withdrawn.

**Resolution (Task 8):** `LOCK()`, `UNLOCK()`, `_portAccessCount` and `_portCountLock` were all
deleted, along with the three-line increment in each of `sendControllerData` and
`sendControllerCommand`; the `lock incl` still appears in the rebuilt binary because it comes from
`outb`. The spinlock half of the finding stands and was fixed: `lock_controller` now performs a
real test-and-set and `unlock_controller` a real release, both with an `xchgl` whose bus lock is
implicit on x86, matching `xchg eax, [edx]` at 34 and `xchg edx, [eax]` at 69:

```c
    asm volatile("xchgl %0, %1"
                 : "=r" (lockValue), "=m" (*lockPtr)
                 : "0" (1)
                 : "memory");
```

Our two-TU build emits `_xxx.86/.89/.92` once per translation unit that includes `ioPorts.h`,
where the reference emits them once. `PS2Keyboard.m` no longer uses `inb`/`outb` after
`keyboardDataPresent` moved out (Finding 18), so its `#import <driverkit/i386/ioPorts.h>` was
dropped; the rebuilt `__DATA,__bss` is 96 bytes, the reference's size exactly.

## Finding 17: `requiredProtocols` returns a list holding `PS2ControllerExported`

`+[PS2Keyboard requiredProtocols]` (2416) returns `_protocols` at `__DATA,__data:8432`, which is 8
bytes — one entry plus a NULL terminator. The entry relocates to `__OBJC,__protocol+40`, and the
protocol structure's name field reads **`PS2ControllerExported`**.

Our `PS2Keyboard.m:25-27` declares an empty list:

```c
static Protocol *protocols[] = {
	nil
};
```

with the comment "PCKeyboardExported lives in the kernel tree; empty list is fine for probe."
Both halves of that comment are wrong: the protocol the reference names is
`PS2ControllerExported`, not `PCKeyboardExported`, and it is not empty. As an indirect device,
`PS2Keyboard` declares that it requires its direct device to conform to `PS2ControllerExported` —
which is how DriverKit matches it to the `PS2Controller` instance. With an empty list the matching
constraint is simply absent.

Task 8 needs `@protocol(PS2ControllerExported)` in the array, which means the protocol declaration
must be available to this translation unit.

**Resolution (Task 8):** `PS2ControllerExported` is declared in `PS2Controller.h` and the array
now reads `{ @protocol(PS2ControllerExported), nil }`. The protocol's four methods were decoded
from the reference's `__OBJC,__protocol` and `__OBJC,__cat_inst_meth` rather than guessed:

| Selector | Encoding |
| --- | --- |
| `setLEDs:` | `v9@8:12C16` |
| `setManualDataHandling:` | `v9@8:12c16` |
| `setKeyboardObject:` | `v12@8:12@16` |
| `setMouseObject:` | `v12@8:12@16` |

`PS2Controller` also had to *adopt* the protocol for the list to mean anything — see Finding 24.
The rebuilt `_protocols` is 8 bytes and `__OBJC,__protocol` is 60, both matching.

## Finding 18: two functions are in the wrong source file

Link order places `PS2Controller.m`'s text at 0–2404 and `PS2Keyboard.m`'s at 2404–4952. Two
functions our source puts in `PS2Keyboard.m` have addresses inside the `PS2Controller` block:

| Address | Function | Reference file (by link order) | Our file |
| --- | --- | --- | --- |
| 484 | `_keyboardDataPresent` | `PS2Controller.m` | `PS2Keyboard.m:475` |
| 2320 | `_NewStealKeyboardEvent` | `PS2Controller.m` | `PS2Keyboard.m:593` |

This is the same class of file-placement finding the Intel spec found in `PCIC`.

The placement is corroborated by what the two functions actually touch. `_keyboardDataPresent`
reads `_keyboardQueue` (Finding 6) — a `PS2Controller` static that no other `PS2Keyboard`-side
function references. `_NewStealKeyboardEvent` calls `_getKeyboardDataIfPresent` (1768) and
`_resendControllerData` (2084), both `PS2Controller` functions, and sits at 2320 immediately below
the boundary, with `+[PS2Keyboard deviceStyle]` at 2404 immediately above it.

Moving them is required for address parity: as long as they are compiled into `PS2Keyboard.m`,
every function in the driver after 484 is displaced.

`__PS2KeyboardNumKeysDown` (3364) is **not** affected — it is at 3364, correctly inside the
`PS2Keyboard` block, and `PS2Controller.m:914` calls it across the file boundary through the
declaration at `PS2Controller.h:124`, which is exactly the arrangement the reference implies.

**Resolution (Task 8):** both functions moved to `PS2Controller.m`. `keyboardDataPresent` sits
between `-[PS2Controller initFromDeviceDescription:]` and `reallyGetKeyboardData`, and
`NewStealKeyboardEvent` is the last function in the file, matching the reference's 484 and 2320.
`PS2Controller.m` imports `PS2Keyboard.h` for the `PS2KeyboardEvent` typedef and the
`scancodeToKeyEvent` declaration.

While moving them, **both `.m` files were also reordered to the reference's link order**, which
the report pass did not ask for but which follows from the same evidence. GCC emits functions and
methods in source order, and the reference's addresses interleave methods with C functions —
`+probe:` at 88 and `-initFromDeviceDescription:` at 208, then five C functions, then
`-interruptOccurred` at 732, and so on — so the original defined its C helpers *inside* the
`@implementation` block. Ours now does the same. Independent corroboration: the reference's
`__OBJC,__inst_meth` lists methods in reverse source order, and reversing both lists reproduces
the address order exactly for both classes.

## Finding 19: `interruptOccurred` does not dispatch when the event queue is full

`-[PS2Keyboard interruptOccurred]` (2968) reaches `dispatchKeyboardEvents` from two of its three
paths, not three:

```
3044: 85D2      test edx, edx
3046: 743D      jz   loc_C25          ; event == NULL   -> 3109, dispatch
3048: 83BB0C01000010  cmp dword ptr [ebx+10Ch], 10h
3055: 74AF      jz   loc_BA0          ; queue full      -> 2976, poll again, NO dispatch
      ... store event, inc count ...
3109: 8B0DCC400000  mov ecx, ds:paDispatchkeyboa
3117: call _objc_msgSend              ; [self dispatchKeyboardEvents]
3125: E966FFFFFF    jmp loc_BA0
```

When `_scancodeToKeyEvent` returns an event but the 16-slot queue is already full, the reference
jumps straight back to the `_keyboardDataPresent` test at 2976 and drops the event without
dispatching.

Ours calls `[self dispatchKeyboardEvents]` unconditionally at the bottom of every loop iteration
(`PS2Keyboard.m:302`), because the call sits outside the `if (event != NULL)` block and there is no
early continue for the full-queue case.

Our behaviour is arguably the better one — it drains the queue instead of spinning on a full one —
but this is a parity effort and the reference's control flow is what it is. Recorded rather than
silently kept.

**Resolution (Task 8):** the reference's control flow was adopted. The full-queue case now
`continue`s back to the `keyboardDataPresent()` test without dispatching, and the two other paths
still reach `[self dispatchKeyboardEvents]`.

## Finding 20: `PS2Keyboard` ivar names differ and ours has one extra ivar

The reference's `PS2Keyboard` has 8 ivars and `instance_size` 548:

| Offset | Reference name | Encoding | Our name (`PS2Keyboard.h:24-32`) |
| --- | --- | --- | --- |
| 264 | `controller` | `@` | `controller` |
| 268 | `numEvents` | `I` | `eventCount` |
| 272 | `pendingEvents` | `[16{?="timeStamp"Q"keyCode"I"goingDown"c}]` | `eventQueue` |
| 528 | `interfaceId` | `I` | `interfaceID` |
| 532 | `handlerId` | `I` | `handlerID` |
| 536 | `_owner` | `@` | `keyboardOwner` |
| 540 | `_desiredOwner` | `@` | `desiredOwner` |
| 544 | `_ownerLock` | `@` | `ownerLock` |

Only `controller` matches. Seven need renaming, and the element type of the event array needs the
`timeStamp`/`keyCode`/`goingDown` member names and types from Finding 11.

Ours also declares a **ninth** ivar the reference does not have — `BOOL alphaLockLED`
(`PS2Keyboard.h:32`). It is never read or written anywhere in our source; `setAlphaLockFeedback:`
(`PS2Keyboard.m:416-432`) computes the LED byte from its argument and forwards it to the
controller without recording it, exactly as the reference does at 4372-4406. The extra ivar pushes
`instance_size` from 548 to 552 and must be deleted.

Note the offsets are also evidence for Finding 3's recommendation: `_ownerLock` sits at 544 and the
class ends at 548, so keeping the ivar and dropping only the allocation preserves the layout.

**Resolution (Task 8):** all seven ivars renamed, `alphaLockLED` deleted, and `numEvents`,
`interfaceId` and `handlerId` retyped to `unsigned int` to match the `I` encodings. The rebuilt
`__OBJC,__instance_vars` reports `PS2Keyboard : IODevice  instance_size 548  ivar_count 8` with
the eight names at 264, 268, 272, 528, 532, 536, 540 and 544 and the encodings
`@ I [16{?="timeStamp"Q"keyCode"I"goingDown"c}] I I @ @ @` — identical to the reference. The
methods `- (int)interfaceId` and `- (int)handlerId` keep their `i8@8:12` encodings and now share
their names with the ivars they return, as in the reference.

## Finding 21: `dispatchKeyboardEvents` calls `bcopy` unconditionally on the else path

`-[PS2Keyboard dispatchKeyboardEvents]` (3140) branches on `numEvents == 1` and, when it is not 1,
falls into the `bcopy` with no further test:

```
3167: 83BE0C01000001  cmp dword ptr [esi+10Ch], 1
3174: 7534            jnz loc_C9C            ; -> 3228, bcopy
      ... single-event fast path, four word copies ...
3224: EB22            jmp loc_CBC
3228: 8B860C010000    mov eax, [esi+10Ch]
3234: C1E004          shl eax, 4
3237: 50              push eax               ; count * 16, may be 0
3238: lea/push dst; 3245: lea/push src
3252: call _bcopy
```

Ours guards it (`PS2Keyboard.m:323`): `else if (eventCount > 0) { bcopy(...); }`.

The effect is identical — a `bcopy` of length 0 copies nothing — so this is a codegen divergence
rather than a behavioural one. It is recorded because a rebuilt binary will differ here, and
because it is the only difference in an otherwise instruction-for-instruction match: the
`splx(6)` entry, the single-event fast path, the `numEvents = 0` reset, the `splx(saved)` restore,
the `_owner != nil` guard and the dispatch loop all correspond exactly.

**Resolution (Task 8):** the `else if (eventCount > 0)` guard became a plain `else`, so the
`bcopy` runs unconditionally on that path as the reference does.

## Finding 22: data symbols are spelled too deep, and two are misscoped

The same underscore inflation as Finding 4 affects the file-scope data, sometimes by two levels:

| Reference symbol | Implied C name | Our source | Our symbol | Depth error |
| --- | --- | --- | --- | --- |
| `__controller` (8456) | `_controller` | `___controller` (`PS2Controller.m:31`) | `____controller` | +2 |
| `__mouse` (8460) | `_mouse` | `__mouse` (`PS2Controller.m:30`) | `___mouse` | +1 |
| `__kbdBitVector` (8520) | `_kbdBitVector` | `__kbdBitVector` (`PS2Keyboard.m:31`) | `___kbdBitVector` | +1 |

The comment at `PS2Controller.m:31`, "Note: triple underscore in original", is mistaken — the
reference symbol has two underscores, which implies **one** in source.

**Two statics are function-scoped in the reference and file-scoped in ours.** GCC's `.NNN` suffix
marks a static declared inside a function:

| Reference symbol | Address | Used by | Our declaration |
| --- | --- | --- | --- |
| `_lastExtended.117` | 8452 | `_doEscape` only | file-scope, `PS2Controller.m:40` |
| `_lastKey.118` | 8453 | `_doEscape` only | file-scope, `PS2Controller.m:41` |
| `_event.100` | 8500 | `_scancodeToKeyEvent` only | file-scope, `PS2Keyboard.m:34` |
| `_extendCount.101` | 8516 | `_scancodeToKeyEvent` only | file-scope, `PS2Keyboard.m:37` |

Each is referenced by exactly one function in the binary, consistent with a function-level
`static`. Moving them inside `doEscape` and `scancodeToKeyEvent` respectively reproduces the
mangled names.

`_lastKey.118` is one byte after `_lastExtended.117` and is accessed as a 16-bit value
(`mov ds:_lastKey_118, si` at 1228, `cmp byte ptr ds:_lastKey_118+1, al` at 1168), matching our
`unsigned short`.

Two of our statics have no counterpart at all and should be deleted: `__escapeState`
(`PS2Controller.m:32`, written once in `initFromDeviceDescription:` and never read) and
`_keyboardState` (`PS2Keyboard.m:40`, see Finding 12). `_portCountLock` is covered by Finding 16.

**Resolution (Task 8):** the three renames landed (`_controller`, `_mouse`, `_kbdBitVector` in
source, emitting `__controller`, `__mouse`, `__kbdBitVector`), and the mistaken "triple underscore
in original" comment is gone. `lastExtended` and `lastKey` moved inside `doEscape`, `event` and
`extendCount` inside `scancodeToKeyEvent`. `__escapeState`, `_keyboardState`, `_portAccessCount`
and `_portCountLock` were all deleted.

Two consequences worth naming. First, `resetEscapes` no longer clears `lastExtended`/`lastKey` —
it cannot see them, and the reference does not clear them there either, which is exactly the
evidence that put them inside `doEscape`. Second, GCC's `.NNN` suffixes came out as
`_lastExtended.117` and `_lastKey.118` — **the reference's numbers exactly** — while `event` and
`extendCount` came out `.98`/`.99` against the reference's `.100`/`.101`. Those numbers are
compiler-assigned and, as the report pass noted for `_xxx.86`, are not chaseable.

The explicit `= 0` / `= nil` initializers first written on these statics put them in
`__DATA,__data`; removing the initializers moved them to `__DATA,__bss`, which is where the
reference has them. All ten were then re-verified from the nlist.

Finding 26 records ten further data symbols with the same one-too-deep spelling that the report
pass did not list.

## Finding 23: the access-functions struct is tagged `controller_funcs`

The method type encoding for `-[PS2Controller controllerAccessFunctions]` names the struct:

```
controllerAccessFunctions   ^{controller_funcs=^?^?^?^?^?^?^?^?}8@8:12
```

The tag is `controller_funcs` with eight function-pointer members. Ours uses an untagged struct
typedef'd to `PS2ControllerFunctions` (`PS2Controller.h:23-32`), which encodes as `^{?=...}` and
loses the tag. The struct needs the tag `controller_funcs`; the typedef name can stay, since it
does not appear in the encoding.

The function body itself matches exactly (`mov eax, offset _exported_funcs; ret` at 1428-1439).

**Resolution (Task 8):** the tag landed, but not the way the finding suggests. Writing
`typedef struct controller_funcs { … } PS2ControllerFunctions;` still encoded as `^{?=…}`, and so
did splitting the definition from the typedef: as long as a `typedef` names the record type, this
`cc` sets `TYPE_NAME` to the typedef declaration and the ObjC encoder falls back to `?`. Dropping
the typedef altogether and spelling the type `struct controller_funcs` at its four uses produced
the reference's `^{controller_funcs=^?^?^?^?^?^?^?^?}8@8:12`. `__OBJC,__meth_var_types` went from
227 bytes to **242**, the reference's size exactly — the 15-byte difference is precisely
`controller_funcs` minus `?`.

drvPS2Mouse is unaffected: it declares its own local copy of the structure
(`PS2Mouse.m:92`) and reaches this driver through `IOGetObjectForDeviceName("PS2Controller", …)`
and a cast of `[controller controllerAccessFunctions]`, so it depends on the member order and not
on any type name here. The registered device name was not touched.

## `_exported_funcs`: settled

`_exported_funcs` at `__DATA,__data:8192` is 32 bytes — eight pointers, since `_lalt_ralt_numlock`
begins at 8224 — so it publishes eight of the fifteen exported C functions. **Which eight, and in
what order, is settled** from the eight `i386-vanilla-32-absolute` relocations against
`__TEXT,__text` at 8192, 8196, …, 8220, whose addends name the targets unambiguously:

| Slot | Offset | Addend | Target |
| --- | --- | --- | --- |
| 0 | +0 | 2132 | `_sendControllerCommand` |
| 1 | +4 | 1608 | `_getKeyboardData` |
| 2 | +8 | 1768 | `_getKeyboardDataIfPresent` |
| 3 | +12 | 1960 | `_clearOutputBuffer` |
| 4 | +16 | 2004 | `_sendControllerData` |
| 5 | +20 | 2208 | `_sendMouseCommand` |
| 6 | +24 | 1824 | `_getMouseData` |
| 7 | +28 | 1892 | `_getMouseDataIfPresent` |

Raw bytes at 8192: `5408 0000 4806 0000 E806 0000 A807 0000 D407 0000 A008 0000 2007 0000 6407 0000`.

**Our `PS2ControllerFunctions` already declares these eight members in exactly this order**
(`PS2Controller.h:23-32`), and `_exported_funcs` already initializes them in exactly this order
(`PS2Controller.m:130-139`). Nothing about the membership or ordering needs to change.

The seven exported functions **not** published through this struct are `_keyboardDataPresent`,
`_resendControllerData`, `_disableMouse`, `_enableMouse`, `_NewStealKeyboardEvent`,
`__PS2KeyboardNumKeysDown` and `_scancodeToKeyEvent`. They are external for other reasons —
`_NewStealKeyboardEvent` because its address goes to `_register_keyboard_entries` (Finding 7),
`__PS2KeyboardNumKeysDown` because `PS2Controller.m` calls it across the file boundary.

The two changes this struct still needs are its linkage (Finding 5: external, not `static`), its
tag (Finding 23), and the member names once the underscore renames land (Finding 4).

**Resolution (Task 8):** membership and order were left alone; only the linkage, the tag and the
member spellings changed. The rebuilt `_exported_funcs` is `external` in `__DATA,__data` and 32
bytes, and `__DATA,__data` totals 248, matching the reference.

## Finding 24: both classes adopt a protocol; ours adopted none

Not seen by the report pass, which read `__OBJC,__class` for superclass and ivars but not for the
`protocols` field. Both reference classes have a non-zero one:

```
PS2Controller  protocols -> __OBJC,__cat_cls_meth+0   -> __OBJC,__protocol+0   "PS2ControllerExported"
PS2Keyboard    protocols -> __OBJC,__cat_cls_meth+12  -> __OBJC,__protocol+20  "PCKeyboardExported"
```

`__OBJC,__cat_cls_meth` is 24 bytes — two 12-byte `objc_protocol_list` records of one entry each —
and `__OBJC,__protocol` is 60 bytes, three 20-byte protocol structures: `PS2ControllerExported`
declared in `PS2Controller.m`, `PCKeyboardExported`, and a second copy of `PS2ControllerExported`
emitted for `PS2Keyboard.m`'s `@protocol(…)` expression, which is the one `_protocols` points at.

`PCKeyboardExported` is not a driver-local invention: it is declared in
`<bsd/dev/i386/PCKeyboardDefs.h>`, which is present on the guest, and its three methods
(`becomeOwner:`, `relinquishOwnership:`, `desireOwnership:`, all `- (IOReturn)`) are exactly the
three the reference's protocol structure carries with encoding `i12@8:12@16`. **That is
independent confirmation of Finding 2's polarity claim from Apple's own header.** The same header
declares `PCKeyboardEvent` with the members `timeStamp` / `keyCode` / `goingDown`, confirming
Finding 11.

Finding 17 is only half a fix without this: a `requiredProtocols` list naming
`PS2ControllerExported` matches nothing unless `PS2Controller` conforms to it.

**Resolution (Task 8):** `PS2Controller` is declared
`@interface PS2Controller : IODirectDevice <PS2ControllerExported>` with the protocol defined
above it in the same header, and `PS2Keyboard` is declared
`@interface PS2Keyboard : IODevice <PCKeyboardExported>` over an import of
`<bsd/dev/i386/PCKeyboardDefs.h>`. That header is `DRIVER_PRIVATE`-guarded, which is why
`-DDRIVER_PRIVATE` was added to the `Makefile`'s `NEXTSTEP_PB_CFLAGS`; the same flag also makes
`<bsd/dev/i386/PCPointer.h>` declare `PCPatoi`, which `readConfigTable:` had been calling
implicitly. The rebuilt binary reproduces both conformances, and `__OBJC,__cat_cls_meth` (24),
`__OBJC,__cat_inst_meth` (100), `__OBJC,__protocol` (60) and `__OBJC,__class_names` (202) all
match the reference exactly.

## Finding 25: the queue heads are 8 bytes, not a full `PS2QueueElement`

`_keyboardQueue` is at 8472 and `_keyboardFreeQueue` at 8480 — **8 bytes apart** — while
`_keyboardQueueElements` is 384 bytes for 32 entries, i.e. 12 bytes each. So the reference's two
list heads hold only the `next` and `prev` links and have no `data` byte, in the manner of Mach's
`queue_head_t`. Our source declared both heads as `PS2QueueElement`, which is 12 bytes, putting
`__DATA,__bss` 8 bytes over the reference's 96.

**Resolution (Task 8):** a two-word `PS2QueueHead` type was added and the two heads declared with
it. To keep the sentinel comparisons readable rather than scattering casts, `PS2Controller.m`
defines

```c
#define KBD_QUEUE       ((PS2QueueElement *)&keyboardQueue)
#define KBD_FREE_QUEUE  ((PS2QueueElement *)&keyboardFreeQueue)
```

`__DATA,__bss` is now 96 bytes, the reference's size exactly.

## Finding 26: ten more data symbols are one underscore too deep

Finding 22 listed three. Reading the reference's whole nlist shows the same one-too-deep spelling
on ten more, every one of which our source wrote with a leading underscore that the compiler then
doubled:

| Reference symbol | Implied C name | Our source | Our symbol |
| --- | --- | --- | --- |
| `_controller_lock` (8496) | `controller_lock` | `_controller_lock` | `__controller_lock` |
| `_lastSent` (8464) | `lastSent` | `_lastSent` | `__lastSent` |
| `_pendingAck` (8468) | `pendingAck` | `_pendingAck` | `__pendingAck` |
| `_exported_funcs` (8192) | `exported_funcs` | `_exported_funcs` | `__exported_funcs` |
| `_escapes` (8288) | `escapes` | `_escapes` | `__escapes` |
| `_lalt_ralt_numlock` (8224) | `lalt_ralt_numlock` | `_lalt_ralt_numlock` | `__lalt_ralt_numlock` |
| `_ralt_lalt_numlock` (8240) | `ralt_lalt_numlock` | `_ralt_lalt_numlock` | `__ralt_lalt_numlock` |
| `_lalt_numlock` (8256) | `lalt_numlock` | `_lalt_numlock` | `__lalt_numlock` |
| `_ralt_numlock` (8272) | `ralt_numlock` | `_ralt_numlock` | `__ralt_numlock` |
| `_keyboardQueueElements` (8536) | `keyboardQueueElements` | ivar (Finding 1) | — |

`parity_check.py` did not report these because it compares `__TEXT,__text` symbols only, which is
the same blind spot Finding 5 warns about for linkage.

`_protocols` in `PS2Keyboard.m` was already correct.

**Resolution (Task 8):** all renamed, and every one verified from the rebuilt nlist to have the
reference's name, binding and section.

## Finding 27: `_register_keyboard_entries` is called one underscore too deep

`+[PS2Keyboard probe:]` at 2570 calls `_register_keyboard_entries`, the symbol for the C function
`register_keyboard_entries` declared in `<bsd/dev/i386/kbd_entries.h>`. `PS2Keyboard.m:86` wrote
`_register_keyboard_entries(...)`, which emits the undefined symbol
`__register_keyboard_entries`. The header is `KERNEL_PRIVATE`-guarded and so supplies no
declaration in this build, meaning the compiler accepted the misspelling as an implicit
declaration and the object file carried an undefined symbol the kernel could never resolve. It is
invisible to `parity_check.py`, which compares defined symbols.

**Resolution (Task 8):** the call site was corrected to `register_keyboard_entries(...)` and an
explicit `extern void register_keyboard_entries(void *list);` added at the top of `PS2Keyboard.m`,
with a comment saying why the real header cannot be used.

## Observations that are not findings

**The command-byte edit is equivalent, not divergent.** `initWithController:` computes the new
controller command byte as

```
2827: 80CB40  or  bl, 40h
2830: 80E3EF  and bl, 0EFh
2833: 80CB01  or  bl, 1
```

that is `((x | 0x40) & 0xEF) | 0x01`. Ours writes `commandByte & 0xEF | 0x41`
(`PS2Keyboard.m:136`). Since `0x40 & 0xEF == 0x40`, both reduce to `(x & 0xEF) | 0x41`. The
instruction sequences differ but the result is identical for every input, so no change is
required; a rebuilt binary may or may not reproduce the three-instruction form depending on the
compiler.

**"Write to Auxiliary Device" is a comment, not a literal.** The brief asks whether the string at
`PS2Controller.m:753` — now line 755 after the build-repair shifted the file — is a string
constant the reference lacks. It is not:

```c
    /* Send the "Write to Auxiliary Device" command (0xD4) to controller */
    _sendControllerCommand(0xD4);
```

It is inside a `/* … */` comment and never reaches `__TEXT,__cstring`. **Not a finding**, and no
action for Task 8.

**`_isEscape`, `_undoEscape` and `_getMouseDataIfPresent` have extra NULL guards.** The reference
begins `_isEscape` at 756 with `mov esi, [ebp+arg_4]; cmp dword ptr [esi+28h], 0` — it dereferences
the escape pointer immediately, with no null test. `_undoEscape` (1020) likewise loads `[eax+2Ch]`
at once, and `_getMouseDataIfPresent` (1892) calls `_lock_controller` before touching `data`. Ours
tests for NULL first in all three (`PS2Controller.m:853`, `:958`, `:720`). These are folded into
Findings 8 and the function entries rather than listed separately, but Task 8 should remove them
for instruction parity. **Task 8 removed all three.**

**`_enqueueKeyboardData` leaves the data byte in `eax`.** The reference ends with
`movzx eax, [ebp+var_4]` at 718 even though the function is used as `void`. This is dead code the
compiler emitted, not a return value any caller reads — `_undoEscape` and `_interruptHandler` both
discard it. No action.

**The reference declares three unused ivars and two unused statics.** `portSet` and
`pendingLEDVal` on `PS2Controller`, and `_xxx.89` / `_xxx.92` in `__bss`, are never read or
written by any of the 49 functions. They still have to be declared to reproduce
`instance_size` 308 and the `__bss` layout, but no code uses them.

**The reference declares three unused ivars and two unused statics** — see the paragraph below;
**Task 8's correction to the two unused statics is in Finding 16**: they are `outw`'s and `outl`'s
copies of `ioPorts.h`'s `xxx`, not driver source, and they reappear in our build automatically.

## What is unsettled

Nothing material. Three items were worth naming so Task 8 did not re-derive them; all three are
now settled:

1. **The two `PS2Controller` ivars `portSet` and `pendingLEDVal` have no observable semantics.**
   Their names come from `__OBJC,__instance_vars` and their types from the encodings (`i` and
   `i`), but since nothing reads them their meaning is inferred from the names alone. Declaring
   them as `int` at offsets 296 and 304 reproduces the layout regardless.
2. **`_xxx.86`'s source name is `xxx`**, from GCC's `.NNN` mangling — the original really did
   name it that. The `.86`, `.89`, `.92` suffixes are compiler-assigned sequence numbers that a
   rebuild will not necessarily reproduce, so exact symbol-name parity on these three is not
   achievable and should not be chased.
3. **Whether `NXLock.h`/`NXLock.m` should be deleted outright or merely unused** is a judgement
   call for Task 8 (Finding 3). The evidence settles what the reference does — a nil `_ownerLock`
   — but not what the build-repair effort intends for the file.

**Task 8's answers.** (1) `portSet` and `pendingLEDVal` were declared as `int` at 296 and 304 with
`mouseObject` between them, reproducing `instance_size` 308; their names come from Apple's own
`<bsd/dev/i386/PS2Keyboard.h>`, the header for the older kernel-resident driver, where the same
three appear as real ivars — so the loadable controller inherited three that had stopped being
used. (2) `xxx` is `ioPorts.h`'s, not the driver's; see Finding 16's correction. The `.86`/`.89`/
`.92` numbering was not chased and our build emits its own copies per translation unit.
(3) `NXLock.h` and `NXLock.m` were deleted outright — the evidence in Finding 3 is decisive and
keeping them would have doubled `__OBJC,__class`.

## Finish campaign (2026-09-16)

Instruction-stream finish against rebuilt `967883F054B1FC06D89EB5F0BF9E59D8CB973DC61749941686B9042F49E3A1B7` (157632 bytes).
At IDA baseline: 5 `raw_equal`, 22 `masked_equal`, 22 open, 0 unpaired.
Task 3 marked the non-glue identical/masked-eq rows `assembly-matched`.
The two Kernel Server glue methods stay `intentional-mismatch` even though they are instruction-identical.
Two Task 8 gate names remain open on `--list` (`setAlphaLockFeedback:`, `relinquishOwnership:`) and were not demoted.

## Task 4 accepts (compiler-shaped leftover)

Empty source-shape lists. Reason on each ledger row:
`compiler-shaped leftover after exhausted source-shape list`. Reviewer: Pat Raynor.
Rebuilt SHA `20C8BD6E1243FE4CB6D1CDCC51654CBADF65E118370ACBF8D49EBE05B3631C07`.

### `-[PS2Keyboard setAlphaLockFeedback:]` (4372) — Task 8 gate, empty by policy

BOOL / `and eax, 0FFh` typed rewrite forbidden. `--name`:

```
-[PS2Keyboard setAlphaLockFeedback:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  xor eax, eax                            xor eax, eax
  cmp [ebp+arg_8], 0                      cmp [ebp+arg_8], 0
* jz loc_1127                             jz loc_6CB
  mov eax, 4                              mov eax, 4
*                                         and eax, 0FFh
  push eax                                push eax
  mov ecx, ds:paSetleds                   mov ecx, ds:paSetleds
  push ecx                                push ecx
  mov edx, [edx+108h]                     mov edx, [edx+108h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### `_resetEscapes` (964) — compiler-shaped, no source experiment

Same mnemonics; starred rows are jump labels and a `ds:` reloc.

```
_resetEscapes
  status=different raw_equal=False masked_equal=False
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, offset _escapes                mov edx, offset _escapes
* cmp ds:off_2078, 0                      cmp ds:off_2080, 0
* jz loc_3F8                              jz loc_C9C
  nop                                     nop
  nop                                     nop
  nop                                     nop
  cmp dword ptr [edx+28h], 0              cmp dword ptr [edx+28h], 0
* jz loc_3EF                              jz loc_C93
  mov eax, [edx+28h]                      mov eax, [edx+28h]
  mov dword ptr [eax+4], 0                mov dword ptr [eax+4], 0
  mov dword ptr [edx+28h], 0              mov dword ptr [edx+28h], 0
  add edx, 30h                            add edx, 30h
  cmp dword ptr [edx+18h], 0              cmp dword ptr [edx+18h], 0
* jnz loc_3D8                             jnz loc_C7C
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### `_lock_controller` (0) — compiler-shaped, no source experiment

`cmp dword ptr [edx], 0` vs `mov`/`test`; `xor eax, 1`/`test` vs `cmp eax, 1`. Equivalent gcc 2.x spinlock.

```
_lock_controller
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push 6                                  push 6
  call near ptr _spln                     call near ptr _spln
  mov ecx, eax                            mov ecx, eax
  mov edx, ds:_controller_lock            mov edx, ds:_controller_lock
  add edx, 4                              add edx, 4
  nop                                     nop
  nop                                     nop
  nop                                     nop
* cmp dword ptr [edx], 0                  mov eax, [edx]
* jnz loc_18                              test eax, eax
*                                         jnz loc_8FC
  mov eax, 1                              mov eax, 1
  xchg eax, [edx]                         xchg eax, [edx]
* xor eax, 1                              cmp eax, 1
* test eax, eax                           jz loc_8FC
* jz loc_18
  mov eax, ds:_controller_lock            mov eax, ds:_controller_lock
  mov [eax], ecx                          mov [eax], ecx
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### `-[PS2Keyboard relinquishOwnership:]` (4632) — Task 8 gate, empty by policy

Then/else order on `respondsTo:` is compiler-shaped leftover under the gate. Body not rewritten.

```
-[PS2Keyboard relinquishOwnership:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edi, [ebp+arg_8]                    mov edi, [ebp+arg_8]
  mov edx, ds:paLock                      mov edx, ds:paLock
  push edx                                push edx
  mov edx, [ebx+220h]                     mov edx, [ebx+220h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  cmp [ebx+218h], edi                     cmp [ebx+218h], edi
* jnz loc_1250                            jnz loc_7F8
  xor esi, esi                            xor esi, esi
  mov dword ptr [ebx+218h], 0             mov dword ptr [ebx+218h], 0
* jmp loc_1255                            jmp loc_7FD
  mov esi, 0FFFFFD2Bh                     mov esi, 0FFFFFD2Bh
  mov edx, ds:paUnlock                    mov edx, ds:paUnlock
  push edx                                push edx
  mov edx, [ebx+220h]                     mov edx, [ebx+220h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  test esi, esi                           test esi, esi
* jnz loc_12D0                            jnz loc_878
  cmp dword ptr [ebx+21Ch], 0             cmp dword ptr [ebx+21Ch], 0
* jz loc_12D0                             jz loc_878
  cmp [ebx+21Ch], edi                     cmp [ebx+21Ch], edi
* jz loc_12D0                             jz loc_878
  mov edx, ds:paCanbecomeowner            mov edx, ds:paCanbecomeowner
  push edx                                push edx
  mov edx, ds:paRespondsto                mov edx, ds:paRespondsto
  push edx                                push edx
  mov edx, [ebx+21Ch]                     mov edx, [ebx+21Ch]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
  test al, al                             test al, al
* jz loc_12B8                             jnz loc_864
* push ebx
* mov edx, ds:paCanbecomeowner
* push edx
* mov ebx, [ebx+21Ch]
* push ebx
* call near ptr _objc_msgSend
* jmp loc_12D0
  mov edx, ds:paName                      mov edx, ds:paName
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push eax                                push eax
  push offset aSDesiredownerD             push offset aSDesiredownerD
  call near ptr _IOLog                    call near ptr _IOLog
*                                         jmp loc_878
*                                         push ebx
*                                         mov edx, ds:paCanbecomeowner
*                                         push edx
*                                         mov ebx, [ebx+21Ch]
*                                         push ebx
*                                         call near ptr _objc_msgSend
  mov eax, esi                            mov eax, esi
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

## Task 4 matches

### `_sendMouseCommand` (2208) — `masked_equal`

Inverted `if (response != 0xFA) return 0; else return 1;` (experiment 2). `--name` differs only by jump labels. Rebuilt `C2B45245EE841E1851BA1FFCB9C8E20F9929D390A6E64AF97995202029A32CF1`. Task 8 gate rows stayed identical / masked-eq. Glue still instruction-identical. Unpaired 0.

### `-[PS2Keyboard desireOwnership:]` (4828) — `masked_equal`

Inverted the conflict test first (`_desiredOwner != nil && _desiredOwner != owner`). `--name` differs only by jump labels. Rebuilt `4FC38265802F44ADCD416DC55FED02E5138218867A93433CDDBAB6C15B74DA62`. `_sendMouseCommand` stayed masked-eq. Task 8 gates unchanged. Unpaired 0.

### `+[PS2Controller probe:]` (88) — accepted leftover

Pointer-increment store still compiled to `mov dword ptr [eax+4], 0`. Remaining: addressing mode and `test eax` vs `mov ebx, eax` / `test ebx`. `--name` after the miss (same shape as baseline):

```
+[PS2Controller probe:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, [ebp+arg_0]                    mov edx, [ebp+arg_0]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 8                              add esp, 8
  test ebx, ebx                           test ebx, ebx
* jz loc_C4                               jz loc_9AC
  mov ds:__controller, ebx                mov ds:__controller, ebx
  mov ds:__mouse, 0                       mov ds:__mouse, 0
  mov ds:_pendingAck, 0                   mov ds:_pendingAck, 0
  push 8                                  push 8
  call near ptr _kalloc                   call near ptr _kalloc
  mov ds:_controller_lock, eax            mov ds:_controller_lock, eax
* add eax, 4                              mov dword ptr [eax+4], 0
* add esp, 4
* mov dword ptr [eax], 0
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, ds:paInitfromdevice            mov edx, ds:paInitfromdevice
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* test eax, eax                           mov ebx, eax
*                                         test ebx, ebx
  setnz al                                setnz al
  and eax, 0FFh                           and eax, 0FFh
* jmp loc_C6                              jmp loc_9AE
  xor eax, eax                            xor eax, eax
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### `-[PS2Keyboard initWithController:]` (2760) — kept source, leftover accepted

Three-statement command-byte edit matches the reference `or`/`and`/`or`. Remaining `--name` star is `ds:stru_40F0.ext` vs `super_class`. Diff 1. Rebuilt `20C8BD6E1243FE4CB6D1CDCC51654CBADF65E118370ACBF8D49EBE05B3631C07`.

```
-[PS2Keyboard initWithController:]
  status=different raw_equal=False masked_equal=False
  starred leftover:
* mov edx, ds:stru_40F0.ext               mov edx, ds:stru_40F0.super_class
```

### `_undoEscape` (1020) — `masked_equal`

Dropped the `scancode` local; enqueue `sequence->keys[index * 2] | 0x80` as an expression after the extended-byte test. `--name` differs only by jump labels. Rebuilt `C3AB80B5D295E5DBBBA30A3228C75D047CC578A0D38899BAA874E3B53DC68B23`. Task 8 gate rows stayed identical / masked-eq. Glue still instruction-identical. Unpaired 0.

### `_getKeyboardDataIfPresent` (1768) — `masked_equal`

Branch on `keyboardDataPresent()` before each unlock with explicit `return 1` / `return 0`, inverted to `if (!keyboardDataPresent())` so the `jz` failure path is laid after the success store. `--name` differs only by jump labels. Rebuilt `66F2CFBFA8781004505F3E4A2DA92FFE8EB9467C5EBF93118BDF7AD30A501496`. `_undoEscape` stayed masked-eq. Task 8 gates unchanged. Unpaired 0.

### `_enqueueKeyboardData` (576) — kept source, leftover accepted

Compared `keyboardFreeQueue.next == KBD_FREE_QUEUE` before loading `element`, then stored `keyboardQueue.prev = element` before `oldPrev->next = element` through existing `tempPtr`. Remaining `--name` star is a dead `movzx eax, [ebp+var_4]` on the reference. Diff 9. Rebuilt `0ED264C35A59ED1EAECA13B36EA184596482F08B67DEBE9207B58B923C151FDE`.

```
_enqueueKeyboardData
  status=different raw_equal=False masked_equal=False
  starred leftover:
* jz loc_2CE                              jz loc_B7A
* jz loc_274                              jz loc_B20
* jz loc_286                              jz loc_B32
* jnz loc_2B8                             jnz loc_B64
* mov ds:dword_211C, edx                  mov ds:dword_2140, edx
* jmp loc_2CE                             jmp loc_B7A
* mov eax, ds:dword_211C                  mov eax, ds:dword_2140
* mov ds:dword_211C, edx                  mov ds:dword_2140, edx
* movzx eax, [ebp+var_4]
```

### `_getMouseDataIfPresent` (1892) — `masked_equal`

Dropped the inverted `noMouseData` BOOL; `if (!(status & 0x20))` returns 0 after unlock so the `jz` failure path is laid after the success read. `--name` differs only by jump labels. Rebuilt `89C796C24C9B73175F9C5C2B644C454665ED2D49B349BDC2E8BC16E2925C2764`. Task 8 gates unchanged. Unpaired 0.

### `-[PS2Keyboard dispatchKeyboardEvents]` (3140) — `masked_equal`

Signed `i` / `savedEventCount` yield `jge`/`jl`; the n==1 path is a struct copy so `goingDown` stores as a dword. `--name` differs only by jump labels. Rebuilt `BD73917E3E2C0AFDD7F6A5E82A8D28B09A59415055533261C382D4B55A8F6359`. Task 8 gates unchanged. Unpaired 0.

### `-[PS2Keyboard enqueueKeyEvent:goingDown:atTime:]` (3420) — `identical`

Scalar parked locals were copy-propagated. A `PS2KeyboardEvent` local filled then struct-assigned into the slot yields `sub esp, 10h` and the four dword stores. `--name` is `raw_equal`. Rebuilt `AF59A809360F8ADBC6010ECDC5781E9FD247D2F9A375A817356DF631E9310BAD`. Task 8 gates unchanged. Unpaired 0.

### `-[PS2Keyboard interruptOccurred]` (2968) — `masked_equal`

`unsigned int scancode` grew unpaired `--list` and was reverted. Struct-assign `pendingEvents[index] = *event` copies goingDown as a dword and also laid `and eax, 0FFh`. `--name` differs only by jump labels. Rebuilt `71A852D8F98F4393FBEF6ED141A0A499794645D762B0368B157769BF7F2237DD`. Task 8 gates unchanged. Unpaired 0. Do not repeat the unsigned-int scancode local.

## Task 4 stop (unpaired growth)

`readConfigTable:` ivar-in-branch experiment made `--list` report 50 functions / 2 unpaired (`missing-rebuilt __PS2KeyboardNumKeysDown`, `missing-reference _resetEscapes`). That is a layout or linkage finding. Experiment reverted. After rebuild, SHA is again `20C8BD6E1243FE4CB6D1CDCC51654CBADF65E118370ACBF8D49EBE05B3631C07`, `--list` 49 / 0 unpaired. Do not repeat the ivar-in-NULL-branch store. Campaign continues on other functions.

### `-[PS2Keyboard readConfigTable:]` (2588) — accepted leftover

In-branch `interfaceId = 3` / `handlerId = 0` is the matching source shape and is forbidden after the unpaired `--list` growth. Remaining starred rows are that join-store versus in-branch ivar stores, plus Interface-path `add esp, 4` scheduling. `--name`:

```
-[PS2Keyboard readConfigTable:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov ebx, [ebp+arg_8]                    mov ebx, [ebp+arg_8]
  test ebx, ebx                           test ebx, ebx
* jnz loc_A3C                             jnz loc_D8
  push offset aPs2keyboardKbd             push offset aPs2keyboardKbd
  call near ptr _IOLog                    call near ptr _IOLog
  xor eax, eax                            xor eax, eax
* jmp loc_ABD                             jmp loc_14D
  push offset aInterface                  push offset aInterface
  mov edx, ds:paValueforstring            mov edx, ds:paValueforstring
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jnz loc_A6C                             jnz loc_104
  push offset aPs2keyboardKbd_0           push offset aPs2keyboardKbd_0
  call near ptr _IOLog                    call near ptr _IOLog
* mov dword ptr [esi+210h], 3             mov eax, 3
* jmp loc_A78                             jmp loc_10A
  push eax                                push eax
  call near ptr _PCPatoi                  call near ptr _PCPatoi
*                                         add esp, 4
  mov [esi+210h], eax                     mov [esi+210h], eax
* add esp, 4
  push offset aHandlerId                  push offset aHandlerId
  mov edx, ds:paValueforstring            mov edx, ds:paValueforstring
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jnz loc_AAC                             jnz loc_13C
  push offset aPs2keyboardKbd_1           push offset aPs2keyboardKbd_1
  call near ptr _IOLog                    call near ptr _IOLog
* mov dword ptr [esi+214h], 0             xor eax, eax
* jmp loc_AB8                             jmp loc_142
  push eax                                push eax
  call near ptr _PCPatoi                  call near ptr _PCPatoi
  mov [esi+214h], eax                     mov [esi+214h], eax
  mov eax, 1                              mov eax, 1
  lea esp, [ebp-8]                        lea esp, [ebp-8]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```