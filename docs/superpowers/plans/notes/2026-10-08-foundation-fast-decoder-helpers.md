# Foundation fast decoder helpers (2026-10-08)

Reconstructed the compact integer, raw-span, and C-string helpers in
`NSSerialization.m` against the i386 and PPC IDA functions: `_decodeFastInt`
(`0x42517540` / `0x42510b70`), `_decodeFastData`
(`0x42521620` / `0x425200c8`), and `_decodeFastCharStar`
(`0x42524898` / `0x42526ee0`). The existing `decodeFastByte` helper remains
the presence-byte reader.

`decodeFastInt` checks the signed marker and encoded span with the target's
address-addition rules, raises the two distinct internal-inconsistency errors
for truncated input, raises `NSRangeException` when the payload exceeds the
destination width, then sign-extends and copies bytes in target order: i386
low address first, PPC high address first. `decodeFastCharStar` returns nil
for an absent value; otherwise it decodes a four-byte length and returns the
payload start after the target bounds check. `decodeFastData` advances and
returns the start of a raw span with the target data-bounds exception.

The `_NSWalkData` source readers now share `decodeFastByte`, `decodeFastInt`,
and `decodeFastCharStar` instead of carrying a second copy of those decode
paths. IDA reports `_decodeFastData` with no direct callers in either image;
it remains a file-local helper and adds no export or ABI record. Static
source/IDA comparison and `git diff --check` only; no tests or builds were run.
