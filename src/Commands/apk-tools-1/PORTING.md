# Porting apk-tools 2.0_pre12 to Rhapsody

apk-tools is vendored under `apk-tools/`. This documents the portability
changes made to build it off-Linux and what remains to validate on Rhapsody
(Apple cc, gcc 2.95.2-based).

## Build (host proxy)

    cd apk-tools && make            # builds apk-tools/src/apk
    sh apk-tools/tests/smoke.sh     # format-level smoke tests

## Build (RhapsodiOS / target)

    make install DSTROOT=<root>     # via the project Makefile / rbuild

## Changes made (resolved on the dev host)

- Build flags (`Make.rules`): dropped `-std=gnu99` (rejected by gcc 2.95),
  `-Werror` (host/target warning differences), and `-D_GNU_SOURCE` (glibc-only,
  no-op off-Linux). Also reordered the dependency-generation flags
  (`-Wp,-MD,$(depfile),-MT,$@` → `-Wp,-MD,$(depfile) -MT $@`) since the
  combined `-Wp,` form concatenates `-MT` as a preprocessor sub-option that
  not every cpp accepts the same way.
- Link (`src/Makefile`): `LIBS ?= -lz` (was hardcoded `/usr/lib/libz.a`,
  Linux-specific path), so the target can override with its own libz;
  removed `-nopie` (not portable to older ld / Darwin's ld).
- `<malloc.h>` → `<stdlib.h>` in 9 files (`apk_defines.h`, `apk_hash.h`,
  `archive.c`, `blob.c`, `database.c`, `gunzip.c`, `io.c`, `package.c`,
  `state.c` — `state.c` needed no replacement, `stdlib.h` was already
  included there). `apk_defines.h` also gained `<stddef.h>` for `offsetof`
  (used by `container_of`/`list_entry`/`hlist_entry`), which `<malloc.h>`
  had been pulling in transitively on Linux.
- `md5.c`: portable `__BYTE_ORDER`/`__LITTLE_ENDIAN` via a guarded
  `<machine/endian.h>` include off-Linux, with `#ifndef` fallbacks mapping
  BSD's `BYTE_ORDER`/`LITTLE_ENDIAN` names to the GNU ones the file expects.
- `mknod`/`makedev` (`archive.c`, `database.c`): added explicit
  `<sys/types.h>` + `<sys/stat.h>` includes. On Linux these two calls are
  declared transitively via glibc's `<sys/sysmacros.h>` (itself pulled in by
  `<malloc.h>`/`<sys/types.h>`); off-Linux they come directly from
  `<sys/types.h>`/`<sys/stat.h>`, so the sysmacros path is Linux-only and
  isn't needed here.
- Residual shims: a guarded static `memrchr()` fallback in `blob.c` (GNU/glibc
  extension, not present in BSD/Darwin libc); `<sys/types.h>`/`<sys/stat.h>`
  added to `io.c`/`package.c` alongside their `malloc.h` removal.
- Applet registration reworked from GNU-ld linker-section magic
  (`__start_apkapplets`/`__stop_apkapplets`, with an ld64 fallback via
  `section$start$`/`section$end$` asm-named symbols that was itself added
  during the port but then replaced) to a portable **explicit applet table**:
  the 9 applet structs (`apk_add`, `apk_del`, `apk_audit`, `apk_index`,
  `apk_fetch`, `apk_search`, `apk_info`, `apk_update`, `apk_ver`) were made
  non-`static` and are listed in an `apk_applets[]` array in `apk.c`, with
  `usage()`/`find_applet()` iterating the array instead of the
  linker-section range. This is the largest change in the port — it removes
  any dependency on ld64/GNU-ld section-boundary symbol conventions.
- Project build (`src/Commands/apk-tools-1/Makefile`): replaced the `GNUSource.make`
  include (which requires a `configure` script apk-tools doesn't have, and
  never passes `DESTDIR`). The project Makefile now compiles
  `apk-tools/src/*.c` itself (see *Changes made on Rhapsody*); the vendored
  `Make.rules` build is still what `cd apk-tools && make` runs on a host.
- Host smoke tests (`apk-tools/tests/smoke.sh`): added a no-root,
  format-level smoke test that builds a minimal rbuild-style `.apk`
  (`.PKGINFO` + file, gzipped tar), runs `apk index` over it (tolerating
  CLI-form variance and WARNing rather than failing if unrecognized), and
  round-trips extraction via `gzip | tar` to confirm the on-disk layout apk
  and rbuild agree on.

## Changes made on Rhapsody

Found by building universal (i386 + ppc) with rbuild on the i386 build guest
(2026-09-25):

