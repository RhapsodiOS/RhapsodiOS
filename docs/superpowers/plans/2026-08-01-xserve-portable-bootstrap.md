# Portable PPC Bootstrap and Clean World Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `vm/build-src.ps1 -All` build host `rbuild`, create a source-only Rhapsody PPC bootstrap sysroot and APK repository, build the kernel/drivers, and finish a resumable clean world build on the Xserve.

**Architecture:** Follow the NetBSD `TOOLDIR + DESTDIR` model for stage 0: GCC-based host tools live under `/build/tools`, while target headers, libraries, and commands accumulate only under `/build/bootstrap-root`. Each stage-0 project still packages from private roots; validated APKs are replayed into the bootstrap sysroot, after which ordinary packages build in fresh chroots populated only from `/build/repo`.

**Tech Stack:** C89, the existing `rbuild` C test harness, POSIX make/sh utilities, PowerShell 5, OpenSSH to Mac OS X Server 10.2 PPC, GCC/Darwin Mach-O provider profiles.

---

## File structure

New focused files:

- `src/rbuild-1/toolchain.h`, `toolchain.c`: parse and validate normalized build/target tool configuration; expand `@SYSROOT@` in provider flags.
- `src/rbuild-1/apk.h`, `apk.c`: validate, quarantine, and extract APK artifacts.
- `src/rbuild-1/runner.h`, `runner.c`: run manifests, replay bootstrap artifacts, aggregate failures, and write atomic project state.
- `src/rbuild-1/toolchains/gcc-darwin.conf`: first GCC provider profile; Jaguar is data, not hard-coded C behavior.
- `src/rbuild-1/tests/test_toolchain.c`, `test_apk.c`: unit tests for the new boundaries.
- `src/rbuild-1/tests/bootstrap-resume.sh`: CLI-level reconstruction and resume test.
- `vm/build-src-lib.ps1`, `vm/test-build-src.ps1`: pure orchestration helpers and dependency-free PowerShell tests.

Existing files with surgical changes:

- `src/rbuild-1/builder.h`, `builder.c`: accept a `BuildOptions` context, inject normalized tools/sysroot, stop touching the live host, and package target objects for replay.
- `src/rbuild-1/main.c`: parse bootstrap options and delegate manifests to `runner.c`.
- `src/rbuild-1/Makefile`: link new modules and tests.
- `src/BootstrapManifest`: order target header/framework/tool providers before consumers.
- `vm/rhap-remote.ps1`, `vm/vm.conf.example`: add output and toolchain-profile configuration.
- `vm/build-src.ps1`: add `-All`/`-Fresh`, build `rbuild` into `TOOLDIR`, and remove temporary seed-script behavior.
- `README.md`, `vm/README.md`, `vm/SSH CONNECTION.md`: document the canonical workflow and portability contract.

## Global constraints

- Preserve C89 declaration rules and the repository's `-Wall -O` compiler compatibility.
- Do not install anything into live `/System`, `/usr`, or `/lib`.
- Do not invoke `_seed-bootstrap-hdrs.sh` or any `_fix-*`, `_install-*`, or `_seed-*` helper.
- Do not silently fall back to host headers or libraries.
- Keep `sync-src.ps1` transfer-only.
- Keep granular build switches while making `-All` the canonical path.
- Commit only files named by the active task; leave unrelated untracked diagnostics untouched.

### Task 1: Parse a portable GCC toolchain profile

**Files:**
- Create: `src/rbuild-1/toolchain.h`
- Create: `src/rbuild-1/toolchain.c`
- Create: `src/rbuild-1/toolchains/gcc-darwin.conf`
- Create: `src/rbuild-1/tests/test_toolchain.c`
- Modify: `src/rbuild-1/Makefile`

- [ ] **Step 1: Write the failing parser/expansion test**

Create `tests/test_toolchain.c` with a temporary profile containing every required key:

```c
#include "toolchain.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>

TEST(test_load_and_expand) {
    Toolchain tc;
    strlist flags;
    FILE *f = fopen("/tmp/rbuild-toolchain.conf", "w");
    fputs("profile=test-gcc\n"
          "build_cc=/host/cc\n"
          "target_cc=/cross/cc\n"
          "target_ar=/cross/ar\n"
          "target_ranlib=/cross/ranlib\n"
          "make=/host/make\n"
          "shell=/bin/sh\n"
          "tar=/usr/bin/tar\n"
          "gzip=/usr/bin/gzip\n"
          "rsync=/usr/bin/rsync\n"
          "path=/tools:/usr/bin:/bin\n"
          "arch_flags=-arch ppc\n"
          "cpp_flags=-nostdinc -I@SYSROOT@/System/Headers\n"
          "ld_flags=-Wl,-syslibroot,@SYSROOT@\n"
          "ln=/tools/ln\n", f);
    fclose(f);
    toolchain_init(&tc);
    CHECK_INT(toolchain_load(&tc, "/tmp/rbuild-toolchain.conf"), 0);
    CHECK_INT(toolchain_validate(&tc), 0);
    CHECK_STR(tc.target_cc, "/cross/cc");
    strlist_init(&flags);
    toolchain_expand_words(tc.cpp_flags, "/target", &flags);
    CHECK_STR(flags.items[0], "-nostdinc");
    CHECK_STR(flags.items[1], "-I/target/System/Headers");
    strlist_free(&flags);
    toolchain_free(&tc);
    remove("/tmp/rbuild-toolchain.conf");
}

TEST(test_missing_target_cc_fails) {
    Toolchain tc;
    toolchain_init(&tc);
    tc.profile = xstrdup("broken");
    CHECK_INT(toolchain_validate(&tc), 1);
    toolchain_free(&tc);
}

static void run_all(void) {
    RUN(test_load_and_expand);
    RUN(test_missing_target_cc_fails);
}
TEST_MAIN()
```

