# drvBusMouse function worklist

Task 3 / Phase 2 snapshot after `VERSIONING_SYSTEM = apple-generic`.
2026-09-16. Kernel Server `Makefile.postamble` still wires
`OTHER_GENERATED_OFILES += $(VERS_OFILE)`. Source was not otherwise edited.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `BusMouse_reloc` | 29796 | `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864` |
| Rebuilt `BusMouse_reloc` | 100372 | `2EAA0112FDA184A6F13305EB6438E2A20C6125D1DF37FB370868824D8C2FC1F9` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvBusMouse` ended
`=== input-recon done fail=0 built: drvBusMouse ===` (`make exit=0`). The
staged object is unstripped Mach-O preload i386. `__TEXT,__text` is 1584
bytes; `__TEXT,__const` is **92** bytes. `BusMouse_vers.c` was generated and
`BusMouse_vers.o` is on the `kl_ld` line. This `_reloc` is not the campaign
result; `ledger.json` `rebuilt_sha256` is left unset.

The published IDA trio under `tools/binrecon/out/busmouse/published/` is from
this rebuilt SHA. Ghidra and angr stayed disabled.

## parity_check.py

| bucket | count |
| --- | --- |
| missing_strings | 0 |
| missing_symbols | 0 |
| extra_strings | 0 |
| extra_symbols | 18 |

The 18 extras are unstripped stabs (`BusMouse.m`, `io_inline.h`, generated
`BusMouse_instance.m`, generated `BusMouse_vers.c`, and one `:fNN`
line-number stab per function). Extra unstripped symbols are not a failure.

## `binrecon function --list`

13 functions: 3 byte-identical, 10 differing, 0 unpaired. Instruction-diff
table is identical to Phase 1. No locked regression-gate method lost
`masked-eq` / `identical`.

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

No ledger status was advanced from this table.

Regression gate on this run: `validConfiguration:`, `interruptHandler`,
`_BusMouseThread`, `mouseInit:`, `free`,
`getHandler:level:argument:forInterrupt:` are `masked-eq`; `getResolution`
is `identical`. `getIntValues:forParameter:count:` still has 7 instruction
diffs (no `masked-eq`); that is not a Task 3 regression. Glue stays
generated.

## Is this reachable?

`__TEXT,__const` exists. The nlist carries apple-generic
`_BusMouseVersionString` and `_BusMouseVersionNumber` (external, in
`__TEXT,__const`). The SGS names `_BusMouse_VERS_STRING` /
`_BusMouse_VERS_NUM` are still absent — same leftover as Cirrus; do not
match the 160-byte string to Apple's. `driverTools` was not edited.
Findings 1–19 stay closed. The three named compiler residuals
(`_GetIRQFromBoard`, `_MouseIntHandler`,
`-[BusMouse setIntValues:forParameter:count:]`) remain for Phase 3.
