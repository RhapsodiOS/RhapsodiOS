# `NSCalendarDate` nil timezone initialization (2026-10-07)

Compared `-[NSCalendarDate initWithYear:month:day:hour:minute:second:timeZone:]`
in both IDA targets:

- i386: `0x4259a4f0`
- PPC: `0x425bcf44`

The i386 body deallocates the receiver and returns nil when the timezone
argument is nil. The PPC body substitutes `[NSTimeZone defaultTimeZone]`, then
uses that zone for offset calculation and retains it on the receiver. The
shared source previously implemented only the i386 nil path. `NSCalendarDate.m`
now selects the default timezone on PPC and keeps the i386 deallocate-and-nil
path.

No ABI metadata changed. Static paired IDA/source review only; no tests or
builds were run.