- [ ] **Step 2: Add the test target and verify the expected failure**

Add `toolchain.o` to `OBJS`, `tests/test_toolchain` to `TESTS`, and:

```make
test_toolchain_OBJS = strutil.o toolchain.o
tests/test_toolchain: tests/test_toolchain.c $(test_toolchain_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_toolchain.c $(test_toolchain_OBJS)
```

Run:

```sh
cd src/rbuild-1 && make tests/test_toolchain
```

Expected: FAIL because `toolchain.h` and `toolchain.o` do not exist.

- [ ] **Step 3: Define the toolchain interface**

Create `toolchain.h`:

```c
#ifndef RBUILD_TOOLCHAIN_H
#define RBUILD_TOOLCHAIN_H
#include "strutil.h"

typedef struct {
    char *profile;
    char *build_cc;
    char *target_cc;
    char *target_ar;
    char *target_ranlib;
    char *make;
    char *shell;
    char *tar;
    char *gzip;
    char *rsync;
    char *path;
    char *arch_flags;
    char *cpp_flags;
    char *ld_flags;
    char *ln;
} Toolchain;

void toolchain_init(Toolchain *tc);
void toolchain_free(Toolchain *tc);
int toolchain_load(Toolchain *tc, const char *path);
int toolchain_validate(const Toolchain *tc);
void toolchain_expand_words(const char *value, const char *sysroot,
                            strlist *out);
#endif
```

- [ ] **Step 4: Implement strict `key=value` parsing and sysroot expansion**

In `toolchain.c`, use a table of key-to-field offsets, reject unknown keys and
duplicates, trim surrounding whitespace, and replace every literal `@SYSROOT@`
before `str_split_ws`. Every struct member is required. `toolchain_validate`
must print `rbuild: toolchain profile missing target_cc` when that field is the
first empty required value.

The expansion loop must be literal and C89-safe:

```c
static char *expand_sysroot(const char *value, const char *sysroot) {
    const char *p = value;
    const char marker[] = "@SYSROOT@";
    sbuf out;
    sbuf_init(&out);
    while (*p) {
        const char *hit = strstr(p, marker);
        if (!hit) { sbuf_puts(&out, p); break; }
        sbuf_putn(&out, p, (size_t)(hit - p));
        sbuf_puts(&out, sysroot);
        p = hit + sizeof(marker) - 1;
    }
    p = sbuf_steal(&out);
    sbuf_free(&out);
    return (char *)p;
}

void toolchain_expand_words(const char *value, const char *sysroot,
                            strlist *out) {
    char *expanded = expand_sysroot(value ? value : "", sysroot);
    str_split_ws(expanded, out);
    free(expanded);
}
```

- [ ] **Step 5: Add the first provider profile**

Create `toolchains/gcc-darwin.conf`:

```text
profile=gcc-darwin-ppc-macho
build_cc=/usr/bin/cc
target_cc=/usr/bin/cc
target_ar=/usr/bin/ar
target_ranlib=/usr/bin/ranlib
make=/usr/bin/make
shell=/bin/sh
tar=/usr/bin/tar
gzip=/usr/bin/gzip
rsync=/usr/bin/rsync
path=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
arch_flags=-arch ppc
cpp_flags=-nostdinc -F@SYSROOT@/System/Library/Frameworks -I@SYSROOT@/System/Library/Frameworks/System.framework/Headers -I@SYSROOT@/System/Library/Frameworks/System.framework/PrivateHeaders
ld_flags=-Wl,-syslibroot,@SYSROOT@
ln=/bin/ln
```

This is the first tested mapping. If the installed Developer Tools expose a different executable path, change only this profile after confirming the capability probe in Task 7.

- [ ] **Step 6: Run all host unit tests**

```sh
cd src/rbuild-1 && make test
```

Expected: `test_toolchain` passes and the suite ends with `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```sh
git add src/rbuild-1/Makefile src/rbuild-1/toolchain.c src/rbuild-1/toolchain.h src/rbuild-1/toolchains/gcc-darwin.conf src/rbuild-1/tests/test_toolchain.c
git commit -m "rbuild: add portable GCC toolchain profiles"
```

### Task 2: Pass target tools and sysroot through `builder`

**Files:**
- Modify: `src/rbuild-1/builder.h`
- Modify: `src/rbuild-1/builder.c`
- Modify: `src/rbuild-1/main.c`
- Modify: `src/rbuild-1/tests/test_builder.c`

- [ ] **Step 1: Write failing build-flag and command tests**

Add a `Toolchain` fixture and replace the native-only assertions with:

```c
static void test_toolchain(Toolchain *tc) {
    toolchain_init(tc);
    tc->profile = xstrdup("test");
    tc->target_cc = xstrdup("/tools/target-cc");
    tc->target_ar = xstrdup("/tools/target-ar");
    tc->target_ranlib = xstrdup("/tools/target-ranlib");
    tc->make = xstrdup("/tools/make");
    tc->shell = xstrdup("/bin/sh");
    tc->tar = xstrdup("/tools/tar");
    tc->gzip = xstrdup("/tools/gzip");
    tc->rsync = xstrdup("/tools/rsync");
    tc->path = xstrdup("/tools:/usr/bin:/bin");
    tc->arch_flags = xstrdup("-arch ppc");
    tc->cpp_flags = xstrdup("-nostdinc -I@SYSROOT@/System/Headers");
    tc->ld_flags = xstrdup("-Wl,-syslibroot,@SYSROOT@");
    tc->ln = xstrdup("/tools/ln");
}

