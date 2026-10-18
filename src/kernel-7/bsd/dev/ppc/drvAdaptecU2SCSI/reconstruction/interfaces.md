# Ultra2 ABI recovery evidence

The frozen reference identity and all 476 body identities are
in `inventory.md`. No ledger entry is promoted by a header or layout check.

## First reviewed declaration batch

All 381 normal CHIM declarations are now individually reviewed. The eleven input-erased declarations
are separately accounted below. `signatures.json` binds every declaration to
its individual evidence row and frozen owner. Target layout and callback
checks are in `tests/layout-checks.m`; `tests/layout-contracts.json` distinguishes
exact extents from accessed prefixes whose original trailing extent is unknown.

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIGetFunctionPointers(HIMFunctions *, unsigned int)` returning void | `0x1a3d04` | `0x187c40` supplies self+`0x4cc`, `0xa8`; `0x1a3d10..0x1a3d24` preserves destination/count into fast_bcopy's arguments. |
| `SCSIGetNextHostDeviceType(unsigned int, unsigned int *, unsigned int *)` returning product-ID word | `0x1a3d38` | `0x187dfc` supplies an incremented index and two word destinations; body bounds index with unsigned comparison against39, loads two words per entry, writes bus type0/mask, and returns the product ID compared with metadata-unsigned `productID` by caller. |
| `SCSICreateInitializationTSCB(InitializationTSCB *)` returning the same pointer | `0x1a3d80` | `0x187d68` passes `initializationTSH`; callee writes tag0 at+0, five0x48-byte tables at+4/+0x4c/+0x94/+0xdc/+0x124, and configuration at+0x16c; explicit final pointer return. Storage belongs to caller. |
| `SCSIGetConfiguration(InitializationTSCB *, Configuration *, unsigned int)` returning void | `0x1a3eb4` | Indirect caller `0x187e9c` supplies initializationTSH, self+0x25c, metadata-unsigned productID in r3/r4/r5. Callee uses first two and copies0x44 bytes; observed unused productID retained. |
| `SCSISetConfiguration(InitializationTSCB *, Configuration *, unsigned int)` returning status word | `0x1a3edc` | Caller `0x187ef4` supplies the same three typed fields. Callee reads/mutates unsigned configuration.maxInternalIOBlocks, checks maxInternalIOBlocks/iobReserveSize/memoryMapped, copies0x44 bytes, returns0 or7. Configuration is mutable, not const. |
| `SCSISizeAdapterTSCB(InitializationTSCB *, unsigned int)` returning size word | `0x1a4034` | Caller `0x187f0c` supplies initializationTSH/productID and consumes result as tscbSize/IOMalloc size; complete body returns2600. Observed caller inputs are retained despite the callee not reading them. |
| `SCSISizeTargetTSCB(AdapterTSCB *)` returning size word | `0x1a4940` | Caller `0x18b030` supplies adapterTSH and consumes size for target-block allocation; complete body returns40. |
| `SCSISetupAdapterTSCB(AdapterTSCB *, const OSMFunctions *, unsigned int)` returning status word | `0x1a4138` | Caller `0x187f84` supplies adapterTSH, OSMRoutines,0x7c. Callee copies the supplied byte count to adapter+0x618 and returns0. Caller retains the services table; callee owns a copy inside its supplied adapter storage. |

The status declarations describe observed full r3 words whose values are
listed above; they do not assert an original typedef spelling. Pointer
declarations follow concrete dereferences, copy operands, and ownership,
not untyped decompiler integer annotations.

The memory-table entries are12 bytes: byte category at+0, byte alignment
mask at+1, unclassified byte+2, byte granularity at+3, unsigned halfword
size/minimum size at+4/+6, and allocation pointer at+8. Evidence:
`SCSICheckMemoryNeeded` (`0x1a4168`) indexes12*entry, zero-extends bytes and
halfwords to output words, and `SCSISetMemoryPointer` (`0x1a433c`) stores
the supplied pointer at+8 and size at+4. `SCSIRGetMemoryTable` (`0x1a24a0`)
writes the descriptor fields at offsets36 and60 for entries3 and5.
The five-table initialization layout has size0x1b0 and config offset0x16c.

## Second reviewed declaration batch

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSICreateAdapterTSCB(InitializationTSCB *, AdapterTSCB *, OSMContext, PciLocation, unsigned int)` returning supplied adapter storage | `0x1a4044` | Caller `0x187f64` passes initialization, allocated storage, controller context, four location words in r6..r9, and product ID in r10. Callee stores context at adapter+0x694, location words at +8/+12/+16/+20, product at +4, and returns storage. The location is one16-byte value, not four independent formal integers. |
| `SCSICheckMemoryNeeded(InitializationTSCB *, AdapterTSCB *, unsigned int, unsigned int, unsigned int *, unsigned int *, unsigned int *, unsigned int *)` returning byte size | `0x1a4168` | Caller `0x188184` passes initialization, adapter, product, index, and four local word addresses in r3..r10. Callee selects initialization tables when adapter is null, otherwise adapter+0x5d0, indexes12*index, zero-extends descriptor fields to the four output words, and returns size. |
| `SCSISetMemoryPointer(AdapterTSCB *, unsigned int, unsigned int, unsigned char *, unsigned int)` returning status word | `0x1a433c` | Caller `0x188248` supplies adapter, index, category, aligned allocation pointer, and full word size. No caller truncation precedes r7; callee truncates only when storing descriptor+4 via sth. Other branches store addresses at adapter+0x9e0/+0x9e4. Index beyond7 returns1; otherwise0. |
| `SCSIVerifyAdapter(AdapterTSCB *)` returning status word | `0x1a439c` | `0x187f98` supplies adapterTSH. Callee consumes adapter fields and its embedded OSM table, returning a status checked against zero by caller. It does not consume additional caller inputs. |
| `SCSIInitialize(AdapterTSCB *)` returning status word | `0x1a4644` | `0x1880b0` supplies adapterTSH; body passes adapter+24 to the resource/hardware initialization chain and returns a normalized word status, checked at the caller. |
| `SCSICheckTargetTSCBNeeded(AdapterTSCB *, unsigned int)` returning Boolean word | `0x1a4950` | HIM slot13; callee consumes r3 as adapter and r4 as an index compared with0xffff. It compares old/current LUN bitmaps at adapter+0x6dc/+0x75c and returns normalized0/1. |
| `SCSICreateTargetTSCB(AdapterTSCB *, unsigned int, TargetTSCB *)` returning target pointer or null | `0x1a4a64` | Caller `0x18b0a0` supplies adapter,0xffff, and allocated target storage. Callee writes tag2, adapter pointer, target ID, LUN and flags at offsets0/4/8/12/16, then initializes the unit-control record at+20; returns supplied storage or null. The caller owns the allocation. |
| `SCSIClearTargetTSH(TargetTSCB *)` returning status word | `0x1a4cfc` | HIM slot23; callee reads target's adapter pointer at+4 and ID/LUN at+8/+12, checks device idle, clears both bitmap entries, and returns6 when busy or0 after clearing. It does not free target storage. |

`AdaptecU2OSMContext` is an intentionally opaque pointer passed unchanged
between CHIM and its callbacks. This is established by the controller pointer
at `0x187f38` and adapter store at `0x1a4044`'s +0x694 access, not a generic
fallback for unknown argument types. PCI location member names are absent
from metadata; the union records the proven four-word extent/argument order.

## Third reviewed declaration batch

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIDisableIRQ(AdapterTSCB *)` returning void | `0x1a4c04` | HIM word 15; controller calls `0x18809c` and `0x18b35c` supply adapterTSH and discard r3. Body adds 24 to the adapter and invokes `SCSIHDisableIRQ` at `0x19d8dc`, which clears HCNTRL bit 1 through the OSM accessor and synchronizes. No caller observes a return value. |
| `SCSIEnableIRQ(AdapterTSCB *)` returning void | `0x1a4c28` | HIM word 16; calls `0x1880fc` and `0x18b3a0` supply adapterTSH and discard r3. Body invokes `SCSIHEnableIRQ` at `0x19d944` with adapter+24, sets HCNTRL bit 1, and synchronizes. |
| `SCSIPollIRQ(AdapterTSCB *)` returning Boolean word | `0x1a4c4c` | HIM word 17; body forwards adapter+24 to `SCSIHPollIRQ` at `0x19d9ac`. That callee reads INTSTAT through the embedded IOHandle, masks its low four bits, and the public wrapper normalizes the result to 0/1 at `0x1a4c60..0x1a4c64`. |
| `SCSIPowerEvent(AdapterTSCB *, unsigned int)` returning status word | `0x1a4c78` | HIM word 21. The adapter is adjusted by 24 at `0x1a4c84`. r4 is forwarded unchanged into `SCSIRPowerManagement`, saved at `0x1a2e3c`, and restored at `0x1a2e58` before `SCSIHPowerManagement`. The terminal callee and `SCSIHCheckHostIdle` (`0x19db8c..0x19dbd8`) never read r4. The second parameter is an opaque 32-bit ABI carrier under the controller ruling, with no original semantic type or signedness claim. Return is 1/2; no allocation or ownership transfer. |
| `SCSIValidateTargetTSH(TargetTSCB *)` returning status word | `0x1a4c9c` | HIM word 22; caller `0x18ad6c` supplies an attached target's TSH and compares the result with 2. The wrapper forwards to `SCSIxNonScamValidateLun`, which reads target+4/+8 as adapter/ID, checks the adapter bitmap with LUN 0, and returns 0/2. |
| `SCSIProfileAdapter(AdapterTSCB *, AdapterProfile *)` returning status word | `0x1a4d90` | HIM word 26; caller `0x188014` supplies adapterTSH and self+0x2ac, whose profile type is preserved in Objective-C metadata. Body copies 464 bytes from the default profile, writes named fields and union words through r4, and returns 0. Destination belongs to caller. |
| `SCSIReportAdjustableAdapterProfile(AdapterTSCB *, AdapterProfile *)` returning status word | `0x1a5170` | HIM word 27; body copies 464 bytes from the adjustable profile, reads adapter byte+43, conditionally clears profile words+144/+148/+152, and returns 0. Destination belongs to caller. |
| `SCSIAdjustAdapterProfile(AdapterTSCB *, const AdapterProfile *)` returning status word | `0x1a51d0` | HIM word 28; caller `0x18803c` supplies adapterTSH and the same metadata profile, checks status 0/1/2, and retains the profile. Callee reads profile words/bytes, updates adapter LUN counts and hardware information, performs no profile stores, and returns 0/2/7. |

`AdaptecU2AdapterProfile` preserves all 54 metadata-named leaf fields,
including the nested five-field `AP_SCSITargetOptTmFunctions`. Their target
offsets are 0, 4, 8, then 40 through 240 in steps of four. The final `himu`
union begins at 244 (`0xf4`); its original member names are absent from the
encoding. Its 220-byte storage is preserved as words/bytes without inventing
member semantics. Total size 464 is independently established by both copy
counts and the next controller ivar. The historical PPC layout object proves
every named leaf offset, union offset, and total size. The final shared storage section below closes the other layout views and
records their extent limitations.

## Fourth reviewed declaration batch

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIFrontEndISR(AdapterTSCB *)` returning Boolean word | `0x1a62cc` | HIM word 18; caller `0x18b2fc` supplies adapterTSH and tests r3 for zero. Body reads IOHandle at adapter+32, operates on the embedded HHCB at+24, and normalizes its result at `0x1a64bc..0x1a64c0`. |
| `SCSIProfileTarget(TargetTSCB *, TargetProfile *)` returning status word | `0x1a5520` | HIM word 29; caller `0x18b0bc` supplies the newly created target TSH and attached-target storage+16. Body reads target+4/+11/+12, copies 124 bytes, writes profile words through offset 120, and returns 0. |
| `SCSIReportAdjustableTargetProfile(unsigned int, TargetProfile *)` returning status word | `0x1a56c4` | HIM word 30 has no controller caller. Incoming r3 is overwritten at `0x1a56d0`; r4 is the destination of the 124-byte copy at `0x1a56dc`. Return is 0. The first position is an opaque discarded machine word under the controller ruling; this two-word machine-compatible declaration does not claim the original unused formal's type or grouping. |
| `SCSIAdjustTargetProfile(TargetTSCB *, const TargetProfile *)` returning status word | `0x1a56f4` | HIM word 31; caller `0x18b108` supplies target TSH and the same profile after modifying its word at+88. Callee reads target adapter/ID, checks idle, consumes profile fields at+60/+68/+88/+100/+112/+120 without writing the profile, updates device/hardware state, and returns 0/6. |
| `SCSIGetNVSize(AdapterTSCB *)` returning size word | `0x1a5a00` | HIM word 32; body reads the embedded OSM size callback at adapter+1584, supplies context at+1684, and otherwise obtains EEPROM size from `SCSIHSizeSEEPROM` (`0x19cb4c`). It scales that size using adapter+1400 and returns it. |
| `SCSIGetNVOSMSegment(AdapterTSCB *, unsigned int *, unsigned int *)` returning status word | `0x1a5ad4` | HIM word 33; body preserves r4/r5 as word-output addresses, reads a 32-halfword EEPROM segment, and stores byte offset/size through those addresses. Return 2 on unavailable/error branches, 0 on successful output. Neither output allocation is retained. |
| `SCSIPutNVData(AdapterTSCB *, unsigned int, const unsigned short *, unsigned int)` returning status word | `0x1a5ce8` | HIM word 34; preserves incoming r4/r5/r6 at `0x1a5d10..0x1a5d18`, invokes OSM with adapter context, then on status 3 supplies logical-right-shifted byte offset/count and the preserved data pointer to `SCSIHWriteSEEPROM` at `0x1a5d44`. The callee loads unsigned halfwords from that pointer at stride two. Buffer is borrowed, never freed. |
| `SCSIGetNVData(AdapterTSCB *, unsigned short *, unsigned int, unsigned int)` returning status word | `0x1a5d70` | HIM word 35; preserves data pointer/byte offset/count from r4/r5/r6, invokes the OSM callback, and on nonzero status calls `SCSIHReadSEEPROM` (`0x19cc94`) with offset/count shifted right one. That callee stores halfwords at stride two. Return is normalized to 0/1; destination remains caller-owned. |

Target-profile storage is 31 words, total 124 bytes. The copy and last word
store at `0x1a569c` establish its extent; member names are not available in
metadata and are not inferred from unrelated header versions. The typed
word-storage representation preserves observed accesses. Public NV buffer
order differs between Get and Put; their offset/count units are bytes, while
the EEPROM callees consume halfword indices/counts. Odd low bits are dropped
by the reference logical shifts, not rejected by this interface.

## Remaining public dispatch bodies

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIBackEndISR(AdapterTSCB *)` returning void | `0x1a64ec` | HIM word 19; caller `0x18b318` supplies adapterTSH and discards r3. Body reads adapter+32/+244, operates on embedded HHCB+24 and completion queues, invokes completion callbacks, and has no uniform result assignment before its epilogue. No ownership of the adapter is transferred. |
| `SCSIQueueIOB(IOB *)` returning void | `0x1a5e60` | HIM word 20; calls `0x18a5fc`, `0x18a858`, `0x18ab9c`, `0x18ae74`, `0x18af38`, and `0x189ccc` supply the allocated IOB and discard r3. Entry reads IOB reserve+8, transport-specific extension+28, task-set handle+40, stores the IOB backlink in reserve+84, then queues its HIOB or invokes the IOB's callback at+52. The IOB remains outstanding until callback completion; this call does not free it. |

All 41 HIM callbacks plus the table getter now have reviewed declarations:
34 typed normal interfaces and eight input-erased table interfaces. The
three other input-erased entries are private CHIM functions.

## First private OSD declaration batch

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `OSDGetBusAddress(HHCB *, uchar category, const uchar *) -> uint` | `0x1a7b04` | `SCSIhSetAddressScratchBA32` calls at `0x18e080`, setting category 1 while retaining its incoming virtual pointer in r5. Wrapper loads context at HHCB+1660 and OSMGetBusAddress at+1552, masks r4 to eight bits at `0x1a7b1c`, and forwards unchanged r5. The third argument is required even though the decompiler's candidate omitted it. |
| `OSDAdjustBusAddress(HHCB *, uint *, uint) -> void` | `0x1a7b3c` | Caller `0x197688` supplies HHCB, a local bus-address word and increment 8. Wrapper loads OSMAdjustBusAddress at HHCB+1556 and shifts incoming r4/r5 into callback r3/r4 at `0x1a7b4c..0x1a7b50`. Caller reads the modified word; r3 is unused. |
| `OSDReadPciConfiguration(HHCB *, uchar) -> uint` | `0x1a7b70` | Caller `0x19234c` supplies HHCB and register 0x2c, preserving the returned config word. Wrapper reads context at+1660 and Dword callback at+1636, explicitly masks r4 to eight bits and forwards the word result. |
| `OSDWritePciConfiguration(HHCB *, uchar, uint) -> void` | `0x1a7ba8` | Caller `0x193408` explicitly prepares HHCB, register 12 and a full config value in r3/r4/r5. Wrapper masks r4 and invokes the Dword write callback at HHCB+1648 with unchanged r5. Its omitted decompiler argument is recovered from both caller and callback use. |
| `OSDGetSGList(HIOB *) -> BufferDescriptor *` | `0x1a77b4` | Callee loads the IOB backlink at HIOB+52 then returns IOB+68. Caller `0x197648` reads the descriptor's virtual pointer at+8 and bus address at+0; SCB builders also test its size word at+4. This is a descriptor pointer, not a direct SG element pointer. Ownership remains with the IOB. |
| `OSDGetHostAddress(HHCB *) -> PciLocation *` | `0x1a7ca4` | Body returns input-16. HHCB is embedded at adapter+24, so the result is adapter+8, the four-word PCI location installed by CreateAdapterTSCB. Caller `0x19259c` supplies its HHCB; other callers use the returned location to select host/channel behavior. No allocation or ownership transfer. |
| `OSDBuildSCB(HIOB *) -> void` | `0x1a6f64` | Caller `0x18b77c` supplies its HIOB. `0x1a6f70..0x1a6f88` loads IOB from HIOB+52 into r4, target TSCB from IOB+40 into r5, adapter from target+4 into r6, then calls adapter's builder at+1736 while retaining HIOB in r3. The four-argument builder contract is not a no-argument callback. Caller discards r3. |
| `OSDCompleteHIOB(HIOB *) -> void` | `0x1a77c8` | Caller `0x1a39c4` passes HIOB after writing status bytes. Callee obtains IOB from+52, maps successful status or invokes TranslateError, then explicitly supplies that IOB in r3 to its completion callback at IOB+52 (`0x1a780c`). Callback ownership may complete/release the IOB; this wrapper does not free it itself. |

These eight declarations bring the accepted normal CHIM total to 42;
339 normal private declarations remain. BufferDescriptor is the observed
three-word bus-address/size/virtual-address record, not a host-sized pointer
array. Its final target size/offset checks remain required.

## Second private OSD declaration batch

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `OSDStandard64BuildSCB(HIOB *, IOB *, TargetTSCB *, AdapterTSCB *) -> void` | `0x1a6f9c` | OSDBuildSCB prepares all four arguments at `0x1a6f70..0x1a6f88`; VerifyAdapter installs this builder in adapter+1736 for its firmware mode. Callee reads HIOB+24 for its SCB descriptor, IOB+8/+56/+60/+68/+72/+76/+104, target+11/+15, and adapter+1580 for address adjustment. It writes the selected SCB and flushes its cache; the caller observes no return. |
| `OSDSwapping32BuildSCB(HIOB *, IOB *, TargetTSCB *, AdapterTSCB *) -> void` | `0x1a7194` | Same dispatch preparation; callee additionally checks the adapter's per-ID device flags at+56+10*ID. It writes its 32-byte SCB view, adjusts the SG bus address by 8 where required, and flushes the SCB. The target/IOB/HIOB arguments are distinct pointer roles, not interchangeable decompiler integers. |
| `OSDStandardAdvBuildSCB(HIOB *, IOB *, TargetTSCB *, AdapterTSCB *) -> void` | `0x1a73c8` | Same dispatch; reads the same typed records, places target/LUN at SCB+1/+2, SG/counted address state at+8/+40/+44, and CDB or CDB address at+16. Uses adapter's address-adjust callback and flushes the destination. |
| `OSDSwappingAdvBuildSCB(HIOB *, IOB *, TargetTSCB *, AdapterTSCB *) -> void` | `0x1a75c0` | Same dispatch; checks adapter device flags, consumes IOB SG/CDB descriptors, writes target/LUN at SCB+12/+13, SG address at+16, CDB at+24, and control at+38 before flushing. |
| `OSDCompleteSpecialHIOB(HIOB *) -> void` | `0x1a7824` | Reads the IOB backlink at HIOB+52 and dispatches on IOB function+12. It updates IOB status/error fields and invokes IOB completion+52 with the IOB in r3; function 6 may then invoke OSDAsyncEvent with adapter+24 and event 7. It does not return a coherent status value or directly free the IOB. |
| `OSDAsyncEvent(HHCB *, uint event, ...) -> void` | `0x1a7bdc` | Subtracts 24 to obtain adapter, maps incoming event values, updates adapter flags at+2596, and calls OSMEvent at `0x1a7c90` with context, mapped event, and explicit zero in r5. Incoming event controls the switch; it is not an opaque unused word. Callers consume its effects, not r3. |

All 14 OSD-owner declarations are now reviewed. Together with the34 public
normal CHIM contracts these form the first48 reviewed normal declarations. The builder descriptions establish
their pointer contracts and some format evidence; they are not a claim that
every SCB field or behavioral path has been reconstructed.

## EEPROM and IRQ helper declaration batch

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhReadE2Register(uint address, const IOHandle *, uchar extendedAddress) -> ushort` | `0x19d220` | Caller `0x19ce14` supplies address, IOHandle pointer, and the zero-extended HHCB byte+223; it stores the result with `sthx`. Callee reads all eight handle words into OSM accessor arguments, selects an 8/10-bit address command, accumulates exactly 16 serial bits while masking to 0xfffe, and returns that unsigned halfword at `0x19d36c`. |
| `SCSIhWriteE2Register(uint address, ushort value, const IOHandle *, uchar extendedAddress) -> void` | `0x19d390` | Caller `0x19d170` explicitly loads the value with `lhzx`, extended-address flag with `lbz`, and passes the handle pointer in r5. Callee shifts/tests the 16 data bits and writes the EEPROM port through the borrowed handle; callers discard its incidental final r3. |
| `SCSIhSendE2Address(uint address, int bitCount, const IOHandle *) -> void` | `0x19d5d0` | Calls `0x19d054`, `0x19d264`, `0x19d3dc` supply command bits, count 8/10, and a handle pointer. Callee uses the count in a signed positive-count loop and variable shift, tests command bits, and performs serial writes; it does not mutate the handle record. Signed count is retained rather than replacing its comparisons with unsigned behavior. |
| `SCSIhWait2usec(uchar value, const IOHandle *) -> void` | `0x19d7e8` | Call `0x19d0b4` supplies 0x20 and the handle. Callee explicitly truncates r3 at `0x19d808`, polls the handle's register 30 and writes that byte three times. It consumes the pointer in r4, not a by-value handle at its own boundary. |
| `SCSIHDisableIRQ(HHCB *) -> void` | `0x19d8dc` | Public wrapper call `0x1a4c14` supplies adapter+24. Callee reads IOHandle pointer at HHCB+8, reads HCNTRL, invokes WriteHCNTRL with bit 1 cleared, and executes sync; caller ignores r3. |
| `SCSIHEnableIRQ(HHCB *) -> void` | `0x19d944` | Public wrapper `0x1a4c38` supplies HHCB. Same handle dereference, HCNTRL bit 1 set, then sync; no result consumer. |
| `SCSIHPollIRQ(HHCB *) -> uchar` | `0x19d9ac` | Wrapper `0x1a4c5c` supplies HHCB and normalizes its return. Callee tests HHCB flags+212 and reads either workaround INTSTAT or register 145 from the handle at+8, returning only bits 0..3. |
| `SCSIHPowerManagement(HHCB *, uint unusedEventWord) -> uint` | `0x19db4c` | Resource caller `0x1a2e54..0x1a2e5c` restores saved HHCB/event into r3/r4. Callee forwards HHCB to CheckHostIdle and returns 1/2; incoming r4 is never read by it or that terminal idle check. The second position is an explicit opaque discarded word, not a recovered source event type. |

