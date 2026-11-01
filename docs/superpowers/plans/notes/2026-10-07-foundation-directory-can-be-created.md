# `NSFileManager -directoryCanBeCreatedAtPath:` call-flow parity (2026-10-07)

Compared DR2 i386 `-[NSFileManager directoryCanBeCreatedAtPath:]` at
`0x4254f438` and MOSXS PPC at `0x42593e24`. Both first obtain
`[path fileSystemRepresentation]`, then derive and check the parent path with
`_NSFileAccessibleForMode(parent, 3)`, probe with `_NSCreateDirectory2`, remove
a successfully created directory with `_NSRemoveDirectory2`, and accept
`cthread_errno() == EEXIST`. The source previously checked the parent before
converting the input path, used a bounded conversion that returned `NO` on
failure, called `mkdir`/`rmdir` directly, and read `errno`. It now follows the
target call order and helpers. Static paired IDA/source review only; no tests
or builds were run.
