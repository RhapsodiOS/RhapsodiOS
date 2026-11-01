# `NSFileManager -contentsEqualAtPath:andPath:` parity (2026-10-07)

Compared the regular-file branch in both Foundation IDA databases:

- DR2 i386 `-[NSFileManager contentsEqualAtPath:andPath:]` at `0x4257ec2c`.
- MOSXS PPC `-[NSFileManager contentsEqualAtPath:andPath:]` at `0x425936e8`.

After file type checks, both targets reject files whose `st_ctimespec.tv_nsec`
or `st_birthtimespec.tv_sec` differs, then compare bytes through the file
descriptor helpers. Before opening the first file, both targets first validate
conversion with `getFileSystemRepresentation:maxLength:withPath:`, then obtain
the opened path through `fileSystemRepresentationWithPath:`. Neither target
compares `st_size` before opening the files. The source had used a size
equality check, skipped both timestamp checks, and opened the validation buffer
directly. `NSFileManager.m` now follows the target timestamp gates, conversion
call order, and removes the source-only size gate. Static source/IDA review
only; no tests or builds were run.

The symlink branches also differ in call order: i386 requests the path-2
symlink contents before path 1, while PPC requests path 1 before path 2. The
source now preserves that target split and still compares path 1's contents
with path 2's contents. Static paired IDA/source review only; no tests or builds
were run.
