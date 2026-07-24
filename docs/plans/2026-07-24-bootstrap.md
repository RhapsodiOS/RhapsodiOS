# From-source Build Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `rbuild` produce the initial `build-base` `.apk` set from RhapsodiOS source with no pre-built package repository, via a new `rbuild bootstrap` subcommand that builds natively against the host root (no chroot, no dependency install), so the whole system can then build itself.

**Architecture:** Add a `native` flag that threads through `builder_build` → `builder_setupdirs` / `builder_buildcmd` / `builder_harvest_objects`, gating exactly four points: skip `builder_makeroot`, skip the chroot `BUILDROOT` mkdir, drop the `chroot <BUILDROOT>` wrapper on the `make` command, and use a plain `cp` for object harvest. A new `bootstrap` subcommand drives this over a curated `src/BootstrapManifest`. Stages 1–2 reuse the existing `buildall` path unchanged.

**Tech Stack:** C89 (`-ansi -pedantic -Wall`), the in-tree unit-test harness (`tests/test.h`), GNU make. Runtime tools: `make`, `rsync`, `tar`, `gzip`, `cp`, `rm`, `mkdir`.

## Global Constraints

- **C89 only** — code must compile clean under `cc -ansi -pedantic -Wall -O` (see `src/rbuild-1/Makefile:2`). Declarations before statements; no `//` comments.
- **Surgical changes** — touch only what the feature requires; match surrounding style; do not refactor unrelated code.
- **The `native` flag is the last parameter** added to each modified function signature, an `int` (0 = normal chroot build, 1 = native host build).
- **Bootstrap builds pass `clean = !native`** — i.e. `bootstrap` never runs the chroot teardown (`clean = 0`), `buildall` keeps `clean = 1`, `buildpackage` keeps `clean = 0`.
- **Seed compiler is `cc-1`** (not `cc-791`).
- **Commit messages** start with `rbuild: ` (or `docs: ` for doc-only) and describe behavior, one to two lines, no metadata.
- All work is under `src/rbuild-1/` unless a task says otherwise.

---

### Task 1: `native` parameter on `builder_buildcmd`

Make the build command omit the `chroot <BUILDROOT>` prefix in native mode. This is a pure function (builds a `strlist`), so it is directly unit-testable.

**Files:**
- Modify: `src/rbuild-1/builder.h:37-38` (declaration)
- Modify: `src/rbuild-1/builder.c:288-303` (`builder_buildcmd`)
- Modify: `src/rbuild-1/builder.c:941,949` (the two callers inside `builder_build` — add `, 0` for now; Task 3 replaces the literal with the real flag)
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Produces: `void builder_buildcmd(const Params *chroot_params, const Params *build_params, const char *target, strlist *out, int native)`. When `native != 0`, `out` begins with `"make"` (no `"chroot"`, no `BUILDROOT`); when `native == 0`, unchanged (`"chroot"`, `chroot_params->BUILDROOT`, `"make"`, …).

- [ ] **Step 1: Add `#include "exec.h"` to the test file (needed by later tasks) and write the failing test**

In `src/rbuild-1/tests/test_builder.c`, add near the top after `#include "test.h"`:

```c
#include "exec.h"
```

Add this test function after `test_buildflags` (around line 135):

```c
TEST(test_buildcmd_native) {
    Params cp, bp;
    strlist cmd;
    params_init(&cp); params_init(&bp);
    cp.BUILDROOT = xstrdup("/br");
    bp.SRCROOT = xstrdup("/s"); bp.OBJROOT = xstrdup("/o");
    bp.SYMROOT = xstrdup("/y"); bp.DSTROOT = xstrdup("/d");
    bp.HDRROOT = xstrdup("/h"); bp.SUBLIBROOTS = xstrdup("/objs");

    /* native: no chroot wrapper, make is first token, -C uses SRCROOT */
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, 1);
    CHECK_STR(cmd.items[0], "make");
    CHECK(!list_has(&cmd, "chroot"));
    CHECK(!list_has(&cmd, "/br"));
    CHECK(list_has(&cmd, "/s"));         /* -C <SRCROOT> */
    strlist_free(&cmd);

    /* non-native: chroot wrapper present */
    strlist_init(&cmd);
    builder_buildcmd(&cp, &bp, "install", &cmd, 0);
    CHECK_STR(cmd.items[0], "chroot");
    CHECK_STR(cmd.items[1], "/br");
    CHECK_STR(cmd.items[2], "make");
    strlist_free(&cmd);

    params_free(&cp); params_free(&bp);
}
```

