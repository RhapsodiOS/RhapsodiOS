# Foundation `_NSIntegerMultiplyByPowerOf10` analysis

Reference: Foundation i386 IDA database `d12fe2f23883`, function at
`0x425a1d70`, and its callers `_NSDecimalDivide` (`0x425a0a34`) and
`_NSDecimalNormalize` (`0x425a0fb0`).

## Signature and observed behavior

IDA pseudocode and stack arguments establish the signature
`int (unsigned short *destination, unsigned short *destinationLength,
const unsigned short *source, unsigned short sourceLength, short power)`.
The incoming `*destinationLength` is saved as destination capacity. When the
destination differs from the source, the helper copies the source first. A
zero power returns `NSCalculationNoError` after that copy.

For positive powers, the helper checks destination capacity using the source
length, the selected power-of-ten mantissa length, and eight words for each
38-digit chunk. Insufficient capacity returns `NSCalculationOverflow` before
the multiply. For negative powers it divides by the corresponding power of ten.
The multiply/divide calls use `_NSIntegerMultiply` and `_NSIntegerDivide`,
which are already implemented in `NSDecimal.m`.

## Power table

`_pow10` at `0x425bba04` contains 39 records for powers `10^0` through `10^38`.
Each record is nine 16-bit words: a word count followed by eight little-endian
mantissa words. `word_425BBA06` is the first record's mantissa, so the helper
passes a pointer to the mantissa and separately passes the count. The adjacent
`unk_425BBCB0` value is 8, matching the maximum eight-word mantissa for
`10^38`.

## Unresolved large-power path

The disassembly subtracts 38 from the signed power in a loop while its
magnitude remains greater than 38, then indexes `_pow10` using the reduced
power and applies a final multiply/divide using that same reduced power. For
powers above 38 this appears to reuse a remainder rather than a fixed 38-digit
chunk, and can index beyond the 39-record table. The positive-capacity guard
rejects such operations for the normal eight-word decimal capacity, but the
negative path has no corresponding guard.

The initial audit had not yet resolved caller reachability for large negative
powers. The follow-up below supersedes that uncertainty.

## Caller reachability and table-boundary recheck (2026-10-07)

Paired i386/PPC decompilation confirms the loop behavior is the same in both
images: after each subtraction of 38, the helper indexes the table using the
reduced power for that iteration and again for the final operation. For
negative powers from 39 through 76, the reduced index remains within the
39-record table. For powers 39 through 75, this applies the same remainder
power twice; power 76 applies `10^38` twice. At 77, the first reduced index is
39, whose count word is the two-byte alignment padding immediately before
`_fpow10`; it is zero in both images. Higher reduced indices read through the
adjacent floating-point table and then beyond it, so their results depend on
target image data and the downstream divide's interpretation of those words.

The negative branch is reachable through `NSDecimalNormalize`: the exponent
difference comes from two signed-byte exponents, and its precision fallback
calls this helper with `maxPower - difference`, which can be below -76. In
contrast, `_NSDecimalDivide` calls it with positive power 38. The current
source's mathematically correct 38-digit negative chunk loop therefore differs
from target behavior for reachable negative powers 39 and above. Exact
emulation above 76 would require modeling architecture-specific reads beyond
the power table; the binary does not define a portable result there. No source
change or runtime test was made during this recheck.

IDA for i386 `_NSIntegerDivide` (`0x425a1748`) returns
`NSCalculationDivideByZero` immediately when the supplied divisor length is
zero, without changing the destination length. The outer power helper ignores
that loop-call result and continues. The raw count word at reduced table index
39 is zero in both images; at index 40 it is `0x0000` on i386 but `0x4059` on
PPC (`_fpow10` begins at `0x425e2898`). Thus even the first out-of-table divide
for power -78 is architecture-dependent: i386 takes the divide-by-zero/no-op
path, while PPC sees a divisor length greater than the eight-word dividend and
sets the quotient length to zero. This confirms that a universal mathematical
fallback would conceal observed target behavior rather than emulate it.

