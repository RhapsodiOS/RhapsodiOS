# `NSProcessInfo -environment` empty-value behavior (2026-10-07)

Compared DR2 i386 `-[NSProcessInfo environment]` at `0x42533bc0` and MOSXS
PPC at `0x42596d08`. Both targets allocate the key string before checking
the value, then release the key without inserting it when the entry has no
`=` or when the value after `=` is empty. Nonempty values are inserted and
both temporary strings are released.

`NSProcessInfo.m` now requires a nonempty value before constructing and
inserting the value string. The key construction and release order is
unchanged. Static paired IDA/source review and whitespace checks only; no
tests or builds were run.
