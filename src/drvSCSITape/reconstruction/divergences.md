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
| 2248 | `-[SCSITape setIgnoreCheckCondition:]` | `unexamined` | Finding: writes to `0x225(r3)`, not the `0x126` the accessor block's own offset progression predicts |
| 2264 | `-[SCSITape majorDevNum]` | `assembly-matched` | 4-instruction leaf; `lwz r3, 0x110(r3)` |
| 2280 | `-[SCSITape acquireDevice]` | `unexamined` | Finding: calls `[_controller reserveTarget:lun:forOwner:]` and `[self reserveAllLuns]`, neither of which our source calls |
| 2464 | `-[SCSITape releaseDevice]` | `unexamined` | Finding: calls `[self releaseAllLuns]` and `[_controller releaseTarget:lun:forOwner:]`, neither of which our source calls |

**The recovered ivar table.** Thirteen of the fourteen 16-24 byte accessors at
2028-2264 are single-load or single-store leaves reading or writing one fixed
offset each, and every one of those thirteen offsets is consistent with a
single, non-overlapping layout that matches `SCSITape.h:20-47`'s `@interface`
field order exactly, including the two bytes of padding GCC inserts after the
two adjacent `u_char` fields to re-align the following `int` on a 4-byte
boundary:

| Offset | Size | Ivar | Confirmed by |
| --- | --- | --- | --- |
| `0x108` (264) | 4 | `_controller` | `-controller` (2060); `-acquireDevice`/`-releaseDevice` read the same offset for the `reserveTarget:`/`releaseTarget:` receiver |
| `0x10C` (268) | 1 | `_target` | `-target` (2028); also read by `-acquireDevice`/`-releaseDevice` |
| `0x10D` (269) | 1 | `_lun` | `-lun` (2044); also read by `-acquireDevice`/`-releaseDevice` |
| `0x10E`-`0x10F` | 2 | *(padding)* | — |
| `0x110` (272) | 4 | `_majorDevNum` | `-majorDevNum` (2264) |
| `0x114` (276) | 4 | `_blockSize` | `-blockSize` (2196); same offset tested by `-isFixedBlock` (2116) |
| `0x118` (280) | 4 | `_senseDataPtr` | `-senseDataPtr` (2180); same offset freed by `-free` (1544) |
| `0x11C` (284) | 4 | `_devLock` | `-free`'s conditional `[_devLock free]`; `-acquireDevice`/`-releaseDevice`'s `[_devLock lock]`/`[_devLock unlock]` |
| `0x120` (288) | 1 | `_isInitialized` | `-isInitialized` (2076) |
| `0x121` (289) | 1 | `_devAcquired` | not directly accessor-mapped, but read/written identically by `-free`, `-acquireDevice` and `-releaseDevice` (see findings below) |
| `0x122` (290) | 1 | `_didWrite` | `-didWrite` (2096) |
| `0x123` (291) | 1 | `_suppressIllegalLength` | `-suppressIllegalLength` (2212) / `-setSuppressIllegalLength:` (2232) |
| `0x124` (292) | 1 | `_senseDataValid` | `-senseDataValid` (2140) / `-forceSenseDataInvalid` (2160) |
| `0x125` (293) | 1 | `_reservedTargetLun` | inferred by elimination (next single byte in `@interface` order); no examined function reads or writes it directly |
| `0x126` (294) *(expected)* | 1 | `_ignoreCheckCondition` | **not observed** — see the `setIgnoreCheckCondition:` finding below |

Our `@interface`'s ivar order (`SCSITape.h:26-46`) agrees with the reference for
every offset actually observed, `_controller` through `_reservedTargetLun`.
The one ivar this block cannot confirm by direct observation is
`_ignoreCheckCondition` itself, because its only accessor in the 20-function
set, `setIgnoreCheckCondition:`, writes to an offset wildly outside this
range — see the finding immediately below, which is this block's headline
result per the brief's Step 1 instructions.

## Finding: `-[SCSITape setIgnoreCheckCondition:]` writes 255 bytes past where the accessor block's own layout puts `_ignoreCheckCondition`

**Source:** `SCSITape.h:46` (`_ignoreCheckCondition` field declaration),
`SCSITape.m:435-439` (`setIgnoreCheckCondition:`).

