# darwin-build C Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three Perl Darwin build commands with a separate C89
`darwin-build` executable that builds Debian packages from local directories.

**Architecture:** One executable dispatches `package`, `all`, and `missing`,
with optional aliases for the historical command names. Small C modules port
the existing metadata, manifest, dependency, chroot, and packaging behavior;
external commands perform the existing build and archive operations. CVS has
no implementation or runtime dependency.

**Tech Stack:** C89, Rhapsody/POSIX libc and process APIs, make, dpkg-deb,
chroot, rsync, the existing system filesystem utilities, C tests, and POSIX
shell integration tests. Perl is used only by reference tests.

**Approved design:**
[darwin-build C port design](../specs/2026-09-07-darwin-build-c-port-design.md).
The user approved the design on 2026-09-07 with CVS support removed.

---

## Execution boundaries

This document is a plan, not authorization to begin implementation. At
implementation time, isolate new work from concurrent repository activity.
Use the approved design as the compatibility authority and the Perl source
as evidence of historical behavior. Preserve `.deb` output, two-architecture
flags, and the documented compatibility corrections.

Do not modify `src/rbuild-1/`, `src/buildtools-2/`,
`src/dpkg_scriptlib-1/`, `src/Manifest`, or `vm/` for this implementation.
The only existing product document to edit is the top-level `README.md`,
adding a separate description of the new command. Existing Perl sources stay
available as reference material and the APK workflow remains separate.

Reject `--cvs` and `cvs` manifest entries before launching any commands or
creating roots. Reject `objs`, `local`, and unknown targets equally early.
Do not add dry-run, resume, source fetching, new package formats, or a GUI.

All build/test commands below run from `src/darwin-build-1/` on a POSIX host.
The Windows workspace is not itself a Rhapsody test environment. Full native
and reference tests run only in disposable test environments; do not start
or replace a shared bootstrap, VM, build root, or package repository.

## File map

| File to create | Responsibility |
| --- | --- |
| `src/darwin-build-1/Makefile` | Native build, focused tests, staged installation, source installation. |
| `src/darwin-build-1/main.c` | CLI parsing, alias dispatch, help/version, result reporting. |
| `src/darwin-build-1/util.c`, `util.h` | Owned strings/lists, dynamic lines, bounded path operations. |
| `src/darwin-build-1/process.c`, `process.h` | Child argv, cwd/environment, exit/signal reporting. |
| `src/darwin-build-1/package.c`, `package.h` | Debian control fields, parsing, serialization, canonical identity. |
| `src/darwin-build-1/manifest.c`, `manifest.h` | Validated, ordered local-source entries and input locations. |
| `src/darwin-build-1/source.c`, `source.h` | Local scan, metadata defaults, directory naming and source staging. |
| `src/darwin-build-1/build.c`, `build.h` | Roots, dependency preparation, make stages, object harvesting, orchestration. |
| `src/darwin-build-1/deb.c`, `deb.h` | Staged control/scripts and atomic publication of `.deb` output. |
| `src/darwin-build-1/tests/test.h` | Minimal assertion harness following the existing C test convention. |
| `src/darwin-build-1/tests/test_*.c` | Focused module tests described below. |
| `src/darwin-build-1/tests/helpers/process_probe.c` | Records exact argument/environment/cwd values and simulates child outcomes. |
| `src/darwin-build-1/tests/helpers/tree_compare.c` | Compares extracted trees by bytes, modes, ownership, and symlink targets. |
| `src/darwin-build-1/tests/fixtures/` | Small local sources, controls, manifests, and expected results. |
| `src/darwin-build-1/tests/oracle/` | Isolated reference runner and explicit comparison normalization. |
| `src/darwin-build-1/tests/cli.sh`, `integration.sh`, `native.sh`, `install.sh` | Executable-level acceptance checks. |
| `src/darwin-build-1/tests/compatibility.md` | Historical behavior, deliberate changes, and owning tests. |
| `src/darwin-build-1/tests/native-results.md` | Actual native host/compiler/results evidence when executed. |
| `src/darwin-build-1/README.md`, `dpkg/control` | User documentation and new project package metadata. |

Header names in the file map are relative to `src/darwin-build-1/` where the
directory is not repeated. Test files for each task are spelled out below.
Do not introduce a shared library dependency on `rbuild`.

## Module contracts

