# darwin-build: separate C replacement for the Perl build tools

Date: 2026-09-07

Status: Design approved on 2026-09-07, with CVS support explicitly removed.
The user selected a separate C replacement instead of extending the existing
`rbuild` application. This document describes the agreed design; the current
request covers planning, not implementation.

## Objective and decisions

Create one maintainable C command-line application that replaces
`darwin-buildpackage`, `darwin-buildall`, `darwin-missing`, and the Perl modules
that implement their behavior. The application is named `darwin-build`, in a new
project at `src/darwin-build-1/`.

The approved decisions are:

- Keep dpkg `.deb` input/output and existing `dpkg/control` metadata.
- Target C89 plus the POSIX interfaces available on Rhapsody DR2 and Mac OS X
  Server 1.x, on i386 and PPC. Windows is the editing host, not a runtime target.
- Provide a terminal application with good help, consistent diagnostics,
  useful progress, and an end-of-run summary. A graphical interface is outside
  this plan.
- Support local directories only; keep optional `--dir` for compatibility.
  Reject `--cvs` and `cvs` manifest entries with a clear removed-support error
  before source inspection or build side effects. Do not port CVS metadata
  queries, tag handling, checkout/update operations, or timestamp versions.
  Do not inherit `rbuild`'s APK format, bootstrap runner, or current PPC policy.
- Retain external `dpkg-deb`, `make`, `chroot`, `rsync`, and ordinary
  filesystem utilities. Removing Perl from orchestration does not remove
  dependencies of the projects being built.

Success means that the new application can build representative packages
without a Perl interpreter, produce equivalent Debian metadata and payloads,
and run manifests through either its new interface or the old command names.

## What exists today

These paths are relative to the repository root.

| Source | Responsibility |
| --- | --- |
| `src/buildtools-2/tools/darwin-buildpackage.pl` | Parse single-package arguments and invoke the engine. |
| `src/buildtools-2/tools/darwin-buildall.pl` | Read a manifest, skip available packages, and invoke builds. |
| `src/buildtools-2/tools/darwin-missing.pl` | Report absent packages without building. |
| `src/buildtools-2/lib/Builder.pm` | Naming, defaults, CVS, dependency extraction, build roots, make invocation, object harvesting, and Debian package creation. |
| `src/buildtools-2/lib/Manifest.pm` | Read a manifest file or enumerate a source directory. |
| `src/dpkg_scriptlib-1/perl5/Dpkg/Package/Package.pm` | Parse and emit control fields and construct package identities. |
| `src/rbuild-1/` | Existing C89 replacement using APK; useful reference, separate product. |

`Builder.pm` imports `Dpkg::Package::List` without using its interfaces. Port
only the package and manifest functionality actually reached by these tools;
the rest of `dpkg_scriptlib-1` is outside scope.

The July 23 `rbuild` design already describes an APK conversion. This document
does not supersede it. `README.md` and `src/Manifest` still reference the Perl
tools, while the current remote build driver uses `rbuild`. These are separate
integration paths and must not be silently switched together.

## Approaches considered

1. **One C executable with subcommands and optional old-name aliases —
   recommended.** A single interface and implementation, with compatibility
   dispatch based on the executable name. It supports gradual adoption while
   keeping the engine small.
2. **Three executables linked to common C modules.** Close to the existing
   scripts and straightforward to package, but maintains three entry points
   and makes consistent help and reporting harder to maintain.
3. **Fork `rbuild` and replace its APK paths with dpkg.** Reuses more initial
   code, but requires separating bootstrap, artifact validation, toolchain,
   architecture, and resume assumptions. That is a larger compatibility audit
   than a focused port of the Perl engine.

Use `rbuild` to inform string ownership, process handling, and tests. Do not
link the new tool to its application modules or copy the entire engine.

## Interface

```text
darwin-build package [--dir] [--target TARGET] SOURCE REPOSITORY DSTDIR
darwin-build all MANIFEST_OR_DIRECTORY REPOSITORY DSTDIR
darwin-build missing MANIFEST_OR_DIRECTORY DSTDIR
darwin-build --help
darwin-build --version
```

`package` defaults to directory sources and target `all`. Accept options in
any order before positional arguments, support `--` as the option terminator,
and report missing values and unknown options before creating build roots.

