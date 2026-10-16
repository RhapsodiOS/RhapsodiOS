# Foundation `NSMethodSignature` cache reconstruction correction

Reference: Foundation i386 IDA database `d12fe2f23883`.

`+[NSMethodSignature signatureWithObjCTypes:]` at `0x42520c88` uses
`_NSMethodSignatureTable` as a lazily created `NSMapTable`. It scrunches the
encoding into a 512-byte stack buffer (default-zone allocation when the
NUL-inclusive length exceeds 511), looks up under `_NSMethodSignatureTableLock`,
allocates the signature on a miss, inserts it under a second lock section, and
then fills the argument records. The map has capacity `0x28`, uses
`_hashStr`/`_equalStr` key callbacks and `NSObjectMapValueCallBacks`, and stores
the signature's inline normalized type string as the key.

`scrunch` at `0x42518498` copies each token using
`_NSGetSizeAndAlignment`, strips its following decimal or negative frame
offset, and returns the argument count excluding the return type. `_hashStr`
at `0x4251c390` ignores named structure tags while hashing;
`_equalStr` at `0x42521560` delegates to `_structurallyEqual` at `0x4251a380`,
which treats `?` structure names as wildcards. The new source callbacks and
normalizer preserve those rules.

`__NSToDoAtFirstThreadStart` at `0x42554f31` initializes
`_NSMethodSignatureTableLock` as an `NSLock` if it is nil. The previous source
used a linear pointer array and a local spin word; those were not supported by
the constructor's IDA pseudocode. The separate exported `__NSFastBSearchInt`
has no xrefs to its function and is not used by this cache path.

Static source, manifest, and whitespace checks only; no tests or builds were
run.

## Unsigned argument-index bounds (2026-10-07)

The i386 `getArgumentTypeAtIndex:` body at `0x42574648` enters its success
branch when `_nargs > idx`; PPC at `0x42584aec` uses `idx < _nargs`. Both
`_argumentInfoAtIndex:` bodies also reject an unsigned index at or above
`_nargs` (i386 `0x425744c0`, PPC `0x42584900`). The source had cast each
unsigned index to `int` before comparing. For values above `INT_MAX`, that
could turn an invalid index into a negative value and skip the check. Both
accessors now compare the unsigned index directly with the nonnegative
argument count. Static IDA/source review and `git diff --check` only; no tests
or builds were run.

## Return-struct register classification by architecture (2026-10-07)

The i386 `-[NSMethodSignature _isReturnStructInRegisters]` body at
`0x42574520` returns `YES` only when the return encoding starts with `{` and
the byte size is 1, 2, 4, or 8. Union `(` returns and other sizes return
`NO`. PPC at `0x425849ac` always returns `NO`. The shared source had treated
small unions as register returns and applied the i386 rule on PPC. It now
keeps the small-struct rule under the i386 branch and returns `NO` on PPC.
Static paired IDA/source review and `git diff --check` only; no tests or builds
were run.

## Interned type-string accessors (2026-10-07)

Both targets' `getArgumentTypeAtIndex:` bodies (i386 `0x42574648`, PPC
`0x42584aec`) copy the consumed type token to stack scratch and return
`_NSUniqueCString` of that token. Both `methodReturnType` bodies (i386
`0x425746e8`, PPC `0x42584be4`) do the same for the return token. The shared
helper at i386 `0x42538dec` and PPC `0x4252ddb8` interns strings in a
process-wide hash table and returns a stable shared pointer. The source
accessors previously returned separately allocated copies. They now use a
shared helper with four-byte i386 or sixteen-byte PPC stack alignment and
return the interned string. A source-wide callsite search found no caller
that frees these accessor results; remaining `NSZoneFree(type, ...)` calls
belong to separately decoded coder-owned type strings. Static paired IDA/source review and
`git diff --check` only; no tests or builds were run.
