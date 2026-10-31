# Foundation `_NSNegativeRetain`

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA confirms `_NSNegativeRetain(void *, int)` at `0x42570b18`. It logs the
object address, the class name from the Objective-C class record, and the
virtual retain count with this format:

```text
*** _NSNegativeRetain(): object (0x%x) of class %s has less than zero (%d) virtual retains\n
```

The function is implemented in `NSDebug.m` using the class layout declared by
`objc/objc-runtime.h`. It is recorded in `NSDebug.json` and assigned to
`NSDebug.m` in `symbols.json`. No tests or builds were run.