For power -77, the first `10^39` lookup returns divide-by-zero without changing
the destination length; the loop then processes remainder 1. The final divide
uses the original source pointer and length, as the decompiled call shows. For
power -78, i386's zero count is a no-op, then the loop and final divide each
process `10^2` against the aliased mantissa. PPC's `0x4059` count makes the
first loop divide set the output length to zero; the next loop divides a
zero-length value by `10^2`, but the final divide again uses the original
source length and the aliased mantissa contents. It therefore must not be
described as remaining zero through the final call. These are consequences of
the decompiled call sequence and raw table-adjacent bytes, not runtime probes.

## Full caller-range out-of-table count scan (2026-10-06)

`NSDecimalNormalize` can request a negative magnitude through 255 from its
signed-byte exponent difference, so the first reduced lookup is at most index
217 (`255 - 38`). A raw count-word scan of `_pow10` indices 39 through 217
classifies every out-of-table divisor used by that caller:

* i386 has 81 zero counts, four one-word counts, and 94 counts greater than
  eight. The one-word entries are indices 211, 213, 215, and 217, with divisor
  words 2067, 4962, 8426, and 11627 respectively. The zero-count bitmap in
  ascending index order (least-significant bit first) is
  `27002c5555555555555555555555555555555555550500`.
* PPC has 10 zero counts and 169 counts greater than eight; there are no
  one-through-eight-word entries. Its zero-count bitmap in the same encoding
  is `1900384000000000000000000100000004400000000000`.

For an input dividend no longer than `NSDecimalMaxSize` (eight words), every
count above eight makes `NSIntegerDivide` take its less-than-divisor path and
set the output length to zero without reading the out-of-range divisor words.
Zero counts return divide-by-zero without changing the output length. This
reduces the per-lookup arithmetic cases to a finite target-specific table.
`NSIntegerMultiplyByPowerOf10` now models those count classes for negative
magnitudes through 255. Each loop captures the current length, resets the
output length to the saved capacity, and ignores the loop divide's return
value. The final divide uses the original source pointer and length, matching
both decompiled bodies. The four i386 one-word divisors and caller-range
evidence were read directly from the two IDA databases; no runtime probes were
made.

## Implemented caller-range parity correction (2026-10-06)

`NSIntegerMultiplyByPowerOf10` now follows the reference's repeated-remainder
negative-power loop through the full -255 range reachable from
`NSDecimalNormalize`, whose destination capacity is eight words. It models the
scanned architecture-specific count words, ignored loop-divide errors,
output-length reset, and final use of the original source pointer and length.
Powers through -76 use generated in-bounds divisors; powers -77 through -255
use the confirmed raw count classes when capacity is at most eight words.
Negative direct calls below -255 and out-of-table calls with source mantissas
larger than eight words retain bounded mathematical chunking because their
table reads or divisor comparisons fall outside the audited caller envelope.
Destination capacity may exceed eight words when the source mantissa is within
the eight-word limit: the target's oversized-divisor branch compares against
dividend length, not destination capacity. No ABI entries changed; no tests or
builds were run.

## Direct-source extension to sixteen words (2026-10-07)

The out-of-table count scan was repeated for indices 39 through 217 in both
IDA images, using a sixteen-word source limit. Neither image has a divisor
count from 9 through 16 in that range. i386 still has 81 zero counts, four
one-word counts (indices 211, 213, 215, and 217), and 94 counts above sixteen;
PPC has 10 zero counts and 169 counts above sixteen. Therefore, for any source
length up to sixteen words, the existing zero-count and i386 one-word cases
remain sufficient, while every remaining out-of-table divisor is longer than
the source and the reference comparison sets the quotient length to zero
without reading divisor words. `NSIntegerMultiplyByPowerOf10` now applies this
exact emulation through -255 for source lengths up to sixteen words. The
architecture-specific raw count scan remains bounded to indices 39 through
217; larger negative direct calls and longer source mantissas retain the
bounded mathematical path. No ABI records changed; no tests or builds were
run.

## Positive in-table path recheck (2026-10-06)

The paired helper pseudocode uses the same reduced-remainder loop for positive
powers and passes the original source pointer and length to the final
`NSIntegerMultiply`. The loop multiply's return value is ignored. The source
now follows that behavior for positive powers through 76, including powers
1–38 where the final multiply reads the original source length. Its existing
capacity guard rejects every positive power above 38 for a normal
eight-word-capacity `NSDecimalNormalize` destination, so those larger positive
table paths are not reached there. Positive powers above 76 remain on the
bounded chunking path for direct helper calls with larger capacities; their
reference table reads are outside the in-table range audited here. No ABI
entries changed; no tests or builds were run.

