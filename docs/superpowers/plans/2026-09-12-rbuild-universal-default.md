# rbuild Universal Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the architectures declared by a package, default ordinary packages to i386 + ppc, and prevent thin artifacts from being advertised or reused as universal.

**Architecture:** Resolve source labels and explicit operation targets into one effective architecture policy before building or checking caches. Feed that policy into existing make invocations, prerequisite probes, package validation, and resume/dependency decisions. Preserve single-target bootstrap and kernel operations with truthful thin metadata.

**Tech Stack:** C89, existing rbuild test macros, POSIX processes/filesystem, legacy Rhapsody make/compiler tools, APK tar/gzip containers, 32-bit Mach-O and ar archives.

**Approved design:** `docs/superpowers/specs/2026-09-12-rbuild-universal-default-design.md`.

---

## Working rules and sequence

Implement tasks in order; do not parallelize changes to builder/runner/APK paths.
Use an isolated checkout for implementation because the current checkout has
unrelated driver work. Preserve that work. This planning commit changes only
this document. Do not start guest builds as part of creating this plan.

Run C tests in a supported POSIX environment, from `src/rbuild-1`. PowerShell
is not the native test shell. Use a private guest build root and temporary disk
image for integration work. Do not overwrite an active bootstrap repository.

For each task: add the specified regression first, observe the relevant failure,
implement the described change, rerun the focused checks, then commit only the
task files. A missing dependency/tool is not a successful regression failure.

## File responsibilities

| Files | Responsibility |
| --- | --- |
| New `src/rbuild-1/architecture.c`, `.h` | Label parsing, effective target resolution, canonical labels and flags |
| New `src/rbuild-1/macho.c`, `.h` | Bounded 32-bit Mach-O/fat/ar inspection; no subprocess parsing |
| New `src/rbuild-1/products.c`, `.h` | Payload tree validation, including harvested object collections |
| `src/rbuild-1/builder.c`, `.h` | Preserve source labels, propagate policy, probe build environment, validate before packaging |
| `src/rbuild-1/runner.c`, `.h` | Explicit targets, artifact reuse, dependency replay and state |
| `src/rbuild-1/apk.c`, `.h` | Validate staged payload before merge/reuse using immutable archive snapshot |
| `src/rbuild-1/main.c` | Architecture-aware missing command and error propagation |
| `src/rbuild-1/Makefile`, tests | Link new modules and regression coverage |
| `src/rbuild-1/README.md`, `docs/build/rbuild-universal.md` | Behavior, prerequisites, migration, recorded guest evidence |

Keep `pkginfo.c` as a metadata writer. Supply it the resolved Package rather
than introducing a second architecture policy there. Keep the current APK
filename format; distinct architecture variants require separate repositories.

## Task 1: Define architecture policy and preserve source labels

**Files:** Create `architecture.c/.h`, `tests/test_architecture.c`; modify
`builder.c`, `Makefile`, `tests/test_builder.c` (all under `src/rbuild-1`).

- [ ] Add this public interface; values are slice masks, not Mach CPU constants:

```c
#ifndef RBUILD_ARCHITECTURE_H
#define RBUILD_ARCHITECTURE_H
#define RB_ARCH_I386 1U
#define RB_ARCH_PPC 2U
#define RB_ARCH_UNIVERSAL (RB_ARCH_I386 | RB_ARCH_PPC)
#define RB_ARCH_POLICY_VERSION "1"
int architecture_parse(const char *label, unsigned *mask);
int architecture_resolve(unsigned source, unsigned operation,
                         unsigned *effective);
const char *architecture_label(unsigned mask);
const char *architecture_archs(unsigned mask);
const char *architecture_cflags(unsigned mask);
#endif
```

`architecture_parse(NULL)` selects universal. Accept only the five labels in
the design, including both aliases for each thin target. Empty/unknown values
return 1. `operation == 0` means ordinary build; otherwise require a thin mask.
Universal source permits the operation's subset; thin source must equal it.
Reject invalid masks. Canonical strings are `i386-apple-rhapsody`,
`ppc-apple-rhapsody`, and `universal-apple-rhapsody`.

- [ ] Add a table-driven test and these explicit assertions:

