# Foundation `NSScanner` construction parity (2026-10-07)

Paired DR2 i386 and MOSXS PPC decompilations show that
`scannerWithString:`, `localizedScannerWithString:`, and `copyWithZone:`
allocate `NSConcreteScanner` directly with a null zone. The source now names
that concrete class explicitly instead of routing through
`NSScanner +allocWithZone:` or `scannerWithString:`.

The target localized factory initializes and autoreleases the concrete scanner
before asking `NSUserDefaults` for its dictionary representation, then sets
the locale. The source now preserves that order. The target copy path reads
`[self string]` before allocating, then copies skipped characters, scan
location, case sensitivity, and locale in that order; the source now forces
the same sequence. `copyWithZone:` continues to use a null allocation zone,
matching both targets despite its `zone` argument.

IDA addresses: i386 `copyWithZone:` `0x4258dc5c`, `initWithString:`
`0x42536490`, `scannerWithString:` `0x425412cc`, and
`localizedScannerWithString:` `0x425873d8`; PPC `copyWithZone:` `0x425a51b4`,
`initWithString:` `0x42557984`, `scannerWithString:` `0x4255a83c`, and
`localizedScannerWithString:` `0x4259f064`. No ABI metadata changed. Static
source/decompilation comparison only; no tests or builds were run.

## Allocation, end detection, and float scan parity

Paired IDA review confirms `+[NSScanner allocWithZone:]` maps only the exact
`NSScanner` class to `NSConcreteScanner`, while subclasses are allocated as
themselves (i386 `0x42536e20`, PPC `0x42557900`). The source uses the same
class identity check and forwards the supplied zone to `NSAllocateObject`.

`-[NSScanner isAtEnd]` (i386 `0x4255299c`, PPC `0x4255ad88`) obtains the string,
current location, length, and skipped-character set; when a set exists, it
searches the remaining range for a member of the inverted set and treats no
match as end-of-string. `-[NSScanner _remainingString]` (i386 `0x4259f1d0`,
PPC `0x425c2944`) returns the substring from current location through the
string's end. Both source methods preserve these paths.

`-[NSScanner scanFloat:]` (i386 `0x4253af20`, PPC `0x425a547c`) reads the
current location, locale, skipped set, and string in that order, calls
`_NSScanDoubleFromString` into a temporary double, writes a narrowed float only
when the output pointer is nonnull, and commits the new location only on
success. `NSScanner.m` follows that order and conditional output behavior.
This was a paired IDA/source audit only; no tests or builds were run.

The paired `NSConcreteScanner initWithString:` bodies call the superclass
initializer but discard its return value, then initialize and return the
original receiver. `NSScanner.m` previously assigned the superclass result to
`self` and returned early on nil; it now preserves the target's ignored return
behavior as well.
