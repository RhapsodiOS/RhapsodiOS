# Foundation `NSLocalTimeZone` selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSTimeZone.json`, and current
`NSTimeZone.m`.

## `description`

`-[NSLocalTimeZone description]` is absent from source and present in IDA at
`0x4259cd7c`. The body obtains `[NSTimeZone defaultTimeZone]`, sends
`description` to that object, and returns an NSString formatted with
`Local Time Zone [%@]`. The selector reference at `0x42608974` is also used by
`NSObject -debugDescription`, whose body simply forwards that selector; this
cross-reference identifies it as `description`.

## Backwards-compatibility category owner

The ABI lists `timeZoneForDate:` under
`NSLocalTimeZone(NSBackwardsCompatibility)` with encoding `@12@8:12@16`. IDA's
`-[NSLocalTimeZone timeZoneForDate:]` body at `0x4259cee8` obtains the default
time zone and forwards `timeZoneForDate:` with the supplied date. The source
already has this body inside `@implementation NSLocalTimeZone`; its behavior
is present, but the owner differs from the ABI category.

These findings support a bounded slice: add the confirmed `description` body
to `NSLocalTimeZone` and move the existing forwarding method into the named
backwards-compatibility category without changing its body. No source change,
test, or build was made for this analysis.

## Implementation status (2026-10-03)

`-[NSLocalTimeZone description]` is implemented with the IDA format string and
the default time zone's `description`. The existing `timeZoneForDate:`
forwarder is now owned by `NSLocalTimeZone(NSBackwardsCompatibility)`, matching
the ABI category while preserving its body.