These eight entries bring this initial group to56. IRQ/power helpers
retain their frozen owner assignments even though they share evidence with
public wrappers; no ownership is inferred from the helper's name prefix.

## Metadata-established controller layout

The reference `AdaptecU2SCSI.m` class record has superclass
`IOSCSIController`, inherited size `0x244`, and final instance size `0x5d0`.
It places `configuration` at `0x25c`, `profile` at `0x2ac`, `HIMFunc` at
`0x4cc`, and `iobQ`, `handleQ`, `commandQ` at `0x580`, `0x588`, `0x590`.
These queue names are metadata names; the draft's incoming/pending/
disconnected interpretation is not the reference contract.

Configuration is 17 four-byte fields, size `0x44`. The metadata gives names
and unsigned `I` versus signed `i` for every field, reproduced in
`AdaptecU2CHIMTypes.h`. `SCSIGetConfiguration` at `0x1a3eb4` copies exactly
`0x44` bytes from initialization-block offset `0x16c`; controller call
`0x187e9c` supplies `self+0x25c` as destination. Profile occupies `0x1d0`
bytes; `SCSIProfileAdapter` at `0x1a4d90` copies that amount from the default
profile, and `SCSIReportAdjustableAdapterProfile` at `0x1a5170` does likewise.

Method `registerHandlerForIRQ:` at `0x1878a8` has encoding `v8@4:8i12`,
therefore returns void and takes signed int. `createOSMIOBPool` at `0x188294`
has encoding `v4@4:8`, therefore returns void. `executeRequest:` at
`0x188498` accepts the private command record, not `IOSCSIRequest *`.
The latter is the first argument of the public buffer/client and memory
descriptor selectors. The four thread selectors remain in category
`AdaptecU2SCSIThread`, not the primary class.

## Dispatch envelopes and public getter

`SCSIFuncPtrs` at `0x27b398` is `0xa8` bytes: version word **4** followed
by 41 code pointers. `OSMRoutines` at `0x278054` is `0x7c` bytes: version
word **0** followed by 30 code pointers. Neither leading word is callable.
`HIMFunc`'s metadata names all 41 HIM slots but encodes each merely `^?`;
this encoding supplies no callback parameter types.

`SCSIGetFunctionPointers` at `0x1a3d04` receives destination in r3 and byte
count in r4, moves count to r5 and destination to r4, and calls
`fast_bcopy(SCSIFuncPtrs, destination, count)` at `0x1a3d24`.
It does not clamp the byte count to `0xa8`. Its sole direct reference is
the controller call at `0x187c40`, with `r3=self+0x4cc` and `r4=0xa8`.
Do not replace this public count-controlled copy with a fixed-length copy.

## Aggregate arguments and ownership

PPC aggregate arguments here are **by value**, including the bytes beyond
the eight argument registers. The apparent flat integer parameter lists in
the untyped decompiler are not accepted prototypes.

* `_allocOSMIOB`, Mach-O `__allocOSMIOB`, at `0x18b448`: caller
  `createOSMIOBPool` copies profile bytes `[0x20,0x1d0)` to caller stack
  `[r1+0x38,r1+0x1e8)` at `0x1882c0..0x1882cc`; it loads bytes
  `[0,0x20)` into r3..r10 at `0x1882d0..0x1882ec`. Call is `0x1882f0`.
  Thus aggregate home starts at entry-SP+`0x18`. The callee allocates an
  `0x50` frame; `0x18b460` reads entry-SP+`0x54`, the profile alignment
  mask at offset `0x3c`, and `0x18b464` reads entry-SP+`0xa0`, profile
  IOB-reserve size at offset `0x88`. It allocates and clears a `0xc8` IOB,
  allocates reserve-size plus alignment-mask bytes, aligns the resulting
  address, and returns the IOB pointer in r3. The owner inserts it into
  `iobQ` using IOB links at offsets `0xc0/0xc4`. A failed physical-address
  conversion returns null without freeing prior allocations; this is
  reference behavior, not a new cleanup contract.
* `_freeOSMIOB`, Mach-O `__freeOSMIOB`, at `0x18b528`: r3 is the IOB
  pointer and the following profile is by value. At `0x188980..0x18898c`
  the caller copies profile bytes `[0x1c,0x1d0)` to stack+`0x38`, then
  loads the first seven profile words into r4..r10 before `0x1889b0`.
  Callee loads entry-SP+`0x58` and +`0xa4`: the profile has shifted by one
  argument word. It releases the backing reserve at IOB+`0x6c`, page
  allocation at +`0x74`, then the `0xc8` IOB. Return r3 is not consumed.
* OSM register accessors also receive a **32-byte IO-handle aggregate**
  in r3..r10. `OSMReadUExact8` at `0x189db4` reads its separate offset
  from the next stack argument and returns a zero-extended byte. These
  are not eight unrelated integer parameters.

The Task 2 runner explicitly supports only up to eight scalar/pointer
arguments in r3..r10. Required later aggregate/OSM-accessor cases need a
reviewed extension that writes the parameter save area and overflow stack
arguments (including big-endian narrow-value positioning), and observes
matching callback aggregate arguments. Static layout checks cannot replace
those executions. This task does not silently truncate such cases to eight
registers.

## OSM service contracts

The OSM table is version 0 followed by 30 callbacks. The following entries
have been reviewed; the three input-erased service slots are separately
accounted below. Context arguments contain the original controller
pointer, copied into adapter+0x694 by CreateAdapterTSCB. A callback's incidental
final r3 contents are not treated as a result when all callers discard them
and the body has no coherent result assignment.

| OSM word | Declaration contract | Entry | Caller/callee evidence and ownership |
| ---: | --- | --- | --- |
| 1 | `MapIOHandle(context, uint barIndex, uint offset, uint length, uint unusedWord, uint accessMode, IOHandle *) -> uint status` | `0x189858` | Call `0x1a4460` explicitly supplies context, BAR index, 0, 256, 0, 2, and adapter+0x698 in r3..r9. Callee ignores r7, maps the BAR, allocates a 32-byte queue node, and copies all eight words into the caller's handle. Status is 0/1. Error paths leak the already allocated node; the reference behavior must not be redesigned during recovery. |
| 2 | `ReleaseIOHandle(context, IOHandle by value) -> uint status` | `0x189aa4` | Callee homes r4..r10, reads the final handle word at entry SP+0x38, unmaps using handle+8/+12/+20 when handle+16 is 1, removes the matching context.handleQ node, frees 32 bytes, and returns 0. The eight words match MapIOHandle's complete copy. It owns the stored allocation, not the by-value argument's caller storage. |
| 3 | `Event(context, uint event, uint unusedWord, ...) -> void` | `0x189b80` | `OSDAsyncEvent` explicitly supplies event in r4 and zero in r5 at `0x1a7c7c..0x1a7c90`. The callee switches on r4, manipulates controller state/IOBs, and never consumes incoming r5. The third position is a discarded machine word, with no original variadic/fixed-formal grouping claim. |
| 4 | `GetBusAddress(context, uint categoryWord, const uchar *virtualAddress) -> uint` | `0x189d10` | Calls `0x1a7f60`, `0x1a8040`, `0x1a8064`, `0x1a8760` supply context, category 1, and allocation pointers in r3/r4/r5. Callee passes r5 to IOPhysicalFromVirtual and returns the resulting physical word or 0. It ignores category and does not acquire the virtual allocation. |
| 5 | `AdjustBusAddress(uint *busAddress, uint offset) -> void` | `0x189d6c` | Calls `0x1a7118`, `0x1a72ac`, `0x1a735c`, `0x1a7540`, `0x1a7754` supply a word address and 0/8. Body loads/adds/stores that word at `0x189d70..0x189d78`. Callers consume the updated word, not r3. |
| 6 | `GetNVSize(context) -> uint` | `0x189d84` | Calls `0x1a5a2c` and `0x1a5b10` explicitly supply adapter context and test the result. Full body returns 0; input type follows those callers, not the empty callee. |
| 7 | `PutNVData(context, uint byteOffset, const ushort *data, uint byteCount) -> uint` | `0x189d94` | `0x1a5d28` supplies context in r3 and retains the public PutNVData's r4/r5/r6 values unchanged. Full body returns 3; typed forwarded positions preserve that observed machine interface without claiming erased original formal spellings. |
| 8 | `GetNVData(context, ushort *data, uint byteOffset, uint byteCount) -> uint` | `0x189da4` | `0x1a5db0` supplies context and retains GetNVData's data/offset/count in r4/r5/r6. Full body returns 1. As for Put, the caller establishes these typed positions despite erased callee use. |
| 9 | `ReadUExact8(IOHandle, uint offset) -> uchar` | `0x189db4` | Homes the handle's r3..r10 words, reads word offset at entry SP+0x38 (`0x189dbc`), and returns an unsigned byte loaded from base+offset. CHIM accessors load the same eight handle words before invoking it. |
| 10 | `ReadUExact16(IOHandle, uint offset) -> ushort` | `0x189de8` | Same argument positions; accessMode bit 1 selects `lhbrx` at `0x189e28`, otherwise `lhzx` at `0x189e30`; final `lhz` at `0x189e38` returns an unsigned halfword. |
| 11 | `ReadUExact32(IOHandle, uint offset) -> uint` | `0x189e44` | Same positions, word load versus byte-reversing word load selected by accessMode bit 1; returns all 32 bits. |
| 12 | `ReadStringUExact8(IOHandle, uint offset, uchar *, uint count, uint strideWords) -> void` | `0x189ea0` | Loads overflow words at entry SP+0x38/+0x3c/+0x40/+0x44. Unsigned count comparison at `0x189ed4`; byte destination increments by one, MMIO displacement increments by four times strideWords. |
| 13 | `ReadStringUExact16(IOHandle, uint offset, ushort *, uint count, uint strideWords) -> void` | `0x189f0c` | Same four overflow words at `0x189f44..0x189f50`; unsigned count loop, halfword destination stride two, MMIO stride four times the supplied word. Selects conversion helpers `0x189120/0x189174/0x1891a0` from mode bits. |
| 14 | `ReadStringUExact32(IOHandle, uint offset, uint *, uint count, uint strideWords) -> void` | `0x18a00c` | Overflow loads `0x18a044..0x18a050`; word destination stride four and the same MMIO stride rule. Conversion helpers `0x18914c/0x18918c/0x1891b0`. |
| 15 | `WriteUExact8(IOHandle, uint offset, uchar value) -> void` | `0x18a10c` | Offset at SP+0x38; value byte at SP+0x3f (`0x18a118`), the low byte of the next big-endian word slot. Byte MMIO store followed by `eieio` at `0x18a13c`. |
| 16 | `WriteUExact16(IOHandle, uint offset, ushort value) -> void` | `0x18a148` | Value loaded as a halfword at entry SP+0x3e (`0x18a150`), offset at+0x38. Mode bit 1 selects reversed versus native halfword store. `eieio` at `0x18a1a8`. |
| 17 | `WriteUExact32(IOHandle, uint offset, uint value) -> void` | `0x18a1b4` | Offset/value are full overflow words at SP+0x38/+0x3c; mode selects word byte order; store is followed by `eieio`. |
| 18 | `WriteStringUExact8(IOHandle, uint offset, const uchar *, uint count, uint strideWords) -> void` | `0x18a20c` | Four overflow word slots match the read-string interface. Reads source bytes at stride one, writes MMIO at four times strideWords, and executes `eieio` after each store. |
| 19 | `WriteStringUExact16(IOHandle, uint offset, const ushort *, uint count, uint strideWords) -> void` | `0x18a27c` | Same slots; source halfword stride two, mode-selected conversion helpers, MMIO stride rule, and per-store `eieio`. Source is borrowed and never written. |
| 20 | `WriteStringUExact32(IOHandle, uint offset, const uint *, uint count, uint strideWords) -> void` | `0x18a380` | Same slots; source word stride four, the three word conversion helpers, MMIO stride rule, and per-store `eieio`. |
| 22 | `Watchdog(context, void (*)(AdapterTSCB *), uint microseconds) -> void` | `0x18a4b0` | Loads context.adapterTSH at+0x2a8, moves callback r4 into ns_timeout's function argument, and multiplies unsigned r5 by 1000. `0x18a4ec..0x18a4f8` supplies adapter as callback argument, 64-bit nanoseconds in high/low r5/r6, and priority 4 in r7. The kernel ns_timeout contract returns void; no callback result is observed. |
| 25 | `ReadPCIConfigurationDword(context, uint offset) -> uint` | `0x1891bc` | Controller context receives `deviceDescription`; offset is aligned with full-word mask 0xfffffffc and passed to `configReadLong:value:`. Returns the full data word or 0 on error. Calls include adapter verification at `0x1a4494` and the HHCB wrapper `0x1a7b70`. |
| 26 | `ReadPCIConfigurationWord(context, uchar offset) -> ushort` | `0x189280` | Aligns the low offset byte at `0x1892b8`, shifts the returned config word by 8*(offset&3), and zero-extends its low halfword at `0x1892e4`. |
| 27 | `ReadPCIConfigurationByte(context, uchar offset) -> uchar` | `0x189364` | Same byte offset alignment, then zero-extends the selected byte at `0x1893c8`. |
| 28 | `WritePCIConfigurationDword(context, uchar offset, uint value) -> void` | `0x189448` | Mask at `0x189464` keeps only offset bits 2..7; the full r5 word is passed to `configWriteLong:value:`. Caller `0x1a4434` supplies context, offset 4 and the command word, discarding the return. Error logging has incidental r3 contents. |
| 29 | `WritePCIConfigurationWord(context, uchar offset, ushort value) -> void` | `0x18951c` | `0x189554` truncates data to 16 bits and `0x189564` truncates aligned offset to eight bits. Reads a config word, replaces the selected halfword, and writes it back. Read-error logging does not stop the subsequent write in the reference. |
| 30 | `WritePCIConfigurationByte(context, uchar offset, uchar value) -> void` | `0x1896bc` | `0x1896f4` truncates data to eight bits, `0x189704` truncates aligned offset, and the body replaces the selected byte in a read-modify-write. As for word writes, preserve the reference's continuation after a failed read. |

`AdaptecU2IOHandle` is eight words: volatile byte-addressed base, accessMode,
length, offset, mapped flag, mapping base, next and previous links at offsets
0/4/8/12/16/20/24/28. MapIOHandle writes all fields and its 32-byte copy,
ReleaseIOHandle reads/removes the queue links, and accessors distinguish MMIO
widths and byte order. Both BAR mapping branches set mapped to 1 in the
reference; the release behavior must be preserved even for that surprising
I/O-aperture branch. Pointer and aggregate layouts still require the final
target gate; no host sizeof is used as proof.

The historical PPC build of the IOHandle call witnesses establishes all eight
field offsets and size 32. Its write wrapper puts the offset at SP+0x38,
byte at+0x3f and halfword at+0x3e before loading the handle into r3..r10.
Its release wrapper keeps context in r3, loads seven handle words into
r4..r10, and stores the final word at SP+0x38. Mach-O branch relocations bind
those calls to OSMWriteUExact8, OSMWriteUExact16 and OSMReleaseIOHandle;
an unlinked-object disassembler's provisional local branch label is not the
callee identity. The same build proves the HIM table's 42 word offsets,
target-profile size 124, and all previously listed profile/configuration fields.

## Separate OSM formal-erasure set

The controller separately authorized the following exact three service
identities. They do not expand the eleven-entry CHIM exception set. Their
legacy unspecified-argument declarations expose observed r3 machine words,
without claiming original formal counts, grouping, or semantic return types.

| Service | Complete body range | OSM word / pointer address | Machine contract |
| --- | --- | --- | --- |
| OSMSynchronizeRange | `0x18a484..0x18a4b0` | 21 / `0x2780a8` | Creates a 32-byte frame, homes r3..r10 at entry SP+24/+28/+32/+36/+40/+44/+48/+52, restores r1, preserves r3, returns. These stack writes are required observable behavior. |
| OSMSaveInterruptState | `0x18a50c..0x18a51c` | 23 / `0x2780b0` | Creates/restores a 32-byte frame and returns r3=0. |
| OSMSetInterruptState | `0x18a51c..0x18a528` | 24 / `0x2780b4` | Creates/restores a 32-byte frame and preserves r3. |

All three have zero direct xrefs. An exhaustive loaded-segment pointer scan
finds each only at its listed OSM table word. Review of all 476 driver bodies
finds no load/call of adapter offsets 0x66c/0x674/0x678 or the corresponding
HHCB offsets 0x654/0x65c/0x660. The sole literal 0x654 load occurs with an
adapter base in VerifyAdapter and copies WriteUExact8 to the cached accessor
slot; it is not a SynchronizeRange use. No range semantics are inferred from
the function name.

An independently compiled empty function taking one 32-byte aggregate has
exactly the same 44 bytes as SynchronizeRange, including all eight homing
stores. This establishes a compatible target convention without uniquely
recovering the erased source declaration. Six frozen zero/varied-register
fixtures execute the complete three bodies, observe r3 and restored r1, and
check the exact 32 homed bytes for SynchronizeRange. They pass with the
bounded stack-observation extension; a scalar return-only execution would
not satisfy this contract.

The OSM header explicitly imports `mach/boolean.h` before `kern/thread_call.h`:
kernel-7's latter header uses boolean_t without declaring it. The historical
layout compile first failed on that missing prerequisite, then passed with
the import. This is a header adaptation, not a runtime behavior change.

## Adapter IRQ queue extent

`+[AdaptecU2SCSI initialize]` at `0x1877c8` initializes 64 circular queue
heads at `0x2780d0`, with eight-byte stride. Instructions `0x1877dc..0x1877ec`
increment the count, compare against 63, and advance by eight. Consequently
the `0x200`-byte envelope contains **64 queue_head_t**, not 256 pointers or
256 heads. `registerHandlerForIRQ:` indexes with the same eight-byte stride
and allocates 12-byte adapter links (controller pointer, next, previous).

## Unit, queue, and interrupt-control helpers

The next eight ordinary private signatures retain these concrete contracts:

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIHSetUnitHandle(HHCB *, UnitControl *, uchar target, uchar lun)` returning void | `0x19d89c` | `0x1a2810` forwards r3/r4/r5/r6 from Resource; `0x1a4a64` supplies adapter+24, target+20 and byte target/LUN. Stores HHCB at unit+0, target/LUN bytes+4/+5, HHCB+32+10*target at+8. No consumer uses the incidental final r3 address; Resource writes its own unit+12 and caller restores target pointer. |
| `SCSIHFreeUnitHandle(UnitHandleArgument unusedHandle)` returning void | `0x19d8d0` | Sole direct caller `0x1a2858` forwards r3 through Resource. Upstream `0x1a4d4c..50` loads target+20 (HHCB pointer), whereas `0x1a81c0..c4`, `0x1a8470..74`, `0x1a84a0..a4`, `0x1a84c0..c4` supply target+20 itself (UnitControl pointer). Complete 12-byte body only adjusts/restores stack, no input use. Both proven pointer values are preserved by the explicitly opaque UnitHandleArgument pointer type; no original pointee/formal type claim. All callers discard r3 after call. |
| `SCSIHQueueHIOB(HIOB *)` returning void | `0x19da14` | Callers `0x1a3220`, `0x1a3834`, `0x1a6714` pass HIOB and ignore result. Callee loads HIOB+0 UnitControl, then HHCB, uses byte SCB index+9 into HHCB+0x538, stores HIOB, dispatches firmware+0x5c with HHCB/HIOB r3/r4, then sync. |
| `SCSIHQueueSpecialHIOB(HIOB *)` returning void | `0x19da64` | Seven callers `0x1a2900/2d28/2e00/2edc/2f68/3840/6720` pass HIOB; none consumes return. Byte function+4 selects abort/reset/negotiation action; completion status written+5. Firmware+0xf8 receives HHCB/HIOB; sync retained. |
| `SCSIHCheckHostIdle(HHCB *)` returning uint0/1 | `0x19db8c` | `0x19db58` consumes r3 in status decision, `0x1a2988` forwards it. HHCB byte+7 bounds a scan of HIOB pointer array+0x538; any non--1 entry returns0, exhaustion1. |
| `SCSIHCheckDeviceIdle(HHCB *, uchar target)` returning uint0/1 | `0x19dbdc` | `0x19df08..14` and `0x19e03c..48` load HHCB/unit target into r3/r4; callee masks r4 to8 bits at0x19dbec, scans active HIOBs and compares their UnitControl byte+4. Other callers0x1a1920/1a1a5c/1a29f0/1a3918/1a6824 branch on0/1. |
| `SCSIhAbortTask(HIOB *)` returning void | `0x19dc40` | Sole caller0x19dab0 passes special HIOB and ignores result. Its+0 names the related HIOB, whose unit+0 supplies HHCB; scans active array and invokes firmware+0xc0 with HHCB/related HIOB/status4. Writes special HIOB+5/+6 and calls completion; possible final HCNTRL write means no common defined result. |
| `SCSIhAbortTaskSet(HIOB *)` returning void | `0x19ddc0` | Sole caller0x19dabc passes HIOB and ignores result. UnitControl from+0 provides HHCB and target byte+4; all matching active HIOBs go to firmware+0xc0 with HHCB/HIOB/status4, then completion and conditional HCNTRL restoration. |

FreeUnitHandle is an ordinary observed one-pointer interface with an erased
argument interpretation, not an additional wholly uncalled exception. Its
different callers demonstrate why inventing one original pointee type would
be unjustified. Void declarations above expose no incidental r3 values as
outputs; the later runner must support explicit void-result observation.

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIHEnableExpStatus(HHCB *)` returning void | `0x19e7a8` | `0x1a7e1c` passes HHCB during bus-scan setup. Callee tests HHCB+12 bit0x20000, sets the same bit in+212, pauses, invokes firmware+256 with HHCB/2, unpauses. No defined common return: disabled branch retains the input pointer, active branch ends in a write helper. |
| `SCSIHDisableExpStatus(HHCB *)` returning void | `0x19e810` | Four PostBusScan calls0x1a8414/8438/845c/858c pass adapter+24 and ignore result. Body clears HHCB+212 bit0x20000 and invokes firmware+260 with HHCB/2 under same feature test. |
| `SCSIhPauseAndWait(HHCB *)` returning void | `0x19e878` | All33 direct calls pass HHCB and do not inspect r3 (e.g.0x19dcb4,0x1927cc,0x1a68fc). Callee loads handle at+8, reads/writes HCNTRL0x87, polls bit4 up to0x800000 iterations, optionally invokes hardware descriptor+0x5c with HHCB. Last r3 varies by read or callback; it is not a contracted result. |
| `SCSIhUnPause(HHCB *)` returning void | `0x19e958` | Five calls0x18e6f0/18eb78/19e7f8/19e860/19f2a0 pass HHCB, no result use. Handle+8 feeds byte read0x87; `0x19e99c..a4` passes HHCB and read&0xfb to WriteHCNTRL. |
| `SCSIHEnableExtScbRam(HHCB *)` returning uint0/1 | `0x19e9bc` | Caller0x1927d4 saves r3 at0x1927dc and tests it before restoring state at0x192b2c. Callee reads hardware descriptor+44 callback, tests masks at+100/+104, normalizes prior enable state into r29, invokes setter+48 and restores HCNTRL, then explicitly returns r29 at0x19eacc. Other caller0x1922b4 forwards result. |
| `SCSIHDisableExtScbRam(HHCB *)` returning uint0/1 | `0x19eaf0` | Caller0x192b38 supplies HHCB. Same descriptor masks and setter as Enable, complementary write; explicitly returns normalized prior enable state r30 at0x19ebc0. Caller discards it, but the complete body defines the value. |
| `SCSIHExtScbRAMAvail(HHCB *)` returning uint0/1 | `0x19f494` | Calls0x1a8a48/1a8a6c branch on r3. Descriptor getter+44 and mask+100 are read under pause/restore; `0x19f51c..20` normalizes nonzero into0/1, `0x19f534` returns saved value. |
| `SCSIhDelayCount500us(HHCB *, uint count)` returning void | `0x19f0b0` | Eight calls pass HHCB and full r4 values0/1/2000/4000 (0x18e8d0/18ead4/192280/193dd0/193fa4/194a48/19fd0c/19fda4). Body preserves r4, compares a full-word incrementing counter by equality, performs register save/poll/restore, no result consumer or common defined r3. Unsigned carrier preserves all32 counter bits; original signed typedef is not uniquely implied by equality alone. |

