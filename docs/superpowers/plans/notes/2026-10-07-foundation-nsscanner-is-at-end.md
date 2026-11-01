# Foundation `NSScanner isAtEnd` paired IDA evidence (2026-10-07)

DR2 i386 implements `-[NSScanner isAtEnd]` at `0x4255299c`; MOSXS PPC
implements it at `0x4255ad88`. Both fetch the current scan location and string
length. When a skip set exists, they search the remaining range for a character
outside that set and use the match location, or the string length when there is
no match. The method returns whether that resulting location equals the string
length; it does not update the scanner's stored scan location.

`NSScanner.m` follows this control flow in `-[NSConcreteScanner isAtEnd]`.
This is a source/IDA parity finding, so no implementation change was needed.
No tests or builds were run.

The same paired review covered `-[NSScanner scanFloat:]` and
`-[NSScanner scanDouble:]` (i386 `0x4253af20` / `0x4253afc0`; PPC
`0x425a547c` / `0x42557780`). Both targets pass the string, skip set, output
storage, cursor, and locale to `_NSScanDoubleFromString`; on failure they
return without changing the scanner location, and on success they store the
result where applicable and set the location returned by the helper. The
concrete source methods match this control flow, including the float
conversion.
