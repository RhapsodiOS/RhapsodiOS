# Dual-architecture build environment

The sources and Project Builder metadata are architecture-neutral. Build PowerPC
and i386 separately so each result and its intermediate files remain attributable
to one target:

```sh
APP=src/Applications/Administration/ProcessViewer
OUT=tools/binrecon/out/processviewer-build
make -C "$APP" RC_ARCHS=ppc \
  OBJROOT="$OUT/ppc/objects" SYMROOT="$OUT/ppc/products"
make -C "$APP" RC_ARCHS=i386 \
  OBJROOT="$OUT/i386/objects" SYMROOT="$OUT/i386/products"
make -C "$APP/tests" ARCH_FLAGS='-arch ppc'
make -C "$APP/tests" ARCH_FLAGS='-arch i386'
```

The corresponding app products are expected at
`$OUT/{ppc,i386}/products/ProcessViewer.app/ProcessViewer`. The makefiles use the
repository's `app.make` rules, which include `wrapped-common.make`, and do not
hard-code a CPU in source or compiler flags. `Makefile.postamble` copies the
complete source `Resources/` tree into each product after linking, preserving
the original NIB subdirectories and archive bytes.

## Environment observed 2026-10-01

- The host has QEMU 11.1, Python 3.13, and Clang at
  `C:\Program Files\LLVM\bin\clang.exe`. Its `make` command is a Windows shim
  and does not provide the Project Builder toolchain.
- A private Rhapsody DR2 `RELEASE_I386` QEMU guest was launched against
  `vm/work/rhap-i386-bootstrapped.img` with `-snapshot`; the shared base image
  and other guests were left untouched. The repository guest-remote helper
  provides shell access. `/usr/bin/cc` is GNU compiler version 2.7.2.1; no
  `make` or `gnumake` was found at the checked paths. Eight focused targets
  (`abi-i386`, `process`, `process-types`, `table`, `controller`, `inspector`,
  `arguments-live`, and `process-live`) compiled and exited 0, including live
  table/sysctl and two-scan process enumeration with stale-process removal.
  A direct full-source link also produced a Mach-O i386
  executable, confirmed by `/usr/bin/file`. The executable and resource tree
  were staged as `ProcessViewer.app`. Launching that bundle and a minimal bundle
  whose only behavior is `NSApplicationMain` both ended with SIGBUS after the
  headless guest logged that it could not connect to the distributed
  notification server. This does not verify GUI integration or establish a
  ProcessViewer-specific launch defect.
- The former PowerPC build host at `10.10.0.241` refuses SSH on port 22. The
  private DR2 i386 guest's GCC 2.7.2.1 accepts `-arch ppc`, and its compiler
  and linker can build PPC when given an appropriate sysroot. A local DR2 PPC
  installer toast was inspected read-only; its UFS partition contains the
  matching-era AppKit, Foundation, and System frameworks, `/lib/crt1.o`, and
  `/usr/lib/libcc_dynamic.a`. Those files were extracted into a temporary
  sysroot (not the source tree), transferred to `/tmp/ppc-sdk` in the
  disposable guest, and used to compile all six application `.m` files with
  `cc -arch ppc -O` and link a full PPC Mach-O executable. The staged bundle
  has the 13 resources. The latest PPC executable is 69,480 bytes with SHA-256
  `3d6f27b63b8b7b1081b0dfe8e31671ea880fba42164f42a1d1ae6f7e7e022e5a`. Both
  PPC and i386 application builds were rerun after the source updates.
- A local 8 GiB Apple partition-map image labeled Mac OS X Server 1.2 and the
  DR2 PPC installer toast were also tried under QEMU `mac99`; neither yielded
  a usable PPC shell or SSH service. Thus PPC execution, deterministic tests,
  and GUI launch have not been verified, despite the successful cross-build.

Direct i386 compilation proves the current source set links for that target;
the disposable guest confirms bundle staging but cannot verify GUI launch.
The recovered DR2 SDK allows a PPC executable link and bundle staging, but no
PPC runtime test has run. Binrecon's PPC normalized-function comparison fails
and must be treated as an open parity issue (1 assembly-matched, 125 differing,
and 5 unpaired function records in the latest 131-record report). The commands above document the
intended per-CPU Project Builder environment; the validated guest builds use
the equivalent direct compiler/linker commands because `make` is unavailable.
## Host syntax checks

Clang `-fsyntax-only` checks have been run for the reconstructed process,
process-type, UID-cache, and table/header sources and their focused tests with
PowerPC and i386 architecture macros. These checks use the host's 64-bit Clang
and temporary system-call declarations under ignored `tools/binrecon/out`; they
catch source/API syntax errors but do not test either 32-bit ABI, link framework
symbols, or execute the tests. Integer-to-pointer warnings in map-table keys and
the diagnostic pointer formatting are expected from the 64-bit host and still
require target-build review.



