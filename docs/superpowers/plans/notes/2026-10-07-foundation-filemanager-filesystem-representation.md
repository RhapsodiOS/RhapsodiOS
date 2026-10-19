# `NSFileManager` filesystem representation call order (2026-10-07)

Compared `-[NSFileManager getFileSystemRepresentation:maxLength:withPath:]`
in DR2 i386 (`0x42510300`) and MOSXS PPC (`0x4250cf54`), and
`-[NSFileManager fileSystemRepresentationWithPath:]` in DR2 i386
(`0x42540424`) and MOSXS PPC (`0x42534b34`). Both methods obtain the path's
`length` and the default filesystem encoding before calling `getBytes:`. i386
requests `length` before `_NSDefaultFileSystemEncoding`; PPC requests the
encoding first. The i386 encoding-helper call receives the length as an extra
argument, which the helper ignores. The path length remains the conversion
range length.

The i386 selector reference at `off_42608968` is used by methods named
`length`, including concrete string `length` implementations. The source had
evaluated the helper and path length within the `getBytes:` argument list,
leaving their order unspecified. `NSFileManager.m` now evaluates them
explicitly in each target's order and reuses the captured path length as the
conversion range. No selectors or ABI fields changed. Static paired IDA/source
review only; no tests or builds were run.
