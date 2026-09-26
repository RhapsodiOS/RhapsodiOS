# drvSym53C8xx divergences

Reference: `SYM53c8_reloc`, SHA-256 `E0AC193DF652271D1B4249440140842B788F0BAAC13F93008B7E029A095CF6D3`,
size 120756. Analyses: IDA 9.2 (partition of record) and angr 9.3.0 (not used as
evidence). Ghidra was disabled in Task 2 after a path-dot failure and then an
ownership-ambiguous normalize error on `_page_size` at file VA `0x4865`
(`_AddBufferToDatalist`, `cmp ds:_page_size, ecx`). Ledger
`analyzer_agreement.analyzers` is `["IDA"]` only.

## Task 5 (historical): baseline build

`rebuilt_sha256` in `ledger.json` is still `null` for every entry: this Task 5
reloc was a BusLogic-stub compile, not a CAM/SIM reconstruction to diff.
Mapped functions that diverged stayed `unexamined`. That pass compared the
reference binary and `SYM53c8.config` against the then-checked-in BusLogic-shaped
stub. Superseded by Task 11 (mapped 158; guest `_reloc` 347304 bytes).

## Task 5 (historical): baseline compile

Guest `sh /tmp/bscsi.sh drvSym53C8xx` succeeded:

```
=== scsi-recon done fail=0 built: drvSym53C8xx reloc=SYM53c8_reloc ===
```

Staged as `/build/source/out/i386/drvSym53C8xx/SYM53c8_reloc`, 204732 bytes,
unstripped (reference `SYM53c8_reloc` is 120756). `gnumake DSTROOT=… install`
failed (`INSTALLDIR` unset); the script copied the reloc. Bare `gnumake` on the
PPC guest defaults to ppc, and live `System.framework` has no `PrivateHeaders`;
the lksproj `Makefile.preamble` sets `RC_ARCHS`/`INCLUDED_ARCHS` to i386 and `-I`
to `/build/bootstrap-root/…/Versions/B/{PrivateHeaders,Headers}`.
`SYM53c8Controller.m` imports `<mach/vm_param.h>` for `PAGE_SIZE`. There is no
i386 `IOPCIDevice.h` (ppc-only in driverkit); the stub's unused pci ivar is
`id`. `completeStatus` is defined in `SYM53c8ControllerPrivate.h`. No CAM/SIM
rewrite in that pass.

## Summary

Task 11 remap (named functions only; see below):

| Bucket | Count |
| --- | --- |
| mapped | 158 |
| unmapped | 3 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Mapped files: `SYM53c8CAM.c` 101, `SYM53c8SIM.c` 35, `SYM53c8Controller.m` 22.
All 22 ObjC methods map to class `SYM53c8`, not `SYM53c8Controller`. Unmapped
are the two Kernel Server glue methods plus `nullsub_1`.

IDA reports **196** functions. Named=**161**. Unnamed=**35** in `__DATA,__data`
at addresses 60560–71060 (last body ends at 71092). `source-map-v1` requires
names, so those 35 were dropped on purpose. They are not missing C functions;
they live inside the SCRIPT / CAMcore dump in `SYM53c8Scripts.c`. `nullsub_1`
@ 63544 is a 1-byte named `retn` inside the same blob.

Raw `check_map.py` against all 196 IDA functions fails on the first unnamed
hit. Filter to named functions (same as Task 3:
`analysis-reference-ida-named.json`) before `load_source_map`. Expected:
`source map OK`. `reference_sha256` is
`E0AC193DF652271D1B4249440140842B788F0BAAC13F93008B7E029A095CF6D3`.

## Task 4–5 (historical): architecture was BusLogic CCB vs CAM/SIM + SCRIPTS

Superseded by Tasks 6–11: class `SYM53c8`, CAM/SIM definition sites in
`SYM53c8SIM.c` / `SYM53c8CAM.c`, mapped 158. The reloc is a DriverKit
`SYM53c8 : IOSCSIController` shell over an NCR SDMS CAM/XPT/SIM engine plus
an on-chip SCRIPTS / CAMcore blob. Our tree was cloned from `drvBusLogic`
(`SYM53c8Controller.h` HISTORY: "Created from BusLogic driver") and at that
pass allocated mailbox-shaped `struct ccb`s.

| In our tree (must go) | In `SYM53c8_reloc` |
| --- | --- |
| `@interface SYM53c8Controller : IOSCSIController` | `@interface SYM53c8 : IOSCSIController` (`__OBJC,__class_names`) |
| `allocCcb:` / `freeCcb:` / `ccbFromCmd:ccb:` | `allocReq` / `freeReq:` / `convertReq:ToXpt:buffer:client:` |
| `runPendingCommands` / `commandCompleted:reason:` | `commandRequestOccurred` dispatches `threadExecuteRequest:` / `threadResetSCSIBus`; completions are `_RespondToComp` → `_CallComp` → `_requestCompleted` |
| `sym_reset_chip` / `sym_init_chip` / `sym_get_istat` / `sym_put_dsa` / `sym_start_scripts` | `_FRun` / `_FResumeXFer` / `_FResetBus` (CAMcore vtable at `HBA+0x100`) plus `_SIMInterrupt` / `_SIMRun` |
| `handleScriptsInterrupt` / `handleDMAError` / `handleBusReset` / `handleSelectionTimeout` / `handleParityError` | no such selectors in `__OBJC,__inst_meth` |
| `threadResetBus:` / `timeoutOccurred` / `interruptOccurredAt:` / `otherOccurred:` / `receiveMsg` / `probeChip` | not in the reloc method lists |
| `struct ccb` / `struct sym_config` in `SYM53c8Types.h` | CAM CCB filled by `convertReq:ToXpt:` (offsets below); SIM `_HBAs` / `_DEVs` / XPT `_Devtab` |

