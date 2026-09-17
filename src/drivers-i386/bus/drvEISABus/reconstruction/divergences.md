# drvEISABus divergences

Reference: `EISABus_reloc`, SHA-256 `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 (angr not used as evidence per the task brief; it
over-segments this binary via `CFGFast` just as it did for the other two drivers)

`src/drivers-i386/README` marks drvEISABus "crashing, needs debugging" -- the only one of the
three bus drivers (drvPCIBus, drvPCMCIABus, drvEISABus) with that status. This pass exists to
produce the evidence for why.

## Baseline build

The driver builds clean today. Artifact: `out/i386/drvEISABus/EISABus.config/EISABus_reloc`,
size 577656 bytes (verified present on disk). This is larger than the reference's 100752 bytes
because our build is unstripped; that size difference is expected and is not a finding.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 149 |
| unmapped | 13 |
| duplicate_candidates | 0 |
| boundary_disputed | 2 |

Of the 149 mapped functions, 3 were examined at instruction level with no divergence found
(`assembly-matched`), 4 more were examined at instruction level or a close structural read with
only a cosmetic difference (`control-flow-confirmed`), 6 were examined at instruction level and
found to diverge from the reference (documented as Findings below, left `unexamined` in the
ledger per the convention established by the drvPCIBus/drvPCMCIABus passes), and the remaining
136 were **not opened at all** in this pass -- this driver has by far the largest mapped set of
the three bus drivers examined so far, and the task's priority list (PnPBios.m, eisa.c, the PnP
paths in EISAKernBus, and port I/O) was followed rather than attempting uniform shallow coverage.
Of the 13 unmapped entries, all 13 were disassembled or confirmed absent from source; 2 of them
(`_getCardConfig`, `_getDeviceCfg`) turned out to actually exist in our source under their exact
reference names despite being listed unmapped, which is itself a finding (see below). Both
`boundary_disputed` entries were disassembled and are central to this pass's main finding.

## Central finding: the PnP BIOS real-mode/PM16 calling apparatus

This is the finding the task was built around, and it holds up: the reference binary contains a
complete, working PnP BIOS call apparatus that our tree replaced with an independent, differently
structured reimplementation. The two are not simply different code paths to the same effect --
they differ in ways that plausibly explain crashing behaviour. This section documents what the
reference actually does (disassembled, not decompiled), then compares it to `bios.c`.

### What the reference does

The reference's call chain for one PnP BIOS function (e.g. Function 0x40, "Get Static Allocation
Resource Information", called from `-[PnPBios getPnPConfig:]`) is:

```
-[PnPBios getPnPConfig:]
  -> [self setupSegments]                 ; save GDT[16..19], install BIOS descriptors,
                                           ;   lazily alloc the PnPArgStack
  -> [argStack reset]                     ; zero _PnPEntry_argStackBase/_PnPEntry_numArgs
  -> [argStack push: ...]                 ; push call-specific 16-bit words (ES selector,
  -> [argStack pushFarPtr: ...]           ;   far pointers relative to the data buffer, ...)
  -> [argStack push: 0x40]                ; push the function code LAST (ends up on top
                                           ;   of the replayed stack)
  -> _call_bios(&self->_bb)               ; the C-visible entry point
       -> __bios32PnP(&self->_bb)         ; PUSHAD/PUSHFD, CLI, load EBX/ECX/EDI/ESI/EBP
                                           ;   from the struct, callf [patched selector:offset]
                                           ;   -> __PnPEntry (see below)
                                           ;   <- returns here after the whole PnP call
                                           ; restore EBX/ECX/EDI/ESI/EBP + status into the
                                           ;   struct, POPFD (re-enables interrupts), POPAD
  -> [self releaseSegments]               ; restore GDT[16..19] to their pre-call contents
