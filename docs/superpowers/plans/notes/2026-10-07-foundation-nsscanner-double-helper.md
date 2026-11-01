# Foundation `_NSScanDoubleFromString` paired IDA recheck (2026-10-07)

Rechecked `_NSScanDoubleFromString` in DR2 i386 (`0x4252c568`) and MOSXS PPC
(`0x4252b948`) against `NSScanner.m`. The existing source matched the bounded
32-character input cursor, skip-set pass, `__NSNumberSet` token filter, locale
decimal-separator substitution, lazy 64-byte local / 128-byte growth buffer,
parser end-pointer cursor update, and architecture-specific `strtod` helper.

Two defensive source checks did not match either target. Both target functions
use `characterAtIndex:0` whenever the locale lookup returns a nonnil decimal
separator, without first checking its length. Both also write through the
result pointer unconditionally after a successful conversion. The source now
follows those branches; a nil locale value still leaves the default `.`
separator. The scanner wrappers' successful `scanDouble:` path therefore
retains the target's nonnull output-pointer assumption.

Static source and whitespace checks only; no tests or builds were run.
