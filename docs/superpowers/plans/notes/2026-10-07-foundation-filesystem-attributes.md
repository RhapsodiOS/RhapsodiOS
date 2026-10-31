# `NSFileManager -fileSystemAttributesAtPath:` available-space parity (2026-10-07)

Compared DR2 i386 `-[NSFileManager fileSystemAttributesAtPath:]` at
`0x4257f444` and MOSXS PPC at `0x42593f50`. PPC pseudocode multiplies
`statfs.f_bavail` by `f_bsize` for `NSFileSystemFreeSize`; the i386 body uses
the corresponding `f_bavail` field at offset 20 from its `statfs` buffer. The
source used `f_bfree`, which reports all free blocks rather than the blocks
available to unprivileged callers. `NSFileManager.m` now computes the value
from `f_bavail` on both targets. Static paired IDA/source review only; no
tests or builds were run.
