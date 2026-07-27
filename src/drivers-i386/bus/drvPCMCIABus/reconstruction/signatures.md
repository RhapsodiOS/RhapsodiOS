# drvPCMCIABus signature divergences against the DR2 reference

Scope: the Objective-C **interface** of `PCMCIAKernBus` and its `(Private)` and
`(Parsing)` categories as declared in `PCMCIABus.drvproj/PCMCIABus.lksproj/` —
method type encodings and ivar layout — compared against Apple's shipped driver.

Companion to `divergences.md` in this directory, which covers the *implementation*
at function level and is backed by `ledger.json`, `source-map.json` and a clean
build. The two are complementary: that pass explicitly deprioritised the large
`PCMCIAKernBus(Private)` methods and left
`-[PCMCIAKernBus statusChangedForSocket:changedStatus:]` unexamined, which is
where most of this record's findings sit.

Two findings were reached independently by both passes and agree: the dead
`parseTuple:` stub (Finding 8 here) and the broken ready-check in
`waitForSocketReady` (recorded here, fixed there). Where the two records state a
signature differently, this one is derived directly from `__meth_var_types` and
should be preferred.

## Reference

| | |
| --- | --- |
| Binary | `Drivers/i386/PCMCIABus.config/PCMCIABus_reloc` |
| Format | Mach-O i386 preload executable, 92192 bytes |
| SHA-256 | `b0d8a35e4c55dd7df2f77b7f8bc07a453d843c24814b874c47b737b3425607ed` |

A second image is cited for Finding 1, because the type in question is shared
across the two drivers:

| | |
| --- | --- |
| Binary | `Drivers/i386/PCIC.config/PCIC_reloc` |
| SHA-256 | `80360707448af7e4e100ce24993e0728f5ddc688d1d31da5161478b0bcc3a208` |

Evidence was read directly out of the images: `__OBJC,__module_info` at `0xc55c`
(eleven modules for `PCMCIABus_reloc`), each `objc_symtab` walked to its class
and category defs, then each method list read for `method_name` /
`method_types` and each `objc_ivar_list` for `ivar_name` / `ivar_type` /
`ivar_offset`. The type strings quoted below are the literal metadata bytes.

The reference's eleven modules are `PCMCIAid.m`, `PCMCIAKernBus.m`,
`PCMCIAKernBusParsing.m`, `PCMCIAPool.m`, `PCMCIAResourceDriver.m`,
`PCMCIATuple.m`, `TuplesLayer1.m` through `TuplesLayer4.m`, and
`PCMCIABus_instance.m`. Our file decomposition differs: Apple has no
`PCMCIAKernBusPrivate.m` — the `(Private)` category is compiled into
`PCMCIAKernBus.m` — and splits tuple parsing across four `TuplesLayerN.m` files
where we have `PCMCIATupleTypes.m`. Nothing below turns on this; it is recorded
because a future source-map pass has to reconcile it.

**No build was performed and nothing here is compile-checked.** A build route
does exist — `vm/build-i386-bus-drivers.sh` builds this driver inside the
Rhapsody guest — but it was not exercised in this pass: no guest was running and
booting one was out of scope. Compiling these changes is the first thing the
next session with a live guest should do.

This document does not carry a `ledger.json` or `source-map.json`. Those require
a `binrecon` per-function analyzer pass that was not run here.

Related: `src/driverkit-3/libDriver/reconstruction/divergences.md` reported the
26 methods of the two public kernel headers declared in commit 99a55c1b, and
noted Finding 1 below without changing it. That report covers only the public
kernel interface; the `(Private)` and `(Parsing)` categories recorded here were
never compared before this pass, which is why Findings 2-8 are new. Both that
commit and that report currently live on the `qemu-debug-loop` branch, which is
ahead of this one — the cross-reference resolves once this branch merges forward.

## Finding 1 — `statusChangedForSocket:changedStatus:` takes a bitfield: **fixed**

> **Resolved.** The deferral below stood while `PCMCIAStatus` did not exist. It
> does now, and the reference's own implementation has since been disassembled,
> which settled the one thing the record said was unmeasured. See
> § The reconciling pass at the end of this finding. The original reasoning is
> kept because it explains why the change waited.


| | |
| --- | --- |
| Reference | `v16@8:12@16{?=b1b1b1b1b2b1b1}20` at `0xfe0` |
| Ours | `- (void)statusChangedForSocket:socket changedStatus:(unsigned int)status` |
| Sites | `PCMCIAKernBus.h:132`, `PCMCIAKernBus.m:690` |

Apple's third parameter is an eight-bit anonymous bitfield passed by value, not
an integer mask. `PCMCIABus_reloc` gives the layout but not the field names;
`PCIC_reloc` gives both, because `PCICSocket` stores one as an ivar and its
`ivar_type` carries the names:

