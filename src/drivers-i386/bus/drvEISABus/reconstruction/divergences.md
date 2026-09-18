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

### Task 6 `setHigh:Level:` if-shape (2026-09-17)

Kernel-only reloc statuses were not reopened. Reloc SHA `1F1DBE7981F9EB97E47E261B99CCB57FDC56EECF3F8F6EEC97183C254918A730`. Same leftover as the tool: register allocation after matching Apple `jz` polarity and flag offsets. Accepted compiler-shaped leftover (reviewer Pat Raynor).

```
-[pnpIRQ setHigh:Level:]
  status=different raw_equal=False masked_equal=False
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* mov edx, [ebp+self]                     mov eax, [ebp+self]
* mov al, [ebp+arg_C]                     mov dl, [ebp+arg_C]
  cmp [ebp+arg_8], 0                      cmp [ebp+arg_8], 0
* jz loc_3F10                             jz loc_4AB8
* test al, al                             test dl, dl
* jz loc_3F08                             jz loc_4AB0
* mov byte ptr [edx+4Ah], 1               mov byte ptr [eax+4Ah], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
* mov byte ptr [edx+48h], 1               mov byte ptr [eax+48h], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
* test al, al                             test dl, dl
* jz loc_3F1C                             jz loc_4AC4
* mov byte ptr [edx+4Bh], 1               mov byte ptr [eax+4Bh], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
* mov byte ptr [edx+49h], 1               mov byte ptr [eax+49h], 1
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `setDeviceName:Length:` min and zero-length test (2026-09-17)

Kernel-only reloc statuses were not reopened. Reloc SHA `2AD36AEF5E4934EBD7C9F8447D5204EADFBB4449524BD9B5E14B3EFD9F19A874` (603952). Both `-[PnPLogicalDevice setDeviceName:Length:]` and `-[PnPDeviceResources setDeviceName:Length:]` are IDA `masked_equal`. Leftover on the tool side is IDA `__src` vs `arg_8`.

```
-[PnPLogicalDevice setDeviceName:Length:]
  status=different raw_equal=False masked_equal=True
  reason: calls differ
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  cmp dword ptr [ebx+54h], 0              cmp dword ptr [ebx+54h], 0
* jnz loc_5ED4                            jnz loc_4DC4
  mov eax, 4Fh                            mov eax, 4Fh
  cmp eax, edx                            cmp eax, edx
* jle loc_5EB3                            jle loc_4DA3
  mov eax, edx                            mov eax, edx
  mov [ebx+54h], eax                      mov [ebx+54h], eax
  push eax                                push eax
* mov ecx, [ebp+__src]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  lea eax, [ebx+4]                        lea eax, [ebx+4]
  push eax                                push eax
  call near ptr _strncpy                  call near ptr _strncpy
  mov eax, [ebx+54h]                      mov eax, [ebx+54h]
  mov byte ptr [eax+ebx+4], 0             mov byte ptr [eax+ebx+4], 0
  mov eax, 1                              mov eax, 1
* jmp loc_5ED6                            jmp loc_4DC6
  xor eax, eax                            xor eax, eax
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

```
-[PnPDeviceResources setDeviceName:Length:]
  status=different raw_equal=False masked_equal=True
  reason: calls differ
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  cmp dword ptr [ebx+58h], 0              cmp dword ptr [ebx+58h], 0
* jnz loc_5FD0                            jnz loc_3A4C
  mov eax, 4Fh                            mov eax, 4Fh
  cmp eax, edx                            cmp eax, edx
* jle loc_5FAF                            jle loc_3A2B
  mov eax, edx                            mov eax, edx
  mov [ebx+58h], eax                      mov [ebx+58h], eax
  push eax                                push eax
* mov ecx, [ebp+__src]                    mov ecx, [ebp+arg_8]
  push ecx                                push ecx
  lea eax, [ebx+8]                        lea eax, [ebx+8]
  push eax                                push eax
  call near ptr _strncpy                  call near ptr _strncpy
  mov eax, [ebx+58h]                      mov eax, [ebx+58h]
  mov byte ptr [eax+ebx+8], 0             mov byte ptr [eax+ebx+8], 0
  mov eax, 1                              mov eax, 1
* jmp loc_5FD2                            jmp loc_3A4E
  xor eax, eax                            xor eax, eax
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 nested `[[list] addObject:]` (2026-09-17)

Kernel-only reloc statuses were not reopened. Reloc SHA `C471FE4013DF9F95FFD3DE61F11183C049347E8812EFCB65B2F29851EC746C42` (603708). All four add methods are IDA `masked_equal`. `addIOPort:`/`addIRQ:`/`addMemory:` match `addDMA:` aside from the ivar offset.

```
-[PnPResources addDMA:]
  status=different raw_equal=False masked_equal=True
  reason: calls differ
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, ds:paAddobject                 mov edx, ds:paAddobject
  push edx                                push edx
  mov edx, ds:paList_0                    mov edx, ds:paList_0
  push edx                                push edx
  mov eax, [eax+8]                        mov eax, [eax+8]
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `deviceWithID:` loop polarity (2026-09-17)

Kernel-only reloc statuses were not reopened. Reloc SHA `F9875D7FFCF001691C92E33C910CEBEDA040E004D476F067773CDC83F445F799` (603708). Same leftover as the tool: inverted ID-compare jump after matching Apple `jz` on nil. Accepted compiler-shaped leftover (reviewer Pat Raynor).

```
-[PnPDeviceResources deviceWithID:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov edi, [ebp+arg_8]                    mov edi, [ebp+arg_8]
  xor esi, esi                            xor esi, esi
  nop                                     nop
  push esi                                push esi
  mov edx, ds:paObjectat                  mov edx, ds:paObjectat
  push edx                                push edx
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  mov ecx, [ecx+4]                        mov ecx, [ecx+4]
  push ecx                                push ecx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 0Ch                            add esp, 0Ch
  test ebx, ebx                           test ebx, ebx
* jz loc_6D54                             jz loc_39F0
  mov edx, ds:paId                        mov edx, ds:paId
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  cmp eax, edi                            cmp eax, edi
* jnz loc_6D50                            jz loc_39EC
*                                         inc esi
*                                         jmp loc_39B8
  mov eax, ebx                            mov eax, ebx
* jmp loc_6D56                            jmp loc_39F2
* inc esi
* jmp loc_6D18
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `deviceWithID:` loop polarity (2026-09-17)

Kernel-only reloc statuses were not reopened. Reloc SHA `F9875D7FFCF001691C92E33C910CEBEDA040E004D476F067773CDC83F445F799` (603708). Same leftover as the tool: inverted ID-compare jump after matching Apple `jz` on nil. Accepted compiler-shaped leftover (reviewer Pat Raynor).

```
-[PnPDeviceResources deviceWithID:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov edi, [ebp+arg_8]                    mov edi, [ebp+arg_8]
  xor esi, esi                            xor esi, esi
  nop                                     nop
  push esi                                push esi
  mov edx, ds:paObjectat                  mov edx, ds:paObjectat
  push edx                                push edx
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  mov ecx, [ecx+4]                        mov ecx, [ecx+4]
  push ecx                                push ecx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 0Ch                            add esp, 0Ch
  test ebx, ebx                           test ebx, ebx
* jz loc_6D54                             jz loc_39F0
  mov edx, ds:paId                        mov edx, ds:paId
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  cmp eax, edi                            cmp eax, edi
* jnz loc_6D50                            jz loc_39EC
*                                         inc esi
*                                         jmp loc_39B8
  mov eax, ebx                            mov eax, ebx
* jmp loc_6D56                            jmp loc_39F2
* inc esi
* jmp loc_6D18
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 accept remaining empty-list leftovers (2026-09-17)

Shared nine-class `none` names that were still `unexamined` on reloc are now `intentional-mismatch` (reviewer Pat Raynor). Names already `assembly-matched` from Task 5/6 were left matched. Kernel-only reloc statuses were not reopened. Reloc SHA `F9875D7FFCF001691C92E33C910CEBEDA040E004D476F067773CDC83F445F799`. Dumps are current published IDA `--name`.

#### `+[PnPDeviceResources setReadPort:]`

Reloc already `assembly-matched`; dump recorded for dual-bar evidence.

```
+[PnPDeviceResources setReadPort:]
  status=different raw_equal=False masked_equal=True
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov ax, [ebp+arg_8]                     mov ax, [ebp+arg_8]
  mov ds:_readPort, ax                    mov ds:_readPort, ax
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPDeviceResources deviceCount]`

Reloc already `assembly-matched`; dump recorded for dual-bar evidence.

```
-[PnPDeviceResources deviceCount]
  status=different raw_equal=False masked_equal=True
  reason: calls differ
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, ds:paCount                     mov edx, ds:paCount
  push edx                                push edx
  mov eax, [eax+4]                        mov eax, [eax+4]
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPLogicalDevice addCompatID:]`

Reloc already `assembly-matched`; dump recorded for dual-bar evidence.

```
-[PnPLogicalDevice addCompatID:]
  status=different raw_equal=False masked_equal=True
  reason: calls differ
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, ds:paAddobject                 mov edx, ds:paAddobject
  push edx                                push edx
  mov eax, [eax+5Ch]                      mov eax, [eax+5Ch]
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `+[PnPDeviceResources setVerbose:]`

Reloc already `assembly-matched`; dump recorded for dual-bar evidence.

```
+[PnPDeviceResources setVerbose:]
  status=different raw_equal=False masked_equal=True
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov al, [ebp+arg_8]                     mov al, [ebp+arg_8]
* mov ds:_verbose_0, al                   mov ds:_verbose, al
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpIOPort initWithBase:Length:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[pnpIOPort initWithBase:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov bx, [ebp+arg_8]                     mov bx, [ebp+arg_8]
  mov si, [ebp+arg_C]                     mov si, [ebp+arg_C]
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov [ebp+var_8.receiver], edi           mov [ebp+var_8.receiver], edi
* mov edx, ds:stru_A534.ext               mov edx, ds:stru_A4F0.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov [edi+6], bx                         mov [edi+6], bx
  mov [edi+4], bx                         mov [edi+4], bx
  mov [edi+0Ah], si                       mov [edi+0Ah], si
  mov eax, edi                            mov eax, edi
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpMemory initWithBase:Length:Bit16:Bit32:HighAddr:Is32:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[pnpMemory initWithBase:Length:Bit16:Bit32:HighAddr:Is32:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 14h                            sub esp, 14h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov edi, [ebp+self]                     mov edi, [ebp+self]
  mov esi, [ebp+arg_C]                    mov esi, [ebp+arg_C]
  mov bl, [ebp+arg_10]                    mov bl, [ebp+arg_10]
  mov dl, [ebp+arg_14]                    mov dl, [ebp+arg_14]
  mov [ebp+var_C], dl                     mov [ebp+var_C], dl
  mov dl, [ebp+arg_18]                    mov dl, [ebp+arg_18]
  mov [ebp+var_10], dl                    mov [ebp+var_10], dl
  mov dl, [ebp+arg_1C]                    mov dl, [ebp+arg_1C]
  mov [ebp+var_14], dl                    mov [ebp+var_14], dl
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov [ebp+var_8.receiver], edi           mov [ebp+var_8.receiver], edi
* mov edx, ds:stru_A534.super_class       mov edx, ds:stru_A540.ext
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  mov [edi+8], edx                        mov [edi+8], edx
  mov [edi+4], edx                        mov [edi+4], edx
  mov [edi+10h], esi                      mov [edi+10h], esi
  test bl, bl                             test bl, bl
  setz al                                 setz al
  mov [edi+19h], al                       mov [edi+19h], al
  mov [edi+1Ah], bl                       mov [edi+1Ah], bl
  mov dl, [ebp+var_C]                     mov dl, [ebp+var_C]
  mov [edi+1Bh], dl                       mov [edi+1Bh], dl
  mov dl, [ebp+var_14]                    mov dl, [ebp+var_14]
  mov [edi+1Ch], dl                       mov [edi+1Ch], dl
  mov dl, [ebp+var_10]                    mov dl, [ebp+var_10]
  mov [edi+16h], dl                       mov [edi+16h], dl
  mov eax, edi                            mov eax, edi
  lea esp, [ebp-20h]                      lea esp, [ebp-20h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResources free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPResources free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov edx, [ebx+8]                        mov edx, [ebx+8]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov edx, [ebx+0Ch]                      mov edx, [ebx+0Ch]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov edx, [ebx+10h]                      mov edx, [ebx+10h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 20h                            add esp, 20h
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A4E4.super_class       mov edx, ds:stru_A590.ext
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResource free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPResource free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
*                                         push edx
  mov edx, ds:paFreeobjects               mov edx, ds:paFreeobjects
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              add esp, 0Ch
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A4E4.ext               mov edx, ds:stru_A590.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResource init]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPResource init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A4E4.ext               mov edx, ds:stru_A590.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paList                      mov edx, ds:paList
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+4], eax                        mov [ebx+4], eax
  mov dword ptr [ebx+8], 0                mov dword ptr [ebx+8], 0
  add esp, 10h                            add esp, 10h
  cmp dword ptr [ebx+4], 0                cmp dword ptr [ebx+4], 0
* jz loc_4EE8                             jz loc_5700
  mov eax, ebx                            mov eax, ebx
* jmp loc_4EF5                            jmp loc_570D
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPDeviceResources free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPDeviceResources free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  cmp dword ptr [ebx+4], 0                cmp dword ptr [ebx+4], 0
* jz loc_6CBB                             jz loc_390C
  mov edx, ds:paFree                      mov edx, ds:paFree
*                                         push edx
  push edx                                push edx
  mov edx, ds:paFreeobjects               mov edx, ds:paFreeobjects
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              add esp, 0Ch
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A444.ext               mov edx, ds:stru_A4A0.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPLogicalDevice free]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPLogicalDevice free]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov edx, [ebx+60h]                      mov edx, [ebx+60h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
*                                         push edx
  mov edx, ds:paFreeobjects               mov edx, ds:paFreeobjects
  push edx                                push edx
  mov edx, [ebx+64h]                      mov edx, [ebx+64h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              add esp, 0Ch
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov edx, [ebx+5Ch]                      mov edx, [ebx+5Ch]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A494.super_class       mov edx, ds:stru_A540.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPLogicalDevice init]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPLogicalDevice init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A494.super_class       mov edx, ds:stru_A540.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paPnpresources              mov edx, ds:paPnpresources
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+60h], eax                      mov [ebx+60h], eax
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paList                      mov edx, ds:paList
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+64h], eax                      mov [ebx+64h], eax
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paList                      mov edx, ds:paList
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+5Ch], eax                      mov [ebx+5Ch], eax
  mov eax, ebx                            mov eax, ebx
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpIOPort print]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[pnpIOPort print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* mov edx, [ebp+self]                     push ebx
* movzx eax, byte ptr [edx+0Ch]           mov ebx, [ebp+self]
*                                         movzx eax, byte ptr [ebx+0Ch]
  push eax                                push eax
* movzx eax, word ptr [edx+0Ah]           movzx eax, word ptr [ebx+0Ah]
  push eax                                push eax
* movzx eax, word ptr [edx+8]             movzx eax, word ptr [ebx+8]
  push eax                                push eax
* movzx eax, word ptr [edx+6]             movzx eax, word ptr [ebx+6]
  push eax                                push eax
* movzx eax, word ptr [edx+4]             movzx eax, word ptr [ebx+4]
  push eax                                push eax
  push offset aIOPort0xX0xXAl             push offset aIOPort0xX0xXAl
  call near ptr _IOLog                    call near ptr _IOLog
*                                         mov eax, ebx
*                                         mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPDeviceResources initForBufNoHeader:Length:CSN:]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPDeviceResources initForBufNoHeader:Length:CSN:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov ebx, [ebp+arg_10]                   mov ebx, [ebp+arg_10]
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
* mov edx, ds:stru_A444.ext               mov edx, ds:stru_A4A0.super_class
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov [esi+64h], ebx                      mov [esi+64h], ebx
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paList                      mov edx, ds:paList
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [esi+4], eax                        mov [esi+4], eax
  add esp, 10h                            add esp, 10h
  test eax, eax                           test eax, eax
