# drvPS2Mouse function worklist

Task 6 (cheapest-first grinding). 2026-09-17.

## Reloc

| | size (bytes) | SHA-256 |
| --- | --- | --- |
| Reference `PS2Mouse_reloc` | 30204 | `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E` |
| Rebuilt `PS2Mouse_reloc` | 94408 | `948DCB8066528D89F8E83B03C62B988769A9B92A0DFF6C2DF6B40AFB989EE771` |

Guest `sh /build/source/vm/build-i386-input-recon.sh drvPS2Mouse` ended
`=== input-recon done fail=0 built: drvPS2Mouse ===`. The staged object is
unstripped Mach-O preload i386. `gnumake` used the same bootstrap-root `-I`
pair as Task 2/3/4/5 (guest copy of the harness only).

This SHA is the kept `readConfigTable:` y/Y rewrite. The 8042
`statusByte &= 0xDF; statusByte |= 0x02` experiment was rebuilt, measured
(initWithController 35→30, not masked-eq), and reverted.

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
    12     65     65  masked-eq   -[PS2Mouse readConfigTable:]
    20     53     49              -[PS2Mouse setIntValues:forParameter:count:]
    26     54     52              -[PS2Mouse mouseInit:]
    35    108    108              -[PS2Mouse initWithController:]
   119    120    111              _PS2MouseIntHandler
```

Glue is still only the two generated `+[` methods. Do not hand-write them.

## Task 6 outcomes

| Function | Result |
| --- | --- |
| `getIntValues:forParameter:count:` | accepted: `edx` vs `eax` register allocation |
| `readConfigTable:` | matched: y/Y branch layout → `masked-eq` |
| `setIntValues:forParameter:count:` | accepted: 12-byte gcc spill of count/`parameterArray` |
| `mouseInit:` | accepted unreachable: store order already matches; leftover is early-return layout |
| `initWithController:` | accepted unreachable after one reverted and/or split |
| `_PS2MouseIntHandler` | accepted: `_func_list` vs `_controllerFunctions` and frame shape |
| `interruptOccurred` / `getHandler:` / `getResolution` / `isMousePresent` / `resetMouse` | already matching; skipped |

## Regression gate

- `getHandler:level:argument:forInterrupt:` stayed `masked-eq`
- `getResolution` stayed `identical`
- `isMousePresent` stayed `masked-eq`
- `resetMouse` stayed `masked-eq`
- `interruptOccurred` stayed `masked-eq`
- `getIntValues:forParameter:count:` stayed at 7 diffs

## Closing

6/11 hand-written functions are IDA masked-eq or identical:
`-[PS2Mouse getHandler:level:argument:forInterrupt:]`,
`-[PS2Mouse getResolution]`, `-[PS2Mouse interruptOccurred]`,
`-[PS2Mouse resetMouse]`, `-[PS2Mouse isMousePresent]`,
`-[PS2Mouse readConfigTable:]`. Five leftovers were accepted as compiler-shaped:
`-[PS2Mouse getIntValues:forParameter:count:]` (7 diffs, edx vs eax),
`-[PS2Mouse setIntValues:forParameter:count:]` (20 diffs, 53 vs 49, gcc spill),
`-[PS2Mouse mouseInit:]` (26 diffs, 54 vs 52, gcc early-return vs inline-error layout),
`-[PS2Mouse initWithController:]` (35/108, `_func_list` vs `_controllerFunctions` and jz/jnz / and-or layout),
`_PS2MouseIntHandler` (119/120 vs 111, `_func_list` vs `_controllerFunctions` and frame shape).
Two Kernel Server glue methods are generated (`kernelServerInstance` masked-eq,
`driverKitVersionForPS2Mouse` identical). Last kept rebuilt `PS2Mouse_reloc`
SHA-256 `948DCB8066528D89F8E83B03C62B988769A9B92A0DFF6C2DF6B40AFB989EE771`
(94408 bytes). `__TEXT,__const` is still absent: Task 5 wired
`OTHER_GENERATED_OFILES += $(VERS_OFILE)` but the guest has no
`next-sgs.make`, so `_PS2Mouse_VERS_STRING` / `_VERS_NUM` were not emitted.
Not yet tested on hardware.
