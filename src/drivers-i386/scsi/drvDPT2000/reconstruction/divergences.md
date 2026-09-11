# drvDPT2000 divergences

Reference: `DPTSCSIDriver_reloc`, SHA-256 `5AE7A361F645EC693444A8AFC829DB477F34DE2576AFC0EB2A0D4128D3BD68A6`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 (angr not used as evidence; IDA is the
partition of record and Ghidra is a second opinion on bodies). Ledger
`analyzer_agreement.analyzers` is stored in schema-canonical order as
`["Ghidra", "IDA"]`.

## Baseline build

Built on guest **10.10.0.241** with rbuild (not `vm/build-i386-scsi.sh`, not a
hand `gnumake` of the `.lksproj`):

```
rbuild buildpackage --state /build/state --dir /build/src/drivers-i386/scsi/drvDPT2000 /build/repo /build/built
```

The first rbuild failed: missing `driverkit/i386/IODirectDevice.h` on the ppc
sysroot, undefined `AUX_IRQ` / `STAT_IRQ` / `EATA_CP_ADDR` / `SR_IOST_CMDTO`,
C89 mixed declarations, undeclared `PAGE_SIZE`, duplicate
`DPTSCSIDriver(Private)` category at `kl_ld`, and `movehelp` with no
`DriverHelp`. A minimum compile-fix is
`244260ced257b94d63be5272c180d688c913ff15` (`drivers-i386: build drvDPT2000`).
Linux residue and the `DPTSCSIDriver` class were left in place;
`EATAController` / `EATASCSIBus` were not implemented.

After that fix, rbuild exited 0. The guest toolchain is `gcc-darwin.conf`
(`RC_ARCHS=ppc`, `cc -arch ppc`). Guest package / reloc (not committed, not
compared with binrecon):

- apk: `/build/built/drvdpt2000-17.apk` (7934 bytes)
- reloc: `private/Drivers/ppc/DPT2000.config/DPT2000_reloc` (26120 bytes inside
  the apk)

`rebuilt_sha256` in `ledger.json` is still `null`. There is still no artifact
under `out/i386/`.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 0 |
| unmapped | 56 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

IDA `__text` contains 56 functions. The source map accounts for all 56 as
unmapped: our tree implements a single class `DPTSCSIDriver` subclassing
`IOSCSIController`, and shares no class name with the reloc. Glue (2) is already
accepted as `intentional-mismatch`; the other 54 entries stay `unexamined`.

The reloc is a two-class DriverKit stack compiled from `EATAController.m`,
`EATAThread.m`, and `SCSIBus.m`. Our stub is Linux-shaped under `DPTSCSIDriver`
and has no `EATASCSIBus`. Forbidden residue that exists in `$LKS` live code,
versus names that actually appear in the reloc:

| In our tree (must go) | In `DPTSCSIDriver_reloc` |
| --- | --- |
| `@interface DPTSCSIDriver` | `@interface EATAController`, `@interface EATASCSIBus` |
| `eataInitController` | `probeAtPortBase:`, `readConfig`, `readDMAConfig` |
| `allocCp` / `freeCp:` | `allocCcb:` / `freeCcb:` / `ccbFromCmd:` |
| `runPendingCommands` | `commandRequestOccurred` dispatches `threadExecuteRequest:` |
| `processCmdComplete` | `commandCompleted:reason:` |
| `struct dpt_config` | ivar `config` typed `{eata_config=...}` |
| `Based on Linux eata.c` (comment on `interruptOccurred`) | IRQ path walks `outstandingQ` and calls `commandCompleted:reason:` |

`allocCcb:`, `freeCcb:`, and `ccbFromCmd:` are Apple names on
`EATAController(IOThread)`. They are not Linux residue. Do not rename them to
`allocCp`. `"Server Name" = "DPTSCSIDriver"` in the tables is required and is
not residue.

## Method

