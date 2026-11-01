# Path-completion username set parity (2026-10-07)

Paired IDA bodies for `-[NSString
completePathIntoString:caseSensitive:matchesIntoArray:filterTypes:]` (i386
`0x425824a4`, PPC `0x42597db0`) build a capacity-32 `NSMutableSet` for the
`~user` branch, add matching `~username` strings, call `allObjects`, release
the set, and return the resulting array/count. Both targets also create each
username with `stringWithCString:length:` using `strlen`.

`NSPathUtilities.m` previously collected usernames in a mutable array and
returned it directly. It now follows the set/all-objects ownership path and
the length-taking string factory, preserving the target's deduplication and
set-derived result ordering. No ABI or symbol ownership changed. Static paired
IDA/source review and whitespace checks only; no tests or builds were run.
