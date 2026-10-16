# Foundation C-string logging hook analysis

Reference: Foundation i386 IDA database `703cb6287da7`.

## Export behavior

| Mach-O export | IDA address | Observed behavior |
| --- | ---: | --- |
| `__NSLogCStringFunction` | `0x42547734` | Returns the current `_NSLogCString` callback. |
| `__NSSetLogCStringFunction` | `0x42585468` | Replaces `_NSLogCString` and returns the supplied callback; null restores the default callback. |
| `_NSLogv` | `0x42547a78` | Formats and converts the message to a C string, computes its length, calls the callback with `(bytes, length, 1)`, then pops its autorelease pool. |
| `_NSDefaultLogCString` | `0x42547748` | Formats process/date metadata, writes to stderr, and falls back to syslog when stderr is not usable. |

The setter's default pointer at `0x42602580` resolves to
`_NSDefaultLogCString`. IDA infers its callback signature as
`(char *, unsigned length, char timestampFlag)`. The getter/setter pair is
not a faithful isolated slice: `NSLogv` must dispatch through the callback,
and the current `NSObjCRuntime.m` instead calls `_NSBasicStdErrLog`
directly. Implementing only the getter and setter would leave the hook
disconnected. The next source change should cover the callback storage,
default restoration, `NSLogv` dispatch, and default logger together, while
preserving the public `NSLog` and `NSLogv` signatures.

No implementation, tests, or builds were added or run for this analysis.