ObjC class, superclass, and ivar evidence comes from `read_macho` on
`DPTSCSIDriver_reloc`: `__OBJC,__module_info`, `__OBJC,__class`,
`__OBJC,__instance_vars`, `__OBJC,__class_names`, and the `Loaded Server`
sections. Function bodies, call targets, and field displacements come from
`tools/binrecon/out/dpt2000/published/analysis-reference-ida.json`. Ghidra was
compared by address and size only. angr was not used as evidence.

## Superclasses, executeRequest owner, ivars, CP / SP

**Superclasses** are the strings the class_t `super` pointers relocate into
`__OBJC,__class_names`, plus the undefined symbols `.objc_class_name_IODirectDevice`
and `.objc_class_name_IOSCSIController`:

- `EATAController` : `IODirectDevice`. `instance_size = 0x1ac` (428). First
  declared ivar is at `+0x128`, so the `IODirectDevice` prefix is 296 bytes.
- `EATASCSIBus` : `IOSCSIController`. `instance_size = 0x24c` (588). First
  declared ivar is at `+0x244`, so the `IOSCSIController` prefix is 580 bytes.

`executeRequest:buffer:client:` is implemented on **`EATASCSIBus`**, not on
`EATAController`. IDA name `-[EATASCSIBus executeRequest:buffer:client:]` at
address 7888. The body loads `_direct` from `self+0x244` and sends
`executeCmdBuf:`.

Modules compiled into the reloc: `EATAController.m` (class +
`EATAController(PrivateMethods)`), `EATAThread.m` (`EATAController(IOThread)`),
`SCSIBus.m` (`EATASCSIBus` + `EATASCSIBus(PrivateMethods)`),
`DPTSCSIDriver_instance.m` (Kernel Server glue). `__OBJC,__class_names` also
contains `EATAExported`, `IOThread`, `IOPower`, `NXLock`, and `NXConditionLock`.

### `EATAController` ivars (`__OBJC,__instance_vars` at 0x7708, 17 entries)

Offsets are from the start of the instance, not from `DPTSCSIDriverTypes.h`.

| Off | Name | Encoded type |
| --- | --- | --- |
| +0x128 | `channelInfo` | `[3{?="owner"@"present"c}]` (3 × 8-byte slots) |
| +0x140 | `config` | `{eata_config=...}` (40 bytes; `ioBase` follows at +0x168) |
| +0x168 | `ioBase` | `S` |
| +0x16c | `busType` | `i` |
| +0x170 | `levelIRQ` | `c` |
| +0x174 | `commandQ` | `{?="next"^{queue_entry}"prev"^{queue_entry}}` |
| +0x17c | `outstandingQ` | same queue head |
| +0x184 | `outstandingCount` | `I` |
| +0x188 | `commandLock` | `@` |
| +0x18c | `maxQueueLen` | `I` |
| +0x190 | `queueLenTotal` | `I` |
| +0x194 | `totalCommands` | `I` |
| +0x198 | `configSgSize` | `I` |
| +0x19c | `dmaLockCount` | `I` |
| +0x1a0 | `ccbFree` | `^{ccb}` |
| +0x1a4 | `interruptPortKern` | `i` |
| +0x1a8 | `ioThreadRunning` | `c` |

`eata_config` field displacements, from the same type encoding (config ivar at
+0x140). Do not substitute `struct dpt_config` / `struct eata_config` from
`DPTSCSIDriverTypes.h`.

| Config off | Instance off | Field |
| --- | --- | --- |
| +0 | +0x140 | `config_data_len` `I` |
| +4 | +0x144 | `eata_signature` `I` |
| +8 | +0x148 | `mbz0:4`, `version:4` |
| +9 | +0x149 | `overlap_ok`, `target_mode_ok`, `truncate_needed`, `more_bit_ok`, `dma_ok`, `dma_channel_valid`, `is_ata`, `addr_valid` |
| +10 | +0x14a | `command_pad` `S` |
| +12 | +0x14c | `rsvd0` `C` |
| +13 | +0x14d | `host_addrs[3]` |
| +16 | +0x150 | `command_length` `I` |
| +20 | +0x154 | `status_length` `I` |
| +24 | +0x158 | `queue_size` `S` |
| +26 | +0x15a | `rsvd1[2]` |
| +28 | +0x15c | `sg_size` `S` |
| +30 | +0x15e | `irq:4`, `edge_triggered:1`, `secondary:1`, `dma_channel:2` |
| +31 | +0x15f | `rsvd2` `C` |
| +32 | +0x160 | `isaIoDisable:1`, `forceAddr:1`, `rsvd3:6` |
| +33 | +0x161 | `maxScsiId:5`, `maxChannel:3` |
| +34 | +0x162 | `maxLun` `C` |
| +35 | +0x163 | `rsvd4:6`, `pci:1`, `eisa:1` |
| +36 | +0x164 | `raidnum` `C` |
| +37 | +0x165 | `rsvd5` `C` |

