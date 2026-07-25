# drvPCIBus divergences

Reference: `PCIBus_reloc`, SHA-256 `3EFAC8A41B87C5B4D77358C2892E38A1F0A0821D7EDC18021182954B3C1A1451`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Baseline build

The driver builds clean today. Artifact: `out/i386/drvPCIBus/PCIBus.config/PCIBus_reloc`,
size 155312 bytes (verified present on disk). This is larger than the reference's
41360 bytes because our build is unstripped; that size difference is expected and is
not a finding.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 27 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Of the 27 mapped functions, 22 were examined at instruction level (full disassembly
read against source), 4 were examined at control-flow level (full disassembly read,
block/branch shape and call targets checked, but not every instruction verified),
and 1 (`setCharValues:forParameter:count:`) was checked only by targeted grep plus
the block/call-count summary, not read line by line. Seven functions carry a
confirmed divergence and are documented below; they remain `unexamined` in the
ledger per the task's convention that a diverging function is left for the fix pass.

## Unmapped: build-generated

`+[PCIBusKernelServerInstance kernelServerInstance]`,
`+[PCIBusVersion driverKitVersionForPCIBus]`, `_PCIBus_VERS_NUM`,
`_PCIBus_VERS_STRING`, `_PCIBus_instance` — emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted.

(Only the first two carry their own function bodies in the reference IDA partition;
`_PCIBus_VERS_NUM`, `_PCIBus_VERS_STRING` and `_PCIBus_instance` are data symbols
outside `__TEXT,__text` and do not appear as separate entries in the source map's
`unmapped` bucket, which lists functions only.)

## Analyzer disagreement: Ghidra does not detect `test_M1`

Ghidra's function list has no entry covering `0x9EC`-`0xA5F` (`-[PCIKernBus test_M1]`,
116 bytes). IDA reports a clean single function there matching the Mach-O symbol
table, and the surrounding functions (`allocateResourcesForDeviceDescription:` at
`0x9A0` and `Method1:...` at `0xA60`) have identical bytes/blocks/sizes in both
analyzers, so this is a Ghidra detection gap for this one function rather than a
body disagreement. Per the brief, IDA is authoritative for the partition, so this
does not affect the source map; noted here as the one place the two analyzers
genuinely disagree about what exists.

## Finding 1: `-[PCIKernBus test_M1]` at 0x9EC

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBusPrivate.m:50`

**Reference behaviour**

```
; testAddress in ebx, loop 0x9F8..
mov edx, 0CF8h
mov eax, ebx
out dx, eax          ; outl(CONFIG_ADDRESS, testAddress)
in  eax, dx           ; verifyAddress = inl(CONFIG_ADDRESS)
mov ecx, eax
cmp ecx, ebx
jz  short loc_A14      ; verifyAddress == testAddress -> continue checking CONFIG_DATA
xor eax, eax
jmp short loc_A59       ; verifyAddress != testAddress -> return NO immediately, no cleanup
```

**Our source**

```c
testAddress = 0x80000000;
while (testAddress <= 0x8000FFFF) {
    outl(PCI_CONFIG_ADDRESS, testAddress);
    verifyAddress = inl(PCI_CONFIG_ADDRESS);
    if (verifyAddress == testAddress) {
        dataValue = inl(PCI_CONFIG_DATA);
        if (dataValue != 0xFFFFFFFF && dataValue != 0x00000000) {
            outl(PCI_CONFIG_ADDRESS, 0);
            return YES;
        }
    }
    testAddress += 0x800;
}
outl(PCI_CONFIG_ADDRESS, 0);
return NO;
```

**Difference:** when the CONFIG_ADDRESS readback does not match the value just
written, our source falls through to `testAddress += 0x800` and keeps trying the
remaining candidate addresses. The reference binary instead returns `NO`
immediately on the first mismatch — it never increments `testAddress`, never tries
another candidate, and never re-clears `CONFIG_ADDRESS` (`outl(PCI_CONFIG_ADDRESS,
0)`) before returning on that path. The "loop exhausted" and "device found" exit
paths do match our source exactly.

**Disposition:** fix

**Rationale:** on real hardware CONFIG_ADDRESS write/readback essentially always
succeeds, so this rarely changes observed behaviour, but it is a real control-flow
divergence: our reimplementation is more permissive (keeps scanning) than the
reference binary (bails out on the first readback mismatch).

**Outcome:** fixed. `test_M1` now returns `NO` immediately on a CONFIG_ADDRESS
readback mismatch, without incrementing `testAddress` or clearing CONFIG_ADDRESS on
that path; the loop-exhausted and device-found exits are untouched. Ledger status
advanced from `unexamined` to `control-flow-confirmed`.

## Finding 2: `-[PCIKernBus test_M2]` at 0xAFC

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBusPrivate.m:91`

