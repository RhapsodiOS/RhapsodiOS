# rbuild Vendored Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revised 2026-09-24** against rbuild at `eb1c28351`. The July version's
metadata tasks (dpkg → `apk/pkginfo`, dotted scripts, `files-5`) are gone,
because that work shipped under the 2026-09-16 apk-pkginfo plan. The remaining
tasks were rewritten for the current `builder_setupdirs()`, `BuildOptions`,
toolchain profiles, and test layout.

**Goal:** Let a project in `src/` carry its upstream code as a pristine tarball plus an ordered patch series. rbuild extracts and patches that into SRCROOT before `make` runs, and the project's wrapper Makefile builds it unchanged.

**Architecture:** A new `vendor.c` owns descriptor parsing, patch enumeration, and the extract → rename → patch sequence, taking plain paths plus a `Toolchain`. Extraction goes through a new `apk_untar()` that reuses `apk.c`'s existing gzip|tar pipeline and pax fallback without APK validation. `builder_setupdirs()` calls `vendor_apply()` right after the rsync.

**Tech Stack:** C89, POSIX, `cc -Wall -O`, GNU Make 3.74 on the box. Home-grown test harness in `src/rbuild-1/tests/test.h`. Runtime tools: toolchain `tar`/`gzip`/`rsync` (default `pax`/`gzip`/`rsync`), plus `patch`, `mv`, `mkdir`, `rmdir`, `rm` from PATH.

**Spec:** `docs/superpowers/specs/2026-07-24-rbuild-vendor-design.md`

## Global Constraints

- **Work in the worktree** `D:\RhapsodiOS\.claude\worktrees\rbuild-vendor`, branch `rbuild-vendor`. Other sessions share the main checkout's git index and stash, so never commit from `D:\RhapsodiOS` itself and never use bare `git stash`.
- **There is no C compiler on the Windows host.** Every `make`/`make test` runs on the Rhapsody build box (10.10.0.241) in the private root `/build/rbuild-vendor`, set up in Task 0. Edit on Windows, sync with `vm/sync-src.ps1 -Path rbuild-1`, then build on the box.
- **One SSH session to the box at a time.** No background box commands, no polling loops. If the box freezes, stop all box work and wait for Pat to say it is back. Pass this rule to any subagent.
- **Box shell gotchas:** `/bin/sh` is 4.4BSD ash, and `ls` exits 0 for missing paths, so test existence with `test -e`/`test -f`/`test -d`. Make is GNU Make 3.74: edit existing variable lines in place, never add a second definition.
- **C89 only:** declarations at the top of a block, `/* */` comments. Match the surrounding code.
- **All subprocesses go through `exec.h`** (`exec_runv`, `exec_run_checked`, `exec_check`) or, for extraction, `apk_untar()`, so that `-n/--dry-run` prints instead of executing. **No `sh -c`.** rbuild no longer uses it anywhere.
- **Return convention:** 0 success, non-zero failure; messages to `stderr` prefixed `rbuild: `.
- **patch invocation, exactly:** `patch -f -E --no-backup-if-mismatch -p<N> -d <dir> -i <file>`. `-f` never prompts, where 2.5 would otherwise read `/dev/tty` under an interactive SSH session. `-E` deletes files a hunk empties. `--no-backup-if-mismatch` stops 2.5's default `.orig` on any offset or fuzz (`patch.c:132,225`).
- **Patch series order:** ascending `strcmp` of filename, `.patch` suffix only.
- **Never hand-edit a `.patch` file with the Edit tool.** Generate it with `diff`. Legacy trees can carry Mac-Roman bytes, which the Edit tool silently re-encodes.
- **Every task ends green:** on the box, `/bin/make CC=/usr/bin/cc test` ends with `ALL TESTS PASSED` and the integration scripts exit 0.
- **Commit messages** start with the subsystem (`rbuild: `, `zlib: `), are one to two lines, describe behavior, and carry **no trailers or metadata** (`CLAUDE.md` §5).

## File Structure

| File | Responsibility |
|---|---|
| `src/rbuild-1/strutil.c/.h` | Add `str_parse_kv()`, the one `key = value` splitter. |
| `src/rbuild-1/pkginfo.c` | Switch `pkginfo_read()` to `str_parse_kv()`. No behavior change. |
| `src/rbuild-1/apk.c/.h` | Add `apk_untar()`: gzip\|tar extraction with toolchain tools or pax fallback, with **no** APK validation. |
| `src/rbuild-1/vendor.c/.h` | **Create.** Descriptor, patch list, extract → rename → patch. |
| `src/rbuild-1/builder.c` | `builder_setupdirs()`: read `apk/vendor`, add anchored rsync excludes, call `vendor_apply()`. |
| `src/rbuild-1/Makefile` | `vendor.o` into `OBJS`, `test_builder_OBJS`, `test_runner_OBJS`; new `tests/test_vendor`. |
| `src/rbuild-1/tests/test_strutil.c`, `test_apk.c`, `test_builder.c` | New cases. |
| `src/rbuild-1/tests/test_vendor.c` | **Create.** |
| `src/rbuild-1/README.md` | Document `apk/vendor` and the `patch` dependency. |
| `.gitattributes` | `src/*/patches/*.patch -text`. |
| `src/zlib-1/` | Add `apk/vendor`, `zlib-1.1.3.tar.gz`, `patches/0001-rhapsody-port.patch`; remove `zlib/`. |

---

### Task 0: Box preflight and a pre-conversion baseline

Nothing is committed in this task. It proves the box has the tools that the
rest of the plan assumes, and it records what zlib's APKs contain **before** any
change, for the comparison in Task 7.

**Files:** none in git. On Windows, `vm/vm.conf` in the worktree (gitignored).

- [ ] **Step 1: Point syncing at a private root**

Copy `D:\RhapsodiOS\vm\vm.conf` to `D:\RhapsodiOS\.claude\worktrees\rbuild-vendor\vm\vm.conf` and set `RemoteRoot=/build/rbuild-vendor` in the copy. Leave the original alone.

- [ ] **Step 2: Create the private tree on the box**

Run on the box. Use a single session, through `vm/rhap-remote.ps1`'s `Invoke-RhapSshScript` or an interactive SSH login:

```sh
mkdir -p /build/rbuild-vendor/src /build/rbuild-vendor/bin /build/rbuild-vendor/roots /build/rbuild-vendor/out-before
cd /build/rbuild-vendor/src && for e in /build/src/*; do n=`basename $e`; case $n in rbuild-1|zlib-1) ;; *) test -e $n || ln -s $e $n ;; esac; done
```