```c
unsigned source, effective;
CHECK_INT(architecture_parse(0, &source), 0);
CHECK_INT(source, RB_ARCH_UNIVERSAL);
CHECK_INT(architecture_parse("i386", &source), 0);
CHECK_INT(architecture_resolve(source, 0, &effective), 0);
CHECK_STR(architecture_label(effective), "i386-apple-rhapsody");
CHECK_INT(architecture_resolve(source, RB_ARCH_PPC, &effective), 1);
CHECK_INT(architecture_resolve(RB_ARCH_UNIVERSAL, RB_ARCH_PPC,
                               &effective), 0);
CHECK_INT(effective, RB_ARCH_PPC);
CHECK_INT(architecture_parse("", &source), 1);
CHECK_INT(architecture_parse("any", &source), 1);
CHECK_INT(architecture_parse("all", &source), 1);
CHECK_INT(architecture_parse("m68k", &source), 1);
CHECK_STR(architecture_archs(RB_ARCH_UNIVERSAL), "i386 ppc");
CHECK_STR(architecture_cflags(RB_ARCH_UNIVERSAL), "-arch i386 -arch ppc");
```

- [ ] Add `architecture.o` to affected link lists and a `tests/test_architecture`
  target using the existing test pattern. Run `make tests/test_architecture`
  and `./tests/test_architecture`; first observe missing implementation, then
  implement exact string/mask mapping and rerun for zero failures.
- [ ] Change control scanning so absent control still synthesizes defaults,
  but present invalid architecture returns failure. Distinguish absent control
  from invalid control; do not let the fallback erase an invalid label. Preserve
  existing explicit source labels until resolution. Validate before returning
  from `builder_scan_dir` and identify the control path in diagnostics.
- [ ] Add source-control fixtures for missing field, explicit i386, canonical
  ppc, explicit universal, empty field and invalid value. Assert `builder_scan`
  preserves explicit labels and invalid labels fail rather than synthesize.
  Run `make tests/test_builder && ./tests/test_builder`.
- [ ] Commit: `rbuild: resolve package architecture labels`.

## Task 2: Thread effective policy through builds and explicit operations

**Files:** Modify `builder.c/.h`, `runner.c/.h`, `tests/test_builder.c`,
`tests/test_runner.c`, `tests/bootstrap-resume.sh`.

- [ ] Extend BuildOptions with `unsigned operation_arch` and
  `unsigned effective_arch`; zero initialization remains valid. Extend
  RunnerOptions with `unsigned operation_arch`. Operation masks are set only
  by bootstrap profile resolution and kernel/kerneldrivers --arch.
- [ ] Resolve after source scan in both runner entry paths and builder_build,
  before clones or filename/reuse decisions. Copy caller BuildOptions into a
  local resolved value, use it for the entire build, and canonicalize the local
  Package's output label. Never mutate dpkg/control. Use this resolution shape:

```c
unsigned source_arch, effective_arch;
if (architecture_parse(pkg.architecture, &source_arch) != 0 ||
    architecture_resolve(source_arch, resolved.operation_arch,
                         &effective_arch) != 0) {
    fprintf(stderr, "rbuild: architecture conflicts with operation target\n");
    /* Return through the enclosing function's owned-resource cleanup. */
} else {
    resolved.effective_arch = effective_arch;
    package_set(&pkg.architecture, architecture_label(effective_arch));
}
```

In the actual error branch include source path, source label and operation
label, set failure, and follow that function's cleanup label. Do not continue
after a failed resolution. Runner and builder must use the same resolver.

- [ ] Replace RBUILD_HOST_ARCH decisions with effective masks. With unresolved
  zero BuildOptions in unit command construction, use universal as the default.
  Set RC_ARCHS and arch portions of RC_CFLAGS from the architecture helpers;
  emit both switches with YES for selected slices and empty values for excluded
  slices so environment variables cannot re-enable an unwanted architecture.
- [ ] Keep bootstrap cpp/link/sysroot expansion. Check its arch_flags agree
  with its target_arch by compiling and inspecting probes in Task 6; do not
  append conflicting architecture flags from two sources.
- [ ] Inspect `src/CoreOSMakefiles-1/ReleaseControl/GNUSource.make` and
  `src/pb_makefiles-1/platform.make` TARGETS use. Retain bootstrap's existing
  target assignment and set ordinary TARGETS only where it is an architecture
  list; do not override unrelated project targets globally.
- [ ] Replace host-dependent assertions with universal assertions:

```c
CHECK(list_has(&f, "RC_ARCHS=i386 ppc"));
CHECK(list_has(&f, "RC_i386=YES"));
CHECK(list_has(&f, "RC_ppc=YES"));
```

Add thin cases with the opposite switch empty, and assert the cflags contain
only requested -arch entries. Bootstrap ppc must remain ppc and emit thin
metadata. Universal source plus kernel --arch i386 builds i386; explicit ppc
source plus that command fails before make. Change the existing m68k bootstrap
fixture to expect unsupported policy rejection at resolution, while retaining
generic toolchain parser tests that are outside package policy.

