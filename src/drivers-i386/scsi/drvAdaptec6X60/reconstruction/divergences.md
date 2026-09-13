# drvAdaptec6X60 divergences

Reference: `AIC6X60SCSI_reloc`, SHA-256 `E70647063BC4E6BC4BF47F73BF298BEAC59264B163C9D9D1920788CCBCE35E13`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 (angr not used as evidence per the task brief; it
over-segments this binary via `CFGFast` the same way it did for the bus drivers and 1542B.
IDA found the 79 functions that match the Mach-O / ObjC method table, so IDA is treated as
the authoritative partition and Ghidra as a second opinion on bodies)

## Baseline build

The report pass compared the reference binary's disassembly and ObjC metadata
directly against the then-mailbox source. The fix pass replaced that tree with
a HIM plus sequencer. `rebuilt_sha256` in `ledger.json` stays `null`: this
task does not run `binrecon compare` on the guest `_reloc`.

## Baseline compile

Guest `sh /tmp/bscsi.sh drvAdaptec6X60` succeeded:

```
=== scsi-recon done fail=0 built: drvAdaptec6X60 reloc=Adaptec6X60_reloc ===
```

Staged as `/build/source/out/i386/drvAdaptec6X60/Adaptec6X60_reloc`, 230628 bytes, unstripped
(reference `AIC6X60SCSI_reloc` is 61892). `gnumake DSTROOT=… install` failed
(`INSTALLDIR` unset); the script copied the reloc. Bare `gnumake` on the PPC guest
defaults to ppc, and live `System.framework` has no `PrivateHeaders`; the lksproj
`Makefile.preamble` sets `RC_ARCHS`/`INCLUDED_ARCHS` to i386 and `-I` to
`/build/bootstrap-root/…/Versions/B/{PrivateHeaders,Headers}`. `AIC6X60Controller.m` and
`AIC6X60Thread.m` import `<mach/vm_param.h>` for `PAGE_SIZE`. This was the mailbox
tree; see Final guest compile for the HIM `_reloc`.

## Final guest compile

Host synced `drivers-i386/scsi/drvAdaptec6X60` and copied `vm/build-i386-scsi.sh`
to `/build/source/vm/`. Guest:

```
tr -d '\r' < /build/source/vm/build-i386-scsi.sh > /tmp/bscsi.sh
sh /tmp/bscsi.sh drvAdaptec6X60
=== scsi-recon done fail=0 built: drvAdaptec6X60 reloc=Adaptec6X60_reloc ===
```

Staged as `/build/source/out/i386/drvAdaptec6X60/Adaptec6X60_reloc`, **363060**
bytes, unstripped Mach-O preload i386 (reference `AIC6X60SCSI_reloc` is 61892).
`gnumake DSTROOT=… install` still fails (`INSTALLDIR` unset); the script copied
the reloc. Compile-fix commit `drivers-i386: build drvAdaptec6X60 HIM`: drop
the unused `struct objc_super` (incomplete type on this compiler), compile
`HIM6X60.c` / `AIC6X60Sequencer.c` with `-ObjC` because they call `objc_msgSend`
and include ObjC headers, and stop listing the `.m` files in both `CLASSES` and
`MFILES` (that doubled `AIC6X60Controller.o` on `kl_ld`).

Warnings (do not gate):

- `port_set_backlog_EXTERNAL` / `bzero` / `msg_send_from_kernel` implicit
  declarations
- unused `bit` in `HIM6X60Initialize`, unused `period` in `negotiateSDTR`
- `memcmp` / `memcpy` builtin-type conflict in `AIC6X60Sequencer.c`
- `libcc.a` ppc vs i386 `-arch` (same guest toolchain warning as the
  mailbox baseline)
- `INSTALLDIR` unset on `install`

No `binrecon compare` of the rebuilt file.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 77 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

HIM names map to `HIM6X60.c` or `AIC6X60Sequencer.c`. DriverKit helpers added
in the glue rewrite (`getDMAAlignment:`, `initDMA`, `scbFromCmd:scb:`,
`allocScb`, `freeScb:`, `commandCompleted:reason:`) map. `repins*` / `repouts*`
map to `AIC6X60Sequencer.c`. `_memset` maps to `HIM6X60.c`. Glue stays
unmapped:

- `+[AIC6X60SCSIKernelServerInstance kernelServerInstance]`
- `+[AIC6X60SCSIVersion driverKitVersionForAIC6X60SCSI]`