TEST(test_bootstrap_flags_use_target_sysroot) {
    Params p;
    Toolchain tc;
    BuildOptions opt;
    strlist flags;
    params_init(&p); test_toolchain(&tc);
    p.SRCROOT=xstrdup("/s"); p.OBJROOT=xstrdup("/o");
    p.SYMROOT=xstrdup("/y"); p.DSTROOT=xstrdup("/d");
    p.HDRROOT=xstrdup("/h"); p.SUBLIBROOTS=xstrdup("/objs");
    build_options_init(&opt);
    opt.bootstrap = 1; opt.sysroot = "/target"; opt.toolchain = &tc;
    strlist_init(&flags);
    builder_buildflags(&p, "install", &flags, &opt);
    CHECK(list_has(&flags, "NEXT_ROOT=/target"));
    CHECK(list_has(&flags, "CC=/tools/target-cc"));
    CHECK(list_has(&flags, "AR=/tools/target-ar"));
    CHECK(list_has(&flags, "RANLIB=/tools/target-ranlib"));
    CHECK(list_has(&flags, "LN=/tools/ln"));
    CHECK(list_has(&flags, "RC_ARCHS=ppc"));
    CHECK(list_has_prefix(&flags, "RC_CFLAGS=-arch ppc -nostdinc"));
    CHECK(list_has_prefix(&flags, "OTHER_LDFLAGS=-Wl,-syslibroot,/target"));
    CHECK(!list_has(&flags, "BOOTSTRAP_SKIP_DYLD=YES"));
    strlist_free(&flags); params_free(&p); toolchain_free(&tc);
}
```

Add `list_has_prefix` beside `list_has`, register the test, and include `toolchain.h` through `builder.h`.

- [ ] **Step 2: Verify the signature failure**

```sh
cd src/rbuild-1 && make tests/test_builder
```

Expected: FAIL because `BuildOptions`, `build_options_init`, and the new `builder_buildflags` signature do not exist.

- [ ] **Step 3: Introduce one build-context structure**

Add to `builder.h`:

```c
#include "toolchain.h"
typedef struct {
    int clean;
    int bootstrap;
    const char *sysroot;
    const char *state_dir;
    const Toolchain *toolchain;
} BuildOptions;

void build_options_init(BuildOptions *opt);
```

Change `builder_buildflags`, `builder_buildcmd`, `builder_setupdirs`,
`builder_harvest_objects`, and `builder_build` to accept `const BuildOptions *`
instead of separate `native`/`clean` booleans. Initialize defaults with
`memset(opt, 0, sizeof(*opt))`.

- [ ] **Step 4: Generate flags only from the normalized contract**

In `builder_buildflags`, keep the existing Rhapsody compatibility defines, but:

```c
push_kv(out, "NEXT_ROOT", opt->bootstrap ? opt->sysroot : "");
if (opt->toolchain) {
    strlist words;
    char *joined;
    push_kv(out, "CC", opt->toolchain->target_cc);
    push_kv(out, "AR", opt->toolchain->target_ar);
    push_kv(out, "RANLIB", opt->toolchain->target_ranlib);
    push_kv(out, "LN", opt->toolchain->ln);
    strlist_init(&words);
    toolchain_expand_words(opt->toolchain->arch_flags, opt->sysroot, &words);
    toolchain_expand_words(opt->toolchain->cpp_flags, opt->sysroot, &words);
    joined = strlist_join(&words, " ");
    push_kv(out, "RC_CFLAGS", joined);
    free(joined); strlist_free(&words);
    strlist_init(&words);
    toolchain_expand_words(opt->toolchain->ld_flags, opt->sysroot, &words);
    joined = strlist_join(&words, " ");
    push_kv(out, "OTHER_LDFLAGS", joined);
    free(joined); strlist_free(&words);
}
```

Add `char *strlist_join(const strlist *list, const char *separator)` to
`strutil.h/.c`, with a unit test proving an empty list yields `""` and three
items yield one-space joining.
Do not emit `BOOTSTRAP_SKIP_DYLD`; target dyld must be built against the target
sysroot.

- [ ] **Step 5: Use configured `make`, `PATH`, and rsync**

`builder_buildcmd` begins with `opt->toolchain->make` in bootstrap mode and
retains `make` inside a target chroot. `run_make` sets `PATH` from
`opt->toolchain->path` and prints the actual value. `builder_setupdirs` uses
the configured rsync executable as argv, not an interpolated shell command.

- [ ] **Step 6: Run tests and command trace**

```sh
cd src/rbuild-1 && make test && make trace-test
```

Expected: all unit tests pass. The legacy non-bootstrap command trace remains
identical; bootstrap-only target flags are covered by `test_builder`.

- [ ] **Step 7: Commit**

```sh
git add src/rbuild-1/builder.c src/rbuild-1/builder.h src/rbuild-1/main.c src/rbuild-1/strutil.c src/rbuild-1/strutil.h src/rbuild-1/tests/test_builder.c src/rbuild-1/tests/test_strutil.c
git commit -m "rbuild: isolate bootstrap builds with target toolchain flags"
```

### Task 3: Validate and replay APKs into the target sysroot

**Files:**
- Create: `src/rbuild-1/apk.h`
- Create: `src/rbuild-1/apk.c`
- Create: `src/rbuild-1/tests/test_apk.c`
- Modify: `src/rbuild-1/Makefile`

- [ ] **Step 1: Write failing valid/corrupt/extract tests**

Create a scratch package containing `.PKGINFO` and `usr/bin/probe`, package it
with `tar | gzip`, and assert:

```c
CHECK_INT(apk_validate("/tmp/rbuild-apk/good.apk", &tc), 0);
CHECK_INT(apk_validate("/tmp/rbuild-apk/bad.apk", &tc), 1);
CHECK_INT(apk_extract("/tmp/rbuild-apk/good.apk",
                      "/tmp/rbuild-apk/root", &tc), 0);
