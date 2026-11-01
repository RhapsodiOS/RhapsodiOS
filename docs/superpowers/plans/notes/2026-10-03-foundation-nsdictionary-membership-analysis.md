# Foundation `NSDictionary` membership selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDictionary.json`, and current
`NSDictionary.m`.

The ABI has two instance methods without source definitions under
`NSDictionary`: `containsObject:` (`c12@8:12@16`) and `countForObject:`
(`I12@8:12@16`). IDA confirms:

- `-[NSDictionary containsObject:]` at `0x4255d764` returns `NO` for a nil
  argument or a dictionary whose count is zero. Otherwise it walks
  `keyEnumerator`. It returns `YES` if the argument is identical to an
  enumerated key, or if the corresponding value is equal to the argument via
  `isEqual:`.
- `-[NSDictionary countForObject:]` at `0x4255d840` returns zero for a nil
  argument or empty dictionary. Otherwise it walks `keyEnumerator` and adds
  one for every identical key or corresponding value that compares equal to
  the argument via `isEqual:`.

Both methods therefore consider keys as well as values, and preserve the
reference's identity fast path for keys. `countForObject:` adds at most one for
each dictionary entry, even when the argument matches both that entry's key
and value. Both obtain values through `objectForKey:` rather than materializing
an `allValues` array.

The source currently has no `NSDictionary` definitions for these selectors.
The proposed bounded implementation adds the two loops to the existing
`NSDictionary` implementation and verifies owner-level selector presence and
whitespace. No source changes, tests, or builds are part of this analysis.

## Implementation status (2026-10-03)

Both selectors are now implemented in `NSDictionary.m`. The methods preserve
the IDA nil/empty fast paths, enumerate keys, count key matches by pointer
identity, and compare each corresponding value with `isEqual:`. Each entry
contributes at most one match. Static exact-owner selector checks find one
definition for each method, and `git diff --check` is clean. No tests or builds
were run.