CAM/SIM `__text` names that did not exist as definition sites in `$LKS` at
that pass include (complete named C list was the source-map `unmapped` bucket
minus the 22 ObjC methods, two glue methods, and `nullsub_1`):

```
SIMStart SIMRun SIMInterrupt SIM17Init SIMAddPath SIM16Start SIM16Int
SIM16Action SIM17Action SIMActionInit SIMInit SIMTickTock
RespondToComp CallComp CallCompletion RespondToBusReset
CCBInSIMQueue AddToDeviceList DeletePathFromDeviceTable
FCalcSync FSetSync FSetWide FWideInit FResumeXFer FSendMsg FRun FResetBus
AutosenseSetup BeginScan ScanStep StartNewIO
xpt_action xpt_init xpt_ccb_alloc xpt_ccb_free xpt_bus_register
XPTInit XPTDeregisterBus XPTClearMem
```

Filenames may stay `SYM53c8Controller.*`. The ObjC class must become `SYM53c8`.
Do not point any of those CAM names at BusLogic helpers.

## Method

ObjC class, superclass, ivars, and Loaded Server sections come from `read_macho`
on `SYM53c8_reloc`. Function bodies, call targets, and field displacements come
from `tools/binrecon/out/sym53c8xx/published/analysis-reference-ida.json`.
Ghidra was not run. angr was not used as evidence.

## IDA 196 vs source-map 161 (35 unnamed `__data` hits)

IDA `functions` length is 196. Named: 161. Unnamed: 35. Every unnamed entry has
`names: []` and an address in `__DATA,__data` (section VA 40960, size 40528, so
40960–81488):

| First unnamed | Last unnamed start | Last unnamed end |
| --- | --- | --- |
| 60560 | 71060 | 71092 |

`nullsub_1` @ 63544 (size 1, `retn`) sits inside that span and was kept in the
source-map only because IDA gave it a name. It is not a reconstructable
`__text` routine.

Bodies in that span disassemble as real x86 (`enter`/`push`/`in`/`out`/`retn`)
and sit next to NCR SDMS strings (`Copyright 1993 NCR Corporation` at VA 43676 /
file offset 46072; `NCR SDMS (TM) V3.0 PCI SCSI BIOS`; `BALLARD_SYNERGY_ROM_SIM`;
`NCRPCI-3.07.00`). Task 8 should dump this blob, not invent C for the 35
unnamed hits.

## Superclass, instance size, ivars

`__OBJC,__class_names` starts `SYM53c8`, then `IOSCSIController`. The class_t
at `__OBJC,__class` (VA 82072, file 84468) has `name=SYM53c8`,
`super=IOSCSIController`, `instance_size=0x600` (1536). First declared ivar is
at `+0x244`, so the `IOSCSIController` prefix is 580 bytes — same prefix width
as `EATASCSIBus` on drvDPT2000. Undefined symbols include
`.objc_class_name_IOSCSIController` and `.objc_class_name_IODirectDevice`.
`__OBJC,__class_names` also contains `Object`, `NCR53c8.m`, `NXLock`,
`NXConditionLock`, `IODirectDevice`, `SYM53c8Version`, `IODevice`,
`SYM53c8KernelServerInstance`, `SYM53c8_instance.m`.

`__OBJC,__instance_vars` at VA 84504 / file 86900, `ivar_count=16`. Offsets are
from the start of the instance, not from `SYM53c8Types.h`.

| Off | Name | Encoded type |
| --- | --- | --- |
| +0x244 | `intPortKern` | `i` |
| +0x248 | `interrupt` | `I` |
| +0x24c | `path` | `C` |
| +0x250 | `reqPoolLock` | `@` |
| +0x254 | `availReqs` | `I` |
| +0x258 | `freereq` | `^{_scsireq}` |
| +0x25c | `reqs` | `[32{?="XPTReq"^{?}"next"^{_scsireq}"reqLock"@"NXConditionLock""NeXTReq"^{?}"client"I"self"@"biodone"i}]` |
| +0x5dc | `levelIRQ` | `c` |
| +0x5dd | `ioThreadRunning` | `b1` |
| +0x5e0 | `pad` | `b31` |
| +0x5e4 | `commandQ` | `{?="next"^{queue_entry}"prev"^{queue_entry}}` |
| +0x5ec | `commandLock` | `@` |
| +0x5f0 | `maxQueueLen` | `I` |
| +0x5f4 | `queueLenTotal` | `I` |
| +0x5f8 | `totalCommands` | `I` |
| +0x5fc | `outstandingCount` | `I` |

