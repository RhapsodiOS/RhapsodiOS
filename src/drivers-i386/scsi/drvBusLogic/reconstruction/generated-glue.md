# BusLogic Kernel Server generated glue

The reference is `BusLogicSCSIDriver_reloc`, SHA-256
`4CF3A04BC07B7C1B41186BB057EF8376844C7AFA223EE46367418DE466564BC4`.
The project's `PB.project` declares `PROJECTTYPE = "Kernel Server"` and
`DYNAMIC_CODE_GEN = YES`; neither method below has a hand-written source site.

Both functions were inspected in IDA as 12-byte i386 functions. Their bodies
are straight-line accessors with a standard frame prologue and epilogue.

## `+[BusLogicSCSIDriverKernelServerInstance kernelServerInstance]`

Address `0x2014` (`8212`), size 12 bytes:

```asm
push    ebp
mov     ebp, esp
mov     eax, offset _BusLogicSCSIDriver_instance
mov     esp, ebp
pop     ebp
retn
```

IDA pseudocode returns the address of the generated global
`BusLogicSCSIDriver_instance`.

## `+[BusLogicSCSIDriverVersion driverKitVersionForBusLogicSCSIDriver]`

Address `0x2020` (`8224`), size 12 bytes:

```asm
push    ebp
mov     ebp, esp
mov     eax, 1F4h
mov     esp, ebp
pop     ebp
retn
```

IDA pseudocode returns `500` (`0x1F4`).

These generated methods remain unmapped in `source-map.json` because the
Kernel Server project emits them and there is no source definition to map.
Their reference control flow and results are reviewed here; assembly parity
remains unverified until a native i386 rebuild is available.
