# Foundation reconstruction: divergences

This file is shared and append-only across all ten stages of the Foundation
reconstruction programme (spec §4). Each stage appends its own section below;
earlier sections are not edited by later stages.

## Stage 1 — `NSGeometry.m`, `NSRange.m`, `NSDecimal.m` (geometry-range-decimal)

Companion artifacts for this stage: `source-map.json` (43/43 reference
functions mapped, 0 unmapped, 0 duplicate candidates, 0 boundary disputes)
and `ledger.json` (43 entries, all reviewed).

### Gate 1 — `abi-check`: PASS, no divergence

`binrecon abi-check` against the guest-compiled `NSGeometry.o`, `NSRange.o`
and `NSDecimal.o` reports `abi-check: ABI matches`, exit 0, against the
committed `abi/*.json` baseline. No class, category, ivar, instance-size or
selector divergence was found — nothing to fix here.

### Gate 2 — test suites: PASS, no divergence

`test_decimal`, `test_geometry` and `test_range` each report
`PASSED: 0 failure(s)` on the guest, covering the 28 behaviourally-tested
functions (14 in `NSGeometry.m`, 3 in `NSRange.m`, 11 in `NSDecimal.m`).

### Reference behaviours recorded during reconstruction (Tasks 12–14)

These are genuine, confirmed behaviours of Apple's shipped binary — not
bugs in this reconstruction — recorded here because later stages have no
other source for them.

- **`_NSIntersectsRange` is exported by the reference but declared in no
  public header.** `NSRange.h` was deliberately left unmodified (Global
  Constraint); the function is declared with external linkage directly in
  `NSRange.m` instead.
- **`NSDecimalPower(result, number, 0, mode)` inherits the operand's sign**
  rather than always producing an unsigned/positive 1, even though
  mathematically `x^0 == 1` for any nonzero `x`. Confirmed directly in the
  decompiled body (`v6 = *((_BYTE*)number+1) & 0x10; ... *((_BYTE*)result+1)
  |= v6;`). No test in this stage's suite exercises a negative base to
  `^0`, so this doesn't surface as a failure here.
- **`NSDecimalDivide` ignores its `roundingMode` argument entirely** and
  never reports `NSCalculationLossOfPrecision`, consistent with the
  header's own "could be silently inexact" comment on the declaration.
- **The `NSCoder (NSGeometryCoding)` category's six methods call the
  variadic `-encodeValuesOfObjCTypes:` / `-decodeValuesOfObjCTypes:`**
  (already declared in `NSCoder.h`'s `NSExtendedCoder` category), passing
  one address per float field with a flat type string (`"ff"` for
  point/size, `"ffff"` for rect) — not the singular
  `-encodeValueOfObjCType:at:` / `-decodeValueOfObjCType:at:` pair on the
  whole struct. Confirmed via the referenced selector's IDA symbol name
  (`paEncodevaluesof...`/`paDecodevaluesof...`) and the multi-address
  argument-push pattern in all six methods' disassembly. This affects wire
  compatibility with anything that calls `decodeValuesOfObjCTypes:`
  directly expecting this exact type string.
- **`NSMouseInRect`'s y-range is half-open in opposite directions depending
  on `flipped`.** x is always `[minX, maxX)`. y is `[minY, maxY)` when
  flipped, but `(minY, maxY]` when not — i.e. which edge is inclusive
  flips with `flipped`, not just the sense of "up is which way".
  `NSPointInRect(p, r)` is structurally identical, instruction-for-
  instruction, to `NSMouseInRect(p, r, YES)`.
- **`NSIntersectionRange` returns `{range1.location, 0}` — not `{0, 0}` —
  for a zero-length `range1` nested inside `range2`.** The location is
  preserved even though the length collapses to zero.
- **Struct-returning functions pass the hidden output pointer in EBX, not
  on the stack.** Every function in this module that returns an `NSRect`
  (`NSInsetRect`, `NSIntegralRect`, `NSUnionRect`, `NSIntersectionRect`,
  `NSOffsetRect`, `-[NSCoder decodeRect]`) loads no output pointer from the
  stack; the prologue's `push ebx` preserves whatever the caller already
  placed there, and the epilogue returns it via `mov eax, ebx`. This
  matters for every later struct-returning module: IDA's automatic
  stack-frame struct recovery assumes the classic "hidden pointer is the
  first stack argument" convention and mislabels every subsequent field by
  one slot until this is corrected by re-disassembling with raw numeric
  `ebp+offset` displacements instead of trusting IDA's symbolic names.
- **`NSStringFromRange`'s exact format literal (`"{%u, %u}"`) is inferred
  by analogy with `NSGeometry.m`'s confirmed `"{%g, %g}"`/`"{{%g, %g},
  {%g, %g}}"` literals, not confirmed from the binary.** The string sits
  behind an indirect pointer table this stage's tooling doesn't resolve. A
  residual evidence gap, resolvable in stage 3 once `NSString`'s own
  module is reconstructed and the string tables are in scope.

### Test-expectation corrections (reference is authority; the brief's test text was wrong)

Four corrections were made against the brief's verbatim test text during
Tasks 12–13, all confirmed against the decompiled reference before the test
was changed — no assertion's *meaning* changed, only what was needed for the
test to compile or to check something well-defined.

1. **C89 mid-block declarations (Task 12, `test_decimal.c`).** gcc 2.7.2.1
   rejects a variable declaration that follows a statement in the same
   block. `test_add_with_differing_exponents`, `test_divide`,
   `test_power_of_zero_is_one`, `test_normalize_aligns_exponents`,
   `test_round_down_truncates` and `test_round_in_place` each declared a
   variable (`expected`, `hundred`, etc.) after an earlier `CHECK(...)` in
   the same block. Fixed by hoisting each declaration to the top of its
   block — pure mechanical reordering.
2. **`test_copy` compared against uninitialized memory (Task 12,
   `test_decimal.c`).** `NSDecimalCopy` only copies the header fields plus
   mantissa words `0.._length-1` (confirmed: `*(_DWORD*)destination &=
   0x3FFFu` clears only the reserved bits; the mantissa loop runs `while
   (v5 < destination.length)`). The original test declared `target`
   uninitialized, then `memcmp`'d the *entire* struct against `source` —
   only well-defined if `target`'s untouched tail happened to already be
   zero. Fixed by zero-initializing `target` via `make(0,0,0,0,0)` so the
   full-struct comparison is well-defined.
3. **`test_multiply_by_negative`'s raw-mantissa check was invalid after
   mandatory compaction (Task 12, `test_decimal.c`).** `NSDecimalMultiply`
   unconditionally clears `isCompact` and calls `NSDecimalCompact()` on its
   result before returning (confirmed in the decompiled tail). `4 * -5 =
   -20`, and the reference's compaction reduces that to mantissa `2`,
   exponent `1`, not raw mantissa `20`. The original test asserted
   `r._mantissa[0] == 20` directly; fixed to assert `r._isNegative == 1`
   plus `NSDecimalCompare(&r, &expected) == NSOrderedSame` against
   `make(1,0,1,20,0)` — a value comparison, robust to whichever compacted
   representation the reference produces, matching how every other
   compaction-sensitive test in the file already compares.
