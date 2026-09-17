# APK architecture filename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish and look up repository APKs as `{pkgname}-{pkgver}-{shortarch}.apk`, rename live `/build/repo` in place, and stop treating old `{pkgname}-{pkgver}.apk` names as hits.

**Architecture:** Add a filename token next to the existing architecture labels (`universal` / `i386` / `ppc`). `package_canon_name` appends that token. Lookup tries the thin name then the universal name. `apk_use_arch` refuses a file whose basename token does not match `.PKGINFO` `arch`. A one-shot guest script renames `/build/repo`; no `rbuild` subcommand.

**Tech Stack:** C89 rbuild, existing `TEST()` macros, guest `make test`, Bourne + PowerShell one-shot rename, gzip/tr `.PKGINFO` inspect.

**Approved design:** `docs/superpowers/specs/2026-09-16-rbuild-apk-arch-filename-design.md`.

## Global Constraints

- Filename stem is `{pkgname}-{pkgver}-{shortarch}`; publish still appends `.apk`.
- Short tokens: `universal`, `i386`, `ppc`. i486 Mach-O still uses `i386`.
- `.PKGINFO` keeps full `*-apple-rhapsody` labels. Do not change APK inner layout.
- Lookup uses the new filename only. Old `csu-23.1-1.apk` is not a hit.
- Thin consumer: try `{name}-{ver}-{cpu}.apk`, then `{name}-{ver}-universal.apk`.
- Universal consumer: only `{name}-{ver}-universal.apk`.
- Filename token must match the `.PKGINFO` mapped token (refuse `*-ppc.apk` whose PKGINFO is universal).
- Missing Architecture on a Package follows `architecture_parse` (NULL means universal) so naming never omits the token. Empty or unknown Architecture fails `package_canon_name` (returns NULL).
- No `rbuild` subcommand for rename. One-shot script over `/build/repo` only. Skip `*.apk.invalid`. Abort if the destination exists. Do not rebuild bootstrap.
- Implement on branch `rbuild-universal-bootstrap` in `D:\RhapsodiOS\.worktrees\rbuild-universal-bootstrap`.
- C tests run on the Rhapsody guest after `vm\sync-src.ps1 -Path rbuild-1`. Host `test-build-src.ps1` still has the pre-existing drvEIDE failure; do not use it as this feature’s gate.

---

## File responsibilities

| Files | Responsibility |
| --- | --- |
| `src/rbuild-1/architecture.h`, `architecture.c`, `tests/test_architecture.c` | Filename token and path-suffix check |
| `src/rbuild-1/package.c`, `tests/test_package.c`, `Makefile` | `package_canon_name` includes the token |
| `src/rbuild-1/builder.c`, `apk.c`, `tests/test_builder.c`, `tests/test_apk.c` | Lookup covering names; PKGINFO/token match |
| `src/rbuild-1/tests/bootstrap-resume.sh`, `bootstrap-closure.sh`, `test_runner.c`, `trace/run.sh` | Fixture APK names |
| `vm/rename-repo-apk-arch.sh`, `vm/rename-repo-apk-arch.ps1` | In-place `/build/repo` rename |
| `src/rbuild-1/README.md`, `docs/build/rbuild-universal.md` | Document the new stem |

---

### Task 1: Filename token API

**Files:**
- Modify: `src/rbuild-1/architecture.h`
- Modify: `src/rbuild-1/architecture.c`
- Modify: `src/rbuild-1/tests/test_architecture.c`

**Interfaces:**
- Consumes: existing `RB_ARCH_I386` / `RB_ARCH_PPC` / `RB_ARCH_UNIVERSAL`
- Produces: `const char *architecture_filename_token(unsigned mask);` returns `"i386"`, `"ppc"`, `"universal"`, or NULL. `int architecture_path_has_token(const char *path, unsigned mask);` returns 1 if the basename ends with `-{token}.apk`.

- [ ] **Step 1: Write the failing tests**

