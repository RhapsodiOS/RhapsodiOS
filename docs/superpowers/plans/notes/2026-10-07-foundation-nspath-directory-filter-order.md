# Path-completion directory filter call-order parity (2026-10-07)

Paired IDA bodies for `_NSDirectoryContentsMatchingPrefixAndSuffixes` are i386
`0x425849a8` and PPC `0x4259bb6c`. Both expand the directory, fetch its
contents, cache the contents count, and allocate the result array before
evaluating the prefix and extension filters. They compute the empty-prefix and
empty-filter flags once, then iterate to the cached count.

`NSPathUtilities.m` previously evaluated the filter count before directory
access, tested prefix length for each item, and re-sent `count` on every loop
condition. It now follows the target call order and cached predicate/count
flow. No ABI or symbol ownership changed. Static paired IDA/source review and
whitespace checks only; no tests or builds were run.
