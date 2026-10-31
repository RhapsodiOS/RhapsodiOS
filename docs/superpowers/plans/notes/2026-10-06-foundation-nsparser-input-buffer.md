# NSParser encoded input buffer parity (2026-10-06)

Rechecked `-[NSParser setString:]` and `-[NSParser nextToken]` in both target
databases before implementing the approved input-buffer design:

- i386 `Foundation-i386`: `setString:` at `0x42532bac`, `nextToken` at
  `0x4250bf98`.
- PPC `Foundation`: `setString:` at `0x42531158`, `nextToken` at
  `0x42505504`.

Both targets select the default C-string encoding as the narrow input path,
copy its encoded bytes into a zone-owned buffer, and otherwise copy UTF-16 code
units. Token positions therefore count bytes for narrow input and code units
for wide input. Narrow token scanning reads bytes directly; quoted high bytes
are decoded with `NSNextEUCToUnicode` for the default Japanese EUC encoding,
then fall back to `NSNEXTSTEPToPrecompUnicode`. The EUC decoder receives the
remaining byte count and its consumed-byte result advances the source cursor.
Both implementations free the prior input buffer when resetting and free the
current buffer at teardown.

`NSParser.m` now follows that storage and decoding split without changing the
ABI ivars. Static source review confirmed both encoding paths, quoted-byte
conversion, zone-based input allocation/free, and cursor advancement. The
source-level selector inventory remains covered by the existing NSParser plan.
`git diff --check` passes for `NSParser.m` and this note. No tests or build were
run; object-level ABI comparison remains unverified because it requires a
Foundation build.

## `setString:` state reset recheck (2026-10-07)

The paired `setString:` bodies reset `_inputPos`, `_inputLine`, and
`_tokenBufferReady` after replacing the input buffer, then drain the parse stack
and interned strings. They do not reset `_tokenInputPos` or `_tokenCount`.
Removed the two source-only resets so the input replacement transition matches
both IDA targets. This is a static source/decompilation comparison; no tests or
builds were run.

## End-of-input cursor advancement (2026-10-07)

Both `-[NSParser nextToken]` bodies increment `_inputPos` immediately after
reading a character, including the NUL sentinel at `_inputLength`. The source
buffer allocates a terminator in both byte and UTF-16 modes, but
`NSParserCharacterAt` previously left the cursor unchanged for every position
at or past `_inputLength`. It now advances the cursor on a read at end-of-input
while still returning zero without reading beyond the allocated input. Static
paired IDA/source review and whitespace check only; no tests or builds were
run.

## Parser source ivar layout audit (2026-10-07)

Reparsed `reconstruction/abi/NSParser.json` and compared its ivar order with
the current source declarations. `NSParser`'s 20 ivars match in order and its
manifest instance size is 72 bytes; `_NSParserSyntaxNode`'s three ivars match
and its instance size is 16 bytes. `NSPropertyListParser` and
`_NSPListParserOldStyle` add no ivars and retain the 72-byte inherited size.
This is a source/manifest layout check only; compiled object ABI comparison
still requires a Foundation build. No tests or builds were run.

## Continuation-character fallback (2026-10-07)

Both `-[NSParser nextToken]` bodies (i386 `0x4250bf98`, PPC `0x42505504`)
fall through to the buffered token path when the first character is not in the
unquoted-start set. If that character is in the continuation set, they build
an unquoted token from it and following continuation characters. In the slow
path for an unquoted-start character followed by a high byte, the targets also
check the first character's continuation bit; when it is clear, they try a
multiple separator and otherwise return that first character as separator or
other without consuming the following character. `NSParser.m` now follows
these transitions. Static paired IDA/source review and whitespace check only;
no tests or builds were run.

## `setString:` encoding and length call order (2026-10-07)

The paired bodies free the previous input before asking for `fastestEncoding`.
For narrow input they obtain `cStringLength`, allocate the byte buffer, then
resolve the default encoding and string length for `getBytes:`. For UTF-16
input they get the string length before allocating the character buffer.
`NSParser.m` now follows those branch-specific calls and order. Static paired
IDA/source comparison only; no tests or builds were run.