`reqs` is 32 × 28 bytes = 0x380, and `0x25c + 0x380 = 0x5dc` (`levelIRQ`).
`outstandingCount` at `+0x5FC` plus 4 bytes reaches `instance_size` `0x600`.

### `_scsireq` (one `reqs[]` slot / `allocReq` object)

From the ivar encoding and `convertReq:ToXpt:buffer:client:` / `_requestCompleted`:

| Off | Field | Evidence |
| --- | --- | --- |
| +0x00 | `XPTReq` | `convertReq` stores `_xpt_ccb_alloc` result into `[ebx]` |
| +0x04 | `next` | free-list; `allocReq` reads `[ebx+258h]` (`freereq`) |
| +0x08 | `reqLock` | `NXConditionLock`; `_requestCompleted` `lock` / `unlockWith:1` |
| +0x0C | `NeXTReq` | `convertReq` `[ebx+0Ch] = IOSCSIRequest*` |
| +0x10 | `client` | `convertReq` `[ebx+10h] = client` |
| +0x14 | `self` | `convertReq` `[ebx+14h] = esi` (the `SYM53c8`) |
| +0x18 | `biodone` | encoded `i`; not traced beyond the encoding |

### CAM / XPT CCB (the object `_xpt_ccb_alloc` returns)

`_xpt_ccb_alloc` pops `_freeccb` and uses `+0x10` as the free-list link. It does
not contain a size immediate. Field stores in `convertReq:ToXpt:buffer:client:`
(IDA 2740) against that pointer (`eax = [ebx]`):

| Off | Written as |
| --- | --- |
| +0x09 | `path` from `self+0x24C` |
| +0x0A | target from `IOSCSIRequest+0` |
| +0x0B | lun from `IOSCSIRequest+1` |
| +0x0C | flags (`0x80` or `0x40`, then `or 0x20`; tagged `or 0x02` if `_cmdQueueEnable`) |
| +0x0D | more flags (`or 0x04`, sync/wide bits `0x20`/`0x40`/`0x80`/`0x10`) |
| +0x18 | back-pointer to `_scsireq` |
| +0x1C | completion function `_requestCompleted` |
| +0x20 | data buffer |
| +0x24 | transfer length from `IOSCSIRequest+0x10` |
| +0x28 | CDB pointer = `IOSCSIRequest+0x38` |
| +0x2C | `0x1A` (CAM `SCSI_IO` function code as compiled) |
| +0x2D | CDB length (6 / 0xA / 0xC from the opcode-group switch) |
| +0x30 | `0xBEEFBEEF` |
| +0x3C | CDB bytes copied from `IOSCSIRequest+2` |
| +0x48 | timeout from `IOSCSIRequest+0x14` |
| +0x54 | `0x20` |

Do not substitute `struct ccb` from `SYM53c8Types.h`.

### Command buf (`executeCmdBuf:` type encoding)

`-[SYM53c8 executeCmdBuf:]` type is
`i12@8:12^{?=i^{_scsireq}@{?=^{queue_entry}^{queue_entry}}}16`:

| Off | Field |
| --- | --- |
| +0x00 | `op` (`i`); `commandRequestOccurred` switches on `[ebx]` (0 / 1 / 2) |
| +0x04 | `^{_scsireq}` for op 0; `threadExecuteRequest:` takes this pointer |
| +0x08 | `NXConditionLock*` (allocated for op != 0; for op 0 the lock on the `_scsireq` is reused) |
| +0x0C / +0x10 | queue chain on `commandQ` (`self+0x5E4`) |

`executeRequest:buffer:client:` does `allocReq`, `convertReq:ToXpt:buffer:client:`,
`executeCmdBuf:`, `updateStatus:`, `_xpt_ccb_free`, `freeReq:`, then
`dec [self+0x5FC]` and returns `[scsiReq+0x1C]`.

### SIM device table / HBA / XPT device table

- `_HBAs` at VA 41924 in `__data`. `_GetIRQ` indexes with `lea eax, [ebx+ebx*4];
  shl eax, 6` → stride **320** (`0x140`) bytes. `SIMRun` walks from `_HBAs` until
  `0xA8C4` (43204): 1280 bytes = **4** HBA slots. Path byte sampled at
  `HBA+0x6C`. Firmware register window pointer at `HBA+4`; CAMcore vtable at
  `HBA+0x100`.
- `_DEVs` (SIM device list) at VA `0xA040`. `_AddToDeviceList` uses stride 16,
  28 slots (`edx` 0..0x1B). Empty test is
  `cmp byte ptr [eax+0A041h], 0FFh` after `shl eax, 4` (id byte of the slot).
  Slot: `+0` path from `HBA+0x6C`, `+1` id, `+2` lun, `+4` queue head from
  `_simqStack`, `+8..+0A` zero, `+0B` = 2.
