# Foundation `NSFileHandle` I/O recheck

Reference: Foundation i386 IDA database `d12fe2f23883`; source reviewed in
`src/Kits/Foundation/NSFileHandle.m`.

Re-decompiled `-[NSConcreteFileHandle writeData:]` (`0x4257a0b4`),
`availableData` (`0x425792a4`), and `readDataOfLength:` (`0x42579af4`) and
compared them with the current source.

- `writeData:` returns for zero-length data, raises on the protected/closed
  flag or a negative write result, and loops over partial writes until all
  bytes are sent. The source follows the same loop and error path.
- `availableData` checks the protected/closed flag and `fstat`; regular files
  read once up to the current file size from the current offset, while other
  descriptors read once up to `NSPageSize()`. A zero-byte read returns empty
  data. The source follows those paths.
- `readDataOfLength:` reads regular files once up to the smaller of the
  request and bytes remaining. Other descriptors are read in chunks of at
  most 4096 bytes until the request is satisfied or a read returns zero. The
  source follows the same chunking and empty-data behavior.

No source discrepancy was found in these three methods. No tests or builds
were run.

## MOSXS PowerPC cross-architecture I/O recheck (2026-10-05)

Re-decompiled the corresponding PPC bodies: `-[NSConcreteFileHandle writeData:]` at `0x4258dc98`, `availableData` at `0x4258cc9c`, and `readDataOfLength:` at `0x4258d5a0`. Their control flow matches the current `NSFileHandle.m` implementation and the i386 comparison above: protected/closed checks precede I/O; `availableData` uses `fstat`, reads regular files only through the current file end, and uses `NSPageSize()` for other descriptors; `readDataOfLength:` caps nonregular reads at 4096 bytes and loops until the request is met or a read returns zero; `writeData:` handles partial writes until complete and raises only for negative results. No source correction was indicated by the PPC pass. No tests or builds were run.

## Constructor, factory, and descriptor-operation recheck (2026-10-07)

Paired IDA review confirms `initWithFileDescriptor:closeOnDealloc:` stores the
descriptor and sets the close-on-deallocation flag only when requested.
`initWithPath:flags:createMode:` obtains a 1024-byte filesystem representation,
opens it with the supplied flags and mode, stores the descriptor on success,
and deallocates the receiver on conversion or open failure. The source follows
those paths on i386 (`0x425798a0`, `0x425798c0`) and PPC (`0x4258d2dc`,
`0x4258d304`).

The three path factories pass flags 0, 2, and 1 for reading, updating, and
writing, respectively, use mode 0, and autorelease the initializer result.
Standard input/output/error are memoized, initialized with descriptors 0/1/2
and close-on-deallocation disabled, tagged with their target flag bits, and
fall back to the memoized null handle when initialization fails. The null
factory memoizes an initialized `NSNullFileHandle`. Source call order matches
both target groups (i386 `0x4257701c`–`0x42577254`; PPC
`0x425895ac`–`0x4258989c`).

The descriptor and state methods also match both targets: `fileDescriptor`
raises when closed; `offsetInFile` and `seekToEndOfFile` use `lseek` with
`SEEK_CUR`/`SEEK_END`; `seekToFileOffset:` checks the seek result;
`truncateFileAtOffset:` seeks before truncating; and `synchronizeFile` checks
`fsync`. i386 addresses are `0x4257952c`, `0x42579970`, `0x42579e14`,
`0x42579e60`, `0x4257a018`, and `0x42579fe8`; PPC addresses are `0x4258cf34`,
`0x4258d3c0`, `0x4258d904`, `0x4258d97c`, `0x4258db9c`, and `0x4258db48`.
No source correction was indicated. No tests or builds were run.

## Deallocation and hidden-data ownership recheck (2026-10-09)

Compared `-[NSConcreteFileHandle dealloc]` in i386 (`0x425794a8`) and PPC
(`0x4258ce8c`). Both targets return early for the `0xE000` terminal-state
flags; otherwise they close the descriptor unless flags `0x9` suppress it,
release the hidden-data reference when present, clear notification modes, and
call superclass deallocation. `_NSHiddenDataReleaseDidDeallocate` takes the
hidden-data pointer on both targets; PPC keeps it live in its argument register
through the call. The source passes `hiddenData` explicitly and preserves the
same cleanup order. No code change was indicated. Static paired IDA/source
review only; no tests or builds were run.
