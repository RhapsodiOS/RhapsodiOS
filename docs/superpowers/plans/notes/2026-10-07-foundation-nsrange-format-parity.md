# `NSStringFromRange` format parity (2026-10-07)

Resolved the earlier uncertainty recorded in `reconstruction/divergences.md`.
The format is architecture-specific:

- DR2 i386 `_NSStringFromRange` at `0x425a27d8` passes a constant string
  object whose character pointer resolves to
  `{location = %d; length = %d}` (28 bytes).
- MOSXS PPC `_NSStringFromRange` at `0x425c5fa4` passes a constant string
  object whose character pointer resolves to `{%u, %u}` (8 bytes).

`NSRange.m` now selects the matching format per target. The arguments remain
the range's location and length fields in both cases. This is a source/IDA
comparison only; no build or tests were run.