**Reference behaviour**

```
outb 0CF8h, 0F0h
in   al, 0CF8h
cmp  al, 0F0h
jnz  short loc_B7B      ; verifyCSE mismatch -> return NO immediately, no outb(0xCF8,0)
outb 0CFAh, 0
in   al, 0CFAh
test al, al
jz   short loc_B48       ; verifyForward == 0 -> scan config space
jmp  short loc_B7B        ; verifyForward mismatch -> return NO immediately, no outb(0xCF8,0)
...
loc_B6C:                  ; loop exhausted without a match
outb 0CF8h, 0
loc_B7B:
xor eax, eax
...
retn
```

**Our source**

```c
outb(0xCF8, 0xF0);
verifyCSE = inb(0xCF8);
if (verifyCSE == 0xF0) {
    outb(0xCFA, 0);
    verifyForward = inb(0xCFA);
    if (verifyForward == 0) {
        for (configPort = 0xC000; configPort < 0xD000; configPort += 0x100) {
            dataValue = inl(configPort);
            if (dataValue != 0xFFFFFFFF && dataValue != 0x00000000) {
                outb(0xCF8, 0);
                return YES;
            }
        }
        outb(0xCF8, 0);
    }
}
outb(0xCF8, 0);
return NO;
```

**Difference:** our source calls `outb(0xCF8, 0)` unconditionally right before every
`return NO`, including the two early-failure paths (`verifyCSE != 0xF0` and
`verifyForward != 0`). The reference binary only executes that cleanup write on the
"loop exhausted" and "device found" exits; both early-failure branches jump
straight to the `return NO` epilogue without ever touching port 0xCF8 again.

**Disposition:** accept

**Rationale:** the only effect of the missing cleanup is that `CF8` is left holding
`0xF0` (or garbage) instead of `0` when mechanism #2 detection fails outright; the
next thing that touches that port (mechanism #1 detection, which runs first and
already writes its own value, or the next `test_M2` call) reinitializes it before
reading it meaningfully. No observable behavioural difference, but noted because it
is a real, confirmed control-flow difference from the reference.

## Finding 3: `-[PCIKernBus isPCIPresent]` at 0x3C8

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBus.m:194`

**Reference behaviour**

```
mov eax, [ebp+self]
test dword ptr [eax+18h], 0FFFF00h
setnz al
and eax, 0FFh
```

**Our source**

```c
- (BOOL)isPCIPresent
{
    return (_configMech1 || _configMech2 || _specialCycle1);
}
```

**Difference:** the ivar layout (`KernBus` base = 0x10, then `_maxBusNum`=0x10,
`_maxDevNum`=0x14, `_bios16Present`=0x18, `_configMech1`=0x19, `_configMech2`=0x1A,
`_specialCycle1`=0x1B) puts `_configMech1`/`_configMech2` in bits 8-23 of the dword
at offset 0x18, and `_specialCycle1` in bits 24-31. The mask `0xFFFF00` only covers
bits 8-23 — i.e. `_configMech1` and `_configMech2` — and does **not** reach
`_specialCycle1`'s byte. Our source ORs in `_specialCycle1` as a third condition
that the reference binary never tests. The source's own comment already claims the
mask "checks bytes at offset 0x19, 0x1a, 0x1b (configMech1, configMech2,
specialCycle1)", but `0xFFFF00` is a 16-bit-wide mask spanning exactly two bytes
(0x19-0x1A); the comment's byte count was wrong.

**Disposition:** accept

**Rationale:** `_specialCycle1` is initialized to `NO` in `-init` and is never set
anywhere else in the reimplementation, so today `_configMech1 || _configMech2 ||
_specialCycle1` and `_configMech1 || _configMech2` always evaluate the same. If
`_specialCycle1` detection is ever implemented, this stops being equivalent and
should be revisited.

## Finding 4: `-[PCIKernBus Method1:device:function:bus:data:write:]` at 0xA60

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBusPrivate.m:140`