`initFromDeviceDescription:` tests `byte ptr [edi+149h], 20h` (bit 5 of the
flags byte = `dma_channel_valid`) before `setTransferMode:forChannel:` /
`enableChannel:` / `readDMAConfig`. It reads the IRQ nibble from `[edi+15Eh]`.

### `EATASCSIBus` ivars (2 entries)

| Off | Name | Encoded type |
| --- | --- | --- |
| +0x244 | `_direct` | `@` (the `EATAController`) |
| +0x248 | `_scsiChannel` | `I` |

`initSCSIBus:channel:` writes those two ivars (`mov [edi+244h], eax` after
`directDevice`, then `mov [edi+248h], esi` from the channel argument) and
calls `[super initFromDeviceDescription:]`.

### In-memory CCB / CP / SP (from `allocCcb:` and `ccbFromCmd:`, not from our headers)

- `sizeof(struct ccb) == 0x37c` (892). `allocCcb:` carves a page with stride
  `+0x37C` and `bzero`s 0x37C bytes.
- `+0x00` / `+0x04`: queue chain. `interruptOccurred` unlinks with
  `[edx]` / `[edx+4]` while walking `outstandingQ` at `self+0x17C`.
- `+0x08`: start of the command packet (`lea edx, [esi+8]`, flags at `[esi+8]`,
  immediate `0x1A` written to `[esi+9]`). SP begins at `+0x34`, so the in-memory
  CP is **0x2c bytes**. Hardware `command_length` lives in `config` at +16 and is
  a board-reported size, not a second layout.
- CP+0x24 (`ccb+0x2c`): physical address of the status packet.
- CP+0x28 (`ccb+0x30`): physical address of the sense buffer.
- `+0x34`: start of the status packet. `interruptOccurred` treats the high bit of
  this byte as EOC (`cmp byte ptr [edx+34h], 0` / `jge` skips incomplete CCBs).
  `commandCompleted:reason:` reads `[ccb+0x35]` as SCSI/host status into the
  `IOSCSIRequest` and `[ccb+0x38]` as residue.
- `+0x4c`: accumulated transfer length.
- `+0x50`: pointer to the command buf.
- `+0x54`: scatter/gather list (`lea edx, [esi+54h]`).
- `+0x254`: DMA page-address array (`lea eax, [esi+254h]`).
- `+0x354` / `+0x358`: `ns_time_t` start time (`IOGetTimestamp`; timeout math
  subtracts this pair).
- `+0x35c`: timeout port (`threadExecuteRequest:` stores `interruptPortKern`).
- `+0x360`: sense buffer (`lea edx, [esi+360h]`).

### Command buf (from `-[EATASCSIBus executeRequest:buffer:client:]` and `executeCmdBuf:`)

Stack object passed to `executeCmdBuf:`:

| Off | Written as |
| --- | --- |
| +0x00 | `_scsiChannel` |
| +0x04 | `0` (op; `commandRequestOccurred` switches on `[ebx+4]`) |
| +0x08 | `scsiReq` |
| +0x0C | `buffer` |
| +0x10 | `client` |
| +0x14 | result (`mov eax, [ebp+var_10]` return) |
| +0x18 | `NXConditionLock` (`initWith:` / `lockWhen:` / `free`) |
| +0x1C / +0x20 | queue chain on `commandQ` (`self+0x174`) |

## Completion policy