* jz loc_6C58                             jz loc_38B8
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  mov edx, ds:paParseconfigLen            mov edx, ds:paParseconfigLen
  push edx                                push edx
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 10h                            add esp, 10h
* test al, al                             test eax, eax
* jz loc_6C62                             jz loc_38C2
  mov eax, esi                            mov eax, esi
* jmp loc_6C6F                            jmp loc_38CF
* push offset aPnpdeviceresou_13          push offset aPnpdeviceresou_0
  call near ptr _IOLog                    call near ptr _IOLog
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResources init]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPResources init]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edx, ds:stru_A4E4.super_class       mov edx, ds:stru_A590.ext
  mov [ebp+var_8.super_class], edx        mov [ebp+var_8.super_class], edx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paPnpresource               mov edx, ds:paPnpresource
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+4], eax                        mov [ebx+4], eax
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paPnpresource               mov edx, ds:paPnpresource
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+8], eax                        mov [ebx+8], eax
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paPnpresource               mov edx, ds:paPnpresource
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+0Ch], eax                      mov [ebx+0Ch], eax
  add esp, 20h                            add esp, 20h
  mov edx, ds:paInit                      mov edx, ds:paInit
  push edx                                push edx
  mov edx, ds:paAlloc                     mov edx, ds:paAlloc
  push edx                                push edx
  mov edx, ds:paPnpresource               mov edx, ds:paPnpresource
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebx+10h], eax                      mov [ebx+10h], eax
  add esp, 8                              add esp, 8
  cmp dword ptr [ebx+4], 0                cmp dword ptr [ebx+4], 0
* jz loc_5162                             jz loc_5966
  cmp dword ptr [ebx+8], 0                cmp dword ptr [ebx+8], 0
* jz loc_5162                             jz loc_5966
  cmp dword ptr [ebx+0Ch], 0              cmp dword ptr [ebx+0Ch], 0
* jz loc_5162                             jz loc_5966
  test eax, eax                           test eax, eax
* jnz loc_5174                            jnz loc_5978
  mov edx, ds:paFree                      mov edx, ds:paFree
  push edx                                push edx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* jmp loc_5176                            jmp loc_597A
  mov eax, ebx                            mov eax, ebx
  mov ebx, [ebp+var_C]                    mov ebx, [ebp+var_C]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[PnPResources print]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[PnPResources print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 20h                            sub esp, 10h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  mov edx, [eax+0Ch]                      mov edx, [eax+0Ch]
* mov [ebp+var_20], edx                   mov [ebp+var_10], edx
  mov edx, [eax+4]                        mov edx, [eax+4]
* mov [ebp+var_1C], edx                   mov [ebp+var_C], edx
  mov edx, [eax+10h]                      mov edx, [eax+10h]
* mov [ebp+var_18], edx                   mov [ebp+var_8], edx
  mov eax, [eax+8]                        mov eax, [eax+8]
* mov [ebp+var_14], eax                   mov [ebp+var_4], eax
* mov edx, [ebp+var_20]
* mov [ebp+var_10], edx
* mov edx, [ebp+var_1C]
* mov [ebp+var_C], edx
* mov edx, [ebp+var_18]
* mov [ebp+var_8], edx
* mov edx, [ebp+var_14]
* mov [ebp+var_4], edx
  xor esi, esi                            xor esi, esi
  nop                                     nop
  nop                                     nop
  mov edx, ds:paList_0                    mov edx, ds:paList_0
  push edx                                push edx
  mov edx, [ebp+esi*4+var_10]             mov edx, [ebp+esi*4+var_10]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edi, eax                            mov edi, eax
  xor ebx, ebx                            xor ebx, ebx
  add esp, 8                              add esp, 8
  push ebx                                push ebx
  mov edx, ds:paObjectat                  mov edx, ds:paObjectat
  push edx                                push edx
  push edi                                push edi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
  test eax, eax                           test eax, eax
* jz loc_5078                             jz loc_63DC
  mov edx, ds:paPrint                     mov edx, ds:paPrint
  push edx                                push edx
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8
  inc ebx                                 inc ebx
* jmp loc_5050                            jmp loc_63B1
  inc esi                                 inc esi
  cmp esi, 3                              cmp esi, 3
* jle loc_5038                            jle loc_639C
* lea esp, [ebp-2Ch]                      lea esp, [ebp-1Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpIRQ print]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[pnpIRQ print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov [ebp+var_4], 1                      mov [ebp+var_4], 1
  push offset aIrq                        push offset aIrq
  call near ptr _IOLog                    call near ptr _IOLog
  xor ebx, ebx                            xor ebx, ebx
  add esp, 4                              add esp, 4
  cmp [esi+44h], ebx                      cmp [esi+44h], ebx
* jle loc_3D31                            jle loc_4B39
  nop                                     nop
*                                         mov eax, offset asc_7854
*                                         cmp [ebp+var_4], 0
*                                         jz loc_4B1C
*                                         mov eax, offset unk_6FCB
  mov edx, [esi+ebx*4+4]                  mov edx, [esi+ebx*4+4]
  push edx                                push edx
* mov eax, offset asc_77D8
* cmp [ebp+var_4], 0
* jz loc_3D19
* mov eax, offset unk_7676
  push eax                                push eax
  push offset aSD                         push offset aSD
  call near ptr _IOLog                    call near ptr _IOLog
  mov [ebp+var_4], 0                      mov [ebp+var_4], 0
  add esp, 0Ch                            add esp, 0Ch
  inc ebx                                 inc ebx
  cmp [esi+44h], ebx                      cmp [esi+44h], ebx
* jg loc_3D04                             jg loc_4B0C
  cmp byte ptr [esi+48h], 0               cmp byte ptr [esi+48h], 0
* jz loc_3D44                             jz loc_4B4C
  push offset aHighEdge                   push offset aHighEdge
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+49h], 0               cmp byte ptr [esi+49h], 0
* jz loc_3D57                             jz loc_4B5F
  push offset aLowEdge                    push offset aLowEdge
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+4Ah], 0               cmp byte ptr [esi+4Ah], 0
* jz loc_3D6A                             jz loc_4B72
  push offset aHighLevel                  push offset aHighLevel
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+4Bh], 0               cmp byte ptr [esi+4Bh], 0
* jz loc_3D7D                             jz loc_4B85
  push offset aLowLevel                   push offset aLowLevel
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
* push offset asc_7818                    push offset asc_76B4
  call near ptr _IOLog                    call near ptr _IOLog