## Input-erased entries

The following exact exception set is authorized by the controller ruling.
No original formal count or original C return type is claimed. These entries
will use intentional legacy unspecified-argument machine-ABI declarations.
They remain required function bodies and, where present, required table slots.

| Function | Body | HIM index including version | Table word | Observed r3 |
| --- | --- | ---: | --- | --- |
| SCSISaveState | `0x1a4d78..0x1a4d84` | 24 | `0x27b3f8` | preserved |
| SCSIRestoreState | `0x1a4d84..0x1a4d90` | 25 | `0x27b3fc` | preserved |
| SCSIProfileNexus | `0x1a5e00..0x1a5e10` | 36 | `0x27b428` | 1 |
| SCSIClearNexusTSH | `0x1a5e10..0x1a5e20` | 37 | `0x27b42c` | 1 |
| SCSIProfileNode | `0x1a5e20..0x1a5e30` | 38 | `0x27b430` | 1 |
| SCSIReportAdjustableNodeProfile | `0x1a5e30..0x1a5e40` | 39 | `0x27b434` | 1 |
| SCSIAdjustNodeProfile | `0x1a5e40..0x1a5e50` | 40 | `0x27b438` | 1 |
| SCSISetOSMNodeContext | `0x1a5e50..0x1a5e60` | 41 | `0x27b43c` | 1 |
| SCSIhSwappingSearchExeQ | `0x1908dc..0x1908ec` | none | none | 0 |
| SCSIhScamSupportCheck | `0x19cb3c..0x19cb4c` | none | none | 0 |
| SCSIHApplyDeviceTable | `0x19db7c..0x19db8c` | none | none | 0 |

The first two bodies are words `9421ffe0 38210020 4e800020`; the remaining
six table entries are `9421ffe0 38600001 38210020 4e800020`. The three
unreferenced entries are `9421ffe0 38600000 38210020 4e800020`. They write the stack
backchain, restore r1, and return through unchanged LR; other argument GPRs
are untouched. There are no direct code references. An exhaustive scan of
loaded segments finds each table-entry pointer only at its listed table word;
it finds no pointer occurrences for the three entries without a slot. Review of
all 57 OSM/controller indirect calls finds no consumer of corresponding
controller offsets `0x52c`, `0x530`, `0x55c..0x570`.

A historical PPC compilation of independent zero-, one-, and two-argument
functions returning one produces identical 16-byte bodies matching the six
reference entries. Independent zero- and two-argument empty functions
produce identical 12-byte bodies matching Save/Restore. This is target
evidence that the original formal inputs cannot be uniquely inferred; it
is not permission to infer absent prototypes elsewhere.

The controller explicitly extended the original eight-entry ruling for the
three unreferenced entries. `test_input_erased_register_contracts` fixes the
exact eleven-address set, checks complete body bytes, and executes two
independently specified eight-register patterns per entry. All 22 frozen
observations pass on the reference. These tests do not establish rebuilt
implementation equivalence or recover original C formal types.

## Scratch and register-value helpers

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIHReadScratchRam(HHCB *, uchar *destination, int offset, int count)` returning void | `0x19f554` | Six callers0x1a46b4/46c8/46dc/46fc/5904/5960 supply HHCB, stack byte buffer, offset and count in r3..r6; all ignore r3. Callee saves those four registers0x19f57c..88. Signed cmpwi offset>63 at0x19f5d0 and signed cmpw loop<count at0x19f5ec/628 establish signed words, stbx at0x19f620 proves byte destination. |
| `SCSIHWriteScratchRam(HHCB *, int offset, int count, const uchar *source)` returning void | `0x19f670` | Caller0x1a59a8 supplies HHCB, computed offset, count1, stack byte source in r3..r6. Callee saves four registers0x19f698..a4, signed comparisons at0x19f6ec/708/748, source lbzx0x19f718 and outgoing byte store+0x3f0x19f71c. Note different read/write argument ordering. |
| `SCSIhWriteHCNTRL(HHCB *, uchar value)` returning void | `0x19ff74` | Calls including0x19e8d8/19e9a4/19f640 restore/read-modify HCNTRL, with no result use. Callee masks r4 to8bits0x19ff8c; HHCB+212 bit0x200000 selects workaround, HHCB+8 supplies handle; ordinary path stores value into OSMWrite8 byte argument at caller SP+0x3f. Both branches end in a void register write. |
| `SCSIhWWWriteHCNTRL(const IOHandle *, uchar value)` returning void | `0x19ffe4` | Sole caller0x19ff9c explicitly passes HHCB+8 pointer in r3 and retained value r4, despite decompiler omission. Callee masks r4 at0x19fffc, loads all8 handle words, pause/polls based on bit4 and INTSTAT0x91&0xd, writes final byte0x87. No result consumer. |
| `SCSIhReadINTSTAT(HHCB *)` returning uchar | `0x1a0128` | HHCB+212 bit0x100000 selects workaround; +8 supplies handle. Both paths explicitly zero-extend r3 at0x1a017c; callers e.g.0x19f2d8 mask status bits and0x1a62c0 consumes interrupt status. |
| `SCSIhWWReadINTSTAT(const IOHandle *)` returning uchar | `0x1a0190` | Call0x1a0148 supplies handle pointer; direct PollIRQ call0x19d9cc also passes HHCB+8. Complete body loads8handle words, preserves pause state, reads0x91 and explicitly zero-extends both result paths at0x1a0274/02e0 before r3 return0x1a02e4. |
| `SCSIhGetAddressScbBA32(HHCB *, uchar offset)` returning uint | `0x1a0588` | Eight residual-length callers0x197540/7600/7814/78a4/7a88/7b08/7d20/7da0 pass HHCB and byte register offsets; wrapper forwards to GetEntity32, resulting full word saved and compared against descriptor bus address. |
| `SCSIhGetEntity32FromScb(HHCB *, uchar offset)` returning uint | `0x1a05a8` | Wrapper0x1a0594 and residual callers0x197530/7804/7a78/7af8/7d10/7d90 supply HHCB/byte offset. Callee loads handle+8, zero-extends r4 at0x1a05c4, reads four consecutive registers, stores returned bytes in reverse order at local+3/+2/+1/+0, then returns full lwz at0x1a0684. |
| `SCSIhCompareBusAddress(uint left, uint right)` returning uint0/1 | `0x1a06a4` | Four callers0x197664/78d8/7b68/7e00 pass full bus-address words and branch on result. Full body homes r3/r4, compares BOTH halfwords at offsets+2 and+0, returns0 iff all32bits equal. Hex-Rays' apparent short arguments would incorrectly drop the high16bits; those types are rejected. |

The FreeUnitHandle opaque pointer carrier follows the controller clarification:
its callers prove pointer kind even though they disagree about the pointee.
This is a documented, address-specific opaque pointer contract, not a generic
void-pointer fallback for unresolved declarations. Target pointer width is32.

## Hardware descriptor callback contracts

The actual data words at0x278c7c (AIC78XX) and0x278cf4 (Bayonet) point to
these functions even though IDA has no xrefs for the untyped data. HHCB+244
is the selected hardware descriptor. Shared slot signatures preserve caller
widths; a chip implementation may consume only the low byte without changing
the shared declaration to an incompatible callback type.

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXLoadScsiRate(HHCB *, ushort rate)` returning void | `0x1a06e4`, table0x278c7c+0 | Slot0 calls0x18d0a0/19b07c/19b1a8 pass HHCB and zero or lhz rate. Callee consumes low8 at0x1a06fc, writes MMIO4. |
| `SCSIhAICBayonetLoadScsiRate(HHCB *, ushort rate)` returning void | `0x1a0734`, table0x278cf4+0 | Same slot callers; callee masks r4 to16bits0x1a074c, writes low byte to4 and high byte to5 at0x1a075c/0790. Callers discard result. |
| `SCSIhAIC78XXResetDFifo(HHCB *)` returning void | `0x1a07d4`, table0x278c80 (+4) | Slot4 call0x18d154 supplies HHCB, ignores result; callee loads handle+8, writes byte1 to MMIO0x93. |
| `SCSIhAICBayonetResetDFifo(HHCB *)` returning void | `0x1a0828`, table0x278cf8 (+4) | Same caller; handle+8 supplies read/write MMIO1, sets bits0x12. |
| `SCSIhAIC78XXGetScbRamCtrls(HHCB *)` returning uint | `0x1a09ac`, table0x278ca8 (+44) | Slot44 calls0x19ea38/19eb68/19f508 pass HHCB and apply full-word descriptor masks to r3. Callee supplies PCI offset0x40 to OSDReadPciConfiguration and returns all32bits. |
| `SCSIhAICBayonetGetScbRamCtrls(HHCB *)` returning uint | `0x1a095c`, table0x278d20 (+44) | Same slot callers; callee MMIO0x84 byte read zero-extends r3 at0x1a0998. Returning this byte as the common32-bit result preserves all defined bits. |
| `SCSIhAIC78XXPutScbRamCtrls(HHCB *, uint value)` returning void | `0x1a0a20`, table0x278cac (+48) | Slot48 callers0x19ea78/19eba8 pass full getter result combined with descriptor masks in r4. Callee moves r4 to r5 at0x1a0a2c and writes PCI dword0x40. |
| `SCSIhAICBayonetPutScbRamCtrls(HHCB *, uint value)` returning void | `0x1a09d0`, table0x278d24 (+48) | Same full-word caller contract, callee intentionally uses low byte at0x1a09e8 for MMIO0x84. Both setters end in void service calls; no caller result use. |

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXGetWideScsiOffset(HIOB *)` returning uchar8 | `0x19bd44`,0x278c88 (+12) | Shared slot12 caller0x19871c (wide branch0x1986ec..700),0x198f4c (wide branch0x198f2c..34) supplies HIOB; return truncated to byte at0x198720/198f50. Complete body returns8. Actual slot callers establish the retained input despite callee erasure. |
| `SCSIhAIC78XXGetNarrowScsiOffset(HIOB *)` returning uchar15 | `0x19bd54`,0x278c8c (+16) | Narrow slot16 at0x19842c/19871c/198f4c receives HIOB; callee returns15. |
| `SCSIhAICBayonetGetScsiOffset(HIOB *)` returning uchar | `0x19bd64`,0x278d00/278d04 (+12/+16) | Same slots/callers. Callee follows HIOB+0 UnitControl, unit+8 device descriptor, returns device byte+6 via lbz0x19bd70. |
| `SCSIhAIC78XXClearScsiOffset(HIOB *)` returning void | `0x19bd7c`,0x278c98 (+28) | Slot28 calls0x198914/198fb4 pass HIOB and ignore r3. Callee follows HIOB/unit/device chain and clears device byte+4 low4bits. |
| `SCSIhAICBayonetClearScsiOffset(HIOB *)` returning void | `0x19bd9c`,0x278d10 (+28) | Same caller/input chain; clears device+4 low4bits and device+6 low7bits. |
| `SCSIhAIC78XXWasSyncXfer(uchar offset)` returning uint0/1 | `0x19bdc8`,0x278c9c (+32) | Slot32 call0x19905c receives byte negotiation offset r28 via mr r3,r28 at0x199034, also stored HIOB+39. Callee masks low4bits, negates, shifts31 to normalize; caller takes result bit0 for device flagbit6. |
| `SCSIhAICBayonetWasSyncXfer(uchar offset)` returning uint0/1 | `0x19bde0`,0x278d14 (+32) | Same caller; low7bit mask then normalization. |
| `SCSIhAIC78XXEnableIOErr(HHCB *)` returning void | `0x1a08bc`,0x278c84 (+8) | Shared slot8 callers0x18d26c/18e918 explicitly load HHCB into r3 and ignore result. Empty12byte body; input recovered from actual callers, so no uncalled-erasure exception. |
| `SCSIhAICBayonetEnableIOErr(HHCB *)` returning void | `0x1a08c8`,0x278cfc (+8) | Same slot callers; callee loads handle+8 and sets bit8 in MMIO0x10 with byte read/write. |

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXSetDataFifoThrshDefault(HHCB *)` returning uchar3 | `0x19bdf8`,0x278cb0 (+52) | Slot52 caller0x192d2c explicitly supplies HHCB at0x192d20 and stores returned byte to HHCB+17 at0x192d40; complete body returns3. |
| `SCSIhAICBayonetSetDataFifoThrshDefault(HHCB *)` returning uchar0x77 | `0x19beb0`,0x278d28 (+52) | Same caller; complete body returns0x77. Constant body still has caller-proven HHCB input. |
| `SCSIhAIC78XXReadDataFifoThrsh(HHCB *)` returning uchar | `0x19be08`,0x278cb4 (+56) | Slot56 caller0x192d70 supplies HHCB and stores byte+17. Callee handle+8, MMIO0x86 read, extracts two bits24..25 at0x19be44. |
| `SCSIhAICBayonetReadDataFifoThrsh(HHCB *)` returning uchar | `0x19bec0`,0x278d2c (+56) | Same caller; MMIO0xfb read, r3 zero-extended at0x19befc. |
| `SCSIhAIC78XXUpdateDataFifoThrsh(HHCB *)` returning void | `0x19be58`,0x278cb8 (+60) | Slot60 calls0x1932d0/19e694 supply HHCB and ignore return. Callee reads byte+17, shifts6, writes lowbyte MMIO0x86. |
| `SCSIhAICBayonetUpdateDataFifoThrsh(HHCB *)` returning void | `0x19bf10`,0x278d30 (+60) | Same callers; byte+17 written directly to MMIO0xfb. |
| `SCSIhAIC78XXGetCacheThEn(HHCB *)` returning uchar0/1 | `0x1a0a48`,0x278cbc (+64) | Slot64 calls0x192e0c/1a5108 supply HHCB, explicitly truncate result to byte and use it as flag. Callee MMIO0x84 reads bit0x80, normalized with extrwi0x1a0a84. |
| `SCSIhAICBayonetGetCacheThEn(HHCB *)` returning uchar0/1 | `0x1a0a98`,0x278d34 (+64) | Same callers; callee pauses/restores if needed, reads same bit, saves normalized result at0x1a0b28 and returns it0x1a0b3c. |

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXUpdateCacheThEn(HHCB *)` returning void | `0x1a0b5c`,0x278cc0 (+68) | Slot68 caller0x19331c passes HHCB, ignores result. Callee tests halfword HHCB+0 against7880 maskfff0, byte+4 and word+12 bit0x10000; may clear HHCB flag, then sets/clears MMIO0x84 bit0x80. |
| `SCSIhAICBayonetUpdateCacheThEn(HHCB *)` returning void | `0x1a0c50`,0x278d38 (+68) | Same caller; HHCB+12 mask0x18000 selects bit0x80 in MMIO0x84, with pause/restore. No output except state/register writes. |
| `SCSIhAIC78XXCheckExtArbAckEnBit(HHCB *)` returning void | `0x1a0f24`,0x278ccc (+80) | Slot80 caller0x19f91c passes HHCB then overwrites r3 for GetHostAddress. Callee loads handle+8, polls MMIO0x1e bit0x10 with counter0x800000; last read value is incidental and unobserved. |
| `SCSIhAICBayonetCheckExtArbAckEnBit(HHCB *)` returning void | `0x1a0fa4`,0x278d44 (+80) | Same caller and full polling algorithm as AIC78XX. |
| `SCSIhAIC78XXGetQNewTail(HHCB *)` returning uchar | `0x1a1b48`,0x278cd0 (+84) | Slot84 calls0x18cb24/18ce40/19024c/19192c/191d4c/197f40/19ac98 pass HHCB and truncate result to byte. Callee loads register offset byte firmware+65 and handle HHCB+8, reads and zero-extends r3 at0x1a1b88. |
| `SCSIhAICBayonetGetQNewTail(HHCB *)` returning uchar | `0x1a1b9c`,0x278d48 (+84) | Same callers. Reads firmware+65 register, zero-extends and saves result, writes same byte back, then returns saved value0x1a1c24. This read/write side effect is retained. |
| `SCSIhAICBayonetWaitForBusStable(HHCB *)` returning void | `0x1a1c44`,0x278d4c (+88) | Optional slot88 call0x18e6b0 supplies HHCB, ignores result. Callee loads handle+8, polls MMIO0x1f bits0xc and0x18 bit0x80 transitions with8000 counter; result differs by exit and is not contracted. |
| `SCSIhAICBayonetSeqStretchWorkaround(HHCB *)` returning void | `0x1a2410`,0x278d50 (+92) | Optional slot92 calls0x18e798/1921f0/193d54/19e934/19f300/1a64a4/1a6a04 pass HHCB, none uses returned read value. Callee performs one MMIO0xee byte read using handle+8. Read itself is required side effect, even though result is unobserved. |

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXGetXferPeriod(HHCB *, HIOB *)` returning uchar | `0x199f74`,0x278c90 (+20) | Slot20 calls0x1988e8/198edc pass HHCB/HIOB r3/r4; result stored/truncated to byte. Callee ignores known HHCB input, follows HIOB/unit/device, interprets device halfword+0 and byte+4, returns bounded byte period. |
| `SCSIhAICBayonetGetXferPeriod(HHCB *, HIOB *)` returning uchar | `0x19a014`,0x278d08 (+20) | Same callers; uses HIOB chain device byte+5 and HHCB handle+8 for MMIO0xd/0x1f speed restrictions. Every result is bounded and zero-extended; r3 at0x19a140. |
| `SCSIhAIC78XXCalcScsiRate(HHCB *, uchar period, uchar offset)` returning ushort | `0x199e10`,0x278c94 (+24) | Slot24 calls0x198ae8/198fd4 explicitly supply HHCB and byte period/offset. Callee masks r4/r5 at0x199e14/20; maps period and ORs offset, zero-extends byte result. Shared slot result is a16-bit rate (Bayonet uses highbyte). HHCB input is caller-proven though unused. |
| `SCSIhAICBayonetCalcScsiRate(HHCB *, uchar period, uchar offset)` returning ushort | `0x199eb8`,0x278d0c (+24) | Same callers; masks both byte inputs, maps period into lowbyte and shifts offset into highbyte at0x199f5c..68. |
| `SCSIhAIC78XXGetSpeed(ushort rate, uchar fastMode)` returning ushort | `0x1a1024` | Direct callers0x1a1464/1a14a0 supply device rate and flag; first flag is device halfword bit15, second firmware callback result. Callee explicitly masks r3 to16bits/r4 to8bits0x1a1028/2c and returns constants36..200; callers store sth. |
| `SCSIhAICBayonetGetSpeed(ushort rate, uint unusedModeWord)` returning ushort | `0x1a1118` | Both callers0x1a1730/1750 explicitly supply r4=0. First r3 is device byte+5, second a zero-extended16-bit firmware rate at0x1a16d0. Body uses low7 rate bits only, never r4, returns constants50..400 consumed with sth. Unused r4 is an explicit opaque32 carrier; no claim about its erased original type. |
| `SCSIhAIC78XXCalcScsiOption(ushort speed, uchar offset, uchar width)` returning ushort | `0x1a11a8` | Caller0x1a18ec loads profile speed with lhz and offset/width with lbz into r3/r4/r5. Callee masks16/8/8 at0x1a11ac/b0/b8, unsigned speed-range comparisons, sets rate/offset/wide bits; complete result fits byte, caller stores byte. |
| `SCSIhAICBayonetCalcScsiOption(ushort speed, uchar offset, uchar width)` returning ushort | `0x1a12a0` | Caller0x1a1a0c loads same widths; callee masks16/8/8, shifts low7 offsetbits into highbyte, sets width bit0x80. Caller zero-extends16 then stores the two bytes separately0x1a1a10..1c. |

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXProcessAutoTerm(HHCB *)` returning void | `0x1936ac`,0x278ca0 (+36) | Slot36 call0x193334 supplies HHCB and ignores return. Tests word+12 bit0x4000000, passes same HHCB through0x1936cc to AutoTermCable, merges cable bits into word+12. |
| `SCSIhAICBayonetProcessAutoTerm(HHCB *)` returning void | `0x193700`,0x278d18 (+36) | Same caller; CableSense receives HHCB, word+12 bits0x4000000/0x800000 govern low/high termination flags. |
| `SCSIhAIC78XXUpdateExtTerm(HHCB *)` returning void | `0x193794`,0x278ca4 (+40) | Slot40 call0x1933b0 supplies HHCB, ignores result. Uses byte+28 bus width, halfword+0 chip ID, word+12 termination flags, handle+8 and PCI location from OSDGetHostAddress. Poll and MMIO writes complete on same handle. |
| `SCSIhAICBayonetUpdateExtTerm(HHCB *)` returning void | `0x1939dc`,0x278d1c (+40) | Same caller; byte+28 and word+12 select output bits, handle+8 feeds MMIO0x1e/0x1d poll/write sequence. |
| `SCSIhAIC78XXGetProfileParameters(HWInformation *, HHCB *)` returning void | `0x1a139c`,0x278cc4 (+72) | Slot72 call0x19e520 explicitly passes output r29 and HHCB r28 in r3/r4. Callee preserves r4/r3 at0x1a13cc/d4, writes16 records at24-byte stride: halfwords+48/+50/+52, bytes+54..60, final halfword+424=36. Caller does not observe result. |
| `SCSIhAICBayonetGetProfileParameters(HWInformation *, HHCB *)` returning void | `0x1a1644`,0x278d3c (+72) | Same caller and record layout; reads device bytes+4/+5/+6, writes corresponding speed/offset/width fields and final halfword+424=50. Input HHCB+8 supplies handle; output is caller-owned. |
| `SCSIhAIC78XXPutProfileParameters(const HWInformation *, HHCB *)` returning void | `0x1a1880`,0x278cc8 (+76) | Slot76 call0x19e76c passes information in r3 and HHCB in r4. Callee preserves them0x1a18a4/a8, reads changed byte+60, speed halfword+52 and bytes+56/+59 per24-byte record, updates HHCB device table and conditionally firmware slot144; no information-buffer writes. |
| `SCSIhAICBayonetPutProfileParameters(const HWInformation *, HHCB *)` returning void | `0x1a1994`,0x278d40 (+76) | Same caller, input widths and ownership; updates device option bytes5/6/4, pauses/assigns/restores for idle device. No information-buffer writes or defined result. |
| `SCSIHGetHWInformation(HWInformation *, HHCB *)` returning void | `0x19e144` | Direct Resource call0x1a2fd4 forwards r3/r4. Output stores bytes0..35, flags word36, per-device halfwords44/46 at24-byte stride, then dispatches slot72 with same output/HHCB. Uses HHCB handle+8, identity+0, FIFO+17, latency+30 and flags+12. Last r3 may be register restoration, never consumed by Resource or public profile callers. |
| `SCSIHPutHWInformation(const HWInformation *, HHCB *)` returning void | `0x19e55c` | Resource call0x1a3034 forwards same two pointers. Reads output-layout fields32..36, updates HHCB+17/+30/+12, invokes threshold slot60, dispatches slot76 with information/HHCB; no information-buffer writes. |
| `SCSIRGetHWInformation(HWInformation *, HHCB *)` returning void | `0x1a2f8c` | Public ProfileAdapter/AdjustAdapter/ProfileTarget/AdjustTarget entries0x1a4d90/1a51d0/1a5520/1a56f4 pass stack output and adapter+24. Body writes queue-depth words at information+40+24*i from HHCB resource records+260/+272 depending +288; then0x1a2fd4 calls Hardware. |
| `SCSIRPutHWInformation(const HWInformation *, HHCB *)` returning void | `0x1a2fe8` | Public adjust callers0x1a51d0/1a56f4 pass same buffer and HHCB. Body reads information+40+24*i and writes selected resource queue-depth word, then0x1a3034 forwards to Hardware. |

HWInformation is a distinct internal profile buffer, not the public464-byte
AdapterProfile or124-byte TargetProfile. Its pointer identity, access widths,
and24-byte device records are established above; the final accessed-prefix
declaration and native layout proof are described below.

| Declaration | Entry and table word | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhAIC78XXIgnoreWideResCalc(HHCB *, HIOB *, uchar residual)` returning void | `0x19c050`,0x278cdc (+96) | Slot96 call0x199c90 passes HHCB/HIOB/r5 residual, ignores result. Callee preserves r3/r4 and masks r5 at0x19c07c/80/8c; reads/writes byte counter registers, updates HIOB word+20 with residual and scratch highbits, adjusts address registers0x88..8b. |
| `SCSIhAICBayonetIgnoreWideResCalc(HHCB *, HIOB *, uchar residual)` returning void | `0x19c488`,0x278d54 (+96) | Same caller; saves HHCB/HIOB0x19c4a4/a8, masks r5 at0x19c4b8, updates HIOB+20 and invokes optional firmware callbacks+264/+268 with HHCB/full32bit count/address. |

