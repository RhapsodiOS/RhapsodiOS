# Foundation NSFileHandle asynchronous path recheck

This note records a read-only comparison of the approved NSFileHandle
reconstruction against IDA database `6c2a913dc37a`.

The four public background methods pass these worker functions and activity
codes to `performFunction:modes:activity:` (`0x425799bc`):

| Entry point | Worker | Activity |
| --- | --- | ---: |
| `acceptConnectionInBackgroundAndNotifyForModes:` | `_acceptConnectionActivity` (`0x42585610`) | 12 |
| `readInBackgroundAndNotifyForModes:` | `_readActivity` (`0x42585aa4`) | 14 |
| `readToEndOfFileInBackgroundAndNotifyForModes:` | `_readAllActivity` (`0x42585b18`) | 16 |
| `waitForDataInBackgroundAndNotifyForModes:` | `_waitForDataActivity` (`0x42585bb8`) | 20 |

The accept worker stores the accepted descriptor at hidden-data field 9 and
records `cthread_errno()` in field 4 on failure. The read worker reads up to
4096 bytes, stores the result length in field 8, and allocates/copies bytes
into field 7 when the read is positive. The read-all worker starts at 4096
bytes, doubles capacity, and passes `4 * length` to `NSZoneRealloc`; it records
the final length and frees the buffer only when the first read fails. The wait
worker selects on the descriptor and records the thread error on failure.
Each worker finishes through `_NSHiddenDataReleaseAndSend`.

`_NSHiddenDataAllocate` (`0x42584fe0`) allocates 40 bytes, initializes the
lock, reference count, port, error, byte pointer, and accepted-descriptor
sentinel; `performFunction:` supplies the descriptor and native handle before
forking the worker. `_NSHiddenDataReleaseDidDeallocate` (`0x425850c0`) locks,
decrements the reference count, clears the lock, and frees on zero.
`_NSHiddenDataReleaseAndSend` (`0x42585074`) copies the 24-byte Mach message
template, inserts the port, releases one reference, and sends only when the
data block remains live. The template's first words are `0x01000000`, `0x18`,
and `0`; its remote-port field is overwritten before sending.

The current `NSFileHandle.m` worker and hidden-data paths match these target
operations, including the target's realloc size. No source changes, tests, or
builds were made during this comparison.

## Synchronous operation recheck

The `NSConcreteFileHandle` initialization and synchronous I/O methods were
also compared against IDA: `initWithFileDescriptor:`,
`initWithFileDescriptor:closeOnDealloc:`, `initWithPath:flags:createMode:`,
`availableData`, `readDataOfLength:`, `readDataToEndOfFile`, `writeData:`,
`offsetInFile`, `seekToEndOfFile`, `seekToFileOffset:`,
`truncateFileAtOffset:`, `synchronizeFile`, `closeFile`, `fileDescriptor`,
and `dealloc`. Their current source branches and state flags match the
decompiled target. The path initializer's stack buffer is 4104 bytes, and its
filesystem-representation call passes a 1024-byte maximum, confirmed by the
`push 400h` at `0x425798d8`. The read-all method passes `0xffffffff` to
`readDataOfLength:`, matching the source's `UINT_MAX`. No discrepancy requiring
a source correction was found.

## Pipe implementation spot-check

The `NSPipe` class methods (`allocWithZone:`, `pipe`, and the abstract base
methods) and `NSConcretePipe` methods (`init`, endpoint accessors,
`copyWithZone:`, and `dealloc`) were checked against IDA at
`0x425776bc`–`0x42581280`. The source preserves class substitution, endpoint
ownership, retain-on-copy behavior, and cleanup for both endpoint-wrapper
failure paths. No pipe discrepancy was found.

## Null-device and standard-handle factories

The cached `fileHandleWithNullDevice` factory allocates and initializes one
`NSNullFileHandle`; the standard input/output/error factories cache their
descriptor wrappers, mark them with `0x8000`, `0x4000`, and `0x2000`, and fall
back to the shared null handle if descriptor initialization fails. The
`NSNullFileHandle` reads return empty `NSData`, its descriptor is `-1`, offsets
are zero, and write/seek/truncate/sync/close operations are no-ops. These
source paths match the target bodies at `0x42577100`, `0x42577154`,
`0x425771d4`, `0x42577254`, and `0x42580fac`–`0x4258106c`.

## Path factories and allocation

`+[NSFileHandle allocWithZone:]` substitutes `NSConcreteFileHandle` only when
allocating the abstract base. The reading, writing, and updating factories
allocate through `self`, call `initWithPath:flags:createMode:` with flags `0`,
`1`, and `2` respectively and create mode `0`, then autorelease the result.
The source matches these target bodies at `0x42576fc0`–`0x425770b4`; the
concrete path initializer also matches its IDA body at `0x425798c0`.

The source path buffer was subsequently corrected from 4096 to 4104 bytes.
IDA's local-variable record gives `char[4104]`, and the disassembly confirms
the separate `getFileSystemRepresentation:maxLength:withPath:` maximum remains
`0x400` (1024) bytes. `git diff --check` passes for `NSFileHandle.m`; no tests
or builds were run.

## Mach-message callback parity recheck

Re-decompiled `-[NSConcreteFileHandle handleMachMessage:]` at
`0x42579550` in the attached Foundation-i386 database and compared it with the
current source. The target ignores messages larger than 24 bytes, removes all
registered run-loop modes, then handles activity 12 by detaching the accepted
descriptor and releasing hidden state before posting the accepted-connection
notification. Activities 14 and 16 detach the byte buffer, release hidden
state, and post the matching completion notification with the data item when
present. Activity 20 releases hidden state and posts an empty data-available
notification. The source follows the same order and notification fields. The
`descriptor < 0` check is equivalent to IDA's `descriptor == -1` because
`accept(2)` returns only a nonnegative descriptor or `-1`. No source changes,
tests, or builds were made.

## PPC Mach-message callback parity recheck

Re-decompiled MOSXS PPC `-[NSConcreteFileHandle handleMachMessage:]` at
`0x4258cf70` and compared it with the source and the earlier i386 recheck.
Both targets reject messages larger than 24 bytes, remove registered modes,
then release hidden state before notification delivery for activities 12, 14,
16, and 20. The PPC notification branches use the same accepted-handle and
no-copy data payloads as the source; activity 20 posts empty user info. The
source's negative accepted-descriptor check matches the target's `-1` check
because `accept(2)` returns a nonnegative descriptor or `-1`. No source
correction was indicated. No tests or builds were run.