## Positive out-of-table path boundary recheck (2026-10-07)

The paired `_NSIntegerMultiplyByPowerOf10` decompilations use the reduced
remainder index after each 38-digit subtraction for positive powers too. For
77 through 255, the first out-of-table index is 39 through 217. The raw count
scan over those indices has no counts from 9 through 16: i386 has 81 zero
counts, four one-word counts, and 94 counts above sixteen; PPC has 10 zero
counts and 169 counts above sixteen. A zero count makes `_NSIntegerMultiply`
set the destination length to zero. A count above sixteen enters its
unchecked multiply loop, which reads that many table-adjacent words and can
write beyond the caller's capacity. The mathematical chunk fallback remains
bounded and therefore is not equivalent for direct positive calls in this
range. The public normalization caller has an eight-word destination and its
preflight rejects positive powers above 38, so these direct-call cases are
outside that caller path. No code change was made: reproducing the unchecked
table-adjacent multiply would encode uncontrolled reads and writes rather
than a bounded reconstruction. No ABI entries changed; no tests or builds
were run.

## i386-only extension approval check (2026-10-07)

The approved i386 range through original positive power 19,490 requires table
rows through reduced index 19,452. The i386 large-tail snapshot includes this
range: its first row is reduced index 218, and a byte-for-byte check of the
173,115-word prefix through row 19,452 matches IDA at `0x425bc958` with SHA-256
`4285af0426cb624a0e8da3bfd0a81ad434bd8ff209be3f7328bc036d7cd17d9e`. The
i386 include and dispatch were already present in the worktree, so no
additional source change was needed for this approval. No PPC files were
changed for this i386-only check; no tests or builds were run.

## Positive out-of-table read extent (2026-10-07)

A fresh IDA byte-range scan confirms the out-of-table count words for indexes
39 through 217 and the corresponding following bytes are readable in both
images. The largest reachable count is 64,447 words at i386 index 210
(128,894 bytes after its count word) and 65,534 words at PPC index 68
(131,068 bytes after its count word). Both spans remain inside their loaded
Foundation image. The helper then passes the raw count to `NSIntegerMultiply`,
whose initialization and multiply loops write according to that count without
checking the caller's destination capacity. Exact direct-call emulation would
therefore require target-specific image-tail data and preserve writes beyond
the caller's declared destination. The public normalization path rejects
positive powers above 38; the exported helper's direct-call behavior remains
an explicit open divergence. Static IDA data and source review only; no tests
or builds were run.

## Negative direct-source extension to the 48-word scratch limit (2026-10-07)

Scanned every out-of-table reduced divisor count at indices 39 through 217
again against both IDA images, this time against `NSIntegerDivide`'s 48-word
`BigInteger` scratch capacity. The only i386 count from 17 through 48 is 32
at index 62; its following 32 words are
`0,52,0,68,0,84,0,100,0,116,0,132,0,148,0,164,0,184,0,204,0,220,0,240,0,256,0,272,0,288,0,312`.
The next i386 count is 184. PPC has no count at or below 48; its minimum
nonzero out-of-table count is 821. `NSIntegerMultiplyByPowerOf10` now emulates
the scanned negative path through -255 for source mantissas up to 48 words:
the i386 index-62 path divides by the recorded 32-word value, and every other
nonzero out-of-table count exceeds the source length and therefore takes the
reference compare path that sets the quotient length to zero. Larger source
lengths, powers outside the scanned range, and positive out-of-table
multiplication remain open. No ABI entries changed; no tests or builds were
run.

## Positive zero-count path through power 255 (2026-10-07)

The first reduced out-of-table index for positive powers 77 through 255 is
`power - 38`, within the scanned 39–217 range. When its target count is zero,
`NSIntegerMultiply` sets the intermediate length to zero. Each later loop
multiply then returns on its zero-length left operand without reading its
divisor, and the final multiply uses the original source pointer and the
remaining in-table power. `NSIntegerMultiplyByPowerOf10` now reproduces this
path for either architecture when the recorded count bitmap identifies a
zero. Nonzero out-of-table counts still use the bounded mathematical fallback
because their target multiply reads image-adjacent words and can write past
the declared capacity. No ABI entries changed; no tests or builds were run.