```

**`__bios32PnP`** (address 0x6F24/28452, 200 bytes) is not in IDA's function list at all --
Ghidra found it (with its correct symbol name, unlike its neighbours) but IDA's analysis has a
200-byte gap here with no function object, despite `__bios32PnP` being a real, non-external,
`__text`-section global symbol per the Mach-O symbol table. **This means `__bios32PnP` is not in
`source-map.json` at all** (the source map is built from IDA's partition), so it does not appear
as a mapped or unmapped entry and is not in `ledger.json`. It is documented here because it is
essential to understanding the call chain; its disassembly is Ghidra-sourced only, with that
caveat. It self-patches an internal `callf 0x0:0x0` (opcode `9A`, at file-relative address 28538)
using a segment (offset 0x20) and address (offset 0x2C) read out of the caller-supplied struct --
the same self-modifying-target trick used again one level down by `__PnPEntry`. It does `cli`
immediately before that `callf` and only implicitly re-enables interrupts via `popfd` after the
call returns, i.e. **the entire real/PM16-mode transition, argument replay, and 16-bit BIOS call
happen with interrupts disabled.**

**`-[PnPBios setupSegments]`** (13668, 587 bytes, mapped to `PnPBios.m:615`) is called before
*every* PnP BIOS call, not once at driver init. Its disassembly shows it:
- Saves the pre-existing GDT[16], GDT[17], GDT[18], GDT[19] descriptors into `self`'s ivars at
  offsets 0x50/0x54 (GDT16), 0x58/0x5c (GDT18), 0x60/0x64 (GDT19), 0x68/0x6c (GDT17) -- this is
  exactly what `-[PnPBios releaseSegments]` (see below) restores afterward.
- Writes `0xC0006FEC` (kernel link base + 0x6FEC) as GDT[19]'s base -- `0x6FEC` = 28652 decimal =
  the exact address of `__PnPEntry`. This is the reference's equivalent of our own
  `PNP_CS32_SEL`/`pnp_bios_callfunc`-aliasing trick: GDT[19] is a 32-bit code descriptor
  (`or [eax+6],0x40` sets D/B=1) that makes `__PnPEntry` appear at offset 0 of selector 0x98, so a
  16-bit far-return back into it stays within a 16-bit-representable offset.
- Sets `ivar+0x3E = 0x90` (a fixed word, GDT[18]'s selector, a 32-bit *data* descriptor aliasing
  the BIOS's own `pm16dseg`); this is the word every one of `getPnPConfig:`/`getNumNodes:AndSize:`/
  `getDeviceNode:ForHandle:` pushes **first**, before any function-specific argument.
- Sets `ivar+0x4C = 0x88` (GDT[17]'s selector, a 32-bit data descriptor over `_kData`, our own
  64KB buffer) -- this is the selector `pushFarPtr:` uses as the base for far pointers into that
  buffer, i.e. our own `_kDataSelector` concept, just stored in a different ivar than the 0x90
  word above.
- Lazily allocates the `PnPArgStack` instance (`if (ivar+4 == 0) { argStack = [[PnPArgStack alloc]
  initWithData:Selector: ivar+0x48 (kData ptr), ivar+0x4C (0x88) ] }`) -- guarded so it is only
  created once across the life of the object, but the GDT save/install/restore around it is not.

**`-[PnPBios releaseSegments]`** (14256, 111 bytes; **unmapped -- no such method exists in our
source at all**) restores GDT[16] from ivar+0x50/0x54, GDT[18] from ivar+0x58/0x5c, GDT[19] from
ivar+0x60/0x64, GDT[17] from ivar+0x68/0x6c -- exactly undoing `setupSegments`'s installs, for
exactly those four slots. It never touches a fifth ("stack") slot, because the reference never
allocates one (see below).

**`__PnPEntry`** (28652, 103 bytes, `boundary_disputed`) is the real-mode/PM16 entry stub that
`__bios32PnP`'s patched `callf` jumps into. Full disassembly:

```
mov ds:save_eax, eax
mov ds:save_ecx, ecx
mov ds:save_edx, edx                 ; save the 3 GP registers __bios32PnP didn't already stage
mov eax, ds:_PnPEntry_biosCodeOffset
mov ds:targ_addr, eax                ; patches the *operand* of the "jmp far" below (self-modifying)
mov ax, ds:_PnPEntry_biosCodeSelector
mov ds:targ_sel, ax                  ; ditto, the selector half
mov ecx, ds:_PnPEntry_argStackBase
mov edx, ds:_PnPEntry_numArgs
jmp check_done                       ; test-at-bottom loop, skip the first push
push_arg:                            ; (own IDA function "push_arg", 6 bytes, address 28708 --
                                      ;  boundary_disputed because it's really an interior label)
  mov ax, [ecx+edx*2]
  push ax
check_done:
  dec edx
  jns push_arg                       ; loop while edx (0-based index) stays >= 0
  mov ax, cs
  push ax                            ; push our own CS (16-bit push, ESP -= 2, even though this
                                      ;   code runs in a 32-bit-attributed segment -- GDT[19]
                                      ;   has D/B=1)
  mov eax, offset bios_rtn
  sub eax, offset __PnPEntry
  push ax                            ; push (bios_rtn - __PnPEntry), i.e. a small CS-relative
                                      ;   16-bit return offset -- this only works because GDT[19]
                                      ;   makes __PnPEntry appear at offset 0
  mov eax, ds:save_eax
  mov ecx, ds:save_ecx
  mov edx, ds:save_edx                ; restore the registers __PnPEntry itself didn't touch
                                      ;   for its own bookkeeping (ebx/edi/esi/ebp pass through
                                      ;   untouched -- __PnPEntry never references them)
; falls through into a 7-byte unlabeled "jmp far ptr [patched]" (opcode EA, at 28755-28761,
; immediately after __PnPEntry's own 103-byte bound and immediately before bios_rtn at 28762) --
; verified against the raw reference binary bytes (EA 00 00 00 00 00 00), and its 4-byte offset
; operand sits at address 0x7054 = 28756 and its 2-byte selector operand at 0x7058 = 28760,
; exactly the addresses "targ_addr"/"targ_sel" were just patched into above. This jmp is not
; claimed by any function in IDA's partition (not a symbol, not part of __PnPEntry's own 103-byte
; bound) -- it is executed as the tail of __PnPEntry's logic but exists as unbound bytes between
; two named functions.
```

`_PnPEntry_biosCodeOffset`/`_PnPEntry_biosCodeSelector` are set once, in `setupSegments`
(`mov ds:_PnPEntry_biosCodeSelector, 0x80` and `mov ds:_PnPEntry_biosCodeOffset, [ivar+0x3C]`,
i.e. the real PM16 BIOS entry point read from the PnP install structure's `pm16offset`/`pm16cseg`
fields at driver init -- these are the actual BIOS ROM target, distinct from the `__PnPEntry`
target that `__bios32PnP`'s own patched `callf` uses).

**`bios_rtn`** (28762, 20 bytes) is where the 16-bit BIOS routine's far return lands:

```
mov ds:save_eax, eax                 ; capture AX (status) from the BIOS
mov eax, ds:_PnPEntry_numArgs
add esp, eax
add esp, eax                        ; esp += 2*numArgs -- pop exactly as many 16-bit words as
                                     ;   were pushed for *this specific call*, tracked dynamically
mov eax, ds:save_eax
retf                                 ; plain retf, no operand -- caller-cleans-stack convention
```

This confirms the reference uses a **caller-cleans-stack convention with a dynamically tracked,
per-call argument count**, not a fixed frame size. `bios_rtn`'s stack cleanup is exactly
`2 * _PnPEntry_numArgs` bytes, where `_PnPEntry_numArgs` was set by however many words that
specific `PnPArgStack` sequence pushed for that specific BIOS function.

### PnPArgStack (Q3: what it does that we don't have)

`PnPArgStack` (a private class our tree has no trace of anywhere -- confirmed via `grep -rl
PnPArgStack` across the whole `drvEISABus` tree, which finds only `source-map.json` itself) is a
small, fixed-capacity (20 words / 40 bytes) LIFO used purely to build the argument words that
`__PnPEntry` replays onto the real stack:

- **`initWithData:Selector:`** (15272, 79 bytes): stores a data-buffer base pointer (arg1) and a
  16-bit "selector" value (arg2) into the instance, then sends itself `reset`.
- **`reset`** (15352, 37 bytes; identical between IDA/Ghidra): zeroes the two globals
  `_PnPEntry_argStackBase`/`_PnPEntry_numArgs` and resets an internal remaining-capacity counter
  to `0x14` (20).
- **`push:`** (15392, 84 bytes): if the counter is 0, logs `"PnPArgStack stack..."` and silently
  drops the push (no crash, just a dropped argument -- overflow is *logged*, not fatal); otherwise
  decrements the counter, writes the 16-bit value into the correct slot of the fixed 20-word
  array, and recomputes `_PnPEntry_argStackBase`/`_PnPEntry_numArgs` so they always describe the
  *current* contents. `__PnPEntry`'s replay loop reads these two globals, which is why every
  `push:`/`pushFarPtr:` call updates them immediately.
- **`pushFarPtr:`** (15476, 108 bytes): computes `offset = pointer - dataBase`; if that offset
  exceeds `0x10000` it logs `"PnPArgStack try..."` and drops the argument (range-checked -- a
  buffer pointer more than 64K past the base cannot be expressed as a 16-bit far-pointer offset
  here); if there is not room for 2 more words it logs a second, distinct overflow message; then
  pushes the stored 16-bit "selector" value via `push:`, then the computed 16-bit offset via
  `push:`. Two `IOLog`-backed guard rails our C code has no equivalent of.

Callers (found via the three `PnPBios` methods that call `_call_bios`, since `PnPArgStack`
methods are dispatched through `objc_msgSend` and have no static call target to grep for) push a
call-specific sequence: `getPnPConfig:` pushes 4 words (ES-like selector, 2-word far pointer,
function code), `getNumNodes:AndSize:` pushes 6, `getDeviceNode:ForHandle:` pushes 7. The word
count is neither fixed nor arbitrary -- it is whatever that specific PnP BIOS function needs, with
the function code always pushed last (ends up on top of the replayed stack).

### What `bios.c` does instead

`call_pnp_bios(func, arg1..arg7)` (`bios.c:56`) always packs exactly 4 dwords -- `eax_in =
func|(arg1<<16)`, `ebx_in = arg2|(arg3<<16)`, `ecx_in = arg4|(arg5<<16)`, `edx_in =
arg6|(arg7<<16)` -- and its inline-asm trampoline `pnp_bios_callfunc` (`PnPBios.m:224`) always
does exactly 4 `pushl`s (8 sixteen-bit words) onto a dedicated 4KB stack reached via a GDT[20]
segment switch, then `lcallw *pnp_bios_callpoint`, then unconditionally `addl $16, %esp`. Every
one of our three call sites (`getDeviceNode:ForHandle:`, `getNumNodes:AndSize:`, `getPnPConfig:`)
passes `0` for the unused trailing `argN` parameters rather than omitting them.

## Finding 1: fixed 8-word vs. call-specific variable-length argument marshalling

**Source:** `bios.c:56` (`call_pnp_bios`), all three call sites in `PnPBios.m`
(`getPnPConfig:` line 589, `getNumNodes:AndSize:` line 556, `getDeviceNode:ForHandle:` line 527).

**Difference:** the reference pushes exactly as many 16-bit words as the specific PnP BIOS
function needs (4, 6, and 7 words for these three functions respectively, per the disassembly
above), always ending with the function code on top of stack, and its own `bios_rtn` cleans up
exactly that many words afterward (`esp += 2*numArgs`, tracked dynamically). Our `call_pnp_bios`
always packs and pushes 8 fixed words regardless of function, and always cleans up exactly 16
bytes. Critically, the reference **always pushes a fixed "ES = 0x90" (BIOS pm16dseg-aliased data
selector) word first**, before any function-specific argument -- our three call sites never push
an equivalent leading word at all; the closest analog (`_kDataSelector`) is instead packed into
`arg2`'s register position, not into the first stack slot.

**Disposition:** fix (needs the real PnP BIOS PM16 spec cross-referenced to confirm the exact
per-function frame, which is follow-up work, not something this analysis pass can complete)

**Rationale:** whether this produces the correct byte layout for the real PM16 BIOS routine to
read depends on how that routine (which lives in the platform's BIOS ROM, outside this
reconstruction's scope entirely -- neither the reference binary nor our source contains it)
addresses its own arguments. If it reads them relative to its own stack frame at fixed offsets
(the conventional interpretation of a callee-cleans-or-caller-cleans, per-function stack ABI, and
the reason `bios_rtn` tracks an exact word count rather than a fixed one), then a fixed 8-word
frame with the ES-selector word missing from the front would shift every subsequent argument by
one 16-bit position relative to what a 4/6/7-word call actually needs, which would deliver the
wrong values to the wrong fields for every single one of these three PnP BIOS functions. This is
plausible, not certain -- I cannot verify against the actual BIOS ROM code, and it is possible
the real PM16 entry convention tolerates the extra/missing padding in a way I have not identified.
Recorded as the strongest concrete, verified calling-convention divergence found in this pass.

**Outcome:** not applied, by design. This finding's own disposition says it needs the real PnP
BIOS PM16 specification cross-referenced to confirm the exact per-function argument frame before
a fix can be written; guessing a frame layout for a real-mode BIOS call neither this reconstruction
nor our source has access to would risk delivering plausible-looking but wrong arguments to
firmware, which is worse than the current, at-least-consistently-wrong 8-word packing. Left for a
follow-up pass once the PM16 spec (or the 11 unmapped `PnPArgStack`/`_call_bios`/`__PnPEntry`/
`bios_rtn` symbols this task also left out of scope) can be cross-referenced. Source and ledger
status (`unexamined`) left unchanged.

## Finding 2: GDT lifecycle -- permanent installation vs. per-call borrow-and-restore

**Source:** `PnPBios.m` `-init` (line 374), `-setupSegments` (line 615), `-free` (line 492).

**Reference behaviour:** `-init` (15104) only reads the PnP BIOS install-structure fields and
`IOMalloc`s the 64KB data buffer -- it does **not** call `setupSegments` and does **not** allocate
a 16-bit stack buffer. `setupSegments` (13668) is called immediately before every individual PnP
BIOS call (from inside `getPnPConfig:`/`getNumNodes:AndSize:`/`getDeviceNode:ForHandle:`, per the
disassembly above) and **saves** the pre-existing contents of GDT[16..19] before overwriting them;
`releaseSegments` is called immediately after every call and **restores** those saved contents.
`-free` (14368) frees the data buffer and the (lazily-allocated) `PnPArgStack`, with no GDT
interaction at all -- consistent with the GDT never being left in the BIOS-specific state outside
the narrow window of an actual call.

**Our source:** `-init` calls `[self setupSegments]` exactly once, which installs GDT[16..20]
(five slots -- 16/17/18/19 matching the reference's four, plus a 20th for a dedicated 16-bit
stack the reference does not use, see Finding 3) **permanently**, with no save of what was there
before. There is no `releaseSegments` anywhere in our source, and `-free` never restores the GDT.
The source's own comment states this explicitly: *"Following Linux's approach, we set up GDT
entries ONCE during initialization. These remain permanently configured - no save/restore
needed."*

**Disposition:** fix

**Rationale:** for the life of the driver (which in a monolithic kernel with a small, shared GDT
is effectively "for the life of the running kernel"), our reimplementation permanently claims 5
GDT slots that the original Rhapsody kernel evidently expected to be borrowed only for the
duration of one BIOS call and otherwise available/restored to their prior contents. If those slot
indices (16-20 / selectors 0x80-0xA0) are used, expected-empty, or reused by any other part of the
kernel or another driver between PnP BIOS calls, permanently squatting on them is a plausible
source of corruption unrelated to the specific BIOS call sequence itself -- a different failure
mode than an argument-marshalling bug, and one that could manifest as instability distant in time
and code from the actual PnP BIOS call site, which is consistent with something described as
simply "crashing" rather than a function returning a wrong value.

**Outcome:** fixed. `-init` no longer calls `[self setupSegments]`; `setupSegments` now saves the
pre-existing GDT[16], GDT[18], GDT[19], GDT[17] entries into the `_saveGDTBiosCode`/
`_saveGDTBiosEntry`/`_saveGDTKData`/`_saveGDTBiosData` ivars (already declared in `PnPBios.h` in
exactly this 16/18/19/17 order -- matching the reference's own save order at ivar offsets
0x50/0x58/0x60/0x68 -- but never wired up before this fix) immediately before overwriting them, and
each of `getPnPConfig:`/`getNumNodes:AndSize:`/`getDeviceNode:ForHandle:` now calls
`[self setupSegments]` as its first statement and `[self releaseSegments]` immediately after
`call_pnp_bios` returns. A new `-releaseSegments` method restores GDT[16], GDT[18], GDT[19], GDT[17]
from those same ivars. `-free` was left unchanged (it already did not touch the GDT, matching the
reference). GDT 20 (our own dedicated 16-bit stack segment for `pnp_bios_callfunc`, which the
reference's differently-structured thunk has no counterpart for at all) is still configured by
`setupSegments` on every call and is not saved/restored, since there is nothing in the reference to
match its lifecycle against; `-init` still allocates the `_kStack` buffer that segment points at.
Ledger status advanced from `unexamined` to `control-flow-confirmed` for `setupSegments`,
`releaseSegments`, and `init`.

## Finding 3: no interrupt disabling around the real/PM16-mode transition

**Source:** `bios.c:56` (`call_pnp_bios`); `PnPBios.m` imports
`<kernserv/i386/spl.h>` "for interrupt control (splhigh/splx)" (line 38) but **never actually
calls `splhigh`/`splx` anywhere in the file** -- confirmed by grep across `PnPBios.m` and
`bios.c`, which finds only the import and its comment, no call sites.

**Reference behaviour:** `__bios32PnP` executes `cli` immediately before the `callf` that enters
`__PnPEntry`, and only implicitly re-enables interrupts via `popfd` (restoring the flags captured
by its own earlier `pushfd`) after the whole call -- meaning **the entire mode-switching sequence
(argument replay, far jump into the PM16 BIOS routine, far return, stack cleanup) runs with
interrupts disabled** in the reference.

**Our source:** `call_pnp_bios`'s inline asm saves/restores `ds`/`es`/`fs`/`gs`/`eflags` around
the `lcall`, but never executes `cli`/`sti` (nor `splhigh`/`splx`, despite the header import
suggesting that was the original intent). Interrupts remain enabled, at whatever level they were,
for the entire PM16 mode-switch-and-call sequence.

**Disposition:** fix

**Rationale:** this is a well-understood class of bug independent of the argument-marshalling
question above. If a hardware interrupt fires while the CPU is mid-transition through the 16-bit
code/32-bit-vs-16-bit-stack segment juggling this call performs, the interrupt handler runs with
whatever segment state happens to be active at that instant -- not a state any interrupt handler
is written to expect. Whether this actually fires in practice depends on timing (how long the
BIOS call takes, and what's enabled on the interrupt controller at the time), so I can state this
is a real, confirmed, structural gap relative to the reference's explicit `cli`/`popfd` bracket,
and that it is a plausible crash mechanism -- I cannot say it *does* cause the observed crash
without a live repro, which is out of scope for this analysis pass.

**Outcome:** fixed. `call_pnp_bios` now brackets its inline-asm `lcall` with
`splhigh()`/`splx()` (added `#include <kernserv/i386/spl.h>` to `bios.c`; the
declarations were already visible to `PnPBios.m` in this same driver, just unused),
matching the codebase's own idiom for this exact purpose elsewhere in
`drivers-i386` (e.g. `IdeCnt.m`, `ISASerialPort.m`, `PS2Controller.m`) rather than
inlining `cli`/`pushfd`/`popfd` into the existing hand-tuned asm block, so the
inline-asm constraints touched by commit `778e0df4` are untouched. `splhigh()`
raises to IPL 7 (the highest level), which is at least as strong as the reference's
bare `cli`. No ledger entry corresponds to this fix: `call_pnp_bios`'s reference
counterpart is `__bios32PnP`, which -- per the central finding above -- has no IDA
function object and so was never added to `source-map.json`/`ledger.json` at all;
there is nothing in the ledger to advance.

