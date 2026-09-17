# Migrate dpkg/control to apk/pkginfo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `apk/pkginfo` the only package metadata rbuild reads, convert all 156 production `dpkg/control` files (plus 2 trace fixtures), and emit Alpine-style `.PKGINFO` plus `makedepends`.

**Architecture:** Hard cutover on a branch from master. `pkginfo_read` parses `key = value`; missing file synthesizes in memory; incomplete file fails. `package_copy` replaces Debian unparse/parse clones. A one-shot Python converter rewrites the tree and deletes every `dpkg/`.

**Tech Stack:** C89 rbuild on the Rhapsody guest (`make test` via `vm/build-src.ps1 -Rbuild`); Python 3 converter on the Windows host; OpenSSH guest sync from the worktree.

**Spec:** `docs/superpowers/specs/2026-09-16-rbuild-apk-pkginfo-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `src/rbuild-1/package.h/.c` | `url`/`license` fields; `package_copy`; delete Debian `package_parse`/`package_unparse` |
| `src/rbuild-1/pkginfo.h/.c` | `pkginfo_read`; `pkginfo_write` emits `makedepends`/`license`/`url` |
| `src/rbuild-1/builder.c` | Scan `apk/pkginfo`; synthesizer; stage `apk/.pre-install` etc. |
| `src/rbuild-1/kernel.c` | Driver discovery via `apk/pkginfo` |
| `src/rbuild-1/runner.c` | Clone packages with `package_copy` |
| `src/rbuild-1/tests/*` | Fixtures use `apk/pkginfo` |
| `tools/convert-dpkg-control-to-pkginfo.py` | One-shot tree conversion |
| `src/**/apk/pkginfo` | Converted metadata |
| `src/rbuild-1/README.md` | Document `apk/pkginfo` and `makedepends` |

Work from the feature worktree. Guest tests: copy `vm/vm.conf` from `D:\RhapsodiOS\vm\vm.conf` if missing, then from the worktree:

```
powershell -NoProfile -File .\vm\sync-src.ps1 -Path rbuild-1
powershell -NoProfile -File .\vm\build-src.ps1 -Rbuild
```

Expected: `ALL TESTS PASSED`, bootstrap scripts PASS, `build-src: complete (rbuild)`, exit 0.

Do not wipe `/build/repo`. Do not run full host `test-build-src.ps1` (pre-existing drvEIDE assertion).

---

### Task 1: `pkginfo_read` and Package url/license

**Files:**
- Modify: `src/rbuild-1/package.h`, `src/rbuild-1/package.c`
- Modify: `src/rbuild-1/pkginfo.h`, `src/rbuild-1/pkginfo.c`
- Modify: `src/rbuild-1/tests/test_pkginfo.c`
- Test: guest `make test` (at least `tests/test_pkginfo`)

- [ ] **Step 1: Write failing `pkginfo_read` tests**

Add these tests to `src/rbuild-1/tests/test_pkginfo.c` and `RUN(...)` them. Include `<sys/stat.h>` if needed for `mkdir`.

```c
static void write_file(const char *path, const char *body) {
    FILE *f = fopen(path, "w");
    CHECK(f != 0);
    if (f) { fputs(body, f); fclose(f); }
}

TEST(test_pkginfo_read_basic) {
    Package p;
    mkdir("/tmp/rb-pkginfo-read", 0700);
    write_file("/tmp/rb-pkginfo-read/pkginfo",
        "pkgname = grep\n"
        "pkgver = 2.1\n"
        "pkgdesc = Get-Regular-Expression-and-Print tool\n"
        "maintainer = Darwin Developers <d@x>\n"
        "license = unknown\n"
        "url = http://example.com/grep\n"
        "makedepends = build-base, libstreams-hdrs architecture-hdrs\n"
        "# comment\n"
        "\n"
        "vendor = ignored\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/pkginfo"), 0);
    CHECK_STR(p.package, "grep");
    CHECK_STR(p.version, "2.1");
    CHECK_STR(p.description, "Get-Regular-Expression-and-Print tool");
    CHECK_STR(p.maintainer, "Darwin Developers <d@x>");
    CHECK_STR(p.license, "unknown");
    CHECK_STR(p.url, "http://example.com/grep");
    CHECK_INT(p.has_build_depends, 1);
    CHECK_INT(p.build_depends.count, 3);
    CHECK_STR(p.build_depends.items[0], "build-base");
    CHECK_STR(p.build_depends.items[2], "architecture-hdrs");
    CHECK(p.architecture == 0 || p.architecture[0] == '\0');
    package_free(&p);
}

