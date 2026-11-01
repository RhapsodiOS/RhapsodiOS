# Foundation `__NSCStringToUnsignedLong` analysis

IDA MOSXS PPC identifies `__NSCStringToUnsignedLong` at `0x4257d6a4` with
the effective signature `unsigned int (char *string, unsigned int *end)`. The
DR2 i386 Foundation database has no matching function. The PPC function has no
code-call xrefs in the Foundation image; its xrefs are an offset in the
`j___NSCStringToUnsignedLong` jump stub at `0x42624e90` and one data reference.
This means the public export may be used by clients outside this image, but the
current binary gives no internal call sites to constrain its contract.

The body is a 32-bit unsigned integer scanner with base autodetection:

- It consumes leading characters marked as whitespace by the current rune
  locale, then accepts one optional `-` or `+`.
- Decimal is the default. A leading `0` selects octal; `0x` or `0X` after that
  selects hexadecimal.
- ASCII decimal digits are recognized through `_DefaultRuneLocale`; other
  hexadecimal digits use rune alphabetic and uppercase classifications and
  the target's ASCII digit mapping.
- Overflow is checked before each multiply/add. Once overflow is detected, the
  function consumes the remainder of the digit sequence, returns
  `0xffffffff`, calls `cthread_set_errno_self(34)`, and sets `errno` to 34.
- A negative sign negates the accumulated result modulo 2^32; the return type
  is unsigned. If the end pointer is non-null, the function stores the current
  scan position (`a1 - 1`) in it.

The export is currently absent from Foundation source and from the shared
symbol, ownership, and ABI maps. `rg` found no current Foundation-source
callers. An implementation needs to preserve the locale rune classifications
and thread-local errno side effect; delegating to libc `strtoul` is not shown
to match the target's two-argument API or end-pointer behavior. No source or
metadata changes were made in this analysis.

## Live PPC decompilation recheck (2026-10-05)

The attached MOSXS IDA database decompiles the export at `0x4257d6a4` as a
620-byte function ending at `0x4257d910`, with the expected two-argument
signature. The scan classifies one initial character in a `do` loop before
checking for a sign, so an empty string reaches digit classification as its
NUL byte. In the `0x`/`0X` path it advances past both prefix characters while
keeping the following byte as the current digit; otherwise the leading zero
is processed by the ordinary octal digit path. After overflow, it continues
consuming valid digits without changing the accumulator, then returns
`0xffffffff` and sets both cthread-local errno and `errno` to 34. The normal
path does not clear a preexisting errno. The end pointer is written as the
current input pointer minus one, including the no-digit path. This recheck
confirms the prior scanner design; it does not authorize implementation.

## PPC parser implementation (2026-10-05)

Implemented the target helper as `_NSCStringToUnsignedLong` in `NSScanner.m`,
guarded to PPC. It retains the do-while whitespace scan, optional sign,
decimal/octal/hexadecimal selection, locale-aware alphabetic digit mapping,
continued digit consumption after overflow, `UINT_MAX` overflow result, dual
cthread/process errno update, and end pointer at the current byte. Added the
export to the PPC-only `abi-ppc/NSScanner.json` overlay, shared source-symbol
assignment, and ownership map; documented the i386 absence in
`reconstruction/divergences.md`. Static checks only; no tests or builds were
run.