*                                         mov eax, esi
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpMemory print]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[pnpMemory print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
*                                         mov eax, offset a24
*                                         cmp byte ptr [ebx+1Ch], 0
*                                         jz loc_538F
*                                         mov eax, offset a32
  mov edx, [ebx+10h]                      mov edx, [ebx+10h]
  push edx                                push edx
  mov edx, [ebx+0Ch]                      mov edx, [ebx+0Ch]
  push edx                                push edx
  mov edx, [ebx+8]                        mov edx, [ebx+8]
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
* mov eax, offset a24
* cmp byte ptr [ebx+1Ch], 0
* jz loc_45DF
* mov eax, offset a32
  push eax                                push eax
  push offset aMemS0xLx0xLxAl             push offset aMemS0xLx0xLxAl
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 18h                            add esp, 18h
  cmp byte ptr [ebx+19h], 0               cmp byte ptr [ebx+19h], 0
* jz loc_4600                             jz loc_53C0
  push offset a8Bit_0                     push offset a8Bit_0
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [ebx+1Ah], 0               cmp byte ptr [ebx+1Ah], 0
* jz loc_4613                             jz loc_53D3
  push offset a16Bit_0                    push offset a16Bit_0
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [ebx+1Bh], 0               cmp byte ptr [ebx+1Bh], 0
* jz loc_4626                             jz loc_53E6
  push offset a32Bit                      push offset a32Bit
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [ebx+14h], 0               cmp byte ptr [ebx+14h], 0
* jz loc_4639                             jz loc_53F9
  push offset aExprom                     push offset aExprom
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [ebx+15h], 0               cmp byte ptr [ebx+15h], 0
* jz loc_464C                             jz loc_540C
  push offset aShadow                     push offset aShadow
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
*                                         mov eax, offset aRange
  cmp byte ptr [ebx+16h], 0               cmp byte ptr [ebx+16h], 0
* jz loc_465C                             jz loc_541C
* push offset aHiAddr                     mov eax, offset aHiAddr
* jmp loc_4661                            push eax
* push offset aRange
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [ebx+18h], 0               cmp byte ptr [ebx+18h], 0
* jnz loc_467C                            jnz loc_5438
  push offset aRom                        push offset aRom
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
* push offset asc_7818                    push offset asc_76B4
  call near ptr _IOLog                    call near ptr _IOLog
*                                         mov eax, ebx
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

#### `-[pnpDMA print]`

Accepted `intentional-mismatch` (compiler-shaped leftover after exhausted source-shape list).

```
-[pnpDMA print]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov [ebp+var_4], 1                      mov [ebp+var_4], 1
  push offset aDmaChannel                 push offset aDmaChannel
  call near ptr _IOLog                    call near ptr _IOLog
  xor ebx, ebx                            xor ebx, ebx
  add esp, 4                              add esp, 4
  cmp [esi+24h], ebx                      cmp [esi+24h], ebx
* jle loc_4001                            jle loc_4599
  nop                                     nop
*                                         mov eax, offset asc_7854
*                                         cmp [ebp+var_4], 0
*                                         jz loc_457C
*                                         mov eax, offset unk_6FCB
  mov edx, [esi+ebx*4+4]                  mov edx, [esi+ebx*4+4]
  push edx                                push edx
* mov eax, offset asc_77D8
* cmp [ebp+var_4], 0
* jz loc_3FE9
* mov eax, offset unk_7676
  push eax                                push eax
  push offset aSD                         push offset aSD
  call near ptr _IOLog                    call near ptr _IOLog
  mov [ebp+var_4], 0                      mov [ebp+var_4], 0
  add esp, 0Ch                            add esp, 0Ch
  inc ebx                                 inc ebx
  cmp [esi+24h], ebx                      cmp [esi+24h], ebx
* jg loc_3FD4                             jg loc_456C
* push offset asc_7848                    push offset asc_785C
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+28h], 0               cmp byte ptr [esi+28h], 0
* jz loc_4021                             jz loc_45B9
  push offset a8Bit                       push offset a8Bit
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  cmp byte ptr [esi+29h], 0               cmp byte ptr [esi+29h], 0
* jz loc_4034                             jz loc_45CC
  push offset a16Bit                      push offset a16Bit
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
  push offset aBusMaster                  push offset aBusMaster
  call near ptr _IOLog                    call near ptr _IOLog
  push offset aByte                       push offset aByte
  call near ptr _IOLog                    call near ptr _IOLog
  push offset aWord                       push offset aWord
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 0Ch                            add esp, 0Ch
  movzx eax, byte ptr [esi+2Dh]           movzx eax, byte ptr [esi+2Dh]
  cmp eax, 1                              cmp eax, 1
* jz loc_407C                             jz loc_4614
* jg loc_4068                             jg loc_4600
  test eax, eax                           test eax, eax
* jz loc_4074                             jz loc_460C
* jmp loc_4099                            jmp loc_462C
  cmp eax, 2                              cmp eax, 2
* jz loc_4084                             jz loc_461C
  cmp eax, 3                              cmp eax, 3
* jz loc_408C                             jz loc_4624
* jmp loc_4099                            jmp loc_462C
* push offset aCompat                     mov eax, offset aCompat
* jmp loc_4091                            jmp loc_462E
* push offset aTypeA                      mov eax, offset aTypeA
* jmp loc_4091                            jmp loc_462E
* push offset aTypeB                      mov eax, offset aTypeB
* jmp loc_4091                            jmp loc_462E
* push offset aTypeF                      mov eax, offset aTypeF
*                                         jmp loc_462E
*                                         xor eax, eax
*                                         test eax, eax
*                                         jz loc_463B
*                                         push eax
  call near ptr _IOLog                    call near ptr _IOLog
  add esp, 4                              add esp, 4
* push offset asc_7818                    push offset asc_76B4
  call near ptr _IOLog                    call near ptr _IOLog
*                                         mov eax, esi
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpMemory matches:]` alignment local (2026-09-17)

Keep `_alignment` in a local and compute the aligned base only when it is nonzero. Reloc IDA `masked_equal`. Kernel-only reloc statuses were not reopened. Reloc SHA `ED488370D3F6326FAA6B49863D0D61D023F4015CFE6FB9379E26B664AD96536B` (603720). Unpaired count unchanged (11).

```
-[pnpMemory matches:]
  status=different raw_equal=False masked_equal=True
  reason: calls differ
  reason: cfg differs
  reason: instruction layout differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paMinBase                   mov edx, ds:paMinBase
  push edx                                push edx
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ecx, eax                            mov ecx, eax
  mov edi, [ebx+0Ch]                      mov edi, [ebx+0Ch]
  test edi, edi                           test edi, edi
* jz loc_46BD                             jz loc_52C5
  lea eax, [edi+ecx-1]                    lea eax, [edi+ecx-1]
  xor edx, edx                            xor edx, edx
  div edi                                 div edi
  imul eax, edi                           imul eax, edi
  cmp ecx, eax                            cmp ecx, eax
* jnz loc_46D4                            jnz loc_52DC
  cmp [ebx+4], ecx                        cmp [ebx+4], ecx
* ja loc_46D4                             ja loc_52DC
  cmp [ebx+8], ecx                        cmp [ebx+8], ecx
* jb loc_46D4                             jb loc_52DC
  mov eax, 1                              mov eax, 1
* jmp loc_46D6                            jmp loc_52DE
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpMemory setControl:]` omit width zeros (2026-09-17)

Omit reciprocal `_bit16=0`/`_bit8=0` stores and the explicit `return self` so the width cases share Apple's tails. Leftover is char-arg vs Apple pointer reload plus jump labels. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `03B7AB6C624D764E9413BA971A56D9EE20C8B7376353F3426FC640C9D2D7D6BC` (603660). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[pnpMemory setControl:]
  status=different raw_equal=False masked_equal=False
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  mov edx, [ebp+self]                     mov edx, [ebp+self]
* mov ecx, [ebp+arg_8]                    mov cl, [ebp+arg_8]
* mov al, [ecx]                           mov al, cl
  shr al, 3                               shr al, 3
  and eax, 3                              and eax, 3
  cmp eax, 1                              cmp eax, 1
* jz loc_479C                             jz loc_5314
* jg loc_4790                             jg loc_5308
  test eax, eax                           test eax, eax
* jz loc_47A8                             jz loc_5320
* jmp loc_47B4                            jmp loc_532C
  cmp eax, 2                              cmp eax, 2
* jz loc_47A4                             jz loc_531C
  cmp eax, 3                              cmp eax, 3
* jz loc_47B0                             jz loc_5328
* jmp loc_47B4                            jmp loc_532C
  mov byte ptr [edx+1Ah], 1               mov byte ptr [edx+1Ah], 1
* jmp loc_47B4                            jmp loc_532C
  mov byte ptr [edx+1Ah], 1               mov byte ptr [edx+1Ah], 1
  mov byte ptr [edx+19h], 1               mov byte ptr [edx+19h], 1
* jmp loc_47B4                            jmp loc_532C
  mov byte ptr [edx+1Bh], 1               mov byte ptr [edx+1Bh], 1
* mov al, [ecx]                           mov al, cl
  shr al, 6                               shr al, 6
  and al, 1                               and al, 1
  mov [edx+14h], al                       mov [edx+14h], al
* mov al, [ecx]                           mov al, cl
  shr al, 5                               shr al, 5
  and al, 1                               and al, 1
  mov [edx+15h], al                       mov [edx+15h], al
* mov al, [ecx]                           mov al, cl
  shr al, 2                               shr al, 2
  and al, 1                               and al, 1
  mov [edx+16h], al                       mov [edx+16h], al
* mov al, [ecx]                           mov al, cl
  shr al, 1                               shr al, 1
  and al, 1                               and al, 1
  mov [edx+17h], al                       mov [edx+17h], al
* mov cl, [ecx]
  and cl, 1                               and cl, 1
  mov [edx+18h], cl                       mov [edx+18h], cl
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpIRQ initFrom:Length:]` mask/flags expressions (2026-09-17)

Load the IRQ mask and flag byte from the buffer expression instead of locals. Leftover is extra edi buffer copy, IDA class-pointer / verbose names, and jump labels. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `9F4690F3B9178CA88EA6C50FB73C3D68F29A6C304C153D950EF5E3EE90495FF1` (603588). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[pnpIRQ initFrom:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
* push edi
  push esi                                push esi
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov esi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
  mov ecx, ds:paInit                      mov ecx, ds:paInit
  push ecx                                push ecx
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov ecx, ds:stru_A584.ext               mov ecx, ds:stru_A4F0.ext
  mov [ebp+var_8.super_class], ecx        mov [ebp+var_8.super_class], ecx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
* mov edi, esi
  mov dword ptr [ebx+44h], 0              mov dword ptr [ebx+44h], 0
  xor edx, edx                            xor edx, edx
  add esp, 8                              add esp, 8
  nop                                     nop
  nop                                     nop
* nop                                     movzx eax, word ptr [esi]
* movzx eax, word ptr [edi]
  bt eax, edx                             bt eax, edx
* jnb loc_3E5E                            jnb loc_49A2
  mov eax, [ebx+44h]                      mov eax, [ebx+44h]
  mov [ebx+eax*4+4], edx                  mov [ebx+eax*4+4], edx
  inc dword ptr [ebx+44h]                 inc dword ptr [ebx+44h]
  inc edx                                 inc edx
  cmp edx, 0Fh                            cmp edx, 0Fh
* jle loc_3E4C                            jle loc_4990
  mov byte ptr [ebx+48h], 1               mov byte ptr [ebx+48h], 1
  cmp [ebp+arg_C], 2                      cmp [ebp+arg_C], 2
* jle loc_3E97                            jle loc_49DB
  mov cl, [esi+2]                         mov cl, [esi+2]
  and cl, 1                               and cl, 1
  mov [ebx+48h], cl                       mov [ebx+48h], cl
  mov al, [esi+2]                         mov al, [esi+2]
  shr al, 1                               shr al, 1
  and al, 1                               and al, 1
  mov [ebx+49h], al                       mov [ebx+49h], al
  mov al, [esi+2]                         mov al, [esi+2]
  shr al, 2                               shr al, 2
  and al, 1                               and al, 1
  mov [ebx+4Ah], al                       mov [ebx+4Ah], al
  mov al, [esi+2]                         mov al, [esi+2]
  shr al, 3                               shr al, 3
  and al, 1                               and al, 1
  mov [ebx+4Bh], al                       mov [ebx+4Bh], al
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_3EAD                             jz loc_49F1
  mov ecx, ds:paPrint                     mov ecx, ds:paPrint
  push ecx                                push ecx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov eax, ebx                            mov eax, ebx
* lea esp, [ebp-14h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpIOPort matches:]` alignment local (2026-09-17)

