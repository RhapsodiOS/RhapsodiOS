# drvBusMouse function worklist

Task 3 / Phase 2 snapshot. 2026-09-16. Kernel Server `Makefile.postamble`
wires `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. Source was not otherwise
edited.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `BusMouse_reloc` | 29796 | `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864` |
| Rebuilt `BusMouse_reloc` | 99112 | `5DC76B2EF94D3C24A8DBEAB4D1B7307B7A70C66D4A02ED0D3AB0448C48429A38` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvBusMouse` ended
`=== input-recon done fail=0 built: drvBusMouse ===` (`make exit=0`). The
staged object is unstripped Mach-O preload i386. `__TEXT,__text` is 1584
bytes; `__TEXT,__const` is still absent. SHA-256 is unchanged from the
Phase 1 baseline: `$(VERS_OFILE)` expanded empty, so `kl_ld` did not link
vers objects. This `_reloc` is not the campaign result; `ledger.json`
`rebuilt_sha256` is left unset.

The published IDA trio under `tools/binrecon/out/busmouse/published/` is from
this rebuilt SHA. Ghidra and angr stayed disabled.

## parity_check.py

| bucket | count |
| --- | --- |
| missing_strings | 0 |
| missing_symbols | 0 |
| extra_strings | 0 |
| extra_symbols | 17 |

The 17 extras are unstripped stabs (`BusMouse.m`, `io_inline.h`, generated
`BusMouse_instance.m`, and one `:fNN` line-number stab per function). Extra
unstripped symbols are not a failure.

## `binrecon function --list`

13 functions: 3 byte-identical, 10 differing, 0 unpaired. Identical to the
Phase 1 table. No locked regression-gate method lost `masked-eq` /
`identical`.

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

The Kernel Server postamble is in tree. `_BusMouse_VERS_STRING` /
`_BusMouse_VERS_NUM` and `__TEXT,__const` are still absent: guest
`VERSIONING_SYSTEM` is `next-sgs`, `/System/Developer/Makefiles/VersioningSystems`
has `apple-generic.make` and `next-cvs.make` only, so `$(VERS_OFILE)` is
empty. `BusMouse_vers.c` / `.o` were not generated and do not appear on the
`kl_ld` line. `driverTools` was not edited. Existence stays unmet; the
postamble line is kept. Findings 1–19 stay closed. The three named compiler
residuals (`_GetIRQFromBoard`, `_MouseIntHandler`,
`-[BusMouse setIntValues:forParameter:count:]`) remain for Phase 3.