## NUL termination inside quoted input (2026-10-07)

Both `nextToken` bodies (i386 `0x4250bf98`, PPC `0x42505504`) raise
`Unterminated quoted string` when the next raw input code unit is zero, even
before the closing quote. The source previously appended that zero and kept
scanning. It now reads through the NUL sentinel and raises there; the
backslash escape path still appends an escaped zero as the target does. Static
paired IDA/source review only; no tests or builds were run.

## Syntax-node class dispatch (2026-10-07)

`-[NSParser parse:]` compares the grammar value's `isa` directly with the
syntax-node class in both targets (i386 `0x42506b24`, PPC `0x42503fd4`). The
PPC `parseForSyntaxNode` body repeats that exact comparison for each child
before choosing recursive syntax parsing or `parse:`. Replaced the source's
`isKindOfClass:` checks with direct class-pointer comparisons in those two
dispatch sites. Static paired IDA/source comparison only; no tests or builds
were run.

## Line-comment newline accounting (2026-10-07)

The paired `nextToken` bodies (DR2 i386 `0x4250bf98`, MOSXS PPC
`0x42505504`) increment `_inputLine` when the `//` scan reaches a newline,
leave that newline at the cursor, and return to the outer scan, which consumes
and counts it again. `NSParser.m` now preserves this double increment. A
line-comment reaching end-of-input without a newline does not take that extra
increment. Static paired IDA/source review only; no tests or builds were run.

## Quoted escape decoding (2026-10-07)

MOSXS PPC `_getSlashedChar` (`0x42529088`) handles `\\U` followed by up to
four ASCII hexadecimal digits, limits octal escapes to three digits total, and
returns a literal escaped newline after incrementing `_inputLine`. Its caller
appends the returned code unit, including zero. The i386 helper
(`0x425393d0`) uses a computed switch and its caller follows the same append
path. `NSParser.m` now implements these escape widths and retains escaped
newline/zero code units instead of dropping them. Static IDA/source review
only; no tests or builds were run.

## Meta-grammar leaf precedence (2026-10-07)

The DR2 i386 parseMetaSyntaxLeafResultShouldBeSkipped: disassembly
(0x4253b054) tries parseTokenWithMask:4 before mask 2; MOSXS PPC
(0x4255456c) has the same order. The source now attempts unquoted rule names
before quoted literal strings, matching both targets. Static IDA/source review
only; no tests or builds were run.

## Syntax-node and meta-grammar parity (2026-10-07)

PPC parseForSyntaxNode (0x4250e508) confirms type 0 literal matching, type 1
sequence selection/array results, type 2 ordered alternatives, type 3
backtracking alternatives with token-head restoration and exception handling,
and type 4 one-or-more repetition. The paired meta-grammar bodies use raw
unquoted rule names, type-0 quoted literals, parenthesized type-4 groups, and
single-pipe versus double-pipe choice nodes. NSParser.m now follows these node
shapes and failure paths; its previous mapping treated type 3 as repetition
and used type 4 for unquoted rule names. Static IDA/source review only; no
tests or builds were run.

## Token-buffer string construction parity (2026-10-07)

Both `_makeNewString` bodies pass sentinel-position ASCII and UTF-16 token
buffers directly to `_NSNewInlineCString` and `_NSNewInlineUnicodeString`
(i386 `0x42507b00`/`0x42503b7c`, PPC `0x4250413c`/`0x42507ee8`). The paired
constructors copy into inline string storage up to 65535 characters and use
their own large-string path above that length. `NSParserStringFromToken` now
passes its token buffer directly to these helpers instead of making an extra
512-character stack/heap copy and adopting that allocation as no-copy string
storage. Static paired IDA/source review only; no tests or builds were run.

## Separator comparison path (2026-10-07)

