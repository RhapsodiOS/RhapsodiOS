# i386 ABI evidence

Reference: `BusLogicFPSCSI_reloc`, 77,964 bytes, SHA-256 `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`. IDA Professional 9.4 recovered 123 functions with complete pseudocode and disassembly in the ignored SDD evidence directory; angr 9.3.0 also completed. `binrecon` consensus is explicitly disputed because angr fragments function boundaries that IDA names. The IDA export is the named-function inventory; each final ledger claim still requires per-function binary comparison.

## Partition and Objective-C identity

IDA reports 28 `BLFPController` methods, 93 named C routines, and two generated `BusLogicFPSCI` kernel-server methods. The two generated entries are at `0x7780` and `0x778c`. The source map presently records all 123 as unmapped because the checked-in implementation is a differently named `BusLogicFPSCSI` scaffold; this is a measured baseline, not a source-map filtering decision.

## Request and SCCB evidence

At `0x0668`, `-[BLFPController executeRequest:buffer:client:]` zeroes a 0x30-byte command record, stores the request, buffer, and client at dword offsets 4, 8, and 12, invokes `executeCmdBuf:`, then returns dword offset 16. This establishes a 48-byte command record and its first five dword fields.

At `0x10c0`, `sccbFromCmd:` stores the owning controller at SCCB byte offset 248 and the command-record pointer at offset 236. It stores completion callback at 40 and controller I/O base at 44. The copied CDB begins at byte 18; target and LUN bytes are at 16 and 17. Sense-buffer physical address is written at byte offset 36, sense size at 3. The scalar data buffer fields occupy dwords at offsets 4 and 8. Scatter/gather pairs start at 100, each pair is 8 bytes, and the loop caps at 17 entries before selecting opcode 4. The SCCB is zeroed for 0x104 (260) bytes in `allocSccb` at `0x1704`; queue links are at offsets 252 and 256 from the free-list operations at `0x1704` and `0x1770`.

CDB length decoding at `0x10c0` uses `cdb[2] & 0xe0`: group 0 selects 6 bytes; groups 1 and 2 select 10; group 5 selects 12; vendor groups 6 and 7 use the high nibble of `cdb[27]` when present, otherwise 6 or 10 respectively. The control bits checked by this routine are the low two bits of the selected final CDB byte; a nonzero value sets request status 7 and rejects submission. Data mapping splits at page boundaries, stores up to 17 physical segments, and sets request status 14 on an untranslatable data address. A failed sense-address translation sets SCCB sense length to 1; successful translation sets it to 26.

`BLCCallback` at `0x193c` dispatches `sccbComplete:reason:` to the controller pointer at SCCB offset 248 with reason zero. Completion at `0x13e8` maps completion reason 1 to request status 5 and reason 2 to 20. For normal reason 0, completion removes the SCCB from the outstanding queue, copies SCSI status, sets residual to requested length minus transferred length for host statuses 0, 12, and 18, and maps SCSI status 0 to request status 0, status 2 to 2, and other nonzero values to 13. Host status 17 maps to 1; 52/53 map to 21/20; unrecognized values map to 22.

## Verified helpers and hardware access

`doesCrossPage(a1,a2)` at `0x1914` returns whether the page portions of `a1` and `a1+a2-1` differ, using `page_mask`. `SccbMgr_my_int(card)` at `0x4938` reads one byte from `*(uint32_t *)(card+8)+55` and tests bit `0x20`. `resetHardware` at `0x1860` calls `SccbMgr_config_adapter`; `-1` returns failure 1, otherwise it stores the returned card pointer, sleeps 10,000 ms and returns 0.

The adapter manager port accessors are at `0x2728`–`0x27a8`; the timer, lock and unlock hooks are at `0x27a8`–`0x27c8`. Their exact kernel service prototypes and calling conventions remain to be recovered at their Task 2/4 implementation sites. Target/card/negotiation structure layouts and the constants/tables consumed by the transfer, SCSI, SCAM and EEPROM paths also remain open; no guessed complete structures are published here.

## Baseline source identity

`Default.table` currently advertises device ID `0x8138104b` and version `1.0`; the reference specification identifies the required values as `0x8130104b` and `5.00`. The repository's checked-in class name and its FlashPoint wrapper are not the reference ABI. They are to be replaced as implementation evidence is recovered.

