# drvSCSITape divergences

References, all under `SCSITape.config`:

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `SCSITape_reloc` | 47624 | `ABB8D7E5FDEB9188A4C58D10AE6A7A1313A79EFBE49513AD3804E386BB65131A` |
| `PreLoad` | 9060 | `177355F05BDCBD6EDE34121F93E6B6A176B105ACF8EAD1945761A9E1D3BFB60A` |
| `PostLoad` | 21520 | `A6025294E3E1AB96270BBE3AFAD73A3885C7C5F44644241E44DD553632699F87` |
| `stblocksize` | 13408 | `E36D1320E5543E9F8B46D522D19150DC6BA21B348C6ECAB8D13AE9CF83BC7648` |

Analysis: IDA 9.2. Ghidra and angr are i386-only and cannot analyse these
binaries.

No PowerPC build exists in this environment, so nothing recorded here is
compile-verified — including the function bodies the fix pass writes. Every
claim rests on the reference disassembly.

## Starting state

| Artifact | Named | Mapped | Unmapped |
| --- | --- | --- | --- |
| `SCSITape_reloc` | 50 | 44 | 6 |
| `PreLoad` | 12 | 1 | 11 |
| `PostLoad` | 16 | 1 | 15 |
| `stblocksize` | 20 | 3 | 17 |

## Out of scope

**94 jump islands.** `SCSITape_reloc`'s IDA analysis finds 144 functions; 94 are
unnamed 16-byte `lis`/`mr`/`mtctr`/`bctr` sequences — build-generated branch glue
for calls exceeding the PowerPC branch displacement. `filter_named_functions.py`
excludes them.

**crt and dyld startup, six per helper.** `start`, `__start`,
`__call_mod_init_funcs`, `__dyld_init_check`, `dyld_stub_binding_helper` and
`__dyld_func_lookup` come from the C runtime and the dynamic linker, not from
our source.

**Every 36-byte `__picsymbol_stub` entry.** 5 in `PreLoad`, 9 in `PostLoad`, 10
in `stblocksize` — confirmed against each binary's stub-section size (180, 324
and 360 bytes, all exact multiples of 36), and matching the libc names one for
one (`_printf`, `_ioctl`, `_open`, `_atoi`, `_strlen`, `_strcmp`, `_bzero`,
`_close`, `_exit`, `_perror`, `_sprintf`, `_unlink`).

Unlike the jump islands these are *named*, so `filter_named_functions.py` cannot
remove them and they stay in the `unmapped` bucket. They are explained here
rather than filtered out of sight.

**Two build-generated classes.**
`+[SCSITapeKernelServerInstance kernelServerInstance]` (20 bytes) and
`+[SCSITapeVersion driverKitVersionForSCSITape]` (16) are emitted by the Kernel
Server build from the project's own settings, exactly as `SCSIServer`'s pair
were. They remain `unmapped` permanently.