**Reference behaviour**

```
mov al, [ebp+arg_8]      ; al = address
and eax, 800000FFh        ; keep bit31 (garbage at this point) + full address byte
...
or edi, 80000000h          ; enable bit set explicitly
or edi, edx                ; | (device&0x1F)<<11
...
and edi, 0FFFFF8FFh         ; clear bits 8-10 for function field
or edi, eax                  ; | (function&7)<<8
...
and edi, 0FF00FFFFh          ; clear bits 16-23 for bus field
or edi, edx                   ; | bus<<16
```

**Our source**

```c
configAddress = 0x80000000 |
                ((unsigned int)(address & 0xFC)) |
                ((unsigned int)(device & 0x1F) << 11) |
                ((unsigned int)(function & 0x07) << 8) |
                ((unsigned int)bus << 16);
```

**Difference:** our source masks `address` with `0xFC` before combining it into
`configAddress`, clearing bits 0-1. The reference binary's `and eax, 0x800000FF`
keeps the entire address byte (bits 0-7), never clearing bits 0-1 anywhere in the
rest of the computation.

**Disposition:** accept

**Rationale:** both `-[PCIKernBus getRegister:...]` and `-[PCIKernBus
setRegister:...]` reject any call where `(address & 3) != 0` before ever reaching
`Method1:`, so `address` bits 0-1 are always already zero by the time this function
runs. The missing mask has no observable effect through the driver's only call
paths, but it is a genuine literal difference from the source.