Never symlink `rbuild-1` or `zlib-1`: they are synced as real directories, and syncing through a symlink would write into the shared `/build/src`.

- [ ] **Step 3: Sync the two real projects** (Windows, worktree root)

```powershell
pwsh vm/sync-src.ps1 -Path rbuild-1
pwsh vm/sync-src.ps1 -Path zlib-1
```

- [ ] **Step 4: Check the host tools vendoring depends on** (box)

```sh
for d in `echo $PATH | tr : ' '`; do test -x $d/patch && echo "patch: $d/patch"; done
patch --version 2>&1 | head -1
test -x /bin/pax && echo "pax: ok"
```

Expected: at least one `patch:` line; a version line reading `patch 2.5` or newer; `pax: ok`.

**If `patch` is missing or older than 2.5, stop and report it.** `--no-backup-if-mismatch` first appeared in 2.5. The options are to install `patch-cmds` from `/build/repo` onto the host or to drop that flag. That decision belongs to Pat, not the implementer.

- [ ] **Step 5: Build the unmodified rbuild and the baseline zlib APKs** (box)

`BUILDIT_DIR` moves the build roots out of the shared `/private/tmp/roots`.

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc clean all && cp rbuild /build/rbuild-vendor/bin/rbuild
cd /build/rbuild-vendor/src && BUILDIT_DIR=/build/rbuild-vendor/roots PATH=/build/rbuild-vendor/bin:$PATH:/build/tools/bin rbuild buildpackage --dir zlib-1 /build/repo /build/rbuild-vendor/out-before
cd /build/rbuild-vendor/out-before && for f in *.apk; do /usr/bin/gzip -dc $f | /bin/pax | sort > $f.list; done; ls
```

Expected: `zlib-1.1.3-1-universal.apk`, plus `zlib-hdrs-1.1.3-1-universal.apk` if zlib installs headers, each with a `.list` beside it. **Write down the exact filenames.** Task 7 must reproduce them. If the build fails, stop: the baseline is broken before any change, and that needs reporting first.

---

### Task 1: `str_parse_kv()`, and `pkginfo_read()` switched to it

`apk/vendor` uses the same syntax as `apk/pkginfo`. One splitter guarantees the two never drift.

**Files:**
- Modify: `src/rbuild-1/strutil.h` (append before `#endif`), `src/rbuild-1/strutil.c` (append)
- Modify: `src/rbuild-1/pkginfo.c` (`pkginfo_read`, the per-line parse)
- Test: `src/rbuild-1/tests/test_strutil.c`

**Interfaces:**
- Produces: `int str_parse_kv(char *line, char **key, char **val)` returns 1 on an entry, with `*key`/`*val` trimmed and pointing into `line`, and 0 for blank lines, `#` comments, and lines without `=`. Only the first `=` splits. **Key case is preserved**, because `pkginfo_read` is case-sensitive today. Mutates `line`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_strutil.c` before `run_all()`:

```c
TEST(test_parse_kv) {
    char l1[] = "pkgname = zlib\n";
    char l2[] = "  Pkgver=1.1.3  ";
    char l3[] = "# comment = x";
    char l4[] = "\n";
    char l5[] = "no equals here";
    char l6[] = "pkgdesc = a = b";
    char l7[] = "patches =";
    char *k = 0, *v = 0;

    CHECK_INT(str_parse_kv(l1, &k, &v), 1);
    CHECK_STR(k, "pkgname");
    CHECK_STR(v, "zlib");

    /* both sides trimmed; key case preserved */
    CHECK_INT(str_parse_kv(l2, &k, &v), 1);
    CHECK_STR(k, "Pkgver");
    CHECK_STR(v, "1.1.3");

    CHECK_INT(str_parse_kv(l3, &k, &v), 0);
    CHECK_INT(str_parse_kv(l4, &k, &v), 0);
    CHECK_INT(str_parse_kv(l5, &k, &v), 0);

    /* only the FIRST '=' separates */
    CHECK_INT(str_parse_kv(l6, &k, &v), 1);
    CHECK_STR(k, "pkgdesc");
    CHECK_STR(v, "a = b");

    /* an empty value is a real entry */
    CHECK_INT(str_parse_kv(l7, &k, &v), 1);
    CHECK_STR(k, "patches");
    CHECK_STR(v, "");
}
```

Add `RUN(test_parse_kv);` as the last line of `run_all()` in that file.

- [ ] **Step 2: Sync and confirm it fails** (Windows, then box)

```powershell
pwsh vm/sync-src.ps1 -Path rbuild-1
```
```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc tests/test_strutil
```

Expected: the link FAILS with an undefined `_str_parse_kv`.

- [ ] **Step 3: Implement**

Append to `strutil.h`, before `#endif`:

```c
/* Splits one "key = value" line in place (apk .PKGINFO syntax). Returns 1
   and points *key/*val into line on an entry; 0 for blank lines, '#'
   comments, and lines with no '='. Only the first '=' separates; both
   sides are trimmed; key case is preserved. Do not free *key or *val. */
int str_parse_kv(char *line, char **key, char **val);
```

Append to `strutil.c`:

```c
int str_parse_kv(char *line, char **key, char **val) {
    char *k, *eq;

    k = str_trim(line);
    if (k[0] == '\0' || k[0] == '#') return 0;
    eq = strchr(k, '=');
    if (eq == 0) return 0;
    *eq = '\0';
    *key = str_trim(k);
    *val = str_trim(eq + 1);
    return 1;
}
```

In `pkginfo.c`'s `pkginfo_read`, delete the `char *eq;` declaration and replace these seven lines:

```c
        line = str_trim(line);
        if (line[0] == '\0' || line[0] == '#') continue;
        eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        key = str_trim(line);
        val = str_trim(eq + 1);
```

with:

```c
        if (!str_parse_kv(line, &key, &val)) continue;
```

The logic is identical line for line. The existing `tests/test_pkginfo.c` is the regression guard, and it must pass **unmodified**.

