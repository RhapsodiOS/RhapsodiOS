# `NSString(NSSearchMethods)` reconstruction design

## Goal

Implement the six `NSString(NSSearchMethods)` selectors recorded by the exact
Foundation i386 ABI, matching their decompiled bodies and preserving the
instruction-confirmed edge behavior.

## Evidence

The selectors and encodings are in
`src/Kits/Foundation/reconstruction/abi/NSNumberFormatter.json`. IDA database
`d12fe2f23883` has symbols and decompilations for each method. The analysis is
recorded in
`docs/superpowers/plans/notes/2026-10-03-foundation-nssearchmethods-analysis.md`.
The ABI assigns this category to `NSNumberFormatter.m`, where no implementation
currently exists.

## Implementation shape

Add one `@implementation NSString (NSSearchMethods)` to
`src/Kits/Foundation/NSNumberFormatter.m`. Add only imports required by the
decompiled calls, including `NSScanner` if needed. Do not add a new translation
unit or modify NSString's general implementation.

Implement the methods as thin reproductions of the reference:

- `_copyToUnicharBuffer:saveLength:` reports the current UTF-16 length, allocates
  `(length + 1) * sizeof(unichar)` from the default zone for non-empty strings,
  copies characters without initializing the spare code unit, frees the
  previously supplied pointer through `NSZoneFromPointer`, then stores the new
  pointer. For empty strings, replace the old pointer with null.
- `_stringWithSeparator:atFrequency:` returns `__NSEmptyString` for an empty
  receiver. For non-empty strings, allocate the target-sized output and
  temporary buffers, copy the receiver's characters, and insert the separator
  by walking backward at the observed frequency boundaries. Do not add a
  frequency-zero guard; the target divides by the supplied frequency.
- `_containsCharFromSet:` creates an `NSScanner`, scans up to the set, and
  returns `!isAtEnd`.
- `_componentsSeparatedBySet:` creates a mutable array with capacity 3 and a
  scanner with skipped characters disabled. Preserve the target loop: scan up
  to the set, add the output component without checking the scan result, then
  advance exactly one code unit if the scanner is not at end. This preserves
  the target's stale/uninitialized component behavior for leading and repeated
  separators.
- `_containsChar:` creates a string from the argument's low byte with the
  reference length rule, searches the full receiver range, and returns whether
  the returned `NSRange.length` is non-zero.
- `_containsString:` searches the full receiver range and returns whether the
  returned `NSRange.length` is non-zero.

## Scope and verification

Preserve the six ABI selectors and encodings; add no other helper API. Do not
change `NSScanner`, `NSString`, or `NSNumberFormatter` behavior outside this
category. Do not add or run tests or builds. Verify selector coverage against
the exact `Foundation-i386` reference and run source-hygiene checks only;
runtime behavior remains unverified.

## Review focus

- Ensure the `NSRange` return convention is interpreted using the returned
  length word, as the target instructions do.
- Keep `_copyToUnicharBuffer:saveLength:`'s pointer ownership and empty-string
  replacement behavior exact.
- Keep separator insertion's reverse indexing and unguarded frequency
  arithmetic exact.
- Preserve the `_componentsSeparatedBySet:` unchecked scan result and one-code-
  unit separator advance, including the target bug.
