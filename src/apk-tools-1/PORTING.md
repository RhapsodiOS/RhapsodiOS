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
- Project build (`src/apk-tools-1/Makefile`): replaced the `GNUSource.make`
  include (which requires a `configure` script apk-tools doesn't have, and
  never passes `DESTDIR`) with a small recursive wrapper that maps the
  standard `DSTROOT`-based `all`/`install`/`clean` targets onto
  `apk-tools/`'s own `DESTDIR`/`SBINDIR`-based Makefile
  (`make -C apk-tools install DESTDIR=$(DSTROOT)`).
- Host smoke tests (`apk-tools/tests/smoke.sh`): added a no-root,
  format-level smoke test that builds a minimal rbuild-style `.apk`
  (`.PKGINFO` + file, gzipped tar), runs `apk index` over it (tolerating
  CLI-form variance and WARNing rather than failing if unrecognized), and
  round-trips extraction via `gzip | tar` to confirm the on-disk layout apk
  and rbuild agree on.

## Target-validation checklist (verify on Rhapsody)

- [ ] Apple `cc` (gcc 2.95.2) accepts the GNU C idioms used (designated
      initializers, `//` comments, mixed declarations, `typeof`,
      `__attribute__`) — build `cd apk-tools && make`.
- [ ] `getopt_long`/`<getopt.h>`, `mknod`/`makedev`, `fnmatch`/`<fnmatch.h>`
      resolve against Rhapsody's libc/headers.
- [ ] zlib is available; set `LIBS` if not `-lz` (e.g. the tree's libz path).
- [ ] `Make.rules`'s `-Wp,-MD,$(depfile) -MT $@` dependency-flag form is
      accepted by gcc 2.95's cpp (`-Wp,`/`-MT` handling was not verified
      against that toolchain — only against the host's gcc/clang).
- [ ] `<machine/endian.h>` exists and exposes `BYTE_ORDER`/`LITTLE_ENDIAN` on
      Rhapsody (used by `md5.c`'s endian shim).
- [ ] `make install DSTROOT=<root>` installs `apk` to `<root>/sbin` via the
      project Makefile (`src/apk-tools-1/Makefile`), in a real chroot/DSTROOT
      environment (not just the host recursive-wrapper proxy).
- [ ] `sh apk-tools/tests/smoke.sh` passes natively; in particular confirm the
      `apk index` CLI form for pre12 (the host script WARNs if unrecognized).
- [ ] Confirm the explicit applet table (`apk_applets[]` in `apk.c`) links
      correctly on Rhapsody's cctools ld for both the i386 and ppc slices of
      a fat binary — no linker-section (`__start_`/`__stop_`, or
      `section$start$`/`section$end$`) support is required any more.
