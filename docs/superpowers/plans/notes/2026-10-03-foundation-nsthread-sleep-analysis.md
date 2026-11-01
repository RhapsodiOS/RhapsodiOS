# Foundation `NSThread` interval sleep analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSThread.json`, and current Foundation
sources.

## `+[NSThread sleepForTimeInterval:]`

The ABI lists `sleepForTimeInterval:` as a class method with encoding
`v16@8:12d16`. IDA locates it at `0x42577cf4`. The implementation multiplies
the supplied seconds by `1000.0`, returns when the millisecond value is not
positive, and otherwise calls `_NSMilliSleep`. Values above `UINT_MAX` use
`(mach_msg_timeout_t)-1`; in-range values are converted to the timeout type.
The method therefore uses the same millisecond timeout path as the existing
`sleepUntilDate:` implementation.

The selector is implemented in `NSThread.m` and declared in `NSThread.h`.
The header imports `NSDate.h` to make `NSTimeInterval` available to callers.
Static exact-owner and whitespace checks only; no tests or builds were run.
