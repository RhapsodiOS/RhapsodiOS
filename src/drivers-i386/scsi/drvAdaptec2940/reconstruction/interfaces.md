# Recovered interfaces and reference layouts

Reference: `Adaptec2940SCSI_reloc`, i386 little-endian, SHA-256 `08E6C11EEC125847F485C86250C94C4AFCC025E59CF085B0C8039B94B2E79DF7`. Function boundaries, signatures, sizes, caller links and code addresses below are exported from IDA 9.4. The C signatures are IDA/Hex-Rays signature strings; caller links are additional call-edge evidence, not proof of source typedef spelling. `Ph_ReadConfig` and `Ph_WriteConfig` are IDA `__usercall` routines whose caller/callee pair is rebuilt together; their recovered source interface is ordinary cdecl: selector, bus, device, register, then write value.

`Adaptec2940Config.c` now implements the PCI configuration mechanism probe and mechanism-1/mechanism-2 read/write paths. The probe scans devices 0–31 on bus zero and the requested bus, uses the top byte of config dword 2 as the presence test, and restores CF8 after every mechanism-1 transaction. `PH_FindHA` recognizes the two supported Adaptec IDs, rejects the excluded revision/feature case, reports the legacy flag when I/O decode is disabled, and enables bus mastering. `PH_GetNumOfBuses` honors the OSM override, then scans PCI bridge class codes and tracks the highest secondary bus. `Ph_AutoTermCable` applies the IDA narrow/wide cable truth table to termination bits and commits changed values through EEPROM register 17. `PH_GetConfig` captures the adapter's I/O registers and PCI fields, initializes narrow/wide defaults, normalizes valid EEPROM settings, and restores HCNTRL when the device was not already paused. `PH_InitHA` sequences the sequencer load, reset callbacks, wide-bus register setup, target termination masks and final HCNTRL resume, returning immediately on sequencer-load errors. The native i386 harness covers these paths with OSM sentinels, explicit mechanism selection and both EEPROM-result branches.

`Adaptec2940Recovery.c` implements the adapter SCSI reset transaction. It snapshots the current transfer and scratch registers, issues the bus reset strobes, waits for HCNTRL pause, applies the 4,000-unit reset delay, restores saved values and returns the saved scratch byte.

## Core HIM helper batch

`SCSIBus.m` now contains the 13 recovered indirect-controller methods. It
publishes the `IOSCSIControllerExported` protocol, probes the controller's
single channel, forwards statistics and transfer queries, builds the exact
36-byte request/reset message expected by `executeCmdBuf:`, and reserves the
eight LUNs for the adapter's SCSI ID during initialization.

`Adaptec2940Optima.c` reconstructs the Optima allocation-size formulas,
busy/Qin maps, free-SCB rings, queue operations, and function table. Sizes cap
at 254 entries; the host configuration stores the resulting size at offset 60
and sets option bit 0 at offset 13. Offsets 272, 276, 492, 496, and 504 in
the Optima block hold pointers to separate SCB, free-queue, command, Qin, and
busy-map arrays, respectively. The free-list head/tail counters are at offsets
488 and 271; queue input/output indices are at 489 and the I/O registers.
`Ph_SetOptimaHaData` builds the SCB and free-queue pointers before
`Ph_SetOptimaScratch` initializes the four hardware scratch rings and their
register pointers. `Ph_ScbPageJustifyQIN` applies the controller's 256-byte Qin
alignment rule; `Ph_MovPtrToScratch` writes each scratch pointer as four
ordered byte writes. `Ph_OptimaRequestSense` repurposes the SCB with a six-byte
REQUEST SENSE CDB, clears its transfer descriptors, places it at the Qin head,
and clears that target's busy marker. `Ph_OptimaEnableNextScbArray` sets the
array-enable bit only when the per-target SCB register contains an index below
`0x7f`. `Ph_OptimaCmdComplete` drains the Qout map, returns internal SCBs to
the free ring, and terminates completed commands. `Ph_OptimaAbortActive`
removes an abort target from Qout or Qin when queued, marks an active SCB when
it cannot be removed, and dispatches the controller callback where IDA does.
`PH_RelocatePointers` subtracts the loaded image delta from the host's Optima
and scratch pointers before rebuilding the host data. Completion helpers
remove the SCB from the chain, copy the final status byte, update target busy
counts for non-active commands, and route completion through
`PH_ScbCompleted` to the controller object's `scbComplete:` method. The HIM
leaf batch also recovers OSM sentinel returns, asynchronous event callback
gating, the two EEPROM control bits, and the three-pulse `Ph_Wait2usec` port
sequence. EEPROM start/address framing, 8/10/16-bit shifts, erase/write
enable commands, register reads and writes, configuration decoding, checksum
validation, and selective checksum-protected updates now follow the recovered
IDA paths.

The controller's statistics methods now match the recovered bodies:
`resetStats` clears the queue-length total, maximum queue length, and sample
count, while `numQueueSamples`, `sumQueueLengths`, and `maxQueueLength` return
those corresponding fields.
`maxTransfer` returns sixteen pages; `AIC_SG_COUNT` is fixed to the IDA
constant 16 so request segmentation and the reported transfer limit agree.
The channel methods use the recovered 8-byte record: bus acquisition succeeds
only for channel zero with an allocated 140-byte record and no current owner;
release clears only the matching owner. The channel record's bytes 30 and 31
provide the SCSI bus ID and target count.
The controller class probe allocates and initializes the device directly, as
the binary does. `interruptOccurredAt:` and `otherOccurred:` log their event
and argument; `receiveMsg` logs then delegates to `IODirectDevice`.

`initFromDeviceDescription:` follows the recovered initialization order: read
PCI configuration, require exactly one I/O BAR among all six BARs, reserve its
256-byte port range and the IRQ before superclass initialization, validate the
HIM adapter, and start the I/O thread. It applies the instance-table settings,
initializes queue sentinels and the single-channel record, sets the interrupt
port and device identity, allocates the 140-byte host record, initializes and
enables the adapter, waits for the bus-reset interval, then registers the
device. Failure paths release the partially initialized object, with direct
superclass cleanup where IDA calls it.

The initial production batch in `Adaptec2940HIM.c` implements the IDA
entry points `_Ph_MemorySet` (0x4224), `_Ph_ChainAppendEnd` (0x4b2c),
`_Ph_ChainInsertFront` (0x4b7c), `_Ph_ChainRemove` (0x4b84), and
`_Ph_ChainPrevious` (0x4bcc). The chain object is addressed through the
host block's pointer at byte offset 52. Its first two 32-bit words hold the
head and tail SCB addresses, and `0xffffffff` is the end marker. An empty
append clears host flag bit 7 at offset 13, copies host bytes 62 and 64 to
chain bytes 268 and 269, and installs the SCB as both head and tail. Removing
the last node sets the empty bit and restores both pointers to the sentinel.
`Ph_ChainInsertFront` is an intentional empty body: IDA shows only its
prologue and epilogue.

The native i386 helper harness checks empty, multi-node append, middle and
tail removal, absent-node lookup, the empty-body helper, and the byte-fill
loop's return value and writes. These results confirm control flow for this
batch only; machine-code equivalence remains pending a guest compiler build.

The same batch now includes `_Ph_Pause` (0x4258), `_Ph_UnPause` (0x4288),
`_Ph_WriteHcntrl` (0x42a8), and `_Ph_ReadIntstat` (0x430c). HCNTRL is at
`io_base + 0x87` and INTSTAT at `io_base + 0x91`. Writes use DriverKit's
`outb`, whose inline assembly supplies the reference lock-increment barrier.
The test port shim checks already-paused and unpaused branches, status mask
`0x0d`, HCNTRL restoration, output order, and barrier counts.