- [ ] Run `make tests/test_builder tests/test_runner` and both test executables.
  Commit: `rbuild: build the resolved package architectures`.

## Task 3: Inspect Mach-O and archive slices without host tools

**Files:** Create `macho.c/.h`, `tests/test_macho.c`; modify `Makefile`.

- [ ] Use a small portable binary reader rather than parsing localized `file`
  or `lipo` output. Read integers bytewise; do not cast buffers to native
  structs. Define:

```c
int macho_file_arches(const char *path, unsigned *mask, int *machine_code);
```

Return 0 for successful inspection including non-code files, and 1 for I/O
errors or malformed recognized containers. Non-code yields mask 0 and
machine_code 0. Recognized but unsupported CPU code is an error, not data.

- [ ] Read repository Mach-O and archive headers as format references before
  coding. Support 32-bit little/big-endian MH_MAGIC (0xfeedface), fat headers
  (0xcafebabe and swapped representation), CPU types i386=7 and PowerPC=18,
  and ar `!<arch>\n`. Do not import host Mach headers into portable tests.
- [ ] Check header lengths, table counts, offsets, sizes, integer overflow,
  overlapping fat ranges, duplicate CPU slices, and agreement between fat
  entries and contained Mach-O headers. Bound nested inspection depth to 4.
  Unsupported recognized 64-bit containers fail explicitly for this target.
- [ ] For ar, handle fixed headers, even-byte padding, BSD extended names and
  GNU name tables. Skip symbol/name-table members, not arbitrary unrecognized
  object members. A thin archive's code members must agree on CPU; a fat archive
  must contain internally consistent archives for its declared CPUs. Reject a
  bare archive mixing ppc and i386 members instead of treating their union as a
  valid universal static library.
- [ ] Generate fixtures in C with explicit bytes and temporary files, including
  both endian thin headers and a fat container with real contained headers:

```c
static const unsigned char thin_i386[28] = {
    0xce,0xfa,0xed,0xfe, 7,0,0,0, 3,0,0,0, 1,0,0,0,
    0,0,0,0, 0,0,0,0, 0,0,0,0
};
static const unsigned char thin_ppc[28] = {
    0xfe,0xed,0xfa,0xce, 0,0,0,18, 0,0,0,0, 0,0,0,1,
    0,0,0,0, 0,0,0,0, 0,0,0,0
};
```

Test scripts, zero-length files, truncated recognized headers, out-of-bounds
fat slices, duplicate entries, wrong inner CPU, valid thin/fat archives, mixed
thin archives, malformed member sizes, and extended names.
- [ ] Run `make tests/test_macho && ./tests/test_macho`, first failing then
  passing. Commit: `rbuild: inspect Mach-O package architectures`.

## Task 4: Validate installed payloads and harvested object collections

**Files:** Create `products.c/.h`, `tests/test_products.c`; modify `builder.c`,
`Makefile`, `tests/test_builder.c`.

- [ ] Introduce:

```c
int products_validate(const char *root, unsigned required,
                      int object_collection, int allow_superset);
```

Use lstat traversal, never follow symlink directories, and inspect all regular
files by content. Report root-relative path and expected/observed architecture
on failure. Header/data-only trees succeed with no code requirement.
Installed code must equal `required`, except dependency compatibility calls
with allow_superset=1 may accept universal code for a thin consumer.

- [ ] Handle object collections only below harvested
  `usr/local/lib/objs/<source>/.../dynamic_obj`. Inspect the real project output
  directory convention and encode exact `i386`/`ppc` path components as slice
  buckets; reject CPU/path disagreement. Group by source and build variant with
  that one architecture component removed. Require each group to contain all
  requested buckets; different filenames between buckets are valid because
  architecture-specific source sets differ. Never OR all objects across the
  entire package. Ordinary installed executables outside these collections
  still require fat code for universal builds.
- [ ] Add tree fixtures: fat executable, thin mislabeled executable, non-code
  executable script, library with no execute bit, symlink escape, paired object
  groups with differing filenames, missing ppc group, wrong CPU inside an i386
  bucket, and a valid fat object outside a bucket. Unknown thin-object layouts
  fail with their path rather than pass on package-wide slice union.
- [ ] Call products_validate after harvesting and before .PKGINFO/APK assembly.
  Validate `local` build products as well even though no APK is emitted. Skip
  filesystem inspection in dry-run; print the intended validation step.