- Each owning struct has init/free operations; output pointers are either
  owned successful results or null on failure. The caller frees successful
  results. No function returns pointers into a temporary line buffer.
- `Package` owns the supported control fields and a dependency string list.
  A separate presence flag distinguishes absent from empty `Build-Depends`.
  It preserves revision fields and rejects simultaneous `revision` and
  `package_revision`, as the reference does.
- `Manifest` owns entries containing source, target, and file/line context.
  Source type is validated as `dir` on input and needs no backend enum.
- `Roots` distinguishes host filesystem locations from make-visible locations
  inside the chroot. Resolve relative inputs from the initial invocation cwd.
- `Process` borrows a null-terminated argv and optional cwd/environment
  overrides until it returns. It inherits stdout/stderr and returns a decoded
  result distinguishing launch error, exit status, and terminating signal.
- The package engine reports success-built, success-skipped, or failure to
  orchestration. It does not print the manifest summary or terminate the
  process. Diagnostics identify package/source, stage, and underlying error.
- The dependency resolver distinguishes no match, one match, ambiguity, and
  directory-read failure. Availability queries and dependency selection are
  separate operations because their ambiguity rules differ.

## Task 1: Establish reference fixtures and a compatibility ledger

**Create:** `src/darwin-build-1/tests/compatibility.md`,
`src/darwin-build-1/tests/fixtures/`,
`src/darwin-build-1/tests/oracle/reference.pl`,
`src/darwin-build-1/tests/oracle/run.sh`.

**Read:** `src/buildtools-2/tools/darwin-buildpackage.pl`,
`src/buildtools-2/tools/darwin-buildall.pl`,
`src/buildtools-2/tools/darwin-missing.pl`,
`src/buildtools-2/lib/Builder.pm`, `src/buildtools-2/lib/Manifest.pm`,
`src/dpkg_scriptlib-1/perl5/Dpkg/Package/Package.pm`.

- [ ] Create a source fixture named `foo-1` with the following control file.
  Add a tiny Makefile that installs a header, a text payload, and an object
  fixture to the make-provided roots. Use inert scripts that only print text;
  do not copy the real `files-5` device-management scripts into executable
  tests.

```text
Package: foo
Version: 1.2
Maintainer: Test Fixture <fixture@example.invalid>
Description: Fixture package
 continuation line
Build-Depends:
```

- [ ] Add separate fixtures for absent controls, malformed existing controls,
  absent dependencies, `build-base`, script permissions, empty header/object
  roots, a second control paragraph, names with directory revisions, and
  success/skip/failure manifest entries. Expected base identity for `foo-1`
  is `foo_1.2-1_universal-apple-rhapsody.deb`.
- [ ] Load the unchanged Perl modules through a temporary
  `Dpkg/Package/Builder.pm` and `Manifest.pm` layout. Pure reference cases call
  naming/control/root functions without invoking `Builder::build`. Record
  these outputs as fixture expectations and fail on reference errors.
- [ ] Require explicit `DB_ORACLE_ROOT` for side-effecting reference tests.
  Validate it as an existing dedicated disposable environment, never `/` or
  the checkout. Run the Perl engine inside that environment with fixture
  commands at the fixed PATH locations it uses. A prepended PATH alone is
  insufficient because the engine resets PATH before chroot/make.
- [ ] Normalize only unordered make-assignment ordering and nondeterministic
  archive timestamps/order. Preserve actual argument boundaries, values,
  stage ordering, control fields, and package contents. Record expected
  differences separately: invalid inputs, error statuses, directory entries,
  ambiguous dependencies, source permissions, and removed CVS support.
- [ ] Run the pure oracle twice and compare its captured outputs. It must
  produce nonempty stable expectations; it must refuse the build mode when
  `DB_ORACLE_ROOT` is unset.

```sh
sh tests/oracle/run.sh pure
sh tests/oracle/run.sh pure
```

Expected: both pure runs exit 0 and report the same case count. Tests requiring
a disposable root are not reported as passed by this command.

**Commit:** `darwin-build: capture the Perl compatibility contract`.

## Task 2: Add the build skeleton, utilities, and test harness

**Create:** `src/darwin-build-1/Makefile`,
`src/darwin-build-1/util.c`, `src/darwin-build-1/util.h`,
`src/darwin-build-1/tests/test.h`,
`src/darwin-build-1/tests/test_util.c`.