TEST(test_pkginfo_read_missing_file) {
    Package p;
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/no-such"), 1);
    package_free(&p);
}

TEST(test_pkginfo_read_missing_pkgname) {
    Package p;
    write_file("/tmp/rb-pkginfo-read/nopkg", "pkgver = 1\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/nopkg"), 2);
    package_free(&p);
}

TEST(test_pkginfo_read_invalid_arch) {
    Package p;
    write_file("/tmp/rb-pkginfo-read/badarch",
        "pkgname = bad\npkgver = 1\narch = m68k\n");
    package_init(&p);
    CHECK_INT(pkginfo_read(&p, "/tmp/rb-pkginfo-read/badarch"), 2);
    package_free(&p);
}
```

- [ ] **Step 2: Sync rbuild-1 and run guest `tests/test_pkginfo` to see FAIL** (link error: `pkginfo_read` undefined, and `p.license` / `p.url` are not fields)

- [ ] **Step 3: Add fields and `pkginfo_read`**

`package.h` — add after `maintainer`:

```c
    char *url;
    char *license;
```

`package_free`: also `free(p->url); free(p->license);`

`pkginfo.h`:

```c
/* 0 success, 1 missing file, 2 invalid (missing pkgname/pkgver or bad arch). */
int pkginfo_read(Package *p, const char *path);
```

`pkginfo.c` — include `architecture.h`. Implement:

```c
int pkginfo_read(Package *p, const char *path) {
    char *data;
    char *cursor;
    unsigned mask;
    data = /* slurp; return 1 if fopen fails */;
    cursor = data;
    while (*cursor) {
        char *line = cursor;
        char *nl = strchr(cursor, '\n');
        char *eq;
        char *key;
        char *val;
        if (nl) { *nl = '\0'; cursor = nl + 1; }
        else cursor += strlen(cursor);
        line = str_trim(line);
        if (line[0] == '\0' || line[0] == '#') continue;
        eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        key = str_trim(line);
        val = str_trim(eq + 1);
        if (strcmp(key, "pkgname") == 0) package_set(&p->package, val);
        else if (strcmp(key, "pkgver") == 0) package_set(&p->version, val);
        else if (strcmp(key, "arch") == 0) package_set(&p->architecture, val);
        else if (strcmp(key, "pkgdesc") == 0) package_set(&p->description, val);
        else if (strcmp(key, "url") == 0) package_set(&p->url, val);
        else if (strcmp(key, "maintainer") == 0) package_set(&p->maintainer, val);
        else if (strcmp(key, "license") == 0) package_set(&p->license, val);
        else if (strcmp(key, "origin") == 0) package_set(&p->source, val);
        else if (strcmp(key, "provides") == 0) package_set(&p->provides, val);
        else if (strcmp(key, "replaces") == 0) package_set(&p->replaces, val);
        else if (strcmp(key, "makedepends") == 0 ||
                 strcmp(key, "depend") == 0) {
            if (strcmp(key, "makedepends") == 0) {
                strlist_free(&p->build_depends);
                strlist_init(&p->build_depends);
                str_split_chars(val, " ,", &p->build_depends);
                p->has_build_depends = 1;
            }
            /* depend: accept (do not error); do not treat as makedepends */
        }
        /* unknown keys ignored */
    }
    free(data);
    if (!p->package) {
        fprintf(stderr, "error: package file does not contain 'pkgname' entry\n");
        return 2;
    }
    if (!p->version) {
        fprintf(stderr, "error: package file does not contain 'pkgver' entry\n");
        return 2;
    }
    if (architecture_parse(p->architecture, &mask) != 0) {
        fprintf(stderr, "rbuild: %s: invalid arch: '%s'\n",
                path, p->architecture);
        return 2;
    }
    return 0;
}
```

`depend` must **not** fill `build_depends`. Unknown keys including `vendor` are ignored.

Do not change `pkginfo_write` yet (still emits `builddepends`). Do not delete `package_parse`.

- [ ] **Step 4: Guest `tests/test_pkginfo` PASS**

- [ ] **Step 5: Commit**

```
git add src/rbuild-1/package.h src/rbuild-1/package.c src/rbuild-1/pkginfo.h src/rbuild-1/pkginfo.c src/rbuild-1/tests/test_pkginfo.c
git commit -m "rbuild: read Alpine apk/pkginfo into Package"
```

---

### Task 2: `pkginfo_write` emits Alpine keys plus makedepends

**Files:**
- Modify: `src/rbuild-1/pkginfo.c` (`pkginfo_write`)
- Modify: `src/rbuild-1/tests/test_pkginfo.c` (`test_pkginfo_write`)

- [ ] **Step 1: Change `test_pkginfo_write` to expect the new keys**

Replace the `builddepends` check with:

```c
    package_set(&p.license, "unknown");
    package_set(&p.url, "http://example.com/make");
    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest.PKGINFO"), 0);
    out = slurp("/tmp/rbtest.PKGINFO");
    CHECK(strstr(out, "makedepends = cc gnumake\n") != 0);
    CHECK(strstr(out, "license = unknown\n") != 0);
    CHECK(strstr(out, "url = http://example.com/make\n") != 0);
    CHECK(strstr(out, "builddepends =") == 0);
    CHECK(strstr(out, "pkgrel") == 0);
