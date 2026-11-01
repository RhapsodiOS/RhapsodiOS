# NSCharacterSet integer parser parity

Compared the source helper `NSCharacterSetParseInteger` with the private
`NSParseIntegerFromString` routines in both Foundation targets:

- i386: `0x42536008`.
- PPC: `0x42561528`.

Both routines skip leading ASCII spaces and select hexadecimal only with the
exact prefix `0x`. PPC parses decimal or hexadecimal digits until the first
invalid character; its switch accepts `a` and `b` in lowercase and `C` through
`F` in uppercase. The i386 jump table accepts lowercase `a` through `f` as
well. The source helper had also accepted `0X`; removed that extra prefix and
kept the target-specific lowercase digit behavior with an architecture guard.

This helper is static, so no ABI or symbol inventory change is needed. The
prefix object is the literal `0x` in both binaries. At i386 jump table
`0x425360f4`, lowercase `a` through `f` have the same target offsets as
uppercase `A` through `F`. Static source review and whitespace check only; no
tests or build were run.