The IRQ handler **finishes the command buf on the interrupt path**. It does not
merely wake the IOThread.

`-[EATAController interruptOccurred]` (IDA 1596):

1. `in al, dx` from `ioBase+7` (`mov dx, [esi+168h]` / `add dx, 7`).
2. Walk `outstandingQ` at `self+0x17C`. For each CCB whose SP byte at `+0x34`
   has the sign bit set, unlink it, `dec outstandingCount` at `self+0x184`,
   and `objc_msgSend` selector `commandCompleted:reason:` with reason `0`
   (`ds:paCommandcomplet`, `push 0` / `push edx` / `push esi`).
3. If `levelIRQ` at `self+0x170` is set, `enableAllInterrupts`.

No `msg_send_from_kernel` in this function.

### Register and command immediates (Task 7)

IRQ still only `in`s `ioBase+7`. Other paths do use more ports; offsets are IDA `add dx/cx, N` immediates:

| Off | Use |
| --- | --- |
| +0 | PIO config data (`in ax, dx` in `readConfig`, `dx = ioBase`) |
| +2..+5 | Physical address bytes (`readDMAConfig`, `threadExecuteRequest:`) |
| +7 | Command out / status in (`0xF0` PIO config, `0xFD` DMA config, `0xFF` send CP, `0xF9` reset) |
| +8 | Aux busy (`_eata_busy` / `_eata_busy_0`, `test al, 1`) |

`readConfig` waits on status bit `0x08` (`test al, 8`). CP byte 1 is immediate `0x1A` (`mov byte ptr [esi+9], 1Ah`). Signature compare is `45415441h` after bswap of config+4. Do not keep unused Linux commands (`0xC6`, `0xF2`, `0xFA`) or `SP_EOC 0x01`.

The IOThread is the **submit** path, not the completion path:

- `-[EATAController executeCmdBuf:]` enqueues on `commandQ` and calls
  `_msg_send_from_kernel` (IDA 2843) to `interruptPortKern`.
- `-[EATAController commandRequestOccurred]` `lock`s `commandLock`, dequeues,
  and `objc_msgSend`s `threadExecuteRequest:` (`ds:paThreadexecuter`) or
  `threadResetBus:initConfig:` (`ds:paThreadresetbus`), or `_IOExitThread`
  (IDA 2294).
- `-[EATAController threadExecuteRequest:]` sends `ccbFromCmd:`, schedules
  `_eataTimeout` via `_IOScheduleFunc` (IDA 4332), waits `_eata_busy_0`,
  then programs the board.
- `_eataTimeout` itself calls `_msg_send_from_kernel` (IDA 7462).
- `timeoutOccurred` also sends `commandCompleted:reason:` (`ds:paCommandcomplet`
  at 2021).
- `commandCompleted:reason:` `IOUnscheduleFunc`s `_eataTimeout`, then
  `completeDMA:` / `abortDMA:` / `freeCcb:`, and on reset
  `threadResetBus:initConfig:`.

`initFromDeviceDescription:` starts that thread with `[super startIOThread]`
(`ds:paStartiothread`) and sets `ioThreadRunning` at `self+0x1A8`. An
`EATAControllerThread.m` (the reloc's `EATAThread.m` / `EATAController(IOThread)`
category) is required later.

## Channel model

Several `EATASCSIBus` objects, one per channel, not a single bus.

- Ivar `channelInfo[3]` at `+0x128`. `initFromDeviceDescription:` loops
  `ecx` from 0 to 2 (`cmp ecx, 2` / `jbe`), stride 8, and sets `present`
  (`byte ptr [edx+4]`) for `ecx < channelCount`. `channelCount` is `1` unless
  `config_data_len > 0x21`, in which case it is `(byte at self+0x161 >> 5) + 1`
  — the `maxChannel` nibble of `eata_config`.
- `-[EATASCSIBus initSCSIBus:channel:]` takes an explicit channel argument,
  stores it in `_scsiChannel`, and logs
  `"EATA SCSIBus: [super initFromDeviceDescription] Failed for channel %d"`.
