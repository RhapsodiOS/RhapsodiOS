# rbuild architecture policy and native verification

## Source labels and operations

| Source Architecture | Ordinary build | Thin bootstrap/kernel operation |
| --- | --- | --- |
| Missing | i386 + PPC | Requested thin CPU |
| `universal-apple-rhapsody` | i386 + PPC | Requested thin CPU |
| `i386` or `i386-apple-rhapsody` | i386 | i386 only; PPC conflicts |
| `ppc` or `ppc-apple-rhapsody` | PPC | PPC only; i386 conflicts |
| Empty or any other value | Error | Error |

`all`, `any`, `universal`, and whitespace-separated CPU lists are not source
architecture labels. Existing legacy synthesis for incomplete control files
preserves a valid explicit architecture. Source control files are never
rewritten; each operation resolves a local package copy and emits canonical
`*-apple-rhapsody` metadata.

Ordinary `RC_ARCHS`, `RC_CFLAGS`, `RC_i386`, and `RC_ppc` reflect the resolved
architecture, independently of the host. Unselected RC switches are explicitly
empty. Ordinary builds leave project-specific `TARGETS` unset. Bootstrap
preserves the profile's compiler/sysroot flags and sets thin `TARGETS`.
`kernel` and `kerneldrivers` pass their explicit `--arch i386` or `--arch ppc`
selection through the same resolver.

## Probes and product checks

An uncached `all` or `binary` build probes every selected architecture before
any project make invocation, including `installhdrs`. Each probe uses a fresh
private directory below OBJROOT, the selected make/chroot/compiler environment,
and actual build flags. Compile and link results must contain the exact
requested Mach-O CPU. A successful command with no output, wrong CPU, malformed
code, or missing runtime fails. Diagnostics identify the CPU and compile,
link, or inspection stage. Outputs are inspected, never executed; there is no
fallback to the host CPU.

Ordinary probes always link. Bootstrap always compiles and links when the
profile's `ld_flags_ready` is absent (default ready) or its expanded marker
exists. An explicitly configured marker that does not yet exist allows
compile-only stage-zero probing. Headers-only builds skip probes; the legacy
`local`/`objs` operations do not acquire new compilation. Dry-run plans checks
and commands without creating private directories or running tools.

Before any package metadata is written, installed/header/object roots and
staged maintainer files are inspected. Ordinary Mach-O files and static
archives must match exactly; scripts, headers, and other data are neutral.
Symlinks are not followed by the product walker. Missing optional header/object
trees are allowed; the installed product root must exist.

Only harvested `usr/local/lib/objs/<source>/.../dynamic_obj/...` collections
allow CPU coverage across separate objects. CPU directory buckets are grouped
by source and remaining variant path; different source filenames may occur in
each CPU bucket. Without such buckets, `.i386.o` and `.ppc.o` pair by the same
base path. Directory CPU, filename suffix, and object contents must agree.
Coverage cannot be borrowed from another source or build variant. Code outside
these collections must itself contain the required architectures.

## Cached APKs, dependencies, and completion state

APK use pins an immutable private copy, validates tar members and identity,
extracts privately, checks products, then optionally merges that same stage.
Exact reuse requires the expected name/version, canonical architecture label,
and matching payload. Existing companion header/object APKs must also validate;
absent optional companions do not prevent reuse. Dependency selection validates
code against the package's own declared architecture first, then checks that it
covers the consumer. Thus a valid universal code dependency can serve a thin
consumer, thin code cannot serve a universal consumer, and data-only packages
remain neutral. Thin aliases are accepted for dependency metadata. Incompatible
candidates do not hide later compatible candidates in the same or later
repository. The existing direct/build-base dependency expansion is unchanged;
this is not a new transitive dependency solver. Basename-only package-list
entries do not prove installed architecture, so selected dependencies are
validated and installed again.

Incompatible cache files are quarantined as `.invalid` before rebuilding or
publication, including direct/forced publication collisions and symlinks.
An existing quarantine file is preserved; when safe quarantine is refused the
build fails instead of overwriting it. `missing` performs readonly inspection,
retains any-version matching, reports incompatible artifacts as needing a
build, and returns nonzero for source scan errors. Its private inspection stage
is discarded; source and repository files are not changed. Dry-run treats
cache entries as unavailable and does not stage or quarantine them.

Package filenames remain version-based, for example `rbpbtool-1-1.apk` and
`rbpbtool-obj-1-1.apk`. Keep universal and thin variants in separate destination
repositories.

Bootstrap completion records use `format=3`, `architecture_policy=1`, and the
canonical `effective_architecture`. The entry fingerprint includes policy and
effective architecture. Existing known older formats or missing/wrong policy
markers force rebuilding for both `headers` and `all`; no record still permits
validated seed APKs to establish state. Mandatory corruption, changed profile
or toolchain fingerprint, and a mismatched current entry fingerprint remain
errors requiring the existing `-Fresh` workflow. State publication stays atomic.

## Repository bootstrap

