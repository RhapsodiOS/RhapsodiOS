# Foundation `_NSStandardizePath` Reconstruction Design

## Goal

Reconstruct the i386 Foundation `_NSStandardizePath` helper and make the four
confirmed callers use it, matching the target's in-place UTF-16 path behavior.

## Evidence

The target is the DR2 i386 Foundation image identified in the repository as
SHA-256 `1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.
IDA locates `_NSStandardizePath` at `0x425179bc`. The existing analysis in
`docs/superpowers/plans/notes/2026-10-04-foundation-c-symbol-coverage.md`
records its algorithm and callers at `0x4253108c`, `0x42532b10`,
`0x42541a1c`, and `0x42545148`.

Raw i386 disassembly of the target function spans `0x425179bc–0x42517f47`
(1,419 bytes; SHA-256
`6774770c0423c2dec7203770f91819fc3796b2d6e1ac2ac0d5753bf885be8501`). The
entry reads arguments at `[ebp+8]`, `[ebp+0xc]`, and `[ebp+0x10]`; it treats
them as the UTF-16 buffer, in/out length pointer, and integer capacity. The
early capacity-failure path returns the saved initial-change byte, while the
normal epilogue returns integer `1`. This pins the C interface as:

```c
int _NSStandardizePath(unichar *characters, unsigned *length, int capacity);
```

Raw disassembly of all four callers confirms each passes capacity `0x400`.
Generic `NSString` callers use 1,024-unit stack buffers and clamp the copied
length. `NSPathStore2` callers copy at most 1,024 units but retain the full
length; the reconstruction instead uses a full-length dynamic workspace for
those two callers, following the saved NSPathStore2 analysis that explicitly
rejects reproducing the reference's out-of-bounds hazard. Both resolving callers call
`_NSResolveSymlinksInPath` immediately before `_NSStandardizePath`; both
standardizing callers omit the symlink call. The Objective-C message calls
after normalization all invoke `+[NSPathStore2 pathStoreWithCharacters:length:]`
with the resulting buffer and length.

The helper mutates a UTF-16 buffer and its length, accepts a capacity, and
returns `1` on the normal path even when normalization makes no change. If an
eligible `..` resolution produces a length beyond capacity, it keeps the
initial slash-transmutation/trailing-slash result and returns that initial
change flag. `_pathHasDotDot` enables filesystem resolution only for absolute
paths beginning with `/` or `~`, and only for complete `..` components.

## Required behavior

1. Transmute slash forms and strip trailing slashes, retaining the change flag
   used by the early capacity-failure return.
2. For eligible absolute paths containing a complete `..` component, resolve
   symlinks on a temporary path with capacity 1,024. Copy the resolved path
   into the caller buffer only when its length fits the caller's capacity.
3. Trim terminal `/.`, remove leading `./` components for non-UNC paths,
   collapse `/./`, and reduce `/../` without crossing the root. Preserve the
   UNC server/share prefix for the decompiled reduction path.
4. Transmute and trim slashes again. Strip a leading `/private/` only when
   the remaining path exists according to the Foundation file-existence
   helper.
5. Return `1` after normal completion, including a no-op normalization.

## Caller behavior

All four target callers expand a leading tilde and return a
`+[NSPathStore2 pathStoreWithCharacters:length:]` result. The resolving
callers first invoke `_NSResolveSymlinksInPath`; all then invoke
`_NSStandardizePath`. This also applies to the generic `NSString` methods,
whose current object-array and UTF-8 `realpath` paths should be replaced by
the target buffer path. Generic callers clamp their copied input length to
1,024 UTF-16 units; preserve the exact NSPathStore2 length handling shown in
its two call sites rather than imposing the generic caller's clamp on it.

## Scope and verification

Changes are limited to `NSPathUtilities.m` and its ABI, source-symbol, and
ownership records. Do not refactor unrelated path helpers. The active session
has a no-tests/no-builds constraint; verify source and manifest consistency,
`git diff --check`, the exact-profile C-symbol audit, and the exact-profile
selector audit. Runtime behavior remains unverified until a target-compatible
test environment is available.
