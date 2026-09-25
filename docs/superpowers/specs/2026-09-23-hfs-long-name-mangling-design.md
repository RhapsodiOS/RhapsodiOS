# Mangling HFS Plus names too long for a 255-byte UTF-8 name

## Goal

An HFS Plus name can be up to 255 UTF-16 units. In UTF-8 that can be as long as
765 bytes, but a BSD name is at most `NAME_MAX` (255) bytes. Today such a name
breaks the directory it lives in:

- `hfs_readdir` and `hfs_readdirattr` stop with an error when they reach it,
  because `IterateCatalogNode` returns the conversion error. Every entry after
  it is unlistable.
- It cannot be looked up: `GetCatalogNode` returns the same error.
- `searchfs` returns the error for the match (since c7ecc61d1).

Give every such name a stable stand-in of at most 255 bytes, in the format
Mac OS X uses, and make every path that takes a name accept it.

**Done when:** a user-space round-trip test on the build box passes for the
cases under "Testing", and the five changed kernel files compile with the real
ppc flags with no new warnings. HFS is ppc-only and cannot be booted here, so
there is no end-to-end test on a real volume; see "The gap worth naming".

## What is already here

Darwin 0.3 kept the lookup half of Mac OS's name mangling:

- `GetEmbeddedFileID` (`UnicodeWrappers.c`) parses `prefix#HEXID` or
  `prefix#HEXID.ext` and returns the ID and the prefix length.
- `LocateCatalogNodeByMangledName` (`CatalogUtilities.c`) finds the node by
  that ID through its thread record, checks that its parent is the directory
  being searched, and checks that the node's real name starts with the prefix.
- `GetCatalogNode`, `DeleteCatalogNode`, `MoveRenameCatalogNode`,
  `UpdateCatalogNode` and `CreateFileIDRef` all fall back to it when an exact
  HFS Plus lookup returns `cmNotFound`.

Nothing produces such names. The Mac OS producers (`ConvertUnicodeToHFSName`,
and the `Str15` helpers `GetFileIDString` and `GetFilenameExtension`) are
`#if 0` or `#if TARGET_OS_MAC`, and make 31-character Mac Roman names.

## The reference

xnu-124 (`D:\xnu-rel-xnu-124\bsd\hfs`) adds `ConvertUnicodeToUTF8Mangled` to
`UnicodeWrappers.c`, with C-string versions of `GetFileIDString` and
`GetFilenameExtension`. Its readdir tries a plain conversion and calls the
mangler when that reports the name too long.

This design follows it, with three labelled divergences:

1. **The ID string.** xnu-124's `GetFileIDString` moved the Mac OS version's
   index to start at 0 but kept its "have we emitted a digit yet" test as
   `i > 1`. It therefore drops a `0` straight after the leading digit: ID
   0x103 becomes `#13`, which parses back to a different file or to none. Ours
   writes every digit after the first significant one.
2. **Where names are mangled.** xnu-124 mangles only in readdir. For lookup and
   searchfs it mallocs a buffer big enough for the full name, so a vnode keeps
   its real, over-long name. In this tree the catalog API returns names in an
   `FSSpec` whose `name` is a 256-byte `Str255`, and getattrlist and searchfs
   size their name buffers at `NAME_MAX + 1`. Carrying full names would mean
   reworking that plumbing, and getattrlist would hand out names longer than
   `NAME_MAX`. Instead lookup and searchfs mangle too, so a file has the same
   name in every view. Operations on its vnode then go by the mangled name,
   through the existing fallback.
3. **The matcher's comparison.** xnu-124 compares at most the first 64 - 6
   bytes of the prefix. Ours compares all of it.

## The name

```
<prefix>#<HEXID><.ext>
```

- `HEXID` is the node's catalog ID in upper-case hex without leading zeros:
  `#10`, `#103`, `#1A2B`, `#FFFFFFFF`.