## Finding 4: `_getCardConfig`'s minimum-length check skips the Wait-for-Key cleanup

**Source:** `EISAKernBus+PlugAndPlayPrivate.m:984` (`getCardConfig`) -- **note:** this function is
listed `unmapped` in `source-map.json` despite existing in our source under its exact reference
name; see the note below. Only the first ~100 of 999 reference instructions were read (the
initiation-key send, the CSN wake, and the length check); the remainder of the function (the
actual per-byte resource-data read loop and its own Wait-for-Key exit, ~140-999) was not
disassembled in this pass.

**Reference behaviour:** after sending the initiation key and waking the card with its CSN
(register 0x03), the reference checks `*length > 8`; if not (`*length <= 8`), it returns `NO`
immediately via `xor eax,eax; jmp <end>` -- **skipping** the "send Wait for Key" cleanup sequence
(`out 0x279,2; out 0xa79,2`) that the normal exit paths execute.

**Our source:** has no minimum-length check at all -- `getCardConfig` will attempt the resource
read loop for any `*length`, including very small values, and always sends the Wait-for-Key
cleanup before returning.

**Disposition:** accept

**Rationale:** the only production caller of `readPnPConfig:length:forCard:` (which calls this
function) allocates a 0x800-byte buffer, far above the 8-byte threshold, so this path is not
reachable through any call site examined in this pass; if it were exercised with a small buffer,
the direction of the difference is that our reimplementation is *more* likely to leave the PnP
bus correctly reset (we always send Wait-for-Key) than the reference is (which skips it on this
one early-exit path) -- the opposite of a new bug, though still a confirmed behavioural
difference from the reference worth recording.

