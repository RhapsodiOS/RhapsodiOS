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

The first rbuild (stub era) failed: missing `driverkit/i386/IODirectDevice.h` on
the ppc sysroot, undefined `AUX_IRQ` / `STAT_IRQ` / `EATA_CP_ADDR` /
`SR_IOST_CMDTO`, C89 mixed declarations, undeclared `PAGE_SIZE`, duplicate
`DPTSCSIDriver(Private)` category at `kl_ld`, and `movehelp` with no
`DriverHelp`. A minimum compile-fix is
`244260ced257b94d63be5272c180d688c913ff15` (`drivers-i386: build drvDPT2000`).

Task 12 deleted `/build/built/drvdpt2000-*.apk` first, then reran the same
rbuild command against the reconstructed tree. That run compiled
`EATASCSIBus.m` (`cc -arch ppc ... -c ... EATASCSIBus.ppc.o EATASCSIBus.m`)
and `kl_ld` linked `EATASCSIBus.o`. Exit 0. The guest toolchain is
`gcc-darwin.conf` (`cc -arch ppc`). Guest package / reloc (not committed, not
copied to the host, not compared with binrecon):

- apk: `/build/built/drvdpt2000-17.apk` (16475 bytes)
- reloc: `private/Drivers/ppc/DPT2000.config/DPT2000_reloc` (55096 bytes inside
  the apk). `file`: Mach-O preload executable ppc. `lipo -info`: architecture
  ppc. `thindriver.sh` moved the config to `ppc`.

`rebuilt_sha256` in `ledger.json` is still `null`. There is still no artifact
under `out/i386/`. This is a ppc guest reloc, not an i386 hardware test.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 54 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

IDA `__text` contains 56 functions. After remapping `$LKS` with
`binrecon source-map --objc-methods`, 54 names resolve to
`EATAController.m` / `EATAControllerThread.m` / `EATASCSIBus.m` /
`EATAControllerRoutines.c`. Glue (2) stays unmapped and
`intentional-mismatch`. The Linux `DPTSCSIDriver` stub is gone; both reloc
classes exist. `tools/binrecon/tests/test_dpt2000_linux_residue.py` and
`test_dpt2000_profile.py` pass (4 tests).

`_parseConfigSpace` lives in `EATAController.m` (it sends `IODirectDevice`
messages). `EATAControllerRoutines.c` is `_eata_busy`, `_eata_busy_0`,
`_eataTimeout`.

Fresh remap put `_eata_busy_0` @ 4184 in `duplicate_candidates` because the
reloc symbol table names both copies `_eata_busy` and IDA suffixes the
second `_0`. The committed map takes the `eata_busy_0` definition
(`EATAControllerRoutines.c:47`), not `eata_busy`. That is the IDA name, not
a hand-written lie.

`allocCcb:`, `freeCcb:`, and `ccbFromCmd:` are Apple names on
`EATAController(IOThread)`. They are not Linux residue. Do not rename them to
`allocCp`. `"Server Name" = "DPTSCSIDriver"` in the tables is required and is
not residue.

## Ledger

| Status | Count |
| --- | --- |
| unexamined | 53 |
| control-flow-confirmed | 1 |
| intentional-mismatch | 2 |
| assembly-matched | 0 |

Tasks 8–9 implemented the two classes from IDA. That is not an
instruction-by-instruction compare, so mapped bodies stay `unexamined`
except the largest function. Glue stays `intentional-mismatch`, reviewer
Pat Raynor.

`-[EATAController ccbFromCmd:]` @ 6152 (1254 bytes) is
`control-flow-confirmed`. Control flow compared to IDA: CDB group dispatch
(`0x00`/`0x20`/`0x40`/`0xa0`/`0xc0`/`0xe0`), link-bit reject
(`SR_IOST_CMDREJ`), `allocCcb:` from `maxTransfer != 0`, page count vs
`configSgSize` (`self+0x198`), `bzero` of SP @ `ccb+0x34` (0x18) and CP @
`ccb+0x8` (0x2c), CDB copy, flags / immediate `0x1A`, sense @ `ccb+0x360`
and SP physical addresses, target/lun/identify/channel, `numReserved` /
disconnect, single-page vs SG walk, `createDMABufferFor:` failure →
`abortDMA:` / `freeCcb:` / `SR_IOST_INT`. Not traced operand-by-operand:
SG-loop addressing arithmetic (`page_mask` rounding), every `eata_bswap32`
on SG entries, and each `IOPhysicalFromVirtual` failure-path immediate.

## Remaining warnings / open items

- `EATAController.m`: incomplete `EATAController(PrivateMethods)` —
  `-executeCmdBuf:` is implemented on the class (in `EATAController.m`) but
  still declared on `(PrivateMethods)`. Left as-is.
- `EATASCSIBus.m:70`: `numberOfTargets` is `int` on `IOSCSIController` /
  `EATASCSIBus` and `unsigned` on `EATAExported` / `EATAController`. Left
  as-is.
