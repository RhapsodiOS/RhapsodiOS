# Foundation `NSURL` accessor fidelity and selector-audit analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSURL.json`, current `NSURL.m`, and
`tools/binrecon/selector_check.py`.

## Accessor source corrections

The five ABI methods `relativeString`, `baseURL`, `absoluteURL`,
`relativePath`, and `isFileURL` previously had a semicolon before an
explanatory `//` comment and an opening brace inside the comment. The source
selector parser consequently failed to recognize their intended definitions.
Their signatures now open the method before the comment. The six `NSURLHandle`
methods with the same malformed spelling are outside the Foundation ABI
inventory and were left untouched.

## IDA behavior and source comparison

- `relativeString` (`0x42594ec8`) returns `_urlString`; source matches.
- `baseURL` (`0x42594ed8`) returns `_baseURL`; source matches.
- `absoluteURL` (`0x42594ee8`) returns `self` when there is no base URL; with a
  base URL it allocates `NSAbsoluteURL` and initializes it with the receiver's
  `absoluteString` and a nil base URL. The source now follows that allocation
  and initializer path directly; the slot holding the allocation selector is
  outside the loaded image, so its exact selector text remains unresolved.
- `relativePath` (`0x42595288`) parses the receiver's raw `_urlString`, returns
  nil for parse failure or an empty path range, otherwise takes that raw path
  substring and applies `standardizedNativePath`. The source now uses the raw
  string's path component and returns nil when the local parser reports an
  absent or empty path range. The local component scanner does not expose a
  separate parse-failure result.
- `isFileURL` (`0x425958bc`) compares `[self scheme]` with the file scheme;
  source matches.

A reference lookup confirmed three uses of the selector slot at `0x42609030`;
its value points outside the loaded image. The decompilation and class receiver
support the direct allocation-plus-initialization reconstruction, while the
selector spelling itself remains unverified.

The accessor definitions and `relativePath`/`absoluteURL` bodies were corrected
in `NSURL.m`. Static selector and whitespace checks were run; no tests or
builds were run.