4. **The `CHECK_RECT` macro's parameters collided with the struct field
   names used in its own body (Task 13, `test_geometry.c`).** `CHECK_RECT`
   was declared with parameters `x, y, w, h`, then referenced
   `.origin.x`/`.origin.y`/`.size.width`/`.size.height` inside its body.
   Token-by-token macro substitution turns `.origin.x` into `.origin.2.0`
   for a call like `CHECK_RECT(r, 2.0, 3.0, ...)` — a preprocessor-level
   bug on any standards-conforming C compiler, not a gcc-2.7.2.1 quirk.
   Fixed by renaming the macro's parameters to `ex, ey, ew, eh` — a pure
   rename, no assertion or expected value changed.

### Functions written but not behaviourally tested this stage

15 of the 43 reconstructed functions/methods have no test in this stage's
28-function suite. Both groups compile and link correctly (proven by Gate 1
and by the test binaries linking against them), but their *behaviour* is
unverified until the stage that owns their test:

| Function | Module | Picked up by |
|---|---|---|
| `NSStringFromPoint`, `NSStringFromSize`, `NSStringFromRect`, `NSPointFromString`, `NSSizeFromString`, `NSRectFromString` | `NSGeometry.m` | Stage 3 |
| `NSStringFromRange`, `NSRangeFromString` | `NSRange.m` | Stage 3 |
| `NSDecimalString` | `NSDecimal.m` | Stage 3 |
| `-encodePoint:`, `-decodePoint`, `-encodeSize:`, `-decodeSize`, `-encodeRect:`, `-decodeRect` (`NSCoder (NSGeometryCoding)`) | `NSGeometry.m` | Stage 2 |

All nine string-facing functions are deferred because they need a working
`NSString` (`-characterAtIndex:`, `-substringWithRange:`, `+stringWithFormat:`,
etc.) to test meaningfully — this stage only links against minimal,
unreviewed stand-in stubs written for the guest build, never committed. The
six `NSGeometryCoding` methods are deferred because verifying their wire
format needs a working `NSCoder`/archiving path, which stage 2 owns.

### Gate 3 — `compare`/ledger: evidence only, not a pass/fail gate

**Headline finding for stages 3–5: `binrecon compare`'s `normalized-functions`
acceptance level cannot produce a function-level correlation for a
multi-module excerpt rebuilt as a single relocatable object, and this is
structural, not a bug to fix.** `compare_artifacts` keys each function by
`(section, occurrence-of-that-section-name, byte-start, byte-end)` — a purely
positional key within each document's own normalized section layout, not by
symbol name. The reference's 43 functions sit at their original scattered
offsets across an 80-module, 1,630,488-byte linked dylib's `__text` section;
this stage's rebuilt object packs the same 43 functions (plus internal static
helpers and PIC stub thunks the reference never separately exposes — 75
functions in total) into one small relocatable object built by concatenating
three source files. No function's byte range coincides with its counterpart's
at the same section-relative offset in the other document, so every single
one of the 118 functions `compare` reports comes back `missing-reference` or
`missing-rebuilt` — not because any function's *behaviour* diverges, but
because the position-keyed matcher has no way to correlate them at all.

This was diagnosed once (not per-function) and confirmed by cross-checking
against Gate 1 (structural ABI, passing) and Gate 2 (behavioural tests,
passing): both gates prove the 43 functions are structurally and
behaviourally correct where they're exercised, so the `compare` output
carries no additional signal beyond "the excerpt was repackaged," and every
entry is dispositioned identically.

**Ledger disposition: all 43 entries, `intentional-mismatch`.** `ledger.json`
records one status per reference function (matching the 43 functions in
`analysis-reference-ida.json`, not the 75 in the rebuilt object, since the
ledger's job is to disposition *reference* evidence). Every entry carries the
same reviewer-recorded reason: `compare`'s positional matcher cannot
correlate a scattered-extraction rebuild, so the missing-rebuilt/
missing-reference status is a structural artifact of the extraction, not a
real divergence; Gate 1 and Gate 2 are this stage's actual correctness
evidence, and `source-map.json`'s 43/43 mapped, 0 unmapped confirms every
reference function has a source counterpart. All 43 were transitioned
`unexamined` → `signature-confirmed` → `intentional-mismatch` via
`binrecon ledger`, reviewer "Task 15 report pass".

No entry required a `real, fix it` disposition — nothing here was actually
wrong, only unresolvable by this comparison mode at this stage's scale.

### The observed ledger review cost

Measured wall-clock from the finished `compare` run (16:18:52 EDT) to every
one of the 43 entries carrying its final `intentional-mismatch` status
(16:22:29 EDT): **217 seconds for 43 entries, ≈5.0 s/entry.**

**This number should not be extrapolated as a per-function analysis rate.**
Because every entry shared one disposition (diagnosed once, see above), the
217 s is almost entirely `binrecon ledger` CLI process-startup overhead — 86
separate invocations (two per entry: the mandatory `unexamined` →
`signature-confirmed` step, then → `intentional-mismatch`), each paying a
fresh Python-venv-import cost of roughly 2.5 s. It measures *mechanical
ledger-CLI overhead for one shared disposition*, not the cost of
independently reading and judging 43 (or 88, or 127) separate pieces of
disassembly.

What stages 3–5 actually need to plan for is upstream of the ledger CLI: (1)
confirm early, before committing to a rebuilt-object strategy, whether their
module's function count and rebuild shape will hit the same positional-match
failure this stage did — if their `analysis_scope` also draws its 43 (or 88,
127) functions from scattered offsets across the reference and their rebuild
also concatenates several source files into one small object, they should
expect the identical "compare produces no correlated pairs" outcome and can
skip budgeting per-function diff-reading time for it entirely; (2) if any
functions genuinely do need individual review (e.g. because the module is
reconstructed and analyzed as a single self-contained rebuild that IS
comparable in scale to its reference slice), the drvPCFloppy stage's own
figure is the better basis: 69 of 222 functions there needed real,
independent written analysis, each taking substantially longer than 5 s once
actually read.

### Toolchain gaps found and fixed during this stage (own `binrecon:` commits)

Two binrecon gaps were discovered and fixed while producing this stage's
Gate 3 evidence — both because this is the first time the pipeline has ever
analyzed an *unlinked relocatable* rebuild rather than a linked dylib or
executable, so neither code path had been exercised before:

1. `binrecon.macho`'s i386 relocation reader rejected any scattered
   relocation type other than vanilla. gcc 2.7.2.1's "`call $+5`; `pop reg`"
   PIC-base idiom for addressing local floating-point constants emits a
   `GENERIC_RELOC_SECTDIFF` scattered relocation immediately followed by a
   scattered `GENERIC_RELOC_PAIR` — present in every one of this stage's
   three built objects (`NSGeometry.o`, `NSRange.o`, `NSDecimal.o` all
   touch floating point). Fixed to decode the pair (commit
   `b4cb1d66`).
2. Analyzing an unlinked object with IDA creates a small `ABS`-class
   segment (for absolute-valued symbols) that the exporter's zero-fill
   classification didn't recognize, alongside a raw byte-diff walk in
   `compare` that rejected a zero-length read once the smaller of two very
   differently-sized artifacts (a 1,630,488-byte linked dylib vs. a
   23,412-byte relocatable rebuild) was fully consumed while the walk kept
   going against the larger one. Fixed both (commit `9a7d27e7`).

Neither fix touches `src/Kits/Foundation`; both are narrowly-scoped,
test-covered `binrecon:` commits landed before this stage's own commit, per
this repo's established practice of fixing tooling gaps in their own
commits as they're discovered (e.g. Task 2's `MH_DYLIB` acceptance).

### Findings from the final whole-branch review (recorded here so they are not lost)

