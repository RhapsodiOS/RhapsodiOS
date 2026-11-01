# PPC Foundation ABI Selector Audit — 2026-10-06

IDA comparison found ten PPC Objective-C methods whose method-list entries were not represented by the source/target ABI manifest union. The source methods are present; these records close the target-specific metadata gap. Encodings below are the strings referenced by the PPC Objective-C method lists. Selector and method-entry addresses are PPC IDA effective addresses.

| Method | Type encoding | Method entry |
|---|---|---:|
| `+[NSDistributedNotificationCenter enableLogging:]` | `v5@4:8c12` | `0x42632224` |
| `+[NSString stringWithUTF8String:]` | `@8@4:8r*12` | `0x42633360` |
| `-[NSConcretePortCoder debugDescription]` | `@4@4:8` | `0x426324bc` |
| `-[NSConcreteTask processIdentifier]` | `I4@4:8` | `0x42638524` |
| `-[NSMachPort(NSPortMessageSpeedups) sendBeforeDate:components:from:reserved:]` | `c20@4:8@12@16@20I24` | `0x426285bc` |
| `-[NSString(NSStringOtherEncodings) UTF8String]` | `r*4@4:8` | `0x42628f60` |
| `-[NSString initWithUTF8String:]` | `@8@4:8r*12` | `0x4263a204` |
| `-[NSURL standardizedURL]` | `@4@4:8` | `0x4263a610` |
| `-[NSUndoManager(NSUndoManagerPrivate) _undoStack]` | `@4@4:8` | `0x42628944` |
| `-[_NSUndoLightInvocation _argument]` | `@4@4:8` | `0x42635f8c` |

Each method was confirmed PPC-only against the i386 selector set. The target encodes `processIdentifier` as unsigned; `NSTask.h` and `NSTask.m` now use `unsigned int` to match it. The shared `NSPort` record already describes a related selector with i386 offsets; the PPC overlay records the distinct `NSMachPort(NSPortMessageSpeedups)` entry and PPC frame encoding. Likewise, `NSConcretePortCoder` already had a class-side `debugDescription` record; this audit adds the separately confirmed PPC instance method.

No tests or builds were run. Verification is limited to JSON parsing, selector/owner presence checks, and whitespace diff checks.

### Whole-tree selector inventory rerun (2026-10-06)

The source selector inventory was rerun against both live reference binaries.
The PPC exact-owner checker reports 3,397 reference selectors and 3,416
source definitions, with no renames or duplicates. Its 11 apparent missing
selectors are the `NSURL` loading methods defined under the source-only
`NSURLLoading` / `NSURLHandleClient` category names; category-normalizing the
source names removes those misses. The i386 checker reports 3,253 reference
selectors and the same 3,416 source definitions, with no renames, duplicates,
or missing selectors. Its 163 extras include methods known to be PPC-only and
still need interpretation by their ABI overlays before being counted as
gaps. These are selector-name checks, not type-encoding or class-layout
verification.
