# drvSCSITape divergences

References, all under `SCSITape.config`:

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `SCSITape_reloc` | 47624 | `ABB8D7E5FDEB9188A4C58D10AE6A7A1313A79EFBE49513AD3804E386BB65131A` |
| `PreLoad` | 9060 | `177355F05BDCBD6EDE34121F93E6B6A176B105ACF8EAD1945761A9E1D3BFB60A` |
| `PostLoad` | 21520 | `A6025294E3E1AB96270BBE3AFAD73A3885C7C5F44644241E44DD553632699F87` |
| `stblocksize` | 13408 | `E36D1320E5543E9F8B46D522D19150DC6BA21B348C6ECAB8D13AE9CF83BC7648` |

Analysis: IDA 9.2. Ghidra and angr are i386-only and cannot analyse these
binaries.

No PowerPC build exists in this environment, so nothing recorded here is
compile-verified — including the function bodies the fix pass writes. Every
claim rests on the reference disassembly.

## Starting state

| Artifact | Named | Mapped | Unmapped |
| --- | --- | --- | --- |
| `SCSITape_reloc` | 50 | 44 | 6 |
| `PreLoad` | 12 | 1 | 11 |
| `PostLoad` | 16 | 1 | 15 |
| `stblocksize` | 20 | 3 | 17 |

## Out of scope

**94 jump islands.** `SCSITape_reloc`'s IDA analysis finds 144 functions; 94 are
unnamed 16-byte `lis`/`mr`/`mtctr`/`bctr` sequences — build-generated branch glue
for calls exceeding the PowerPC branch displacement. `filter_named_functions.py`
excludes them.

**crt and dyld startup, six per helper.** `start`, `__start`,
`__call_mod_init_funcs`, `__dyld_init_check`, `dyld_stub_binding_helper` and
`__dyld_func_lookup` come from the C runtime and the dynamic linker, not from
our source.

**Every 36-byte `__picsymbol_stub` entry.** 5 in `PreLoad`, 9 in `PostLoad`, 10
in `stblocksize` — confirmed against each binary's stub-section size (180, 324
and 360 bytes, all exact multiples of 36). These bind dynamically to the C
library and Objective-C runtime:
- `PreLoad`: `_bzero`, `_exit`, `_printf`, `_sprintf`, `_unlink`
- `PostLoad`: `__objcInit`, `_bzero`, `_exit`, `_mknod`, `_objc_msgSend`, `_printf`, `_sprintf`, `_umask`, `_unlink`
- `stblocksize`: `_atoi`, `_bzero`, `_close`, `_exit`, `_ioctl`, `_open`, `_perror`, `_printf`, `_strcmp`, `_strlen`

Unlike the jump islands these are *named*, so `filter_named_functions.py` cannot
remove them and they stay in the `unmapped` bucket. They are explained here
rather than filtered out of sight.

**Two build-generated classes.**
`+[SCSITapeKernelServerInstance kernelServerInstance]` (20 bytes) and
`+[SCSITapeVersion driverKitVersionForSCSITape]` (16) are emitted by the Kernel
Server build from the project's own settings, exactly as `SCSIServer`'s pair
were. They remain `unmapped` permanently.

## The analyzer gap at address 0

`+[SCSITape deviceStyle]` occupies address 0: `__OBJC,__cls_meth` lists it
(`i4@4:8`, alongside `probe:` and `requiredProtocols`) with `imp = 0x0`, and
the four bytes at address 0 are `9421ffe0 38600001 38210020 4e800020` —
`stwu r1,-0x20(r1)` / `li r3,1` / `addi r1,r1,0x20` / `blr`, i.e. `return 1`
(`IO_IndirectDevice`), exactly matching `SCSITape.m:49-52`'s
`+ (IODeviceStyle) deviceStyle { return IO_IndirectDevice; }`. IDA emits no
function entry at address 0 (the same analyzer artifact `SCSIServer`'s
reconstruction hit for its own `deviceStyle`), so this method is missing from
both `analysis.named.json` and every ledger under
`src/drvSCSITape/reconstruction/` — confirmed by `grep` finding no
`deviceStyle` hits anywhere in the ledger. Our source implements this method
correctly; its absence from the ledger is an analyzer artifact, not a missing
function, and it means the ledger is not a complete coverage map of the real
class.

## SCSITape accessors and lifecycle block

Task 2 read the 20 functions at addresses 16-2591 (`analysis.named.json`)
instruction by instruction against `SCSITape.m`, using `read_macho` against
`SCSITape_reloc` to resolve `__message_refs` entries (e.g. `paReleasedevice` /
`paReservetargetL`) to the selector strings in `__cstring`/`__OBJC` they
actually bind to, since the named export's `calls: []` strips every `bl` target
into an opaque `sub_XXXX` island.

| Address | Function | Status | What was compared |
| --- | --- | --- | --- |
| 16 | `+[SCSITape requiredProtocols]` | `assembly-matched` | 5-instruction leaf computing `&_protocols`; `_protocols` (`__data`, address 12288) carries one relocation to `stru_4418` (a `Protocol` struct) at element 0 with element 1 left as a zero (implicit `nil`) — a plain file-scope `Protocol *[2]`, matching `SCSITape.m:57-60`'s `static Protocol *protocols[] = { @protocol(IOSCSIControllerExported), nil };` exactly, direct pointer with no extra indirection (unlike the equivalent `SCSIServer` finding) |
| 36 | `+[SCSITape probe:]` | `unexamined` | Finding: queries `[controllerId numberOfTargets]` and clamps/warns instead of using the compile-time `SCSI_NTARGETS`; Finding: no target/lun reservation call anywhere in the function |
| 1544 | `-[SCSITape free]` | `unexamined` | Finding: calls `[self releaseDevice]` guarded on `_devAcquired` and never touches `_reservedTargetLun`/`_controller`/`releaseTarget:lun:forOwner:` |
| 1736 | `-[SCSITape getIntValues:forParameter:count:]` | `assembly-matched` | both `strcmp` sites (`"IOMajorDevice"`, `"Unit"`), the `maxCount` normalization, and the `[super getIntValues:...count:&maxCount]` fallback (confirmed via the `stru_4170.super_class` objc_super load) match `SCSITape.m:330-356` instruction for instruction, including passing `&maxCount` rather than the caller's own `count` pointer to the super call |
| 2028 | `-[SCSITape target]` | `assembly-matched` | 4-instruction leaf; `lbz r3, 0x10C(r3)`, no `extsb` (unsigned byte to int is a zero-extend, matching `(int)_target`) |
| 2044 | `-[SCSITape lun]` | `assembly-matched` | 4-instruction leaf; `lbz r3, 0x10D(r3)`, same zero-extend pattern as `target` |
| 2060 | `-[SCSITape controller]` | `assembly-matched` | 4-instruction leaf; `lwz r3, 0x108(r3)` |
| 2076 | `-[SCSITape isInitialized]` | `assembly-matched` | 5-instruction leaf; `lbz`/`extsb` at `0x120(r3)` |
| 2096 | `-[SCSITape didWrite]` | `assembly-matched` | 5-instruction leaf; `lbz`/`extsb` at `0x122(r3)` |
| 2116 | `-[SCSITape isFixedBlock]` | `assembly-matched` | `lwz r3, 0x114(r3)` (same offset `blockSize` reads) followed by the `addic`/`subfe` "nonzero-to-1" idiom, matching `if (_blockSize) return YES; else return NO;` |
| 2140 | `-[SCSITape senseDataValid]` | `assembly-matched` | 5-instruction leaf; `lbz`/`extsb` at `0x124(r3)` |
| 2160 | `-[SCSITape forceSenseDataInvalid]` | `assembly-matched` | `stb` of a literal 0 at `0x124(r3)` — same offset `senseDataValid` reads, confirming `_senseDataValid = NO; return self;` |
| 2180 | `-[SCSITape senseDataPtr]` | `assembly-matched` | 4-instruction leaf; `lwz r3, 0x118(r3)` — same offset `-free`'s `IOFree(_senseDataPtr, ...)` guard reads |
| 2196 | `-[SCSITape blockSize]` | `assembly-matched` | 4-instruction leaf; `lwz r3, 0x114(r3)` — same offset `isFixedBlock` reads |
| 2212 | `-[SCSITape suppressIllegalLength]` | `assembly-matched` | 5-instruction leaf; `lbz`/`extsb` at `0x123(r3)` — same offset `setSuppressIllegalLength:` writes |
| 2232 | `-[SCSITape setSuppressIllegalLength:]` | `assembly-matched` | 4-instruction leaf; `stb r5, 0x123(r3)` — matches the getter's offset |
| 2248 | `-[SCSITape setIgnoreCheckCondition:]` | `unexamined` | Finding: writes to `0x225(r3)` — resolved via `__OBJC,__instance_vars` as the separate `_ignoreOpenCheckCondition` ivar, not `_ignoreCheckCondition`; see finding below |
| 2264 | `-[SCSITape majorDevNum]` | `assembly-matched` | 4-instruction leaf; `lwz r3, 0x110(r3)` |
| 2280 | `-[SCSITape acquireDevice]` | `unexamined` | Finding: calls `[_controller reserveTarget:lun:forOwner:]` and `[self reserveAllLuns]`, neither of which our source calls |
| 2464 | `-[SCSITape releaseDevice]` | `unexamined` | Finding: calls `[self releaseAllLuns]` and `[_controller releaseTarget:lun:forOwner:]`, neither of which our source calls |

**The recovered ivar table.** The offset table below is not inferred from
accessor bodies at all — it is parsed directly from `SCSITape_reloc`'s own
Objective-C class metadata: `__OBJC,__instance_vars` (vaddr 20848) is the
class's ivar list, 15 `{name, type, offset}` triples (184 bytes), and
`__OBJC,__class` (vaddr 16752) gives `instance_size = 556`. That metadata is
authoritative for layout, and it is what the thirteen accessors below are
checked *against*, not the other way around:

| Offset | Size | Type encoding | Ivar | Source |
| --- | --- | --- | --- | --- |
| `0x108` (264) | 4 | `@` (id) | `_controller` | `__OBJC,__instance_vars`; matches `-controller` (2060); `-acquireDevice`/`-releaseDevice` read the same offset for the `reserveTarget:`/`releaseTarget:` receiver |
| `0x10C` (268) | 1 | `C` (unsigned char) | `_target` | `__OBJC,__instance_vars`; matches `-target` (2028); also read by `-acquireDevice`/`-releaseDevice` |
| `0x10D` (269) | 1 | `C` (unsigned char) | `_lun` | `__OBJC,__instance_vars`; matches `-lun` (2044); also read by `-acquireDevice`/`-releaseDevice` |
| `0x10E`-`0x10F` | 2 | — | *(padding)* | — |
| `0x110` (272) | 4 | `i` (int) | `_majorDevNum` | `__OBJC,__instance_vars`; matches `-majorDevNum` (2264) |
| `0x114` (276) | 4 | `i` (int) | `_blockSize` | `__OBJC,__instance_vars`; matches `-blockSize` (2196); same offset tested by `-isFixedBlock` (2116) |
| `0x118` (280) | 4 | `^{?}` (opaque struct pointer) | `_senseDataPtr` | `__OBJC,__instance_vars`; matches `-senseDataPtr` (2180); same offset freed by `-free` (1544) |
| `0x11C` (284) | 4 | `@` (id) | `_devLock` | `__OBJC,__instance_vars`; matches `-free`'s conditional `[_devLock free]`; `-acquireDevice`/`-releaseDevice`'s `[_devLock lock]`/`[_devLock unlock]` |
| `0x120` (288) | 1 | `c` (char/BOOL) | `_isInitialized` | `__OBJC,__instance_vars`; matches `-isInitialized` (2076) |
| `0x121` (289) | 1 | `c` (char/BOOL) | `_devAcquired` | `__OBJC,__instance_vars`; not directly accessor-mapped, but read/written identically by `-free`, `-acquireDevice` and `-releaseDevice` (see findings below) |
| `0x122` (290) | 1 | `c` (char/BOOL) | `_didWrite` | `__OBJC,__instance_vars`; matches `-didWrite` (2096) |
| `0x123` (291) | 1 | `c` (char/BOOL) | `_suppressIllegalLength` | `__OBJC,__instance_vars`; matches `-suppressIllegalLength` (2212) / `-setSuppressIllegalLength:` (2232) |
| `0x124` (292) | 1 | `c` (char/BOOL) | `_senseDataValid` | `__OBJC,__instance_vars`; matches `-senseDataValid` (2140) / `-forceSenseDataInvalid` (2160) |
| `0x125` (293) | 256 | `[32[8c]]` (`char[32][8]`) | `_ignoreCheckCondition` | `__OBJC,__instance_vars` — a per-target/per-lun matrix (32 targets × 8 luns), not the single `BOOL` our `@interface` declares; see finding below |
| `0x225` (549) | 1 | `c` (char/BOOL) | `_ignoreOpenCheckCondition` | `__OBJC,__instance_vars` — absent from our `@interface` entirely; this is the ivar `setIgnoreCheckCondition:` (2248) actually writes, see finding below |
| `0x228` (552) | 4 | `I` (unsigned int) | `_lunsReserved` | `__OBJC,__instance_vars` — absent from our `@interface` entirely; almost certainly the bitmask the absent `reserveAllLuns`/`releaseAllLuns` methods (ledger addresses 7012/7280, see findings below) manipulate |

`instance_size` is 556; ivar count is 15. All offsets and the
`assembly-matched` verdicts on the thirteen accessors above assume `IODevice`'s
instance size in our tree is 264 (0x108), matching the reference's ivar base —
only the *relative* layout from that base was checked, not that absolute
assumption itself.

Our `@interface`'s ivar order (`SCSITape.h:26-46`) agrees with the reference
only through `_senseDataValid` at `0x124` (292) — the ten ivars `_controller`
through `_senseDataValid` match exactly, offset for offset. From `0x125` (293)
on, our header diverges completely: we declare a single 1-byte
`_reservedTargetLun` (293) followed by a single 1-byte
`_ignoreCheckCondition` (294), for a total instance size of about 296 bytes
(264 + 32, 4-byte aligned). The reference has no `_reservedTargetLun` ivar at
all — `0x125` is the start of the 256-byte `_ignoreCheckCondition` matrix,
followed by two ivars we don't declare at all (`_ignoreOpenCheckCondition` at
549, `_lunsReserved` at 552), for `instance_size = 556`. This is a 260-byte
tail divergence (556 − 296 = 260) in the layout from `0x125` onward, not one
unexplained accessor as the previous pass characterized it.

## Finding: `-[SCSITape setIgnoreCheckCondition:]` writes to `_ignoreOpenCheckCondition`, a distinct ivar 256 bytes past `_ignoreCheckCondition`

**Source:** `SCSITape.h:45-46` (`_reservedTargetLun`/`_ignoreCheckCondition`
field declarations), `SCSITape.m:435-439` (`setIgnoreCheckCondition:`).

**Reference behaviour:** the function (address 2248, 16 bytes) is a 4-instruction
leaf identical in shape to every other one-line setter in this block —
`stwu`/`stb r5, 0x225(r3)`/`addi r1`/`blr`. `__OBJC,__instance_vars` (see the
ivar table above) answers what `0x225` (549) actually is: `_ignoreCheckCondition`
sits at `0x125` (293) but is typed `[32[8c]]` — a `char[32][8]` matrix, 256
bytes — not the single `BOOL` our `@interface` declares. `293 + 256 = 549 =
0x225`, which is exactly the *next* ivar, `_ignoreOpenCheckCondition` (a
`char`/`BOOL`). `_lunsReserved` (`unsigned int`) follows immediately after at
552 (`0x228`). There is no mystery left: `setIgnoreCheckCondition:` writes
`_ignoreOpenCheckCondition`, a real, separate field the reference class
declares that ours does not, at the offset the matrix's true size predicts.

**Our source:** `SCSITape.h:45-46` declares `_reservedTargetLun` and
`_ignoreCheckCondition` as single-byte `BOOL`s, and `SCSITape.m:435-439` stores
directly into `_ignoreCheckCondition` at what the compiler would place at
`0x126` (294) given that declaration — 255 bytes before where the reference's
compiled setter actually writes, and typed as a single flag rather than a
32×8 matrix.

**Consequence:** this is exactly the class of bug the brief warns about — the
accessor reads as individually correct in isolation, but on a real rebuild it
would write the wrong storage relative to the reference's memory layout. The
repair is now well-defined rather than speculative: retype
`_ignoreCheckCondition` in `SCSITape.h` as a per-target/per-lun matrix
(`char _ignoreCheckCondition[32][8]` or equivalent, indexed by
target/lun), and add the two missing ivars, `_ignoreOpenCheckCondition`
(`BOOL`) and `_lunsReserved` (`unsigned int`), immediately after it and before
the rest of the header's tail. `_lunsReserved` is almost certainly the bitmask
the absent `reserveAllLuns`/`releaseAllLuns` methods (ledger addresses
7012/7280, see the `acquireDevice`/`releaseDevice` findings below) manipulate —
one bit per LUN, matching the `[8c]` inner dimension of the matrix. Left
`unexamined`; the fix pass should apply this retyping alongside adding the two
ivars. Note also that `-[SCSITape ignoreCheckCondition]` (the getter),
`-[SCSITape setReservedTargetLun:]` and `-[SCSITape reservedTargetLun]` — all
three declared in `SCSITape.h:74-77` — have no compiled counterpart anywhere in
`SCSITape_reloc`'s 50 named functions at all (Task 7's absent-methods pass
should account for this).

## Finding: `+[SCSITape probe:]` queries the controller for its target count and never reserves a target/lun

**Source:** `SCSITape.m:69-174` (`probe:`).

**Reference behaviour:** after the `st_devsw_init()` guard (addresses 116-132,
matching `SCSITape.m:81-83`), the function calls
`objc_msgSend(controllerId, @selector(numberOfTargets))` (addresses 136-148,
`paNumberoftarget` resolves via `read_macho` to `sel_numberOfTargets`) and
clamps the result to 32 if larger (addresses 156-164), logging
`"drvSCSITape supports bus ID targets 0 .. %d\n"` (string at address 11356,
argument literal `0x1F`/31) when the clamp fires (addresses 168-180, guarded by
the same `ble` that skips the clamp). The outer loop bound (`r27`, compared at
address 188 and again at 384) is this dynamically-queried, clamped value, not
a compile-time constant.

Separately, no instruction in this function's entire 36-476 address range
loads `paReservetargetL` (`reserveTarget:lun:forOwner:`, confirmed via
`read_macho` against `SCSITape_reloc` — the message ref exists in
`__message_refs` at address 16564 but every reference to it resolves inside
`-acquireDevice` and `-releaseDevice`, never inside `probe:`) or
`paReleasetargetL`. The switch-equivalent code at addresses 292-304 (matching
the `switch(irtn)` in `SCSITape.m:128-156`) goes straight from the
`STR_GOOD`/`STR_SELECTTO`/default branch decisions to the loop increment with
no intervening call at all in the default/error case.