Add to `src/rbuild-1/tests/test_architecture.c` (include `string.h` if not already):

```c
TEST(test_filename_token) {
    CHECK_STR(architecture_filename_token(RB_ARCH_I386), "i386");
    CHECK_STR(architecture_filename_token(RB_ARCH_PPC), "ppc");
    CHECK_STR(architecture_filename_token(RB_ARCH_UNIVERSAL), "universal");
    CHECK(architecture_filename_token(0) == 0);
    CHECK(architecture_filename_token(4) == 0);
}

TEST(test_path_has_token) {
    CHECK_INT(architecture_path_has_token("csu-23.1-1-universal.apk",
                                          RB_ARCH_UNIVERSAL), 1);
    CHECK_INT(architecture_path_has_token(
        "/build/repo/drvpcfloppy-5-i386.apk", RB_ARCH_I386), 1);
    CHECK_INT(architecture_path_has_token("kernel-154.5.1-7-ppc.apk",
                                          RB_ARCH_PPC), 1);
    CHECK_INT(architecture_path_has_token("csu-23.1-1.apk",
                                          RB_ARCH_UNIVERSAL), 0);
    CHECK_INT(architecture_path_has_token("csu-23.1-1-ppc.apk",
                                          RB_ARCH_UNIVERSAL), 0);
    CHECK_INT(architecture_path_has_token(0, RB_ARCH_UNIVERSAL), 0);
}
```

Register both in `run_all`.

- [ ] **Step 2: Run tests to verify they fail**

Sync and on the guest:

```
cd /build/src/rbuild-1 && make tests/test_architecture && ./tests/test_architecture
```

Expected: compile error `architecture_filename_token` / `architecture_path_has_token` undeclared, or link failure.

- [ ] **Step 3: Implement the token API**

In `architecture.h` after `architecture_cflags`:

```c
const char *architecture_filename_token(unsigned mask);
int architecture_path_has_token(const char *path, unsigned mask);
```

In `architecture.c`:

```c
const char *architecture_filename_token(unsigned mask) {
    switch (mask) {
    case RB_ARCH_I386: return "i386";
    case RB_ARCH_PPC: return "ppc";
    case RB_ARCH_UNIVERSAL: return "universal";
    }
    return 0;
}

int architecture_path_has_token(const char *path, unsigned mask) {
    const char *token = architecture_filename_token(mask);
    const char *slash;
    const char *base;
    size_t base_len;
    size_t token_len;
    size_t need;
    if (path == 0 || token == 0) return 0;
    slash = strrchr(path, '/');
    base = slash ? slash + 1 : path;
    base_len = strlen(base);
    token_len = strlen(token);
    need = token_len + 5; /* - + token + .apk */
    if (base_len < need) return 0;
    if (base[base_len - need] != '-') return 0;
    if (strncmp(base + base_len - need + 1, token, token_len) != 0) return 0;
    return strcmp(base + base_len - 4, ".apk") == 0;
}
```

Do not treat short token `"universal"` as a parse label. `architecture_parse("universal")` stays invalid.

- [ ] **Step 4: Run tests to verify they pass**

```
cd /build/src/rbuild-1 && make tests/test_architecture && ./tests/test_architecture
```

Expected: silent pass / `test_architecture` exit 0.

- [ ] **Step 5: Commit**

```
git add src/rbuild-1/architecture.h src/rbuild-1/architecture.c src/rbuild-1/tests/test_architecture.c
git commit -m "rbuild: add APK filename architecture tokens"
```

---

### Task 2: Canon name includes the token

**Files:**
- Modify: `src/rbuild-1/package.c`
- Modify: `src/rbuild-1/package.h` (comment only if present)
- Modify: `src/rbuild-1/tests/test_package.c`
- Modify: `src/rbuild-1/Makefile` (`test_package_OBJS`)