## Method

Every function was read from
`tools/binrecon/out/adaptec6x60/published/analysis-reference-ida.json`. Ivar names, type
encodings, and offsets come from `__OBJC,__instance_vars` in the reference Mach-O together
with `__OBJC,__meth_var_names` / `__OBJC,__meth_var_types` (reloc addends, not the raw
pointer words). Call targets are the IDA analysis `calls[].target` / `calls[].name`
fields. Ghidra's 77-function partition is recorded under Analyzer disagreement; it is not
used to invent a majority vote.

Offsets below were **not** taken from the mailbox `AIC6X60Types.h`. The live
header matches these IDA displacements.

## Architecture: HIM + sequencer

The mailbox clone is deleted. `AIC6X60Routines.m` is gone. Forbidden mailbox
tokens (`AIC_CMD_INIT`, `aic_setup_mb_area`, `aicMbArea`, `allocCcb:`,
`runPendingCommands`, …) have no definition site; 
`tools/binrecon/tests/test_adaptec6x60_mailbox_residue.py` passes. The engine
is `HIM6X60.c` plus `AIC6X60Sequencer.c`. Completions stay IOThread-side:
ISR/IRQ mark `scb->completed`; `interruptOccurred` walks `him_scb` and sends
`commandCompleted:reason:`.

`repinsb` / `repinsw` / `repinsd` / `repoutsb` / `repoutsw` / `repoutsd`
live in `AIC6X60Sequencer.c`. `__OBJC,__class_names` in the reference `_reloc`
still contains the original compilation unit names `HIMRoutines.m`,
`AICController.m`, and `AICThread.m`.

`+[AIC6X60 probe:]` logs `"AIC6X60: can't find host adapter!\n"`; init
failure logs `"AIC6X60: couldn't initialize HIM!\n"`.

## Ivar / SCB / HIM-state layouts

Read from `__OBJC,__class` + `__OBJC,__instance_vars` (148 bytes at address 36600: count 12
followed by twelve 12-byte `{name, type, offset}` entries) and from IDA bodies that index
`self`. Class `AIC6X60` superclass `IOSCSIController`, `instance_size` **4220** (`0x107c`).
First driver ivar is at `0x244`, the same `IOSCSIController` tail that 1542B uses; after
that the layouts share nothing.

### `AIC6X60` ivars

| Offset | Name | Encoding |
| --- | --- | --- |
| 580 (`0x244`) | `hacb` | `{_HACB=...}` (see below) |
| 1492 (`0x5d4`) | `scsiBus` | `C` |
| 1494 (`0x5d6`) | `ioBase` | `S` |
| 1496 (`0x5d8`) | `totalCommands` | `I` |
| 1500 (`0x5dc`) | `interruptPortKern` | `i` |
| 1504 (`0x5e0`) | `ioThreadRunning` | `c` |
| 1508 (`0x5e4`) | `him_scb` | `[32{_SCB=...}]` |
| 4196 (`0x1064`) | `nextScb` | `i` |
| 4200 (`0x1068`) | `pendingQ` | `{?=next^{queue_entry} prev^{queue_entry}}` |
| 4208 (`0x1070`) | `numFreeScbs` | `i` |
| 4212 (`0x1074`) | `dmaEnabled` | `c` |
| 4216 (`0x1078`) | `currentDMABuffer` | `^v` |

`him_scb` is a 32-element inline array: `0x5e4 + 32*0x54 = 0x1064`, which is exactly
`nextScb`. `initFromDeviceDescription:` writes `numFreeScbs = 0x20` (32) at `self+0x1070`
and `controllerId = self` at `self+0x5d0` (`hacb+0x38c`).

`AIC6X60Types.h` now declares this ivar layout (`hacb`, `scsiBus`, `him_scb`,
`nextScb`, `pendingQ`, `numFreeScbs`, `dmaEnabled`, `currentDMABuffer`). The
mailbox names (`aicMbArea`, `aicCcb`, `numFreeCcbs`, …) are gone.

### `struct _SCB` (`sizeof` 84 / `0x54`)

The `him_scb` encoding lists fields in order. Sizes on i386: `^`/`*`/`I`/`i` = 4, `S` = 2,
`C`/`c` = 1, `Q` = 8. One pad byte before `timeout_Port` restores 4-byte alignment. This
matches IDA: `_HIM6X60CompleteSCB` does `mov byte ptr [eax+46h], 1`;
`interruptOccurred` tests `[ebx+46h]` (`completed`) and `[ebx+44h]` (`in_use`) and steps
the pool by `0x54`.