`--verbose` adds commands and resolved parameters to normal stage messages.
Child build output remains visible; diagnostics go to stderr. Manifest builds
end with counts and names for built, skipped, and failed entries. Keep missing
package records on stdout without a success banner so they remain scriptable.

The compatibility dispatch maps these names to the same code:

| Invocation name | Action |
| --- | --- |
| `darwin-buildpackage` | `package`, accepting `--dir` and the supported target options; rejecting `--cvs`. |
| `darwin-buildall` | `all`. |
| `darwin-missing` | `missing`, using the historical two positional arguments. |

Exit 0 means the requested operation completed successfully. Exit 1 means a
usage, scan, dependency, build, package, or filesystem failure. `all` continues
after an individual entry fails and returns 1 if any failed. `missing` returns
0 when it successfully reports absent packages, but 1 on an inspection error.
Exact historical prose and false-success exit codes are not compatibility
requirements.

Do not add a GUI, interactive wizard, parallel scheduler, dependency solver,
new manifest format, configuration language, or persistent resume database.
Defer dry-run mode: output-dependent packaging needs a separate definition
before a no-side-effects promise would be reliable.

## Compatibility contract

### Preserve

- Package identity: `<package>_<version>_<architecture>.deb`, including
  source-directory revisions and the existing naming transformations.
- Read the first control paragraph, fold continuation lines, and emit the
  fields used by the Perl package object in its established order. Preserve
  the difference between absent and explicitly empty `Build-Depends`.
- Generate default metadata when the control file is absent. Keep the
  architecture label `universal-apple-rhapsody` and the historical two-arch
  make flags, including `RC_ARCHS`, `RC_CFLAGS`, and the Rhapsody defines.
- Preserve `BUILDIT_DIR` and the root-variable overrides from `getparams`.
  Store host paths and paths inside the chroot separately, resolving relative
  inputs from the invocation directory before starting any subprocess.
- Search repositories in `[destination, seed]` order. Expand the exact Perl
  `build-base` list, deduplicate it, and extract dependencies with `dpkg-deb -x`.
  Preserve `var/adm/package-list` as the build-root extraction record.
- Preserve the legacy distinction between any-version availability in
  `all`/`missing` and exact artifact checks in the single-package engine.
  This port does not redefine availability as an up-to-date build cache.
- Preserve manifest file order and relative-path interpretation for `dir`
  entries. Reject unsupported source types while validating the complete
  manifest, before any package in that invocation starts building.
- Run `installhdrs` and `install` under the same chroot environment and root
  assignments as the Perl engine. Keep its `UNAME_SYSNAME` and build-time PATH.
- Emit base, `-hdrs`, and `-obj` packages. The base package provides,
  conflicts with, and replaces its header package. Omit empty optional
  packages and retain `dynamic_obj` harvesting under `/usr/local/lib/objs`.
- Put `control`, `conffiles`, and available maintainer scripts in `DEBIAN/`.
  Remove `System/Developer/Source` only from the staged payload, as before.
- Preserve successful manifest-build cleanup and standalone-build retention;
  retain failed roots for diagnosis.

### Deliberate corrections to specify in tests

1. **Targets:** support `all`, `headers`, and the already implemented `binary`
   target. The Perl help advertises `objs` and `local`, but neither executes
   the build/package branches. Reject these before side effects, explaining
   that object packages accompany `all`/`binary` and `local` has no implemented
   action. Reject other unknown targets equally early. Apply this contract to
   manifests and aliases too; do not invent new target behavior during a port.
2. **Manifest parsing:** skip `.` and `..`, consider only child directories,
   and sort directory-mode entries bytewise. Reject malformed records with
   filename and line number rather than scanning an empty source. Require
   two or three fields; omitted targets mean `all`. Do not truncate long lines.
3. **Metadata:** distinguish missing control files from unreadable or malformed
   existing ones. Fail on malformed input instead of silently replacing it
   with synthesized metadata. Validate package identities before using them
   as output filenames. Diagnose unsupported dependency expressions rather
   than treating operators as package names.
4. **Repository ambiguity:** in the first repository containing a dependency,
   require one matching regular package file. If several match, print the
   candidates and fail rather than relying on directory enumeration order.
   Availability queries may still answer yes when several versions exist.
5. **Process and filesystem failures:** check child exits, signals, reads,
   writes, and close operations. Report the affected package and stage. Update
   `package-list` through a temporary file only after successful extraction.