Register it in `run_all()` (after `RUN(test_buildflags);`):

```c
    RUN(test_buildcmd_native);
```

- [ ] **Step 2: Run test to verify it fails to compile**

```bash
cd src/rbuild-1 && make tests/test_builder
```
Expected: FAIL — compile error, `builder_buildcmd` called with 5 args but declared with 4 (`too many arguments to function`).

- [ ] **Step 3: Update the declaration**

In `src/rbuild-1/builder.h`, replace lines 37-38:

```c
void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out);
```
with:
```c
void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out, int native);
```

- [ ] **Step 4: Update the definition**

In `src/rbuild-1/builder.c`, replace the head of `builder_buildcmd` (lines 288-294):

```c
void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out) {
    size_t i;
    strlist flags;
    strlist_push(out, "chroot");
    strlist_push(out, chroot_params->BUILDROOT);
    strlist_push(out, "make");
```
with:
```c
void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out, int native) {
    size_t i;
    strlist flags;
    if (!native) {
        strlist_push(out, "chroot");
        strlist_push(out, chroot_params->BUILDROOT);
    }
    strlist_push(out, "make");
```

- [ ] **Step 5: Update the two callers inside `builder_build`**

In `src/rbuild-1/builder.c`, line 941, change:
```c
        builder_buildcmd(&params, &bparams, "installhdrs", &cmd);
```
to:
```c
        builder_buildcmd(&params, &bparams, "installhdrs", &cmd, 0);
```
And line 949, change:
```c
        builder_buildcmd(&params, &bparams, "install", &cmd);
```
to:
```c
        builder_buildcmd(&params, &bparams, "install", &cmd, 0);
```

- [ ] **Step 6: Run test to verify it passes**

```bash
cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder
```
Expected: PASS — all builder tests pass, including `test_buildcmd_native`.

- [ ] **Step 7: Commit**

```bash
cd src/rbuild-1 && git add builder.h builder.c tests/test_builder.c
git commit -m "rbuild: add native flag to builder_buildcmd (skip chroot wrapper)"
```

---

### Task 2: `native` parameter on `builder_setupdirs` and `builder_harvest_objects`

In native mode, skip `builder_makeroot` (no dependency install), skip the chroot-root mkdir, and copy harvested objects with a plain `cp`. `builder_setupdirs` is testable under `exec_dry_run`: dependency resolution in `makeroot` is filesystem-based (not `exec`), so against an empty repository the non-native path fails while the native path succeeds.

**Files:**
- Modify: `src/rbuild-1/builder.h:46-53` (declarations)
- Modify: `src/rbuild-1/builder.c:560-592` (`builder_setupdirs`)
- Modify: `src/rbuild-1/builder.c:810-846` (`builder_harvest_objects`)
- Modify: `src/rbuild-1/builder.c:935,954` (callers inside `builder_build` — add `, 0` for now; Task 3 replaces the literal)
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Produces: `int builder_setupdirs(const Package *pkg, const Params *params, const char *srcname, const char *srctype, const strlist *repository, int native)` — when `native`, does not call `builder_makeroot` and does not `mkdir` `params->BUILDROOT`.
- Produces: `int builder_harvest_objects(const Package *pkg, const Params *params, const Params *bparams, int native)` — when `native`, copies with `cp -rp <src> <dst>` instead of `chroot <BUILDROOT> cp -rp <src> <dst>`.

- [ ] **Step 1: Write the failing test**

In `src/rbuild-1/tests/test_builder.c`, add after `test_buildcmd_native`:

```c
TEST(test_setupdirs_native_skips_makeroot) {
    Package pkg;
    Params p;
    strlist repo;               /* empty repository */
    int rc_native, rc_normal;

    exec_dry_run = 1;           /* mkdir/rsync become no-ops */
    package_init(&pkg);         /* no build_depends -> basedeps fallback */
    strlist_init(&repo);        /* nothing resolves */

    params_init(&p);
    p.BUILDROOT = xstrdup("/tmp/rb_nat/br");
    p.OBJROOT = xstrdup("/tmp/rb_nat/obj");
    p.SYMROOT = xstrdup("/tmp/rb_nat/sym");
    p.DSTROOT = xstrdup("/tmp/rb_nat/dst");
    p.HDRROOT = xstrdup("/tmp/rb_nat/hdr");
    p.PACKAGEROOT = xstrdup("/tmp/rb_nat/pkg");
    p.SRCROOT = xstrdup("/tmp/rb_nat/src");
    p.SRCDIR = xstrdup("/tmp/rb_nat/srcdir");

    /* native: makeroot skipped -> empty repo is fine -> success */
    rc_native = builder_setupdirs(&pkg, &p, "foo", "dir", &repo, 1);
    CHECK_INT(rc_native, 0);

    /* non-native: makeroot runs -> cannot resolve "cc" in empty repo -> fail */
    rc_normal = builder_setupdirs(&pkg, &p, "foo", "dir", &repo, 0);
    CHECK_INT(rc_normal, 1);

    exec_dry_run = 0;
    params_free(&p);
    strlist_free(&repo);
    package_free(&pkg);
}
```

Register it in `run_all()`:

```c
    RUN(test_setupdirs_native_skips_makeroot);
```

- [ ] **Step 2: Run test to verify it fails to compile**

```bash
cd src/rbuild-1 && make tests/test_builder
```
Expected: FAIL — `builder_setupdirs` called with 6 args but declared with 5.

- [ ] **Step 3: Update declarations**

In `src/rbuild-1/builder.h`, replace lines 46-53:

```c
int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository);

int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target);
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams);
```
with:
```c
int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository, int native);

int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target);
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams, int native);
```

- [ ] **Step 4: Update `builder_setupdirs`**

In `src/rbuild-1/builder.c`, replace the signature and the `BUILDROOT` mkdir + `makeroot` block (lines 560-572):

```c
int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository) {
    (void) srcname;   /* only used by the dropped cvs branch */

    if (exec_check(mkdirp(params->OBJROOT))) return 1;
    if (exec_check(mkdirp(params->SYMROOT))) return 1;
    if (exec_check(mkdirp(params->DSTROOT))) return 1;
    if (exec_check(mkdirp(params->HDRROOT))) return 1;
    if (exec_check(mkdirp(params->PACKAGEROOT))) return 1;
    if (exec_check(mkdirp(params->BUILDROOT))) return 1;

    if (builder_makeroot(pkg, params->BUILDROOT, repository) != 0) return 1;
```
with:
```c
int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository, int native) {
    (void) srcname;   /* only used by the dropped cvs branch */

    if (exec_check(mkdirp(params->OBJROOT))) return 1;
    if (exec_check(mkdirp(params->SYMROOT))) return 1;
    if (exec_check(mkdirp(params->DSTROOT))) return 1;
    if (exec_check(mkdirp(params->HDRROOT))) return 1;
    if (exec_check(mkdirp(params->PACKAGEROOT))) return 1;

    /* Native builds run on the host root: no chroot to create or populate. */
    if (!native) {
        if (exec_check(mkdirp(params->BUILDROOT))) return 1;
        if (builder_makeroot(pkg, params->BUILDROOT, repository) != 0) return 1;
    }
```

- [ ] **Step 5: Update `builder_harvest_objects`**

In `src/rbuild-1/builder.c`, change the signature (line 810):
```c
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams) {
```
to:
```c
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams, int native) {
```
Then replace the copy block (lines 833-840):
```c
        {
            char *argv[9];
            argv[0] = "chroot"; argv[1] = params->BUILDROOT;
            argv[2] = "cp"; argv[3] = "-rp";
            argv[4] = srcpath; argv[5] = cobjpath; argv[6] = 0;
            exec_printcmd(argv);
            if (exec_run_checked(argv)) rc = 1;
        }
```
with:
```c
        {
            char *argv[9];
            int a = 0;
            if (!native) { argv[a++] = "chroot"; argv[a++] = params->BUILDROOT; }
            argv[a++] = "cp"; argv[a++] = "-rp";
            argv[a++] = srcpath; argv[a++] = cobjpath; argv[a] = 0;
            exec_printcmd(argv);
            if (exec_run_checked(argv)) rc = 1;
        }
```

- [ ] **Step 6: Update the two callers inside `builder_build`**

In `src/rbuild-1/builder.c`, line 935, change:
```c
    if (builder_setupdirs(&pkg, &params, srcname, srctype, repository) != 0) {
```
to:
```c
    if (builder_setupdirs(&pkg, &params, srcname, srctype, repository, 0) != 0) {
```
And line 954, change:
```c
        if (builder_harvest_objects(&pkg, &params, &bparams) != 0) { rc = 1; goto done; }
```
to:
```c
        if (builder_harvest_objects(&pkg, &params, &bparams, 0) != 0) { rc = 1; goto done; }
```