**Interfaces:**
- Consumes: `architecture_parse`, `architecture_filename_token` from Task 1
- Produces: `char *package_canon_name(const Package *p)` returns `{pkgname}-{pkgver}-{token}` or NULL on empty/unknown Architecture. NULL Architecture still maps to `universal`.

- [ ] **Step 1: Write the failing tests**

Replace `test_canon_names` in `src/rbuild-1/tests/test_package.c` and add `#include "architecture.h"`:

```c
TEST(test_canon_names) {
    Package p;
    char *v, *n;
    package_init(&p);
    package_parse(&p, "Package: foo\nVersion: 1.2-3\n");
    package_set(&p.architecture, "universal-apple-rhapsody");
    v = package_canon_version(&p);
    n = package_canon_name(&p);
    CHECK_STR(v, "1.2-3");
    CHECK_STR(n, "foo-1.2-3-universal");
    free(v); free(n);

    package_set(&p.architecture, "i386-apple-rhapsody");
    n = package_canon_name(&p);
    CHECK_STR(n, "foo-1.2-3-i386");
    free(n);

    package_set(&p.architecture, "ppc-apple-rhapsody");
    n = package_canon_name(&p);
    CHECK_STR(n, "foo-1.2-3-ppc");
    free(n);

    package_set(&p.architecture, 0);
    n = package_canon_name(&p);
    CHECK_STR(n, "foo-1.2-3-universal");
    free(n);

    package_set(&p.architecture, "");
    n = package_canon_name(&p);
    CHECK(n == 0);

    package_set(&p.architecture, "m68k");
    n = package_canon_name(&p);
    CHECK(n == 0);
    package_free(&p);
}
```

Add `architecture.o` to `test_package_OBJS` in `src/rbuild-1/Makefile`:

```
test_package_OBJS = strutil.o package.o architecture.o
```

- [ ] **Step 2: Run test to verify it fails**

```
cd /build/src/rbuild-1 && make tests/test_package && ./tests/test_package
```

Expected: FAIL on `CHECK_STR(n, "foo-1.2-3-universal")` because current stem is `foo-1.2-3`.

- [ ] **Step 3: Implement canon name**

In `package.c` add `#include "architecture.h"` and replace `package_canon_name`:

```c
/* apk stem: "<pkgname>-<pkgver>-<shortarch>". */
char *package_canon_name(const Package *p) {
    unsigned mask = 0;
    const char *token;
    char *ver;
    char *out;
    if (p->architecture && p->architecture[0] == '\0') {
        fprintf(stderr,
            "rbuild: missing or unsupported architecture for package \"%s\"\n",
            p->package ? p->package : "");
        return 0;
    }
    if (architecture_parse(p->architecture, &mask) != 0 ||
        (token = architecture_filename_token(mask)) == 0) {
        fprintf(stderr,
            "rbuild: missing or unsupported architecture for package \"%s\"\n",
            p->package ? p->package : "");
        return 0;
    }
    ver = package_canon_version(p);
    out = str_cats(p->package ? p->package : "", "-", ver, "-", token,
                   (char *)0);
    free(ver);
    return out;
}
```

Callers already `free(canon)`. If a caller would `str_cats(..., canon, ".apk")` on NULL, they must check NULL in Task 3. This task only changes `package_canon_name` and its unit test.

- [ ] **Step 4: Run test to verify it passes**