The inner (lun) loop's bound is now resolved. The back-edge instruction at
address 372 is `0x41a2ff68` (confirmed against the raw bytes): `bc` with
`BO=13`, `BI=2` (`CR0.EQ`) and a 14-bit displacement of `-38` words
(`-152` bytes), branching to address `220` (`372 - 152 = 220`) — matching the
disassembly's own `beq- cr0,loc_DC` at addresses 364-372 (`addi r0,r30,1` /
`andi. r30,r0,0xFF` / `beq- cr0,loc_DC`). With `stLun` a `u_char`, this is a
post-test `do`-loop: it runs the body once for `stLun == 0`, then increments
to 1, masks to a byte (`1 & 0xFF == 1`, non-zero), and does *not* branch back
— so the loop body executes for LUN 0 only and stops; the mask-and-test-zero
form only re-enters on a full byte wraparound (`stLun == 0xFF` incrementing to
`0x100 & 0xFF == 0`), which never happens starting from 0. The bound is 1, not
`SCSI_NLUNS`: the `_ignoreCheckCondition` matrix's `[8c]` inner dimension (see
the ivar table above) proves `SCSI_NLUNS == 8` in Apple's build, so `probe:`
scans LUN 0 only regardless of that constant — tape devices are LUN-0-only by
design, independent of how many LUNs the class's own storage budgets for. The
matrix's outer `[32]` dimension likewise proves `SCSI_NTARGETS == 32` in
Apple's build, which is also exactly the clamp value `probe:`'s outer loop
applies to `[controllerId numberOfTargets]` above — direct corroboration that
the 32 clamp and the ivar matrix come from the same build-time constant.

**Our source:** `SCSITape.m:85-86` loops `stTarget` and `stLun` over the
compile-time constants `SCSI_NTARGETS` (8, `src/kernel-7/bsd/dev/scsireg.h:732`)
and `SCSI_NLUNS` (8, ibid. line 733) — no controller query, no clamp, no
warning log. `SCSITape.m:102-112` calls
`[controllerId reserveTarget:stTarget lun:stLun forOwner:tapeId]` before
`initSCSITape:...`, and `SCSITape.m:142-145` calls `releaseTarget:lun:forOwner:`
plus `setReservedTargetLun:NO` in the failure case — none of which the
reference's `probe:` does at all.

**Consequence:** two independent, non-cosmetic divergences. (1) Our fixed
8-target loop bound (our `SCSI_NTARGETS`) is genuinely smaller than the
reference's compile-time 32 (recovered from the ivar matrix and corroborated
by the 32 clamp above) — our `probe:` could scan fewer targets than a
controller advertising more than 8. `SCSI_NLUNS` (8 in our tree, also 8 in
Apple's build per the matrix's `[8c]` dimension) is not the divergence here;
the reference's *loop bound* is 1 regardless of `SCSI_NLUNS`, so this is not
actually a target/lun-count mismatch on the LUN side, only on the target side
(though `SCSI_NTARGETS`/`SCSI_NLUNS` are also the values `IOSCSIController`
itself is built against elsewhere in this tree, so the practical impact needs
checking against that class, not asserted here).
(2) The reservation calls our `probe:`/`free` make have no reference
counterpart in `probe:`/`free` at all — the reference defers actual
target/lun reservation to `-acquireDevice`/`-releaseDevice` (see the findings
below), meaning our source's reservation bookkeeping during enumeration is
architecturally different from the shipped driver's, not just missing a call.
Left `unexamined` for Task 3/the fix pass.

## Finding: `-[SCSITape free]` releases the device through `_devAcquired`, not `_reservedTargetLun`

**Source:** `SCSITape.m:318-327` (`free`).

**Reference behaviour:** the function (address 1544, 144 bytes) does, in
order: `if (_senseDataPtr /* 0x118 */) IOFree(_senseDataPtr, 0x1C)`
(addresses 1564-1580, `0x1C` = 28 = `sizeof(struct esense_reply)`, matching);
`if (_devAcquired /* 0x121 */) [self releaseDevice]` (addresses 1584-1608,
`paReleasedevice` resolves via `read_macho` to `sel_releaseDevice`) — **before**
`_devLock` is freed; `if
(_devLock /* 0x11C */) [_devLock free]` (addresses 1612-1632); then
unconditionally builds an `objc_super` (receiver = self, class =
`stru_4170.super_class`) and calls `[super free]` (addresses 1636-1668).
There is no reference to `_reservedTargetLun`, `_controller`, `_target`,
`_lun` or `releaseTarget:lun:forOwner:` anywhere in this function.

**Our source:** `SCSITape.m:318-327` does `if (_senseDataPtr) IOFree(...)`;
`if (_devLock) [_devLock free]`; `if (_reservedTargetLun) [_controller
releaseTarget:_target lun:_lun forOwner:_controller]`; `return [super free]`
— no `_devAcquired` check, no `[self releaseDevice]` call, and the
`_controller`-relative release call the reference simply does not have here.

**Consequence:** real, non-cosmetic divergence in both directions — our
`free` never releases an acquired device via `releaseDevice`'s own path (so
`-acquireDevice`'s and `-releaseDevice`'s missing `reserveTarget:`/
`reserveAllLuns:`/`releaseAllLuns:` calls, see below, would also never fire
during teardown if an object is freed while the device is held), and it
performs a `releaseTarget:lun:forOwner:` call the reference never makes at
this call site. The `[_controller releaseTarget:_target lun:_lun
forOwner:_controller]` argument list is also suspect independent of this
finding: it passes `_controller` as `forOwner:`, which does not match
`SCSITape.m:102-104`'s own `probe:`-time reservation using `forOwner:tapeId`
(the `SCSITape` instance, not the controller) — but since the reference makes
no such call here at all, this task cannot compare it against a reference
argument list and records it only as an internal inconsistency worth Task
3/fix-pass attention. Left `unexamined`.

**Ordering hazard for the fix pass:** the reference calls `[self
releaseDevice]` *before* `[_devLock free]`, and `-releaseDevice` (see below)
itself locks and unlocks `_devLock`. A fix that adds the `releaseDevice` call
to our `free` by simply appending it after the existing `[_devLock free]`
line, rather than inserting it before, would have `-releaseDevice` lock an
already-freed `_devLock` — a use-after-free. The fix pass must preserve the
reference's ordering, not just add the missing call anywhere in the function.

## SCSI command methods

Task 3 read the nine SCSI-command-issuing methods at addresses 2608-5756
(`analysis.named.json`) instruction by instruction against `SCSITape.m`,
resolving every `bl` island via `read_macho` against `SCSITape_reloc`'s
relocation table (the same technique Task 2 used for `__message_refs`) and
cross-checking every literal against the constants in
`src/kernel-7/bsd/dev/scsireg.h` and
`src/drvSCSITape/SCSITape.drvproj/SCSITape.lksproj/SCSITapeTypes.h`. All nine
reached `assembly-matched` — no divergence found in this block.

### The jump-table check (spec §2.1)

`-[SCSITape executeMTOperation:]` (address 5000) builds a 14-entry jump table
at `__TEXT,__const` offset 0 (raw address 0x2e34-0x2e68, the `PPC_RELOC_SECTDIFF`
run the spec calls out). Resolving it against `__TEXT,__text`:

| `mt_op` (index) | Target | Owning function |
| --- | --- | --- |
| 0 (`MTWEOF`) | `0x140c` | `-[SCSITape executeMTOperation:]` |
| 1 (`MTFSF`) | `0x1418` | `-[SCSITape executeMTOperation:]` |
| 2 (`MTBSF`) | `0x1448` | `-[SCSITape executeMTOperation:]` |
| 3 (`MTFSR`) | `0x1478` | `-[SCSITape executeMTOperation:]` |
| 4 (`MTBSR`) | `0x14a4` | `-[SCSITape executeMTOperation:]` |
| 5 (`MTREW`) | `0x14d4` | `-[SCSITape executeMTOperation:]` |
| 6 (`MTOFFL`) | `0x14dc` | `-[SCSITape executeMTOperation:]` |
| 7 (`MTNOP`) | `0x14f0` | `-[SCSITape executeMTOperation:]` |
| 8 (`MTRETEN`) | `0x14f0` | `-[SCSITape executeMTOperation:]` |
| 9 (`MTERASE`) | `0x14f0` | `-[SCSITape executeMTOperation:]` |
| 10 (unused) | `0x14f0` | `-[SCSITape executeMTOperation:]` |
| 11 (unused) | `0x14f0` | `-[SCSITape executeMTOperation:]` |
| 12 (`MTCACHE`) | `0x14f0` | `-[SCSITape executeMTOperation:]` |
| 13 (`MTNOCACHE`) | `0x14f0` | `-[SCSITape executeMTOperation:]` |

Exactly the expected shape: 14 entries, all inside this one function, distinct
targets for indices 0-6, and indices 7-13 (`MTNOP`/`MTRETEN`/`MTERASE`/two
unused slots/`MTCACHE`/`MTNOCACHE`) all collapsing onto the same default body
at `0x14f0`. `src/kernel-7/bsd/sys/mtio.h:75-88` gives the `mt_op` values
(`MTWEOF`=0 ... `MTOFFL`=6, `MTNOP`=7, `MTRETEN`=8, `MTERASE`=9, `MTCACHE`=12,
`MTNOCACHE`=13, with 10-11 unassigned) — the reference's switch range is
therefore 0-13 packed contiguously, matching our `SCSITape.m:801`'s `switch`
case set and case order (`MTWEOF`, `MTFSF`, `MTBSF`, `MTFSR`, `MTBSR`, `MTREW`,
`MTOFFL` as distinct cases; `MTNOP`/`MTCACHE`/`MTNOCACHE`/`MTRETEN`/`MTERASE`
falling to one `default:` body) case for case, index for index. No reordering,
no collapsed case that should be distinct or vice versa — this is the
`SCSIServer` mis-wired-dispatch-table class of defect, checked and clean.

