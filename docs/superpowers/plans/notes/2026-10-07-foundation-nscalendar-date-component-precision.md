# `NSCalendarDate` component precision (2026-10-07)

Compared the hour, minute, and second component accessors in both IDA targets:

| Component | i386 | PPC |
| --- | --- | --- |
| `hourOfDay` | `0x425488d8` | `0x425bc0fc` |
| `minuteOfHour` | `0x425487e0` | `0x425bd1d8` |
| `secondOfMinute` | `0x42548660` | `0x425bd5e8` |

The microsecond accessor uses `floor` and double-precision multiplication in
both targets: i386 `0x4259a680` and PPC `0x425bd174`.

Each target calculates the timezone-adjusted hour, minute, and second value
using extended precision, converts it to `double`, then computes the
within-unit remainder with `floor` and converts the result to `int`. The source
helper previously kept the value in `long double` through the remainder
calculation and used `floorl`. It now preserves the target's `double` conversion
point and `floor` operation, while retaining the existing negative-component
normalization. The microsecond method also uses the target's double-precision
expression.

No ABI metadata changed. Static paired IDA/source review only; no tests or
builds were run.