| Offset | Field |
| --- | --- |
| `0x00` | `chain` (`^{_SCB}`) |
| `0x04` | `length` (`I`) |
| `0x08` | `osRequestBlock` (`^v`) |
| `0x0c` | `linkedScb` (`^{_SCB}`) |
| `0x10` | `function` (`C`) |
| `0x11` | `scbStatus` (`C`) |
| `0x12` | `flags` (`S`) |
| `0x14` | `targetStatus` (`C`) |
| `0x15` | `scsiBus` (`C`) |
| `0x16` | `targetID` (`C`) |
| `0x17` | `lun` (`C`) |
| `0x18` | `queueTag` (`C`) |
| `0x19` | `tagType` (`C`) |
| `0x1a` | `cdbLength` (`C`) |
| `0x1b` | `senseDataLength` (`C`) |
| `0x1c` | `cdb` (`*`) |
| `0x20` | `senseData` (`*`) |
| `0x24` | `dataPointer` (`*`) |
| `0x28` | `dataLength` (`I`) |
| `0x2c` | `dataOffset` (`I`) |
| `0x30` | `segmentAddress` (`I`) |
| `0x34` | `segmentLength` (`I`) |
| `0x38` | `transferLength` (`I`) |
| `0x3c` | `transferResidual` (`I`) |
| `0x40` | `provisionalTransfer` (`I`) |
| `0x44` | `in_use` (`c`) |
| `0x45` | `timedOut` (`c`) |
| `0x46` | `completed` (`c`) |
| `0x47` | pad |
| `0x48` | `timeout_Port` (`I`) |
| `0x4c` | `startTime` (`Q`) |

`commandCompleted:reason:` in the reference takes this SCB: `osRequestBlock` at `+8` is the
command buf, `scbStatus` at `+0x11`, `targetStatus` at `+0x14`, `timedOut` at `+0x45`,
`transferLength` at `+0x38`.

### `struct _HACB` (`sizeof` 1488 / `0x390`)

`hacb.length` is written with literal `0x390` at `initFromDeviceDescription:` (`mov dword
ptr [esi+244h], 390h`). `scsiBus` begins immediately after the HACB (`0x244+0x390 =
0x5d4`). Full encoding from `__meth_var_types`:

```
{_HACB="length"I"baseAddress"^(?)"scsiPhase"C"ownID"C"busID"C"lun"C
 "ac"(?)"cs"(?)"disableINT"I"deferredScb"^{?}"eligibleScb"^{?}
 "queueFreezeScb"^{?}"resetScb"^{?}"nx"(?)
 "targetStatus"C"reservedForAlignment1"C
 "syncCycles"[8C]"syncOffset"[8C]"cQueuedScb"I"cActiveScb"I
 "negotiateSDTR"C
 "sdtrMsg"{?="extMsgCode"C"extMsgLength"C"extMsgType"C"transferPeriod"C"reqAckOffset"C}
 "requestSenseCdb"[6C]
 "sStat0"C"maskedSStat0"C"sStat1"C"maskedSStat1"C
 "selectTimeLimit"S"sXfrCtl1Image"C"irqConnected"C"clockPeriod"C
 "IRQ"C"dmaChannel"C"revision"C"dmaBusOnTime"C"dmaBusOffTime"C
 "signature"I"scsiCount"I
 "lucb"[64{?="busy"C"queuedScb"^{?}"activeScb"^{?}}]
 "controllerId"@}
```