- XPT `_Devtab`: `_PathIDLUNToDeviceInfoPtr` / `_DeletePathFromDeviceTable`
  stride **0x28** (40). `path@0`, `id@1`, `lun@2`. Delete copies `ecx=0x0A`
  dwords (40 bytes) when compacting.

## I/O vs MMIO

Named `__text` functions contain **zero** `in`/`out` instructions
(`named_io_count=0` over the IDA JSON). Chip access in the DriverKit / SIM C
is not PIO in the host code.

`-[SYM53c8 initFromDeviceDescription:]` (IDA 324):

1. `bzero` 0x100 bytes and `getPCIConfigSpace:withDeviceDescription:`
   (`ds:paGetpciconfigsp`).
2. Interrupt line: `movzx edx, [ebp+var_C4]` into `self+0x248`. `var_C4` is
   `var_100 + 0x3C` (PCI config `interruptLine`).
3. BAR0 at PCI config +0x10 (`lea eax, [ebp+var_F0]`, `var_100 + 0x10`):
   `test byte ptr [eax], 1` — **I/O BAR** (bit 0 set). `and al, 0FCh` yields
   the port base; range length stored as `0x100`. Failure logs
   `SYM53c8: No I/O Port Base Found`.
4. `setPortRangeList:num:` with that one range; `setInterruptList:num:` with
   `&self->interrupt` (`self+0x248`).
5. `[super initFromDeviceDescription:]`.
6. If `path == 0` (`self+0x24C`): `IOMapPhysicalIntoIOTask(0xE0000, 0x20000)`
   — the **ISA BIOS window**, not a PCI MMIO BAR — into `_bios_rom_vap`, then
   `_xpt_init`, then `IOUnmapPhysicalFromIOTask` of the same 128 KB.

`_ROMReadByte` / `_PtoV` then read that BIOS mapping as memory
(`movzx eax, byte ptr [eax]`; `_PtoV` does `lea eax, [edx-0E0000h]`).
`_pci_initialize` starts its ROM scan at segment `0xE000`.

`_FRun` / `_FResumeXFer` / `_FResetBus` write a command byte to
`[*(HBA+4)+0x14]` (`2`, `0x0D`, `0x0A`) and `call` the CAMcore function at
`[*(HBA+0x100)+0x0C]`. That is the firmware register window (ISTAT-sized
offset 0x14 on the 53C8xx), not a `sym_write_reg` helper.

The 35 unnamed `__data` hits **do** contain `in`/`out` (45 `in`, 50 `out` in
the IDA JSON). That is the NCR BIOS / CAMcore image talking to the chip, not
the DriverKit C.

## SCRIPTS / CAMcore location

There is no `__TEXT` SCRIPT section. The reloc stores the NCR SDMS / CAMcore
image in `__DATA,__data`:

| | |
| --- | --- |
| Mach-O section | `__DATA,__data` |
| Virtual address | 40960 (`0xA000`) |
| File offset | 43356 (`0xA95C`) |
| Length | 40528 (`0x9E50`) |
| SHA-256 | `E139BB6F965C26EF7F1E3EC89B0799648866C7322749701295E1A2CE1658C3F5` |

IDA's unnamed "functions" (the part Task 8 should dump first) span:

| | |
| --- | --- |
| VA | 60560–71092 (`0xEC90`–`0x115E4`), length 10532 |
| File offset | 62956–73488 (`0xF5EC`–`0x11F10`) |

Head of `__data` is not a SCRIPT block (`01000000 00000018 …` at VA 40960).
NCR copyright / BIOS identifiers sit earlier in the same section (VA 43220–
44008). `_FRun` does not load DSP (`0x2C`) from host C; it calls the firmware
vtable. Host C never writes `DSP`/`DSA` as named helpers — those immediates
at `+0x2C` in CAM CCB paths are the CAM function code / CDB fields above.

Quote for Task 8: dump `__DATA,__data` file offset 43356 size 40528, and
especially file offset 62956 size 10532. Do not treat the 35 unnamed IDA hits
as C to rewrite.

## Completion policy

The IRQ handler **runs the SIM on the interrupt path**. It does not only wake
the IOThread, and it does not finish the command buf itself.

`-[SYM53c8 interruptOccurred]` (IDA 4276, 71 bytes):

1. `movzx eax, byte ptr [ebx+248h]` (`interrupt` ivar).
2. `call _SIMInterrupt` (target 21984).
3. `objc_msgSend` selector `enableAllInterrupts` (`ds:paEnableallinter`).
4. On failure, `IOLog` `aSUnableToEnabl`.

No `msg_send_from_kernel` in this function. No `commandCompleted:reason:`.

`_SIMInterrupt` (21984): `_DisableInterrupts`, then `_SIMRun` (6076) or
`_SIM16Int` (19336), then `_RestoreInterrupts`. `_DisableInterrupts` /
`_EnableInterrupts` are 9-byte `xor eax,eax; ret` stubs.

