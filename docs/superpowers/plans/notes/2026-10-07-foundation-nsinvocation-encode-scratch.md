# `NSInvocation` PPC encoding scratch storage (2026-10-07)

PPC `-[NSInvocation encodeWithCoder:]` at `0x42525104` uses a dynamically
sized, 16-byte-aligned stack buffer for each ordinary argument. It copies the
argument into that buffer with `getArgument:atIndex:` and passes the buffer to
the coder's typed encoder. i386 encodes directly from the argument frame.

`NSInvocation.m` now follows those architecture-specific paths. The PPC branch
uses aligned `__builtin_alloca` storage and no zone allocation or free. Static
IDA/source comparison only; no tests or builds were run.