- **Task 13 deleted the pre-existing `@implementation NSValue` stubs
  (`+valueWithPoint:`, `+valueWithSize:`, `+valueWithRect:`,
  `-pointValue`, `-sizeValue`, `-rectValue`) from `NSGeometry.m`.** These
  were TODO-stub bodies (`return nil;` / `return NSMakePoint(0, 0);`) left
  over from before the module was reconstructed; commit `fc76240a` removed
  them because `__OBJC,__module_info` places the `NSValue` geometry
  category in `NSValue.m`, not `NSGeometry.m` — the deletion was correct
  for this module's scope. Verified: `src/Kits/Foundation/NSValue.m`
  exists but implements only `+valueWithPointer:`/`-pointerValue`; it
  contains none of `+valueWithPoint:`, `+valueWithSize:`,
  `+valueWithRect:`, `-pointValue`, `-sizeValue` or `-rectValue`. **These
  six header-declared entry points currently exist nowhere in the tree.**
  Stage 5 (`NSValue.m`) must supply them.
- **The `NSDecimal` mantissa is base-65536, not base-10000 as the plan
  originally stated; corrected in commit `e18c5fe3`.** Stage 5's
  `NSDecimalNumber` depends on this: the mantissa is a plain multi-word
  binary integer (one `unsigned short` per digit, little-endian), scaled
  by `10^exponent` for the decimal value — not a base-10000
  binary-coded-decimal representation.
- **The bignum helpers in `NSDecimal.m` are reconstructed as private
  statics under invented `BigXxx` names** (`BigTrim`, `BigFromMantissa`,
  `BigToMantissa`, `BigAddMantissas`, `BigSubtractMantissas`,
  `BigMultiplyMantissas`, `BigDivideByShort`, `BigMultiplyByShort`,
  `BigAddShort`, `BigDivideMantissas`, etc.) — see the open item below,
  which supersedes this: the reference exports this layer under real
  names, so it is a claimed cross-TU interface, not purely-internal
  scratch code.

#### Open item: the unclaimed exported bignum layer (`_NSIntegerXxx`)

The reference binary (`Foundation-i386`) exports twelve external
`__TEXT,__text` symbols that this stage's `NSDecimal.m` reconstructed as
private statics under invented `BigXxx` names instead of their real
exported names:

`_NSIntegerAdd`, `_NSIntegerSubtract`, `_NSIntegerMultiply`,
`_NSIntegerDivide`, `_NSIntegerCompare`, `_NSIntegerCopy`,
`_NSIntegerAddShort`, `_NSIntegerSubShort`, `_NSIntegerMultiplyByShort`,
`_NSIntegerDivideByShort`, `_NSIntegerMultiplyByPowerOf10`,
`_NSIntegerMaxPowerOf10Multiplier`.

Verified directly against the reference slice:

- All twelve are `binding: external`, `section: __TEXT,__text`, at
  addresses `0x425a1510`–`0x425a2020`.
- They are declared in no public header (confirmed: absent from
  `NSDecimal.h` and every other Foundation header), so `attach_symbols`
  — which attributes C symbols from headers — cannot see them, and they
  appear in no `abi/*.json`.
- They are a real cross-TU interface, not internals: byte-scanning the
  callers' own bodies for `call rel32` confirms `__NSCStringToDecimal`
  (at `0x425a2950`) calls `_NSIntegerMultiplyByShort` (from
  `0x425a2a3f` and `0x425a2b23`) and `_NSIntegerAddShort` (from
  `0x425a2a75` and `0x425a2b59`), and `_decimaltostr` (at `0x425a3c90`)
  calls `_NSIntegerDivideByShort` (from `0x425a3d71`) — all well outside
  the `NSInteger*` functions' own `0x425a15xx`–`0x425a20xx` address
  range, i.e. called from other translation units.

Our reconstruction currently provides equivalent behaviour under
different private (`BigXxx`) names, so nothing links against the real
`_NSIntegerXxx` symbols — this is a naming/API-surface gap, not a
behavioural one. Ownership (does this layer belong in `NSDecimal.m` or
move to `NSDecimalNumber.m`?) and whether to reconstruct it under its
real exported names must be settled by stage 5, the first stage to
depend on `NSDecimal`'s bignum layer from outside this module.

**This is a class of omission, not a one-off**: any external
`__TEXT,__text` symbol with no public header declaration is invisible to
the current attribution method (`attach_symbols` only sees symbols
`assignment` names, and `assignment` is declared from public headers). A
binrecon check that every external `__TEXT,__text` symbol is claimed by
some module's `text_symbols` would catch this class in each of the nine
remaining stages, rather than relying on a reviewer noticing it by hand
as happened here.

## Stage 2a — `NSZone.m`, `NSObject.m`, `NSProxy.m`, `NSAutoreleasePool.m`, `NSPrivate.m` (object core)

Companion artifacts for this stage: `object-core/source-map.json` (193/193
reference functions mapped, 0 unmapped, 0 duplicate candidates, 0 boundary
disputes) and `object-core/ledger.json` (193 entries, all reviewed). Five
modules, 193 functions: `NSZone.m` (25 C functions), `NSObject.m` (37
instance + 47 class methods, plus `_NSZombie`'s 9 instance methods = 93),
`NSProxy.m` (27 instance + 20 class = 47), `NSAutoreleasePool.m` (8 instance
+ 15 class = 23) and `NSPrivate.m` (`_NSAutoreleasedMallocMemory`, 4
instance + 1 class = 5).

### Gate 1 — `abi-check`: PASS (`ABI matches`), after two rounds of corrections recorded below

`--abi-dir` contains stage 1's three documents as well as stage 2a's five;
`abi-check` reports any module with no `--built` object as a divergence.
The final verification run therefore compiles **all eight** modules and
points `--abi-dir` at the committed
`src/Kits/Foundation/reconstruction/abi` directly, which checks the whole
branch's ABI surface in one pass rather than only stage 2a's share of it.
(An earlier run copied just the five 2a documents to a scratch directory
instead; passing all eight objects is strictly stronger and needs no
scratch copy.)

The first run against the five freshly-built i386 objects reported five
divergences, all "unexpected exported symbol": `_NSAutoreleaseObject`,
`__NSPushAutoreleasePool` and `__NSPopAutoreleasePool` in
`NSAutoreleasePool.m`, and `__NSZombieClassForClass` and
`__NSOriginalClassForZombieClass` in `NSZone.m`. None of the five 2a ABI
documents' `text_symbols` lists these — they were never part of stage 2a's
193-function scope (Task 3's scope draws only from header-declared C
functions plus the 25 explicitly-added `NSZone.m` functions), so
`abi-check`'s "local symbols are ours to choose, external ones must match
the evidence" rule (`abi_check.py`'s own comment) correctly flagged all
five as unaccounted-for exported surface.

Two were fixed at the source correctly, confirmed safe by checking every
call site first:

- **`_NSZombieClassForClass`** (`NSZone.m`) is called only from within that
  same file (`NSDeallocateObject`) — made `static`. No behavioural change.
  Confirmed against the reference: `_NSZombieClassForClass` is **not**
  present in `Foundation-i386`'s exported symbol table, so `static` is
  correct here — there is no reference behaviour to diverge from.
- **`_NSOriginalClassForZombieClass`** (`NSZone.m`/`NSObject.m`) was a
  reverse `zombieClass -> originalClass` lookup existing solely so
  `NSObject.m`'s `_NSZombie` diagnostic could recover the original class's
  name — but that name is already encoded in the zombie class's own
  `"NSZombie_<originalClass>"` name string (set by
  `_NSZombieClassForClass` itself), so the whole reverse-lookup function
  was redundant. Removed; `NSObject.m`'s `logMessageAndRaise` now strips
  the fixed `"NSZombie_"` prefix off `self->isa->name` directly, with the
  same observable diagnostic text as before. Confirmed against the
  reference: `_NSOriginalClassForZombieClass` is also **not** present in
  `Foundation-i386`'s exported symbol table, so deleting it (rather than
  claiming it) is correct. This also let a genuine pre-existing bug
  surface and get fixed (see below): `NSDebug.m` still had TODO-stub
  bodies for 11 of `NSAutoreleasePool`'s 15 class methods
  (`NSAutoreleasePoolDebugging`, declared in `NSDebug.h`), which is a real
  duplicate-`@implementation`-`NSAutoreleasePool` hazard now that
  `NSAutoreleasePool.m` implements them for real — confirmed by
  `abi/NSAutoreleasePool.json` listing all 15 class methods directly under
  the class (no separate category), matching the reference's own
  `__OBJC,__module_info`, so `NSAutoreleasePool.m` is where the real
  implementation belongs and now lives. `NSDebug.m`'s stub block was
  removed (Makefile already listed `NSDebug.m`; no registration change
  needed). This is the same class of "attribute-by-declaring-header
  overridden by the reference's actual module placement" divergence
  `NSZone.m` itself already represents (see below) — not new. The new
  prefix-stripping logic in `NSObject.m`'s `logMessageAndRaise` is not
  exercised by any test — neither zombie test in `test_object.m` actually
  sends a message to a zombie object (both only inspect `object->isa` and
  `zombieClass->name` directly), so this diagnostic path was already
  untested before this change and remains so after it; see the
  untested-methods table below.

