# pdservd reconstruction

2026-09-25. `pdservd` rebuilt against Apple's DR2 binary, at the user's request.

Reference: `PortServer.config/pdservd` from DR2 (drvPortServer-14), 37840 bytes,
SHA-256 `21242911022A6B347FCA13E8E95A41863A836FB25ACD30192DB6841E67D3D9EF`,
`MH_EXECUTE` i386, dyld-linked and prebound. The copy on the DR2 guest's
`/usr/Devices/PortServer.config` is the same file.

The main pass left `pdservd.tproj` out of scope (`divergences.md` §2): binrecon's
Mach-O reader rejects `MH_EXECUTE`, so there is no ledger or source map for it.
This record stands in for them.

## What was wrong

The old `pdservd.m` did not compile. `readInstanceTable` walked `nodeList`, an
array of structs, as though it held strings. Beyond that, it did not match the
binary:

- It made two nodes per tty, `/dev/tty<x>` and `/dev/cu<x>` at minor +128.
  Apple's makes four: `ttyd<x>` (+0), `ttyid<x>` (+0x40), `cua<x>` (+0x20) and
  `cuia<x>` (+0x60). The driver reads bit 0x20 as the call-out side and
  `dev & 0x1f` as the unit, so +128 could never have worked.
- Its prefix list was `tty` and `cu`, so the driver's `ttyda` came out as
  suffix `d`, and every port as `/dev/ttyd` and `/dev/cud`. Apple's strips
  `ttyd` or `/dev/ttyd`.
- Table keys were `Path_%d_IN` / `Path_%d_OUT`; Apple's are `Path %d IN`,
  `Path %d IN Init`, `Path %d OUT` and `Path %d OUT Init`.
- Node mode `0021666` (sticky bit set) where Apple's uses `020666`.
- `removeStringKey:`, which `NXStringTable` does not have, where Apple's uses
  `HashTable`'s `removeKey:`, `valueForKey:` and `insertKey:value:`. Apple's
  also copies each key and value with `NXCopyStringBuffer`.
- It defined its own `device_master_self()` through the bootstrap port and
  called `IOGetIntValues` and friends, which nothing defines. Apple's imports
  `device_master_self` and carries its own `IODeviceMaster` class and MIG
  client stubs.
- `openlog(..., LOG_NDELAY, ...)` against Apple's `LOG_CONS`, and extra
  "starting" / "complete" syslog lines that Apple's does not print.

## Method

Every hand-written function in the reference was read in full with capstone:
`init`, `serverPostLoad`, `genSuffix`, `ttyPostLoad`, `process_ttys`,
`readInstanceTable`, `writeInstanceTable` and `main`. PIC loads, dyld stubs and
selector references were resolved against the binary's own sections (its
`__message_refs` are prebound into libobjc, so selectors were matched by index
to `__meth_var_names`). `__data` gives the node table directly, and the nlist
gives each symbol's linkage: `init`, `serverPostLoad`, `ttyPostLoad`,
`process_ttys` and all the data are `static`; `genSuffix`,
`readInstanceTable`, `writeInstanceTable` and `main` are external;
`prefixList` is a static local of `genSuffix`.

`IODeviceMaster.h`/`.m` and `driverServer.defs` are the ones drvBPF's PostLoad
already uses. Apple's pdservd and BPF PostLoad carry the same `IODeviceMaster`
methods and the same MIG client stubs, in the same order.

## Parity

Built on the i386 guest with `rbuild buildpackage --toolchain
.../gcc-darwin-i386.conf --arch i386` and compared function by function, with
addresses reduced to what they point at (strings, selectors, symbols, stubs)
and jump targets to instruction indexes:

| Function | Reference | Ours | |
|---|---|---|---|
| `_init` | 30 | 30 | identical |
| `_serverPostLoad` | 194 | 194 | identical |
| `_genSuffix` | 51 | 51 | identical |
| `_ttyPostLoad` | 205 | 205 | identical |
| `_process_ttys` | 84 | 84 | identical |
| `_readInstanceTable` | 119 | 119 | identical |
| `_writeInstanceTable` | 51 | 51 | identical |
| `_main` | 22 | 22 | identical |

Three source shapes were needed to get there, each settled by the first diff:
`genSuffix` holds `prefixList[i]` in a local (Apple's keeps it in a register
across `strncmp`); `process_ttys`'s switch lists the free-and-return case
first (Apple's places that block straight after the dispatch); and `main`'s
`umask` result is an `int` (Apple's truncates it on assignment).

`__data` holds the same four node entries and terminator, `lastPort` = 0x60
and `prefixList`, in the reference's order, and `__bss` the same three
statics in the same order. Two differences remain, neither in `pdservd.m`:
the local static is labelled `prefixList.88` against the reference's
`prefixList.18` (a compiler counter), and our binary has a common
`_catch_exception_raise` from the shared `IODeviceMaster`/MIG half.

`readInstanceTable` calls `atoi` on the port count once before its loop and
throws the result away, then again on every test of the loop condition. That
is the reference's behaviour and is kept.

## Packaging

`pdservd.tproj` sat at the top of the aggregate, in its `TOOLS`, and installed
to `/usr/sbin/pdservd`. `driverLoader` runs a config's Post-Load from inside the
`.config`, so the built package never ran it (`pdservd: not found`). It now
lives in `PortServer.drvproj` and is listed in that project's `TOOLS`, as
drvBPF's `PostLoad.tproj` and drvEIDE's are, so it installs as
`PortServer.config/pdservd`, where Apple's is.

## Guest test

On a private i386 guest running kernel-7, with our `PortServer_reloc` loaded:

- `driverLoader D=PortServer` ran our pdservd, which made `/dev/ttyda` (1,0),
  `ttyida` (1,64), `cuaa` (1,32), `cuiaa` (1,96), `pdservd` (1,192) and
  `rpski01` to `rpski16` (1,193-208), all `crw-rw-rw-`. That is the set Apple's
  pdservd makes against the same driver. It logged the same two syslog lines
  and exited 1, as Apple's does.
- Given the same `Instance0.table`, fresh (`"Port Count" = "0"`) or stale (two
  ports' worth of old `Path` keys plus an unrelated key), our pdservd and
  Apple's wrote byte-identical tables: stale `Path` keys removed, the unrelated
  key kept, the four `Path 0` keys added and `Port Count` set to 1.

This tests pdservd only. Opening a data tty through the reconstructed driver
still crashes kernel-7; that is a driver defect, not a pdservd one.
