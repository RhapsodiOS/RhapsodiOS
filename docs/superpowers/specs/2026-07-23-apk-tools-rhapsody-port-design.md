# apk-tools 2.0_pre12 — Rhapsody port (host-proxy portability pass)

**Date:** 2026-07-23
**Status:** Design approved, pending implementation plan

## Summary

Port Alpine's `apk-tools` 2.0_pre12 (already vendored at
`src/apk-tools-1/apk-tools/`) so it builds and runs on Rhapsody, giving the
system a native apk package manager to replace dpkg's install/query/remove
role. Validation is done via a **host-proxy build** — portability is fixed and
proven on the dev host (approximating the Rhapsody toolchain), and the final
build plus `apk` smoke-tests on real Rhapsody are performed by the maintainer.

This is the **first** sub-project of the larger "minimal apk switchover." It
does not attempt the full migration.

### Context / current state

- `src/apk-tools-1/apk-tools/` — Alpine apk-tools 2.0_pre12, ~7,144 LOC C,
  `VERSION := 2.0_pre12`. Vendored as-is; not yet built in the tree.
- `src/apk-tools-1/dpkg/control` — the project already carries a Debian control
  file (so `rbuild`/`darwin-buildall` would package it), but it lacks a
  RhapsodiOS project Makefile to drive the standard build.
- `rbuild` (branch `rbuild-c89`) already produces `.apk` files and extracts them
  with `gzip | tar`; it does **not** depend on the `apk` binary. The `apk`
  binary's role here is the **system package manager**, not the build tool.
- Rhapsody's C compiler is Apple `cc` (v783.x / `cc-791`), an Apple gcc
  2.95.2-based toolchain. It accepts apk-tools' GNU C idioms (`.field =`
  designated initializers, `//` comments, mixed declarations, `typeof`,
  `__attribute__`) as GNU extensions.

## Reconnaissance findings (the assessment)

The "assess first" step is captured here; the port is small and well-characterized.

- **No `*at()` syscalls** (`openat`/`unlinkat`/`fchownat`/…) — the hardest Darwin
  gap is absent.
- **No** `mount`/`statfs`/`statvfs`/`mntent` usage.
- **No glibc-only functions**: none of `strchrnul`, `memmem`, `mempcpy`,
  `error`, `argp`, `asprintf`, `getline`, `qsort_r`, `canonicalize_file_name`.
- External libraries: **only zlib** (2 includes). apk-tools ships its **own MD5**
  (`md5.c`). No OpenSSL, no libfetch/libcurl — `url.c` fetches by shelling out
  (fork/exec) on `http:`/`https:` prefixes.
- Linux-ism inventory:
  - `<malloc.h>` — **9 files** (`apk_defines.h`, `apk_hash.h`, `io.c`, `state.c`,
    `database.c`, `gunzip.c`, `package.c`, `archive.c`, `blob.c`).
  - `<endian.h>` — **1 file**.
  - `<getopt.h>` — **3 files** (long options).
  - `mknod` — **2 call sites** (device-node extraction; BSD-available).
  - `fnmatch` — **2 call sites** (POSIX).
- GNU extensions used: `typeof` (8), `__attribute__` (2) — fine on Apple gcc 2.95.
- Build system: `Makefile` + `Make.rules` + `src/Makefile`, parameterized by
  `DESTDIR`/`SBINDIR`/`INSTALL`/`INSTALLDIR`. **No** pkg-config, rpath, or
  shared-object (`.so`) assumptions. Installs a single `apk` binary to `SBINDIR`.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Cycle scope | Only the apk-tools port; bootstrap/repo/docs deferred | Smallest coherent step; downstream depends on a working `apk`. |
| Validation | Host-proxy build; maintainer does final build + smoke-test on Rhapsody | No reachable Rhapsody environment here; host approximates the toolchain. |
| Source style | Keep it GNU C; do **not** C89-ify | Apple's cc 2.95 accepts the GNU idioms; rewriting is churn with no benefit. |
| Fix strategy | Small compat shims over invasive rewrites | Minimize divergence from upstream apk-tools; easier to reason about. |
| `rbuild` / `dpkg/control` | Untouched | Minimal-switchover decision; out of scope. |
| Unresolvable-on-host items | Logged as a target-validation checklist, not guessed | Honest about what the proxy cannot prove. |

