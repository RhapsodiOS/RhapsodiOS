# Foundation delayed-perform category owner correction

The delayed-perform method bodies in `NSRunLoop.m` match IDA: NSObject's
selector wrappers delegate to NSTimer, class cancellation delegates to the
current run loop, and ordered run-loop performers are inserted or invalidated
by selector, target, and argument. The bodies were registered in flat
`NSObject` and `NSRunLoop` implementations, while
`reconstruction/abi/NSRunLoop.json` assigns them to
`NSObject(NSDelayedPerforming)` and `NSRunLoop(NSPerformTimerStuff)`.

Rehomed the existing definitions to those category owners and added the
missing public declaration for `performSelector:object:afterDelay:`. Static
exact-owner and whitespace checks only; no tests or builds were run.