- [ ] Run `make tests/test_products tests/test_builder` and both tests.
  Commit: `rbuild: validate architecture coverage before packaging`.

## Task 5: Validate APK payloads before reuse and dependency installation

**Files:** Modify `apk.c/.h`, `builder.c/.h`, `runner.c`, `main.c`,
`tests/test_apk.c`, `tests/test_builder.c`, `tests/test_runner.c`, `Makefile`.

- [ ] Extend the existing APK private snapshot/staging flow with architecture
  validation before merge_stage. Preserve immutable-copy, tar path/link, and
  source-identity checks. Do not validate one pathname and extract a later
  reopening of it. Provide one architecture-aware entry point:

```c
int apk_use_arch(const char *path, const char *root, const Toolchain *tc,
                 const char *pkgname, const char *pkgver,
                 unsigned required, int object_collection,
                 int allow_superset);
```

`root == NULL` means inspect in private staging then discard; non-null means
validate then merge. Missing expected name/version can omit those comparisons
for a dependency only; always parse and validate its architecture label. Exact
reuse requires exact canonical metadata, dependency mode permits supersets.
Resource/header-only dependency payloads are architecture-neutral for code
compatibility, but malformed/unsupported labels still fail.

- [ ] Replace builder's private shell-only dependency apk_extract helper with
  the validated staging path; rename/remove the private helper to avoid the
  existing name collision with apk.h. Validate each transitive dependency before
  it touches the build root. Preserve repository search order but continue past
  an incompatible candidate if a later compatible candidate exists.
- [ ] Replace filename-only builder skip paths and runner existence paths with
  exact architecture-aware inspection. Invalid legacy universal artifacts are
  quarantined using existing machinery before rebuilding, with a diagnostic.
  `missing` uses inspection without quarantine and reports incompatible APKs as
  missing. A source scan failure must make `missing` return nonzero.
- [ ] Keep architecture out of filenames. Before publishing, an incompatible
  existing name/version must be diagnosed and moved aside via quarantine;
  never silently overwrite it. Document separate output directories for users
  who need to retain multiple variants simultaneously.
- [ ] Extend APK fixtures with real thin/fat bytes from Task 3. Assert universal
  metadata plus thin code fails, thin metadata plus wrong CPU fails, universal
  dependency satisfies thin consumer, thin dependency fails universal consumer,
  and incompatible payload never reaches merge. Retain all existing tar/link
  and race regression tests.
- [ ] Run `make tests/test_apk tests/test_builder tests/test_runner` and all
  three executables. Commit: `rbuild: reject incompatible cached packages`.

## Task 6: Probe the actual build compiler and runtime

**Files:** Modify `builder.c/.h`, `tests/test_builder.c`, trace shims as needed.

- [ ] After build-root/dependency setup and before compilation, write a private
  probe source under OBJROOT containing `int main(void) { return 0; }`. Use the
  selected make environment to compile/link it, with the same compiler,
  architecture, include, framework, library and sysroot assignments as the
  package. Keep the probe makefile/source outside source-project directories.
- [ ] For each required slice, build an object and inspect it with
  macho_file_arches; for install/all/binary/local targets also link an executable
  and inspect that. Use a private makefile with these recipes (real tabs):

```make
probe.o: probe.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(RC_CFLAGS) $(LOCAL_CFLAGS) -c probe.c -o probe.o
probe: probe.o
	$(CC) $(CFLAGS) $(RC_CFLAGS) $(LDFLAGS) probe.o -o probe
```

Construct invocation arguments from the same resolved BuildOptions and compiler
assignments as builder_buildcmd; ordinary probes execute inside its chroot,
bootstrap probes execute with its configured tools. Run in private per-slice
directories and invoke target-specific -arch flags. Never execute the produced
target executable. Header-only installs skip compiler/link prerequisites;
object-only work performs compile-only checks when that build path is used.

- [ ] Add shims that emit valid thin fixture bytes, emit the wrong architecture,
  reject the second architecture, or fail only the link. Assert the latter
  failures stop before project make/packaging. Error messages name architecture
  and failed compile/link/inspection stage. Dry-run logs probes but creates no
  files and invokes no tools.
- [ ] Retain stage-zero bootstrap behavior: no premature link checks before
  that operation's runtime libraries exist. Apply bootstrap link probes when
  its profile's existing ld_flags_ready prerequisite exists; always inspect
  compiled code for architecture. Ordinary linked builds have no such bypass.
- [ ] Run `make tests/test_builder && ./tests/test_builder`.
  Commit: `rbuild: check requested toolchain slices before builds`.