- [ ] **Step 7: Run test to verify it passes**

```bash
cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder
```
Expected: PASS — including `test_setupdirs_native_skips_makeroot`.

- [ ] **Step 8: Commit**

```bash
cd src/rbuild-1 && git add builder.h builder.c tests/test_builder.c
git commit -m "rbuild: add native flag to setupdirs/harvest_objects (skip makeroot and chroot)"
```

---

### Task 3: `native` on `builder_build`, the `bootstrap` subcommand, and dispatch

Thread `native` into `builder_build` (choosing host-root params and passing the flag down), wire the three literal `0`s from Tasks 1–2 to the real flag, and add the `rbuild bootstrap` subcommand. DRY the manifest loop: refactor `cmd_buildall`'s body into `run_manifest(argc, argv, native)` shared by `buildall` (native 0) and `bootstrap` (native 1).

**Files:**
- Modify: `src/rbuild-1/builder.h:55-57` (declaration)
- Modify: `src/rbuild-1/builder.c:878-983` (`builder_build`)
- Modify: `src/rbuild-1/main.c` (usage string, refactor `cmd_buildall`, add `cmd_bootstrap`, dispatch, `buildpackage` caller)
- Test: shell smoke check (below)

**Interfaces:**
- Consumes: `builder_buildcmd(..., int native)`, `builder_setupdirs(..., int native)`, `builder_harvest_objects(..., int native)` from Tasks 1–2.
- Produces: `int builder_build(const char *srctype, const char *srcname, const strlist *repository, const char *target, const char *dstdir, int clean, int native)` — when `native`, builds against host-root params (`chrootparams` with `"/"`, so `params` paths equal `bparams`, `BUILDROOT` empty), skips makeroot/chroot via the flags, and does not run the `clean` teardown.
- Produces: `rbuild bootstrap <srclist> <repository> <dstdir>` subcommand.

- [ ] **Step 1: Update the `builder_build` declaration**

In `src/rbuild-1/builder.h`, replace lines 55-57:
```c
int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean);
```
with:
```c
int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean, int native);
```

- [ ] **Step 2: Update `builder_build` definition — signature, params, flags, clean**

In `src/rbuild-1/builder.c`, change the signature (lines 878-880):
```c
int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean) {
```
to:
```c
int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean, int native) {
```

Replace the `chrootparams` call (lines 920-921):
```c
    params_init(&params);
    builder_chrootparams(&bparams, bparams.BUILDROOT, &params);
```
with:
```c
    params_init(&params);
    /* Native: prefix with "/" so params paths equal the (host) bparams paths
       and BUILDROOT is empty -- there is no chroot in native mode. */
    builder_chrootparams(&bparams, native ? "/" : bparams.BUILDROOT, &params);
```

Change the `builder_setupdirs` caller (line 935):
```c
    if (builder_setupdirs(&pkg, &params, srcname, srctype, repository, 0) != 0) {
```
to:
```c
    if (builder_setupdirs(&pkg, &params, srcname, srctype, repository, native) != 0) {
```

Change the `installhdrs` buildcmd (line 941):
```c
        builder_buildcmd(&params, &bparams, "installhdrs", &cmd, 0);
```
to:
```c
        builder_buildcmd(&params, &bparams, "installhdrs", &cmd, native);
```

Change the `install` buildcmd (line 949):
```c
        builder_buildcmd(&params, &bparams, "install", &cmd, 0);
```
to:
```c
        builder_buildcmd(&params, &bparams, "install", &cmd, native);
```

Change the `builder_harvest_objects` caller (line 954):
```c
        if (builder_harvest_objects(&pkg, &params, &bparams, 0) != 0) { rc = 1; goto done; }
```
to:
```c
        if (builder_harvest_objects(&pkg, &params, &bparams, native) != 0) { rc = 1; goto done; }
```

Change the clean teardown (line 967-969):
```c
    if (clean) {
        if (exec_runv("rm", "-rf", params.BUILDROOT, (char *)0) != 0) { rc = 1; goto done; }
    }
```
to:
```c
    /* No chroot BUILDROOT to remove in native mode (it is empty). */
    if (clean && !native) {
        if (exec_runv("rm", "-rf", params.BUILDROOT, (char *)0) != 0) { rc = 1; goto done; }
    }
```

