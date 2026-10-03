# drvIntel82596 recovered ABI and reference notes

Reference image: `Intel82596NetworkDriver_reloc`, i386 little-endian, 69,108 bytes, SHA-256 `BE6AED4264AB64119188AEE6A82AAB415940010DCF5705B6C241266AF45D0A11`. IDA 9.4 reports 86 functions in `__text` (`0x0..0x4240`): 75 handwritten Objective-C methods, nine C helpers, and two server-generated methods. Address zero is the 146-byte `+[CogentEMaster probe:]`. Full decompilation, disassembly, signatures, and call edges are retained in ignored `tools/binrecon/out/intel82596/evidence/ida-functions.json`.

## Class and method ownership

The reference classes are `Intel82596 : IOEthernet`, `CogentEMaster : Intel82596`, `IntelEEFlash32 : Intel82596`, `IntelPRO10PCI : Intel82596`, and `Intel82596Buf : Object`. IDA's decoded `__instance_vars` section reports 38 `Intel82596` fields beginning at absolute object offset 372 (end offset 512), 10 buffer-pool fields beginning at offset 4 (end offset 40), three PRO10PCI fields beginning at offset 512, and no own fields on either EISA adapter. `Intel82596(Private)` owns 13 private methods. The base offset 372 also confirms the inherited `IOEthernet` instance layout used by this binary.

| Class | Offset | Field | Encoding |
|---|---:|---|---|
| Intel82596 | 372 | ioBase | `S` |
| | 376 | irq | `i` |
| | 380 | myAddress | six-byte `ether_addr_octet` struct |
| | 388 | chipRev | `i` |
| | 392 | networkInterface | `IONetwork *` |
| | 396 | bufferPool | `Intel82596Buf *` |
| | 400 | xmtQueue | `IONetbufQueue *` |
| | 404–409 | promiscuousEnabled, multicastEnabled, allMulticastEnabled, multicastConfigured, sourceAddressInsertion, resetAndEnabled | six `c` bytes |
| | 412 | sharedMemPtr | `void *` |
| | 416 | sharedMemSize | `I` |
| | 420 | sharedMemAllocPtr | `void *` |
| | 424 | sharedMemAvail | `I` |
| | 428 | sharedMem_actualPtr | `void *` |
| | 432 | sharedMem_actualSize | `I` |
| | 436 | scp | pointer to struct |
| | 440 | iscp | pointer to struct |
| | 444 | scb | pointer to struct |
| | 448 | selfTestArea | `void *` |
| | 452 | tcbList | pointer to struct |
| | 456 | headFreeTcb | pointer to struct |
| | 460 | activeTcbHead | pointer to struct |
| | 464 | pendingTcbHead | pointer to struct |
| | 468 | pendingTcbTail | pointer to struct |
| | 472 | kdbTcb | pointer to struct |
| | 476 | kdbPacketBuffer | `void *` |
| | 480 | kdbPacketPhysical | `I` |
| | 484 | rfdList | pointer to struct |
| | 488 | headRfd | pointer to struct |
| | 492 | tailRfd | pointer to struct |
| | 496 | rfdZeroSize | `I` |
| | 500 | rbdZeroSize | `I` |
| | 504 | tcbZeroSize | `I` |
| | 508 | fullDuplexMode | `c` |
| Intel82596Buf | 4 | initFlag | `c` |
| | 5 | freeInProgress | `c` |
| | 8 | freeList | `void *` |
| | 12 | numFree | `I` |
| | 16 | bufSize | `I` |
| | 20 | bufSizeUser | `I` |
| | 24 | bufCount | `I` |
| | 28 | memPtr | `void *` |
| | 32 | memSize | `i` |
| | 36 | freeListLock | `NXSpinLock *` |
| IntelPRO10PCI | 512 | connector | `i` |
| | 516 | RJ45Only | `c` |
| | 517 | autoDetectedPort | `c` |

