# Foundation `NSValue` geometry selector-owner audit

Reference: DR2 i386 Foundation IDA database `d12fe2f23883` and the current
Foundation selector audit.

IDA names the nine geometry and range methods as direct `NSValue` methods:
`allocWithZone:`, `valueWithPoint:`, `valueWithRange:`, `valueWithRect:`,
`valueWithSize:`, `pointValue`, `rangeValue`, `rectValue`, and `sizeValue`.
The source already implemented their bodies under the
`NSValueGeometryExtensions` category. The selector audit therefore reported
the class-owned methods missing and the category-owned methods extra.

The implementations are now part of `@implementation NSValue`, preserving the
existing source bodies. The factory methods' type encodings and `_valueType`
values match IDA at `0x42598fe0`, `0x42599024`, `0x42599068`, and
`0x425990a0`; `allocWithZone:` matches the placeholder/subclass split at
`0x42598fa8`. The four accessors read values through `getValue:` as in IDA at
`0x425a01b4`, `0x425a01e4`, `0x425a0214`, and `0x425a0264`.

The Foundation selector audit now reports 429 missing selectors and 121
extras, down from 438 and 130. It reports zero renames and duplicates. The
remaining `NSValue` gaps are separate base and decoder methods. `git diff
--check` passed; tests and builds were not run.
