# Foundation `NSMutableString(NSCharacterSetMethods)` analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSNumberFormatter.json`.

## ABI owner gaps

The ABI manifest assigns four instance selectors to
`NSMutableString(NSCharacterSetMethods)`. No definitions under that category
exist in current source.

| Selector | Encoding | IDA address |
| --- | --- | ---: |
| `_replaceLastAppearanceOfString:withString:` | `v16@8:12@16@20` | `0x4258b47c` |
| `_replaceFirstAppearanceOfString:withString:` | `v16@8:12@16@20` | `0x42552e74` |
| `_replaceAllAppearancesOfString:withString:` | `v16@8:12@16@20` | `0x42552edc` |
| `_deleteAllCharactersFromSet:` | `v12@8:12@16` | `0x425416d4` |

## Confirmed behavior

- First and last replacement obtain the receiver's current length, search the
  entire range with `rangeOfString:options:range:`, and replace the found range
  once with `replaceCharactersInRange:withString:`. The first form uses search
  options `0`; the last form uses options `4`.
- Replace-all repeatedly searches the current full range for the source string
  and replaces each match with the constant string `M*A*G*I*C`. It then
  repeatedly searches the full range for that marker and replaces it with the
  requested replacement. IDA's constant string object at `0x426080fc` has
  length 9 and points to the bytes `M*A*G*I*C`. This two-pass marker algorithm
  avoids re-searching the replacement text during the first pass; the second
  pass also replaces pre-existing marker strings and can loop if the requested
  replacement itself contains the marker.
- Delete-from-set repeatedly obtains the receiver's current length, searches
  the full range with `rangeOfCharacterFromSet:options:range:` using options
  `0`, and replaces each nonempty match with `__NSEmptyString`.
- Each loop stops when the returned range length is zero. Searches are
  reissued against the receiver's updated full length after every mutation.

The methods use ordinary Objective-C dispatch to the `NSString` search
selectors and the receiver's `replaceCharactersInRange:withString:`. Current
source already implements those APIs. A source addition can therefore remain
within a category in `NSMutableString.m`; no new helper or public declaration
is indicated by the ABI.

No source code, tests, or builds were changed or run for this analysis.

## Implementation status (2026-10-03)

Implemented the four ABI-owned methods in `NSMutableString(NSCharacterSetMethods)`.
First/last replacement perform one full-range search; replace-all uses the
reference's two-pass `M*A*G*I*C` sentinel; deletion repeatedly removes the first
character-set match until none remains. All mutations dispatch through the
existing NSString range methods and NSMutableString replacement primitive.

The exact-owner audit reports 4 expected selectors, 0 missing, and 0 duplicate
owners. `git diff --check` is clean. No tests or builds were run.