Live repository bootstrap is a three-walk sequence driven by the host
`-Bootstrap` phase:

1. **Thin bootstrap** — `rbuild bootstrap` with the profile's thin
   `target_arch` walks the full `BootstrapManifest` once. This stages the
   profile CPU, build tools, and the thin sysroot marker required by the
   universal walk.
2. **Universal runtime bootstrap** — `rbuild bootstrap-universal` loads the
   sibling `BootstrapRuntimeManifest` beside the caller's manifest and walks
   Csu through Libsystem with `RB_ARCH_UNIVERSAL`.
3. **Universal full manifest** — the same `bootstrap-universal` invocation
   then walks the caller-supplied full `BootstrapManifest`.

Per-CPU link readiness applies on every walk: rbuild compiles every requested
CPU slice, but links a CPU only when the sysroot already provides that slice's
`crt1.o` and `System` framework. Until both exist, compile-only probing is
allowed. No `golden.img` seeds or other read-only guest image inputs are used;
bootstrap products come only from the synced source tree and resumable state.

Kernel, kernel drivers, and world (`buildall`) are out of scope for bootstrap.
The host orchestrator runs them in separate phases after bootstrap completes.

## Verification environment and scope

The 2026-09-12 acceptance run used implementation commit
`99b23feb2b314ebddc6990ad3c358c42f2d25d5f`. The guest is Rhapsody 5.6 PPC with Apple cc-783.1 (GCC 2.7.2.1). Tests use independently
named directories under `/tmp/rbuild-universal-*`; no canonical guest runtime,
boot image, or golden image is modified, and no produced target executable is
run.

The private framework template contains original pb_makefiles rules and guest
helper binaries, both compiler backends, and a fat runtime assembled solely for
these fixtures from readonly original i386 image inputs and native PPC files.
The x86 startup object has i486 subtype, which is the i386 CPU family. This
proves compile/link and package architecture, not runtime execution compatibility.

Tool and STATIC Library fixtures use `tool.make` and `library.make`, including
the real per-architecture object, lipo, link, libtool, strip, and install rules.
They explicitly set `OFILE_DIR=$(OBJROOT)/dynamic_obj` to exercise rbuild's
legacy harvest layout; the framework's normal `objects$(OFILE_DIR_SUFFIX)`
default is not automatically harvested. Their headerless sources and explicit
empty `Build-Depends` use a prepopulated private fixture SDK. This does not
establish that the full repository dependency closure or entire OS builds
universally. The single-entry library manifest is deliberate: ordinary
buildall cleans its build root after each entry.

Prepared environment provenance is in the local, untracked files
`D:/RhapsodiOS/vm/_rbuild-universal-runtime-evidence.md` and
`D:/RhapsodiOS/vm/_rbuild-universal-runtime/framework-evidence.md`.
The earlier `initial-rbuild-evidence.md` describes Tasks1-5 only and is not final
acceptance for probes or state migration.

## Fixture acceptance matrix

The table below records the 2026-09-12 bounded fixture run. It is acceptance
evidence for rbuild's architecture policy and probe behavior, not evidence that
the live repository bootstrap path above has completed on a guest.

Current rbuild was compiled natively in
`/tmp/rbuild-universal-final-20260912/src/rbuild-1`. The full command was:

```powershell
powershell -NoProfile -File D:/RhapsodiOS/vm/_rbuild-universal-test.ps1 `
  -RemoteDir /tmp/rbuild-universal-final-20260912 `
  -TestCommand 'gnumake test trace-test'
```

Result: **1,835 checks, zero failures**, bootstrap-resume PASS, bootstrap
closure PASS, and TRACE MATCH. Trace comparison preserves the legacy two
spaces before the ordinary CFLAGS defines; neither CPU values nor spacing are
normalized away. The separate i386 fixture checks complete CFLAGS, both RC
switches, per-CPU probe plans, and absence of dry-run build roots.
The local full log is
`D:/RhapsodiOS/vm/_rbuild-universal-runtime/final-native-tests.log`.

Real framework builds used the separate acceptance base
`/tmp/rbuild-universal-acceptance-20260912` (abbreviated `$base` below), and
`$framework=/tmp/rbuild-universal-framework-20260912`.
Every row received a new copy of `$framework/framework-template`, never the
template itself. Repeated invocations used the resulting APKs after ordinary
cleanup removed the disposable build root.

| Actual operation | APKs (version `1-1`) | Verified result |
| --- | --- | --- |
| Tool `buildpackage --target all`, then repeat | `tool-apks/rbpbtool-1-1.apk`, `rbpbtool-obj-1-1.apk` | Canonical universal metadata; executable i486 + PPC; repeat reused validated cache |
| Single-library `buildall`, then repeat | `library-apks/rbpblib-1-1.apk`, `rbpblib-obj-1-1.apk` | Canonical universal metadata; static archive i386 + PPC; repeat reused validated cache |
| Explicit-i386 Tool `buildpackage --target all` | `thin-apks/rbpbthin-1-1.apk`, `rbpbthin-obj-1-1.apk` | Canonical i386 metadata; executable i486, object i386; no PPC probe |
| Universal Tool with private PPC-only System framework | No APKs | i386 compile succeeded; i386 link failed before project make or any `.PKGINFO` |

