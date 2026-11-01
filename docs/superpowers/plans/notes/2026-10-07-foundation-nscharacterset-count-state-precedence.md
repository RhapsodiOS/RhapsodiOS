# NSConcreteMutableCharacterSet count state precedence (2026-10-07)

Paired IDA decompilation confirms `-[NSConcreteMutableCharacterSet count]`
uses `_countMembersOfSetStruct` whenever `set` is non-null, and otherwise
counts the bitmap bytes:

- i386 `Foundation-i386`: `count` at `0x42588c38`.
- PPC `Foundation`: `count` at `0x425a0de4`.

The source previously selected the compact-set count only when `bits` was
null. `bitmapRepresentation` can materialize `bits` while preserving `set`, so
the source and target chose different representations in that state. The
source now gives `set` precedence. No ABI fields or selectors changed. Static
diff and whitespace checks only; no tests or build were run.

## `isEmpty` compact-state behavior

The same paired IDA bodies show `-[NSConcreteMutableCharacterSet isEmpty]`
returns true immediately when a non-null compact set has no singles or ranges;
otherwise it scans `bits` only when that pointer is non-null, and returns true
if it is null. Thus the target reports a nonempty compact-only set as empty.
The source previously delegated to `count`; it now follows these direct
checks, including that target behavior:

- i386 `Foundation-i386`: `isEmpty` at `0x42589528`.
- PPC `Foundation`: `isEmpty` at `0x425a1370`.