## Negative direct-call extension through the mapped table-adjacent image range (2026-10-07)

Scanned reduced indices 39 through 26,363 in both IDA images. Every count word
and every following divisor word for counts up to 48 is readable throughout
that shared range. i386 contains 3,247 zero counts, 1,214 counts from 1 through
48 (6,449 divisor words), and 21,864 counts above 48. PPC contains 3,086 zero
counts, 1,701 counts from 1 through 48 (8,558 divisor words), and 21,538
counts above 48. Added architecture-specific bitmaps and sorted divisor
records generated from those IDA bytes. `NSIntegerMultiplyByPowerOf10` now
models negative powers through -26,401 for source mantissas up to the 48-word
`BigInteger` scratch limit. Larger table counts take the reference's
length-only compare path and clear the quotient length without reading the
divisor. IDA reports no value at i386 index 26,364, so larger negative powers
remain outside the common mapped range; source lengths above 48 also remain
outside the scratch model. No ABI entries changed; no tests or builds were
run.

## Positive direct-call table path through power 255 (2026-10-07)

For reduced indices 39 through 217, every count and following divisor word
used by positive powers 77 through 255 is readable in both IDA images. The
i386 span contains 65,987 words starting at index 39; its 98 nonzero records
sum to 1,235,758 divisor words, with a maximum count of 64,447 at index 210.
The PPC span contains 65,796 words; its 169 nonzero records sum to 9,278,081
divisor words, with a maximum count of 65,534 at index 68. Added contiguous
architecture-specific table-tail snapshots and routed positive powers
77–255 through the recorded reduced index, count, and divisor pointer on every
loop iteration. The loop still ignores multiplication status and the final
multiply still uses the original source pointer and length. This reproduces
the target's unchecked `NSIntegerMultiply` writes when the recorded count
exceeds the declared destination capacity. Positive powers above 255 remain
outside the scanned range. No ABI entries changed; no tests or builds were
run.

## Positive direct-call table path through power 19,490 (2026-10-07)

Extended the paired IDA count and divisor-extent scan through reduced index
19,452. Every full divisor span for indices 218 through 19,452 lies in mapped
segments in both images; i386's next extent at index 19,602 and PPC's next
extent at index 19,453 extend beyond mapped data. The i386 raw word span starts
at `0x425bc958` and ends at `0x4262e5d2` (466,042 bytes); the PPC span starts
at `0x425e352c` and ends at `0x4265677c` (471,632 bytes). Added these
architecture-specific snapshots and routed the positive loop through the
recorded counts and divisor pointers for original powers 256 through 19,490,
whose first reduced index is at most 19,452. Existing 39–217 snapshots remain
in use. The loop continues to ignore multiply status and reproduce the target's
unchecked writes. For negative calls, large recorded counts enter
`NSIntegerDivide`'s length comparison before divisor words are read when the
source is within the existing 48-word limit. Positive powers above 19,490
remain outside the shared mapped extent. No ABI entries changed; no tests or
builds were run.

## i386 positive table snapshot extent correction (2026-10-07)

The later i386 snapshot in `NSDecimalPowerTableI386LargeTail.inc` contains
235,308 little-endian words (470,616 bytes) starting at `0x425bc958`, ending
at `0x4262f7b0`. A full-byte comparison against IDA returns the same SHA-256
for the snapshot and reference bytes:
`c28a0ebf3f0cb46209af6fcf39df6dcb212d2462ff569b438622c756cd97fb9d`.
This corrects the earlier `0x4262e5d2` / 466,042-byte extent recorded above.
IDA places the exclusive end at the start of the following `UNDEF`/`XTRN`
segment; the final captured table row is reduced index 26,363 with a zero
count. The next row is outside the initialized snapshot. The implementation's
i386 positive-path limit of original power 26,401 therefore matches the last
captured lookup; PPC remains bounded at 19,490. Static IDA/source byte review
only; no tests or builds were run.

## PPC positive mapped-row path through power 26,401 (2026-10-07)