The checked-in initial implementation has no shared headers or project hierarchy. It incorrectly imports `IOEthernetDriver.h`, declares a fabricated `Intel82596 : IOEthernetDriver` with offset comments that conflict with its order, duplicates adapter interfaces inside `.m` files, and contains fake `disableAllInterrupts`, debugger-lock, netbuf, timeout, run-state, power, and initializer stubs. Source-map hits are name-resolution evidence only; they do not establish body parity.

## Reference evidence inventory

`reconstruction/ledger.json` preserves every analyzer function range and symbol. `source-map.json` is generated with `--objc-methods` and without `--scope-to-objc`, so C functions and the address-zero probe remain visible. Binrecon's `analyzer_agreement.generated` means the analyzer generated a ledger row; it does not mean compiler-generated code. Only `+[Intel82596NetworkDriverKernelServerInstance kernelServerInstance]` at `0x4228` and `+[Intel82596NetworkDriverVersion driverKitVersionForIntel82596NetworkDriver]` at `0x4234` are generated-code exceptions.

Source function ownership by translation unit follows the five binary class groups. C symbols are linked with one Mach-O leading underscore removed: `__resetFunc` is `_resetFunc`; preserve external linkage for the reset callback and buffer callbacks, and internal linkage only where the reference symbol table says local.

## Recovered public signatures

These declarations are confirmed by selector encodings and call-site use; fixed-width integer arguments below are 32-bit in the i386 target. `BOOL` is one byte in Objective-C metadata but returns/arguments are passed using the target's ABI rules.

* `Intel82596Buf`: `-initWithRequestedSize:(unsigned int)requested actualSize:(unsigned int *)actual count:(unsigned int)count` returns the initialized object or `nil`; `-free`; `-getNetBuffer` returns a `netbuf_t`; `-numFree` returns an unsigned count.
* Kernel buffer callbacks: `_getNetBuffer(void *owner)` returns a netbuf; `_recycleNetbuf(void *owner, netbuf_t)` recycles or defers release according to pool lifetime.
* Reset callback: `_resetFunc(id driver)` has external C linkage and schedules `-[Intel82596 resetAndEnable:YES]`.
* Physical/memory helpers: `_IOIsPhysicallyContiguous(unsigned int virtualAddress, unsigned int length)` returns the last contiguous address (zero means failure); `_IOMallocPage(unsigned int size, unsigned int *physical)` and `_IOMallocNonCached(unsigned int size, unsigned int *physical)` return virtual addresses with physical output; `_card_irq(...)`, `_get_connector_type(...)`, and `_set_connector_type(...)` use the bus resource helpers recorded by their IDA call sites.

## Hardware and ownership invariants to verify during implementation

The controller uses SCP/ISCP/SCB, command blocks, TCB/TBD transmit chains and RFD/RBD receive chains. Addresses stored in controller-visible descriptors are physical addresses. TCB/RFD links are target 32-bit pointers or physical fields according to descriptor role, never host-sized pointers. Ethernet addresses are six bytes in wire order. The receive pool stores its owner/callback metadata in a wrapper prefix and returns a netbuf view; the wrapper must not refer back to a destroyed pool after shutdown. The target callback is `recycleNetbuf(data, size, context)`: kernel `m_free` calls `ext_free(ext_buf, ext_size, ext_arg)` in `src/kernel-7/bsd/kern/uipc_mbuf.c`. Transmit completion owns and releases the queued netbuf; failure paths must clear the TCB's retained packet pointer exactly once.

Task-derived checkpoints (the exact instruction/call-site references are in the JSON IDA export):

