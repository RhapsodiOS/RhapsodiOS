# NSData immutable empty-data constructor

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA identifies `__NSNewImmutableData` at `0x425476f0`. It allocates an
`NSConcreteData` instance in the requested zone and sends
`initWithBytes:length:copy:freeWhenDone:bytesAreVM:` with copy enabled,
free-when-done disabled, and VM storage disabled. `-[NSData
subdataWithRange:]` calls it for an empty range before autoreleasing the
result. `NSData.m` now provides that helper and uses it in the matching
branch. The ABI, ownership, and module symbol maps claim the export.

IDA also identifies `__NSNewImmutableDataNoCopy` at `0x425852b8`. It uses
the same allocation path but initializes with copy disabled and
free-when-done enabled. It has no callers in the reference database; the
export is nevertheless present in the binary, so `NSData.m` now provides
the matching helper and the metadata maps claim it.

No tests or builds were run.
