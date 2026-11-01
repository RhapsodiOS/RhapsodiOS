# Foundation object introspection helpers

Reference: Foundation i386 IDA database `703cb6287da7`.

Implemented three helpers in `NSObjCRuntime.m`:

| Mach-O export | IDA address | Behavior |
| --- | ---: | --- |
| `__NSIMPForObjectAndSelector` | `0x425046ec` | Looks up the selector on the receiver's class; returns the method implementation, or `objc_msgSend` when the runtime reports `_objc_msgForward`. |
| `__NSImplementationForObjectAndSelector` | `0x425755d0` | Registers the selector name and returns the method implementation, or null when the runtime reports `_objc_msgForward`. |
| `__NSFullMethodName` | `0x4257075c` | Formats a receiver and selector as `+[Class selector]` for a class object, or `-[Class selector]` for an instance. |

All three exports and their `NSObjCRuntime.m` ownership are recorded in the
ABI and symbol manifests. No tests or builds were run.