`_SIMRun` calls `_RespondToComp` (6616 → 6824) among `_FRun` / `_FResumeXFer`
/ `_CheckForStart` / `_GotMSG` / `_WantMSG`. `_RespondToComp` calls
`_CallComp` (6991, 7381). `_CallComp` is also reached from `_SIMStart`,
`_SIMTickTock`, `_RespondToBusReset`, `_ResetDevice`, `_AbortedRequest`.
`convertReq` plants `_requestCompleted` at CAM CCB `+0x1C`; that function
`lock`s / `unlockWith:1` the `_scsireq.reqLock`. Completions therefore
finish the waiting `executeCmdBuf:` on the **SIM/IRQ path**, not by the
DriverKit method writing a result code itself.

The IOThread is the **submit** path:

- `executeCmdBuf:` enqueues on `commandQ` (`self+0x5E4`) and
  `_msg_send_from_kernel`s (IDA 4567) using `intPortKern` at `self+0x244`.
- `commandRequestOccurred` `lock`s `commandLock` at `self+0x5EC`, dequeues,
  and `objc_msgSend`s `threadExecuteRequest:` (`ds:paThreadexecuter`, from
  `[ebx+4]`) or `threadResetSCSIBus` (`ds:paThreadresetscs`) or
  `_IOExitThread` (3590) for op 2.
- `threadExecuteRequest:` calls `_IOGetTimestamp` then `_xpt_action` on
  `[_scsireq].XPTReq`.

`initFromDeviceDescription:` sets `ioThreadRunning` (`or byte ptr [edx+5DDh], 1`)
after `IOConvertPort` of `interruptPort` into `intPortKern`.

## Task 5 (historical): DriverKit methods were still BusLogic in our source

Superseded by Tasks 6–9. At that pass every reloc ObjC method was unmapped
because the class name was `SYM53c8Controller` instead of `SYM53c8`. The
selectors below existed (or had near-miss names) in our tree and still called
BusLogic helpers. Disposition then: rewrite in later tasks; do not adapt the
CCB mailbox path.

### Finding 1 — `@interface SYM53c8Controller` instead of `SYM53c8`

**Source:** `SYM53c8Controller.h`.

**Reference:** class_t / `__OBJC,__class_names` `SYM53c8` : `IOSCSIController`.
21 instance methods in `__OBJC,__inst_meth` plus class `probe:`.

**Disposition:** rename the class (filenames may stay). This is why `mapped=0`.

### Finding 2 — `interruptOccurred` is invented ISTAT/SCRIPTS PIO

**Source:** `SYM53c8Controller.m`. Reads `sym_get_istat` / `sym_get_dstat` /
`sym_get_sist0`, calls `handleScriptsInterrupt` / `handleDMAError` /
`handleBusReset`, then `runPendingCommands` and `commandRequestOccurred` on
the same thread.

**Reference:** push `interrupt` ivar, `_SIMInterrupt`, `enableAllInterrupts`.
71 bytes. No PIO, no `runPendingCommands`.

**Disposition:** rewrite from the IDA body.

### Finding 3 — `executeRequest:buffer:client:` builds a BusLogic `SYMCommandBuf`

**Source:** fills `cmdBuf.op = SO_Execute` and `[self executeCmdBuf:&cmdBuf]`.

**Reference:** `allocReq` → `convertReq:ToXpt:buffer:client:` → `executeCmdBuf:`
→ `updateStatus:` → `_xpt_ccb_free` → `freeReq:`. Returns `[scsiReq+0x1C]`.

**Disposition:** rewrite; add `allocReq` / `convertReq` / `updateStatus:`.

### Finding 4 — `threadExecuteRequest:` allocates `struct ccb` and `ccbFromCmd:`

**Source:** `SYM53c8Thread.m` `allocCcb:` / `ccbFromCmd:ccb:` /
`runPendingCommands` / `sym_put_dsa` / `sym_start_scripts`.

**Reference:** `_IOGetTimestamp` + `_xpt_action` on the CAM CCB at `[_scsireq]`.

**Disposition:** delete the BusLogic CCB path; call XPT.

### Finding 5 — `commandRequestOccurred` skips the IOThread switch

**Source:** only `[self runPendingCommands]`.

**Reference:** lock `commandLock`, dequeue `commandQ`, switch op 0/1/2 to
`threadExecuteRequest:` / `threadResetSCSIBus` / `_IOExitThread`.

**Disposition:** rewrite.

### Finding 6 — `executeCmdBuf:` does not `msg_send_from_kernel`

**Source:** locks, enqueues, then calls `commandRequestOccurred` on the caller.

**Reference:** enqueue, `_msg_send_from_kernel` to `intPortKern`, then
`lockWhen:` on the command/req lock.

**Disposition:** rewrite.

### Finding 7 — `initFromDeviceDescription:` / `probeChip` use `sym_init_chip`

**Source:** `IOMallocLow` a 4096-byte "SCRIPTS" buffer, `kvtophys`,
`sym_init_chip(ioBase, &config)`.

**Reference:** PCI config BAR0 I/O, `setPortRangeList`, map/unmap BIOS
`0xE0000+0x20000`, `_xpt_init`. No `sym_init_chip` symbol.

