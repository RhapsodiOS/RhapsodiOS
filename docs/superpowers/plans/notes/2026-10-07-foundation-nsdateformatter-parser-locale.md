# `NSDateFormatter` parser locale call (2026-10-07)

Compared `-[NSDateFormatter getObjectValue:forString:errorDescription:]` in
both IDA targets:

- DR2 i386 `0x42589f28` sends `dateWithString:calendarFormat:locale:` to
  `NSCalendarDate`, passing the string, `_format`, and the user-defaults
  dictionary representation.
- MOSXS PPC `0x425a1d7c` sends `dateWithString:calendarFormat:` to
  `NSCalendarDate`, passing only the string and `_format`.

Both targets use the user-defaults dictionary representation for the
natural-language fallback when `_naturalLanguage` is enabled. The current
`NSDateFormatter.m` source passes the locale to the calendar-format parser on
both targets, so its PPC parser call differs from IDA. The proposed source
correction is an architecture-specific selector split, with the locale
argument retained for i386 parsing and for natural-language fallback on both
targets. This source change was approved and applied in `NSDateFormatter.m`.

The adjacent `dateFormat`, `allowsNaturalLanguage`, `encodeWithCoder:`, and
`dealloc` methods were also compared: i386 `0x42589e70`, `0x42589e60`,
`0x42589ecc`, and `0x42589e80`; PPC `0x425a1c98`, `0x425a1c84`, `0x425a1d08`,
and `0x425a1ca8`. Their source access, coding, and release/super-call paths
match both targets.

## Approved source correction

`getObjectValue:forString:errorDescription:` now sends the two-argument
calendar-format selector on PPC and retains the locale-taking selector on
i386. The natural-language fallback continues to receive the locale on both
targets. This follows the paired IDA call sites above; no ABI changed. Static
diff and whitespace checks only; no tests or builds were run.

## Paired current-source recheck (2026-10-08)

Re-decompiled the i386 method at `0x42589f28` and PPC method at
`0x425a1d7c`. The i386 target passes the user-defaults dictionary to
`dateWithString:calendarFormat:locale:`; PPC passes only the string and
`_format`. Both targets keep the dictionary for the
`dateWithNaturalLanguageString:locale:` fallback, catch parsing exceptions,
write nil for an empty input when an output pointer is supplied, and localize
the failure description only when its output pointer is nonnull. The current
`NSDateFormatter.m` matches those branches and target-specific selector calls.

Also rechecked `initWithCoder:` at i386 `0x42557c04` and PPC `0x425a1f28`.
Both request the class version, call `NSFormatter -initWithCoder:`, decode
`@c` for versions above 40, and use the legacy object-plus-optional-char path
for earlier versions. Source coding and ownership order match both targets.
Static paired IDA/source review only; no tests or builds were run.