The paired `parseSeparatorEqualTo:` bodies (i386 `0x4250b990`, PPC
`0x42504388`) compare the token directly with the separator's C-string bytes.
They first require a separator token, equal token/byte lengths, and an ASCII
token, then compare against the token buffer, UTF-16 input, or narrow input
according to the stored input path. `NSParser.m` now follows these branches
and consumes the token only after a match, instead of creating an NSString and
calling `isEqual:`. Static paired IDA/source review only; no tests or builds
were run.

## Parsed-token equality and interned return value (2026-10-07)

Both `parseTokenEqualTo:mask:` bodies (i386 `0x4256c6ec`, PPC `0x425797f4`)
check the token mask and, for ASCII tokens, compare the token length with the
expected string length. They ensure the expected string has a zone-owned copy
in `_allStrings`, materialize the current token, compare with
`isEqualToString:`, and return the original expected string on a match.
`NSParser.m` now follows this behavior instead of returning the materialized
token after `isEqual:`. Static paired IDA/source review only; no tests or builds
were run.

## Data literal hex decoding (2026-10-07)

Paired IDA bodies for `-[NSParser parseData]` (i386 `0x4251680c`, PPC
`0x4250f064`) set the mutable data length for each parsed hex token, then fill
the new range through `mutableBytes`. Odd-length tokens raise
`Data representation should always contain an even number of hex digits: '%@'`.
The paired `_fromHexDigit` helpers (i386 `0x42572090`, PPC `0x42550220`) use
digit classification and locale lowercase mapping, raising `Incorrect hex
digit: %c` for invalid input. `NSParser.m` now matches the messages,
conversion rules, and set-length/direct-fill sequence. Both parsers allocate
with `allocWithZone:`, call plain `init`, and autorelease only after requiring
the closing `>`. `NSParser.m` now follows that allocation and ownership path.
Static paired IDA/source review only; no tests or builds were run.

## Generic dictionary pair suite (2026-10-07)

The paired `parseSuiteOfPairsKey:separator:value:separator:allowOmitLastSeparator:`
bodies (i386 `0x4251d420`, PPC `0x4252be8c`) initialize the temporary mutable
dictionary with capacity 32. PPC additionally installs an exception handler
that releases this dictionary before re-raising; i386 has no corresponding
cleanup handler. `NSParser.m` now matches the capacity on both targets and
uses a PPC-only `NS_DURING` cleanup path. Static paired IDA/source review only;
no tests or builds were run.

## Generic suite object storage (2026-10-07)

Both `parseSuite:separator:allowOmitLastSeparator:` bodies (i386
`0x42523e30`, PPC `0x4252ce18`) collect up to 128 object pointers in a stack
buffer, then double capacity with zone allocation/reallocation as needed. They
initialize the result with `initWithObjects:count:`, free grown storage, and
autorelease the array. `NSParser.m` now follows that buffer and ownership path
instead of building a temporary mutable array. Static paired IDA/source review
only; no tests or builds were run.

## Parse-error context (2026-10-07)

Paired parseError: bodies (i386 0x4253ecfc, PPC 0x42579644) format the
reason, line, position, active parse-rule stack, and next token into the
NSParseErrorException. They allocate the reason in the parser zone and
autorelease it; when no token is buffered, the context uses the shared empty
string. NSParser.m now follows this message and context path. Static paired
IDA/source review only; no tests or builds were run.

## Expect-wrapper diagnostics (2026-10-07)

Both targets' expect: body appends a copy of the failed rule to the parse
stack before raising with "%@ expected". The token and separator wrappers
raise "Token '%@' expected" and "Separator '%@' expected"; end-of-input uses
"End of input expected". NSParser.m now preserves the failed rule in the
diagnostic stack and matches these messages. Static paired IDA/source review
only; no tests or builds were run.

## Built-in grammar parser parity (2026-10-07)

