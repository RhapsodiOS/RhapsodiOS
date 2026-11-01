# Foundation C-string logging hooks

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA confirms `_NSLogCStringFunction()` returns the active callback and
`_NSSetLogCStringFunction(callback)` stores the callback, resetting to the
default when passed null. `NSLogv` formats the message, obtains its lossy C
string, measures its length, and invokes the callback with display flag `1`.

The getter, setter, and `NSLogv` callback dispatch are implemented in
`NSObjCRuntime.m`; the callback type is declared in `NSObjCRuntime.h`. The
default adapter preserves this source's existing stderr sink. IDA's default
callback adds process/date formatting and syslog fallback; that behavior is a
remaining fidelity gap. The two exports are recorded in `NSObjCRuntime.json`
and assigned to `NSObjCRuntime.m` in `symbols.json`. No tests or builds were
run.
