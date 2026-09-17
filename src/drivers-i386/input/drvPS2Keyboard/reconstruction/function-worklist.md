# drvPS2Keyboard instruction-stream baseline

Date: 2026-09-16
Branch: `drvps2keyboard-binrecon-finish`

Angr was disabled because rebuilt decode at 0x10 failed normalization.

Analyzer: IDA 9.2 only (`analyzers.angr.enabled` is false; Ghidra stays off).
`binrecon analyze` published `complete: true` with `normalized-functions=FAIL` (exit 1 expected).

## Identities

| | SHA-256 | size |
| --- | --- | --- |
| Reference | `AB413CA3919950F22A1F5D10B0BF1167387FEF320C9FB82A3EA66E586A6BE02A` | 43460 |
| Rebuilt | `967883F054B1FC06D89EB5F0BF9E59D8CB973DC61749941686B9042F49E3A1B7` | 157632 |

`__TEXT,__text`: reference 4952, rebuilt 4652.

`parity_check.py`: `missing_strings (0)`, `missing_symbols (0)`. Extra symbols 54 (stabs / file names on the unstripped guest `_reloc`).

## `__OBJC,__class` instance sizes

Read from the rebuilt `_reloc` with `binrecon.macho.read_macho` (`__OBJC,__class`, 40-byte `objc_class`, little-endian `instance_size` at word 5; names from the `name` pointer). Reference dump matches.

| Class | Superclass | `instance_size` |
| --- | --- | --- |
| `PS2Controller` | `IODirectDevice` | **308** |
| `PS2Keyboard` | `IODevice` | **548** |
| `PS2KeyboardVersion` | `IODevice` | 264 |
| `PS2KeyboardKernelServerInstance` | `Object` | 4 |

## `binrecon function --list` (IDA)

```
  diff    ref    new  flags       name

     0      6      6  identical   +[PS2Keyboard deviceStyle]
     0      6      6  masked-eq   +[PS2Keyboard requiredProtocols]
     0      6      6  identical   +[PS2KeyboardKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[PS2KeyboardVersion driverKitVersionForPS2Keyboard]
     0      6      6  masked-eq   -[PS2Controller controllerAccessFunctions]
     0     12     12  masked-eq   -[PS2Controller getHandler:level:argument:forInterrupt:]
     0     10     10  masked-eq   -[PS2Controller interruptOccurred]
     0      7      7  masked-eq   -[PS2Controller setKeyboardObject:]
     0     29     29  masked-eq   -[PS2Controller setLEDs:]
     0      7      7  masked-eq   -[PS2Controller setMouseObject:]
     0      7      7  identical   -[PS2Keyboard handlerId]
     0      7      7  identical   -[PS2Keyboard interfaceId]
     0     13     13  masked-eq   _unlock_controller
     1     21     21  masked-eq   -[PS2Controller setManualDataHandling:]
     1     16     16  masked-eq   _clearOutputBuffer
     1      9      9  masked-eq   _disableMouse
     1      9      9  masked-eq   _enableMouse
     1     25     25  masked-eq   _getMouseData
     1     14     14  masked-eq   _keyboardDataPresent
     1     15     15  masked-eq   _resendControllerData
     2     16     17              -[PS2Keyboard setAlphaLockFeedback:]
     2     28     28  masked-eq   __PS2KeyboardNumKeysDown
     2     19     19  masked-eq   _reallyGetKeyboardData
     2     25     25  masked-eq   _sendControllerCommand
     2     26     26  masked-eq   _sendControllerData
     3     56     56  masked-eq   +[PS2Keyboard probe:]
     3     34     34  masked-eq   _NewStealKeyboardEvent
     3     32     32  masked-eq   _interruptHandler
     4     19     19              _resetEscapes
     4     19     17              _sendMouseCommand
     6     32     32              -[PS2Keyboard desireOwnership:]
     6     22     22              _lock_controller
     7     36     35              +[PS2Controller probe:]
     7     68     67              -[PS2Keyboard initWithController:]
    10     50     50              -[PS2Keyboard readConfigTable:]
    10     34     34              _undoEscape
    12     19     20              _getKeyboardDataIfPresent
    13     43     43              _enqueueKeyboardData
    14     24     29              _getMouseDataIfPresent
    20     63     63              -[PS2Keyboard relinquishOwnership:]
    27     63     63              -[PS2Keyboard dispatchKeyboardEvents]
    31     29     24              -[PS2Keyboard enqueueKeyEvent:goingDown:atTime:]
    32     50     51              -[PS2Keyboard interruptOccurred]
    37     41     45              _getKeyboardData
    40     73     70              _isEscape
    43     69     69              -[PS2Keyboard becomeOwner:]
    48     74     60              -[PS2Controller initFromDeviceDescription:]
    50     61     65              _doEscape
   102    112    110              _scancodeToKeyEvent

49 functions: 5 byte-identical, 44 differing, 0 unpaired
```

`--list` counts every non-`raw_equal` row as differing, including `masked-eq`. Split:

- **identical (`raw_equal`):** 5
- **masked-eq (not identical):** 22
- **open (empty flags, not masked-eq):** 22
- **unpaired:** 0