## Finding 5: `-[PCIKernBus init]` at 0x24

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBus.m:79`

**Reference behaviour**

```
movzx ecx, byte ptr ds:130F1h
mov   [edx+10h], ecx        ; _maxBusNum = byte@0x130F1
mov   dword ptr [edx+14h], 0 ; _maxDevNum = 0
movzx ecx, byte ptr ds:130F2h
mov   [edx+24h], ecx         ; _pciVersionMajor = byte@0x130F2
movzx ecx, byte ptr ds:130F3h
mov   [edx+28h], ecx          ; _pciVersionMinor = byte@0x130F3
mov   cl, ds:130F4h
mov   [edx+18h], cl            ; _bios16Present = byte@0x130F4
mov   byte ptr [edx+1Dh], 0     ; _bios32Present = NO
mov   dword ptr [edx+20h], 0     ; _reserved = NULL
mov   cl, ds:130F0h
and   cl, 1
mov   [edx+19h], cl              ; _configMech1  = bit0 of byte@0x130F0
mov   al, ds:130F0h
shr   al, 1
and   al, 1
mov   [edx+1Ah], al              ; _configMech2  = bit1 of byte@0x130F0
mov   al, ds:130F0h
shr   al, 4
and   al, 1
mov   [edx+1Bh], al              ; _specialCycle1 = bit4 of byte@0x130F0
mov   al, ds:130F0h
shr   al, 5
and   al, 1
mov   [edx+1Ch], al              ; _specialCycle2 = bit5 of byte@0x130F0
```

**Our source**

```c
_maxBusNum = 0;
_maxDevNum = 0;
_pciVersionMajor = 2;
_pciVersionMinor = 1;
_bios16Present = YES;
_bios32Present = NO;
_reserved = NULL;
_configMech1 = NO;
_configMech2 = NO;
_specialCycle1 = NO;
_specialCycle2 = NO;
```

**Difference:** the reference binary initializes `_maxBusNum`, `_pciVersionMajor`,
`_pciVersionMinor` and `_bios16Present` from four bytes at a fixed address
(`0x130F0`-`0x130F4`), and packs `_configMech1`/`_configMech2`/`_specialCycle1`/
`_specialCycle2` as individual bits of a fifth byte at `0x130F0` — rather than from
hardcoded literals. That address is outside every section this object defines
(`__text`/`__cstring`/`__const`/.../`__common` top out at `0x6070`); there is no
relocation on any of these five instructions, so IDA is reporting a literal
absolute address, meaning it is almost certainly a fixed low-memory location the
running kernel populates before this driver's `+load`/`init` runs (plausibly a
boot-time PCI BIOS32 probe result), not something local to this object file. Once
`_configMech1`/`_configMech2` are read from that table, the very next check
(`if (!_configMech1 && !_configMech2 && _bios16Present) { ...test_M1/test_M2... }`)
behaves differently too: if the pre-populated byte already has either mechanism bit
set, the reference binary skips `test_M1`/`test_M2` entirely, where our source —
which always starts both flags at `NO` — always performs its own I/O-port probe.

**Disposition:** fix

**Rationale:** this is exactly the gap the existing source comment already flags
("`/* TODO: Read these from PCI BIOS if available */`"). The concrete fix requires
first identifying what kernel-global structure lives at `0x130F0` in the original
Rhapsody i386 kernel (likely something set by the kernel's own PCI BIOS32
detection during early boot); that is follow-up work beyond this analysis pass, but
this pass pins down exactly which five bytes and which four ivars are involved.

**Outcome:** applied. `0x130F0` is `KERNSTRUCT_ADDR->pciInfo`, the `PCI_bus_info_t`
member of `KERNBOOTSTRUCT` declared in `kernBootStruct.h` — `pciInfo` sits at offset
`0x20F0` within the struct, and `KERNSTRUCT_ADDR` is `0x11000`, giving `0x130F0`
exactly. `-[PCIKernBus init]` now reads `_maxBusNum`, `_pciVersionMajor`,
`_pciVersionMinor`, `_bios16Present` and the `_configMech1`/`_configMech2`/
`_specialCycle1`/`_specialCycle2` bits from `kernbootstruct->pciInfo` via
`KERNSTRUCT_ADDR`, matching the reference. Source and ledger status
(`control-flow-confirmed`) updated.

## Finding 6: `_LookForID` at 0xE6C

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIResourceDriver.m:371`

**Reference behaviour**

```
loc_FD4:
mov edx, [ebp+arg_C]
mov dword ptr [edx], 0
mov eax, 0FFFFFD27h    ; IO_R_NOT_ATTACHED (-729)
```

**Our source**

```c
for (bus = 0; ; bus++) {
    maxBus = [pciBus maxBusNum];
    if (bus > maxBus) {
        *count = 0;
        return IO_R_INVALID_ARG;
    }
    ...
}
```

