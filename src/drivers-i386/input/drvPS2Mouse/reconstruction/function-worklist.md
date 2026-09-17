# drvPS2Mouse function worklist

Task 4 (Finding 14 handler-return half: `void`). 2026-09-16.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `PS2Mouse_reloc` | 30204 | `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E` |
| Rebuilt `PS2Mouse_reloc` | 94408 | `30CB12E57AB8774148915AA5954328A0C644D66407343ECA8877C0F350DBBA94` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvPS2Mouse` ended
`=== input-recon done fail=0 built: drvPS2Mouse ===`. The staged object is
unstripped Mach-O preload i386. `gnumake` used the same bootstrap-root `-I`
pair as Task 2/3 (guest copy of the harness only).

Live `System.framework` on the guest has no `PrivateHeaders`. The published IDA
trio under `tools/binrecon/out/ps2mouse/published/` is from this rebuilt SHA.

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
     2     13     13  masked-eq   -[PS2Mouse resetMouse]
     7     36     36              -[PS2Mouse getIntValues:forParameter:count:]
     9     37     37  masked-eq   -[PS2Mouse isMousePresent]
    18     65     65              -[PS2Mouse readConfigTable:]
    20     53     49              -[PS2Mouse setIntValues:forParameter:count:]
    26     54     52              -[PS2Mouse mouseInit:]
    35    108    108              -[PS2Mouse initWithController:]
   119    120    111              _PS2MouseIntHandler
```

Vs Task 3: `_PS2MouseIntHandler` 133/120/112 → **119/120/111**. Not
`raw_equal` / `masked_equal`; stays `intentional-mismatch` for Task 6.
`--name` rebuilt epilogue is `mov esp,ebp; pop ebp; retn` with no `xor eax,eax`.

## Regression gate

- `getHandler:level:argument:forInterrupt:` stayed `masked-eq`
- `getResolution` stayed `identical`
- `getIntValues:forParameter:count:` stayed at 7 diffs (not increased)
- `isMousePresent` stayed `masked-eq`
- `resetMouse` stayed `masked-eq`

Finding 14's handler-return half is now `void`. The missing `VERS_OFILE` line
is still in source.