6. **Permissions:** chmod only staged copies of maintainer scripts and
   `conffiles`, never the source files. Do not execute maintainer scripts as
   part of creating or comparing archives.
7. **Cleanup:** destructive operations must remain inside the resolved build
   or package staging directory and must reject `/` or a source/repository
   overlap. Do not follow symlinked directories during object discovery.
8. **Environment:** apply command-specific cwd/environment in the child; do
   not let one build's PATH or working directory leak into later manifest
   entries. Pass arguments directly rather than constructing `sh -c` strings.

## C organization and data flow

Keep fixed, explicit structs for package metadata, root paths,
target, and execution options. Each owning struct has init/free functions;
borrowed strings have documented lifetimes. No general object system or
plugin backend is needed.

| Module | Responsibility and dependencies |
| --- | --- |
| `main.c` | Parse CLI/aliases and dispatch; depends on the build and manifest APIs. |
| `util.c/.h` | Owned strings, lists, line reading, and small path helpers; libc/POSIX only. |
| `process.c/.h` | argv execution, child cwd/environment, and decoded status; no build policy or output-capture API. |
| `package.c/.h` | Control fields, names, versions, and subpackage metadata; uses utilities. |
| `manifest.c/.h` | Manifest entries with file/line context; uses utilities. |
| `source.c/.h` | Local-directory scanning and source staging; uses package and process APIs. |
| `build.c/.h` | Root calculation, dependency lookup/extraction, make stages, object harvesting, and manifest results. |
| `deb.c/.h` | Staged `DEBIAN` metadata/scripts and `dpkg-deb --build`; uses package/process APIs. |

The build flow is: parse and validate -> inspect source metadata -> compute
package identities and roots -> check existing output -> resolve all required
dependencies -> prepare the build root -> stage sources -> run requested make
targets -> harvest objects -> write metadata -> build archives -> report and
clean up after success.

`missing` stops after scanning local metadata and checking repository
filenames. It launches no commands and does not write files. Manifest execution
repeats the shared package flow without sharing mutable cwd, source, or
command-environment state between entries.

Keep the native Makefile simple: `cc`, ordinary object compilation, and
`all`, `test`, `install`, `installhdrs`, and `installsrc` targets. Avoid
requiring C99, `getline`, `asprintf`, `getopt_long`, modern build generators,
or contemporary GNU utility options. Use modern compiler warnings and
sanitizers for host checks where available, with native target builds as the
portability authority.

## Staged implementation plan

All paths below are under `src/darwin-build-1/` unless stated otherwise.
Each stage should be a reviewable change with focused regression coverage.
The first stage defines expected behavior before translation begins.

### 1. Capture the Perl contract

Create `tests/fixtures/`, `tests/oracle/`, and `tests/compatibility.md`. Record
expected metadata, make arguments, package contents, and accepted divergences
for local sources; every supported target; absent, empty, and malformed
metadata; missing dependencies; cached artifacts; and multi-entry failures.

Run the unmodified Perl modules from an isolated module-layout overlay, as the
existing trace harness does. Use a disposable Rhapsody environment or process
stubs in a disposable root. A PATH-only shim is insufficient: the Perl engine
resets PATH and the existing rbuild trace harness can reach a real chroot.

Verify that fixtures reach the stage they claim to cover and capture real
process outcomes. Do not accept empty traces or suppress arbitrary failures.
Include rejection cases for `--cvs` and `cvs` manifest entries, including an
unsupported entry after a valid one. No CVS server, client, or repository
fixture is required.

### 2. Establish the C executable and process layer

Create `Makefile`, `main.c`, `util.c/.h`, `process.c/.h`, and the lightweight
C test harness. Add help, version, option validation, and alias dispatch.
Implement child cwd/environment changes without shell interpolation. Children
inherit stdout/stderr; no captured-output machinery is needed for this port.

Verify native compiler acceptance, CLI failures before side effects, argument
boundaries for spaces and shell metacharacters, child failure/signal handling,
and parent cwd/environment preservation. No build action needs to work yet.

### 3. Port metadata, manifests, and root calculations

Create `package.c/.h`, `manifest.c/.h`, and the pure portions of `build.c/.h`.
Port naming transformations and make/root flags from the Perl source, not the
APK variant. Cover malformed and multiline metadata, optional fields, source
suffixes, absolute/relative roots, environment overrides, and directory mode.