## Objective-C controller instance fields

The runtime `__instance_vars` list at `0xcb9c` contains 18 entries; each stores name/type pointers and a byte offset. The class record at `0xc138` declares instance size `0x294`. IDA pseudocode confirms these fields and offsets:

| Offset | Field | Runtime type | Notes |
|---:|---|---|---|
| `0x244` | `ioBase` | `S` | 16-bit port base |
| `0x248` | `irq` | `I` | 32-bit |
| `0x24c` | `sccbMgr` | `^{?}` | pointer to 64-byte manager-info prefix used by `probeForBoard` |
| `0x250` | `sccbMgrRaw` | `I` | IDA emitted an integer type; `IOMalloc`/`IOFree` call sites prove pointer semantics |
| `0x254` | `cardHandle` | `I` | `SccbMgr_config_adapter` return stored and passed as a card pointer |
| `0x258` | `sccbFreeList` | queue head | 8 bytes |
| `0x260` | `commandQ` | queue head | 8 bytes |
| `0x268` | `commandLock` | object pointer | `NXLock` |
| `0x26c` | `outstandingQ` | queue head | 8 bytes |
| `0x274` | `outstandingCount` | `I` | 32-bit |
| `0x278` | `maxQueueLen` | `I` | 32-bit |
| `0x27c` | `queueLenTotal` | `I` | 32-bit |
| `0x280` | `totalCommands` | `I` | 32-bit |
| `0x284` | `interruptPortKern` | `i` | signed port name |
| `0x288` | `ioThreadRunning` | `c` | byte |
| `0x28c` | `busType` | `i` | 32-bit |
| `0x290` | `levelIRQ` | `c` | byte |
| `0x291` | `targetsPerBus` | `C` | byte |

These offsets are from the reference's Objective-C runtime metadata, with pointer types corrected only where allocation/call sites prove an integer-typed IDA field is a pointer. Retain the inherited object prefix through byte `0x243`; the new subclass instance allocation is `0x294` bytes total.

The manager-info prefix consumed by `probeForBoard` is zeroed for 64 bytes. Confirmed fields are base I/O address at `+0`, present flag `+4`, IRQ `+5`, adapter flags `+16`, family `+17`, bus type `+18`, model string `+19..+21`, and owning controller at `+28`. `initFromDeviceDescription:` sets `flags |= 0x41` and clears flag bit `0x04`; `probeForBoard` sets bus type values 1/2/3 for EISA/VL/PCI and leaves the prefix sized to 64 bytes. Fields beyond this observed prefix are still under review.

## Objective-C metadata and message templates

The reference main class is `BLFPController` (`__class` record `0xc138`), with categories `BLFPController_IOThread` (`__category` record at `0xcb74`) and `BLFPController_PrivateMethods` (record at `0xcb84`). It exposes 16 primary instance methods, 2 private-category methods, 9 IOThread methods, and one class probe method (28 methods total). The two standalone generated kernel-server methods are separate from the controller class.

The binary data object `_BLCMessageTemplate` at `0x8000` is 24 bytes, SHA-256 `725C4237436D3D04C9EEC72F7D176E81CECE5E644921E26F8B9526A7D730F3BB`; `_timeoutMsgTemplate` at `0x8018` is 24 bytes, SHA-256 `829B6B553A43E84E06AEA78C22223D5F02467E2F1704DC56F668C62F63B55863`. Both begin `00 00 00 01 18 00 00 00`, have a zero-filled body through byte 19, and end in distinct three-byte message IDs (`24 23 23` and `23 23 23`). `_first_time.2` at `0x8030` is `01 00 00 00` (SHA-256 `67ABDD721024F0FF4E0B3F4C2FC13BC5BAD42D0B7851D456D88D203D15AAA450`). Raw metadata and table bytes are preserved in ignored IDA evidence; the complete table inventory and use sites are not yet final.


## Interrupt, timeout and queue-order expectations measured from IDA

`-[BLFPController interruptOccurred]` at `0x06ec` calls `SccbMgr_my_int(cardHandle)` first. That helper performs a byte read from `cardHandle.ioBase + 55` and tests `0x20`. The ISR call occurs only when the bit is set. For a level-triggered IRQ (`levelIRQ != 0`), `enableAllInterrupts` follows whether or not this card's interrupt was pending. The reconstructed test must assert this read/mask and ISR ordering; the mock must not execute a native port instruction.