```
cd /build/src/rbuild-1 && make tests/test_package && ./tests/test_package
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```
git add src/rbuild-1/package.c src/rbuild-1/tests/test_package.c src/rbuild-1/Makefile
git commit -m "rbuild: put short architecture token in APK canon names"
```

---

### Task 3: Lookup covering names and PKGINFO/token match

**Files:**
- Modify: `src/rbuild-1/builder.c` (`find_arch_package`, already-exists path around the `names[i]-version.apk` loop, `package_canon_name` NULL checks at publish)
- Modify: `src/rbuild-1/apk.c` (`use_artifact`)
- Modify: `src/rbuild-1/tests/test_builder.c`
- Modify: `src/rbuild-1/tests/test_apk.c` (`test_architecture_use` and any `apk_use_arch` path whose basename lacks `-{token}.apk`)

**Interfaces:**
- Consumes: `architecture_filename_token`, `architecture_path_has_token`, `package_canon_name`
- Produces: `find_arch_package` looks up `{name}-{ver}-{token}.apk` (thin then universal). `use_artifact` fails unless `architecture_path_has_token(path, declared)`.

- [ ] **Step 1: Write the failing lookup tests**

In `test_builder.c`, change `test_cache_accepts_covering_architecture` so the universal file is `cover-1-universal.apk` and the thin file is `thin-1-ppc.apk`. Assert:

- `builder_exists` for package `cover` version `1` arch `ppc-apple-rhapsody` finds `cover-1-universal.apk`.
- `builder_exists` for `universal-apple-rhapsody` finds `cover-1-universal.apk`.
- `builder_exists` does not find an old-named `cover-1.apk` planted next to it.
- `builder_cache_status` on `cover-1-ppc.apk` whose PKGINFO is `universal-apple-rhapsody` fails (token mismatch).

Also update `test_match_pkgfile` to keep matching `foo-1.0-universal.apk` for name `foo`:

```c
CHECK_INT(builder_match_pkgfile("foo-1.0-universal.apk", "foo"), 1);
CHECK_INT(builder_match_pkgfile("foo-1.0.apk", "foo"), 1);
```

In `test_apk.c` `test_architecture_use`, write APKs as `test-universal.apk` / `test-i386.apk` / `test-ppc.apk` matching each PKGINFO token (PKGINFO `arch = i386` is the short label `architecture_parse` already accepts, token `i386`). Add one case: `test-ppc.apk` with `arch = universal-apple-rhapsody` → `apk_use_arch` nonzero.

Update `cache_fixture` in `test_builder.c` from:

```c
sprintf(path,"%s/%s-%s.apk",repo,name,version);
```

to append the token from `architecture_filename_token` after `architecture_parse(arch, &mask)`.

- [ ] **Step 2: Run the focused tests to verify they fail**

```
cd /build/src/rbuild-1 && make tests/test_builder tests/test_apk && ./tests/test_builder
```

Expected: covering / exists checks fail because `find_arch_package` still looks for `name-version.apk`.

- [ ] **Step 3: Implement lookup and token match**

Replace `find_arch_package` in `builder.c`:

```c
static char *apk_name_for_mask(const char *name, const char *version,
                               unsigned mask) {
    const char *token = architecture_filename_token(mask);
    if (!token) return 0;
    return str_cats(name, "-", version, "-", token, ".apk", (char *)0);
}

static char *open_arch_package(const char *dir, const char *filename,
                               const char *name, const char *version,
                               unsigned required, int dependency,
                               const Toolchain *tc) {
    char *path = path_join(dir, filename);
    if (!exec_dry_run && apk_use_arch(path, 0, tc, name, version,
            required, str_has_suffix(name, "-obj"), dependency) == 0)
        return path;
    if (exec_dry_run) printf("validate APK %s for %s\n", path,
                            architecture_label(required));
    free(path);
    return 0;
}

