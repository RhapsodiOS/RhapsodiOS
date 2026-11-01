# Base `NSScanner -scanInt:` implementation gap (2026-10-07)

Paired IDA review confirms `-[NSScanner scanInt:]` is implemented on both
targets: i386 `0x4258e43c` and PPC `0x425a5b38` read the current scan location,
skip set, and input string, then call `_NSScanIntFromString`. They update the
scanner's scan location only after the helper succeeds. On failure, the
method returns `NO` without changing the location.

The base `NSScanner.m` implementation raised
`NSRequestConcreteImplementation`, while `NSConcreteScanner` has a separate
optimized override that remains unchanged. The existing
`_NSScanIntFromString` source helper was also compared with the paired IDA
helpers at i386 `0x4252ec54` and PPC `0x42524174`; its signed parsing,
overflow saturation, decimal digit handling, and cursor result follow the
reference path. The base wrapper now reads the scan location, skip set, and
string, passes a local cursor and the caller's result pointer to the helper,
and updates the scanner location only on success, matching both target bodies.
Static paired IDA/source review and whitespace checks only; no tests or builds
were run.