**Disposition:** rewrite from IDA.

### Finding 8 — extra BusLogic selectors that the reloc does not implement

**Source:** `timeoutOccurred`, `interruptOccurredAt:`, `otherOccurred:`,
`receiveMsg`, `probeChip`, `threadResetBus:`, `commandCompleted:reason:`,
`allocCcb:`, `freeCcb:`, `ccbFromCmd:ccb:`, `runPendingCommands`,
`handleScriptsInterrupt` and friends.

**Reference:** `__OBJC,__inst_meth` does not list them. Reloc extras we lack:
`setPath:`, `allocReq`, `freeReq:`, `convertReq:ToXpt:buffer:client:`,
`threadResetSCSIBus`, `numberOfTargets`, `updateStatus:`, `manualTURScan`.

**Disposition:** delete the BusLogic-only selectors; add the missing CAM
DriverKit methods.

### Finding 9 — `SYM53c8Types.h` is a BusLogic `struct ccb`

**Source:** mailbox `opcode` / `host_status` / SG list, plus invented
`SYM_*_OFF` PIO register map.

**Reference:** CAM CCB offsets in `convertReq` above; chip access through
CAMcore, not `sym_write_reg`.

**Disposition:** replace the header from the reloc encodings. Do not copy
Linux `ncr53c8xx` layouts.

## Table / help findings

Compared host files to
`C:\Users\raynorpat\Downloads\test\Drivers\i386\SYM53c8.config`.
`"Driver Version"` ignored. Inspector nib and the `SYM53c8` DYLDLINK beside
the `_reloc` are out of scope (present in the reference config listing;
not copied).

| # | File | Result |
| --- | --- | --- |
| 1 | `Default.table` | Task 10: added `"Version" = "5.00";`. Still omit `"Driver Version"` PROGRAM line. Auto Detect IDs already `0x00011000 0x00021000 0x00031000 0x00041000`. Title / Family / Server Name / Wide SCSI / Synchronous / Valid IRQ Levels match. |
| 2 | `DriverInfo` | Present in our `.drvproj` (`DRIVER_NAME="SYM53c8"`). **Absent** from the reference bundle. |
| 3 | `Load_Commands.sect` | Task 10: first line is `"# \n"` (hash-space) to match the reloc. Same `WIRE` / no Mig handler. Reloc `Server Name` is `SYM53c8`; `Instance Var` is `SYM53c8_instance`. |
| 4 | `English.lproj/Localizable.strings` | Byte-identical (`"SYM53c8" = "Symbios 53C8xx"` / `"Long Name" = "Symbios Logic 53C8xx SCSI Adapter"`). |
| 5 | Help directory | Task 10: `English.lproj/Help/`; `Makefile` `LOCAL_RESOURCES = Localizable.strings Help SYM53c8Inspector.nib`. Inspector nib left in place; DYLDLINK `SYM53c8` not copied. |
| 6 | Help contents | `TableOfContents.rtf`, `Symbios_Logic_53C8xx_SCSI_Adapter.rtfd/TXT.rtf`, and the three tiffs are byte-identical across those two directory names. |

## Analyzer disagreement

Ghidra is unused (`analyzers.ghidra.enabled` is false after commit
`6d5ee5126`). The disable reason recorded here is the path-dot failure
followed by an ownership-ambiguous normalize on the `_page_size` reloc at
VA `0x4865` in `_AddBufferToDatalist`. angr 9.3.0 remains enabled on the
profile and is not evidence. IDA is the only analyzer of record; every
ledger `analyzer_agreement` is `agreed` / `["IDA"]`.

## Unmapped reason classes

| Class | Count | Why unmapped |
| --- | --- | --- |
| Kernel Server glue | 2 | `+[SYM53c8KernelServerInstance kernelServerInstance]` @ 32132, `+[SYM53c8Version driverKitVersionForSYM53c8]` @ 32144. Emitted by project type `Kernel Server` / `Load_Commands.sect`. Stay unmapped. Ledger `intentional-mismatch`, reviewer Pat Raynor. |
| `nullsub_1` | 1 | 1-byte named IDA hit @ 63544 in `__data`, not a reconstructable `__text` routine. Stay unmapped. Ledger `intentional-mismatch`, reviewer Pat Raynor. Not a glue-only unmapped. |

2 + 1 = 3. CAM/SIM C and ObjC methods are mapped. The 35 unnamed `__data`
hits are **not** in this table.

## Task 7: SIM API written

`SYM53c8SIM.c` / `SYM53c8SIM.h` hold the DriverKit-facing SIM and the SIM-layer
helpers those bodies call. Ledger rows stay `unexamined` until Task 11.