## Finding 5: `EISAKernBusInterrupt` has no IRQ registration, trigger-mode setup, or dispatch trampoline at all

**Source:** `EISAKernBusInterrupt.h`/`EISAKernBusInterrupt.m` (whole file read; contains
`dealloc`, `attachDeviceInterrupt:`, `attachDeviceInterrupt:atLevel:`, `detachDeviceInterrupt:`,
`suspend`, `resume` -- **no `initForResource:item:shareable:` override is declared or defined
anywhere**, confirmed by reading both the header's method list and the whole implementation file).

**Reference behaviour:** `-[EISAKernBusInterrupt initForResource:item:shareable:]` (address 0,
197 bytes) calls `[super init...]`, stores the IRQ number, and -- unless the IRQ is 2 (the legacy
8259 cascade line, which it skips registering entirely) -- calls
`intr_register_irq(irq, __EISAKernBusInterruptDispatch, self, /*priority*/3)`, then
`intr_change_mode(irq, shareable)` (setting edge- vs. level-triggered mode based on the caller's
`shareable` argument -- EISA, unlike plain ISA, supports level-triggered shared interrupts), then
allocates a `KernLock` at priority level 7. `__EISAKernBusInterruptDispatch` (920, 62 bytes) is
the actual interrupt trampoline the kernel's IRQ dispatch calls: it calls the generic
`KernBusInterruptDispatch(self, userData)`, and if that returns false (no attached device claimed
the interrupt), it acquires the lock, calls `intr_disable_irq`, clears an "enabled" flag, and
releases the lock -- **auto-disabling an IRQ line that fires without being claimed**, which
guards against an interrupt storm from a misbehaving or unshared device.

**Our source:** has neither piece. `EISAKernBusInterrupt` relies entirely on whatever its generic
`KernBusInterrupt` superclass does for `-init`/interrupt registration, with no EISA-specific
override for trigger-mode configuration or for a self-disabling dispatch trampoline.

**Disposition:** fix

**Rationale:** this is unrelated to the PnP BIOS thunk story and, on its own reasoning, arguably a
*more* likely explanation of "crashing" for a real bus driver: PnP BIOS calls happen a handful of
times during enumeration, but a misconfigured interrupt line is live for the entire time any
attached EISA device can raise it. If the inherited generic registration path (whatever it is)
does not configure level-triggered mode for a device that actually drives its IRQ line
level-triggered and shared -- exactly the case EISA (unlike ISA) is designed to support -- and
there is no auto-disable safety valve on an unclaimed interrupt, a single misbehaving or
unacknowledged device could produce a continuous interrupt storm, which is a classic way for a
system to appear hung/crashed. I have not traced what the generic `KernBusInterrupt` superclass
actually does at `-init` time (out of scope for this pass), so I cannot say registration is
*absent* versus merely *generic* -- only that the EISA-specific trigger-mode and self-disabling
dispatch behaviour the reference clearly has is entirely missing from our override set.

**Superclass tracing (prerequisite for the fix):** `src/kernel-7/driverkit/KernBusInterrupt.m`'s
`-initForResource:item:withHandler:shareable:` (and the 3-arg `-initForResource:item:shareable:`
that forwards to it with `handler:nil`) calls `[super initForResource:resource item:item
shareable:shareable]` (superclass `KernBusItem`, which just records `_resource`/`_item`/
`_shareable`), then allocates a generic attached-interrupt list (`_attachedInterrupts`) and two
`KernLock`s (`_interruptLock`, `_suspendLock`) used purely for the shared attach/detach/suspend/
resume bookkeeping every `KernBusInterrupt` subclass gets for free. **It does not call
`intr_register_irq`, `intr_change_mode`, or touch any hardware IRQ vector at all** -- it has no
concept of an IRQ number distinct from the generic `item` value, and no dispatch trampoline of its
own; `KernBusInterruptDispatch()` (the generic C function it exposes) only walks the attached
device list and reports whether any of them claimed the interrupt, it does not get called by
anything unless something registers it with the interrupt controller first. This confirms
registration is genuinely **absent**, not merely generic: nothing in the class hierarchy above
`EISAKernBusInterrupt` ever calls `intr_register_irq` for any bus. This changed what was
implemented: instead of guessing whether to duplicate superclass behaviour, the fix below adds
only the EISA-specific pieces (IRQ storage, `intr_register_irq`/`intr_change_mode`, the dispatch
trampoline, and the lock) and continues to call `[super initForResource:item:shareable:]` first so
the generic list/lock bookkeeping still runs exactly as it does for every other `KernBusInterrupt`
subclass.

**Outcome:** fixed. `EISAKernBusInterrupt` now has an `-initForResource:item:shareable:` override
(`EISAKernBusInterrupt.m:81`) that calls `[super initForResource:item:shareable:]`, stores `_irq`
from `item`, and -- skipping both calls for IRQ 2, the 8259 cascade -- calls `intr_register_irq`
with a new static trampoline `_EISAKernBusInterruptDispatch` at priority 3, then
`intr_change_mode(_irq, shareable)`, then allocates `_EISALock` via `[[KernLock alloc]
initWithLevel:7]`. The trampoline (`EISAKernBusInterrupt.m:56`) calls the generic
`KernBusInterruptDispatch()` and, if unclaimed, acquires `_EISALock`, calls `intr_disable_irq`, and
clears `_irqEnabled` -- the same auto-disable-on-unclaimed-interrupt behaviour the reference has.
The existing (previously dead) `-dealloc`, which already called `intr_unregister_irq(_irq)` and
`[_EISALock free]` on ivars nothing ever initialized, is now operating on real values and needed no
changes itself. `intr_register_irq`, `intr_change_mode`, `intr_disable_irq`, and `KernLock`
(`-initWithLevel:`) were all confirmed present in `src/kernel-7/machdep/i386/intr_exported.h` and
`src/kernel-7/driverkit/KernLock.h` with the signatures used. `_irqAttached` (declared in the
header) remains unused, matching the reference, which the 197-byte `initForResource:item:shareable:`
disassembly summary does not mention touching either. Ledger status advanced from `unexamined` to
`control-flow-confirmed` for both `-[EISAKernBusInterrupt initForResource:item:shareable:]` and
`__EISAKernBusInterruptDispatch`.

## Finding 6: missing diagnostic-access counter in the raw PnP register accessors (cosmetic)

**Source:** `EISAKernBus+PlugAndPlay.m:70` (`readPnPRegister:`), `:88`
(`writePnPRegister:value:`).

**Reference behaviour:** after every `out` to ports 0x279/0xa79, the reference does
`inc ds:_xxx_86_0` -- a global counter with no resolved symbol name (IDA could not name it),
consistent with an internal diagnostics/statistics counter rather than anything with observable
functional effect.

**Our source:** issues the identical `outb`/`inb` sequences on the identical ports
(`0x279`/`pnpReadPort` for read, `0x279`/`0xa79` for write) with no counter.

**Disposition:** accept

**Rationale:** a missing internal statistics counter has no effect on device behaviour. Noted
because both functions were verified instruction-by-instruction and this is the only difference
found in either.

## Note: `_getCardConfig`/`_getDeviceCfg` are unmapped in name only

Unlike the other 11 unmapped entries (which are genuinely absent -- confirmed via `grep`), these
two **do** exist in our source under their exact reference names:
`BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length)`
(`EISAKernBus+PlugAndPlayPrivate.m:984`) and
`BOOL getDeviceCfg(unsigned char csn, int logicalDevice, void *buffer, unsigned int *size)`
(`:1062`), each also forward-declared identically in both `EISAKernBus+PlugAndPlay.m` and
`EISAKernBus+PlugAndPlayPrivate.m`. Why the source-map's automatic matcher left them unmapped
was not investigated (out of scope for this pass -- the source map is generated tooling this task
says not to regenerate); the double forward-declaration across two files is a plausible cause but
unconfirmed. This is functionally different from the PnP BIOS thunk cluster and the
`EISAKernBusInterrupt` gap above, which are genuinely missing code -- these two are present, and
`getCardConfig` was found to have a real (if low-impact) divergence on partial examination, see
Finding 4. `getDeviceCfg`'s 700-byte reference body was not disassembled in this pass at all.

## Unmapped: build-generated

`+[EISABusKernelServerInstance kernelServerInstance]` and
`+[EISABusVersion driverKitVersionForEISABus]` -- emitted by the Kernel Server project type, not
written by hand. Accepted, same as the equivalent pair in drvPCIBus and drvPCMCIABus.

## Unmapped/boundary_disputed: genuinely absent from our source

Confirmed via `grep -rl PnPArgStack src/drivers-i386/bus/drvEISABus/` (only match:
`source-map.json` itself) and via reading `PnPBios.h`/`PnPBios.m` and
`EISAKernBusInterrupt.h`/`.m` in full:

- The whole `PnPArgStack` class (`initWithData:Selector:`, `reset`, `push:`, `pushFarPtr:`) --
  see the central finding above.
- `-[PnPBios releaseSegments]` -- see Finding 2.
- The thunk itself: `_call_bios`, `bios_rtn`, `__PnPEntry`+`push_arg` (`boundary_disputed`, an
  interior-label pair, not two independent functions -- `push_arg` at 28708 is 6 bytes inside
  `__PnPEntry`'s own 103-byte span reached by a backward branch, not a separate call target) --
  see the central finding above. `__bios32PnP`, one level further out, is not in the source map
  at all because IDA's own partition has no function object there (see the central finding's
  first paragraph) -- flagged here since it is easy to assume from the unmapped-list count alone
  that these 4 named entries are the complete missing-thunk story, when there is a 5th piece
  (`__bios32PnP`) invisible to the tooling entirely.
- `-[EISAKernBusInterrupt initForResource:item:shareable:]`, `__EISAKernBusInterruptDispatch` --
  see Finding 5.

## Analyzer disagreement

**Ghidra has no function objects across the entire PnP-thunk region.** Its function list has
nothing between `__bios32PnP` (which it *does* find, with its correct symbol name -- the reverse
gap from IDA) ending at 28652 and its next entry at 28796 (`+[EISABusVersion
driverKitVersionForEISABus]`) -- a 144-byte gap covering `__PnPEntry`, the unbound self-modifying
`jmp far` tail, `bios_rtn`, and `+[EISABusKernelServerInstance kernelServerInstance]` entirely.
This is consistent with Ghidra's CFG-based function discovery being unable to follow a
self-modifying, runtime-patched indirect far jump -- exactly the mechanism `__PnPEntry` uses to
reach the real BIOS entry point. Per the brief, IDA is authoritative for the source-map partition,
so this does not change the source map; it is independent evidence that this specific code
structure (a runtime-patched far transfer) is unusual enough to defeat at least one of the two
disassemblers outright, which is itself a small piece of evidence that this mechanism is fragile.

**IDA has no function object for `__bios32PnP`** (28452, 200 bytes) despite it being a real,
non-external `__text` symbol in the Mach-O symbol table; Ghidra found it with a normal function
boundary and the correct name. This is the reverse of the above gap and is the reason
`__bios32PnP` does not appear in `source-map.json`/`ledger.json` at all (see above).

Elsewhere in the binary, IDA and Ghidra agree closely: of the 149 mapped + 13 unmapped + 2
boundary_disputed entries, 62 have byte-identical instructions, blocks, and call targets between
the two tools; 98 more have byte-identical instructions and blocks with only immaterial
differences in how each tool records external call targets (Ghidra does not resolve a `target`
address for external calls the way IDA does -- confirmed by direct comparison, e.g. both agree
`_EISAParseID` calls `_strtoul`/`_strtol` at the same addresses, Ghidra just leaves `target: null`
where IDA fills in the PLT-style stub address); the 4 gap cases above are the only real
disagreements found in either direction.

## Crash candidates

Ranked by how plausibly each explains the "crashing" status in `src/drivers-i386/README`, most
first. All three PnP-BIOS-related candidates require the PnP BIOS to actually be present and
successfully detected (`+[PnPBios Present:]` returns YES) before any of this code runs at all;
`EISAKernBusInterrupt` (candidate 2) requires only that some EISA device be attached and generate
an interrupt, which is a broader trigger condition.

1. **Finding 1 -- fixed 8-word vs. call-specific argument marshalling, with a missing leading
   ES-selector word.** Confidence: plausible, not confirmed. If the real PM16 BIOS routine reads
   its arguments at fixed positions relative to its own stack frame (the natural reading of why
   the reference tracks an exact per-call word count in `bios_rtn`), every one of our three PnP
   BIOS calls delivers arguments at the wrong stack offsets to the BIOS ROM code, which is
   consistent with a call to genuinely unpredictable/garbage-interpreting firmware -- a strong
   candidate for outright memory corruption or an immediate fault inside the BIOS call. I cannot
   verify this against the actual BIOS ROM (outside this reconstruction's scope), so I hold this
   at "plausible", not "confirmed".
2. **Finding 5 -- `EISAKernBusInterrupt` has no EISA-specific IRQ registration, trigger-mode
   setup, or self-disabling dispatch trampoline.** Confidence: plausible, arguably broader in
   applicability than candidate 1, because it doesn't require PnP BIOS to be present or
   successfully probed at all -- it applies to any EISA device with an interrupt. If shared/
   level-triggered EISA interrupts are misconfigured as edge-triggered by the generic
   superclass's default, or an unclaimed interrupt is never auto-disabled, an attached device
   could produce a sustained interrupt storm that looks exactly like "crashing" from the outside.
   I did not trace the generic `KernBusInterrupt` superclass's own `-init` behaviour, so I cannot
   rule out that it does something adequate generically -- held at "plausible".
3. **Finding 3 -- no `cli`/interrupt-disable around the real/PM16-mode transition.** Confidence:
   plausible, lower than 1 and 2 because it is timing-dependent (requires an interrupt to
   actually fire during the narrow window of the mode-switching sequence) rather than
   deterministic like the argument-layout question.
4. **Finding 2 -- GDT slots 16-20 permanently installed rather than borrowed per call.**
   Confidence: plausible but the least direct of the four -- this is more a "long-run corruption
   of unrelated kernel/driver state" story than an immediate crash inside this driver's own call
   path, and would require something else in the kernel to actually depend on those GDT slots
   being available, which this pass did not verify.

The PnP BIOS calling-convention question (this task's central hypothesis, candidates 1 and 3
above) is real and well-evidenced by disassembly, but this pass's own findings suggest the
`EISAKernBusInterrupt` gap (candidate 2, discovered while covering the task's Q4 priorities) is at
least as plausible a "crashing" explanation, and is simpler to fix. Neither is confirmed as *the*
cause; both are confirmed, concrete divergences from the reference.

## Functions examined with no divergence found

Instruction-level match (`assembly-matched` in the ledger): `_EISAParseID`, `-[EISAKernBus
readPnPConfig:length:forCard:]`, `-[EISAKernBus readPnPDeviceCfg:length:forCard:andLogicalDevice:]`.

Instruction-level or close structural match with only a cosmetic difference
(`control-flow-confirmed` in the ledger): `-[EISAKernBus readPnPRegister:]`, `-[EISAKernBus
writePnPRegister:value:]` (both: missing diagnostic counter, Finding 6), `_EISAParsePrefix`,
`_EISAMatchIDs` (both: structure matches source, not re-verified operand by operand).

## Not examined

The remaining 136 mapped functions were not opened in this pass at all: all of `PnPResources.m`
(15), `PnPLogicalDevice.m` (13), `PnPDeviceResources.m` (16), `pnpIOPort.m` (10), `pnpIRQ.m` (8),
`pnpDMA.m` (7), `pnpMemory.m` (15), `PnPResource.m` (6), `PnPDependentResources.m` (2),
`EISAKernBusDMAChannel.m` (2), `EISAResourceDriver.m` (5), the four
`EISAKernBusInterrupt.m`/`.h` methods other than the two disassembled for Finding 5
(`attachDeviceInterrupt:`, `attachDeviceInterrupt:atLevel:`, `detachDeviceInterrupt:`, `suspend`,
`resume`, `dealloc`), `_isolateCard`/`_setBit`/`_computeChecksum`/`_clearPnPConfigRegisters`/
`_readIsolationBit` in `bios.c` (this is the separate ISA PnP card-isolation/serial-ID protocol,
unrelated to the PM16 calling convention -- our own `bios.c` has a matching family of functions
implementing the same algorithm, not examined against the reference in this pass), the large
PnP resource-allocation methods in `EISAKernBus+PlugAndPlayPrivate.m`
(`allocateResources:Using:DependentFunction:Description:`, 1203 bytes;
`pnpSetResourcesForDescription:`, 1596 bytes; `initializePnP`, 791 bytes; `initializeNoBIOS`, 754
bytes; `deactivateLogicalDevices:`, 313 bytes; `findCardWithID:Serial:LogicalDevice:`, 149 bytes),
`-[EISAKernBus getEISASlotNumber:slotID:usingDeviceDescription:]` (609 bytes),
`-[EISAKernBus init]` (525 bytes), `-[EISAResourceDriver getCharValues:forParameter:count:]`
(1251 bytes), `_getEISASlotInfo`/`_getEISAFunctionInfo`/`_testSlotForID` in `eisa.c` (source read
in full, reference disassembly not opened), `-[EISAKernBus getPnPId:forCsn:]`/`-[EISAKernBus
testIDs:csn:]`/`-[EISAKernBus lookForPnPIDs:Instance:LogicalDevice:]`, and the remainder of
`EISAKernBus.m`/`EISAKernBus+PlugAndPlay.m`/`EISAKernBus+PlugAndPlayPrivate.m` not named above.
These are the natural next targets for a follow-up pass, in roughly this priority order: the
PnP resource-allocation methods (most likely to interact with the calling-convention findings
above, since they consume the results of the BIOS calls), then `getEISASlotNumber:...` and the
rest of `EISAKernBus.m`, then the `pnp*.m`/`PnP*Resources.m` family.

## Finish campaign

Date: 2026-09-17. Branch: `pnpdump-binrecon-finish`.

Task 5 IDA `--list` against the Task 4 rebuilt reloc (`4430CA7B…`): **45** of the 93 shared
nine-class names were already `raw_equal` or `masked_equal`; those reloc ledger rows are now
`assembly-matched` (reviewer Pat Raynor). Kernel-only reloc statuses were not changed. The tool
side recorded **43** baseline-identical rows in `reconstruction/pnpdump/ledger.json` (see
`reconstruction/pnpdump/divergences.md`).

### Task 6 omit `return self` on add-to-list (2026-09-17)

Rebuilt reloc SHA `BBD159B9E775073D3F1571C95746D4B2F13D48D9F171C161DB5D7FB1FCF88B7D` (603928). Kernel-only reloc statuses were not reopened. `-[pnpDMA addDMAToList:]` and `-[pnpIRQ addToIRQList:]` are IDA `raw_equal` / `masked_equal`.

```
-[pnpDMA addDMAToList:]
  status=different raw_equal=True masked_equal=True
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp dword ptr [edx+24h], 7              cmp dword ptr [edx+24h], 7
* jg loc_4219                             jg loc_44C5
  mov eax, [edx+24h]                      mov eax, [edx+24h]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [edx+eax*4+4], ecx                  mov [edx+eax*4+4], ecx
  inc dword ptr [edx+24h]                 inc dword ptr [edx+24h]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

```
-[pnpIRQ addToIRQList:]
  status=different raw_equal=True masked_equal=True
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  cmp dword ptr [edx+44h], 0Fh            cmp dword ptr [edx+44h], 0Fh
* jg loc_3EE5                             jg loc_4AE5
  mov eax, [edx+44h]                      mov eax, [edx+44h]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov [edx+eax*4+4], ecx                  mov [edx+eax*4+4], ecx
  inc dword ptr [edx+44h]                 inc dword ptr [edx+44h]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```
