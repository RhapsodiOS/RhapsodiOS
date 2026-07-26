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

**Predictions this pass makes, all checkable in a rebuilt `PCMCIABus_reloc`:**
the emitted encoding becomes `v16@8:12@16{?=b1b1b1b1b2b1b1}20`; the test becomes
the reference's two instructions; the `socketNum` spill disappears; and both
call sites emit `push 1`.

**One divergence found here and left open.** In the verbose logging path the
reference zero-extends a *single byte* of each status:

```
0f b6 55 fc    movzx edx, byte ptr [ebp - 4]    ; currentStatus
0f b6 55 14    movzx edx, byte ptr [ebp + 0x14] ; changedStatus
```

Ours passes the values whole. Since the struct is four bytes, `movzx` from a
byte means Apple's source narrowed both at the call — a cast, or byte-typed
locals. Which of those it was is not recoverable from the encoding, and the path
is `_verbose`-only, so nothing was invented to match it. `currentStatus` is also
still an `unsigned int` here, assigned from `[socket status]` through an untyped
receiver; the reference's `-[PCICSocket status]` returns the bitfield. Both
belong to the same unfinished thread.

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
