# Foundation NSDate coding reconstruction

Reference: Foundation i386 IDA database instance `d12fe2f23883`.

IDA confirms that `-[NSDate classForCoder]` returns the `NSDate` class and
`-[NSDate encodeWithCoder:]` encodes the reference-date interval as one `double`.
`-[NSDate initWithCoder:]` decodes that same value and initializes with
`initWithTimeIntervalSinceReferenceDate:`. `-[NSDate initWithDate:]` initializes
from another date's reference-date interval. The port-coder replacement method
returns `self`.

These methods are implemented in `NSDate.m`; `initWithDate:` is declared in
`NSDate.h`. The source selector audit reports 738 missing selectors, down from
743, with zero renames and duplicates and 135 extra selectors remaining. No
tests or builds were run.
