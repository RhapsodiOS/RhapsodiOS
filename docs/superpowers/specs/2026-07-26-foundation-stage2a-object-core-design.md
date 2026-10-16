# Foundation stage 2a: the object core

Reconstruct the root of Rhapsody's object layer — `NSObject`, `NSProxy`,
`NSAutoreleasePool`, the zombie and autoreleased-memory helpers, and the C
functions behind object allocation, retain counting and zones.

This is the first of three sub-stages of what
[2026-07-26-foundation-i386-reconstruction-design.md](2026-07-26-foundation-i386-reconstruction-design.md)
§3.1 called stage 2. That stage measured at 366 functions and 31,932 bytes —
8.5× stage 1's function count — so it is split into 2a (object core), 2b
(exceptions and runtime) and 2c (invocation and coding), each with its own
design, plan and execution cycle.

## Motivation

Stage 1 reconstructed three leaf modules of plain C: geometry, ranges and
decimal arithmetic. Nothing in Foundation depends on them. Stage 2a is the
opposite — `NSObject` is what every other class in the framework inherits from,
and the retain-count functions are what every object's lifetime runs through.
Until this exists, no further stage can produce a class that actually works.

It is also the first stage that exercises the ABI machinery built in stage 1 on
real classes. Stage 1's entire Objective-C surface was one category on `NSCoder`;
`abi-check` compared no superclass links, no instance sizes and no ivar offsets,
because there were none. Those are precisely the facts client code bakes in, so
2a is where that gate starts earning its keep.

## 1. Scope

### 1.1 Target

Reference of record is unchanged: the extracted thin i386 slice at
`C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1,630,488**, SHA-256
`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.

| Module | Classes | Methods | Bytes |
| --- | --- | --- | --- |
| NSObject.m | `NSObject`, `_NSZombie` | 93 | 2,908 |
| NSProxy.m | `NSProxy` | 47 | 1,856 |
| NSAutoreleasePool.m | `NSAutoreleasePool` | 23 | 1,484 |
| NSPrivate.m | `_NSAutoreleasedMallocMemory` | 5 | 724 |
| NSZone.m *(see §2.1)* | — | 25 C functions | 3,380 |
| **Total** | **5 classes** | **193 functions** | **10,352** |

Class layouts, read from `__OBJC`:

| Class | Superclass | `instance_size` | Ivars |
| --- | --- | --- | --- |
| `NSObject` | *(root)* | 4 | `isa` `#` @0 |
| `NSProxy` | *(root)* | 4 | `isa` `#` @0 |
| `NSAutoreleasePool` | `NSObject` | 20 | `_token`, `_reserved3`, `_reserved2`, `_reserved` — all `^v`, @4/@8/@12/@16 |
| `_NSZombie` | `NSProxy` | 4 | none |
| `_NSAutoreleasedMallocMemory` | `NSObject` | 12 | `mutableBytes` `^v` @4, `length` `I` @8 |

The 25 C functions, by the header that declares them:

- **`NSObject.h` (7, 2,088 bytes):** `NSIncrementExtraRefCount` (612),
  `NSDeallocateObject` (520), `NSDecrementExtraRefCountWasZero` (480),
  `NSExtraRefCount` (236), `NSCopyObject` (96), `NSAllocateObject` (84),
  `NSShouldRetainWithZone` (60).
- **`NSZone.h` (18, 1,292 bytes):** `NSCopyMemoryPages`,
  `NSAllocateMemoryPages`, `NSCreateZone`, `NSDeallocateMemoryPages`,
  `NSZoneCalloc`, `NSZoneRealloc`, `NSZoneMalloc`, `NSRealMemoryAvailable`,
  `NSRecycleZone`, `NSZoneFree`, `NSZoneName`, `NSSetZoneName`,
  `NSLogPageSize`, `NSRoundUpToMultipleOfPageSize`,
  `NSRoundDownToMultipleOfPageSize`, `NSPageSize`, `NSDefaultMallocZone`,
  `NSZoneFromPointer`.