The paired scan already retains count classifications and exact divisor
records through reduced index 26,363 on PPC. The positive path now uses rows
above the contiguous raw span through original power 26,401 only when each
nonzero divisor is recorded (at most 48 words), or after an earlier zero
count has made the intermediate mantissa empty. In the latter case,
`NSIntegerMultiply` returns on its zero-length operand before reading divisor
words; mapped counts remain sufficient for later loop decisions. Unknown
nonzero divisors before a zero still take the bounded fallback. PPC zero and
unrecorded divisor lookups now provide a defined zero length and safe pointer
for the empty-intermediate call. Powers above 26,401 remain outside the
scanned count range. Static paired IDA/source review only; no tests or builds
were run.

## Sparse decimal snapshot cross-check against live IDA (2026-10-07)

Rebuilt the zero-count bitmaps, sorted count-1-through-48 divisor records, and
concatenated divisor words from the live i386 and PPC table-adjacent bytes for
reduced indices 39 through 26,363. Canonical hashes (bitmap bytes, followed by
independent little-endian serialization of record triples and divisor words)
match the checked-in `NSDecimalPowerTableI386.inc` and
`NSDecimalPowerTablePPC.inc` exactly. i386 counts: 3,247 zero, 1,214 retained
small divisors / 6,449 words, 21,864 larger counts. PPC counts: 3,086 zero,
1,701 retained small divisors / 8,558 words, 21,538 larger counts. The PPC
count origin is `0x425e2896` (two bytes before `_fpow10`); the i386 origin is
`0x425bbcc2`. Matching SHA-256 triples for zero bitmap, record triples, and
divisor words are i386 `3775b40d03eb57483fca29982a4cb02ccfe5946dc9177eae96f7d14fe6e34c3c`,
`3cf334c80746a1c60ff1efb15d965d80f26acd704c52e8b6612fc1998f9dcb60`,
`aab029a09b4fe04d0e4a0d4f5a46c745a262d7c375bb77f74167211385479d88`; PPC
`e323176140e2d052f9fb9d686eb09ae628a08a62e63f6ac32108da5affe35c6b`,
`914d5db7fc2741f7419c54916e8f1e70723a0acbd8b5f259fb3bf629e50cc8a3`,
`abbc76a7201d88f9c184206ec280173940363f551cae1ba24d33fcbd3e217a8f`.
This was a static IDA/source comparison only; no tests or builds were run.

## Large-source negative-divide preflight coverage estimate (2026-10-07)

A static simulation of the current `NSDecimalReferencePowerTableDivisor` lookup
and negative chunk loop shows how many additional negative powers would use the
reference path for source mantissas above 48 words if every intermediate
lookup must be a known zero or a retained complete divisor. For powers 77
through 26,401, this condition admits 21,567 i386 powers (77–19,639 as one
contiguous range, plus mapped sparse cases) and 19,415 PPC powers (77–19,490,
plus the mapped power 19,521 case). Unmapped or unretained divisors remain on
the existing fallback. This count is derived from the current source tables,
whose zero bitmaps, divisor records, and divisor words match live IDA as
verified above; it is a scope estimate, not a runtime result.

## i386 large-source negative-divide extension (2026-10-07)

Added an i386-only preflight for negative powers through 26,401 with source
mantissas longer than the 48-word `NSIntegerDivide` scratch capacity. It admits
a power only when every intermediate table divide is a known zero-count no-op, a
one-word short divide, a comparison that clears the quotient before scratch
use, or a complete multiword divide with at most 48 dividend words. It also
requires the final remainder power of ten to fit the one-word divide path.
Unknown rows and unsafe cases continue through the existing bounded fallback.
PPC behavior is unchanged. Static source/whitespace review only; no tests or
builds were run.

## Reference divide capacity clarification (2026-10-08)

Paired IDA decompilation of `NSIntegerDivide` shows that the reference does not
have a 48-word operand ceiling. Both targets use 36-byte local work arrays
(18 16-bit words) and allocate `2 * (operandLength + 1)` bytes when either
operand exceeds 16 words. The 48-word bound in
`NSDecimalLargeSourceNegativePowerAvailable` protects this reconstruction's
fixed `BigInteger` scratch capacity; it is not a behavior or limit of the
reference binary. The i386 large-source preflight and its current accepted
subset are unchanged. Static paired IDA/source review only; no tests or builds
were run.

