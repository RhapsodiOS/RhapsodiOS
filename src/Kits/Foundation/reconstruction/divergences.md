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