## Task 7: Version resume state and audit all operation paths

**Files:** Modify `runner.c`, `tests/test_runner.c`,
`tests/bootstrap-resume.sh`, `tests/bootstrap-closure.sh`.

- [ ] Add effective canonical label and RB_ARCH_POLICY_VERSION to state output
  and entry_fingerprint. Require exact matches in check_state. Old/missing
  markers force validation and rebuild; never replay solely because a legacy
  .done exists. Keep existing toolchain fingerprint and artifact identity checks.

```text
architecture_policy=1
effective_architecture=ppc-apple-rhapsody
```

- [ ] Resolve source architecture before run_entry's early cache branch and
  before runner_buildpackage's separate direct path. Pass explicit targets from
  both kernel entry points. Inspect all `already have`, `already exists`,
  `builder_exists`, `replay`, and `file_apk_exists` sites for bypasses.
- [ ] Add resume cases changing universal to thin, thin to universal, bootstrap
  target, policy marker, and source label with unchanged package/version. Verify
  old falsely universal artifacts rebuild and new valid artifacts resume.
  Bootstrap header/object/base variants must all carry its effective thin label.
- [ ] Run `make test` (includes resume and closure scripts). Commit:
  `rbuild: include architecture policy in resume state`.

## Task 8: Trace coverage, documentation, and isolated guest proof

**Files:** Modify `tests/trace/run.sh`, `tests/trace/normalize.sed`, relevant
trace fixtures/shims, `README.md`; create `docs/build/rbuild-universal.md`
at repository root.

- [ ] Update intentional Perl trace differences explicitly: native default
  universal flags should now match historical intent; APK validation/probes
  are new operations. Do not normalize away architecture values. Add a thin
  source fixture and assert exact command flags independently of Perl.
- [ ] Run from `src/rbuild-1`:

```sh
make test
make trace-test
```

Expected: all unit tests, bootstrap scripts, and trace checks pass. Run broader
checks only if changes/failures require them. Record the exact environment.

- [ ] In an isolated guest root with both runtime slices and compiler backends,
  build a small source fixture with no Architecture field and one with i386.
  Give each a unique Package name/version and private repository/output root.
  Exercise ordinary buildpackage and buildall, then repeat to prove reuse.
  Exercise bootstrap ppc and kernel --arch conflict tests through controlled
  fixtures before attempting expensive OS projects.
- [ ] Build one representative executable, static library, and harvested object
  package using actual legacy make frameworks. Inspect extracted .PKGINFO and
  code with the new validator and guest `lipo -info` as independent evidence.
  Check guest lipo's usage before selecting flags; do not assume modern options.
  Record actual package names, commands, logs, CPU slices and exit statuses.
- [ ] Demonstrate failure when the i386 runtime or backend is absent in the
  private test root; confirm no universal APK is published. Never remove live
  guest libraries to create this test.
- [ ] Document the accepted labels, missing-versus-empty behavior, explicit
  operation exceptions, prerequisite diagnostics, old-cache quarantine, separate
  destinations for variants, and migration of bootstrap outputs to thin labels.
  If guest prerequisites are unavailable, state exactly which acceptance tests
  remain unverified and do not claim working universal OS builds.
- [ ] Commit: `rbuild: document and verify universal build defaults`.

## Final review and acceptance checklist

- [ ] Every ordinary code package follows its label and defaults to both slices.
- [ ] Host CPU does not silently affect target selection or output metadata.
- [ ] Bootstrap/kernel effective targets are explicit, consistent and tested.
- [ ] Invalid labels/conflicts fail before build or cache use.
- [ ] Both skip paths, missing, dependencies, and replay validate compatibility.
- [ ] Preflight and product validation detect missing/wrong slices.
- [ ] Object collections are checked by group, not by whole-package CPU union.
- [ ] Policy changes invalidate resume assumptions and old mislabeled products.
- [ ] Tests and guest evidence are reported separately; unavailable guest
  coverage is visible.
- [ ] No unrelated driver/source changes are included.

## Plan self-review

Spec coverage: metadata/defaults (1), make/explicit targets (2), concrete binary
inspection (3), product and object coverage (4), dependency/cache/missing and
collision handling (5), prerequisites/dry-run (6), resume (7), migration and
real guest proof (8). Interfaces above use unsigned slice masks consistently;
canonical package labels are produced only through architecture_label.

Implementation must preserve existing ownership/cleanup and APK race checks.
The code snippets establish interfaces and critical assertions; the enclosing
functions must retain their existing failure cleanup and argument handling.
