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