## `NSIntegerDivideByShort` paired parity recheck (2026-10-08)

The i386 (`0x425a1b14`) and PPC (`0x4255ac74`) implementations both set the
destination length to zero and return divide-by-zero when the divisor is zero.
For nonzero divisors, both walk source words from high to low, write each
quotient word, trim high zero words from the result length, store the final
remainder, and return success. `NSDecimal.m` has the same branch and traversal
order, including when source and destination alias. No source change was
indicated. Static paired IDA/source review only; no tests or builds were run.

## `NSIntegerAddShort` and `NSIntegerSubShort` paired parity recheck (2026-10-08)

The i386/PPC short-add bodies (`0x425a1650` / `0x4255a48c`) propagate the
16-bit carry across the source, return overflow only when a final carry remains
and destination capacity equals the source length, and otherwise append it.
The short-subtract bodies (`0x425a1f9c` / `0x425c55ec`) use the same
subtrahend-minus-one borrow encoding, set output length to the input length,
return overflow for a remaining borrow, and trim high zero words on success.
`NSDecimal.m` matches those operations and capacity check. No source changes
were indicated. Static paired IDA/source review only; no tests or builds were
run.

## `NSIntegerMultiplyByShort` paired parity recheck (2026-10-08)

The i386 (`0x425a1f0c`) and PPC (`0x4255a3ec`) bodies both clear the output
length and return success for a zero factor. For a nonzero factor, they reject
capacity smaller than the input length before writing, multiply words in
low-to-high order, return overflow if a final carry has no spare capacity, and
otherwise append the carry and update the result length. The source matches
these checks and ordering. No source change was indicated. Static paired
IDA/source review only; no tests or builds were run.

## `NSIntegerMultiply` paired parity recheck (2026-10-08)

The i386 (`0x425a1c14`) and PPC (`0x425c5280`) bodies agree on the source's
schoolbook multiply: empty operands clear the result length; only destination
aliasing the left operand triggers a temporary buffer; the reported length is
the 16-bit sum of operand lengths; the result buffer is zeroed before the
right-major multiply loop; a final carry is stored only when nonzero; high zero
words are trimmed; and an alias temporary is copied back and freed. The source
matches those choices, including leaving destination/right aliasing untreated.
No source change was indicated. Static paired IDA/source review only; no tests
or builds were run.

## `NSIntegerAdd` and `NSIntegerSubtract` paired parity recheck (2026-10-08)

The i386/PPC addition bodies (`0x425a1510` / `0x425c4c6c`) process the common
word prefix, propagate carry through the longer operand, copy its untouched
suffix when the carry clears, and compare the supplied destination capacity to
the current word index only when a final carry remains. The subtraction bodies
(`0x425a2020` / `0x425c5690`) use the same borrow state across the common
prefix, left-only suffix, then right-only suffix; they report overflow when a
borrow remains and otherwise trim high zero words. `NSDecimal.m` preserves
these orderings, result lengths, and return paths. No source changes were
indicated. Static paired IDA/source review only; no tests or builds were run.

## Positive power preflight signed-size parity correction (2026-10-08)

The i386 `NSIntegerMultiplyByPowerOf10` body (`0x425a1d70`) keeps the initial
source length and adds eight words per 38-digit chunk in a 16-bit register,
adds the table count for the remainder, then compares that wrapped 16-bit
required length with the initial destination length using a signed condition.
PPC (`0x425c5418`) likewise sign-extends each 16-bit sum and uses a signed
comparison. The source previously used an unbounded unsigned `requiredLength`
comparison, which diverged for large direct-call lengths. `NSDecimal.m` now
wraps the intermediate count to 16 bits and compares the two signed 16-bit
values. Static paired IDA/source review only; no tests or builds were run.

## `NSIntegerMaxPowerOf10Multiplier` paired parity recheck (2026-10-08)

The i386 body (`0x425a1bb0`) computes the unsigned 16-bit length difference,
multiplies by `4.81647993`, narrows the result to double, floors it, and returns
the low 16 bits. PPC (`0x425c51bc`) uses double precision and `floor` before
the same low-16-bit return. The source computes the nonnegative product and
converts it to an integer, which is equivalent to floor over this function's
unsigned-difference domain; its intermediate narrowing also matches i386.
The live name tables and `NSDecimal.m` contain matching implementations for
all twelve `NSInteger*` exports on both architectures. No source change was
indicated. Static paired IDA/source inventory only; no tests or builds were
run.