All25 hardware descriptor slots now have normal typed caller/callee closure.
The descriptor is120bytes:25 four-byte function pointers, three words at100/
104/108, four bytes112..115, two halfwords116/118. Concrete mask uses100/104
are in the external-SCB-RAM helpers; byte114 is loaded by0x192d50 into HHCB
cache-enable bit, byte115 selects the configuration register in0x192d7c and
0x19e5cc, halfword116 is compared against negotiation period at0x198f6c,
and halfword118 is the delay count read in0x19f134's hardware descriptor path.
Words/bytes whose semantic names remain unestablished retain offset names.
The25 pointer declarations use the same types as their implementations; the
AIC78XX null optional88/92 slots remain null, not erased functions.

The historical PPC compiler accepted the public declarations and table types
in the hardware-layout translation unit. That unit did not yet include the
private header; the later variadic witness explicitly includes it and compiles
all148 then-reviewed normal declarations and eleven CHIM exceptions. Its hardware layout object
exports size120 and every hardware field offset0..118; the Mach-O reader
verified all34 offsets, OSM table size124/all31 offsets and BufferDescriptor
size12/offsets0/4/8, alongside prior layout constants. The retained manifest
and four-header SHA-256 closure bind this intermediate proof to the exact
inputs. This is target layout evidence, not completion of unreviewed shared
structures, all392 prototypes, or behavioral reconstruction.

## Resource configuration and initialization

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIRGetConfiguration(HHCB *)` returning uint0 | `0x1a245c` | VerifyAdapter0x1a45f4 passes adapter+24. Body forwards HHCB to Hardware0x1a2470, copies firmware byte80 into HHCB+24 and writes+25=4, explicitly returns0 at0x1a2478. |
| `SCSIHGetConfiguration(HHCB *)` returning uint0 | `0x191f44` | Resource caller above; callee handle+8, flags+12, SetupEnvironment/PrepareConfig and firmware+124 receive HHCB. Performs hardware configuration, restores HCNTRL, sync, explicit r3=0 at0x192040. |
| `SCSIRGetMemoryTable(uchar firmwareMode, uchar scbCount, MemoryDescriptor *table)` returning void | `0x1a24a0` | Nine public initialization/configuration/memory callers0x1a3dcc/3de0/3e20/3e34/3f50/3f64/3fbc/3fec/421c pass mode constants0/3/4/5, byte SCB count and one6-entry72-byte table. Body masks count, forwards, fills entries3/5 sizes4*count/20*count. All callers ignore incidental r3 table-index value. |
| `SCSIHGetMemoryTable(uchar firmwareMode, uchar scbCount, MemoryDescriptor *table)` returning void | `0x192064` | Resource0x1a24c4 forwards all3slots; callee masks mode to8bits before pointer-table indexing0x192088 and count to8bits, fills byte/halfword descriptor fields. Existing entry4 size at+52 is read/preserved into minimum size, so table is mutable input/output rather than fresh output only. |
| `SCSIRApplyMemoryTable(HHCB *, const MemoryDescriptor *)` returning uint0/1 | `0x1a2528` | VerifyAdapter0x1a4668 supplies adapter+24 and adapter+1488, branches on returned status. Body reads entry3/5 pointers+44/+68 into HHCB+1344/+1340 then calls Hardware. |
| `SCSIHApplyMemoryTable(HHCB *, const MemoryDescriptor *)` returning uint0/1 | `0x19213c` | Resource0x1a2544 forwards both inputs. Callee copies entry pointers+8/+32/+20 into HHCB+196/+1336/+208, computes supported SCBs from halfword table+16 and firmware size, updates byte+7 or returns1 if insufficient. Explicit status at0x1921ac. |
| `SCSIRInitialize(HHCB *)` returning int0/-1 | `0x1a2558` | Public Initialize0x1a491c passes HHCB and maps nonzero status. Resource calls Reset then Hardware with saved HHCB, preserves status r3. |
| `SCSIHInitialize(HHCB *)` returning int0/-1 | `0x1921b8` | Resource0x1a2574; uses HHCB hardware/firmware callbacks, returns-1 for sequencer-load failure and0 after hardware init/start/sync. Failure is represented as signed32 -1, not a fabricated byte-only status. |
| `SCSIrReset(HHCB *)` returning void | `0x1a2598` | Sole caller0x1a256c passes HHCB and replaces r3 before Hardware call. Reads byte SCB count+7, builds20-byte SCB descriptor ring from HHCB+1340, DMA bases+208, firmware stride+4, initializes sixteen68-byte resource records+248. Optional firmware+292 callback receives HHCB; final r3 is not defined. |
| `SCSIrStandardRemoveScbs(HHCB *)` returning void | `0x1a27c0` | Actual firmware words0x27ae40/27b090 (Standard64/StandardAdv +292) point here. Reset's optional slot+292 call passes HHCB. Body links descriptor1 next at ring+36 to ring+60, decrements HHCB byte+1352; caller ignores r3. |
| `SCSIRSetUnitHandle(HHCB *, UnitControl *, uchar target, uchar lun)` returning void | `0x1a27e4` | Calls0x1a4b54/1a7f8c/1a8788 supply HHCB, target-block+20, byte target/LUN. Body forwards all4 to Hardware0x1a2810 then stores HHCB+248+68*target at unit+12. Results ignored. |
| `SCSIRFreeUnitHandle(UnitHandleArgument unusedHandle)` returning void | `0x1a284c` | All four caller identities and the two distinct pointer forms are documented with Hardware FreeUnitHandle above. Complete wrapper forwards r3 unchanged to0x19d8d0 at0x1a2858; no input/return interpretation added. |

## Event calling convention correction

The fixed OSDAsyncEvent declaration was incomplete: entry0x1a7bf0..10 homes
r4..r10 at entrySP+28..52, even though only HHCB/event are consumed.
SCSIrAsyncEvent0x1a2bf4..0c has the same homing. Historical PPC cc witnesses
with two named words plus ellipsis produce precisely this homing range;
three named words plus ellipsis home r5..r10 at entrySP+32..52. The compiler
homes the last named word as well. Therefore both event declarations retain
the two caller-proven fixed parameters and ellipsis. OSMEvent0x189ba4..b8
has the latter range, and its actual caller supplies context/event/zero;
its declaration/table slot now preserve three named words plus ellipsis.
The third word is explicitly discarded, with no recovered semantic type.
No reference path reads extra variadic values or forwards a va_list. This
is a machine-compatible declaration, not proof of original source spelling.
The separate OSMSynchronizeRange ambiguity remains: both an aggregate and
one-fixed-word variadic witness produce its homing, so no formal recovery
claim is added there.

The retained varargs-layout.o and IDA varargs-witness-disassembly.json show
all four witnesses, bound by source/object/four-header SHA-256 closure.
The two-word forwarding witness has frame64 and stores r4..r10 at currentSP
+92..116; the empty two-word witness has frame32 and stores at+60..84.
The three-word witness stores r5..r10 at currentSP+64..84 with frame32.
Later event bodies must preserve these caller-save-area effects. Existing
stack observation can freeze them; no extra consumed payload or serializer
extension is justified by these paths. Proven-void result observation is
still needed in the downstream runner. Adding ellipses after this build
changes header hashes, so the current object cannot satisfy the final gate.

## Resource queue and completion contracts

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIRQueueSpecialHIOB(HIOB *)` returning void | `0x1a286c` | Sole caller0x1a62ac passes request HIOB. Reads function byte+4, clears status bytes5/6/7/32/33, dispatches abort/reset helpers and completion with same pointer; no result consumed. |
| `SCSIRCheckHostIdle(HHCB *)` returning uint0/1 | `0x1a2944` | Callers0x1a2e40/1a5204/1a6218 pass HHCB and branch on result. Scans host queue+1364 and16device heads at+248 with68-byte stride before Hardware idle query; explicit boolean status. |
| `SCSIRCheckDeviceIdle(HHCB *, uchar target)` returning uint0/1 | `0x1a299c` | Callers0x1a4d20/1a5748 pass HHCB/target byte. Callee masks r4 to8bits0x1a29b0, scans host HIOB links+28/unit target+4, checks resource head HHCB+248+68*target and Hardware idle status. |
| `SCSIrCompleteHIOB(HIOB *)` returning void | `0x1a2a0c` | Calls0x18d360/191908/191a94/191c74/191eb4/195d7c pass completed HIOB, ignore return. Unit+0/+12 gives HHCB/resource; status+5=5 frees SCB/requeues, otherwise status+7=40 freezes queue before freeing SCB and appending to HHCB done-array+1344 using byte index+1348. |
| `SCSIrCompleteSpecialHIOB(HIOB *)` returning void | `0x1a2acc` | Eleven direct callers including0x191914/195e24/19db30/19dd80/19deb0/1a292c/1a2ed0/1a6958 pass HIOB, ignore return. Function+4 determines HIOB+0 union interpretation (HHCB, related HIOB or unit); updates resource counters32/36, unfreezes, posts done queue, calls OSDCompleteSpecialHIOB. |
| `SCSIrAsyncEvent(HHCB *, uint event, ...)` returning void | `0x1a2bd0` | Nine direct calls0x193c60/193e6c/193e78/193f04/194040/19404c/194a34/194b38/194b44 supply HHCB/event1/3/6/7/8. Event1/3/5/8 clears queues/posts completions;6 freezes,7 unfreezes. All except7 forward HHCB/event to OSD; no result or extra variadic payload consumed. Homing proof above. |
| `SCSIrScsiBusReset(HIOB *)` returning void | `0x1a2ce4` | Sole caller0x1a28e8. HIOB+0 is HHCB for reset-bus function; freezes all queues, clears host/all device queues with status6, queues same special HIOB through Hardware. |
| `SCSIrBusDeviceReset(HIOB *)` returning void | `0x1a2d48` | Sole caller0x1a28f4. HIOB+0 is UnitControl, unit+0/+12 gives HHCB/resource; freezes counter32, aborts target queue status8, increments active+16, firmware+280 allocates byte SCB into HIOB+9. 0xff appends host queue, otherwise queues Hardware; caller observes state only. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIRPowerManagement(HHCB *, uint unusedEventWord)` returning uint status | `0x1a2e24` | Public PowerEvent0x1a4c88 forwards HHCB and r4; callee saves both0x1a2e38/3c, returns2 if not idle, else restores r3/r4 at0x1a2e54/58 for Hardware. Forwarded opaque-word ruling and terminal ignored-input proof above apply. |
| `SCSIrAbortTask(HIOB *)` returning void | `0x1a2e78` | Sole caller0x1a28d0. HIOB+0 holds related HIOB; passes related request/status4 to HostQ and DevQ abort helpers, then sets original status+5=1 and completes or submits original special request. No result consumed. |
| `SCSIrAbortTaskSet(HIOB *)` returning void | `0x1a2ef8` | Sole caller0x1a28dc. HIOB+0 holds unit, unit+12 resource, unit+0 HHCB. Freezes resource flag16 if counter+36 zero, aborts matching unit/status4, increments counter and queues original special request. |
| `SCSIRGetFreeHead(HHCB *)` returning SCBDescriptor pointer | `0x1a3048` | Four reset-software callers0x18d470/18d720/18d984/18dcfc pass HHCB; returned HHCB+1356 is dereferenced for byte SCB number+0, virtual address+12 and link+16. Full body single word load at0x1a304c; pointer identity follows Reset's20-byte descriptor ring. |
| `SCSIrAsyncEventCommand(HHCB *, HIOB *, uint event, ...)` returning void | `0x1a3058` | Freeze-HW-queue callers0x1917fc/191aec/191b68/191f0c supply HHCB/HIOB and1or2; no result consumed. Callee homes r5..r10 at entrySP+32..52 (three-fixed target witness above), follows HIOB+0 unit/resource, saves/restores resource active count+16/+28 and rearranges queue pointers+48/+52/+56. No variadic value is read. |
| `SCSIrAllocateScb(HHCB *, HIOB *)` returning void | `0x1a31dc` | Direct callers0x1a3900/1a3cb8/1a60f4/1a6808 provide HHCB/request. Firmware+280 receives same pair; byte result goes to HIOB+9. 0xff host-enqueues; otherwise Hardware submits. Callers ignore incidental r3. |
| `SCSIrGetScb(HHCB *, HIOB *)` returning uchar | `0x1a324c` | All four firmware descriptors slot280. Indirect calls0x1a2dd8/1a3208/1a381c/1a66fc pass HHCB/HIOB, consume lowbyte as SCB number. Body checks byte HHCB+1352, returns0xff if<=1, else transfers free descriptor+1356 to HIOB+24, advances descriptor link+16, returns descriptor byte+0. |
| `SCSIrReturnScb(HHCB *, HIOB *)` returning void | `0x1a3290` | All four firmware descriptors slot284. Calls0x1a3800/1a3860/1a66e0 supply HHCB/request then overwrite r3; no return observation. Body increments free count+1352, links previous tail descriptor+16 to HIOB+24 and stores same descriptor as tail+1360. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIrDeviceQueueAppend(ResourceControl *, HIOB *)` returning void | `0x1a32bc` | Callers0x1a2a54/1a6104 pass unit+12 resource and HIOB. Stores HIOB link+28=-1; updates resource head/tail+0/+4 and queued count+64. Callers ignore r3. |
| `SCSIrDeviceQueueRemove(ResourceControl *)` returning HIOB pointer or -1 sentinel | `0x1a3300` | Calls0x1a38ec/1a3c88/1a3ccc pass resource, compare returned pointer with-1 before dispatching. Body reads head+0; HIOB flags+8 bit0x4000 selects unsigned limit+12 or+8. Compares limit against active+16 minus queued+64, unlinks head and decrements queued on acceptance. |
| `SCSIrAbortHIOBInDevQ(HIOB *, uchar status)` returning uchar0/1 | `0x1a3380` | Sole caller0x1a2eb4 passes related request/status4 and masks return to byte. Callee masks status at0x1a33ac; HIOB+0/unit+12 identifies resource, scans links+28 for identity, adjusts head/tail and posts aborted request. Explicit0/1 returns. |
| `SCSIrClearDeviceQueue(ResourceControl *, uchar status)` returning void | `0x1a3414` | Calls0x1a2da4/1a2f54/1a34d8 pass resource/status8or4orforwarded byte. Callee masks status0x1a343c, drains head through link+28 up to saved tail, posts each aborted HIOB; caller ignores result. |
| `SCSIrClearAllDeviceQueues(HHCB *, uchar status)` returning void | `0x1a34ac` | Calls0x1a2c94/1a2d20 pass HHCB/status5or6. Masks status0x1a34c4, iterates16 resource blocks starting+248 stride68, forwards to ClearDeviceQueue. |
| `SCSIrHostQueueAppend(HHCB *, HIOB *)` returning void | `0x1a3508` | Calls0x1a2df4/1a3230/1a60b4 pass HHCB/HIOB; writes link+28=-1 and host head/tail+1364/+1368, no return used. |
| `SCSIrHostQueueRemove(HHCB *, uchar unusedScbNumber)` returning HIOB pointer or -1 sentinel | `0x1a3540` | Firmware slot288 at0x27ae3c/27af64/27b08c/27b1b4. Both actual calls0x1a37d8/1a66c0 explicitly load HIOB byte+9 into r4 and HHCB into r3. Complete body does not read r4; retain caller-proven SCB byte argument, not invented no-arg form. Body removes host head+1364, follows HIOB link+28, updates tail+1368; returns former head. |
| `SCSIrAbortHIOBInHostQ(HIOB *, uchar status)` returning uchar0/1 | `0x1a3580` | Sole caller0x1a2e9c supplies related HIOB/status4 and masks returned byte. Callee masks status0x1a35ac, follows HIOB/unit/HHCB, scans host head+1364 links+28, adjusts queue and posts aborted request. Explicit0/1 returns. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIrFindAndAbortHIOB(HHCB *, UnitControl *, uchar status)` returning void | `0x1a3614` | Calls0x1a2d98/1a2f48 supply HHCB/unit/status8or4. Callee saves pointers0x1a3638/40, masks r5 to byte0x1a3644, scans HHCB host queue and matches target byte at unit+4, adjusts queue/posts aborted HIOB. No result consumed. |
| `SCSIrClearHostQueue(HHCB *, uchar status)` returning void | `0x1a370c` | Calls0x1a2c40/58/70/88/1a2d14 supply HHCB/status7/9/10/5/6. Callee masks r4 at0x1a3734, drains host queue up to saved tail through HIOB+28, posts each aborted HIOB and clears tail if empty. |
| `SCSIrFreeScb(HHCB *, HIOB *)` returning void | `0x1a37a4` | Calls0x1a2a48/7c/1a2b78 pass HHCB/completed HIOB. Invokes slot288(HHCB, HIOB.scbNumber), returns old descriptor through slot284, allocates new descriptor for dequeued request through slot280, queues normal/special request, finally FreeCriteria(completed HIOB). No status result consumed. |
| `SCSIrFreeCriteria(HIOB *)` returning void | `0x1a3888` | Sole caller0x1a3868 supplies completed HIOB. Reads flags+8, unit/resource chain, decrements resource active+16; unsigned queue limits+8/+12 and flags+40 select dispatch/unfreeze paths. Request word+48 compared unsigned with0x7f. Return is incidental across mutually different paths and unused. |
| `SCSIrPostAbortedHIOB(HIOB *, uchar status)` returning void | `0x1a3998` | Eight calls0x1a33dc/1a345c/347c/1a35dc/1a3698/36e0/1a3754/3774 provide HIOB and already byte-masked status. Body decrements unit.resource.active+16, stores status2 to HIOB+5 and incoming r4 byte to+6, calls OSDCompleteHIOB with unchanged HIOB. No result consumed. |
| `SCSIrPostDoneQueue(HHCB *)` returning void | `0x1a39d8` | Calls0x1a2ba8/1a2c9c pass HHCB, ignore result. Compares byte producer+1348/consumer+1349, advances consumer modulo byte count+7, calls OSDCompleteHIOB on pointer from done array+1344[index]. |
| `SCSIrAdjustQueue(HIOB **head, HIOB **tail, HIOB *const *previous, HIOB *current)` returning void | `0x1a3a5c` | Four calls0x1a33d0/1a35d0/1a368c/1a36d4 pass addresses of head/tail, address of local previous pointer, current HIOB. Callee reads all four, writes head/tail or previous->link+28; never writes through third parameter to replace previous. Callers overwrite r3 after return. |
| `SCSIrFinishQueueFull(HIOB *)` returning void | `0x1a3abc` | Calls0x1a3934/1a6840 pass HIOB and ignore return. Unit/resource chain selects unsigned limit+24, halves if>1, unfreezes mask1 and dispatches queued requests for same unit. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIrFreezeAllDeviceQueues(HHCB *)` returning void | `0x1a3b10` | Calls0x1a2ca8/1a2d08 pass HHCB. Callee walks16 resources+248 stride68, calls FreezeDeviceQueue with mask8; no return observed. |
| `SCSIrUnFreezeAllDeviceQueues(HHCB *)` returning void | `0x1a3b60` | Calls0x1a2b5c/1a2cb4 pass HHCB. Walks same resources, clears mask8 and dispatches head HIOB when head!=-1. No return observed. |
| `SCSIrFreezeDeviceQueue(ResourceControl *, uint mask)` returning void | `0x1a3bc0` | Calls0x1a2a70/1a2d88/1a2f38/1a30b8/1a3b34 pass resource with masks1/2/16/4/8. Body reads flagword+40, saves limits+8/+12 into+20/+24 and zeroes live limits on first freeze; ORs full r4 into+40 at0x1a3bfc. |
| `SCSIrUnFreezeDeviceQueue(ResourceControl *, uint mask)` returning void | `0x1a3c0c` | Calls0x1a2914/1a2b98/1a3970/1a3af0/1a3b84/1a687c pass resource/mask4/2/32/1/8/32. Full-word andc0x1a3c20 clears mask; only when all freeze bits clear restores saved limits and zeroes saved fields. Caller ignores r3. |
| `SCSIrDispatchQueuedHIOB(HIOB *)` returning void | `0x1a3c50` | Calls0x1a291c/1a2ba0/1a3978/1a3af8/1a3b94/1a6884 pass request. Callee gets unit/resource, skips frozen resources, removes pending HIOBs, selects tag/non-tag limit from request flag0x4000, allocates/submits up to unsigned limit; no caller consumes return. |

All47 Resource-owner functions now have individually accepted contracts.
The descriptor pointer is distinct from its embedded DMA data: Reset0x1a2598
writes20-byte descriptors, number byte0, translated bus-address word4,
firmware SCB byte-size word8, virtual-address word12, descriptor next pointer16.
The previous GetFreeHead prose mislabeled offset12 as a bus address; the
translation call and separate stores establish the correction above.

