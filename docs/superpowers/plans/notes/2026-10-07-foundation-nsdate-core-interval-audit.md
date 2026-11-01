# `NSDate` core interval methods (2026-10-07)

Compared these methods in the DR2 i386 and MOSXS PPC IDA targets against
`NSDate.m`:

| Method | i386 | PPC | Result |
| --- | --- | --- | --- |
| `timeIntervalSinceDate:` | `0x4259b120` | `0x42553cd0` | Returns receiver interval minus argument interval. |
| `isEqualToDate:` | `0x4253f9bc` | `0x42558aac` | Compares the two reference-date intervals for equality. |
| `earlierDate:` | `0x42548354` | `0x425be49c` | Copies and autoreleases the earlier date; ties select the argument. |
| `laterDate:` | `0x4259b074` | `0x425be808` | Copies and autoreleases the later date; ties select the argument. |
| `+[NSDate dateWithTimeIntervalSinceReferenceDate:]` | `0x425120d4` | `0x425489cc` | Allocates with a null zone, initializes with the supplied interval, then autoreleases. |
| `+[NSDate timeIntervalSinceReferenceDate]` | `0x42543124` | `0x4254b178` | Returns `__NSCurrentTime()`. |
| `-[NSDate initWithTimeIntervalSinceReferenceDate:]` | `0x4259b05c` | `0x425be754` | Requests a concrete object from the abstract base initializer and returns nil. |
| `-[NSDate timeIntervalSinceReferenceDate]` | `0x4259b160` | `0x425be8d0` | Requests a concrete implementation, then returns the target's zero fallback. |

The source matches those bodies. `compare:` has a separate recorded PPC
unordered-interval difference in
`2026-10-07-foundation-nsdate-compare-unordered.md`.

The four factory/base interval methods in the table also match the paired IDA
bodies; no source change was needed. The concrete date subclass provides the
stored-interval initializer/accessor used by the factory.

`NSDistantDate` also returns its stored sentinel interval unchanged from
`timeIntervalSinceNow`, `timeIntervalSinceDate:`, and `timeIntervalSince1970`
in both targets (i386 `0x42513e1c`, `0x4259ccd0`, `0x4259ccc0`; PPC
`0x42526a60`, `0x425c09ec`, `0x425c09dc`). The source preserves this behavior.

No source or ABI changes were needed for this audit. Static paired
IDA/source review only; no tests or builds were run.

## Current-time helper and epoch conversions (2026-10-08)

Compared `_NSCurrentTime` in i386 (`0x42507ac0`) and PPC (`0x4251042c`).
Both call `gettimeofday` and return microseconds plus seconds relative to the
2001 reference epoch; PPC's `tv_sec - 978321408 + 14208` is algebraically the
same offset as i386's `tv_sec - 978307200`. The paired `timeIntervalSinceNow`
methods subtract this helper from the receiver interval, and
`timeIntervalSince1970` adds `978307200`. `NSDate.m` matches these paths.
Static paired IDA/source review only; no tests or builds were run.