`threadExecuteRequest:` at `0x0efc` allocates an SCCB and converts the request. Conversion failure goes directly to command completion. Success writes the kernel interrupt port into the SCCB, schedules its timeout using the request timeout, sets the SCCB timeout-scheduled byte, appends it to `outstandingQ`, increments outstanding count, updates max and cumulative queue statistics, increments total command count, then calls `SccbMgr_start_sccb`.

`timeoutOccurred` at `0x07d4` samples one timestamp, walks the outstanding queue in order, and treats the request as expired when `now >= request.timestamp + 1,000,000,000 * timeoutSeconds`. Each expired node is unlinked and decrements `outstandingCount` before `sccbComplete:reason:` with reason 1. If any request expired, it invokes `threadResetBus:nil` after finishing the scan. This order determines timeout and reset completion assertions.


## IDA C routine signature inventory

These signatures are the decompiler prototype hypotheses emitted by IDA 9.4 at each start address. They are preserved to inventory all 93 C routines; pointer-like integer returns/arguments and global state still require assembly/call-site confirmation before becoming public declarations. The pseudocode sidecar holds complete function bodies and disassembly.

- `0x0d48` `int __cdecl parseConfigSpace(id a1, int a2, int a3, _WORD *a4, _DWORD *a5)`
- `0x18b4` `int __cdecl blcTimeout(int a1)`
- `0x1914` `_BOOL4 __cdecl doesCrossPage(int a1, int a2)`
- `0x193c` `id __cdecl BLCCallback(int a1)`
- `0x195c` `int __cdecl autoLoadDefaultMap(__int16 a1)`
- `0x1c94` `int __cdecl autoCmdCmplt(__int16 a1, unsigned __int8 a2)`
- `0x1ea0` `int __cdecl dataXferProcessor(int a1, _BYTE *a2)`
- `0x1eec` `int __cdecl busMstrSGDataXferStart(__int16 a1, int a2)`
- `0x209c` `int __cdecl busMstrDataXferStart(__int16 a1, int a2)`
- `0x217c` `_BOOL4 __cdecl busMstrTimeOut(__int16 a1)`
- `0x2218` `int __cdecl hostDataXferAbort(__int16 a1, unsigned __int8 a2, int a3)`
- `0x2594` `void __cdecl hostDataXferRestart(int a1)`
- `0x25f0` `int __cdecl XbowInit(__int16 a1)`
- `0x26b4` `int __cdecl BusMasterInit(__int16 a1)`
- `0x2728` `int __cdecl OS_InPortByte(unsigned __int16 a1)`
- `0x273c` `int __cdecl OS_InPortWord(unsigned __int16 a1)`
- `0x2750` `unsigned __int32 __cdecl OS_InPortLong(unsigned __int16 a1)`
- `0x275c` `int __cdecl OS_OutPortByte(unsigned __int16 a1, unsigned __int8 a2)`
- `0x2774` `int __cdecl OS_OutPortWord(unsigned __int16 a1, unsigned __int16 a2)`
- `0x2790` `int __cdecl OS_OutPortLong(unsigned __int16 a1, unsigned int a2)`
- `0x27a8` `void OS_start_timer()`
- `0x27b0` `void OS_stop_timer()`
- `0x27b8` `void OS_Lock()`
- `0x27c0` `void OS_UnLock()`
- `0x27c8` `int __cdecl phaseDecode(int a1, unsigned __int8 a2)`
- `0x2810` `int __cdecl phaseDataOut(int a1, unsigned __int8 a2)`
- `0x28d0` `int __cdecl phaseDataIn(int a1, unsigned __int8 a2)`
- `0x2994` `int __cdecl phaseCommand(__int16 a1, unsigned __int8 a2)`
- `0x2a78` `int __cdecl phaseStatus(__int16 a1)`
- `0x2a90` `int __cdecl phaseMsgOut(int a1, unsigned __int8 a2)`
- `0x2ce8` `int __cdecl phaseMsgIn(int a1, unsigned __int8 a2)`
- `0x2d68` `int __cdecl phaseIllegal(__int16 a1, unsigned __int8 a2)`
- `0x2dd0` `int __cdecl phaseChkFifo(int a1, unsigned __int8 a2)`
- `0x2f68` `int __cdecl phaseBusFree(__int16 a1, unsigned __int8 a2)`
- `0x3160` `int ScamInit(unsigned __int8 a1, unsigned __int8 a2, ...)`
- `0x3344` `int __cdecl ScamArbitration(int a1, char a2)`
- `0x3488` `int __cdecl ScamBusFree(__int16 a1)`
- `0x3530` `int __cdecl ScamAssignID(char a1, int a2)`
- `0x3610` `int __cdecl ScamSelect(int a1)`
- `0x36a4` `int __cdecl ScamXferCycle(int a1, char a2)`
- `0x376c` `int __cdecl ScamSendIsolate(int a1, int a2)`
- `0x380c` `int __cdecl ScamIsolate(int a1, int a2)`
- `0x3880` `int __cdecl ScamWireOrData(__int16 a1, unsigned __int8 a2)`
- `0x38bc` `int __cdecl ScamWireOrSig(__int16 a1, unsigned __int8 a2)`
- `0x38f8` `_BOOL4 __cdecl ScamValidQ(unsigned __int8 a1)`
- `0x3924` `int __cdecl ScamSelLegacy(int a1, unsigned __int8 a2)`
- `0x3b5c` `int __cdecl ScamWaitSelection(__int16 a1)`
- `0x3b7c` `int __cdecl initScamInfo(unsigned __int8 a1, int a2)`
- `0x3ca4` `int __cdecl scamMatchId(unsigned __int8 a1, char *a2)`
- `0x3f04` `int __cdecl scamSaveDeviceInfo(unsigned __int8 a1, int a2)`
- `0x4010` `int __cdecl SccbMgr_sense_adapter(int *a1)`
- `0x432c` `int __cdecl SccbMgr_config_adapter(int a1)`
- `0x46a0` `int __cdecl SccbMgr_start_sccb(int a1, int a2)`
- `0x484c` `int __cdecl SccbMgr_abort_sccb(int a1, int a2)`
- `0x4938` `_BOOL4 __cdecl SccbMgr_my_int(int a1)`
- `0x4960` `int __cdecl SccbMgr_isr(int *a1)`
- `0x4e88` `int __cdecl SccbMgr_bad_isr(int a1, unsigned __int8 a2, _DWORD *a3, char a4)`
- `0x50fc` `int __cdecl SccbMgr_scsi_reset(int a1)`
- `0x51b4` `void SccbMgr_timer_expired()`
- `0x51bc` `int SccbMgrTableInitAll()`
- `0x5218` `int __cdecl SccbMgrTableInitCard(int a1, unsigned __int8 a2)`
- `0x5294` `int __cdecl SccbMgrTableInitTarget(unsigned __int8 a1, unsigned __int8 a2)`
- `0x5318` `int __cdecl scsiFetchMsg(__int16 a1, int a2)`
- `0x53e0` `int __cdecl scsiSelect(int a1, unsigned __int8 a2)`
- `0x585c` `int __cdecl scsiReselection(__int16 a1, unsigned __int8 a2, int *a3)`
- `0x5b2c` `int __cdecl scsiDecodeMsg(unsigned __int8 a1, int a2, unsigned __int8 a3)`
- `0x5e24` `int __cdecl scsiHandleExtMsg(int a1, char a2, int a3)`
- `0x5f58` `int __cdecl scsiInitSyncNego(__int16 a1, unsigned __int8 a2)`
- `0x60c8` `int __cdecl scsiTargSyncNego(int a1, unsigned __int8 a2)`
- `0x6288` `int __cdecl scsiInitSyncRespond(__int16 a1, unsigned __int8 a2, unsigned __int8 a3)`
- `0x6398` `int __cdecl scsiInitWideNego(__int16 a1, unsigned __int8 a2)`
- `0x64bc` `int __cdecl scsiTargWideNego(int a1, unsigned __int8 a2)`
- `0x65bc` `int __cdecl scsiInitWideRespond(__int16 a1, unsigned __int8 a2)`
- `0x66b0` `int __cdecl scsiSetSyncValue(__int16 a1, unsigned __int8 a2, unsigned __int8 a3, int a4)`
- `0x6774` `int __cdecl scsiResetBus(int a1, unsigned __int8 a2)`
- `0x691c` `int __cdecl scsiSenseSetup(int *a1)`
- `0x698c` `int __cdecl scsiXferPad(__int16 a1, unsigned __int8 a2)`
- `0x6bac` `char __cdecl scsiChkDmaDone(int a1, unsigned __int8 a2)`
- `0x6d94` `int __cdecl scsiInitSCCB(int a1, unsigned __int8 a2)`
- `0x6e88` `int __cdecl queueSearchSelect(_BYTE *a1, unsigned __int8 a2)`
- `0x6f3c` `char __cdecl queueSelectFail(int *a1, unsigned __int8 a2)`
- `0x6fc8` `int __cdecl queueCmdComplete(int a1, int a2)`
- `0x70c0` `int __cdecl queueDisconnect(unsigned __int8 *a1, unsigned __int8 a2)`
- `0x7140` `int __cdecl queueFlushSccb(unsigned __int8 a1, char a2)`
- `0x71ec` `int __cdecl queueAddSccb(int a1, unsigned __int8 a2)`
- `0x725c` `int __cdecl queueFindSccb(int a1, unsigned __int8 a2)`
- `0x72fc` `int __cdecl utilUpdateResidual(int a1)`
- `0x7358` `int __cdecl Wait1Second(int a1)`
- `0x73a0` `int __cdecl Wait(__int16 a1, unsigned __int8 a2)`
- `0x7480` `int __cdecl utilEEWriteOnOff(int a1, char a2)`
- `0x74e4` `int __cdecl utilEEWrite(int a1, unsigned __int16 a2, __int16 a3)`
- `0x75cc` `int __cdecl utilEERead(int a1, __int16 a2)`
- `0x7688` `int __cdecl utilEESendCmdAddr(__int16 a1, unsigned __int8 a2, unsigned __int16 a3)`