```
+12 {?="present"b1"locked"b1"ejectRequest"b1"insertRequest"b1"batteryStatus"b2"writeProtect"b1"ready"b1} statusMask
```

so the shared type is:

```c
typedef struct {
    unsigned int present       : 1;
    unsigned int locked        : 1;
    unsigned int ejectRequest  : 1;
    unsigned int insertRequest : 1;
    unsigned int batteryStatus : 2;
    unsigned int writeProtect  : 1;
    unsigned int ready         : 1;
} PCMCIAStatus;
```

No such type exists anywhere in our tree. Our stack is internally consistent —
the 82365 driver's `PCMCIAStatusChange` protocol also declares
`(unsigned int)status` (`Intel82365PCMCIA/.../PCIC.h:47`), matching our
`PCMCIAKernBus.h:59` — so nothing is broken today, but both sides diverge from
Apple's.

> **Both halves of that paragraph have since stopped being true, which is the
> reason to revisit this finding.**
>
> `PCMCIAStatus` now exists, in `<driverkit/i386/PCMCIA.h>`, declared with the
> four PCMCIA protocols recovered from `PCIC_reloc`. And the 82365 driver no
> longer declares `(unsigned int)status`: its invented `PCMCIAStatusChange` was
> deleted, and `PCICSocket` now adopts the real `PCMCIASocket`, whose `status`,
> `statusChangeMask` and `setStatusChangeMask:` all carry
> `{?=b1b1b1b1b2b1b1}` — verified byte-identical to the reference in a rebuilt
> `PCIC_reloc`.
>
> So the stack is no longer internally consistent: `PCICSocket` takes the
> bitfield and `PCMCIAKernBus` still passes an integer. `PCMCIAKernBus.m:607`'s
> `[socket setStatusChangeMask:1]` happens to survive only because the receiver
> is an untyped `id` and a four-byte struct occupies the same stack slot as the
> `int` — it is right by coincidence, not by type.
>
> The deferral's other reason — a coordinated change across three classes —
> still stands, and the work is still not done here. What it now needs is the
> mechanical part: `changedStatus`'s two declarations and its implementation,
> the `(changedStatus & 1)` test that reads bit 0 (`present`), and the two call
> sites that pass a literal `1`. Before changing the test, disassemble
> `-[PCMCIAKernBus statusChangedForSocket:changedStatus:]` at `0xfe0` in
> `PCMCIABus_reloc` and confirm the reference tests `present` rather than some
> other bit — the field mapping is known, but which field this method reads
> is not, in this record, measured.

### The reconciling pass

**The reference tests `present`, measured.** At `0xfe0 + 0x1c`:

```
f6 45 14 01    test byte ptr [ebp + 0x14], 1
0f 85 aa 00..  jne  0x10b0
```

`[ebp+0x14]` is the third argument — `changedStatus` — and the mask is bit 0,
which the ivar-type names give as `present`. Our build did test the same bit,
but through the type: `mov ecx, [ebp+0x14]` then `test cl, 1`, a dword load
because the parameter was an `unsigned int`. The reference tests the byte in
memory directly.

Our build also spilled `socketNum` to `[ebp-4]` where the reference keeps it in
`eax`, most likely because that dword load needed the register.

**`sizeof(PCMCIAStatus)` is 4, and ours already agrees.** Worth recording
because the reference's logging path reads it a byte at a time, which invites
the opposite conclusion. `PCICSocket` stores one as an ivar, and the two
binaries' layouts are identical — `instance_size` 20, `statusMask` at +12,
`windows` at +16. A one-byte struct would have put `windows` at +13.

**Changed**, in `PCMCIAKernBus.h` and `PCMCIAKernBus.m`:

- the `PCMCIAStatusChange` protocol declaration, which also lacked its `(void)`
  return — the reference encoding is `v16@8:12@16{?=b1b1b1b1b2b1b1}20`
- the matching class declaration and the implementation's signature
- `(changedStatus & 1) == 0` → `!changedStatus.present`
- both call sites in `addAdapter:`, via a local `PCMCIAStatus cardPresent = { 1 }`

The reference pushes a literal `1` at both call sites, so Apple's source also
had a constant whose four bytes are `present` alone; `{ 1 }` initialises the
first bitfield and zeroes the rest, giving the same value.

**Predictions this pass made, and how they came out** in a rebuilt
`PCMCIABus_reloc` (349164 bytes, 2026-07-26 19:26):

| Prediction | Result |
| --- | --- |
| encoding becomes `v16@8:12@16{?=b1b1b1b1b2b1b1}20` | **held** — the `PCMCIAStatusChange` record is now identical to the reference's, selector and type both |
| the test becomes the reference's instruction | **held** — `f6 45 14 01`, byte-identical, at the same position in the prologue |
| the `socketNum` spill disappears | **failed** — it is still there, and the frame grew from `sub esp, 0x14` to `0x18` |
| both call sites emit `push 1` | **held** — twice in `addAdapter:`, with the same surrounding instruction sequences |