**The other two — `_NSPushAutoreleasePool`/`_NSPopAutoreleasePool`
(`NSAutoreleasePool.m`) — were fixed wrongly in the original pass, and
that mistake is corrected here.** They were made `static` on the
reasoning that only `-initWithCapacity:`, `-release` and
`+releaseAllPools` in this same file call them. That reasoning only
applies to symbols the reference itself does not export. Checked directly
against the reference slice (`Foundation-i386`): **both are `binding:
external`, `section: __TEXT,__text`** — Apple exports them, exactly like
`_NSAutoreleaseObject` below. Making them `static` does not merely fail to
match an internal convention; it silences a real "unexpected exported
symbol" finding by making the symbol *not exported*, which is the
opposite of what `abi-check` exists to enforce (`abi_check.py`'s own
comment: "local symbols are ours to choose, external ones must match the
evidence" — these are not local, the evidence says so). Any translation
unit that linked against `_NSPushAutoreleasePool`/`_NSPopAutoreleasePool`
in Apple's Foundation, or a client relying on them, would fail to link
against a build with them `static`. **Corrected**: both restored to
external linkage in `NSAutoreleasePool.m`, and both — together with
`_NSAutoreleaseObject` — are now claimed by name in
`reconstruction/symbols.json` under `NSAutoreleasePool.m`.

**That correction was necessary but not sufficient, and the guest re-run
found the rest of it.** Restoring external linkage exposed a second,
separate error the `static` had been masking: the C identifiers in
`NSAutoreleasePool.m` were spelled `_NSPushAutoreleasePool` and
`_NSPopAutoreleasePool`, *with* a leading underscore. i386 Mach-O prefixes
another underscore when mangling, so those definitions emitted
`__NSPushAutoreleasePool`/`__NSPopAutoreleasePool` — two symbols the
reference does not have — while leaving the two the reference *does*
export undefined. `abi-check` reported exactly that, as one missing and
one unexpected symbol per function. Confirmed against the reference's
symbol table: it contains `_NSPushAutoreleasePool` and
`_NSPopAutoreleasePool` and no double-underscore variant of either, so the
C-level names are `NSPushAutoreleasePool`/`NSPopAutoreleasePool`, matching
`NSAutoreleaseObject` in this same file, which was already spelled
correctly. Both were renamed at their definitions and their three call
sites. No header declares either name, so no header changed. With that,
`abi-check` reports `ABI matches` across all eight modules.

**`_NSAutoreleaseObject`, defined in `NSAutoreleasePool.m`, is genuinely
called directly (`call _NSAutoreleaseObject`, not `objc_msgSend`) from
`-[NSObject autorelease]` and `-[NSProxy autorelease]`**, confirmed
straight from the reference's disassembly (`-[NSObject autorelease]` at
`0x42503fd8`: `call _NSAutoreleaseObject` at `0x42503fd8+8`, resolved via
the analysis JSON's own `calls` list, not inferred). It was already left
external (correctly), but unclaimed by any ABI document — the original
pass's residual, disclosed divergence. No header declares any of the
three symbols (`_NSAutoreleaseObject`, `_NSPushAutoreleasePool`,
`_NSPopAutoreleasePool`; confirmed: absent from every
`src/Kits/Foundation/*.h`), so they are invisible to `attach_symbols`'
header-only attribution and were never captured in any of the five 2a ABI
documents — this is the same class of gap Task 2's `symbol-audit` already
flagged programme-wide (146 `__NS`-prefixed private exports no header
declares), just the first concrete instance stage 2a's own reconstruction
needed to actually define rather than merely observe as unclaimed. All
three are autorelease-pool machinery with no natural header home and
`NSAutoreleasePool.m` is a real reference module, so all three are
assigned there in `symbols.json` — the same category as the other 145
undeclared private exports, not a new kind of gap.

`abi/NSAutoreleasePool.json` was regenerated from `symbols.json` (`binrecon
abi --module NSAutoreleasePool.m`) rather than hand-edited, so it stays
derived evidence; it now lists all three names in `text_symbols`, with no
other field changed (verified by diffing the regenerated document against
its previous committed version — same classes, ivars, selectors, `types`
strings).

**Lesson for the remaining eight stages, since this will recur:** an
"unexpected exported symbol" from `abi-check` means the symbol needs
*claiming*, not suppressing. `static` is only correct when the reference
itself does not export the symbol (as it correctly was for
`_NSZombieClassForClass` above) — check the reference's own symbol table
before changing linkage, not just this file's own call sites. Two of
three symbols in the original pass were static-ed based on caller
analysis alone, without that check, and that inverted the project's own
rule that the reference is the authority and source changes to match it,
not the other way around.

**Guest verification: done, against this exact tree.** The linkage fix was
made while the ppc guest at `10.10.0.241` was powered off, so it was
committed on the strength of the reference symbol table alone and both
gates were left open. The guest has since returned and both were re-run
from scratch:

- All eight modules cross-compiled to i386 objects
  (`cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers`),
  all eight clean.
- `binrecon abi-check --abi-dir src/Kits/Foundation/reconstruction/abi`
  with `--built` for all eight: **`ABI matches`, exit 0.**
- All five suites rebuilt native ppc and run: **`PASSED: 0 failure(s)`**
  each.

That re-run is what surfaced the underscore-spelling error above, which
neither the reference symbol-table check nor local reasoning had caught —
the `static` had hidden it, and "this changes only linkage, not logic"
was true and still missed a real ABI defect. Worth remembering for the
remaining stages: a gate deferred because the hardware is down is *not*
a gate that can be reasoned closed.

One gap the re-run did expose and does **not** close: stage 1's three
suites (`test_decimal`, `test_geometry`, `test_range`) still do not link
against the committed `link_stubs.m`, which supplies `NSString`,
`NSException`, `NSMethodSignature` and
`_NSConstantStringClassReference` but not `NSCoder` or
`_NSDecimalSeparator`. Those three were verified in stage 1 with stubs
written on the guest and never committed, so they remain
non-reproducible from the tree — the same non-reproducibility Task 6's
`link_stubs.m` was created to end, fixed for stage 2a's five suites but
not retrofitted to stage 1's three.

### Gate 2 — test suites: PASS, no divergence

All five suites report `PASSED: 0 failure(s)` on the guest against the
current tree (including the `-addObject:` fix and the zombie-lookup
simplification above): `test_zone`, `test_refcount`, `test_object`,
`test_proxy`, `test_pool`.

### The `-addObject:` bookkeeping divergence: closed

Task 10 left `-[NSAutoreleasePool addObject:]` (the instance method)
bypassing `NSAutoreleaseObject` entirely, appending straight to the
target pool's own frame. The reference (`0x425732d8`) calls
`_NSAutoreleaseObject` *first* — recording the object against the
**innermost** pool and incrementing the global autoreleased-object
counter — then re-homes it into the target pool's slot by shifting every
more-deeply-nested frame along a shared per-thread buffer. Task 10's
version skipped the counter bump entirely, so `[somePool addObject:obj]`
followed by `[NSAutoreleasePool totalAutoreleasedObjects]` returned one
less than the reference would.

Closed this task: `-[NSAutoreleasePool addObject:]` now calls
`NSAutoreleaseObject(anObject)` first (bumping the counter and recording
against the innermost frame, exactly as the reference does), then — if
`self`'s own frame differs from the innermost one — removes the tail
entry from the innermost frame and appends it to `self`'s frame instead,
reproducing the reference's externally observable "record against
innermost first, then re-home into the target pool" contract without its
buffer-shifting internals. All five suites still pass after this change.
No test in this stage calls the instance method (still true after this
fix — see the untested-methods table below), so the fix is verified by
code inspection against the disassembly and by the five suites continuing
to pass, not by a new assertion.

### Gate 3 — `compare`/ledger: evidence only, not a pass/fail gate

Same structural outcome as stage 1, now confirmed at 193-function scale.
The rebuilt object was produced by compiling the five modules to i386
objects (`cc -c -arch i386`, the same objects used for Gate 1) and
combining them with `ld -r -arch i386` into one 55,176-byte relocatable
object (249 functions once internal statics and PIC stub thunks are
counted — the same "extra" pattern stage 1 observed, `75` for its `43`).
`compare --require normalized-functions`: `code=442 relocation=1
symbol-string-order=0 layout=32 padding=1 metadata=2004`; every one of
the 442 function-level findings is `missing-reference-function` (249,
covering all of the rebuilt object's own functions) or
`missing-rebuilt-function` (193, covering all of the reference's
scoped functions) — 0 functions were positionally correlated. This is
`compare`'s positional `(section, occurrence, byte start/end)` matcher
failing to correlate a 5-file excerpt rebuild against the reference's
profile-guided scattered layout across an 80-module dylib, exactly as
stage 1 diagnosed and predicted would recur — not a behavioural or
instruction-level divergence in any of the 193 functions themselves.

**Ledger disposition: all 193 entries, `intentional-mismatch`.**
`object-core/ledger.json` records one status per reference function
(matching the 193 functions in `analysis-reference-ida.json`, not the 249
in the rebuilt object). Every entry carries the same reviewer-recorded
reason: `compare`'s positional matcher cannot correlate a scattered-
extraction rebuild, so the missing-rebuilt/missing-reference status is a
structural artifact of the extraction, not a real divergence; Gate 1 and
Gate 2 are this stage's actual correctness evidence, and
`source-map.json`'s 193/193 mapped, 0 unmapped confirms every reference
function has a source counterpart. All 193 were transitioned `unexamined`
-> `signature-confirmed` -> `intentional-mismatch` via `binrecon ledger`,
reviewer "Task 11 report pass". No entry required a `real, fix it`
disposition.

**Seeding note (tooling, not a code divergence):** an unscoped
`analyze --ledger` run against the full 1,630,488-byte reference (needed
to seed 193 `unexamined` ledger entries from a fresh comparison) exceeds
the IDA adapter's 64 MiB output cap (68,085,924 bytes observed, rejected)
— the same cap Task 3 of this stage already measured as dominated by
fixed per-run overhead, not scoped-function count. Worked around by
reusing stage 2a's own `analysis_scope` (the 193 committed ranges) plus
one extra `{0, 65536}` range covering the rebuilt object's own (much
lower, near-zero-based) address space, in a scratch profile never
committed to the repo. Not a code or evidence divergence; a tooling
scaling note for stages 3-5, whose modules (88 and 127 functions) will
hit the same cap on any unscoped ledger-seeding attempt.

### The measured ledger review cost

Measured wall-clock from the seeded ledger's 193 `unexamined` entries to
every one carrying its final `intentional-mismatch` status, via 386
separate `binrecon ledger` invocations (two per entry: the mandatory
`unexamined` -> `signature-confirmed` step, then ->
`intentional-mismatch`): **189 seconds for 193 entries, ≈0.98 s/entry
(≈0.49 s/invocation, 386 invocations).**

As stage 1 noted and this stage confirms at more than 4x the scale: this
number is not a per-function analysis rate. Every entry shares one
disposition (diagnosed once, in "Gate 3" above), so the measured time is
almost entirely `binrecon ledger` CLI process-startup overhead — 386
separate Python-venv-import invocations. At 193 entries this stage now
has the first genuinely usable comparison point against stage 1's
43-entry, 217-second/86-invocation figure (≈5.0 s/entry, ≈2.52
s/invocation there): **≈5x faster per invocation this run** (0.49 s vs
2.52 s), which is almost certainly warm-filesystem/venv-import caching
from this session's many prior `binrecon` invocations rather than a real
"cost falls as scale grows" trend — the two measurements ran in different
sessions on the same machine, not a controlled comparison, so stages 3-5
should not extrapolate a specific per-invocation constant from either
number. The comparison that *does* generalize: both stages' costs were
dominated by CLI startup, not analysis time, because both stages'
`compare` runs produced one shared disposition rather than genuinely
distinct per-function judgements. What stages 3-5 (88 and 127
functions) actually need to plan for remains upstream of the ledger CLI:
confirm early whether their rebuild will hit the same positional-match
failure (if so, skip budgeting per-function diff-reading time for Gate 3
entirely, as both stage 1 and this stage did), and reserve real
independent-review time only for functions that need it on the
drvPCFloppy-style basis stage 1's own report already established (69 of
222 functions there needed real, independent written analysis).