Keep `_alignment` in a 32-bit local, `otherBase` 16-bit, and skip the div when alignment is zero. Leftover is register vs stack for the divisor plus jump labels. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `5AEF7E33F96356FF7D824FE2CDEAECA68BC420D5550E06D2B24A6DF620E03350` (603612). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[pnpIOPort matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 4                              sub esp, 4
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
* mov esi, [ebp+self]                     mov ebx, [ebp+self]
* mov edx, ds:paMinBase                   mov eax, ds:paMinBase
* push edx                                push eax
  mov edx, [ebp+arg_8]                    mov edx, [ebp+arg_8]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* mov ebx, eax                            mov ecx, eax
* movzx ecx, bx                           movzx edi, word ptr [ebx+8]
* mov eax, ecx                            movzx esi, cx
* movzx edx, word ptr [esi+8]             test edi, edi
* mov [ebp+var_4], edx                    jz loc_485B
* test edx, edx                           lea esi, [edi+esi-1]
* jnz loc_42F4                            mov eax, esi
* mov edi, ecx
* jmp loc_4306
* mov edx, [ebp+var_4]
* lea eax, [edx+eax-1]
  xor edx, edx                            xor edx, edx
* div [ebp+var_4]                         div edi
* mov edi, [ebp+var_4]                    mov esi, eax
* imul edi, eax                           imul esi, edi
* cmp ecx, edi                            movzx eax, cx
* jnz loc_4320                            cmp eax, esi
* cmp [esi+4], bx                         jnz loc_4878
* ja loc_4320                             cmp [ebx+4], cx
* cmp [esi+6], bx                         ja loc_4878
* jb loc_4320                             cmp [ebx+6], cx
*                                         jb loc_4878
  mov eax, 1                              mov eax, 1
* jmp loc_4322                            jmp loc_487A
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-10h]                      lea esp, [ebp-10h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 -[PnPResource objectAt:Using:] if/else if dispatch (2026-09-17)

Flatten index dispatch to if (index < _depStart) / else if / else so the outer compare is Apple jle. Leftover is the usingList local versus Apple nested [list] plus inner jl/jge polarity. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA 28B80C9E5FA1BB95EF62F525D4B48A532BDAC434650B438AC63601CC9A1B42AC (603620). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

`
-[PnPResource objectAt:Using:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  mov ebx, [ebp+arg_8]                    mov ebx, [ebp+arg_8]
* mov edi, [ebp+arg_C]                    mov edx, ds:paList_0
* mov ecx, ds:paCount                     push edx
* push ecx                                mov edx, [ebp+arg_C]
* mov ecx, ds:paList_0                    push edx
* push ecx                                call near ptr _objc_msgSend
*                                         mov edi, eax
*                                         mov edx, ds:paCount
*                                         push edx
  push edi                                push edi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              add esp, 10h
* push eax
* call near ptr _objc_msgSend
* mov edx, eax
* add esp, 8
  cmp [esi+8], ebx                        cmp [esi+8], ebx
* jle loc_4FA8                            jle loc_57A0
  push ebx                                push ebx
* jmp loc_4FDC                            mov edx, ds:paObjectat
* mov eax, edx                            push edx
*                                         mov esi, [esi+4]
*                                         push esi
*                                         jmp loc_57C6
  add eax, [esi+8]                        add eax, [esi+8]
  cmp ebx, eax                            cmp ebx, eax
* jge loc_4FD4                            jl loc_57B8
*                                         add eax, ebx
*                                         push eax
*                                         mov edx, ds:paObjectat
*                                         push edx
*                                         mov esi, [esi+4]
*                                         push esi
*                                         jmp loc_57C6
  mov eax, ebx                            mov eax, ebx
  sub eax, [esi+8]                        sub eax, [esi+8]
  push eax                                push eax
* mov ecx, ds:paObjectat                  mov edx, ds:paObjectat
* push ecx                                push edx
* mov ecx, ds:paList_0
* push ecx
  push edi                                push edi
* call near ptr _objc_msgSend
* add esp, 8
* push eax
* jmp loc_4FE7
* mov eax, edx
* add eax, [esi+8]
* add eax, ebx
* push eax
* mov ecx, ds:paObjectat
* push ecx
* mov esi, [esi+4]
* push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 `-[pnpDMA initFrom:Length:]` do-while mask walk (2026-09-17)

Walk the DMA channel mask with a do-while so the compiler still emits Apple `bt` / `cmp 7` / `jle`. Leftover is explicit `_count = 0` plus `data[1]` versus Apple's post-increment buffer pointer. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `25DC982C3EE8B344B7239162BC99532E17574BC8095051E2B12F0A7D7E0EE516` (603644). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[pnpDMA initFrom:Length:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov esi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
  mov edi, ds:paInit                      mov edi, ds:paInit
  push edi                                push edi
  mov [ebp+var_8.receiver], ebx           mov [ebp+var_8.receiver], ebx
* mov edi, ds:stru_A584.super_class       mov edi, ds:stru_A4A0.ext
  mov [ebp+var_8.super_class], edi        mov [ebp+var_8.super_class], edi
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
* mov al, [esi]                           mov dword ptr [ebx+24h], 0
* inc esi
  xor edx, edx                            xor edx, edx
  add esp, 8                              add esp, 8
* movzx ecx, al                           movzx ecx, byte ptr [esi]
  nop                                     nop
  nop                                     nop
  bt ecx, edx                             bt ecx, edx
* jnb loc_4173                            jnb loc_440B
  mov eax, [ebx+24h]                      mov eax, [ebx+24h]
  mov [ebx+eax*4+4], edx                  mov [ebx+eax*4+4], edx
  inc dword ptr [ebx+24h]                 inc dword ptr [ebx+24h]
  inc edx                                 inc edx
  cmp edx, 7                              cmp edx, 7
* jle loc_4164                            jle loc_43FC
* mov edx, esi                            mov dl, [esi+1]
* mov al, [edx]                           mov eax, edx
  and eax, 3                              and eax, 3
  cmp eax, 1                              cmp eax, 1
* jz loc_41A4                             jz loc_443C
* jg loc_4190                             jg loc_4428
  test eax, eax                           test eax, eax
* jz loc_4198                             jz loc_4430
* jmp loc_41B4                            jmp loc_444C
  cmp eax, 2                              cmp eax, 2
* jz loc_41AC                             jz loc_4444
* jmp loc_41B4                            jmp loc_444C
  mov byte ptr [ebx+28h], 1               mov byte ptr [ebx+28h], 1
  mov byte ptr [ebx+29h], 0               mov byte ptr [ebx+29h], 0
* jmp loc_41B4                            jmp loc_444C
  mov byte ptr [ebx+28h], 1               mov byte ptr [ebx+28h], 1
* jmp loc_41B0                            jmp loc_4448
  mov byte ptr [ebx+28h], 0               mov byte ptr [ebx+28h], 0
  mov byte ptr [ebx+29h], 1               mov byte ptr [ebx+29h], 1
* mov al, [edx]                           mov al, dl
  shr al, 2                               shr al, 2
  and al, 1                               and al, 1
  mov [ebx+2Ah], al                       mov [ebx+2Ah], al
* mov al, [edx]                           mov al, dl
  shr al, 3                               shr al, 3
  and al, 1                               and al, 1
  mov [ebx+2Bh], al                       mov [ebx+2Bh], al
* mov al, [edx]                           mov al, dl
  shr al, 4                               shr al, 4
  and al, 1                               and al, 1
  mov [ebx+2Ch], al                       mov [ebx+2Ch], al
* mov al, [edx]                           mov al, dl
  shr al, 5                               shr al, 5
  and al, 3                               and al, 3
  mov [ebx+2Dh], al                       mov [ebx+2Dh], al
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_41F2                             jz loc_448A
  mov edi, ds:paPrint                     mov edi, ds:paPrint
  push edi                                push edi
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov eax, ebx                            mov eax, ebx
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 -[PnPResource matches:Using:] count==0 else-wrap (2026-09-17)

Same else-wrap as the tool. Leftover is Apple's list/count and nested `[list objectAt:]` stack reuse versus a `configList` local. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA 2CA61BA37A7EF5A8D33FFB885D1A7C516DD6A58779288B1EFBC5AD038C67A0F0 (603644). Previously identical rows stayed matched (46). Unpaired count unchanged (11).

`
-[PnPResource matches:Using:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
* mov edi, [ebp+arg_8]                    mov edx, ds:paList_0
*                                         push edx
*                                         mov edx, [ebp+arg_8]
*                                         push edx
*                                         call near ptr _objc_msgSend
*                                         mov edi, eax
  mov edx, ds:paCount                     mov edx, ds:paCount
* push edx
* mov edx, ds:paList_0
  push edx                                push edx
  push edi                                push edi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              add esp, 10h
* push eax
* call near ptr _objc_msgSend
* add esp, 8
  test eax, eax                           test eax, eax
* jnz loc_4E1C                            jnz loc_5810
  mov eax, 1                              mov eax, 1
* jmp loc_4E7E                            jmp loc_5862
  xor eax, eax                            xor eax, eax
* jmp loc_4E7E                            jmp loc_5862
  xor ebx, ebx                            xor ebx, ebx
  nop                                     nop
  nop                                     nop
  mov edx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
  push edx                                push edx
  push ebx                                push ebx
  mov edx, ds:paObjectatUsing             mov edx, ds:paObjectatUsing
  push edx                                push edx
  mov edx, [ebp+self]                     mov edx, [ebp+self]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov esi, eax                            mov esi, eax
  add esp, 10h                            add esp, 10h
  test esi, esi                           test esi, esi
* jz loc_4E74                             jz loc_5858
  push ebx                                push ebx
  mov edx, ds:paObjectat                  mov edx, ds:paObjectat
  push edx                                push edx
* mov edx, ds:paList_0
* push edx
  push edi                                push edi
* call near ptr _objc_msgSend
* add esp, 8
* push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push eax                                push eax
  mov edx, ds:paMatches                   mov edx, ds:paMatches
  push edx                                push edx
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 18h                            add esp, 18h
  test al, al                             test al, al
* jz loc_4E18                             jz loc_580C
  inc ebx                                 inc ebx
* jmp loc_4E20                            jmp loc_5814
  test ebx, ebx                           test ebx, ebx
  setnle al                               setnle al
  and eax, 0FFh                           and eax, 0FFh
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 -[pnpDMA matches:] else-if on otherCount (2026-09-17)

Same else-if as the tool. Leftover is Apple's double `[number]` and in-loop `dmaChannels` versus locals plus register scheduling. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA 7903D28185A72DADE601548D5447579C6EC2636D95BB1ABFEC9D3135B152903D (603644). Previously identical rows stayed matched (46). Unpaired count unchanged (11).

`
-[pnpDMA matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
* mov esi, [ebp+self]                     mov ebx, [ebp+self]
* mov edi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov edx, ds:paNumber                    mov edi, ds:paNumber
* push edx
  push edi                                push edi
*                                         push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_411E                             jz loc_453A
* mov edx, ds:paNumber
* push edx
* push edi
* call near ptr _objc_msgSend
* add esp, 8
  cmp eax, 1                              cmp eax, 1
* jz loc_40F8                             jz loc_4514
  push offset aPnpdmaCanOnlyM             push offset aPnpdmaCanOnlyM
  call near ptr _IOLog                    call near ptr _IOLog
* jmp loc_411E                            jmp loc_453A
  mov eax, 1                              mov eax, 1
* jmp loc_4120                            jmp loc_453C
* xor ebx, ebx                            mov edi, ds:paDmachannels
* cmp [esi+24h], ebx                      push edi
* jle loc_411E                            push esi
*                                         call near ptr _objc_msgSend
*                                         mov ecx, eax
*                                         xor edx, edx
*                                         cmp [ebx+24h], edx
*                                         jle loc_453A
  nop                                     nop
* mov edx, ds:paDmachannels               nop
* push edx                                mov eax, [ebx+edx*4+4]
* push edi                                cmp [ecx], eax
* call near ptr _objc_msgSend             jz loc_450C
* add esp, 8                              inc edx
* mov eax, [eax]                          cmp [ebx+24h], edx
* cmp [esi+ebx*4+4], eax                  jg loc_452C
* jz loc_40F0
* inc ebx
* cmp [esi+24h], ebx
* jg loc_4100
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 -[pnpIRQ matches:] else-if on otherCount (2026-09-17)

Same else-if as the tool. Leftover is Apple's double `[number]` and in-loop `irqs` versus locals plus register scheduling. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA 0588D62FCE54FB6EF7D1FB9C65C783E51160FD8DFE8BD8D30DF0FC6E4FB77A5C (603644). Previously identical rows stayed matched (46). Unpaired count unchanged (11).

`
-[pnpIRQ matches:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
* mov esi, [ebp+self]                     mov ebx, [ebp+self]
* mov edi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov edx, ds:paNumber                    mov edi, ds:paNumber
* push edx
  push edi                                push edi
*                                         push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_3E02                             jz loc_4A72
* mov edx, ds:paNumber
* push edx
* push edi
* call near ptr _objc_msgSend
* add esp, 8
  cmp eax, 1                              cmp eax, 1
* jz loc_3DDC                             jz loc_4A4C
  push offset aPnpirqCanOnlyM             push offset aPnpirqCanOnlyM
  call near ptr _IOLog                    call near ptr _IOLog
* jmp loc_3E02                            jmp loc_4A72
  mov eax, 1                              mov eax, 1
* jmp loc_3E04                            jmp loc_4A74
* xor ebx, ebx                            mov edi, ds:paIrqs
* cmp [esi+44h], ebx                      push edi
* jle loc_3E02                            push esi
*                                         call near ptr _objc_msgSend
*                                         mov ecx, eax
*                                         xor edx, edx
*                                         cmp [ebx+44h], edx
*                                         jle loc_4A72
  nop                                     nop
* mov edx, ds:paIrqs                      nop
* push edx                                mov eax, [ebx+edx*4+4]
* push edi                                cmp [ecx], eax
* call near ptr _objc_msgSend             jz loc_4A44
* add esp, 8                              inc edx
* mov eax, [eax]                          cmp [ebx+44h], edx
* cmp [esi+ebx*4+4], eax                  jg loc_4A64
* jz loc_3DD4
* inc ebx
* cmp [esi+44h], ebx
* jg loc_3DE4
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 -[PnPResources markStartDependentResources] nested walks (2026-09-17)

Same nested walks as the tool. Reloc stream nearly matches Apple; leftover is the final `[ebx+10h]` push register versus ebx clobber plus explicit return self. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA 27E6FFC4C2875ECCD322AD6FA55AD5D8B6F8256DF1B4DBDB55CA3A7950B7E805 (603492). Previously identical rows stayed matched (46). Unpaired count unchanged (11).

`
-[PnPResources markStartDependentResources]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  push ebx                                push ebx
  mov ebx, [ebp+self]                     mov ebx, [ebp+self]
  mov edx, ds:paCount                     mov edx, ds:paCount
  push edx                                push edx
  mov edx, ds:paList_0                    mov edx, ds:paList_0
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push eax                                push eax
  mov edx, ds:paSetdepstart               mov edx, ds:paSetdepstart
  push edx                                push edx
  mov edx, [ebx+4]                        mov edx, [ebx+4]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paCount                     mov edx, ds:paCount
  push edx                                push edx
  mov edx, ds:paList_0                    mov edx, ds:paList_0
  push edx                                push edx
  mov edx, [ebx+8]                        mov edx, [ebx+8]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push eax                                push eax
  mov edx, ds:paSetdepstart               mov edx, ds:paSetdepstart
  push edx                                push edx
  mov edx, [ebx+8]                        mov edx, [ebx+8]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 28h                            add esp, 28h
  mov edx, ds:paCount                     mov edx, ds:paCount
  push edx                                push edx
  mov edx, ds:paList_0                    mov edx, ds:paList_0
  push edx                                push edx
  mov edx, [ebx+0Ch]                      mov edx, [ebx+0Ch]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push eax                                push eax
  mov edx, ds:paSetdepstart               mov edx, ds:paSetdepstart
  push edx                                push edx
  mov edx, [ebx+0Ch]                      mov edx, [ebx+0Ch]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov edx, ds:paCount                     mov edx, ds:paCount
  push edx                                push edx
  mov edx, ds:paList_0                    mov edx, ds:paList_0
  push edx                                push edx
  mov edx, [ebx+10h]                      mov edx, [ebx+10h]
  push edx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push eax                                push eax
  mov edx, ds:paSetdepstart               mov edx, ds:paSetdepstart
  push edx                                push edx
* mov ebx, [ebx+10h]                      mov edx, [ebx+10h]
* push ebx                                push edx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
*                                         mov eax, ebx
  mov ebx, [ebp+var_4]                    mov ebx, [ebp+var_4]
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
`

### Task 6 `-[pnpIOPort initFrom:Length:Type:]` declaration order after header (2026-09-17)

Same declaration-order experiment as the tool. Leftover is type-8/9 layout polarity, flags-bit jump polarity, and verbose symbol naming. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `90981EC419B4016D184F560CD065F8D7CEA6070E3398F1FEC6F479E3B707A212` (603504). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[pnpIOPort initFrom:Length:Type:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction layout differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
*                                         mov edi, [ebp+arg_C]
  mov ebx, [ebp+arg_8]                    mov ebx, [ebp+arg_8]
* mov edi, [ebp+arg_C]
  mov ecx, ds:paInit                      mov ecx, ds:paInit
  push ecx                                push ecx
  mov [ebp+var_8.receiver], esi           mov [ebp+var_8.receiver], esi
* mov ecx, ds:stru_A534.ext               mov ecx, ds:stru_A4F0.super_class
  mov [ebp+var_8.super_class], ecx        mov [ebp+var_8.super_class], ecx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  add esp, 8                              add esp, 8
  cmp [ebp+arg_10], 8                     cmp [ebp+arg_10], 8
* jz loc_43FC                             jnz loc_4718
* cmp [ebp+arg_10], 9                     cmp edi, 7
* jnz loc_4472                            jz loc_46CC
* cmp edi, 3
* jz loc_43C4
  push edi                                push edi
* push offset aPnpdeviceresou             push offset aPnpdeviceresou_9
* jmp loc_4407                            jmp loc_4729
* mov ax, [ebx]
* and ah, 3
* mov [esi+6], ax
* mov [esi+4], ax
* movzx ax, byte ptr [ebx+2]
* mov [esi+0Ah], ax
* mov [esi+8], ax
* mov byte ptr [esi+0Ch], 0Ah
* cmp ds:_verbose_0, 0
* jz loc_4472
* push offset aFixed
* call near ptr _IOLog
* jmp loc_4465
* cmp edi, 7
* jz loc_441C
* push edi
* push offset aPnpdeviceresou_0
* call near ptr _IOLog
* mov ecx, ds:paFree
* push ecx
* push esi
* call near ptr _objc_msgSend
* jmp loc_4474
  mov dl, [ebx]                           mov dl, [ebx]
  inc ebx                                 inc ebx
  mov cx, [ebx]                           mov cx, [ebx]
  mov [esi+4], cx                         mov [esi+4], cx
  mov cx, [ebx+2]                         mov cx, [ebx+2]
  mov [esi+6], cx                         mov [esi+6], cx
  movzx cx, byte ptr [ebx+5]              movzx cx, byte ptr [ebx+5]
  mov [esi+0Ah], cx                       mov [esi+0Ah], cx
  movzx ax, byte ptr [ebx+4]              movzx ax, byte ptr [ebx+4]
  mov [esi+8], ax                         mov [esi+8], ax
  test ax, ax                             test ax, ax
* jnz loc_444D                            jnz loc_46FD
  mov cx, [esi+0Ah]                       mov cx, [esi+0Ah]
  mov [esi+8], cx                         mov [esi+8], cx
  test dl, 1                              test dl, 1
* jz loc_4458                             jnz loc_4708
*                                         mov byte ptr [esi+0Ch], 0Ah
*                                         jmp loc_470C
  mov byte ptr [esi+0Ch], 10h             mov byte ptr [esi+0Ch], 10h
* jmp loc_445C                            cmp ds:_verbose, 0
*                                         jz loc_477F
*                                         jmp loc_4772
*                                         cmp [ebp+arg_10], 9
*                                         jnz loc_477F
*                                         cmp edi, 3
*                                         jz loc_4740
*                                         push edi
*                                         push offset aPnpdeviceresou_10
*                                         call near ptr _IOLog
*                                         mov ecx, ds:paFree
*                                         push ecx
*                                         push esi
*                                         call near ptr _objc_msgSend
*                                         jmp loc_4781
*                                         mov ax, [ebx]
*                                         and ah, 3
*                                         mov [esi+6], ax
*                                         mov [esi+4], ax
*                                         movzx ax, byte ptr [ebx+2]
*                                         mov [esi+0Ah], ax
*                                         mov [esi+8], ax
  mov byte ptr [esi+0Ch], 0Ah             mov byte ptr [esi+0Ch], 0Ah
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_4472                             jz loc_477F
*                                         push offset aFixed
*                                         call near ptr _IOLog
  mov ecx, ds:paPrint                     mov ecx, ds:paPrint
  push ecx                                push ecx
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov eax, esi                            mov eax, esi
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[pnpMemory initFrom:Length:Type:]` early data32 (2026-09-17)

Same early `data32` experiment as the tool. Leftover is type-switch layout and extra flag zeros. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `56457B5FF7AE8D62AA4C9AF8C1FAD048B9D7BFFFBDFF2DD0F38BE1729F319D69` (603536). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[pnpMemory initFrom:Length:Type:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 8                              sub esp, 8
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
* mov esi, [ebp+self]                     mov ebx, [ebp+self]
* mov ebx, [ebp+arg_8]                    mov edi, [ebp+arg_8]
* mov edi, [ebp+arg_10]                   mov edx, ds:paInit
* mov ecx, ds:paInit                      push edx
* push ecx                                mov [ebp+var_8.receiver], ebx
* mov [ebp+var_8.receiver], esi           mov edx, ds:stru_A540.ext
* mov ecx, ds:stru_A534.super_class       mov [ebp+var_8.super_class], edx
* mov [ebp+var_8.super_class], ecx
  lea eax, [ebp+var_8]                    lea eax, [ebp+var_8]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
* mov eax, ebx                            lea esi, [edi+1]
* lea ebx, [eax+1]                        mov byte ptr [ebx+1Bh], 0
* mov byte ptr [esi+1Bh], 0               mov byte ptr [ebx+1Ah], 0
* mov byte ptr [esi+1Ah], 0               mov byte ptr [ebx+19h], 0
* mov byte ptr [esi+19h], 0               mov byte ptr [ebx+1Ch], 0
* mov byte ptr [esi+1Ch], 0               mov byte ptr [ebx+14h], 0
*                                         mov byte ptr [ebx+15h], 0
*                                         mov byte ptr [ebx+18h], 0
  add esp, 8                              add esp, 8
* cmp edi, 5                              cmp [ebp+arg_10], 5
* jz loc_4934                             jnz loc_507C
* jg loc_48BC                             mov byte ptr [ebx+1Ch], 1
* cmp edi, 1                              cmp [ebp+arg_C], 11h
* jz loc_48CC                             jz loc_503C
* jmp loc_49F6                            mov edx, [ebp+arg_C]
* cmp edi, 6                              push edx
* jz loc_498C                             push offset aPnpdeviceresou_11
* jmp loc_49F6                            jmp loc_5101
*                                         movzx eax, byte ptr [edi]
*                                         push eax
*                                         mov edx, ds:paSetcontrol
*                                         push edx
*                                         push ebx
*                                         call near ptr _objc_msgSend
*                                         mov edx, [esi]
*                                         mov [ebx+4], edx
*                                         mov edx, [esi+4]
*                                         mov [ebx+8], edx
*                                         mov edx, [esi+8]
*                                         mov [ebx+0Ch], edx
*                                         mov esi, [esi+0Ch]
*                                         mov [ebx+10h], esi
*                                         add esp, 0Ch
*                                         cmp dword ptr [ebx+0Ch], 0
*                                         jnz loc_515D
*                                         mov [ebx+0Ch], esi
*                                         jmp loc_515D
*                                         cmp [ebp+arg_10], 6
*                                         jnz loc_50EC
*                                         mov byte ptr [ebx+1Ch], 1
  cmp [ebp+arg_C], 9                      cmp [ebp+arg_C], 9
* jz loc_48E0                             jz loc_5098
* mov ecx, [ebp+arg_C]                    mov edx, [ebp+arg_C]
* push ecx                                push edx
* push offset aPnpdeviceresou_1           push offset aPnpdeviceresou_12
* jmp loc_499F                            jmp loc_5101
*                                         movzx eax, byte ptr [edi]
  push eax                                push eax
* mov ecx, ds:paSetcontrol                mov edx, ds:paSetcontrol
* push ecx                                push edx
* push esi                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* mov edx, ebx                            mov edx, [esi]
* movzx eax, word ptr [ebx]               mov [ebx+4], edx
* shl eax, 8                              mov edx, [esi]
* mov [esi+4], eax                        mov [ebx+8], edx
* movzx eax, word ptr [ebx+2]             mov edx, [esi+4]
* shl eax, 8                              mov [ebx+10h], edx
* mov [esi+8], eax                        mov esi, [esi+4]
* movzx eax, word ptr [ebx+4]             mov [ebx+0Ch], esi
* mov [esi+0Ch], eax
  add esp, 0Ch                            add esp, 0Ch
* test eax, eax                           cmp ds:_verbose, 0
* jnz loc_4918                            jz loc_5179
* mov dword ptr [esi+0Ch], 10000h
* movzx eax, word ptr [edx+6]
* shl eax, 8
* mov [esi+10h], eax
* cmp ds:_verbose_0, 0
* jz loc_49F6
* jmp loc_49E9
* mov byte ptr [esi+1Ch], 1
* cmp [ebp+arg_C], 11h
* jz loc_494C
* mov ecx, [ebp+arg_C]
* push ecx
* push offset aPnpdeviceresou_2
* jmp loc_499F
* push eax
* mov ecx, ds:paSetcontrol
* push ecx
* push esi
* call near ptr _objc_msgSend
* mov ecx, [ebx]
* mov [esi+4], ecx
* mov ecx, [ebx+4]
* mov [esi+8], ecx
* mov ecx, [ebx+0Ch]
* mov [esi+10h], ecx
* mov ebx, [ebx+8]
* mov [esi+0Ch], ebx
* add esp, 0Ch
* test ebx, ebx
* jnz loc_497E
* mov ecx, [esi+10h]
* mov [esi+0Ch], ecx
* cmp ds:_verbose_0, 0
* jz loc_49F6
* jmp loc_49E9
* mov byte ptr [esi+1Ch], 1
* cmp [ebp+arg_C], 9
* jz loc_49B4
* mov ecx, [ebp+arg_C]
* push ecx
* push offset aPnpdeviceresou_3
* call near ptr _IOLog
* mov ecx, ds:paFree
* push ecx
* push esi
* call near ptr _objc_msgSend
* jmp loc_49F8
* push eax
* mov ecx, ds:paSetcontrol
* push ecx
* push esi
* call near ptr _objc_msgSend
* mov eax, [ebx]
* mov [esi+8], eax
* mov [esi+4], eax
* mov ebx, [ebx+4]
* mov [esi+10h], ebx
* mov [esi+0Ch], ebx
* add esp, 0Ch
* cmp ds:_verbose_0, 0
* jz loc_49F6
  push offset aFixed                      push offset aFixed
  call near ptr _IOLog                    call near ptr _IOLog
* mov ecx, ds:paPrint                     mov edx, ds:paPrint
* push ecx                                push edx
* push esi                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* mov eax, esi                            add esp, 0Ch
*                                         jmp loc_515D
*                                         cmp [ebp+arg_10], 1
*                                         jnz loc_515D
*                                         cmp [ebp+arg_C], 9
*                                         jz loc_5118
*                                         mov edx, [ebp+arg_C]
*                                         push edx
*                                         push offset aPnpdeviceresou_13
*                                         call near ptr _IOLog
*                                         mov edx, ds:paFree
*                                         push edx
*                                         push ebx
*                                         call near ptr _objc_msgSend
*                                         jmp loc_517B
*                                         movzx eax, byte ptr [edi]
*                                         push eax
*                                         mov edx, ds:paSetcontrol
*                                         push edx
*                                         push ebx
*                                         call near ptr _objc_msgSend
*                                         movzx eax, word ptr [esi]
*                                         shl eax, 8
*                                         mov [ebx+4], eax
*                                         movzx eax, word ptr [esi+2]
*                                         shl eax, 8
*                                         mov [ebx+8], eax
*                                         movzx edx, word ptr [esi+4]
*                                         mov [ebx+0Ch], edx
*                                         movzx eax, word ptr [esi+6]
*                                         shl eax, 8
*                                         mov [ebx+10h], eax
*                                         add esp, 0Ch
*                                         cmp dword ptr [ebx+0Ch], 0
*                                         jnz loc_515D
*                                         mov dword ptr [ebx+0Ch], 10000h
*                                         cmp ds:_verbose, 0
*                                         jz loc_5179
*                                         cmp [ebp+arg_10], 6
*                                         jz loc_5179
*                                         mov edx, ds:paPrint
*                                         push edx
*                                         push ebx
*                                         call near ptr _objc_msgSend
*                                         mov eax, ebx
  lea esp, [ebp-14h]                      lea esp, [ebp-14h]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[PnPDeviceResources initForBuf:Length:CSN:]` header locals (2026-09-17)

Same header-local reorder as the tool. Leftover is Apple's byte-copy ID loop versus shift-or. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `8D19FE9A6A75FA0D1CDF13C706E8CF1C2734BFC33699C395AB03E1232B9A94C7` (603536). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[PnPDeviceResources initForBuf:Length:CSN:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 1Ch                            sub esp, 20h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
* mov ebx, [ebp+self]                     mov edi, [ebp+arg_8]
* mov esi, [ebp+arg_8]
* mov edi, [ebp+arg_C]
  mov ecx, ds:paInit                      mov ecx, ds:paInit
  push ecx                                push ecx
*                                         mov ebx, [ebp+self]
  mov [ebp+var_14.receiver], ebx          mov [ebp+var_14.receiver], ebx
* mov ecx, ds:stru_A444.ext               mov ecx, ds:stru_A4A0.super_class
  mov [ebp+var_14.super_class], ecx       mov [ebp+var_14.super_class], ecx
  lea eax, [ebp+var_14]                   lea eax, [ebp+var_14]
  push eax                                push eax
  call near ptr _objc_msgSendSuper        call near ptr _objc_msgSendSuper
  add esp, 8                              add esp, 8
* cmp edi, 8                              cmp [ebp+arg_C], 8
* ja loc_6A94                             jg loc_36E8
  push 9                                  push 9
* push edi                                mov ebx, [ebp+arg_C]
* push offset aPnpdeviceresou_12          push ebx
*                                         push offset aPnpdeviceresou
  call near ptr _IOLog                    call near ptr _IOLog
  xor eax, eax                            xor eax, eax
* jmp loc_6BCF                            jmp loc_3830
* mov [ebp+var_1C], esi                   mov dl, [edi+3]
* lea edx, [ebp+var_15]                   shl edx, 18h
* mov eax, 3                              movzx eax, byte ptr [edi+2]
* nop                                     shl eax, 10h
* mov ecx, [ebp+var_1C]                   or edx, eax
* mov cl, [ecx]                           movzx eax, byte ptr [edi+1]
* mov [edx], cl                           shl eax, 8
* inc [ebp+var_1C]                        or edx, eax
* dec edx                                 movzx eax, byte ptr [edi]
* dec eax                                 or edx, eax
* cmp eax, 0FFFFFFFFh                     mov ebx, [ebp+arg_10]
* jnz loc_6AA0                            mov ecx, [ebp+self]
* mov ecx, [ebp+arg_10]                   mov [ecx+64h], ebx
* mov [ebx+64h], ecx                      push edx
* mov ecx, [ebp-18h]
* push ecx
  mov ecx, ds:paSetid                     mov ecx, ds:paSetid
  push ecx                                push ecx
*                                         mov ebx, [ebp+self]
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* mov ecx, [esi+4]                        mov ecx, [edi+4]
*                                         mov [ebp+var_18], ecx
  push ecx                                push ecx
* mov ecx, ds:paSetserialnumbe            mov ebx, ds:paSetserialnumbe
*                                         push ebx
*                                         mov ecx, [ebp+self]
  push ecx                                push ecx
*                                         call near ptr _objc_msgSend
*                                         add esp, 18h
*                                         cmp ds:_verbose, 0
*                                         jz loc_37B3
*                                         mov bl, [edi+8]
*                                         mov [ebp+var_1C], bl
*                                         mov ecx, ds:paId
*                                         push ecx
*                                         mov ebx, [ebp+self]
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 18h                            mov esi, eax
* cmp ds:_verbose_0, 1                    shr eax, 1Ah
* jnz loc_6B6E                            and al, 1Fh
* movzx eax, byte ptr [esi+8]             add al, 40h
*                                         mov [ebp+var_C], al
*                                         mov eax, esi
*                                         shr eax, 15h
*                                         and al, 1Fh
*                                         add al, 40h
*                                         mov [ebp+var_B], al
*                                         mov eax, esi
*                                         shr eax, 10h
*                                         and al, 1Fh
*                                         add al, 40h
*                                         mov [ebp+var_A], al
*                                         movzx eax, si
  push eax                                push eax
* mov ecx, ds:paSerialnumber              push offset a04x
*                                         lea ecx, [ebp+var_C]
*                                         mov [ebp+var_20], ecx
*                                         lea eax, [ebp+var_9]
*                                         push eax
*                                         call near ptr _sprintf
*                                         mov [ebp+var_5], 0
*                                         movzx eax, [ebp+var_1C]
*                                         push eax
*                                         mov ebx, [ebp+var_18]
*                                         push ebx
*                                         push esi
*                                         mov ecx, [ebp+var_20]
  push ecx                                push ecx
*                                         push offset aVendorIdS0xLxS
*                                         call near ptr _IOLog
*                                         add esp, 28h
*                                         mov ebx, ds:paInit
*                                         push ebx
*                                         mov ecx, ds:paAlloc
*                                         push ecx
*                                         mov ebx, ds:paList
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
* mov ecx, ds:paId
* push ecx
* push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              mov ecx, [ebp+self]
* push eax                                mov [ecx+4], eax
* mov ecx, ds:paId
* push ecx
* push ebx
* call near ptr _objc_msgSend
* add esp, 8
* mov edx, eax
* shr eax, 1Ah
* and al, 1Fh
* add al, 40h
* mov [ebp+var_C], al
* mov eax, edx
* shr eax, 15h
* and al, 1Fh
* add al, 40h
* mov [ebp+var_B], al
* mov eax, edx
* shr eax, 10h
* and al, 1Fh
* add al, 40h
* mov [ebp+var_A], al
* movzx eax, dx
* push eax
* push offset a04x
* lea eax, [ebp+var_9]
* push eax
* call near ptr _sprintf
* mov [ebp+var_5], 0
* lea eax, [ebp+var_C]
* add esp, 0Ch
* push eax
* push offset aVendorIdS0xLxS
* call near ptr _IOLog
* add esp, 14h
* mov ecx, ds:paInit
* push ecx
* mov ecx, ds:paAlloc
* push ecx
* mov ecx, ds:paList
* push ecx
* call near ptr _objc_msgSend
* add esp, 8
* push eax
* call near ptr _objc_msgSend
* mov [ebx+4], eax
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_6BB8                             jnz loc_37FC
* push edi                                push offset aPnpdeviceresou_0
* lea eax, [esi+9]                        call near ptr _IOLog
*                                         mov ebx, ds:paFree
*                                         push ebx
*                                         mov ecx, [ebp+self]
*                                         push ecx
*                                         jmp loc_382B
*                                         mov ebx, [ebp+arg_C]
*                                         push ebx
*                                         lea eax, [edi+9]
  push eax                                push eax
  mov ecx, ds:paParseconfigLen            mov ecx, ds:paParseconfigLen
  push ecx                                push ecx
*                                         mov ebx, [ebp+self]
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 10h                            add esp, 10h
* test al, al                             test eax, eax
* jz loc_6BC2                             jz loc_3820
* mov eax, ebx                            mov eax, [ebp+self]
* jmp loc_6BCF                            jmp loc_3830
* push offset aPnpdeviceresou_13
* call near ptr _IOLog
  mov ecx, ds:paFree                      mov ecx, ds:paFree
  push ecx                                push ecx
*                                         mov ebx, [ebp+self]
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* lea esp, [ebp-28h]                      lea esp, [ebp-2Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

### Task 6 `-[PnPResources initFromRegisters:]` do-while walks (2026-09-17)

Same do-while register walks as the tool. Leftover is verbose / selector PIC. Accepted compiler-shaped leftover (reviewer Pat Raynor). Reloc SHA `1CF72ADC5E1827867389CB5D7B90780D14BAF9E74E1D926F750B49D4E20542D4` (603536). Previously identical rows stayed matched (46). Unpaired count unchanged (11). Kernel-only reloc statuses were not reopened.

```
-[PnPResources initFromRegisters:]
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt                               
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
  sub esp, 10h                            sub esp, 10h
  push edi                                push edi
  push esi                                push esi
  push ebx                                push ebx
  mov ecx, ds:paInit                      mov ecx, ds:paInit
  push ecx                                push ecx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jnz loc_548C                            jnz loc_5F98
  xor eax, eax                            xor eax, eax
* jmp loc_5857                            jmp loc_6358
  mov ecx, ds:paFree                      mov ecx, ds:paFree
  push ecx                                push ecx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* jmp loc_5857                            jmp loc_6358
  xor edi, edi                            xor edi, edi
  nop                                     nop
  nop                                     nop
  lea eax, [edi+edi]                      lea eax, [edi+edi]
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov dl, [eax+ecx+38h]                   mov dl, [eax+ecx+38h]
  shl dx, 8                               shl dx, 8
  movzx ax, byte ptr [eax+ecx+39h]        movzx ax, byte ptr [eax+ecx+39h]
  or ax, dx                               or ax, dx
* jz loc_550A                             jz loc_6016
  push 0                                  push 0
  and eax, 0FFFFh                         and eax, 0FFFFh
  push eax                                push eax
* mov esi, ds:paInitwithbaseLe_0          mov esi, ds:paInitwithbaseLe
  push esi                                push esi
  mov ecx, ds:paAlloc                     mov ecx, ds:paAlloc
  push ecx                                push ecx
  mov esi, ds:paPnpioport                 mov esi, ds:paPnpioport
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 10h                            add esp, 10h
  test ebx, ebx                           test ebx, ebx
* jz loc_5474                             jz loc_5F80
  push ebx                                push ebx
  mov ecx, ds:paAddioport                 mov ecx, ds:paAddioport
  push ecx                                push ecx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_550A                             jz loc_6016
  mov ecx, ds:paPrint                     mov ecx, ds:paPrint
  push ecx                                push ecx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  inc edi                                 inc edi
  cmp edi, 7                              cmp edi, 7
* jle loc_5490                            jle loc_5F9C
  xor edi, edi                            xor edi, edi
  nop                                     nop
  nop                                     nop
  mov esi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
  mov bl, [esi+edi*2+48h]                 mov bl, [esi+edi*2+48h]
  cmp bl, 2                               cmp bl, 2
* jnz loc_5522                            jnz loc_602E
  mov bl, 9                               mov bl, 9
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
  mov cl, [ecx+edi*2+49h]                 mov cl, [ecx+edi*2+49h]
  mov [ebp+var_4], cl                     mov [ebp+var_4], cl
  test bl, bl                             test bl, bl
* jz loc_55C4                             jz loc_60D0
  mov esi, ds:paInit                      mov esi, ds:paInit
  push esi                                push esi
  mov ecx, ds:paAlloc                     mov ecx, ds:paAlloc
  push ecx                                push ecx
  mov esi, ds:paPnpirq                    mov esi, ds:paPnpirq
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov [ebp+var_10], eax                   mov [ebp+var_10], eax
  add esp, 8                              add esp, 8
  test eax, eax                           test eax, eax
* jz loc_5474                             jz loc_5F80
  movzx eax, bl                           movzx eax, bl
  push eax                                push eax
  mov ecx, ds:paAddtoirqlist              mov ecx, ds:paAddtoirqlist
  push ecx                                push ecx
  mov esi, [ebp+var_10]                   mov esi, [ebp+var_10]
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov al, [ebp+var_4]                     mov al, [ebp+var_4]
  and eax, 1                              and eax, 1
  push eax                                push eax
  mov al, [ebp+var_4]                     mov al, [ebp+var_4]
  and eax, 2                              and eax, 2
  push eax                                push eax
  mov ecx, ds:paSethighLevel              mov ecx, ds:paSethighLevel
  push ecx                                push ecx
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push esi                                push esi
  mov esi, ds:paAddirq                    mov esi, ds:paAddirq
  push esi                                push esi
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  push ecx                                push ecx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 28h                            add esp, 28h
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_55C4                             jz loc_60D0
  mov esi, ds:paPrint                     mov esi, ds:paPrint
  push esi                                push esi
  mov ecx, [ebp+var_10]                   mov ecx, [ebp+var_10]
  push ecx                                push ecx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  inc edi                                 inc edi
  cmp edi, 1                              cmp edi, 1
* jle loc_5514                            jle loc_6020
  xor edi, edi                            xor edi, edi
  mov ecx, [ebp+arg_8]                    mov ecx, [ebp+arg_8]
* mov cl, [edi+ecx+4Ch]                   mov cl, [ecx+edi*2+4Ch]
  mov [ebp+var_8], cl                     mov [ebp+var_8], cl
  cmp cl, 4                               cmp cl, 4
* jz loc_564E                             jz loc_615A
  mov esi, ds:paInit                      mov esi, ds:paInit
  push esi                                push esi
  mov ecx, ds:paAlloc                     mov ecx, ds:paAlloc
  push ecx                                push ecx
  mov esi, ds:paPnpdma                    mov esi, ds:paPnpdma
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 8                              add esp, 8
  test ebx, ebx                           test ebx, ebx
* jz loc_5474                             jz loc_5F80
  movzx eax, [ebp+var_8]                  movzx eax, [ebp+var_8]
  push eax                                push eax
  mov ecx, ds:paAdddmatolist              mov ecx, ds:paAdddmatolist
  push ecx                                push ecx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  push ebx                                push ebx
  mov esi, ds:paAdddma                    mov esi, ds:paAdddma
  push esi                                push esi
  mov ecx, [ebp+self]                     mov ecx, [ebp+self]
  push ecx                                push ecx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 18h                            add esp, 18h
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_564E                             jz loc_615A
  mov esi, ds:paPrint                     mov esi, ds:paPrint
  push esi                                push esi
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  inc edi                                 inc edi
  cmp edi, 1                              cmp edi, 1
* jle loc_55D0                            jle loc_60DC
  xor edi, edi                            xor edi, edi
  nop                                     nop
  nop                                     nop
  lea ecx, [edi+edi*4]                    lea ecx, [edi+edi*4]
  mov [ebp+var_C], ecx                    mov [ebp+var_C], ecx
  mov esi, [ebp+arg_8]                    mov esi, [ebp+arg_8]
  movzx edx, byte ptr [ecx+esi]           movzx edx, byte ptr [ecx+esi]
  shl edx, 10h                            shl edx, 10h
  movzx eax, byte ptr [ecx+esi+1]         movzx eax, byte ptr [ecx+esi+1]
  shl eax, 8                              shl eax, 8
  or edx, eax                             or edx, eax
  mov [ebp+var_10], edx                   mov [ebp+var_10], edx
* jz loc_5727                             jz loc_622F
* mov bl, [ecx+esi+2]                     movzx ebx, byte ptr [ecx+esi+2]
  movzx edx, byte ptr [ecx+esi+3]         movzx edx, byte ptr [ecx+esi+3]
  shl edx, 10h                            shl edx, 10h
  movzx eax, byte ptr [ecx+esi+4]         movzx eax, byte ptr [ecx+esi+4]
  shl eax, 8                              shl eax, 8
  or eax, edx                             or eax, edx
  xor edx, edx                            xor edx, edx
  test eax, eax                           test eax, eax
* jz loc_56B5                             jz loc_61BD
  test bl, 1                              test bl, 1
* jz loc_56A8                             jnz loc_61B8
*                                         mov edx, eax
*                                         xor edx, 0FFFFFFh
*                                         inc edx
*                                         jmp loc_61BD
  mov edx, eax                            mov edx, eax
  sub edx, [ebp+var_10]                   sub edx, [ebp+var_10]
* jmp loc_56B5
* and eax, 0FFFFFFh
* xor eax, 0FFFFFFh
* lea edx, [eax+1]
  push 0                                  push 0
  mov eax, ebx                            mov eax, ebx
  and eax, 1                              and eax, 1
  push eax                                push eax
  push 0                                  push 0
  mov eax, ebx                            mov eax, ebx
  and eax, 2                              and eax, 2
  push eax                                push eax
  push edx                                push edx
  mov ecx, [ebp+var_10]                   mov ecx, [ebp+var_10]
  push ecx                                push ecx
* mov esi, ds:paInitwithbaseLe            mov esi, ds:paInitwithbaseLe_0
  push esi                                push esi
  mov ecx, ds:paAlloc                     mov ecx, ds:paAlloc
  push ecx                                push ecx
  mov esi, ds:paPnpmemory                 mov esi, ds:paPnpmemory
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  test ebx, ebx                           test ebx, ebx
* jz loc_5474                             jz loc_5F80
  push ebx                                push ebx
  mov ecx, ds:paAddmemory                 mov ecx, ds:paAddmemory
  push ecx                                push ecx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_5727                             jz loc_622F
  mov ecx, ds:paPrint                     mov ecx, ds:paPrint
  push ecx                                push ecx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  inc edi                                 inc edi
  cmp edi, 3                              cmp edi, 3
* jle loc_565C                            jle loc_6168
*                                         mov esi, ds:paList_0
*                                         push esi
*                                         mov ecx, [ebp+self]
*                                         mov ecx, [ecx+10h]
*                                         push ecx
*                                         call near ptr _objc_msgSend
  mov esi, ds:paCount                     mov esi, ds:paCount
  push esi                                push esi
* mov ecx, ds:paList_0
* push ecx
* mov esi, [ebp+self]
* mov esi, [esi+10h]
* push esi
* call near ptr _objc_msgSend
* add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
* add esp, 8                              add esp, 10h
  test eax, eax                           test eax, eax
* jnz loc_5854                            jnz loc_6355
  xor edi, edi                            xor edi, edi
  nop                                     nop
  nop                                     nop
* nop                                     lea ecx, [edi+edi*8]
* lea ebx, [edi+edi*8]                    mov [ebp+var_C], ecx
* mov ecx, [ebp+arg_8]                    mov esi, [ebp+arg_8]
* mov dl, [ebx+ecx+14h]                   mov dl, [ecx+esi+14h]
  shl edx, 18h                            shl edx, 18h
* movzx eax, byte ptr [ebx+ecx+15h]       movzx eax, byte ptr [ecx+esi+15h]
  shl eax, 10h                            shl eax, 10h
  or edx, eax                             or edx, eax
* movzx eax, byte ptr [ebx+ecx+16h]       movzx eax, byte ptr [ecx+esi+16h]
  shl eax, 8                              shl eax, 8
  or edx, eax                             or edx, eax
* movzx eax, byte ptr [ebx+ecx+17h]       movzx eax, byte ptr [ecx+esi+17h]
  or edx, eax                             or edx, eax
  mov [ebp+var_10], edx                   mov [ebp+var_10], edx
* jz loc_584A                             jz loc_634B
* mov dl, [ebx+ecx+18h]                   movzx ebx, byte ptr [ecx+esi+18h]
* mov cl, [ebx+ecx+19h]                   mov dl, [ecx+esi+19h]
* shl ecx, 18h                            shl edx, 18h
* mov esi, [ebp+arg_8]                    movzx eax, byte ptr [ecx+esi+1Ah]
* movzx eax, byte ptr [ebx+esi+1Ah]
  shl eax, 10h                            shl eax, 10h
* or ecx, eax                             or edx, eax
* movzx eax, byte ptr [ebx+esi+1Bh]       movzx eax, byte ptr [ecx+esi+1Bh]
  shl eax, 8                              shl eax, 8
* or ecx, eax                             or edx, eax
* movzx eax, byte ptr [ebx+esi+1Ch]       movzx eax, byte ptr [ecx+esi+1Ch]
* or ecx, eax                             or eax, edx
* mov [ebp+var_C], ecx                    xor edx, edx
* xor ebx, ebx                            test eax, eax
* test ecx, ecx                           jz loc_62DD
* jz loc_57DC                             test bl, 1
* test dl, 1                              jnz loc_62D8
* jz loc_57D4                             mov edx, eax
* mov ebx, ecx                            not edx
* sub ebx, [ebp+var_10]                   inc edx
* jmp loc_57DC                            jmp loc_62DD
* mov eax, [ebp+var_C]                    mov edx, eax
* not eax                                 sub edx, [ebp+var_10]
* lea ebx, [eax+1]
  push 1                                  push 1
* mov eax, edx                            mov eax, ebx
  and eax, 1                              and eax, 1
  push eax                                push eax
* mov eax, edx                            mov eax, ebx
  and eax, 4                              and eax, 4
  push eax                                push eax
* mov eax, edx                            mov eax, ebx
  and eax, 2                              and eax, 2
  push eax                                push eax
* push ebx                                push edx
  mov ecx, [ebp+var_10]                   mov ecx, [ebp+var_10]
  push ecx                                push ecx
* mov esi, ds:paInitwithbaseLe            mov esi, ds:paInitwithbaseLe_0
  push esi                                push esi
  mov ecx, ds:paAlloc                     mov ecx, ds:paAlloc
  push ecx                                push ecx
  mov esi, ds:paPnpmemory                 mov esi, ds:paPnpmemory
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  push eax                                push eax
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  mov ebx, eax                            mov ebx, eax
  add esp, 20h                            add esp, 20h
  push ebx                                push ebx
  mov ecx, ds:paAddmemory                 mov ecx, ds:paAddmemory
  push ecx                                push ecx
  mov esi, [ebp+self]                     mov esi, [ebp+self]
  push esi                                push esi
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 0Ch                            add esp, 0Ch
* cmp ds:_verbose_0, 0                    cmp ds:_verbose, 0
* jz loc_584A                             jz loc_634B
  mov ecx, ds:paPrint                     mov ecx, ds:paPrint
  push ecx                                push ecx
  push ebx                                push ebx
  call near ptr _objc_msgSend             call near ptr _objc_msgSend
  add esp, 8                              add esp, 8
  inc edi                                 inc edi
  cmp edi, 3                              cmp edi, 3
* jle loc_5764                            jle loc_6268
  mov eax, [ebp+self]                     mov eax, [ebp+self]
  lea esp, [ebp-1Ch]                      lea esp, [ebp-1Ch]
  pop ebx                                 pop ebx
  pop esi                                 pop esi
  pop edi                                 pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```
