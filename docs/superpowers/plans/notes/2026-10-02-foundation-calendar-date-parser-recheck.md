# Foundation NSCalendarDate parser recheck

This note records a source-to-reference recheck of the approved
`NSCalendarDate` string parser work in the DR2 i386 Foundation database
`6c2a913dc37a`.

IDA locates `-[NSCalendarDate initWithString:calendarFormat:locale:]` at
`0x42599818`. Its outer loop creates one scanner for the description and one
for the format, obtains `+[NSLanguageContext systemLanguageContext]`, skips
input whitespace, and compares literal format characters against the input.
When it sees `%`, it reads the next format character and dispatches through a
table covering `%` through `z`. Parsing fails if either scanner reaches an
incompatible end or a literal does not match. On success, the method selects
the parsed or default time zone, resolves a day-of-year value through the
Gregorian helpers, initializes the date, stores the calendar format, and adds
the parsed milliseconds. Failure deallocates `self` and returns nil.

The current source implements this work through recursive
`NSCalendarDateParseFormat` calls and locale-key lookups, while the target's
outer method performs the scanner loop and directive dispatch directly. The
dispatch table includes distinct entries for the approved `%c`, `%x`, and `%X`
expansions as well as numeric and name directives. The switch's destinations
are not defined as code items in the current IDA database, so their directive
semantics still need to be traced from their raw instruction bytes before
changing source behavior. The initial table-only pass made no source edits and
ran no tests or builds.

Reading the relative dispatch table at `0x42599aec` confirms the exact
non-default directive set: `%%`, `%A/%a`, `%B/%b`, `%c`, `%d/%e`, `%F`,
`%H/%I`, `%j`, `%m/%M`, `%p`, `%S`, `%w`, `%x/%X`, `%y/%Y`, and `%z/%Z`.
`%H` and `%I` share a target address; the others have their own table entries.
The current source's switch has the same set. The simple wrapper methods also
match: `initWithString:` calls the superclass implementation, and
`initWithString:calendarFormat:` forwards to the locale-taking initializer
with a nil locale.

Raw instruction decoding (read-only; the IDA database was not reclassified)
now confirms several handler calls:

- `%d` passes a local output address and width `2` to the shared
  `_scanDecimal:into:` call sequence.
- `%j` passes a local output address to `scanInt:`.
- `%z` also calls `scanInt:`. Its handler branches on the parsed sign and
  divides the value into base-100 quotient and remainder components before
  jumping to shared timezone handling. This is consistent with the source's
  signed `HHMM`-to-seconds conversion, though the shared conversion path still
  needs a full semantic trace.
- `%Z` obtains `+[NSCharacterSet whitespaceAndNewlineCharacterSet]`, skips
  whitespace, then calls `scanUpToCharactersFromSet:intoString:`. The source
  uses the same character set and scanner selector; its outer parse loop
  already skips input whitespace before each format directive.
- `%A` and `%B` obtain the locale arrays under `NSWeekDayNameArray` and
  `NSMonthNameArray`; `%a` and `%b` use `NSShortWeekDayNameArray` and
  `NSShortMonthNameArray`. `%c` obtains its localized expansion under
  `NSTimeDateFormatString`. These are the keys used by the source.
- The target's `-[NSScanner _scanDecimal:into:]` at `0x4259f244` matches the
  source category implementation: both scan at most the requested count of
  ASCII digits, fail without advancing when no digit is present, and only then
  store the parsed integer and advance the scan location.
- `%w` reads one character at the scanner's current location, subtracts `'0'`,
  rejects values above `6`, and advances one character. The source performs
  the same check and advance.
- `%F` and `%Y` pass widths `3` and `4`, respectively, to
  `_scanDecimal:into:`. `%p` obtains `NSAMPMDesignation` through the locale
  lookup path and scans the second name first; on a match it adds 12 when the
  hour is at most 11. If that scan fails, it scans the first name and resets
  the hour to 0 only when the hour is exactly 12. The source now applies the
  same conversion immediately while parsing `%p`.

The function prologue stores `+[NSLanguageContext systemLanguageContext]` in
the local used as the second lookup receiver. For `%A`, the handler first sends
`objectForKey:` for `NSWeekDayNameArray` to the explicit locale argument, and
when that returns nil, sends the same lookup to the system language context.
`%B` follows the same pattern with `NSMonthNameArray`; `%c` uses it with
`NSTimeDateFormatString`. The prior source ignored the explicit locale and used
only the system context's `_dictionary`. The parser now checks the supplied
locale first and falls back to the system language context for name and
localized-format lookups.

The `%c`, `%x`, and `%X` handlers all use the `NSTimeDateFormatString` key.
When lookup returns nil, their embedded constant-string defaults are,
respectively, `%a %b %d %H:%M:%S %Z %Y`, `%a %b %d %Y`, and
`%H:%M:%S %Z`. The source now uses these exact keys and fallback strings.