- [ ] Adapt the small assertion convention in
  `src/rbuild-1/tests/test.h` into the new project's test harness. Return
  nonzero if any assertion fails and print the number of checks and failures.
- [ ] Add tests for empty/long strings, list ownership after the source buffer
  changes, lines longer than 4096 bytes, final lines without newlines, clean
  EOF versus read failure, allocation-size overflow, and path joins with
  spaces. A failed line read must not appear as clean EOF.
- [ ] Run the focused target and verify missing utilities prevent the tests
  from passing. Implement growable buffers/lists and explicit allocation
  checks in C89; do not use `getline`, `asprintf`, or a fixed-size input line.
- [ ] Add ordinary `.c.o` rules, `CC = cc`, overrideable `CFLAGS`, focused test
  targets, and a `test` aggregate. Link only the modules each test needs.
  `make test` must propagate a failed test's status. Defer the executable's
  link rule until its entry point exists in Task 4.
- [ ] Run the focused suite, including an intentionally failing harness
  assertion once to confirm failure propagation, then restore the passing
  test and run again.

```sh
make tests/test_util
./tests/test_util
```

Expected: exit 0 and zero failed checks. On native Rhapsody, avoid forcing
`-ansi -pedantic` on platform headers that use compiler extensions; retain
C89 source conventions and use stricter host checks where the headers allow.

**Commit:** `darwin-build: add portable utilities and the test harness`.

## Task 3: Add direct child-process execution

**Create:** `src/darwin-build-1/process.c`,
`src/darwin-build-1/process.h`,
`src/darwin-build-1/tests/test_process.c`,
`src/darwin-build-1/tests/helpers/process_probe.c`.
**Modify:** `src/darwin-build-1/Makefile`.

- [ ] Make the probe record one argument length/value per record, cwd, and
  selected environment values to a test-selected file. Give it explicit
  modes for exit 7 and termination by SIGTERM. Do not parse shell-quoted
  output as a substitute for recording argv.
- [ ] Add failing tests for an argument containing spaces and `$()` text,
  a missing executable, a child cwd error, an environment override, SIGTERM,
  and a successful command after each failure. Check the parent's cwd and
  environment before and after every child.
- [ ] Implement fork, child cwd/environment setup, direct `execvp`, and
  `waitpid` retry on EINTR. Use a close-on-exec error pipe to distinguish
  setup/exec failure from a command that itself exits 127. Close all owned
  pipe descriptors on each path and use `_exit` in the child after an error.
- [ ] Print commands only when requested by the caller's verbosity setting;
  escape diagnostic text without ever re-executing that text. Inherit child
  stdout/stderr. Do not add captured-output support after removing CVS.
- [ ] Run the probe tests and the utilities suite.

```sh
make tests/test_process
./tests/test_process
make test
```

Expected: the probe receives exact arguments, all error classes are distinct,
the parent remains unchanged, and all tests exit 0.

**Commit:** `darwin-build: execute commands with isolated child state`.

## Task 4: Define the CLI and reject unsupported operations early

**Create:** `src/darwin-build-1/main.c`,
`src/darwin-build-1/build.h`,
`src/darwin-build-1/tests/cli.sh`,
`src/darwin-build-1/tests/helpers/cli_engine.c`.
**Modify:** `src/darwin-build-1/Makefile`.

- [ ] Define the shared target enum (`all`, `headers`, `binary`) and parsed
  request structure in `build.h`. Keep source paths as strings; there is no
  source-provider abstraction. The CLI owns parsed arguments through the
  synchronous engine call.
- [ ] For parser tests, link `main.c` with a test-only engine that records the
  request and creates a marker when called. Do not add test shortcuts to the
  production CLI. This supplies a buildable parser test executable before
  the real engine is complete.
- [ ] Add this executable-level assertion for both the canonical name and
  the `darwin-buildpackage` alias, using temporary symlinks in the test tree:

```sh
status=0
./tests/cli-driver package --cvs foo repo dst >out 2>err || status=$?
test "$status" -eq 1
grep 'CVS support has been removed; use --dir' err
test ! -e engine-called
```

