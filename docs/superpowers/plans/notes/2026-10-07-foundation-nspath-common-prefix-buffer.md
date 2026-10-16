# Path-completion common-prefix buffer parity (2026-10-07)

Paired IDA bodies for `_NSFindCommonPrefixInStringArray` are i386
`0x42584c3c` and PPC `0x4259bf20`. Both return the empty singleton for zero
elements and the sole element for one. For larger arrays, they copy objects
once with `getObjects:range:` into a 256-pointer stack buffer, allocating
`count * sizeof(id)` from the default zone only when the count exceeds 256.
They advance the first string by composed-character sequence, build each
candidate prefix with `substringWithRange:`, and accept a candidate when
`rangeOfString:options:range:` reports a match at location zero.

`NSPathUtilities.m` now follows that storage and dispatch path. It no longer
calls `objectAtIndex:` for every candidate or adds a source-only matched-length
check; it releases a dynamically allocated pointer buffer after comparison.
Static paired IDA/source review and whitespace checks only; no tests or builds
were run.