Both protocol records now match, and `__OBJC,__protocol` lists them in the
reference's order, which the `PCMCIAAdapter` change corrected as a side effect.

**Why the spill prediction failed, now measured rather than guessed.** It was
never about the parameter's type. Before the verbose `IOLog`, the reference
*re-sends* `socketNumber`:

```
0f b6 55 fc    movzx edx, byte ptr [ebp - 4]     ; currentStatus
0f b6 55 14    movzx edx, byte ptr [ebp + 0x14]  ; changedStatus
8b 35 ..       mov esi, [selector socketNumber]
e8 ..          call objc_msgSend                 ; socket number again
50             push eax
```

where ours pushes a cached `[ebp - 8]`. Our source assigns
`socketNum = [socket socketNumber]` once at the top and reuses it across four
logging sites; Apple's sends the message afresh each time. That local is what
occupies the stack slot, so the spill is a consequence of the caching, not of
this finding's change. It is the same construct as the 82365 driver's Finding
19, which was examined and accepted there.

The frame growing by four bytes is a second-order effect of the same area and
was not chased further; it is confined to a `_verbose` path.

**One divergence found here and left open.** In the verbose logging path the
reference zero-extends a *single byte* of each status:

```
0f b6 55 fc    movzx edx, byte ptr [ebp - 4]    ; currentStatus
0f b6 55 14    movzx edx, byte ptr [ebp + 0x14] ; changedStatus
```

Ours passes the values whole — the rebuild confirms it, pushing `changedStatus`
as `mov ecx, [ebp + 0x14]` against the reference's `movzx`. Since the struct is
four bytes, `movzx` from a byte means Apple's source narrowed both at the call —
a cast, or byte-typed locals. Which of those it was is not recoverable from the
encoding, and the path is `_verbose`-only, so nothing was invented to match it.
`currentStatus` is also still an `unsigned int` here, assigned from
`[socket status]` through an untyped receiver; the reference's
`-[PCICSocket status]` returns the bitfield.

Three loose ends therefore remain in this one logging path, all of them
cosmetic and all `_verbose`-gated: the byte-versus-dword width above, the
`socketNum` caching, and `currentStatus`'s type. They are worth doing together
or not at all, since each moves the same stack frame.

### The loose-ends pass

All three are closed. `currentStatus` had already become a `PCMCIAStatus` in
commit `2d41c7e9`; the other two are done here.

**`socketNum`'s caching is gone.** Counting selector sends over each method's
true extent — bounded by the next function prologue, not the next Objective-C
method, which otherwise swallows intervening static functions and inflates the
count — the reference sends `socketNumber` **five** times and ours sent it once:

| Selector | Reference | Before | After |
| --- | --- | --- | --- |
| `socketNumber` | 5 | 1 | 5 |

Five is exactly the number of places the number is used, so Apple's source
re-sends at each rather than caching. The local is deleted and each of the five
`IOLog` sites now sends `[socket socketNumber]` inline. Argument order supports
this reading: the reference pushes `currentStatus`, then `changedStatus`, then
*calls* `socketNumber` and pushes its result — right-to-left evaluation with the
socket number as the leftmost argument, which is what an inline send produces.

**The logged widths are bytes.** `*(unsigned int *)&` on both status values
became `*(unsigned char *)&`, to match the reference's
`movzx edx, byte ptr` rather than a dword push.

**Two choices this pass left alone were checked against the reference and are
correct as they stand.** Immediately after the log the reference does:

```
8b 75 fc       mov esi, dword ptr [ebp - 4]     ; currentStatus
89 37          mov dword ptr [edi], esi         ; socketInfo->status = it
f6 45 fc 01    test byte ptr [ebp - 4], 1       ; currentStatus.present
```

a **dword** store and a **byte** test — which `socketInfo->status =
*(unsigned int *)&currentStatus` and `!currentStatus.present` already produce.

### Two divergences this pass uncovered, both out of its scope

Counting sends over the true extents left exactly two selector differences
besides `socketNumber`:

| Selector | Reference | Ours |
| --- | --- | --- |
| `status` | 1 | 2 |
| `freeObjects` / `freeObjects:` | `freeObjects` ×1 | `freeObjects:` ×1 |

**`status` twice** is not a defect introduced here. The second send is at +1048,
in a wait loop, and reads `test al, al` / `jl` — a sign-bit test, which is bit 7,
`ready`. That is the explicit ready-bit test added deliberately in commit
`b611dee9` under Finding 5 of `divergences.md`. The reference reaches the same
check without a second `status` send, so how it observes readiness is worth
settling, but it belongs to Finding 5 and was not touched.

**`freeObjects` versus `freeObjects:`** is a plain selector mismatch: the
reference sends the no-argument `freeObjects`, ours sends
`freeObjects:@selector(free)`. One line, in the card-removal path. Not
investigated here.

