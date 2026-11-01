# `NSCalendarDate` date addition across timezone changes (2026-10-07)

Compared `-[NSCalendarDate dateByAddingYears:months:days:hours:minutes:seconds:]`
in DR2 i386 and MOSXS PPC IDA:

- i386: `0x425991f8`
- PPC: `0x425bad94`

The i386 body normalizes the calendar components, constructs one result date,
preserves the receiver's fractional reference-date seconds, and copies its
calendar format. The existing non-PPC source path follows that flow.

PPC additionally reads the receiver's GMT offset and loops after constructing
the candidate date. If the candidate's offset differs, it releases that date,
adjusts the seconds by the offset difference, and retries normalization and
construction. Once the offset is stable, PPC autoreleases the result, preserves
the fractional seconds, and copies the format. `NSCalendarDate.m` now keeps
this correction loop in its PPC-only path while retaining the i386 flow.

No ABI metadata changed. Static paired IDA/source review only; no tests or
builds were run.