- `acquireSCSIBus:owner:` / `releaseSCSIBus:owner:` exist on `EATAController`.
- `executeRequest:buffer:client:` stamps the command buf's channel field from
  `_scsiChannel` before `executeCmdBuf:`.

## Standalone C symbols

Four `__text` symbols are not Objective-C methods. Recommend
`EATAControllerRoutines.c` later (do not write it in this pass). Call sites
from IDA:

| Symbol | Addr | Size | Callers |
| --- | --- | --- | --- |
| `_eata_busy` | 0 | 36 | `readConfig` @ 3091; `readDMAConfig` @ 3466 and 3662 |
| `_parseConfigSpace` | 3740 | 442 | `+[EATAController probe:]` @ 499 (PCI `Card Type` path) |
| `_eata_busy_0` | 4184 | 36 | `threadExecuteRequest:` @ 4442 (IDA suffix on the second `_eata_busy` copy) |
| `_eataTimeout` | 7408 | 68 | address taken by `threadExecuteRequest:` @ 4327 (`IOScheduleFunc`) and `commandCompleted:reason:` @ 5167 (`IOUnscheduleFunc`) |

`_parseConfigSpace` talks to `IODirectDevice` (`getPCIConfigSpace:withDeviceDescription:`,
`setInterruptList:num:`, `setPortRangeList:num:`). Both busy helpers are 36-byte
port-wait copies; keep them as two functions because IDA's partition of record
does.

## Findings: stub methods on the wrong class / Linux bodies

Every mapped-looking selector on `DPTSCSIDriver` is a name collision at best.
`binrecon source-map` reported 0 mapped because the class name does not match.

### Finding 1 — `@interface DPTSCSIDriver : IOSCSIController` instead of two reloc classes

**Source:** `DPTSCSIDriver.h`.

**Reference:** `EATAController : IODirectDevice` and `EATASCSIBus : IOSCSIController`.

**Disposition:** rewrite (later tasks). The Linux stub cannot be adapted in place.

### Finding 2 — `executeRequest:buffer:client:` and `resetSCSIBus` live on the controller class

**Source:** `DPTSCSIDriver.m`.

**Reference:** both selectors are on `EATASCSIBus`. The bus method builds a
command buf and sends `executeCmdBuf:` to `_direct`. For CDB opcode `0x1B` with
flag bit 1 at `scsiReq+6`, it first sends `flushCacheForTarget:lun:`.

**Disposition:** rewrite; move onto `EATASCSIBus`.

### Finding 3 — Linux helper names with no reloc symbol

**Source:** `DPTSCSIDriverPrivate.h`, `DPTSCSIDriverRoutines.m`,
`DPTSCSIDriverThread.m`.

`eataInitController`, `eataResetBus`, `eataAllocateResources`,
`eataFreeResources`, `allocCp`, `freeCp:`, `runPendingCommands`,
`processCmdComplete` have no `__text` symbol in the reloc. The Apple names
are `probeAtPortBase:`, `readConfig`, `readDMAConfig`, `allocCcb:`, `freeCcb:`,
`ccbFromCmd:`, `commandCompleted:reason:`, `threadResetBus:initConfig:`.

**Disposition:** delete the Linux names; do not keep them as wrappers.

### Finding 4 — `interruptOccurred` is the Linux eata.c IRQ path

**Source:** `DPTSCSIDriver.m`, comment `Based on Linux eata.c interrupt handling`.
Reads `REG_AUX_STATUS` / `REG_STATUS`, reconstructs a CP address from
`REG_LOW`..`REG_MSB`, indexes `cpArray`, calls `processCmdComplete:`.

**Reference:** walk `outstandingQ`, test SP EOC at `ccb+0x34`, call
`commandCompleted:reason:` with reason 0, optionally `enableAllInterrupts`.
One status `in` from `ioBase+7`. No AUX register, no CP-address ports, no
`cpArray`.

**Disposition:** rewrite from the IDA body.

### Finding 5 — `commandRequestOccurred` / `executeCmdBuf:` skip the IOThread message