### Verification of the loose-ends pass

Measured in a rebuilt `PCMCIABus_reloc` (349192 bytes, 2026-07-26 23:38 — 28
bytes larger than before, as an edit of this kind should be). All four
predictions held:

| Prediction | Reference | Rebuilt |
| --- | --- | --- |
| `socketNumber` sent five times | 5 | 5 |
| two `movzx` byte reads in the log | `[ebp-4]`, `[ebp+0x14]` | `[ebp-4]`, `[ebp+0x14]` |
| the spill disappears | — | gone |
| frame returns to the reference's | `sub esp, 0x14` | `sub esp, 0x14` |

The `movzx` operands match slot for slot, which means `currentStatus` now
occupies `[ebp-4]` exactly as it does in the reference — the frame layout, not
just its size, agrees.

`status` also dropped from two sends to one, matching. That was not predicted and
is not claimed as a consequence of this change: the second send sat near the end
of the method, and this count is sensitive to where the extent is cut, so the
earlier reading of two may have included a neighbouring static function.

### What the pass revealed once its own noise was gone

With the three loose ends closed, the method can be compared as a whole for the
first time, and it is **70.7% similar** to the reference — 367 reference
instructions against 357 of ours. The remaining differences are real and none of
them belong to this finding:

- **`_verbose` is tested against 1, not 0.** The reference does
  `cmp byte ptr [ecx + 0x20], 1` / `jne`, ours `cmp byte ptr [...], 0` / `je`, at
  four sites. Apple's source compares the flag to a value rather than testing it
  for truth, or the ivar's type differs.
- **The first `socketNumber` send is unconditional in the reference.** It is
  issued before `test byte ptr [ebp+0x14], 1`, so its result is computed even
  when the `present` test sends control elsewhere. Ours now sends it inside the
  branch. Five sends is right; where the first one sits is not.
- **Ours has extra message sends around several logging sites**, visible as
  inserted `push`/`call` runs in the instruction diff.
- **`freeObjects` versus `freeObjects:`**, as above.

These are a separate pass's work. Recording the 70.7% figure here so that a
future pass has a baseline to move rather than a fresh guess.

### The remaining-differences pass

**One item on that list was not real.** "Extra message sends around logging
sites" was an artefact of reading an instruction diff whose alignment had
slipped. Every selector count already matched except `freeObjects`. What the
diff was showing is a **basic-block layout** difference: the reference groups
all of the early-return `IOLog` blocks together — its `present` test jumps
forward past the lot, to +208 — while ours emits each one inline where the
source puts it. No source construct was identified for that, and none was
invented; it is left as an open observation. The `[edi+4]` flag test, which
compares the same value on both sides and differs only in branch direction, is
the same phenomenon.

The other three were real and are fixed.

**`_verbose` is compared against `YES`, and it is a whole-binary pattern**, not
a quirk of this method. Counting over `__TEXT,__text`:

| | `cmp byte ptr [..+0x20], 1` | `cmp byte ptr [..+0x20], 0` |
| --- | --- | --- |
| Reference | 66 | 1 |
| Ours, before | 0 | 66 |

The same 66 sites, in the opposite form. `_verbose` is a `BOOL`, so
`if (_verbose)` yields `cmp 0` / `je` where Apple's `if (_verbose == YES)`
yields `cmp 1` / `jne`. All 63 `if (_verbose)` in `PCMCIAKernBus.m` and
`PCMCIAKernBusPrivate.m`, plus the two compound `&& _verbose` tests, now compare
against `YES`. This is much larger than the one method under study, which is why
it is recorded here rather than buried in a method-level note.

**The first `socketNumber` send is unconditional again.** The reference issues
it before `test byte ptr [ebp+0x14], 1`, so the number is fetched even when the
`present` test sends control elsewhere — a message send cannot be hoisted above
a branch by the compiler, so Apple's source evaluates it unconditionally. A
local, assigned before the test and read only by the "don't care" log, restores
that while leaving the other four sends inline: five sends, the first
unconditional.

**`probed` is compared against 1 at the second test.** The reference has
`cmp byte ptr [edi+5], 1` / `je` where ours had `cmp 0` / `jne`; identical for a
0/1 flag, different source. `if (socketInfo->probed == 0)` became
`if (socketInfo->probed != 1)`. The *first* `probed` test already matched and
was left alone.

**`freeObjects` takes no argument.** `[[socketInfo->tupleList
freeObjects:@selector(free)] free]` became `[[socketInfo->tupleList freeObjects]
free]`.

**Predictions for the next build:** 66 `cmp byte ptr [..+0x20], 1` and none
against 0; the `freeObjects:` selector replaced by `freeObjects`; the first
`socketNumber` send ahead of the `present` test; `cmp byte ptr [edi+5], 1` at
the second `probed` test; and a similarity above 70.7%. Whether the block
layout converges is genuinely unknown — the branch-polarity changes may reorder
blocks as a side effect, or may not.

