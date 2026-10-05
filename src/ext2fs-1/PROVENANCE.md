# Mount helper provenance

NetBSD netbsd-2-0 snapshot c90afb5a84a9c36a5c076093afade8e63ed2b6a9,
`sbin/mount_ext2fs/`, BSD licensed notices retained in each file.

| Original file | SHA-256 before adaptation |
| --- | --- |
| mount_ext2fs.c | dfdab885e0ddb778c3f600d295fa5cd57c3c06e5fb17f26bbf988b68c9057ad7 |
| mount_ext2fs.8 | 050261940683e2590e18bc3ad414977ff4378152457763f3e90e9a886fcf68f1 |

Native mount uses the exported one-pointer ext2fs_args and local flag values.
The unavailable NetBSD getmntopts and GETARGS/NODEVMTIME options are not
carried over. Unknown options are refused before the mount syscall.
Only the mount subproject exists at this milestone.