- [ ] Cover `--help`, `--version`, no arguments, unknown command, unknown
  option, missing target value, `objs`, `local`, all three supported targets,
  default directory mode, optional `--dir`, `--`, and reordered options before
  positionals. `--verbose` may appear before the subcommand or among its
  options; no options are parsed after the first positional or `--`.
- [ ] Implement argv[0] alias selection and option parsing in `main.c`.
  Supported commands return the engine's result. Do not print success for
  incomplete production operations; until Task 11, only the test driver
  supplies the engine used by parser tests.

```sh
make tests/cli-driver
sh tests/cli.sh ./tests/cli-driver
```

Expected: all malformed requests exit 1 before the marker exists; supported
requests record the right action/target/path strings. Help and version exit 0.

**Commit:** `darwin-build: define the CLI and reject removed source modes`.

## Task 5: Port Debian control metadata and identities

**Create:** `src/darwin-build-1/package.c`,
`src/darwin-build-1/package.h`,
`src/darwin-build-1/tests/test_package.c`.
**Modify:** `src/darwin-build-1/Makefile`.

**Read:** `Package.pm` parse/unparse/canon methods and `Builder.pm`
`makecontrol`, `readcontrol`, and `buildpackage`.

- [ ] Add fixture assertions for case-insensitive keys, folded continuations,
  first-paragraph termination, absent versus empty build dependencies,
  optional provides/conflicts/replaces, both revision fields, malformed
  physical lines, and input lacking Package or Version.
- [ ] Define owned `Package` fields and implement parse, clone, unparse,
  canonical-version, and canonical-name operations. Serialize exactly the
  supported fields from `Package.pm`; unknown well-formed fields remain
  ignored as in the reference. Do not introduce modern Debian metadata
  requirements or accept dependency operators as literal names.
- [ ] Require package names containing lowercase letters, digits, `+`, `-`,
  or `.`, with a lowercase letter/digit first. Require nonempty version and
  architecture components without slashes, whitespace, control characters,
  or path traversal. Permit historical revision/version punctuation needed
  by the actual fixtures; this is filename validation, not a version solver.
- [ ] Compare complete serialized controls with the pure oracle. Assert the
  Debian underscore-and-architecture identity explicitly; the APK-style
  canonical-name helper from `rbuild` must not be copied unchanged.

```sh
make tests/test_package
./tests/test_package
sh tests/oracle/run.sh pure
```

Expected: zero failed C checks and unchanged historical control expectations
for valid inputs; malformed-input corrections have separate assertions.

**Commit:** `darwin-build: port Debian metadata and package identities`.

## Task 6: Validate complete manifests before building

**Create:** `src/darwin-build-1/manifest.c`,
`src/darwin-build-1/manifest.h`,
`src/darwin-build-1/tests/test_manifest.c`.
**Modify:** `src/darwin-build-1/Makefile`.

- [ ] Cover comments, blank lines, two/three-field records, default `all`,
  too few/many fields, overlong lines, supported targets, and unknown source
  types. Add `dir good all` followed by `cvs removed all`: parsing must fail
  with the second line's location and must not return a runnable partial
  manifest.
- [ ] Implement dynamic line reading and whole-manifest validation. Resolve
  relative source entries from the invocation cwd, not the manifest's parent
  directory. Preserve file order. On failure free the partial result.
- [ ] For directory input, skip dot entries and nondirectories, enumerate
  immediate source directories only, and sort by bytewise `strcmp`. The
  legacy whitespace-delimited manifest grammar remains unchanged; a local
  source path containing spaces is supported through `package` or directory
  enumeration, not by adding quoting syntax to manifests.
- [ ] Verify invalid source/target diagnostics contain the input location.
  Unknown source types fail; `cvs` uses the specific removed-support message.

```sh
make tests/test_manifest
./tests/test_manifest
```

Expected: all parser cases pass and rejected manifests have no usable entries.

**Commit:** `darwin-build: validate directory-only manifests before execution`.

## Task 7: Port local source scans, roots, and source copying

**Create:** `src/darwin-build-1/source.c`,
`src/darwin-build-1/source.h`,
`src/darwin-build-1/build.c`,
`src/darwin-build-1/tests/test_source.c`,
`src/darwin-build-1/tests/test_roots.c`.
**Modify:** `src/darwin-build-1/build.h`,
`src/darwin-build-1/Makefile`.