**Source:** `commandRequestOccurred` only calls `runPendingCommands`.
`executeCmdBuf:` locks, enqueues, then calls `commandRequestOccurred` on the
same thread.

**Reference:** `executeCmdBuf:` enqueues and `_msg_send_from_kernel`s to
`interruptPortKern`. `commandRequestOccurred` is the IOThread loop
(`lock` / dequeue / `threadExecuteRequest:` or `threadResetBus:initConfig:` /
`IOExitThread`).

**Disposition:** rewrite.

### Finding 6 — `threadExecuteRequest:` builds a Linux `struct eata_cp`

**Source:** `DPTSCSIDriverThread.m` calls `allocCp`, fills `cp_scsi_addr` /
`cp_cdb` / `cp_flags1`, `outl`s a CP address, `outb`s `EATA_CMD_SEND_CP`.

**Reference:** `allocCcb:`, `ccbFromCmd:`, `_eata_busy_0`, `IOScheduleFunc(_eataTimeout)`,
`IOPhysicalFromVirtual`. CCB size 0x37C, not `sizeof(struct eata_cp)` from
`DPTSCSIDriverTypes.h`.

**Disposition:** rewrite in `EATAController(IOThread)`.

### Finding 7 — `probe:` / `initFromDeviceDescription:` ignore Card Type and channels

**Source:** `probe:` reads four PIO signature bytes from `EATA_DATA`. `init`
calls `eataInitController` and does not create bus objects.

**Reference:** `+[EATAController probe:]` reads `"Card Type"` from the config
table and branches `EISA` / `ISA` / `PCI`. PCI calls `_parseConfigSpace`.
Success path is `probeAtPortBase:` then `initFromDeviceDescription:`. Init
calls `[super startIOThread]`, fills `channelInfo[3]` from `maxChannel`, and
`registerDevice`.

**Disposition:** rewrite.

### Finding 8 — types header is Linux eata.c, not the reloc `eata_config`

**Source:** `DPTSCSIDriverTypes.h` (`Based on Linux eata.c driver definitions`,
`struct dpt_config`, `struct eata_cp`, `struct eata_sp` with `SP_EOC 0x01`).

**Reference:** the ObjC `eata_config` encoding above; SP EOC is the sign bit of
`ccb+0x34`, not `0x01` in a separate `sp_eoc` field.

**Disposition:** replace the header from the reloc encoding. Do not copy Linux
layouts forward.

## Table / help findings

Compared host files to
`C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config`.
`"Driver Version"` ignored. `IntrInspector.nib` is present in the reference
and must not be copied.