Status and short-transfer helpers are also recovered: `_Ph_CheckLength`
(0x2ba0), `_Ph_GetScbStatus` (0x52bc), and `_Ph_SetMgrStat` (0x52f4).
`Ph_CheckLength` reads four residual bytes from `io_base + 0xb0..0xb3` for
phase `0xc0`, except when the SCB's bit `0x40` or target status 2 suppresses
the read. Other phases follow the SCSISIG/SXFRCTL1/SSTAT1 handshake and clear
the residual. `Ph_GetScbStatus` receives the chain object (the pointer stored
at host offset 52), using its per-target counts at offsets 8.. and limits at
268/269. The harness checks these paths and manager status choices.

The verified low-level set also includes interrupt enable/disable
(`_PH_EnableInt`, 0x26e0; `_PH_DisableInt`, 0x2710), byte port transfers
(`_Ph_OutBuffer`, 0x5478; `_Ph_InBuffer`, 0x54c4), and the negotiation marker
`_Ph_SetNeedNego` (0x333c). The reference bodies `_Ph_Abort` (0x2984),
`_Ph_SendTrmMsg` (0x31b8), `_Ph_TrmCmplt` (0x31c4), `_Ph_BusReset` (0x31d0),
`_Ph_HaSoftReset` (0x5124), and `_Ph_SoftReset` (0x52b4) are literal no-op or
zero-return stubs. The native and guest harnesses cover transfer byte order,
interrupt control writes, the marker port, and stub results.

The chain helper also supports the embedded bookmark routines
`_Ph_SetScbMark` (0x5100), `_Ph_InsertBookmark` (0x563c), and
`_Ph_RemoveBookmark` (0x5660). Tests check the physical mark values at chain
offsets 356 and 372, the embedded node at 352, and head/tail restoration.
`_Ph_ScbPrepare` (0x4c10) walks the SCB chain, clears each host status,
increments its target count, stores status 16/32, and increments the free-SCB
word at chain offset 266 for each status-16 entry. A two-node case verifies
the final busy transition and count.
`_Ph_SyncSet` (0x35bc) maps the SCB period byte at offset 67 to sequencer
period values 0, 16, 32, 48, 64, 80, 96, or 112. Boundary tests cover every
branch endpoint from 0 through 255.
Negotiation recovery also includes `_Ph_ScbRenego` (0x4450), which mirrors
the device's sync/wide marker into host negotiation bits and emits the
`0x8f` marker when needed. `_Ph_ClearFast20Reg` (0x44cc) clears the target's
bit in the low/high Fast20 map and clears SXFRCTL0 bit `0x20`; `_Ph_LogFast20Map`
(0x4550) updates both from the negotiated period. Port traces test targets
below and above 8 and the period threshold at `0x18`.
`_Ph_Delay` (0x4378) snapshots timer bytes at `io_base + 0xb0/b1`, programs
the delay counter for each iteration, unpauses until the sequencer pauses
again, then restores both timer bytes. A simulated pause transition checks
the full one-iteration register order and barrier count.
`_PH_PollInt` (0x4ab4) forces the sequencer into the paused state, waits for
HCNTRL bit `0x04`, reads INTSTAT's low nibble through `Ph_ReadIntstat`, then
restores the original HCNTRL through `Ph_WriteHcntrl`. The native port shim
checks status masking and restoration.

## Function inventory

| Group | Count |
|---|---:|
| Controller Objective-C methods | 30 |
| SCSIBus Objective-C methods | 13 |
| Handwritten C | 125 |
| Build-generated Objective-C methods | 2 |

### Controller (30)

| Address | Size | Name | IDA signature | Owner | Callers |
|---:|---:|---|---|---|---|
| `0x0` | 57 | `+[Adaptec2940 probe:]` | `char __cdecl(id, SEL, id)` | `Adaptec2940.m` | none recorded |
| `0x3c` | 1991 | `-[Adaptec2940 initFromDeviceDescription:]` | `id __cdecl(Adaptec2940 *self, SEL, id)` | `Adaptec2940.m` | `0x3c` |
| `0x804` | 435 | `-[Adaptec2940 free]` | `id __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | `0x3c`, `0x804` |
| `0x9b8` | 40 | `-[Adaptec2940 resetStats]` | `void __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | `0x3c` |
| `0x9e0` | 16 | `-[Adaptec2940 numQueueSamples]` | `unsigned int __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0x9f0` | 16 | `-[Adaptec2940 sumQueueLengths]` | `unsigned int __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0xa00` | 16 | `-[Adaptec2940 maxQueueLength]` | `unsigned int __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0xa10` | 31 | `-[Adaptec2940 numberOfTargets:]` | `int __cdecl(Adaptec2940 *self, SEL, int)` | `Adaptec2940.m` | `0x3c` |
| `0xa30` | 148 | `-[Adaptec2940 interruptOccurred]` | `void __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0xac4` | 41 | `-[Adaptec2940 interruptOccurredAt:]` | `void __cdecl(Adaptec2940 *self, SEL, int)` | `Adaptec2940.m` | none recorded |
| `0xaf0` | 41 | `-[Adaptec2940 otherOccurred:]` | `void __cdecl(Adaptec2940 *self, SEL, int)` | `Adaptec2940.m` | none recorded |
| `0xb1c` | 69 | `-[Adaptec2940 receiveMsg]` | `void __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | `0xb1c` |
| `0xb64` | 370 | `-[Adaptec2940 timeoutOccurred]` | `void __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0xcd8` | 290 | `-[Adaptec2940 commandRequestOccurred]` | `void __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0xdfc` | 367 | `-[Adaptec2940 setIntValues:forParameter:count:]` | `int __cdecl(Adaptec2940 *self, SEL, unsigned int *, char *, unsigned int)` | `Adaptec2940.m` | `0xdfc` |
| `0xf6c` | 206 | `-[Adaptec2940 getIntValues:forParameter:count:]` | `int __cdecl(Adaptec2940 *self, SEL, unsigned int *, char *, unsigned int *)` | `Adaptec2940.m` | `0xf6c` |
| `0x103c` | 54 | `-[Adaptec2940 acquireSCSIBus:owner:]` | `char __cdecl(Adaptec2940 *self, SEL, unsigned int, id)` | `Adaptec2940.m` | none recorded |
| `0x1074` | 75 | `-[Adaptec2940 releaseSCSIBus:owner:]` | `void __cdecl(Adaptec2940 *self, SEL, unsigned int, id)` | `Adaptec2940.m` | none recorded |
| `0x10c0` | 15 | `-[Adaptec2940 maxTransfer]` | `unsigned int __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | none recorded |
| `0x10d0` | 31 | `-[Adaptec2940 scsiBusId:]` | `unsigned int __cdecl(Adaptec2940 *self, SEL, unsigned int)` | `Adaptec2940.m` | none recorded |
| `0x10f0` | 303 | `-[Adaptec2940 executeCmdBuf:]` | `int __cdecl(Adaptec2940 *self, SEL, $E7BB6EE711814A6885BC94630F193936 *)` | `Adaptec2940.m` | `0x804` |
| `0x1244` | 116 | `-[Adaptec2940 checkScbAlign:]` | `char __cdecl(Adaptec2940 *self, SEL, $7AA098F75E74859150CF1D52C47E8BF8 *, $D05E80C3BC593CB6499B19108CB7B188, [8L]{?)` | `Adaptec2940.m` | none recorded |
| `0x12b8` | 211 | `-[Adaptec2940 allocScb]` | `$7AA098F75E74859150CF1D52C47E8BF8 *__cdecl(Adaptec2940 *self, [8L]{?)` | `Adaptec2940.m` | none recorded |
| `0x138c` | 113 | `-[Adaptec2940 freeScb:]` | `void __cdecl(Adaptec2940 *self, SEL, $7AA098F75E74859150CF1D52C47E8BF8 *, $D05E80C3BC593CB6499B19108CB7B188, [8L]{?)` | `Adaptec2940.m` | none recorded |
| `0x1400` | 177 | `-[Adaptec2940 createScbs:size:]` | `void __cdecl(Adaptec2940 *self, SEL, unsigned int, unsigned int)` | `Adaptec2940.m` | `0x2078` |
| `0x14b4` | 1400 | `-[Adaptec2940 threadExecuteRequest:]` | `void __cdecl(Adaptec2940 *self, SEL, $E7BB6EE711814A6885BC94630F193936 *)` | `Adaptec2940.m` | `0xcd8` |
| `0x1a2c` | 425 | `-[Adaptec2940 threadResetBus:channel:reason:]` | `void __cdecl(Adaptec2940 *self, SEL, $E7BB6EE711814A6885BC94630F193936 *, unsigned int, const char *)` | `Adaptec2940.m` | `0xa30`, `0xb64`, `0xcd8` |
| `0x1bd8` | 135 | `-[Adaptec2940 commandCompleted:]` | `void __cdecl(Adaptec2940 *self, SEL, $7AA098F75E74859150CF1D52C47E8BF8 *, $D05E80C3BC593CB6499B19108CB7B188, [8L]{?)` | `Adaptec2940.m` | `0xb64`, `0x1a2c` |
| `0x1c60` | 1048 | `-[Adaptec2940 scbComplete:]` | `void __cdecl(Adaptec2940 *self, SEL, $7AA098F75E74859150CF1D52C47E8BF8 *, $D05E80C3BC593CB6499B19108CB7B188, [8L]{?)` | `Adaptec2940.m` | none recorded |
| `0x2078` | 676 | `-[Adaptec2940 initHostAdaptor]` | `unsigned int __cdecl(Adaptec2940 *self, SEL)` | `Adaptec2940.m` | `0x3c`, `0x1a2c` |

