# NSInvertedCharacterSet equality parity (2026-10-07)

Paired IDA decompilation confirms `-[NSInvertedCharacterSet isEqual:]` first
checks identity, then requires the argument's exact class to be
`NSInvertedCharacterSet` before comparing `realset` identity; other objects
fall through to the superclass implementation:

- i386 `Foundation-i386`: method at `0x4258ab34`.
- PPC `Foundation`: method at `0x425a2d88`.

The source previously used `isKindOfClass:`, accepting subclasses in the
specialized identity case. It now checks exact class equality. No ABI fields or
selectors changed. Static diff and whitespace checks only; no tests or build
were run.