- [ ] Add scan assertions for `foo-1`, names without revisions, underscore
  conversion, `appkit`, and the historical `ssh` naming rule. Test absent
  source, nondirectory source, absent control, unreadable control, malformed
  control, and two consecutive scans using different source directories.
- [ ] Implement only `Builder.pm`'s `scandir` path. Derive defaults from
  `makecontrol`, replace `Source` with the source basename transformation,
  and append the directory revision as `scandir` does. Only an absent control
  triggers defaults; read/parse failures return errors. Do not copy `scancvs`
  or `getcvs`, or create timestamp-version fields.
- [ ] Port all `getparams` root defaults and overrides. Test initial cwd,
  `BUILDIT_DIR`, individual root variables, and separate host/chroot roots.
  Preserve `SUBLIBROOTS=/usr/local/lib/objs` and its override semantics.
- [ ] Validate staging/cleanup boundaries before mutation: normalize existing
  parents and symlinks, retain nonexistent suffixes, compare full path
  components, and reject `/`, traversal, and overlap with sources/repositories.
  Test sibling names such as `root` and `root-other` so prefix matching does
  not mistake them for ancestor/descendant paths.
- [ ] Stage local sources using child cwd set to the source directory and
  argv equivalent to `rsync -avr . --exclude=CVS/ DEST`. Retain the exclusion
  solely for historical administrative directories. Fail on copy errors;
  never use `sh -c` or change the parent's cwd.

```sh
make tests/test_source tests/test_roots
./tests/test_source
./tests/test_roots
```

Expected: local scan/root cases pass, unsafe roots create nothing, and argv
tests preserve spaces without invoking a shell.

**Commit:** `darwin-build: scan and stage local sources with historical roots`.

## Task 8: Resolve and extract Debian build dependencies

**Create:** `src/darwin-build-1/tests/test_dependencies.c`.
**Modify:** `src/darwin-build-1/build.c`,
`src/darwin-build-1/build.h`, `src/darwin-build-1/Makefile`.

- [ ] Add cases for destination priority, seed fallback, no match, ambiguous
  matches in the first matching repository, matching directories, repository
  read errors, repeated dependencies, missing build dependencies, and an
  explicitly empty dependency list.
- [ ] Match literal `<dependency>_*.deb` filenames, not an interpolated regex.
  Require regular files for dependency selection. Select only the first
  repository with matches; fail if it contains multiple candidates rather
  than consulting a lower-priority repository.
- [ ] Expand absent `Build-Depends` or the `build-base` token into this exact
  Perl list, then deduplicate. This is direct dependency expansion, not a
  recursive package solver:

```text
cc cctools gnumake
pb-makefiles coreosmakefiles project-makefiles
zsh tcsh
file-cmds text-cmds shell-cmds developer-cmds awk grep gnutar
libsystem libc-hdrs architecture-hdrs kernel-hdrs csu objc4-hdrs
files basic-cmds bootstrap-cmds system-cmds
```

- [ ] Resolve the complete set before extraction. Use a stable bytewise order
  for the deduplicated package list, documenting that Perl hash order was
  unspecified. Read `<BUILDROOT>/var/adm/package-list`; for each selected
  archive absent from the record, execute `dpkg-deb -x ARCHIVE BUILDROOT`.
- [ ] Write a sibling temporary record only after every extraction succeeds,
  check write/close results, and rename it over `package-list`. On failure
  preserve the prior record and retain the root. Already-extracted contents
  need no rollback; a retry may safely extract them again.
- [ ] Inject failure on the second extraction and on record publication.
  Assert the correct error and unchanged prior record. Do not use package
  installation or execute maintainer scripts to construct the build root.

```sh
make tests/test_dependencies
./tests/test_dependencies
```

Expected: missing/ambiguous dependencies run no extraction, each selected
archive extracts at most once per attempt, and record failure is propagated.

**Commit:** `darwin-build: prepare roots from Debian dependencies`.

## Task 9: Run make targets and harvest objects

**Create:** `src/darwin-build-1/tests/test_build.c`.
**Modify:** `src/darwin-build-1/build.c`,
`src/darwin-build-1/build.h`, `src/darwin-build-1/Makefile`.

- [ ] Record argv for the three target modes. `all` invokes `installhdrs`
  then `install`; `headers` invokes only `installhdrs`; `binary` invokes only
  `install`. Headers use `HDRROOT` as make's `DSTROOT`. Failure in headers
  stops `all` before the install stage.