- Guest toolchain is ppc only (`gcc-darwin.conf`). Do not read this reloc as
  i386 hardware proof.
- Help lives under `English.lproj/Help/`. `driver.make` `movehelp` wants
  `English.lproj/DriverHelp`. `Makefile.postamble` stubs `movehelp` with
  `@true`; leave that stub.
- `DRIVERNAME` stays `DPT2000` (installed `DPT2000.config` vs reference
  `DPTSCSIDriver.config`). Recorded, not a rename.
- `English.lproj/IntrInspector.nib` is in the reference only. Do not copy.

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
(`ds:paStartiothread`) and sets `ioThreadRunning` at `self+0x1A8`.
`EATAControllerThread.m` is the reloc's `EATAThread.m` /
`EATAController(IOThread)` category.

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

Four `__text` symbols are not Objective-C methods. Call sites from IDA:

| Symbol | Addr | Size | Callers |
| --- | --- | --- | --- |
| `_eata_busy` | 0 | 36 | `readConfig` @ 3091; `readDMAConfig` @ 3466 and 3662 |
| `_parseConfigSpace` | 3740 | 442 | `+[EATAController probe:]` @ 499 (PCI `Card Type` path) |
| `_eata_busy_0` | 4184 | 36 | `threadExecuteRequest:` @ 4442 (IDA suffix on the second `_eata_busy` copy) |
| `_eataTimeout` | 7408 | 68 | address taken by `threadExecuteRequest:` @ 4327 (`IOScheduleFunc`) and `commandCompleted:reason:` @ 5167 (`IOUnscheduleFunc`) |

`_parseConfigSpace` talks to `IODirectDevice` (`getPCIConfigSpace:withDeviceDescription:`,
`setInterruptList:num:`, `setPortRangeList:num:`). It is defined in
`EATAController.m`. Both busy helpers are 36-byte port-wait copies in
`EATAControllerRoutines.c`; keep them as two functions because IDA's
partition of record does.

## Findings: stub methods on the wrong class / Linux bodies

Resolved. The Linux `DPTSCSIDriver` class and helper names are gone. The
tree is `EATAController` + `EATASCSIBus` as in the reloc. Residue test
`test_dpt2000_linux_residue.py` is green.

### Finding 1 — two reloc classes — resolved

`EATAController : IODirectDevice` and `EATASCSIBus : IOSCSIController`.

### Finding 2 — `executeRequest:buffer:client:` / `resetSCSIBus` — resolved

Both selectors are on `EATASCSIBus`. The bus method builds a command buf and
sends `executeCmdBuf:` to `_direct`. For CDB opcode `0x1B` with flag bit 1
at `scsiReq+6`, it first sends `flushCacheForTarget:lun:`.

### Findings 3–8 — Linux names, IRQ path, IOThread, CCB, probe, types — resolved

Implemented from IDA in Tasks 8–9. Not stamped `assembly-matched`.

## Table / help findings

Compared host files to
`C:\Users\raynorpat\Downloads\test\Drivers\i386\DPTSCSIDriver.config`.
Tables and `English.lproj` strings/Help were aligned in
`4349515f` (`drivers-i386: align drvDPT2000 tables and help with
DPTSCSIDriver.config`). `"Driver Version"` ignored.
`IntrInspector.nib` is present in the reference and must not be copied.

Still recorded, not a rename or a `movehelp` rewrite:

| # | File | Result |
| --- | --- | --- |
| 9 | `DriverInfo` | Present in our `.drvproj` (`DRIVER_NAME="DPTSCSIDriver"`). Absent from the reference bundle. |
| 10 | `Load_Commands.sect` | Matches the reloc `Loaded Server,Load Commands` section (`WIRE`, no Mig handler). Reloc `Server Name` is `DPTSCSIDriver`; `Instance Var` is `DPTSCSIDriver_instance`. |
| 20 | Installed config name | `DRIVERNAME` stays `DPT2000`, so the installed bundle is `DPT2000.config` versus reference `DPTSCSIDriver.config`. |
| 21 | `English.lproj/IntrInspector.nib` | In the reference only. Do not copy. |
| 22 | Help directory | Sources use `English.lproj/Help/`. `driver.make` `movehelp` expects `DriverHelp`. `Makefile.postamble` stubs `movehelp`; leave the stub. |

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

54 mapped + 2 unmapped = 56.

## Unmapped: build-generated

`+[DPTSCSIDriverKernelServerInstance kernelServerInstance]` and
`+[DPTSCSIDriverVersion driverKitVersionForDPTSCSIDriver]` — emitted by the
Kernel Server project type and `Load_Commands.sect`, not written by hand.
Accepted, same as the equivalent pair in drvAdaptec1542B.

## What was not attempted

No instruction-by-instruction `assembly-matched` pass. No binrecon compare
against the guest ppc reloc. No host `out/i386` extract. No QEMU or hardware
run. The `movehelp` stub is left in place.
