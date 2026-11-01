# `NSDate -compare:` unordered intervals (2026-10-07)

Compared `-[NSDate compare:]` in both IDA targets:

- i386 `0x4259ae04` compares the other interval against the receiver interval.
  An unordered floating-point comparison reaches the non-ascending return path
  and produces `NSOrderedSame`.
- PPC `0x425be380` returns `NSOrderedAscending` when the receiver interval is
  not greater than or equal to the other interval. An unordered comparison
  takes that branch, producing `NSOrderedAscending`.

The source previously used a shared `<` / `>` / fallback comparison, which
returned Same for unordered intervals on both architectures. `NSDate.m` now
preserves the PPC `>=` branch behavior and leaves the i386 path unchanged.

No ABI metadata changed. Static paired IDA/source review only; no tests or
builds were run.