### `NSZone.m`: 25 C functions in a module the reference does not have

All 25 zone/allocation/refcount C functions (page allocation, zone
allocation, and the retain-count side table) live in `NSZone.m` — a
module the reference's `__OBJC,__module_info` does not have (it names 80
units in the full binary, none of them `NSZone.m`; these 25 functions sit
scattered across other modules' address ranges in the reference, the same
"scattered extraction" pattern Gate 3 measures for every function in this
stage). Seven of the 25
(`NSAllocateObject`, `NSDeallocateObject`, `NSCopyObject`,
`NSShouldRetainWithZone`, `NSIncrementExtraRefCount`,
`NSDecrementExtraRefCountWasZero`, `NSExtraRefCount`) are declared in
`NSObject.h`, not a `NSZone.h` this tree has — spec §2.1's reasoning
applies: attributing a C function by its declaring header is the
project's default rule, but grouping all 25 zone/allocation/refcount
functions into one new file mirrors how the reference's own memory
layout keeps them address-adjacent and behaviourally coupled (the page
allocator, the zone allocator built on it, and the retain-count table
that zone-allocates its own storage), and avoids scattering 18
header-undeclared private functions with no natural header home across
existing files. **A divergence in file organisation only — symbols,
linkage (except the one Gate 1 residual above) and behaviour are
unchanged**, confirmed by Gate 1 matching all 25 of `NSZone.m`'s own ABI
document exactly and Gate 2's suites exercising them successfully.

