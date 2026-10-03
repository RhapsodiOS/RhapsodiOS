# Foundation i386 `NSStringArray` Reconstruction

## Goal

Reconstruct the target Foundation i386 `NSStringArray` class from IDA evidence
and the checked-in ABI manifest. The class is used by Foundation code that
needs an array-like view over packed UTF-8 strings, including file-system
directory results.

## Scope

Add a standalone `NSStringArray.m` implementation and register it in the
Foundation source list. Implement every selector assigned to `NSStringArray`
in `src/Kits/Foundation/reconstruction/abi/NSStringArray.json`: its four
factory methods and twenty-two instance methods, including construction,
indexed access, lifetime management, concatenation, bit-vector matching, and
word extraction from strings, data, HTML, and RTF.

The ABI manifest is authoritative for class layout and signatures. Its
`NSStringArray` instance is 24 bytes with `_count` at offset 4,
`_extraRefCount` at 8, `_data` at 12, `_strings` at 16, and `_reserved` at 20.
The implementation must preserve those offsets and the superclass `NSArray`.
Keep the interface private to the implementation unless IDA or an existing
public header proves that the target exports a header declaration.

## Design

The packed representation is a copied `NSData` containing NUL-terminated
UTF-8 strings. `_count` records the known element count or the target's lazy
count state; `_strings` holds the decoded objects when indexed access needs
them. Array and component initializers encode into this representation.
`UTF8Data` exposes the packed form, while `count` and `objectAtIndex:` provide
the NSArray view. Deallocation and the custom retain/release overrides must
follow IDA's observed ownership and extra-reference-count behavior.

Matching and bit-vector methods must follow the target's helper routines and
option branches. Word extraction must preserve the distinct plain-text, HTML,
and RTF scanning modes, duplicate handling, case conversion, and the plain
data fallback for non-ASCII input. Implement helper algorithms only after
tracing their callers and behavior in IDA; do not infer option meanings or
parser behavior from selector names alone.

Existing Foundation support is reused where the target calls it: `NSData`,
`NSMutableData`, `NSHashTable`, `NSString`, `NSCharacterSet`, and locale
lookups through `NSLanguageContext`. No generic collection or string behavior
is redesigned as part of this module.

## Constraints and non-goals

- IDA behavior and the ABI manifest are the source of truth; retain no
  decompiler-generated identifiers in source.
- Preserve the existing Foundation source style and manual retain/release
  conventions.
- Do not modify unrelated string or collection modules.
- Do not reconstruct `NSPathStore2`, `_NSUTF8String`, or neighboring private
  string classes in this increment.
- Do not add or run tests or builds in this increment. Verify source hygiene
  and selector coverage with the existing static audit; behavioral validation
  remains a separate project step.

## Verification

After implementation, run `git diff --check` and the existing
`tools/binrecon/selector_check.py` against the Foundation i386 reference and
Foundation source directory. Confirm all `NSStringArray` selectors are
accounted for without duplicates or renames. Do not claim runtime behavior is
verified without a permitted build or behavioral check.