- [ ] **Step 4: Sync and run the full suite** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc test
```

Expected: `- test_parse_kv` with no `FAIL`, every `test_pkginfo` case still passing, and `ALL TESTS PASSED`.

- [ ] **Step 5: Commit** (Windows, worktree)

```bash
git add src/rbuild-1/strutil.c src/rbuild-1/strutil.h src/rbuild-1/pkginfo.c src/rbuild-1/tests/test_strutil.c
git commit -m "rbuild: share the key=value line splitter used by apk/pkginfo"
```

---

### Task 2: `apk_untar()`, raw tarball extraction

`apk_extract()` cannot be reused. It always runs `validate_artifact()`, which demands POSIX `ustar\0` magic (`apk.c:383`) and rejects old-GNU headers (`test_rejects_oldgnu_header_layout`). Upstream tarballs from the 1990s are GNU tar archives.

**Files:**
- Modify: `src/rbuild-1/apk.h`, and `src/rbuild-1/apk.c` (append after `apk_extract`, around line 1080)
- Test: `src/rbuild-1/tests/test_apk.c`

**Interfaces:**
- Consumes: static `tar_pipeline(fd, root, list_only, tc)`, `valid_tools(tc)`, and `FALLBACK_TAR`, all existing in `apk.c`.
- Produces: `int apk_untar(const char *path, const char *root, const Toolchain *tc)`. `root` must already exist. A NULL `tc` means `pax` + `gzip` from PATH, the same fallback `apk_use_arch` uses. In dry-run it prints `extract <path> into <root>` and returns 0.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_apk.c` before `run_all()`:

```c
/* Vendored upstream tarballs are not APKs: an old-GNU header, which
   apk_validate rejects (test_rejects_oldgnu_header_layout), must extract. */
TEST(test_untar_extracts_oldgnu_upstream_archive) {
    char scratch[128];
    char archive[192];
    char root[192];
    char extracted[256];
    Toolchain tc;
    TarEntry entries[] = {
        { "widget-1.0/hello.txt", '0', 0, "orig\n", ENTRY_OLDGNU }
    };

    make_scratch(scratch, sizeof(scratch), "untar");
    sprintf(archive, "%s/widget-1.0.tar.gz", scratch);
    sprintf(root, "%s/root", scratch);
    sprintf(extracted, "%s/widget-1.0/hello.txt", root);
    CHECK_INT(make_apk(archive, entries, 1), 0);
    CHECK_INT(mkdir(root, 0700), 0);
    init_toolchain(&tc);
    CHECK_INT(apk_untar(archive, root, &tc), 0);
    CHECK(access(extracted, F_OK) == 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}

TEST(test_untar_missing_archive_fails) {
    Toolchain tc;
    init_toolchain(&tc);
    CHECK_INT(apk_untar("/tmp/rbuild-no-such-archive.tar.gz", "/tmp", &tc), 1);
}

TEST(test_untar_dry_run_touches_nothing) {
    char scratch[128];
    char root[192];
    char archive[192];

    make_scratch(scratch, sizeof(scratch), "untardry");
    sprintf(root, "%s/root", scratch);
    sprintf(archive, "%s/none.tar.gz", scratch);
    exec_dry_run = 1;
    /* root does not exist and the archive is missing: dry-run still only prints */
    CHECK_INT(apk_untar(archive, root, 0), 0);
    exec_dry_run = 0;
    CHECK(access(root, F_OK) != 0);
    CHECK_INT(exec_runv("/bin/rm", "-rf", scratch, (char *)0), 0);
}
```

Append to the end of `run_all()` in `tests/test_apk.c`:

```c
    RUN(test_untar_extracts_oldgnu_upstream_archive);
    RUN(test_untar_missing_archive_fails);
    RUN(test_untar_dry_run_touches_nothing);
```

- [ ] **Step 2: Sync and confirm it fails** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc tests/test_apk
```

Expected: the link FAILS with an undefined `_apk_untar`.

- [ ] **Step 3: Implement**

Add to `apk.h`, before `#endif`:

```c
/* Extracts a gzipped tar into an existing root with the toolchain's gzip and
 * tar (NULL: pax and gzip from PATH). No APK validation: for vendored
 * upstream tarballs. Dry-run prints and returns 0. */
int apk_untar(const char *path, const char *root, const Toolchain *tc);
```

Append to `apk.c`, after `apk_extract()`:

```c
int apk_untar(const char *path, const char *root, const Toolchain *tc) {
    Toolchain fallback;
    int fd;
    int rc;

    if (exec_dry_run) {
        printf("extract %s into %s\n", path, root);
        fflush(stdout);
        return 0;
    }
    if (!tc) {
        toolchain_init(&fallback);
        fallback.tar = FALLBACK_TAR; fallback.gzip = "gzip";
        tc = &fallback;
    }
    if (!valid_tools(tc)) {
        fprintf(stderr, "rbuild: missing configured tar/gzip\n");
        return 1;
    }
    fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "rbuild: unable to open %s\n", path);
        return 1;
    }
    rc = tar_pipeline(fd, root, 0, tc);
    close(fd);
    if (rc) fprintf(stderr, "rbuild: unable to extract %s\n", path);
    return rc;
}
```

- [ ] **Step 4: Sync and run the full suite** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc test
```

Expected: the three `test_untar_*` cases pass and the run ends `ALL TESTS PASSED`. `unable to open` on stderr is expected.

**If `test_untar_extracts_oldgnu_upstream_archive` fails, stop and report.** It means the box's tar cannot read GNU-format archives, and the zlib pilot would fail the same way.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/apk.c src/rbuild-1/apk.h src/rbuild-1/tests/test_apk.c
git commit -m "rbuild: extract plain gzipped tarballs without APK validation"
```

---

### Task 3: `vendor.c`, descriptor and patch list

**Files:**
- Create: `src/rbuild-1/vendor.h`, `src/rbuild-1/vendor.c`, `src/rbuild-1/tests/test_vendor.c`
- Modify: `src/rbuild-1/Makefile`

**Interfaces:**
- Consumes: `str_parse_kv()` (Task 1); `apk_untar()` (Task 2, first called in Task 4).
- Produces:
  - `typedef struct { char *tarball; char *directory; char *patches; int patchlevel; int patches_explicit; } Vendor;`
  - `void vendor_init(Vendor *v)` zeroes the struct and sets `patchlevel = 1`. `void vendor_free(Vendor *v)`.
  - `char *vendor_path(const char *source)` returns malloc'd `"<source>/apk/vendor"` if that file exists, else NULL.
  - `int vendor_read(Vendor *v, const char *path)` returns 0/1 and fails on a missing file, `tarball`, or `directory`.
  - `int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out)` returns 0/1 and pushes full paths in ascending `strcmp` order.
  - `int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot, const Toolchain *tc)`: declared here, implemented in Task 4.

- [ ] **Step 1: Write the failing test**

Create `tests/test_vendor.c`:

