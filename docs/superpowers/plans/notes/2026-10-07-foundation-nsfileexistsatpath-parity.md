# `_NSFileExistsAtPath` paired helper parity (2026-10-07)

Compared `_NSFileExistsAtPath` in DR2 i386 (`0x4252e394`) and MOSXS PPC
(`0x42526f88`) with the source helper in `NSFileManager.m`. Both targets wrap
the supplied UTF-16 slice in a no-copy mutable string, ask the manager for a
filesystem representation with maximum length 1026, release the temporary
string, and return false if conversion fails. They then call `lstat`; a
successful result is accepted directly except for symbolic links that are
followed with `stat`. `NSFileManager.m` uses the same conversion, cleanup,
`lstat`, mode mask, and conditional `stat` sequence in both its string-path
helper and exported character-slice helper.

The i386 and PPC control flow agrees. No source or ABI changes were needed.
Static paired IDA/source review only; no tests or builds were run.