Paired `+[NSParser parsedGrammarForString:]` bodies install the `Token`,
`MetaSyntaxSequence`, and `MetaRuleBody` productions, configure `||` as a
multi-character separator, then parse `Token = MetaRuleBody;` pairs through
`parseSuiteOfPairsKey:separator:value:separator:allowOmitLastSeparator:`.
`parseMetaSyntaxLeaf` uses `<...>` for type-4 groups. `NSParser.m` now follows
these grammar rules, separators, and delimiters. Static paired IDA/source
review only; no tests or builds were run.

## Dynamic token-buffer representation (2026-10-07)

Paired IDA helpers `_growBuffer` (i386 `0x425222bc`, PPC `0x4251b6e0`),
`_makeBufferWide` (i386 `0x425455e8`, PPC `0x4253e2a0`), and
`_makeNewString` (i386 `0x42514084`, PPC `0x42509710`) use an initially empty
token buffer, byte storage while ASCII, geometric growth (`2 * max + 1`), and
an in-place or allocated conversion to UTF-16 when needed. `NSParser.m` now
follows that dynamic capacity and representation behavior, widens ASCII bytes
back to UTF-16 in reverse order, resets capacity units between tokens, and
compares buffered ASCII separators as bytes. Backtracking snapshots now save
and restore token bytes with their encoding mode only when a ready token uses
the sentinel input position. Numeric and ASCII unquoted direct-input slices
are recorded in the following reconstruction entry. Static paired IDA/source
review only; no tests or builds were run.

## Direct-input token strings (2026-10-07)

Paired `-[NSParser nextToken]` bodies (i386 `0x4250bf98`, PPC `0x42505504`)
leave `_tokenInputPos` at the sentinel for quoted and synthesized tokens, but
set it to the input start and store only the length for numeric and unquoted
tokens. Paired `_makeNewString` bodies (i386 `0x42514084`, PPC `0x42509710`)
then use the input slice directly when its representation matches the token;
they convert UTF-16 input to ASCII bytes or ASCII input to UTF-16 in a stack
buffer for lengths up to 512, and use zone-owned no-copy NSString storage for
longer converted strings. Sentinel-position tokens are materialized from the
dynamic token buffer. Paired `_pushTokenHead`/`_popTokenHead` bodies (i386
`0x4257237c`/`0x425722ec`, PPC `0x425813cc`/`0x425812f0`) snapshot and restore
token-buffer bytes only when a token is ready and its input position is the
sentinel. `NSParser.m` now records direct slices for numeric and ASCII
unquoted tokens, uses representation-aware `NSParserStringFromToken` paths,
and snapshots buffer bytes only for buffered tokens. For unquoted tokens,
continuation characters above ASCII take the token-buffer path, as in IDA;
ordinary ASCII continuations remain direct input slices. Static paired
IDA/source review only; no tests or builds were run.

`NSParserStringFromToken` now follows the paired representation branches:
matching-width input slices go directly to the inline constructor; wide input
for ASCII tokens is narrowed, and ASCII input for wide tokens is widened, in
512-element stack buffers or zone allocations. Converted tokens above 512
elements use `initWithCStringNoCopy:` or `initWithCharactersNoCopy:` with
ownership transfer. The intern-table lookup and insertion remain after string
construction, matching `_makeNewString`.

## Approved implementation follow-up (2026-10-07)

Rechecked `setString:` and `nextToken` at the same paired i386/PPC addresses.
The source retains the IDA-confirmed zone-owned byte or UTF-16 input buffer,
byte-oriented narrow cursor, quoted-byte EUC/NEXTSTEP conversion, and consumed
byte cursor update. Static ABI ownership comparison finds all 47 manifest
selectors exactly once. Removed a duplicate source definition of
`NSParserAutoreleaseAllStrings`; the helper now has one definition. No tests or
builds were run, and object-level ABI comparison remains unverified.

## Grammar lookup ordering (2026-10-07)

Paired `-[NSParser parse:]` bodies (i386 `0x42506b24`, PPC `0x42503fd4`)
grow the parse stack when count is greater than or equal to capacity, push a
copy of the rule, and only then query `_grammar` with `objectForKey:`. They
check the returned production for nil before reading its `isa`. The source
previously queried the grammar first, grew only on exact equality, and read
`production->isa` before the nil check. `NSParser.m` now follows the target
capacity predicate, lookup order, and nil guard. Static paired IDA/source
review and whitespace check only; no tests or builds were run.

