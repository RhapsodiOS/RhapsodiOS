# Foundation `NSDictionary` coding selector reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSDictionary.json`.

## IDA behavior

- `-[NSDictionary classForCoder]` at `0x4255d720` returns
  `__NSDictionaryClass`; `-[NSMutableDictionary classForCoder]` at
  `0x4254e740` returns `__NSMutableDictionaryClass`.
- `-[NSDictionary encodeWithCoder:]` at `0x4255e5dc` encodes the count using
  type `i`, then encodes each key and its value with `encodeBycopyObject:` in
  key-enumerator order.
- `-[NSDictionary initWithCoder:]` at `0x42537cd0` decodes the count as type
  `i`. Zero initializes with null object/key arrays. A nonzero count passes
  through `__NSDictionaryCheckSize`; counts above 128 use two default-zone
  buffers. It decodes each key then value as type `@`, initializes with the
  object and key buffers, releases every decoded object, and frees both heap
  buffers.
- `__NSDictionaryCheckSize` at `0x42509390` rejects counts above
  `0x07ffffff` with `NSInvalidArgumentException` and format
  `%@: absurd %s: %d`.

## Implementation status (2026-10-03)

Implemented both `classForCoder` methods, `encodeWithCoder:`, and
`initWithCoder:` in `NSDictionary.m` with the shared count guard. Static source
selector and whitespace checks are clean. Tests and builds were not run.

Also implemented `NSDictionary -replacementObjectForPortCoder:` at
`0x4255ef50`: by-copy coding returns the receiver; by-reference coding returns
a local `NSDistantObject` proxy using the coder's connection.