The empty `(?)` unions (`ac`, `cs`, `nx`, and `baseAddress`'s pointee) do not have a width
in the encoding. Do not guess those widths from `AIC6X60Types.h`. IDA-confirmed accesses
into the HACB (`ebx` = `&self->hacb`, i.e. `self+0x244`):

| HACB offset | Access | Field (encoding name) |
| --- | --- | --- |
| `+0` | `mov dword ptr [esi+244h], 390h` | `length` |
| `+4` | `mov dx, [ebx+4]` then `in`/`out` at `dx+0x0b`..`+0x14` | `baseAddress` used as 16-bit I/O port |
| `+8` | `mov byte ptr [ebx+8], 0FFh` in `HIM6X60Initialize` | `scsiPhase` |
| `+9` | `mov byte ptr [esi+24Dh], 7` | `ownID` |
| `+0x0d` | `or`/`and` bit 7 in `HIM6X60ISR` / `HIM6X60IRQ` | (inside `ac`/`cs` region) |
| `+0x10` | `inc`/`dec dword ptr [ebx+10h]` | `disableINT` nested-ISR count |
| `+0x24` | `cmp dword ptr [ebx+24h], 0` then treat as SCB* in `_isr` | one of the SCB* slots (`deferredScb` / `eligibleScb` / `queueFreezeScb` / `resetScb`) |
| `+0x74` | `_isr` `mov [ebx+74h], al` | `sStat0` |
| `+0x75` | `mov [ebx+75h], al` | `maskedSStat0` |
| `+0x76` | `mov [ebx+76h], al` | `sStat1` |
| `+0x77` | `mov [ebx+77h], al` | `maskedSStat1` |
| `+0x78` | `mov word ptr [ebx+78h], 100h` | `selectTimeLimit` |
| `+0x7b` | `cmp byte ptr [ebx+7Bh], 0` in `HIM6X60IRQ` | `irqConnected` |
| `+0x38c` | `mov [esi+5D0h], esi` | `controllerId` |

`lucb[64]` is in the encoding (`busy` / `queuedScb` / `activeScb` per LUN). Per-entry
stride was not locked from a single IDA displacement in this pass; `HIM6X60GetLUCB`
exists at 17160 (31 bytes) as the accessor.

## Completion policy

The HIM does **not** finish the command buf and does **not** wake the IOThread by itself.

1. `-[AIC6X60 interruptOccurred]` (1048) does `lea eax, [edi+244h]` / `call _HIM6X60IRQ`.
   It does not call `_HIM6X60ISR`.
2. `_HIM6X60IRQ` (8012) acknowledges the chip (`in` at `base+0x14`, mask `0x20`), optionally
   `call _HIM6X60Watchdog` (17512), then `call _isr` (8612).
3. `_HIM6X60ISR` (8164) is the same chip-ack / nested-`disableINT` envelope without the
   watchdog arm, then `call _isr`.
4. `_isr` dispatches the sequencer: `_HIM6X60ResetBus`, `_scsiBusFree`, `_reselection`,
   `_selection`, `_quiesceDmaAndSCSI`, `_updateDataPointer`, `_targetREQuest`.
5. `_HIM6X60CompleteSCB` (17056, 14 bytes) only does `mov byte ptr [eax+46h], 1`
   (`scb->completed = 1`) and returns. `_HIM6X60Event` (17072) is an empty `ret`.
   `_HIM6X60TerminateSCB` calls `_HIM6X60CompleteSCB` at 7476.
6. Back in `interruptOccurred`, the IOThread walks `him_scb` (`edi+0x5e4` .. `edi+0x1010`
   inclusive, step `0x54`). For each SCB with `completed && in_use` it sends
   `commandCompleted:reason:` with reason `0`. If `pendingQ` is non-empty and
   `numFreeScbs != 0` it dequeues and sends `threadExecuteRequest:`.

So completions are **IOThread-side**: ISR/IRQ mark the SCB; `interruptOccurred` calls
`commandCompleted:reason:`, which unlocks the command-buf lock the client is waiting on
in `executeCmdBuf:`.

## Numbered findings: report-pass mailbox bodies (rewritten)

These were the report-pass notes. The rewrite landed in Tasks 7–8; the
"Source:" lines below describe the **old** mailbox tree, not the live HIM
sources. Call targets on the **reference** side remain IDA.

### Finding 1: `-[AIC6X60 initFromDeviceDescription:]` (156)

**Source:** `AIC6X60Controller.m:97` — `IOMallocLow` of `aic_mb_area` / `struct ccb`,
`aic_setup_mb_area(ioBase, aicMbArea, aicCcb)`.

**Reference:** `call _HIM6X60GetConfiguration` (4116) then `call _HIM6X60Initialize`
(5212). Writes `hacb.length = 0x390`, `ownID = 7`, `numFreeScbs = 32`. Failure path logs
`"AIC6X60: couldn't initialize HIM!\n"`.

**Disposition:** rewrite (HIM, not mailbox).

### Finding 2: `-[AIC6X60 free]` (864)

**Source:** `AIC6X60Controller.m:198` — `IOFreeLow` of `aicMbArea` / `aicCcb`.

**Reference:** if `ioThreadRunning` (`self+0x5e0`) is set, `executeCmdBuf:` with `op = 2`
(`AO_Abort`), then `[super free]`. No mailbox free.

**Disposition:** rewrite.

### Finding 3: `-[AIC6X60 interruptOccurred]` (1048)

**Source:** `AIC6X60Controller.m:292` — `aic_get_intr` / `aic_clr_intr`, walk
`aicMbArea->mb_in`, `commandCompleted:` on CCBs, `runPendingCommands`.

**Reference:** `call _HIM6X60IRQ` then SCB-pool walk / `commandCompleted:reason:` /
`threadExecuteRequest:` as in Completion policy.

**Disposition:** rewrite.

### Finding 4: `-[AIC6X60 timeoutOccurred]` (1268)

**Source:** `AIC6X60Controller.m:374` — scan CCB `outstandingQ`/`pendingQ`,
`commandCompleted: reason:CS_Timeout`, `threadResetBus:`.

**Reference:** `call _IOSleep` then one `objc_msgSend` (91 bytes total). Not a CCB mailbox
scan.

**Disposition:** rewrite.

### Finding 5: `-[AIC6X60 commandRequestOccurred]` (1260)

**Source:** `AIC6X60Controller.m:443` — drain `commandQ`, `threadResetBus:` /
`threadExecuteRequest:` / `allocCcb` back-pressure.

**Reference:** empty function (`push ebp; mov ebp, esp; mov esp, ebp; pop ebp; retn`).
Command bufs are not dequeued here; `receiveMsg` (1392, 225 bytes) is the IOThread message
pump (`_msg_receive`, `executeCmdBuf:` waiters, `IOExitThread`).

**Disposition:** rewrite (and stop using this selector as the commandQ processor).

### Finding 6: `-[AIC6X60 probeAtPortBase:]` (1620)

**Source:** `AIC6X60Controller.m:498` — `aic_reset_board`, `aic_probe_cmd(...,
AIC_CMD_DO_INQUIRY)`, `aic_probe_cmd(..., AIC_CMD_GET_CONFIG)`.

**Reference:** `call _bzero` then `call _HIM6X60FindAdapter` (3820). 66 bytes.

**Disposition:** rewrite.

### Finding 7: `-[AIC6X60 threadExecuteRequest:]` (2260)

**Source:** `AIC6X60Thread.m:53` — `allocCcb:`, `ccbFromCmd:ccb:`, `IOScheduleFunc(aicTimeout,
...)`, `runPendingCommands`.

**Reference:** `objc_msgSend` (alloc/build SCB), `call _IOScheduleFunc`, `call
_HIM6X60QueueSCB` (6568).

**Disposition:** rewrite.

### Finding 8: `-[AIC6X60 threadResetBus:]` (2508)

**Source:** `AIC6X60Thread.m:98` — drain CCB queues, `aic_reset_board`, `aic_setup_mb_area`,
`aic_put_ctrl` with `scsi_rst`.

**Reference:** `call _HIM6X60ResetBus` (7772), `IOLog` / `IOSleep`, then complete the
command buf.

**Disposition:** rewrite.

### Finding 9: `-[AIC6X60 commandCompleted:reason:]` (2976)

**Source:** `AIC6X60Thread.m:391` — `struct ccb` host_status / `aic_get_24(data_len)`,
`freeCcb:`, `IOUnscheduleFunc(aicTimeout, ccb)`.

**Reference:** operates on `_SCB` (`osRequestBlock`, `scbStatus`, `targetStatus`,
`timedOut`); `call _IOGetTimestamp`, `objc_msgSend` (DMA complete/abort / `freeScb:`),
`call _IOUnscheduleFunc`. No CCB.

**Disposition:** rewrite.

### Finding 10: `+[AIC6X60 probe:]` (0)

**Source:** `AIC6X60Controller.m:70` — `probeAtPortBase:` (Finding 6).

**Reference:** still a DriverKit probe, but the failure string is `"AIC6X60: can't find host
adapter!\n"` and init failure is the HIM log from Finding 1. Indirect mailbox only through
our `probeAtPortBase:`.

**Disposition:** rewrite with Finding 6.

`maxTransfer` now uses `dmaEnabled` at `self+0x1074` (`0x10000` vs `_page_size`).
`executeRequest:buffer:client:`, `resetSCSIBus`, `otherOccurred:`, `receiveMsg`,
`executeCmdBuf:`, `completeDMA:length:`, and `abortDMA:length:` stay mapped;
several remain `unexamined` in the ledger because this pass did not re-read
every instruction.

## Table / help / bundle extras

`"Driver Version"` is ignored throughout. Task 9 aligned `Default.table` and
`AIC_PCMCIA.table` with the reference bundle; the diffs below are the
report-pass snapshot.

### `Default.table`

| Key | Ours | Reference |
| --- | --- | --- |
| Valid DMA Channels | *absent* | `"0 5 6 7"` |
| Valid I/O Ports | `"0x340-0x35f"` | *absent* |
| Help File | mangled `AIC6X60SCSI_PROJECT.drvAdaptec6x60-15_DEVELOPER.root_BUILT:Sat Mar 28 21:59:55 PST 1998` | `AIC_6X60_SCSI_Adapter.rtfd` |

Title, Family, Driver Name, DMA Channels, IRQ, I/O Ports, Valid IRQ Levels, Boot Driver,
Server Name, Version otherwise match.

### `AIC_PCMCIA.table`

| Key | Ours | Reference |
| --- | --- | --- |
| Driver Name | `"AIC6X60"` | *absent* |
| Class Names | *absent* | `"AIC6X60"` |
| Auto Detect IDs | *absent* | `"MFR=AdaptecInc.,PROD=APA-1460SCSIHostAdapter"` |

Help File already `AIC_6360_PCMCIA_SCSI_Adapter.rtfd`. Valid DMA Channels already `"0 5 6 7"`.

### `DriverInfo`

Ours: `Adaptec6X60.drvproj/DriverInfo` (short text, "Adaptec 6x60 SCSI Driver", Version 5.00).
The reference `AIC6X60SCSI.config` directory has **no** `DriverInfo`.

### `Load_Commands.sect` vs `Loaded Server,Load Commands`

The `_reloc` section `Loaded Server,Load Commands` (164 bytes) is:

```
# 
# This loadable kernel driver does not use a Mig-generated interface,
# so no handler or server interface is specified.
#
# This driver must be wired down.
WIRE
```

Our `$LKS/Load_Commands.sect` is the same text except the first line is `#` without the
trailing space the `_reloc` has (`"# \n"` vs `"#\n"`). `Loaded Server,Server Name` is
`AIC6X60SCSI`. `Loaded Server,Instance Var` is `AIC6X60SCSI_instance`. `Loaded Server,Server
Version` is the single byte `2`.

### `English.lproj`

Copied from the reference bundle in Task 9. Present:

- `Localizable.strings`
- `AIC_PCMCIA.strings`
- `Help/AIC_6X60_SCSI_Adapter.rtfd/TXT.rtf`
- `Help/AIC_6360_PCMCIA_SCSI_Adapter.rtfd/TXT.rtf`
- `Help/TableOfContents.rtf`

## Analyzer disagreement

IDA 9.2 reports **79** `__text` functions. Ghidra 12.1 reports **77**. Ghidra has no
function starting at the two IDA addresses:

| Address | IDA name | Size | Ghidra |
| --- | --- | --- | --- |
| 2260 | `-[AIC6X60 threadExecuteRequest:]` | 247 | no function at this address (previous IDA function is `initDMA` at 1884 size 373, ending 2257) |
| 17916 | `+[AIC6X60SCSIKernelServerInstance kernelServerInstance]` | 12 | no function at this address (`_repoutsw` is 17856 size 58 ending 17914; next Ghidra function is 17928, the Version glue) |

Ghidra-only addresses: none. No `boundary_disputed` entries were added. IDA is the
partition of record; the ledger stamps `analyzer_agreement.status = agreed` with
`analyzers = ["Ghidra", "IDA"]` (schema-canonical order) and the reason that IDA partitions
and Ghidra is a second opinion on bodies. That object is **not** a majority vote that the
77- and 79-function partitions are the same.

angr 9.3.0 produced `analysis-reference-angr.json`; it is not evidence.

## Unmapped reason classes

2 unmapped, both with `source_path` null.

**Glue (2)** — Kernel Server project type, marked `intentional-mismatch` /
reviewer `Pat Raynor`:

- 17916 `+[AIC6X60SCSIKernelServerInstance kernelServerInstance]`
- 17928 `+[AIC6X60SCSIVersion driverKitVersionForAIC6X60SCSI]`

## Task 7: HACB sync-array layout

IDA indexes `[hacb+4Eh+i]` / `[hacb+56h+i]` as the per-target sync arrays
(`updateSDTR`, `selection`, `resetSDTR`). The ObjC `_HACB` encoding listed
`targetStatus`/`reservedForAlignment1` at `+0x4E` and put `syncCycles` at
`+0x50`. IDA wins: `syncCycles[8]` is at `+0x4E`, `syncOffset[8]` at `+0x56`,
and a two-byte pad at `+0x5E` keeps `cQueuedScb` at `+0x60`, `sStat0` at
`+0x74`, `selectTimeLimit` at `+0x78`, `controllerId` at `+0x38c`,
`sizeof(_HACB) == 0x390`.

## Task 7: HIM / sequencer definition sites

Written from IDA `analysis-reference-ida.json` instructions/blocks/calls (no
decompilation in the published JSON). `repins*` / `repouts*` now live in
`AIC6X60Sequencer.c`.

- [x] HIM6X60Initialize
- [x] HIM6X60ISR
- [x] HIM6X60QueueSCB
- [x] HIM6X60AbortSCB
- [x] HIM6X60FindAdapter
- [x] HIM6X60GetConfiguration
- [x] HIM6X60GetStackContents
- [x] HIM6X60TerminateSCB
- [x] HIM6X60ResetBus
- [x] HIM6X60DisableINT
- [x] HIM6X60EnableINT
- [x] HIM6X60AssertINT
- [x] HIM6X60IRQ
- [x] HIM6X60CompleteSCB
- [x] HIM6X60Event
- [x] HIM6X60FlushDMA
- [x] HIM6X60GetLUCB
- [x] HIM6X60GetPhysicalAddress
- [x] HIM6X60LogError
- [x] HIM6X60MapDMA
- [x] HIM6X60Watchdog
- [x] HIM6X60DmaProgrammed
- [x] himTimeout
- [x] initiateIO
- [x] deferredIsr
- [x] watchdog
- [x] isr
- [x] linkScbPreemptive
- [x] linkScb
- [x] unlinkScb
- [x] memset
- [x] selection
- [x] reselection
- [x] scsiBusFree
- [x] scsiBusReset
- [x] targetREQuest
- [x] samePhaseREQuest
- [x] interpretMessageIn
- [x] prepareMessageOut
- [x] negotiateSDTR
- [x] updateSDTR
- [x] resetSDTR
- [x] dataInPIO
- [x] dataOutPIO
- [x] dataPhaseDMA
- [x] quiesceDmaAndSCSI
- [x] updateDataPointer
- [x] bitbucketAndABORT

HACB sync arrays follow IDA displacements, not the ObjC encoding order that
placed `targetStatus`/`reservedForAlignment1` at `+0x4E`. `syncCycles[8]` is
at `+0x4E` and `syncOffset[8]` at `+0x56`, with two pad bytes at `+0x5E` so
`cQueuedScb` stays at `+0x60`, `sStat0` at `+0x74`, `selectTimeLimit` at
`+0x78`, `controllerId` at `+0x38c`, and `sizeof(_HACB)` at `0x390`.

The first sequencer pass truncated several bodies (`targetREQuest` tested
`scb->function & 0x408000` as a byte, which is always 0). Those functions
were rewritten from the IDA instruction dumps so the reference call targets
and major branches exist. `samePhaseREQuest` returns `int` (IDA `eax`).
`targetREQuest` tests the dword at SCB `+0x10` against `0x408000`.

### Task 7 quality review (IDA, not Linux)

**PIO `+0x34 == 0`.** `_dataInPIO` / `_dataOutPIO` do **not** call
`_HIM6X60GetPhysicalAddress`. That call exists only in `_dataPhaseDMA`.
When segment length at `hacb+34h` is 0 the PIO bodies store `+0x28` and
`+0x34` to themselves, then compare residual `+0x2C` against `+0x34` and
`jz` back to refill. Unsigned `2C >= 0` is always true, so the clamp is
dead and IDA itself tight-loops; it does not return or `ResetBus`. Left
as that control flow.

`_dataInPIO` (no GetPhysicalAddress in `calls`; refill is `loc_3648`):

```
13906  cmp      dword ptr [esi+34h], 0
13910  jnz      loc_3678
13912  mov      eax, [esi+28h]
13915  mov      [esi+28h], eax
13918  mov      eax, [esi+34h]
13921  mov      [esi+34h], eax
13924  mov      edx, [esi+34h]
13927  cmp      [esi+2Ch], edx
13930  jnb      loc_366F
13932  mov      edx, [esi+2Ch]
13935  mov      [esi+34h], edx
13938  test     edx, edx
13940  jz       loc_3648
```

`_dataOutPIO` (same shape; refill is `loc_3450`):

```
13402  cmp      dword ptr [esi+34h], 0
13406  jnz      loc_3480
13408  mov      eax, [esi+28h]
13411  mov      [esi+28h], eax
13414  mov      edx, [esi+34h]
13417  mov      [esi+34h], edx
13420  mov      ecx, [esi+34h]
13423  cmp      [esi+2Ch], ecx
13426  jnb      loc_3477
13428  mov      ecx, [esi+2Ch]
13431  mov      [esi+34h], ecx
13434  test     ecx, ecx
13436  jz       loc_3450
```

Contrast `_dataPhaseDMA`, which does refill `+0x34` from GetPhysicalAddress:

```
14323  cmp      dword ptr [ebx+34h], 0
14327  jnz      loc_3823
14329  lea      eax, [ebx+34h]
...
14346  call     _HIM6X60GetPhysicalAddress
```

**Watchdog scale.** `_HIM6X60Watchdog` multiplies milliseconds by `3E8h`
(1000), not 1_000_000. The reloc passes that product to `_ns_timeout`.
Kept `milliseconds * 1000ULL`.

```
17548  mov      eax, 3E8h
17553  mul      ecx
```

**Signature immediates differ in IDA.** `_HIM6X60GetConfiguration` uses
`0FFFFFFAEh` (window `0x52`/`0x53`); `_updateSDTR` / `_resetSDTR` use
`0FFFFFFADh` (window `0x53`/`0x54`). Both kept.

```
4199   add      eax, 0FFFFFFAEh     ; GetConfiguration
4485   add      eax, 0FFFFFFAEh
4912   add      eax, 0FFFFFFAEh
16188  add      eax, 0FFFFFFADh     ; updateSDTR
16521  add      eax, 0FFFFFFADh     ; resetSDTR
16698  add      eax, 0FFFFFFADh
```

## Ledger (Task 10)

Statuses were advanced only after re-reading IDA against the live source.
Do not treat `unexamined` as "wrong"; those bodies were not instruction-compared
in this pass.

| Status | Count |
| --- | --- |
| assembly-matched | 13 |
| control-flow-confirmed | 10 |
| unexamined | 54 |
| intentional-mismatch | 2 |

**assembly-matched** (every IDA instruction compared): `HIM6X60CompleteSCB`,
`HIM6X60Event`, `commandRequestOccurred`, `probeAtPortBase:`, `freeScb:`,
`maxTransfer`, `getDMAAlignment:`, `repinsb` / `repinsw` / `repinsd` /
`repoutsb` / `repoutsw` / `repoutsd`.

**control-flow-confirmed** — block shape and call targets compared; not traced
operand-by-operand:

- `targetREQuest` — SCSISIG/SXFRCTL programming and the `0x408000` dword-test
  side paths
- `interpretMessageIn` — each message-byte table compare and residual SDTR
  field writes
- `HIM6X60Initialize` — each `outb` immediate and the IRQ-connected probe loop
- `HIM6X60GetConfiguration` — every STACK in/out and `ac` bitfield pack
- `HIM6X60QueueSCB` — LUCB busy/unlink arithmetic and `segmentLength` clamps
- `scsiBusFree` — each CLRSINT/SIMODE immediate and linked-SCB complete cases
- `commandCompleted:reason:` — `scsiReq` field stores and the bad-status
  IOLog format immediate
- `initFromDeviceDescription:` — each `objc_msgSend` selector word and the
  `hacb.ac` bit stores
- `initDMA` — width immediate vs `hacb.dmaChannel` at `self+0x2C2` and every
  `stringFromReturn:` path
- `scbFromCmd:scb:` — each SCB field store displacement and the default
  reject immediates

Glue stays `intentional-mismatch`, reviewer Pat Raynor.

## What was not attempted

No `binrecon compare` of the guest `_reloc` against the reference. No hardware
test. Mapped bodies not listed above stay `unexamined` rather than guessed.
HACB `(?)` union widths that IDA did not pin are left as the Task 7 layout
rather than invented. Linux `aic6x60` was not used as a template.
