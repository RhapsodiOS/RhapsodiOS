# drvSerialPointingDevice function worklist

Phase 1 baseline. 2026-09-16. Branch `drvserialpointingdevice-binrecon-finish`.
Source was not edited for this snapshot.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `SerialPointingDevice_reloc` | 39928 | `59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59` |
| Rebuilt `SerialPointingDevice_reloc` | 112064 | `7A0D1052C9178CFE8DCD576605DA163ECF0835A4A28F04309CB30D459E7C8E64` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvSerialPointingDevice` ended
`=== input-recon done fail=0 built: drvSerialPointingDevice ===`. The staged
object is unstripped Mach-O preload i386. This `_reloc` is not the campaign
result; `ledger.json` `rebuilt_sha256` is left unset.

`validate` printed `reference ... sha256=59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`.
IDA-only analyze: `complete: true`, `normalized-functions=FAIL` (expected),
published trio `analysis-reference-ida.json`, `analysis-rebuilt-ida.json`,
`comparison-ida.json`. Rebuilt analysis SHA matches this `_reloc`.

## `__TEXT,__text`

| | size (bytes) |
| --- | --- |
| Reference | 4468 |
| Rebuilt | 4368 |

## `SerialPointingDevice` `instance_size`

356 (0x164), decoded from rebuilt `__OBJC,__class` (40-byte stride, name +
`instance_size`). Superclass `PCPointer`. Glue classes unchanged:
`SerialPointingDeviceVersion : IODevice` 264,
`SerialPointingDeviceKernelServerInstance : Object` 4.

## parity_check.py

| bucket | count |
| --- | --- |
| missing_strings | 0 |
| missing_symbols | 0 |
| extra_strings | 0 |
| extra_symbols | 21 |

The 21 extras are unstripped stabs, the two translation-unit names, and
local Objective-C method labels. Extra unstripped symbols are not a failure.

## `binrecon function --list`

18 functions: 3 byte-identical (`raw_equal`), 8 further `masked_equal`,
7 remaining, 0 unpaired.

```
  diff    ref    new  flags       name

     0      6      6  masked-eq   +[SerialPointingDeviceKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]
     0     14     14  masked-eq   -[SerialPointingDevice MMProtocol]
     0     10     10  masked-eq   -[SerialPointingDevice MPlusProtocol]
     0     14     14  masked-eq   -[SerialPointingDevice RBProtocol]
     0     14     14  masked-eq   -[SerialPointingDevice UnknownProtocol]
     0      7      7  identical   -[SerialPointingDevice getResolution]
     0     12     12  identical   _mainLoop
     2     28     28  masked-eq   -[SerialPointingDevice setEventTarget:]
     3     31     31  masked-eq   -[SerialPointingDevice free]
     7     43     43              -[SerialPointingDevice getByte:sleep:]
    15     76     76  masked-eq   -[SerialPointingDevice mainLoop:]
    42     36     56              -[SerialPointingDevice getIntValues:forParameter:count:]
    58    248    249              -[SerialPointingDevice mouseInit:]
    75    129    128              -[SerialPointingDevice MSProtocol]
    80     85    108              -[SerialPointingDevice setIntValues:forParameter:count:]
   118    161    112              -[SerialPointingDevice FiveBProtocol]
   239    404    405              -[SerialPointingDevice detect]
```

No ledger status was advanced from this table.

## July `assembly-matched` regression gate

All five July claims are `raw_equal` or `masked_equal` on this `_reloc`:

| Address | Function | This run |
| --- | --- | --- |
| 1016 | `-[SerialPointingDevice getResolution]` | `identical` (`raw_equal`) |
| 3700 | `-[SerialPointingDevice MPlusProtocol]` | `masked-eq` |
| 4324 | `-[SerialPointingDevice MMProtocol]` | `masked-eq` |
| 4364 | `-[SerialPointingDevice RBProtocol]` | `masked-eq` |
| 4404 | `-[SerialPointingDevice UnknownProtocol]` | `masked-eq` |

Those five plus `_mainLoop` (`identical`) are the instruction-stream
regression gate. The two glue methods stay generated (`intentional-mismatch`).

## Is this reachable?

Cheapest remaining rows, source-shaped vs compiler-shaped:

- `getByte:sleep:` (7 diffs, 43/43). Compiler-shaped. CFG already matches
  Finding 8's `do`/`while`. The live diffs are `data` at `[ebp+var_8]` vs
  `[ebp+var_5]` and jump labels — stack-slot packing of `unsigned char data`.
- `getIntValues:forParameter:count:` (42 diffs, 36 vs 56). Source-shaped.
  Reference is `cld`/`cmpsb` against `"Resolution"` / `"Inverted"`; ours is
  the counted char loop. Same class of rewrite drvPS2Mouse landed with
  `strcmp`.
- `mouseInit:` (58 diffs, 248 vs 249). Mostly compiler-shaped: nearly equal
  length; early failure returns `xor eax,eax` in place vs a shared epilogue
  jump; string reloc names differ. Not a missing path at the prologue.
- `MSProtocol` (75 diffs, 129 vs 128). Compiler-shaped: frame `sub esp,28h`
  vs `30h`, `esi` allocation, extra spilled locals. Counts nearly equal.
- `setIntValues:forParameter:count:` (80 diffs, 85 vs 108). Source-shaped:
  the same `cmpsb` vs counted loop as `getIntValues:`; reference also spills
  the compare count to `[ebp+var_4]`.
- `FiveBProtocol` (118 diffs, 161 vs 112). Source-shaped overall: prologue
  register allocation is compiler noise, but the 49-instruction deficit is
  the compact `ns_time_t` subtract / `switch` vs the reference jump table
  and expanded 64-bit compare.
- `detect` (239 diffs, 404 vs 405). Compiler-shaped scheduling in a large
  function: same frame size, instruction counts nearly equal, first diff is
  `xor edi,edi` moved a few slots.

`setEventTarget:`, `free`, and `mainLoop:` already `masked_equal` (display
`diff` 2 / 3 / 15 is unmasked labels / relocs). They are not grind targets
for source edits.