The two Kernel Server glue methods are instruction-identical here. Task 3 still keeps them `intentional-mismatch`.

Task 8 regression-gate rows at this baseline: `deviceStyle` / `handlerId` / `interfaceId` identical; `getHandler:level:argument:forInterrupt:` / `setLEDs:` / `_clearOutputBuffer` masked-eq; `setAlphaLockFeedback:` and `relinquishOwnership:` still open.

## Cheapest open rows (empty flags)

| diff | name |
| --- | --- |
| 2 | `-[PS2Keyboard setAlphaLockFeedback:]` |
| 4 | `_resetEscapes` |
| 4 | `_sendMouseCommand` |
| 6 | `-[PS2Keyboard desireOwnership:]` |
| 6 | `_lock_controller` |
| 7 | `+[PS2Controller probe:]` |
| 7 | `-[PS2Keyboard initWithController:]` |
| 10 | `-[PS2Keyboard readConfigTable:]` |
| 10 | `_undoEscape` |
| 12+ | `_getKeyboardDataIfPresent` and the rest of the empty-flag list |

## Reachability

From `binrecon function --name` of the cheapest open rows:

- **`-[PS2Keyboard setAlphaLockFeedback:]` (diff 2) — source-shaped.** Rebuilt inserts `and eax, 0FFh` after `mov eax, 4` on the true path (`calls differ` / `instruction shape differs`). Worth a typed rewrite of the LED / BOOL local; do not grind it as a Task 8 match unless that experiment is empty.
- **`_resetEscapes` (diff 4) — compiler-shaped.** Same mnemonics; starred lines are jump targets and a `ds:` offset (`instruction layout differs`). Looks like reloc / label masking, not a wrong constant or missing call.
- **`_sendMouseCommand` (diff 4) — source-shaped.** Reference is `jnz` / `mov eax, 1` / `jmp` / `xor eax, eax`; rebuilt is `setz al` / `and eax, 0FFh`. Classic comparison-as-return vs if/else.
- **`-[PS2Keyboard desireOwnership:]` (diff 6) — source-shaped.** Same lock / owner / `0xFFFFFD2B` pieces; the if/else blocks are in opposite order (`jz`/`jz` vs `jz`/`jnz`). Candidate for `if` vs `else if` or reversed `cmp`.
- **`_lock_controller` (diff 6) — compiler-shaped.** `cmp dword ptr [edx], 0` vs `mov`/`test`, and `xor eax, 1`/`test` vs `cmp eax, 1`. Register vs memory compare and test-vs-cmp on the spinlock; not a missing call.
- **`+[PS2Controller probe:]` (diff 7) — mixed, first try source-shaped.** `add eax, 4` then `mov [eax], 0` vs `mov [eax+4], 0` (how the kalloc'd lock is zeroed) plus a `test eax` vs `mov ebx, eax` / `test ebx` return. Try the store shape before accepting the register move.

## Task 4 experiment lists

One idea per remaining empty-flag row, cheapest first. Add more only after a miss. Task 8 gate bodies are not rewritten.

### `-[PS2Keyboard setAlphaLockFeedback:]` (diff 2) — empty by policy

Task 8 regression gate. Do not apply the BOOL / `and eax, 0FFh` typed rewrite. Accept without a source edit.

**Accepted** 2026-09-16: `intentional-mismatch`, compiler-shaped leftover after exhausted source-shape list.

### `_resetEscapes` (diff 4) — empty; compiler-shaped confirmed

`--name` 2026-09-16: same mnemonics; starred rows are jump labels and `ds:off_2078` vs `ds:off_2080`. Reloc / layout masking, not a wrong constant or missing call. Accept without a source experiment.

**Accepted** 2026-09-16: `intentional-mismatch`, compiler-shaped leftover after exhausted source-shape list.

### `_sendMouseCommand` (diff 4)

1. Rewrite `return (response == 0xFA)` as an if/else that returns 1 or 0 (`jnz` / `mov eax, 1` / `xor eax, eax` vs `setz`).
   **Tried, miss:** `if (response == 0xFA) return 1; else return 0;` laid the `xor eax, eax` path first (`jz` to `mov eax, 1`). Diff 4 → 5. No closed-function regression. Reverted.
2. Invert the compare: `if (response != 0xFA) return 0; else return 1;` so the `jnz` failure path matches the reference.
   **Match:** `masked_equal` after rebuild `C2B45245EE841E1851BA1FFCB9C8E20F9929D390A6E64AF97995202029A32CF1`. Ledger `assembly-matched`.

### `-[PS2Keyboard desireOwnership:]` (diff 6)

1. Invert the if/else: test the conflict (`_desiredOwner != nil && _desiredOwner != owner`) first so the `-725` store is laid out before the success store (`jz`/`jz` vs `jz`/`jnz`).
   **Match:** `masked_equal` after rebuild `4FC38265802F44ADCD416DC55FED02E5138218867A93433CDDBAB6C15B74DA62`. Ledger `assembly-matched`.

### `_lock_controller` (diff 6) — empty; compiler-shaped confirmed

`--name` 2026-09-16: `cmp dword ptr [edx], 0` vs `mov`/`test`, and `xor eax, 1`/`test` vs `cmp eax, 1`. Equivalent gcc 2.x spinlock shape; no missing call. Accept without a source experiment.

**Accepted** 2026-09-16: `intentional-mismatch`, compiler-shaped leftover after exhausted source-shape list.

### `+[PS2Controller probe:]` (diff 7)

1. Zero the kalloc'd lock flag through a pointer increment (`eax += 4; *eax = 0`) instead of `controller_lock[1] = 0`.
   **Tried, miss:** extra `lockFlag` local still compiled to `mov dword ptr [eax+4], 0`. Diff stayed 7. No closed-function regression. Reverted.
   **Accepted** 2026-09-16: leftover is addressing mode plus `test eax` vs `mov ebx, eax` / `test ebx`. `intentional-mismatch`, compiler-shaped leftover after exhausted source-shape list.

### `-[PS2Keyboard initWithController:]` (diff 7)

1. Apply the command-byte edit as three statements (`|= 0x40`, `&= 0xEF`, `|= 1`) immediately after `getKeyboardData()`, before `sendControllerCommand(0x60)`.
   **Kept, leftover accepted:** three-instruction form now matches; remaining starred row is `stru_40F0.ext` vs `super_class` (objc_super operand). Diff 7 → 1, not masked-eq. Rebuild `20C8BD6E1243FE4CB6D1CDCC51654CBADF65E118370ACBF8D49EBE05B3631C07`. `intentional-mismatch`.

### `-[PS2Keyboard readConfigTable:]` (diff 10)

1. Store the Interface/Handler defaults into the ivars inside each NULL branch (`interfaceId = 3`, `handlerId = 0`) instead of through `interfaceValue` / `handlerValue` locals.

### `_undoEscape` (diff 10)

1. Drop the `scancode` local; enqueue `sequence->keys[index * 2] | 0x80` as an expression after testing the extended byte, so gcc does not park the scancode in `[ebp+var_4]` before the `0xE0` test.

### `_getKeyboardDataIfPresent` (diff 12)

1. Branch on `keyboardDataPresent()` before the matching unlock, with explicit `return 1` / `return 0` on each path, instead of parking the BOOL and always unlocking first.

### `_enqueueKeyboardData` (diff 13)

1. Compare `keyboardFreeQueue.next == KBD_FREE_QUEUE` before loading `element`, matching the reference's `cmp ds:_keyboardFreeQueue` before `mov edx, ds:_keyboardFreeQueue`.

### `_getMouseDataIfPresent` (diff 14)

1. Replace the inverted `noMouseData` BOOL with `if (status & 0x20)` / else, returning 1 or 0 on each path (`test al, 20h` / `jz` vs `shr`/`xor`/`and`).

### `-[PS2Keyboard relinquishOwnership:]` (diff 20) — empty by policy

Task 8 regression gate. `--name` shows then/else order on `respondsTo:`, but do not rewrite the body. Accept without a source edit.

**Accepted** 2026-09-16: `intentional-mismatch`, compiler-shaped leftover after exhausted source-shape list.

### `-[PS2Keyboard dispatchKeyboardEvents]` (diff 27)

1. Signedness of the dispatch loop index: declare `i` as `int` so the count compare is `jl`/`jge` rather than `jb`/`jnb`.

### `-[PS2Keyboard enqueueKeyEvent:goingDown:atTime:]` (diff 31)

1. Park `timestamp`, `keyCode`, and `goingDown` in locals before computing the slot address (`sub esp, 10h` then four stores vs immediate indexed stores).

### `-[PS2Keyboard interruptOccurred]` (diff 32)

1. Keep `scancode` as `unsigned int` (signedness of a local) so the `scancodeToKeyEvent` argument is `and eax, 0FFh` / `push eax` rather than `movzx`.

### `_getKeyboardData` (diff 37)

1. Invert the empty-queue if/else so the hardware read is the `jnz` fall-through and the dequeue unlink is the taken path.

### `_isEscape` (diff 40)

1. Do not hoist `scancodeChar` / `extendedChar` locals; compare `key` bytes in place after the `currentSequence` test (`cmp byte ptr [ebp+arg_0]` vs stack extracts).

### `-[PS2Keyboard becomeOwner:]` (diff 43)

1. Invert the `_owner == nil` if/else so the already-owned / `respondsTo:` path is laid out first (`jz` to the grant vs `jnz` to the ask).

### `-[PS2Controller initFromDeviceDescription:]` (diff 48)

1. Inside the free-queue fill loop, branch empty vs non-empty insert (`if (keyboardFreeQueue.next == KBD_FREE_QUEUE)` set both links, else tail-insert).

### `_doEscape` (diff 50)

1. Test `data == 0xE0` before copying `lastExtended` into a local, matching the reference's `cmp dl, 0E0h` before the `mov al, ds:_lastExtended` else path.

### `_scancodeToKeyEvent` (diff 102)

1. Store each jump-table keycode into `event.keyCode` in the case body instead of a `keyCode` local (`mov ds:dword_213C, 62h` vs `mov bl, 62h`).