## Approach

A host-proxy portability pass on `src/apk-tools-1/apk-tools/`:

1. Attempt to build on the dev host with flags approximating Apple gcc 2.95
   (`-std=gnu89` plus warnings) and `zlib` linked; capture and triage the errors.
   This triage **is** the empirical assessment.
2. Fix portability by category (see Work Items), preferring a single shared
   compat header over scattered edits where practical, and matching upstream
   style.
3. Produce a working host `apk` binary; smoke-test format-level operations that
   need neither root nor a live install DB.
4. Add a RhapsodiOS project Makefile so the standard build flow builds apk.
5. Record everything the host proxy could not prove as a target-validation
   checklist for the Rhapsody build.

## Work items

1. **`<malloc.h>` → `<stdlib.h>`** across the 9 files. Prefer a single
   `apk_compat.h` (included where `malloc.h` was) that pulls `<stdlib.h>` and any
   other shims, rather than 9 independent edits — but a direct swap is acceptable
   if cleaner.
2. **`<endian.h>` shim** (1 file): provide the byte-order macros the file uses
   via a portable path (Darwin `<machine/endian.h>` / `<architecture/byte_order.h>`),
   guarded so Linux still works.
3. **Verify host availability** of `getopt_long` (`<getopt.h>`), `mknod`,
   `fnmatch`, and `zlib`; fix includes/links as needed. Note for the target any
   that may need the tree's own headers on Rhapsody.
4. **apk-tools build system**: confirm `make` + `make install` produce a working
   `apk` with `DESTDIR`/`SBINDIR`; adjust only what blocks the host build.
5. **RhapsodiOS project Makefile** at `src/apk-tools-1/Makefile`: implement the
   standard targets (`install`, `installhdrs`, `installsrc`, `clean`) used by the
   build flow (`rbuild` → `chroot make install DSTROOT=…`), mapping `DSTROOT` to
   apk-tools' `DESTDIR` (and appropriate `SBINDIR`), mirroring sibling projects
   (compare `src/buildtools-2/Makefile`).

## Verification

### Host (proxy)

- `apk` compiles and links clean under the proxy flags with `zlib`.
- Smoke tests requiring neither root nor a live system, e.g.:
  - `apk version` / version-comparison operations;
  - `apk index` over a couple of `.apk` files produced by `rbuild`;
  - `apk` extraction of an `rbuild`-produced `.apk` into a scratch root,
    confirming `apk` agrees with rbuild's `.PKGINFO` + gzip-tar layout.
- (These confirm apk and rbuild are format-compatible — the practical payoff.)

### Target (maintainer, on Rhapsody)

- Documented steps to build `apk` on Rhapsody via the standard flow.
- A **target-validation checklist** of what the host proxy could not prove:
  old-gcc acceptance of the GNU C idioms, `getopt_long`/`mknod`/`fnmatch`
  availability in Rhapsody's libc/headers, and the smoke tests re-run natively.

## Deliverables

- Portability patches under `src/apk-tools-1/apk-tools/` (compat shims + minimal
  Makefile tweaks), kept close to upstream.
- `src/apk-tools-1/Makefile` — RhapsodiOS project wrapper for the standard build.
- `src/apk-tools-1/PORTING.md` — what changed, why, and the target-validation
  checklist.

## Out of scope (deferred to later cycles)

- The apk-based bootstrap chain (how `apk` first gets installed — the
  chicken-and-egg), converting the released package repository `.deb` → `.apk`,
  and updating `README.md`/build docs.
- Migrating the 82 source `dpkg/control` files to an apk-native metadata format.
- Retiring `dpkg-3` / `dpkg_scriptlib-1`.
- Any change to `rbuild`.
