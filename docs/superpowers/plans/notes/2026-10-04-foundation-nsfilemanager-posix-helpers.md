# Foundation NSFileManager POSIX helpers

Reference: Foundation i386 IDA database `703cb6287da7`.

Implemented four exports in `NSFileManager.m`:

| Mach-O export | IDA address | Behavior |
| --- | ---: | --- |
| `__NSCreateDirectory` | `0x42555388` | Converts an `NSString` path to a filesystem representation and delegates to `_NSCreateDirectory2`. |
| `__NSCreateDirectory2` | `0x4251f7c0` | Calls `mkdir(path, 0777)` and returns whether it succeeded. |
| `__NSDeleteFile2` | `0x4258498c` | Calls `unlink(path)` and returns whether it succeeded. |
| `__NSRemoveDirectory2` | `0x4251f7a4` | Calls `rmdir(path)` and returns whether it succeeded. |

All four exports are recorded in `NSFileManager.json` and assigned to
`NSFileManager.m` in `symbols.json`. No tests or builds were run.

## Numeric account accessor parity

Compared `fileOwnerAccountNumber` and `fileGroupOwnerAccountNumber` in both
Foundation IDA targets. The generic `NSDictionary` category implementations
return zero on i386 and PPC; `NSFileAttributes` overrides return
`statInfo.st_uid` and `statInfo.st_gid`. `NSFileManager.m` matches both
behaviors, so the category's zero returns are target behavior rather than
unfinished implementations. Static decompile/source review only; no tests or
builds were run.

## Path existence helper

IDA at `0x4252e394` confirms `_NSFileExistsAtPath(NSFileManager *,
unichar *, int, struct stat *)`. It wraps the UTF-16 buffer in an
`NSCheapMutableString`, converts it with a 1026-byte maximum, uses `lstat`,
and follows symbolic links except for the binary's special directory-link
case. The implementation uses `st_mode` for the file-type mask, as confirmed
by the `stat` layout in the ABI manifest and the existing `NSFileManager`
helper. The export is now recorded in `NSFileManager.json` and owned by
`NSFileManager.m` in `symbols.json`. No tests or builds were run.
