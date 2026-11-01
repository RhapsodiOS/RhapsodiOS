# Foundation `NSArchiver` selector reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSArchiver.json`.

IDA identifies seven methods absent from the source: `NSArchiver`'s `data`,
`encodeDataObject:`, `encodeValuesOfObjCTypes:`, and class-wide class-name
mapping methods; `NSUnarchiver`'s `data` and `decodeValuesOfObjCTypes:`.
The data methods return the backing data directly. Data-object encoding writes
an `i` byte count followed by a `c` array. Typed variadic encoding and decoding
record or validate the complete type descriptor once, then process each value
through the existing typed helpers. Class-wide name mappings use a lazy
object-keyed map; instance mappings remain independent.

The seven methods are now implemented and declared in the existing archiver
header. The implementation also removes five source-only accessor selectors
that had been used by static C helpers. Those helpers now read the
`NSArchiver` ivars through a private layout matching the ABI manifest. The
manifest's 48 selectors now match the source exactly, with no missing,
additional, or duplicate selectors. No build or runtime test has been run.

IDA method addresses: `encodeDataObject:` `0x4254a310`,
`encodeValuesOfObjCTypes:` `0x4251e97c`, `decodeValuesOfObjCTypes:`
`0x425058f0`, `NSUnarchiver -data` `0x42575f4c`, `NSArchiver -data`
`0x42575d44`, `+[NSArchiver classNameEncodedForTrueClassName:]`
`0x42575b30`, and `+[NSArchiver encodeClassName:intoClassName:]`
`0x42575b98`.

## Archiver callback category ownership (2026-10-03)

The current ABI manifest places `classForArchiver` and
`replacementObjectForArchiver:` under `NSObject(NSArchiverCallBack)`. Their
source methods were in an unqualified `@implementation NSObject`, and the
header used the differently spelled category name `NSArchiverCallback`. The
implementation and declaration now both use the ABI category name. IDA at
`0x4252f74c` and `0x4252f83c` confirms the methods forward to `classForCoder`
and `replacementObjectForCoder:` without extra behavior. The separate legacy
`Object(NSCompatibility)` implementations remain distinct. Static exact-owner
and whitespace checks only; no tests or builds were run.
