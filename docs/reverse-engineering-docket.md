# Reverse-engineering docket

This lists components that projects in `src/` need but that the tree has no
source for. Each one has to be reverse engineered from Apple's binaries
before the projects that use it can build.

| Component | Needed by | Blocks |
|---|---|---|
| `oamshim.framework` | `src/bootp-1` (bootplib, bootpd) | `/usr/sbin/bootpc` on ppc, `/usr/libexec/bootpd` on both CPUs |
| `ServerControl.framework` | `src/bootp-1` (bootplib) | `/usr/sbin/bootpc` on ppc, `/usr/libexec/bootpd` on ppc |

## bootp-1

### Why it matters

`src/files-5/private/etc/startup/0800_Network` runs `bootpc <if>` for every
`-AUTOMATIC-` interface in `/etc/iftab`. On master it is the only BOOTP
path. On the `dhcpcd-1` branch it is the fallback after `dhcpcd` fails.
`1700_IPServices` runs `bootpd`, or `bootpd -m` for NetBoot, when
`CONFIGSERVER=-YES-`; `hostconfig` defaults that to `-NO-`. `bpwhoami`, the
script's other fallback, comes from `Commands/network_cmds` and is already
built.

`bootp-1` is not in `src/Manifest`, so rbuild never builds it. An i386 guest
printed `Trying BOOTP for interface en0:bootpc: not found`. Nothing else
supplies these tools either:

- `Commands/network_cmds` (version 57) no longer carries a `bootpd`.
- DR2 has no `bootpc`. Its `/usr/libexec/bootpd` is the older one from
  `network_cmds-38`, which links only `System.framework`.

### Build results

The project was built on 2026-09-25 as an unmodified universal
`rbuild buildpackage --toolchain .../gcc-darwin-i386.conf`, on a private
`-snapshot` guest from `rhap-i386-bootstrapped.img`. A second pass added
`libinfo-hdrs` to the build root by hand and ran the install with `make -k`:

| Subproject | i386 | ppc |
|---|---|---|
| `bootplib` | compiles | fails: `hfsvols.c`, `sharepoints.c` |
| `bootpc.tproj` | compiles; the link stops at the missing `libbootplib.a` | same |
| `bootpd.tproj` | fails: `afpuser.h`, `bootpd.m` | same |
| `bscfg` | `libtool -static` cannot find `-lbootplib`; not retried with the library present | same |

The i386 slice of `bootplib` builds because `hfsvols.c` and `sharepoints.c`
are wrapped in `#ifdef ppc`. `afpuser.c` is compiled on both CPUs, and
`macNC.m` imports `afpuser.h` unconditionally. So `bootpd` needs `oamshim`
on i386 as well, and a reconstruction has to cover both CPUs.

### oamshim.framework

The `bootplib` and `bootpd.tproj` Makefiles list
`-framework oamshim -framework ServerControl`, and bootplib's `sharepoints`
test target finds them in `/System/Library/PrivateFrameworks`. Headers
imported:
`<oamshim/MacTypes.h>`, `<oamshim/OAMTypes.h>`, `<oamshim/OAM.h>` (from
`bootpd.tproj/afpuser.h`) and `<oamshim/AppleShareRegistry.h>` (from
`bootplib/sharepoints.c`).

Functions `bootpd.tproj/afpuser.c` calls, in the forms it uses:

| Call | Used for |
|---|---|
| `OAMInitialize(1, 1, NULL, NULL)` | one-time setup |
| `OAMOpenSession(NULL, &session, NULL)` | open a session |
| `OAMCloseSession(session, NULL)` | close it |
| `OAMCreateObject(session, &spec, attrs, NULL)` | create a user (the NetBoot client) or a group; `attrs` may be `NULL` |
| `OAMDeleteObject(session, &spec, NULL)` | delete a user |
| `OAMGetAttribute(session, &spec, attrs, NULL)` | check that a user exists |
| `OAMSetAttribute(session, &spec, attrs, NULL)` | set a user's password |
| `OAMAddGroupMember(session, &group, &user, NULL)` | add a client to the NetBoot group |
| `OAMRemoveGroupMember(session, &group, &user, NULL)` | remove it |