## Message negotiation and EEPROM expectations measured from IDA

`scsiDecodeMsg` (`0x5b2c`) dispatches extended-message code 1 to `scsiHandleExtMsg`. Codes 8 and above `0x7f` follow the message-reject path (`OUT B+68, 2`, then `OUT B+101, 0x28`). Unknown ordinary messages store host status 20 and SCSI message status 7, wait until `IN B+68 & 0x20` clears, then write `0x0a` to `B+68`. Extended negotiation at `0x5e24` accepts `(length=3, type=3)` for target sync negotiation and `(length=2, type=2)` for target wide negotiation. Other pairs store SCSI message status 7 and issue the reject sequence. The decompiler showed an uninitialized value in one message-ack write; assertions for that branch require the disassembly in the saved sidecar, not that pseudocode value.

`scsiSetSyncValue` (`0x66b0`) permutes target IDs through the explicit 16-entry selector order `0x0c..0x0f, 0x08..0x0b, 0x04..0x07, 0x00..0x03`, writes the negotiated byte to `B+84+selector`, and stores that byte in target state at offset 208. Initiator sync negotiation emits firmware words at `B+128, +130, +136, +138, +140, +142, +144, +146, +148`, with the +142 word selected as `0x860c`, `0x8619`, `0x8632`, or `0x8600` for rate classes 3, 2, 1, or 0. Wide negotiation uses its own fixed sequence at those offsets and records negotiation state bits.

