# Foundation `NSData` mapped-file helper

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA confirms `_NSMapBytesFromFile(NSString *, vm_offset_t *, vm_size_t *)` at
`0x42551dbc`. It converts the path with `getFileSystemRepresentation:maxLength:`
using a 1024-byte limit, opens read-only, obtains the file size with `fstat`,
and maps the file with `map_fd`. It sets the returned address to zero before
opening. On `fstat` or mapping failure it saves the cthread error across
`close`, restores both cthread errno and `errno`, and returns zero. On success
it closes the descriptor, writes the mapped size, conditionally records an
`NSVMAllocateEvent`, and returns one.

`-[NSData initWithContentsOfMappedFile:]` calls this helper directly, then
initializes VM-backed data with `copy:NO`, `freeWhenDone:YES`, and
`bytesAreVM:YES`. The source follows that call path. The helper is recorded in
`NSData.json` and assigned to `NSData.m` in `symbols.json`. No tests or builds
were run.

## PPC reader and mapped-file behavior (2026-10-07)

The MOSXS PPC image uses a different shared reader. `_NSReadBytesFromFile` at
`0x4251c880` takes a fifth `allocatePages` argument. It reads into
`NSZoneMalloc(zone, size)` when false, or `NSAllocateMemoryPages(size)` when
true; the empty-file path allocates four bytes from the corresponding
allocator. Read failures free with the matching allocator and restore both
cthread errno and `errno`. `_NSMapBytesFromFile` at `0x425530c4` delegates to
that reader with a null zone and `allocatePages = 1`. DR2 i386 retains the
four-argument `_NSReadBytesFromFile` at `0x425204fc` and its `map_fd`-based
`_NSMapBytesFromFile` at `0x42551dbc`.

PPC `-[NSData initWithContentsOfMappedFile:]` at `0x42553090` is a forwarding
stub: its selector reference at `0x4262cf30` resolves to
`sel_initWithContentsOfFile:`. The i386 method at `0x4255339c` instead calls
`_NSMapBytesFromFile` and initializes VM-backed data. `NSStringEncodings.m`
and `NSData.m` now preserve this target split; the shared symbol and module
assignments were already present. Static source/metadata checks only; no tests
or builds were run.

## PPC zero-length ownership parity (2026-10-07)

A paired IDA check of `-[NSConcreteData initWithBytes:length:copy:freeWhenDone:bytesAreVM:]`
confirmed that the PPC zero-length path frees a non-null input pointer with
`_NSGenericFree` when `freeWhenDone` is true. The i386 path only clears the
capacity, byte pointer, and flags. `NSData.m` now performs that cleanup only
for PPC. This releases the four-byte allocation returned by the PPC shared
file reader when an empty file is loaded with `freeWhenDone:YES`. Static
source checks only; no tests or builds were run.