## Default unquoted grammar characters (2026-10-07)

Paired `-[NSParser initWithGrammar:]` bodies (i386 `0x425313d4`, PPC
`0x425306c4`) pass the constant string `_$/:.` to both unquoted-character
setters with lowercase, uppercase, and digit flags enabled. The source
previously populated only ASCII letters and digits directly, omitting those
five punctuation characters. It now calls the same setters with the confirmed
string and applies the target separator and quoting defaults in order. Static
IDA/source review and whitespace check only; no tests or builds were run.

## Multiple-separator length staging (2026-10-07)

Both `-[NSParser setMultipleCharacterSeparators:]` bodies (i386
`0x4254df08`, PPC `0x42556b20`) sort separators, allocate a default-zone
`unsigned` length array, validate and store lengths in reverse order, then
allocate and populate the parser-zone byte buffer using those saved lengths.
They free the temporary array after the packed buffer is complete. The source
previously queried each length twice and skipped the temporary allocation. It
now follows the target allocation, query, copy, and cleanup sequence. Static
paired IDA/source review and whitespace check only; no tests or builds were
run.

## Tokenization-setter byte semantics (2026-10-07)

Paired IDA bodies for `setMonoCharacterSeparatorCharacters:usualPunctuation:`
(i386 `0x4250928c`, PPC `0x425307b4`),
`setUnquotedStringStartCharacters:lowerCaseLetters:upperCaseLetters:digits:`
(i386 `0x4252dac8`, PPC `0x42530a60`), and
`setUnquotedStringCharacters:lowerCaseLetters:upperCaseLetters:digits:`
(i386 `0x4252dbb8`, PPC `0x425302c4`) call `cString` and set bits for its
nonzero bytes. The source previously iterated UTF-16 characters and rejected
values above 255. It now consumes the C-string bytes and keeps the target's
punctuation, letter, and digit ordering. Static paired IDA/source review and
whitespace check only; no tests or builds were run.

## Property-list autorelease-pool path (2026-10-07)

Both target `NSString` property-list category methods (i386
`propertyList` `0x42535974`, strings-file parser `0x4253ada4`; PPC
`propertyList` `0x4253ddd0`, strings-file parser `0x42535474`) push a pool
with `_NSPushAutoreleasePool` and pop its token with `_NSPopAutoreleasePool`.
The source previously allocated an `NSAutoreleasePool` object and released it,
which enables the pool's subclass-routing path. The category methods now use
the existing C helpers and retain the target's parser/result/exception cleanup
order. Static paired IDA/source review and whitespace check only; no tests or
builds were run.

## Block-comment scanner transitions (2026-10-07)

Both `-[NSParser nextToken]` bodies (i386 `0x4250bf98`, PPC `0x42505504`)
consume one lookahead after every `*` inside a block comment. A newline in
that lookahead increments `_inputLine` again; `/` closes the comment and
restarts the outer whitespace/comment scan; `*` backs the cursor up one unit
to preserve overlapping `**` candidates. End-of-input in a block comment
returns the end token. The source previously checked only for `*/`, missed
the extra newline accounting and overlap behavior, and continued scanning
after unterminated comments. `NSParser.m` now follows those transitions.
Static paired IDA/source review and whitespace check only; no tests or builds
were run.

## Numeric exponent marker locale mapping (2026-10-07)

In the ASCII-input branch of `-[NSParser nextToken]`, IDA checks the active
rune locale's lowercase mapping against `e` before accepting an exponent; the
UTF-16 branch checks for `e` or `E` directly. The source previously used the
direct two-character check for both input forms. It now uses `tolower` on the
unsigned input byte for ASCII and retains the direct UTF-16 check. Static
paired IDA/source review and whitespace check only; no tests or builds were
run.