Compare control output and make argument values with the recorded contract.
Normalize only Perl hash iteration order where semantically irrelevant;
preserve whitespace inside flag values. Verify the original i386/PPC flags.

### 4. Port local-directory source handling

Create `source.c/.h`. Add local metadata scans and source copying.
Exclude `CVS/` during local copying as the Perl does; do not broaden source
exclusions silently. Keep command cwd changes local to the child process.

Verify local paths with spaces, absent or unreadable source directories,
copy failures, and two consecutive sources without state leaking between
them. Preserve the `CVS/` copy exclusion for local trees containing historical
administrative directories; it does not enable CVS operations.

### 5. Assemble dependencies and run builds

Complete dependency resolution, `build-base` expansion, extraction records,
root setup, `installhdrs`/`install`, and object harvesting in `build.c/.h`.
Resolve missing or ambiguous dependencies before extraction starts. Keep the
two repository priorities and the exact historical base package list.

Verify extraction and make failures stop that package, records update only
after successful extraction, repeated dependencies extract once, existing
records are respected, and nested object directories preserve their paths.
Include cleanup-boundary and source-permission regression cases.

### 6. Produce and compare real Debian packages

Create `deb.c/.h` and package integration fixtures. Build base/header/object
archives through the in-tree-era `dpkg-deb`. Preserve Debian control placement,
permissions, header replacement metadata, and omission of empty optional
packages. Create each archive at a temporary destination and publish its
canonical filename only after `dpkg-deb` succeeds.

Extract the Perl and C archives into separate scratch directories. Compare
control fields, file contents, modes, symlink targets, and numeric ownership
under equivalent test users. Do not require byte-identical `.deb` archives:
archive ordering and timestamps need not be identical. Fault injection must
leave no apparently complete final package after a failed archive command.

### 7. Complete orchestration and terminal presentation

Wire `package`, `all`, and `missing` through the shared engine. Add stage
messages, verbose command printing, the final manifest summary, and consistent
exit status. Preserve any-version versus exact-version availability as
specified; make the distinction visible in documentation and tests.

Verify a manifest containing a successful package, an existing package, and a
failing package. The final summary must match those results and exit nonzero.
Verify missing-source, invalid-target, and multi-version repository cases
through the executable as well as the module tests.

### 8. Validate native use and provide an explicit migration path

Create `README.md` and `dpkg/control` for the new project. Default `install`
installs only `/usr/bin/darwin-build` under `DSTROOT`, allowing coexistence with
Perl and `rbuild`. Provide a separate `install-compat` target that deliberately
installs old-name aliases to this executable; exercise it only in staging
during tests. Do not recursively delete `DSTROOT` as the old installer does.

Document native compilation, `.deb` seed requirements, command mappings,
behavior corrections, and rollback to the existing Perl commands. Add a
clearly identified section to the repository README without redirecting the
APK bootstrap instructions or remote driver. Keep `src/Manifest` and the Perl
reference sources unchanged in this port; making the new app the system
default is a separate adoption change after validation.

Run a small real local-source build, headers-only build, and multi-package
manifest in disposable native test roots on i386 and PPC. Use architecture
and dependency fixtures appropriate to the original two-arch build contract.
Record host/toolchain details and any target not actually exercised. Run one
representative C build with Perl unavailable to prove the orchestration no
longer requires it; choose a fixture whose own build does not use Perl.

## Acceptance and review boundaries

- Core C tests, CLI integration tests, and artifact comparisons pass.
- The listed intentional divergences each have regression coverage; no other
  behavioral differences are silently accepted through trace normalization.
- Native i386 and PPC results are recorded independently. Host-only checks do
  not establish target compatibility.
- The new executable and optional aliases require no Perl modules at runtime.
- CVS is neither a runtime dependency nor a source backend. The new command,
  compatibility aliases, and manifest parser reject CVS input before build
  side effects, with tests proving no command was launched.
- `.deb` control metadata and payloads match the historical pipeline for the
  representative fixtures, including scripts, headers, and harvested objects.
- Existing `rbuild` code, APK workflows, Perl reference sources, and unrelated
  working-tree changes remain outside the implementation changes.

The detailed implementation checklist is
[`../plans/2026-09-07-darwin-build-c-port.md`](../plans/2026-09-07-darwin-build-c-port.md).
It carries forward the approved `.deb` packaging, target corrections, and
coexistence approach, with local-directory sources only.