- [x] `SIMInit` `SIM17Init` `SIMAddPath` `SIMActionInit`
- [x] `SIMStart` `SIMRun` `SIMInterrupt` `SIMTickTock`
- [x] `RespondToComp` `CallComp` `CallCompletion` `RespondToBusReset` `CCBInSIMQueue`
- [x] `SIM16Start` `SIM16Int` `SIM16Action` `SIM17Action`
- [x] `DisableInterrupts` `EnableInterrupts` `RestoreInterrupts`
- [x] `QInsert` `QAppend` `QDelete` `IDLUNToDP` `PathToROMInfoPtr` `GetNumROMs` `GetROMTableBase`
- [x] `SIMClearMem` `GetWidth` `Do17On16` `Do16On17` `Start17On16` `Start16On17` `r16Comp` `r17Comp`

Extern to Task 8: `FindROMs` `InitROMs` `MemAlloc` `VtoP` `FCalcSync` `FWideInit`
`InitializeQueueTags` `FRun` `FResumeXFer` `FResetBus` `FRespRes` `CheckForStart`
`FindRunningRequest` `SetFrag` `GotMSG` `WantMSG` `FreeQueueTag` `AutosenseSetup`
`PreTransfer17` `PostTransfer17` `PreTransfer16` `PostTransfer16` `PeekAtData`
`DoneWithCurrentData` `AddToDeviceList` `ResetDevice` `xpt_async` `T17To16`
`T16To17` `Stat16To17` `Stat17To16`.

## Task 8: CAM helpers and SCRIPTS bytes

`SYM53c8CAM.c` holds the remaining named `__text` C (device table, scan,
autosense, sync/wide, xfer/message, XPT, FindROMs). `SYM53c8Scripts.c` is the
byte-exact `__DATA,__data` dump (file offset 43356, length 40528). The unnamed
IDA span (file offset 62956, length 10532) lives inside that blob and is not
C. `RAMcorePtr` is the option ROM at blob offset 2688; CAM.c uses
`#define RAMCORE_PTR (&SYM53c8Scripts[2688])` because IDA treats the label as
a byte-array, not a pointer variable.

- [x] Step 1: dump remaining C (`_task8_dumps/`, not committed)
- [x] Step 2: `SYM53c8CAM.c` (no `return 0;` stubs; no Linux / ppc SCRIPT
  source)
- [x] Step 3: `SYM53c8Scripts.c` full 40528-byte array
- [x] Step 4: Makefile `CFILES = SYM53c8SIM.c SYM53c8CAM.c SYM53c8Scripts.c`
- [x] `_StuffAction` @ 21228 with the `xpt_bus_register` path
- [x] `FindROMs` `InitROMs` `MemAlloc` `VtoP` `FCalcSync` `FSetSync` `FSetWide` `FWideInit` `FSendMsg`
- [x] `InitializeQueueTags` `FRun` `FResumeXFer` `FResetBus` `FRespRes` `CheckForStart`
- [x] `FindRunningRequest` `SetFrag` `GotMSG` `WantMSG` `FreeQueueTag` `AutosenseSetup`
- [x] `PreTransfer17` `PostTransfer17` `PreTransfer16` `PostTransfer16` `PeekAtData`
- [x] `DoneWithCurrentData` `AddToDeviceList` `DeletePathFromDeviceTable` `ResetDevice`
- [x] `xpt_async` `T17To16` `T16To17` `Stat16To17` `Stat17To16` `StuffAction`
- [x] `BeginScan` `ScanStep` `StartNewIO` `xpt_action` `xpt_init` `xpt_ccb_alloc` `xpt_ccb_free`
- [x] `xpt_bus_register` `XPTInit` `XPTDeregisterBus` `XPTClearMem` `AbortedRequest`

The 40528-byte array duplicates live C globals that also exist as symbols
(`HBAs`, `DEVs`, `SIMs`, `Devtab`, `dlStack`, …). Residue pytest stays RED
until a later packing pass. Handshake BSS (`SyncSCSIEnable` etc.) stays for
Task 9.

## Unmapped: build-generated

`+[SYM53c8KernelServerInstance kernelServerInstance]` and
`+[SYM53c8Version driverKitVersionForSYM53c8]` — emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted, same as
the equivalent pair in drvAdaptec1542B.

## Task 11: remap, ledger, final compile

Fresh `binrecon source-map` against `analysis-reference-ida.json` failed on
the unnamed function at 60560 (`source-map-v1` requires names). Remap used
the Task 3 named analysis
`tools/binrecon/out/sym53c8xx/published/analysis-reference-ida-named.json`.
`source_path` / `source_line` were copied into the committed map by address.

`_puthex_0` @ 31912 and `_putbyte_0` @ 31956 landed in `duplicate_candidates`
because Mach-O symbols are still `_puthex` / `_putbyte`. Same resolution as
DPT2000 `eata_busy_0`: keep the later `_0` definition in `SYM53c8CAM.c`
(lines 355 and 365). Duplicate bucket is empty in the committed map.

Category implementations did not map (`SYM53c8(IOThread)`,
`SYM53c8(PrivateMethods)`). `executeCmdBuf:` moved into the main
`@implementation SYM53c8` in `SYM53c8Controller.m`.
`threadExecuteRequest:` / `threadResetSCSIBus` also live there: keeping them
as `@implementation SYM53c8` in `SYM53c8Thread.m` produced
`ld: multiple definitions of symbol .objc_class_name_SYM53c8`.
`SYM53c8Thread.m` is now an empty `@implementation SYM53c8(IOThread)` so the
file stays in `CLASSES`. `StartTime` moved to Controller.m.

