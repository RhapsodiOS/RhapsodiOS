# `NSProcessInfo -processName` target ownership parity (2026-10-07)

Compared i386 `-[NSProcessInfo processName]` at `0x42540398` and PPC at
`0x4252d30c`. Both lazily allocate an NSString and initialize it from
`_NSProcessName()` with its C-string length. The PPC body then sends `retain`
to the initialized string before storing it in `self->name`; the i386 body
stores the initializer result directly.

`NSProcessInfo.m` now preserves this architecture-specific ownership flow
with a PPC-only retain. The method's lazy cache and input conversion are
otherwise unchanged. Static paired IDA/source review and whitespace checks
only; no tests or builds were run.