`utilEERead` (`0x75cc`) sends read command 6 and the address through `utilEESendCmdAddr`, clocks exactly 16 data bits by writing the register at `B+34`, reads bit 0 once per bit, shifts them into a 16-bit return, then writes the end/idle values. It has no readiness poll in that 16-bit loop. `utilEEWrite` (`0x74e4`) sends command 5 and a 16-bit value MSB first, then calls `Wait(B,7)` before its end sequence. `utilEESendCmdAddr` (`0x7688`) shifts three command bits (4, 2, 1) and eight or ten address bits, chosen by bit `0x10` read from `B+41`; the address loop starts at `0x80` or `0x200` and shifts through bit 0. Every bit is the ordered low/clock/high sequence at `B+34`. These counts follow the actual `do/while (bit != 0)` loops in IDA and are the EEPROM mock assertions.

SCAM initialization (`0x3160`) calls `initScamInfo`, a one-second wait, and reads EEPROM word 10. It checks 16 IDs when `IN B+41 & 0x10` is set, otherwise 8. If the read word has bit 2 set, it resets the bus, waits again, repeatedly calls `ScamArbitration` until success, then selects and assigns IDs. The arbitration routine (`0x3344`) contains unbounded waits for bus-line state and a retry loop in `ScamInit`; no timeout or maximum retry count is present in the reference path. Tests must assert the observed successful trace and avoid manufacturing a termination bound the binary does not have.

