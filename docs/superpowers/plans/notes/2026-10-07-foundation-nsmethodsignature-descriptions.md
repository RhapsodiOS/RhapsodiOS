# `NSMethodSignature` descriptions (2026-10-07)

Paired IDA review confirms i386 `description` at `0x425745fc` and PPC
`description` at `0x42584a84` format the cached type string, argument count,
parameter size, and return-value length as
`NSMethodSignature: types=%s nargs=%d sizeOfParams=%d returnValueLength=%d; `.

The i386 `debugDescription` at `0x42574558` and PPC method at `0x425849bc`
format the instance address, cached type string, argument count, frame size,
return type, and return length, then append each cached argument record. The
row format is `%@{%d : type(%s) size(%d) offset(%d)}\n`; both targets render
nested records recursively using `_NSIndentSpace` and the child format `%@%@`.
The PPC helper at `0x42586bbc` confirms the same nested traversal as i386
`_stringFromArgInfo` at `0x42575a18`. `NSMethodSignature.m` now implements the
paired formats and recursive record rendering; its former generic object
address description and `debugDescription` alias are removed. Static paired
IDA/source comparison and `git diff --check` only; no tests or builds were run.
