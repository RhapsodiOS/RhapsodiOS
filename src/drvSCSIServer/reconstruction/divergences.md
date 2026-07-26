# drvSCSIServer divergences

Reference: `SCSIServer.config/SCSIServer_reloc`, SHA-256
`E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`, `__text`
13744 bytes.
Analysis: IDA 9.2 (`tools/binrecon/out/scsiserver-ppc/published/analysis-reference-ida.json`).
Ghidra and angr are i386-only and cannot analyse this binary.

No PowerPC build exists in this environment, so nothing recorded here is
compile-verified. Every claim rests on the reference disassembly.

## Starting state

| Bucket | Count | Bytes |
| --- | --- | --- |
| mapped | 41 | 5796 |
| unmapped | 27 | 5724 |
| duplicate_candidates | 0 | — |
| boundary_disputed | 0 | — |

## Out of scope

**138 jump islands.** IDA finds 206 functions; 138 are unnamed 16-byte
`lis`/`mr`/`mtctr`/`bctr` sequences — build-generated branch glue for calls that
exceed the PowerPC branch displacement. They are not source and are excluded
from the map by `filter_named_functions.py`. Note that a 16-byte size alone does
not identify one: `+[IOSCSISession controllerNameList]`, `-[IOSCSISession name]`
and `+[SCSIServerVersion driverKitVersionForSCSIServer]` are also 16 bytes.

**Two build-generated classes.**
`+[SCSIServerKernelServerInstance kernelServerInstance]` (address 13708, 20
bytes) and `+[SCSIServerVersion driverKitVersionForSCSIServer]` (13728, 16
bytes) are emitted by the Kernel Server build from the project's own settings,
not written by hand. They remain in the `unmapped` bucket permanently.

## The analyzer gap at address 0

`+[SCSIServer deviceStyle]` occupies address 0 in the symbol table, but IDA
emits no function entry there, so it cannot appear in `source-map.json` — the map
covers 68 functions, not the symbol table's 69. Our `SCSIServer.m:37` implements
it. This is the same mismatch `ppc_invariant_check.py --analysis` reported during
the binrecon PowerPC acceptance run, and it is an analyzer artifact, not a
missing function.
