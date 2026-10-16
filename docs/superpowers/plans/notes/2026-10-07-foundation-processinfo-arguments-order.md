# `NSProcessInfo -arguments` initialization order (2026-10-07)

Compared `-[NSProcessInfo arguments]` in DR2 i386 (`0x4254dc3c`) and MOSXS
PPC (`0x42539884`) with `NSProcessInfo.m`. Both targets read `_NSArgc()`
before `_NSArgv()`. The source called them in the opposite order; it now
matches the target sequence.

The paired bodies also confirm the existing architecture split: both
standardize the `_NSProcessPath()` value for element zero; i386 leaves later
arguments unchanged, while PPC standardizes them. The source already matches
those conversions and releases the owned argument strings after array
initialization. Static paired IDA/source review and whitespace checks only;
no tests or builds were run.
