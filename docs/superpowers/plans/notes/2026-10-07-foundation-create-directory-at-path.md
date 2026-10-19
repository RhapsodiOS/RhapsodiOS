# `NSFileManager -createDirectoryAtPath:attributes:` helper parity (2026-10-07)

Compared DR2 i386 `-[NSFileManager createDirectoryAtPath:attributes:]` at
`0x42557bb8` and MOSXS PPC at `0x42593c24`. Both call `_NSCreateDirectory`
with the original NSString path, return `NO` if it fails, apply optional
attributes through `changeFileAttributes:atPath:`, ignore that method's result,
and return `YES`. `_NSCreateDirectory` performs the NSString filesystem
conversion and delegates to `_NSCreateDirectory2`. `NSFileManager.m` now uses
that existing helper instead of duplicating conversion and `mkdir` in the
method body. Static paired IDA/source review only; no tests or builds were
run.
