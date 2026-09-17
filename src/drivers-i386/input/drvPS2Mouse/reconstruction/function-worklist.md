# drvPS2Mouse function worklist

Phase 1 baseline. 2026-09-16. Source was not edited for this snapshot.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `PS2Mouse_reloc` | 30204 | `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E` |
| Rebuilt `PS2Mouse_reloc` | 94604 | `78273466617EE2960E4912D22F386BDBA295DB7863E985D172A1D063B3899473` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvPS2Mouse` ended
`=== input-recon done fail=0 built: drvPS2Mouse ===`. The staged object is
unstripped Mach-O preload i386. This `_reloc` is not the campaign result;
`ledger.json` `rebuilt_sha256` is left unset.

Live `System.framework` on the guest has no `PrivateHeaders`. The compile
used the same bootstrap-root `-I` pair as the SCSI reconstructions
(`Versions/B/PrivateHeaders` and `Versions/B/Headers`). The published IDA
trio under `tools/binrecon/out/ps2mouse/published/` is from this rebuilt
SHA, not leftover Ghidra/angr files.

## parity_check.py

| bucket | count |
| --- | --- |
| missing_strings | 0 |
| missing_symbols | 0 |
| extra_strings | 0 |
| extra_symbols | 16 |

The 16 extras are unstripped locals, stabs, and the two build-generated glue
methods. Extra unstripped symbols are not a failure.

## `binrecon function --list`

13 functions: 2 byte-identical, 11 differing, 0 unpaired.

```
  diff    ref    new  flags       name

     0      6      6  masked-eq   +[PS2MouseKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[PS2MouseVersion driverKitVersionForPS2Mouse]
     0     12     12  masked-eq   -[PS2Mouse getHandler:level:argument:forInterrupt:]
     0      7      7  identical   -[PS2Mouse getResolution]
     1     15     15  masked-eq   -[PS2Mouse interruptOccurred]
     4     13     15              -[PS2Mouse resetMouse]
     7     36     36              -[PS2Mouse getIntValues:forParameter:count:]
    11     37     39              -[PS2Mouse isMousePresent]
    18     65     65              -[PS2Mouse readConfigTable:]
    20     53     49              -[PS2Mouse setIntValues:forParameter:count:]
    26     54     52              -[PS2Mouse mouseInit:]
    83    108    125              -[PS2Mouse initWithController:]
   133    120    114              _PS2MouseIntHandler
```

No ledger status was advanced from this table.

## Is this reachable?

This snapshot is pre-fix. Finding 13's `controllerFunctions` null guards,
Finding 14's `unsigned int` / `return 0` interrupt handler, and the missing
`VERS_OFILE` line are still in source. Phases 2–4 reverse those three; this
worklist is the regression baseline to measure them against, not a claim
that the remaining diffs are already closed.

The three previously `assembly-matched` methods on this run:
`getHandler:level:argument:forInterrupt:` is `masked-eq`, `getResolution`
is `identical`, and `getIntValues:forParameter:count:` still has 7
instruction diffs (no `masked-eq`). Glue stays generated.