## Manager card, target and SCAM record layouts

These are fixed-stride global records, independently recoverable from the reference's indexed stores/clears. They supersede similarly named declarations in the nearby Linux code where byte offsets differ.

- `_BL_Card` has a `20 * 4`-byte table. `SccbMgrTableInitAll` iterates four cards at `0x51bc`. `SccbMgr_config_adapter` selects a card with a 20-byte stride at `0x432c`. The 20-byte record fields are: current SCCB pointer `+0`; 32-bit manager-info pointer `+4`; 32-bit I/O base `+8`; command counter `u16 +12`; manager card index `u8 +14`; tag queue cursor `u8 +15`; card flags `u8 +16`; host ID `u8 +17`; opaque bytes `+18..+19`. `SccbMgrTableInitCard` zeros `+15`, `+0`, `+16`, and `+12`; `SccbMgrTableInitAll` zeros I/O base/info pointer and sets `+14` to `0xff`, `+17` to zero. `SccbMgr_config_adapter` stores the chosen index at `+14`, info pointer at `+4`, and host ID at `+17`. These stores and later flag tests establish the corrected tail offsets.
- `_sccbMgrTbl` has `4 * 16` target records, each `212` bytes: `0x51bc` iterates 4 cards; `0x5218` iterates 16 targets at each card; queue arithmetic uses 848 dwords/card = 3392 bytes/card and 53 dwords/target = 212 bytes/target. Initialization clears bytes `0..63`, clears 33 dwords at `+64..+195`, clears selection-list head/tail pointers at `+196/+200`, per-target count/status bytes at `+204/+205`, `+208`, and other state at `+206/+207` through initialization/configuration paths. Recovered names from uses: 33 dword queue slots `+64..+195`; selection-list head/tail `+196/+200`; selection eligibility/count bytes `+204/+205`; target status `+206`; EEPROM negotiation value `+207`; sync/negotiation value `+208`. Bytes `+0..+63` are cleared as a block but have no safely recovered field names yet and stay a byte array in the reconstructed declarations.
- `_scamInfo` has 4 card regions of `576` bytes each and 16 entries of 36 bytes. `initScamInfo` (`0x3b7c`) reads 16 16-bit EEPROM words per entry into the first 32 bytes; `scamMatchId` reads/writes the same 32-byte ID string. The state word begins at `+32` in each 36-byte entry. `ScamInit` uses a companion state array with 9 dwords per target and 144 bytes per card.

The manager `sccb_mgr_info` record is at least 64 bytes and uses the field offsets listed above. Its later NVRAM/capability fields are read by `SccbMgr_sense_adapter` at bytes `+16`, `+19..+22`, `+32..+35`, and words `+20/+24/+28`; the exact typed NVRAM fields remain to be correlated with `sccb_mgr_info` call-site setup before those declarations are published.

### Task 2 implementation corrections

The port accessors return `int` for byte and word input, with the result zero-extended to EAX; long input returns `u32`. All six take a 16-bit port. Output functions return zero after the native access and one locked increment of their matching counter. `OS_start_timer`, `OS_stop_timer`, `OS_Lock`, and `OS_UnLock` have no parameters and no body effects. The first implementation now exports the 20 Task 2 functions; their per-function IDA evidence, source mapping, compile result, and focused test coverage are in `evidence-task2.md`.

Selection list `+196/+200` uses SCCB forward/back links at `+76/+80`, with an 8-bit count at target `+205`. Disconnected queues use the 33 pointer slots at `+64..+195`, indexed by tag, while 32 LUN counters occupy target bytes `+32..+63`. `queueFlushSccb` starts with the active SCCB's target ID and completes disconnected entries in ascending tag slot before clearing the LUN counters. These byte/stride interpretations are based on instructions at `0x6e88..0x7358`, not Linux structure names.



