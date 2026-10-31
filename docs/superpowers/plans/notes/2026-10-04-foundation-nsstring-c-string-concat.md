# Foundation fast multi-C-string concatenation

Reference: Foundation i386 IDA database `703cb6287da7`.

Reconstructed `__NSFastMultiCStringConcat` at `0x4253335c` in
`NSString.m`. The helper finds the terminator in the destination, appends
the first source C string and each subsequent variadic C string until the
null sentinel, then returns the original destination pointer. Its export is
assigned to `NSString.m` in the ABI and symbol manifests.

No tests or builds were run.
