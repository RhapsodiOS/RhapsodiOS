# Foundation `NSThread` identity selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`, the project ABI
manifest, and `src/Libc-1/threads.subproj/cthreads.h`.

## Confirmed methods

IDA locates `-[NSThread _threadName]` at `0x425838a4`. It obtains the current
cthread name, counts its bytes up to the nul terminator, obtains that name
again, and calls `+[NSString stringWithCString:length:]`. In the project
cthreads header, `cthread_self()` is the current `ur_cthread_self()->incarnation`,
matching the target's load from offset four of the `ur_cthread_self()` record.
The source now uses `cthread_name(cthread_self())` and `strlen` to supply the
same name and explicit byte length.

IDA locates `-[NSThread description]` at `0x42583a08`. Its format constant is
`"Thread %d"`; the argument is the current record's `incarnation` field, which
is the `cthread_self()` value in the project header. The source formats that
value as a 32-bit integer, matching the i386 target.

Both methods are defined under the exact `NSThread` owner. Static selector
ownership and whitespace checks only; no tests or builds were run.