Types, fields and constants the code depends on:

- `OAMStatus`, `OAMSessionID`, `OAMType`, `OAMShortObjectSpec`.
- `OAMObjectSpec`: `specType`, `objectType`, and a union `u` with `name` (a
  Pascal string) and `shortID`.
- `OAMAttributeDescriptor`: `attributeSignature`, `attributeType`, and
  `bufferDescriptor` with `buffer`, `bufferLen` and `actCount`. A zero
  `attributeSignature` ends a list.
- Spec types: `kOAMObjectSpecByNameType`, `kOAMObjectSpecByShortID`.
- Object types and signatures: `kUser`, `kGroup`, `kBasic`.
- Attributes: `kPasswordAttribute` (8 bytes, NUL padded), `kInternetName`
  (a `Str31`), `kUserFlags` (a `short`).
- User flags: `bmLoginEnabled`, `bmDisableChangePwd`.
- Status codes: `noErr`, `kOAMErrDuplicateObject`.
- From `MacTypes.h`: `Str31`, `StringPtr`. `afpuser.h` wraps the imports in
  `#define nil pascal_nil` / `#undef nil`, which suggests the oamshim headers
  define their own `nil`, clashing with Objective-C's.

The `TEST_AFPUSER` harness also uses `kMachine`, `kServerName` and
`kMachineShortID`, but the daemon does not.

### ServerControl.framework

`bootplib/sharepoints.c` imports `<ServerControl/ServerControlAPI.h>`. It
lists and creates AFP share points for the NetBoot volumes, ppc only.
Without the headers we can't tell which of these come from ServerControl
and which from oamshim's `AppleShareRegistry.h`:

- Calls: `AddSharePoint(kAFPServer, &spec)`,
  `CreateSharePointIter(kAFPServer, kSCSharePointRec, &iter)`,
  `GetNextSharePoint(iter, &ref)`,
  `GetSharePointAttribute(ref, kSharePointName, sizeof(SharePointInfo), &size, &spec)`,
  `DeleteSharePointIter(iter)`.
- Types: `SharePointSpec` (`volumeID`, `dirID`, `filename`),
  `SharePointInfo`, `SharePointIterRef`, `SharePointRef`.
- Constants: `kAFPServer`, `kSCSharePointRec`, `kSharePointName`.

### Reference binaries

The frameworks have to come from Mac OS X Server 1.0–1.2v3, which shipped
the AFP file server and NetBoot. The DR2 guest's
`/System/Library/PrivateFrameworks` has neither framework.

### Other bootp-1 gaps

These don't need reverse engineering, but they have to be fixed before
`bootp-1` goes into the Manifest:

- `apk/pkginfo` lists only `build-base`. It also needs `libinfo-hdrs` for
  `<netinfo/ni.h>` and `<netinfo/ni_util.h>`.
- `bootpd.m` imports `<arpa/nameser.h>`. The file is in
  `src/Libinfo-1/dns.subproj`, but `libinfo-hdrs` does not export it.
- The ppc `hfsvols.c` and `sharepoints.c` import `<vol.h>`, and `bootpd`
  links `-lVDI-interface`. Both come from `src/hfs-1/hfs_glue`, which installs
  `vol.h` under `System.framework/.../PrivateHeaders/bsd`, off the default
  include path. The bootstrapped repo has no `hfs` apk.

### Getting bootpc without the frameworks

`bootpc` itself needs neither framework. Judging by the build results,
three changes should get `/usr/sbin/bootpc` building universally now. This
is untested. `bscfg` also has to be rechecked once `libbootplib.a` exists.

1. Take `bootpd.tproj` out of the aggregate.
2. Take `hfsvols.c` and `sharepoints.c` out of `bootplib`. Only the ppc
   `macNC.m` in `bootpd` uses them.
3. Add `libinfo-hdrs` to the makedepends.

This was set aside on 2026-09-25 in favour of reverse engineering the
frameworks. Either way, the Manifest line is
`dir     bootp-1               all`, between `boot-2` and
`Commands/bootstrap_cmds`.
