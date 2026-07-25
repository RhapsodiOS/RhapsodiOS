# rbuild Vendored Sources + apk Metadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a project in `src/` carry its upstream code as a pristine tarball plus an ordered patch series that rbuild extracts and applies into SRCROOT before `make` runs, and move package metadata from `dpkg/control` to an apk-native `apk/pkginfo`.

**Architecture:** A new `vendor.c` module owns everything tarball- and patch-related and knows nothing about `Package` or `Params` — it takes two paths and does its work. `builder_setupdirs()` calls it once, after the rsync of SRCDIR → SRCROOT and before any `make`. Metadata reading gains a second reader (`pkginfo_read`) selected by whether the project has an `apk/` directory; the `dpkg/control` path stays as a fallback for the 80 unconverted projects.

**Tech Stack:** C89, no libraries beyond POSIX. Built with `cc -Wall -O`. Home-grown test harness in `src/rbuild-1/tests/test.h` (`TEST`/`RUN`/`CHECK`/`CHECK_STR`/`CHECK_INT`/`TEST_MAIN`). Shells out to `tar`, `gzip`, `rsync`, `patch`, `mv`, `mkdir`, `rm`, `rmdir`, `cp`, `chmod`.

**Spec:** `docs/specs/2026-07-24-rbuild-vendor-design.md`

## Global Constraints

- **C89 only.** Declarations at the top of a block, `/* */` comments, no `//`, no mixed declarations and code. The existing files are the style reference.
- **All subprocesses go through `exec.h`** (`exec_run`, `exec_runv`, `exec_run_checked`, `exec_check`) so that `-n/--dry-run` prints instead of executing.
- **Never `tar -z`.** Rhapsody's tar has no `-z` and the in-tree GNU tar predates `--strip-components`. Use `gzip -dc <file> | tar -C <dir> -xf -` via `sh -c`, matching `apk_extract()` in `builder.c`.
- **Return convention:** 0 on success, non-zero on failure. Error messages go to `stderr` prefixed `rbuild: `.
- **Every task ends green:** `make test` passes and prints `ALL TESTS PASSED` before you commit.
- **Working directory for all `make` commands** is `src/rbuild-1`.
- **Commit messages** start with the subsystem, e.g. `rbuild: `, are one to two lines, describe behavior not files, and carry **no metadata or trailers** (`CLAUDE.md` §5).
- **Patch series order** is ascending `strcmp` of filename — byte-wise, not locale-dependent.
- **`patch` is a host-side dependency.** `patch-cmds` is in `src/Manifest` but not `src/BootstrapManifest`; no vendored project may join the stage-0 bootstrap set.

## File Structure

| File | Responsibility |
|---|---|
| `src/rbuild-1/strutil.c/.h` | Modify: add `str_parse_kv()`, the shared `key = value` line splitter used by both new readers. |
| `src/rbuild-1/pkginfo.c/.h` | Modify: add `pkginfo_read()`, the reader matching the existing `pkginfo_write()`. |
| `src/rbuild-1/vendor.c/.h` | **Create.** Vendor descriptor parsing, patch enumeration, and the extract → rename → patch sequence. Takes plain paths; no `Package`/`Params` coupling. |
| `src/rbuild-1/builder.c/.h` | Modify: `builder_apkdir()`; metadata reader selection in `builder_scan_dir()`; `vendor_apply()` call and rsync excludes in `builder_setupdirs()`; apk-named dotted scripts in `builder_buildpackage()`. |
| `src/rbuild-1/Makefile` | Modify: `vendor.o` in `OBJS`, `tests/test_vendor` in `TESTS`, per-test object lists. |
| `src/rbuild-1/tests/test_strutil.c` | Modify: `str_parse_kv` cases. |
| `src/rbuild-1/tests/test_pkginfo.c` | Modify: `pkginfo_read` cases. |
| `src/rbuild-1/tests/test_vendor.c` | **Create.** Descriptor parsing, patch ordering, and `vendor_apply()` end to end against a synthetic tarball. |
| `src/rbuild-1/tests/test_builder.c` | Modify: `builder_apkdir` and apk-vs-dpkg metadata selection. |
| `src/rbuild-1/README.md` | Modify: document the two new files and the `patch` dependency. |
| `src/files-5/apk/` | **Create** (`pkginfo`, `pre-install`, `post-install`); delete `src/files-5/dpkg/`. |
| `src/zlib/apk/` | **Create** (`pkginfo`, `vendor`); add `zlib-1.1.3.tar.gz` + `patches/`; delete `src/zlib/zlib/` and `src/zlib/dpkg/`. |

---

### Task 1: `str_parse_kv()` — the shared line splitter

Both new file formats are apk `.PKGINFO` syntax: one `key = value` per line, `#` comments, blank lines, no continuations. One function serves both readers.

**Files:**
- Modify: `src/rbuild-1/strutil.h` (append before `#endif`)
- Modify: `src/rbuild-1/strutil.c` (append at end)
- Test: `src/rbuild-1/tests/test_strutil.c`

**Interfaces:**
- Consumes: `str_chomp()`, `str_trim()`, `str_lowercase()` — all existing, all mutate the caller's buffer in place and return a pointer into it.
- Produces: `int str_parse_kv(char *line, char **key, char **val)`. Returns 1 on a real entry with `*key`/`*val` pointing into `line`; returns 0 for blank lines, `#` comments, lines with no `=`, and lines with an empty key. Mutates `line`.

- [ ] **Step 1: Write the failing test**

Add to `src/rbuild-1/tests/test_strutil.c`, before `run_all()`:

```c
TEST(test_parse_kv) {
    char l1[] = "pkgname = zlib\n";
    char l2[] = "  Pkgver=1.1.3  ";
    char l3[] = "# comment = x";
    char l4[] = "\n";
    char l5[] = "no equals here";
    char l6[] = "= orphan";
    char l7[] = "pkgdesc = a = b";
    char l8[] = "patches =";
    char *k = 0, *v = 0;

    CHECK_INT(str_parse_kv(l1, &k, &v), 1);
    CHECK_STR(k, "pkgname");
    CHECK_STR(v, "zlib");

    /* key is lowercased; whitespace around both sides is trimmed */
    CHECK_INT(str_parse_kv(l2, &k, &v), 1);
    CHECK_STR(k, "pkgver");
    CHECK_STR(v, "1.1.3");

    CHECK_INT(str_parse_kv(l3, &k, &v), 0);
    CHECK_INT(str_parse_kv(l4, &k, &v), 0);
    CHECK_INT(str_parse_kv(l5, &k, &v), 0);
    CHECK_INT(str_parse_kv(l6, &k, &v), 0);

    /* only the FIRST '=' separates */
    CHECK_INT(str_parse_kv(l7, &k, &v), 1);
    CHECK_STR(k, "pkgdesc");
    CHECK_STR(v, "a = b");

    /* an empty value is a real entry */
    CHECK_INT(str_parse_kv(l8, &k, &v), 1);
    CHECK_STR(k, "patches");
    CHECK_STR(v, "");
}
```

And add this line to `run_all()` in the same file, after `RUN(test_str_cats_pathjoin);`:

```c
    RUN(test_parse_kv);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_strutil
```

Expected: compile FAILS with an implicit-declaration or undefined-symbol error for `str_parse_kv`.

- [ ] **Step 3: Write the implementation**

Append to `src/rbuild-1/strutil.h`, immediately before the final `#endif`:

```c
/* Splits one "key = value" line in place, apk .PKGINFO style. Returns 1 and
   points *key/*val into the buffer on a real entry; returns 0 for blank
   lines, "#" comments, lines with no '=', and lines with an empty key.
   Only the first '=' separates. Key is trimmed and lowercased; value is
   trimmed. Mutates line; do not free *key or *val. */
int str_parse_kv(char *line, char **key, char **val);
```

Append to `src/rbuild-1/strutil.c`:

```c
int str_parse_kv(char *line, char **key, char **val) {
    char *k, *eq;

    str_chomp(line);
    k = str_trim(line);
    if (k[0] == '\0' || k[0] == '#') return 0;

    eq = strchr(k, '=');
    if (eq == 0) return 0;
    *eq = '\0';

    *key = str_trim(k);
    if ((*key)[0] == '\0') return 0;
    str_lowercase(*key);
    *val = str_trim(eq + 1);
    return 1;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: `- test_parse_kv` appears with no `FAIL` lines, and the run ends `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/strutil.c src/rbuild-1/strutil.h src/rbuild-1/tests/test_strutil.c