All six APKs passed the current `apk_use_arch` exact metadata/payload validator
through a small native inspection utility linked against the current rbuild
objects. Extracted metadata was checked independently. The production Mach-O
reader and guest `lipo -info` agreed on each installed binary/library and object.
Universal object APKs contained `main.i386.o`, `main.ppc.o`, and fat `main.o`
under `usr/local/lib/objs/pbtool/dynamic_obj`; the library contained the
corresponding `value` files under `objs/pblib/dynamic_obj`. Thin `main.o` under
`objs/thin/dynamic_obj` was i386. i486 executable subtypes count as i386, not a
third architecture. No produced target program was executed.

The exact per-row environment was generated by this shell function (`label`
was `tool`, `library`, `thin`, or `missing-runtime`):

```sh
BUILDROOT=$base/$label-root
if test -e "$BUILDROOT"; then exit 1; fi
mkdir "$BUILDROOT"
cp -Rp "$framework/framework-template/." "$BUILDROOT"
SRCROOT=/src/accept-$label
OBJROOT=/obj/accept-$label
SYMROOT=/sym/accept-$label
DSTROOT=/dst/accept-$label
HDRROOT=/hdr/accept-$label
LIBCOBJROOT=/cobj/accept-$label
PACKAGEROOT=/pkg/accept-$label
SUBLIBROOTS=/usr/local/lib/objs
TMPDIR=$base/compiler-tmp
mkdir -p "$TMPDIR" "$BUILDROOT$TMPDIR" "$base/$label-repo" "$base/$label-apks"
export BUILDROOT SRCROOT OBJROOT SYMROOT DSTROOT HDRROOT LIBCOBJROOT
export PACKAGEROOT SUBLIBROOTS TMPDIR
rbuild=/tmp/rbuild-universal-final-20260912/src/rbuild-1/rbuild
```

Commands, after setting the corresponding fresh environment:

```sh
"$rbuild" buildpackage --dir --target all "$framework/src/rbuild-1/pbtool-1" \
  "$base/tool-repo" "$base/tool-apks"
# Repeated identically: "already exists; not building", with no probe commands.

printf 'dir %s all\n' "$framework/src/rbuild-1/pblib-1" > "$base/library.manifest"
"$rbuild" buildall "$base/library.manifest" "$base/library-repo" "$base/library-apks"
# Repeated identically: "already have", with no probe commands.

# thin-1 is a private copy of pbtool-1 with Package: rbpbthin and Architecture: i386.
"$rbuild" buildpackage --dir --target all "$base/thin-1" "$base/thin-repo" "$base/thin-apks"
```

For the negative row, only the copied runtime was changed:

```sh
cp /System/Library/Frameworks/System.framework/Versions/B/System \
  "$BUILDROOT/System/Library/Frameworks/System.framework/Versions/B/System"
"$rbuild" buildpackage --dir --target all "$framework/src/rbuild-1/pbtool-1" \
  "$base/missing-runtime-repo" "$base/missing-runtime-apks"
```

Guest lipo confirmed that copied System was PPC-only. The linker reported a
PPC/i386 CPU mismatch and unresolved `_errno`/`_exit`; rbuild reported
`i386 toolchain probe failed during link`. Assertions checked no project
`installhdrs` invocation, APK, or product `.PKGINFO`. The original template,
canonical guest System framework, and golden image were unchanged.

Guest evidence is preserved beneath `$base`: `tool-build.log`, `tool-reuse.log`,
`library-build.log`, `library-reuse.log`, `thin-build.log`, `missing-runtime.log`,
the APK directories, and `extracted-*` directories. Local inspection summary
and combined build logs are
`D:/RhapsodiOS/vm/_rbuild-universal-runtime/final-acceptance.log` and
`D:/RhapsodiOS/vm/_rbuild-universal-runtime/final-acceptance-build-logs.log`. The complete guarded script and text-upload
runner are in the untracked local directory
`D:/RhapsodiOS/vm/_rbuild-universal-acceptance` (`src/rbuild-1/final-acceptance.sh`,
`run.ps1`). Use a newly named acceptance base before repeating. Binary CPIO
transport retries failed before execution; the successful run uploaded only
that script using text-encoded chunks. The matrix ended
`CURRENT_RBUILD_ACCEPTANCE_PASS`, exit zero.

The original framework emitted its known minimal-chroot javaconfig warnings
and ignored initial chmod errors on not-yet-installed products; those remain
visible in the logs. Controlled bootstrap behavior is additionally exercised
by `test_toolchain_probes` and bootstrap-resume's real PPC compiler probes.
`test_kernel_architecture_controls_build_commands` verifies kernel/driver
architecture propagation and early conflicts using command fixtures. These
are not claims that a real kernel, complete SDK, or full OS was built.