- [ ] **Step 3: Run the unit suite to confirm nothing regressed**

```bash
cd src/rbuild-1 && make test
```
Expected: PASS — `ALL TESTS PASSED` (the two callers of `builder_build` in `main.c` still pass 6 args, so this will FAIL to link until Step 4; if so, proceed to Step 4 and re-run).

- [ ] **Step 4: Update the usage string and refactor `main.c`**

In `src/rbuild-1/main.c`, replace the `USAGE` string (lines 9-15):
```c
static const char *USAGE =
    "usage:\n"
    "  rbuild buildpackage [--dir] [--target {all|headers|objs|local}]"
    " <source> <repository> <dstdir>\n"
    "  rbuild buildall  <srclist> <repository> <dstdir>\n"
    "  rbuild missing   <srclist> <dstdir>\n"
    "  (global: -n/--dry-run)\n";
```
with:
```c
static const char *USAGE =
    "usage:\n"
    "  rbuild buildpackage [--dir] [--target {all|headers|objs|local}]"
    " <source> <repository> <dstdir>\n"
    "  rbuild buildall  <srclist> <repository> <dstdir>\n"
    "  rbuild bootstrap <srclist> <repository> <dstdir>\n"
    "  rbuild missing   <srclist> <dstdir>\n"
    "  (global: -n/--dry-run)\n";
```

In `cmd_buildpackage`, update the `builder_build` call (line 52):
```c
    rc = builder_build(type, source, &repo, target, dstdir, 0);
```
to:
```c
    rc = builder_build(type, source, &repo, target, dstdir, 0, 0);
```

Replace the whole `cmd_buildall` function (lines 57-103) with a shared helper plus two thin wrappers:
```c
static int run_manifest(int argc, char **argv, int native) {
    const char *srclist, *seeddir, *dstdir;
    strlist repo;
    Manifest m;
    size_t i;

    if (argc != 3) { usage(); return 1; }
    srclist = argv[0]; seeddir = argv[1]; dstdir = argv[2];

    make_repo(dstdir, seeddir, &repo);
    manifest_init(&m);
    if (manifest_read(&m, srclist) != 0) {
        manifest_free(&m); strlist_free(&repo); return 1;
    }

    for (i = 0; i < m.count; i++) {
        const char *type = m.items[i].type;
        const char *source = m.items[i].source;
        const char *targets = m.items[i].targets ? m.items[i].targets : "all";
        Package pkg; Params params; char *found;

        package_init(&pkg); params_init(&params);
        if (builder_scan(type, source, &pkg, &params) != 0) {
            fprintf(stderr, "rbuild: skipping \"%s\": scan failed\n", source);
            package_free(&pkg); params_free(&params);
            continue;
        }
        found = builder_exists(&pkg, "any", dstdir);
        if (!found) {
            char *canon = package_canon_name(&pkg);
            printf("must build %s.apk using %s %s\n", canon, type, source);
            fflush(stdout);
            free(canon);
            if (builder_build(type, source, &repo, targets, dstdir,
                              !native, native) != 0)
                fprintf(stderr, "rbuild: build of \"%s\" failed; continuing\n",
                        source);
        } else {
            printf("already have %s\n", found);
            free(found);
        }
        package_free(&pkg); params_free(&params);
    }

    manifest_free(&m);
    strlist_free(&repo);
    return 0;
}

static int cmd_buildall(int argc, char **argv) {
    return run_manifest(argc, argv, 0);
}

static int cmd_bootstrap(int argc, char **argv) {
    return run_manifest(argc, argv, 1);
}
```

Add `bootstrap` to dispatch in `main` (after the `buildall` dispatch, around line 166):
```c
    if (strcmp(sub, "buildall") == 0)
        return cmd_buildall(argc - i, argv + i);
```
becomes:
```c
    if (strcmp(sub, "buildall") == 0)
        return cmd_buildall(argc - i, argv + i);
    if (strcmp(sub, "bootstrap") == 0)
        return cmd_bootstrap(argc - i, argv + i);
```

- [ ] **Step 5: Build and run the full unit suite**

```bash
cd src/rbuild-1 && make clean && make && make test
```
Expected: PASS — `ALL TESTS PASSED`, and `./rbuild` links.