Beyond the table itself, every one of the seven distinct case bodies (and the
default) was read at instruction level and matches `SCSITape.m:821-874`
exactly, including a compiler code-sharing pattern worth recording since it
looks like a bug on first read: cases that compute a value and then jump
*into the middle of another case's own instruction sequence* to reach a
shared tail. `MTFSF`/`MTBSF` (cases 1/2) each compute
`timeoutLength = mt_count * ST_IOTO_SPFM` (`0x258` = 600) into `r0`, then
branch directly to the `stw r0,timeoutLength` instruction that is physically
part of the `MTFSR`/`MTBSR` (cases 3/4) bodies, skipping those cases' own
literal-timeout stores, and fall through into the shared `assign_cdb_c6s_len`
call — reproducing `goto setcount_f;`/`goto setcount_b;` (`SCSITape.m:830`,
`836`) exactly. `MTWEOF` (case 0) branches straight into case 3's tail past
*both* the timeout store and the `stb` opcode store, reproducing the
fallthrough `goto setcount_f;` at `SCSITape.m:824` (no per-op timeout
override). `MTREW` (case 5) branches into case 6's (`MTOFFL`) `stb` opcode
instruction with `r0` pre-loaded to `C6OP_REWIND` (1), then falls through
case 6's own `timeoutLength = ST_IOTO_RWD` (`0x12C` = 300) store — matching
`SCSITape.m:855-858`'s `cdbp->c6s_opcode = C6OP_REWIND; scsiReq.timeoutLength
= ST_IOTO_RWD;` exactly, since both `MTREW` and `MTOFFL` want that same
timeout value. The default case sets `r3 = SR_IOST_CMDREJ` (7) and branches
straight to the function epilogue, skipping the `executeRequest:` call
entirely — matching `default: rtn = SR_IOST_CMDREJ; goto out;`
(`SCSITape.m:872-873`). None of this sharing changes behavior; it is the
compiler merging identical tail instructions across cases, not a control-flow
divergence, so it does not block `assembly-matched`.

### Per-function CDB evidence

All nine build (or, for `setBlockSize:`, indirectly rely on)
`cdb_6_t`/`cdb_6s_t` at a fixed 4-byte offset into the `IOSCSIRequest` on the
stack (confirmed by the `cdbp` pointer arithmetic in every function: cdb base
= scsiReq base + 4, matching `struct cdb_6`'s big-endian bitfield layout in
`scsireg.h:80-100`, where `c6_opcode:8`/`c6_lun:3`/`c6_lba:21` share one
32-bit word at cdb offset 0 and `c6_len` is a separate byte at cdb offset 4;
`struct cdb_6s` packs `c6s_opcode` alone at offset 0 and
`c6s_lun:3`/`c6s_spare:3`/`c6s_opt:2` alone at offset 1, per `scsireg.h:108-133`).
Every opcode, offset, and length constant below was cross-checked against
`scsireg.h`'s `#define`s and the struct sizes they imply.

