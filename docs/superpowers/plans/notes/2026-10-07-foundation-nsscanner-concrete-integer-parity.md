# `NSConcreteScanner` integer path parity (2026-10-07)

Compared the concrete scanner's `setScanLocation:` and `scanHexInt:` bodies
against both current IDA targets. The i386 methods are at `0x42534e94` and
`0x4258def4`; the PPC methods are at `0x42557abc` and `0x425a554c`.

Both `setScanLocation:` bodies check the receiver's current `_scanLocation`
against the string length before assigning the requested position. The source
has the same check and assignment order. This check looks unusual, but is
confirmed target behavior and was left unchanged.

Both `scanHexInt:` implementations skip configured characters, accept digits
and A-F/a-f, recognize an optional `0x`/`0X` prefix after a leading zero, and
saturate at `UINT_MAX` when the prior accumulated value exceeds `0x0fffffff`.
For a leading zero followed by a non-hex character, or by a prefix without a
valid following digit, both return success with zero and leave the scan cursor
immediately after the leading zero. An invalid initial nonzero character
returns failure without changing the cursor. `NSScanner.m` matches those
branches; no source or ABI change was needed. Static paired IDA/source review
only; no tests or builds were run.