- [ ] **Step 6: Smoke-test the new subcommand is recognized**

```bash
cd src/rbuild-1 && ./rbuild bootstrap 2>&1; echo "exit=$?"
```
Expected: prints the `usage:` block (which now includes the `bootstrap` line) and `exit=1`. It must NOT print `unknown subcommand "bootstrap"`.

- [ ] **Step 7: Commit**

```bash
cd src/rbuild-1 && git add builder.h builder.c main.c
git commit -m "rbuild: add bootstrap subcommand for native from-source seed build"
```

---

### Task 4: `src/BootstrapManifest`

The curated build-base closure that `rbuild bootstrap` builds. Same three-column format as `src/Manifest`.

**Files:**
- Create: `src/BootstrapManifest`

- [ ] **Step 1: Create the manifest**

Create `src/BootstrapManifest` with exactly this content:
```
#       Project[-Version]     Target
#------ --------------------- -------
dir     CoreOSMakefiles-1     all
dir     pb_makefiles-1        all
dir     project_makefiles-1   all
dir     cc-1                  all
dir     cctools-2             all
dir     gnumake-1             all
dir     gnutar-1              all
dir     awk-1                 all
dir     grep-1                all
dir     Csu-1                 all
dir     objc4-1               all
dir     Libc-1                all
dir     Libsystem-2           all
dir     architecture-1        all
dir     kernel-7              headers
dir     files-5               all
dir     basic_cmds-1          all
dir     bootstrap_cmds-1      all
dir     system_cmds-2         all
dir     shell_cmds-2          all
dir     file_cmds-1           all
dir     text_cmds-1           all
dir     developer_cmds-1      all
dir     zsh-1                 all
dir     tcsh-1                all
```

- [ ] **Step 2: Verify every project directory exists**

```bash
cd D:/RhapsodiOS/src && \
awk '/^dir/ {print $2}' BootstrapManifest | while read p; do \
  [ -d "$p" ] && echo "OK  $p" || echo "MISSING  $p"; done
```
Expected: every line prints `OK <project>`; no `MISSING`. (These names are the closure of `basedeps[]` in `src/rbuild-1/builder.c:401`; each is present in `src/Manifest`.)

- [ ] **Step 3: Verify the manifest parses**

```bash
cd D:/RhapsodiOS/src && ./rbuild-1/rbuild -n missing BootstrapManifest /tmp/rb_bm_dst 2>&1 | head
```
Expected: one `must build <name>.apk using dir <project>` line per project (no parse errors). `missing` needs no repository and does not build — it only exercises manifest reading + scan.

- [ ] **Step 4: Commit**

```bash
cd D:/RhapsodiOS && git add src/BootstrapManifest
git commit -m "rbuild: add BootstrapManifest listing the build-base seed closure"
```

---

### Task 5: README bootstrap procedure

Replace the "download the released set of packages" prerequisite with the from-source stage-0/1/2 bootstrap.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the released-packages step**

In `README.md`, in the `## Pre-requisites` list, replace this bullet:
```
 * Download the released set of packages from the [GitHub releases page](https://github.com/evolver56k/Darwin-0.3/releases/tag/v1.0) and extract it to a directory on a supported system e.g. /build/repo
```
with:
```
 * The `/build/repo` directory starts **empty** — the seed package set is built
   from source in Stage 0 below (no pre-built package download required).
```

- [ ] **Step 2: Add the bootstrap procedure section**

In `README.md`, immediately after the `## Building from the manifest file` section, append:
```
## Bootstrapping from source (no pre-built packages)

The build root that `rbuild` populates for every package needs a `build-base`
set (cc, cctools, gnumake, libsystem, headers, makefile frameworks, core
commands). Those packages are themselves built by `rbuild`, so a fresh
`/build/repo` cannot build anything. Break the cycle with a three-stage
from-source bootstrap on the Rhapsody host (which already has Apple's native
toolchain):

* **Stage 0 — native seed.** Build the `build-base` closure against the host
  root (no chroot, no dependency install) and write the seed `.apk`s into the
  repository:
  ```
  cd /build/source
  rbuild bootstrap BootstrapManifest /build/repo /build/repo
  ```
* **Stage 1 — self-host.** Build the whole system in clean chroots seeded only
  by Stage 0's output (this also rebuilds `build-base`, now self-hosted):
  ```
  rbuild buildall Manifest /build/repo /build/built
  ```
* **Stage 2 — self-consistency (optional).** Reseed from Stage 1's output and
  rebuild; the `build-base` `.apk`s from Stage 1 and Stage 2 should match,
  confirming the bootstrap is reproducible:
  ```
  rbuild buildall Manifest /build/built /build/built2
  ```
```

