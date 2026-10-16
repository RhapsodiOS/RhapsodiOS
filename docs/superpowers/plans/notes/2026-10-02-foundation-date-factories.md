# Foundation NSDate factory reconstruction

Reference: Foundation i386 IDA database instance `d12fe2f23883`.

`+[NSDate dateWithDate:]` reads the input date's reference interval and sends
`dateWithTimeIntervalSinceReferenceDate:` to the receiving class.
`+[NSDate dateWithTimeInterval:sinceDate:]` adds the supplied interval to the
date's reference interval, allocates in the default zone, initializes with the
sum, and autoreleases the result. The two factory declarations and
implementations are now present in `NSDate.h` and `NSDate.m`.

The source selector audit recognizes both methods. Its totals changed from 745
to 743 missing selectors, with zero renames or duplicates and 135 extra
selectors remaining. Source-only checks found no trailing whitespace in
`NSDate.m`; no tests or builds were run.