### `NSPrivate.m`: the programme's first new source file

`_NSAutoreleasedMallocMemory`'s implementation (4 instance + 1 class
method) lives in `src/Kits/Foundation/NSPrivate.m` — a file the tree did
not have before Task 10, because the original stub-generation pass only
created a `.m` file per **public** header, and `_NSAutoreleasedMallocMemory`
has none. Registered in the `Makefile`'s `CLASSES` list, between
`NSPortNameServer.m` and `NSProcessInfo.m`, preserving the existing
grouping and trailing-backslash continuations; no `HFILES`/
`PUBLIC_HEADERS` entry, since there is no header.

### The `binrecon symbol-audit` inventory (Task 2, programme-level)

373 exported C functions in the reference binary were claimed by no
module before this stage; assigning `NSZone.m`'s 25 dropped that to 348 —
confirmed exactly by Task 2/Task 3's cross-check. 348 is still roughly
half of Foundation's 736 total C functions. 146 of the 348 are
`__NS`-prefixed private exports declared in no header at all, so the
project's attribute-by-declaring-header rule can never claim them
regardless of which stage runs — `_NSAutoreleaseObject`, the one residual
Gate 1 finding above, is a concrete instance of exactly this bucket, not
a new discovery: Task 2 already predicted stages would run into
undeclared private exports they must actually *implement* (not merely
list as unclaimed), and this stage is the first time that happened. The
remaining clusters map to specific future stages (`NSSimple`/`NSUnicode`
for stage 3 strings, `NSHash`/`NSMap` for stage 4 collections, etc., per
Task 2's own breakdown) — this remains a programme-level finding, not
resolved by any single stage.

### Substitutions for unreconstructed machinery

- The retain-count overflow store (`NSZone.m`'s `ExtraRefCountOverflow*`)
  and the zombie class table (`NSZone.m`'s `zombieClasses` array) use
  private linear-scan arrays rather than `NSMapTable`, because
  `NSMapTable.m` is stage 4's territory.
- `NSPushAutoreleasePool`/`NSPopAutoreleasePool`/`NSAutoreleaseObject`
  (`NSAutoreleasePool.m`) and `_NSAutoreleasedMallocMemory`'s cache
  (`NSPrivate.m`) use process-global single-threaded equivalents rather
  than the reference's per-thread storage, because `NSThread.m` is not
  reconstructed yet.
- `NSDefaultMallocZone`'s cache self-initialises on first call rather
  than being set up by a platform bootstrap routine.
- `NSZoneName`/`NSSetZoneName` (`NSZone.m`) use a private zone-to-name
  table rather than the undocumented `NXZone` field the reference
  apparently uses (not confirmed from the disassembly at this stage's
  scope).

Every one of these is single-threaded, matching every other substitution
in this stage (`NSZone.m`'s own lock is skipped; `_NSInitializePlatform`
no-ops) — no test in this stage runs threaded, so none of these are
exercised concurrently.

### Two genuinely unrecoverable strings (contrast with Task 7's false claim)

`+[NSObject new]`/`+[NSObject debugDescription]` and
`-[NSProxy description]` reference `__message_refs` cells resolving to
addresses around `0x4140xxxx` (`0x414067cc`/`0x41406990` for the two
`NSObject` selectors, `0x414067b4` for `NSProxy`'s) — far below this
slice's own `0x42500000` base, meaning they resolve into a *different*,
out-of-slice prebound image this stage has no access to. These are
**genuinely** unrecoverable: confirmed by the addresses falling outside
every range this slice's `relocations`/`symbols` tables cover, not merely
asserted. Contrast with Task 7's *false* unrecoverability claim for three
other strings (`-description`, `doesNotRecognizeSelector:`, `forward::`),
where the real text sat verbatim in the analysis JSON's `strings` array
the whole time and invented placeholder text was committed before a
reviewer caught it (corrected in `612a7fe1`) — the lesson recorded there
("grep the analysis JSON before accepting a negative claim") is why these
two were checked and confirmed absent before being accepted as
unrecoverable here.

### Runtime facts carried forward for later stages

- A root class must implement `+initialize`, or the Objective-C runtime
  crashes with "Does not recognize selector forward::" the first time
  any message reaches it — confirmed on the guest's native ppc runtime
  (Task 1).
- A root metaclass's `super_class` points back to its own class
  (`src/objc-1/objc-class.m:708`), which is why
  `[NSObject isKindOfClass:[NSObject class]]` returns **YES** (the
  `isa`-chain walk reaches `NSObject` on its second step through the
  metaclass tie-down) and why `[NSProxy superclass]` sent to the *class
  object* `NSProxy` returns `NSProxy` itself, not `nil` — `NSProxy` has
  no class-side `+superclass` override, so the message falls through the
  same root-metaclass tie-down to the *instance* `-superclass`
  implementation (`isa->super_class`), which for the metaclass is the
  class itself. (`-[anInstance superclass]` sent to a real instance still
  correctly returns `nil`, unaffected by this.)
- `+[NSProxy initialize]` patches `-[NSProxy forward::]`'s installed IMP
  to `-[NSObject forward::]`'s, at runtime (`class_getInstanceMethod` on
  both, then a direct write to `method_imp`, confirmed against
  `src/objc-1/objc-class.h`'s layout).
- `NSProxy`'s `-isKindOfClass:`/`-isMemberOfClass:`/
  `-conformsToProtocol:`/`-respondsToSelector:` all route through a
  private `NSInvocationBuilder` and `-forwardInvocation:`, not a direct
  `isa` comparison — so on this stage's reconstruction (matching the
  reference) they **raise** rather than answering YES/NO. The
  naive-looking "just return YES" implementation would have passed every
  test that existed before Task 9 added coverage for this specifically.
- `-[NSObject autorelease]` and `-[NSProxy autorelease]` both perform a
  **direct C call** to `_NSAutoreleaseObject`, not an `objc_msgSend` —
  confirmed from each call site's own `calls` list in the analysis JSON
  (see Gate 1 above). This is why that one symbol cannot be made
  `static` without diverging from confirmed reference behaviour.

### Test-expectation corrections (reference is authority; the brief's assumed text was wrong)

Two corrections, both confirmed against the disassembly before the test
was changed:

1. **`[NSObject isKindOfClass:[NSObject class]]` (Task 8,
   `test_object.m`).** The brief's assumed expectation was `== NO`
   ("`NSObject` is not a kind of the abstract notion `[NSObject class]`
   applied to itself" reads plausible on paper). The reference disagrees:
   `+isKindOfClass:` walks `self->isa` (the metaclass chain), and a root
   metaclass's `super_class` points back to its own class (see above), so
   the walk reaches `NSObject` on its second step. Corrected to
   `CHECK([NSObject isKindOfClass:[NSObject class]] == YES)`.
2. **`[NSProxy superclass]` sent to the class object (Task 9,
   `test_proxy.m`).** The brief's assumed expectation was `== nil`. The
   reference disagrees for the same root-metaclass-tie-down reason:
   `NSProxy` has no class-side `+superclass`, so the message falls
   through to the instance `-superclass` implementation, which for
   the metaclass returns `NSProxy` itself. Corrected to
   `CHECK([NSProxy superclass] == [NSProxy class])`, while
   `CHECK([anActualProxyInstance superclass] == nil)` (a real instance,
   not the class object) is kept and still passes, since that path is
   unaffected.

### Every method implemented but not behaviourally tested, and which stage picks it up

| Function/method | Module | Why untested this stage | Picked up by |
|---|---|---|---|
| `NSAllocateObject`, `NSDeallocateObject`, `NSCopyObject` (instance `-copy`/`-mutableCopy` path specifically; the class-side `+copy`/`+mutableCopy` identity no-ops ARE tested) | `NSZone.m` | Exercising `-copy`/`NSCopyObject` meaningfully needs a real registered class with instance data to copy | Stage 3+ (whichever stage first needs `-copy` behaviourally) |
| `description`, `NSSetZoneName`/`NSZoneName` | `NSObject.m`/`NSZone.m` | Need a working `NSString` | Stage 3 |
| `NSProxy`'s forwarding methods actually forwarding a call (their *raise* paths ARE tested, by Task 9) | `NSProxy.m` | Real forwarding needs `NSInvocation`/`NSMethodSignature` | Stage 2c |
| `_NSAutoreleasedMallocMemory` (all 5 methods) | `NSPrivate.m` | Only proven to link; no test references it | Whichever stage first needs autoreleased scratch memory |
| Instance `-[NSAutoreleasePool addObject:]` | `NSAutoreleasePool.m` | No test in this stage calls the instance method (only the class method); the bookkeeping fix above is verified by inspection and by the suites still passing, not a new assertion | Later stage exercising multiple simultaneously-active pools |
| ~12 of `NSAutoreleasePool`'s 15 class methods (`+autoreleasePoolExists`, `+autoreleasedObjectCount`, `+topAutoreleasePoolCount`, `+poolCountHighWaterMark`/`+setPoolCountHighWaterMark:`, `+poolCountHighWaterResolution`/`+setPoolCountHighWaterResolution:`, `+enableFreedObjectCheck:`, `+enableRelease:`, `+showPools`, `+resetTotalAutoreleasedObjects`, `+totalAutoreleasedObjects`, `+releaseAllPools`) | `NSAutoreleasePool.m` | `test_autoreleasepool.m`'s 5 tests only exercise pool lifecycle, drain ordering and `+addObject:` | Later stage/final review pass |
| `+[NSObject implementsSelector:]` | `NSObject.m` | Its `_NSIMPForSelector` stub unconditionally aborts (confirmed empirically, exit 134) | Whichever stage reconstructs `_NSIMPForSelector` |
| `-[NSAutoreleasePool retain]`/`-autorelease`/`-dealloc`'s warning path | `NSAutoreleasePool.m` | All three raise/warn through `_NSMethodExceptionProem`, whose stub unconditionally aborts *before* reaching `link_stubs.m`'s armed raise-capture harness — unlike `NSProxy`'s raise paths, which don't route through that same helper | Whichever stage reconstructs `_NSMethodExceptionProem` for real |
| `-[NSObject performSelector:withObject:]` etc. with a non-`NULL` selector; `-isProxy`/`-isFault`/`-classForCoder`/`-replacementObjectForCoder:`/`-awakeAfterUsingCoder:` | `NSObject.m` | Trivial one-liners inherited untested from Task 7's review (test gaps, not defects) | Final review pass |

### Task 1's runtime-hosting verdict, carried forward

The design question the whole stage depends on — will the guest's
Objective-C runtime host a foreign root class not compiled by Apple's own
toolchain? — is **YES**, proven on the guest's native ppc runtime
(`PASS: answer=42`), corrected from the brief's own literal framing
("link an i386 executable"), which is impossible on this guest (no i386
`crt1.o`/`libcc_dynamic.a`/System framework there at all — confirmed
again by this task's own object-vs-executable split, see the header of
this report). Every later stage's test binaries must build **native
ppc, linked**; only the `abi-check` objects are `-arch i386`, compiled
and never linked. This split is load-bearing for every remaining stage
of the whole ten-stage programme, not just 2a.

---

## Stage 2b: exceptions and the Objective-C runtime helpers

### The three substitutions (spec §3.2)

1. **No `NSString` (stage 3).** Every string this stage produces or consumes is the
   `NXConstantString`-shaped record the compiler emits for `@"..."` literals
   (`{ Class isa; char *c_string; unsigned int len; }`, per
   `src/cc-1/cc/objc/NXConstStr.h`). `NSObjCRuntime.m` carries file-static
   `_NSObjCRuntimeStringBytes`/`_NSObjCRuntimeStringWithCString`, `NSException.m`
   its own `_NSExceptionStringBytes`/`_NSExceptionStringWithCString`/`_NSExceptionReasonFromFormat`
   — duplicated by design (accepted pre-flight decision: each module stays
   independently linkable/deletable when stage 3 removes both). Stage 3 replaces
   all of this with real `NSString` instances; no exported ABI moves.
2. **No per-thread state (NSThread.m is stage 7).** The exception handler stack,
   the alternate-handler table and `+[NSAssertionHandler currentHandler]`'s
   handler are process globals here, the same substitution stage 2a made for the
   pool stack and `_NSRefCountLock`. Every test in this stage runs unthreaded.
3. **No `NSDictionary` (stage 4).** `-[NSException initWithName:reason:userInfo:]`
   takes ownership of its ivars by assignment and `-dealloc` does not release
   them: stage 2b's strings are literals or zone-allocated records that are never
   freed, and messaging one (a `retain` would dispatch through the still-zeroed
   `_NSConstantStringClassReference`) faults the process. The plan's
   retain/release form was written, measured on the guest (bus error in
   `objc_msgSend` from `[aName retain]`), and replaced with the assignment form.
   Stage 3/4 restore retain/release. Recorded here so the change is not silently
   inherited.

### The box substitution

The plan was written against the native ppc Rhapsody 5.6 guest at `10.10.0.241`,
which stayed unreachable all stage (network-layer unreachable, not VM-off). All
guest work ran instead on the project's i386 QEMU guest ("hfsle", Rhapsody 5.3
i386 kernel built 2026-09-18, gcc 2.7.2.1 / cc-771.4), reached via its SSH
forward. Consequences:

- Test binaries and `abi-check` objects are both **i386** — the plan's
  native-ppc-vs-i386 build split collapses into one architecture, which removes
  the cross-architecture doubt from every behavioural test.
- The Task 1 hosting probe verdict (`## RESULT: hosted`, recorded in
  `docs/superpowers/plans/notes/2026-09-20-setjmp-hosting-probe.md`) is an i386
  verdict. `_NSSETJMP` still resolves to `_setjmp` on this platform, so
  `_longjmp` remains mandatory in every raise path.

### NSLog's formatter is provisional (spec §5.4)

`NSLogv` walks the format's own bytes, substitutes `%@` from the record layout,
and hands every other specifier to `vsprintf`. It covers `%@ %s %d %u %x %c %%`
and no more, formats at C level (no locale, no `%@` beyond the record's bytes),
and writes through `_NSBasicStdErrLog` only. **Stages 3–9 must not build on it.**
The `vsprintf`-plus-manual-`va_arg` re-read was measured working on this
platform (all formatter tests pass without the plan's fallback switch).

### The nine out-of-stage exception constants (spec acceptance criterion 10)

The reference exports 23 `NSString * const` exception-name globals; the 14
`NSException.h` declares are defined in `NSException.m`. The other 9 belong to
later stages under the attribute-by-declaring-header rule:

| Constant | Declared in | Stage |
|---|---|---|
| `NSCharacterConversionException` | `NSString.h` | 3 |
| `NSParseErrorException` | `NSString.h` | 3 |
| `NSTimeOutException` | `NSString.h` | 3 |
| `NSDecimalNumberExactnessException` | `NSDecimalNumber.h` | 4 |
| `NSDecimalNumberOverflowException` | `NSDecimalNumber.h` | 4 |
| `NSDecimalNumberUnderflowException` | `NSDecimalNumber.h` | 4 |
| `NSDecimalNumberDivideByZeroException` | `NSDecimalNumber.h` | 4 |
| `NSFileHandleOperationException` | `NSFileHandle.h` | 5 |
| `NSInconsistentArchiveException` | `NSArchiver.h` | 6 |
| (`NSFailedUnarchivingException` | `NSArchiver.h` | 6) |
| (`NSPortMessageException`-family leftovers | `NSConnection.h` | 8) |

Listed so none is lost; the final count per stage is settled when each stage
claims what its header declares.

### Stage 2a's extern-versus-local correction (spec §2.2)

`_NSObjectRaiseNullSelectorException` and `_NSProxyRaiseNullSelectorException`
are `local` in the reference's symbol table (verified: both `local
__TEXT,__text`, alongside a third, `__NSFaultRaiseNullSelectorException`, which
belongs to NSFault in stage 2c). Stage 2a declared both `extern` and stubbed
them; Task 11 moved each into its own module as a `static` definition raising
with `_NSMethodExceptionProem`. **`abi-check` does not catch this class of
error**: it compares defined external symbols only, so an extern-declared-but-
stubbed local helper is invisible to Gate 1. The lesson is recorded for later
stages: extern stubs in test harnesses are ABI claims, and each one needs its
reference symbol-table check.

### `_NSGetSizeAndAlignment` public/private pair

The reference exports both `_NSGetSizeAndAlignment` (public, mangled) and
`__NSGetSizeAndAlignment` (private). No header declares the private one and no
caller in this stage's modules reaches it; both walk the same encodings, so the
reconstruction shares one implementation (`NSSizeAndAlignmentOfType`) between
the two entry points rather than guessing at a difference the disassembly does
not show. Gate 1 confirms both symbols with matching encodings.

### `NSDetailedDescription`'s unconfirmed output text

`-[Protocol detailedDescription]` and `+[NSObject detailedDescriptionForClass:]`
are reconstructed to the observable shape — the name, returned as this stage's
string record. The reference's exact formatting (whether it lists methods,
ivars, conformances) is outside this stage's published analysis scope and is
**not** confirmed. Both categories are declared and implemented only in
`NSObjCRuntime.m` (no header in this tree declares them) and are claimed by name
in `symbols.json`'s method lists through the generated ABI baseline. Gate 1 also
showed the reference carries two same-named `NSDetailedDescription` categories
(one on `Protocol`, one on `NSObject`) — binrecon's abi-check keyed categories
by name alone and collapsed them; fixed to key on (name, host class).

### The raising conveniences live in the main class

`NSException.h` declares `+raise:format:`/`+raise:format:arguments:` inside an
`NSExceptionRaisingConveniences` category, and the plan implemented them there;
Gate 1's abi-check refused it — the reference's `__OBJC` metadata carries both
methods (plus an undeclared `-init`) **in the main class's method list, with no
such category in this image**. The implementation was moved into the main
`@implementation` to match. This is a header-vs-image divergence, of the same
family as the underscore rule: the metadata arbitrates.

### Untested table (stage 2b additions)

| Symbol/method | Module | Why untested | Unblocked by |
|---|---|---|---|
| `-encodeWithCoder:` / `-initWithCoder:` | `NSException.m` | `NSCoder` is stage 2c; written against `NSCoder.h`'s declared selectors only | Stage 2c |
| `-replacementObjectForPortCoder:` | `NSException.m` | `NSPortCoder` is stage 8; selector undeclared by any header in this tree (Gate-1 claim only) | Stage 8 |
| `-copyWithZone:` | `NSException.m` | Copying `userInfo` needs NSDictionary (stage 4); the name/reason path is exercised only via the `isEqual:` test | Stage 4 |
| `_NSAddAltHandler2` / `_NSRemoveAltHandler2` | `NSException.m` | Semantics out of scope; reconstructed from disassembly (per-thread table + growable identifier array, process-global here); callers do not exist until Distributed Objects | Stage 8 |
| `_NSExceptionObjectFromHandler` | `NSException.m` | The legacy `NSHandler` is opaque in the shipped header, so nothing can construct one; structurally reconstructed (reads the same field as the 2b accessor), never behaviourally executed | Never, probably; carried as an ABI claim |
| `_NSClearExceptionStack` | `NSException.m` | Exercised only directly by tests (stack-clearing assertion), no production caller until threads | Stage 7 |
| `NSHangOnUncaughtException`'s hang path | `NSException.m` | The infinite loop is untestable in a suite; the flag is verified only as readable/writable data | Final review pass |
| `+[NSException _enableLogging:]` | `NSException.m` | Toggles a file-static flag; no observable behaviour in this stage (logging of raises not reconstructed) | Final review pass |

### Gate 3 ledger disposition and tooling corrections

The ledger holds 46 reference-side entries, all dispositioned
`intentional-mismatch` with the same structural reason stage 2a recorded:
`compare`'s normalized-functions matcher keys on (section, occurrence, byte
start/end) position, and a two-module relocatable object cannot coincide with
an 80-module linked image's offsets. Gate 1 (abi-check, ten modules, ABI
matches) and Gate 2 (seven suites, `PASSED: 0 failure(s)` each) carry the
correctness verdict; `source-map.json` (46/46 mapped, 0 unmapped) confirms
every reference function has a source counterpart.

Three binrecon corrections were needed to produce that evidence (all
behaviour-preserving for stage 2a's artifacts):

1. `abi_check.diff_abi` keyed categories by name alone; the reference legally
   carries two same-named `NSDetailedDescription` categories on different host
   classes, which collapsed into one dict entry and produced phantom
   divergences. Now keyed on (name, host class).
2. `ida._mapping_manifest` applied the profile's reference-absolute
   `analysis_scope` to the rebuilt artifact too, whose functions live at
   object-file addresses — the scope matched no functions and IDA aborted. The
   scope is a reference-image selection; a rebuilt artifact (which contains by
   construction exactly the stage's modules) is analyzed whole.
3. `cli compare` dereferenced `profile.rebuilt` unconditionally; a committed
   stage profile carries no `rebuilt` artifact (its path is local and
   uncommitted), so the compare step ran against a scratch profile copy that
   carries the local `rebuilt` block while the committed profile stays clean.

### Unclaimed-export count

`symbol-audit` after stage 2b: **321** unclaimed exported C functions, down
from the programme baseline **345** — the 24 symbols this stage claimed (12
`NSObjCRuntime.m` C entry points plus 12 `NSException.m` machine-level symbols,
the 14 name constants among them). The tail remains concentrated in stages 3
and 6 as the programme spec sizes it.

### Environment deviation (recorded, not actionable this stage)

The profiled IDA path (`C:/Program Files/IDA Professional 9.2/idat.exe`) does
not exist on this machine — the 9.2 directory holds only a licence file;
**IDA Professional 9.4** is installed and produced both published analyses
(`version: 9.4` recorded in the committed 2b profile). Re-exporting with 9.2
when available is a re-run, not a re-write: the documents are version-stamped
and the pipeline revalidates identity on every run.