- [ ] Port `baseflags`, `cflags`, `buildflags`, and `buildcmd` directly from
  `Builder.pm`. Preserve `RC_ARCHS=i386 ppc`, both `RC_i386=YES` and
  `RC_ppc=YES`, and exact whitespace inside `RC_CFLAGS`. Set
  `UNAME_SYSNAME=Rhapsody` and the fixed child PATH from the Perl source.
- [ ] Run argv equivalent to `chroot BUILDROOT make -w -C SRCROOT` followed
  by the make assignment arguments and target. Do not reuse `rbuild`'s
  bootstrap/native build path or PPC-only flag normalization.
- [ ] Discover `dynamic_obj` directories under OBJROOT without following
  symlinked directories, stop descending into a discovered object directory,
  and preserve its relative path under
  `LIBCOBJROOT/usr/local/lib/objs/SOURCE/`. Use the reference chroot copy
  semantics so symlink interpretation stays relative to the build root.
- [ ] Test multiple object directories, nested directories, a symlink escape,
  no objects, and copy failure. Verify make/harvest errors include the stage
  and retain the failed root. Successful cleanup is invoked only after the
  packaging stages added in Task 10 complete.

```sh
make tests/test_build
./tests/test_build
```

Expected: exact make values match the reference fixtures and all target and
object-path assertions pass without starting real builds in host unit tests.

**Commit:** `darwin-build: run Rhapsody make targets and collect objects`.

## Task 10: Stage Debian metadata and publish archives

**Create:** `src/darwin-build-1/deb.c`,
`src/darwin-build-1/deb.h`,
`src/darwin-build-1/tests/test_deb.c`.
**Modify:** `src/darwin-build-1/build.c`,
`src/darwin-build-1/Makefile`.

- [ ] Add cases for base/header/object controls, empty optional roots,
  scripts, `conffiles`, binary/header replacement fields, staged-source
  pruning, command failure, and publish failure.
- [ ] Clone package metadata per output. Base uses the package name and
  provides/conflicts/replaces `<name>-hdrs`; headers use `<name>-hdrs`;
  objects use `<name>-obj`. Base creates DEBIAN even for an otherwise empty
  payload. Empty headers/objects produce no archive.
- [ ] Write `DEBIAN/control` using the package serializer. Copy only present
  binary-package `conffiles`, `preinst`, `postinst`, `prerm`, and `postrm` into
  DEBIAN. Apply 0644 to staged conffiles and 0755 to staged scripts. Assert
  source modes are unchanged. Remove staged `System/Developer/Source` only
  after its path has passed the staging boundary check.
- [ ] Create a uniquely owned temporary output in the destination filesystem,
  run `dpkg-deb --build STAGED_ROOT TEMP_OUTPUT`, and rename to the canonical
  `.deb` path only on success. Use exclusive creation with bounded collision
  retries; check every failure and unlink only this invocation's temp file.
  A failed build must not replace a previously complete final archive.
- [ ] Wire the target/output mapping: `all` produces headers then base and
  objects; `headers` produces headers; `binary` produces base and objects.
  Execute successful manifest cleanup only after all requested outputs have
  been published. Standalone builds retain their roots.

```sh
make tests/test_deb
./tests/test_deb
```

Expected: all metadata/mode/publication assertions pass; failed commands and
failed renames return 1 and leave no new apparently complete final artifact.

**Commit:** `darwin-build: stage and publish Debian package archives`.

## Task 11: Complete package, manifest, and missing orchestration

**Create:** `src/darwin-build-1/tests/test_runner.c`.
**Modify:** `src/darwin-build-1/build.c`,
`src/darwin-build-1/build.h`, `src/darwin-build-1/main.c`,
`src/darwin-build-1/tests/cli.sh`, `src/darwin-build-1/Makefile`.

- [ ] Implement the engine entry points used by Task 4 and add the production
  `darwin-build` link rule. Test the real executable in addition to keeping
  the parser's test-only recording engine for early-dispatch assertions.
- [ ] Preserve availability policy: `all`/`missing` ask whether any base
  `<package>_*.deb` exists, matching the old wrappers even for a headers
  manifest entry. Standalone `package` skips an exact requested header
  archive for `headers`, and an exact base archive for any supported target,
  matching `Builder::build`. Test older-version and headers-only repository
  cases explicitly; do not substitute rbuild's current cache policy.