| Checkpoint | Reference behavior to assert | Primary function |
| --- | --- | --- |
| Pool page packing | Capacity is at least 1516 bytes, rounded to four bytes; prefix/guard and stride are included before page packing. Three requested 1514-byte buffers yield capacity 1516, stride 1540, four slots across aligned 4096-byte pages. 1517 yields capacity 1520, stride 1544. 4072 gives stride 4096; 4073 exceeds a page and follows the failure path. | `Intel82596Buf` initializer at `0x2cf8` |
| Outstanding wrapper shutdown | Mark the pool as shutting down while holding the pool lock; outstanding wrappers recycle without dereferencing freed pool state. Release each allocation once after the final wrapper returns. | `Intel82596Buf free` at `0x2e90`, `_recycleNetbuf` at `0x2c48` |
| Descriptor links | RFD/TBD/TCB fields have explicit 16/32-bit widths and sentinel values; links and physical addresses are translated separately. | `_initRfdList` at `0x714`, `_initTcbList` at `0x9b4`, `_transmitPacket:` at `0x1044` |
| Shared IRQ | Probe the adapter-specific pending/latch state before acknowledging or dispatching; unrelated devices sharing a level IRQ are not consumed. | Adapter `interruptOccurred` methods at `0x241c`, `0x3390`, `0x3f7c` |
| Reset/timeouts | Disable adapter interrupts, stop/abort units, acknowledge pending causes, restore queues and restart units in reference order; bound all polling loops. | `resetAndEnable:` at `0x154c`, `_scheduleReset` at `0xdf0`, `_waitScb` at `0x12f8`, `_waitCu:` at `0x1270` |
| Debugger restore | Inspect binary branches and call edges before implementing; the reference public method set has no debugger-lock selector, so don't add one. | `-[Intel82596 free]` at `0x1428`, reset/interrupt paths |

The raw IDA export is the line-level evidence source for refining these summaries and recording exact selector argument types and state offsets. Hardware I/O register traces are reviewed per adapter in their task evidence; tests must intercept the port-access boundary and never execute native port instructions.

### Task 2 function review: pool and allocation paths

The four buffer methods and five pool/allocation helpers were checked against their full IDA pseudocode and disassembly. Their control-flow contracts are:

* `IOIsPhysicallyContiguous` (`0x33c`, global C symbol): examines each page boundary in the inclusive requested range, translates the boundary and prior byte, returns zero on either translation failure, the byte before the first discontinuity, or the inclusive range end if contiguous.
* `IOMallocPage` (`0x3c8`, global): requests `2 * size`, publishes that backing size, returns zero on allocation failure, otherwise retains the original pointer and returns its next page-aligned address.
* `IOMallocNonCached` (`0x408`, global): requests `page_size + round_up(size, page_size)`, stores size and backing pointer before testing allocation success, and returns the aligned interior pointer or zero.
* `getNetBuffer` (`0x2b6c`, global): reads the freelist head then locks; empty unlocks and returns null. A hit pops/decrements under lock, unlocks, checks both guards, creates the three-argument recycle callback wrapper over the payload, stores the wrapper at node offset 8, and restores the node under lock if wrapper allocation fails.
* `recycleNetbuf` (`0x2c48`, local): checks both guards before examining the shutdown byte at pool offset 5. Normal release pushes the node and increments the count while locked. During shutdown it increments only the outstanding count under lock; if it reaches `bufCount`, it calls pool `free` after unlocking.
* Pool initialization (`0x2cf8`): repeated init returns self. First init sets its byte flag, creates `NXSpinLock`, chooses `max(requested, 1514)`, rounds capacity to four, reports actual capacity, uses a 24-byte per-slot overhead, panics if a slot exceeds page size, allocates whole pages based on slots per page and requested count, then enumerates each page without allowing a slot to cross its boundary. Every slot stores owner, `0xCAFE2BAD` start/end guards and a null wrapper; list/count changes are individually locked.
* Pool free (`0x2e90`): first call marks shutdown under lock. If wrappers remain, it returns self without freeing storage or lock. A later call after the last wrapper returns frees the lock, frees the original allocation and logs delayed completion before superclass free. Immediate free uses the same lock/allocation release order but has no delayed-free log.
* `getNetBuffer` method (`0x2f48`) is a direct C-helper forwarder. `numFree` (`0x2f58`) returns the field directly; it does not lock.

Descriptor list extents are instruction-confirmed: the receive list is 16 records at 64-byte stride (`0x400` bytes); each record contains its embedded 24-byte receive buffer descriptor at byte offset 40. The transmit list is eight 108-byte TCBs (`0x360` bytes), each containing three 24-byte TBDs at offsets 32, 56 and 80 and the retained netbuf at offset 104. `_initRfdList` translates fields at record offsets 0/36 and 40/60, and `_initTcbList` translates TCB offset 0/28 and TBD offsets `+32/+44` and `+52/+48`; preserve the exact source/destination pairs when implementing.

