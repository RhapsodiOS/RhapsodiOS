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