CHECK(file_exists("/tmp/rbuild-apk/root/usr/bin/probe"));
```

Use the test fixture's `/usr/bin/tar` and `/usr/bin/gzip` paths in `Toolchain`.

- [ ] **Step 2: Verify the missing-module failure**

```sh
cd src/rbuild-1 && make tests/test_apk
```

Expected: FAIL because `apk.h`/`apk.o` do not exist.

- [ ] **Step 3: Define the APK boundary**

Create `apk.h`:

```c
#ifndef RBUILD_APK_H
#define RBUILD_APK_H
#include "toolchain.h"
int apk_validate(const char *path, const Toolchain *tc);
int apk_extract(const char *path, const char *root, const Toolchain *tc);
int apk_quarantine(const char *path);
#endif
```

Implement validation as two checked argv calls: `gzip -t <apk>` and
`tar -tzf <apk>`, capturing the listing to confirm an entry whose normalized
name is `.PKGINFO`. Extraction is `mkdir -p <root>` followed by
`tar -xzf <apk> -C <root>`. Quarantine uses `rename(path, path + ".invalid")`
and refuses to overwrite an existing quarantine file.

- [ ] **Step 4: Run the focused and full tests**

```sh
cd src/rbuild-1 && make tests/test_apk && ./tests/test_apk && make test
```

Expected: APK tests pass and the full suite ends `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```sh
git add src/rbuild-1/Makefile src/rbuild-1/apk.c src/rbuild-1/apk.h src/rbuild-1/tests/test_apk.c
git commit -m "rbuild: validate and extract bootstrap APKs"
```

### Task 4: Add a resumable manifest runner

**Files:**
- Create: `src/rbuild-1/runner.h`
- Create: `src/rbuild-1/runner.c`
- Create: `src/rbuild-1/tests/bootstrap-resume.sh`
- Modify: `src/rbuild-1/main.c`
- Modify: `src/rbuild-1/Makefile`
- Modify: `src/rbuild-1/exec.h`
- Modify: `src/rbuild-1/exec.c`
- Modify: `src/rbuild-1/tests/test_exec.c`

- [ ] **Step 1: Write a failing CLI reconstruction test**

The shell test creates a one-project source fixture, valid base/header APKs
containing distinct marker files, an empty sysroot, and invokes:

```sh
./rbuild bootstrap --sysroot /tmp/rb-resume/root \
  --toolchain /tmp/rb-resume/toolchain.conf \
  --state /tmp/rb-resume/state \
  /tmp/rb-resume/Manifest /tmp/rb-resume/repo /tmp/rb-resume/repo
test -f /tmp/rb-resume/root/usr/bin/foo
test -f /tmp/rb-resume/root/System/Headers/foo.h
test -f /tmp/rb-resume/state/projects/foo-1.0-all.done
```

Then remove only `root`, rerun, and assert both marker files return while the
APK mtimes remain unchanged. Finally change `cpp_flags` in the profile and
assert resume exits nonzero with `toolchain state mismatch; use -Fresh`.

- [ ] **Step 2: Verify option parsing fails**

```sh
cd src/rbuild-1 && make rbuild && sh tests/bootstrap-resume.sh
```

Expected: FAIL with usage output because bootstrap options are not recognized.

- [ ] **Step 3: Add streamed persistent command logging**

First add this failing test to `tests/test_exec.c`:

```c
TEST(test_log_tees_child_output) {
    char *cmd[] = { "sh", "-c", "printf logged-output", 0 };
    char buf[64];
    FILE *f;
    remove("/tmp/rbuild-exec.log");
    CHECK_INT(exec_set_log("/tmp/rbuild-exec.log"), 0);
    CHECK_INT(exec_run(cmd), 0);
    exec_clear_log();
    f = fopen("/tmp/rbuild-exec.log", "r");
    CHECK(f != 0);
    memset(buf, 0, sizeof(buf));
    fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    CHECK_STR(buf, "logged-output");
    remove("/tmp/rbuild-exec.log");
}
```

Declare `int exec_set_log(const char *path)` and `void exec_clear_log(void)` in
`exec.h`. In `exec_run`, when logging is active, create a pipe before `fork`;
the child `dup2`s the write end onto stdout and stderr, while the parent reads
the pipe, writes each block to its own stdout and the opened append-mode log,
then waits for the child. Close every pipe/file descriptor in both processes.
Without an active log, preserve the existing fast path exactly.

Run `make tests/test_exec && ./tests/test_exec`; expected: all exec tests pass
and `logged-output` is both displayed and present in the file.

- [ ] **Step 4: Define runner options and API**

Create `runner.h`:

```c
#ifndef RBUILD_RUNNER_H
#define RBUILD_RUNNER_H
#include "toolchain.h"
typedef struct {
    int bootstrap;
    const char *sysroot;
    const char *state_dir;
    const Toolchain *toolchain;
} RunnerOptions;
int runner_manifest(const char *srclist, const char *seeddir,
                    const char *dstdir, const RunnerOptions *opt);
#endif
```

- [ ] **Step 5: Move manifest execution out of `main.c`**

`runner_manifest` owns the existing scan/build loop. For each entry it computes
the exact base package canonical name and its `-hdrs`/`-obj` variants. Required
artifacts are: header APK for `headers`; base APK plus any emitted header/object
APKs for `all`. Existing artifacts must pass `apk_validate`; invalid artifacts
are quarantined and rebuilt.

In bootstrap mode, replay all valid emitted APKs into `sysroot` in manifest
order, even when the build itself is skipped. Compute an FNV-1a fingerprint over
the complete toolchain file and another over `type`, `source`, and `target` from
the manifest entry. Write the completion record to the project's `.done.tmp`
path under the configured state directory, `fflush`/`fclose`, then rename it to
`.done`. A fixture record is:

```text
profile=test-gcc
toolchain_fingerprint=7d53b8a1
entry_fingerprint=2c249f09
source=foo-1.0
target=all
package=/tmp/rb-resume/repo/foo-1.0.apk
```

On resume, an existing record with a different profile or fingerprint is a
hard error naming `-Fresh`; never combine configurations.

Return nonzero if scanning, building, validation, extraction, or state writing
fails. Non-bootstrap world mode may continue after a project failure, but must
return nonzero after the loop if any project failed.

Before each project command, create `<state>/logs` and call `exec_set_log` with
`<state>/logs/<canon>-<target>.log`; call `exec_clear_log` on every success and
failure exit. This keeps child output visible over SSH and persistent without a
shell pipeline.

- [ ] **Step 6: Parse bootstrap options in `main.c`**

Support these forms:

```text
rbuild bootstrap --sysroot ROOT --toolchain FILE --state DIR MANIFEST REPO DST
rbuild buildall --state DIR MANIFEST REPO DST
rbuild buildpackage --state DIR [--dir] [--target TARGET] SOURCE REPO DST
```

Load and validate `Toolchain`, require absolute `ROOT` and `DIR`, initialize
`RunnerOptions`, call `runner_manifest`, and free the profile. Preserve the
three existing positional arguments for `buildall` and `buildpackage`; their
new `--state` option only selects persistent project logs/state. The old forms
without `--state` remain valid for compatibility.

- [ ] **Step 7: Run resume, unit, and trace tests**

```sh
cd src/rbuild-1 && sh tests/bootstrap-resume.sh && make test && make trace-test
```

Expected: reconstruction passes, all unit tests pass, and non-bootstrap trace
compatibility remains intact.

- [ ] **Step 8: Commit**

```sh
git add src/rbuild-1/Makefile src/rbuild-1/main.c src/rbuild-1/runner.c src/rbuild-1/runner.h src/rbuild-1/exec.c src/rbuild-1/exec.h src/rbuild-1/tests/test_exec.c src/rbuild-1/tests/bootstrap-resume.sh
git commit -m "rbuild: resume bootstrap manifests from validated APKs"
```

### Task 5: Remove all live-host seeding from package roots

**Files:**
- Modify: `src/rbuild-1/builder.c`
- Modify: `src/rbuild-1/tests/test_builder.c`
- Modify: `src/rbuild-1/tests/trace/run.sh`

- [ ] **Step 1: Add a failing no-host-seed command test**

Run `builder_makeroot` under `exec_dry_run` with a complete stub dependency
repository, capture its command trace, and assert it contains none of:

```text
/usr/lib/dyld
/lib/crt1.o
/usr/bin/strip.real
/build/bin
```

Also update object-harvest tests to assert bootstrap mode copies only into the
private `LIBCOBJROOT`; it must not copy into live `/usr/local/lib/objs`.

- [ ] **Step 2: Run the focused test and observe failure**

```sh
cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder
```

Expected: FAIL because current `builder_makeroot` seeds host dyld, crt1, and
strip, while native object harvest copies into live `SUBLIBROOTS`.

- [ ] **Step 3: Delete the host-seed blocks**

Remove the three `builder_makeroot` blocks beginning with the comments
`Stage-0 skipped cctools dyld`, `csu.apk may predate`, and `cctools apk
overwrites`. Remove the native live-`SUBLIBROOTS` copy block from
`builder_harvest_objects`. Retain copying to the private object package root;
Task 4 replays the resulting `-obj` APK into the target sysroot.

Replace hard-coded `/build/bin` PATH and `LN` behavior with values from the
selected toolchain profile. Do not add alternate host fallback paths.

- [ ] **Step 4: Verify tests and source scan**

```sh
cd src/rbuild-1 && make test && make trace-test
rg -n 'seed.*host|/lib/crt1.o|strip.real|/build/bin|live SUBLIBROOTS' builder.c
```

Expected: tests pass; `rg` returns no matches.

- [ ] **Step 5: Commit**

```sh
git add src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c src/rbuild-1/tests/trace/run.sh
git commit -m "rbuild: remove live-host bootstrap seeding"
```

### Task 6: Make the target bootstrap closure explicit

**Files:**
- Modify: `src/BootstrapManifest`
- Create: `src/rbuild-1/tests/bootstrap-closure.sh`
- Modify: `src/rbuild-1/Makefile`

