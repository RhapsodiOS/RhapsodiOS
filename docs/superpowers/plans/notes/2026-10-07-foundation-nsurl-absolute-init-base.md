# `NSURL` absolute initializer base argument

Paired DR2 i386 IDA at `0x425946f4` and MOSXS PPC IDA at `0x425ad478` show
that `-[NSURL initWithString:relativeToURL:]` releases its receiver when the
input contains a scheme, allocates `NSAbsoluteURL`, and initializes it with
the original string and a nil base URL. The source previously forwarded the
supplied `baseURL` in this branch. `NSURL.m` now passes nil, matching both
targets. The relative-string branch continues to retain the supplied base URL.
Static IDA/source review only; no tests or builds were run.
