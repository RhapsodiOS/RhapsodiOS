# Foundation `NSThread` selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSThread.json`, and current
`NSThread.m`.

The ABI has three `NSThread` selectors with no source definition: class
`sleepForTimeInterval:` (`0x42577cf4`) and instance `_threadName`
(`0x425838a4`) and `description` (`0x42583a08`).

- `+[NSThread sleepForTimeInterval:]` multiplies the input seconds by 1000. It
  does nothing when the scaled value is not positive. If the result exceeds
  `UINT_MAX`, it passes `-1` to `_NSMilliSleep`; otherwise it converts the
  positive millisecond value to an integer using the reference's x87 conversion
  sequence and passes that value to `_NSMilliSleep`.
- `-[NSThread _threadName]` obtains the current thread's cthread name with
  `ur_cthread_self` and `cthread_name`, computes its C-string length, then
  creates a string with `stringWithCString:length:`. The length is left on the
  caller's stack across the second `ur_cthread_self` call and consumed as the
  second string-constructor argument.
- `-[NSThread description]` obtains the current thread identifier from the
  word at offset 4 of `ur_cthread_self()` and returns a string formatted with
  `Thread %d`. The receiver is not read by the IDA body.

The ABI signatures are `v16@8:12d16`, `@8@8:12`, and `@8@8:12`,
respectively. These are small additions to the existing `NSThread`
implementation; no source change, test, or build was made for this analysis.