**Reference behaviour:** the function (address 2248, 16 bytes) is a 4-instruction
leaf identical in shape to every other one-line setter in this block —
`stwu`/`stb r5, 0x225(r3)`/`addi r1`/`blr` — except the displacement is
`0x225` (549 decimal), not `0x126` (294) that the surrounding offset table
predicts (`0x124` = `_senseDataValid`, and `0x125` would be `_reservedTargetLun`
by elimination, leaving `0x126` for the next declared field,
`_ignoreCheckCondition`). `0x225 - 0x126 = 0xFF` (255 bytes). This displacement
is a bare 16-bit immediate baked into the `stb` opcode, not a relocated symbol
reference, so there is no relocation-table alternative reading to check — the
compiler genuinely emitted offset 549 for this store.

The other thirteen accessors in this same address range (2028-2264) are
internally consistent with each other and with `SCSITape.h`'s declared order
with no gaps large enough to hide 255 bytes — the entire observed span from
`_controller` (264) to `_reservedTargetLun` (293, by elimination) is only 30
bytes. Nothing else in the 20-function set touches any offset between 294 and
549 either, so this task cannot determine what the reference class actually
keeps in that stretch — only that whatever it is, it pushes
`_ignoreCheckCondition` far outside the block our own `@interface` places it
in.

**Our source:** `SCSITape.m:435-439` stores directly into `_ignoreCheckCondition`,
which the compiler would place at `0x126` given `SCSITape.h`'s declared field
order — 255 bytes before where the reference's compiled setter actually writes.

**Consequence:** this is exactly the class of bug the brief warns about — each
accessor reads as individually correct, but `setIgnoreCheckCondition:` and (if
our reimplementation ever adds one) a `-ignoreCheckCondition` getter would
silently read and write the wrong storage relative to the reference's memory
layout on a real PowerPC rebuild. Left `unexamined`; this task could not
establish *why* the offset is 255 bytes further out (whether the real Apple
`@interface` declares additional, larger fields between
`_reservedTargetLun`/`_ignoreCheckCondition` and the rest of the block, was
compiled against a different superclass size, or something else) — flagging
this for whoever fixes Phase 2 rather than guessing. Note also that
`-[SCSITape ignoreCheckCondition]` (the getter), `-[SCSITape
setReservedTargetLun:]` and `-[SCSITape reservedTargetLun]` — all three
declared in `SCSITape.h:74-77` — have no compiled counterpart anywhere in
`SCSITape_reloc`'s 50 named functions at all (Task 7's absent-methods pass
should account for this alongside the offset anomaly, since a getter for
`_ignoreCheckCondition` would be the most direct way to cross-check the real
offset).

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

The inner (lun) loop's bound test (addresses 364-372: `addi r0,r30,1` /
`andi. r30,r0,0xFF` / `beq- cr0,loc_DC`) is a mask-and-test-zero idiom, not a
`cmpwi` against a small immediate — this task could not fully establish
whether it reflects a compile-time `SCSI_NLUNS` of 1 (tape units are
conventionally LUN-0-only, which would make this codegen's apparent
one-iteration-per-target behavior plausible) or some other transform; flagged
as uncertain rather than asserted.

**Our source:** `SCSITape.m:85-86` loops `stTarget` and `stLun` over the
compile-time constants `SCSI_NTARGETS` (8, `src/kernel-7/bsd/dev/scsireg.h:732`)
and `SCSI_NLUNS` (8, ibid. line 733) — no controller query, no clamp, no
warning log. `SCSITape.m:102-112` calls
`[controllerId reserveTarget:stTarget lun:stLun forOwner:tapeId]` before
`initSCSITape:...`, and `SCSITape.m:142-145` calls `releaseTarget:lun:forOwner:`
plus `setReservedTargetLun:NO` in the failure case — none of which the
reference's `probe:` does at all.

**Consequence:** two independent, non-cosmetic divergences. (1) Our fixed
8-target loop bound could scan fewer targets than a controller advertising
more than 8 (though `SCSI_NTARGETS`/`SCSI_NLUNS` are also the values
`IOSCSIController` itself is built against elsewhere in this tree, so the
practical impact needs checking against that class, not asserted here).
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
`paReleasedevice` resolves via `read_macho` to `sel_releaseDevice`); `if
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