The source spells the four local helpers in C with exactly the binary linkage: `recycleNetbuf`, `card_irq`, `get_connector_type`, and `set_connector_type` are file-local. `IOIsPhysicallyContiguous`, `IOMallocPage`, `IOMallocNonCached`, `getNetBuffer`, and `_resetFunc` are global. `getNetBuffer` is declared from the Objective-C pool method and uses the class's recovered offsets through the 40-byte i386 pool mirror.

## Function index and IDA prototypes

These IDA prototype strings include hidden Objective-C `self` and `_cmd`; selector-facing declarations must account for those two ABI arguments. They are signature evidence, not body review.

| Address | Bytes | Symbol | IDA prototype | Kind |
|---:|---:|---|---|---|
| `0x0` | 146 | `+[CogentEMaster probe:]` | `char __cdecl(id, SEL, id)` | Objective-C |
| `0x94` | 565 | `-[CogentEMaster initFromDeviceDescription:]` | `id __cdecl(CogentEMaster *self, SEL, id)` | Objective-C |
| `0x2cc` | 33 | `-[CogentEMaster clearIrqLatch]` | `void __cdecl(CogentEMaster *self, SEL)` | Objective-C |
| `0x2f0` | 27 | `-[CogentEMaster sendChannelAttention]` | `void __cdecl(CogentEMaster *self, SEL)` | Objective-C |
| `0x30c` | 48 | `-[CogentEMaster sendPortCommand:with:]` | `void __cdecl(CogentEMaster *self, SEL, int, unsigned int)` | Objective-C |
| `0x33c` | 138 | `_IOIsPhysicallyContiguous` | `unsigned int __cdecl(int, int)` | C |
| `0x3c8` | 61 | `_IOMallocPage` | `int __cdecl(int, int *, _DWORD *)` | C |
| `0x408` | 77 | `_IOMallocNonCached` | `int __cdecl(int, int *, int *)` | C |
| `0x458` | 70 | `-[Intel82596 _recAllocateNetbuf]` | `$199DFB5D1DF31DC82E78091AC4DEC886 *__cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x4a0` | 60 | `__resetFunc` | `id __cdecl(id)` | C |
| `0x4dc` | 191 | `-[Intel82596 _abortReceiveUnit]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x59c` | 375 | `-[Intel82596 _init596]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x714` | 672 | `-[Intel82596 _initRfdList]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x9b4` | 507 | `-[Intel82596 _initTcbList]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0xbb0` | 56 | `-[Intel82596 _memAlloc:]` | `void *__cdecl(Intel82596 *self, SEL, unsigned int)` | Objective-C |
| `0xbe8` | 520 | `-[Intel82596 _resetAndSelfTest]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0xdf0` | 100 | `-[Intel82596 _scheduleReset]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0xe54` | 234 | `-[Intel82596 _startCommandUnit]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0xf40` | 257 | `-[Intel82596 _startReceiveUnit]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1044` | 554 | `-[Intel82596 _transmitPacket:]` | `void __cdecl(Intel82596 *self, SEL, $199DFB5D1DF31DC82E78091AC4DEC886 *)` | Objective-C |
| `0x1270` | 134 | `-[Intel82596 _waitCu:]` | `char __cdecl(Intel82596 *self, SEL, unsigned int)` | Objective-C |
| `0x12f8` | 86 | `-[Intel82596 _waitScb]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1350` | 75 | `-[Intel82596 serviceTransmitQueue]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x139c` | 137 | `-[Intel82596 acknowledgeInterrupts:]` | `char __cdecl(Intel82596 *self, SEL, unsigned __int16)` | Objective-C |
| `0x1428` | 291 | `-[Intel82596 free]` | `id __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x154c` | 173 | `-[Intel82596 resetAndEnable:]` | `char __cdecl(Intel82596 *self, SEL, char)` | Objective-C |
| `0x15fc` | 7 | `-[Intel82596 clearIrqLatch]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1604` | 156 | `-[Intel82596 hwInit]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x16a0` | 115 | `-[Intel82596 swInit]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1714` | 613 | `-[Intel82596 coldInit]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x197c` | 919 | `-[Intel82596 processRecInterrupt]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1d14` | 452 | `-[Intel82596 processXmtInterrupt]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1ed8` | 215 | `-[Intel82596 setThrottleTimers]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x1fb0` | 375 | `-[Intel82596 config]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x2128` | 291 | `-[Intel82596 iaSetup]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x224c` | 461 | `-[Intel82596 mcSetup]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x241c` | 120 | `-[Intel82596 interruptOccurred]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x2494` | 127 | `-[Intel82596 transmit:]` | `void __cdecl(Intel82596 *self, SEL, $199DFB5D1DF31DC82E78091AC4DEC886 *)` | Objective-C |
| `0x2514` | 47 | `-[Intel82596 timeoutOccurred]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x2544` | 42 | `-[Intel82596 enablePromiscuousMode]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x2570` | 39 | `-[Intel82596 disablePromiscuousMode]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x2598` | 22 | `-[Intel82596 enableMulticastMode]` | `char __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x25b0` | 75 | `-[Intel82596 disableMulticastMode]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x25fc` | 65 | `-[Intel82596 addMulticastAddress:]` | `void __cdecl(Intel82596 *self, SEL, $D91DDCA3822F03E96939068EA8DE741A *)` | Objective-C |
| `0x2640` | 58 | `-[Intel82596 removeMulticastAddress:]` | `void __cdecl(Intel82596 *self, SEL, $D91DDCA3822F03E96939068EA8DE741A *)` | Objective-C |
| `0x267c` | 589 | `-[Intel82596 receivePacket:length:timeout:]` | `void __cdecl(Intel82596 *self, SEL, void *, unsigned int *, unsigned int)` | Objective-C |
| `0x28cc` | 521 | `-[Intel82596 sendPacket:length:]` | `void __cdecl(Intel82596 *self, SEL, void *, unsigned int)` | Objective-C |
| `0x2ad8` | 21 | `-[Intel82596 setIOBase:]` | `void __cdecl(Intel82596 *self, SEL, unsigned __int16)` | Objective-C |
| `0x2af0` | 7 | `-[Intel82596 sendChannelAttention]` | `void __cdecl(Intel82596 *self, SEL)` | Objective-C |
| `0x2af8` | 7 | `-[Intel82596 sendPortCommand:with:]` | `void __cdecl(Intel82596 *self, SEL, int, unsigned int)` | Objective-C |
| `0x2b00` | 12 | `-[Intel82596 getPowerState:]` | `int __cdecl(Intel82596 *self, SEL, int *)` | Objective-C |
| `0x2b0c` | 72 | `-[Intel82596 setPowerState:]` | `int __cdecl(Intel82596 *self, SEL, int)` | Objective-C |
| `0x2b54` | 12 | `-[Intel82596 getPowerManagement:]` | `int __cdecl(Intel82596 *self, SEL, int *)` | Objective-C |
| `0x2b60` | 12 | `-[Intel82596 setPowerManagement:]` | `int __cdecl(Intel82596 *self, SEL, int)` | Objective-C |
| `0x2b6c` | 219 | `_getNetBuffer` | `int __cdecl(int)` | C |
| `0x2c48` | 173 | `_recycleNetbuf` | `id __cdecl(int, int, int *)` | C |
| `0x2cf8` | 408 | `-[Intel82596Buf initWithRequestedSize:actualSize:count:]` | `Intel82596Buf *__cdecl(Intel82596Buf *self, SEL, unsigned int, unsigned int *, unsigned int)` | Objective-C |
| `0x2e90` | 184 | `-[Intel82596Buf free]` | `id __cdecl(Intel82596Buf *self, SEL)` | Objective-C |
| `0x2f48` | 16 | `-[Intel82596Buf getNetBuffer]` | `$199DFB5D1DF31DC82E78091AC4DEC886 *__cdecl(Intel82596Buf *self, SEL)` | Objective-C |
| `0x2f58` | 13 | `-[Intel82596Buf numFree]` | `unsigned int __cdecl(Intel82596Buf *self, SEL)` | Objective-C |
| `0x2f68` | 80 | `_card_irq` | `int __cdecl(unsigned int)` | C |
| `0x2fb8` | 20 | `_get_connector_type` | `int __cdecl(__int16)` | C |
| `0x2fcc` | 55 | `_set_connector_type` | `unsigned __int8 __cdecl(__int16, char)` | C |
| `0x3004` | 151 | `+[IntelEEFlash32 probe:]` | `char __cdecl(id, SEL, id)` | Objective-C |
| `0x309c` | 676 | `-[IntelEEFlash32 initFromDeviceDescription:]` | `id __cdecl(IntelEEFlash32 *self, SEL, id)` | Objective-C |
| `0x3340` | 80 | `-[IntelEEFlash32 clearIrqLatch]` | `void __cdecl(IntelEEFlash32 *self, SEL)` | Objective-C |
| `0x3390` | 188 | `-[IntelEEFlash32 interruptOccurred]` | `void __cdecl(IntelEEFlash32 *self, SEL)` | Objective-C |
| `0x344c` | 563 | `-[IntelEEFlash32 doAutoConnectorDetect]` | `void __cdecl(IntelEEFlash32 *self, SEL)` | Objective-C |
| `0x3680` | 167 | `-[IntelEEFlash32 checksum_OK:]` | `char __cdecl(IntelEEFlash32 *self, SEL, unsigned int)` | Objective-C |
| `0x3728` | 27 | `-[IntelEEFlash32 sendChannelAttention]` | `void __cdecl(IntelEEFlash32 *self, SEL)` | Objective-C |
| `0x3744` | 48 | `-[IntelEEFlash32 sendPortCommand:with:]` | `void __cdecl(IntelEEFlash32 *self, SEL, int, unsigned int)` | Objective-C |
| `0x3774` | 671 | `+[IntelPRO10PCI probe:]` | `char __cdecl(id, SEL, id)` | Objective-C |
| `0x3a14` | 80 | `-[IntelPRO10PCI _setConnectorType:]` | `void __cdecl(IntelPRO10PCI *self, SEL, int)` | Objective-C |
| `0x3a64` | 585 | `-[IntelPRO10PCI doAutoConnectorDetect]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x3cb0` | 713 | `-[IntelPRO10PCI initFromDeviceDescription:]` | `id __cdecl(IntelPRO10PCI *self, SEL, id)` | Objective-C |
| `0x3f7c` | 158 | `-[IntelPRO10PCI interruptOccurred]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x401c` | 28 | `-[IntelPRO10PCI clearIrqLatch]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x4038` | 77 | `-[IntelPRO10PCI initPLXchip]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x4088` | 67 | `-[IntelPRO10PCI resetPLXchip]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x40cc` | 48 | `-[IntelPRO10PCI sendPortCommand:with:]` | `void __cdecl(IntelPRO10PCI *self, SEL, int, unsigned int)` | Objective-C |
| `0x40fc` | 31 | `-[IntelPRO10PCI sendChannelAttention]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x411c` | 31 | `-[IntelPRO10PCI _enableAdapterInterrupts]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x413c` | 31 | `-[IntelPRO10PCI _disableAdapterInterrupts]` | `void __cdecl(IntelPRO10PCI *self, SEL)` | Objective-C |
| `0x415c` | 201 | `-[IntelPRO10PCI resetAndEnable:]` | `char __cdecl(IntelPRO10PCI *self, SEL, char)` | Objective-C |
| `0x4228` | 12 | `+[Intel82596NetworkDriverKernelServerInstance kernelServerInstance]` | `$8EF4127CF77ECA3DDB612FCF233DC3A8 **__cdecl(id, SEL)` | Objective-C |
| `0x4234` | 12 | `+[Intel82596NetworkDriverVersion driverKitVersionForIntel82596NetworkDriver]` | `int __cdecl(id, SEL)` | Objective-C |