## `NSIntegerDivide` normalized multiword path detail (2026-10-08)

The i386 body (`0x425a1748`) and PPC body (`0x425c4df4`) use the same
normalized word-division structure after the zero-divisor, dividend-smaller,
and one-word-divisor cases. They choose the normalization factor
`0x10000 / (highDivisorWord + 1)`, multiply both operands into temporary
work arrays, ensure the normalized dividend has a zero high word (appending
one only when multiplication did not grow its recorded length), and estimate
each quotient word from its leading two words. The estimate is corrected at
most twice using the divisor's next-highest word. Each digit is subtracted
from the matching dividend window; a borrow decrements the estimate and adds
the divisor back. Both targets trim high zero quotient words and free only
the work arrays that were dynamically allocated for operands longer than 16
words. Their stack arrays hold 18 words, with dynamic sizes of
`2 * (operandLength + 1)` bytes for longer inputs.

At the time this analysis was recorded, `NSDecimal.m`'s `BigDivideMantissas`
performed bit-at-a-time binary long division in fixed `BIG_WORDS` storage.
That was the remaining algorithm and capacity divergence. A direct port of
the observed normalized word path was selected because it removes the
48-word ceiling and preserves the target's quotient estimation, correction,
subtraction, and add-back order. The implementation is recorded below.

## i386 positive power-table current worktree revalidation (2026-10-08)

Re-read the checked-in `NSDecimalPowerTableI386LargeTail.inc` and compared its
235,308 little-endian 16-bit words (470,616 bytes) with the current i386 IDA
database at `0x425bc958`. The decoded include and mapped IDA bytes both hash to
`c28a0ebf3f0cb46209af6fcf39df6dcb212d2462ff569b438622c756cd97fb9d`.
This confirms the approved table snapshot remains byte-for-byte current; no
table or source change was needed. Static IDA/source verification only; no
tests or builds were run.

## `NSIntegerDivide` target-specific workspace and correction details (2026-10-08)

Re-decompiled i386 `0x425a1748` and PPC `0x425c4df4` from the live databases.
The earlier `0x425c4f60` citation was an interior address in the PPC body, not
its function entry.
Both use 18-word stack work arrays and switch to zone allocations when the
corresponding operand length exceeds 16 words. The i386 allocation computes
`2 * (unsigned short)(length + 1)` bytes; PPC computes
`(2 * (length + 1)) & 0x1fffe`. Those expressions agree for the ordinary
16-bit operand-length range, including the target's wrap at the maximum length.
Both append a zero high word to the normalized divisor and append a dividend
word only when multiplication did not grow its recorded length.

The quotient estimate uses the top two normalized dividend words divided by
the divisor's top word. Each target makes at most two corrections using the
next divisor word; the guard for the second correction is written against the
pre-decrement estimate on i386 and the post-decrement estimate on PPC. The
subtraction loops use different borrow expressions but both decrement the
estimate and add the divisor window back when the final borrow is clear. The
one-word fast path passes a local remainder address to `NSIntegerDivideByShort`
and does not expose that remainder. These details narrow the pending port to
target-equivalent workspace sizing, correction guards, quotient subtraction,
and add-back; no source behavior changed. Static paired IDA review only; no
tests or builds were run.

## `NSIntegerDivide` normalized word-division implementation (2026-10-08)

Following user approval, replaced the fixed `BigInteger` binary divider with
the paired i386/PPC normalized word algorithm. The implementation keeps the
18-word stack buffers, allocates `(length + 1)` words through `NSZoneMalloc`
for operands longer than 16 words, delegates one-word divisors to
`NSIntegerDivideByShort`, and preserves the target normalization, estimate
corrections, subtraction/add-back, and quotient trimming. The second estimate
correction uses the equivalent pre-decrement i386 / post-decrement PPC guard.
Removed the now-unused bit-at-a-time divider and shift helper. Static source
inspection, paired IDA comparison, and `git diff --check` only; no tests or
builds were run.