## SCCB field map confirmed by manager instruction offsets

The target SCCB begins with the standard request prefix through byte 51, then the manager uses this exact layout. These offsets are independently visible in `scsiInitSCCB` (`0x6d94`), queue/phase routines and controller code:

| Offset | Width | Evidence / use |
|---:|---:|---|
| `+0` | 1 | operation code; tested as 2/4 by `scsiInitSCCB` |
| `+1` | 1 | control byte and tagged queue bit |
| `+2` | 1 | CDB length |
| `+3` | 1 | request sense length |
| `+4` | 4 | requested data length; copied to `+52` by `scsiInitSCCB` |
| `+8` | 4 | data pointer or SG-list pointer |
| `+12..+13` | 2 | reserved |
| `+14` / `+15` | 1 each | host / target status |
| `+16` / `+17` | 1 each | target ID / LUN |
| `+18..+29` | 12 | CDB bytes |
| `+30..+35` | 6 | reserved words |
| `+36` | 4 | sense physical address |
| `+40` | 4 | completion callback |
| `+44` | 4 | I/O base |
| `+48` | 1 | manager completion state |
| `+50` | 2 | manager OS flags |
| `+52` | 4 | transfer count/current data count |
| `+56` | 4 | DMA/ATC bookkeeping; zeroed in `scsiInitSCCB` |
| `+60` | 4 | virtual data pointer |
| `+64` | 4 | reserved manager word |
| `+68` | 2 | manager flags |
| `+70` | 2 | SG segment count/index |
| `+72` / `+73` | 1 each | outgoing SCSI message / tag |
| `+74` / `+75` | 1 each | SCSI phase/state / saved identify message |
| `+76` / `+80` | 4 each | manager forward/back links |
| `+84` | 4 | saved transfer count |
| `+88..+93` | 6 | saved CDB bytes |
| `+94` | 1 | saved CDB length |
| `+95` | 1 | transfer state flags; cleared/set by `scsiInitSCCB` and consumed by `queueCmdComplete` |
| `+96` | 4 | SG offset, zeroed for SG opcodes |
| `+100..+235` | 136 | 17 physical SG `{length,address}` entries of 8 bytes each |
| `+236` | 4 | owning 48-byte command record |
| `+240..+247` | 8 | opaque driver/manager tail; retain raw bytes pending complete use-site map |
| `+248` | 4 | owning `BLFPController *`, used by `BLCCallback` |
| `+252` / `+256` | 4 each | controller queue next/previous links |

`allocSccb` clears the full 260-byte record at `0x1704`. `sccbFromCmd:` stores the CDB at `+18`, command record at `+236`, controller at `+248`, callback at `+40`, I/O base at `+44`, and SG descriptors at `+100`. `scsiInitSCCB` sets flag byte `+95`, copies length from `+4` to `+52`, clears `+56`, `+84`, and `+96` as appropriate, and sets message/state bytes `+72..+75`. These observations match the i386 manager access widths and rule out the current header's widened 32-bit manager flags/SG-count fields.

Boundary fixtures from `sccbFromCmd:` (`0x10c0`):

- `(virtual=0x10ffd, length=4)` gives two page chunks of 3 and 1 bytes; expect SG list at `SCCB+100`, lengths `{3,1}`, SG data byte size 16, and total mapped count 4 when both physical translations succeed.
- `(virtual=0x1000, length=18*4096)` plans 18 pages but emits at most 17 entries (17*4096 bytes); verify the residual remains 4096 after host transfer of those entries.
- Length zero uses opcode 3 and zero pointer/length. Invalid selected CDB control bits set request status 7 and skip manager submission. Failed sense physical conversion writes sense length 1 and continues; failed data conversion sets status 14 and returns an error.

Abort fixture (`SccbMgr_abort_sccb`, `0x484c`): `IN B+41` bit `0x08` causes unlock and `-1`. If `queueFindSccb` removes the queued command, decrement manager active count; when it reaches zero, do read/modify/write at `B+12` with `value & 0xfc`, set `SCCB+48=2`, then call callback at `SCCB+40`. If absent from both the active slot and 33 disconnected entries, return `-1`.



