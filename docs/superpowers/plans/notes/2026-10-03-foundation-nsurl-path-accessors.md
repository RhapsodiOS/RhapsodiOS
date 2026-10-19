# Foundation `NSURL` path accessor reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSURL.json`.

IDA confirmed four remaining `NSURL` selectors at `0x42594b20`
(`description`), `0x42594ba0` (`copyWithZone:`), `0x425952fc`
(`_absoluteURLPath`), and `0x42595224` (`_relativeURLPath`).

- `_relativeURLPath` returns the parsed path substring when its length is
  nonzero, otherwise nil.
- `_absoluteURLPath` returns that path for a URL without a base or with a
  scheme. For a relative path, it uses the base path, returns absolute-path
  inputs directly, removes `.` components and eligible `..` pairs, then
  preserves the target's leading/trailing slash cases (`/%@`, `%@/`, and
  `/%@/`).
- `copyWithZone:` returns a retain of the receiver and ignores the zone.
- `description` returns `relativeString` without a base; with a base it formats
  `baseURL -- relativeString`.

The four methods are implemented once under `@implementation NSURL` in
`NSURL.m`. `git diff --check` reports no whitespace errors in the changed file.
Tests and builds were not run.