### Verification

All held. `statusChangedForSocket:changedStatus:` went from **70.7% to 77.4%**
similar, and five of its six byte-flag tests are now instruction-identical:

| Test | Reference | Rebuilt |
| --- | --- | --- |
| `[edi+4]` flag1 | `cmp 0` → `jne` | `cmp 0` → `je` |
| `[ecx+0x20]` `_verbose` | `cmp 1` → `jne` | `cmp 1` → `jne` |
| `[edi+5]` `probed` | `cmp 0` → `je` | `cmp 0` → `je` |
| `[edi+5]` `probed` | `cmp 1` → `je` | `cmp 1` → `je` |
| `[esi+0x20]` `_verbose` | `cmp 1` → `jne` | `cmp 1` → `jne` |
| `[ecx+0x20]` `_verbose` | `cmp 1` → `jne` | `cmp 1` → `jne` |

The one still differing is `[edi+4]`, which compares the same value and differs
only in branch direction — the block-layout artefact, unchanged, so the
polarity edits did **not** reorder blocks. The method's prologue now matches:
the `socketNumber` send precedes `test byte ptr [ebp+0x14], 1`.

**`freeObjects` went wider than one call site.** The reference's selector table
contains `freeObjects` and **no `freeObjects:` at all**, so every site takes the
no-argument form. Fixing only the one in `statusChangedForSocket:` left the
other nine, in `PCMCIAKernBusPrivate.m`, still emitting `freeObjects:` — all ten
now send `freeObjects`.

**The `_verbose` count came back 65 against the reference's 66**, and the
missing one localises to a single method: `-[PCMCIAKernBus(Private)
probeDevice:withDescription:]` has ten tests in the reference and nine in ours.

### The missing guard in `probeDevice:withDescription:`

It is not a missing log. Both binaries reference the same thirteen strings in
this method; what differs is that the reference guards one of them with
`_verbose` and we do not. Mapping each guard to the string it protects:

| Guarded string | Reference | Ours |
| --- | --- | --- |
| `PKB: Driver %s could not be configured` | `_verbose` | `serverName != NULL` |

The reference's structure at `+250`:

```
+250  cmp byte ptr [edx+0x20], 1 ; jne 0x1f8e     <- outer
+260  push edi ; push "driver class '%s' was not loaded" ; call IOLog
+274  mov edx, dword ptr [ebp+8]
+277  cmp byte ptr [edx+0x20], 1 ; jne 0x1f8e     <- inner, same target
+287  mov edx, dword ptr [ebp-0x10] ; push edx ; push "Driver %s could not be configured"
```

Both `jne`s branch to **the same address**, which is what a nested test
produces: the outer false-branch and the inner false-branch both land at the end
of the outer block. Two sibling `if`s would have sent the first elsewhere. So
Apple wrote `_verbose` twice, once inside the other — redundant in source, and
faithfully reproduced here.

**This drops a NULL check the reconstruction had added.** The reference tests
nothing before `mov edx, [ebp-0x10] ; push edx`; it pushes `serverName`
unguarded, relying on it being valid at that point. Our source had
`if (serverName != NULL)` in the position the reference uses for the second
`_verbose` test. Matching the reference removes that defensive check, which is
recorded here rather than left implicit.

**Verified.** The rebuilt binary carries **66** `cmp byte ptr [..+0x20], 1` and
one against 0 — the reference's counts exactly — and
`probeDevice:withDescription:` now has ten guards. The first four line up with
the same strings in the same order, the repaired one included:

```
[0] PKB: class list '%s'
[1] PKB: driver class '%s' was not loaded
[2] PKB: Driver %s could not be configured      <- repaired
[3] PKB:probeDriver: initFromDeviceDescription failed for class %s
```

**One block sat in a different place**, and it was not the compiler. `PKB:
aborting probe` is the tenth and last guard in the reference and was the fifth
in ours. Reading the reference's tail shows why:

```
+795  cmp byte ptr [edx+0x20], 1 ; jne +814     <- the guard
+801  push 'PKB: aborting probe' ; call IOLog
+814  cmp dword ptr [ebp-0x14], 0 ; je +836     <- IOFree(classNames, classListLength)
+836  cmp dword ptr [ebp-0x10], 0 ; je +865     <- [device freeString:serverName]
+865  cmp dword ptr [ebp-8], 0    ; je +890     <- [kernDevice free]
+890  cmp dword ptr [ebp-4], 0    ; je +912     <- [pcmciaDesc free]
+912  xor eax, eax                              <- return NO
```