## `NSIntegerDivide` caller range recheck (2026-10-08)

The live i386 xrefs to `NSIntegerDivide` are `NSDecimalDivide` at
`0x425a0af2` and two call sites inside `NSIntegerMultiplyByPowerOf10`
(`0x425a1e8c`, `0x425a1eda`). PPC has the corresponding `NSDecimalDivide`
call at `0x425c4570` and two power-scaling calls at `0x425c5554` and
`0x425c55b4`. `NSDecimalDivide` passes the stored mantissa lengths; valid
`NSDecimal` values have an eight-word mantissa. The separately exported
`_NSIntegerDivide` accepts an independent 16-bit length, and the power helper
also receives its source length directly. Therefore the dynamic-workspace
branch above 16 words is part of the low-level exported behavior even though
ordinary `NSDecimal` operands do not reach it. The then-current fixed 48-word
`BigInteger` diverged for those direct inputs. This finding led to the
normalized divider implementation documented below; the pending-approval
status in this entry was superseded after that implementation was approved.
Static IDA/source review only; no tests or builds were run.

## `NSDecimalDivide` caller body paired source recheck (2026-10-08)

Re-decompiled i386 `NSDecimalDivide` (`0x425a0a34`) and PPC
`_NSDecimalDivide` (`0x425c44a0`) from the live IDA databases and compared
them with `NSDecimalDivide` in `NSDecimal.m`. Both targets match the source's
NaN and zero-divisor results, zero-dividend flag clearing, 16-word scaling
buffer, 38-digit multiply before division, divide-by-short precision trimming,
lost-remainder correction, mantissa copy, sign/exponent calculation, exponent
range handling, compacting, and ignored rounding-mode parameter. The caller
therefore contributes no additional confirmed mismatch; the outstanding
algorithm difference is isolated to the separately exported `NSIntegerDivide`
normalized multiword path recorded above. Static paired IDA/source review only;
no tests or builds were run.

## `NSIntegerCompare` and `NSIntegerCopy` paired parity recheck (2026-10-08)

`NSIntegerCompare` at i386 `0x425a16b4` and PPC `0x4255ed7c` compares lengths,
then scans equal-length operands from the highest word down; `NSDecimal.m`
matches both. `NSIntegerCopy` at i386 `0x425a170c` returns the last copied word
index for nonempty inputs, while PPC `0x425c4db8` leaves the destination pointer
in its integer return register for every length. The source now preserves the
i386 result and returns the destination pointer on PPC. For zero-length i386
copies, the target does not initialize its return register; source keeps its
existing deterministic zero. Static paired IDA/source review and
`git diff --check` only; no tests or builds were run.

## Negative mapped-power preflight after normalized divide port (2026-10-08)

The reference `NSIntegerDivide` uses dynamic work arrays above 16-word
operands on both targets, as confirmed at i386 `0x425a1748` and PPC
`0x425c4df4`. The earlier negative-power preflight still carried the former
48-word `BigInteger` ceiling on i386, while PPC bypassed its mapped-row
preflight for source lengths above 48. It also required the final power-of-ten
divisor to fit the short-divide path (powers no greater than 4).

The preflight is now shared by both architectures and uses the captured table
rows through power 26,401 only when each nonzero divisor is fully retained.
An unretained count is accepted only when it exceeds the current dividend's
48-word maximum, so `NSIntegerDivide` returns through its length comparison
without reading missing words. Retained multiword divisors use the normalized
dynamic-workspace path, including the final remainder divisor through `10^38`.
Unmapped rows and unretained counts that may fit the current dividend continue
through the bounded fallback. Static source/IDA review and `git diff --check`
only; no tests or builds were run.

## Correction: `NSIntegerDivide` caller recheck status (2026-10-08)

The preceding `NSIntegerDivide` caller-range recheck contains stale status text.
It was written before the approved normalized word-divider was implemented.
The current `NSDecimal.m` at `NSIntegerDivide` uses the 18-word stack buffers,
allocates `(operandLength + 1)` words for operands above 16 words, and follows
the paired i386/PPC normalization, quotient-correction, subtraction/add-back,
and trimming flow described in the implementation section above. The statement
that the source still used fixed `BigInteger` storage and that the port was
pending approval is superseded. No code change was made in this correction.