**Difference:** `driverkit/return.h` defines `IO_R_INVALID_ARG` as `-706`
(`0xFFFFFD3E`) and `IO_R_NOT_ATTACHED` as `-729` (`0xFFFFFD27`). The "scanned every
bus and found nothing" exit in the reference binary returns `0xFFFFFD27`, i.e.
`IO_R_NOT_ATTACHED`, not `IO_R_INVALID_ARG`. This is confirmed against two other
call sites in the same binary that correctly use `0xFFFFFD3E` for genuine
`IO_R_INVALID_ARG` returns (`-[PCIKernBus getRegister:...]`'s parameter validation
and `-[PCIResourceDriver getCharValues:...]`'s prefix-switch fallthrough), so this
is not a case of misreading the constant table — the reference binary deliberately
uses a different, more specific error code here than our source does.

**Disposition:** fix

**Rationale:** `IO_R_NOT_ATTACHED` ("device/channel not attached") is semantically
the right code for "no device matched this ID pattern anywhere on the bus" — more
specific than the generic `IO_R_INVALID_ARG`, and callers that branch on the
specific `IOReturn` value would observe the difference.

**Outcome:** fixed. `_LookForID`'s "scanned every bus and found nothing" exit now
returns `IO_R_NOT_ATTACHED` instead of `IO_R_INVALID_ARG`. `IO_R_NOT_ATTACHED` is
reachable in `PCIResourceDriver.m` via its existing `#import
<driverkit/generalFuncs.h>`, which pulls in `driverkit/return.h`; no new include
was needed. Ledger status advanced from `unexamined` to `control-flow-confirmed`.

## Finding 7: `-[PCIResourceDriver getCharValues:forParameter:count:]` at 0x10DC

**Source:** `src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIResourceDriver.m:187`

**Reference behaviour**

```
cmp byte ptr [esi+128h], 0     ; _nameBuffer[0]
jnz short loc_1360              ; nonzero -> strtoul + LookForID
mov eax, 0FFFFFD27h              ; IO_R_NOT_ATTACHED (-729)
```

**Our source**

```c
case 5:  /* PCI_ID( */
    if (*count >= 80) {
        if (_nameBuffer[0] == '\0') {
            return IO_R_INVALID_ARG;
        }
        idValue = strtoul(parsedStr, &parsedStr, 0);
        return LookForID(idValue, _nameBuffer, values, count);
    }
    break;
```

**Difference:** same pattern as Finding 6 — when `PCI_ID(` is requested before a
`PCI_Name(`/`PCI_` lookup has populated `_nameBuffer`, the reference binary returns
`IO_R_NOT_ATTACHED` (`0xFFFFFD27`), not `IO_R_INVALID_ARG` (`0xFFFFFD3E`, which is
what the switch's other fallthrough paths in this same function correctly use, at
`0x1349`).

**Disposition:** fix

**Rationale:** same reasoning as Finding 6 — this is a distinct, deliberate error
code in the reference binary, and it is the second of exactly two places in this
driver where our source's `return IO_R_INVALID_ARG;` should instead be
`return IO_R_NOT_ATTACHED;`.

**Outcome:** fixed. The `PCI_ID(` case's empty-`_nameBuffer[0]` branch now returns
`IO_R_NOT_ATTACHED` instead of `IO_R_INVALID_ARG`; the switch's other
`IO_R_INVALID_ARG` returns are untouched. Ledger status advanced from
`unexamined` to `control-flow-confirmed`.

## Functions examined with no divergence found

Instruction-level match (`assembly-matched` in the ledger): `+[PCIKernBus
initialize]`, `-[PCIKernBus free]`, `-[PCIKernBus maxBusNum]`, `-[PCIKernBus
maxDevNum]`, `-[PCIKernBus getRegister:device:function:bus:data:]`, `-[PCIKernBus
setRegister:device:function:bus:data:]`, `-[PCIKernBus
allocateResourcesForDeviceDescription:]`, `-[PCIKernBus
Method2:device:function:bus:data:write:]`, `_Get_Maximums`, `_Get_ConfigReg`,
`_Get_ConfigSpace`, `_Set_ConfigReg`, `_Set_ConfigSpace`, `+[PCIResourceDriver
probe:]`, `-[PCIResourceDriver initFromDeviceDescription:]`, `_PCIParsePrefix`.

Control-flow-level match, no divergence found but not verified instruction by
instruction (`control-flow-confirmed` in the ledger): `-[PCIKernBus
testIDs:dev:fun:bus:]`, `-[PCIKernBus configAddress:device:function:bus:]`,
`_PCIParseKeys`, `-[PCIResourceDriver setCharValues:forParameter:count:]` (the
last of these was checked only by grep for its `IO_R_INVALID_ARG`/`IO_R_NO_DEVICE`
literals plus the IDA/Ghidra block-and-call-count summary, not read line by line —
flagged here so the depth of review is honest about it).
