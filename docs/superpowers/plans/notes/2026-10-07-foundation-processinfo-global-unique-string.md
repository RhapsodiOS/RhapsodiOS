# `NSProcessInfo -globallyUniqueString` target format parity (2026-10-07)

Compared the i386 body at `0x42581558` and PPC body at `0x425623a8` with the
current source. Both create a prototype from the host name, process ID, and
absolute current-time value, then append the incrementing counter. Their final
prototype field differs: both use `"%@_%d_%d_%d_"`. PPC obtains the UTF-16
process-name length and passes it as the last integer. i386 obtains the
process name's C-string pointer before calling `_NSProcessID`; the stack
arguments remain in place for `initWithFormat:`, so the pointer occupies the
final `%d` vararg.

`NSProcessInfo.m` now preserves that target-specific field and call order:
PPC uses `processNameLength`; i386 captures `processNameCString` before the
process-ID call and passes its 32-bit value. The format literals match. Static
paired IDA/source review and whitespace checks only; no tests or builds were
run.

## Singleton and process-path helper recheck (2026-10-08)

Rechecked `+[NSProcessInfo processInfo]` in i386 (`0x42535d84`) and PPC
(`0x42527b18`). Both lazily allocate with a null zone, initialize, cache, and
return the singleton without a lock; the source follows that sequence.
Compared `_NSProcessPath`, `_NSProcessName`, `_NSSearchForNameInPath`, and
`_NSGetEnvironmentVariable` in both images with their source implementations.
The environment override, PATH search, regular-file check, working-directory
fallback, argv fallback, basename extraction, cache ownership, and empty-string
fallbacks match the target bodies. No additional source correction was
indicated. Static paired IDA/source review only; no tests or builds were run.