- [ ] **Step 1: Add a static closure test**

Create `tests/bootstrap-closure.sh` to parse `basedeps[]` from `builder.c`, scan
each manifest project with `rbuild missing`, and assert the manifest provides
every base dependency plus these known header inputs:

```text
architecture-hdrs kernel-hdrs libc-hdrs objc4-hdrs
libstreams-hdrs driverkit-hdrs cctools-hdrs
```

The test must also assert `bison-1` precedes `cc-1`, the header-only
`pb_makefiles-1` and `project_makefiles-1` entries precede `kernel-7`, and every
target header provider precedes `Libc-1`. The host `relpath` used by kernel
header installation is built into `/build/tools/bin` by Task 8.

- [ ] **Step 2: Run the test to expose ordering/coverage gaps**

```sh
cd src/rbuild-1 && sh tests/bootstrap-closure.sh
```

Expected: FAIL naming any provider not represented or ordered correctly.

- [ ] **Step 3: Set the canonical bootstrap order**

Keep the existing three-column format. Use header-only entries to install the
frameworks and target headers before any target C program is compiled, then
repeat those projects with `all` later when the sysroot can compile them. Order
these groups:

```text
CoreOSMakefiles-1(all), pb_makefiles-1(headers), project_makefiles-1(headers)
architecture-1(headers), kernel-7(headers), Libstreams-1(headers), objc4-1(headers), driverkit-3(headers), cctools-2(headers)
bison-1, cc-1, cctools-2, gnumake-1, gnutar-1, awk-1, grep-1, patch-1
pb_makefiles-1(all), project_makefiles-1(all), Commands/bootstrap_cmds(all)
Csu-1, objc4-1(all), Libstreams-1(all), driverkit-3(all)
Libc-1, Libcompat-1, Libcurses-1, Libedit-1, Libinfo-1, Libkvm-1, Libm-1, Libsystem-2
files-5 and the Commands/* build-base projects
```

Use the actual source directory names already present in the tree. Do not add a
copy directive or a host path to the manifest.

- [ ] **Step 4: Verify header providers package their owned files**

On the Xserve after Tasks 1-5 are synced, run the bootstrap through each header
provider and inspect APK listings:

```sh
tar -tzf /build/repo/kernel-hdrs-*.apk | grep -E 'bsd/dev/(ppc/)?evio.h|PrivateHeaders/mach_debug'
tar -tzf /build/repo/libstreams-hdrs-*.apk | grep 'PrivateHeaders/streams/streams.h'
tar -tzf /build/repo/objc4-hdrs-*.apk | grep 'Headers/objc/maptable.h'
tar -tzf /build/repo/cctools-hdrs-*.apk | grep 'Headers/mach-o/rld.h'
tar -tzf /build/repo/driverkit-hdrs-*.apk | grep 'PrivateHeaders/driverkit/Event.defs'
```

Expected: every command finds its owned target header. The inspected project
rules already declare these files: a failure is therefore a reproducible
bootstrap defect, not permission to copy the file manually. Stop at the first
failure and diagnose it with `superpowers:systematic-debugging` before changing
the owning project's rule.

- [ ] **Step 5: Run closure and unit tests**

```sh
cd src/rbuild-1 && sh tests/bootstrap-closure.sh && make test
```

Expected: static closure passes and all unit tests pass.

- [ ] **Step 6: Commit**

```sh
git add src/BootstrapManifest src/rbuild-1/Makefile src/rbuild-1/tests/bootstrap-closure.sh
git commit -m "bootstrap: package the complete target header closure"
```

### Task 7: Add testable PowerShell preflight and safe output handling

**Files:**
- Create: `vm/build-src-lib.ps1`
- Create: `vm/test-build-src.ps1`
- Modify: `vm/rhap-remote.ps1`
- Modify: `vm/vm.conf.example`

- [ ] **Step 1: Write failing dependency-free PowerShell tests**

Test these pure functions:

```powershell
. "$PSScriptRoot\build-src-lib.ps1"
Assert-RhapSafeRemoteOutputPath -RemoteRoot '/build' -Path '/build/repo'
Assert-Throws { Assert-RhapSafeRemoteOutputPath -RemoteRoot '/build' -Path '/' }
Assert-Throws { Assert-RhapSafeRemoteOutputPath -RemoteRoot '/build' -Path '/usr' }
$phases = Get-RhapBuildPhases -All
Assert-Equal ($phases -join ',') 'rbuild,bootstrap,kernel-drivers,world'
$cmd = New-RhapPreflightCommand -SourceRoot '/build/src' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -StateDir '/build/state' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
Assert-Match $cmd 'test -x /usr/bin/cc'
Assert-Match $cmd '/usr/bin/cc -arch ppc -c'
Assert-Match $cmd 'case-sensitive filesystem required'
```

Implement `Assert-Throws`, `Assert-Equal`, and `Assert-Match` inside the test
script so no Pester installation is required.

- [ ] **Step 2: Verify the missing-library failure**

```powershell
powershell -NoProfile -File vm\test-build-src.ps1
```

Expected: FAIL because `build-src-lib.ps1` does not exist.

- [ ] **Step 3: Implement the pure helper library**

`Assert-RhapSafeRemoteOutputPath` normalizes repeated `/`, rejects `.`/`..`,
requires an absolute path, requires `Path` to start with `RemoteRoot + '/'`, and
rejects equality with `RemoteRoot`. `Get-RhapBuildPhases` returns the canonical
four-phase order for `-All` or the one selected phase.