No function is declared in both headers.

### 1.2 Out of scope

`NSException.m`, `NSObjCRuntime.m` and `NSFault.m` (stage 2b);
`NSInvocation.m`, `NSMethodSignature.m` and `NSCoder.m` (stage 2c). Modifying
any header. Adding Foundation to `src/Manifest` or building the framework as a
framework — still deferred, and still not possible with five classes.
Reconstructing the `_NSInteger*` bignum layer (stage 1's open item; see §2.4).

## 2. Findings that shaped this design

### 2.1 There is no `NSZone.m` in the reference

`__OBJC,__module_info` names 80 translation units. `NSZone.m` is not among them.
The 25 functions above are exported C symbols that Apple compiled into some
other unit, and C functions carry no module attribution in a Mach-O — only
Objective-C definitions do — so which unit is unknowable from the binary.

**Decision: all 25 live in `src/Kits/Foundation/NSZone.m`.** The tree already
has that file as a stub, and keeping the allocator, the object allocator and the
retain-count functions together is how a maintainer would expect to find them.

This deliberately overrides the project's usual rule that a C function is
attributed by its declaring header — under that rule the 7 from `NSObject.h`
would go to `NSObject.m`. It is a divergence in **file organisation only**: the
symbols, their linkage and their behaviour are unchanged, which is all
`abi-check` and any linking client observe. It is recorded in
`divergences.md`.

This is the second instance of a general problem, after stage 1's `_NSInteger*`
finding: **an exported C symbol has no binary-recorded owner.** §5.4 proposes
the check that would make it systematic rather than case-by-case.

### 2.2 Two root classes, which the ABI gate has never seen

`NSObject` and `NSProxy` both have a null `superclass`. Stage 1's ABI surface
was a single category, so `abi-check` has never compared a class at all, let
alone a root one. `abi/*.json` represents a null superclass as JSON `null`
(`abi-v1.json` types it `["string", "null"]`), and `diff_abi` compares the field
directly, so this should work — but it is unexercised, and a root class getting
a non-null superclass in our rebuild would be a serious, silent ABI break.
The plan verifies it explicitly rather than assuming.

### 2.3 Testing `NSObject` requires hosting it, not just linking it

Stage 1's modules were leaf C functions: a test binary compiled them, stubbed a
handful of Foundation symbols, and ran. `NSObject` cannot work that way. It is
the class the Objective-C runtime dispatches through, so a test must run in a
process where **our** `NSObject` is the registered root class — which means
linking `libobjc` and `libSystem` but **not** the system Foundation, or two
`NSObject` implementations collide.

Whether Rhapsody's `libobjc` can host a root class with no Foundation present is
**unknown**. Stage 1 already needed hand-written link stubs for far simpler
code, so this is not a formality. It is the stage's single largest risk and §3.2
sequences the work around it.

### 2.4 Carried forward from stage 1

Three items from stage 1's `divergences.md` bear on 2a:

- **`objc_method_index` now resolves prebound selectors** (fixed at the end of
  stage 1, verified 2,884 → 3,253 named addresses). 2a's modules are
  prebound-heavy — `NSObject.m` alone had 28 prebound entries — so this fix is
  load-bearing here and its absence would have silently under-mapped the stage.
- **The `_NSInteger*` bignum layer** remains unclaimed by any module. It is not
  2a's to resolve (it belongs with the decimal work, stage 5), but 2a adds a
  second instance of the same class of problem, which strengthens the case for
  §5.4's check.
- **The deleted `NSValue` geometry stubs** currently exist nowhere in the tree.
  Not 2a's concern — stage 5 supplies them — but the deferral is live.

## 3. Design

### 3.1 Acceptance bar

Unchanged from stage 1, and for the same reasons:

- **Gate 1 — ABI, machine-checked.** `binrecon abi-check` against the built
  objects. In 2a this finally covers superclass links, `instance_size`, ivar
  names, type encodings and offsets, and every selector and signature across
  five classes. Pass/fail.
- **Gate 2 — behaviour, tested.** Pass/fail, on the guest.
- **Gate 3 — instruction comparison, evidence only.** `compare` runs, its ledger
  is reviewed and dispositioned in `divergences.md`. Divergence prompts
  investigation, not failure. Stage 1 established that a per-module excerpt
  rebuild cannot be positionally correlated against the reference's
  profile-guided layout, so entries are expected to disposition as
  `intentional-mismatch` again.

### 3.2 Sequencing, arranged so a gate failure still leaves value

The runtime-hosting question in §2.3 governs the order:

1. **Prove the host.** Build and run a test binary containing a trivial
   Objective-C root class of our own against the guest's `libobjc`, without the
   system Foundation. This is 2a's equivalent of stage 1's Task 1 gate, and like
   it, a failure **stops the stage and reshapes the design** rather than being
   worked around. It runs before any reconstruction.
2. **The 25 C functions**, into `NSZone.m`. Zones and retain counts are ordinary
   C over plain memory, testable exactly as stage 1's decimal arithmetic was and
   **independent of step 1's outcome**. `NSIncrementExtraRefCount` (612 bytes)
   and `NSDecrementExtraRefCountWasZero` (480) implement the refcount side
   table and carry most of the subtlety.
3. **`NSObject` and `_NSZombie`**, then **`NSProxy`**, then
   **`NSAutoreleasePool`** and **`_NSAutoreleasedMallocMemory`** — in dependency
   order, each gated on step 1 having succeeded.

If step 1 fails, steps 2 and 3 still produce correct, ABI-checked source; only
Gate 2 narrows to the C functions, and the stage reports honestly which methods
went untested. That is a materially better outcome than discovering the problem
after reconstructing 168 methods.

### 3.3 Artifacts

The layout established in stage 1, extended:

```
src/Kits/Foundation/reconstruction/
  divergences.md                  shared, append-only — 2a appends a section
  symbols.json                    extended with NSZone.m's 25 C symbols
  ownership.json                  extended with 2a's method and function names
  abi/
    NSObject.json  NSProxy.json  NSAutoreleasePool.json  NSPrivate.json
    NSZone.json                   C symbols only; no Objective-C content
  object-core/                    this stage's group directory
    ledger.json
    source-map.json
```

`NSZone.json` is the first ABI document describing a module the reference does
not have. It carries the 25 symbols and empty `classes`/`categories`, which is
consistent with `abi-v1` and with how `module_from_object` treats an object with
no `__OBJC` segment.

**A new profile, not an edit to stage 1's.**
`tools/binrecon/profiles/foundation-i386-object-core.json`, carrying 2a's own
`analysis_scope` generated by `binrecon module-scope`. Overwriting
`foundation-i386.json`'s scope would leave stage 1's analysis unreproducible —
its published artifact is gitignored, so the profile is the only committed record
of how it was produced. One profile per stage group keeps every stage
regenerable from the tree alone.

Expect roughly 193 ranges against stage 1's 43. The master spec's §5.2 measured
the cost at about 660 on-disk bytes per exported instruction on top of ~15 MB of
fixed per-image overhead, so the published analysis should land near 17 MB —
well inside the 64 MB cap.

### 3.4 Reconstruction standard

Unchanged and non-negotiable: **reconstruct, do not transcribe.** Stage 1's
three modules passed review on this and set the house style — Apple's copyright
header preserved, C89 throughout (the guest compiler is gcc 2.7.2.1), working
variables named for what they hold, comments explaining why rather than
narrating a disassembly. Source containing decompiler-generated identifiers
fails review.

Two stage-1 findings apply directly to reading this stage's disassembly:

- The reference returns structs via a hidden pointer in **EBX**, not on the
  stack, which makes IDA's automatic struct recovery mislabel fields by one
  slot. Any struct-returning function here needs the same care.
- The IDA analysis names category methods **without** the category qualifier
  while the Mach-O symbol table names them **with** it. `module-scope` matches
  the symbol table; `ownership.json` matches the analysis. Both are correct in
  their own context and must not be "unified".

## 4. Verification

Stage 2a is complete when:

1. The runtime-hosting gate (§3.2 step 1) has a recorded, reproducible outcome —
   pass or fail — with the exact link line.
2. `binrecon module-scope` emits a scope covering all 193 functions, and
   `binrecon analyze` completes with `complete: true` having exported exactly
   that many.
3. `abi/NSObject.json`, `NSProxy.json`, `NSAutoreleasePool.json`,
   `NSPrivate.json` and `NSZone.json` are committed, schema-valid, and describe
   the five classes with the layouts in §1.1 — including both null superclasses.
4. `binrecon abi-check` exits zero against the built objects.
5. The C test suite passes for all 25 zone and refcount functions.
6. If the gate passed: the Objective-C test suite passes, and stage 1's six
   deferred `NSGeometryCoding` tests remain deferred (they need `NSCoder`, which
   is stage 2c). If the gate failed: the untested methods are enumerated in
   `divergences.md` with the reason.
7. `binrecon source-map` reports every 2a function mapped, with `by_module`
   accounting for all of them.
8. `ledger.json` is committed with every entry reviewed and dispositioned.
9. binrecon's own suite passes.
10. No header under `src/Kits/Foundation` is modified.

## 5. Risks

### 5.1 The runtime-hosting gate may fail

§2.3. Handled by sequencing (§3.2): it runs first, and failure narrows the stage
rather than wasting reconstruction work. If it fails, the likely fallbacks — in
order of preference — are linking against the guest's own Foundation with our
classes under temporary names purely to exercise logic (which does *not* satisfy
Gate 1 and must be labelled as such), or deferring all Objective-C behavioural
testing to a later stage that can build a linkable framework. The design does
not pre-commit to either; the gate's actual error decides.

### 5.2 `NSObject`'s 93 methods are mostly one-liners, which flatters the byte count

2,908 bytes across 93 methods averages 31 bytes each, and the largest is 116.
The reconstruction risk is therefore not complexity but **volume and
uniformity** — 93 nearly-trivial methods is exactly the shape where a reviewer's
attention lapses and a wrong selector or a swapped argument slips through.
`abi-check` catches signature and selector errors; it does not catch a method
whose body does the wrong correct-looking thing. The plan should group these for
review by behaviour rather than presenting 93 diffs.

### 5.3 Retain counting is the subtle part

`NSIncrementExtraRefCount` and `NSDecrementExtraRefCountWasZero` are 612 and 480
bytes — an order of magnitude above the method average — because they implement
a side table rather than an inline counter. Getting the overflow, the
zero-transition return value, or the table's hashing wrong produces leaks or
double-frees that no ABI check detects and that only targeted tests will catch.
These deserve disproportionate test attention relative to their line count.

### 5.4 Unclaimed exported symbols are now a pattern, not an incident

Stage 1 found 12 exported `_NSInteger*` symbols owned by no module; 2a adds 25
more whose owner is unknowable. Both were caught by a human reading a review, not
by tooling. **Proposal, to be built in 2a's plan:** a `binrecon` check that every
external `__TEXT,__text` symbol in the reference is claimed by exactly one
module's `symbols.json`, reporting the unclaimed. Run once, it would enumerate
the remaining eight stages' hidden work in a single pass instead of discovering
it stage by stage. This is small — the data is already in the analysis document
and `symbols.json` — and it is the highest-leverage tooling addition available.

### 5.5 Ledger review cost is still unmeasured

Stage 1 recorded its ledger cost, but with all 43 entries taking one shared
disposition it measured CLI overhead rather than a real per-function rate. 2a's
193 entries across five classes are the first chance to get a usable number for
stages 3–5, which face modules of 88 and 127 methods. The plan should capture it
deliberately rather than as a footnote.