```

If `p.license` is unset, `pkginfo_write` must still emit `license = unknown`.

- [ ] **Step 2: Guest test FAIL** on missing `makedepends` / leftover `builddepends`

- [ ] **Step 3: Update `pkginfo_write`**

```c
    emit(f, "pkgname", p->package);
    emit(f, "pkgver", ver);
    emit(f, "arch", p->architecture);
    emit(f, "pkgdesc", p->description);
    emit(f, "url", p->url);
    emit(f, "maintainer", p->maintainer);
    emit(f, "license", p->license && p->license[0] ? p->license : "unknown");
    emit(f, "origin", p->source);
    emit(f, "provides", p->provides);
    emit(f, "replaces", p->replaces);
    if (p->has_build_depends) {
        /* join with spaces, emit makedepends */
    }
```

Do not emit `size`, `builddate`, `datahash`, `commit`, or `pkgrel`.

- [ ] **Step 4: Guest `tests/test_pkginfo` PASS**

- [ ] **Step 5: Commit**

```
git commit -m "rbuild: write makedepends, license, and url in .PKGINFO"
```

---

### Task 3: Scan `apk/pkginfo`, copy packages, drop Debian control parser

**Files:**
- Modify: `src/rbuild-1/package.h`, `src/rbuild-1/package.c`
- Modify: `src/rbuild-1/builder.c` (`builder_scan_dir`, `makecontrol` rename, `stage_ancillary_files`, clones)
- Modify: `src/rbuild-1/kernel.c`
- Modify: `src/rbuild-1/runner.c` (`variant_canon`)
- Modify: `src/rbuild-1/tests/test_package.c`
- Modify: `src/rbuild-1/Makefile` if `test_package_OBJS` needs `architecture.o` (already on master)

- [ ] **Step 1: Failing tests for scan + copy**

Add to `test_package.c` (include `pkginfo.h`; add `pkginfo.o` to `test_package_OBJS` if linking `pkginfo_read` — prefer testing `package_copy` here and scan in `test_builder.c`):

```c
TEST(test_package_copy) {
    Package src, dst;
    package_init(&src);
    package_set(&src.package, "foo");
    package_set(&src.version, "1");
    package_set(&src.url, "http://x");
    package_set(&src.license, "unknown");
    strlist_push(&src.build_depends, "build-base");
    src.has_build_depends = 1;
    package_init(&dst);
    CHECK_INT(package_copy(&dst, &src), 0);
    CHECK_STR(dst.package, "foo");
    CHECK_STR(dst.url, "http://x");
    CHECK_STR(dst.license, "unknown");
    CHECK_INT(dst.build_depends.count, 1);
    package_set(&src.package, "bar");
    CHECK_STR(dst.package, "foo");
    package_free(&src);
    package_free(&dst);
}
```

Delete `test_parse_basic`, `test_parse_continuation`, and `test_unparse` from `test_package.c` (Debian parser is gone). Keep canon-name tests. Do not link `pkginfo.o` into `test_package`; `pkginfo_read` coverage stays in `test_pkginfo.c`.

Add a builder scan test (in `test_builder.c` or a small new case): directory with `apk/pkginfo` missing `pkgname` must fail scan (return 1), not synthesize.

- [ ] **Step 2: Guest tests FAIL** (`package_copy` missing; scan still opens `dpkg/control`)

- [ ] **Step 3: Implement**

`package.h`:

```c
int package_copy(Package *dst, const Package *src);
```

`package_copy`: `package_free(dst); package_init(dst);` then `package_set` every string field including `url`/`license`/`revision`/`package_revision`; copy `build_depends` items; copy `has_build_depends`. Return 0.

Delete `package_parse` and `package_unparse`.

`builder.c`:
- Rename `makecontrol` → `makepkginfo` (same defaults).
- `builder_scan_dir`: `pkginfo_path = str_cats(source, "/apk/pkginfo", NULL)`; `rc = pkginfo_read(pkg, pkginfo_path)`.
  - `rc == 2` → return 1 (invalid).
  - `rc == 1` (missing file) → `makepkginfo(pkg, pname)`.
  - `rc == 0` → apply defaults for missing `description`/`maintainer`/`architecture` (`DEFAULT_DESC`, `DEFAULT_MAINT`, `ARCH`) **without** treating missing required keys as synthesis (already handled by `pkginfo_read`).
- Still `package_set(&pkg->source, pbase)` after read (origin is directory basename).
- Replace every `package_unparse`/`package_parse` clone with `package_copy`.
- `stage_ancillary_files`: names become `.pre-install`, `.post-install`, `.pre-deinstall`, `.post-deinstall`; source dir `apk/` not `dpkg/`; dest is `DSTROOT/<name>` (leading dot). Drop `conffiles`. Mode 755 for scripts.

`kernel.c` `has_control`: join `apk/pkginfo` instead of `dpkg/control`. Rename the helper to `has_pkginfo` if it is clearer; call sites must match.

`runner.c` `variant_canon`: `package_copy(&variant, pkg)`.

- [ ] **Step 4: Guest tests for `test_package` / `test_builder` / `test_kernel` / `test_runner` will still FAIL on fixtures that write `dpkg/control` — that is Task 4.** For this task, keep those fixtures compiling by also teaching a **temporary** dual path? **No.** Spec is hard cutover. Task 3 and Task 4 must land so `make test` can pass: **do Task 3 implementation and immediately continue to Task 4 in the same work if tests cannot pass otherwise.** Prefer two commits: (3) library/scan/copy, (4) fixtures. If commit 3 cannot compile tests, include the fixture helper in Task 3 only as needed for compile, and finish fixture content in Task 4.

Practical split: Task 3 changes C code + `test_package.c` parse tests + `package_copy` test. Task 4 rewrites remaining fixtures. After Task 3, `test_package` and `test_pkginfo` PASS; `test_builder`/`test_runner`/`test_kernel`/`bootstrap-*.sh` FAIL until Task 4.

- [ ] **Step 5: Commit Task 3**

```
git commit -m "rbuild: scan apk/pkginfo and drop dpkg control parsing"
```

---

### Task 4: Rewrite rbuild test fixtures to `apk/pkginfo`

**Files:**
- Modify: `src/rbuild-1/tests/test_builder.c`
- Modify: `src/rbuild-1/tests/test_runner.c`
- Modify: `src/rbuild-1/tests/test_kernel.c`
- Modify: `src/rbuild-1/tests/bootstrap-resume.sh`
- Modify: `src/rbuild-1/tests/bootstrap-closure.sh`
- Modify: `src/rbuild-1/tests/bootstrap-runtime-manifest.sh` if it writes `dpkg/control`
- Modify: `src/rbuild-1/tests/trace/fixtures/pkgsrc/foo-1.0/dpkg/control` → `apk/pkginfo`
- Modify: `src/rbuild-1/tests/trace/fixtures/pkgsrc/thin-1.0/dpkg/control` → `apk/pkginfo`
- Modify: `src/rbuild-1/tests/trace/run.sh` if it greps `dpkg/control`

- [ ] **Step 1: Add a small C helper used in tests** (or repeat mkdir+write):

Every `fopen(".../dpkg/control")` becomes mkdir `.../apk` and write `.../apk/pkginfo` with:

```
pkgname = <Package>
pkgver = <Version>
pkgdesc = <Description>
maintainer = <Maintainer>
license = unknown
makedepends = <Build-Depends with commas OK>
```

If the old control had `Architecture: i386`, add `arch = i386`.

`test_kernel.c` `write_rel(".../dpkg/control", ...)` → `write_rel(".../apk/pkginfo", "pkgname = PExpert\npkgver = 0\n")` (scan requires pkgver when file exists; synthesizer is only for missing file). Kernel discovery only checks file existence; still write a valid pkginfo so later scans would work.

- [ ] **Step 2: `bootstrap-resume.sh`**

Replace the control heredoc with `apk/pkginfo`. Change the assertion that source control is unchanged from:

```
grep '^Architecture: universal-apple-rhapsody$' "$src/dpkg/control"
```

to grep `apk/pkginfo` for the original `arch` line (or absence of arch if the fixture omitted it). Do not require rbuild to rewrite the source file.

Bad-package cases: write `apk/pkginfo` with `arch = m68k` / missing pkgname as appropriate.

- [ ] **Step 3: `bootstrap-closure.sh`**

```
pkginfo="$src_dir/$source/apk/pkginfo"
if test ! -f "$pkginfo"; then
    say_fail "manifest source has no apk/pkginfo: $source"
    continue
