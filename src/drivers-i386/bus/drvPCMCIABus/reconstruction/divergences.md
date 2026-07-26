# drvPCMCIABus divergences against the DR2 reference

Scope: the Objective-C interface of `PCMCIAKernBus` and its `(Private)` and
`(Parsing)` categories as declared in `PCMCIABus.drvproj/PCMCIABus.lksproj/`,
compared against Apple's shipped driver.

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

## Finding 1 — `statusChangedForSocket:changedStatus:` takes a bitfield: **intentional mismatch, not changed**

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

The same idiom one file up is outright broken, and is the sharpest argument for
finishing this properly. `waitForSocketReady()` declares `unsigned char status`
(`PCMCIAKernBusPrivate.m:58`) and then tests `if (status < 0)` (`:67`), with the
comment "Signed char < 0 means bit 7 is set". An `unsigned char` is never
negative, so that branch is unreachable and the function polls its full 100
iterations and returns `NO` for every card, ready or not. A real `PCMCIAStatus`
with a named `ready` bit removes the whole class of error. **This bug is
pre-existing and was left unchanged** — it is outside this pass's scope and
deserves its own fix and test.

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
