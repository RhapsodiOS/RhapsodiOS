# `NSCalendarDate` absolute-day upper clamp (2026-10-07)

Compared the absolute-day conversion paths in both IDA targets:

- i386 `yearOfCommonEra` (`0x4259a860`), `monthOfYear` (`0x42548728`),
  `dayOfMonth` (`0x425489cc`), `dayOfWeek` (`0x425994cc`), and `dayOfYear`
  (`0x42599580`) clamp computed days above `INT_MAX` to `1460972` before
  converting to an integer and deriving calendar fields.
- i386 `dayOfCommonEra` (`0x4259945c`) directly converts an extended-precision
  day count without the field-accessor clamp.
- PPC `yearOfCommonEra` (`0x425bd7d4`), `monthOfYear` (`0x425bd290`),
  `dayOfMonth` (`0x425bb220`), `dayOfWeek` (`0x425bb308`), and `dayOfYear`
  (`0x425bb418`) use the same lower/upper clamp flow. The PPC upper replacement
  constant at `0x425e208c` is `1460972.0`.
- PPC `dayOfCommonEra` (`0x425bb188`) directly converts a `double` day count
  without the field-accessor clamp.

The shared `NSCalendarDateAbsoluteDay` helper already clamps below day 1, but
previously saturated above `INT_MAX`. It now uses the target's upper replacement
value, `1460972`, for all calendar-field accessors that share this helper. The
PPC accessors form the day value in `double`; the i386 accessors use the
extended-precision intermediate. The source helper now follows those separate
arithmetic paths. `dayOfCommonEra` remains a separate direct conversion in
both targets, uses the matching target precision, and does not use this clamp.

No ABI metadata changed. Static paired IDA/source review only; no tests or
builds were run.
