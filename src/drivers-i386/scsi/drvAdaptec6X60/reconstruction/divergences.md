# drvAdaptec6X60 divergences

Reference: `AIC6X60SCSI_reloc`, SHA-256 `E70647063BC4E6BC4BF47F73BF298BEAC59264B163C9D9D1920788CCBCE35E13`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 (angr not used as evidence per the task brief; it
over-segments this binary via `CFGFast` the same way it did for the bus drivers and 1542B.
IDA found the 79 functions that match the Mach-O / ObjC method table, so IDA is treated as
the authoritative partition and Ghidra as a second opinion on bodies)

## Baseline build

The report pass compared the reference binary's disassembly and ObjC metadata directly
against the checked-in source. `rebuilt_sha256` in `ledger.json` is still `null` for every
entry: the Task 5 reloc is a mailbox-stub compile, not a HIM reconstruction to diff.
Mapped functions that diverge stay `unexamined`. `src/drivers-i386/README` still lists this
driver as a stub on the wrong architecture.

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
`AIC6X60Thread.m` import `<mach/vm_param.h>` for `PAGE_SIZE`. No HIM rewrite.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 25 |
| unmapped | 54 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

The architecture is wrong. The reference is an Adaptec HIM plus a SCSI sequencer that
programs AIC-6260/6360 ports directly. Our tree is still the AHA-1542B mailbox clone
(`AIC_CMD_INIT`, `aic_setup_mb_area`, `allocCcb:`, `runPendingCommands`). The 25 mapped
symbols are DriverKit selector names (and `memset` / `repins*` / `repouts*`) that happen
to exist in `$LKS/*.m`; the bodies still call mailbox helpers, or, for the PIO primitives,
live in the mailbox `AIC6X60Routines.m` file. The 54 unmapped symbols are the actual chip
engine plus five DriverKit helpers our `.m` files never define, plus two Kernel Server
glue methods.

## Method

Every function was read from
`tools/binrecon/out/adaptec6x60/published/analysis-reference-ida.json`. Ivar names, type
encodings, and offsets come from `__OBJC,__instance_vars` in the reference Mach-O together
with `__OBJC,__meth_var_names` / `__OBJC,__meth_var_types` (reloc addends, not the raw
pointer words). Call targets are the IDA analysis `calls[].target` / `calls[].name`
fields. Ghidra's 77-function partition is recorded under Analyzer disagreement; it is not
used to invent a majority vote.

Offsets below are **not** taken from `AIC6X60Types.h`. That header is the mailbox layout
and is the thing being replaced.

## Architecture: mailbox vs HIM

Our live code still defines these forbidden mailbox symbols (they must have no definition
site and no call site after the rewrite):

```
aic_cmd aic_probe_cmd aicTimeout aic_start_scsi aic_setup_mb_area
aic_reset_board aic_unlock_mb
AIC_CMD_INIT AIC_CMD_START_SCSI AIC_CMD_DO_INQUIRY
AIC_CMD_GET_CONFIG AIC_CMD_GET_BIOS_INFO AIC_CMD_SET_MB_ENABLE
allocCcb: freeCcb: ccbFromCmd:ccb: runPendingCommands
aicMbArea aic_mb_area
```

Homes: `AIC6X60Types.h`, `AIC6X60Inline.h`, `AIC6X60ControllerPrivate.h`,
`AIC6X60Controller.h`, `AIC6X60Controller.m`, `AIC6X60Thread.h`, `AIC6X60Thread.m`,
`AIC6X60Routines.m`.

The reference has none of those names. Its engine, which our tree does not define, includes:

```
HIM6X60Initialize HIM6X60ISR HIM6X60QueueSCB HIM6X60AbortSCB
HIM6X60FindAdapter HIM6X60GetConfiguration HIM6X60ResetBus
HIM6X60IRQ HIM6X60CompleteSCB HIM6X60TerminateSCB
selection reselection scsiBusFree scsiBusReset
targetREQuest samePhaseREQuest interpretMessageIn prepareMessageOut
negotiateSDTR updateSDTR resetSDTR
dataInPIO dataOutPIO dataPhaseDMA
```

`repinsb` / `repinsw` / `repinsd` / `repoutsb` / `repoutsw` / `repoutsd` exist in both;
they stay. `__OBJC,__class_names` in the `_reloc` still contains the original compilation
unit names `HIMRoutines.m`, `AICController.m`, and `AICThread.m`.

`+[AIC6X60 probe:]` in the reference logs `"AIC6X60: can't find host adapter!\n"` and
`"AIC6X60: couldn't initialize HIM!\n"`. Ours probes with `AIC_CMD_DO_INQUIRY` /
`AIC_CMD_GET_CONFIG`.

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

Our header instead declares `config`, `aicBoardId`, `aicMbArea`, `aicCcb`, `numFreeCcbs`,
`commandQ`, `commandLock`, `outstandingQ`, `outstandingCount`, `dmaLockCount`, `maxQueueLen`,
`queueLenTotal`. Those names are not in `__instance_vars`.

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

## Numbered findings: mapped DriverKit methods that still call mailbox helpers

These selectors exist in both the `_reloc` and our `.m` files (source-map `mapped`).
Our bodies still talk mailboxes. They stay `unexamined`. Call targets on the **reference**
side are quoted from IDA.

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

`maxTransfer`, `executeRequest:buffer:client:`, `resetSCSIBus`, `otherOccurred:`,
`receiveMsg`, `executeCmdBuf:`, `completeDMA:length:`, and `abortDMA:length:` are mapped
and stay `unexamined`; they do not call the forbidden `aic_*` helpers by name, but several
still assume mailbox constants (`AIC_SG_COUNT` in our `maxTransfer` vs the reference's
`dmaEnabled` at `self+0x1074` choosing `_page_size` vs `0x10000`).

## Table / help / bundle extras

`"Driver Version"` is ignored throughout.

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

Ours: **missing**. Reference `AIC6X60SCSI.config/English.lproj/` contains:

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

54 unmapped, all with `source_path` null.

**Glue (2)** — Kernel Server project type, marked `intentional-mismatch` / reviewer
`Pat Raynor`:

- 17916 `+[AIC6X60SCSIKernelServerInstance kernelServerInstance]`
- 17928 `+[AIC6X60SCSIVersion driverKitVersionForAIC6X60SCSI]`

**Absent DriverKit helpers without `.m` defs (5):**

- 780 `-[AIC6X60 getDMAAlignment:]`
- 1884 `-[AIC6X60 initDMA]`
- 2632 `-[AIC6X60 scbFromCmd:scb:]`
- 3420 `-[AIC6X60 allocScb]`
- 3600 `-[AIC6X60 freeScb:]`

Our thread category still declares `ccbFromCmd:ccb:`, `allocCcb:`, `freeCcb:` instead.

**Absent HIM / sequencer (47):** everything else in `unmapped`, including `_himTimeout`,
the `HIM6X60*` API, `_isr` / `_deferredIsr` / `_watchdog`, the phase machine
(`_selection` … `_prepareMessageOut`), SDTR, PIO/DMA data path, SCB link helpers, and the
HIM callbacks (`_HIM6X60CompleteSCB`, `_HIM6X60Event`, `_HIM6X60MapDMA`, …).

## What was not attempted

No source rewrite, no guest compile, no `binrecon compare` of a rebuilt `_reloc`. Mapped
mailbox bodies were not promoted past `unexamined`. HACB `(?)` union widths that IDA did
not pin are left unset rather than copied from the mailbox headers.
