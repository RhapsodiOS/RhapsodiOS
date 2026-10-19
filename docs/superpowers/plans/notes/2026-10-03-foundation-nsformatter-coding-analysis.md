# Foundation `NSFormatter` coding and copying analysis

Reference: project Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSFormatter.json`, and
`src/Kits/Foundation/NSFormatter.m`.

## Confirmed base-class methods

The ABI includes three methods under `NSFormatter` that have no definitions in
its source implementation before this reconstruction:

- `-[NSFormatter initWithCoder:]` at `0x42553058` returns `self` without
  reading from the coder.
- `-[NSFormatter copyWithZone:]` at `0x4258a314` ignores the zone and returns
  `[self retain]`.
- `-[NSFormatter encodeWithCoder:]` at `0x4258a358` is a no-op.

Their ABI encodings are `@12@8:12@16`, `@12@8:12^{?=}16`, and
`v12@8:12@16`, respectively. `NSFormatter.m` already contains the
`@implementation NSFormatter` block and imports `NSObjCRuntime.h`; these three
definitions have been added there without new files or dependencies. The
selector audit and whitespace checks were run; no build or runtime tests were
run.