- [ ] **Step 3: Verify the rendered list reads correctly**

```bash
cd D:/RhapsodiOS && grep -n "Bootstrapping from source" README.md && \
grep -n "rbuild bootstrap BootstrapManifest" README.md
```
Expected: both greps match (section header and Stage 0 command present).

- [ ] **Step 4: Commit**

```bash
cd D:/RhapsodiOS && git add README.md
git commit -m "docs: document the from-source stage-0/1/2 bootstrap in README"
```

---

### Task 6: On-host staged verification (manual)

Automated unit tests cover the `native` plumbing; the full seed build must run on a Rhapsody DR2 / Mac OS X Server host with the Apple toolchain (it cannot run on the Windows dev host). Perform these once on the guest to prove the bootstrap end to end. Record results; if a stage fails, capture the failing project/output before fixing.

**Files:** none (verification only).

- [ ] **Step 1: Build and install rbuild on the guest**

Run on the Rhapsody host:
```bash
cd /build/source/rbuild-1 && make && make test
```
Expected: `ALL TESTS PASSED`; `./rbuild` exists.

- [ ] **Step 2: Stage 0 dry run — inspect the native commands**

```bash
cd /build/source && ./rbuild-1/rbuild -n bootstrap BootstrapManifest /build/repo /build/repo 2>&1 | head -60
```
Expected: per project, a `make -w -C ... install` line with **no leading `chroot`**, and **no** `Building build root:` / `installing ...` (makeroot) output.

- [ ] **Step 3: Stage 0 real run — produce the seed**

```bash
cd /build/source && ./rbuild-1/rbuild bootstrap BootstrapManifest /build/repo /build/repo
ls /build/repo/*.apk | wc -l
```
Expected: build completes; `/build/repo` now contains an `.apk` (and `-hdrs.apk` where applicable) for every `BootstrapManifest` project — covering the full `basedeps[]` closure (`cc, cctools, gnumake, pb-makefiles, coreosmakefiles, project-makefiles, zsh, tcsh, file-cmds, text-cmds, shell-cmds, developer-cmds, awk, grep, gnutar, libsystem, libc-hdrs, architecture-hdrs, kernel-hdrs, csu, objc4-hdrs, files, basic-cmds, bootstrap-cmds, system-cmds`).

- [ ] **Step 4: Stage 1 — self-host the full tree**

```bash
cd /build/source && ./rbuild-1/rbuild buildall Manifest /build/repo /build/built 2>&1 | tee /tmp/stage1.log | head -40
```
Expected: the first project's `Building build root:` step reports `installing .../build/repo/*.apk` (proving the Stage 0 seed satisfies `build-base`), then the tree builds. No `unable to find dependency` errors.

- [ ] **Step 5: Stage 2 — confirm self-consistency**

```bash
cd /build/source && ./rbuild-1/rbuild buildall Manifest /build/built /build/built2
for f in cc cctools gnumake libsystem csu objc4; do \
  a=$(ls /build/built/$f-*.apk 2>/dev/null | head -1); \
  b=$(ls /build/built2/$f-*.apk 2>/dev/null | head -1); \
  cmp -s "$a" "$b" && echo "MATCH $f" || echo "DIFF  $f"; done
```
Expected: each sampled build-base package reports `MATCH`. A `DIFF` indicates non-reproducibility (e.g. embedded timestamps or host drift) to investigate — not necessarily a bootstrap failure, but a signal.

---

## Notes for the implementer

- The Windows dev host can run Tasks 1–5 (edit + `make test` + smoke checks) if `cc` is available; if not, at minimum verify edits compile mentally against the shown line numbers, and defer compilation to the guest in Task 6. Line numbers reference the files as they exist at plan-writing time; if they have drifted, match on the surrounding code shown in each step rather than the number.
- Every `native` parameter is the **last** argument and an `int`. If a compile error reports an argument-count mismatch, a caller was missed — search: `grep -n "builder_buildcmd\|builder_setupdirs\|builder_harvest_objects\|builder_build" src/rbuild-1/*.c`.
- Do not add an `apk`/`chroot` runtime dependency to Stage 0; native mode deliberately avoids both.