static char *find_arch_package(const char *dir, const char *name,
                               const char *version, unsigned required,
                               int dependency, const Toolchain *tc) {
    unsigned try_mask[2];
    unsigned tries = 0;
    unsigned i;
    if (version) {
        if (required == RB_ARCH_I386 || required == RB_ARCH_PPC) {
            try_mask[tries++] = required;
            try_mask[tries++] = RB_ARCH_UNIVERSAL;
        } else {
            try_mask[tries++] = RB_ARCH_UNIVERSAL;
        }
        for (i = 0; i < tries; i++) {
            char *exact = apk_name_for_mask(name, version, try_mask[i]);
            char *found;
            struct stat st;
            if (!exact) continue;
            found = path_join(dir, exact);
            free(exact);
            if (stat(found, &st) != 0) { free(found); continue; }
            {
                char *ok = open_arch_package(dir,
                    (strrchr(found, '/') ? strrchr(found, '/') + 1 : found),
                    name, version, required, dependency, tc);
                free(found);
                if (ok) return ok;
            }
        }
        return 0;
    }
    /* version == 0: scan, new names only via apk_use_arch token check */
    {
        DIR *d = opendir(dir);
        struct dirent *de;
        char *found = 0;
        if (!d) return 0;
        while ((de = readdir(d)) != 0) {
            if (!builder_match_pkgfile(de->d_name, name)) continue;
            found = open_arch_package(dir, de->d_name, name, version,
                                      required, dependency, tc);
            if (found) break;
        }
        closedir(d);
        return found;
    }
}
```

Simplify `open_arch_package` if the basename dance is clumsy: `path_join` then `apk_use_arch` on that path, return path on success.

In the already-exists loop (`builder.c` ~1628), replace

```c
char *path = str_cats(dstdir, "/", names[i], "-", version, ".apk", (char *)0);
```

with:

```c
const char *token = architecture_filename_token(opt->effective_arch);
char *path;
if (token == 0) { rc = 1; free(version); break; }
path = str_cats(dstdir, "/", names[i], "-", version, "-", token, ".apk",
                (char *)0);
```

Where `package_canon_name` is used to build `apk_path`, if `canon == 0` set `rc = 1` and skip `str_cats`.

In `use_artifact` (`apk.c`), after `declared` is parsed successfully, add:

```c
if (!result && required &&
    !architecture_path_has_token(path, declared))
    result = 1;