git commit -m "rbuild: add key=value line splitter for apk-style metadata files"
```

---

### Task 2: `pkginfo_read()` — read `apk/pkginfo`

`pkginfo.c` already writes `.PKGINFO`. Give it the matching reader so the input format and the output format are the same syntax.

**Files:**
- Modify: `src/rbuild-1/pkginfo.h`
- Modify: `src/rbuild-1/pkginfo.c`
- Test: `src/rbuild-1/tests/test_pkginfo.c`

**Interfaces:**
- Consumes: `str_parse_kv()` from Task 1; `package_set()`, `str_split_chars()`, `strlist_init/free` (all existing).
- Produces: `int pkginfo_read(Package *p, const char *path)` — 0 on success; 1 if the file cannot be opened or `pkgname`/`pkgver` is missing. Fields set: `package`, `version`, `description`, `maintainer`, `provides`, `replaces`, `build_depends` + `has_build_depends`. `arch` and `origin` in the file are **ignored** — the caller computes them.

- [ ] **Step 1: Write the failing test**

Add to `src/rbuild-1/tests/test_pkginfo.c`, before `run_all()`:

```c
static void write_file(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    fputs(text, f);
    fclose(f);
}

TEST(test_pkginfo_read) {
    Package p;
    package_init(&p);
    write_file("/tmp/rbtest_in.pkginfo",
        "# zlib metadata\n"
        "\n"
        "pkgname = zlib\n"
        "pkgver = 1.1.3\n"
        "pkgdesc = Zip library\n"
        "maintainer = Darwin Developers <darwin-development@public.lists.apple.com>\n"
        "builddepends = build-base\n"
        "url = http://www.cdrom.com/pub/infozip/zlib/\n"
        "arch = ignored-on-input\n");

    CHECK_INT(pkginfo_read(&p, "/tmp/rbtest_in.pkginfo"), 0);
    CHECK_STR(p.package, "zlib");
    CHECK_STR(p.version, "1.1.3");
    CHECK_STR(p.description, "Zip library");
    CHECK_STR(p.maintainer,
              "Darwin Developers <darwin-development@public.lists.apple.com>");
    CHECK_INT(p.has_build_depends, 1);
    CHECK_INT(p.build_depends.count, 1);
    CHECK_STR(p.build_depends.items[0], "build-base");
    /* unknown keys ignored; arch is not honored from the file */
    CHECK(p.architecture == 0);
    package_free(&p);
    remove("/tmp/rbtest_in.pkginfo");
}

TEST(test_pkginfo_read_builddepends_commas) {
    Package p;
    package_init(&p);
    /* pasted straight from a Debian-style Build-Depends line */
    write_file("/tmp/rbtest_in2.pkginfo",
        "pkgname = openssh\n"
        "pkgver = 2.3.0p1\n"
        "builddepends = build-base, openssl, zlib, perl\n");

    CHECK_INT(pkginfo_read(&p, "/tmp/rbtest_in2.pkginfo"), 0);
    CHECK_INT(p.build_depends.count, 4);
    CHECK_STR(p.build_depends.items[0], "build-base");
    CHECK_STR(p.build_depends.items[3], "perl");
    package_free(&p);
    remove("/tmp/rbtest_in2.pkginfo");
}

TEST(test_pkginfo_read_errors) {
    Package p;

    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rbtest_does_not_exist.pkginfo"), 1);
    package_free(&p);

    package_init(&p);
    write_file("/tmp/rbtest_in3.pkginfo", "pkgver = 1.0\n");
    CHECK_INT(pkginfo_read(&p, "/tmp/rbtest_in3.pkginfo"), 1);   /* no pkgname */
    package_free(&p);

    package_init(&p);
    write_file("/tmp/rbtest_in3.pkginfo", "pkgname = foo\n");
    CHECK_INT(pkginfo_read(&p, "/tmp/rbtest_in3.pkginfo"), 1);   /* no pkgver */
    package_free(&p);
    remove("/tmp/rbtest_in3.pkginfo");
}

TEST(test_pkginfo_round_trip) {
    Package p, q;
    package_init(&p);
    package_set(&p.package, "zlib");
    package_set(&p.version, "1.1.3");
    package_set(&p.description, "Zip library");
    package_set(&p.maintainer, "M <m@x>");
    strlist_push(&p.build_depends, "build-base");
    p.has_build_depends = 1;

    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest_rt.pkginfo"), 0);
    package_init(&q);
    CHECK_INT(pkginfo_read(&q, "/tmp/rbtest_rt.pkginfo"), 0);
    CHECK_STR(q.package, p.package);
    CHECK_STR(q.version, p.version);
    CHECK_STR(q.description, p.description);
    CHECK_STR(q.maintainer, p.maintainer);
    CHECK_INT(q.build_depends.count, 1);
    CHECK_STR(q.build_depends.items[0], "build-base");
    package_free(&p);
    package_free(&q);
    remove("/tmp/rbtest_rt.pkginfo");
}
```

Replace `run_all()` in the same file with:

```c
static void run_all(void) {
    RUN(test_pkginfo_write);
    RUN(test_pkginfo_read);
    RUN(test_pkginfo_read_builddepends_commas);
    RUN(test_pkginfo_read_errors);
    RUN(test_pkginfo_round_trip);
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_pkginfo
```

Expected: compile FAILS on `pkginfo_read` being undeclared.

- [ ] **Step 3: Write the implementation**

In `src/rbuild-1/pkginfo.h`, add before the final `#endif`:

```c
/* Reads apk .PKGINFO syntax into p. Returns 0 on success; 1 if the file
   cannot be opened or pkgname/pkgver is missing. "arch" and "origin" in the
   file are ignored -- rbuild computes those. Unknown keys are ignored, so
   "url"/"vendor" may be kept as documentation. */
int pkginfo_read(Package *p, const char *path);
```

In `src/rbuild-1/pkginfo.c`, add `#include <string.h>` to the includes, then append:

```c
int pkginfo_read(Package *p, const char *path) {
    FILE *f = fopen(path, "r");
    char line[4096];
    char *key, *val;

    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s\n", path);
        return 1;
    }
    while (fgets(line, sizeof(line), f) != 0) {
        if (!str_parse_kv(line, &key, &val)) continue;
        if (strcmp(key, "pkgname") == 0) package_set(&p->package, val);
        else if (strcmp(key, "pkgver") == 0) package_set(&p->version, val);
        else if (strcmp(key, "pkgdesc") == 0) package_set(&p->description, val);
        else if (strcmp(key, "maintainer") == 0) package_set(&p->maintainer, val);
        else if (strcmp(key, "provides") == 0) package_set(&p->provides, val);
        else if (strcmp(key, "replaces") == 0) package_set(&p->replaces, val);
        else if (strcmp(key, "builddepends") == 0) {
            strlist_free(&p->build_depends);
            strlist_init(&p->build_depends);
            str_split_chars(val, " ,", &p->build_depends);
            p->has_build_depends = 1;
        }
    }
    fclose(f);

    if (!p->package) {
        fprintf(stderr, "rbuild: %s: missing pkgname\n", path);
        return 1;
    }
    if (!p->version) {
        fprintf(stderr, "rbuild: %s: missing pkgver\n", path);
        return 1;
    }
    return 0;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: the four new `test_pkginfo_*` lines appear with no `FAIL`, ending `ALL TESTS PASSED`. The two "missing pkgname/pkgver" and one "unable to open" messages printed to stderr during `test_pkginfo_read_errors` are expected output, not failures.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/pkginfo.c src/rbuild-1/pkginfo.h src/rbuild-1/tests/test_pkginfo.c
git commit -m "rbuild: read package metadata from apk .PKGINFO syntax"
```

---

### Task 3: `vendor.c` — descriptor parsing and patch enumeration

**Files:**
- Create: `src/rbuild-1/vendor.h`
- Create: `src/rbuild-1/vendor.c`
- Create: `src/rbuild-1/tests/test_vendor.c`
- Modify: `src/rbuild-1/Makefile`

**Interfaces:**
- Consumes: `str_parse_kv()` (Task 1); `str_cats()`, `path_join()`, `str_has_suffix()`, `strlist_*`, `xstrdup()` (existing).
- Produces:
  - `typedef struct { char *tarball; char *directory; char *patches; int patchlevel; int patches_explicit; } Vendor;`
  - `void vendor_init(Vendor *v)` — zeroes and sets `patchlevel = 1`.
  - `void vendor_free(Vendor *v)`
  - `char *vendor_path(const char *source)` — malloc'd `"<source>/apk/vendor"` if that file exists, else `NULL`.
  - `int vendor_read(Vendor *v, const char *path)` — 0 / 1.
  - `int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out)` — 0 / 1; pushes full paths in ascending `strcmp` order.
  - `int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot)` — declared here, implemented in Task 4.

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_vendor.c`:

```c
#include "vendor.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>

static void write_file(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    fputs(text, f);
    fclose(f);
}

TEST(test_vendor_read_full) {
    Vendor v;
    system("rm -rf /tmp/rbtest_vd && mkdir -p /tmp/rbtest_vd/apk");
    write_file("/tmp/rbtest_vd/apk/vendor",
        "# upstream zlib\n"
        "tarball = zlib-1.1.3.tar.gz\n"
        "directory = zlib\n"
        "patches = series\n"
        "patchlevel = 2\n");

    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 0);
    CHECK_STR(v.tarball, "zlib-1.1.3.tar.gz");
    CHECK_STR(v.directory, "zlib");
    CHECK_STR(v.patches, "series");
    CHECK_INT(v.patchlevel, 2);
    CHECK_INT(v.patches_explicit, 1);
    vendor_free(&v);
}