## Remaining HIM contracts

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIHSetupHardware(HHCB *)` returning void | `0x192304` | Sole call0x1a89dc passes adapter+24, ignores r3. Byte HHCB+19 indexes hardware pointer table; stores descriptor at+244. |
| `SCSIHSizeSEEPROM(HHCB *)` returning uint word count | `0x19cb4c` | Calls0x1a5a40/1a5be0 supply HHCB, use size in nonnegative arithmetic. Callee reads handle+8, hardware mode+19 and address mode+223; returns0/64/128 after pause/MMIO/restore. |
| `SCSIHReadSEEPROM(HHCB *, ushort *destination, uint wordOffset, int wordCount)` returning uint0/1 | `0x19cc94` | Calls0x1a5bd0/1a5dd4 pass HHCB, writable stack/buffer, word offset, word count in r3..r6. Saves all four0x19ccc0..cc; count has signed comparisons0x19cdf8/19ce18. E2Register gets offset+index; sthx0x19ce1c writes successive destination halfwords. |
| `SCSIHWriteSEEPROM(HHCB *, uint wordOffset, int wordCount, const ushort *source)` returning uint0/1 | `0x19cea4` | Call0x1a5d44 passes HHCB, logical byte offset/2, byte count/2, buffer in r3..r6. Saves all four0x19cee4..f0; signed count comparisons0x19d05c/19d174, lhzx0x19d164 reads successive source halfwords. Address uses bitwise opcode OR/add; source is never written. Read/write orders differ and are preserved. |
| `SCSIHSuppressNegotiation(UnitControl *)` returning void | `0x19deec` | Sole call0x1a8144 passes target+20 and ignores return. Callee unit+0 HHCB/+4 target selects idle check, firmware read rate+156 and conditional assign+144; MMIO pause/restore via HHCB+8. |
| `SCSIHForceNegotiation(UnitControl *)` returning void | `0x19e01c` | Calls0x1a8150/1a8534/1a8604 pass target+20, ignore result. Unit+0/+4/+8 gives HHCB/target/device; checks idle, derives negotiation rate from device state, calls firmware+144, restores HCNTRL. |
| `SCSIHReadHADDR(HHCB *, uchar destination[4])` returning void | `0x1a0304` | No direct or stored-pointer caller: full reference scan finds sole literal0x1a0304 at file0x2ae218, the value field of nlist at0x2ae210 (`_SCSIHReadHADDR`), not a dispatch slot. Body saves r3/r4 at0x1a0328/2c, dereferences HHCB+8; four byte reads MMIO0x88..8b are stored to destination0..3. Exit r3 is either last read byte or incidental HCNTRL helper result; reconstructed contract exposes only four output bytes and required MMIO effects, no original return-type claim. |

All31 HIM functions are now covered (30 normal and the separately audited
ApplyDeviceTable erasure). The uncalled ReadHADDR has live, fully interpreted
pointer inputs and output accesses; it is not an input-erasure exception.

## Resource storage boundaries

ResourceControl has an exact68-byte stride, sixteen entries beginning HHCB
+248 and ending+1336. Reset0x1a2598 initializes head/tail0/4, limits8/12,
active16, saved limits20/24, reset32, abort-set36, freeze40, saved tail48,
recovery60 and queued64. AsyncEventCommand establishes saved active28 and
frozen queue head/tail52/56. Offset44 has no accepted semantic interpretation;
its word storage is retained explicitly. Queue comparison/dispatch uses
unsigned arithmetic for counts/limits, and freeze operations use full-word
masks. Pointer members retain the reference's all-ones empty sentinel.

SCBDescriptor's exact20-byte stride is independently used by memory-table
size calculation0x1a24a0 and Reset0x1a2598. Its byte number0 is followed by
three unaccessed storage bytes; word4 is OSD-translated bus address, word8
firmware byte-size, pointer12 virtual SCB buffer, pointer16 circular next.
The ring storage is supplied through memory descriptor5, the SCB data through
HHCB+208. Allocation transfers a ring entry to HIOB+24; release links it back.

UnitControl's accessed16-byte prefix is fixed by Hardware SetUnitHandle
0x19d89c (HHCB pointer0, target byte4, LUN byte5, device pointer8) and Resource
SetUnitHandle0x1a27e4 (resource pointer12). Device pointer is HHCB+32+10*target;
resource pointer is HHCB+248+68*target. Bytes6/7 are preserved storage. This
prefix is embedded at TargetTSCB+20; the independently allocated target is
40bytes, so its remaining four bytes are retained separately, without a
claim that original source used a16-byte standalone unit allocation.

The historical PPC layouts-resource object confirms SCBDescriptor20 and all
five data offsets0/4/8/12/16, ResourceControl68 and all17 offsets0..64,
UnitControl16 and offsets0/4/5/8/12. All twelve constant sets, source/object
hashes and four exact header hashes passed the retained read-resource-proof
check. This build compiled192 normal plus11 erased CHIM declarations; later
header edits require fresh hash closure before final acceptance.

## Transport bitmap and configuration helpers

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIxMaximizeMemory(MemoryDescriptor *destination, const MemoryDescriptor *source)` returning void | `0x1a3e68` | Six calls0x1a3dec/1a3e0c/1a3e40/1a3f70/1a3f90/1a3ff8 pass six-entry memory tables. Body unsigned-compares halfword size+4 and byte alignment+1, takes maxima into destination, advances both pointers by12 for6 entries. No source writes or returned pointer consumed. |
| `SCSIxNonScamValidateLun(TargetTSCB *)` returning uint0/2 | `0x1a4cbc` | Sole caller0x1a4ca8 forwards target. Body loads target.adapter+4 and target ID word+8, checks bitmap adapter+1756/LUN0, maps result to0or2. |
| `SCSIxApplyNVData(AdapterTSCB *)` returning uint1 | `0x1a7cb4` | Sole caller0x1a4680 passes adapter. Full body writes word+1404=0xffff and returns1. No unobserved original formal claimed. |
| `SCSIxBiosExist(AdapterTSCB *)` returning uint0 | `0x1a7cd0` | Caller0x1a4688 explicitly supplies saved adapter pointer in r3, tests return. Complete body returns0; caller establishes ignored pointer input, so no erasure exception needed. |
| `SCSIxOptimaExist(AdapterTSCB *)` returning uint0 | `0x1a7ce0` | Caller0x1a4698 explicitly supplies same adapter pointer and tests return; complete body returns0. |
| `SCSIxChkLunExist(const uchar *bitmap, uint target, uint lun)` returning uint0/1 | `0x1a7cf0` | Eleven direct calls including0x1a49a4/49b8/4acc/4ae0/4cdc/8650/8664 pass bitmap adapter+1756or1884, fullword target/LUN. Body computes full32-bit `(target<<6)+lun`, logical shifts by3 to byte index, extracts bit&7; reads one byte and returns lowbit. |
| `SCSIxSetLunExist(uchar *bitmap, uint target, uint lun)` returning void | `0x1a7d18` | Calls0x1a4af8/1a8284/1a83c4 pass same bitmap/index convention. Fullword shift/add, byte read/or/store. No caller uses preserved r3. |
| `SCSIxClearLunExist(uchar *bitmap, uint target, uint lun)` returning void | `0x1a7d48` | Calls0x1a4d38/4d48/1a7e6c/7e7c pass same bitmap/index convention. Fullword shift/add, rotated clear-mask and byte store; result unobserved. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIxTranslateError(IOB *, const HIOB *)` returning void | `0x1a7924` | Calls0x1a77f8/1a78b0 pass IOB/HIOB, overwrite r3 afterward. Reads HIOB bytes5/6/7/17 and word20, writes IOB status44 and residual96/100 with sense-length word92; no HIOB writes. |
| `SCSIxSetupBusScan(AdapterTSCB *)` returning void | `0x1a7d78` | No call/data xrefs; sole literal entry address file0x2af1fc is nlist value. Callee saves r3 and zeros adapter bitmap+1756 length128 and target block+2536 length40; initializes target/type/context, own-ID exclusion, scan counters, optionally modifies HHCB device table and calls EnableExpStatus. Typed live input/observable state, no original return-type claim; r3 is incidental memset/helper result. |
| `SCSIxSetupLunProbe(AdapterTSCB *, uchar target, uchar lun)` returning void | `0x1a7e38` | Call0x1a61ec supplies IOB task-set handle and two extension bytes16/18; callee masks r4/r5 at0x1a7e5c/64. Clears both bitmap bits, zeros embedded40-byte target, writes IDs/type/context and scan state. Caller ignores r3. |
| `SCSIxQueueBusScan(AdapterTSCB *)` returning void | `0x1a7ee8` | Calls0x1a61f4/1a84b8/1a85d8 supply adapter. Reads owned IOB+2532 and DMA storage+2528; zeros108-byte IOB, points reserve at DMA+72 size88, installs PostBusScan callback+52, sets target+40 and CDB6/data/sense descriptors. Callback receives this IOB; request remains outstanding until completion. |
| `SCSIxQueueSpecialIOB(AdapterTSCB *, uint function)` returning void | `0x1a86fc` | Call0x1a8480 supplies adapter and11. Callee saves r4 at0x1a8720 then stores full word to IOB+12 at0x1a878c. Builds108-byte IOB, reserve, embedded target, PostQueueSpecialIOB callback, submits; no result consumed. |
| `SCSIxPostQueueSpecialIOB(IOB *)` returning uint0/1 | `0x1a87cc` | Address is stored at IOB+52 by0x1a8798..a0; completion calls0x1a780c and special completion paths pass IOB. Body loads IOB status44, explicitly returns status!=1. This result is preserved although current callers ignore it; all nine post callbacks have coherent machine-word returns. |
| `SCSIxGetSpeed(ushort rate, uchar fastMode)` returning uint | `0x1a87e8` | No direct/data xrefs; literal file0x2af190 only nlist value. Entry masks r3 to16 and r4 to8 at0x1a87ec/f0, interprets rate bits0x70 and mode nonzero; all exits choose36..200 in r9 then return r3=r9 at0x1a88d0. No original narrow return spelling claimed. |
| `SCSIxCalcScsiOption(uint speed, uint offset, uint width)` returning uint | `0x1a88dc` | No direct/data xrefs; literal file0x2af154 only nlist. Full r3 participates in unsigned interval comparisons; low4 r4 bits are used at0x1a899c; full r5 compared with16 at0x1a8998. Returned word combines rate/offset/wide bits. The second formal is a typed machine word with low4-bit interpretation, not an unused opaque fallback or an inferred byte from its name. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIxPostBusScan(IOB *)` returning uint0 | `0x1a8180` | QueueBusScan stores entry address at IOB+52 at0x1a7fa4; completion passes IOB. Body saves r3 at0x1a81ac, follows IOB+40 target/+4 adapter, maps status+44, updates LUN bitmaps/negotiation, frees unit handle, resubmits scan or invokes originating IOB completion. Every normal exit explicitly returns0 at0x1a86c8. The scan IOB remains adapter-owned reusable storage. |
| `SCSIxDetermineFirmwareMode(AdapterTSCB *)` returning uchar mode | `0x1a89bc` | VerifyAdapter call0x1a4534 supplies adapter and masks result to8bits. Body configures embedded HHCB+24 hardware descriptor, examines full product-ID word+4 and external RAM availability, selects mode0/3/4/5 in r3. |
| `SCSIxGetNextSubSystemSubVendorID(uint index, uint *mask)` returning uint ID | `0x1a8aa4` | VerifyAdapter0x1a44fc passes enumeration index and stack-word output, tests ID then masks it with stored output. Unsigned index<=13 selects8-byte table entry; returns first word, stores second at r4; out-of-range returns0 without writing output. |

All19 Transport-owner declarations are now accepted. Completion callback
compatibility is word-result(IOB*): PostBusScan returns0, PostQueueSpecialIOB
returns boolean; seven OSM post bodies have explicit r3=0 epilogues at
0x18a7cc/18aadc/18acf4/18ae78/18af4c/18afb4/18b184. Later OSM declarations must
use this common typed callback contract, although current invocation sites
ignore its result.

## Configuration owner contracts

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhStandardConfigureScbRam(HHCB *)` returning uint0/1 | `0x1922a8` | Firmware slot128 at0x27ad9c/27afec; optional call0x192210 explicitly passes HHCB. Full wrapper forwards r3 to EnableExtScbRam0x1922b4 and preserves its boolean result. |
| `SCSIhSetupEnvironment(HHCB *)` returning void | `0x1922c8` | Call0x191fec passes HHCB and later overwrites r3. Uses bytes19/18 to select hardware/firmware pointers, stores+244/+240. |
| `SCSIhPrepareConfig(HHCB *)` returning void | `0x192328` | Call0x192004 passes HHCB, ignores result. Body saves r3, loads handle+8, invokes PCI read with explicit offset0x2c at0x192348 (missing in decompiler), writes ID halfword0, flagwords212/1376, revision byte4, firmware byte5 and per-device flags. |
| `SCSIhGetCapability(HHCB *)` returning void | `0x1924fc` | Call0x192464 passes HHCB, ignores incidental host-address result. Halfword chipID0 controls capability word1376; host-address device word8 selects channel byte23. |
| `SCSIhStandardGetConfig(HHCB *)` returning void | `0x192708` | Firmware slot124 at0x27ad98/27afe8; call0x19201c supplies HHCB and overwrites r3. Gets max SCB byte, stores HHCB+7/+31, sets flagword+12 bit0x20000000 when255, calls CommonConfig(HHCB). |
| `SCSIhGetMaxHardwareScbs(HHCB *)` returning uchar | `0x19275c` | Sole caller0x19271c forwards HHCB and stores returned byte. Uses handle+8, probes SCB bank register0x90 and RAM0xa0..a3, restores saved contents/control; capacity arithmetic is truncated to byte and returned in r3. |
| `SCSIhNonStandardGetConfig(HHCB *)` returning void | `0x192b6c` | Firmware slot124 at0x27aec0/27b110, same caller0x19201c. Writes byte HHCB+7=255 then forwards HHCB to CommonConfig; caller ignores r3. |
| `SCSIhGetCommonConfig(HHCB *)` returning void | `0x192b94` | Calls0x192744/192b80 explicitly pass HHCB and do not consume return, so the complete12-byte empty body retains that caller-proven pointer argument. No input-erasure exception added. |

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhGetHardwareConfiguration(HHCB *)` returning void | `0x192ba0` | Sole call0x192024 passes HHCB, ignores result. Uses handle+8, writes control byte16, max-target byte28,16 device records stride10; calls IDBasedConfiguration and hardware slots52/56/64 to populate FIFO/cache/latency flags and bytes. |
| `SCSIhGetIDBasedConfiguration(HHCB *)` returning void | `0x192e3c` | Sole call0x192cf0 passes HHCB, ignores r3. Uses capability word1376, flags12/212, chipID0, revision4, mode19 to set device flags/option bytes and EEPROM mode223. Only observable output is state/MMIO read effects. |
| `SCSIhStandard64SetupSequencer(HHCB *)` returning int0/-1 | `0x193124` | Firmware slot84 at0x27ad70; call0x192228 supplies HHCB, tests status. Body loads handle+8 and passes Seq_s64/2000 in r4/r5 to LoadSequencer0x193140, preserving status. |
| `SCSIhSwapping32SetupSequencer(HHCB *)` returning int0/-1 | `0x193154` | Firmware slot84 at0x27ae98, same caller; passes handle+8, Seq_w32,1772 to0x193170. |
| `SCSIhStandardAdvSetupSequencer(HHCB *)` returning int0/-1 | `0x193184` | Firmware slot84 at0x27afc0, same caller; passes handle+8, Seq_sAdv,2072 to0x1931a0. |
| `SCSIhSwappingAdvSetupSequencer(HHCB *)` returning int0/-1 | `0x1931b4` | Firmware slot84 at0x27b0e8, same caller; passes handle+8, Seq_wAdv,2256 to0x1931d0. LoadSequencer has explicit0 and-1 outcomes; these wrappers preserve them. |
| `SCSIhInitializeHardware(HHCB *)` returning void | `0x1931e4` | Sole call0x192260 supplies HHCB and ignores r3. Uses handle+8, hardware descriptor+244/config-byte115, threshold/cache/termination slots; optional firmware+180, PCI configuration read/write and final scratch write. Does not define a common result. |
| `SCSIhStartToRunSequencer(HHCB *)` returning void | `0x193554` | Sole call0x192288 passes HHCB, then executes sync and sets r3=0 itself. Body programs sequencer MMIO0x60/62/63/68/87 via handle+8 using firmware entry byte35, clears HHCB flags12 bit0x4000. |

All20 Configuration-owner declarations are accepted, including the four
termination helpers previously closed through hardware descriptor slots.

## Remaining hardware helpers

| Declaration | Entry | Caller and callee evidence |
| --- | --- | --- |
| `SCSIhLoadSequencer(const IOHandle *, const uchar *program, int byteCount)` returning int0/-1 | `0x19ebe0` | Four setup calls0x193140/170/1a0/1d0 supply handle pointer, static firmware bytes and exact length. Entry saves r3/r4/r5 at0x19ec04/08/0c. Signed count loops write each program byte to MMIO0x61 then verify byte reads; mismatch returns-1, success restores sequencer control and returns0. No program/handle storage writes. |
| `SCSIhWait4Req(HHCB *)` returning uchar phase/0xff | `0x19eed0` | Twenty callers including0x1944d8/19459c/1982c8/198380/199c40/19bcb4 pass HHCB, mask result to byte and compare phase. Callee loads handle+8, polls MMIO3/12 bounded by0x800000, returns0xff on timeout/bus error or phase bits0xe0. |
| `SCSIhSetupAssignScbBuffer(HHCB *)` returning void | `0x19f42c` | All four firmware slot132, optional call0x18e044 supplies HHCB and ignores result. Translates virtual buffer HHCB+208 via OSDGetBusAddress(category1), stores bus address+200 and size+204=firmware SCB stride*count byte7. |
| `SCSIhAIC78XXAutoTermCable(HHCB *)` returning uchar mask | `0x19f790` | Call0x1936cc passes HHCB, masks returned byte. Uses handle+8, CableSense result and MMIO0x1f width; explicit bitmask0/8/16/24 return. |
| `SCSIhCableSense(HHCB *)` returning uchar mask | `0x19f86c` | Calls0x193720/193760/19f7a8 pass HHCB, consume lowbyte. Uses handle+8, flags212 and hardware descriptor+244/slot80, PCI location; preserves/restores cable-control register and returns bounded cable bits/read byte. |
| `SCSIhSetAddressScbBA32(HHCB *, uchar offset, const uchar *virtualAddress)` returning void | `0x1a0474` | Calls0x18ca18/18cd34/195664/195b1c supply HHCB, byte register base, virtual SCB/sense-buffer pointer. Masks r4 at0x1a048c, replaces r4 with category1 while retaining r5 for address translation, writes translated32-bit address low-byte-first to four registers. No return consumed. |
| `SCSIhStandardResetCCCtl(HHCB *)` returning void | `0x1a0d8c` | Firmware slot232 at0x27ae04/27b054/27b17c; optional call0x18d28c passes HHCB, ignores return. Loads handle+8, writes zero to MMIO0xee/eb. |
| `SCSIhStandardInitCCHHAddr(HHCB *)` returning void | `0x1a0e28` | Firmware slot236 at0x27ae08/27b058/27b180; optional call0x18d2ac passes HHCB, ignores return. Loads handle+8, writes zero to MMIO0xe4..e7. |

Breakpoint callbacks share `void(HHCB *, uchar mask)`. Firmware slot256
set is called with HHCB/mask1 from abort/BDR paths0x18ef7c/18f2d0/18f3bc/
18f704/190f74/1910dc/1913f0/19155c and mask2 from0x19e7f0; slot260 clear
is called0x195f6c/195ffc/19e858 with mask1or2. All results are discarded.
Advanced bodies explicitly mask incoming r4 to8bits; older clear bodies
ignore this caller-proven common-slot mask. No convention/exception change.

| Declaration (shared signature above) | Entry / firmware word | Callee access evidence |
| --- | --- | --- |
| `SCSIhSwapping32SetBreakPoint` | `0x1a1d50` /0x27af44 | Masks r4 at0x1a1d78, handle+8, sets MMIO0x60 bit8, selects firmware word32or52 by mask1/2, writes breakpoint registers0x67/68. |
| `SCSIhSwappingAdvSetBreakPoint` | `0x1a1eb4` /0x27b194 | Masks r4 at0x1a1ec8; mask1/2 sets corresponding MMIO0x49 bit; no common result. |
| `SCSIhStandard64SetBreakPoint` | `0x1a1f88` /0x27ae1c | Masks r4 at0x1a1fb0; like Swapping32 but firmware word36 instead of32 for mask1. |
| `SCSIhStandardAdvSetBreakPoint` | `0x1a20ec` /0x27b06c | Masks r4 at0x1a2100; sets MMIO0x4a bit1or2. |
| `SCSIhSwapping32ClearBreakPoint` | `0x1a21c0` /0x27af48 | Full body ignores caller-supplied mask, loads handle+8 and writes MMIO0x68=0x80. Shared byte mask remains declared. |
| `SCSIhSwappingAdvClearBreakPoint` | `0x1a2214` /0x27b198 | Masks r4 at0x1a2228; clears selected bit1/2 in MMIO0x49. |
| `SCSIhStandard64ClearBreakPoint` | `0x1a22e8` /0x27ae20 | Full body ignores caller-supplied mask, writes MMIO0x68=0x80 through handle+8. |
| `SCSIhStandardAdvClearBreakPoint` | `0x1a233c` /0x27b070 | Masks r4 at0x1a2350; clears selected bit1/2 in MMIO0x4a. |

All61 Hardware-owner functions are accounted:60 normal declarations plus
the exact previously ruled ScamSupportCheck erasure.

## SCB delivery and queue-head contracts

These eight functions share `void(HHCB *, HIOB *)`. None of the actual
callers consumes r3. HIOB ownership stays with the active request/queue.

| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `SCSIhDeliverScb` | `0x18b754` | All four firmware slot92; HardwareQueueHIOB0x19da4c passes HHCB and active HIOB. Saves r3/r4 at0x18b76c/774, builds SCB, optional patch slot96 receives same pair, increments HHCB queue byte216 and writes firmware register64. |
| `SCSIhSwapping32PatchXferOpt` | `0x18b804` | Firmware word0x27aea4/slot96; calls0x18b7a0/1a605c explicitly pass HHCB/HIOB. Body ignores HHCB, follows HIOB.unit.device and descriptor.virtualAddress, writes SCB byte29 from device byte3; optional device flag0x2000 sets SCB byte1 bit4 and flushes32 bytes. |
| `SCSIhStandardAdvPatchXferOpt` | `0x18b85c` | Firmware word0x27afcc/slot96; same callers. Actual instructions use r4, not a Hex-Rays inferred64-bit sole argument: HIOB+24/+0, descriptor+12, unit+8, device halfword2; sthbrx stores to SCB+3. Caller-proven HHCB r3 is unused. |
| `SCSIhSwappingAdvPatchXferOpt` | `0x18b88c` | Firmware word0x27b0f4/slot96; same caller/input chain, byte-reversed halfword store at SCB+36. Same rejection of false64-bit decompiler signature. |
| `SCSIhStandard64QHead` | `0x18b8bc` | Direct calls0x18cabc/195710/196540 pass HHCB/HIOB. Saves both0x18b8e4/e8, uses handle+8, HIOB status7/SCB9 and unit target4, active arrayHHCB+1336; updates sequencer queue registers0x5e/5f/c6 and restores SCBPTR0x90. |
| `SCSIhSwapping32QHead` | `0x18bc6c` | Calls0x18cc48/19580c/19679c supply pair. Saves HHCB0x18bc98/HIOB0x18bca8; uses firmware register offsets60/65/66, HIOB bytes7/9 and unit target, slot220 next-number writes. |
| `SCSIhSwappingAdvQHead` | `0x18bf68` | Calls0x18cf64/195cec/197114 supply pair, saved0x18bf98/bfa8. Same queue state plus bounded command-channel MMIO0xee polling; slot216 gets next SCB and220 updates it; preserves incoming request pointer. |
| `SCSIhStandardAdvQHead` | `0x18c4ac` | Calls0x18cdd8/195bc8/196c44 supply pair, saved0x18c4d4/d8. Analogous queue manipulation at MMIO0x36/37/a5, request bytes7/9 and unit target4; restores SCBPTR. |

| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `SCSIhStandardRetrieveScb(HHCB *)` returning uchar number/0xff | `0x18c85c` | All four firmware slot104 at0x27ad84/27aeac/27afd4/27b0fc. No direct or slot104 invocation in476-body review (ISR paths inline queue handling). Body uses HHCB pointer r3, queue pointer196, index217/pass218/count7;8-byte ring entry byte7 is pass, byte0 number. Advances index/pass on match, explicit byte result or0xff. Live typed input/return are body-proven despite no caller. |
| `SCSIhStandardQoutcnt(const HHCB *)` returning uchar count | `0x18c8dc` | All four firmware slot108 at0x27ad88/27aeb0/27afd8/27b100; no direct or slot108 invocation in476-body review. Reads same ring/index/pass/count, iterates matching passes with byte-wrapped counter, returns count; does not mutate HHCB/ring. |
| `SCSIhStandard64QHeadBDR(HHCB *, HIOB *)` returning void | `0x18c954` | Firmware slot100 at0x27ad80; BreakInterrupt0x196098 passes HHCB/HIOB and ignores result. Entry saves pointers0x18c978/97c, follows HIOB descriptor+24/next+16 to number0/bus4/virtual12, adjusts new queue via firmware216/220/228, then QHead. |
| `SCSIhSwapping32QHeadBDR(HHCB *, HIOB *)` returning void | `0x18cae8` | Slot100 at0x27aea8, same caller. Saves HHCB/HIOB0x18cb08/18, descriptor.next gives replacement SCB number, hardware84 gives tail, firmware216/220 traverse/update, then QHead or producer increment. |
| `SCSIhStandardAdvQHeadBDR(HHCB *, HIOB *)` returning void | `0x18cc70` | Slot100 at0x27afd0, same caller. Saves inputs0x18cc94/98; same descriptor chain as Standard64, address register base32 instead of60, then StandardAdvQHead. |
| `SCSIhSwappingAdvQHeadBDR(HHCB *, HIOB *)` returning void | `0x18ce04` | Slot100 at0x27b0f8, same caller. Saves HHCB/HIOB0x18ce24/34, same byte-number queue traversal as Swapping32, dispatches SwappingAdvQHead. |
| `SCSIhResetChannelHardware(HHCB *)` returning void | `0x18cf8c` | Seven calls0x18eadc/192240/193c68/193d5c/193f14/193f6c/194a50 pass HHCB, ignore result. Loads handle+8, programs/reset-polls hardware, invokes hardware slots0/4/8 and optional firmware232/236, ends firmware120(HHCB). |
| `SCSIhAbortChannel(HHCB *, uchar status)` returning void | `0x18d2ec` | Calls0x18eae8/193c74/193f20/194a5c supply HHCB/status6/7/9/20. Masks r4 at0x18d31c; scans active pointer array+1336/count7, matches HIOB.unit.hhcb, writes status2/+5 and reason/+6, clears active slot to-1, calls ResourceCompleteHIOB. |

## SCB reset and scratch-address contracts

All eight routines return void: actual reset/init callers discard r3, which
is incidental MMIO/service output. Firmware slot88 is called at0x192258
with HHCB; slot120 at0x18d2c4 with HHCB. Allocation/queue ownership remains
with the adapter; reset initializes existing storage.

| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `SCSIhStandard64ResetSoftware(HHCB *)` | `0x18d39c` | Firmware slot88 word0x27ad74; saves HHCB0x18d3b8, CommonReset0x18d3c0. Builds target mask from16 device records stride10; free descriptor virtual+12 to scratch60/number0 to register68; qout pointer196 to scratch78, indices216..218 reset, fills8*(count7+1) ring bytes with0xff. |
| `SCSIhSwappingResetSoftware(HHCB *)` | `0x18d6f0` | Slot88 word0x27ae9c; saves HHCB0x18d70c, CommonReset0x18d718; free descriptor number to register64, queue pointer196 to scratch72, SCB buffer208 to scratch80; indices216..218 and ring initialized. |
| `SCSIhStandardAdvResetSoftware(HHCB *)` | `0x18d938` | Slot88 word0x27afc4; saves HHCB0x18d958, CommonReset0x18d964; descriptor virtual to scratch32/number to register58, qout196 to scratch40/48; initializes indices/ring and capacity register250, flag register77 from HHCB212 bit0x8000. |
| `SCSIhSwappingAdvResetSoftware(HHCB *)` | `0x18dccc` | Slot88 word0x27b0ec; saves HHCB0x18dce8, CommonReset0x18dcf4; descriptor number to register40, qout to scratch41/49, SCB buffer208 to scratch32; initializes same ring/index/capacity state. |
| `SCSIhCommonResetSoftware(HHCB *)` | `0x18dfd8` | Four calls above pass HHCB, ignore result. Initializes active-array pointer1336 for byte7 entries to-1, calls CheckSyncNego(HHCB), optional firmware132 SetupAssignScbBuffer(HHCB). |
| `SCSIhSetAddressScratchBA32(HHCB *, uchar offset, const uchar *virtualAddress)` | `0x18e05c` | Calls0x18d484/18d530/18d7cc/18d848/18d998/18da74/18da84/18ddd8/18dde8/18de30 supply pointer in r5. Entry0x18e074 masks r4 byte;0x18e078 replaces r4 with category1;0x18e07c loads HHCB handle8;0x18e080 OSDGetBusAddress consumes retained r5. Writes returned bus word little-endian to four consecutive registers. Hex-Rays omitted third formal; declaration preserves actual live input. |
| `SCSIhStandardResetBTA(HHCB *)` | `0x18e170` | Firmware slot120 words0x27ad94/27afe4; ResetChannelHardware caller0x18d2c4. Loops HHCB byte31 times invoking StandardIndexClearBusy(HHCB, index). |
| `SCSIhSwappingResetBTA(HHCB *)` | `0x18e1d0` | Slot120 words0x27aebc/27b10c, same caller; loops16 entries invoking SwappingIndexClearBusy(HHCB, index). |

## SCB busy-table and abort entry contracts



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhStandardTargetClearBusy(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x18e21c` | RequestSense callers0x195704/195bbc pass HHCB/HIOB and ignore result; entry saves r3/r4, follows HIOB.unit, byte9 SCB number and unit target4/lun5; indexes busy table, restores SCBPTR. |
| `void SCSIhSwappingTargetClearBusy(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x18e324` | Calls0x195818/195cf8 pass pair, ignore result; loads unit from r4, target byte4 to r4, forwards HHCB to SwappingIndexClearBusy. |
| `void SCSIhStandardIndexClearBusy(AdaptecU2HHCB *hhcb, unsigned char index)` | `0x18e34c` | ResetBTA0x18e1a4 and TargetClear0x18e2d0 pass HHCB/index; r4 stored as byte at0x18e374, MMIO SCBPTR144 then firmware byte56 selects register receiving0xff. No result consumed. |
| `void SCSIhSwappingIndexClearBusy(AdaptecU2HHCB *hhcb, unsigned char index)` | `0x18e3f0` | ResetBTA0x18e1f4 and TargetClear0x18e338; masks r4 to8bits0x18e40c, adds firmware byte56 to index, writes0xff. Callers ignore incidental r3. |
| `void SCSIhResetScsi(AdaptecU2HHCB *hhcb)` | `0x18e450` | Calls0x18eac8/192274/193ccc/193f0c/194a3c all pass HHCB and ignore result. Saves r3 at0x18e478, accesses handle8/firmware240/hardware244/flags12/device records32+10*i; performs reset/delay and marks16 device flag halfwords bit4. |
| `void SCSIhScsiBusReset(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x18ea28` | QueueSpecialHIOB0x19dacc passes HIOB union HHCB plus HIOB, ignores result. Saves r3/r4 at0x18ea40/48; selected active HIOB from HHCB1336 stored to reset HIOB+12; resets/aborts channel, firmware88 resets software, unpauses. |
| `void SCSIhBusDeviceReset(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x18eb98` | AbortTarget0x194d0c passes pair, ignores result. Scans active array1336/count7, excludes supplied HIOB, compares each unit HHCB and target; firmware192 called0x18ec20 with HHCB, matched HIOB, status8. No defined return across empty/nonempty scan. |
| `void SCSIhStandard64AbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x18ec54` | Firmware192 Standard64; callers0x18ec20/19dcfc/19de8c supply HHCB,HIOB,status8/4, ignore r3. Saves r3/r4 and masks r5 at0x18ec88. Uses HIOB byte9, status5/6, manager32; tests done/new/execution queues, terminates or requests breakpoint. Ownership/completion depends on queue path; no unconditional release. |

## SCB abort variants and done/new-queue searches



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhStandardAdvAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x18efa8` | Firmware192 word0x27b02c; callers0x18ec20/19dcfc/19de8c use HHCB/HIOB/status8or4, discard result. Entry0x18efcc/d0/dc saves pointers/masks r5; status5/6/manager32 and SCB9 accesses. Advanced SCB control register160 bit0x10 replaces Standard64 register195 bit8; same conditional completion ownership. |
| `void SCSIhSwappingAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x18f2fc` | Firmware192 word0x27af04, same three callers. Entry0x18f318/31c/320 establishes pair/byte; searches DoneQ then NewQ; status8 terminates, other status may set manager9 and breakpoint; r3 ignored. |
| `void SCSIhSwappingAdvAbortHIOB(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x18f3e0` | Firmware192 word0x27b154, same callers. Entry0x18f404/408/414 establishes pair/byte; command-channel MMIO238/241, firmware byte66 or register58 selects active SCB; control198 bit0x10, same queue/termination decisions; result ignored. |
| `unsigned char SCSIhStandardSearchSeqDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate)` | `0x18f730` | Firmware196 word0x27ade0 and direct0x196374; actual calls pass HHCB/HIOB/r5=1, mask returned byte and branch. Entry0x18f760/768/76c reads handle/save HIOB/masks r5. Searches register112-linked SCBs through198, unlinks matching HIOB9; if terminate nonzero sets status0/manager1 and completes, returns0/1. |
| `unsigned char SCSIhStandardAdvSearchSeqDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate)` | `0x18f984` | Firmware196 word0x27b030 and direct0x196a7c; same three arguments and byte result consumption. Entry0x18f9b4/bc/c0 saves HIOB/handle/masks r5; analogous queue at registers56/165, conditional termination and explicit0/1. |
| `unsigned char SCSIhStandardSearchDoneQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x18fbd8` | Eight direct calls0x18ee7c/18f1d0/18f324/18f6f0/19638c/196738/196a94/1970b4 pass pair, mask r3 byte and branch. Reads HHCB196/217/218/count7 and HIOB9, compacts8-byte ring, advances consumer/pass, sets HIOB status0/manager1 and terminates on match; decrements HHCB222, returns0/1. |
| `unsigned char SCSIhStandard64SearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x18fd60` | Firmware204 word0x27ade8; caller0x18eea8 passes HHCB/HIOB/status and masks returned byte. Entry0x18fd90/94/b4 saves pointers/masks r5. Traverses active array1336 using firmware216, compares HIOB9, writes status5/6/manager32; marks head abort or unlinks via216/220/224/228 and terminates. Explicit0/1 result. |
| `unsigned char SCSIhStandardAdvSearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x18ffac` | Firmware204 word0x27b038; caller0x18f1fc same three arguments and byte-result branch. Entry0x18ffdc/e0/190000 saves pair/masks r5. Same pointer/field/queue ownership contract as Standard64 with mode descriptor callbacks; explicit0/1. |

## SCB next-number accessors



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `unsigned char SCSIhSwappingSearchNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x1901f8` | Direct0x18f344/18f70c pass pair/status, mask byte result. Saves r3/r4, masks r5; queue tail hardware84 and producer216 delimit traversal, HIOB9 matches; status5/6/manager32 set, head abort or unlink/terminate, explicit0/1. |
| `unsigned char SCSIhStandard64ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)` | `0x190408` | Firmware216 Standard64; actual0x18ca38/18fea8/18ff58 passes HHCB/HIOB and masks byte result. Entire body follows r4+24 descriptor+12 virtual, lbz SCB38 to r3. Caller-proven HHCB is ignored, no semantic guess. |
| `unsigned char SCSIhSwapping32ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)` | `0x190424` | Firmware216 Swapping32; actual0x18cc18/190350/1919f0 passes pair, masks byte result. Full body follows r4+24/+12 and lbz SCB28; HHCB ignored. |
| `unsigned char SCSIhStandardAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)` | `0x190440` | Firmware216 StandardAdv; calls0x18cd54/1900f4/1901a4 pass pair, mask result. Full body follows r4+24/+12 and lbz SCB5; HHCB ignored. |
| `unsigned char SCSIhSwappingAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)` | `0x19045c` | Firmware216 SwappingAdv; calls0x18c298/18cf34/191e10 pass pair, mask result. Full body follows r4+24/+12 and lbz SCB11; HHCB ignored. |
| `void SCSIhStandard64UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)` | `0x190478` | Firmware220 Standard64; calls0x18ca70/18fef8 pass HHCB/HIOB/byte number and discard result. Full body follows r4+24/+12, stb r5 SCB38, flushes64 bytes; HHCB unused. |
| `void SCSIhSwapping32UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)` | `0x1904a8` | Firmware220 Swapping32; calls0x18be08/18cbe0/190378 pass pair/byte number, ignore result. Full body stores r5 at SCB28 through r4 descriptor, flushes32 bytes; HHCB unused. |
| `void SCSIhStandardAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)` | `0x1904d8` | Firmware220 StandardAdv; calls0x18cd8c/190144 pass pair/number, ignore result. Full body stores r5 at SCB5 through descriptor, flushes64 bytes; HHCB unused. |

## SCB bus-address and execution-queue contracts



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhSwappingAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)` | `0x190508` | Firmware220 SwappingAdv; actual0x18c2c0/18cefc/191e84 passes HHCB/HIOB/byte, ignores result. Whole body follows r4+24/+12, stores r5 byte SCB11, flushes64; known HHCB unused. |
| `unsigned int SCSIhStandard64ObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)` | `0x190538` | Firmware224; call0x18fec8 passes pair and preserves full r3 for slot228. Body follows r4+24/+12, lwbrx SCB40 to r3 at0x190554. Returns32-bit bus address (not CPU pointer); HHCB unused. |
| `unsigned int SCSIhStandardAdvObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)` | `0x190564` | Firmware224; call0x190114 passes pair and preserves r3 for228. Body follows r4+24/+12, lwbrx SCB32 at0x190580;32-bit bus address, HHCB unused. |
| `void SCSIhStandard64UpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress)` | `0x190590` | Firmware228;0x18ca98 passes descriptor bus+4,0x18ff20 passes ObtainNextScbAddress word in r5; pair r3/r4. Body stwbrx r5 into SCB40 at0x1905b0, flush64, callers ignore result; HHCB unused. |
| `void SCSIhStandardAdvUpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress)` | `0x1905cc` | Firmware228;0x18cdb4 descriptor bus+4 and0x19016c accessor word passed r5 with pair. Body stwbrx r5 into SCB32 at0x1905ec, flush64; result ignored, HHCB unused. |
| `unsigned char SCSIhStandard64SearchExeQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate)` | `0x190608` | Firmware208 calls0x18ef0c/19743c plus direct0x196358 pass HHCB/HIOB/status8orHIOB6/terminate1or0, mask byte result. Entry masks r5/r6 at0x19064c/654; traverses SCB queue registers94/95/198, unlinks match, writes HIOB5/6/32, optionally terminates;0/1 result. |
| `unsigned char SCSIhStandardAdvSearchExeQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate)` | `0x1908ec` | Firmware208 calls0x18f260/19743c plus direct0x196a60 same four arguments/byte result. Entry masks r5/r6 at0x190930/938; same unlink/completion contract with registers54/55/165;0/1 result. |
| `void SCSIhStandard64UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x190bc0` | Firmware212; caller0x18fe38 passes pair and discards result. Entire body ignores known HHCB r3, follows r4+24/+12, ORs SCB35 bit8, flushes64; no request ownership transfer. |

## SCB abort flags and device-reset setup



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhStandardAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x190bfc` | Firmware212 caller0x190084 passes pair, discards result; body r4+24/+12 yields SCB, byte0 OR0x10, flush64; known HHCB unused. |
| `void SCSIhSwapping32UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x190c38` | Firmware212 caller0x1902e4 passes pair, discards result; body follows r4 descriptor virtual, byte0 OR8, flush32; HHCB unused. |
| `void SCSIhSwappingAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x190c74` | Firmware212 caller0x1902e4 passes pair, discards result; body follows r4 descriptor virtual, byte38 OR0x10, flush64; HHCB unused. |
| `void SCSIhStandard64SetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x190cb0` | Firmware248 word0x27ae14; QueueSpecial0x19daf0 passes HHCB from HIOB.unit.hhcb/r4HIOB, ignores return. Saves pair0x190cdc/ce0; clears40 hardware SCB bytes, uses target/lun unit4/5, inserts HIOB into active array1336 indexed HIOB9, manager32=10, sets breakpoint; request remains active. |
| `void SCSIhSwapping32SetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x190fbc` | Firmware248 word0x27af3c, same caller; saves pair0x190fe4/fe8, clears32 SCB bytes at descriptor.virtual12, fills control1/target2/lun31/message3..5/next28; activates HIOB and flushes32, manager10/breakpoint; no ownership release. |
| `void SCSIhStandardAdvSetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19111c` | Firmware248 word0x27b064, same caller; pair saved0x19114c/150, target combined with HHCB hostID byte30, clears40 hardware SCB bytes, fields0/1/2/6/8/9; active array and manager10/breakpoint, result ignored. |
| `void SCSIhSwappingAdvSetupBDR(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19143c` | Firmware248 word0x27b18c, same caller; pair saved0x191464/468; clears64 virtual SCB bytes, control38,target12,lun13,message14/16/17,next11; active array/manager10, flush64, breakpoint, result ignored. |
| `void SCSIhStandard64StackBugFix(AdaptecU2HHCB *hhcb)` | `0x19159c` | Firmware244 word0x27ae10; callers0x18ea6c/193cec pass HHCB, ignore r3. Entry byte18 and handle8 dereferences, reads8 sequencer stack bytes from register111, optional ninth read and register99 clear according to pattern; no defined return (HHCB or service residue). |

