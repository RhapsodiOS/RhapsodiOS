# NSLanguageContext reconstruction

IDA database: Foundation i386, instance `d12fe2f23883`.

Reconstructed the class and instance selectors listed in
`src/Kits/Foundation/reconstruction/abi/NSLanguageContext.json`. The class
methods manage the language dictionary cache and default/system contexts.
Language files are searched under the Foundation `Resources/Languages`
directory, with readable `.splist` files preferred. Their dictionaries are
loaded through `NSDeserializer` or the mutable dictionary file loader, then
merged with parent contexts named by `NSParentContext`.

The IDA trace showed `__NSLanguageContextLock` is a recursive lock created in
`_NSToDoAtFirstThreadStart`; `NSThread.m` now initializes the reconstructed
global at that hook. IDA also showed the lock is released in
`_NSToDoAtLastThreadExit`, but the current source has no matching exit hook to
wire up. That lifecycle path remains unimplemented.

`NSLanguages` is the defaults key used to choose the first available preferred
language context. `English` wraps `_NSDefaultEnglishLanguageDict()`.

Static selector audit after the change reports 2692 source definitions and 697
missing target selectors (down from 2667 and 722); it reports no duplicate or
renamed selectors. Behavioral tests and builds were not run.

## Thread-lock teardown recheck (2026-10-06)

The earlier statement that the exit hook was absent is superseded. The current
`NSThread.m` releases and clears `__NSLanguageContextLock` in
`_NSToDoAtLastThreadExit`; both the i386 target at `0x42571898` and PPC target
at `0x4257fdfc` do the same. No additional lifecycle code was needed for
`NSLanguageContext`.

## Resource-root helper call path (2026-10-07)

Both i386 `+[NSLanguageContext languageContextWithName:]` at `0x42549000`
and PPC at `0x4253f9c8` call `_NSFoundationResourceDirectory()` before
appending `Languages` and the requested context name. Both target helper
implementations return the Foundation resource-root constant.
`NSLanguageContext.m` had duplicated that literal through a local helper; it
now calls the shared exported helper for context lookup, installed-name
enumeration, and parent-context fallback. The path value is unchanged, and
the source follows the target call path. No ABI metadata changed. No tests or
builds were run.

## Installed language-name array ownership (2026-10-08)

Both i386 `+[NSLanguageContext allTheLanguageContextNamesInstalledOnTheSystem]`
(`0x42564ba0`) and PPC (`0x4256f4b4`) make a mutable copy of the directory
contents, remove `.splist`, `.`, and `..` entries, then return that same
object directly. The i386 epilogue returns the local array pointer in EAX; the
PPC epilogue moves it to r3 and returns. Neither body autoreleases it. The
current source autoreleased the copied array, so its ownership differed from
both targets. `NSLanguageContext.m` now returns the mutable copy directly
after filtering, preserving the +1 ownership from `mutableCopyWithZone:`. No
ABI metadata changed. Static paired IDA/source review only; no tests or builds
were run.

## Neighboring cache and context methods (2026-10-08)

Rechecked `_langList`, `availableLanguageContextNames`,
`defaultLanguageContext`, `setDefaultLanguageContext:`,
`setSystemLanguageContext:`, `systemLanguageContext`, `copyWithZone:`, and
`mutableCopyWithZone:` in the i386 database (functions at `0x42564b0c`,
`0x42564cc8`, `0x42564d10`, `0x42564e38`, `0x42564ec0`, `0x4254a53c`,
`0x42565080`, and `0x42565258`) and the PPC database (`0x4256f400`,
`0x4256f5e8`, `0x4256f648`, `0x4256f794`, `0x4256f838`, `0x4256f8dc`,
`0x4256fb48`, and `0x4256fdf8`). The cache accessors, preferred-language
fallback, retained global setters, and copy behavior match the current source.
The lock calls differ with the target ABI but remain paired around the same
state accesses. No further source change was indicated. Static paired
IDA/source review only; no tests or builds were run.
