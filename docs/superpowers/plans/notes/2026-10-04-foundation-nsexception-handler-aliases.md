# Legacy NSException handler aliases

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA identifies `_NSAddHandler` at `0x42575408` and `_NSRemoveHandler` at
`0x425757e4`. Each forwards its handler pointer to `_NSAddHandler2` or
`_NSRemoveHandler2`, respectively. The source-level `NSHandler` type is
opaque in `NSException.h`; the wrappers therefore pass the pointer through
to the existing `NSHandler2` implementation. Both exports are recorded in
the NSException ABI, ownership, and module symbol maps. Neither has direct
callers in this IDA database.

No tests or builds were run.