- [ ] Read and validate the entire manifest before any build call. Then
  inspect each entry; operational scan/dependency/build failures are counted
  and processing continues. A malformed manifest, unsupported source type,
  or invalid target aborts before any entry starts.
- [ ] Aggregate the engine's built/skipped/failed results. Print the final
  counts and the names in each category; return 1 if any entry failed.
  `missing` prints historical-style missing-package records only, launches
  no processes, writes nothing, and returns 1 if any scan/query failed.
- [ ] Add stage messages and verbosity. Ordinary execution shows stage and
  child build output; `--verbose` additionally shows resolved roots and
  commands. Diagnostics go to stderr. Do not add an interactive prompt.
- [ ] Run a three-entry manifest whose results are one build, one skip, and
  one failure. Repeat with a later `cvs` entry and assert no first-entry work.
  Validate canonical and historical-name invocations against the same engine.

```sh
make darwin-build tests/test_runner
./tests/test_runner
sh tests/cli.sh ./darwin-build
make test
```

Expected: the mixed operational run reports `built: 1`, `skipped: 1`, and
`failed: 1`, lists the associated sources, and exits 1. CVS rejection starts
no work. The aggregate suite exits 0 when all expected outcomes are observed.

**Commit:** `darwin-build: complete commands and report manifest outcomes`.

## Task 12: Compare complete Debian artifacts with the reference

**Create:** `src/darwin-build-1/tests/integration.sh`,
`src/darwin-build-1/tests/helpers/tree_compare.c`.
**Modify:** `src/darwin-build-1/tests/oracle/run.sh`,
`src/darwin-build-1/tests/compatibility.md`,
`src/darwin-build-1/Makefile`.

- [ ] Build Perl and C fixture outputs in separate fresh roots under the
  disposable oracle environment. The fixture build commands may be controlled
  stubs, but `dpkg-deb --build` and archive extraction must be real operations.
  Record process exits directly, without a pipeline hiding the build status.
- [ ] Extract control and payload trees using the target-era tools. For each
  archive, the script resolves absolute `archive`, `control`, and `payload`
  paths in its own test directory, then invokes:

```sh
dpkg-deb -e "$archive" "$control"
dpkg-deb -x "$archive" "$payload"
```

- [ ] Implement `tree_compare.c` using lstat, readdir, readlink, and file
  byte reads. Compare relative names, file types, bytes, permissions, numeric
  uid/gid, and symlink targets. Ignore timestamps and traversal order. It
  must return nonzero on any mismatch or read error and never execute files.
- [ ] Compare base/header/object payloads and exact supported control fields.
  Compare source-tree permissions before and after the C run. Match make
  argv values and stage ordering, allowing only documented Perl hash ordering.
- [ ] Deliberately alter one header byte, one permission, and one make flag
  in separate test runs to confirm each comparison detects the mismatch.
  Restore the fixtures and run the aggregate target.

```sh
make integration-test
make oracle-test
```

Expected: complete fixtures pass; corrupted comparisons fail in their own
negative tests. `oracle-test` exits nonzero with a setup diagnostic when a
validated `DB_ORACLE_ROOT` is unavailable; it never claims native/reference
coverage based only on unit tests.

**Commit:** `darwin-build: compare Debian outputs with the Perl reference`.

## Task 13: Add staged installation and user documentation

**Create:** `src/darwin-build-1/README.md`,
`src/darwin-build-1/dpkg/control`,
`src/darwin-build-1/tests/install.sh`.
**Modify:** `src/darwin-build-1/Makefile`, repository `README.md`.

- [ ] Set the initial project metadata to Package `darwin-build`, Version
  `0.1`, with `Build-Depends: build-base`. Keep the project-directory revision
  convention separate from the user-visible command version. Build dependencies
  are not a complete declaration of commands required when running the tool;
  document those commands in the README.
- [ ] Add `install` for `$(DSTROOT)/usr/bin/darwin-build`; `installhdrs` is a
  no-op; `installsrc` copies the project into `SRCROOT` using existing-era
  tools. Add explicit `install-compat` to install symlinks for the three old
  command names. It depends on installing the canonical executable.
