# Configured Archive-Create Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route configured APK creation through a generic pax ustar backend while retaining tar only for extraction and the no-profile legacy fallback.

**Architecture:** Add required `archive_create` and `archive_create_flags` toolchain fields and remove `tar_create_flags`. Configured pkginfo creation changes the archive child's working directory to the package root and invokes the configured creator plus expanded flags and `.`, while gzip and unconfigured tar behavior remain unchanged.

**Tech Stack:** C89/POSIX process pipelines, pax/ustar, PowerShell 5.1 profile generation tests, existing rbuild C test harness.

---

### Task 1: Define the schema contract

**Files:**
- Modify: `src/rbuild-1/tests/test_toolchain.c`
- Modify: `vm/test-build-src.ps1`

- [ ] **Step 1: Write failing C schema tests**

Change the profile fixture to emit:

```c
fputs("tar=/usr/bin/tar\n", fp);
if (include_archive_create)
    fputs("archive_create=/bin/pax\n", fp);
if (include_archive_create_flags)
    fputs("archive_create_flags=-w -x ustar\n", fp);
```

Assert successful load exposes both values; missing creator and missing flags each fail validation; `tar_create_flags` is rejected as unknown.

- [ ] **Step 2: Write failing PowerShell schema/preflight tests**

Assert the real profile contains `/bin/pax` and `-w -x ustar`, both new fields are required, `tar_create_flags` is unknown, and generated preflight reads `ARCHIVE_CREATE_TOOL` and includes it in the absolute executable loop.

- [ ] **Step 3: Run focused tests and verify RED**

Run the LLVM-built `tests/test_toolchain` and `vm/test-build-src.ps1`. Expect failures because the fields are not recognized.

### Task 2: Define configured creation behavior

**Files:**
- Modify: `src/rbuild-1/tests/test_pkginfo.c`

- [ ] **Step 1: Replace the tar-specific configured argv expectation**

Use a creator wrapper and assert its argv is exactly:

```text
-w
-x
ustar
.
```

Have the wrapper record `pwd` and delegate to `/bin/pax`; assert the recorded directory equals `root_dir`. Keep the no-toolchain tar wrapper test and its `-C ROOT -cf - .` expectation unchanged.

- [ ] **Step 2: Add strict long-path raw archive proof**

Create a payload whose ustar `prefix/name` combination exceeds 100 bytes, build the APK with the configured profile, decompress it, and scan 512-byte headers. For every nonzero header assert typeflag is NUL or `0` through `5`, and assert neither type `L` nor the name `././@LongLink` occurs. Then run `apk_validate` and `apk_extract` and verify the long payload.

- [ ] **Step 3: Add configured fail-fast cases**

Set `archive_create` to null, then set `archive_create_flags` to null and whitespace-only values. Assert `pkginfo_build_apk` returns 1 without accepting output.

- [ ] **Step 4: Run `tests/test_pkginfo` and verify RED**

Expect the old implementation to use `tar` and tar-specific arguments.

### Task 3: Implement and propagate the schema

**Files:**
- Modify: `src/rbuild-1/toolchain.h`
- Modify: `src/rbuild-1/toolchain.c`
- Modify: `src/rbuild-1/toolchains/gcc-darwin.conf`
- Modify: `src/rbuild-1/tests/bootstrap-resume.sh`
- Modify: `src/rbuild-1/tests/test_builder.c`
- Modify: `vm/build-src-lib.ps1`

- [ ] **Step 1: Replace the C field**

Use:

```c
char *tar;
char *archive_create;
char *archive_create_flags;
char *gzip;
```

Add both new fields to the generic field table and remove `tar_create_flags`; existing init/free/load/validate logic then owns and requires them.

- [ ] **Step 2: Update canonical and test profiles**

Replace `tar_create_flags=--posix` with:

```text
archive_create=/bin/pax
archive_create_flags=-w -x ustar
```

Update builder and bootstrap fixtures to supply the new required capability.

- [ ] **Step 3: Update PowerShell profile and preflight**

Add the two keys to `$script:RhapToolchainKeys`, read `ARCHIVE_CREATE_TOOL=$(profile_value archive_create)`, and include it in the existing absolute executable verification loop. Do not use it in extraction commands.

- [ ] **Step 4: Run schema tests and verify GREEN**

Run the focused C toolchain test and PowerShell suite. Expect the schema tests to pass while pkginfo behavior remains RED.

### Task 4: Implement configured creator cwd and argv

**Files:**
- Modify: `src/rbuild-1/pkginfo.c`

- [ ] **Step 1: Separate archive command construction**

For `tc != NULL`, require `archive_create`, `archive_create_flags`, and `gzip`, expand the flags, append `.`, and pass `root_dir` as the child working directory. For `tc == NULL`, retain `tar -C root_dir -cf - .` and no child cwd override.

- [ ] **Step 2: Guard configured child cwd**

Extend the pipeline helper with `archive_cwd`; in the archive child execute:

```c
if (archive_cwd != 0 && chdir(archive_cwd) != 0) _exit(127);
execvp(archive_argv[0], archive_argv);
```

Leave gzip argv, pipe ownership, waits, and failed-output unlink behavior unchanged.

- [ ] **Step 3: Run pkginfo and full rbuild tests**

Run `gnumake clean test` on the target-capable environment when available. Locally run every portable focused test and require the long-path raw scanner to pass wherever `/bin/pax` is present.

### Task 5: Verify and commit

**Files:**
- Verify all files above plus `docs/superpowers/specs/2026-08-02-archive-create-backend-design.md`.

- [ ] **Step 1: Run local gates**

Run the full PowerShell suite with explicit wrapper exit, PowerShell parser checks, shell syntax checks for bootstrap fixtures, LLVM-focused C tests, and `git diff --check`.

- [ ] **Step 2: Audit behavior boundaries**

Confirm configured creation never references `tc->tar`, extraction still does, no `tar_create_flags` remains outside rejection tests/history, and no validator relaxation or GNU LongLink allowance was added.

- [ ] **Step 3: Commit focused changes**

Stage only the schema, creation implementation/tests, canonical fixtures, spec, and plan. Commit with a short build-subsystem message. Do not run remote bootstrap or install anything live.
