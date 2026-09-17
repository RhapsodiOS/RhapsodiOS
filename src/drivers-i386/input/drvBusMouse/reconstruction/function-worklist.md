# drvBusMouse function worklist

Task 4 / Phase 3 cheapest-first grinding.
2026-09-16. `BusMouse.m` was not kept-changed: every source experiment
was reverted. Kernel Server apple-generic versioning from Task 3 stays.
`source-map.json` addresses and line numbers are unchanged.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `BusMouse_reloc` | 29796 | `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864` |
| Rebuilt `BusMouse_reloc` | 100372 | `55BB1C543C383A311E57447DDD6B722D251ED577D2769BC9ECD0475334C9815D` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvBusMouse` ended
`=== input-recon done fail=0 built: drvBusMouse ===` (`make exit=0`).
Unstripped Mach-O preload i386. `__TEXT,__text` is 1584 bytes;
`__TEXT,__const` is **92** bytes. The SHA differs from Task 3's
`2EAA0112…` because `BusMouse_vers.c` embeds a new build timestamp.
Instruction-diff table is unchanged from Phase 1 / Task 3.
`ledger.json` `rebuilt_sha256` records this SHA. This is an
instruction-stream finish, not a byte-identity campaign result.

The published IDA trio under `tools/binrecon/out/busmouse/published/`
is from this rebuilt SHA. Ghidra and angr stayed disabled.

## parity_check.py

| bucket | count |
| --- | --- |
| missing_strings | 0 |
| missing_symbols | 0 |
| extra_strings | 0 |
| extra_symbols | 18 |

The 18 extras are unstripped stabs. Extra unstripped symbols are not a
failure.

## `binrecon function --list`

13 functions: 3 byte-identical, 10 differing, 0 unpaired. Glue is still
only the two generated class methods. No locked regression-gate method
lost `masked-eq` / `identical`.

```
  diff    ref    new  flags       name

     0      6      6  identical   +[BusMouseKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[BusMouseVersion driverKitVersionForBusMouse]
     0     15     15  masked-eq   -[BusMouse free]
     0     12     12  masked-eq   -[BusMouse getHandler:level:argument:forInterrupt:]
     0      7      7  identical   -[BusMouse getResolution]
     1     15     15  masked-eq   -[BusMouse interruptHandler]
     4     43     43  masked-eq   -[BusMouse validConfiguration:]
     6     43     43  masked-eq   _BusMouseThread
     7     36     36              -[BusMouse getIntValues:forParameter:count:]
    10    108    108  masked-eq   -[BusMouse mouseInit:]
    20     53     49              -[BusMouse setIntValues:forParameter:count:]
    22    114    112              _MouseIntHandler
    24     42     46              _GetIRQFromBoard
```

Regression gate: `validConfiguration:`, `interruptHandler`,
`_BusMouseThread`, `mouseInit:`, `free`,
`getHandler:level:argument:forInterrupt:` are `masked-eq`;
`getResolution` is `identical`.

## Grind dispositions

| function | IDA diffs | disposition |
| --- | ---: | --- |
| `getIntValues:forParameter:count:` | 7 | **accept** — gcc register allocation (`edx` vs `eax` for the stored value) and jump labels. Same calls, constants, offsets. |
| `setIntValues:forParameter:count:` | 20 | **accept** — gcc hoist/spill of `parameterArray` and the compare count. Ours smaller (49 vs 53). No missing call, no wrong offset. Starter list treated as empty. |
| `_MouseIntHandler` | 22 | **accept / unreachable** — Exp 1–3 tried, all reverted. Leftover is widen-before-xor, right-button spill, extra `and al,1`, frame size. |
| `_GetIRQFromBoard` | 24 | **accept / unreachable** — Exp 1–4 tried, all reverted. Leftover is gcc spilling the masked nibble to `[ebp-8]` and putting the result in `ecx` instead of `ebx`. |

Ledger: 7 `assembly-matched` (the locked gates), 6 `intentional-mismatch`
(`getIntValues:`, `setIntValues:`, `_MouseIntHandler`, `_GetIRQFromBoard`,
plus the two glue methods). See `divergences.md` Task 4.

## Is this reachable?

`__TEXT,__const` exists with apple-generic `_BusMouseVersionString` /
`_BusMouseVersionNumber`. SGS `_BusMouse_VERS_*` names remain absent —
accepted leftover, same as Cirrus. `driverTools` was not edited.
Findings 1–19 stay closed. The four remaining IDA diffs are gcc 2.7
allocation / spill / scheduling and are recorded unreachable.

## Closing

7/11 hand-written functions are IDA masked-eq or identical:
`-[BusMouse validConfiguration:]`, `-[BusMouse interruptHandler]`,
`_BusMouseThread`, `-[BusMouse mouseInit:]`, `-[BusMouse free]`,
`-[BusMouse getHandler:level:argument:forInterrupt:]`,
`-[BusMouse getResolution]`. Four leftovers were accepted as gcc 2.7
register allocation / spill / scheduling:
`-[BusMouse getIntValues:forParameter:count:]` (edx vs eax store),
`-[BusMouse setIntValues:forParameter:count:]` (parameterArray/count hoist),
`_MouseIntHandler` (button-decode scheduling), `_GetIRQFromBoard`
(masked-nibble spill). Two Kernel Server glue methods are generated.
Last kept rebuilt `BusMouse_reloc` SHA-256
`55BB1C543C383A311E57447DDD6B722D251ED577D2769BC9ECD0475334C9815D`
(100372 bytes). Apple-generic `_BusMouseVersionString` /
`_BusMouseVersionNumber` are present; SGS `_BusMouse_VERS_*` names are
absent. Not yet tested on hardware.

