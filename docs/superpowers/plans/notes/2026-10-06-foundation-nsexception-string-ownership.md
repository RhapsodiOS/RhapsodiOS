# NSException string ownership and formatting recheck

Re-decompiled the relevant methods from the DR2 i386 and MOSXS PPC Foundation
databases. The confirmed behavior is:

- `-[NSException initWithName:reason:userInfo:]` copies `name` and `reason`
  with a null zone and retains `userInfo`; `dealloc` releases all three.
- `-[NSException isEqual:]` requires the same exact class and compares only
  `name` using `isEqual:`. It does not compare `reason` or `userInfo`, and it
  has no identity shortcut for an exception whose name is nil.
- `-[NSException initWithCoder:]` decodes three objects and passes them to
  `initWithName:reason:userInfo:`.
- `+[NSException raise:format:arguments:]` creates its reason with
  `[[NSString allocWithZone:NULL] initWithFormat:arguments:]`, autoreleases
  it, creates the named exception with nil `userInfo`, and raises it.
- `_NSMethodExceptionProem` returns the assembled C string through
  `+[NSString stringWithCString:length:]`.

`NSException.m` now follows these paths. It no longer reads arbitrary strings
as raw NXConstantString records or formats exception reasons with its private
`sprintf` loop. The old source-level `isEqual:` comparison helper was removed.
The i386 method addresses are `0x4253ee3c`, `0x4253f7e4`, `0x425739c0`,
`0x42573928`, `0x4253f4cc`, `0x42570a00`; the corresponding PPC addresses
are `0x42583af4`, `0x42583974`, `0x42583bc0`, `0x42583a70`,
`0x425819d8`, and `0x4257eba8`.

Static source/whitespace checks only; no tests or build were run.