| # | File | Result |
| --- | --- | --- |
| 1 | `Default.table` | `"Family"` is `"SDSI"` here, `"SCSI"` in the reference. |
| 2 | `Default.table` | Reference has `"Location" = ""`; we do not. |
| 3 | `Default.table` | Reference has `"IRQ Levels" = "15"`; we do not. |
| 4 | `Default.table` | Shared keys `Valid IRQ Levels` / `I/O Ports` / `Memory Maps` are present in both but in different order (ours after `"Card Type"`; reference before `"Bus Type"`). |
| 5 | `DPT_EISA.table` | Identical ignoring `"Driver Version"`. |
| 6 | `DPT_PCI.table` | Ours has extra `"IRQ Levels" = "15"` and `"Memory Maps" = ""`; reference has neither as default lines. |
| 7 | `DPT_PCI.table` | `"Share IRQ Levels"` is `"NO"` here, `"YES"` in the reference. |
| 8 | `DPT_OnBoard.table` | Identical ignoring `"Driver Version"`. |
| 9 | `DriverInfo` | Present in our `.drvproj` (`DRIVER_NAME="DPTSCSIDriver"`). Absent from the reference bundle. |
| 10 | `Load_Commands.sect` | Matches the reloc `Loaded Server,Load Commands` section (`WIRE`, no Mig handler). Reloc `Server Name` is `DPTSCSIDriver`; `Instance Var` is `DPTSCSIDriver_instance`. |
| 11 | `English.lproj/Localizable.strings` | Ours is `"Driver Name" = "DPT2000"`. Reference is `"DPTSCSIDriver" = "DPT 2021"` plus `"Long Name" = "DPT 2021 ISA SCSI Adapter"`. |
| 12 | `English.lproj/DPT_EISA.strings` | Missing here. Reference: `"DPTSCSIDriver" = "DPT EISA Series"` / `"Long Name" = "DPT 2xx2/3222 Series EISA SCSI Adapter"`. |
| 13 | `English.lproj/DPT_PCI.strings` | Missing here. Reference: `"DPTSCSIDriver" = "DPT PCI"` / `"Long Name" = "DPT 2xx4/3224 PCI SCSI Adapter"`. |
| 14 | `English.lproj/DPT_OnBoard.strings` | Missing here. Reference: `"DPTSCSIDriver" = "DPT On-Board"` / `"Long Name" = "DPT On-Board SCSI Adapter"`. |
| 15 | `English.lproj/Help/DPT_ISA.rtfd` | Missing (reference has `TXT.rtf` plus tiffs). |
| 16 | `English.lproj/Help/DPT_EISA.rtfd` | Missing. |
| 17 | `English.lproj/Help/DPT_PCI.rtfd` | Missing. |
| 18 | `English.lproj/Help/DPT_On_Board.rtfd` | Missing. |
| 19 | `English.lproj/Help/TableOfContents.rtf` | Missing. Links the four Help RTFDs (EISA, On Board, PCI, ISA). |
| 20 | Installed config name | `DRIVERNAME` stays `DPT2000`, so the installed bundle is `DPT2000.config` versus reference `DPTSCSIDriver.config`. Recorded, not a rename. |
| 21 | `English.lproj/IntrInspector.nib` | In the reference only. Do not copy. |

## Analyzer disagreement

IDA reports 56 `__text` functions. Ghidra reports 55 functions at the same
addresses and sizes as IDA for every shared entry. The one IDA-only function is
the 12-byte glue `+[DPTSCSIDriverKernelServerInstance kernelServerInstance]` at
8808. No size mismatches on the 55 shared addresses. Ghidra did not recover
ObjC names (it emits `binrecon_symbol_*`); that is a naming gap, not a second
partition. angr was not used as evidence.

## Unmapped reason classes

| Class | Count | Why unmapped |
| --- | --- | --- |
| Kernel Server glue | 2 | `+[DPTSCSIDriverKernelServerInstance kernelServerInstance]` @ 8808, `+[DPTSCSIDriverVersion driverKitVersionForDPTSCSIDriver]` @ 8820. Emitted by project type `Kernel Server` / `Load_Commands.sect`. Ledger `intentional-mismatch`, reviewer Pat Raynor. |
| Missing `EATASCSIBus` | 19 | No `EATASCSIBus` type in our tree. Includes `executeRequest:buffer:client:`, `resetSCSIBus`, `initSCSIBus:channel:`, cache flush, power, stats, `probe:`, `deviceStyle`, `requiredProtocols`. |
| Missing `EATAController` engine | 31 | Controller class is `DPTSCSIDriver`, not `EATAController`. Includes probe/init, IRQ/IOThread, `allocCcb:` / `freeCcb:` / `ccbFromCmd:`, `acquireSCSIBus:owner:`, `readConfig`, `readDMAConfig`. |
| Standalone C | 4 | `_eata_busy`, `_parseConfigSpace`, `_eata_busy_0`, `_eataTimeout`. No `.c` home yet. |

2 + 19 + 31 + 4 = 56.

## Unmapped: build-generated

`+[DPTSCSIDriverKernelServerInstance kernelServerInstance]` and
`+[DPTSCSIDriverVersion driverKitVersionForDPTSCSIDriver]` — emitted by the
Kernel Server project type and `Load_Commands.sect`, not written by hand.
Accepted, same as the equivalent pair in drvAdaptec1542B.

## What was not attempted

This pass did not rewrite source, did not guest-compile a `_reloc`, and did not
trace every instruction of `ccbFromCmd:` beyond the field stores needed for the
CCB map. The rewrite starts after this document is committed.
