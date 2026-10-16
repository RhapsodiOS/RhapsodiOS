# Foundation Objective-C Type Walker Reconstruction Design

## Goal

Reconstruct the exported Objective-C type-walking helpers in the i386
Foundation reference, route the existing `NSData` serialization categories
through the reconstructed walker, and restore the class-name fallback used
while decoding class encodings.

## Evidence

The reference is the DR2 i386 Foundation image with SHA-256
`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.

IDA identifies `_NSWalkData` at `0x4251db30` (2,923 bytes). Its operation
argument selects decode (`0`), encode (`1`), release (`2`), retain (`3`), or
autorelease (`4`) behavior. It walks Objective-C type encodings, including
arrays and structs, and handles object, class, selector, pointer, C-string,
scalar, and bitfield cases. The three exported wrappers at
`0x4252e978`, `0x425761a4`, and `0x425761c0` invoke operations `4`, `2`, and
`3`, respectively. The `NSData` deserializer and `NSMutableData` serializer
methods at `0x42575dfc` and `0x42575e94` call `_NSWalkData` for operations `0`
and `1`.

The current source implements those two category methods in
`NSSerialization.m` through a separate static `NSWalkObjCType` walker. The
category selectors are already represented in `NSSerialization.json`,
but the C helpers are absent from source and ABI ownership records.

The target worker signature is
`NSUInteger _NSWalkData(int operation, BOOL walkPointers, void *context,
void *value, const char *type)`. The three parse wrappers pass a null context
and set `walkPointers` to one. The typed `NSData` methods also pass one, but
the worker clears the flag for recursive array, struct, and pointee walks, so
it follows only a top-level pointer. The mode-1 context dispatches byte,
compact-integer, and C-string writes through the three entries of
`_NSDataFuncList`; these match the current source's direct byte appends,
`NSSerializerAppendFastInteger`, and `NSSerializerAppendCString`. The mode-0
context carries cursor and end pointers and dispatches the matching fast
byte/integer reads.

The archive context matches the target's i386 offsets: storage at 0, cursor at
4, end at 8, reserved word at 12, function table at 16, callback at 20, and
callback-mode byte at 24 (byte 25 is reserved). The callback-mode byte selects
the special retained/bycopy/byref object callback path. `O` and `R` qualifiers
are separate per-walk flags passed to that callback; they do not enable the
callback mode and must not persist into subsequent struct fields.

Operation 2 frees `*` string storage using the zone recovered from the
pointer; operation 3 copies the NUL-terminated string into the default zone;
operation 4 wraps its bytes in an `NSData` object. `%` remains a C-string
encoding and does not take those ownership branches. `:` is selector-valued:
decode interns its string and registers the selector name. `#`, `%`, and `:`
decoding intern directly from the checked archive cursor; `*` decoding makes
an owned NUL-terminated copy. These distinctions are confirmed in the
individual switch cases and callback table.

IDA's `_NSClassFromString` at `0x42517610` calls `-cString`, then
`objc_getClass`, and calls the zero-initialized
`__NSAltClassNameFromString` function pointer with the original string on a
miss. `_NSWalkData` also calls this pointer indirectly while decoding the `#`
type. `NSSerialization.m` currently calls `objc_getClass` for decoded class
names without the alternate-name fallback. The target function-pointer
signature is `Class (*)(NSString *)`.

## Proposed architecture

Keep the implementation in the existing `NSSerialization.m` translation unit;
do not add another source module. Implement `_NSWalkData` as the shared walker
for encode, decode, retain, release, and autorelease operations. Adapt the two
existing `NSData` category methods to construct the target-compatible context
and use that walker, replacing `NSWalkObjCType` and any helpers used only by
it. Preserve the existing property-list serializer/deserializer code in the
same file.

Define the zero-initialized `_NSAltClassNameFromString` callback pointer in
`NSObjCRuntime.m`. Use it in both `NSClassFromString` and class-type decoding.
For decoding, construct the callback's `NSString` from the decoded class
name before releasing the temporary C string. The callback is consulted only
after `objc_getClass` returns `Nil` and when the pointer is non-null.

Register `_NSWalkData` and the three operation wrappers in the
`NSSerialization` ABI, symbol, and ownership maps. Register the
callback pointer in the `NSObjCRuntime` data-symbol, symbol, and ownership
maps. Keep the existing category selector ABI records and source owners
single-counted.

## Required behavior

1. Preserve the target operation codes and returned byte-size behavior.
2. Walk arrays and aligned struct fields recursively; preserve the target's
   supported type encodings, qualifier handling, bitfield layout, top-level
   pointer traversal, and exception paths for unsupported or malformed
   encodings. Arrays advance by recursive element sizes; aligned struct fields
   advance by recursive field sizes before final alignment. `%` stays
   C-string-valued and `:` stays selector-valued.
3. For encode/decode operations, preserve the existing callback protocol,
   `NSData` cursor updates, and serialized representation while matching the
   target's category call flow through `_NSWalkData`. Select the special object
   callback path with context byte 24; keep `O`/`R` qualifier flags local to
   the current recursive walk.
4. For retain/release/autorelease operations, apply the target ownership action
   to nested Objective-C objects and its corresponding handling for C strings.
5. For `#` class decoding and `NSClassFromString`, use the alternate-name
   callback only after `objc_getClass` returns nil and only when the callback
   pointer is non-null.
6. Keep the callback pointer zero-initialized; IDA shows no Foundation-side
   writes to it.

## Scope

Expected source changes are limited to `NSSerialization.m` and
`NSObjCRuntime.m`. Update `NSSerialization.json`, `NSObjCRuntime.json`,
`symbols.json`, and `ownership.json`. Do not change public headers or unrelated
serialization/property-list behavior.

Static verification should confirm the four C function exports and one data
export are each represented once in their ABI and ownership records, and that
the category selector ownership remains unique. Runtime behavior remains
unverified until exercised in a target-compatible environment.