- `.ext` is copied from the name when it ends in a dot followed by 1 to 5 ASCII
  letters or digits (xnu-124's `kMaxFileExtensionChars` and `EXTENSIONCHAR`).
  Otherwise it is empty.
- `prefix` is the name with that extension removed, converted to UTF-8 and cut
  to fit. The whole name, suffix and extension included, is at most
  `maxDstLen - 1` bytes (255 at every call site), plus its NUL.

Example: a name of 120 Japanese characters followed by `.txt`, catalog ID
0x1A2B. Its UTF-8 is 364 bytes. It is listed as its first 82 characters (246 bytes), then
`#1A2B.txt`: 255 bytes.

## Producing it

### `ConvertUnicodeToUTF8Mangled`

New in `UnicodeWrappers.c`, declared in `HFSUnicodeWrappers.h`, with xnu-124's
signature:

```c
OSErr ConvertUnicodeToUTF8Mangled(ByteCount srcLen, ConstUniCharArrayPtr srcStr,
        ByteCount maxDstLen, ByteCount *actualDstLen, unsigned char *dstStr,
        HFSCatalogNodeID cnid);
```

1. Build the ID string and the extension, both as C strings.
2. Convert the name minus its extension with `ConvertUnicodeToUTF8` into
   `maxDstLen - strlen(id) - strlen(ext)` bytes. Since 595c43409 that call
   always NUL-terminates, and when the name does not fit it drops the last
   whole character, so the prefix never ends in part of a character. Its
   result is ignored, as xnu-124 ignores `utf8_encodestr`'s.
3. Append the ID string, then the extension. Set `*actualDstLen` to the total
   and return `noErr`.

It mangles unconditionally, as xnu-124's does. Callers decide when to use it.

Its two helpers are new `static` functions. They get their own names, because
the file already declares the Mac OS `Str15` versions as `GetFileIDString` and
`GetFilenameExtension` (those prototypes and their `TARGET_OS_MAC` bodies are
left alone).

### Call sites

Each keeps its plain conversion and adds, as xnu-124's readdir does:

```c
if (result == kTECOutputBufferFullStatus)
    result = ConvertUnicodeToUTF8Mangled(..., cnid);
```

This applies only on the HFS Plus branch. Plain HFS names are at most 31 Mac
Roman characters, 93 bytes of UTF-8, and never overflow.

| Function | File | Serves | `cnid` from |
|---|---|---|---|
| `IterateCatalogNode` | `Catalog.c` | readdir, readdirattr | `nodeData->nodeID` |
| `GetCatalogNode` | `Catalog.c` | lookup, so the name stored in the vnode | `nodeData->nodeID` |
| `InsertMatch` | `hfs_vnodeops.c` | searchfs | `catalogInfo.nodeData.nodeID` |

`IterateCatalogNode` and `GetCatalogNode` convert the name before calling
`CopyCatalogNodeData`. Both swap the two, so the ID is known when the name is
converted; the two steps do not depend on each other. `InsertMatch` already
calls `CopyCatalogNodeData` first.

## Looking it up

### The parser

`CountFilenameExtensionChars`, which `GetEmbeddedFileID` uses to skip an
extension, counts any printable ASCII character (`Is7BitASCII`), `#` included.
When the prefix ends in a dot and a few letters just before the `#`, as in
`...x.ab#1A`, it takes `ab#1A` for an extension, removes `.ab#1A`, finds no
`#`, and the name never parses. It changes to xnu-124's class, ASCII
letters and digits only, which is also exactly what the producer copies.

`GetEmbeddedFileID` has no other callers, and its only user is the fallback
above.

### The matcher

`LocateCatalogNodeByMangledName` converts the found node's real name into a
64-byte buffer and requires it to be at least `prefixlen` bytes long. A
mangled prefix is about 250 bytes, so nothing produced here could ever match.
The buffer grows to `NAME_MAX + 1`. That costs 192 more bytes of kernel stack
in a frame reached from `GetCatalogNode`, which already holds about 1 KB.

The comparison then holds for every name the producer makes. The prefix is a
whole-character prefix of the name's UTF-8, at most 252 bytes: an ID string is
at least 3 bytes (`#10`). The real name converted into 256 bytes is the longest
whole-character prefix that fits in 255, so it is at least as long and starts
with the same bytes.

### exchangedata

`ExchangeFileIDs` (`FileIDsServices.c`) looks both files up by name with
`LocateCatalogNodeByKey` and has no fallback, so `exchangedata()` would fail
on a file whose vnode holds a mangled name. Its HFS Plus branch gets the same
fallback as the other catalog routines, for each file. The fallback fills in
the node's real key, and the function goes on to use that key: it looks both
files up by it again and passes it to `ReplaceBTreeRecord`.

## Behaviour

- **Exact names win.** The fallback runs only when an exact lookup finds
  nothing, so a real file named like a mangled name is found first. If
  another system gives a file exactly a long file's mangled name in the same
  directory, the long file cannot be reached by that name, and a vnode that
  holds it reaches the other file instead. RhapsodiOS cannot create such a
  name: open, mkdir and rename resolve it to the long file.
- **Shorter typed forms still resolve.** `abc#1A2B` finds ID 0x1A2B if it is
  in this directory and its name starts with `abc`. That is how the matcher
  already behaves, and how Mac OS behaves.
- **Deleting, renaming, moving, chmod, utimes and writes** go through the
  vnode's stored name, which is the mangled one, and reach the catalog
  through the fallback. Renaming a file to a new, short name gives it a real
  name again. Moving it to another directory under the same mangled name
  keeps its real name: `MoveRenameCatalogNode` builds the destination key
  from the real key the fallback found, not from the mangled string.
- **No new errors.** The mangler returns `noErr`, so readdir, readdirattr,
  lookup and searchfs no longer fail on these names. searchfs still returns the
  error for a corrupt plain HFS name (728cf26e6).

## Out of scope

- **Creating over-long names.** `namei` rejects any component over `NAME_MAX`,
  so RhapsodiOS cannot make one. They come from other systems.
- **The root folder's name.** A volume name can also be over-long. Its ID, 2,
  is below `kHFSFirstUserCatalogNodeID`, so the fallback refuses the `#2`
  name it would get. `UpdateCatalogNode` and volume renames take the root's
  stored name, so a volume name over 255 bytes would break them; that is left
  alone.
- **The Mac OS-only code** (`TARGET_OS_MAC`, `#if 0`) and its unused `static`
  prototypes, which cause three existing warnings. They are left as they are.

## Testing

A user-space harness on the build box, compiled natively with `cc`, links the
real `ConvertUTF.c` and function bodies that `extract.py` copies from the edited
`UnicodeWrappers.c`: `ConvertUnicodeToUTF8`, `ConvertUnicodeToUTF8Mangled` and
its helpers, `CountFilenameExtensionChars`, `GetEmbeddedFileID` and
`HexStringToInteger`. The matcher cannot be extracted, because it needs the
catalog. The harness repeats its comparison: convert the real name into
`NAME_MAX + 1` bytes, then require `actualDstLen >= prefixlen` and the first
`prefixlen` bytes to match.

For each case: mangle, check that the result is NUL-terminated, at most 255
bytes, and does not end in part of a character, parse it back, and check that
the ID and prefix length are right and the matcher comparison passes.

- a long CJK name, with no extension and with `.txt`
- a tail of 6 letters after the dot, too long to count as an extension
- a name ending in `.`, which has no extension
- a prefix whose last characters before the `#` include a dot, such as
  `.ab#1A` (fails before the parser change)
- an extension with capitals and a digit, such as `.MP3`
- the trigger itself: a 255-byte name converts whole and a 256-byte one is
  reported too long
- IDs 0x10, 0x103 (fails with xnu-124's ID string), 0x1000 and 0xFFFFFFFF
- a surrogate pair (4 UTF-8 bytes) right at the cut
- names whose prefix exactly fills the space left

The five changed files (`UnicodeWrappers.c`, `Catalog.c`, `CatalogUtilities.c`,
`FileIDsServices.c`, `hfs_vnodeops.c`) are compiled with the real ppc kernel
flags against the last kernel build's chroot. Warnings must match the
unmodified files'. `nm -u` may gain only `ConvertUnicodeToUTF8Mangled` where it
is called, `LocateCatalogNodeByMangledName` in `FileIDsServices.o`, and
`BlockMoveData` in `UnicodeWrappers.o`, which the mangler copies with.

`UnicodeWrappers.c`, `Catalog.c`, `CatalogUtilities.c` and `FileIDsServices.c`
contain Mac Roman bytes. They are edited byte-for-byte with Python in latin-1,
and reach the box inside uuencoded tars.

## The gap worth naming

Nothing here has run against a real HFS Plus volume. The kernel side is checked
by compiling and by reading, not by listing, opening and renaming a file with
an over-long name. Doing that needs a ppc machine or emulator that boots this
kernel, and a volume holding such a name, written by Mac OS 9 or Mac OS X.

## Outcome (2026-09-25)

The shared ppc box froze twice, so the checks ran on a private QEMU i386
guest booted from `vm/work/rhap-i386-bootstrapped.img` with `-snapshot`. A
ppc kernel built there supplied the chroot. It needed a copy of
`gcc-darwin-i386.conf` with `/usr/local/bin` added to its `path=`, because
the stock profiles leave out where the build root's `relpath` and `config`
live. A successful build deletes its build root, so the root was kept by
stopping rbuild once the HFS objects existed.

- `run-tests.sh`: 10 cases passed, with no compiler warnings.
- `ppc-compile-check.sh 0222b235b`: all five changed files compile with the
  same warnings as before; `nm -u` gains exactly `_BlockMoveData`,
  `_ConvertUnicodeToUTF8Mangled` (in two files) and
  `_LocateCatalogNodeByMangledName`.
- The whole-branch review found that a move to another directory under an
  unchanged mangled name inserted the record under the mangled string, while
  its thread kept the real name. `MoveRenameCatalogNode` now takes the
  destination key from the real key the fallback found.