### Bus (13)

| Address | Size | Name | IDA signature | Owner | Callers |
|---:|---:|---|---|---|---|
| `0x2398` | 139 | `+[SCSIBus probe:]` | `char __cdecl(id, SEL, id)` | `SCSIBus.m` | none recorded |
| `0x2424` | 12 | `+[SCSIBus deviceStyle]` | `int __cdecl(id, SEL)` | `SCSIBus.m` | none recorded |
| `0x2430` | 12 | `+[SCSIBus requiredProtocols]` | `id *__cdecl(id, SEL)` | `SCSIBus.m` | none recorded |
| `0x243c` | 29 | `-[SCSIBus maxTransfer]` | `unsigned int __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x245c` | 41 | `-[SCSIBus free]` | `id __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | `0x245c` |
| `0x2488` | 38 | `-[SCSIBus resetStats]` | `void __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x24b0` | 29 | `-[SCSIBus numQueueSamples]` | `unsigned int __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x24d0` | 29 | `-[SCSIBus sumQueueLengths]` | `unsigned int __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x24f0` | 29 | `-[SCSIBus maxQueueLength]` | `unsigned int __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x2510` | 36 | `-[SCSIBus numberOfTargets]` | `int __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x2534` | 73 | `-[SCSIBus executeRequest:buffer:client:]` | `int __cdecl -[SCSIBus executeRequest:buffer:client:](` | `SCSIBus.m` | none recorded |
| `0x2580` | 55 | `-[SCSIBus resetSCSIBus]` | `int __cdecl(SCSIBus *self, SEL)` | `SCSIBus.m` | none recorded |
| `0x25b8` | 296 | `-[SCSIBus initSCSIBus:channel:]` | `id __cdecl(SCSIBus *self, SEL, id, unsigned int)` | `SCSIBus.m` | none recorded |

### C (125)

| Address | Size | Name | IDA signature | Owner | Callers |
|---:|---:|---|---|---|---|
| `0x1220` | 12 | `_PH_ReadConfigOSM` | `int PH_ReadConfigOSM(int, bus, device, register)` | `Adaptec2940Config.c` | `0x6cf4` |
| `0x122c` | 12 | `_PH_WriteConfigOSM` | `int PH_WriteConfigOSM(int, bus, device, register, value)` | `Adaptec2940Config.c` | `0x6e44` |
| `0x1238` | 12 | `_PH_GetNumOfBusesOSM` | `int PH_GetNumOfBusesOSM()` | `Adaptec2940Thread.m` | `0x673c` |
| `0x231c` | 33 | `_PH_ScbCompleted` | `id __cdecl PH_ScbCompleted(int a1)` | `Adaptec2940Thread.m` | `0x4df0`, `0x4e60`, `0x512c` |
| `0x2340` | 86 | `_a2940Timeout` | `int __cdecl a2940Timeout(int a1)` | `Adaptec2940Timeout.c` | none recorded |
| `0x26e0` | 46 | `_PH_EnableInt` | `int __cdecl PH_EnableInt(int a1)` | `Adaptec2940HIM.c` | `0xa30`, `0x2078` |
| `0x2710` | 44 | `_PH_DisableInt` | `int __cdecl PH_DisableInt(int a1)` | `Adaptec2940HIM.c` | none recorded |
| `0x273c` | 64 | `_Ph_NonInit` | `int __cdecl Ph_NonInit(int a1)` | `Adaptec2940HIM.c` | `0x4618` |
| `0x277c` | 520 | `_PH_Special` | `int __cdecl PH_Special(char a1, int a2, int a3)` | `Adaptec2940HIM.c` | `0x1a2c`, `0x4618` |
| `0x2984` | 7 | `_Ph_Abort` | `void Ph_Abort()` | `Adaptec2940HIM.c` | none recorded |
| `0x298c` | 199 | `_Ph_IntSrst` | `char __cdecl Ph_IntSrst(int a1)` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x2a54` | 221 | `_Ph_ResetChannel` | `char __cdecl Ph_ResetChannel(int a1)` | `Adaptec2940HIM.c` | `0x298c`, `0x2ee4`, `0x4f9c`, `0x6b1c` |
| `0x2b34` | 105 | `_Ph_CheckSyncNego` | `char __cdecl Ph_CheckSyncNego(int a1)` | `Adaptec2940HIM.c` | `0x298c`, `0x2ee4`, `0x4f9c`, `0x6b1c` |
| `0x2ba0` | 190 | `_Ph_CheckLength` | `char __cdecl Ph_CheckLength(int a1, __int16 a2)` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x2c60` | 245 | `_Ph_CdbAbort` | `char __cdecl Ph_CdbAbort(int a1, int a2)` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x2d58` | 394 | `_Ph_ResetSCSI` | `unsigned __int8 __cdecl Ph_ResetSCSI(int a1)` | `Adaptec2940HIM.c` | `0x298c`, `0x2ee4`, `0x4f9c`, `0x6b1c` |
| `0x2ee4` | 110 | `_Ph_BadSeq` | `char __cdecl Ph_BadSeq(int a1, int a2)` | `Adaptec2940HIM.c` | `0x2c60`, `0x3080`, `0x369c`, `0x3d4c`, `0x46d4` |
| `0x2f54` | 299 | `_Ph_CheckCondition` | `char __cdecl Ph_CheckCondition(int a1, __int16 a2)` | `Adaptec2940CheckCondition.c` | `0x46d4` |
| `0x3080` | 310 | `_Ph_TargetAbort` | `int __cdecl Ph_TargetAbort(int a1, int a2, int a3)` | `Adaptec2940HIM.c` | `0x3d4c`, `0x46d4` |
| `0x31b8` | 9 | `_Ph_SendTrmMsg` | `int __cdecl(_DWORD, _DWORD)` | `Adaptec2940HIM.c` | `0x3080`, `0x46d4` |
| `0x31c4` | 9 | `_Ph_TrmCmplt` | `int Ph_TrmCmplt()` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x31d0` | 7 | `_Ph_BusReset` | `void Ph_BusReset()` | `Adaptec2940HIM.c` | none recorded |
| `0x31d8` | 355 | `_Ph_SendMsgo` | `unsigned __int8 __cdecl Ph_SendMsgo(_BYTE *a1, int a2)` | `Adaptec2940HIM.c` | `0x3364`, `0x46d4` |
| `0x333c` | 38 | `_Ph_SetNeedNego` | `char __cdecl Ph_SetNeedNego(unsigned __int8 a1, __int16 a2)` | `Adaptec2940HIM.c` | `0x2b34`, `0x369c`, `0x4450`, `0x5c20` |
| `0x3364` | 597 | `_Ph_Negotiate` | `char __cdecl Ph_Negotiate(int a1, int a2)` | `Adaptec2940HIM.c` | `0x31d8`, `0x46d4` |
| `0x35bc` | 115 | `_Ph_SyncSet` | `int __cdecl Ph_SyncSet(int a1)` | `Adaptec2940HIM.c` | `0x369c`, `0x3b90` |
| `0x3630` | 107 | `_Ph_SyncNego` | `unsigned __int8 __cdecl Ph_SyncNego(int a1, int a2)` | `Adaptec2940HIM.c` | `0x31d8`, `0x3364` |
| `0x369c` | 1266 | `_Ph_ExtMsgi` | `char __cdecl Ph_ExtMsgi(int a1, int a2)` | `Adaptec2940ExtMsgi.c` | `0x46d4` |
| `0x3b90` | 442 | `_Ph_ExtMsgo` | `int __cdecl Ph_ExtMsgo(int a1, int a2)` | `Adaptec2940HIM.c` | `0x31d8`, `0x3364`, `0x3630` |
| `0x3d4c` | 661 | `_Ph_HandleMsgi` | `char __cdecl Ph_HandleMsgi(int a1, int a2)` | `Adaptec2940HandleMsgi.c` | `0x46d4` |
| `0x3fe4` | 147 | `_Ph_IntSelto` | `char __cdecl Ph_IntSelto(int a1, int a2)` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x4078` | 226 | `_Ph_IntFree` | `char __cdecl Ph_IntFree(int a1, int a2)` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x415c` | 48 | `_Ph_ParityError` | `unsigned __int8 __cdecl Ph_ParityError(int a1, int a2)` | `Adaptec2940HIM.c` | `0x46d4` |
| `0x418c` | 150 | `_Ph_Wt4Req` | `int __cdecl Ph_Wt4Req(int a1, __int16 a2)` | `Adaptec2940HIM.c` | `0x2c60`, `0x3080`, `0x3364`, `0x3630`, `0x369c`, `0x3b90`, `0x3d4c`, `0x415c` |
| `0x4224` | 50 | `_Ph_MemorySet` | `char __cdecl Ph_MemorySet(_BYTE *a1, char a2, int a3)` | `Adaptec2940HIM.c` | `0x50a0`, `0x5efc`, `0x5fb4`, `0x6918` |
| `0x4258` | 48 | `_Ph_Pause` | `unsigned __int8 __cdecl Ph_Pause(int a1)` | `Adaptec2940HIM.c` | `0x57b4`, `0x5c20`, `0x6918` |
| `0x4288` | 32 | `_Ph_UnPause` | `int __cdecl Ph_UnPause(int a1)` | `Adaptec2940HIM.c` | `0x2d58`, `0x4378` |
| `0x42a8` | 100 | `_Ph_WriteHcntrl` | `_DWORD(_DWORD, ...)` | `Adaptec2940HIM.c` | `0x26e0`, `0x2710`, `0x277c`, `0x4258`, `0x4288`, `0x4618`, `0x46d4`, `0x4ab4`, `0x4c5c`, `0x4ed8`, `0x4f9c`, `0x512c`, `0x5328`, `0x53d0`, `0x57b4`, `0x5c20`, `0x640c`, `0x6918`, `0x6b1c` |
| `0x430c` | 106 | `_Ph_ReadIntstat` | `int __cdecl Ph_ReadIntstat(__int16 a1)` | `Adaptec2940HIM.c` | `0x2ee4`, `0x3080`, `0x46d4`, `0x4ab4` |
| `0x4378` | 215 | `_Ph_Delay` | `unsigned __int8 __cdecl Ph_Delay(int a1, int a2)` | `Adaptec2940HIM.c` | `0x2d58` |
| `0x4450` | 124 | `_Ph_ScbRenego` | `char __cdecl Ph_ScbRenego(int a1, unsigned __int8 a2)` | `Adaptec2940HIM.c` | `0x277c` |
| `0x44cc` | 132 | `_Ph_ClearFast20Reg` | `unsigned __int8 __cdecl Ph_ClearFast20Reg(int a1, int a2)` | `Adaptec2940HIM.c` | `0x3364`, `0x369c` |
| `0x4550` | 200 | `_Ph_LogFast20Map` | `void __cdecl Ph_LogFast20Map(int a1, _BYTE *a2)` | `Adaptec2940HIM.c` | `0x369c`, `0x3b90` |
| `0x4618` | 185 | `_PH_ScbSend` | `char __cdecl PH_ScbSend(int a1)` | `Adaptec2940HIM.c` | `0x14b4` |
| `0x46d4` | 992 | `_PH_IntHandler` | `int __usercall PH_IntHandler@<eax>(int a1@<edi>, int a2)` | `Adaptec2940Interrupt.c` | `0xa30`, `0xb64` |
| `0x4ab4` | 91 | `_PH_PollInt` | `int __cdecl PH_PollInt(int a1)` | `Adaptec2940HIM.c` | `0xa30`, `0xb64` |
| `0x4b10` | 26 | `_PH_RelocatePointers` | `int __cdecl PH_RelocatePointers(int a1, unsigned __int16 a2)` | `Adaptec2940HIM.c` | none recorded |
| `0x4b2c` | 77 | `_Ph_ChainAppendEnd` | `char __cdecl Ph_ChainAppendEnd(int a1, _DWORD *a2)` | `Adaptec2940HIM.c` | `0x273c`, `0x4618`, `0x512c`, `0x563c` |
| `0x4b7c` | 7 | `_Ph_ChainInsertFront` | `void Ph_ChainInsertFront()` | `Adaptec2940HIM.c` | none recorded |
| `0x4b84` | 70 | `_Ph_ChainRemove` | `int __cdecl Ph_ChainRemove(int a1, _DWORD *a2)` | `Adaptec2940HIM.c` | `0x4df0`, `0x4e60`, `0x5660` |
| `0x4bcc` | 65 | `_Ph_ChainPrevious` | `int __cdecl Ph_ChainPrevious(int *a1, int a2)` | `Adaptec2940HIM.c` | `0x4b84`, `0x54f4` |
| `0x4c10` | 73 | `_Ph_ScbPrepare` | `int __cdecl Ph_ScbPrepare(int a1, int *a2)` | `Adaptec2940HIM.c` | `0x4618`, `0x4ed8`, `0x512c` |
| `0x4c5c` | 225 | `_Ph_SendCommand` | `int __cdecl Ph_SendCommand(int **a1, int a2)` | `Adaptec2940Command.c` | `0x277c`, `0x4618`, `0x46d4` |
| `0x4d40` | 173 | `_Ph_TerminateCommand` | `void __cdecl Ph_TerminateCommand(int a1, char a2)` | `Adaptec2940HIM.c` | `0x2f54`, `0x3080`, `0x3fe4`, `0x4078`, `0x4eb0`, `0x512c`, `0x5c20` |
| `0x4df0` | 111 | `_Ph_PostCommand` | `id __cdecl Ph_PostCommand(int a1)` | `Adaptec2940HIM.c` | `0x3080`, `0x46d4`, `0x512c` |
| `0x4e60` | 36 | `_Ph_RemoveAndPostScb` | `id __cdecl Ph_RemoveAndPostScb(int a1, int a2)` | `Adaptec2940HIM.c` | `0x4e84`, `0x4eb0` |
| `0x4e84` | 42 | `_Ph_PostNonActiveScb` | `id __cdecl Ph_PostNonActiveScb(int a1, int a2)` | `Adaptec2940HIM.c` | `0x4ed8`, `0x54f4` |
| `0x4eb0` | 38 | `_Ph_TermPostNonActiveScb` | `id __cdecl Ph_TermPostNonActiveScb(int a1)` | `Adaptec2940HIM.c` | `0x54f4` |
| `0x4ed8` | 194 | `_Ph_AbortChannel` | `unsigned __int8 __cdecl Ph_AbortChannel(int a1, char a2)` | `Adaptec2940HIM.c` | `0x298c`, `0x2ee4`, `0x4f9c` |
| `0x4f9c` | 257 | `_Ph_HaHardReset` | `unsigned __int8 __cdecl Ph_HaHardReset(int a1)` | `Adaptec2940HIM.c` | `0x277c`, `0x512c` |
| `0x50a0` | 95 | `_Ph_SetHaData` | `int __cdecl Ph_SetHaData(int a1)` | `Adaptec2940HIM.c` | `0x4ed8`, `0x56fc` |
| `0x5100` | 34 | `_Ph_SetScbMark` | `int __cdecl Ph_SetScbMark(int a1)` | `Adaptec2940HIM.c` | `0x50a0` |
| `0x5124` | 7 | `_Ph_HaSoftReset` | `void Ph_HaSoftReset()` | `Adaptec2940HIM.c` | none recorded |
| `0x512c` | 389 | `_Ph_BusDeviceReset` | `unsigned __int8 __cdecl Ph_BusDeviceReset(int a1)` | `Adaptec2940HIM.c` | `0x273c` |
| `0x52b4` | 7 | `_Ph_SoftReset` | `void Ph_SoftReset()` | `Adaptec2940HIM.c` | none recorded |
| `0x52bc` | 56 | `_Ph_GetScbStatus` | `int __cdecl Ph_GetScbStatus(int a1, int a2)` | `Adaptec2940HIM.c` | `0x4c10`, `0x4d40` |
| `0x52f4` | 52 | `_Ph_SetMgrStat` | `unsigned __int8 __cdecl Ph_SetMgrStat(_BYTE *a1)` | `Adaptec2940HIM.c` | `0x4d40` |
| `0x5328` | 166 | `_Ph_WriteBiosInfo` | `unsigned __int8 __cdecl Ph_WriteBiosInfo(int a1, unsigned __int16 a2, int a3, unsigned __int16 a4)` | `Adaptec2940HIM.c` | none recorded |
| `0x53d0` | 166 | `_Ph_ReadBiosInfo` | `unsigned __int8 __cdecl Ph_ReadBiosInfo(int a1, unsigned __int16 a2, int a3, unsigned __int16 a4)` | `Adaptec2940HIM.c` | `0x59fc` |
| `0x5478` | 73 | `_Ph_OutBuffer` | `unsigned __int8 __cdecl Ph_OutBuffer(__int16 a1, int a2, int a3)` | `Adaptec2940HIM.c` | `0x5328` |
| `0x54c4` | 48 | `_Ph_InBuffer` | `unsigned __int8 __cdecl Ph_InBuffer(__int16 a1, int a2, int a3)` | `Adaptec2940HIM.c` | `0x53d0` |
| `0x54f4` | 143 | `_Ph_ScbAbort` | `char __cdecl Ph_ScbAbort(int a1)` | `Adaptec2940HIM.c` | `0x277c`, `0x512c` |
| `0x5584` | 184 | `_SWAPCurrScratchRam` | `int __cdecl SWAPCurrScratchRam(int a1, char a2)` | `Adaptec2940HIM.c` | `0x277c`, `0x56fc` |
| `0x563c` | 33 | `_Ph_InsertBookmark` | `char __cdecl Ph_InsertBookmark(int a1)` | `Adaptec2940HIM.c` | `0x298c`, `0x4f9c` |
| `0x5660` | 25 | `_Ph_RemoveBookmark` | `int __cdecl Ph_RemoveBookmark(int a1)` | `Adaptec2940HIM.c` | `0x298c`, `0x4f9c` |
| `0x567c` | 49 | `_Ph_AsynchEvent` | `int __cdecl Ph_AsynchEvent(int a1, int a2, int a3)` | `Adaptec2940HIM.c` | `0x298c`, `0x2ee4`, `0x4f9c` |
| `0x56b0` | 75 | `_Ph_GetDrvrConfig` | `int __cdecl Ph_GetDrvrConfig(int a1)` | `Adaptec2940Config.c` | `0x6918` |
| `0x56fc` | 182 | `_Ph_InitDrvrHA` | `int __cdecl Ph_InitDrvrHA(int a1)` | `Adaptec2940Config.c` | `0x6b1c` |
| `0x57b4` | 559 | `_PH_GetBiosInfo` | `int __usercall PH_GetBiosInfo@<eax>(int a1@<ebx>, char a2, char a3, _BYTE *a4)` | `Adaptec2940Config.c` | none recorded |
| `0x59e4` | 22 | `_PH_CalcDataSize` | `int __cdecl PH_CalcDataSize(int a1, __int16 a2)` | `Adaptec2940Config.c` | none recorded |
| `0x59fc` | 43 | `_Ph_CheckBiosPresence` | `_BOOL4 __cdecl Ph_CheckBiosPresence(int a1)` | `Adaptec2940Config.c` | `0x56b0` |
| `0x5a28` | 53 | `_Ph_GetOptimaConfig` | `int __cdecl Ph_GetOptimaConfig(int a1)` | `Adaptec2940Optima.c` | `0x56b0` |
| `0x5a60` | 42 | `_Ph_CalcOptimaSize` | `int __cdecl Ph_CalcOptimaSize(unsigned __int16 a1)` | `Adaptec2940Optima.c` | `0x59e4`, `0x5a28` |
| `0x5a8c` | 98 | `_Ph_OptimaEnque` | `unsigned __int8 __cdecl Ph_OptimaEnque(unsigned __int8 a1, int a2, __int16 a3)` | `Adaptec2940Optima.c` | none recorded |
| `0x5af0` | 50 | `_Ph_OptimaEnqueHead` | `int __cdecl Ph_OptimaEnqueHead(unsigned __int8 a1, int a2, int a3)` | `Adaptec2940Optima.c` | none recorded |
| `0x5b24` | 252 | `_Ph_OptimaQHead` | `unsigned __int8 __cdecl Ph_OptimaQHead(char a1, int a2, __int16 a3)` | `Adaptec2940Optima.c` | `0x5af0`, `0x5dfc` |
| `0x5c20` | 474 | `_Ph_OptimaCmdComplete` | `int __cdecl Ph_OptimaCmdComplete(int a1, unsigned __int8 a2, int a3)` | `Adaptec2940Optima.c` | none recorded |
| `0x5dfc` | 170 | `_Ph_OptimaRequestSense` | `int __cdecl Ph_OptimaRequestSense(int a1, char a2)` | `Adaptec2940Optima.c` | none recorded |
| `0x5ea8` | 7 | `_Ph_OptimaClearDevQue` | `void Ph_OptimaClearDevQue()` | `Adaptec2940Optima.c` | none recorded |
| `0x5eb0` | 27 | `_Ph_OptimaIndexClearBusy` | `int __cdecl Ph_OptimaIndexClearBusy(int a1, unsigned __int8 a2)` | `Adaptec2940Optima.c` | `0x5dfc`, `0x5ecc` |
| `0x5ecc` | 37 | `_Ph_OptimaClearTargetBusy` | `int __cdecl Ph_OptimaClearTargetBusy(int a1, unsigned __int8 a2)` | `Adaptec2940Optima.c` | none recorded |
| `0x5ef4` | 7 | `_Ph_OptimaClearChannelBusy` | `void Ph_OptimaClearChannelBusy()` | `Adaptec2940Optima.c` | none recorded |
| `0x5efc` | 182 | `_Ph_SetOptimaHaData` | `int __cdecl Ph_SetOptimaHaData(int a1)` | `Adaptec2940Optima.c` | `0x4b10`, `0x50a0` |
| `0x5fb4` | 363 | `_Ph_SetOptimaScratch` | `char __cdecl Ph_SetOptimaScratch(int a1)` | `Adaptec2940Optima.c` | `0x5efc` |
| `0x6120` | 86 | `_Ph_ScbPageJustifyQIN` | `int __cdecl Ph_ScbPageJustifyQIN(int a1)` | `Adaptec2940Optima.c` | `0x5fb4` |
| `0x6178` | 88 | `_Ph_OptimaMoreFreeScb` | `int __cdecl Ph_OptimaMoreFreeScb(int a1, int a2)` | `Adaptec2940Optima.c` | none recorded |
| `0x61d0` | 170 | `_Ph_OptimaGetFreeScb` | `int __cdecl Ph_OptimaGetFreeScb(int a1, int a2)` | `Adaptec2940Optima.c` | none recorded |
| `0x627c` | 94 | `_Ph_OptimaReturnFreeScb` | `int __cdecl Ph_OptimaReturnFreeScb(int a1, unsigned __int8 a2)` | `Adaptec2940Optima.c` | `0x5c20` |
| `0x62dc` | 35 | `_Ph_OptimaClearQinFifo` | `int __cdecl Ph_OptimaClearQinFifo(int a1)` | `Adaptec2940Optima.c` | none recorded |
| `0x6300` | 129 | `_Ph_MovPtrToScratch` | `unsigned int __cdecl Ph_MovPtrToScratch(__int16 a1, unsigned int a2, int a3)` | `Adaptec2940Optima.c` | `0x5fb4` |
| `0x6384` | 133 | `_Ph_OptimaLoadFuncPtrs` | `_DWORD *__cdecl Ph_OptimaLoadFuncPtrs(int a1)` | `Adaptec2940Optima.c` | `0x56fc` |
| `0x640c` | 764 | `_Ph_OptimaAbortActive` | `int __cdecl Ph_OptimaAbortActive(int a1)` | `Adaptec2940Optima.c` | none recorded |
| `0x6708` | 52 | `_Ph_OptimaEnableNextScbArray` | `unsigned __int8 __cdecl Ph_OptimaEnableNextScbArray(int a1)` | `Adaptec2940Optima.c` | none recorded |
| `0x673c` | 265 | `_PH_GetNumOfBuses` | `int PH_GetNumOfBuses()` | `Adaptec2940Config.c` | none recorded |
| `0x6848` | 53 | `_PH_FindMechanism` | `int PH_FindMechanism()` | `Adaptec2940Config.c` | none recorded |
| `0x6880` | 151 | `_PH_FindHA` | `int __cdecl PH_FindHA(__int16 a1, __int16 a2)` | `Adaptec2940Config.c` | `0x3c` |
| `0x6918` | 515 | `_PH_GetConfig` | `unsigned __int8 __cdecl PH_GetConfig(int a1)` | `Adaptec2940Config.c` | `0x2078` |
| `0x6b1c` | 469 | `_PH_InitHA` | `int __cdecl PH_InitHA(int a1)` | `Adaptec2940Config.c` | `0x2078` |
| `0x6cf4` | 333 | `_Ph_ReadConfig` | `int __usercall Ph_ReadConfig@<eax>(` | `Adaptec2940Config.c` | `0x57b4`, `0x673c`, `0x6880`, `0x6918` |
| `0x6e44` | 369 | `_Ph_WriteConfig` | `int __usercall Ph_WriteConfig@<eax>(` | `Adaptec2940Config.c` | `0x6880` |
| `0x6fb8` | 191 | `_Ph_AccessConfig` | `int __cdecl Ph_AccessConfig(unsigned __int8 a1)` | `Adaptec2940Config.c` | `0x6848`, `0x6cf4`, `0x6e44` |
| `0x7078` | 246 | `_Ph_AutoTermCable` | `int __usercall Ph_AutoTermCable@<eax>(char a1@<bl>, int a2)` | `Adaptec2940Config.c` | `0x6918` |
| `0x7170` | 237 | `_Ph_NoAssistTerm` | `unsigned __int8 __cdecl Ph_NoAssistTerm(int a1)` | `Adaptec2940Config.c` | `0x7078` |
| `0x7260` | 43 | `_Ph_RebuildEEControl` | `int __cdecl Ph_RebuildEEControl(int a1, __int16 a2)` | `Adaptec2940Config.c` | `0x752c` |
| `0x728c` | 672 | `_Ph_ReadEeprom` | `int __cdecl Ph_ReadEeprom(unsigned __int16 *a1, int a2)` | `Adaptec2940Config.c` | `0x6918` |
| `0x752c` | 436 | `_Ph_UpdateEeprom` | `int __cdecl Ph_UpdateEeprom(unsigned __int16 *a1, int a2, unsigned __int16 a3)` | `Adaptec2940Config.c` | `0x7078` |
| `0x76e0` | 238 | `_Ph_ReadE2Register` | `int __cdecl Ph_ReadE2Register(__int16 a1, int a2, int a3)` | `Adaptec2940Config.c` | `0x728c`, `0x752c` |
| `0x77d0` | 399 | `_Ph_WriteE2Register` | `int __cdecl Ph_WriteE2Register(__int16 a1, int a2, int a3, __int16 a4)` | `Adaptec2940Config.c` | `0x752c` |
| `0x7960` | 129 | `_Ph_EnableEraseWriteEE` | `int __cdecl Ph_EnableEraseWriteEE(int a1, int a2)` | `Adaptec2940Config.c` | `0x752c` |
| `0x79e4` | 122 | `_Ph_DisableEraseWriteEE` | `int __cdecl Ph_DisableEraseWriteEE(int a1, int a2)` | `Adaptec2940Config.c` | `0x752c` |
| `0x7a60` | 93 | `_Ph_SendStartBitEE` | `int __cdecl Ph_SendStartBitEE(__int16 a1)` | `Adaptec2940Config.c` | `0x76e0`, `0x77d0`, `0x7960`, `0x79e4` |
| `0x7ac0` | 183 | `_Ph_SendAddressEE` | `__int16 __cdecl Ph_SendAddressEE(__int16 a1, int a2, __int16 a3)` | `Adaptec2940Config.c` | `0x76e0`, `0x77d0`, `0x7960`, `0x79e4` |
| `0x7b78` | 48 | `_Ph_Wait2usec` | `unsigned __int8 __cdecl Ph_Wait2usec(unsigned __int8 a1, __int16 a2)` | `Adaptec2940Config.c` | `0x76e0`, `0x77d0`, `0x7960`, `0x79e4`, `0x7a60`, `0x7ac0` |
| `0x7ba8` | 374 | `_Ph_LoadSequencer` | `int __cdecl(int)` | `Adaptec2940Sequencer.c` | `0x6b1c` |
| `0x7d20` | 511 | `_Ph_ReadCableStatus` | `int __cdecl Ph_ReadCableStatus(int a1)` | `Adaptec2940Config.c` | `0x7078` |

### Generated (2)

| Address | Size | Name | IDA signature | Owner | Callers |
|---:|---:|---|---|---|---|
| `0x7f20` | 12 | `+[Adaptec2940SCSIKernelServerInstance kernelServerInstance]` | `$8EF4127CF77ECA3DDB612FCF233DC3A8 **__cdecl(id, SEL)` | `compiler-generated` | none recorded |
| `0x7f2c` | 12 | `+[Adaptec2940SCSIVersion driverKitVersionForAdaptec2940SCSI]` | `int __cdecl(id, SEL)` | `compiler-generated` | none recorded |

## Class layouts recovered from IDA

Offsets are byte offsets; pointer and `id` widths are four bytes in this i386 image. The IDA type names identify the superclass prefixes: `Adaptec2940` inherits `IODirectDevice` (296-byte prefix) and `SCSIBus` inherits `IOSCSIController` (580-byte prefix). These are distinct roles in the binary: the direct PCI device owns the adapter and its SCSIBus object, while the bus object presents the IOSCSIController interface.

### `Adaptec2940` — 396 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 296 | `IODirectDevice_opaque` | `unsigned __int8[296]` |
| 296 | 2 | `ioBase` | `unsigned __int16` |
| 300 | 8 | `channelInfo` | `$09A2DBEA93E9C6DB96C97A6AF43F6724[1]` |
| 308 | 4 | `hspStructSave` | `$8EF4127CF77ECA3DDB612FCF233DC3A8 *` |
| 312 | 4 | `hspStructFreeSize` | `unsigned int` |
| 316 | 4 | `interruptPortKern` | `int` |
| 320 | 8 | `commandQ` | `$BAB6C68F9D34F0972F921D3DB17D7446` |
| 328 | 4 | `commandLock` | `id` |
| 332 | 8 | `activeQ` | `$BAB6C68F9D34F0972F921D3DB17D7446` |
| 340 | 8 | `scbQ` | `$BAB6C68F9D34F0972F921D3DB17D7446` |
| 348 | 4 | `scbQLength` | `unsigned int` |
| 352 | 8 | `scbBadQ` | `$BAB6C68F9D34F0972F921D3DB17D7446` |
| 360 | 4 | `autoSenseEnable` | `__int32 : 1` |
| 360 | 4 | `cmdQueueEnable` | `__int32 : 1` |
| 360 | 4 | `syncModeEnable` | `__int32 : 1` |
| 360 | 4 | `ioThreadRunning` | `__int32 : 1` |
| 360 | 4 | `needReinit` | `__int32 : 1` |
| 360 | 4 | `pad` | `__int32 : 27` |
| 364 | 4 | `reinitChannel` | `unsigned int` |
| 368 | 4 | `resetState` | `int` |
| 372 | 4 | `maxQueueLen` | `unsigned int` |
| 376 | 4 | `queueLenTotal` | `unsigned int` |
| 380 | 4 | `totalCommands` | `unsigned int` |
| 384 | 4 | `outstandingCount` | `unsigned int` |
| 388 | 4 | `busType` | `int` |
| 392 | 1 | `levelIRQ` | `char` |
| 393 | 1 | `busNumber` | `unsigned __int8` |
| 394 | 1 | `deviceNumber` | `unsigned __int8` |
| 395 | 1 | `functionNumber` | `unsigned __int8` |

### `SCSIBus` — 588 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 580 | `IOSCSIController_opaque` | `unsigned __int8[580]` |
| 580 | 4 | `_direct` | `id` |
| 584 | 4 | `_scsiChannel` | `unsigned int` |

## Firmware and global data

| Symbol | Address | Length | SHA-256 |
|---|---:|---:|---|
| `P_Seq_01` | `0xA038` | 1960 | `6daaeab5ad831ac6a778d5eaa66a980943b5d32c39eb496192c931fba6d392e8` |
| `P_SeqExist` | `0xA7E0` | 24 | `95088dbc9ce187acde41ecf4d4bf782c26e0b470093b113f820e0f0953c61140` |

`P_SeqExist` is two 12-byte mode records. The first record has length zero; the mode-2 record has length 1,960 and patch offset zero in the pinned image. `_Ph_LoadSequencer` reads each record as a 16-bit length plus a 32-bit patch offset at record byte 8. `P_Seq_01` is the mutable 1,960-byte sequencer image; its address and digest pin the exact bytes captured from IDA. Raw bytes and pseudocode stay in ignored analyzer output.

## Remaining IDA UDTs

IDA's private type database contains additional shared packet, queue, command, and CDB layouts. Hex-Rays assigned hashes or generic member names to several private UDTs; those names are retained verbatim and are not guesses about Apple's source identifiers.

### `$09A2DBEA93E9C6DB96C97A6AF43F6724` — 8 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `owner` | `cfpStruct *` |
| 4 | 4 | `var0` | `$8EF4127CF77ECA3DDB612FCF233DC3A8 *` |

### `$BAB6C68F9D34F0972F921D3DB17D7446` — 8 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `next` | `queue_entry *` |
| 4 | 4 | `prev` | `queue_entry *` |

### `$8CD9B4164FBF5A24F48A5A20CADA0334` — 8 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `var0` | `queue_entry *` |
| 4 | 4 | `var1` | `queue_entry *` |

### `$E7BB6EE711814A6885BC94630F193936` — 36 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `var0` | `unsigned int` |
| 4 | 4 | `var1` | `int` |
| 8 | 4 | `var2` | `$8EF4127CF77ECA3DDB612FCF233DC3A8 *` |
| 12 | 4 | `var3` | `void *` |
| 16 | 4 | `var4` | `unsigned int` |
| 20 | 4 | `var5` | `int` |
| 24 | 4 | `var6` | `id` |
| 28 | 8 | `var7` | `$8CD9B4164FBF5A24F48A5A20CADA0334` |

### `_cdb_6` — 1 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 1 | `var0` | `unsigned __int8` |
| 0 | 4 | `var1` | `__int32 : 5` |
| 0 | 4 | `var2` | `__int32 : 3` |
| 0 | 1 | `var3` | `unsigned __int8` |
| 0 | 1 | `var4` | `unsigned __int8` |
| 0 | 1 | `var5` | `unsigned __int8` |
| 0 | 1 | `var6` | `unsigned __int8` |

### `cdb_6s` — 6 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 1 | `var0` | `unsigned __int8` |
| 1 | 4 | `var1` | `__int32 : 2` |
| 1 | 4 | `var2` | `__int32 : 3` |
| 1 | 4 | `var3` | `__int32 : 3` |
| 2 | 1 | `var4` | `unsigned __int8` |
| 3 | 1 | `var5` | `unsigned __int8` |
| 4 | 1 | `var6` | `unsigned __int8` |
| 5 | 1 | `var7` | `unsigned __int8` |

### `cdb_10` — 10 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 1 | `var0` | `unsigned __int8` |
| 1 | 4 | `var1` | `__int32 : 1` |
| 1 | 4 | `var2` | `__int32 : 2` |
| 1 | 4 | `var3` | `__int32 : 1` |
| 1 | 4 | `var4` | `__int32 : 1` |
| 1 | 4 | `var5` | `__int32 : 3` |
| 2 | 1 | `var6` | `unsigned __int8` |
| 3 | 1 | `var7` | `unsigned __int8` |
| 4 | 1 | `var8` | `unsigned __int8` |
| 5 | 1 | `var9` | `unsigned __int8` |
| 6 | 1 | `var10` | `unsigned __int8` |
| 7 | 1 | `var11` | `unsigned __int8` |
| 8 | 1 | `var12` | `unsigned __int8` |
| 9 | 1 | `var13` | `unsigned __int8` |

### `cdb_12` — 12 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 1 | `var0` | `unsigned __int8` |
| 1 | 4 | `var1` | `__int32 : 1` |
| 1 | 4 | `var2` | `__int32 : 2` |
| 1 | 4 | `var3` | `__int32 : 1` |
| 1 | 4 | `var4` | `__int32 : 1` |
| 1 | 4 | `var5` | `__int32 : 3` |
| 2 | 1 | `var6` | `unsigned __int8` |
| 3 | 1 | `var7` | `unsigned __int8` |
| 4 | 1 | `var8` | `unsigned __int8` |
| 5 | 1 | `var9` | `unsigned __int8` |
| 6 | 1 | `var10` | `unsigned __int8` |
| 7 | 1 | `var11` | `unsigned __int8` |
| 8 | 1 | `var12` | `unsigned __int8` |
| 9 | 1 | `var13` | `unsigned __int8` |
| 10 | 1 | `var14` | `unsigned __int8` |
| 11 | 1 | `var15` | `unsigned __int8` |

### `$55B996686E2E2C4974FEF7D53845AF12` — 26 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `var0` | `__int32 : 4` |
| 0 | 4 | `var1` | `__int32 : 3` |
| 0 | 4 | `var2` | `__int32 : 1` |
| 1 | 1 | `var3` | `unsigned __int8` |
| 2 | 4 | `var4` | `__int32 : 4` |
| 2 | 4 | `var5` | `__int32 : 1` |
| 2 | 4 | `var6` | `__int32 : 1` |
| 2 | 4 | `var7` | `__int32 : 1` |
| 2 | 4 | `var8` | `__int32 : 1` |
| 3 | 1 | `var9` | `unsigned __int8` |
| 4 | 1 | `var10` | `unsigned __int8` |
| 5 | 1 | `var11` | `unsigned __int8` |
| 6 | 1 | `var12` | `unsigned __int8` |
| 7 | 1 | `var13` | `unsigned __int8` |
| 8 | 4 | `var14` | `unsigned __int8[4]` |
| 12 | 1 | `var15` | `unsigned __int8` |
| 13 | 1 | `var16` | `unsigned __int8` |
| 14 | 1 | `var17` | `unsigned __int8` |
| 15 | 1 | `var18` | `unsigned __int8` |
| 16 | 1 | `var19` | `unsigned __int8` |
| 17 | 1 | `var20` | `unsigned __int8` |
| 18 | 1 | `var21` | `unsigned __int8` |
| 19 | 1 | `var22` | `unsigned __int8` |
| 20 | 1 | `var23` | `unsigned __int8` |
| 21 | 1 | `var24` | `unsigned __int8` |
| 22 | 1 | `var25` | `unsigned __int8` |
| 23 | 1 | `var26` | `unsigned __int8` |
| 24 | 1 | `var27` | `unsigned __int8` |
| 25 | 1 | `var28` | `unsigned __int8` |

### `Adaptec2940SCSIVersion` — 264 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 264 | `IODevice_opaque` | `unsigned __int8[264]` |

### `Adaptec2940SCSIKernelServerInstance` — 4 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `Object_opaque` | `unsigned __int8[4]` |

### `$D05E80C3BC593CB6499B19108CB7B188` — 4 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `var0` | `__int32 : 8` |
| 1 | 4 | `var1` | `__int32 : 8` |
| 2 | 4 | `var2` | `__int32 : 1` |
| 2 | 4 | `var3` | `__int32 : 1` |
| 2 | 4 | `var4` | `__int32 : 2` |
| 2 | 4 | `var5` | `__int32 : 1` |
| 2 | 4 | `var6` | `__int32 : 1` |
| 2 | 4 | `var7` | `__int32 : 1` |
| 2 | 4 | `var8` | `__int32 : 1` |
| 3 | 4 | `var9` | `__int32 : 8` |

### `_8L_{_` — 4 bytes

| Offset | Width | Member | IDA type |
|---:|---:|---|---|
| 0 | 4 | `var0` | `__int32 : 8` |
| 0 | 4 | `var1` | `__int32 : 2` |
| 0 | 4 | `var2` | `__int32 : 1` |
| 0 | 4 | `var3` | `__int32 : 1` |
| 0 | 4 | `var4` | `__int32 : 1` |
| 0 | 4 | `var5` | `__int32 : 1` |
| 0 | 4 | `var6` | `__int32 : 1` |
| 0 | 4 | `var7` | `__int32 : 1` |
| 0 | 4 | `var8` | `__int32 : 8` |
| 0 | 4 | `var9` | `__int32 : 8` |
| 0 | 4 | `var10` | `unsigned int` |
| 0 | 4 | `var11` | `unsigned int` |
| 0 | 4 | `var12` | `__int32 : 8` |
| 0 | 4 | `var13` | `__int32 : 1` |
| 0 | 4 | `var14` | `__int32 : 1` |
| 0 | 4 | `var15` | `__int32 : 1` |
| 0 | 4 | `var16` | `__int32 : 1` |
| 0 | 4 | `var17` | `__int32 : 4` |
| 0 | 4 | `var18` | `__int32 : 8` |
| 0 | 4 | `var19` | `__int32 : 8` |
| 0 | 4 | `var20` | `unsigned int` |
| 0 | 4 | `var21` | `unsigned int` |
| 0 | 4 | `var22` | `unsigned int` |
| 0 | 4 | `var23` | `__int32 : 24` |
| 0 | 4 | `var24` | `__int32 : 8` |

## Host-adapter initialization and completion

`Ph_InitDrvrHA` resets per-adapter counters, captures current scratch registers, initializes the host data block and Optima scratch maps, sets the sequencer RAM window to address 1, reads the scratch byte at address 3, stores its one-based value at block offset 264, then installs the Optima function table. `SWAPCurrScratchRam` snapshots I/O offsets 32–95 into block offsets 288–351, forces offset 65 to zero and offsets 70–85 to `0x7f`; with saving enabled it first restores offsets 59–95 from the prior snapshot. Both routines clear the sequencer address registers at the end of the swap.

`Ph_PostCommand` drains the completion index queue from its tail, calls the host completion marker with each index, removes the associated SCB from the host chain, copies the SCB completion status, and routes it through `PH_ScbCompleted`. `checkScbAlign:` adds an SCB whose transfer region crosses a page boundary to the controller's bad-SCB list, preserving the list links at SCB offsets 248 and 252.

## Message negotiation and cable sensing

`Ph_ExtMsgo` saves and restores transfer control registers, sends the SCB message bytes through the request port, completes the extended-message response phase, and applies synchronous negotiation period/offset fields when the SCB carries a negotiation request. `Ph_SyncNego` then interprets the returned negotiation code and handles the additional WDTR-style response loop. `Ph_ReadCableStatus` reads the termination/cable pins using controller-family-specific GPIO sequencing for device IDs `0x7550`, `0x7850`, `0x7870`, and `0x7880`.

`Ph_ExtMsgi` in `Adaptec2940ExtMsgi.c` reconstructs extended-message input,
including the B0 response, message-length reception, synchronous and wide
negotiation updates, Fast20 target-map changes, downgrade retry behavior, and
bad-sequence dispatch. Its native i386 port-shim harness checks those message
paths and their output order.