```

Place this next to the existing `required && (... architecture_parse ...)` block so a token mismatch fails before `tar_pipeline`.

- [ ] **Step 4: Run focused tests**

```
cd /build/src/rbuild-1 && make tests/test_builder tests/test_apk tests/test_package tests/test_architecture && ./tests/test_architecture && ./tests/test_package && ./tests/test_apk && ./tests/test_builder
```

Expected: those four binaries exit 0. Full `make test` may still fail on `bootstrap-resume.sh` until Task 4.

- [ ] **Step 5: Commit**

```
git add src/rbuild-1/builder.c src/rbuild-1/apk.c src/rbuild-1/tests/test_builder.c src/rbuild-1/tests/test_apk.c
git commit -m "rbuild: look up APKs by short architecture filename"
```

---

### Task 4: Remaining test fixtures use the new stem

**Files:**
- Modify: `src/rbuild-1/tests/bootstrap-resume.sh`
- Modify: `src/rbuild-1/tests/bootstrap-closure.sh`
- Modify: `src/rbuild-1/tests/test_runner.c`
- Modify: `src/rbuild-1/tests/trace/run.sh` if it plants `*-1.0.apk` that rbuild must find
- Modify: any leftover `sprintf(..., "%s-%s.apk"` in `src/rbuild-1/tests/` that represents a repo APK rbuild will open

**Interfaces:**
- Consumes: Task 2 stems and Task 3 lookup
- Produces: `make test` and `make trace-test` PASS on the guest

- [ ] **Step 1: Update fixture names (this is the regression: current scripts still write old names)**

In `bootstrap-resume.sh` the control Architecture is `universal-apple-rhapsody`. Replace repo artifact names:

- `foo-1.0.apk` → `foo-1.0-universal.apk`
- `foo-hdrs-1.0.apk` → `foo-hdrs-1.0-universal.apk`
- `foo-obj-1.0.apk` → `foo-obj-1.0-universal.apk`
- `must build foo-1.0.apk` → `must build foo-1.0-universal.apk`
- `must build later-1.0.apk` → `must build later-1.0-universal.apk`
- `must build rt-1.0.apk` → `must build rt-1.0-universal.apk`

For `make_wrong_apk` plants, the **filename token must match that fixture’s PKGINFO arch**, not the consumer:

- wrong universal metadata on the foo cache path → `foo-1.0-universal.apk`
- ppc PKGINFO → `*-ppc.apk`

Do not leave an old `foo-1.0.apk` as the cache path rbuild will look up.

In `bootstrap-closure.sh`:

- `sample-header-hdrs-1.apk` → `sample-header-hdrs-1-universal.apk` (or `-ppc` if that fixture’s arch is ppc — read `make_fixture_apk` and match PKGINFO)
- `sample-base-1.apk` → `sample-base-1-universal.apk`
- `must build sample-base-1.apk` → `must build sample-base-1-universal.apk`

In `test_runner.c` replay artifact `foo-hdrs-1.0.apk` → `foo-hdrs-1.0-universal.apk` if that file is an rbuild cache path.

In `test_builder.c` remaining paths (`collision-1.apk`, `companions-1.apk`, `gnumake-3.79.apk` for `scan_dir_for` only): `builder_resolve_dependency` / `builder_match_pkgfile` do not require a token. Leave scan-only `touch` files unless `apk_use_arch` opens them. Any `builder_cache_status` / `builder_exists` / publish dest must use the token.

- [ ] **Step 2: Run `make test` on the guest (expect FAIL until names match)**

```
cd /build/src/rbuild-1 && make test
```

Expected before this task’s edits: `bootstrap-resume` cannot find `foo-1.0-universal.apk`. After the replacements: `ALL TESTS PASSED`, `bootstrap-resume: PASS`, `bootstrap-runtime-manifest: PASS`.

- [ ] **Step 3: Run `make trace-test`**

```
cd /build/src/rbuild-1 && make trace-test
```

Expected: `TRACE MATCH: universal project flags identical; thin policy and dry-run verified`

If `trace/run.sh` seeds `$seed/$d-1.0.apk` and rbuild lookup now requires a token, rename those seeds to `$d-1.0-universal.apk` (or the arch that fixture declares).

- [ ] **Step 4: Commit**

```
git add src/rbuild-1/tests/bootstrap-resume.sh src/rbuild-1/tests/bootstrap-closure.sh src/rbuild-1/tests/test_runner.c src/rbuild-1/tests/trace/run.sh
git commit -m "rbuild: update tests for architecture APK filenames"
```

Include every test file actually changed.

---

### Task 5: One-shot `/build/repo` rename and docs

**Files:**
- Create: `vm/rename-repo-apk-arch.sh`
- Create: `vm/rename-repo-apk-arch.ps1`
- Modify: `src/rbuild-1/README.md` (package name sentence)
- Modify: `docs/build/rbuild-universal.md` (one short note under live evidence that current `/build/repo` names are `{pkg}-{ver}-{token}.apk` after the rename)

**Interfaces:**
- Consumes: Task 1 token mapping (duplicated in the shell case, not by linking rbuild)
- Produces: guest `/build/repo/*.apk` renamed; rbuild can resolve them

- [ ] **Step 1: Add the guest rename script**

`vm/rename-repo-apk-arch.sh`:

```sh
#!/bin/sh
# Rename /build/repo APKs from {name}-{ver}.apk to {name}-{ver}-{token}.apk.
# No rebuild. Abort if the destination exists. Skip *.apk.invalid.
set -e
repo=${1-/build/repo}
if test ! -d "$repo"; then
    echo "rename-repo-apk-arch: missing directory $repo" >&2
    exit 1
fi
n=0
for f in "$repo"/*.apk; do
    test -f "$f" || continue
    case "$f" in
        *.apk.invalid) continue ;;
    esac
    base=`basename "$f"`
    case "$base" in
        *-universal.apk|*-i386.apk|*-ppc.apk) continue ;;
    esac
    arch=`gzip -dc "$f" | tr '\000' '\012' | grep '^arch =' | sed -n '1p'`
    tok=
    case "$arch" in
        *universal-apple-rhapsody*) tok=universal ;;
        *i386-apple-rhapsody*) tok=i386 ;;
        *ppc-apple-rhapsody*) tok=ppc ;;
        *) echo "rename-repo-apk-arch: unknown arch in $base [$arch]" >&2; exit 1 ;;
    esac
    dest="$repo/`echo "$base" | sed 's/\.apk$//' `-$tok.apk"
    if test -e "$dest"; then
        echo "rename-repo-apk-arch: collision $dest" >&2
        exit 1
    fi
    mv "$f" "$dest"
    echo "renamed $base -> `basename "$dest"`"
    n=`expr "$n" + 1`
done
echo "rename-repo-apk-arch: renamed $n apks in $repo"
```

`vm/rename-repo-apk-arch.ps1` loads `vm/rhap-remote.ps1`, uploads or inlines that script, and runs it on the guest with `/build/repo`. Do not wipe `/build/repo`. Do not pass other directories.

- [ ] **Step 2: Document the stem**

In `src/rbuild-1/README.md` replace the sentence about producing `<name>.apk` with: published files are `<pkgname>-<pkgver>-<universal|i386|ppc>.apk`; architecture in `.PKGINFO` remains `*-apple-rhapsody`.

In `docs/build/rbuild-universal.md` add one paragraph that after this rename, `/build/repo` uses that stem (example `csu-23.1-1-universal.apk`) and old names are not looked up.

- [ ] **Step 3: Run the rename on the live guest**

From the worktree:

```
powershell -NoProfile -File vm\rename-repo-apk-arch.ps1
```

Expected: `rename-repo-apk-arch: renamed 68 apks` (or 68 minus any already-suffixed). `ls /build/repo/*.apk` shows `*-universal.apk` only. Zero leftover unsuffixed `csu-23.1-1.apk`. `*.apk.invalid` untouched.

Spot-check:

```
gzip -dc /build/repo/csu-23.1-1-universal.apk | tr '\000' '\012' | grep '^arch ='
```

Expected: `arch = universal-apple-rhapsody`.

- [ ] **Step 4: Re-run guest rbuild tests after sync**

```
powershell -NoProfile -File vm\sync-src.ps1 -Path rbuild-1
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
```

Expected: `ALL TESTS PASSED`, `build-src: complete (rbuild)`.

Optional proof that lookup works against the renamed repo (do not rebuild bootstrap): one `rbuild buildpackage` dry-run or `builder` exists-style inspect is enough; do not run `rbuild kernel`.

- [ ] **Step 5: Commit**

```
git add vm/rename-repo-apk-arch.sh vm/rename-repo-apk-arch.ps1 src/rbuild-1/README.md docs/build/rbuild-universal.md
git commit -m "rbuild: rename live repo APKs to include architecture"
```

If `docs/build/rbuild-universal.md` also has unrelated uncommitted PKGINFO notes, include only the new filename paragraph in this commit (keep the PKGINFO extract note if it is still uncommitted and still accurate).

---

## Spec coverage

| Spec requirement | Task |
| --- | --- |
| `{pkgname}-{pkgver}-{shortarch}.apk` | 2, 3 |
| Tokens `universal` / `i386` / `ppc`; i486 files as `i386` | 1 |
| `.PKGINFO` full labels unchanged | 1–5 (no pkginfo writer change) |
| Companions get the suffix | 2 (`package_canon_name` on `-hdrs`/`-obj` clones), 3 exists loop |
| Missing/unmapped architecture does not emit old stem | 2 |
| Lookup new names only; old name not a hit | 3 |
| Thin tries cpu then universal; universal only universal | 3 |
| PKGINFO token must match filename | 3 (`architecture_path_has_token`) |
| Cache already exists uses new stem | 3 |
| One-shot `/build/repo` rename, skip invalid, abort on collision | 5 |
| No rbuild subcommand; no bootstrap rebuild | 5 |
| Unit tests for canon/lookup/mismatch | 1–4 |
| Out of scope (gcc-darwin, kernel skip, `-undefined suppress`, merge to main) | not tasked |
