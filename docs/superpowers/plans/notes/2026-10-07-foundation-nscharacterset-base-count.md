# NSCharacterSet base count parity (2026-10-07)

Paired IDA decompilation confirms `-[NSCharacterSet count]` obtains
`bitmapRepresentation`, asks the data object for its bytes, then counts set
bits across `0x2000` bytes:

- i386 `Foundation-i386`: `count` at `0x42588388`.
- PPC `Foundation`: `count` at `0x425a0600`.

The source previously called `characterIsMember:` for every UTF-16 code unit,
which included U+FFFF. The base `bitmapRepresentation` implementation in both
targets iterates only through U+FFFE, leaving the final bit clear. The source
now counts bits from the returned bitmap, matching the target's observable
behavior. No ABI fields or selectors changed. Static diff and whitespace
checks only; no tests or build were run.

## Base `isEmpty` bitmap-length parity

Paired IDA decompilation of `-[NSCharacterSet isEmpty]` shows it obtains the
bitmap, returns `YES` when it is nil, then scans every byte up to the bitmap's
reported length and returns `NO` on the first nonzero byte. i386 is at
`0x42588498`; PPC is at `0x425a075c`. The source previously delegated to
`count`, whose fixed `0x2000`-byte loop can differ for subclasses returning
other bitmap lengths. The base method now follows the target scan and signed
length check. No ABI fields or selectors changed. Static source/IDA review
only; no tests or build were run.