- [ ] Create an installation fixture with an unrelated sentinel file.
  Default install must preserve it and create no old-name aliases. A second
  compatibility install must create aliases resolving to the same binary,
  and invoking those aliases must pass CLI tests. Never remove DSTROOT.

```sh
make install-test
```

Expected: default and compatibility staged installs pass, and unrelated
staged files survive both operations.

- [ ] Document build requirements, `.deb` seed repositories, optional `--dir`,
  targets, verbosity, exit behavior, missing queries, manifest cwd rules,
  removed CVS support, retained `CVS/` exclusion, intentional bug corrections,
  and the any-version skip policy. Show alias adoption as an explicit step
  and describe restoring the previous Perl command files for rollback.
- [ ] Add a separate section to the root README linking to this project.
  Do not rewrite APK bootstrap examples, switch manifests, remove Perl from
  unrelated build prerequisites, or claim the new command builds a fresh
  seed repository without existing Debian build dependencies.

**Commit:** `darwin-build: document and stage the standalone C tool`.

## Task 14: Record native i386 and PPC acceptance

**Create:** `src/darwin-build-1/tests/native.sh`,
`src/darwin-build-1/tests/native-results.md`.
**Modify:** `src/darwin-build-1/Makefile`,
`src/darwin-build-1/tests/compatibility.md`.

- [ ] Define `native-test` to require explicit `DB_NATIVE_ROOT` and
  `DB_NATIVE_SEED`, both dedicated absolute paths in a disposable native
  test environment. The seed must be a Debian repository providing the
  Perl base-dependency list; APKs do not satisfy it. Refuse shared production
  locations and reject missing setup before mutation.
- [ ] On each architecture, compile with the native compiler, run unit/CLI
  tests, and use the original two-arch make flag contract for a representative
  local-source build, headers-only build, and multi-entry manifest. Exercise
  native chroot and dpkg-deb, not just trace stubs. Keep i386 and PPC evidence
  separate; a PPC build does not establish i386 execution compatibility.
- [ ] Check the resulting archive names, metadata, header/object paths, and
  extraction records. Validate failed-build root retention, successful
  manifest cleanup, and standalone root retention in dedicated test paths.
- [ ] Run a C fixture build in a disposable environment where Perl and CVS
  executables/modules are unavailable at both the inherited PATH and the
  fixed child PATH. Use a source Makefile that itself needs neither tool.
  Preserve make, shells, rsync, dpkg-deb, and the normal utilities.

```sh
make clean
make all
make test
make native-test
```

Expected: successful native builds on each tested host, no Perl/CVS invocation,
and the documented output/status/cleanup behavior. Missing native resources
are reported as unverified acceptance items, never converted into passing
results. Do not attempt a shared full-system bootstrap to fill this gap.

- [ ] Record actual host OS, architecture, compiler version, dpkg-deb version,
  test command exits, and evidence locations in `native-results.md`. Do not
  prepopulate successful outcomes. Close every compatibility-ledger item
  with its owning test/result or an explicit unresolved native acceptance item.
- [ ] Run final unit, integration, reference, installation, and available
  native checks after the last relevant code change. Review the change list
  against the execution boundaries before committing the validation record.

**Commit:** `darwin-build: record native port validation`.

## Coverage map and completion criteria

| Approved requirement | Owning tasks |
| --- | --- |
| Separate C89 command and optional aliases | 2–4, 11, 13 |
| No CVS backend/dependency, rejection before work | 4, 6, 11, 14 |
| Debian names, fields, continuations, revisions, defaults | 1, 5, 7, 10, 12 |
| Validated manifests and original cwd semantics | 6, 7, 11 |
| Root overrides, child environment, two-arch make flags | 3, 7, 9, 12, 14 |
| Dependency priority, ambiguity errors, extraction records | 8, 12, 14 |
| Base/header/object packaging and script permissions | 9, 10, 12 |
| Cleanup boundaries and failed-root retention | 7–11, 14 |
| Failure summaries, missing behavior, no false success | 4, 11, 12 |
| Historical availability semantics | 8, 11 |
| Controlled rollout, Perl/rbuild coexistence | 13 |
| Native portability and no Perl runtime requirement | 14 |

Completion requires passing evidence for the implementation's tests and
artifact comparisons, with independent native acceptance on both architectures.
No commit or final report may treat an unexecuted native check as passed.
The planning task itself ends with this document; executing it is subsequent
work.
