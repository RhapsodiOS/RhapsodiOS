# Foundation `NSConstantString` analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSConstantString.json`.

The ABI manifest records `NSConstantString : NSSimpleCString`, with no added
ivars and a 12-byte instance size. IDA names all nine instance methods in the
manifest. The header already declares the class, and its inherited `bytes`
ivar is the C-string pointer used by the binary.

## Decompiled behavior

- `retain`, `autorelease`, and `copyWithZone:` return `self`; `release` is a
  no-op; `retainCount` returns `UINT_MAX`.
- `cString` and `lossyCString` both return the inherited `bytes` pointer.
- `dealloc` logs `*** dealloc called for %s`, passing the runtime class name.
  It does not deallocate the object.
- `initWithCharactersNoCopy:length:` sends `doesNotRecognizeSelector:` with
  its own selector and returns nil if that call returns.

Method addresses: `release` `0x425029d4`, `copyWithZone:` `0x42502fe0`,
`retain` `0x425051f8`, `cString` `0x4250aa88`, `autorelease` `0x42519914`,
`lossyCString` `0x425430a4`, `retainCount` `0x425533fc`, `dealloc`
`0x42589e18`, and `initWithCharactersNoCopy:length:` `0x42589e3c`.

The implementation is in its manifest module, `NSConstantString.m`, and is
registered in both Foundation source lists. Verification for this increment
is static selector coverage and source hygiene; no build or runtime check has
been run.
