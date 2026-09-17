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
object is unstripped Mach-O preload i386. This Finish `_reloc` is 112064 bytes
and supersedes July's 112072. It is not the campaign result; `ledger.json`
`rebuilt_sha256` is left unset.

`validate` printed `reference ... sha256=59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`.
IDA-only analyze: `complete: true`, `normalized-functions=FAIL` (expected),
published trio `analysis-reference-ida.json`, `analysis-rebuilt-ida.json`,
`comparison-ida.json`. Rebuilt analysis SHA matches this `_reloc`.

## Task 4 (`VERS_OFILE`)

2026-09-16. Kernel Server postamble added. Guest `fail=0`. Reloc size and
SHA-256 **unchanged** from the table above: `VERS_OFILE` expanded empty
(see `divergences.md` Task 4). `_SerialPointingDevice_VERS_STRING` /
`_SerialPointingDevice_VERS_NUM` MISSING; no `__TEXT,__const`.
`parity_check.py` still 0 / 0. `--list` identical to the baseline table
below; the nine hand-written gates still `identical` / `masked-eq`.
`rebuilt_sha256` left unset.

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

18 functions: 3 identical + 8 further masked = **11 `masked_equal` total**,
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

## Baseline regression gate

Any hand-written row that is `raw_equal` or `masked_equal` is a gate.
The nine non-glue equals:

| Address | Function | This run |
| --- | --- | --- |
| 1016 | `-[SerialPointingDevice getResolution]` | `identical` (`raw_equal`) |
| 0 | `_mainLoop` | `identical` (`raw_equal`) |
| 3700 | `-[SerialPointingDevice MPlusProtocol]` | `masked-eq` |
| 4324 | `-[SerialPointingDevice MMProtocol]` | `masked-eq` |
| 4364 | `-[SerialPointingDevice RBProtocol]` | `masked-eq` |
| 4404 | `-[SerialPointingDevice UnknownProtocol]` | `masked-eq` |
| 1032 | `-[SerialPointingDevice setEventTarget:]` | `masked-eq` |
| 908 | `-[SerialPointingDevice free]` | `masked-eq` |
| 1464 | `-[SerialPointingDevice mainLoop:]` | `masked-eq` |

The two glue methods stay generated (`intentional-mismatch`) and are not
grind targets: `+[SerialPointingDeviceKernelServerInstance kernelServerInstance]`
(`masked-eq`) and `+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]`
(`identical`).

July's five `assembly-matched` rows all held and sit inside this nine.
`_mainLoop`, `setEventTarget:`, `free`, and `mainLoop:` are the additional
hand-written equals from this baseline.

## Is this reachable?

Cheapest remaining rows, source-shaped vs compiler-shaped:

- `getByte:sleep:` (7 diffs, 43/43). Compiler-shaped. CFG already matches
  Finding 8's `do`/`while`. The live diffs are `data` at `[ebp+var_8]` vs
  `[ebp+var_5]` and jump labels — stack-slot packing of `unsigned char data`.
  One declaration-order try (`IOReturn ret`, `int eventType`, `unsigned char data`), then accept as stack packing.
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

Source-shaped grind order after `getByte:sleep:`'s one-shot:

- `getIntValues:forParameter:count:`
- `setIntValues:forParameter:count:`
- `FiveBProtocol`

`mouseInit:`, `MSProtocol`, and `detect` stay compiler-shaped leftovers,
not grind targets unless a later dump shows a source-level hole.

## Task 5 experiment lists (before first source edit)

Cheapest remaining first. One idea per function; add more only after a miss.

| Function | Experiment |
| --- | --- |
| `getByte:sleep:` | Declaration-order: `unsigned char data` then `IOReturn ret` then `int eventType` (live order is already ret/eventType/data; a no-op is not a try). Then accept as stack packing. **Tried: miss** (still `lea eax, [ebp+var_5]` vs ref `[ebp+var_8]`; 7 diffs; gates held). Reverted. **Accepted** as stack packing. |
| `getIntValues:forParameter:count:` | Replace counted char loops with `strcmp(parameterName, RESOLUTION)` / `INVERTED` (drvPS2Mouse Finding 15). **Kept:** `strcmp` + store through `*parameterArray` (no `value` local) → **masked-eq** 4/36/36. |
| `setIntValues:forParameter:count:` | Same `strcmp` rewrite. Keep verbose logs and the existing stores/sends. Do not add dummy spills. **Kept `strcmp`.** Leftover is gcc spilling `ecx=0Bh` to `[ebp+var_4]` plus register allocation (31 diffs, 85 vs 81). Dummy spills forbidden. **Accepted.** |
| `FiveBProtocol` | Split combined `case 2:`/`case 4:` into distinct cases so gcc can emit a 5-entry jump table; `lastTimeStamp = currentTimeStamp` stays in case 2 only. **Kept** split + `switch (byteIndex++)` (diffs 118→103; dispatch now `inc esi` / `jmp ds:jpt_*[edx*4]`). Sync-if polarity no-op. Leftover: frame 24h vs 28h, `and dl` vs `and edx`, `setnz` vs if. **Accepted.** |
| `mouseInit:` | Compiler-shaped. Dump `--name` only; grind only if a source-level hole appears. **Accepted** (shared vs in-place failure epilogue, cstring reloc names). |
| `MSProtocol` | Compiler-shaped. Dump `--name` only; optional `maskedByte` fold / default fallthrough only if that dump shows they are the cheapest source-shaped leftover. In-place mask + `switch(byteIndex++)` tried; diffs rose 74→75/80. **Reverted. Accepted.** |
| `detect` | Compiler-shaped. Dump `--name` only; optional inline `byte & 0x3F` only if that dump shows a source-level hole. **Accepted** (`xor edi` scheduling). |

## Task 5 results

Guest `fail=0`. Reloc 111660 bytes, SHA-256
`D6D751BA6A1015D93B65CD72CD18F61924A6517CC67279B1129E38EB1939D30F`.
`parity_check.py` 0 / 0. Nine original gates plus `getIntValues:` stayed
`identical` / `masked-eq`. 0 unpaired besides generated glue. No
layout/linkage growth.

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
     4     36     36  masked-eq   -[SerialPointingDevice getIntValues:forParameter:count:]
     7     43     43              -[SerialPointingDevice getByte:sleep:]
    15     76     76  masked-eq   -[SerialPointingDevice mainLoop:]
    31     85     81              -[SerialPointingDevice setIntValues:forParameter:count:]
    58    248    249              -[SerialPointingDevice mouseInit:]
    74    129    128              -[SerialPointingDevice MSProtocol]
   103    161    177              -[SerialPointingDevice FiveBProtocol]
   239    404    405              -[SerialPointingDevice detect]
```

18 functions: 3 identical + 8 further masked = **11 `masked_equal` total**,
5 remaining accepted as compiler-shaped leftovers, 0 unpaired.

Stop condition: unpaired is only the two generated glue methods; every other
hand-written row is identical, masked_equal, or accepted. No unexamined
hand-written function.