fi
package=`awk -F ' = ' '$1 == "pkgname" { print $2; exit }' "$pkginfo"`
```

Temporary closure sources (`header-src`, `base-src`, `bad-source`) write `apk/pkginfo` not `dpkg/control`. Invalid arch fixture: `arch = m68k`.

Until Task 5 converts production packages, **guest `bootstrap-closure.sh` will FAIL** for every BootstrapManifest row (still `dpkg/control` on disk). That is expected; Task 5 is next. After Task 4, unit tests and `bootstrap-resume.sh` should PASS; document closure FAIL until convert.

- [ ] **Step 4: Guest `make test`** — expect unit tests + resume PASS; closure FAIL on missing `apk/pkginfo` in `/build/src` projects. If running only unit binaries: all PASS.

- [ ] **Step 5: Commit**

```
git commit -m "rbuild: use apk/pkginfo in tests"
```

---

### Task 5: Converter and bulk tree rewrite

**Files:**
- Create: `tools/convert-dpkg-control-to-pkginfo.py`
- Create: `src/**/apk/pkginfo` (156 production + 2 already done in Task 4 fixtures)
- Delete: every `src/**/dpkg/` including `files-5` scripts after mapping
- Create: `src/files-5/apk/.pre-install`, `src/files-5/apk/.post-install`

- [ ] **Step 1: Write the converter**

`tools/convert-dpkg-control-to-pkginfo.py` (Python 3, stdlib only):

- Walk `src/` for `dpkg/control` (skip nothing under `src/`).
- Parse Debian control: `Key: value` plus continuation lines (leading space) folded with a single space (not `"\n "`).
- If `apk/pkginfo` already exists → abort that package, non-zero exit (Task 4 fixtures already have pkginfo **and** may still have empty dpkg dirs — if control is gone, skip; if both exist, abort). After Task 4 the two trace fixtures have pkginfo and no control. Production still has only control.
- Map fields per spec. Always write `license = unknown`. Omit `arch` if control had no Architecture. Omit `url` if no URL. Flatten Description. `makedepends` from Build-Depends (preserve tokens; join with spaces).
- Do not write `origin` / `Source`.
- Map scripts: `preinst`→`apk/.pre-install`, `postinst`→`apk/.post-install`, `prerm`→`apk/.pre-deinstall`, `postrm`→`apk/.post-deinstall`. Copy bytes, keep executable bit if present.
- Do **not** copy `conffiles`.
- Write `apk/pkginfo` then delete the `dpkg/` directory (after successful write).
- Print counts: converted, scripts moved, remaining `dpkg/control` (must be 0).
- Exit 2 if any control could not be mapped (missing Package or Version).

Refuse `Vendor` mapping (dropped). Unknown extra keys dropped.

- [ ] **Step 2: Run from repo root**

```
py -3 tools/convert-dpkg-control-to-pkginfo.py
```

Expected: converted=156 (or 158 if fixtures still had control), remaining control=0, `src/files-5/apk/.pre-install` and `.post-install` exist, no `src/files-5/dpkg/`.

- [ ] **Step 3: Verify grep**

```
git grep -l dpkg/control -- src
```

Expected: no production hits. Tests/comments should not open `dpkg/control`.

- [ ] **Step 4: Commit**

```
git add tools/convert-dpkg-control-to-pkginfo.py src
git commit -m "rbuild: convert dpkg/control trees to apk/pkginfo"
```

Do not keep `dpkg/` “just in case.”

---

### Task 6: Docs and guest verification

**Files:**
- Modify: `src/rbuild-1/README.md` — metadata is `apk/pkginfo`; `.PKGINFO` uses `makedepends` not `builddepends`; source files are not rewritten; Architecture → `arch`.
- Modify: `docs/build/rbuild-universal.md` only if it still says `dpkg/control` or `builddepends` as current policy (leave historical Task 9 tables).

- [ ] **Step 1: Update README notes** that currently say:

```
- `.PKGINFO` carries a custom `builddepends` field (apk ignores unknown keys).
```

to:

```
- Source metadata is `apk/pkginfo`. Packaged `.PKGINFO` uses the same keys
  (`makedepends`, `license`, `url`, …). apk ignores unknown keys.