`New-RhapPreflightCommand` emits one POSIX `sh` command that checks profile
existence, reads the configured executables, checks free space, creates a
case-probe pair whose names differ only by case, and removes only those probe
files. It compiles `int rbuild_probe;` with `BUILD_CC`, then with `TARGET_CC`
and `arch_flags`, verifies both objects are nonempty, and removes them. It must
not create the build outputs yet.

- [ ] **Step 4: Add configuration defaults**

Add to `Get-RhapVmConfig` and `vm.conf.example`:

```text
ToolsDir=/build/tools
BootstrapRoot=/build/bootstrap-root
StateDir=/build/state
ToolchainProfile=rbuild-1/toolchains/gcc-darwin.conf
```

Resolve relative `ToolchainProfile` beneath `RemoteRoot/src`.

- [ ] **Step 5: Run tests**

```powershell
powershell -NoProfile -File vm\test-build-src.ps1
```

Expected: `build-src tests: PASS`.

- [ ] **Step 6: Commit**

```sh
git add vm/build-src-lib.ps1 vm/test-build-src.ps1 vm/rhap-remote.ps1 vm/vm.conf.example
git commit -m "build: add portable Xserve preflight checks"
```

### Task 8: Make `build-src.ps1 -All` the resumable orchestrator

**Files:**
- Modify: `vm/build-src.ps1`
- Modify: `vm/test-build-src.ps1`

- [ ] **Step 1: Add failing command-generation tests**

Assert the generated remote commands contain:

```text
rbuild:        cd /build/src/rbuild-1 && /usr/bin/make clean test all && install -d /build/tools/bin && install -c -m 755 rbuild /build/tools/bin/rbuild && /usr/bin/cc -O -o /build/tools/bin/relpath /build/src/Commands/bootstrap_cmds/relpath.tproj/relpath.c
bootstrap:     /build/tools/bin/rbuild bootstrap --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo
kernel:        /build/tools/bin/rbuild buildpackage --state /build/state --dir kernel-7 /build/repo /build/built
world:         /build/tools/bin/rbuild buildall --state /build/state Manifest /build/repo /build/built
```

Assert none contain `/tmp/_`, `_seed-bootstrap-hdrs.sh`, `DSTROOT=/`, or
`/usr/bin/rbuild`.

- [ ] **Step 2: Verify tests fail against current orchestration**

```powershell
powershell -NoProfile -File vm\test-build-src.ps1
```

Expected: FAIL because `-All`, `-Fresh`, and the isolated commands do not exist.

- [ ] **Step 3: Add the canonical switches**

Use this parameter shape:

```powershell
param(
    [switch]$All,
    [switch]$Rbuild,
    [switch]$Bootstrap,
    [switch]$KernelDrivers,
    [switch]$World,
    [switch]$Fresh
)
```

Require exactly one mode from the first five; `Fresh` is only a modifier.
Dot-source `build-src-lib.ps1`, resolve safe paths, run preflight once, and loop
over `Get-RhapBuildPhases`.

- [ ] **Step 4: Implement safe fresh behavior**

After local and remote safety checks, `-Fresh` removes exactly the configured
`ToolsDir`, `BootstrapRoot`, `RepoDir`, `BuiltDir`, and `StateDir`, then recreates
their parents. It must use literal configured paths in one remote POSIX shell;
do not build a wildcard or derive deletion targets from remote output.

- [ ] **Step 5: Remove workaround orchestration**

Delete the date-setting/header-seed upload and invocation from `-Bootstrap`.
Build `rbuild` with the profile's `build_cc`, run its tests, and install it to
`ToolsDir/bin`. Invoke Tasks 4's bootstrap CLI. Retain required core package
failure behavior and optional-driver summary behavior.

- [ ] **Step 6: Run PowerShell tests and syntax validation**

```powershell
powershell -NoProfile -File vm\test-build-src.ps1
$errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'vm\build-src.ps1'),[ref]$null,[ref]$errors); if($errors){$errors;exit 1}
```

Expected: tests pass and the parser reports no errors.

- [ ] **Step 7: Commit**

```sh
git add vm/build-src.ps1 vm/test-build-src.ps1
git commit -m "build: orchestrate resumable bootstrap and world builds"
```

### Task 9: Prove the Xserve bootstrap and clean-package boundary

**Files:**
- Create: `docs/build/xserve-bootstrap.md`

- [ ] **Step 1: Install the accepted prerequisite and capture versions**

After Jaguar Developer Tools are installed on `root@10.10.0.113`, run:

```sh
cc --version
gnumake --version
ld -v
as -v
```

Expected: all tools execute and the compiler accepts `-arch ppc`. Record exact
versions in `docs/build/xserve-bootstrap.md`.

- [ ] **Step 2: Sync and run a fresh bootstrap**

```powershell
powershell -File vm\sync-src.ps1 -All
powershell -File vm\build-src.ps1 -Rbuild
# Run on the Xserve before -Fresh (which intentionally recreates /build/state):
find /System /usr /lib -type f -exec cksum {} \; | sort > /build/host-before.cksum
powershell -File vm\build-src.ps1 -All -Fresh
```

Expected: preflight passes, `rbuild` tests pass remotely, and bootstrap begins
without uploading or invoking any `/tmp/_*` helper.

- [ ] **Step 3: Enforce contamination checks at the first C compile and link**

Run the resolved target compiler with the profile's expanded flags:

```sh
echo | /usr/bin/cc -arch ppc -nostdinc \
  -F/build/bootstrap-root/System/Library/Frameworks \
  -I/build/bootstrap-root/System/Library/Frameworks/System.framework/Headers \
  -I/build/bootstrap-root/System/Library/Frameworks/System.framework/PrivateHeaders \
  -v -E - 2>&1 | tee /build/state/target-include-search.log
```

Add `-Wl,-map,/build/state/target-link.map` to the first target link probe.
Fail verification if either log resolves an input below live `/System`,
`/usr/include`, `/usr/lib`, or `/lib`. Allowed roots are `/build/src`,
`/build/tools`, and `/build/bootstrap-root`; the compiler executable and its
internal compiler runtime are allowed from the selected provider.

- [ ] **Step 4: Complete and validate build-base**

```sh
cd /build/src
/build/tools/bin/rbuild missing BootstrapManifest /build/repo
find /build/repo -name '*.apk' -type f -print | sort
```

Expected: `missing` prints nothing, and every APK passes the Task 3 validator.
If the target exposes a source/build-rule defect not covered by this plan, stop
at that command, use `superpowers:systematic-debugging`, and write a focused
follow-up plan naming the literal failing file and regression test. Do not add
an unplanned copy or host fallback.

- [ ] **Step 5: Prove reconstruction and interruption safety**

Move `/build/bootstrap-root` to `/build/bootstrap-root.saved`, rerun
`build-src.ps1 -Bootstrap`, compare file inventories, then remove the saved
copy only after the comparison passes. Interrupt one disposable project build,
resume, and confirm no `.done` record was accepted before its APK validated.

- [ ] **Step 6: Prove the clean package boundary**

Build one representative package with `rbuild buildpackage`, inspect its
makeroot log, and assert every installed build dependency came from
`/build/repo`. The build root must contain no file copied directly from the live
host by `rbuild`.

- [ ] **Step 7: Build kernel/drivers and world, then verify no-op resume**

```powershell
powershell -File vm\build-src.ps1 -KernelDrivers
powershell -File vm\build-src.ps1 -World
powershell -File vm\build-src.ps1 -All
```

Expected: required kernel/core drivers and world succeed; the final `-All`
validates and skips completed artifacts rather than recompiling them.

- [ ] **Step 8: Audit the live host**

Capture and compare the same file set:

```sh
find /System /usr /lib -type f -exec cksum {} \; | sort > /build/host-after.cksum
diff -u /build/host-before.cksum /build/host-after.cksum
```

Expected: no difference. Investigate an OS-generated change rather than adding
a blanket exclusion; the three roots should be stable on this dedicated box.

- [ ] **Step 9: Commit verification evidence**

```sh
git add docs/build/xserve-bootstrap.md
git commit -m "bootstrap: complete clean PPC source bootstrap"
```

### Task 10: Document the portable workflow and remove documented hack paths

**Files:**
- Modify: `README.md`
- Modify: `vm/README.md`
- Modify: `vm/SSH CONNECTION.md`
- Modify: `src/rbuild-1/README.md`

- [ ] **Step 1: Update user-facing commands**

Document:

```powershell
powershell -File vm\sync-src.ps1 -All
powershell -File vm\build-src.ps1 -All
```

Explain `-Fresh`, the four granular phase switches, output directories,
artifact-validated resume, and how to select a different GCC profile.

- [ ] **Step 2: Replace the old host-native bootstrap description**

Remove claims that stage 0 builds against host `/` or requires a Rhapsody host
root. Describe the supported contract: GCC provider for host tools, exclusive
Rhapsody target sysroot, then clean APK-populated package roots.

- [ ] **Step 3: Document troubleshooting without temporary scripts**

Point users to `/build/state/logs`, `rbuild missing`, toolchain probe output,
and the exact granular resume commands. Do not recommend `_seed-*`, `_fix-*`,
or `/tmp` upload helpers.

- [ ] **Step 4: Verify documentation and the full local test suite**

```powershell
rg -n '_seed-bootstrap-hdrs|DSTROOT=/|rbuild bootstrap BootstrapManifest' README.md vm/README.md 'vm/SSH CONNECTION.md' src/rbuild-1/README.md
powershell -NoProfile -File vm\test-build-src.ps1
```

Expected: `rg` finds no obsolete workflow; PowerShell tests pass. Also run on a
POSIX development host:

```sh
cd src/rbuild-1 && make clean && make test && make trace-test && sh tests/bootstrap-resume.sh && sh tests/bootstrap-closure.sh
```

Expected: every suite passes.

- [ ] **Step 5: Commit**

```sh
git add README.md vm/README.md 'vm/SSH CONNECTION.md' src/rbuild-1/README.md
git commit -m "docs: document portable PPC build workflow"
```

## Final verification

- [ ] Run `git status --short` and confirm only pre-existing unrelated files remain untracked or modified.
- [ ] Run every local C, trace, shell, and PowerShell test named above from a clean build.
- [ ] Run `build-src.ps1 -All` on the Xserve and retain the successful `/build/state/logs` evidence.
- [ ] Run `build-src.ps1 -All` again and confirm it is a no-op apart from validation.
- [ ] Confirm the host-root audit reports no build mutations.
- [ ] Use `superpowers:requesting-code-review` before integration.
- [ ] Use `superpowers:verification-before-completion` before claiming the implementation complete.
- [ ] Use `superpowers:finishing-a-development-branch` to choose merge, PR, or cleanup.