TEST(test_vendor_read_defaults) {
    Vendor v;
    write_file("/tmp/rbtest_vd/apk/vendor",
        "tarball = zlib-1.1.3.tar.gz\n"
        "directory = zlib\n");

    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 0);
    CHECK_STR(v.patches, "patches");
    CHECK_INT(v.patchlevel, 1);
    CHECK_INT(v.patches_explicit, 0);
    vendor_free(&v);
}

TEST(test_vendor_read_errors) {
    Vendor v;

    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/nope"), 1);
    vendor_free(&v);

    write_file("/tmp/rbtest_vd/apk/vendor", "directory = zlib\n");
    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 1);   /* no tarball */
    vendor_free(&v);

    write_file("/tmp/rbtest_vd/apk/vendor", "tarball = z.tar.gz\n");
    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 1);   /* no directory */
    vendor_free(&v);
}

TEST(test_vendor_path) {
    char *p;
    write_file("/tmp/rbtest_vd/apk/vendor",
        "tarball = z.tar.gz\ndirectory = z\n");
    p = vendor_path("/tmp/rbtest_vd");
    CHECK_STR(p, "/tmp/rbtest_vd/apk/vendor");
    free(p);
    CHECK(vendor_path("/tmp/rbtest_vd/apk") == 0);
}

TEST(test_vendor_list_patches_sorted) {
    Vendor v;
    strlist out;

    /* created out of order on purpose; must come back sorted */
    system("mkdir -p /tmp/rbtest_vd/patches");
    system("touch /tmp/rbtest_vd/patches/0002-second.patch");
    system("touch /tmp/rbtest_vd/patches/0001-first.patch");
    system("touch /tmp/rbtest_vd/patches/README");

    vendor_init(&v);
    v.tarball = xstrdup("z.tar.gz");
    v.directory = xstrdup("z");
    v.patches = xstrdup("patches");
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 0);
    CHECK_INT(out.count, 2);   /* README is not a .patch */
    CHECK_STR(out.items[0], "/tmp/rbtest_vd/patches/0001-first.patch");
    CHECK_STR(out.items[1], "/tmp/rbtest_vd/patches/0002-second.patch");
    strlist_free(&out);
    vendor_free(&v);
}

TEST(test_vendor_list_patches_missing_dir) {
    Vendor v;
    strlist out;

    /* default "patches" absent -> fine, no patches */
    vendor_init(&v);
    v.tarball = xstrdup("z.tar.gz");
    v.directory = xstrdup("z");
    v.patches = xstrdup("nosuchdir");
    v.patches_explicit = 0;
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 0);
    CHECK_INT(out.count, 0);
    strlist_free(&out);

    /* explicitly configured but absent -> error */
    v.patches_explicit = 1;
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 1);
    strlist_free(&out);
    vendor_free(&v);

    system("rm -rf /tmp/rbtest_vd");
}

static void run_all(void) {
    RUN(test_vendor_read_full);
    RUN(test_vendor_read_defaults);
    RUN(test_vendor_read_errors);
    RUN(test_vendor_path);
    RUN(test_vendor_list_patches_sorted);
    RUN(test_vendor_list_patches_missing_dir);
}

