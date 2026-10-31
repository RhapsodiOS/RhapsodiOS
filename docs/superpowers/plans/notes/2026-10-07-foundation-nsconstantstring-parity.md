# `NSConstantString` paired method parity (2026-10-07)

Compared all nine `NSConstantString` methods in `NSConstantString.m` against
both live Foundation IDA targets. The i386 bodies are at `0x425029d4`
(`release`), `0x42502fe0` (`copyWithZone:`), `0x425051f8` (`retain`),
`0x4250aa88` (`cString`), `0x42519914` (`autorelease`), `0x425430a4`
(`lossyCString`), `0x425533fc` (`retainCount`), `0x42589e18` (`dealloc`),
and `0x42589e3c` (`initWithCharactersNoCopy:length:`). The corresponding
PPC bodies are at `0x425032a8`, `0x4250328c`, `0x425039c8`, `0x42506f5c`,
`0x42511d04`, `0x42554318`, `0x425a1c74`, `0x425a1bfc`, and `0x425a1c38`.

Both targets make retain/release/autorelease no-ops or identity operations,
return the constant-string byte pointer from both CString accessors, return
`UINT_MAX` from `retainCount`, log the class name if `dealloc` is reached, and
raise `doesNotRecognizeSelector:` then return nil from the unsupported
initializer. `copyWithZone:` returns the receiver. `NSConstantString.m`
matches these bodies; no code or ABI changes were needed. Static paired
IDA/source review only; no tests or builds were run.
