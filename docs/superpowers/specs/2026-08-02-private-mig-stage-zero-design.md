# Private MIG Stage-Zero Design

## Problem

Kernel header generation invokes `mig -typed` before the bootstrap sysroot can
contain MIG.  The live Jaguar wrapper does not recognize `-typed` and searches
the incomplete sysroot for `migcom`.  Bootstrap therefore needs a complete MIG
toolchain outside both the host installation and target sysroot.

## Private tool layout

The existing rbuild phase will build these source-owned tools beneath its
configured `ToolsDir`:

- `bin/mig`
- `libexec/migcom`
- `libexec/migcom_typd`
- `libexec/migcom_untypd`

Generated yacc, lex, and object inputs live only below
`ToolsDir/mig-build/<project>`.  The rbuild phase removes and recreates exactly
`ToolsDir/mig-build`; it does not use `/tmp`, a live install root, or the
bootstrap sysroot.

The build also creates `ToolsDir/mig-build/include`, an explicit symlink
overlay containing only the source-owned Mach headers reached by the three MIG
compilers.  Every overlay input is preflighted and every link is declared by
name.  This avoids both a host header manifest and a broad `-I kernel-7`, which
would shadow 67 live `mach`/`mach_debug` headers on the verified Xserve.  The
overlay is recreated only as part of the already-scoped `mig-build` reset.

Each compiler executable comes from the configured `build_cc`.  Each project
uses its checked-in C source list, `/usr/bin/yacc`, `/usr/bin/lex`, and private
generated sources.  The untyped compiler also links its checked-in version
stub.  The repository wrapper is installed from `migcom.tproj/mig.sh`; no live
MIG artifact is copied.

The classic sources use standard C varargs so GCC 3 and later can compile
them.  Classic and typed diagnostic formatting uses `strerror` instead of the
obsolete `sys_errlist`/`sys_nerr` tables.  These are build-host portability
updates only; generated interface behavior and error text shape remain
unchanged.

## Wrapper binding

`mig.sh` accepts `MIGCC` and `MIGCOM_DIR` overrides.  When supplied, it invokes
`MIGCC -E` and selects `migcom`, `migcom_typd`, or `migcom_untypd` only beneath
`MIGCOM_DIR`.  It forwards `-i` and its argument to the selected compiler.

When these overrides are absent, the wrapper retains its historical compiler,
architecture-specific preprocessor, and `/usr/libexec` defaults so the source
remains usable when later packaged into the target.

The bootstrap command always supplies both overrides with the configured
build compiler and private libexec directory.  Its toolchain profile PATH
already begins with `ToolsDir/bin`, so kernel `installhdrs` selects private
`mig`.  The variables are inline on the bootstrap rbuild invocation and do not
alter other phases or the live host.

## Validation

PowerShell command-generation tests cover default, alternate compiler, and
space-containing source/tool paths.  They require all private build products,
explicit bootstrap bindings, `-typed` selection, and `-i` forwarding.  They
forbid `/usr/bin/mig`, live `/usr/libexec` selection in stage zero,
`NEXT_ROOT`/sysroot MIG lookup, live executable copying, and `DSTROOT=/`.

Preflight checks every required project source plus yacc and lex.  Local tests,
PowerShell parsing/import, POSIX shell syntax, and `git diff --check` complete
the focused verification.  The full bootstrap is intentionally not run.

Each backend also emits a dependency file using its real compile flags.  The
rbuild phase rejects dependencies beneath live `/usr/include/mach` or the
bootstrap sysroot, proving that target protocol definitions came only through
the private source-owned overlay while normal host libc headers remain host
headers.
