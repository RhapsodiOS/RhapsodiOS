# Foundation NSCalendarDate formatter recheck

Read-only comparison of `-[NSCalendarDate descriptionWithCalendarFormat:locale:]`
in the Foundation-i386 IDA database with the current `NSCalendarDate.m`.

IDA locates the method at `0x42541d14`. Its directive dispatch table begins at
`0x425420ec`; the entries for `%X`, `%c`, and `%x` lead to handlers at
`0x42542afc`, `0x4254299c`, and `0x42542a40`, respectively. Each handler loads
the same locale-key reference from the PIC base at offset `0x0c1027`, sends
`objectForKey:` to the supplied locale, and uses a directive-specific fallback
when the lookup returns nil. The indirect key data reaches the constant string
`NSTimeDateFormatString` at `0x425f8a9f`. The `%x` and `%X` handlers use the
same operand; neither loads a distinct `NSShortDateFormatString` or
`NSTimeFormatString` key.

The three fallback constant-string objects resolve through PIC offsets
`0x0c6767`, `0x0c6773`, and `0x0c677f` to:

| Directive | Fallback |
| --- | --- |
| `%c` | `%a %b %d %H:%M:%S %Z %Y` |
| `%x` | `%a %b %d %Y` |
| `%X` | `%H:%M:%S %Z` |

Current source uses `%A, %B %d, %Y %H:%M:%S %Z` for `%c`, `%d %b %Y` for
`%x`, and `%H:%M:%S` for `%X`. It also looks up `NSShortDateFormatString` for
`%x` and `NSTimeFormatString` for `%X`. Thus all three fallback strings differ,
and `%x` / `%X` use different locale keys than the common target operand.

No source changes were made in this read-only pass. The bounded correction is
to use `NSTimeDateFormatString` and the recovered fallback for each of these
three formatter cases. Parser behavior is outside this note. No tests or builds
were run.

PowerPC cross-target recheck (2026-10-05): the MOSXS method is at
`0x425bb5e4`. Its `%` dispatch table is relative to the function PIC base at
`0x425e21d4`; entries for `%c`, `%x`, and `%X` branch to `0x425bbde4`,
`0x425bbe70`, and `0x425bbefc`. All three handlers load the same
`NSTimeDateFormatString` constant through `0x42626d28`. Their nil fallbacks
are constant strings at `0x4262cb04`, `0x4262cb10`, and `0x4262cb1c`, which
resolve to `%a %b %d %H:%M:%S %Z %Y`, `%a %b %d %Y`, and `%H:%M:%S %Z`.
Thus the i386 correction applies unchanged to the PPC target as well. Source
still uses the older fallbacks and the distinct `%x` / `%X` locale keys; no
source changes were made.

## Implementation update (2026-10-05)

Applied the IDA-confirmed correction in `NSCalendarDate.m` for all three
formatter directives. `%c`, `%x`, and `%X` now share the
`NSTimeDateFormatString` locale key and use the recovered i386/PPC
fallback strings above. Static source inspection only; no tests or builds
were run.

## Formatter width digit predicate (2026-10-07)

The formatter bodies use `[NSCharacterSet decimalDigitCharacterSet]` and
`characterIsMember:` while scanning the optional width after `%` on both
targets: i386 `0x42541d14` and PPC `0x425bb5e4`. `NSCalendarDate.m` had
restricted this scan to ASCII `0`–`9`. It now uses the target character-set
predicate and keeps the existing substring, `lossyCString`, and `snprintf`
flow. Static source/IDA comparison only; no tests or builds were run.

## Localized name handler follow-up (2026-10-07)

Read-only raw decoding of the i386 `%A` handler at `0x42542320` found two
`objc_msgSend` calls at `0x42542343` and `0x42542363`. The handler also reads
through `_NSWeekDayNameArray_ptr`. The handler's selector load uses PIC
displacement `0x0c6b8b`, named `paObjectforkey` in IDA and pointing to the
`objectForKey:` string at `0x4261ad99`. A separate selector reference at PIC
offset `0x0c72ab` points to `arrayByAddingObjectsFromArray:` and is not used by
these calls. IDA marks the handler bytes as data, so the source must be checked
against the raw instruction sequence rather than pseudocode.

The PPC `%A` handler at `0x425bb8f0` is disassembled as code. It obtains the
weekday index from `-dayOfWeek`, looks up `NSWeekDayNameArray` in the explicit
locale with `objectForKey:`, looks up the same key in the saved system
language context, and passes both arrays to `_appendName`. The current source
does the same for `%a`, `%B`, `%b`, and `%p`; `%p` is at `0x425bbb10`.
`NSCalendarDate.m` now passes the explicit locale array and the system-context
array separately to `appendName` on PPC, matching the target's lookup order.
The i386 handler was unresolved at the time of this initial comparison; its
selector and receiver sequence are resolved in the follow-up below. Static
source/IDA review and `git diff --check`; no tests or builds were run.

### i386 `%A` dispatch and receiver confirmation (2026-10-07)

Rechecked the dispatch calculation at the indirect jump (`0x425420e0`): the
table base is `0x425420ec`, and the `%A` entry is relative offset `0x234`,
which does target `0x42542320`. Raw decoding confirms that the first
`objectForKey:` receiver is the result of `+[NSLanguageContext
systemLanguageContext]` at `[ebp-0xa0]`; the second is the explicit locale at
`[ebp+0x14]`. The key comes from `_NSWeekDayNameArray_ptr`. The third send at
`0x42542383` uses selector `dayOfWeek`, resolved through PIC offset `0x0c7b77`
to `sel_dayOfWeek` at `0x4262307f`; its receiver is the date instance. Its
result supplies the index to the common name-selection path.

The same two-lookup sequence is present in the i386 `%a`, `%B`, `%b`, and `%p`
handlers at `0x425422b0`, `0x42542414`, `0x42542394`, and `0x42542654`, using
`_NSShortWeekDayNameArray_ptr`, `_NSMonthNameArray_ptr`,
`_NSShortMonthNameArray_ptr`, and `_NSAMPMDesignation_ptr`, respectively. The
source fallback helper now looks up the same key in the system language
context on both i386 and PPC; previously i386 fell back directly to built-in
arrays. Static raw-IDA/source review only; no tests or builds were run.

### Formatter directive dispatch coverage (2026-10-07)

Compared the full `%` dispatch tables for
`-[NSCalendarDate descriptionWithCalendarFormat:locale:]` in both IDA images.
The i386 table at `0x425420ec` and PPC table at `0x425e21d4` route the same
directives to handlers: `%`, `%A`, `%B`, `%F`, `%H`, `%I`, `%M`, `%S`, `%X`,
`%Y`, `%Z`, `%a`, `%b`, `%c`, `%d`, `%e`, `%j`, `%m`, `%p`, `%w`, `%x`, `%y`,
and `%z`. Both tables route other entries in their indexed range to the
unknown-directive path. `NSCalendarDate.m` has a case for each routed
directive. No source change was needed. Static table/source comparison only;
no tests or builds were run.