```c
#include "vendor.h"
#include "exec.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

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
        "patchlevel = 2\n"
        "url = ignored\n");

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
        "tarball = zlib-1.1.3.tar.gz\ndirectory = zlib\n");

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
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 1);
    vendor_free(&v);

    write_file("/tmp/rbtest_vd/apk/vendor", "tarball = z.tar.gz\n");
    vendor_init(&v);
    CHECK_INT(vendor_read(&v, "/tmp/rbtest_vd/apk/vendor"), 1);
    vendor_free(&v);
}

TEST(test_vendor_path) {
    char *p;
    write_file("/tmp/rbtest_vd/apk/vendor", "tarball = z.tar.gz\ndirectory = z\n");
    p = vendor_path("/tmp/rbtest_vd");
    CHECK_STR(p, "/tmp/rbtest_vd/apk/vendor");
    free(p);
    CHECK(vendor_path("/tmp/rbtest_vd/apk") == 0);
}

TEST(test_vendor_list_patches_sorted) {
    Vendor v;
    strlist out;

    /* created out of order on purpose */
    system("mkdir -p /tmp/rbtest_vd/patches && "
           "touch /tmp/rbtest_vd/patches/0002-second.patch "
           "/tmp/rbtest_vd/patches/0001-first.patch "
           "/tmp/rbtest_vd/patches/README");

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

    vendor_init(&v);
    v.tarball = xstrdup("z.tar.gz");
    v.directory = xstrdup("z");
    v.patches = xstrdup("nosuchdir");

    /* absent DEFAULT patch dir: fine, no patches */
    strlist_init(&out);
    CHECK_INT(vendor_list_patches(&v, "/tmp/rbtest_vd", &out), 0);
    CHECK_INT(out.count, 0);
    strlist_free(&out);

    /* absent EXPLICIT patch dir: error */
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

Edit `src/rbuild-1/Makefile` **in place**. GNU Make 3.74 silently lets a later duplicate win, so do not add second definitions:

1. `OBJS =` line: insert `vendor.o` after `apk.o`.
2. `TESTS =` line: append ` tests/test_vendor`.
3. `test_builder_OBJS =` and `test_runner_OBJS =` lines: insert `vendor.o` after `apk.o` in each. `builder.o` calls `vendor.o` from Task 5 on.
4. Add a new line after `test_runner_OBJS`:
   ```make
   test_vendor_OBJS = strutil.o exec.o toolchain.o apk.o products.o macho.o architecture.o vendor.o
   ```
5. Add the rule after the `tests/test_kernel` rule:
   ```make
   tests/test_vendor: tests/test_vendor.c $(test_vendor_OBJS)
   	$(CC) $(CFLAGS) -I. -o $@ tests/test_vendor.c $(test_vendor_OBJS)
   ```
   The recipe line starts with a TAB.

- [ ] **Step 2: Sync and confirm it fails** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc tests/test_vendor
```

Expected: FAILS with `vendor.h: No such file or directory`.

- [ ] **Step 3: Implement**

Create `vendor.h`:

```c
#ifndef RBUILD_VENDOR_H
#define RBUILD_VENDOR_H

#include "strutil.h"
#include "toolchain.h"

/* A vendored source: a pristine upstream tarball plus an ordered patch
   series, described by "<project>/apk/vendor". */
typedef struct {
    char *tarball;        /* required; relative to the project dir */
    char *directory;      /* required; name the extracted tree gets in SRCROOT */
    char *patches;        /* default "patches"; relative to the project dir */
    int patchlevel;       /* default 1; -p level passed to patch */
    int patches_explicit; /* 1 if "patches" was named in the file */
} Vendor;

void vendor_init(Vendor *v);
void vendor_free(Vendor *v);

/* Malloc'd "<source>/apk/vendor" if that file exists, else NULL. */
char *vendor_path(const char *source);

/* 0 on success; 1 if unreadable or tarball/directory is missing. */
int vendor_read(Vendor *v, const char *path);

/* Pushes every "*.patch" under "<srcdir>/<patches>" in ascending strcmp
   order. An absent default directory means no patches; an absent explicit
   one is an error. */
int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out);

/* Extracts <srcdir>/<tarball> into <srcroot>/<directory> (renaming the
   tarball's sole top-level entry), then applies the patch series.
   <srcroot>/<directory> must not already exist. */
int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot,
                 const Toolchain *tc);

#endif
```

Create `vendor.c`. The `vendor_apply` stub is replaced in Task 4:

```c
#include "vendor.h"
#include "apk.h"
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
        /* unknown keys ignored, as in pkginfo_read */
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
    /* Same directory prefix on every path, so this orders by filename. */
    if (out->count > 1)
        qsort(out->items, out->count, sizeof(char *), cmp_str);
    return 0;
}

int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot,
                 const Toolchain *tc) {
    (void) v; (void) srcdir; (void) srcroot; (void) tc;
    fprintf(stderr, "rbuild: vendor_apply not implemented\n");
    return 1;
}
```

- [ ] **Step 4: Sync and run the full suite** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc test
```

Expected: six `test_vendor` cases pass, and the run ends `ALL TESTS PASSED`. The descriptor and patch-dir error messages are expected stderr.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/vendor.c src/rbuild-1/vendor.h src/rbuild-1/tests/test_vendor.c src/rbuild-1/Makefile
git commit -m "rbuild: parse vendored-source descriptors and list their patch series"
```

---

### Task 4: `vendor_apply()`, extract → rename → patch

**Files:**
- Modify: `src/rbuild-1/vendor.c` (replace the stub)
- Test: `src/rbuild-1/tests/test_vendor.c`

**Interfaces:**
- Consumes: `apk_untar()` (Task 2), `vendor_list_patches()` (Task 3), `exec_runv`/`exec_check`/`exec_dry_run`.
- Produces: `vendor_apply()` as declared in Task 3. It prints `vendoring <tarball> into <dest>` and `applying <patch>`. Builders and humans grep for those lines.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_vendor.c`, before `run_all()`, and add `#include <sys/stat.h>` to its includes:

```c
static int file_is(const char *path, const char *want) {
    FILE *f = fopen(path, "r");
    char buf[256];
    size_t n;
    if (!f) return 0;
    n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = '\0';
    fclose(f);
    return strcmp(buf, want) == 0;
}

/* /tmp/rbtest_va/src: a project dir holding widget-1.0.tar.gz (top-level
   widget-1.0/ with hello.txt = "top\norig\n" and gone.txt = "bye\n");
   /tmp/rbtest_va/root: an empty SRCROOT. */
static void make_widget_project(void) {
    system("rm -rf /tmp/rbtest_va && "
           "mkdir -p /tmp/rbtest_va/src/patches /tmp/rbtest_va/root "
           "/tmp/rbtest_va/stage/widget-1.0 && "
           "printf 'top\\norig\\n' > /tmp/rbtest_va/stage/widget-1.0/hello.txt && "
           "echo bye > /tmp/rbtest_va/stage/widget-1.0/gone.txt && "
           "cd /tmp/rbtest_va/stage && /bin/pax -w -x ustar widget-1.0 | "
           "/usr/bin/gzip -c > /tmp/rbtest_va/src/widget-1.0.tar.gz");
}

static void widget_vendor(Vendor *v) {
    vendor_init(v);
    v->tarball = xstrdup("widget-1.0.tar.gz");
    v->directory = xstrdup("widget");
    v->patches = xstrdup("patches");
}

TEST(test_vendor_apply) {
    Vendor v;
    struct stat st;

    make_widget_project();
    /* 0001: "@@ -1" but "orig" is on line 2, so it applies at offset 1.
       Plain patch 2.5 would leave hello.txt.orig behind. */
    write_file("/tmp/rbtest_va/src/patches/0001-change.patch",
        "--- widget-1.0/hello.txt\n"
        "+++ widget/hello.txt\n"
        "@@ -1 +1 @@\n"
        "-orig\n"
        "+patched\n");
    /* 0002: empties gone.txt; -E must delete it */
    write_file("/tmp/rbtest_va/src/patches/0002-remove.patch",
        "--- widget-1.0/gone.txt\n"
        "+++ widget/gone.txt\n"
        "@@ -1 +0,0 @@\n"
        "-bye\n");

    widget_vendor(&v);
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 0);
    CHECK(file_is("/tmp/rbtest_va/root/widget/hello.txt", "top\npatched\n"));
    CHECK(stat("/tmp/rbtest_va/root/widget/gone.txt", &st) != 0);
    CHECK(stat("/tmp/rbtest_va/root/widget/hello.txt.orig", &st) != 0);
    CHECK(stat("/tmp/rbtest_va/root/.vendor-tmp", &st) != 0);
    vendor_free(&v);
}

TEST(test_vendor_apply_refuses_existing_tree) {
    Vendor v;
    /* left over from test_vendor_apply: root/widget exists, which is what a
       project with both apk/vendor and an expanded tree looks like */
    widget_vendor(&v);
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_missing_tarball) {
    Vendor v;
    widget_vendor(&v);
    free(v.tarball);
    v.tarball = xstrdup("nosuch.tar.gz");
    system("rm -rf /tmp/rbtest_va/root/widget");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_rejects_tarbomb) {
    Vendor v;
    system("rm -rf /tmp/rbtest_va/root && mkdir -p /tmp/rbtest_va/root "
           "/tmp/rbtest_va/bomb && echo a > /tmp/rbtest_va/bomb/a.txt && "
           "echo b > /tmp/rbtest_va/bomb/b.txt && cd /tmp/rbtest_va/bomb && "
           "/bin/pax -w -x ustar a.txt b.txt | /usr/bin/gzip -c "
           "> /tmp/rbtest_va/src/bomb.tar.gz");
    widget_vendor(&v);
    free(v.tarball);
    v.tarball = xstrdup("bomb.tar.gz");
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_bad_patch_fails) {
    Vendor v;
    make_widget_project();
    write_file("/tmp/rbtest_va/src/patches/0001-bad.patch",
        "--- widget-1.0/hello.txt\n"
        "+++ widget/hello.txt\n"
        "@@ -1 +1 @@\n"
        "-something else entirely\n"
        "+patched\n");
    widget_vendor(&v);
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 1);
    vendor_free(&v);
}

TEST(test_vendor_apply_dry_run) {
    Vendor v;
    struct stat st;
    make_widget_project();
    widget_vendor(&v);
    exec_dry_run = 1;
    CHECK_INT(vendor_apply(&v, "/tmp/rbtest_va/src", "/tmp/rbtest_va/root", 0), 0);
    exec_dry_run = 0;
    CHECK(stat("/tmp/rbtest_va/root/widget", &st) != 0);
    vendor_free(&v);
    system("rm -rf /tmp/rbtest_va");
}
```

Append to `run_all()`:

```c
    RUN(test_vendor_apply);
    RUN(test_vendor_apply_refuses_existing_tree);
    RUN(test_vendor_apply_missing_tarball);
    RUN(test_vendor_apply_rejects_tarbomb);
    RUN(test_vendor_apply_bad_patch_fails);
    RUN(test_vendor_apply_dry_run);
```

- [ ] **Step 2: Sync and confirm the new cases fail** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc tests/test_vendor && ./tests/test_vendor
```

Expected: `test_vendor_apply` and `test_vendor_apply_dry_run` FAIL with `got 1 want 0` (the stub). The failure-path cases pass trivially for now.

- [ ] **Step 3: Implement**

Replace the stub at the end of `vendor.c` with:

```c
/* Number of entries other than "." and ".."; the first is returned in *name
   (malloc'd). -1 if the directory cannot be opened. */
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

int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot,
                 const Toolchain *tc) {
    char *dest = str_cats(srcroot, "/", v->directory, (char *)0);
    char *tmp = str_cats(srcroot, "/.vendor-tmp", (char *)0);
    char *tarball = str_cats(srcdir, "/", v->tarball, (char *)0);
    char *entry = 0;
    char *moved;
    strlist patches;
    char plevel[16];
    struct stat st;
    size_t i;
    int n;
    int rc = 1;

    strlist_init(&patches);
    if (!is_file(tarball)) {
        fprintf(stderr, "rbuild: %s: tarball not found\n", tarball);
        goto done;
    }
    if (vendor_list_patches(v, srcdir, &patches) != 0) goto done;
    /* SRCROOT was just wiped and rsynced, so dest can only exist if the
       project still carries its expanded tree next to apk/vendor. */
    if (!exec_dry_run && lstat(dest, &st) == 0) {
        fprintf(stderr, "rbuild: %s already exists; a project with "
                "apk/vendor must not also carry the expanded tree\n", dest);
        goto done;
    }

    printf("vendoring %s into %s\n", v->tarball, dest);
    fflush(stdout);
    if (exec_check(exec_runv("mkdir", tmp, (char *)0))) goto done;
    if (apk_untar(tarball, tmp, tc) != 0) goto done;
    if (exec_dry_run) {
        printf("rename sole entry of %s to %s\n", tmp, dest);
        fflush(stdout);
    } else {
        n = sole_entry(tmp, &entry);
        if (n != 1) {
            fprintf(stderr, "rbuild: %s: tarball must contain exactly one "
                    "top-level entry (found %d)\n", tarball, n);
            goto done;
        }
        moved = str_cats(tmp, "/", entry, (char *)0);
        n = exec_runv("mv", moved, dest, (char *)0);
        free(moved);
        if (exec_check(n)) goto done;
    }
    if (exec_check(exec_runv("rmdir", tmp, (char *)0))) goto done;

    sprintf(plevel, "-p%d", v->patchlevel);
    for (i = 0; i < patches.count; i++) {
        printf("applying %s\n", patches.items[i]);
        fflush(stdout);
        n = exec_runv("patch", "-f", "-E", "--no-backup-if-mismatch", plevel,
                      "-d", dest, "-i", patches.items[i], (char *)0);
        if (exec_check(n)) {
            fprintf(stderr, "rbuild: %s: patch failed\n", patches.items[i]);
            goto done;
        }
    }
    rc = 0;

done:
    strlist_free(&patches);
    free(entry); free(dest); free(tmp); free(tarball);
    return rc;
}
```

- [ ] **Step 4: Sync and run the full suite** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc test
```