The log is the **head of the shared `cleanup_and_fail` block**, ahead of four
conditional frees that match ours one for one, in the same order. Ours had it
inside the `pcmciaDesc == nil` branch instead, so only that one failure path
logged it; the reference logs it on every path that reaches the label. Moving it
to the top of `cleanup_and_fail` is therefore a behaviour fix as well as a
placement one — the other `goto cleanup_and_fail` sites now log too, as Apple's
do. The `_verbose` site count is unchanged at 57; the block moved rather than
multiplied.

**The method as a whole is only 42.4% similar**, far below
`statusChangedForSocket:`'s 77.4%. Fixing the guard did what it claimed and
nothing more: `probeDevice:withDescription:` carries substantial divergences
beyond the scope of this thread, and that figure is the baseline for whoever
takes it on.

**Verified after the move.** All ten guards now appear in the reference's order,
`PKB: aborting probe` last, and the whole-binary `_verbose` counts still read 66
and 1 — the block moved rather than multiplied, as intended.

Similarity rose only from 42.4% to **42.9%**, which is the honest measure of what
a log-placement fix is worth. The instruction counts are nearly equal — 307
reference against 308 ours — but the bodies diverge across 21 runs. The largest:

| | |
| --- | --- |
| ref 64 insns / ours 3 | at `ref[233]`, beginning `mov eax, 1 ; jmp` — a success-return path we largely lack |
| ours 30 / ref 0 | at `ref[217]` |
| ours 22 / ref 12 | at `ref[219]` |
| ours 20 / ref 0 | at `ref[213]` |
| ours 16 / ref 0 | at `ref[173]` |

Roughly 64 reference instructions are missing from ours and a similar volume of
ours has no counterpart. That is a body-level reconstruction gap in this method,
not a residue of the logging work, and it wants its own pass.

The nine-site `freeObjects` change was then confirmed in turn: `freeObjects:` is
absent from our selector table, as it is from the reference's, and `_verbose`
sits at 65 of 66 exactly as predicted. `statusChangedForSocket:` holds at 77.4%,
unchanged — its own call site had already been fixed a build earlier.

### Where this driver stands, more broadly

Comparing whole selector tables puts the remaining work in proportion:

| | Reference | Rebuilt |
| --- | --- | --- |
| selectors | 160 | 185 |
| shared | 135 | 135 |
| reference-only | 25 | — |
| rebuilt-only | — | 50 |

The 25 we lack — `BVDActive`, `IOAddrLines`, `IRQInfo`, `MemSpaceInfo`,
`MemoryWaitRequired`, `PortRanges`, `ReadyBusyActive`, `VccPowerInfo`,
`Vpp1PowerInfo`, `Vpp2PowerInfo`, `WPActive`, `_private` and others — are
accessors this reconstruction has not implemented. The 50 we have and the
reference does not are largely our own ivar names.

So the method-level agreement reached here sits inside a driver whose class
surface still differs substantially. The 77.4% figure is a real measurement of
one method and should not be read as a statement about the driver.

**Left unchanged.** Adopting the bitfield is not a one-line change to this
driver; it is a coordinated change across three classes in a driver outside this
record's scope. `PCICSocket` in the reference uses the same type in three more
places:

| Method | Reference |
| --- | --- |
| `-[PCICSocket status]` | `{?=b1b1b1b1b2b1b1}8@8:12` |
| `-[PCICSocket statusChangeMask]` | `{?=b1b1b1b1b2b1b1}8@8:12` |
| `-[PCICSocket setStatusChangeMask:]` | `c12@8:12{?=b1b1b1b1b2b1b1}16` |

Changing only the bus side would put a struct-passing caller against an
integer-reading callee across the one boundary that currently works. Changing
both sides is the right fix, but it belongs with a reconstruction pass on
`Intel82365PCMCIA`, where `PCICSocket` needs reworking anyway: the reference
declares four ivars and `instance_size` 20, while ours declares ten ivars.
Doing it here, with no build host and no parity run, would be an unverifiable
cross-driver ABI change made in the wrong repository corner.

Note also that `-[PCICSocket status]` returns this struct **by value** with no
hidden struct-return pointer in the encoding (`self` is still at `8`), i.e. it
comes back in `al`. Our `enableSocket:` reads it as a signed byte and tests bit
7 (`PCMCIAKernBusPrivate.m:1208,1240-1241`), which happens to agree with `ready`
being the top bit — so that code works by arithmetic coincidence, not by
contract.

The same idiom one file up was outright broken, and is the sharpest argument for
finishing this properly. `waitForSocketReady()` declared `unsigned char status`
and then tested `if (status < 0)`, with the comment "Signed char < 0 means bit 7
is set". An `unsigned char` is never negative, so that branch was unreachable
and the function polled its full 100 iterations and returned `NO` for every
card, ready or not. This pass found it but left it alone as out of scope; the
implementation pass found it independently and fixed it by making `status` a
plain `char` (see Finding 5 of `divergences.md`).

That fix is correct but still leans on plain `char` being signed. A real
`PCMCIAStatus` with a named `ready` bit removes the whole class of error, which
is the standing argument for adopting the type.