- The target's make is GNU make 3.74, which has no `$(call)` or `$(if)`, so
  the vendored `Make.rules` silently builds nothing and installs only the
  README. The project Makefile compiles the sources directly with `cc` and
  rbuild's `RC_CFLAGS` (`-arch i386 -arch ppc` plus the NeXT defines), links
  `apk-tools/src/apk` with `-lz`, and installs it to `/sbin`.
- Rhapsody's libc has no `getopt_long` or `<getopt.h>`: `compat/` carries GNU
  getopt (`getopt.c`, `getopt1.c`, `getopt.h`, GPL v2 or later, copied from
  `src/Developer/Commands/bison-1/bison`).
- gcc 2.95 rejects C99 designated initializers (`.field = value`): all are
  now the GNU `field: value` form, and the nested `.is.read`/`.os.write`
  ones are `is: { read: ..., close: ... }`.
- gcc 2.95 rejects C99 flexible array members: `x[]` in structs is now the
  GNU zero-length `x[0]`.
- No `<stdint.h>`: `apk_defines.h` typedefs `intptr_t` as `long` under
  `__NeXT__`. No `MAP_FAILED` in `<sys/mman.h>`: `io.c` defines it.
- `add.c` includes `<unistd.h>` for `STDOUT_FILENO`, which glibc had been
  pulling in transitively.
- No `lchown`: under `__NeXT__`, extraction leaves a symlink's owner as the
  extracting user (root).
- `apk/pkginfo` gained `zlib` in `makedepends`; zlib is not part of
  `build-base`.

Found by running apk on the guest (2026-09-25 to 27):

- Rhapsody's zlib is 1.1.3, whose `inflateInit2` has no gzip modes (window
  bits +16/+32 arrived in 1.2.0), so `apk_bstream_gunzip` returned NULL and
  every package read crashed. `gunzip.c` now reads past the RFC 1952 header
  itself and inflates the raw deflate data, and `apk_parse_tar_gz` refuses a
  NULL stream instead of calling through it.
- rbuild packs with pax: the tar reader joins POSIX ustar's `prefix` to the
  name, bounds both fields, drops a leading `./` and skips the archive's `.`
  entry. `apk_pkg_read` initialises `version` and keeps reading until
  `.PKGINFO` has been seen, so it need not be the first member.
- Rhapsody's printf has no `%zu`: the index and installed-database writer
  prints sizes as `%lu`.
- GNU tar (1.12 on Rhapsody) pads numeric header fields with spaces, which
  `apk_blob_uint` read as 0, so `.PKGINFO` came out empty. The tar reader
  parses those fields as tar readers do.
- `mknod` is given the file-type bits; without them Rhapsody refuses a device
  node (Linux quietly makes a plain file).
- Rhapsody's root layout, under `__NeXT__`:
  - `--initdb` creates `private/tmp`, `private/dev` and `private/var/lib/apk`
    with `tmp`, `dev` and `var` symlinks to them, the links the files package
    ships, which it then replaces. `private/dev/null` takes the running
    system's device number, and the world starts empty.
  - Entries at the top of the root (files' `etc -> private/etc`, `/.hidden`)
    install; apk gives the package a directory entry for the root itself.
  - Dot files other than `.PKGINFO` and the install scripts are data.
  - The protected configuration path is `private/etc`.

With those, `apk add --root <scratch> --initdb` of every base universal apk
in the bootstrap repository (41 packages, the `-hdrs`/`-obj` companions left
out) installs them all, records them in `private/var/lib/apk/installed`, and
lays down the root as files ships it.

## Target-validation checklist (verify on Rhapsody)

- [x] Apple `cc` (gcc 2.95.2) accepts the GNU C idioms used (`//` comments,
      `typeof`, statement expressions, `__attribute__`) once designated
      initializers and flexible arrays are converted (above).
- [x] `getopt_long`/`<getopt.h>` (from `compat/`), `mknod`/`makedev`,
      `fnmatch`/`<fnmatch.h>` resolve against Rhapsody's libc/headers.
- [x] zlib is available: the `zlib` apk, linked with `-lz`.
- [x] `Make.rules`'s `-Wp,-MD,$(depfile) -MT $@` dependency-flag form: moot on
      the target, which no longer builds through `Make.rules`.
- [x] `<machine/endian.h>` exists and `md5.c`'s endian shim compiles for both
      slices (the ppc slice has not been run).
- [x] `make install DSTROOT=<root>` installs `apk` to `<root>/sbin` via the
      project Makefile, in rbuild's chroot.
- [x] `sh apk-tools/tests/smoke.sh` passes natively, with the guest's GNU
      tar 1.12 building its package. pre12's form is `apk index <apks>` to
      stdout, and the script now fails unless the index names the package.
- [x] The explicit applet table (`apk_applets[]` in `apk.c`) links with
      Rhapsody's cctools ld for both slices (`lipo`: `ppc i386`), and the i386
      slice runs: `apk` prints its applet list.