### Ledger (honest)

Do not claim `assembly-matched` without a re-read this task. Glue +
`nullsub_1` stay `intentional-mismatch`. `analyzer_agreement` stays IDA only.

| Status | Count |
| --- | --- |
| unexamined | 153 |
| assembly-matched | 4 |
| control-flow-confirmed | 1 |
| intentional-mismatch | 3 |

Re-read against IDA this task:

| Addr | Name | Status | Source |
| --- | --- | --- | --- |
| 2740 | `-[SYM53c8 convertReq:ToXpt:buffer:client:]` | assembly-matched | Controller.m 360 |
| 21984 | `_SIMInterrupt` | assembly-matched | SIM.c 1125 |
| 24204 | `_FRun` | assembly-matched | CAM.c 501 (inlines camcore, cmd=2, `[hba+4]+0x14` / `[hba+0x100]+0x0C`) |
| 31632 | `_xpt_init` | assembly-matched | CAM.c 1685 (ref has a one-shot loop around `xpt_bus_register`; equivalent to one call) |
| 11964 | `_WantMSG` | control-flow-confirmed | CAM.c 2753 |

`_WantMSG` is the largest named function (2563 bytes). Control flow was
confirmed (send/`FSendMsg` switch, sync/wide negotiation, extmsg WDTR/SDTR
path, `fw_put_msg` into `+0x2A`). It was **not** traced operand-by-operand
for every instruction, so it is not `assembly-matched`.

### Final guest compile

Host sync: `powershell -File vm\sync-src.ps1 -Path drivers-i386/scsi/drvSym53C8xx`
(worktree `LocalRoot`). Guest:

```
tr -d '\r' < /build/source/vm/build-i386-scsi.sh > /tmp/bscsi.sh
sh /tmp/bscsi.sh drvSym53C8xx
```

Exit 0. Staged `/build/source/out/i386/drvSym53C8xx/SYM53c8_reloc`, **347304**
bytes, unstripped (reference 120756, stripped). `gnumake DSTROOT=… install`
failed (`INSTALLDIR` unset); the script copied the reloc. Did not run
`binrecon compare` on the rebuilt file. Did not commit `out/`.

Hygiene / compile-error fixes applied (allowed by Task 11):

- Deleted `unsigned char *RAMcorePtr = &SYM53c8Scripts[2688];` in
  `SYM53c8Scripts.c`; kept `#define RAMCORE_PTR`.
- `StuffAction` in `SYM53c8SIM.h`: `extern void StuffAction(struct xpt_bus *bus);`
  plus `struct xpt_bus;` forward decl.
- Dropped duplicate CAM `extern` block in `SYM53c8SIM.c` (prototypes in SIM.h).
- `_scsireq.XPTReq` typed `struct sim_ccb *` in `SYM53c8Types.h`.
- Trailing newline on `Default.table`.
- `SYM53c8Types.h`: `#ifdef __OBJC__` around `scsiTypes.h`; C path uses
  `objc/objc.h` plus `typedef struct IOSCSIRequest IOSCSIRequest` (SIM.c as C
  was pulling `Object.h`).
- Dropped `#import <objc/objc-runtime.h>` from CAM.c.
- `pcidir` inline asm: NeXT gcc rejected `"+a"`; matching constraints
  `"=a"/"0"` etc. (`call *%4` still `fn`).

Did not “fix” IDA-faithful sharp edges (probe leak, `unlockWith:0` vs
`lockWhen:1`, `base[+3]`).

Warnings (do not gate):

- `SYM53c8Controller.m`: implicit `port_set_backlog_EXTERNAL`
- `SYM53c8Thread.m:18`: incomplete category `IOThread` (methods live on the
  main class)
- `SYM53c8CAM.c`: unused `rc` in `InitStep`, unused `per2` in `GotMSG`,
  `lun` maybe uninitialized in `WantMSG`, unused `xpt_sim_action`
- `ld`: ppc `libcc.a` vs `-arch i386` (same class as other i386 guest builds)

Residue pytest `tools/binrecon/tests/test_sym53c8xx_buslogic_residue.py`: PASS.

## Default.table: "Server Name" came out twice

2026-09-25. Not a divergence: the earlier comparisons of `Default.table` with
the reference did not allow for the build's append.

The driver build's `post_copy_tables` rule
(`src/driverTools-1/DriverProjectType/driver.make:154-159`) appends
`"Server Name" = "$(NAME)";` to every table. Our source table carried the line
as well, so the built table had it twice. The line is gone from the source, and
the built table now has it once, as the reference does.

One ordering difference remains. The reference ends `"Server Name"`,
`"Driver Version"`, `"Version"` because Apple's build appended all three:
`veredit.sh` adds `"Version"` only when the source table lacks it. Our source
carries `"Version"`, so the appended `"Server Name"` now follows it.