## Findings 2-8 — private-category signatures: **fixed**

None of these were covered by the kernel-header pass. In four of them our own
implementation was already the evidence that the declaration was wrong: the body
cast the parameter straight back to the type Apple declared.

### 2. `allocateSharedMemory:ForDescription:AndSocket:` took `unsigned int`

| | |
| --- | --- |
| Reference | `@20@8:12@16@20@24` at `0x2598` |
| Ours, before | `- allocateSharedMemory:(unsigned int)size ForDescription:...` |

The first parameter was named `size` and typed `unsigned int`, but the body
never used it as a size — it dereferenced it as a pointer to a config entry at
`+0x104`, `+0x108` and `+0x71`, and the sole call site passes `selectedConfig`,
an object (`PCMCIAKernBusPrivate.m:798`). Apple's `@` is correct. The parameter
is now untyped (`id`) and renamed `configEntry`; the six dereferences follow the
rename. This was a live mistyping, not just a metadata difference.

### 3. `entry:matchesUserIOPorts:` took `const char *`

| | |
| --- | --- |
| Reference | `c16@8:12@16@20` at `0x22f4` |
| Ours, before | `- (BOOL)entry:entry matchesUserIOPorts:(const char *)portString` |

The body sent `count` and `objectAt:` to the parameter through `(id)` casts, and
the call site passes `portRangeList`, a `List` (`PCMCIAKernBusPrivate.m:677`).
Parameter is now untyped; four `(id)` casts deleted.

### 4. `reserveIOPorts:UsingEntry:` took `const char *`

| | |
| --- | --- |
| Reference | `c16@8:12@16@20` at `0x24a8` |
| Ours, before | `- (BOOL)reserveIOPorts:(const char *)portString UsingEntry:entry` |

Same defect as Finding 3 — the body sent `freeObjects:` and `addObject:` through
`(id)` casts. Parameter is now untyped; two `(id)` casts deleted.

### 5. `testIDs:ForAdapter:andSocket:` took three `id`

| | |
| --- | --- |
| Reference | `c20@8:12*16i20i24` at `0x18e0` |
| Decoded | `(char *)idList` plus two `int` |
| Ours, before | all three parameters untyped |

The body opened with `adapterIndex = (int)adapter; socketIndex = (int)socket;`
and later `idString = (char *)idList;`. Now typed as Apple declared them and the
three casts are gone. The method has no callers in-tree, so the change is
confined to the declaration and body.

`*` cannot distinguish `char *` from `unsigned char *` under this compiler;
`char *` was chosen to match the body's existing local.

### 6. `configureSocket:` and `disableSocket:` returned `BOOL`

| | |
| --- | --- |
| Reference | `v12@8:12@16` at `0x1b58` and `0x1568` |
| Ours, before | `- (BOOL)` on both |

Both are now `void`. `disableSocket:` only ever returned `YES`;
`configureSocket:` returned `NO` on exhausting the config-table list and `YES`
otherwise. Neither result was consulted — the only call sites are
`PCMCIAKernBus.m:674` and `:748`, both discarding — so no caller loses a
decision it was making.

### 7. `freeMemoryWindowElement:` returned `id`

| | |
| --- | --- |
| Reference | `v12@8:12@16` at `0x143c` |
| Ours, before | `- freeMemoryWindowElement:element` returning `self` |

Now `void`. Both call sites (`PCMCIAKernBus.m:744`,
`PCMCIAKernBusPrivate.m:938`) discard the result.

### 8. The `(Parsing)` selectors were underscore-prefixed — and the real parser was unreachable

| | |
| --- | --- |
| Reference | `-[PCMCIAKernBus(Parsing) parseTuple:intoDeviceDescription:]` `@16@8:12@16@20` at `0x4928` |
| | `-[PCMCIAKernBus(Parsing) allocResourcesForDescription:fromTupleList:]` `@16@8:12@16@20` at `0x48b4` |
| Ours, before | `_parseTuple:intoDeviceDescription:` returning `void`, `_allocResourcesForDescription:fromTupleList:` |

This is the one finding that was not merely a typing difference. A selector name
is dispatched on, so the underscores were a real mismatch — and they had hidden a
live bug:

- `PCMCIAKernBusPrivate.h:61` declared `- (BOOL)parseTuple:tuple
  intoDeviceDescription:deviceDesc`, implemented at `PCMCIAKernBusPrivate.m:1207`
  as a stub whose entire body was `// TODO: Implement based on decompiled code`
  followed by `return NO;`.
- The real tuple parser — the one with the dispatch table over
  `tupleParserTable` — was `_parseTuple:intoDeviceDescription:` in `(Parsing)`.
- The card-insertion path at `PCMCIAKernBus.m:731` sends
  `parseTuple:intoDeviceDescription:`, so it reached **the stub**. Every tuple
  parsed on card insertion was silently dropped and the real parser was dead
  code reachable only from `_allocResourcesForDescription:`, which itself had no
  callers.

