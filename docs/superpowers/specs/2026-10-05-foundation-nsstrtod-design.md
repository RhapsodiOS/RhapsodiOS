# PPC Foundation `__NSstrtod` Reconstruction Design

## Goal

Reconstruct the MOSXS PPC Foundation `__NSstrtod` export and route the PPC
`NSScanner` double scan through it. Match the current IDA reference's accepted
input, end-pointer, decimal-to-binary rounding, and range-error behavior.
Keep the i386 scanner on its current libc `strtod` path.

## Evidence and current state

The live MOSXS PPC IDA database identifies `__NSstrtod` at `0x4252abdc`; its
sole direct caller is `__NSScanDoubleFromString` at `0x4252b948`. The converter
parses sign, decimal digits, fraction, and exponent, retains up to sixteen
significant digits for an initial estimate, then uses a private binary-integer
rounding path for longer inputs. It writes the first unconsumed byte through
its end-pointer argument. Overflow returns infinity and underflow returns zero;
both set `errno` to 34.

The target's long-decimal path calls these helpers, all present in the live
reference image:

| Helper | PPC entry | Responsibility |
| --- | --- | --- |
| `_Balloc` | `0x4254d554` | Allocate a `Bigint` using the size-class freelist |
| `_d2b` | `0x4254f410` | Convert the estimate double to integer bits and exponents |
| `_Bfree` | `0x42550160` | Return a `Bigint` to its size-class freelist |
| `_lo0bits` | `0x4254f640` | Remove and count low zero bits in a word |
| `_cmp` | `0x4255b488` | Compare nonnegative `Bigint` magnitudes |
| `_multadd` | `0x4255b4ec` | Multiply a `Bigint` by a small integer and add a digit |
| `_mult` | `0x4255eb88` | Multiply `Bigint` magnitudes |
| `_lshift` | `0x4255ef9c` | Shift a `Bigint` left by a bit count |
| `_i2b` | `0x42560700` | Construct a `Bigint` from an integer |
| `_pow5mult` | `0x42560da0` | Multiply by a power of five |
| `_hi0bits` | `0x42560e9c` | Count high zero bits in a word |
| `_diff` | `0x425ac954` | Subtract ordered `Bigint` magnitudes |
| `_b2d` | `0x425ac75c` | Convert a `Bigint` magnitude to a normalized double |
| `_ratio` | `0x425acb74` | Estimate the ratio of two `Bigint` values |
| `_s2b` | `0x425acc10` | Convert significant decimal digits to a `Bigint` |
| `_ulp` | `0x425acd04` | Calculate the estimate's unit in the last place |

`_s2b` and `_pow5mult` call `_multadd`; `_d2b` calls `_lo0bits` and
`_hi0bits`; `_ratio` calls `_b2d`. Xrefs show `_Balloc`, `_Bfree`, `_d2b`,
`_lo0bits`, `_b2d`, `_i2b`, `_pow5mult`, `_mult`, `_lshift`, `_cmp`,
`_multadd`, `_hi0bits`, and `_diff` are shared with the target's `___dtoa`. The target
uses one shared `Bigint` layout, freelist, and power-of-five cache. The header
stores its free-list link, size class, capacity, sign, and used-word count at
offsets 0, 4, 8, 12, and 16, followed by 32-bit words at offset 20. `_Balloc`
allocates `20 + 4 * (1 << k)` bytes through `_NSZoneMalloc(NULL, size)` and
uses a 16-entry size-class freelist; the observed freelist operations have no
lock. `_pow5mult` lazily seeds a cached power-of-five square chain from 625.

Both converters read shared `tens` and `bigtens` tables; `__NSstrtod` also
reads the five `tinytens` scaling values. Its first-significant-digit combine
expression uses an offset view into `tens` for the 10^1 through 10^7
multipliers. None of this helper family is implemented in Foundation sources.
The current `_NSScanDoubleFromString` builds an ASCII token using the locale's
decimal separator, then calls libc `strtod`; this leaves PPC rounding and
consumption behavior different from the reference.

## Design

### Module boundary

Add `NSBigint.h` and `NSBigint.m` for the target's shared internal `Bigint`
type, allocator/free-list state, power-of-five cache, shared `tens` and
`bigtens` tables, and arithmetic helpers used by both `__NSstrtod` and
`___dtoa`. Keep the helpers linkable between Foundation source files but
outside the public export and source-symbol assignment manifests. Add
`NSStrtod.m` for `double _NSstrtod(const char *string, char **endPointer)`,
the converter-only `_s2b`, `_ratio`, `_ulp`, `tinytens` table, and parser and
rounding control flow. Do not implement the `___dtoa` body or its
`_quorem`-only dependency in this slice. Register both `.m` files and the new
header in `PB.project` and `Makefile.preamble`.

In `NSScanner.m`, route `_NSScanDoubleFromString` to `_NSstrtod` under the PPC
compiler guard and retain libc `strtod` in the i386 branch. Preserve the
existing locale decimal-separator normalization and update `_scanLocation`
from the custom converter's end pointer exactly as the current caller uses
libc's end pointer.

### Conversion behavior

Reconstruct the target stages from their IDA bodies:

1. Skip the six ASCII C whitespace characters, consume an optional sign, and
   scan the decimal significand using the target's leading-zero and fractional
   place accounting.
2. Retain at most sixteen significant digits for the initial floating-point
   estimate while tracking the discarded decimal places.
3. Parse an optional exponent only when at least one exponent digit follows.
   If no digit follows, leave the end pointer at the `e` or `E`. Consume the
   full exponent digit run and preserve the target's 19,999 magnitude cap.
4. Use the target power tables for direct decimal scaling and for the initial
   estimate of large or small values.
5. For inputs needing precise rounding, run the target `Bigint` comparison,
   multiply, shift, difference, ratio, and ULP correction loop. Preserve its
   tie handling and cleanup/recycling order.
6. Return the target result, write the target end pointer, and set `errno` to
   `ERANGE` (34) only on the confirmed overflow and underflow paths. Preserve
   the target behavior for inputs with no accepted numeric token.

### ABI and platform records

Add `__NSstrtod` to a PPC-only ABI overlay for `NSStrtod.m`, assign its source
symbol in `symbols.json`, and record its owner in `ownership.json`. Do not add
the shared internal helper names to exported-symbol assignments. Record the
i386 divergence: the i386 image does not export this helper and continues to
use libc in the scanner.

## Verification

- Compare the converter, every helper, table values, and caller integration
  against their live PPC IDA bodies and data.
- Validate the PPC ABI JSON, symbol assignment, ownership entry, and source
  registration; verify each defined export is unique.
- Run `git diff --check` for the slice.
- Do not add or run tests or builds for this reconstruction slice; runtime
  verification is outside its current scope.

## Out of scope

- Replacing the i386 `strtod` path.
- Changing `NSScanner` tokenization or locale behavior beyond forwarding the
  normalized PPC token to the target converter and honoring its end pointer.
- Reconstructing `__NSvsnprintf` or the Java bundle setup path.
