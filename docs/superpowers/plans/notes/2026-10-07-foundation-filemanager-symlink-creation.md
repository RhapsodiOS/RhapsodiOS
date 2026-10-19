# `NSFileManager` symbolic-link creation evaluation order (2026-10-07)

Compared `-[NSFileManager createSymbolicLinkAtPath:pathContent:]` in DR2 i386
(`0x4257f2f0`) and MOSXS PPC (`0x42593d28`). Both targets convert the link
path first, then attempt conversion of the link contents regardless of whether
the first conversion succeeded. They call `symlink(contents, path)` only when
both conversions succeed.

`NSFileManager.m` used a chained `&&`, which skipped link-content conversion
when path conversion failed. The method now preserves the two conversion calls
and gates only the final `symlink` operation on their combined result. Static
paired IDA/source review only; no tests or builds were run.