The reference has exactly one such selector, in `(Parsing)`, which is what
settles it. Applied: the stub and its declaration are deleted, both `(Parsing)`
methods lose the underscore, and `parseTuple:` returns `id` to match `@`.
`PCMCIAKernBus.m` now imports `PCMCIAKernBusParsing.h` so the call site still
sees a declaration (`PCMCIAKernBusPrivate.h` is unguarded, `PCMCIAKernBusParsing.h`
sits inside `#ifdef DRIVER_PRIVATE`, and `Makefile:32` puts `-DDRIVER_PRIVATE`
in `NEXTSTEP_PB_CFLAGS`, so both are visible).

The returned object is the one guess in this pass: `@` says an object comes
back, both call sites discard it, and nothing in the metadata says which. We
return `description`, by analogy with `allocResourcesForDescription:fromTupleList:`
in the same category, which returns its `description` argument. If a build ever
disagrees, this is the line to revisit.

## Recorded, not changed

### Ivar names, and `busRange`

| Offset | Reference | Ours |
| --- | --- | --- |
| +16 | `@ adapters` | `id _adapters` |
| +20 | `{?="base"I"length"I} busRange` | `unsigned int _memoryBase` (+20), `unsigned int _memoryLength` (+24) |
| +28 | `@ socketTable` | `id _socketMap` |
| +32 | `c verbose` | `BOOL _verbose` |
| +36 | `@ attrMem` | `id _memoryRangeResource` |

`instance_size` matches at 40 on both sides and every offset agrees.

`_verbose` was `int` and is now `BOOL`, so its metadata type matches the
reference's `c`. That was the same `i`-for-`c` slip corrected on the PCI side,
and it is risk-free here: the ivar is assigned only `0` (`PCMCIAKernBus.m:371`)
and the `BOOL` argument of `setVerbose:` (`:601`), and is only ever tested for
truth.

The names themselves were **not** changed. They are not part of the ABI, our
`_`-prefixed `@private` convention is used consistently across this driver, and
renaming five ivars to recover metadata-only parity was judged not worth the
diff.

`busRange` is the one entry that is structural rather than cosmetic: Apple holds
a single `Range` where we hold two `unsigned int`s at the same two offsets. The
bytes are identical and `setBusRange:(Range)range` already matches Apple's
`v16@8:12{?=II}16`, splitting the argument into the two fields at
`PCMCIAKernBus.m:592-593`. Consolidating to one `Range` ivar would touch all
fourteen use sites across `PCMCIAKernBus.m` and `PCMCIAKernBusPrivate.m`; that
is a refactor rather than a signature fix, so it is recorded here for whoever
does the next structural pass.

### Everything else agrees

Checked against the metadata and matching exactly:

- `PCMCIAKernBus`: `init`, `free` (`@8@8:12`), `addAdapter:`, `removeAdapter:`,
  `allocIOWindowForSocket:`, `allocMemoryWindowForSocket:` (`@12@8:12@16`),
  `memoryRangeResource` (`@8@8:12`), `setBusRange:` (`v16@8:12{?=II}16`),
  `setVerbose:` (`v9@8:12c16`); metaclass `+probe:`,
  `+configureDriverWithTable:` (`c12@8:12@16`), `+deviceStyle` (`i8@8:12`),
  `+requiredProtocols` (`^@8@8:12`).
- `PCMCIAKernBus(Private)`, the twelve that were already right:
  `allocateResourcesForDeviceDescription:`, `copyTupleList:` (`@12@8:12@16`),
  `tupleListFromSocket:mappedAddress:` (`@16@8:12@16I20`),
  `configureSocket:withDescription:`, `configureSocket:withDriverTable:`,
  `configTable:matchesSocket:`, `probeDevice:withDescription:` (`c16@8:12@16@20`),
  `configureDriverWithTable:`, `enableSocket:` (`c12@8:12@16`),
  `findAndReserveRangeBase:Length:AlignedTo:` (`@20@8:12I16I20I24`),
  `mapAttributeMemory:ForSocket:CardBase:` and
  `mapMemory:ForSocket:ToCardAddress:` (`@24@8:12{?=II}16@24I28`).

### Out of scope but noted

`PCMCIAConfigEntry` is compiled into the reference's `PCMCIAKernBus.m` module,
not its own translation unit as in our tree, and its seventeen ivars carry named
struct types in the metadata (`_IOPortRangeTable`, the `mantissa`/`exponent`
power tuples, the `irqUsed`/`share`/`pulse`/`level`/`NMI`/`IOCK`/`BERR`/`VEND`
IRQ bitfield). `instance_size` is 520. That layout has not been compared against
`PCMCIAConfigEntry.h` in this pass and is the obvious next piece of work in this
driver.