| Address | Function | Status | CDB evidence |
| --- | --- | --- | --- |
| 2608 | `-[SCSITape stInquiry:]` | `assembly-matched` | `cdbp[0] = 0x12` (`C6OP_INQUIRY`); `c6_lun` bitfield insert (`insrwi`) into the same 32-bit word at offset 0, sourced from `_target`/`_lun` (`0x10C`/`0x10D`); `cdbp[4] = 0x41` (65 = `sizeof(inquiry_reply_t)`, confirmed by summing `scsireg.h:522-601`'s fields: 4 packed bytes + `ir_addlistlen`+`ir_zero3`+`ir_zero4` byte+`ir_reladr` byte + `vendorid[8]`+`productid[16]`+`revision[4]`+`misc[28]`+`endofid[1]` = 65); matches `SCSITape.m:523-525` exactly. The "bad DMA transfer" branch compares `bytesTransferred` against a baked-in `5` (`offsetof(inquiry_reply_t, ir_zero3)`), matching `SCSITape.m:533-534`'s `(char*)&alignedReply->ir_zero3 - (char*)alignedReply` computed at compile time |
| 3124 | `-[SCSITape stTestReady]` | `assembly-matched` | `cdbp[0] = 0x00` (`C6OP_TESTRDY`); `c6_lun` bitfield insert from `_lun`; no `c6_len` write (source sets none either); return value computed via `subfic`/`adde` ("zero-to-1, else-0" idiom) — `YES` iff `driverStatus == SR_IOST_GOOD` (0), `NO` otherwise, matching the `switch(driverStatus){case SR_IOST_GOOD: YES; default: NO;}` at `SCSITape.m:592-599` |
| 3332 | `-[SCSITape stCloseFile]` | `assembly-matched` | `cdbp->c6s_opcode = 0x10` (`C6OP_WRTFM`) at offset 0; no `c6s_lun` write (matches — source never sets it for the sequential CDB, leaving `bzero`'s 0); calls `_assign_cdb_c6s_len(cdbp, 1)` (address 6872, confirmed by symbol lookup in `analysis.named.json`) — matches `SCSITape.m:616-617`'s `cdbp->c6s_opcode = C6OP_WRTFM; assign_cdb_c6s_len(cdbp, 1);` |
| 3560 | `-[SCSITape stRewind]` | `assembly-matched` | `timeoutLength = 0x12C` (300 = `ST_IOTO_RWD`, `SCSITapeTypes.h:29`); `cdbp->c6s_opcode = 0x01` (`C6OP_REWIND`) at offset 0; no length write; matches `SCSITape.m:634-636` |
| 3740 | `-[SCSITape requestSense:]` | `assembly-matched` | `cdbp[0] = 0x03` (`C6OP_REQSENSE`); `c6_lun` bitfield insert from `_lun`; `cdbp[4] = 0x1C` (28 = `sizeof(esense_reply_t)`, confirmed by summing `scsireg.h:422-502`'s big-endian, non-natural-alignment fields and rounding to 4-byte struct alignment: 26 raw bytes → 28); calls `_controller`'s 3-arg `executeRequest:buffer:client:` directly (selector resolved via `__message_refs` offset 112, distinct from the other eight functions' 4-arg `executeRequest:buffer:client:senseBuf:` at offset 108) — matches `SCSITape.m:682-684`'s direct `[_controller executeRequest:...]` call that bypasses `self`'s wrapper |
| 4172 | `-[SCSITape stModeSelect:]` | `assembly-matched` | `count` read from `modeSelectParmsPtr` offset `0x3C` (60 = `sizeof(mode_sel_data_t)`, confirmed via `mode_sel_hdr_t`(4) + `mode_sel_bd_t`(8) + `msd_vudata[0x30]`(48) = 60, so `msp_bcount` sits immediately after `msp_data`); `cdbp[0] = 0x15` (`C6OP_MODESELECT`); `c6_lun` bitfield insert; `cdbp[4] = count` (register, not immediate, but same offset); `bcopy(&modeSelectParmsPtr->msp_data, alignedBuf, count)` — matches `SCSITape.m:700, 730-734` |
| 4584 | `-[SCSITape stModeSense:]` | `assembly-matched` | Same `count`-at-`0x3C` read; `cdbp[0] = 0x1A` (`C6OP_MODESENSE`); `c6_lun` bitfield insert; `cdbp[4] = count`; post-call `bcopy(alignedBuf, &modeSenseParmsPtr->msp_data, count)` guarded on `rtn == SR_IOST_GOOD` — matches `SCSITape.m:752, 782-784, 791-792` |
| 5000 | `-[SCSITape executeMTOperation:]` | `assembly-matched` | Jump table and all seven case bodies verified above (opcodes `C6OP_WRTFM`(0x10)/`C6OP_SPACE`(0x11, `C6OPT_SPACE_FM`=1 or `C6OPT_SPACE_LB`=0)/`C6OP_REWIND`(0x01)/`C6OP_STARTSTOP`(0x1B), timeouts `ST_IOTO_SPFM`(600)/`ST_IOTO_SPR`(60)/`ST_IOTO_RWD`(300), default `rtn = SR_IOST_CMDREJ`(7)) — matches `SCSITape.m:821-874` case for case |
| 5496 | `-[SCSITape setBlockSize:]` | `assembly-matched` | Builds no CDB directly (delegates to `stModeSense:`/`stModeSelect:`); `IOMalloc(0x40)` (64 = `sizeof(modesel_parms_t)` = 60 + 4); `msh_sd_length_0`/`msh_med_type` zeroed at offsets 0/1; `msh_wp` cleared via a 1-bit `clrlwi` at offset 2 (preserving the sense-derived `bufmode`/`speed` bits already in that byte, not zeroing the whole byte); `msh_bd_length = 8` (`sizeof(mode_sel_bd_t)`) at offset 3; calls `_assign_msbd_blocklength`/`_assign_msbd_numblocks` (addresses 6928/6904, confirmed by symbol lookup) on the block descriptor at `msp_data+4`; `_blockSize = blockSize` written at `0x114` (matches the ivar table); both `stModeSense:`/`stModeSelect:` failure paths converge on the same `IOFree(mspp,0x40); return [_controller returnFromScStatus:rtn];` — matches `SCSITape.m:895-929` in full |

No findings were added for this block — every entry reached
`assembly-matched` and none diverges from the source.

## Finding: `-[SCSITape acquireDevice]` reserves the target/lun and all LUNs with the controller; our source only flips a flag

**Source:** `SCSITape.m:457-470` (`acquireDevice`).

**Reference behaviour:** the function (address 2280, 168 bytes), after `[_devLock
lock]` (addresses 2304-2316, offset `0x11C`), reads `_devAcquired` (`0x121`)
and if already `1` sets `r30 = -0x2D5` (`-725` = `IO_R_BUSY`,
`src/driverkit-3/driverkit/return.h:64`) and jumps straight to unlock/return
(addresses 2320-2372). Otherwise it calls `[_controller reserveTarget:_target
lun:_lun forOwner:self]` (addresses 2332-2356, `_target`/`_lun` read from
`0x10C`/`0x10D`, `_controller` from `0x108`, receiver = self) and if that
returns non-zero (matching `probe:`'s own convention that a non-zero
`reserveTarget:lun:forOwner:` means "someone already has this one") takes the
same `IO_R_BUSY` path. Only when the reservation actually succeeds does it
call `[self reserveAllLuns]` (addresses 2376-2388, `paReserveallluns`),
then set `_devAcquired = 1` and return `IO_R_SUCCESS` (0).

**Our source:** `SCSITape.m:457-470` locks `_devLock`, checks `_devAcquired`
for the busy case, and otherwise unconditionally sets `_devAcquired = YES`
and returns `IO_R_SUCCESS` — it never calls `reserveTarget:lun:forOwner:` or
`reserveAllLuns` at all.

**Consequence:** real, non-cosmetic divergence — our `acquireDevice` can never
actually fail with `IO_R_BUSY` from a controller-level conflict (only from
re-entrant acquisition on the same object), and never performs the
controller-level reservation the reference treats as the actual exclusion
mechanism. `-reserveAllLuns` and `-releaseAllLuns` (ledger addresses 7012 and
7280) exist in the reference binary but have no implementation anywhere in
our `SCSITape.m`/`SCSITape.h` (`grep` confirms no such selector text in this
tree) — Task 7's absent-methods pass needs both, and the fix pass needs this
function rewritten to call them. Left `unexamined`.

## Finding: `-[SCSITape releaseDevice]` releases all LUNs and the controller reservation; our source only flips a flag

**Source:** `SCSITape.m:472-478` (`releaseDevice`).

**Reference behaviour:** the function (address 2464, 128 bytes) locks
`_devLock` (`0x11C`), sets `_devAcquired = 0` (`0x121`), then calls `[self
releaseAllLuns]` (addresses 2508-2520, `paReleaseallluns`) and `[_controller
releaseTarget:_target lun:_lun forOwner:self]` (addresses 2524-2548,
`paReleasetargetL`, same `_controller`/`_target`/`_lun` offsets as
`acquireDevice`), before unlocking and returning `IO_R_SUCCESS`.

**Our source:** `SCSITape.m:472-478` locks `_devLock`, sets `_devAcquired =
NO`, unlocks, and returns `IO_R_SUCCESS` — no `releaseAllLuns` call and no
`releaseTarget:lun:forOwner:` call.

**Consequence:** the mirror image of the `acquireDevice` finding above: our
`releaseDevice` never actually releases the controller-level reservation
`acquireDevice` is supposed to take, so once both functions are fixed to match
the reference they need to be fixed together (the fix pass should not add the
`reserveTarget:`/`reserveAllLuns` calls to `acquireDevice` without adding the
matching `releaseTarget:`/`releaseAllLuns` calls here, or the reservation
would leak). Left `unexamined`.

## SCSITape.m C helpers

Task 4 read the six C (non-Objective-C) helper functions at addresses
6748-7012 (`analysis.named.json`) instruction by instruction against
`SCSITape.m:1093-1196`, cross-checking every offset against `struct cdb_6s`,
`struct mode_sel_bd` and `struct esense_reply` in
`src/kernel-7/bsd/dev/scsireg.h`. `SCSITape.m:38-43`'s old-style (no
prototype) forward declarations name all six; none of them are Objective-C
methods, so none carry a `+`/`-` selector prefix in the reference symbol
table — they are plain C functions named `_moveString`,
`_assign_cdb_c6s_len`, `_assign_msbd_numblocks`, `_assign_msbd_blocklength`,
`_cdb_c6s_len_value`, `_er_info_value`.

**The compiler-defined-macro check.** Three of these five bit-field
functions turn on `#if __BIG_ENDIAN__` / `#if __NATURAL_ALIGNMENT__` pairs in
`scsireg.h`. `src/cc-1/cc/config/rs6000/apple.h:135-141` defines three
branches of `CPP_PREDEFINES`: the `MAC_OS_X_SERVER_1_0` branch predefines
`-DNATURAL_ALIGNMENT` (no underscores), while the `MAC_OS_X` and default
branches predefine `-D__NATURAL_ALIGNMENT__` (double underscores). The
recovered disassembly itself — not the macro — settles which branch Apple's
build took: the three `stb` instructions in `_assign_cdb_c6s_len` (6872) at
byte offsets 2, 3, and 4 can only be explained by the `u_char c6s_len[3]`
array form, which requires the `__NATURAL_ALIGNMENT__` test (with double
underscores) to be true. Apple's build therefore took either the `MAC_OS_X`
branch or the default branch, not the `MAC_OS_X_SERVER_1_0` branch. The
recovered bit layouts confirm this.

**The recovered bit-layout table.**

| Structure | Field | Byte offset (from struct base) | Bits | Confirmed by |
| --- | --- | --- | --- | --- |
| `cdb_6s_t` | `c6s_opcode` | 0 | 8 (whole byte) | inferred (untouched by any of the six; `stCloseFile`/`stRewind` etc. write it directly per Task 3) |
| `cdb_6s_t` | `c6s_lun:3, c6s_spare:3, c6s_opt:2` | 1 | bits 7-5 / 4-2 / 1-0 of byte 1 | Task 3's `c6s_opt` finding (low 2 bits of CDB byte 1); not directly touched by these six |
| `cdb_6s_t` | `c6s_len[0..2]` (array, `__NATURAL_ALIGNMENT__`) | 2, 3, 4 (one byte each) | 8 each, MSB-first (`len[0]<<16 \| len[1]<<8 \| len[2]`) | `_assign_cdb_c6s_len` (6872): `stb` at offsets 2/3/4 from `length>>16`, `length>>8`, `length` — matches `SCSITape.m:1131-1133` exactly; `_cdb_c6s_len_value` (6952) reads the same three offsets back with the inverse shifts (see finding below) |
| `cdb_6s_t` | `c6s_ctrl` | 5 | 8 (whole byte) | inferred (never touched by these six; last byte of the 6-byte CDB) |
| `mode_sel_bd_t` | `msbd_density:8, msbd_numblocks:24` | word at offset 0 (density = byte 0, numblocks = bytes 1-3) | 8 / 24 | `_assign_msbd_numblocks` (6904): `lwz`+`insrwi r0,r4,24,8`+`stw` — inserts the low 24 bits of `numblocks` into bits 8-31 of the word at offset 0, leaving byte 0 (`msbd_density`) untouched; matches `SCSITape.m:1154-1160`'s unconditional `msbdp->msbd_numblocks = numblocks;` (no `__NATURAL_ALIGNMENT__` branch on this struct, unlike `cdb_6s_t`) |
| `mode_sel_bd_t` | `msbd_rsvd_0:8, msbd_blocklength:24` | word at offset 4 (rsvd = byte 4, blocklength = bytes 5-7) | 8 / 24 | `_assign_msbd_blocklength` (6928): identical `lwz`+`insrwi r0,r4,24,8`+`stw` pattern at offset 4; matches `SCSITape.m:1167-1173`'s `msbdp->msbd_blocklength = length;` |
| `esense_reply_t` | `er_info:24, er_addsenselen:8` | word at offset 4 (info = bytes 4-6, addsenselen = byte 7) | 24 / 8 | `_er_info_value` (6992): `lwz r3,4(r3)` + `srwi r3,r3,8` — loads the aligned word at offset 4 and shifts right 8 to drop `er_addsenselen`, leaving the top 24 bits; matches `SCSITape.m:1190-1195`'s unconditional `return (esrp->er_info);` (this field's home word starts at offset 4, a 4-byte-aligned boundary, so no `__NATURAL_ALIGNMENT__` branch is needed here the way `cdb_6s_t.c6s_len` needs one at its unaligned offset 2) |

Per-function disposition:

| Address | Function | Status | What was compared |
| --- | --- | --- | --- |
| 6748 | `_moveString` | `assembly-matched` | Full control flow (11 basic blocks) traced against `SCSITape.m:1093-1119`: `lastCharSpace` in `r9`, `outpStart` in `r11`, the `'\0'`-skip branch (`loc_1A94`), the `' '`-collapse branch pair (`loc_1AA0`/`loc_1AA8`), the shared `copyit:` tail (`loc_1AAC`), and the `while(inlength && outlength)` two-part post-test loop (`cmpwi cr1,r5,0` / `bne- loc_1A70` testing `inlength`, looping back to the `outlength` test) — matches the `switch(*inp){case '\0': ...; case ' ': ...; default: ...}` state machine and the `outp - outpStart` return value exactly |
| 6872 | `_assign_cdb_c6s_len` | `assembly-matched` | Three `stb`s at offsets 2/3/4 from `length>>16`, `length>>8`, `length` — matches `SCSITape.m:1131-1133`'s `__NATURAL_ALIGNMENT__` branch (confirmed active per the macro check above) instruction for instruction; also confirms the `c6s_len` byte-offset table above |
| 6904 | `_assign_msbd_numblocks` | `assembly-matched` | `lwz`/`insrwi r0,r4,24,8`/`stw` at offset 0 — matches `SCSITape.m:1154-1160` |
| 6928 | `_assign_msbd_blocklength` | `assembly-matched` | `lwz`/`insrwi r0,r4,24,8`/`stw` at offset 4 — matches `SCSITape.m:1167-1173` |
| 6952 | `_cdb_c6s_len_value` | `unexamined` | Finding: reference reconstructs the 24-bit value by loading the three `c6s_len` bytes at offsets 2/3/4 and shifting/OR-ing them (`<<16`/`<<8`/`<<0`); `SCSITape.m:1180-1187`'s `__BIG_ENDIAN__` branch is a bare `return (cdbp->c6s_len);` with no `__NATURAL_ALIGNMENT__` sub-branch, unlike its sibling `assign_cdb_c6s_len` — see finding below |
| 6992 | `_er_info_value` | `assembly-matched` | `lwz r3,4(r3)` + `srwi r3,r3,8` — matches `SCSITape.m:1190-1195`'s unconditional `return (esrp->er_info);`; confirms `er_info` occupies the top 24 bits of the aligned word at offset 4 |

## Finding: `cdb_c6s_len_value`'s `__BIG_ENDIAN__` branch returns the array's address instead of reconstructing the 24-bit length

**Source:** `SCSITape.m:1180-1187` (`cdb_c6s_len_value`), compared against its
sibling `SCSITape.m:1127-1149` (`assign_cdb_c6s_len`) and
`src/kernel-7/bsd/dev/scsireg.h:108-133` (`struct cdb_6s`).

**Reference behaviour:** the function (address 6952, 40 bytes) loads three
individual bytes — `lbz r9,2(r3)` / `lbz r0,3(r3)` / `lbz r3,4(r3)` — shifts
the first two left by 16 and 8 respectively, and ORs all three together,
returning `(c6s_len[0]<<16) | (c6s_len[1]<<8) | c6s_len[2]`. This is exactly
the inverse of what `_assign_cdb_c6s_len` (address 6872, confirmed
`assembly-matched` above) writes to those same three offsets, and it is the
same reconstruction shape as the `__LITTLE_ENDIAN__` branch of our own source
(`SCSITape.m:1185`: `cdbp->c6s_len0 | (cdbp->c6s_len1 << 8) | (cdbp->c6s_len2
<< 16)`, same idea with the byte order flipped for the opposite endianness).

**Our source:** `scsireg.h:108-133` declares `cdb_6s_t.c6s_len` two different
ways depending on `__NATURAL_ALIGNMENT__`: a 3-element `u_char c6s_len[3]`
array (offsets 2/3/4) when it's defined, or a packed 24-bit `u_int
c6s_len:24` bitfield sharing a word with `c6s_ctrl:8` when it isn't.
`src/cc-1/cc/config/rs6000/apple.h:137` and `src/cc-791/.../apple.h:137`
confirm `__NATURAL_ALIGNMENT__` is unconditionally predefined for ppc, so the
array form is what a real build uses — and `assign_cdb_c6s_len`'s own
`__NATURAL_ALIGNMENT__`-guarded three-`stb` body (`SCSITape.m:1131-1133`)
agrees. But `cdb_c6s_len_value`'s `__BIG_ENDIAN__` branch
(`SCSITape.m:1183`) is a single, unguarded `return (cdbp->c6s_len);` — no
nested `__NATURAL_ALIGNMENT__` check at all. With the array form active,
`cdbp->c6s_len` decays to a `u_char *` (the address of `c6s_len[0]`), and
returning it from a function declared `int cdb_c6s_len_value()` implicitly
truncates/reinterprets that pointer as an integer — a compiler warning in
practice, and a value with no relationship to the transfer length the
reference binary actually computes.

**Consequence:** real, non-cosmetic divergence, and a live one:
`SCSITape.m:1001-1003` calls `cdb_c6s_len_value (&scsiReq->cdb.cdb_c6s) -
er_info_value (senseBuf)` to compute `transferLength` in the filemark/`bytesTransferred`
correction path of `-executeRequest:...` (the "DPT firmware bug" workaround),
and that value is written back into `scsiReq->bytesTransferred` and used in
the `isFixedBlock`/`_blockSize` multiply right after. A garbage
pointer-as-int in place of the real byte count corrupts that whole
correction path. The fix is narrow and mirrors the sibling function: give
`cdb_c6s_len_value`'s `__BIG_ENDIAN__` branch the same `__NATURAL_ALIGNMENT__`
split `assign_cdb_c6s_len` already has, with the array-form side reading
`(cdbp->c6s_len[0] << 16) | (cdbp->c6s_len[1] << 8) | cdbp->c6s_len[2]`
(matching the reference exactly) instead of `return (cdbp->c6s_len);`. Left
`unexamined`; Task 7/the fix pass should apply this.

## SCSITapeKern.m

Task 5 read the nine BSD kernel device-switch functions at addresses
7424-11320 (`analysis.named.json`) instruction by instruction against
`SCSITapeKern.m:87-747`. This completes `SCSITape_reloc`'s 44 mapped
functions.

### Device-switch slot mapping (spec's Step 1 check)

`_st_devsw_init` (address 7424) builds its `IOAddToCdevsw` call by loading
`r3`-`r10` and three stack slots in argument order, confirmed by resolving
every load through `read_macho`'s relocation table rather than trusting IDA's
`sub_XXXX` labels:

| Register/stack slot | Argument (per `driverkit/devsw.h`) | Value loaded | Relocation target |
| --- | --- | --- | --- |
| `r3` | `openFunc` | `_stopen` | `__TEXT,__text` (internal) |
| `r4` | `closeFunc` | `_stclose` | `__TEXT,__text` (internal) |
| `r5` | `readFunc` | `_stread` | `__TEXT,__text` (internal) |
| `r6` | `writeFunc` | `_stwrite` | `__TEXT,__text` (internal) |
| `r7` | `ioctlFunc` | `_stioctl` | `__TEXT,__text` (internal) |
| `r8` | `stopFunc` | `_enodev` | external, confirmed by relocation at address 7456 |
| `r9` | `resetFunc` | `_nulldev` | external, confirmed by relocation at address 7516 |
| `r10` | `selectFunc` | `_nulldev` (copy of `r9`) | same value as `resetFunc` |
| stack +0 | `mmapFunc` | `_enodev` (copy of `r8`, pre-stored at address 7464) | same value as `stopFunc` |
| stack +4 | `getcFunc` | `_enodev` | same |
| stack +8 | `putcFunc` | `_enodev` | same |

`IOAddToCdevswAt`'s own body (`src/driverkit-3/libDriver/Kernel/devswAndVfssw.m:166-176`)
assigns its eleven parameters straight across to `struct cdevsw`'s eleven
switch-function fields (`src/kernel-7/bsd/sys/conf.h:150-165`) in the exact
same order the header declares them — no indirection between the parameter
list and the struct fields. Combined with the table above: **every slot our
source installs (`SCSITapeKern.m:98-108`) lands in the position the reference
uses** — `stopen`/`stclose`/`stread`/`stwrite`/`stioctl` in the five primary
slots, `nulldev` in `reset`/`select`, and an `enodev`-class stub in
`stop`/`mmap`/`getc`/`putc`. There is no transposition anywhere in this table;
the slot-mapping check the brief called out as the critical risk is clean.

### Finding: `_st_devsw_init` installs `_enodev`, but our source passes `nodev`, an identifier with no definition anywhere in this tree

**Source:** `SCSITapeKern.m:81-82` (`extern int nodev();` declaration),
`SCSITapeKern.m:103,106-108` (the four `(IOSwitchFunc) nodev` arguments to
`IOAddToCdevsw`).

**Reference behaviour:** as the table above shows, the `stop`/`mmap`/`getc`/
`putc` slots are all loaded from a single external relocation to `_enodev`
(confirmed at addresses 7456-7460; the same loaded value is stored to the
three stack-passed argument slots and left live in `r8` for the register
argument, so all four slots get the identical stub).

**Our source:** declares and calls `nodev()`, not `enodev()`. `grep` across
`src/kernel-7/bsd` finds no function named `nodev` anywhere — only `enodev`
(`src/kernel-7/bsd/kern/subr_xxx.c:82`, returns `ENODEV`) and `nulldev`
(`src/kernel-7/bsd/kern/subr_xxx.c:155`, returns 0) exist as real kernel
stubs. `src/kernel-7/bsd/sys/systm.h:129,131` prototypes both `enodev` and
`nulldev` but never `nodev`. The only other reference to a function spelled
`nodev` in the entire tree is `src/driverkit-3/Examples/KStub/IOStubKernLoad.m`,
an example that has the identical undefined-symbol problem.

**Consequence:** as written, `SCSITapeKern.m` cannot link against this tree's
kernel — `nodev` resolves to nothing. This is distinct from the slot-mapping
check above (which is clean): the four affected slots are in the *right
position*, they just name a stub that doesn't exist. Given the reference's
`_enodev` and our tree's `nulldev`/`enodev` pair, `nodev` was almost certainly
meant to be `enodev` (an `ENODEV`-returning stub is exactly the correct
semantics for `stop`/`mmap`/`getc`/`putc` on a tape device). Left
`unexamined`; this is squarely Task 8's "naming and compile errors" scope,
but it surfaced here because Step 1 required resolving every slot's actual
target.

## Finding: `_st_rw`'s read path unconditionally forces `setSuppressIllegalLength:` and `C6OPT_SIL`, with no getter check at all

**Source:** `SCSITapeKern.m:337-352` (the `suppressIllegalLength` branch
inside `st_rw`, called from `stread`/`stwrite` at lines 252-260).

**Reference behaviour:** `_st_rw` (address 8544) branches on `rw_flag` at
address 9032 (`cmpwi cr1,r25,0` / `bne` to address 9084 for writes, skipping
this whole section). For reads, execution falls into a single 40-byte basic
block (addresses 9040-9079) with **no internal branch at all**: it calls
`objc_msgSend` through the message-ref at `__OBJC,__message_refs` offset 148
(address 16688) with `r5=1` — the identical message-ref address used by
`_stopen`'s confirmed `[scsiTape setSuppressIllegalLength: YES]` call at
address 7888 (both resolve to the same relocation target, confirmed via
`read_macho`) — and then unconditionally performs a read-modify-write OR of
`C6OPT_SIL` (2) into `cdbp->c6s_opt` (addresses 9060-9080). There is no
comparison of any return value anywhere in this block; both the setter call
and the `c6s_opt` OR execute on every single read, regardless of the tape
object's prior `_suppressIllegalLength` state.

**Our source:** calls the *getter* `[scsiTape suppressIllegalLength]` and
only performs `cdbp->c6s_opt |= C6OPT_SIL;` when it returns true; when false,
it takes an else branch that (outside `#ifdef DEBUG`) does nothing. It never
calls `setSuppressIllegalLength:` from `st_rw` at all — that setter is only
ever invoked from `stopen`'s Exabyte setup path (line 167) in our source.

**Consequence:** real, non-cosmetic, and unconditional — not merely a
different check order. The reference silently latches
`_suppressIllegalLength` to `YES` as a side effect of the *first* read (or
write, since `stwrite` also calls `st_rw`, though the write path never
reaches this block) and, independent of that ivar, unconditionally suppresses
illegal-length errors on every read's CDB. Our source instead honours
whatever `_suppressIllegalLength` already was, never changes it from within
`st_rw`, and only sets `C6OPT_SIL` when that pre-existing flag was already
true. A caller that never explicitly called `setSuppressIllegalLength:` (the
common case outside Exabyte's `stopen` path) gets different CDB bytes and a
different persistent ivar value than the reference produces on every read.
Left `unexamined`; Task 11/the fix pass should replace the conditional with
the reference's unconditional setter call + OR.

## Finding: `_stioctl`'s `MTIOCGET` case writes `MT_ISEXB`, an identifier with no definition anywhere in this tree

**Source:** `SCSITapeKern.m:484-485` (`if(ST_EXABYTE(dev)) mgp->mt_type =
MT_ISEXB;`).

**Reference behaviour:** address 9928 (`li r0, 0xC`) stores `0xC` (12) into
`mgp->mt_type` on the Exabyte branch; address 9936 (`li r0, 0x14`) stores
`0x14` (20, confirmed equal to `MT_ISGS` in `src/kernel-7/bsd/sys/mtio.h:141`)
on the generic branch.

**Our source:** writes `MT_ISEXB`, which — unlike `MT_ISGS` — is not defined
anywhere in `src/kernel-7/bsd/sys/mtio.h` or anywhere else in this tree
(`grep` finds only this one use site). `mtio.h:128-129` defines
`MT_ISEXABYTE` and `MT_ISEXA8200`, both `0xc`, which numerically match what
the reference stores, but neither is spelled `MT_ISEXB`.

**Consequence:** same class as the `nodev` finding above — this is a missing
macro definition, not a value or control-flow mismatch (the reference's
constant, `0xC`, agrees with `MT_ISEXABYTE`/`MT_ISEXA8200`), but the file as
written will not compile. Every other case in this switch was checked against
the reference's decision-tree constants (see below) and matches exactly. Left
`unexamined`; Task 8's scope, surfaced here for the same reason as `nodev`.

**The switch's decision tree (spec's error-path check).** `_stioctl` compares
`cmd` (r4) against nine 32-bit ioctl codes via a signed-comparison binary
search rather than a jump table (the codes are too sparse for one). Every
comparison constant was decoded from its `lis`/`ori` pair and checked against
`_IO`/`_IOR`/`_IOW`/`_IOWR` (`src/kernel-7/bsd/sys/ioccom.h:88-92`) applied to
each `MTIOC*` macro in `src/kernel-7/bsd/sys/mtio.h` and
`src/kernel-7/bsd/dev/scsireg.h:994-1004`:

| Constant compared | Encodes | Matches |
| --- | --- | --- |
| `0xC0586D0B` | `_IOWR('m',11,88)` | `MTIOCSRQ` (`scsi_req_t`, confirmed 88 bytes below) |
| `0x80086D01` | `_IOW('m',1,8)` | `MTIOCTOP` (`struct mtop`, 8 bytes) |
| `0x80046D05` | `_IOW('m',5,4)` | `MTIOCFIXBLK` (`int`) |
| `0x80406D07` | `_IOW('m',7,64)` | `MTIOCMODSEL` (`struct modesel_parms`, 64 bytes) |
| `0xC0406D08` | `_IOWR('m',8,64)` | `MTIOCMODSEN` |
| `0x20006D09` | `_IO('m',9)` | `MTIOCINILL` |
| `0x20006D06` | `_IO('m',6)` | `MTIOCVARBLK` |
| `0x20006D0A` | `_IO('m',10)` | `MTIOCALILL` |
| `0x403C6D02` | `_IOR('m',2,60)` | `MTIOCGET` (`struct mtget`, 60 bytes) |

All nine constants match their macros exactly (group `'m'`=0x6D and opcode
number both confirmed per constant), every `beq` lands in the case body that
implements the matching source `case`, and the final catch-all (`b loc_27F8`,
address 10232) sets `error = EINVAL` — matching `default: error = EINVAL;`
(`SCSITapeKern.m:548-549`). No case is misrouted and no case is missing.

**The `MTIOCMODSEL`/`MTIOCMODSEN`/`MTIOCSRQ` fall-through is real in both the
reference and our source, not a divergence.** `SCSITapeKern.m:526-546`'s
`MTIOCMODSEL` and `MTIOCMODSEN` cases have no `break;` after their success
path, so on success each one falls into the next case's body. The reference
reproduces this exactly: address 10200 (`beq cr1,loc_27E4`) branches *into*
the `MTIOCSRQ` case body (address 10212) only when `stModeSense:` succeeds,
and the `MTIOCMODSEL` case's own success path (address 10172, not taken on
failure) falls straight into `MTIOCMODSEN`'s body (address 10176) with no
intervening test. Both cases' error paths (`error = EIO; break;`) go through
the same shared block (address 10204) as the `requestSense:` failure path in
`MTIOCGET`. This is a faithfully-reproduced quirk (or bug) in the original
driver, confirmed present in both the reference binary and our source's
current text — not something Task 5 is flagging as a divergence.

## Finding: `_st_doiocsrq` never reads `srp->sr_discon_disable` or `srp->sr_ignore_chkcond`, both of which the reference honours

**Source:** `SCSITapeKern.m:574-732` (`st_doiocsrq`), compared against
`scsi_req_t` (`src/kernel-7/bsd/dev/scsireg.h:826-886`), whose non-`m68k`
branch (lines 857-884) declares, immediately after `sr_exec_time`:
```
u_char sr_cdb_length;
u_char sr_discon_disable:1, sr_cmd_queue_disable:1, sr_sync_disable:1,
       sr_ignore_chkcond:1, sr_pad1:4;
u_char sr_pad2;
u_char sr_flags;
queue_chain_t sr_io_q;
```
the comment on `sr_ignore_chkcond` reads "specifically used for MTIOCSRQ
requests" — i.e. this field exists precisely for this function.

**Reference behaviour (disconnect):** after `bzero(&scsiReq, 88)` and the
`target`/`lun`/`cdb` copies, `_st_doiocsrq` (address 10332) reads the packed
word at `srp+0x4C` (addresses 10796-10828, `sr_cdb_length`/the bitfield
byte/`sr_pad2`/`sr_flags` packed into one big-endian word — `sr_cdb_length`
at offset 0x4C is confirmed by summing every preceding field's offset:
`sr_cdb`(12)+`sr_dma_dir`(4)+`sr_addr`(4)+`sr_dma_max`(4)+`sr_ioto`(4)+
`sr_io_status`(4)+`sr_scsi_status`(1, padded to 4)+`sr_esense`(28)+
`sr_dma_xfr`(4)+`sr_exec_time`(8) = 0x4C, and every one of those offsets is
independently confirmed by a load/store at that exact offset elsewhere in
this same function). It tests bit `0x00800000` of that word — bit 8 of a
32-bit big-endian word, i.e. the *first* bit of the second byte, exactly
where `sr_discon_disable` sits — and sets `scsiReq.disconnect` (the bitfield
word at `scsiReq+28`, per `IOSCSIRequest`'s layout in
`src/driverkit-3/driverkit/scsiRequest.h:56`, whose first bit is `disconnect`
too) to the *inverse*: bit clear (`sr_discon_disable`==0) sets
`disconnect`=1; bit set clears it to 0.

**Reference behaviour (ignore check condition):** it then tests bit
`0x00100000` of the same word — bit 11, exactly where `sr_ignore_chkcond`
sits — and if set (addresses 10832-10908): reads
`scsiTape`'s own `_ignoreCheckCondition[target][lun]` matrix entry (the
`char[32][8]` ivar at offset `0x125`, recovered in Task 2; indexed here by
`scsiReq.target`/`scsiReq.lun`, i.e. the `SCSITape` object's own `target`/
`lun`, not `srp`'s) and `_ignoreOpenCheckCondition` (offset `0x225`), saves
both old values (`r21`, `r22`), forces both to `1`, calls `executeRequest:`,
then (addresses 10944-10980, gated on re-testing the same bit) restores both
ivars to their saved values. If the bit is clear, none of this save/set/
restore runs — `executeRequest:` is called directly with the ivars
untouched.

**Our source:** hardcodes `scsiReq.disconnect = 1;` (`SCSITapeKern.m:689`)
unconditionally and never reads `srp->sr_discon_disable`. It never reads
`srp->sr_ignore_chkcond`, never touches `_ignoreCheckCondition` or
`_ignoreOpenCheckCondition`, anywhere in `st_doiocsrq`.

**Consequence:** two independent, real divergences reachable through the
`MTIOCSRQ` ioctl (the raw SCSI passthrough path used by, e.g., `stblocksize`
and `sdform`-style tools): (1) a caller that sets `sr_discon_disable` to
request "no disconnect during this command" is silently ignored — our source
always allows disconnect; (2) a caller that sets `sr_ignore_chkcond` (the
field's own comment says this is its purpose) to suppress check-condition
handling for one passthrough command gets no suppression at all, and the
`SCSITape` object's ivar state is left completely alone rather than
temporarily overridden and restored. Both are silent (no error returned) —
the caller has no way to detect that its request was not honoured. Left
`unexamined`; the fix pass must preserve the reference's save/restore
ordering (set before `executeRequest:`, restore after, and only when the bit
was actually set) to avoid leaking a forced `_ignoreCheckCondition` state
into later use of the same `SCSITape` object.

## Finding: `_st_doiocsrq` diverges from source for `srp->sr_dma_max == 0`, passing `srp->sr_addr`/`IOVmTaskCurrent()` instead of the declared `NULL` defaults

**Source:** `SCSITapeKern.m:576-581` (initial declarations: `alignedPtr =
NULL`, `alignedLen = 0`, `didAlign = NO`, `client = NULL`), `:596-672` (the
`if(srp->sr_dma_max != 0) { ... }` block that is the only place these four
variables are assigned).

**Reference behaviour:** address 10460 tests `srp->sr_dma_max == 0` and, if
true, branches to address 10672 — a block that runs `alignedLen =
srp->sr_dma_max` (0), **`alignedPtr = srp->sr_addr`**, calls
**`_IOVmTaskCurrent()`** (confirmed via `read_macho`'s relocation at address
10680) for `client`, and sets `didAlign = NO`. This is the exact body of our
source's `else` clause at `SCSITapeKern.m:667-671` — but the reference
reaches it specifically on the `sr_dma_max == 0` path, and it is the *only*
place in the whole function that sets `alignedPtr`/`client` to anything other
than the values computed inside the aligned-copy path (confirmed: the
aligned-copy path, after its own `copyin` handling, branches directly to the
`bzero`/`scsiReq` setup at address 10692, never through address 10672).

**Our source:** the `if(srp->sr_dma_max != 0)` block (`:596-672`) contains an
inner `if(...) { ... } else { alignedLen = srp->sr_dma_max; alignedPtr =
srp->sr_addr; client = IOVmTaskCurrent(); didAlign = NO; }` whose condition
ends in a literal `|| YES` (`:626-631`, with the comment explaining this is
deliberate — "Prevent DMA from user space for now"), making the inner
condition always true and that `else` clause **unreachable dead code** in our
source as written. When the *outer* `if(srp->sr_dma_max != 0)` is false
(`sr_dma_max == 0`), our source skips the entire block, leaving `alignedPtr`,
`client`, `alignedLen`, and `didAlign` at their declared initial values
(`NULL`, `NULL`, `0`, `NO`) — it never executes the code the reference
executes for this case.

**Consequence:** for an `MTIOCSRQ` request with `sr_dma_max == 0` (a valid
no-data-phase SCSI command, e.g. `TEST UNIT READY` through the raw
passthrough), our source calls `executeRequest:buffer:NULL client:NULL
senseBuf:...`, while the reference calls `executeRequest:buffer:srp->sr_addr
client:IOVmTaskCurrent() senseBuf:...`. Since `alignedLen`/`maxTransfer` is 0
either way, whether this is observable depends on whether `executeRequest:`
or anything it calls dereferences `client`/`buffer` when `maxTransfer` is 0 —
not established by this task. What is established is that our source's
control-flow structure (the always-true `|| YES` making the sibling `else`
genuinely unreachable) cannot produce the reference's `sr_dma_max == 0`
behaviour no matter how it is compiled; the defaulting logic needs to move
outside the `if(srp->sr_dma_max != 0)` gate, or be duplicated for the
`sr_dma_max == 0` case, to match. Left `unexamined`.

### Per-function disposition

| Address | Function | Status | What was compared |
| --- | --- | --- | --- |
| 7424 | `_st_devsw_init` | `unexamined` | Slot-mapping table above (clean); `nodev`/`_enodev` finding above |
| 7640 | `_stopen` | `assembly-matched` | Full instruction-level trace: `ST_UNIT`/`stIdMap` lookup, `acquireDevice`/`IO_R_BUSY`→`EBUSY` short-circuit-return (bypassing `IOSetUNIXError`/`IOFree`, matching a bare `return`), `unit>=NST \|\| isInitialized==NO` short-circuit→`releaseDevice`+`ENXIO`, `setIgnoreCheckCondition:`/`stTestReady` bracket, the Exabyte block's `IOMalloc(0x40)`/`msp_bcount=0x11`(`sizeof(mode_sel_hdr)+sizeof(mode_sel_bd)+MSP_VU_EXABYTE`=4+8+5)/`evudp` offset `0xC`/`msh_wp`-only-bit-clear/`msh_bufmode=1` insert/EBD-bit pattern (`0xE00`<<16 matching `nd=0,ebd=1,pe=1,nbe=1` = bits4-6 set, bit2 cleared)/`setBlockSize:`,`stModeSense:`,`stModeSelect:` each with matching `IOFree`+`releaseDevice`+`EIO` failure paths — no divergence |
| 8228 | `_stclose` | `assembly-matched` | `didWrite==YES`→`stCloseFile`→branchless `rtn=(result!=SR_IOST_GOOD)?EIO:0` (verified by simulating the `srawi`/`xor`/`subf`/`srawi`/`andi.` sequence for all inputs); `ST_RETURN(dev)==0`→`stRewind`→same `EIO`-on-failure pattern; unconditional `releaseDevice`; `return(rtn)` — no divergence |
| 8440 | `_stread` | `assembly-matched` | 9-instruction wrapper; tail-calls `_st_rw` (confirmed via relocation, target address 8544) with `r5=0` (`SR_DMA_RD`, confirmed `=0` in `scsireg.h:818`) |
| 8492 | `_stwrite` | `assembly-matched` | Same wrapper shape, `r5=1` (`SR_DMA_WR=1`, `scsireg.h:819`) |
| 8544 | `_st_rw` | `unexamined` | Full trace against `SCSITapeKern.m:265-426`: `unit>=NST`/`uio_iovcnt!=1`/`iov_len==0` triple bare-return (all three share one epilogue target that bypasses `IOFree`/`IOSetUNIXError`, matching plain `return` vs. `goto out`); nested `[[scsiTape controller] allocateBufferOfLength:...]` call shape; `bzero(&scsiReq,0x58)`; `IOAlign`-vs-plain `maxTransfer`; `disconnect` OR-in; `isFixedBlock`→`howmany()` calling `blockSize` **twice** (matches the macro's literal double-expansion, confirmed via `src/kernel-7/bsd/sys/types.h:150`, not a divergence); read/write opcode+`scsiReq.read` setup; `C6S_MAXLEN`→`EINVAL`; `copyin`-on-write→`EIO`; `executeRequest:`→`EIO`; post-read `copyout`; `driverStatus`→`EIO`; `out:` (`uio_resid`/`IOFree`/`IOSetUNIXError`/return) — all matched **except** the `suppressIllegalLength` finding above |
| 9544 | `_stioctl` | `unexamined` | Full decision-tree decode (table above, clean) and every case body traced (`MTIOCTOP`'s `SR_IOST_CMDREJ`→`EINVAL`/else `EIO` branchless-then-branch pattern; `MTIOCGET`'s `senseDataValid`/`requestSense:` guard and all seven `mgp` field stores against `esense_reply_t` offsets 2/0xC/0x13/0x14/0x15/0x16, and the inlined `er_info` extraction (`lwz`+`srwi 8`) matching the confirmed `__BIG_ENDIAN__` branch; `MTIOCFIXBLK`/`MTIOCVARBLK` shared `setBlockSize:`+`errnoFromReturn:` tail; `MTIOCINILL`/`MTIOCALILL`; the real `MTIOCMODSEL`→`MTIOCMODSEN`→`MTIOCSRQ` fall-through, confirmed present in both; `unit>=NST` bare-return) — all matched **except** the `MT_ISEXB` finding above |
| 10332 | `_st_doiocsrq` | `unexamined` | Full trace against `SCSITapeKern.m:574-732`: `sr_dma_max>maxTransfer`→bare-return `EINVAL`; `getDMAAlignment:`/`alignLength` selection (confirmed the `alignStart`/`IOIsAligned`/`stForcePageAlign` computation is entirely absent from the reference, consistent with the `\|\| YES` making it compile-time dead); `allocateBufferOfLength:`/`copyin`-on-write→`EFAULT`-to-`err_exit`; `scsi_req_t`→`IOSCSIRequest` field copy (offsets 0xC/0x10/0x14/0x18/0x1C/0x20/0x24/0x40/0x44/0x4C, all self-consistently confirmed against `scsireg.h:826-886`'s field layout); `executeRequest:` call; `sr_io_status`/`sr_scsi_status`/`sr_dma_xfr`-with-clamp/`ns_time_to_timeval`; final conditional `copyout`; `err_exit:`'s `didAlign`-gated `IOFree` — matched **except** the three findings above (`sr_discon_disable`, `sr_ignore_chkcond`, `sr_dma_max==0` defaults) |
| 11300 | `_read_er_info_low_24` | `assembly-matched` | 5-instruction leaf: `lwz r3,4(r3)` + `srwi r3,r3,8`, exactly the `__BIG_ENDIAN__` branch's `return ((unsigned int) erp->er_info);` (`SCSITapeKern.m:741-742`) — the function's only caller in source is inside the dead `#elif __LITTLE_ENDIAN__` branch of `stioctl` (`:497-498`), so it is uncalled in this build, but its own compiled body matches the source it would compile to |

Five of the nine reached `assembly-matched`; four (`_st_devsw_init`,
`_st_rw`, `_stioctl`, `_st_doiocsrq`) carry findings above and stay
`unexamined`. Every finding corresponds to exactly one of those four entries,
and every one of those four entries has at least one finding.
