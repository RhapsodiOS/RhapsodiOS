# Foundation i386 `NSStringArray` Reconstruction

## Goal

Reconstruct the target Foundation i386 `NSStringArray` class from IDA evidence
and the checked-in ABI manifest. The class is used by Foundation code that
needs an array-like view over packed UTF-8 strings, including file-system
directory results.

## Scope

Add a standalone `NSStringArray.m` implementation and register it in the
Foundation source list. Implement every class and selector in
`src/Kits/Foundation/reconstruction/abi/NSStringArray.json`: `NSStringArray`
has four factory methods and twenty-three instance methods; `_NSUTF8String`,
`_NSUTF8ASCIIString`, and `_NSUTF8NonASCIIString` provide the array-backed
element objects returned by indexed access. The complete module covers
construction, indexed access, lifetime management, concatenation, bit-vector
matching, and word extraction from strings, data, HTML, and RTF.

The ABI manifest is authoritative for class layout and signatures.
`NSStringArray` instances are 24 bytes with `_count` at offset 4,
`_extraRefCount` at 8, `_data` at 12, `_strings` at 16, and `_reserved` at 20.
The three element classes have sizes 8, 16, and 16 bytes respectively, with
their ivars and superclasses preserved exactly as recorded in the manifest.
The implementation must preserve `NSStringArray`'s superclass `NSArray`.
Keep the interfaces private to the implementation; no source header currently
declares these classes.

## Design

The packed representation is a copied `NSData` containing NUL-terminated
UTF-8 strings. `_count` records the known element count or the target's lazy
count state. On first indexed access, `_strings` becomes a contiguous cache of
16-byte element records. ASCII records point into the packed data;
non-ASCII records own a decoded `NSString`. These records use the
`_NSUTF8ASCIIString` and `_NSUTF8NonASCIIString` class layouts, whose common
`_NSUTF8String` base retains and releases the owning `NSStringArray` through
its extra reference count. `UTF8Data` exposes the packed form, while `count`
and `objectAtIndex:` provide the NSArray view. Cache cleanup and the custom
retain/release overrides must preserve IDA's observed ownership behavior.

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
- Do not reconstruct `NSPathStore2` or neighboring private string classes in
  this increment.
- Do not add or run tests or builds in this increment. Verify source hygiene
  and selector coverage with the existing static audit; behavioral validation
  remains a separate project step.

## Verification

After implementation, run `git diff --check` and the existing
`tools/binrecon/selector_check.py` against the Foundation i386 reference and
Foundation source directory. Confirm all classes and selectors in the
`NSStringArray.json` ABI manifest are accounted for without duplicates or
renames. Do not claim runtime behavior is verified without a permitted build
or behavioral check.