Expected: all twelve `test_vendor` cases pass, and the run ends `ALL TESTS PASSED`. Expected stderr: `already exists`, `tarball not found`, `found 2`, and patch's own hunk-failure output.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/vendor.c src/rbuild-1/tests/test_vendor.c
git commit -m "rbuild: extract vendored tarballs and apply their patch series"
```

---

### Task 5: Wire vendoring into `builder_setupdirs()`

**Files:**
- Modify: `src/rbuild-1/builder.c` (includes; the `if (strcmp(srctype, "dir") == 0)` block at the end of `builder_setupdirs`, about lines 1113-1134)
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Consumes: `vendor_*` (Tasks 3-4); `opt->toolchain`.
- Produces: no new symbols. A project with `apk/vendor` gets `--exclude=/<tarball>` and `--exclude=/<patches>/` on its rsync, and its tree is materialized afterwards.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_builder.c` before `run_all()`:

```c
static void vendor_fixture_file(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    fputs(text, f);
    fclose(f);
}

static void vendor_fixture_params(Params *p, const char *base) {
    params_init(p);
    p->OBJROOT = str_cats(base, "/obj", (char *)0);
    p->SYMROOT = str_cats(base, "/sym", (char *)0);
    p->DSTROOT = str_cats(base, "/dst", (char *)0);
    p->HDRROOT = str_cats(base, "/hdr", (char *)0);
    p->PACKAGEROOT = str_cats(base, "/pkg", (char *)0);
    p->SRCROOT = str_cats(base, "/src", (char *)0);
    p->SRCDIR = str_cats(base, "/srcdir", (char *)0);
    p->LIBCOBJROOT = str_cats(base, "/cobj", (char *)0);
    p->BUILDROOT = str_cats(base, "/br", (char *)0);
}

TEST(test_setupdirs_vendors) {
    Package pkg;
    Params p;
    strlist repo;
    BuildOptions opt;

    CHECK_INT(system("rm -rf /tmp/rb_ven && "
        "mkdir -p /tmp/rb_ven/srcdir/apk /tmp/rb_ven/srcdir/patches "
        "/tmp/rb_ven/srcdir/sub/patches /tmp/rb_ven/stage/widget-1.0 && "
        "echo orig > /tmp/rb_ven/stage/widget-1.0/hello.txt && "
        "echo keep > /tmp/rb_ven/srcdir/sub/patches/keep.txt && "
        "echo all: > /tmp/rb_ven/srcdir/Makefile && "
        "cd /tmp/rb_ven/stage && /bin/pax -w -x ustar widget-1.0 | "
        "/usr/bin/gzip -c > /tmp/rb_ven/srcdir/widget-1.0.tar.gz"), 0);
    vendor_fixture_file("/tmp/rb_ven/srcdir/apk/vendor",
        "tarball = widget-1.0.tar.gz\ndirectory = widget\n");
    vendor_fixture_file("/tmp/rb_ven/srcdir/patches/0001-change.patch",
        "--- widget-1.0/hello.txt\n+++ widget/hello.txt\n"
        "@@ -1 +1 @@\n-orig\n+patched\n");

    package_init(&pkg);
    strlist_init(&repo);
    build_options_init(&opt);
    opt.bootstrap = 1;          /* no chroot: empty repository is fine */
    vendor_fixture_params(&p, "/tmp/rb_ven");

    CHECK_INT(builder_setupdirs(&pkg, &p, "widget", "dir", &repo, &opt), 0);
    CHECK(access("/tmp/rb_ven/src/Makefile", F_OK) == 0);
    CHECK(access("/tmp/rb_ven/src/widget/hello.txt", F_OK) == 0);
    /* build inputs stay out of SRCROOT ... */
    CHECK(access("/tmp/rb_ven/src/widget-1.0.tar.gz", F_OK) != 0);
    CHECK(access("/tmp/rb_ven/src/patches", F_OK) != 0);
    /* ... but the excludes are anchored: a nested patches/ still copies */
    CHECK(access("/tmp/rb_ven/src/sub/patches/keep.txt", F_OK) == 0);

    /* half-finished conversion: expanded tree still in the project */
    CHECK_INT(system("mkdir -p /tmp/rb_ven/srcdir/widget"), 0);
    CHECK_INT(builder_setupdirs(&pkg, &p, "widget", "dir", &repo, &opt), 1);

    params_free(&p);
    strlist_free(&repo);
    package_free(&pkg);
    system("rm -rf /tmp/rb_ven");
}
```

Append `RUN(test_setupdirs_vendors);` to `run_all()` in that file.

- [ ] **Step 2: Sync and confirm it fails** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc tests/test_builder && ./tests/test_builder
```

Expected: `test_setupdirs_vendors` FAILS. The tarball and `patches/` are rsynced into SRCROOT, and `src/widget/hello.txt` does not exist.

- [ ] **Step 3: Implement**

Add `#include "vendor.h"` to `builder.c`'s includes. Replace the `if (strcmp(srctype, "dir") == 0) { ... }` branch in `builder_setupdirs` (keep the `else` that follows it) with:

```c
    if (strcmp(srctype, "dir") == 0) {
        char *source;
        char *argv[11];
        char *tar_exclude = 0;
        char *patch_exclude = 0;
        char *vpath;
        const char *rsync = "rsync";
        Vendor v;
        int have_vendor = 0;
        int a;
        int rc;

        vendor_init(&v);
        vpath = vendor_path(params->SRCDIR);
        if (vpath) {
            rc = vendor_read(&v, vpath);
            free(vpath);
            if (rc) { vendor_free(&v); return 1; }
            have_vendor = 1;
        }
        if (exec_check(mkdirp(params->SRCROOT))) { vendor_free(&v); return 1; }
        if (opt && opt->toolchain && opt->toolchain->rsync)
            rsync = opt->toolchain->rsync;
        source = str_cats(params->SRCDIR, "/", (char *)0);
        argv[0] = (char *)rsync; argv[1] = "-avr"; argv[2] = source;
        argv[3] = "--exclude=CVS/"; argv[4] = "--exclude=.svn/";
        argv[5] = "--exclude=.git/"; argv[6] = "--exclude=.hg/";
        a = 7;
        if (have_vendor) {
            /* Build inputs, not sources. Leading '/' anchors at SRCDIR/. */
            tar_exclude = str_cats("--exclude=/", v.tarball, (char *)0);
            patch_exclude = str_cats("--exclude=/", v.patches, "/", (char *)0);
            argv[a++] = tar_exclude;
            argv[a++] = patch_exclude;
        }
        argv[a++] = params->SRCROOT; argv[a] = 0;
        exec_printcmd(argv);
        rc = exec_run_checked(argv);
        free(source); free(tar_exclude); free(patch_exclude);
        if (rc == 0 && have_vendor)
            rc = vendor_apply(&v, params->SRCDIR, params->SRCROOT,
                              opt ? opt->toolchain : 0);
        vendor_free(&v);
        if (rc) return 1;
    }
```

- [ ] **Step 4: Sync and run the full suite** (box)

```sh
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc test
```

Expected: `test_setupdirs_vendors` passes; the existing `test_setupdirs_*` cases and the integration scripts still pass (their SRCDIRs have no `apk/vendor`), and the run ends `ALL TESTS PASSED`. Then run `/bin/make CC=/usr/bin/cc trace-test` and confirm it is unchanged: its fixtures have no `apk/vendor`.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: materialize vendored sources into SRCROOT during setup"
```

---

### Task 6: `.gitattributes` and README

**Files:**
- Modify: `.gitattributes`, `src/rbuild-1/README.md`

- [ ] **Step 1: Keep patch bytes exact**

`* text=auto eol=lf` would strip any CR byte inside a hunk on commit, and the patch would then stop applying. Add to `.gitattributes`, directly after the `# --- Preserve original CRLF line endings` block:

```
# Vendored patch series must be stored byte-for-byte: a hunk against an
# upstream CRLF file carries CR bytes that eol=lf would strip.
src/*/patches/*.patch -text
```

Verify the rule matches and does not reach existing patches elsewhere in the tree:

```bash
git check-attr text -- src/zlib-1/patches/0001-x.patch src/perl-1/perl/win32/des_fcrypt.patch
```

Expected: `src/zlib-1/patches/0001-x.patch: text: unset` and `.../des_fcrypt.patch: text: auto`.

- [ ] **Step 2: Document it**

`README.md` has one non-ASCII line (a UTF-8 `…`). It is valid UTF-8, so the Edit tool is safe; check `git diff` afterwards anyway.

In `src/rbuild-1/README.md`, in the `## Notes` list, change the last bullet to:

```markdown
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm` on `PATH`, and for vendored projects on `mv`, `rmdir`
  and GNU `patch` 2.5 or later. Patching runs on the host, before any chroot.
```

Then add this section immediately before the paragraph that begins ``make trace-test` is an rbuild `-n` dry-run``:

```markdown
## Vendored sources

A project may ship a pristine upstream tarball and an ordered patch series
instead of an expanded tree. `apk/vendor` uses `apk/pkginfo` syntax:

    tarball = zlib-1.1.3.tar.gz
    directory = zlib
    patches = patches
    patchlevel = 1

`tarball` and `directory` are required; `patches` and `patchlevel` default as
shown. After rsyncing the project into SRCROOT (without the tarball or the
patch directory), rbuild extracts the tarball with the toolchain's `gzip` and
`tar`, renames its single top-level directory to `directory`, and runs
`patch -f -E --no-backup-if-mismatch -p<level>` for each `<patches>/*.patch`
in filename order. The project's Makefile then builds normally. The tarball
must hold exactly one top-level directory, and the project must not also
carry the expanded tree. See `src/zlib-1`.
```

- [ ] **Step 3: Commit**

```bash
git add .gitattributes src/rbuild-1/README.md
git commit -m "rbuild: document vendored sources and store patch series byte-exact"
```

---

### Task 7: Convert `zlib-1` to a vendored tarball + patch

`zlib-1/Makefile` sets `Project = zlib`, so GNUSource.make builds from `$(SRCROOT)/zlib`, which is exactly `directory = zlib`. **The Makefile is not modified.** Steps 1-6 run on Windows in the worktree. Steps 7-9 run on the box.

**Files:**
- Create: `src/zlib-1/apk/vendor`, `src/zlib-1/zlib-1.1.3.tar.gz`, `src/zlib-1/patches/0001-rhapsody-port.patch`
- Delete: `src/zlib-1/zlib/` (102 files)

- [ ] **Step 1: Obtain the upstream tarball. This needs Pat's explicit go-ahead first: it downloads a file.**

```bash
curl -fL -o src/zlib-1/zlib-1.1.3.tar.gz https://zlib.net/fossils/zlib-1.1.3.tar.gz
```

Verify it before trusting it:

```bash
tar -tzf src/zlib-1/zlib-1.1.3.tar.gz | sed 's#/.*##' | sort -u
tar -xzOf src/zlib-1/zlib-1.1.3.tar.gz zlib-1.1.3/zlib.h | grep 'define ZLIB_VERSION'
sha1sum src/zlib-1/zlib-1.1.3.tar.gz
```

Expected: exactly one top-level name, `zlib-1.1.3`; `#define ZLIB_VERSION "1.1.3"`, matching `src/zlib-1/zlib/zlib.h:40`. Keep the sha1 for the commit message.

- [ ] **Step 2: Generate the patch**

```bash
W="$(pwd)" && S="$(mktemp -d)" && tar -xzf "$W/src/zlib-1/zlib-1.1.3.tar.gz" -C "$S" && cp -R "$W/src/zlib-1/zlib" "$S/zlib" && (cd "$S" && diff -urN --strip-trailing-cr zlib-1.1.3 zlib > 0001-rhapsody-port.patch; echo "diff exit $? (1 expected)") && echo "$S"
```

`--strip-trailing-cr` exists because git stored this tree LF-only (all 102 files are `i/lf`), while upstream may carry CRLF DOS/Windows build files. Without it the patch fills with line-ending noise.

- [ ] **Step 3: Review the patch**

```bash
grep -E '^(\+\+\+|---) ' "$S/0001-rhapsody-port.patch"
LC_ALL=C grep -c $'\r' "$S/0001-rhapsody-port.patch"
```

Expected: `configure` is patched (the `Darwin*)`/`Rhapsody*)` `.dylib` cases around line 118). Deletions of upstream-generated files are plausible and fine. Git's copy of zlib 1.1.3 has no top-level `Makefile`, which the tarball may ship; `-E` removes such files at apply time. The CR count must be `0`. Read every hunk. If one is not a genuine Apple/RhapsodiOS change (editor backups, build residue), remove that file from `$S/zlib` and regenerate.

- [ ] **Step 4: Prove it reproduces the git tree with rbuild's exact flags**

```bash
C="$(mktemp -d)" && tar -xzf "$W/src/zlib-1/zlib-1.1.3.tar.gz" -C "$C" && mv "$C/zlib-1.1.3" "$C/zlib" && patch -f -E --no-backup-if-mismatch -p1 -d "$C/zlib" -i "$S/0001-rhapsody-port.patch" && diff -r --strip-trailing-cr "$C/zlib" "$W/src/zlib-1/zlib" && find "$C/zlib" -name '*.orig' -o -name '*.rej' | wc -l
```

Expected: `patch` reports only successful hunks, `diff -r` prints nothing, and the final count is `0`. **Do not continue until this is clean.**

- [ ] **Step 5: Install the descriptor and patch; remove the expanded tree**

```bash
mkdir -p src/zlib-1/patches && cp "$S/0001-rhapsody-port.patch" src/zlib-1/patches/
printf 'tarball = zlib-1.1.3.tar.gz\ndirectory = zlib\n' > src/zlib-1/apk/vendor
git rm -r --quiet src/zlib-1/zlib
git add src/zlib-1/apk/vendor src/zlib-1/zlib-1.1.3.tar.gz src/zlib-1/patches
git check-attr text -- src/zlib-1/patches/0001-rhapsody-port.patch
```

Expected: `text: unset` (Task 6's rule). **Do not commit yet.** The box verification comes first.

- [ ] **Step 6: Sync the converted project and the finished rbuild**

```powershell
pwsh vm/sync-src.ps1 -Path rbuild-1
pwsh vm/sync-src.ps1 -Path zlib-1
```

- [ ] **Step 7: Build the converted zlib** (box, one session)

```sh
test -d /build/rbuild-vendor/src/zlib-1/zlib && echo "STALE: remote still has the expanded tree"
cd /build/rbuild-vendor/src/rbuild-1 && /bin/make CC=/usr/bin/cc clean all && cp rbuild /build/rbuild-vendor/bin/rbuild
mkdir -p /build/rbuild-vendor/out-after
cd /build/rbuild-vendor/src && BUILDIT_DIR=/build/rbuild-vendor/roots PATH=/build/rbuild-vendor/bin:$PATH:/build/tools/bin rbuild -n buildpackage --dir zlib-1 /build/repo /build/rbuild-vendor/out-after 2>&1 | grep -n 'rsync\|vendoring\|extract\|rename\|applying\|patch '
BUILDIT_DIR=/build/rbuild-vendor/roots PATH=/build/rbuild-vendor/bin:$PATH:/build/tools/bin rbuild buildpackage --dir zlib-1 /build/repo /build/rbuild-vendor/out-after
```

Expected: no `STALE` line. The dry-run shows, in order: the `rsync` line with `--exclude=/zlib-1.1.3.tar.gz --exclude=/patches/`, `vendoring zlib-1.1.3.tar.gz into …/zlib`, `extract …`, `rename sole entry …`, `applying …/0001-rhapsody-port.patch`, and the `patch -f -E --no-backup-if-mismatch -p1 …` line. The real build succeeds. If a stale remote `zlib/` does show up, the build fails with `already exists`; remove the remote directory and re-sync.

- [ ] **Step 8: Compare against the Task 0 baseline** (box)

```sh
cd /build/rbuild-vendor/out-after && for f in *.apk; do /usr/bin/gzip -dc $f | /bin/pax | sort > $f.list; done
cd /build/rbuild-vendor && for l in out-before/*.list; do n=`basename $l`; if cmp -s $l out-after/$n; then echo "SAME $n"; else echo "DIFF $n"; diff $l out-after/$n; fi; done; ls out-before out-after
```

Expected: the same APK filenames in both directories, and `SAME` for every list. A `DIFF` means the vendored tree is not equivalent to the old one: go back to Step 3 rather than accepting it.

- [ ] **Step 9: Commit** (Windows, worktree)

Put the Step 1 sha1 in the body so the tarball's provenance is recorded:

```bash
git commit -m "zlib: vendor the pristine 1.1.3 tarball with the Rhapsody port as a patch" -m "Upstream zlib-1.1.3.tar.gz sha1 <from step 1>."
```

---

## Self-Review Notes

| Spec requirement | Task |
|---|---|
| One `key = value` splitter shared with `apk/pkginfo` | 1 |
| Extraction via toolchain tar/gzip or pax fallback, without APK validation (accepts old-GNU) | 2 |
| `apk/vendor` fields, defaults, errors | 3 |
| Patch series in `strcmp` order, `.patch` only; default vs explicit missing dir | 3 |
| Extract → sole-entry rename → patch; tarbomb rejected | 4 |
| `patch -f -E --no-backup-if-mismatch`: no prompt, deletions, no `.orig` | 4 (offset and deletion fixtures) |
| Half-finished conversion rejected | 4, 5 |
| Dry-run prints and touches nothing | 2, 4, 7 |
| Anchored rsync excludes; nested `patches/` still copied | 5 |
| Covers every command (`builder_setupdirs` is the single entry) | 5 |
| `.gitattributes` byte-exact patches; README | 6 |
| Box has `patch` ≥ 2.5 and `pax` | 0 |
| zlib pilot: provenance, CR-safe generation, exact-flag reproduction, same APK members | 0, 7 |
| No `Manifest` change | none needed: `dir zlib-1 all` already exists |