## SCB freeze and recovery interrupt contracts



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhSwapping32FreezeHWQueue(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1917b8` | Firmware272 word0x27af54; calls0x1940e0/194708/194da0/1950f4/1952b8 supply HHCB/HIOB, ignore result. Saves pair0x1917e8/ec, event1 start/event2 finish. Compares target through unit4, unlinks matching active/new requests, status5=5, completes normal/special by command4; queue ownership transferred only for removed requests. |
| `void SCSIhSwappingAdvFreezeHWQueue(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x191b24` | Firmware272 word0x27b1a4, same callers; pair saved0x191b54/58. Same target/queue/ownership contract, selected SCB register57 and additional command-channel238 cancellation; events bracket completion. |
| `void SCSIhIntSrst(AdaptecU2HHCB *hhcb)` | `0x193bb8` | BackEndISR0x1a6a44 passes HHCB, ignores result. Saves r3 at0x193bd8, handle8/firmware240/hardware244, resets/aborts status7, marks16 device records,4000 delays, restores HCNTRL byte221, sync before events1/7. |
| `void SCSIhIntIOError(AdaptecU2HHCB *hhcb)` | `0x193ea0` | BackEndISR0x1a6a84 passes HHCB, ignores result. Saves r3 at0x193ec0, uses handle8, reset/abort status9,4000 delays, flag12 and HCNTRL221, sync then events8/7. |
| `void SCSIhCheckLength(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x194074` | BackEndISR0x1a6bac passes pair and ignores result. Saves r4/r3 at0x194098/a0; HIOB flags8/unit.resource40, optional firmware272, residue252 written HIOB20 or sense-residue17, status6=18; phase-specific MMIO/delay paths have incidental r3. |
| `void SCSIhCdbAbort(AdaptecU2HHCB *hhcb)` | `0x19431c` | BackEndISR0x1a6bb8 passes HHCB, ignores result. Entry saves r3 at0x194334 and loads handle8; phase checks/Wait4Req and BadSeq paths, firmware19/47 sequencer entry bytes, no common return value. |
| `void SCSIhCheckCondition(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19462c` | BackEndISR0x1a6be8 passes pair, ignores result. Entry0x194650/658 saves pointers; HIOB manager32/status7/flags8, target/unit/device and resource40; freezes, invokes RequestSense116 or ClearBusy112+Terminate, then sequencer register reset. Request ownership depends on sense versus completion. |
| `void SCSIhBadSeq(AdaptecU2HHCB *hhcb)` | `0x1949d0` | Eight calls0x1944f4/194d20/195270/198bc4/199d18/19ba34/19bc0c/1a6bf4 pass HHCB, ignore result. Saved0x1949e4; handle8/firmware240/HCNTRL221; phase path just restarts sequencer, otherwise resets/aborts status20 and sync before events3/7. |

## Recovery phase and sense-request contracts



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhAbortTarget(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x194bd4` | Calls0x199c08/1a6c24 pass pair and ignore result. Entry saves r3/r4 at0x194bec/bf4; permits HIOB sentinel-1 before manager32 dispatch to firmware240/BusDeviceReset; other path BadSeq. No common result. |
| `void SCSIhIntSelto(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x194d40` | BackEndISR0x1a6c58 passes pair, ignores result. Saves r4/r3 at0x194d5c/64; dereferences HIOB flags8/unit before late sentinel-1 check (historical behavior retained); device negotiation/freeze/ClearBusy112, status6=17, Terminate. |
| `void SCSIhIntFree(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x194eb8` | BackEndISR0x1a6c70 passes pair, ignores result. Saves0x194ed4/d8, programs MMIO and firmware sequencer word32; HIOB sentinel-1 is checked before flags8/unit.resource40, freeze/ClearBusy112, status6=19 and Terminate. |
| `void SCSIhParityError(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x195144` | BackEndISR0x1a6c88 passes pair, ignores result. Entry r4 sentinel-1 test0x195164 and HHCB save0x195168. Sentinel path BadSeq; live request flags8/resource40, sets message44=5or9 and optional parity43, status6=72; no unconditional completion. |
| `void SCSIhStandard64RequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1953d4` | Firmware116 CheckCondition caller0x194740 supplies pair, ignores result. Saves HIOB/HHCB0x1953f8/400; manager32=7, writes40 hardware SCB bytes and sense CDB, HIOB12 sense virtual pointer passed to bus translation with length byte16; ClearBusy/QHead retains request for sense. |
| `void SCSIhSwapping32RequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19573c` | Firmware116 same caller; saves pair0x195758/75c, descriptor virtual12, HIOB sense12/length16/manager32. SCB CDB8..19, little-endian bus20 and count24; QHead/ClearBusy and flush32, request retained. |
| `void SCSIhStandardAdvRequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x195848` | Firmware116 same caller; saved HHCB/HIOB0x195870/878, hostID30+unit.target4, manager7;40 hardware SCB bytes, CDB register176..181, sense virtual12 to address200/count204; ClearBusy/QHead retains request. |
| `void SCSIhSwappingAdvRequestSense(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x195bf8` | Firmware116 same caller; saved HIOB/HHCB0x195c14/1c, descriptor virtual, sense12/length16/manager32; SCB CDB24..35, little-endian bus0/count4, mode bits12/13/38; QHead/ClearBusy flush64, request retained. |

## Recovery completion and active-abort callbacks



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhTerminateCommand(AdaptecU2HIOB *hiob)` | `0x195d28` | Fifteen calls including0x18ef30/18f284/194768/194e94/195120 pass HIOB and discard r3; entry0x195d44 saves r3, follows unit.hhcb, clears active array1336 at number9, SetStat then ResourceCompleteHIOB or Special by command4. Completion transfers ownership; no further request use implied. |
| `void SCSIhSetStat(AdaptecU2HIOB *hiob)` | `0x195e48` | Only caller0x195d68 retains live HIOB r3 from entry and ignores result. Full leaf body reads bytes5/6/7, maps status and sometimes clears6; r3 physically unchanged but no pointer-return contract used or required. |
| `void SCSIhBreakInterrupt(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x195f20` | BackEndISR0x1a6c34/1a6ca4 passes pair and ignores r3. HHCB212 flags control breakpoint256/260; conditional r4.unit.device updates flags; scans active array1336/count7, manager9 invokes188 and manager10 invokes100. No common return. |
| `void SCSIhStandard64ActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1960d0` | Firmware188 called0x196070 with pair, result ignored. Saves0x1960f0/f4; handle8,HIOB9/flags8/status5/6/manager32; active transfer registers53/235/238/147 may defer, selected52 marks control195 bit8, searches queues or QHead message abort. Completion only through successful searches. |
| `void SCSIhSwapping32ActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1965a0` | Firmware188 same caller. Saves0x1965c0/c4; selected register86 marks hardware control160 bit8; otherwise DoneQ search or descriptor.virtual SCB0/1 bits8,message4/5 selected by HIOB flags0x4000,QHead flush32; manager2/5. |
| `void SCSIhStandardAdvActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1967d8` | Firmware188 same caller. Saves0x1967f8/fc; same conditional defer/search/requeue as Standard64 using registers61/60/control160 bit0x10,message168/169; HIOB9/flags8/status5/6/manager32; no unconditional release. |
| `void SCSIhSwappingAdvActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x196ca4` | Firmware188 same caller. Saves0x196cc4/c8; active58/selected57/command-channel238 paths, control198 bit0x10; otherwise DoneQ or virtual SCB38/message16/17,QHead flush64; manager1/2/5, result ignored. |
| `void SCSIhSwappingRemoveActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x197150` | Firmware240 caller0x194cec supplies pair and ignores result. Saves0x197174/178; compares selected/active firmware register bytes60/59, cancels selection and manager32=1 or invokes RemoveAbortHIOBFromNewQ(HHCB,HIOB,status6) then manager1 if found. Does not itself complete request. |

## Recovery residue and abort-removal contracts



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhStandardRemoveActiveAbort(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1972dc` | Firmware240 caller0x194cec passes pair, ignores result. Saves0x197300/304; selected/active-register comparison cancels selection and manager32=1, else slot208(HHCB,HIOB,status6,terminate0), marks manager1 on found. Does not complete request. |
| `unsigned int SCSIhStandard64ResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19747c` | Firmware252 caller0x194144 passes pair, stores full r3 to HIOB20 or lowbyte17. Saves0x1974ac/b0; reads24-bit residual/count and bus pointer via MMIO174/188/176 or160/166, obtains HIOB SG descriptor via OSDGetSGList. Walks8-byte SG entries using little-endian countword+4 low24bits, bit31 terminates, adds counts modulo32bits; zero/no-data or byte count result. |
| `unsigned int SCSIhSwapping32ResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x197754` | Firmware252 same caller/result use. Saves0x197780/784; MMIO163 flag,count184/168,address164/173; HIOB SG descriptor bus0/virtual8 and8-byte little-endian length24/last-bit31 entries. Full32-bit count sum, no signed comparison of returned residue. |
| `unsigned int SCSIhStandardAdvResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1979c0` | Firmware252 same caller. Saves0x1979f0/f4; flags167,count204/176,address168/182,index167/181; same SG bus/virtual/stride8/low24length/bit31 traversal, returns32-bit residue or0. |
| `unsigned int SCSIhSwappingAdvResidueCalc(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x197c58` | Firmware252 same caller. Saves0x197c88/8c; flags175,count164/184,address176/189,index175/188; same SG traversal/32-bit count result. |
| `unsigned char SCSIhSwappingRemoveAbortHIOBFromNewQ(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status)` | `0x197ef0` | Direct0x19729c passes HHCB/HIOB/status from byte6, masks returned byte and branches. Entry0x197f20/30/34 saves pair/masks r5; traverses new queue using firmware216/220 and HHCB1336/216, writes status5/6, unlinks without terminating, returns0/1. |

## Negotiation message state contracts



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhNegotiate(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x198100` | ISR0x1a6bd8 passes pair and ignores result; saves0x198120/124, unit target4/device8, HHCB handle8/firmware240/hardware244, HIOB negotiation33; sends pending response or initiates wide/sync. Incidental phase/service results have no caller use; ownership retained. |
| `void SCSIhExtMsgi(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x198464` | HandleMsgIn0x199b54 and ISR0x1a6c04 pass pair; consumers check HIOB34 or ignore, not r3. Saves HHCB/HIOB0x19847c/48c; reads length firmware58, ReceiveMessage, dispatches HIOB35/33 to verify/respond/modify-pointer184; failure flag34=1. |
| `void SCSIhInitiateWide(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1985a4` | Negotiate0x1982c0 passes pair then overwrites r3 for Wait4Req. Body follows r4.unit.device, flags halfword0 bit0x200, writes HIOB33/35..38, calls SendMessage with count4; no consumed return. |
| `void SCSIhVerifyWideResponse(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x198614` | ExtMsgi0x198538 passes pair, result not observed by either ExtMsgi caller. Saves pair0x19863c/640, gets option firmware156(targetbyte), HIOB36 selectswide/narrow offset hardware12/16, assigns option144; optional InitiateSync, otherwise clears negotiation33. |
| `void SCSIhInitiateSync(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char offset)` | `0x198884` | Calls0x19843c/19881c pass pair and offset from hardware12/16 byte-result, no ultimate return use. Saves pair0x1988a4/a8, r5 retained then stored HIOB39 (or0 if device flag0x400 clear), fills message35..38, SendMessage count5/phase handling; no defined result. |
| `void SCSIhVerifySyncResponse(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x198a5c` | ExtMsgi0x198550 passes pair; result not observed. Saves0x198a78/7c; unsigned HIOB period36/offset37 compared hardware max ushort116, rejected message/BadSeq or hardware24 rate calculation, firmware144 assign/168 fast map; clears33, sets34 on success. |
| `void SCSIhRespondToWide(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x198d08` | ExtMsgi0x19856c passes pair; no observed result. Saves0x198d2c/30; compares byte36 with hardwarewide capability, device flags0/4, HHCB212 bit0x80000; fills outgoing35..38 and state33=3/34=1, writes attention, retains request. |
| `void SCSIhRespondToSync(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x198e88` | ExtMsgi0x198584 passes pair; no observed result. Saves0x198eb4/bc; clamps HIOB36/37 period/offset through hardware12/16/20/24 and max116, updates firmware144/168, device flags, HHCB212, outgoing35..39, state33=4/34=1; retains request. |

## Negotiation message transfer and Fast20 queries



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhSendMessage(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, int count)` | `0x1990e4` | Five calls0x19824c/198260/198600/198928/1997d4 pass pair/count4or5; no ultimate result use. Entry saves full r5 at0x199120, signed count-1 compare/loop, reads HIOB35+index, MMIO handshake; restores saved transfer-count registers. Count is signed32, not byte guessed from values. |
| `int SCSIhReceiveMessage(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, int count)` | `0x1993d8` | Calls0x1984c8/199ad4 pass pair/count from byte or1, consume low8 returned count. Entry r5 saved0x199408, signed cmpw0x199410, writes HIOB35+index; returns full incrementing32-bit count or0. Declaration retains full machine count; caller narrowing is explicit, original return typedef spelling unclaimed. |
| `void SCSIhHandleMsgOut(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x199708` | ISR0x1a6bc8 passes pair, ignores r3. Saves0x19972c/730; HIOB negotiation33/parity43/message44 and HHCBmode18/handle8; sends pending count4/5 or one message byte, waits ACK; no defined return. |
| `void SCSIhHandleMsgIn(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x1999e8` | Calls0x19b36c/19b6b0/1a6c14 pass pair and ignore result. Saves0x199a08/0c, phase/message MMIO, HIOB35 message/state34, ExtMsgi/AbortTarget/BadSeq/hardware96; no uniform result or ownership transfer. |
| `unsigned char SCSIhStandardGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19a15c` | Firmware160; calls0x19e4e4/1a1494 pass HHCB/byte target, narrow result. Entry masks r4 at0x19a16c, target>7 selects firmware74 instead73, shifts bit and tests MMIO; returns0/1. |
| `unsigned char SCSIhStandardAdvGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19a1f0` | Firmware160 actual callers0x19e4e4/1a1494 prove HHCB/target positions despite body erasure. Entire16-byte body returns0; common slot type retained, no new unspecified-argument exception. |
| `unsigned char SCSIhSwappingGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19a200` | Firmware160 same callers; masks r4 at0x19a204, reads device halfword HHCB32+10*target, extracts0x2000 bit to0/1 result. |
| `unsigned char SCSIhSwappingAdvGetFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19a228` | Firmware160 actual callers0x19e4e4/1a1494 prove typed pair; entire16-byte body returns0, common slot signature retained; not an uncalled erasure exception. |

## Negotiation Fast20 updates and option assignment



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhStandardClearFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19a238` | Firmware164 calls0x198220/1982a8 pass HHCB/target, no result use. Entry masks r4 at0x19a254, selects firmware register73/74 by target>7, clears target mask and register1 bit0x20. |
| `void SCSIhSwappingClearFast20Reg(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19a3a0` | Firmware164 same callers. r4 mask0x19a3c0, clears device flag0x2000 at32+10*target, invokes176(HHCB,0), scans active1336/count7 matching unit target then172(HHCB,HIOB,0); clears MMIO1 bit0x20, no result use. |
| `void SCSIhStandardLogFast20Map(AdaptecU2HHCB *hhcb, unsigned char target, unsigned char period)` | `0x19a4ec` | Firmware168 calls0x198b34/199028 pass HHCB/target/period, ignore result. Masks r4/r5 at0x19a520/528; unsigned period>24 selects clear versus set target map73/74 and MMIO1 bit0x20. |
| `void SCSIhSwappingLogFast20Map(AdaptecU2HHCB *hhcb, unsigned char target, unsigned char period)` | `0x19a6c4` | Firmware168 same callers; masks r4/r5 at0x19a6ec/6f4. Period>24 sets/clears device0x2000, updates HW176 flag0/1 and matching active HIOB172 flag0/1, writes MMIO1; no release or result. |
| `void SCSIhSwapping32UpdateFast20HostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char enabled)` | `0x19a8e4` | Firmware172 calls0x19a458/19a7c4/19a878 pass HHCB/matched HIOB/0or1, ignore result. r3 unused known HHCB; r4+24/+12 virtualSCB, masks r5 at0x19a8f4, sets/clears SCB1 bit4, flush32. |
| `void SCSIhSwapping32UpdateFast20HW(AdaptecU2HHCB *hhcb, unsigned char enabled)` | `0x19a93c` | Firmware176 calls0x19a400/19a76c/19a820 supply HHCB/0or1, ignore result. Masks r4 at0x19a954, loads handle8, sets/clears hardware SCB register161 bit4. |
| `void SCSIhCheckSyncNego(AdaptecU2HHCB *hhcb)` | `0x19a9ec` | CommonReset0x18e024 passes HHCB, ignores result. Saved0x19aa00, countbyte28,16 device record flags byte36+10*i; firmware144(HHCB,target,0x8f or0). No defined result for empty/nonempty loop. |
| `void SCSIhStandardXferOptAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option)` | `0x19aa94` | Firmware144 callers0x1981fc/198284/198b0c/199000 supply HHCB/byte target/option halfword, discard result. Entry sth r5 at0x19aaac homes actual16-bit formal, masks r4 at0x19aab4; this mode reads low byte of halfword to firmware61+target and optional register4, clears HHCB212 flag0x80000. Do not narrow common option contract to decompiler char. |

## Negotiation shared halfword-option callbacks



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhHostXferOptAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option)` | `0x19ab58` | Firmware144 caller0x198b0c/199000 passes three arguments, ignores result. r4/r5 masks0x19ab84/88 prove byte/halfword; forwards148(HHCB,target,option)0x19aba0 then152(HHCB,activeHIOB,option)0x19abf8 matching unit target. Hex-Rays omitted live third input; preserve it. |
| `void SCSIhChkCondXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option)` | `0x19ac30` | Firmware140 in three non-Standard64 modes. Entry saves r3, masks r4/r5 at0x19ac64/68; calls1480x19ac80, walks newqueue from hardware84/firmware66 through descriptor.next and updates1520x19ad1c with option. No direct caller; typed live input/side-effect contract follows full body and shared callback domain, no original return spelling claim. |
| `void SCSIhSwapping32CommonXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option)` | `0x19ad70` | Firmware148 callers0x19aba0/19ac80 pass HHCB/target/option, discard result. Masks target0x19ad98, homes r5 halfword0x19adac and stores device option34+10*target; mode writes lowbyte hardware189/4, restores pause state. |
| `void SCSIhStandardAdvCommonXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option)` | `0x19af7c` | Firmware148 same callers; targetmask0x19af98 and halfword home0x19afac/device store0x19afb8. Compares selected target at161, writes option low/high to163/164 and hardware0 if flag0x80000; no return use. |
| `void SCSIhSwappingAdvCommonXferAssign(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option)` | `0x19b0a8` | Firmware148 same callers; targetmask0x19b0c4 and halfword home0x19b0d8/device store0x19b0e4. Selected target172, option low/high196/197, optional hardware0; no return use. |
| `void SCSIhSwapping32UpdateXferOptionHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option)` | `0x19b1d4` | Firmware152 calls0x19abf8/19ad1c pass HHCB/HIOB/halfword, ignore result. Entire body homes r5 halfword0x19b1e0, reads lowbyte and stores SCB29 through r4+24/+12, flush32; known HHCB ignored. |
| `void SCSIhStandardAdvUpdateXferOptionHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option)` | `0x19b20c` | Firmware152 same callers; masks r5 to16 at0x19b220, sthbrx SCB3 at0x19b230 through HIOB descriptor, flush64; HHCB ignored, no return use. |
| `void SCSIhSwappingAdvUpdateXferOptionHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option)` | `0x19b24c` | Firmware152 same callers; masks r5 to16 at0x19b260, sthbrx SCB36 at0x19b270, flush64; HHCB ignored, no return use. |

## Negotiation option queries and modify-data callbacks



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `unsigned short SCSIhStandardGetOption(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19b28c` | Firmware156; callers198668/198ac4/198efc mask returned low16 and19e4b4 stores halfword. Entry masks r4 byte; reads MMIO at firmware byte61 + target through HHCB8. Byte-valued implementation satisfies the observed common unsigned-halfword slot. |
| `unsigned short SCSIhHostGetOption(AdaptecU2HHCB *hhcb, unsigned char target)` | `0x19b2e8` | Same firmware156 callers; entry masks r4 byte and lhz r3 at HHCB34+10*target, no sign extension. |
| `void SCSIhStandard64ModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19b30c` | Firmware184 invoked198508 with HHCB/HIOB, continuation ignores result. Entry retains r3/r4; HIOB36 delta and HHCB8 IO handle used. MMIO172 flag selects HandleMsgIn; otherwise updates address bytes; final write result is incidental. |
| `void SCSIhSwapping32ModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19b650` | Same slot184/caller198508. Entry retains r3/r4, HIOB36 delta; MMIO161 flag selects HandleMsgIn, updates address bytes and sequencer address. Caller ignores result. |
| `void SCSIhStandardAdvModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19b994` | Same slot184/caller198508 supplies both typed pointers. Entire body discards HIOB r4; HHCB8/240 accessed; phase handshake rejects modification and resets sequencer, result ignored. Common slot establishes otherwise erased second formal position. |
| `void SCSIhSwappingAdvModifyDataPtr(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)` | `0x19bb6c` | Same slot184/caller198508 supplies both pointers. HIOB argument discarded in full body; HHCB8/240 drives rejection handshake. Typed caller establishes the slot, not decompiler one-argument guess. |
| `void SCSIhSwappingClearAllFast20Reg(AdaptecU2HHCB *hhcb)` | `0x19bf64` | Firmware180 invoked1933d0 with HHCB and no result use. Iterates16 device records at32+10*i clearing halfword bit0x2000; physical r3 preserved but not a defined result. |
| `void SCSIhStandard64ClearAllFast20Reg(AdaptecU2HHCB *hhcb)` | `0x19bfa0` | Firmware180/caller1933d0; accesses HHCB8/240, writes zero MMIO registers selected by firmware bytes73/74. Final MMIO call result unused. |

## Negotiation SG update callbacks



| Declaration | Entry | Caller/slot and callee evidence |
| --- | --- | --- |
| `void SCSIhStandardAdvUpdateSGLength(AdaptecU2HHCB *hhcb, unsigned int length)` | `0x19c7b4` | Firmware264; actual19c598 indirect call loads r11 slot, HHCB r3 and reconstructed32-bit MMIO count plus residue r4. Entry stw r4 home; emits low24bits to MMIO204..206; caller ignores result. |
| `void SCSIhSwappingAdvUpdateSGLength(AdaptecU2HHCB *hhcb, unsigned int length)` | `0x19c87c` | Same firmware264/caller19c598 fullword count. Entry homes r4 word and emits low24bits to MMIO164..166. Fullword carrier preserves all input bits; high8 discarded, no signed use. |
| `void SCSIhStandardAdvUpdateSGAddress(AdaptecU2HHCB *hhcb, unsigned int busAddress)` | `0x19c944` | Firmware268; actual19c790 indirect call passes HHCB r3 and fullword MMIO bus address minus residue r4. Entry homes r4 word; writes all4bytes to MMIO200..203; no pointer dereference or result consumption. |
| `void SCSIhSwappingAdvUpdateSGAddress(AdaptecU2HHCB *hhcb, unsigned int busAddress)` | `0x19ca40` | Same firmware268/caller19c790 full32-bit bus address integer. Entry homes r4 word; writes all4bytes to MMIO160..163. Result ignored; CPU pointer interpretation would be unsupported. |

## Firmware descriptor contract

The four data objects at0x27ad1c/0x27ae44/0x27af6c/0x27b094 each occupy296 bytes. Their first84 bytes are sequencer constants and byte register selectors, preserved without inferred source member names as14 words and28 bytes. Offsets84..292 contain51 populated callback positions plus two all-mode zero words136/276; these zero words do not acquire invented callable contracts. Every populated position uses the corresponding reviewed declaration above; each mode initializer is checked against the exact slot type. HHCB240 holds this descriptor, HHCB244 the120-byte hardware descriptor. Constant registers are numeric data even when IDA associates their value with an unrelated address.

## Complete indirect-call closure

The full frozen 476-body disassembly contains 307 indirect branches:
264 with nearest target write from r0 into LR, 22 r0 into CTR, 12 r9 into LR,
four r11, four r28 and one r10. All 312 non-epilogue LR/CTR writes were also
reviewed, including alternative predecessors at joined calls. Their target
sources are 286 constant-offset loads, 22 switch-address additions, and four
conversion-helper address selections. The latter selections have two paths;
both addresses were followed. The short r0/window scanner used to locate
firmware callers was only a navigation aid, never the closure criterion.
The complete scans and disassembly remain ignored in task3/
`all-indirect-calls.json`, `all-target-writes.json`, and `disassembly.json`.

In particular the r11 calls at 0x19c598/0x19c790 reach firmware offsets264/268;
the r9 address-adjust calls in all four SCB builders reach adapter1580;
the r28 calls in string conversion paths reach the six conversion helpers.
The r10 call in VerifyAdapter reaches adapter1660 (PCI read), not an erased
service. The load at adapter1620 (0x654) is OSMWriteUExact8 and is copied to
adapter1724; 0x654 relative to HHCB would instead mean adapter1644, so offset
matching without proving the base would falsely report SynchronizeRange.
No reviewed call reaches OSM offsets1644/1652/1656 (slots21/23/24), nor the
eight erased HIM slots. The three additional erased CHIM bodies have no
call or stored-code-pointer occurrence beyond their symbol records. Thus the
eleven CHIM and separate three OSM exceptions remain exact; no new exception
was inferred from a missing direct xref. IOB+52 callbacks, adapter+1736 builders,
copied register accessors, hardware/firmware tables, cached Objective-C IMPs,
and switch destinations were included. This is closure over this pinned
image's scoped callers and stored tables, not a claim about external binaries.

## Shared storage, unions and ownership

All numeric offsets here are target bytes. `layout-contracts.json` records
273 member offsets in the 19 final structure views, in addition to the earlier
configuration/profile/descriptor/table constants. Every size/offset is emitted
by the historical PPC compiler and read from its big-endian object, never
calculated using the host C layout. Names absent from metadata are descriptive
ABI views; neutral byte/word storage preserves unclassified bits. C bitfields
are deliberately avoided: integer masks and byte arrays retain the reference
bit numbering independently of host/compiler bitfield allocation.

| View | Extent and independent access evidence |
| --- | --- |
| AdapterTSCB | Exact2600 from SizeAdapter0x1a4034 and caller allocation; CreateAdapter0x1a4044 puts HHCB at24; SetupAdapter0x1a4138 copies124 bytes to1560; VerifyAdapter0x1a439c installs IOHandle1688, read/write1720/1724 and four-argument builder1736. Memory descriptors1488, context1684, LUN arrays1740/1756/1884, scan pointers2528/2532, target2536, origin2576, counters2580..2596 are accessed in initialization/scan bodies0x1a77b4..0x1a86fc. Bytes2016..2527 remain unclassified storage, not an inferred field or a claim that no alias can touch them. |
| HHCB | Accessed prefix1380 embedded at adapter24; DeviceTable stride10 at32 is established by0x19e01c/0x19e144; firmware240/hardware244 by0x19275c/0x19e144; ResourceControl16*68 at248 by0x1a2598; active HIOBs1336, SCB list1340, done queue1344 and indices1348/1349 by0x1a2528/0x1a3380; free/host lists1356..1368 by0x1a3048..0x1a32bc; OSM context1372 and identification1376 by0x1a3e68/0x1a4044. No original standalone sizeof claim: trailing bytes before the next adapter field are not identified. |
| TargetTSCB | Exact40 from0x1a4940;0x1a4a64 clears40 and stores tag0, adapter4, target8, LUN12, flags16, unit20. UnitControl is a16-byte accessed prefix with HHCB0, ID4/LUN5, Device8, Resource12 from0x1a2d48. Tail36..39 is retained. |
| HIOB and reserve | HIOB56 at reserve+32; IOB backlink at HIOB52/reserve84 from QueueIOB0x1a5e60; reserve88 is set by GetConfiguration0x1a3eb4 and scan0x1a7ee8. Context0 is unit for ordinary requests, HHCB for special requests, or related HIOB for abort relationships; auxiliary12 is sense buffer or related HIOB according to the function path. Flagsword8 aliases SCB byte9 and neighboring flag bytes; status5/host6/target7, sense length16/residual17, residue20, SCB descriptor24, queue link28 and manager32 are used throughout0x18b754..0x198100. Message bytes35..39 and negotiation/ack33/34 are used in0x198100..0x199eb8. The neutral bytes28 array at40 additionally contains the parity-related flag at43 (bit0x10) and outgoing message byte44 used by HandleMsgOut0x199708; preserving a neutral array does not discard those accesses. Preserve byte versus word accesses to the union. |
| IOB | Exact108 from0x1a7ee8 memset; reserve descriptor0, function12, priority16, flags20, transport28, command32, related36, target/adapter union40, status44, callback52, CDB56/count60, data descriptor68, transfer80, sense88/count92, residues96/100 and task attribute104 appear in0x188ab8/0x1a5e60/0x1a7ee8. Callback receives the IOB in r3; explicit callback word result exists but invokers discard it. CPU pointers, bus-address integers and data lengths are distinct. |
| TransportSpecific | Accessed prefix20: words4/8/12 and ID16/bus17/LUN18; QueueIOB0x1a5e60 interprets flags, ProbeTarget0x18ab0c fills ID/LUN. OSM embeds28 bytes at136, with eight additional unclassified bytes after this prefix. Neutral word names avoid guessing original semantic names. |
| HardwareInformation | Accessed, aligned prefix428: header40, sixteen24-byte records, minimum-speed halfword424. GetHardwareConfiguration0x19e144 and PutHardwareConfiguration0x19f86c access these offsets; profile callers0x1a4d90/0x1a51d0 reserve432 stack bytes. Stack rounding does not establish original sizeof432. |
| OSMIOB | Exact200 allocation/zeroing in0x18b448, free size200 in0x18b528; IOB0, reserveAllocation108, owner112, SG allocation116, retry120, timestamp124, interruptPort132, transport136, sense164[28], queue links192/196. Owner is controller for management operations and AttachedTarget for normal requests; the active path determines the union member. |
| AttachedTarget | Exact156 allocation at PostProbe0x18afd4: controller0, targetTSH4, storage8, size12, profile16[124], waiting140/144 and active148/152. CleanupWaitingQ0x18b1b4 and SendIOBsMaybe0x18a528 distinguish the queues; freeing the target requires draining its IOB ownership first. |
| Command | Exact44 stack envelope in executeRequest0x188498/0x188644; request16, completion lock20, result24, data28, client32, queue36/40. Thread dispatcher0x188ab8 selects operation0, follows request16, and completes through lock20/result24. This is distinct from IOSCSIRequest. |
| adapterQ | Exact64 queue heads: initialize0x1877c8 loops over0x2780d0..0x2782d0 in8-byte strides. IRQ registration0x1878a8 indexes eight*interrupt and allocates12-byte entries containing controller0/link4. Array is512 bytes, not256 entries. |

Queue links are borrowed intrusive links, not independent allocations. CHIM
owns queue membership while a request is outstanding; it does not own the
caller's TargetTSCB/AdapterTSCB storage. Memory descriptors retain caller
allocations; returned bus addresses remain32-bit integers. Cache/MMIO accesses
must preserve the reference `eieio`, synchronization and flush operations in
later bodies; these typed storage views do not replace those operations.

## SCB and scatter/gather byte contracts

SG entries are exactly8 bytes: little-endian bus address at0 and
little-endian length/last word at4. Bit31 marks the final entry;0x80000000
is the zero-length sentinel. Length payload uses low24 bits in SCB transfers.
OSD builders0x1a6f9c/0x1a7194/0x1a73c8/0x1a75c0 use `lwbrx`, `stwbrx` and
byte/halfword writes; these buffers must not be mapped to native-endian words.
Reference SG generation in threadExecuteRequest0x188ab8 and scan0x1a7ee8
stores this same eight-byte format. Physical bus address and virtual SG pointer
are separately present in IOB.data at68/76.

| SCB byte role | Standard64 (64) | Swapping32 (32) | StandardAdv (64) | SwappingAdv (64) |
| --- | --- | --- | --- | --- |
| CDB inline12 or little-endian external address | 0 | 8 | 16 | 24 |
| Control byte | 12 | 1 | 0 | 38 |
| Target/LUN | 13/39 | 2/31 | 1/2 | 12/13 |
| CDB length byte | 14 | 3 | 6 | 14 |
| SG state/count selector | 15=8 | none | 7=8/9/10 | 15=8/9/10 |
| SG list bus address (LE32) | 16 | 4, adjusted by8 | 8 | 16 |
| Current data bus address (LE32) | 24 | 20 | 40 | 0 |
| Current count (LE24) | 28..30 | 24..26 | 44..46 | 4..6 |
| Next SCB number | 38 | 28 | 5 | 11 |
| Next SCB bus address (LE32) | 40 | absent | 32 | absent |
| Negotiated option | no host patch slot | byte29 | LE16 at3 | LE16 at36 |
| Host-memory abort flag | byte35 bit8 | byte0 bit8 | byte0 bit0x10 | byte38 bit0x10 |

The four raw byte-array types intentionally allow mode-dependent overlays,
including special/reset CDB/message paths. Firmware strides and flush counts
establish64/32/64/64; no union overlay is allowed to enlarge these buffers.
For the first two modes CDB-length byte bit0x40 means no data and0x80 denotes
a final first SG entry; control0x80 marks additional SG processing. Advanced
selector8 is ordinary,9 no data,10 final first segment. HIOB flags0x2000
disable the builder's0x40 permission bit;0x4000 selects SCSIscontrol by IOB
taskAttribute104. For old modes0x40 is in control; advanced modes put it in
the LUN byte. Swapping builders additionally gate it on Device.flags0x4000.
Do not assign source bitfield names to these masks. Option writes are proven
by0x18b804/0x18b85c/0x18b88c and0x19b1d4/0x19b20c/0x19b24c; abort writes by
0x190bc0/0x190bfc/0x190c38/0x190c74. Reset/sense overlays and firmware access
remain individually documented by those functions' rows above; later mode
implementations must exercise their byte-exact fixtures rather than equate
the host buffers with the MMIO SCB-window register offsets.

## Private allocation, lifecycle and helper declarations

| Declaration | Entry | Caller/callee and ownership evidence |
| --- | --- | --- |
| `AdptMallocContiguous(unsigned int) -> void *` | 0x18770c | Calls0x1881f4/0x18b4a0 pass byte counts; body rejects zero or sizes above page_size, allocates2*size+4, and selects a virtual subrange contained in one page; the original allocation is stored at result-4. Generic allocated storage has no fixed pointee type. |
| `AdptFreeContiguous(void *, unsigned int) -> void` | 0x18779c |0x18b568 passes original reserveAllocation and profile reserve+alignment; body releases that allocation. Caller discards the kernel result. |
| `sub_189120(unsigned short) -> unsigned short` | 0x189120 | String-read16 chooses this function when byte swap is required; full body rotates/masks low16. Frozen varied conversion input verifies0x1234 ->0x3412. |
| `sub_18914C(unsigned int) -> unsigned int` | 0x18914c | String-read32 selects it; full body byte-reverses all32 bits,0x12345678 ->0x78563412. |
| `sub_189174(unsigned short) -> unsigned short` | 0x189174 | Alternative string-read16 target; halfword homing/load, zero-extended identity. |
| `sub_18918C(unsigned int) -> unsigned int` | 0x18918c | Alternative string-read32 target; word homing/load, identity. |
| `sub_1891A0(unsigned short) -> unsigned short` | 0x1891a0 | String-write16 alternative target; low16 mask identity, typed source loads are halfwords. |
| `sub_1891B0(unsigned int) -> unsigned int` | 0x1891b0 | String-write32 alternative target; fullword identity. These six are handwritten inventory bodies, not generated exemptions. |
| `sub_18B2A8(thread_call_spec_t, thread_call_t) -> void` | 0x18b2a8 | AU2Handler0x18b3e0 supplies its address to thread_call_func with controller context. Actual executor0xf15fc/0xf1600 loads routine/context,0xf1654/0xf1658 sets r3=context/r4=call-or-null,0xf1664 invokes; next call splsched observes no result. Helper uses controller r3 to invoke HIM ISR/IRQ functions; r4 is unused but established by provider. |
| `AU2Handler(int, void *, void *) -> void` | 0x18b3d0 | Registration0x187908 supplies it to platform registrar, which stores routine/context in interrupt entry0/8 (registrars0x227700/0x227cf4/0x228594/0x228bbc). Executors0x227950/0x227fc4/0x228834/0x228ea8 pass interrupt number, saved-state pointer and context; concrete0x2279c4..0x2279d8 and0x228f1c..0x228f30 set r3/r4/r5. Only context is forwarded to thread_call_func; no result consumed. |
| `AdaptecU2SCSITimeout(void *) -> void` | 0x18b400 | SendIOBsMaybe0x18a5d4 and NormalPost0x18aa34 pass IOB context to IOScheduleFunc0x1d8938; ns_timeout0xe72ec forwards routine/context to thread_call_func_delayed. The same executor0xf1664 supplies the first pointer and an unused second runtime argument. Body follows IOB.owner112 to controller and sends resetSCSIBus; the timer boundary has no defined return. |
| `_allocOSMIOB(AdapterProfile) -> OSMIOB *` | 0x18b448 | Callers0x1882f0/0x18b628 pass the complete metadata464-byte profile by value. Allocates200, reserveSize+alignment contiguous bytes and one page SG; stores original reserve allocation108, aligned virtual8, physical0, SG116 and transport28=&iob136. Returns pointer/null; the reference physical-translation failure leaks prior allocations and must not be silently repaired. |
| `_freeOSMIOB(OSMIOB *, AdapterProfile) -> void` | 0x18b528 | Callers0x1889b0/0x18b72c pass IOB followed by complete464-byte profile. Frees original reserve allocation108 with profile sum, SG116 with page_size, then IOB with200; no result consumed. |
| `AllocOSMIOB(controller *) -> OSMIOB *` | 0x18b59c | Calls0x188c88/0x18a810/0x18ab40 supply self; removes from controller.iobQ1408 or allocates using self.profile684, increments active1396, resets request fields and returns pointer. Reference null handling remains a later body obligation. |
| `FreeOSMIOB(controller *, OSMIOB *) -> void` | 0x18b6a4 | Calls0x18a7b0/0x18aa88/0x18b120 supply owner and IOB. Active count>15 releases allocation; otherwise appends links192/196 to free pool1408; decrements count. Callers ignore incidental r3. |
| `SendIOBsMaybe(AttachedTarget *) -> void` | 0x18a528 | Calls0x189c18/0x18a6a8/0x18a730 supply target. Follows controller0 and waiting140, moves requests to active148, schedules timeout and HIMQueueIOB; retains outstanding IOB ownership. |
| `EnqueueOsmIOB(OSMIOB *, AttachedTarget *) -> void` | 0x18a66c |0x18902c passes allocated request/target; links IOB192/196 onto target140/144 then invokes SendIOBsMaybe. |
| `HandleHIMFrozen(OSMIOB *) -> void` | 0x18a6bc | NormalPost0x18a9f8 supplies request; follows owner112, queues unfreeze operation and requeues waiting request. |
| `ResetSCSIBus(controller *, Command *) -> void` | 0x18a7e0 | Category0x1890cc/0x189108 and NormalPost0x18aad8 pass controller/command or null; allocates management IOB, stores command32 and controller owner112, installs reset callback, queues it. |
| `ProbeTarget(controller *, Command *) -> unsigned int` | 0x18ab0c | Thread dispatcher0x188bbc supplies both; target byte through command.request16, lock20/result24, IOB command32/controller112. Both branches explicitly return0. |
| `ValidateTargets(OSMIOB *) -> void` | 0x18ad14 | Calls0x18ac38/0x18af90 pass management IOB; uses controller from owner112, validates attached target handles and drains removed target queues. |
| `CleanupWaitingQ(AttachedTarget *) -> void` | 0x18b1b4 | Controller free0x188914 and ValidateTargets0x18ad7c supply target; traverses waiting140/144, completes commands and returns each IOB via FreeOSMIOB. |
| `NormalPostRoutine(IOB *) -> unsigned int` | 0x18a878 | Stored in IOB52 at0x188fb8, invoked by CHIM completion with original IOB r3. Accesses OSM extension112..196, cancels timer, handles status/residue, completes/returns request; explicit0. |
| `PostUnfreezeHIMQueue(IOB *) -> unsigned int` | 0x18a74c | Stored0x18a6f4 at IOB52; follows owner112, clears frozen state, frees control IOB, restarts waiting queues; explicit0. |
| `PostProtocolAutoConfig(IOB *) -> unsigned int` | 0x18ac08 | Stored0x18ae20 at IOB52; validates targets, completes command and frees IOB; explicit0. |
| `PostRoutineResetHW(IOB *) -> unsigned int` | 0x18add4 | Stored0x18a828 at IOB52; queues follow-on autoconfiguration or completes/reset-clears state; explicit0. |
| `PostRoutineEventResetHW(IOB *) -> unsigned int` | 0x18aea0 | Stored0x189c8c at IOB52; controller112, event recovery/PAC path, control-IOB release; explicit0. |
| `PostRoutineEventPAC(IOB *) -> unsigned int` | 0x18af70 | Stored0x189c44/0x18af0c at IOB52; validates targets, clears active flag, releases IOB; explicit0. |
| `PostProbe(IOB *) -> unsigned int` | 0x18afd4 | Stored0x18ab58 at IOB52; controller112/command32, allocates156-byte attached target and40-byte target block, profiles target, links queues and releases probe IOB; explicit0. |

## Aggregate profile ABI and inherited metadata

The historical compiler witness `_au2_allocate_profile_check` loads profile
words0..28 into r3..r10 and copies profile+32,432 bytes, to outgoing SP+56.
Its call relocation identifies `__allocOSMIOB`. Free has IOB in r3, profile
words0..24 in r4..r10, and copies profile+28,436 bytes, to SP+56 before
`__freeOSMIOB`. The corresponding native callee witnesses home registers to
entry SP+24..52 (allocate) or+28..52 (free); alignment mask/reserve size are
read at entry SP+84/+160 or+88/+164. These match reference0x18b448/0x18b528
and caller memcpy counts0x1b0/0x1b4. The complete1 witness instruction offsets
are0x250 memcpy/0x274 alloc and0x2c4 memcpy/0x2e8 free; Mach-O relocations,
not IDA's misleading unresolved-branch display names, establish callees.
No apparent eight-/35-/36-argument decompiler prototype is retained.

Reference inherited metadata establishes Object4, IODevice264,
IODirectDevice296, IOSCSIController580. IODevice fields begin unit4,
name8[80], location88[80], kind168[80], description248, reserved252[3];
IODirectDevice adds description264, port268, thread272, delegate276,
busPrivate280/private284 and reserved288[2]. IOSCSIController adds reserveQ296,
reserved304[62], count552, lock556, alignment560 and reserved564[4]. The
actual kernel-7 SDK inheritance produces the same580-byte superclass prefix.
The controller's own ivar names, encodings and offsets, class size1488, all21
class/instance methods and four thread-category methods are compared exactly
with the pinned Objective-C metadata. RegisterHandlerForIRQ is void(int),
createOSMIOBPool is void, and selector/category spellings are unchanged.
The three handle ivars intentionally remain metadata `^v`; typed CHIM APIs
establish their concrete uses without changing the runtime type encodings.
Cached lock IMPs receive id/SEL plus the observed condition integer and
return id, matching NXLock/NXConditionLock metadata and their calls.

The target layout unit is a test-only declaration/type witness; its empty
method bodies never enter a kernel and prove no product implementation.
Public SCSIGetFunctionPointers retains the caller-supplied copy count rather
than clamping to168; the known controller caller supplies168. SetupAdapter
similarly copies caller count124. Later body recovery must retain these caller
assumptions and observable behavior. No production behavior or ledger status
is changed by this ABI task.

## Task 4 firmware and static data

`data.json` is the frozen per-envelope accounting contract for all 48 data
ranges listed in the inventory. It records exact bytes/hash/extents, native
field widths, pointer eligibility/targets, consumers, and the required gate.
The 21 CHIM-owned envelopes now have production definitions. Their 261 nonzero
pointer words are symbolic C initializers. Null callbacks, header words,
reserved words, profile masks, PCI IDs/masks and0xff selectors remain data.
The firmware register array is additionally interpreted byte by byte with
its low-level consuming routines. The ABI's deliberately opaque scalar names
are retained where the binary does not preserve original member names; an
unreferenced stored constant is not assigned an invented callback or purpose.

| Mode | Descriptor | Source image | Loader entry | Exact bytes | SHA-256 |
| --- | --- | --- | --- | ---: | --- |
| 0 | `SCSIFirmwareStandard64` | `Seq_s64` | `0x193124` | 2000 | `B08E925A06751F830A1C04A34812B0969E9F616A20E4710B25416C755A871420` |
| 3 | `SCSIFirmwareSwapping32` | `Seq_w32` | `0x193154` | 1772 | `25AD3CFF17D046C2A63EC8BE8BE210541E50196A537BD635ACB057647D5ED6E5` |
| 4 | `SCSIFirmwareStandardAdv` | `Seq_sAdv` | `0x193184` | 2072 | `AAC7445EBE26BEF9C088AA3202EC2EA939DEEFDAA393ACBDF4890BC0609E6EEF` |
| 5 | `SCSIFirmwareSwappingAdv` | `Seq_wAdv` | `0x1931b4` | 2256 | `5D0F6D1A951C8ACF6D5E9A81529E303341DA10D6AB45475BBF12E13BE8E6107D` |

Each48-byte setup wrapper loads HHCB+8 into r3, the source address into r4,
and the immediate byte count into r5 before calling `SCSIhLoadSequencer`.
Extraction now decodes those actual PPC instructions and checks that the
count reaches the next image/descriptor boundary exactly. Descriptor slot84
points to its corresponding wrapper. `SCSIFirmware[7]` is exactly
`{Standard64,0,0,Swapping32,StandardAdv,SwappingAdv,0}`. The null modes1/2 and
trailing null6 are preserved. `SCSIHardware[3]` is `{AIC78XX,Bayonet,0}`.
`SCSIhSetupEnvironment`0x1922c8 and `SCSIHSetupHardware`0x192304 index the mode
bytes directly and install descriptors at HHCB+240/+244.

`SCSICreateAdapterTSCB`0x1a4044 sets hardware mode0 by default, mode1 when
`(productID &0xff80ffff)==0x00009005`; its initial firmware modes are0 for
`(productID &0xfff0ffff)==0x78909004`,4 for that Bayonet mask,3 otherwise.
`SCSIxDetermineFirmwareMode`0x1a89bc then probes external SCB RAM: Bayonet
selects4 with RAM and5 without; the0x78909004 family selects0 with RAM and3
without; remaining products select3. `SCSIVerifyAdapter`0x1a439c installs
matching SCB builders and sizes64/32/64/64. Its subsystem-check gate applies
to0x78959004 with revision byte<=4, or products0x78609004/0x38609004. This
revision gate restricts acceptance; it does not select a replacement image.

`SCSIhLoadSequencer`0x19ebe0 saves SEQCTL(0x60), writes0xb1 and clears
SEQADDR0/1(0x62/0x63), writes exactly r5 bytes to SEQRAM(0x61), cycles
SEQCTL0xb0/0xb1, clears the address again, and reads back every byte against
the source. The loops are at0x19ece8..0x19ed1c and0x19ee1c..0x19ee44.
Success writes0xb0 then restores saved SEQCTL and returns0; a mismatched
readback returns-1 immediately without the successful cleanup sequence.
Preserve that error behavior in the later loader implementation.

All 8100 source-image bytes have pointer-reference closure: each image has
only its setup-wrapper address reference, with no direct write reference to
any image byte. The loader has indexed source loads and no source stores.
There is no source-image patch list or hardware-revision replacement in
this binary. Runtime transfer-option/SG/cache/breakpoint operations modify
SCBs, adapter scratch/registers and sequencer execution addresses. They do
not rewrite these arrays or substitute a sequencer revision. The breakpoint
callbacks in firmware slots256/260 use mode-specific addresses/constants;
`SCSIhStartToRunSequencer`0x193554 uses descriptor byte35 for the idle entry.
`SCSIhInitializeHardware`0x1931e4 applies the hardware0 AIC789x revision3
PCI-command workaround and cache-line conditions; these affect registers.
Bayonet's slot92 sequence-stretch callback0x1a2410 reads register0xee, while
the corresponding AIC78XX slot is null. Descriptor scalar bytes and callback
choices retain all such mode-specific behavior for the owning later tasks.

Hardware descriptors are120 bytes:25 callback words, three native mask/control
words, four byte scalars, two16-bit period/delay values. Firmware descriptors
are296 bytes:14 native words,28 byte positions, then53 callback/reserved
words. Offsets136/276 are zero scalar reserves in all four modes. Firmware
word04 is SCB size; its low byte at7 is also used as memory-table granularity.
The memory allocator at0x192064 calculates SCB buffer sizes from that word
and a minimum of four SCBs; it does not use a guessed trailing HHCB sizeof.
Other sequencer entry/breakpoint constants and unused0xff/zero positions
retain their exact representation and consumers in `data.json`.

`SCSIHostType` holds40 ID/mask pairs including the final zero/zero sentinel;
`SCSIGetNextHostDeviceType`0x1a3d38 permits unsigned indices0..39 and leaves
outputs untouched for a zero ID or an out-of-range index. Subsystem data has
16 full-mask pairs, but `SCSIxGetNextSubSystemSubVendorID`0x1a8aa4 accepts
only0..13. Entries14/15 are the preserved unreachable0x38689004/0x38699004
pairs. `SCSIscontrol` is exactly8 bytes `{0x60,0x62,0x61,0,0,0,0,0}`;
SCB builders index by task attribute. It has no pointer entries.

Configuration's17 native scalars, both 464-byte adapter profiles and both
124-byte target profiles are exact. Adjustable profiles are masks, not
callback tables. The adapter profile's32 WWID bytes, five task-management
flags and55-word union remain fully represented. The target profile uses
the already reviewed31-word scalar-position ABI. No pointer normalization
is applied to any profile/configuration word, even when a value resembles
an address. HIM version4 remains a scalar before its41 callbacks; the exact
11 CHIM/3 OSM erased-formal exceptions remain unchanged.

All 22 switch envelopes contain signed32-bit table-relative offsets. Each
resolved target is `table_base + signed_word`, not the stored word treated
as a native pointer. `data.json` records every target (including duplicated
default slots), containing function, instruction-byte window, index/guard
and `lwzx/add/mtctr/bctr` dispatch. Resolved target sets match saved-analysis
code references and fresh IDA jump targets for all 22. Their future product
counterparts must arise from their owning routine's recovered control flow;
Task4 emits no orphan arrays of reference branch addresses. All unnamed
functions remain ordinary required bodies.