TEST_MAIN()
```

Wire it into `src/rbuild-1/Makefile` with three edits.

Change the `OBJS` line to:

```make
OBJS = strutil.o package.o manifest.o exec.o pkginfo.o vendor.o builder.o main.o
```

Change the `TESTS` line to:

```make
TESTS = tests/test_strutil tests/test_package tests/test_manifest tests/test_builder tests/test_exec tests/test_pkginfo tests/test_vendor
```

Add these two object lists next to the others (and update `test_builder_OBJS`, since `builder.o` will call into `vendor.o` from Task 6 onward):

```make
test_vendor_OBJS = strutil.o exec.o vendor.o
test_builder_OBJS = strutil.o package.o exec.o pkginfo.o vendor.o builder.o
```

Add the build rule after the `tests/test_pkginfo` rule:

```make
tests/test_vendor: tests/test_vendor.c $(test_vendor_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_vendor.c $(test_vendor_OBJS)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_vendor
```

Expected: FAILS — `vendor.h: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Create `src/rbuild-1/vendor.h`:

```c
#ifndef RBUILD_VENDOR_H
#define RBUILD_VENDOR_H

#include "strutil.h"

/* A vendored source: a pristine upstream tarball plus an ordered patch
   series, described by "<project>/apk/vendor". */
typedef struct {
    char *tarball;        /* required; relative to the project dir */
    char *directory;      /* required; name the extracted tree gets in SRCROOT */
    char *patches;        /* defaults to "patches"; relative to project dir */
    int patchlevel;       /* defaults to 1; -p level passed to patch */
    int patches_explicit; /* 1 if "patches" was named in the file */
} Vendor;

void vendor_init(Vendor *v);
void vendor_free(Vendor *v);

/* Malloc'd "<source>/apk/vendor" if that file exists, else NULL. */
char *vendor_path(const char *source);

/* Reads the descriptor. 0 on success; 1 if the file cannot be opened or a
   required key is missing. */
int vendor_read(Vendor *v, const char *path);

/* Pushes the full path of every "*.patch" under "<srcdir>/<patches>" onto
   out, in ascending strcmp order. An absent DEFAULT patch directory yields
   no patches and success; an absent EXPLICITLY configured one is an error. */
int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out);

/* Extracts <srcdir>/<tarball> into <srcroot>/<directory>, renaming the
   tarball's sole top-level directory, then applies the patch series.
   0 on success, 1 on any failure. */
int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot);

#endif
```

Create `src/rbuild-1/vendor.c`:

```c
#include "vendor.h"
#include "exec.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <sys/stat.h>

void vendor_init(Vendor *v) {
    memset(v, 0, sizeof(*v));
    v->patchlevel = 1;
}

void vendor_free(Vendor *v) {
    free(v->tarball); free(v->directory); free(v->patches);
    memset(v, 0, sizeof(*v));
}

static int is_dir(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int is_file(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

char *vendor_path(const char *source) {
    char *p = str_cats(source, "/apk/vendor", (char *)0);
    if (is_file(p)) return p;
    free(p);
    return 0;
}

int vendor_read(Vendor *v, const char *path) {
    FILE *f = fopen(path, "r");
    char line[4096];
    char *key, *val;

    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s\n", path);
        return 1;
    }
    while (fgets(line, sizeof(line), f) != 0) {
        if (!str_parse_kv(line, &key, &val)) continue;
        if (strcmp(key, "tarball") == 0) {
            free(v->tarball); v->tarball = xstrdup(val);
        } else if (strcmp(key, "directory") == 0) {
            free(v->directory); v->directory = xstrdup(val);
        } else if (strcmp(key, "patches") == 0) {
            free(v->patches); v->patches = xstrdup(val);
            v->patches_explicit = 1;
        } else if (strcmp(key, "patchlevel") == 0) {
            v->patchlevel = atoi(val);
        }
    }
    fclose(f);

    if (!v->tarball) {
        fprintf(stderr, "rbuild: %s: missing tarball\n", path);
        return 1;
    }
    if (!v->directory) {
        fprintf(stderr, "rbuild: %s: missing directory\n", path);
        return 1;
    }
    if (!v->patches) v->patches = xstrdup("patches");
    return 0;
}

static int cmp_str(const void *a, const void *b) {
    return strcmp(*(const char **) a, *(const char **) b);
}

int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out) {
    char *dir = str_cats(srcdir, "/", v->patches, (char *)0);
    DIR *d;
    struct dirent *de;

    if (!is_dir(dir)) {
        int rc = 0;
        if (v->patches_explicit) {
            fprintf(stderr, "rbuild: %s: patch directory does not exist\n", dir);
            rc = 1;
        }
        free(dir);
        return rc;
    }

    d = opendir(dir);
    if (!d) {
        fprintf(stderr, "rbuild: unable to open %s\n", dir);
        free(dir);
        return 1;
    }
    while ((de = readdir(d)) != 0) {
        if (!str_has_suffix(de->d_name, ".patch")) continue;
        strlist_push_owned(out, path_join(dir, de->d_name));
    }
    closedir(d);
    free(dir);

    /* Every path shares the same directory prefix, so sorting full paths
       orders them by filename. */
    if (out->count > 1)
        qsort(out->items, out->count, sizeof(char *), cmp_str);
    return 0;
}
```

`vendor_apply()` arrives in Task 4. To keep this task's build green, add this stub at the end of `vendor.c` for now:

```c
int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot) {
    (void) v; (void) srcdir; (void) srcroot;
    fprintf(stderr, "rbuild: vendor_apply not implemented\n");
    return 1;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: `== tests/test_vendor ==` runs all six cases with no `FAIL`, and the run ends `ALL TESTS PASSED`. The three descriptor error messages from `test_vendor_read_errors` and one from `test_vendor_list_patches_missing_dir` are expected stderr output.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/vendor.c src/rbuild-1/vendor.h src/rbuild-1/tests/test_vendor.c src/rbuild-1/Makefile
git commit -m "rbuild: parse vendored-source descriptors and enumerate patch series"
```

---

### Task 4: `vendor_apply()` — extract, rename, patch

**Files:**
- Modify: `src/rbuild-1/vendor.c` (replace the Task 3 stub)
- Test: `src/rbuild-1/tests/test_vendor.c`

**Interfaces:**
- Consumes: `vendor_list_patches()` (Task 3); `exec_run()`, `exec_runv()`, `exec_check()`, `exec_dry_run` (existing).
- Produces: `int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot)`. Sequence: `rm -rf <srcroot>/<directory>`; `rm -rf` then `mkdir -p <srcroot>/.vendor-tmp`; `gzip -dc <srcdir>/<tarball> | tar -C <srcroot>/.vendor-tmp -xf -`; require exactly one top-level entry; `mv` it to `<srcroot>/<directory>`; `rmdir` the scratch dir; then `patch -p<patchlevel> -d <srcroot>/<directory> < <each patch>`.

Note on dry-run: nothing is actually extracted, so the sole-entry check is skipped and the tarball stem (`zlib-1.1.3.tar.gz` → `zlib-1.1.3`) is used to print a plausible `mv`.

- [ ] **Step 1: Write the failing test**

Add to `src/rbuild-1/tests/test_vendor.c`, before `run_all()`:

```c
static char *slurp(const char *path) {
    FILE *f = fopen(path, "r");
    static char buf[4096];
    size_t n;
    if (!f) return 0;
    n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = '\0';
    fclose(f);
    return buf;
}

/* Builds a synthetic project: a tarball whose top-level directory is
   "widget-1.0" plus a one-hunk patch, and applies it into a fake SRCROOT. */
TEST(test_vendor_apply) {
    Vendor v;
    struct stat st;

    system("rm -rf /tmp/rbtest_va && "
           "mkdir -p /tmp/rbtest_va/src/apk /tmp/rbtest_va/src/patches "
           "/tmp/rbtest_va/root /tmp/rbtest_va/stage/widget-1.0");
    system("echo orig > /tmp/rbtest_va/stage/widget-1.0/hello.txt");
    system("(cd /tmp/rbtest_va/stage && tar -cf - widget-1.0 | gzip -9 "
           "> /tmp/rbtest_va/src/widget-1.0.tar.gz)");
    {
        FILE *f = fopen("/tmp/rbtest_va/src/patches/0001-change.patch", "w");
        fputs("--- widget-1.0/hello.txt\n"
              "+++ widget/hello.txt\n"
              "@@ -1 +1 @@\n"
              "-orig\n"
              "+patched\n", f);
        fclose(f);
    }

    vendor_init(&v);
    v.tarball = xstrdup("widget-1.0.tar.gz");
    v.directory = xstrdup("widget");
    v.patches = xstrdup("patches");

    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root"), 0);

    /* renamed from widget-1.0/ to widget/, and the patch was applied */
    CHECK_STR(slurp("/tmp/rbtest_va/root/widget/hello.txt"), "patched\n");
    /* scratch dir cleaned up */
    CHECK(stat("/tmp/rbtest_va/root/.vendor-tmp", &st) != 0);

    /* idempotent: running again from the same state succeeds and does not
       double-apply the patch */
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root"), 0);
    CHECK_STR(slurp("/tmp/rbtest_va/root/widget/hello.txt"), "patched\n");

    vendor_free(&v);
}

TEST(test_vendor_apply_missing_tarball) {
    Vendor v;
    vendor_init(&v);
    v.tarball = xstrdup("nosuch.tar.gz");
    v.directory = xstrdup("widget");
    v.patches = xstrdup("patches");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root"), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_rejects_tarbomb) {
    Vendor v;
    system("rm -rf /tmp/rbtest_va/stage2 && mkdir -p /tmp/rbtest_va/stage2");
    system("echo a > /tmp/rbtest_va/stage2/a.txt");
    system("echo b > /tmp/rbtest_va/stage2/b.txt");
    system("(cd /tmp/rbtest_va/stage2 && tar -cf - a.txt b.txt | gzip -9 "
           "> /tmp/rbtest_va/src/bomb.tar.gz)");

    vendor_init(&v);
    v.tarball = xstrdup("bomb.tar.gz");
    v.directory = xstrdup("widget");
    v.patches = xstrdup("patches");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root"), 1);
    vendor_free(&v);

    system("rm -rf /tmp/rbtest_va");
}

TEST(test_vendor_apply_bad_patch_fails) {
    Vendor v;
    system("rm -rf /tmp/rbtest_vb && "
           "mkdir -p /tmp/rbtest_vb/src/patches /tmp/rbtest_vb/root "
           "/tmp/rbtest_vb/stage/widget-1.0");
    system("echo orig > /tmp/rbtest_vb/stage/widget-1.0/hello.txt");
    system("(cd /tmp/rbtest_vb/stage && tar -cf - widget-1.0 | gzip -9 "
           "> /tmp/rbtest_vb/src/widget-1.0.tar.gz)");
    {
        /* context does not match the file -> patch must fail */
        FILE *f = fopen("/tmp/rbtest_vb/src/patches/0001-bad.patch", "w");
        fputs("--- widget-1.0/hello.txt\n"
              "+++ widget/hello.txt\n"
              "@@ -1 +1 @@\n"
              "-something else entirely\n"
              "+patched\n", f);
        fclose(f);
    }

    vendor_init(&v);
    v.tarball = xstrdup("widget-1.0.tar.gz");
    v.directory = xstrdup("widget");
    v.patches = xstrdup("patches");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_vb/src", "/tmp/rbtest_vb/root"), 1);
    vendor_free(&v);

    /* removes the tree along with any .orig/.rej patch left behind */
    system("rm -rf /tmp/rbtest_vb");
}
```

Add `#include <sys/stat.h>` to the test's includes, and extend `run_all()`:

```c
static void run_all(void) {
    RUN(test_vendor_read_full);
    RUN(test_vendor_read_defaults);
    RUN(test_vendor_read_errors);
    RUN(test_vendor_path);
    RUN(test_vendor_list_patches_sorted);
    RUN(test_vendor_list_patches_missing_dir);
    RUN(test_vendor_apply);
    RUN(test_vendor_apply_missing_tarball);
    RUN(test_vendor_apply_rejects_tarbomb);
    RUN(test_vendor_apply_bad_patch_fails);
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_vendor && ./tests/test_vendor
```

Expected: compiles, then the four new cases FAIL — `vendor_apply not implemented` on stderr and `got 1 want 0` for `test_vendor_apply`.

- [ ] **Step 3: Write the implementation**

Replace the stub at the end of `src/rbuild-1/vendor.c` with:

```c
/* Counts entries other than "." and ".."; the first one found is returned in
   *name (malloc'd). -1 if the directory cannot be opened. */
static int sole_entry(const char *dir, char **name) {
    DIR *d = opendir(dir);
    struct dirent *de;
    int n = 0;

    *name = 0;
    if (!d) return -1;
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        if (n == 0) *name = xstrdup(de->d_name);
        n++;
    }
    closedir(d);
    return n;
}

/* "widget-1.0.tar.gz" -> "widget-1.0". Dry-run only: nothing was extracted,
   so guess the conventional top-level name to keep the trace readable. */
static char *tarball_stem(const char *tarball) {
    char *s = xstrdup(tarball);
    size_t n = strlen(s);
    if (n > 7 && strcmp(s + n - 7, ".tar.gz") == 0) s[n - 7] = '\0';
    else if (n > 4 && strcmp(s + n - 4, ".tgz") == 0) s[n - 4] = '\0';
    return s;
}

static int run_sh(const char *cmd) {
    char *argv[4];
    argv[0] = "sh"; argv[1] = "-c"; argv[2] = (char *) cmd; argv[3] = 0;
    return exec_run(argv);
}

int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot) {
    char *dest = str_cats(srcroot, "/", v->directory, (char *)0);
    char *tmp = str_cats(srcroot, "/.vendor-tmp", (char *)0);
    char *tarball = str_cats(srcdir, "/", v->tarball, (char *)0);
    char *cmd, *entry, *moved;
    strlist patches;
    char plevel[16];
    size_t i;
    int n;
    int rc = 1;

    strlist_init(&patches);

    if (!is_file(tarball)) {
        fprintf(stderr, "rbuild: %s: tarball not found\n", tarball);
        goto done;
    }
    if (vendor_list_patches(v, srcdir, &patches) != 0) goto done;

    printf("vendoring %s into %s\n", v->tarball, dest);
    fflush(stdout);

    /* Fresh extraction every time: SRCROOT persists between builds and rsync
       runs without --delete, so a stale patched tree would be patched twice. */
    if (exec_check(exec_runv("rm", "-rf", dest, (char *)0))) goto done;
    if (exec_check(exec_runv("rm", "-rf", tmp, (char *)0))) goto done;
    if (exec_check(exec_runv("mkdir", "-p", tmp, (char *)0))) goto done;

    cmd = str_cats("gzip -dc '", tarball, "' | tar -C '", tmp, "' -xf -",
                   (char *)0);
    n = run_sh(cmd);
    free(cmd);
    if (exec_check(n)) goto done;

    if (exec_dry_run) {
        entry = tarball_stem(v->tarball);
    } else {
        n = sole_entry(tmp, &entry);
        if (n != 1) {
            fprintf(stderr, "rbuild: %s: tarball must contain exactly one "
                            "top-level directory (found %d)\n", tarball, n);
            free(entry);
            goto done;
        }
    }
    moved = str_cats(tmp, "/", entry, (char *)0);
    free(entry);
    n = exec_runv("mv", moved, dest, (char *)0);
    free(moved);
    if (exec_check(n)) goto done;
    if (exec_check(exec_runv("rmdir", tmp, (char *)0))) goto done;

    sprintf(plevel, "%d", v->patchlevel);
    for (i = 0; i < patches.count; i++) {
        printf("applying %s\n", patches.items[i]);
        fflush(stdout);
        cmd = str_cats("patch -p", plevel, " -d '", dest, "' < '",
                       patches.items[i], "'", (char *)0);
        n = run_sh(cmd);
        free(cmd);
        if (n != 0) {
            if (((n >> 8) & 0xff) == 127)
                fprintf(stderr, "rbuild: \"patch\" not found on PATH; "
                                "install the patch-cmds package\n");
            fprintf(stderr, "rbuild: %s: patch failed\n", patches.items[i]);
            exec_check(n);
            goto done;
        }
    }
    rc = 0;

done:
    strlist_free(&patches);
    free(dest); free(tmp); free(tarball);
    return rc;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: all ten `tests/test_vendor` cases pass; run ends `ALL TESTS PASSED`. Expected stderr noise: the tarbomb message (`found 2`), the not-found message, and `patch` reporting a failed hunk.

- [ ] **Step 5: Verify the dry-run trace by hand**

```bash
cd src/rbuild-1 && rm -rf /tmp/vt && mkdir -p /tmp/vt/src/apk /tmp/vt/root && printf 'tarball = widget-1.0.tar.gz\ndirectory = widget\n' > /tmp/vt/src/apk/vendor && : > /tmp/vt/src/widget-1.0.tar.gz && cat > /tmp/vt/drv.c << 'EOF'
#include "vendor.h"
#include "exec.h"
int main(void) {
    Vendor v; char *p;
    exec_dry_run = 1;
    vendor_init(&v);
    p = vendor_path("/tmp/vt/src");
    if (!p || vendor_read(&v, p) != 0) return 1;
    return vendor_apply(&v, "/tmp/vt/src", "/tmp/vt/root");
}
EOF
cc -Wall -O -I. -o /tmp/vt/drv /tmp/vt/drv.c strutil.o exec.o vendor.o && /tmp/vt/drv
```

Expected output — note the `mv` uses the tarball stem because nothing was really extracted:

```
vendoring widget-1.0.tar.gz into /tmp/vt/root/widget
rm -rf /tmp/vt/root/widget
rm -rf /tmp/vt/root/.vendor-tmp
mkdir -p /tmp/vt/root/.vendor-tmp
sh -c "gzip -dc '/tmp/vt/src/widget-1.0.tar.gz' | tar -C '/tmp/vt/root/.vendor-tmp' -xf -"
mv /tmp/vt/root/.vendor-tmp/widget-1.0 /tmp/vt/root/widget
rmdir /tmp/vt/root/.vendor-tmp
```

Then clean up: `rm -rf /tmp/vt`

- [ ] **Step 6: Commit**

```bash
git add src/rbuild-1/vendor.c src/rbuild-1/tests/test_vendor.c
git commit -m "rbuild: extract vendored tarballs and apply patch series into SRCROOT"
```

---

### Task 5: `builder_apkdir()` and metadata reader selection

**Files:**
- Modify: `src/rbuild-1/builder.h`
- Modify: `src/rbuild-1/builder.c` (`builder_scan_dir`, currently lines 393-422)
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Consumes: `pkginfo_read()` (Task 2); existing `readcontrol()`, `makecontrol()`, `builder_dir2name()`, `builder_getparams()`, and the file-scope constants `DEFAULT_DESC`, `DEFAULT_MAINT`, `ARCH`.
- Produces: `char *builder_apkdir(const char *source)` — malloc'd `"<source>/apk"` if that directory exists, else `NULL`. Used again in Tasks 6 and 7.

Resolution order in `builder_scan_dir`: `apk/` exists → `apk/pkginfo` is **required** (hard error, no fall-through); else `dpkg/control` if readable; else the synthesized defaults `makecontrol()` already produces.

- [ ] **Step 1: Write the failing test**

Add to `src/rbuild-1/tests/test_builder.c`, before `run_all()`:

```c
TEST(test_apkdir) {
    char *p;
    system("rm -rf /tmp/rbtest_meta && mkdir -p /tmp/rbtest_meta/have/apk "
           "/tmp/rbtest_meta/lack/dpkg");
    p = builder_apkdir("/tmp/rbtest_meta/have");
    CHECK_STR(p, "/tmp/rbtest_meta/have/apk");
    free(p);
    CHECK(builder_apkdir("/tmp/rbtest_meta/lack") == 0);
    system("rm -rf /tmp/rbtest_meta");
}

TEST(test_scan_dir_apk_preferred) {
    Package pkg;
    Params params;
    int rc;

    /* both apk/ and dpkg/ present: apk/pkginfo wins */
    system("rm -rf /tmp/rbtest_src2 && "
           "mkdir -p /tmp/rbtest_src2/zlib/apk /tmp/rbtest_src2/zlib/dpkg");
    {
        FILE *f = fopen("/tmp/rbtest_src2/zlib/apk/pkginfo", "w");
        fputs("pkgname = zlib\npkgver = 1.1.3\n"
              "pkgdesc = Zip library\n"
              "builddepends = build-base\n", f);
        fclose(f);
        f = fopen("/tmp/rbtest_src2/zlib/dpkg/control", "w");
        fputs("Package: wrong\nVersion: 0\n", f);
        fclose(f);
    }
    package_init(&pkg);
    params_init(&params);
    rc = builder_scan_dir("/tmp/rbtest_src2/zlib", &pkg, &params);
    CHECK_INT(rc, 0);
    CHECK_STR(pkg.package, "zlib");
    CHECK_STR(pkg.version, "1.1.3");
    CHECK_STR(pkg.source, "zlib");
    CHECK_STR(pkg.architecture, "universal-apple-rhapsody");
    CHECK_STR(pkg.description, "Zip library");
    /* maintainer defaulted, since apk/pkginfo omitted it */
    CHECK(pkg.maintainer != 0);
    package_free(&pkg);
    params_free(&params);
    system("rm -rf /tmp/rbtest_src2");
}

TEST(test_scan_dir_apk_without_pkginfo_fails) {
    Package pkg;
    Params params;
    int rc;

    system("rm -rf /tmp/rbtest_src3 && mkdir -p /tmp/rbtest_src3/zlib/apk");
    package_init(&pkg);
    params_init(&params);
    rc = builder_scan_dir("/tmp/rbtest_src3/zlib", &pkg, &params);
    CHECK_INT(rc, 1);
    package_free(&pkg);
    params_free(&params);
    system("rm -rf /tmp/rbtest_src3");
}
```

Extend `run_all()` in the same file, after `RUN(test_scan_dir);`:

```c
    RUN(test_apkdir);
    RUN(test_scan_dir_apk_preferred);
    RUN(test_scan_dir_apk_without_pkginfo_fails);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_builder
```

Expected: FAILS on `builder_apkdir` being undeclared.

- [ ] **Step 3: Write the implementation**

In `src/rbuild-1/builder.h`, add next to the other `builder_*` declarations (after `builder_resolve_dependency`):

```c
/* Malloc'd "<source>/apk" if that directory exists, else NULL. Its presence
   is what makes a project apk-native: metadata comes from apk/pkginfo,
   maintainer scripts from apk/<script>, vendoring from apk/vendor. */
char *builder_apkdir(const char *source);
```

In `src/rbuild-1/builder.c`, add this function immediately above `builder_scan_dir`:

```c
char *builder_apkdir(const char *source) {
    char *p = str_cats(source, "/apk", (char *)0);
    struct stat st;
    if (stat(p, &st) == 0 && S_ISDIR(st.st_mode)) return p;
    free(p);
    return 0;
}
```

Then replace the whole body of `builder_scan_dir` with:

```c
int builder_scan_dir(const char *source, Package *pkg, Params *params) {
    char *pbase = 0, *pname = 0, *rev = 0;
    char *apkdir;
    char *projname;

    builder_dir2name(source, &pbase, &pname, &rev);

    apkdir = builder_apkdir(source);
    if (apkdir) {
        /* apk-native: apk/pkginfo is required. No silent fall-through to
           dpkg/, so metadata never comes from two places at once. */
        char *info = str_cats(apkdir, "/pkginfo", (char *)0);
        int rc = pkginfo_read(pkg, info);
        free(info);
        free(apkdir);
        if (rc != 0) {
            free(pbase); free(pname); free(rev);
            return 1;
        }
        if (!pkg->description) package_set(&pkg->description, DEFAULT_DESC);
        if (!pkg->maintainer) package_set(&pkg->maintainer, DEFAULT_MAINT);
        package_set(&pkg->architecture, ARCH);
    } else {
        char *control_path = str_cats(source, "/dpkg/control", (char *)0);
        if (readcontrol(pkg, control_path) != 0) {
            /* reset any partial parse and synthesize default */
            package_free(pkg);
            package_init(pkg);
            makecontrol(pkg, pname);
        }
        free(control_path);
    }

    package_set(&pkg->source, pbase);
    if (rev) {
        char *nv = str_cats(pkg->version, "-", rev, (char *)0);
        package_set(&pkg->version, nv);
        free(nv);
    }

    projname = str_cats(pkg->package, "-", pkg->version, (char *)0);
    builder_getparams(projname, params);
    free(projname);

    free(pbase); free(pname); free(rev);
    return 0;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: the three new `test_builder` cases pass, the pre-existing `test_scan_dir` (dpkg path) still passes, and the run ends `ALL TESTS PASSED`. One `unable to open .../apk/pkginfo` message on stderr is expected.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/builder.c src/rbuild-1/builder.h src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: prefer apk/pkginfo over dpkg/control for package metadata"
```

---

### Task 6: Wire vendoring into `builder_setupdirs()`

**Files:**
- Modify: `src/rbuild-1/builder.c` (`builder_setupdirs`, currently lines 593-628)
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Consumes: `vendor_path()`, `vendor_read()`, `vendor_apply()`, `vendor_init()`, `vendor_free()` (Tasks 3-4).
- Produces: no new symbols. `builder_setupdirs()` keeps its signature; a project with `apk/vendor` gets its tarball and patch dir excluded from the rsync and the tree materialized afterwards.

- [ ] **Step 1: Write the failing test**

Add to `src/rbuild-1/tests/test_builder.c`, before `run_all()`:

```c
/* A project with apk/vendor gets extracted and patched into SRCROOT as part
   of setupdirs, with no make involved. */
TEST(test_setupdirs_vendors) {
    Package pkg;
    Params p;
    strlist repo;
    int rc;
    FILE *f;

    system("rm -rf /tmp/rb_ven && "
           "mkdir -p /tmp/rb_ven/srcdir/apk /tmp/rb_ven/srcdir/patches "
           "/tmp/rb_ven/stage/widget-1.0");
    system("echo orig > /tmp/rb_ven/stage/widget-1.0/hello.txt");
    system("(cd /tmp/rb_ven/stage && tar -cf - widget-1.0 | gzip -9 "
           "> /tmp/rb_ven/srcdir/widget-1.0.tar.gz)");
    f = fopen("/tmp/rb_ven/srcdir/apk/vendor", "w");
    fputs("tarball = widget-1.0.tar.gz\ndirectory = widget\n", f);
    fclose(f);
    f = fopen("/tmp/rb_ven/srcdir/apk/pkginfo", "w");
    fputs("pkgname = widget\npkgver = 1.0\n", f);
    fclose(f);
    f = fopen("/tmp/rb_ven/srcdir/patches/0001-change.patch", "w");
    fputs("--- widget-1.0/hello.txt\n"
          "+++ widget/hello.txt\n"
          "@@ -1 +1 @@\n"
          "-orig\n"
          "+patched\n", f);
    fclose(f);
    f = fopen("/tmp/rb_ven/srcdir/Makefile", "w");
    fputs("all:\n", f);
    fclose(f);

    package_init(&pkg);
    strlist_init(&repo);
    params_init(&p);
    p.BUILDROOT = xstrdup("/tmp/rb_ven/br");
    p.OBJROOT = xstrdup("/tmp/rb_ven/obj");
    p.SYMROOT = xstrdup("/tmp/rb_ven/sym");
    p.DSTROOT = xstrdup("/tmp/rb_ven/dst");
    p.HDRROOT = xstrdup("/tmp/rb_ven/hdr");
    p.PACKAGEROOT = xstrdup("/tmp/rb_ven/pkg");
    p.SRCROOT = xstrdup("/tmp/rb_ven/src");
    p.SRCDIR = xstrdup("/tmp/rb_ven/srcdir");

    /* native=1 so makeroot is skipped and the empty repository is fine */
    rc = builder_setupdirs(&pkg, &p, "widget", "dir", &repo, 1);
    CHECK_INT(rc, 0);

    /* the wrapper Makefile was rsynced in ... */
    CHECK(access("/tmp/rb_ven/src/Makefile", 0) == 0);
    /* ... the upstream tree was extracted, renamed and patched ... */
    CHECK(access("/tmp/rb_ven/src/widget/hello.txt", 0) == 0);
    /* ... and the tarball and patch dir were NOT copied into SRCROOT */
    CHECK(access("/tmp/rb_ven/src/widget-1.0.tar.gz", 0) != 0);
    CHECK(access("/tmp/rb_ven/src/patches", 0) != 0);

    params_free(&p);
    strlist_free(&repo);
    package_free(&pkg);
    system("rm -rf /tmp/rb_ven");
}
```

Add `#include <unistd.h>` to the test's includes if it is not already there, and extend `run_all()`:

```c
    RUN(test_setupdirs_vendors);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder
```

Expected: compiles, and `test_setupdirs_vendors` FAILS — the tarball is rsynced into SRCROOT and `/tmp/rb_ven/src/widget/hello.txt` does not exist.

- [ ] **Step 3: Write the implementation**

Add `#include "vendor.h"` to the includes at the top of `src/rbuild-1/builder.c`.

Replace the `if (strcmp(srctype, "dir") == 0) { ... } else { ... }` block at the end of `builder_setupdirs` with:

```c
    if (strcmp(srctype, "dir") == 0) {
        Vendor v;
        char *vpath;
        char *cmd;
        char *argv[4];
        int have_vendor = 0;
        int rc;

        vendor_init(&v);
        vpath = vendor_path(params->SRCDIR);
        if (vpath) {
            if (vendor_read(&v, vpath) != 0) {
                free(vpath); vendor_free(&v); return 1;
            }
            free(vpath);
            have_vendor = 1;
        }

        if (exec_check(mkdirp(params->SRCROOT))) { vendor_free(&v); return 1; }

        /* The tarball and the patch series are build inputs, not sources:
           keep them out of SRCROOT. */
        if (have_vendor)
            cmd = str_cats("(cd '", params->SRCDIR,
                           "' && rsync -avr . --exclude=CVS/ --exclude=.svn/ "
                           "--exclude=.git/ --exclude=", v.tarball,
                           " --exclude=", v.patches, "/ '",
                           params->SRCROOT, "')", (char *)0);
        else
            cmd = str_cats("(cd '", params->SRCDIR,
                           "' && rsync -avr . --exclude=CVS/ --exclude=.svn/ "
                           "--exclude=.git/ '", params->SRCROOT, "')", (char *)0);
        argv[0] = "sh"; argv[1] = "-c"; argv[2] = cmd; argv[3] = 0;
        exec_printcmd(argv);
        rc = exec_run_checked(argv);
        free(cmd);
        if (rc) { vendor_free(&v); return 1; }

        if (have_vendor &&
            vendor_apply(&v, params->SRCDIR, params->SRCROOT) != 0) {
            vendor_free(&v);
            return 1;
        }
        vendor_free(&v);
    } else {
        fprintf(stderr, "rbuild: unknown source type %s\n", srctype);
        return 1;
    }
    return 0;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: `test_setupdirs_vendors` passes; the pre-existing `test_setupdirs_native_skips_makeroot` still passes (its SRCDIR does not exist, so `vendor_path` returns NULL and the unchanged rsync command is used); run ends `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: materialize vendored sources into SRCROOT during setup"
```

---

### Task 7: apk-native maintainer scripts

apk executes scripts stored as **dotted** members of the package root — `.pre-install`, `.post-install`, `.pre-deinstall`, `.post-deinstall`, `.pre-upgrade`, `.post-upgrade` (`src/apk-tools-1/apk-tools/src/package.c:234`, matched via `apk_script_type(&ae->name[1])` at `database.c:1053`). The dpkg names rbuild emits today are never executed by apk, and apk has no `conffiles` concept.

**Files:**
- Modify: `src/rbuild-1/builder.c` (`builder_buildpackage`, the script-copy block currently at lines 729-751)
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Consumes: `builder_apkdir()` (Task 5); existing `file_exists()`, `exec_runv()`.
- Produces: no new symbols. Scripts are read from `<SRCDIR>/apk/<name>` and written to `<dstroot>/.<name>`, mode 755. `conffiles` and the dpkg names are no longer read.

- [ ] **Step 1: Write the failing test**

Add to `src/rbuild-1/tests/test_builder.c`, before `run_all()`:

```c
/* builder_buildpackage("binary") installs apk-named scripts as dotted
   members of the package root. */
TEST(test_buildpackage_apk_scripts) {
    Package pkg;
    Params p;
    FILE *f;

    system("rm -rf /tmp/rb_scr && mkdir -p /tmp/rb_scr/srcdir/apk "
           "/tmp/rb_scr/dst /tmp/rb_scr/pkgdir");
    f = fopen("/tmp/rb_scr/srcdir/apk/post-install", "w");
    fputs("#! /bin/sh\necho hi\n", f);
    fclose(f);
    /* a dpkg-named script must now be ignored */
    system("mkdir -p /tmp/rb_scr/srcdir/dpkg");
    f = fopen("/tmp/rb_scr/srcdir/dpkg/postinst", "w");
    fputs("#! /bin/sh\necho old\n", f);
    fclose(f);

    package_init(&pkg);
    package_set(&pkg.package, "widget");
    package_set(&pkg.version, "1.0");
    package_set(&pkg.architecture, "universal-apple-rhapsody");
    package_set(&pkg.description, "Widget");
    package_set(&pkg.maintainer, "M <m@x>");

    params_init(&p);
    p.DSTROOT = xstrdup("/tmp/rb_scr/dst");
    p.HDRROOT = xstrdup("/tmp/rb_scr/hdr");
    p.LIBCOBJROOT = xstrdup("/tmp/rb_scr/cobj");
    p.SRCDIR = xstrdup("/tmp/rb_scr/srcdir");
    p.PACKAGEDIR = xstrdup("/tmp/rb_scr/pkgdir");

    CHECK_INT(builder_buildpackage(&pkg, &p, "binary"), 0);
    CHECK(access("/tmp/rb_scr/dst/.post-install", 0) == 0);
    CHECK(access("/tmp/rb_scr/dst/postinst", 0) != 0);
    CHECK(access("/tmp/rb_scr/dst/.PKGINFO", 0) == 0);
    CHECK(access("/tmp/rb_scr/pkgdir/widget-1.0.apk", 0) == 0);

    params_free(&p);
    package_free(&pkg);
    system("rm -rf /tmp/rb_scr");
}
```

Extend `run_all()`:

```c
    RUN(test_buildpackage_apk_scripts);
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder
```

Expected: `test_buildpackage_apk_scripts` FAILS — `/tmp/rb_scr/dst/.post-install` does not exist and `/tmp/rb_scr/dst/postinst` does.

- [ ] **Step 3: Write the implementation**

In `src/rbuild-1/builder.c`, replace the script-copy block inside `builder_buildpackage` (the one beginning `/* For binary, copy present maintainer scripts into dstroot. */`) with:

```c
    /* For binary, install apk maintainer scripts. apk reads them as dotted
       members of the package root (apk-tools src/package.c:234,
       src/database.c:1053), so "post-install" becomes ".post-install".
       apk has no conffiles concept -- it writes ".apk-new" for locally
       modified files -- so there is nothing to declare. */
    if (strcmp(target, "binary") == 0 && params->SRCDIR) {
        static const char *names[] =
            { "pre-install", "post-install", "pre-deinstall",
              "post-deinstall", "pre-upgrade", "post-upgrade", 0 };
        char *apkdir = builder_apkdir(params->SRCDIR);
        if (apkdir) {
            int i;
            for (i = 0; names[i]; i++) {
                char *extra = str_cats(apkdir, "/", names[i], (char *)0);
                if (file_exists(extra)) {
                    char *dest = str_cats(dstroot, "/.", names[i], (char *)0);
                    printf("copying %s\n", names[i]);
                    fflush(stdout);
                    if (exec_runv("cp", "-p", extra, dest, (char *)0) != 0) {
                        free(extra); free(dest); free(apkdir);
                        rc = 1; goto done;
                    }
                    exec_runv("chmod", "755", dest, (char *)0);
                    free(dest);
                }
                free(extra);
            }
            free(apkdir);
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd src/rbuild-1 && make test
```

Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Verify the emitted package members**

```bash
cd src/rbuild-1 && ./tests/test_builder > /dev/null && ls -a /tmp/rb_scr 2>/dev/null; echo "(cleaned up by the test)"
```

Expected: the directory is gone — the test cleans up. The `CHECK(access(...))` assertions in Step 1 are the real verification.

- [ ] **Step 6: Commit**

```bash
git add src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: emit maintainer scripts under apk's dotted names"
```

---

### Task 8: Convert `files-5` to apk metadata

`files-5` is the only project with maintainer scripts. **Consequence to be aware of:** its scripts have never actually run (apk ignored the dpkg names); after this task they will run on install. Their content is safe — no arguments are consumed, so apk's `execle(fn, "pre-install", version, "", NULL)` convention needs no change to them.

**Files:**
- Create: `src/files-5/apk/pkginfo`
- Move: `src/files-5/dpkg/preinst` → `src/files-5/apk/pre-install`
- Move: `src/files-5/dpkg/postinst` → `src/files-5/apk/post-install`
- Delete: `src/files-5/dpkg/conffiles`, `src/files-5/dpkg/control`

**Interfaces:**
- Consumes: `apk/pkginfo` format (Task 2), apk script names (Task 7).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Create the apk metadata directory and move the scripts**

```bash
cd src && mkdir -p files-5/apk && git mv files-5/dpkg/preinst files-5/apk/pre-install && git mv files-5/dpkg/postinst files-5/apk/post-install
```

- [ ] **Step 2: Write `src/files-5/apk/pkginfo`**

Translated from the old `dpkg/control` (`Package: files`, `Version: 282.0`, `Description: Miscellaneous system files`, `Build-Depends: build-base, adv-cmds`), with `Vendor:` preserved as documentation:

```
pkgname = files
pkgver = 282.0
pkgdesc = Miscellaneous system files
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
builddepends = build-base adv-cmds
vendor = Apple Computer
```

- [ ] **Step 3: Remove the dpkg directory**

`conffiles` is dropped because apk has no equivalent — it writes `.apk-new` for any locally-modified file automatically.

```bash
cd src && git rm files-5/dpkg/conffiles files-5/dpkg/control
```

- [ ] **Step 4: Verify rbuild reads the new metadata**

Confirm the scan resolves the right package name and version from `apk/pkginfo`:

```bash
cd src && mkdir -p /tmp/emptydst && printf 'dir\tfiles-5\tall\n' > /tmp/m1 && rbuild-1/rbuild missing /tmp/m1 /tmp/emptydst
```

Expected:

```
must build files-282.0.apk using dir files-5
```

- [ ] **Step 5: Commit**

```bash
git add src/files-5/apk src/files-5/dpkg
git commit -m "files: convert package metadata and maintainer scripts to apk names"
```

---

### Task 9: Convert `zlib` to a vendored tarball + patch series

This is the pilot. `zlib/Makefile` sets `Project = zlib`, so GNUSource.make resolves `Sources = $(SRCROOT)/zlib` — exactly the `directory` the descriptor names. **The Makefile is not modified.**

The in-tree delta is small: `src/zlib/zlib/configure` carries `Darwin*)` and `Rhapsody*)` cases setting `SHAREDEXT='.dylib'` (lines 118-125) that upstream 1.1.3 does not have.

**Files:**
- Create: `src/zlib/apk/pkginfo`, `src/zlib/apk/vendor`
- Create: `src/zlib/zlib-1.1.3.tar.gz`, `src/zlib/patches/0001-rhapsody-port.patch`
- Delete: `src/zlib/zlib/` (102 files), `src/zlib/dpkg/control`

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Obtain the upstream tarball**

**This step downloads a file and needs the user's explicit go-ahead before you run it.** The canonical archive is:

```bash
curl -fLO https://zlib.net/fossils/zlib-1.1.3.tar.gz
```

Verify it is the right artifact before using it, and record its checksum in the commit message so the provenance is auditable:

```bash
gzip -dc zlib-1.1.3.tar.gz | tar -tf - | head -3 && gzip -dc zlib-1.1.3.tar.gz | tar -xOf - zlib-1.1.3/zlib.h | grep 'define ZLIB_VERSION' && openssl sha1 zlib-1.1.3.tar.gz
```

Expected: the archive's sole top-level directory is `zlib-1.1.3/`, and `zlib.h` declares `#define ZLIB_VERSION "1.1.3"` — matching `src/zlib/zlib/zlib.h:40`.

Then place it: `mv zlib-1.1.3.tar.gz src/zlib/`

- [ ] **Step 2: Generate the patch series**

Run this from the repository root; `REPO` captures it so the `cd` does not lose the path:

```bash
REPO="$(pwd)" && rm -rf /tmp/zvendor && mkdir -p /tmp/zvendor && cd /tmp/zvendor && gzip -dc "$REPO/src/zlib/zlib-1.1.3.tar.gz" | tar -xf - && cp -R "$REPO/src/zlib/zlib" ./zlib && diff -urN zlib-1.1.3 zlib > 0001-rhapsody-port.patch; echo "diff exit $? (1 = differences found, expected)"
```

- [ ] **Step 3: Review the patch before accepting it**

```bash
cd /tmp/zvendor && grep -c '^+++' 0001-rhapsody-port.patch && grep '^+++' 0001-rhapsody-port.patch
```

Expected: `configure` appears. If files you did not expect show up — object files, editor backups, `.DS_Store` — delete them from the copied tree and regenerate, because they are build residue rather than a real delta. Read the `configure` hunk and confirm it is the `Darwin*)` / `Rhapsody*)` block.

- [ ] **Step 4: Install the patch and the descriptor**

```bash
cd src/zlib && mkdir -p apk patches && cp /tmp/zvendor/0001-rhapsody-port.patch patches/
```

Write `src/zlib/apk/vendor`:

```
tarball = zlib-1.1.3.tar.gz
directory = zlib
```

Write `src/zlib/apk/pkginfo` (translated from `dpkg/control`, with the multi-line `Description` folded onto one line — the whole point of the format change):

```
pkgname = zlib
pkgver = 1.1.3
pkgdesc = Zip library
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
builddepends = build-base
vendor = Info-ZIP
url = http://www.cdrom.com/pub/infozip/zlib/
```

- [ ] **Step 5: Verify the patch applies to a fresh extraction**

Again from the repository root:

```bash
REPO="$(pwd)" && rm -rf /tmp/zcheck && mkdir -p /tmp/zcheck && cd /tmp/zcheck && gzip -dc "$REPO/src/zlib/zlib-1.1.3.tar.gz" | tar -xf - && mv zlib-1.1.3 zlib && patch -p1 -d zlib < "$REPO/src/zlib/patches/0001-rhapsody-port.patch" && diff -r zlib "$REPO/src/zlib/zlib" && echo "IDENTICAL"
```

Expected: `patch` reports only successful hunks, `diff -r` prints nothing, and `IDENTICAL` is printed. If `diff -r` prints anything, the patch is incomplete — go back to Step 2.

- [ ] **Step 6: Remove the expanded tree and the dpkg metadata**

Only after Step 5 printed `IDENTICAL`:

```bash
cd src && git rm -r --quiet zlib/zlib && git rm zlib/dpkg/control
```

- [ ] **Step 7: Verify the dry-run trace**

```bash
cd src && mkdir -p /tmp/emptydst && rbuild-1/rbuild -n buildpackage --dir zlib /tmp/emptydst /tmp/emptydst 2>&1 | head -30
```

Expected: among the printed commands, in this order — the `rsync` line carrying `--exclude=zlib-1.1.3.tar.gz --exclude=patches/`, then `vendoring zlib-1.1.3.tar.gz into .../zlib`, the `gzip -dc ... | tar -C ... -xf -` line, `mv .../.vendor-tmp/zlib-1.1.3 .../zlib`, and `applying .../patches/0001-rhapsody-port.patch`.

- [ ] **Step 8: Build for real on the Rhapsody guest**

This is the acceptance test and must run on the guest, where `cc`, `make`, and the seed repository live. Use the same repository and destination you normally pass to `rbuild buildall`.

```bash
rbuild buildpackage --dir zlib <repository> <dstdir>
```

Expected: `zlib-1.1.3.apk` and `zlib-hdrs-1.1.3.apk` appear in `<dstdir>`, and the build log shows the vendoring lines before the first `make` invocation.

- [ ] **Step 9: Compare against a pre-conversion build**

```bash
gzip -dc <dstdir>/zlib-1.1.3.apk | tar -tf - | sort > /tmp/after.txt && git stash && rbuild buildpackage --dir zlib <repository> /tmp/beforedst && gzip -dc /tmp/beforedst/zlib-1.1.3.apk | tar -tf - | sort > /tmp/before.txt && git stash pop && diff /tmp/before.txt /tmp/after.txt && echo "PACKAGE CONTENTS MATCH"
```

Expected: `PACKAGE CONTENTS MATCH`. If the lists differ, the vendored tree is not equivalent to the old one — return to Step 2 rather than accepting the difference.

- [ ] **Step 10: Commit**

Put the checksum from Step 1 in the message body so the tarball's provenance is recorded:

```bash
git add src/zlib
git commit -m "zlib: vendor pristine 1.1.3 tarball with the Rhapsody port as a patch

Upstream zlib-1.1.3.tar.gz sha1 <paste from step 1>."
```

---

### Task 10: Document the new project layout

**Files:**
- Modify: `src/rbuild-1/README.md`

**Interfaces:**
- Consumes: the behavior built in Tasks 1-7.
- Produces: nothing.

- [ ] **Step 1: Update the Notes section**

In `src/rbuild-1/README.md`, replace the `## Notes` list with:

```markdown
## Notes

- Source type is always `dir`; `--cvs` is rejected (support removed).
- Produces `<name>.apk`, `<name>-hdrs.apk`, `<name>-obj.apk`.
- `.PKGINFO` carries a custom `builddepends` field (apk ignores unknown keys).
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm`, `mv`, `rmdir` and — for vendored projects — `patch`
  on `PATH`. `patch` comes from the `patch-cmds` package, which is in
  `Manifest` but not `BootstrapManifest`, so no vendored project may join
  the stage-0 bootstrap set.

## Project metadata

A project's metadata lives in `apk/`, or in `dpkg/control` for projects not
yet migrated. When `apk/` exists it is authoritative and `apk/pkginfo` is
required.

`apk/pkginfo` uses apk `.PKGINFO` syntax — one `key = value` per line, `#`
comments, no continuation lines. `pkgname` and `pkgver` are required;
`pkgdesc`, `maintainer`, `provides`, `replaces`, and `builddepends` are
optional; `builddepends` splits on space or comma; unknown keys such as
`url` and `vendor` are ignored and may be kept as documentation. `arch` and
`origin` are computed by rbuild and ignored on input.

Maintainer scripts are `apk/{pre-install,post-install,pre-deinstall,
post-deinstall,pre-upgrade,post-upgrade}`, installed into the package as
dotted members (`.post-install`). apk has no `conffiles` equivalent.

## Vendored sources

A project may ship a pristine upstream tarball plus an ordered patch series
instead of an expanded source tree. Add `apk/vendor`:

    tarball = zlib-1.1.3.tar.gz
    directory = zlib
    patches = patches
    patchlevel = 1

`tarball` and `directory` are required; `patches` defaults to `patches` and
`patchlevel` to `1`. After rsyncing the project into SRCROOT — excluding the
tarball and the patch directory — rbuild extracts the tarball, renames its
sole top-level directory to `directory`, and applies `<patches>/*.patch` in
ascending filename order. The project's Makefile then builds normally and
needs no knowledge of any of this. Tarballs must contain exactly one
top-level directory.

See `src/zlib` for a worked example.
```

- [ ] **Step 2: Verify the file reads correctly**

```bash
cd src/rbuild-1 && cat README.md
```

Expected: the three sections above appear, with no leftover mention of `dpkg/control` as the only metadata source.

- [ ] **Step 3: Commit**

```bash
git add src/rbuild-1/README.md
git commit -m "rbuild: document apk metadata layout and vendored sources"
```

---

## Self-Review Notes

Spec coverage check against `docs/specs/2026-07-24-rbuild-vendor-design.md`:

| Spec requirement | Task |
|---|---|
| `key = value` parsing shared by both readers | 1 |
| `apk/pkginfo` reader, required keys, ignored `arch`/`origin` | 2 |
| `apk/vendor` descriptor + fields and defaults | 3 |
| Patch series in ascending `strcmp` order, `.patch` only | 3 |
| Explicit-vs-default missing patch directory | 3 |
| Extract via `gzip -dc | tar -xf -`, rename sole entry, idempotent re-extract | 4 |
| Tarbomb rejection | 4 |
| `patch` exit 127 → `patch-cmds` hint | 4 |
| Metadata resolution order, `apk/` without `pkginfo` is fatal | 5 |
| rsync excludes for tarball and patch dir | 6 |
| Vendor step after rsync, before `make` | 6 |
| apk dotted script names, `conffiles` dropped | 7 |
| `files-5` conversion | 8 |
| `zlib` pilot, expanded tree removed | 9 |
| Manual verification: dry-run trace, real build, package-content comparison | 9 |
| `patch`/bootstrap constraint documented | 10 |
| No `Manifest` change needed | — none required; `dir zlib all` already works |