The remaining numeric handlers use the expected scanner operations: `%e` and
`%j` call `scanInt:`, `%d`, `%H/%I`, `%m`, `%M`, `%S`, `%y`, and `%Y` use
`_scanDecimal:into:` with widths 2 except `%Y` at width 4, and `%y` adds
`0x76c` (1900). `%F` uses width 3. The source matches these operations and
widths.

The target's finalization selects a named timezone before a numeric `%z`
offset and the default timezone, then checks the parsed month and day against
a `%j` day-of-year conversion and fills missing month and day with `1`.
Both i386 (`0x4259a3ba`–`0x4259a3d8`) and PPC (`0x425bcd54`–`0x425bcd88`)
place timezone selection before `absolute_from_year_day` and
`gregorian_from_absolute`. The method then calls
`initWithYear:month:day:hour:minute:second:timeZone:` with the parsed locals.
When the milliseconds local is nonzero it adds that value divided by `1000`
to the date's reference interval. These source paths match. The `%z` handler's
sign branches form `hours * 3600 + minutes * 60`, negating the result for a
negative input; the source's `HHMM` conversion matches that calculation.

The `%p` handler tries the second designation before the first, applies the
12-hour adjustment when that token is consumed, adds 12 only for hours at most
11, and resets to zero only for hour 12 with the first designation. The source
now follows that order and those conditions.

The final time-zone selection was checked against the raw instruction block
following the parser dispatch, since IDA's ctree omits the unrecognized jump
handlers. When a `%Z` name was parsed, the target calls
`+[NSTimeZone timeZoneWithName:]`, then tries
`+[NSTimeZone timeZoneWithAbbreviation:]` if that returns nil. With no name,
it uses `timeZoneForSecondsFromGMT:` when `%z` supplied an offset, and otherwise
uses `defaultTimeZone`. The source follows the same order.

The parser's end-of-input behavior also matches: IDA accepts once the format
scanner reaches its end and does not require the description scanner to be at
end. `NSCalendarDateParseFormat` likewise returns success when the format
scanner is exhausted, leaving trailing description text unconsumed.

The MOSXS PowerPC `%y` handler differs from the i386 handler. Its lazy global
`_doExcelLittleY` reads `NSUserDefaults` key
`NSUseExcelTwoDigitYearSemantics`; an absent key enables Excel's two-digit-year
mapping, while a present key uses its Boolean value. With the behavior enabled,
years 00–29 map to 2000–2029 and larger two-digit years map to 1900–1999. With
the behavior disabled, all values receive 1900. The DR2 i386 binary has no
reference to this preference and always adds 1900. The parser source now keeps
that target difference under the existing PowerPC compiler guards. The PPC
initializer tests the global's `-1` sentinel and caches the preference before
entering the directive loop, even when the current format has no `%y`; the
source now preserves that one-time timing. This conclusion comes from
`-[NSCalendarDate initWithString:calendarFormat:locale:]` at `0x425bc2d4`, the
`%y` handler at `0x425bc99c`, the global at `0x42626720`, and the constant key
string at `0x42622bc4`; no tests or builds were run.

The byte-level decoder reads the case blocks without changing the IDA database,
even though IDA currently marks the region as data. No discrepancy remained in
the i386 parser paths checked in that pass. The later PPC comparison found the
`%y` preference difference described above. No tests or builds were run.

## MOSXS PowerPC parser outer-flow recheck

Re-decompiled `-[NSCalendarDate initWithString:calendarFormat:locale:]` at
`0x425bc2d4` in the MOSXS PowerPC database. The outer method also creates
description and format scanners, gets the system language context, skips input
whitespace, dispatches `%` directives through a table, rejects literal
mismatches, and deallocates/returns nil on parse failure. Its success path
selects the parsed or default time zone, initializes the date, and stores the
calendar format. The table at `0x425e2344` covers `%` through `z`; its
supported directives match the i386 table. The PPC handlers confirm the same
locale lookup keys, numeric scan widths, localized format expansions, and
timezone parsing traced above, with the `%y` preference behavior as the one
confirmed difference. `NSCalendarDateParseFormat` now retains that difference
behind the PPC compiler guards. The PPC read was static; no tests or builds
were run.

## Name-token scanner case-sensitivity recheck (2026-10-08)

The `%A/%a/%B/%b` handler paths call `scanString:intoString:` for each
localized name and do not send `setCaseSensitive:`. The paired concrete
scanner initializers (i386 `0x425364c4`, PPC `0x4255783c`) initialize the
string, default skip set, and scan location without writing the case-sensitive
flag. `NSScanner` allocation uses zero-initialized object storage, so the
flag remains false, matching the parser helper's `setCaseSensitive:NO` before
name matching. The source setting is redundant but does not diverge from the
target. Static paired IDA/source review only; no tests or builds were run.