```

Also change “without rewriting source control files” to “without rewriting `apk/pkginfo`”.

- [ ] **Step 2: Sync worktree to guest** — `apk/pkginfo` lives under many `src/` projects, so:

```
powershell -NoProfile -File .\vm\sync-src.ps1 -All
powershell -NoProfile -File .\vm\build-src.ps1 -Rbuild
```

`-All` is required so `bootstrap-closure.sh` sees converted packages under `/build/src`.

Expected: `ALL TESTS PASSED`, `bootstrap-resume: PASS`, `bootstrap-closure: PASS`, `bootstrap-runtime-manifest: PASS` if that target exists on master, `build-src: complete (rbuild)`, exit 0.

- [ ] **Step 3: Commit README** (and any current-policy doc sentence)

```
git commit -m "rbuild: document apk/pkginfo as package metadata"
```

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| `apk/pkginfo` only reader | 3 |
| Synthesize if missing file | 3 |
| Fail if file missing pkgname/pkgver | 1, 3 |
| Invalid arch fails | 1 |
| Alpine keys + makedepends | 1–2 |
| No pkgrel | 2 |
| license=unknown | 2, 5 |
| url from URL | 5 |
| Vendor/Section/Priority/Conflicts dropped | 5 |
| origin = directory basename | 3 |
| Do not rewrite source on arch resolve | 3 (unchanged resolve) |
| files-5 scripts + drop conffiles | 3, 5 |
| kernel discovery | 3 |
| Converter refuse overwrite / unmappable | 5 |
| Old APKs with builddepends still consumed | no apk.c change |
| Test fixtures | 4 |
| 156 converted, 0 control | 5 |
| Guest Rbuild, no repo wipe | 6 |
| Branch from master | worktree |

## Out of scope

- Live `/build/repo` rebuild
- Real SPDX licenses
- `apk/vendor` tarballs
- Host `test-build-src.ps1` drvEIDE assertion
- `pkgrel` / Alpine combined version
