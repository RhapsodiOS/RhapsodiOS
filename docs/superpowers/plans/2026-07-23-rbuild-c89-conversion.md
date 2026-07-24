# rbuild C89 Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three Perl build scripts (`darwin-buildpackage`, `darwin-buildall`, `darwin-missing`) and their `Dpkg::Package::*` engine with a single C89 executable, `rbuild`, that produces/consumes apk packages instead of dpkg `.deb`.

**Architecture:** A new self-contained project at `src/rbuild-1/`. Foundational string/collection utilities (`strutil`) underpin a package-metadata module (`package`), a manifest reader (`manifest`), a subprocess runner (`exec`), an apk packaging module (`pkginfo`), and the build engine (`builder`, ported from `Builder.pm`). `main.c` dispatches three subcommands. The unmodified Perl in `src/buildtools-2/` stays in the tree as the reference oracle for a command-trace comparison test.

**Tech Stack:** C89 (`cc -ansi -pedantic`), POSIX libc only (`opendir`, `stat`, `fork`/`exec`, `waitpid`, `getcwd`, `getenv`). Shells out to `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`, `mkdir`, `cp`, `rm`. No external libraries.

## Global Constraints

- Language: **C89 only**. `/* */` comments (no `//`), all declarations at the top of their block (no mixed declarations and statements), no C99 library functions. **Do not use `snprintf`** (C99) — build strings with the `sbuf` helper or `sprintf` into a sized local buffer for small integers only.
- No external libraries; POSIX + shelling out only. No `libapk`, `libarchive`, `zlib`, or regex library.
- Target package tool: **apk-tools 2.0_pre11** (no package-build subcommand; `rbuild` assembles `.apk` itself via `tar`+`gzip`).
- Package file naming: **`<pkgname>-<pkgver>.apk`**. Existence/dependency matching requires the version segment to **start with a digit** (`<name>-<digit…>.apk`), so `foo` never matches `foo-hdrs-1.0.apk`.
- Architecture string in metadata: `universal-apple-rhapsody`.
- Default description when absent: `No description available.`
- Default maintainer when absent: `Anonymous <darwin-development@public.lists.apple.com>`.
- `.PKGINFO` uses apk keys `pkgname`, `pkgver`, `arch`, `pkgdesc`, `maintainer`, `origin`, `provides`, `replaces`, plus the custom `builddepends` (space-separated). `builddepends` is NOT apk's runtime `depend`; apk ignores unknown keys.
- Source staging excludes `CVS/`, `.svn/`, `.git/`.
- `--cvs` is rejected with an error (support dropped); source type is always `dir`.
- Every function returns `int` status (`0` = success) or a pointer that is `NULL` on failure; messages go to stderr. No `exit()` outside `main.c` / usage.
- Frequent commits: one per task minimum.

---

## File Structure

All paths under `src/rbuild-1/`:

- `Makefile` — build + install (Rhapsody conventions) + `test`/`trace-test`
- `strutil.h` / `strutil.c` — allocation wrappers, `sbuf`, `strlist`, string helpers
- `package.h` / `package.c` — `Package` struct, control parse/unparse, canon names
- `manifest.h` / `manifest.c` — manifest/directory reader
- `exec.h` / `exec.c` — subprocess runner, `checkret`, `printcmd`, dry-run gate
- `pkginfo.h` / `pkginfo.c` — write `.PKGINFO`, assemble `.apk`
- `builder.h` / `builder.c` — the build engine (ported from `Builder.pm`)
- `main.c` — subcommand dispatch and the three entrypoints
- `tests/test.h` — tiny assertion harness (header-only)
- `tests/test_strutil.c`, `tests/test_package.c`, `tests/test_manifest.c`, `tests/test_builder.c` — unit tests
- `tests/trace/shim/*` — fake tools that log argv
- `tests/trace/run.sh` — trace-comparison driver
- `tests/trace/fixtures/` — sample manifest + source tree

Authoritative behavioral references (read these while porting):
- `src/buildtools-2/lib/Builder.pm`
- `src/buildtools-2/lib/Manifest.pm`
- `src/dpkg_scriptlib-1/perl5/Dpkg/Package/Package.pm`
- `src/buildtools-2/tools/darwin-*.pl`

---

## Task 1: Project scaffolding, test harness, Makefile

**Files:**
- Create: `src/rbuild-1/Makefile`
- Create: `src/rbuild-1/tests/test.h`
- Create: `src/rbuild-1/.gitignore`

**Interfaces:**
- Produces: `TEST(name)`, `RUN(name)`, `CHECK(cond)`, `CHECK_STR(got, want)`, `CHECK_INT(got, want)`, `TEST_MAIN()` macros for later test files; a `make test` target that compiles and runs every `tests/test_*.c`.

- [ ] **Step 1: Create the test harness header**

Create `src/rbuild-1/tests/test.h`:

```c
#ifndef RBUILD_TEST_H
#define RBUILD_TEST_H

#include <stdio.h>
#include <string.h>

static int test_failures = 0;
static int test_checks = 0;

#define CHECK(cond) \
    do { \
        test_checks++; \
        if (!(cond)) { \
            printf("  FAIL %s:%d: CHECK(%s)\n", __FILE__, __LINE__, #cond); \
            test_failures++; \
        } \
    } while (0)

#define CHECK_STR(got, want) \
    do { \
        const char *g_ = (got); \
        const char *w_ = (want); \
        test_checks++; \
        if (g_ == 0 || w_ == 0 || strcmp(g_, w_) != 0) { \
            printf("  FAIL %s:%d: got \"%s\" want \"%s\"\n", \
                   __FILE__, __LINE__, g_ ? g_ : "(null)", w_ ? w_ : "(null)"); \
            test_failures++; \
        } \
    } while (0)

#define CHECK_INT(got, want) \
    do { \
        long g_ = (long)(got); \
        long w_ = (long)(want); \
        test_checks++; \
        if (g_ != w_) { \
            printf("  FAIL %s:%d: got %ld want %ld\n", \
                   __FILE__, __LINE__, g_, w_); \
            test_failures++; \
        } \
    } while (0)

#define TEST(name) static void name(void)
#define RUN(name) \
    do { printf("- %s\n", #name); name(); } while (0)

#define TEST_MAIN() \
    int main(void) { \
        run_all(); \
        printf("%s: %d checks, %d failures\n", \
               __FILE__, test_checks, test_failures); \
        return test_failures ? 1 : 0; \
    }

#endif
```

- [ ] **Step 2: Create the Makefile**

Create `src/rbuild-1/Makefile` (note: real tabs for recipe lines):

```make
CC = cc
CFLAGS = -ansi -pedantic -Wall -O

d = $(DSTROOT)
p = rbuild

OBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o main.o

TESTS = tests/test_strutil tests/test_package tests/test_manifest tests/test_builder

.PHONY: all clean install installhdrs installsrc test trace-test

all: rbuild

rbuild: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

# Unit tests: each test binary links the module objects (except main.o).
LIBOBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o

test: $(TESTS)
	@fail=0; for t in $(TESTS); do echo "== $$t =="; ./$$t || fail=1; done; \
		[ $$fail -eq 0 ] && echo "ALL TESTS PASSED" || (echo "TESTS FAILED"; exit 1)

tests/test_strutil: tests/test_strutil.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_strutil.c $(LIBOBJS)
tests/test_package: tests/test_package.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_package.c $(LIBOBJS)
tests/test_manifest: tests/test_manifest.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_manifest.c $(LIBOBJS)
tests/test_builder: tests/test_builder.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_builder.c $(LIBOBJS)

trace-test: rbuild
	sh tests/trace/run.sh

install: rbuild
	install -d $(d)/usr/bin
	install -c -m 755 rbuild $(d)/usr/bin/rbuild

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	$(RM) $(OBJS) rbuild $(TESTS) tests/*.o
	find . -name \*~ -print0 | xargs -0 $(RM)
```

- [ ] **Step 3: Create .gitignore**

Create `src/rbuild-1/.gitignore`:

```
*.o
/rbuild
/tests/test_strutil
/tests/test_package
/tests/test_manifest
/tests/test_builder
/tests/trace/*.log
/tests/trace/*.out
```

- [ ] **Step 4: Verify the Makefile parses**

Run: `cd src/rbuild-1 && make -n all`
Expected: prints compile commands (no "no rule" / syntax errors). It will reference not-yet-created `.c` files — that's fine for `-n`.

- [ ] **Step 5: Commit**

```bash
git add -f src/rbuild-1/Makefile src/rbuild-1/tests/test.h src/rbuild-1/.gitignore
git commit -m "rbuild: project scaffolding, test harness, Makefile"
```

Note: `git add -f` is used throughout because `docs/superpowers` is gitignored but `src/` is not — verify `src/rbuild-1` is not ignored with `git check-ignore src/rbuild-1/Makefile` (should print nothing). If it prints, drop `-f`.

---

## Task 2: strutil — allocation wrappers, sbuf, strlist

**Files:**
- Create: `src/rbuild-1/strutil.h`
- Create: `src/rbuild-1/strutil.c`
- Test: `src/rbuild-1/tests/test_strutil.c`

**Interfaces:**
- Produces:
  - `void *xmalloc(size_t)`, `void *xrealloc(void *, size_t)`, `char *xstrdup(const char *)`
  - `sbuf` = `{ char *buf; size_t len; size_t cap; }`; `sbuf_init`, `sbuf_free`, `sbuf_putc`, `sbuf_puts`, `sbuf_putn(sbuf*, const char*, size_t)`, `char *sbuf_steal(sbuf*)`
  - `strlist` = `{ char **items; size_t count; size_t cap; }`; `strlist_init`, `strlist_free`, `strlist_push(strlist*, const char*)`, `strlist_push_owned(strlist*, char*)`

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_strutil.c`:

```c
#include "strutil.h"
#include "test.h"

TEST(test_sbuf_appends) {
    sbuf s;
    char *out;
    sbuf_init(&s);
    sbuf_puts(&s, "he");
    sbuf_putc(&s, 'l');
    sbuf_putn(&s, "llo world", 3);
    out = sbuf_steal(&s);
    CHECK_STR(out, "hello");
    free(out);
    sbuf_free(&s);
}

TEST(test_strlist_push) {
    strlist l;
    strlist_init(&l);
    strlist_push(&l, "a");
    strlist_push(&l, "b");
    strlist_push_owned(&l, xstrdup("c"));
    CHECK_INT(l.count, 3);
    CHECK_STR(l.items[0], "a");
    CHECK_STR(l.items[2], "c");
    strlist_free(&l);
}

static void run_all(void) {
    RUN(test_sbuf_appends);
    RUN(test_strlist_push);
}

TEST_MAIN()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src/rbuild-1 && make tests/test_strutil`
Expected: FAIL — link/compile errors (`strutil.h` / functions not found).

- [ ] **Step 3: Write the header**

Create `src/rbuild-1/strutil.h`:

```c
#ifndef RBUILD_STRUTIL_H
#define RBUILD_STRUTIL_H

#include <stddef.h>
#include <stdlib.h>

void *xmalloc(size_t n);
void *xrealloc(void *p, size_t n);
char *xstrdup(const char *s);

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
} sbuf;

void sbuf_init(sbuf *s);
void sbuf_free(sbuf *s);
void sbuf_putc(sbuf *s, char c);
void sbuf_puts(sbuf *s, const char *str);
void sbuf_putn(sbuf *s, const char *str, size_t n);
char *sbuf_steal(sbuf *s);   /* NUL-terminated malloc'd copy; resets s */

typedef struct {
    char **items;
    size_t count;
    size_t cap;
} strlist;

void strlist_init(strlist *l);
void strlist_free(strlist *l);
void strlist_push(strlist *l, const char *s);       /* copies */
void strlist_push_owned(strlist *l, char *s);       /* takes ownership */

#endif
```

- [ ] **Step 4: Write the implementation**

Create `src/rbuild-1/strutil.c`:

```c
#include "strutil.h"
#include <string.h>
#include <stdio.h>

void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (p == 0) { fprintf(stderr, "rbuild: out of memory\n"); exit(2); }
    return p;
}

void *xrealloc(void *p, size_t n) {
    void *q = realloc(p, n ? n : 1);
    if (q == 0) { fprintf(stderr, "rbuild: out of memory\n"); exit(2); }
    return q;
}

char *xstrdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = (char *) xmalloc(n);
    memcpy(p, s, n);
    return p;
}

void sbuf_init(sbuf *s) {
    s->cap = 16;
    s->len = 0;
    s->buf = (char *) xmalloc(s->cap);
    s->buf[0] = '\0';
}

void sbuf_free(sbuf *s) {
    free(s->buf);
    s->buf = 0;
    s->len = 0;
    s->cap = 0;
}

static void sbuf_reserve(sbuf *s, size_t extra) {
    size_t need = s->len + extra + 1;
    if (need > s->cap) {
        while (s->cap < need) s->cap *= 2;
        s->buf = (char *) xrealloc(s->buf, s->cap);
    }
}

void sbuf_putc(sbuf *s, char c) {
    sbuf_reserve(s, 1);
    s->buf[s->len++] = c;
    s->buf[s->len] = '\0';
}

void sbuf_putn(sbuf *s, const char *str, size_t n) {
    sbuf_reserve(s, n);
    memcpy(s->buf + s->len, str, n);
    s->len += n;
    s->buf[s->len] = '\0';
}

void sbuf_puts(sbuf *s, const char *str) {
    sbuf_putn(s, str, strlen(str));
}

char *sbuf_steal(sbuf *s) {
    char *out = xstrdup(s->buf);
    s->len = 0;
    s->buf[0] = '\0';
    return out;
}

void strlist_init(strlist *l) {
    l->cap = 4;
    l->count = 0;
    l->items = (char **) xmalloc(l->cap * sizeof(char *));
}

void strlist_free(strlist *l) {
    size_t i;
    for (i = 0; i < l->count; i++) free(l->items[i]);
    free(l->items);
    l->items = 0;
    l->count = 0;
    l->cap = 0;
}

void strlist_push_owned(strlist *l, char *s) {
    if (l->count == l->cap) {
        l->cap *= 2;
        l->items = (char **) xrealloc(l->items, l->cap * sizeof(char *));
    }
    l->items[l->count++] = s;
}

void strlist_push(strlist *l, const char *s) {
    strlist_push_owned(l, xstrdup(s));
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd src/rbuild-1 && make tests/test_strutil && ./tests/test_strutil`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/strutil.h src/rbuild-1/strutil.c src/rbuild-1/tests/test_strutil.c
git commit -m "rbuild: strutil sbuf + strlist + alloc wrappers"
```

---

## Task 2b: strutil — string helpers

**Files:**
- Modify: `src/rbuild-1/strutil.h` (add declarations)
- Modify: `src/rbuild-1/strutil.c` (add implementations)
- Modify: `src/rbuild-1/tests/test_strutil.c` (add tests)

**Interfaces:**
- Produces:
  - `char *str_chomp(char *s)` — strip one trailing `\n` in place, return `s`
  - `void str_lowercase(char *s)` — ASCII lowercase in place
  - `char *str_trim(char *s)` — strip leading/trailing ASCII whitespace; returns pointer within `s`
  - `int str_has_prefix(const char *s, const char *prefix)`
  - `int str_has_suffix(const char *s, const char *suffix)`
  - `void str_split_ws(const char *s, strlist *out)` — split on runs of whitespace (Perl `split`)
  - `void str_split_chars(const char *s, const char *seps, strlist *out)` — split on runs of any char in `seps` (Perl `split /[ ,]+/`)
  - `char *str_cats(const char *first, ...)` — concatenate NUL-terminated arg list, malloc'd
  - `char *path_join(const char *a, const char *b)` — `"a/b"`, malloc'd

- [ ] **Step 1: Add failing tests**

Append to `src/rbuild-1/tests/test_strutil.c` (before `run_all`, and add `RUN(...)` lines inside `run_all`):

```c
TEST(test_str_ops) {
    char a[] = "line\n";
    char b[] = "MixEd";
    char c[] = "  hi  ";
    CHECK_STR(str_chomp(a), "line");
    str_lowercase(b); CHECK_STR(b, "mixed");
    CHECK_STR(str_trim(c), "hi");
    CHECK_INT(str_has_prefix("foobar", "foo"), 1);
    CHECK_INT(str_has_prefix("foobar", "bar"), 0);
    CHECK_INT(str_has_suffix("x.deb", ".deb"), 1);
    CHECK_INT(str_has_suffix("x.apk", ".deb"), 0);
}

TEST(test_str_split) {
    strlist l;
    strlist_init(&l);
    str_split_ws("  dir   /path/to/src   all ", &l);
    CHECK_INT(l.count, 3);
    CHECK_STR(l.items[0], "dir");
    CHECK_STR(l.items[1], "/path/to/src");
    CHECK_STR(l.items[2], "all");
    strlist_free(&l);

    strlist_init(&l);
    str_split_chars("build-base, gnuzip  libfoo", " ,", &l);
    CHECK_INT(l.count, 3);
    CHECK_STR(l.items[0], "build-base");
    CHECK_STR(l.items[1], "gnuzip");
    CHECK_STR(l.items[2], "libfoo");
    strlist_free(&l);
}

TEST(test_str_cats_pathjoin) {
    char *x = str_cats("a", "-", "b", (char *)0);
    char *y = path_join("/root", "usr/bin");
    CHECK_STR(x, "a-b");
    CHECK_STR(y, "/root/usr/bin");
    free(x); free(y);
}
```

Add to `run_all`:
```c
    RUN(test_str_ops);
    RUN(test_str_split);
    RUN(test_str_cats_pathjoin);
```

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_strutil`
Expected: FAIL — undefined references to the new functions.

- [ ] **Step 3: Add declarations to the header**

Add before `#endif` in `src/rbuild-1/strutil.h`:

```c
char *str_chomp(char *s);
void str_lowercase(char *s);
char *str_trim(char *s);
int str_has_prefix(const char *s, const char *prefix);
int str_has_suffix(const char *s, const char *suffix);
void str_split_ws(const char *s, strlist *out);
void str_split_chars(const char *s, const char *seps, strlist *out);
char *str_cats(const char *first, ...);
char *path_join(const char *a, const char *b);
```

- [ ] **Step 4: Add implementations**

Append to `src/rbuild-1/strutil.c` (and add `#include <stdarg.h>` and `#include <ctype.h>` near the top):

```c
char *str_chomp(char *s) {
    size_t n = strlen(s);
    if (n > 0 && s[n - 1] == '\n') s[n - 1] = '\0';
    return s;
}

void str_lowercase(char *s) {
    for (; *s; s++) *s = (char) tolower((unsigned char) *s);
}

char *str_trim(char *s) {
    char *end;
    while (*s && isspace((unsigned char) *s)) s++;
    if (*s == '\0') return s;
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char) *end)) *end-- = '\0';
    return s;
}

int str_has_prefix(const char *s, const char *prefix) {
    size_t n = strlen(prefix);
    return strncmp(s, prefix, n) == 0;
}

int str_has_suffix(const char *s, const char *suffix) {
    size_t ls = strlen(s), lx = strlen(suffix);
    if (lx > ls) return 0;
    return strcmp(s + (ls - lx), suffix) == 0;
}

static int in_set(char c, const char *set) {
    for (; *set; set++) if (*set == c) return 1;
    return 0;
}

static void split_on(const char *s, const char *seps, strlist *out) {
    const char *p = s;
    while (*p) {
        const char *start;
        while (*p && in_set(*p, seps)) p++;
        if (*p == '\0') break;
        start = p;
        while (*p && !in_set(*p, seps)) p++;
        {
            char *tok = (char *) xmalloc((size_t)(p - start) + 1);
            memcpy(tok, start, (size_t)(p - start));
            tok[p - start] = '\0';
            strlist_push_owned(out, tok);
        }
    }
}

void str_split_ws(const char *s, strlist *out) {
    split_on(s, " \t\n\r\f\v", out);
}

void str_split_chars(const char *s, const char *seps, strlist *out) {
    split_on(s, seps, out);
}

char *str_cats(const char *first, ...) {
    sbuf s;
    va_list ap;
    const char *arg;
    char *out;
    sbuf_init(&s);
    sbuf_puts(&s, first);
    va_start(ap, first);
    while ((arg = va_arg(ap, const char *)) != 0) sbuf_puts(&s, arg);
    va_end(ap);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

char *path_join(const char *a, const char *b) {
    return str_cats(a, "/", b, (char *)0);
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_strutil && ./tests/test_strutil`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/strutil.h src/rbuild-1/strutil.c src/rbuild-1/tests/test_strutil.c
git commit -m "rbuild: strutil string helpers (split/trim/cats/path_join)"
```

---

## Task 3: package — Package struct, parse/unparse, canon names

**Reference:** `src/dpkg_scriptlib-1/perl5/Dpkg/Package/Package.pm`.

**Files:**
- Create: `src/rbuild-1/package.h`
- Create: `src/rbuild-1/package.c`
- Test: `src/rbuild-1/tests/test_package.c`

**Interfaces:**
- Consumes: `strutil` (`sbuf`, `strlist`, `str_*`, `xstrdup`).
- Produces:
  - `Package` struct (fields per Global spec) with `strlist build_depends; int has_build_depends;`
  - `void package_init(Package *)`, `void package_free(Package *)`
  - `void package_set(char **field, const char *value)` — free+dup helper (internal, but exposed for reuse by builder)
  - `void package_parse(Package *, const char *data)` — parse control text; keys lowercased; continuation lines folded; `build-depends` split on `[ ,]+`
  - `char *package_unparse(const Package *)` — control text (field order matches `Package.pm::unparse`)
  - `char *package_canon_version(const Package *)`
  - `char *package_canon_name(const Package *)` — **apk stem** `"<pkgname>-<pkgver>"` (redefined from the Perl's `pkg_ver_arch`; arch now lives only in `.PKGINFO`)

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_package.c`:

```c
#include "package.h"
#include "test.h"
#include <stdlib.h>

TEST(test_parse_basic) {
    Package p;
    package_init(&p);
    package_parse(&p,
        "Package: objc4\n"
        "Maintainer: Darwin Developers <d@x>\n"
        "Version: 174\n"
        "Description: Objective-C runtime\n"
        "Build-Depends: build-base, libstreams-hdrs architecture-hdrs\n");
    CHECK_STR(p.package, "objc4");
    CHECK_STR(p.version, "174");
    CHECK_STR(p.maintainer, "Darwin Developers <d@x>");
    CHECK_STR(p.description, "Objective-C runtime");
    CHECK_INT(p.has_build_depends, 1);
    CHECK_INT(p.build_depends.count, 3);
    CHECK_STR(p.build_depends.items[0], "build-base");
    CHECK_STR(p.build_depends.items[2], "architecture-hdrs");
    package_free(&p);
}

TEST(test_parse_continuation) {
    Package p;
    package_init(&p);
    package_parse(&p,
        "Package: foo\n"
        "Version: 1\n"
        "Description: line one\n"
        " line two\n");
    CHECK_STR(p.description, "line one\n line two");
    package_free(&p);
}

TEST(test_canon_names) {
    Package p;
    char *v, *n;
    package_init(&p);
    package_parse(&p, "Package: foo\nVersion: 1.2-3\n");
    package_set(&p.architecture, "universal-apple-rhapsody");
    v = package_canon_version(&p);
    n = package_canon_name(&p);
    CHECK_STR(v, "1.2-3");
    CHECK_STR(n, "foo-1.2-3");
    free(v); free(n);
    package_free(&p);
}

TEST(test_unparse_order) {
    Package p;
    char *out;
    package_init(&p);
    package_set(&p.package, "foo");
    package_set(&p.maintainer, "M <m@x>");
    package_set(&p.version, "1");
    package_set(&p.source, "foo");
    package_set(&p.architecture, "universal-apple-rhapsody");
    package_set(&p.description, "d");
    out = package_unparse(&p);
    CHECK_STR(out,
        "Package: foo\n"
        "Maintainer: M <m@x>\n"
        "Version: 1\n"
        "Source: foo\n"
        "Architecture: universal-apple-rhapsody\n"
        "Description: d\n");
    free(out);
    package_free(&p);
}

static void run_all(void) {
    RUN(test_parse_basic);
    RUN(test_parse_continuation);
    RUN(test_canon_names);
    RUN(test_unparse_order);
}

TEST_MAIN()
```

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_package`
Expected: FAIL — `package.h` not found.

- [ ] **Step 3: Write the header**

Create `src/rbuild-1/package.h`:

```c
#ifndef RBUILD_PACKAGE_H
#define RBUILD_PACKAGE_H

#include "strutil.h"

typedef struct {
    char *package;
    char *version;
    char *architecture;
    char *source;
    char *description;
    char *maintainer;
    char *provides;
    char *conflicts;
    char *replaces;
    char *revision;
    char *package_revision;
    strlist build_depends;
    int has_build_depends;
} Package;

void package_init(Package *p);
void package_free(Package *p);
void package_set(char **field, const char *value);
void package_parse(Package *p, const char *data);
char *package_unparse(const Package *p);
char *package_canon_version(const Package *p);
char *package_canon_name(const Package *p);

#endif
```

- [ ] **Step 4: Write the implementation**

Port notes: the Perl `parse` (Package.pm:24-47) folds continuation lines (`\n` followed by whitespace becomes a joined line), then matches `^(\S+):\s*(.*)$` per line, lowercases the key, and stores the value. Continuation folding here is implemented by, for each header, appending subsequent lines that start with whitespace as `"\n "` + trimmed-content. `build-depends` is split on `[ ,]+`.

Create `src/rbuild-1/package.c`:

```c
#include "package.h"
#include <string.h>
#include <ctype.h>

void package_init(Package *p) {
    memset(p, 0, sizeof(*p));
    strlist_init(&p->build_depends);
    p->has_build_depends = 0;
}

void package_free(Package *p) {
    free(p->package); free(p->version); free(p->architecture);
    free(p->source); free(p->description); free(p->maintainer);
    free(p->provides); free(p->conflicts); free(p->replaces);
    free(p->revision); free(p->package_revision);
    strlist_free(&p->build_depends);
    memset(p, 0, sizeof(*p));
}

void package_set(char **field, const char *value) {
    free(*field);
    *field = value ? xstrdup(value) : 0;
}

/* Assign a parsed key/value into the struct. Unknown keys are ignored
   (mirrors Perl storing them in the hash but us never reading them). */
static void assign_field(Package *p, const char *key, const char *value) {
    if (strcmp(key, "package") == 0) package_set(&p->package, value);
    else if (strcmp(key, "version") == 0) package_set(&p->version, value);
    else if (strcmp(key, "architecture") == 0) package_set(&p->architecture, value);
    else if (strcmp(key, "source") == 0) package_set(&p->source, value);
    else if (strcmp(key, "description") == 0) package_set(&p->description, value);
    else if (strcmp(key, "maintainer") == 0) package_set(&p->maintainer, value);
    else if (strcmp(key, "provides") == 0) package_set(&p->provides, value);
    else if (strcmp(key, "conflicts") == 0) package_set(&p->conflicts, value);
    else if (strcmp(key, "replaces") == 0) package_set(&p->replaces, value);
    else if (strcmp(key, "revision") == 0) package_set(&p->revision, value);
    else if (strcmp(key, "package_revision") == 0)
        package_set(&p->package_revision, value);
    else if (strcmp(key, "build-depends") == 0) {
        strlist_free(&p->build_depends);
        strlist_init(&p->build_depends);
        str_split_chars(value, " ,", &p->build_depends);
        p->has_build_depends = 1;
    }
}

void package_parse(Package *p, const char *data) {
    /* Work on a mutable copy split into lines. */
    char *copy = xstrdup(data);
    char *line, *save = copy;
    char curkey[128];
    sbuf curval;
    int have = 0;

    sbuf_init(&curval);
    curkey[0] = '\0';

    for (;;) {
        line = save;
        if (*line == '\0' && line == save && *save == '\0' && have == 0 && curkey[0] == '\0')
            ; /* fallthrough handled below */
        /* find end of this line */
        {
            char *nl = strchr(save, '\n');
            if (nl) { *nl = '\0'; save = nl + 1; }
            else { save = save + strlen(save); }
        }

        if (line[0] == ' ' || line[0] == '\t') {
            /* continuation line: append "\n " + trimmed remainder */
            char *t = str_trim(line);
            if (curkey[0] != '\0') {
                sbuf_puts(&curval, "\n ");
                sbuf_puts(&curval, t);
            }
        } else {
            char *colon = strchr(line, ':');
            /* flush previous field */
            if (curkey[0] != '\0') {
                assign_field(p, curkey, curval.buf);
                curkey[0] = '\0';
                sbuf_free(&curval);
                sbuf_init(&curval);
            }
            if (colon) {
                char *value;
                size_t klen = (size_t)(colon - line);
                if (klen >= sizeof(curkey)) klen = sizeof(curkey) - 1;
                memcpy(curkey, line, klen);
                curkey[klen] = '\0';
                str_lowercase(curkey);
                value = colon + 1;
                while (*value == ' ' || *value == '\t') value++;
                sbuf_puts(&curval, str_trim(value));
                have = 1;
            }
        }

        if (*line == '\0' && *save == '\0') {
            /* reached end after processing the final (empty) segment */
            if (line == save) break;
        }
        if (save > copy && save[-1] == '\0' && *save == '\0' &&
            (size_t)(save - copy) >= strlen(data))
            break;
        if (*save == '\0' && (line[0] != '\0' ? 1 : 1)) {
            /* one more pass may be needed only if there was trailing text */
        }
        if (save == line) break; /* no progress guard */
        if (*save == '\0') {
            /* process trailing segment once, then stop */
            if (*line != '\0' || curkey[0] != '\0') {
                /* already handled 'line'; flush and finish */
            }
            break;
        }
    }

    if (curkey[0] != '\0') assign_field(p, curkey, curval.buf);

    sbuf_free(&curval);
    free(copy);
}

char *package_canon_version(const Package *p) {
    sbuf s;
    char *out;
    sbuf_init(&s);
    sbuf_puts(&s, p->version ? p->version : "");
    /* Perl: dies if both revision and package_revision set; append whichever. */
    if (p->package_revision) sbuf_puts(&s, p->package_revision);
    if (p->revision) sbuf_puts(&s, p->revision);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

char *package_canon_name(const Package *p) {
    char *ver = package_canon_version(p);
    char *out = str_cats(p->package ? p->package : "", "-", ver, (char *)0);
    free(ver);
    return out;
}

static void unparse_field(sbuf *s, const char *label, const char *value) {
    sbuf_puts(s, label);
    sbuf_puts(s, ": ");
    sbuf_puts(s, value ? value : "");
    sbuf_putc(s, '\n');
}

char *package_unparse(const Package *p) {
    sbuf s;
    char *out;
    sbuf_init(&s);
    unparse_field(&s, "Package", p->package);
    if (p->provides) unparse_field(&s, "Provides", p->provides);
    if (p->conflicts) unparse_field(&s, "Conflicts", p->conflicts);
    if (p->replaces) unparse_field(&s, "Replaces", p->replaces);
    unparse_field(&s, "Maintainer", p->maintainer);
    unparse_field(&s, "Version", p->version);
    unparse_field(&s, "Source", p->source);
    if (p->has_build_depends) {
        sbuf bd;
        char *joined;
        size_t i;
        sbuf_init(&bd);
        for (i = 0; i < p->build_depends.count; i++) {
            if (i) sbuf_puts(&bd, ", ");
            sbuf_puts(&bd, p->build_depends.items[i]);
        }
        joined = sbuf_steal(&bd);
        unparse_field(&s, "Build-Depends", joined);
        free(joined);
        sbuf_free(&bd);
    }
    unparse_field(&s, "Architecture", p->architecture);
    unparse_field(&s, "Description", p->description);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}
```

> **Implementer note:** the `package_parse` loop above is fiddly. Prefer to rewrite it as a clean two-pass: (1) split `data` into physical lines; (2) fold any line beginning with whitespace onto the previous field's value as `"\n " + trim(line)`; (3) for each header line, split at the first `:`, lowercase the key, `str_trim` the value, and call `assign_field`. Drive it with the four tests in Step 1 — especially `test_parse_continuation`. The exact loop shape is not what matters; passing the tests (and matching `Package.pm`) is.

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_package && ./tests/test_package`
Expected: PASS — `0 failures`. If `test_parse_continuation` fails, apply the two-pass rewrite from the implementer note.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/package.h src/rbuild-1/package.c src/rbuild-1/tests/test_package.c
git commit -m "rbuild: package metadata parse/unparse/canon"
```

---

## Task 4: builder — dir2name and pkgname (pure functions)

**Reference:** `Builder.pm:241-278` (`pkgname`, `dir2name`).

**Files:**
- Create: `src/rbuild-1/builder.h`
- Create: `src/rbuild-1/builder.c`
- Test: `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Consumes: `strutil`.
- Produces (in `builder.h`, this task adds only these two + the `Params` struct skeleton used by later tasks):
  - `void builder_dir2name(const char *srcname, char **pbase, char **pname, char **rev)` — `*rev` is `NULL` when no `-<digits>` revision is present; caller frees all three.
  - `char *builder_pkgname(const char *pbase, const char *revision)`

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_builder.c`:

```c
#include "builder.h"
#include "test.h"
#include <stdlib.h>

TEST(test_dir2name) {
    char *base = 0, *name = 0, *rev = 0;
    builder_dir2name("/some/path/gnumake-3.79", &base, &name, &rev);
    CHECK_STR(base, "gnumake");
    CHECK_STR(name, "gnumake");
    CHECK_STR(rev, "3.79");
    free(base); free(name); free(rev);

    base = name = rev = 0;
    builder_dir2name("foo_bar", &base, &name, &rev);
    CHECK_STR(base, "foo_bar");
    CHECK_STR(name, "foo-bar");   /* pkgname lowercases + _->- */
    CHECK(rev == 0);
    free(base); free(name); free(rev);
}

TEST(test_pkgname) {
    char *a = builder_pkgname("Foo_Bar", 0);
    char *b = builder_pkgname("appkit", 0);
    char *c = builder_pkgname("ssh", "1.2");
    char *d = builder_pkgname("ssh", "2.0");
    CHECK_STR(a, "foo-bar");
    CHECK_STR(b, "appkit-old");
    CHECK_STR(c, "ssh1");
    CHECK_STR(d, "ssh2");
    free(a); free(b); free(c); free(d);
}

static void run_all(void) {
    RUN(test_dir2name);
    RUN(test_pkgname);
}

TEST_MAIN()
```

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_builder`
Expected: FAIL — `builder.h` not found.

- [ ] **Step 3: Write the header (initial)**

Create `src/rbuild-1/builder.h`:

```c
#ifndef RBUILD_BUILDER_H
#define RBUILD_BUILDER_H

#include "strutil.h"
#include "package.h"

typedef struct {
    char *BUILDROOT;
    char *SRCROOT;
    char *OBJROOT;
    char *SYMROOT;
    char *DSTROOT;
    char *HDRROOT;
    char *LIBCOBJROOT;
    char *LOGFILE;
    char *SUBLIBROOTS;
    char *PACKAGEROOT;
    char *SRCDIR;
    char *PACKAGEDIR;
} Params;

void params_init(Params *p);
void params_free(Params *p);

void builder_dir2name(const char *srcname, char **pbase, char **pname, char **rev);
char *builder_pkgname(const char *pbase, const char *revision);

#endif
```

- [ ] **Step 4: Write the implementation (initial)**

Port notes:
- `pkgname` (Builder.pm:241-259): replace `_`→`-`; if name is `appkit` → `appkit-old`; if `ssh` → `ssh1` when revision starts with `1`, else `ssh2`; finally lowercase.
- `dir2name` (Builder.pm:261-278): strip trailing slashes; take the basename (text after last `/`); the revision is the `-<[0-9.]+>` suffix (may be absent → NULL); `pbase` is the basename with that `-<digits>` suffix removed; `pname = pkgname(pbase, revision)`.

Create `src/rbuild-1/builder.c`:

```c
#include "builder.h"
#include <string.h>
#include <ctype.h>

void params_init(Params *p) { memset(p, 0, sizeof(*p)); }

void params_free(Params *p) {
    free(p->BUILDROOT); free(p->SRCROOT); free(p->OBJROOT); free(p->SYMROOT);
    free(p->DSTROOT); free(p->HDRROOT); free(p->LIBCOBJROOT); free(p->LOGFILE);
    free(p->SUBLIBROOTS); free(p->PACKAGEROOT); free(p->SRCDIR); free(p->PACKAGEDIR);
    memset(p, 0, sizeof(*p));
}

char *builder_pkgname(const char *pbase, const char *revision) {
    char *name = xstrdup(pbase);
    char *out;
    char *q;
    for (q = name; *q; q++) if (*q == '_') *q = '-';
    if (strcmp(name, "appkit") == 0) {
        out = xstrdup("appkit-old");
        free(name);
        name = out;
    } else if (strcmp(name, "ssh") == 0) {
        if (revision && revision[0] == '1') out = xstrdup("ssh1");
        else out = xstrdup("ssh2");
        free(name);
        name = out;
    }
    str_lowercase(name);
    return name;
}

void builder_dir2name(const char *srcname, char **pbase, char **pname, char **rev) {
    /* strip trailing slashes */
    char *tmp = xstrdup(srcname);
    size_t n = strlen(tmp);
    char *base, *slash, *dash;
    char *revision = 0;

    while (n > 0 && tmp[n - 1] == '/') tmp[--n] = '\0';
    slash = strrchr(tmp, '/');
    base = xstrdup(slash ? slash + 1 : tmp);
    free(tmp);

    /* find trailing "-<[0-9.]+>" */
    dash = strrchr(base, '-');
    if (dash) {
        const char *r = dash + 1;
        int ok = (*r != '\0');
        const char *s;
        for (s = r; *s; s++) {
            if (!isdigit((unsigned char) *s) && *s != '.') { ok = 0; break; }
        }
        if (ok) {
            revision = xstrdup(r);
            *dash = '\0';   /* strip suffix from base */
        }
    }

    *pbase = base;
    *rev = revision;
    *pname = builder_pkgname(base, revision);
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: builder dir2name + pkgname"
```

---

## Task 5: builder — package-file matching (match_pkgfile, exists, resolve_dependency)

**Reference:** `Builder.pm:919-960` (`resolve_dependency`, `exists`). Naming rule per Global Constraints.

**Files:**
- Modify: `src/rbuild-1/builder.h` (add declarations)
- Modify: `src/rbuild-1/builder.c` (add implementations)
- Modify: `src/rbuild-1/tests/test_builder.c` (add tests)

**Interfaces:**
- Produces:
  - `int builder_match_pkgfile(const char *filename, const char *name)` — 1 iff `filename` is `"<name>-<digit…>.apk"` (version segment starts with a digit).
  - `char *builder_exists(const Package *pkg, const char *type, const char *dir)` — for `type=="any"`, returns malloc'd `"<dir>/<match>"` for the first matching file in `dir`, else NULL. For `type=="exact"`, returns `"<dir>/<canon_name>.apk"` if it exists, else NULL.
  - `char *builder_resolve_dependency(const char *name, const strlist *repository)` — scan each dir in `repository`; return malloc'd `"<dir>/<match>"` for the first `builder_match_pkgfile` hit, else NULL.

- [ ] **Step 1: Add failing tests**

Append to `tests/test_builder.c` (and add `RUN(...)`s):

```c
TEST(test_match_pkgfile) {
    CHECK_INT(builder_match_pkgfile("foo-1.0.apk", "foo"), 1);
    CHECK_INT(builder_match_pkgfile("foo-hdrs-1.0.apk", "foo"), 0);
    CHECK_INT(builder_match_pkgfile("foo-hdrs-1.0.apk", "foo-hdrs"), 1);
    CHECK_INT(builder_match_pkgfile("foo.apk", "foo"), 0);
    CHECK_INT(builder_match_pkgfile("foo-1.0.deb", "foo"), 0);
    CHECK_INT(builder_match_pkgfile("foobar-1.0.apk", "foo"), 0);
}

TEST(test_resolve_and_exists) {
    /* Build a temp dir with a couple of .apk files. */
    Package p;
    strlist repo;
    char *r, *e;
    system("rm -rf /tmp/rbtest_repo && mkdir -p /tmp/rbtest_repo");
    system("touch /tmp/rbtest_repo/gnumake-3.79.apk");
    system("touch /tmp/rbtest_repo/gnumake-hdrs-3.79.apk");

    strlist_init(&repo);
    strlist_push(&repo, "/tmp/rbtest_repo");
    r = builder_resolve_dependency("gnumake", &repo);
    CHECK_STR(r, "/tmp/rbtest_repo/gnumake-3.79.apk");
    free(r);
    strlist_free(&repo);

    package_init(&p);
    package_set(&p.package, "gnumake");
    e = builder_exists(&p, "any", "/tmp/rbtest_repo");
    CHECK_STR(e, "/tmp/rbtest_repo/gnumake-3.79.apk");
    free(e);
    package_free(&p);
    system("rm -rf /tmp/rbtest_repo");
}
```

Add to `run_all`:
```c
    RUN(test_match_pkgfile);
    RUN(test_resolve_and_exists);
```

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_builder`
Expected: FAIL — undefined references.

- [ ] **Step 3: Add declarations**

Add to `builder.h` before `#endif`:

```c
int builder_match_pkgfile(const char *filename, const char *name);
char *builder_exists(const Package *pkg, const char *type, const char *dir);
char *builder_resolve_dependency(const char *name, const strlist *repository);
```

- [ ] **Step 4: Add implementations**

Append to `builder.c` (add `#include <dirent.h>`, `#include <sys/stat.h>`, `#include <stdio.h>` near the top):

```c
int builder_match_pkgfile(const char *filename, const char *name) {
    size_t nl = strlen(name);
    if (strncmp(filename, name, nl) != 0) return 0;
    if (filename[nl] != '-') return 0;
    if (!isdigit((unsigned char) filename[nl + 1])) return 0;
    return str_has_suffix(filename, ".apk");
}

static char *scan_dir_for(const char *dir, const char *name) {
    DIR *d = opendir(dir);
    struct dirent *de;
    char *found = 0;
    if (!d) return 0;
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        if (builder_match_pkgfile(de->d_name, name)) {
            found = path_join(dir, de->d_name);
            break;
        }
    }
    closedir(d);
    return found;
}

char *builder_resolve_dependency(const char *name, const strlist *repository) {
    size_t i;
    for (i = 0; i < repository->count; i++) {
        char *hit = scan_dir_for(repository->items[i], name);
        if (hit) return hit;
    }
    return 0;
}

char *builder_exists(const Package *pkg, const char *type, const char *dir) {
    if (strcmp(type, "any") == 0) {
        return scan_dir_for(dir, pkg->package);
    } else if (strcmp(type, "exact") == 0) {
        char *canon = package_canon_name(pkg);
        char *base = str_cats(canon, ".apk", (char *)0);
        char *full = path_join(dir, base);
        struct stat st;
        free(canon); free(base);
        if (stat(full, &st) == 0) return full;
        free(full);
        return 0;
    }
    fprintf(stderr, "rbuild: invalid match type \"%s\"\n", type);
    return 0;
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: builder package-file matching (exists/resolve)"
```

---

## Task 6: manifest — read srclist file or directory

**Reference:** `src/buildtools-2/lib/Manifest.pm`.

**Files:**
- Create: `src/rbuild-1/manifest.h`
- Create: `src/rbuild-1/manifest.c`
- Test: `src/rbuild-1/tests/test_manifest.c`

**Bug-fix divergence (documented):** the Perl directory branch has a bug — `next if $dir =~ /\.|\.\./` tests `$dir` instead of the entry, so it never skips `.`/`..`. `rbuild` skips `.` and `..` entries (the correct behavior). The trace tests use a srclist *file*, not directory mode, so this does not affect trace parity.

**Interfaces:**
- Consumes: `strutil`.
- Produces:
  - `ManifestEntry` = `{ char *type; char *source; char *targets; }` (`targets` may be NULL)
  - `Manifest` = `{ ManifestEntry *items; size_t count; size_t cap; }`
  - `void manifest_init(Manifest *)`, `void manifest_free(Manifest *)`
  - `int manifest_read(Manifest *, const char *path)` — 0 on success, non-0 on error (prints to stderr).

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_manifest.c`:

```c
#include "manifest.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>

TEST(test_manifest_file) {
    Manifest m;
    FILE *f = fopen("/tmp/rbtest_srclist", "w");
    fputs("# a comment\n"
          "\n"
          "dir  /src/gnumake-3.79   all\n"
          "dir /src/objc4-174\n"
          "   \n"
          "dir /src/foo # trailing comment\n", f);
    fclose(f);

    manifest_init(&m);
    CHECK_INT(manifest_read(&m, "/tmp/rbtest_srclist"), 0);
    CHECK_INT(m.count, 3);
    CHECK_STR(m.items[0].type, "dir");
    CHECK_STR(m.items[0].source, "/src/gnumake-3.79");
    CHECK_STR(m.items[0].targets, "all");
    CHECK_STR(m.items[1].source, "/src/objc4-174");
    CHECK(m.items[1].targets == 0);
    CHECK_STR(m.items[2].source, "/src/foo");
    manifest_free(&m);
    remove("/tmp/rbtest_srclist");
}

static void run_all(void) {
    RUN(test_manifest_file);
}

TEST_MAIN()
```

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_manifest`
Expected: FAIL — `manifest.h` not found.

- [ ] **Step 3: Write the header**

Create `src/rbuild-1/manifest.h`:

```c
#ifndef RBUILD_MANIFEST_H
#define RBUILD_MANIFEST_H

#include "strutil.h"

typedef struct {
    char *type;
    char *source;
    char *targets;   /* may be NULL */
} ManifestEntry;

typedef struct {
    ManifestEntry *items;
    size_t count;
    size_t cap;
} Manifest;

void manifest_init(Manifest *m);
void manifest_free(Manifest *m);
int manifest_read(Manifest *m, const char *path);

#endif
```

- [ ] **Step 4: Write the implementation**

Port notes (Manifest.pm:8-38): if `path` is a directory, push one entry per child with `type="dir"`, `source="<path>/<child>"` (skipping `.`/`..`). Otherwise open as a file; per line: `chomp`, delete from `#` to end-of-line, skip if blank/whitespace-only, `split` on whitespace into `type`/`source`/`targets`.

Create `src/rbuild-1/manifest.c`:

```c
#include "manifest.h"
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <dirent.h>

void manifest_init(Manifest *m) {
    m->cap = 8;
    m->count = 0;
    m->items = (ManifestEntry *) xmalloc(m->cap * sizeof(ManifestEntry));
}

void manifest_free(Manifest *m) {
    size_t i;
    for (i = 0; i < m->count; i++) {
        free(m->items[i].type);
        free(m->items[i].source);
        free(m->items[i].targets);
    }
    free(m->items);
    m->items = 0; m->count = 0; m->cap = 0;
}

static ManifestEntry *manifest_new(Manifest *m) {
    ManifestEntry *e;
    if (m->count == m->cap) {
        m->cap *= 2;
        m->items = (ManifestEntry *) xrealloc(m->items, m->cap * sizeof(ManifestEntry));
    }
    e = &m->items[m->count++];
    e->type = 0; e->source = 0; e->targets = 0;
    return e;
}

static int read_directory(Manifest *m, const char *dir) {
    DIR *d = opendir(dir);
    struct dirent *de;
    if (!d) { fprintf(stderr, "rbuild: unable to open \"%s\"\n", dir); return 1; }
    while ((de = readdir(d)) != 0) {
        ManifestEntry *e;
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        e = manifest_new(m);
        e->type = xstrdup("dir");
        e->source = path_join(dir, de->d_name);
    }
    closedir(d);
    return 0;
}

static int read_file(Manifest *m, const char *path) {
    FILE *f = fopen(path, "r");
    char line[4096];
    if (!f) { fprintf(stderr, "rbuild: unable to open \"%s\"\n", path); return 1; }
    while (fgets(line, sizeof(line), f) != 0) {
        char *hash;
        strlist toks;
        str_chomp(line);
        hash = strchr(line, '#');
        if (hash) *hash = '\0';
        strlist_init(&toks);
        str_split_ws(line, &toks);
        if (toks.count == 0) { strlist_free(&toks); continue; }
        {
            ManifestEntry *e = manifest_new(m);
            e->type = xstrdup(toks.items[0]);
            if (toks.count >= 2) e->source = xstrdup(toks.items[1]);
            else e->source = xstrdup("");
            if (toks.count >= 3) e->targets = xstrdup(toks.items[2]);
        }
        strlist_free(&toks);
    }
    fclose(f);
    return 0;
}

int manifest_read(Manifest *m, const char *path) {
    struct stat st;
    if (stat(path, &st) == 0 && S_ISDIR(st.st_mode))
        return read_directory(m, path);
    return read_file(m, path);
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_manifest && ./tests/test_manifest`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/manifest.h src/rbuild-1/manifest.c src/rbuild-1/tests/test_manifest.c
git commit -m "rbuild: manifest reader (file + directory)"
```

---

## Task 7: exec — subprocess runner, checkret, printcmd, dry-run

**Reference:** `Builder.pm:95-105` (`printcmd`), `Builder.pm:337-362` (`checkret`), all `system(...)` call sites.

**Files:**
- Create: `src/rbuild-1/exec.h`
- Create: `src/rbuild-1/exec.c`
- Test: extend `tests/test_strutil.c` is wrong scope — create `tests/test_exec.c` and register it.
- Modify: `src/rbuild-1/Makefile` (add `tests/test_exec` to `TESTS` and a build rule)

**Interfaces:**
- Consumes: `strutil`.
- Produces:
  - `extern int exec_dry_run;`
  - `void exec_printcmd(char *const argv[])` — prints args (quoting any containing whitespace), then newline. `argv` NULL-terminated.
  - `int exec_run(char *const argv[])` — fork/exec/waitpid; returns the raw wait status (like Perl `$?`), or `-1` on spawn failure. In dry-run, calls `exec_printcmd` and returns 0.
  - `int exec_runv(const char *arg0, ...)` — varargs convenience (NULL-terminated); builds argv and calls `exec_run`.
  - `char *exec_checkret(int status)` — malloc'd human string ("exited successfully" / "failed with status N" / "terminated by signal N[ (core dumped)]" / "stopped").
  - `int exec_check(int status)` — if `status==0` returns 0; else prints `exec_checkret` to stderr and returns 1.
  - `int exec_run_checked(char *const argv[])` — `exec_check(exec_run(argv))`.

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_exec.c`:

```c
#include "exec.h"
#include "test.h"
#include <stdlib.h>

TEST(test_checkret_strings) {
    char *a = exec_checkret(0);
    char *b = exec_checkret(2 << 8);      /* exit status 2 */
    CHECK_STR(a, "exited successfully");
    CHECK_STR(b, "failed with status 2");
    free(a); free(b);
}

TEST(test_run_true_false) {
    char *ok[] = { "true", 0 };
    char *bad[] = { "false", 0 };
    CHECK_INT(exec_run(ok), 0);
    CHECK(exec_run(bad) != 0);
}

TEST(test_dry_run) {
    char *cmd[] = { "false", 0 };
    exec_dry_run = 1;
    CHECK_INT(exec_run(cmd), 0);   /* not actually run */
    exec_dry_run = 0;
}

static void run_all(void) {
    RUN(test_checkret_strings);
    RUN(test_run_true_false);
    RUN(test_dry_run);
}

TEST_MAIN()
```

- [ ] **Step 2: Register the test and run to verify failure**

In `src/rbuild-1/Makefile`, add `tests/test_exec` to the `TESTS` list and add:

```make
tests/test_exec: tests/test_exec.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_exec.c $(LIBOBJS)
```

Run: `cd src/rbuild-1 && make tests/test_exec`
Expected: FAIL — `exec.h` not found.

- [ ] **Step 3: Write the header**

Create `src/rbuild-1/exec.h`:

```c
#ifndef RBUILD_EXEC_H
#define RBUILD_EXEC_H

extern int exec_dry_run;

void exec_printcmd(char *const argv[]);
int exec_run(char *const argv[]);
int exec_runv(const char *arg0, ...);
char *exec_checkret(int status);
int exec_check(int status);
int exec_run_checked(char *const argv[]);

#endif
```

- [ ] **Step 4: Write the implementation**

Port notes for `checkret` (Builder.pm:337-362): `status==0` → "exited successfully"; `lowbyte = status & 0xff`; if `lowbyte==0x7f` → "stopped"; `signal = lowbyte & 0177`; if signal → "terminated by signal N" + " (core dumped)" if `lowbyte & 0200`; else `exitstatus = (status>>8)&0xff` → "failed with status N". This decodes the raw `wait()` status word, so `exec_run` must return that raw word.

Create `src/rbuild-1/exec.c`:

```c
#include "exec.h"
#include "strutil.h"
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

int exec_dry_run = 0;

static int has_space(const char *s) {
    for (; *s; s++)
        if (*s == ' ' || *s == '\t' || *s == '\n') return 1;
    return 0;
}

void exec_printcmd(char *const argv[]) {
    int i;
    for (i = 0; argv[i]; i++) {
        if (has_space(argv[i])) printf("\"%s\" ", argv[i]);
        else printf("%s ", argv[i]);
    }
    printf("\n");
    fflush(stdout);
}

int exec_run(char *const argv[]) {
    pid_t pid;
    int status;

    if (exec_dry_run) {
        exec_printcmd(argv);
        return 0;
    }

    pid = fork();
    if (pid < 0) {
        fprintf(stderr, "rbuild: fork failed\n");
        return -1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        fprintf(stderr, "rbuild: exec \"%s\" failed\n", argv[0]);
        _exit(127);
    }
    if (waitpid(pid, &status, 0) < 0) return -1;
    return status;   /* raw wait status word */
}

int exec_runv(const char *arg0, ...) {
    strlist args;
    va_list ap;
    const char *a;
    int rc;
    char **argv;
    size_t i;

    strlist_init(&args);
    strlist_push(&args, arg0);
    va_start(ap, arg0);
    while ((a = va_arg(ap, const char *)) != 0) strlist_push(&args, a);
    va_end(ap);

    argv = (char **) xmalloc((args.count + 1) * sizeof(char *));
    for (i = 0; i < args.count; i++) argv[i] = args.items[i];
    argv[args.count] = 0;

    rc = exec_run(argv);
    free(argv);
    strlist_free(&args);
    return rc;
}

char *exec_checkret(int status) {
    int lowbyte, signal, exitstatus;
    char buf[64];

    if (status == 0) return xstrdup("exited successfully");

    lowbyte = status & 0xff;
    if (lowbyte == 0x7f) return xstrdup("stopped");

    signal = lowbyte & 0177;
    if (signal != 0) {
        sbuf s; char *out;
        sbuf_init(&s);
        sprintf(buf, "terminated by signal %d", signal);
        sbuf_puts(&s, buf);
        if (lowbyte & 0200) sbuf_puts(&s, " (core dumped)");
        out = sbuf_steal(&s);
        sbuf_free(&s);
        return out;
    }

    exitstatus = (status >> 8) & 0xff;
    sprintf(buf, "failed with status %d", exitstatus);
    return xstrdup(buf);
}

int exec_check(int status) {
    if (status == 0) return 0;
    {
        char *msg = exec_checkret(status);
        fprintf(stderr, "rbuild: %s\n", msg);
        free(msg);
    }
    return 1;
}

int exec_run_checked(char *const argv[]) {
    return exec_check(exec_run(argv));
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_exec && ./tests/test_exec`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/exec.h src/rbuild-1/exec.c src/rbuild-1/tests/test_exec.c src/rbuild-1/Makefile
git commit -m "rbuild: exec subprocess runner + checkret + dry-run"
```

---

## Task 8: pkginfo — write .PKGINFO and assemble .apk

**Reference:** spec "apk mapping"; replaces `Builder.pm` `dpkg-deb --build`.

**Files:**
- Create: `src/rbuild-1/pkginfo.h`
- Create: `src/rbuild-1/pkginfo.c`
- Test: `src/rbuild-1/tests/test_pkginfo.c`
- Modify: `src/rbuild-1/Makefile` (register `tests/test_pkginfo`)

**Interfaces:**
- Consumes: `package`, `exec`, `strutil`.
- Produces:
  - `int pkginfo_write(const Package *p, const char *path)` — write a `.PKGINFO` file at `path`. Emits `pkgname`, `pkgver` (= `package_canon_version`), `arch`, `pkgdesc`, `maintainer`, `origin`, and (when set) `provides`, `replaces`, and `builddepends` (space-separated join of `build_depends`). Returns 0 on success.
  - `int pkginfo_build_apk(const char *root_dir, const char *out_apk)` — `tar -C <root_dir> -cf - . | gzip -9 > <out_apk>` via `sh -c`. Returns 0 on success.

- [ ] **Step 1: Write the failing test**

Create `src/rbuild-1/tests/test_pkginfo.c`:

```c
#include "pkginfo.h"
#include "package.h"
#include "test.h"
#include <stdio.h>
#include <stdlib.h>

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

TEST(test_pkginfo_write) {
    Package p;
    char *out;
    package_init(&p);
    package_set(&p.package, "gnumake");
    package_set(&p.version, "3.79");
    package_set(&p.architecture, "universal-apple-rhapsody");
    package_set(&p.description, "GNU make");
    package_set(&p.maintainer, "M <m@x>");
    package_set(&p.source, "gnumake");
    strlist_push(&p.build_depends, "cc");
    strlist_push(&p.build_depends, "gnumake");
    p.has_build_depends = 1;

    CHECK_INT(pkginfo_write(&p, "/tmp/rbtest.PKGINFO"), 0);
    out = slurp("/tmp/rbtest.PKGINFO");
    CHECK(out != 0);
    CHECK(strstr(out, "pkgname = gnumake\n") != 0);
    CHECK(strstr(out, "pkgver = 3.79\n") != 0);
    CHECK(strstr(out, "arch = universal-apple-rhapsody\n") != 0);
    CHECK(strstr(out, "builddepends = cc gnumake\n") != 0);
    package_free(&p);
    remove("/tmp/rbtest.PKGINFO");
}

static void run_all(void) {
    RUN(test_pkginfo_write);
}

TEST_MAIN()
```

- [ ] **Step 2: Register and run to verify failure**

Add `tests/test_pkginfo` to `TESTS` in the Makefile plus:

```make
tests/test_pkginfo: tests/test_pkginfo.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_pkginfo.c $(LIBOBJS)
```

Run: `cd src/rbuild-1 && make tests/test_pkginfo`
Expected: FAIL — `pkginfo.h` not found.

- [ ] **Step 3: Write the header**

Create `src/rbuild-1/pkginfo.h`:

```c
#ifndef RBUILD_PKGINFO_H
#define RBUILD_PKGINFO_H

#include "package.h"

int pkginfo_write(const Package *p, const char *path);
int pkginfo_build_apk(const char *root_dir, const char *out_apk);

#endif
```

- [ ] **Step 4: Write the implementation**

Create `src/rbuild-1/pkginfo.c`:

```c
#include "pkginfo.h"
#include "strutil.h"
#include "exec.h"
#include <stdio.h>

static void emit(FILE *f, const char *key, const char *value) {
    if (value) fprintf(f, "%s = %s\n", key, value);
}

int pkginfo_write(const Package *p, const char *path) {
    FILE *f = fopen(path, "w");
    char *ver;
    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s for writing\n", path);
        return 1;
    }
    ver = package_canon_version(p);
    emit(f, "pkgname", p->package);
    emit(f, "pkgver", ver);
    emit(f, "arch", p->architecture);
    emit(f, "pkgdesc", p->description);
    emit(f, "maintainer", p->maintainer);
    emit(f, "origin", p->source);
    emit(f, "provides", p->provides);
    emit(f, "replaces", p->replaces);
    if (p->has_build_depends) {
        sbuf s;
        char *joined;
        size_t i;
        sbuf_init(&s);
        for (i = 0; i < p->build_depends.count; i++) {
            if (i) sbuf_putc(&s, ' ');
            sbuf_puts(&s, p->build_depends.items[i]);
        }
        joined = sbuf_steal(&s);
        emit(f, "builddepends", joined);
        free(joined);
        sbuf_free(&s);
    }
    free(ver);
    fclose(f);
    return 0;
}

int pkginfo_build_apk(const char *root_dir, const char *out_apk) {
    /* tar -C <root_dir> -cf - . | gzip -9 > <out_apk> */
    char *cmd = str_cats("tar -C '", root_dir, "' -cf - . | gzip -9 > '",
                         out_apk, "'", (char *)0);
    char *argv[4];
    int rc;
    argv[0] = "sh"; argv[1] = "-c"; argv[2] = cmd; argv[3] = 0;
    rc = exec_run_checked(argv);
    free(cmd);
    return rc;
}
```

> **Note:** `root_dir`/`out_apk` are internal, non-user paths (build roots), so single-quoting for `sh -c` is sufficient here; do not extend this pattern to untrusted input.

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_pkginfo && ./tests/test_pkginfo`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/pkginfo.h src/rbuild-1/pkginfo.c src/rbuild-1/tests/test_pkginfo.c src/rbuild-1/Makefile
git commit -m "rbuild: pkginfo .PKGINFO writer + .apk assembler"
```

---

## Task 9: builder — getparams / canonparams / chrootparams

**Reference:** `Builder.pm:139-239` (`canonparams`, `chrootparams`, `getparams`).

**Files:**
- Modify: `src/rbuild-1/builder.h` (declarations)
- Modify: `src/rbuild-1/builder.c` (implementations)
- Modify: `src/rbuild-1/tests/test_builder.c` (tests)

**Interfaces:**
- Produces:
  - `void builder_getparams(const char *projectname, Params *out)` — fills `out` from `BUILDIT_DIR` (default `/private/tmp/roots`) and per-root env overrides, exactly as Builder.pm:178-239. `out` must be `params_init`'d by the caller; this function assigns malloc'd strings to each field.
  - `void builder_canonparams(Params *p, const char *cwd)` — for each path field that is non-NULL and does not begin with `/`, replace it with `cwd + "/" + value` (Builder.pm:139-154). `SRCDIR`/`PACKAGEDIR` included.
  - `void builder_chrootparams(const Params *in, const char *buildroot, Params *out)` — strip trailing slashes from `buildroot`; set each root in `out` to `buildroot + in->ROOT`; `out->BUILDROOT = buildroot` (Builder.pm:156-176).

- [ ] **Step 1: Add failing tests**

Append to `tests/test_builder.c` (add `RUN`s):

```c
TEST(test_getparams_defaults) {
    Params p;
    /* Ensure no env overrides interfere. */
    unsetenv("BUILDIT_DIR"); unsetenv("BUILDROOT"); unsetenv("SRCROOT");
    unsetenv("OBJROOT"); unsetenv("SYMROOT"); unsetenv("DSTROOT");
    unsetenv("HDRROOT"); unsetenv("LIBCOBJROOT"); unsetenv("LOGFILE");
    unsetenv("SUBLIBROOTS"); unsetenv("PACKAGEROOT");
    params_init(&p);
    builder_getparams("foo-1.0", &p);
    CHECK_STR(p.BUILDROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.root");
    CHECK_STR(p.SRCROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0");
    CHECK_STR(p.OBJROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.obj");
    CHECK_STR(p.DSTROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.dst");
    CHECK_STR(p.HDRROOT, "/private/tmp/roots/foo-1.0.roots/foo-1.0.hdr");
    CHECK_STR(p.SUBLIBROOTS, "/usr/local/lib/objs");
    params_free(&p);
}

TEST(test_canonparams) {
    Params p;
    params_init(&p);
    p.SRCROOT = xstrdup("relative/src");
    p.OBJROOT = xstrdup("/already/abs");
    builder_canonparams(&p, "/cwd");
    CHECK_STR(p.SRCROOT, "/cwd/relative/src");
    CHECK_STR(p.OBJROOT, "/already/abs");
    params_free(&p);
}

TEST(test_chrootparams) {
    Params in, out;
    params_init(&in); params_init(&out);
    in.SRCROOT = xstrdup("/a/src");
    in.DSTROOT = xstrdup("/a/dst");
    builder_chrootparams(&in, "/build/", &out);
    CHECK_STR(out.SRCROOT, "/build/a/src");
    CHECK_STR(out.DSTROOT, "/build/a/dst");
    CHECK_STR(out.BUILDROOT, "/build");
    params_free(&in); params_free(&out);
}
```

Add to `run_all`:
```c
    RUN(test_getparams_defaults);
    RUN(test_canonparams);
    RUN(test_chrootparams);
```

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_builder`
Expected: FAIL — undefined references.

- [ ] **Step 3: Add declarations**

Add to `builder.h`:

```c
void builder_getparams(const char *projectname, Params *out);
void builder_canonparams(Params *p, const char *cwd);
void builder_chrootparams(const Params *in, const char *buildroot, Params *out);
```

- [ ] **Step 4: Add implementations**

Append to `builder.c` (add `#include <stdlib.h>` for `getenv` if not present):

```c
/* Return env value if set and non-empty, else NULL (mirrors Perl
   defined($ENV{X} && $ENV{X})). */
static const char *env_or_null(const char *name) {
    const char *v = getenv(name);
    if (v && v[0]) return v;
    return 0;
}

static char *default_root(const char *buildroot, const char *project,
                          const char *suffix) {
    /* "<buildroot>/<project>.roots/<project><suffix>" */
    return str_cats(buildroot, "/", project, ".roots/", project, suffix, (char *)0);
}

void builder_getparams(const char *project, Params *out) {
    const char *buildroot = env_or_null("BUILDIT_DIR");
    const char *ov;
    if (!buildroot) buildroot = "/private/tmp/roots";

    out->BUILDROOT = default_root(buildroot, project, ".root");
    if ((ov = env_or_null("BUILDROOT")) != 0) { free(out->BUILDROOT); out->BUILDROOT = xstrdup(ov); }

    out->SRCROOT = default_root(buildroot, project, "");
    if ((ov = env_or_null("SRCROOT")) != 0) { free(out->SRCROOT); out->SRCROOT = xstrdup(ov); }

    out->OBJROOT = default_root(buildroot, project, ".obj");
    if ((ov = env_or_null("OBJROOT")) != 0) { free(out->OBJROOT); out->OBJROOT = xstrdup(ov); }

    out->SYMROOT = default_root(buildroot, project, ".sym");
    if ((ov = env_or_null("SYMROOT")) != 0) { free(out->SYMROOT); out->SYMROOT = xstrdup(ov); }

    out->DSTROOT = default_root(buildroot, project, ".dst");
    if ((ov = env_or_null("DSTROOT")) != 0) { free(out->DSTROOT); out->DSTROOT = xstrdup(ov); }

    out->HDRROOT = default_root(buildroot, project, ".hdr");
    if ((ov = env_or_null("HDRROOT")) != 0) { free(out->HDRROOT); out->HDRROOT = xstrdup(ov); }

    out->LIBCOBJROOT = default_root(buildroot, project, ".cobj");
    if ((ov = env_or_null("LIBCOBJROOT")) != 0) { free(out->LIBCOBJROOT); out->LIBCOBJROOT = xstrdup(ov); }

    out->LOGFILE = default_root(buildroot, project, ".log");
    if ((ov = env_or_null("LOGFILE")) != 0) { free(out->LOGFILE); out->LOGFILE = xstrdup(ov); }

    out->SUBLIBROOTS = xstrdup("/usr/local/lib/objs");
    if ((ov = env_or_null("SUBLIBROOTS")) != 0) { free(out->SUBLIBROOTS); out->SUBLIBROOTS = xstrdup(ov); }

    out->PACKAGEROOT = default_root(buildroot, project, ".pkg");
    if ((ov = env_or_null("PACKAGEROOT")) != 0) { free(out->PACKAGEROOT); out->PACKAGEROOT = xstrdup(ov); }
}

static void canon_one(char **field, const char *cwd) {
    if (*field && (*field)[0] != '/') {
        char *joined = path_join(cwd, *field);
        free(*field);
        *field = joined;
    }
}

void builder_canonparams(Params *p, const char *cwd) {
    canon_one(&p->BUILDROOT, cwd);
    canon_one(&p->SRCROOT, cwd);
    canon_one(&p->OBJROOT, cwd);
    canon_one(&p->SYMROOT, cwd);
    canon_one(&p->DSTROOT, cwd);
    canon_one(&p->HDRROOT, cwd);
    canon_one(&p->LIBCOBJROOT, cwd);
    canon_one(&p->PACKAGEROOT, cwd);
    canon_one(&p->LOGFILE, cwd);
    canon_one(&p->SUBLIBROOTS, cwd);
    canon_one(&p->SRCDIR, cwd);
    canon_one(&p->PACKAGEDIR, cwd);
}

static char *prefixed(const char *buildroot, const char *path) {
    if (!path) return 0;
    return str_cats(buildroot, path, (char *)0);
}

void builder_chrootparams(const Params *in, const char *buildroot, Params *out) {
    char *br = xstrdup(buildroot);
    size_t n = strlen(br);
    while (n > 0 && br[n - 1] == '/') br[--n] = '\0';

    out->SRCROOT = prefixed(br, in->SRCROOT);
    out->OBJROOT = prefixed(br, in->OBJROOT);
    out->SYMROOT = prefixed(br, in->SYMROOT);
    out->DSTROOT = prefixed(br, in->DSTROOT);
    out->HDRROOT = prefixed(br, in->HDRROOT);
    out->LIBCOBJROOT = prefixed(br, in->LIBCOBJROOT);
    out->LOGFILE = prefixed(br, in->LOGFILE);
    out->SUBLIBROOTS = prefixed(br, in->SUBLIBROOTS);
    out->PACKAGEROOT = prefixed(br, in->PACKAGEROOT);
    out->BUILDROOT = xstrdup(br);
    free(br);
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder`
Expected: PASS — `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: builder getparams/canonparams/chrootparams"
```

---

## Task 10: builder — buildflags / buildcmd

**Reference:** `Builder.pm:36-93,107-130` (`@cflags`, `$baseflags`, `buildflags`, `buildcmd`).

**Files:**
- Modify: `src/rbuild-1/builder.h`, `src/rbuild-1/builder.c`, `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Produces:
  - `void builder_buildflags(const Params *params, const char *target, strlist *out)` — pushes `KEY=VALUE` strings for the full base flag set with `SRCROOT`/`OBJROOT`/`SYMROOT`/`SUBLIBROOTS`/`DSTROOT` filled from `params` (DSTROOT = HDRROOT when `target=="installhdrs"`, else DSTROOT), and the fixed `RC_CFLAGS`/`RC_ARCHS`/`RC_i386`/`RC_ppc` overrides. Order need not match Perl (Perl iterates a hash, unordered); the trace test normalizes flag order.
  - `void builder_buildcmd(const Params *params, const char *srcroot, const char *target, strlist *out)` — builds the argv list: `chroot <BUILDROOT> make -w -C <srcroot>` then each flag then `<target>`. (Note: Perl uses `bparams->SRCROOT` for `-C`; pass the build-params SRCROOT as `srcroot`.)

- [ ] **Step 1: Add failing test**

Append to `tests/test_builder.c` (add `RUN`):

```c
static int list_has(const strlist *l, const char *s) {
    size_t i;
    for (i = 0; i < l->count; i++) if (strcmp(l->items[i], s) == 0) return 1;
    return 0;
}

TEST(test_buildflags) {
    Params p;
    strlist f;
    params_init(&p);
    p.SRCROOT = xstrdup("/s"); p.OBJROOT = xstrdup("/o");
    p.SYMROOT = xstrdup("/y"); p.DSTROOT = xstrdup("/d");
    p.HDRROOT = xstrdup("/h"); p.SUBLIBROOTS = xstrdup("/objs");
    strlist_init(&f);
    builder_buildflags(&p, "install", &f);
    CHECK(list_has(&f, "SRCROOT=/s"));
    CHECK(list_has(&f, "DSTROOT=/d"));
    CHECK(list_has(&f, "RC_ARCHS=i386 ppc"));
    CHECK(list_has(&f, "RC_i386=YES"));
    strlist_free(&f);

    strlist_init(&f);
    builder_buildflags(&p, "installhdrs", &f);
    CHECK(list_has(&f, "DSTROOT=/h"));   /* headers target uses HDRROOT */
    strlist_free(&f);
    params_free(&p);
}
```

Add `RUN(test_buildflags);` and ensure `#include <string.h>` is present in the test (it is, via `test.h`). Add `list_has` once (it is defined above; if already added earlier in the file, do not duplicate).

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_builder`
Expected: FAIL — `builder_buildflags` undefined.

- [ ] **Step 3: Add declarations**

Add to `builder.h`:

```c
void builder_buildflags(const Params *params, const char *target, strlist *out);
void builder_buildcmd(const Params *params, const char *srcroot,
                      const char *target, strlist *out);
```

- [ ] **Step 4: Add implementation**

Port notes: `@cflags` (Builder.pm:36-53) is the fixed `-D` list; `RC_CFLAGS` (Builder.pm:124) = `"-arch i386 -arch ppc " . liststring(@cflags)` where `liststring` prepends a space before each element. `$baseflags` (Builder.pm:55-78) is the constant KEY=VALUE set; `buildflags` overrides SRCROOT/OBJROOT/SYMROOT/SUBLIBROOTS/DSTROOT and the RC_* arch flags.

Append to `builder.c`:

```c
static const char *cflags[] = {
    "-Dunix", "-D__unix", "-D__unix__",
    "-DNX_COMPILER_RELEASE_3_0=300", "-DNX_COMPILER_RELEASE_3_1=310",
    "-DNX_COMPILER_RELEASE_3_2=320", "-DNX_COMPILER_RELEASE_3_3=330",
    "-DNX_CURRENT_COMPILER_RELEASE=520",
    "-DNS_TARGET=52", "-DNS_TARGET_MAJOR=5", "-DNS_TARGET_MINOR=2",
    "-DNeXT", "-D__NeXT", "-D__NeXT__", "-D_NEXT_SOURCE", 0
};

/* baseflags as {key, value} pairs (value may be ""). */
static const char *baseflags[][2] = {
    { "RC_JASPER", "YES" },
    { "RC_ARCHS", "i386 ppc" },
    { "RC_CFLAGS", "" },
    { "RC_hppa", "" }, { "RC_i386", "" }, { "RC_m68k", "" },
    { "RC_ppc", "" }, { "RC_sparc", "" },
    { "RC_KANJI", "" }, { "JAPANESE", "" },
    { "RC_OS", "teflon" },
    { "CURRENT_PROJECT_VERSION", "1" },
    { "RC_RELEASE", "Rhapsody" },
    { "NEXT_ROOT", "" },
    { "GnuNoInstallSource", "YES" },
    { "Install_Source", "" },
    { 0, 0 }
};

static void push_kv(strlist *out, const char *k, const char *v) {
    char *s = str_cats(k, "=", v ? v : "", (char *)0);
    strlist_push_owned(out, s);
}

void builder_buildflags(const Params *params, const char *target, strlist *out) {
    int i;
    char *rc_cflags;
    sbuf s;

    /* Fixed base flags, but skip the ones we override below. */
    for (i = 0; baseflags[i][0]; i++) {
        const char *k = baseflags[i][0];
        if (strcmp(k, "RC_CFLAGS") == 0 || strcmp(k, "RC_ARCHS") == 0 ||
            strcmp(k, "RC_i386") == 0 || strcmp(k, "RC_ppc") == 0)
            continue;
        push_kv(out, k, baseflags[i][1]);
    }

    /* Path roots. */
    push_kv(out, "SRCROOT", params->SRCROOT);
    push_kv(out, "OBJROOT", params->OBJROOT);
    push_kv(out, "SYMROOT", params->SYMROOT);
    push_kv(out, "SUBLIBROOTS", params->SUBLIBROOTS);
    if (strcmp(target, "installhdrs") == 0)
        push_kv(out, "DSTROOT", params->HDRROOT);
    else
        push_kv(out, "DSTROOT", params->DSTROOT);

    /* RC_CFLAGS = "-arch i386 -arch ppc" + " -D..." for each cflag. */
    sbuf_init(&s);
    sbuf_puts(&s, "-arch i386 -arch ppc");
    for (i = 0; cflags[i]; i++) { sbuf_putc(&s, ' '); sbuf_puts(&s, cflags[i]); }
    rc_cflags = sbuf_steal(&s);
    sbuf_free(&s);
    push_kv(out, "RC_CFLAGS", rc_cflags);
    free(rc_cflags);

    push_kv(out, "RC_ARCHS", "i386 ppc");
    push_kv(out, "RC_i386", "YES");
    push_kv(out, "RC_ppc", "YES");
}

void builder_buildcmd(const Params *params, const char *srcroot,
                      const char *target, strlist *out) {
    size_t i;
    strlist flags;
    strlist_push(out, "chroot");
    strlist_push(out, params->BUILDROOT);
    strlist_push(out, "make");
    strlist_push(out, "-w");
    strlist_push(out, "-C");
    strlist_push(out, srcroot);
    strlist_init(&flags);
    builder_buildflags(params, target, &flags);
    for (i = 0; i < flags.count; i++) strlist_push(out, flags.items[i]);
    strlist_free(&flags);
    strlist_push(out, target);
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: builder buildflags/buildcmd"
```

---

## Task 11: builder — scan (readcontrol / makecontrol / scandir)

**Reference:** `Builder.pm:280-335` (`makecontrol`, `readcontrol`), `Builder.pm:450-481` (`scandir`), `Builder.pm:723-734` (`scan`).

**Files:**
- Modify: `src/rbuild-1/builder.h`, `src/rbuild-1/builder.c`, `src/rbuild-1/tests/test_builder.c`

**Interfaces:**
- Produces:
  - `int builder_scan_dir(const char *source, Package *pkg, Params *params)` — fills `pkg` and `params` for a `--dir` source. Reads `<source>/dpkg/control` if present (via `package_parse`) else synthesizes a default (`makecontrol`); sets `source` field to `pbase`; appends `-<revision>` to `version` when a revision exists; computes `params` via `builder_getparams(pkg->package + "-" + version)`. Returns 0 on success, non-0 on error. `pkg` and `params` must be `_init`'d by the caller.
  - `int builder_scan(const char *type, const char *source, Package *pkg, Params *params)` — dispatch: `type=="dir"` → `builder_scan_dir`; anything else → error to stderr, return non-0.

- [ ] **Step 1: Add failing test**

Append to `tests/test_builder.c` (add `RUN`):

```c
TEST(test_scan_dir) {
    Package pkg;
    Params params;
    int rc;
    system("rm -rf /tmp/rbtest_src && mkdir -p /tmp/rbtest_src/objc4-174/dpkg");
    {
        FILE *f = fopen("/tmp/rbtest_src/objc4-174/dpkg/control", "w");
        fputs("Package: objc4\nVersion: 174\n"
              "Description: Objective-C runtime\n"
              "Build-Depends: build-base\n", f);
        fclose(f);
    }
    package_init(&pkg);
    params_init(&params);
    rc = builder_scan_dir("/tmp/rbtest_src/objc4-174", &pkg, &params);
    CHECK_INT(rc, 0);
    CHECK_STR(pkg.package, "objc4");
    CHECK_STR(pkg.version, "174-174");   /* base version + "-" + revision */
    CHECK_STR(pkg.source, "objc4");
    CHECK(params.SRCROOT != 0);
    package_free(&pkg);
    params_free(&params);
    system("rm -rf /tmp/rbtest_src");
}
```

> Note the `174-174`: the control's `Version: 174` gets `"-" . revision` appended, and `dir2name("objc4-174")` yields revision `174`. This matches the Perl (`scandir` Builder.pm:472-477). Confirm against the Perl if surprised.

Add `RUN(test_scan_dir);`.

- [ ] **Step 2: Run to verify failure**

Run: `cd src/rbuild-1 && make tests/test_builder`
Expected: FAIL — `builder_scan_dir` undefined.

- [ ] **Step 3: Add declarations**

Add to `builder.h`:

```c
int builder_scan_dir(const char *source, Package *pkg, Params *params);
int builder_scan(const char *type, const char *source, Package *pkg, Params *params);
```

- [ ] **Step 4: Add implementation**

Port notes:
- `makecontrol` (Builder.pm:280-295): default package with `version="0"`, arch `universal-apple-rhapsody`, source=package, default description/maintainer, `build-depends=['build-base']`.
- `readcontrol` (Builder.pm:297-335): parse control text; require `package` and `version`; default description/maintainer when absent; set arch and `source=package`.
- `scandir` (Builder.pm:450-481): `dir2name`; try `<src>/dpkg/control` → readcontrol, else makecontrol; set `source=pbase`; `version = version + "-" + revision` when revision defined; `params = getparams(package + "-" + version)`.

Append to `builder.c` (add `#include "pkginfo.h"` is not needed; add `#include <stdio.h>` already present):

```c
static const char *DEFAULT_DESC = "No description available.";
static const char *DEFAULT_MAINT =
    "Anonymous <darwin-development@public.lists.apple.com>";
static const char *ARCH = "universal-apple-rhapsody";

static void makecontrol(Package *pkg, const char *pname) {
    package_set(&pkg->package, pname);
    package_set(&pkg->version, "0");
    package_set(&pkg->architecture, ARCH);
    package_set(&pkg->source, pname);
    package_set(&pkg->description, DEFAULT_DESC);
    package_set(&pkg->maintainer, DEFAULT_MAINT);
    strlist_free(&pkg->build_depends);
    strlist_init(&pkg->build_depends);
    strlist_push(&pkg->build_depends, "build-base");
    pkg->has_build_depends = 1;
}

/* Read <path> into a string; returns malloc'd or NULL. */
static char *slurp_file(const char *path) {
    FILE *f = fopen(path, "r");
    sbuf s;
    char buf[1024];
    size_t n;
    char *out;
    if (!f) return 0;
    sbuf_init(&s);
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) sbuf_putn(&s, buf, n);
    fclose(f);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

/* Returns 0 and fills pkg on success; 1 if control missing/invalid. */
static int readcontrol(Package *pkg, const char *control_path) {
    char *data = slurp_file(control_path);
    if (!data) return 1;
    package_parse(pkg, data);
    free(data);
    if (!pkg->package) {
        fprintf(stderr, "error: package file does not contain 'Package:' entry\n");
        return 1;
    }
    if (!pkg->version) {
        fprintf(stderr, "error: package file does not contain 'Version:' entry\n");
        return 1;
    }
    if (!pkg->description) package_set(&pkg->description, DEFAULT_DESC);
    if (!pkg->maintainer) package_set(&pkg->maintainer, DEFAULT_MAINT);
    package_set(&pkg->architecture, ARCH);
    package_set(&pkg->source, pkg->package);
    return 0;
}

int builder_scan_dir(const char *source, Package *pkg, Params *params) {
    char *pbase = 0, *pname = 0, *rev = 0;
    char *control_path;
    char *projname;

    builder_dir2name(source, &pbase, &pname, &rev);

    control_path = str_cats(source, "/dpkg/control", (char *)0);
    if (readcontrol(pkg, control_path) != 0) {
        /* reset any partial parse and synthesize default */
        package_free(pkg);
        package_init(pkg);
        makecontrol(pkg, pname);
    }
    free(control_path);

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

int builder_scan(const char *type, const char *source,
                 Package *pkg, Params *params) {
    if (strcmp(type, "dir") == 0)
        return builder_scan_dir(source, pkg, params);
    fprintf(stderr, "rbuild: invalid source type \"%s\"\n", type);
    return 1;
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: builder scan (readcontrol/makecontrol/scandir)"
```

---

## Task 12: builder — makeroot (dependency install)

**Reference:** `Builder.pm:619-721` (`@basedeps`, `makeroot`).

**Files:**
- Modify: `src/rbuild-1/builder.h`, `src/rbuild-1/builder.c`

This task has no cheap unit test (it does directory + subprocess I/O); it is verified by the trace test (Task 17) and by compilation here. Implement carefully against the Perl.

**Interfaces:**
- Produces:
  - `int builder_makeroot(const Package *pkg, const char *buildroot, const strlist *repository)` — resolves build-deps (expanding the `build-base` meta-dep to `@basedeps`), extracts each not-already-present dep into `buildroot`, and writes the `<buildroot>/var/adm/package-list` tracking file. Returns 0 on success, non-0 on error.
  - Internal helper: uses `builder_resolve_dependency` and, in place of the Perl `dpkg-deb -x`, extracts via `apk` — see note.

**apk extraction note:** the Perl runs `dpkg-deb -x <debfile> <buildroot>`. For apk, extract the package payload into `buildroot`. Since an `.apk` is a gzipped tar, extract with `sh -c "gzip -dc '<apk>' | tar -C '<buildroot>' -xf -"` (this also unpacks the `.PKGINFO` member into `buildroot`; acceptable for a build root, matching how `dpkg-deb -x` leaves no control files but here `.PKGINFO` is harmless). Document this as the apk analog of `dpkg-deb -x`.

- [ ] **Step 1: Add declaration**

Add to `builder.h`:

```c
int builder_makeroot(const Package *pkg, const char *buildroot,
                     const strlist *repository);
```

- [ ] **Step 2: Add implementation**

Port notes: `@basedeps` (Builder.pm:619-644) is the fixed base dependency list. `makeroot` (Builder.pm:646-721): deps = pkg build-depends or `@basedeps` if none; build a set, expanding `build-base` → all of `@basedeps`; resolve each to a `.apk`; derive `debname` = basename without `.apk`; read existing `<buildroot>/var/adm/package-list` into a set; for each dep not already present, extract into buildroot; `mkdir -p <buildroot>/var/adm`; write the new package-list.

Append to `builder.c`:

```c
static const char *basedeps[] = {
    "cc", "cctools", "gnumake",
    "pb-makefiles", "coreosmakefiles", "project-makefiles",
    "zsh", "tcsh",
    "file-cmds", "text-cmds", "shell-cmds", "developer-cmds",
    "awk", "grep", "gnutar",
    "libsystem", "libc-hdrs",
    "architecture-hdrs", "kernel-hdrs",
    "csu", "objc4-hdrs",
    "files",
    "basic-cmds", "bootstrap-cmds", "system-cmds",
    0
};

/* strlist "set" helpers (linear; lists are small). */
static int set_has(const strlist *l, const char *s) {
    size_t i;
    for (i = 0; i < l->count; i++) if (strcmp(l->items[i], s) == 0) return 1;
    return 0;
}
static void set_add(strlist *l, const char *s) {
    if (!set_has(l, s)) strlist_push(l, s);
}

/* basename without ".apk" suffix: "/a/b/foo-1.0.apk" -> "foo-1.0" */
static char *deb_to_name(const char *path) {
    const char *slash = strrchr(path, '/');
    const char *base = slash ? slash + 1 : path;
    char *out = xstrdup(base);
    size_t n = strlen(out);
    if (n >= 4 && strcmp(out + n - 4, ".apk") == 0) out[n - 4] = '\0';
    return out;
}

static int apk_extract(const char *apkfile, const char *buildroot) {
    char *cmd = str_cats("gzip -dc '", apkfile, "' | tar -C '",
                         buildroot, "' -xf -", (char *)0);
    char *argv[4];
    int rc;
    argv[0] = "sh"; argv[1] = "-c"; argv[2] = cmd; argv[3] = 0;
    rc = exec_run_checked(argv);
    free(cmd);
    return rc;
}

int builder_makeroot(const Package *pkg, const char *buildroot,
                     const strlist *repository) {
    strlist deps;       /* expanded, deduped dependency names */
    strlist depnames;   /* resolved package basenames (no .apk) */
    strlist depfiles;   /* resolved full paths, parallel to depnames */
    strlist curdeps;    /* already-installed names from package-list */
    size_t i;
    char *listpath;
    char *admdir;
    FILE *f;
    int rc = 0;

    strlist_init(&deps);
    strlist_init(&depnames);
    strlist_init(&depfiles);
    strlist_init(&curdeps);

    printf("Building build root:\n");
    fflush(stdout);

    /* Expand build-depends (or basedeps) into a deduped set. */
    if (pkg->has_build_depends && pkg->build_depends.count > 0) {
        for (i = 0; i < pkg->build_depends.count; i++) {
            const char *d = pkg->build_depends.items[i];
            if (strcmp(d, "build-base") == 0) {
                int j;
                for (j = 0; basedeps[j]; j++) set_add(&deps, basedeps[j]);
            } else {
                set_add(&deps, d);
            }
        }
    } else {
        int j;
        for (j = 0; basedeps[j]; j++) set_add(&deps, basedeps[j]);
    }

    /* Resolve each dep to a package file. */
    for (i = 0; i < deps.count; i++) {
        char *file = builder_resolve_dependency(deps.items[i], repository);
        char *name;
        if (!file) {
            fprintf(stderr, "rbuild: unable to find dependency for \"%s\"\n",
                    deps.items[i]);
            rc = 1;
            goto cleanup;
        }
        name = deb_to_name(file);
        strlist_push_owned(&depnames, name);
        strlist_push_owned(&depfiles, file);
    }

    /* Read existing package-list. */
    listpath = str_cats(buildroot, "/var/adm/package-list", (char *)0);
    f = fopen(listpath, "r");
    if (f) {
        char line[1024];
        while (fgets(line, sizeof(line), f) != 0) {
            str_chomp(line);
            if (line[0]) set_add(&curdeps, line);
        }
        fclose(f);
    }

    /* Install any dep not already present. */
    for (i = 0; i < depnames.count; i++) {
        if (set_has(&curdeps, depnames.items[i])) {
            printf("\talready have %s\n", depfiles.items[i]);
        } else {
            printf("\tinstalling %s\n", depfiles.items[i]);
            fflush(stdout);
            if (apk_extract(depfiles.items[i], buildroot) != 0) {
                rc = 1;
                free(listpath);
                goto cleanup;
            }
        }
    }

    /* mkdir -p <buildroot>/var/adm and rewrite package-list. */
    admdir = str_cats(buildroot, "/var/adm", (char *)0);
    if (exec_runv("mkdir", "-p", admdir, (char *)0) != 0) {
        rc = 1; free(admdir); free(listpath); goto cleanup;
    }
    free(admdir);

    f = fopen(listpath, "w");
    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s\n", listpath);
        rc = 1; free(listpath); goto cleanup;
    }
    for (i = 0; i < depnames.count; i++)
        fprintf(f, "%s\n", depnames.items[i]);
    fclose(f);
    free(listpath);

cleanup:
    strlist_free(&deps);
    strlist_free(&depnames);
    strlist_free(&depfiles);
    strlist_free(&curdeps);
    return rc;
}
```

- [ ] **Step 3: Compile-check**

Run: `cd src/rbuild-1 && make builder.o`
Expected: compiles clean (no warnings from `-Wall -pedantic`).

- [ ] **Step 4: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c
git commit -m "rbuild: builder makeroot (dependency install via apk extract)"
```

---

## Task 13: builder — setupdirs (mkdir roots + makeroot + rsync source)

**Reference:** `Builder.pm:736-776` (`setupdirs`).

**Files:**
- Modify: `src/rbuild-1/builder.h`, `src/rbuild-1/builder.c`

Verified by compilation + trace test.

**Interfaces:**
- Produces:
  - `int builder_setupdirs(const Package *pkg, const Params *params, const char *srcname, const char *srctype, const strlist *repository)` — `mkdir -p` OBJROOT/SYMROOT/DSTROOT/HDRROOT/PACKAGEROOT/BUILDROOT; `builder_makeroot`; for `srctype=="dir"`, `mkdir -p SRCROOT` then rsync `<SRCDIR>` into SRCROOT excluding VCS dirs. Returns 0 on success. (CVS branch dropped.)

- [ ] **Step 1: Add declaration**

Add to `builder.h`:

```c
int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository);
```

- [ ] **Step 2: Add implementation**

Port notes (Builder.pm:736-776): six `mkdir -p` of the roots (each checked); `makeroot`; then for `dir`: `mkdir -p SRCROOT`, and `sh -c "(cd <SRCDIR> && rsync -avr . --exclude=CVS/ --exclude=.svn/ --exclude=.git/ <SRCROOT>)"`. Use `params->SRCDIR` (set by `build()` before calling).

Append to `builder.c`:

```c
static int mkdirp(const char *path) {
    return exec_runv("mkdir", "-p", path, (char *)0);
}

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

    if (strcmp(srctype, "dir") == 0) {
        char *cmd;
        char *argv[4];
        int rc;
        if (exec_check(mkdirp(params->SRCROOT))) return 1;
        cmd = str_cats("(cd '", params->SRCDIR,
                       "' && rsync -avr . --exclude=CVS/ --exclude=.svn/ "
                       "--exclude=.git/ '", params->SRCROOT, "')", (char *)0);
        argv[0] = "sh"; argv[1] = "-c"; argv[2] = cmd; argv[3] = 0;
        exec_printcmd(argv);
        rc = exec_run_checked(argv);
        free(cmd);
        if (rc) return 1;
    } else {
        fprintf(stderr, "rbuild: unknown source type %s\n", srctype);
        return 1;
    }
    return 0;
}
```

- [ ] **Step 3: Compile-check**

Run: `cd src/rbuild-1 && make builder.o`
Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c
git commit -m "rbuild: builder setupdirs (mkdir + makeroot + rsync)"
```

---

## Task 14: builder — buildpackage subroutine (produce one .apk) + object harvest

**Reference:** `Builder.pm:364-448` (`buildpackage`), `Builder.pm:778-785` (`findobjs`).

**Files:**
- Modify: `src/rbuild-1/builder.h`, `src/rbuild-1/builder.c`

Verified by compilation + trace test.

**Interfaces:**
- Produces:
  - `int builder_buildpackage(const Package *spkg, const Params *params, const char *target)` — `target` ∈ {`binary`,`headers`,`objects`,`local`}. Chooses the dstroot per target; adjusts the package name/provides/replaces; skips empty dstroots; copies dpkg maintainer scripts for `binary`; writes `.PKGINFO`; assembles the `.apk` into `params->PACKAGEDIR`. `local` returns 0 immediately. Returns 0 on success.
  - `int builder_harvest_objects(const Package *pkg, const Params *params, const Params *bparams)` — the `dynamic_obj` File::Find pass (Builder.pm:868-896). Finds directories containing `dynamic_obj` under OBJROOT and copies them into LIBCOBJROOT via `chroot ... cp -rp`. Returns 0 on success.

**Mapping note:** the Perl writes a Debian `control` into `<dstroot>/DEBIAN/control` then runs `dpkg-deb --build`. For apk we write `<dstroot>/.PKGINFO` (via `pkginfo_write`) and assemble with `pkginfo_build_apk` to `<PACKAGEDIR>/<canon_name>.apk`. The `binary` sub-package gets `provides = <name>-hdrs` and `replaces = <name>-hdrs` (apk has no `conflicts`).

- [ ] **Step 1: Add declarations**

Add to `builder.h`:

```c
int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target);
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams);
```

- [ ] **Step 2: Add implementation**

Port notes (Builder.pm:364-448):
- Clone the package (copy fields), take `pname = package->package`.
- `binary`: dstroot=DSTROOT; package stays `pname`; provides/conflicts/replaces = `pname-hdrs` → map to apk provides+replaces.
- `headers`: dstroot=HDRROOT; package = `pname-hdrs`.
- `objects`: dstroot=LIBCOBJROOT; package = `pname-obj`.
- `local`: return 0.
- For `binary`, `mkdir -p <dstroot>/DEBIAN` first (Perl); for apk we don't need DEBIAN — skip. Instead ensure `<dstroot>` exists for the empty-check.
- If `opendir(dstroot)` fails → no files → return 0. If exactly 2 entries (`.`/`..`) → empty → return 0 (Perl checks `$#entries == 1`, i.e. 2 entries).
- `rm -rf <dstroot>/System/Developer/Source`.
- Write metadata + assemble.
- For `binary`, copy `<SRCDIR>/dpkg/{conffiles,preinst,postinst,prerm,postrm}` when present. apk uses different script conventions; for the port, copy any present scripts into `<dstroot>` root (not DEBIAN) and log. Keep behavior minimal — see note; the trace test only checks that the file-copy commands are issued for present files.

Append to `builder.c` (add `#include "pkginfo.h"` at the top of the file):

```c
/* Count directory entries excluding . and .. ; -1 if cannot open. */
static int dir_nonempty(const char *path) {
    DIR *d = opendir(path);
    struct dirent *de;
    int n = 0;
    if (!d) return -1;
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        n++;
        if (n > 0) { /* early out possible, but keep counting cheap */ }
    }
    closedir(d);
    return n;
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target) {
    Package pkg;
    const char *dstroot;
    char *pname;
    char *unparsed;
    char *canon;
    char *pkginfo_path;
    char *apk_path;
    int nonempty;
    int rc = 0;

    if (strcmp(target, "local") == 0) return 0;

    /* Clone spkg by round-tripping through unparse/parse (matches Perl). */
    package_init(&pkg);
    unparsed = package_unparse(spkg);
    package_parse(&pkg, unparsed);
    free(unparsed);
    /* unparse drops arch/desc? No — unparse includes them; re-set arch to be safe */
    if (!pkg.architecture) package_set(&pkg.architecture, ARCH);

    pname = xstrdup(pkg.package ? pkg.package : "");

    if (strcmp(target, "binary") == 0) {
        char *hdrs = str_cats(pname, "-hdrs", (char *)0);
        dstroot = params->DSTROOT;
        package_set(&pkg.package, pname);
        package_set(&pkg.provides, hdrs);
        package_set(&pkg.replaces, hdrs);
        free(hdrs);
    } else if (strcmp(target, "headers") == 0) {
        char *hdrs = str_cats(pname, "-hdrs", (char *)0);
        dstroot = params->HDRROOT;
        package_set(&pkg.package, hdrs);
        free(hdrs);
    } else if (strcmp(target, "objects") == 0) {
        char *obj = str_cats(pname, "-obj", (char *)0);
        dstroot = params->LIBCOBJROOT;
        package_set(&pkg.package, obj);
        free(obj);
    } else {
        fprintf(stderr, "rbuild: bad target: \"%s\"\n", target);
        free(pname); package_free(&pkg);
        return 1;
    }

    /* Ensure the base package dir exists (Perl mkdir -p DEBIAN for binary). */
    if (strcmp(target, "binary") == 0) {
        if (exec_check(mkdirp(dstroot))) { rc = 1; goto done; }
    }

    nonempty = dir_nonempty(dstroot);
    if (nonempty <= 0) {
        /* cannot open (no files) or empty -> nothing to package */
        goto done;
    }

    if (exec_runv("rm", "-rf",
                  (canon = str_cats(dstroot, "/System/Developer/Source", (char *)0)),
                  (char *)0) != 0) {
        free(canon); rc = 1; goto done;
    }
    free(canon);

    if (exec_check(mkdirp(dstroot))) { rc = 1; goto done; }

    /* Write .PKGINFO into dstroot. */
    pkginfo_path = str_cats(dstroot, "/.PKGINFO", (char *)0);
    if (pkginfo_write(&pkg, pkginfo_path) != 0) { free(pkginfo_path); rc = 1; goto done; }
    free(pkginfo_path);

    /* For binary, copy present maintainer scripts into dstroot. */
    if (strcmp(target, "binary") == 0 && params->SRCDIR) {
        static const char *names[] =
            { "conffiles", "preinst", "postinst", "prerm", "postrm", 0 };
        int i;
        for (i = 0; names[i]; i++) {
            char *extra = str_cats(params->SRCDIR, "/dpkg/", names[i], (char *)0);
            if (file_exists(extra)) {
                char *dest = str_cats(dstroot, "/", names[i], (char *)0);
                printf("copying %s\n", names[i]);
                fflush(stdout);
                if (exec_runv("cp", "-p", extra, dest, (char *)0) != 0) {
                    free(extra); free(dest); rc = 1; goto done;
                }
                if (strcmp(names[i], "conffiles") == 0)
                    exec_runv("chmod", "644", dest, (char *)0);
                else
                    exec_runv("chmod", "755", dest, (char *)0);
                free(dest);
            }
            free(extra);
        }
    }

    /* Assemble <PACKAGEDIR>/<canon_name>.apk */
    canon = package_canon_name(&pkg);
    apk_path = str_cats(params->PACKAGEDIR, "/", canon, ".apk", (char *)0);
    rc = pkginfo_build_apk(dstroot, apk_path);
    free(canon);
    free(apk_path);

done:
    free(pname);
    package_free(&pkg);
    return rc;
}

/* Object harvest: find directories containing a 'dynamic_obj' entry under
   OBJROOT and copy them into LIBCOBJROOT (Builder.pm:778-896). */
static int harvest_walk(const char *objroot_abs, const char *rel,
                        const Package *pkg, const Params *params,
                        const Params *bparams) {
    char *dirpath = (rel[0] == '\0')
        ? xstrdup(objroot_abs)
        : path_join(objroot_abs, rel);
    DIR *d = opendir(dirpath);
    struct dirent *de;
    int rc = 0;
    int found_obj = 0;

    if (!d) { free(dirpath); return 0; }

    /* First, does this directory contain 'dynamic_obj'? */
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, "dynamic_obj") == 0) { found_obj = 1; break; }
    }
    rewinddir(d);

    if (found_obj) {
        /* file = "./<rel>/dynamic_obj" relative form matching Perl $File::Find::dir/$_ */
        char *file = (rel[0] == '\0')
            ? xstrdup("./dynamic_obj")
            : str_cats("./", rel, "/dynamic_obj", (char *)0);
        char *objdest = str_cats("/usr/local/lib/objs/",
                                 pkg->source ? pkg->source : "", "/", file, (char *)0);
        char *dstdir = str_cats(params->LIBCOBJROOT, objdest, (char *)0);
        char *srcpath = str_cats(bparams->OBJROOT, "/", file, (char *)0);
        char *cobjpath = str_cats(bparams->LIBCOBJROOT, objdest, (char *)0);

        printf("copying files from %s\n", file);
        fflush(stdout);
        exec_check(mkdirp(dstdir));
        exec_runv("rmdir", dstdir, (char *)0);
        {
            char *argv[9];
            argv[0] = "chroot"; argv[1] = params->BUILDROOT;
            argv[2] = "cp"; argv[3] = "-rp";
            argv[4] = srcpath; argv[5] = cobjpath; argv[6] = 0;
            exec_printcmd(argv);
            if (exec_run_checked(argv)) rc = 1;
        }
        free(file); free(objdest); free(dstdir); free(srcpath); free(cobjpath);
        /* Perl prunes (does not descend) once dynamic_obj found. */
        closedir(d);
        free(dirpath);
        return rc;
    }

    /* Otherwise descend into subdirectories. */
    while ((de = readdir(d)) != 0) {
        char *child;
        struct stat st;
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        child = path_join(dirpath, de->d_name);
        if (stat(child, &st) == 0 && S_ISDIR(st.st_mode)) {
            char *newrel = (rel[0] == '\0')
                ? xstrdup(de->d_name)
                : path_join(rel, de->d_name);
            if (harvest_walk(objroot_abs, newrel, pkg, params, bparams) != 0)
                rc = 1;
            free(newrel);
        }
        free(child);
    }
    closedir(d);
    free(dirpath);
    return rc;
}

int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams) {
    printf("finding files in %s\n", params->OBJROOT);
    fflush(stdout);
    return harvest_walk(params->OBJROOT, "", pkg, params, bparams);
}
```

> **Implementer note:** the harvest path/relative-name construction is the trickiest port. Cross-check against Builder.pm:780-785 and 876-896: `@objs` collects `"$File::Find::dir/$_"` (the directory holding `dynamic_obj`, plus `/dynamic_obj`), then each is copied. Getting the exact string form right matters for the trace test; if the trace diff flags harvest lines, adjust the `file`/`objdest` construction to match the Perl output on the fixture.

- [ ] **Step 3: Compile-check**

Run: `cd src/rbuild-1 && make builder.o`
Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c
git commit -m "rbuild: builder buildpackage subroutine + object harvest"
```

---

## Task 15: builder — build (top-level orchestration)

**Reference:** `Builder.pm:787-917` (`build`).

**Files:**
- Modify: `src/rbuild-1/builder.h`, `src/rbuild-1/builder.c`

Verified by compilation + trace test.

**Interfaces:**
- Produces:
  - `int builder_build(const char *srctype, const char *srcname, const strlist *repository, const char *target, const char *dstdir, int clean)` — the full port of `build`. Returns 0 on success, non-0 on failure. On the "package already exists" short-circuits, returns 0 without building (matching the Perl).

- [ ] **Step 1: Add declaration**

Add to `builder.h`:

```c
int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean);
```

- [ ] **Step 2: Add implementation**

Port notes (Builder.pm:787-917), in order:
1. `scan(srctype, srcname)` → pkg, params.
2. Build `hdrpackage` (clone; name += `-hdrs`) → `hdrfilename = canon_name`.
3. `filename = pkg canon_name`.
4. If `target=="headers"` and `<dstdir>/<hdrfilename>.apk` exists → print + return 0.
5. If `<dstdir>/<filename>.apk` exists → print + return 0.
6. `bparams = params` (keep a copy); `params = chrootparams(params, params.BUILDROOT)`.
7. `params.SRCDIR = srcname` (dir case).
8. `params.PACKAGEDIR = dstdir`.
9. `canonparams(params)`, `canonparams(bparams)` against cwd (`getcwd`).
10. Print banners (building X, package unparse, params, bparams) — keep the prints (trace test ignores stdout banners but they help debugging).
11. `setupdirs(pkg, params, srcname, srctype, repository)`.
12. If target all/headers: `buildcmd(installhdrs)` with env `UNAME_SYSNAME=Rhapsody`, fixed `PATH`; run.
13. If target all/binary: `buildcmd(install)` similarly; run; then object harvest.
14. If target all/headers: `buildpackage(headers)`.
15. If target all/binary: `buildpackage(binary)`, `buildpackage(objects)`, `buildpackage(local)`.
16. If clean: `rm -rf BUILDROOT`.
17. return 0.

Environment: the Perl sets `$ENV{UNAME_SYSNAME}` and `$ENV{PATH}` before the make. In C, `putenv`/`setenv` before `exec_run` (the child inherits). Use `setenv("UNAME_SYSNAME","Rhapsody",1)` and `setenv("PATH","/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin",1)`. (POSIX `setenv` is available on the target; if strict C89-only libc lacks it, fall back to `putenv` with static strings.)

Append to `builder.c` (ensure `#include <unistd.h>` for `getcwd`):

```c
static char *cwd_dup(void) {
    char buf[4096];
    if (getcwd(buf, sizeof(buf)) == 0) return xstrdup(".");
    return xstrdup(buf);
}

static int file_apk_exists(const char *dstdir, const char *canon) {
    char *p = str_cats(dstdir, "/", canon, ".apk", (char *)0);
    struct stat st;
    int ok = (stat(p, &st) == 0);
    free(p);
    return ok;
}

static int run_make(strlist *cmd) {
    char **argv;
    size_t i;
    int rc;
    argv = (char **) xmalloc((cmd->count + 1) * sizeof(char *));
    for (i = 0; i < cmd->count; i++) argv[i] = cmd->items[i];
    argv[cmd->count] = 0;
    setenv("UNAME_SYSNAME", "Rhapsody", 1);
    setenv("PATH", "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin", 1);
    printf("UNAME_SYSNAME=Rhapsody PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin ");
    exec_printcmd(argv);
    rc = exec_run_checked(argv);
    free(argv);
    return rc;
}

int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean) {
    Package pkg, hdrpkg;
    Params bparams, params;
    char *hdrfilename, *filename;
    char *cwd;
    int rc = 0;
    int do_hdr = (strcmp(target, "all") == 0 || strcmp(target, "headers") == 0);
    int do_bin = (strcmp(target, "all") == 0 || strcmp(target, "binary") == 0);

    package_init(&pkg);
    params_init(&bparams);
    if (builder_scan(srctype, srcname, &pkg, &bparams) != 0) {
        package_free(&pkg); params_free(&bparams);
        return 1;
    }

    /* hdrpackage = clone(pkg); name += "-hdrs" */
    {
        char *u = package_unparse(&pkg);
        char *h;
        package_init(&hdrpkg);
        package_parse(&hdrpkg, u);
        free(u);
        h = str_cats(hdrpkg.package, "-hdrs", (char *)0);
        package_set(&hdrpkg.package, h);
        free(h);
    }
    hdrfilename = package_canon_name(&hdrpkg);
    filename = package_canon_name(&pkg);

    if (strcmp(target, "headers") == 0 && file_apk_exists(dstdir, hdrfilename)) {
        printf("package file for \"%s\" already exists; not building\n", hdrfilename);
        goto done_ok;
    }
    if (file_apk_exists(dstdir, filename)) {
        printf("package file for \"%s\" already exists; not building\n", filename);
        goto done_ok;
    }

    /* params = chrootparams(bparams, bparams.BUILDROOT) */
    params_init(&params);
    builder_chrootparams(&bparams, bparams.BUILDROOT, &params);

    /* SRCDIR */
    if (strcmp(srctype, "dir") == 0) params.SRCDIR = xstrdup(srcname);
    else { fprintf(stderr, "rbuild: invalid source type \"%s\"\n", srctype); rc = 1; goto done; }
    params.PACKAGEDIR = xstrdup(dstdir);

    cwd = cwd_dup();
    builder_canonparams(&params, cwd);
    builder_canonparams(&bparams, cwd);
    free(cwd);

    printf("building %s from %s:\n\n", filename, params.SRCDIR);

    if (builder_setupdirs(&pkg, &params, srcname, srctype, repository) != 0) {
        rc = 1; goto done;
    }

    if (do_hdr) {
        strlist cmd; strlist_init(&cmd);
        builder_buildcmd(&params, params.SRCROOT, "installhdrs", &cmd);
        if (run_make(&cmd)) { strlist_free(&cmd); rc = 1; goto done; }
        strlist_free(&cmd);
        printf("\n");
    }

    if (do_bin) {
        strlist cmd; strlist_init(&cmd);
        builder_buildcmd(&params, params.SRCROOT, "install", &cmd);
        if (run_make(&cmd)) { strlist_free(&cmd); rc = 1; goto done; }
        strlist_free(&cmd);
        printf("\n");

        if (builder_harvest_objects(&pkg, &params, &bparams) != 0) { rc = 1; goto done; }
        printf("\n");
    }

    if (do_hdr) {
        if (builder_buildpackage(&pkg, &params, "headers") != 0) { rc = 1; goto done; }
    }
    if (do_bin) {
        if (builder_buildpackage(&pkg, &params, "binary") != 0) { rc = 1; goto done; }
        if (builder_buildpackage(&pkg, &params, "objects") != 0) { rc = 1; goto done; }
        if (builder_buildpackage(&pkg, &params, "local") != 0) { rc = 1; goto done; }
    }

    if (clean) {
        if (exec_runv("rm", "-rf", params.BUILDROOT, (char *)0) != 0) { rc = 1; goto done; }
    }

done:
    params_free(&params);
    free(hdrfilename); free(filename);
    package_free(&pkg); package_free(&hdrpkg);
    params_free(&bparams);
    return rc;

done_ok:
    free(hdrfilename); free(filename);
    package_free(&pkg); package_free(&hdrpkg);
    params_free(&bparams);
    return 0;
}
```

- [ ] **Step 3: Compile-check**

Run: `cd src/rbuild-1 && make builder.o`
Expected: clean compile. If `setenv` is flagged under `-ansi -pedantic`, add `#define _POSIX_C_SOURCE 200112L` at the very top of `builder.c` (before includes) or switch to `putenv` with static buffers.

- [ ] **Step 4: Commit**

```bash
git add -f src/rbuild-1/builder.h src/rbuild-1/builder.c
git commit -m "rbuild: builder build() top-level orchestration"
```

---

## Task 16: main — subcommand dispatch and the three entrypoints

**Reference:** the three `src/buildtools-2/tools/darwin-*.pl` scripts.

**Files:**
- Create: `src/rbuild-1/main.c`

**Interfaces:**
- Consumes: `builder`, `manifest`, `exec`, `strutil`, `package`.
- Produces: the `rbuild` binary. `main` dispatches on `argv[1]`.

Semantics to port:
- `buildpackage`: parse a leading `--dir` (accept) or `--cvs` (error "cvs support has been removed; build from a --dir source"); optional `--target <T>` (default `all`); then exactly `<source> <repository> <dstdir>`. `repository` list = `[dstdir, seeddir]` where `seeddir` is the given `<repository>` arg. Exit code = `builder_build(type, source, repo, target, dstdir, 0)`. (darwin-buildpackage.pl)
- `buildall`: `<srclist> <repository> <dstdir>`; `manifest_read`; for each entry: `builder_scan(type, source)` → `builder_exists(pkg, "any", dstdir)`; if missing, print `must build <canon>.apk using <type> <source>` then `builder_build(type, source, repo, targets?"all", dstdir, 1)` — on failure, warn and continue (do not abort). (darwin-buildall.pl + Builder eval/warn)
- `missing`: `<srclist> <dstdir>`; `manifest_read`; for each entry: `scan` → `exists(any, dstdir)`; if missing, print `must build <canon>.apk using <type> <source>`. Build nothing. (darwin-missing.pl)
- Global `-n`/`--dry-run` (accepted anywhere before positional args) sets `exec_dry_run = 1`.
- Wrong arg counts → usage to stderr, exit 1.

- [ ] **Step 1: Write main.c**

Create `src/rbuild-1/main.c`:

```c
#include "builder.h"
#include "manifest.h"
#include "exec.h"
#include "strutil.h"
#include "package.h"
#include <stdio.h>
#include <string.h>

static const char *USAGE =
    "usage:\n"
    "  rbuild buildpackage [--dir] [--target {all|headers|objs|local}]"
    " <source> <repository> <dstdir>\n"
    "  rbuild buildall  <srclist> <repository> <dstdir>\n"
    "  rbuild missing   <srclist> <dstdir>\n"
    "  (global: -n/--dry-run)\n";

static void usage(void) { fputs(USAGE, stderr); }

/* Build the [dstdir, seeddir] repository search list. */
static void make_repo(const char *dstdir, const char *seeddir, strlist *out) {
    strlist_init(out);
    strlist_push(out, dstdir);
    strlist_push(out, seeddir);
}

static int cmd_buildpackage(int argc, char **argv) {
    const char *type = "dir";
    const char *target = "all";
    const char *source, *seeddir, *dstdir;
    strlist repo;
    int i = 0;
    int rc;

    /* optional --dir/--cvs */
    if (i < argc && strcmp(argv[i], "--dir") == 0) { type = "dir"; i++; }
    else if (i < argc && strcmp(argv[i], "--cvs") == 0) {
        fprintf(stderr, "rbuild: cvs support has been removed; "
                        "build from a --dir source\n");
        return 1;
    }

    if (i < argc && strcmp(argv[i], "--target") == 0) {
        i++;
        if (i >= argc) { usage(); return 1; }
        target = argv[i]; i++;
    }

    if (argc - i != 3) { usage(); return 1; }
    source = argv[i]; seeddir = argv[i + 1]; dstdir = argv[i + 2];

    make_repo(dstdir, seeddir, &repo);
    rc = builder_build(type, source, &repo, target, dstdir, 0);
    strlist_free(&repo);
    return rc;
}

static int cmd_buildall(int argc, char **argv) {
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
            if (builder_build(type, source, &repo, targets, dstdir, 1) != 0)
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

static int cmd_missing(int argc, char **argv) {
    const char *srclist, *dstdir;
    Manifest m;
    size_t i;

    if (argc != 2) { usage(); return 1; }
    srclist = argv[0]; dstdir = argv[1];

    manifest_init(&m);
    if (manifest_read(&m, srclist) != 0) { manifest_free(&m); return 1; }

    for (i = 0; i < m.count; i++) {
        const char *type = m.items[i].type;
        const char *source = m.items[i].source;
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
            free(canon);
        } else {
            free(found);
        }
        package_free(&pkg); params_free(&params);
    }

    manifest_free(&m);
    return 0;
}

int main(int argc, char **argv) {
    int i = 1;
    const char *sub;

    /* Global flags before the subcommand. */
    while (i < argc && (strcmp(argv[i], "-n") == 0 ||
                        strcmp(argv[i], "--dry-run") == 0)) {
        exec_dry_run = 1;
        i++;
    }

    if (i >= argc) { usage(); return 1; }
    sub = argv[i]; i++;

    /* Allow -n between subcommand and its args too. */
    while (i < argc && (strcmp(argv[i], "-n") == 0 ||
                        strcmp(argv[i], "--dry-run") == 0)) {
        exec_dry_run = 1;
        i++;
    }

    if (strcmp(sub, "buildpackage") == 0)
        return cmd_buildpackage(argc - i, argv + i);
    if (strcmp(sub, "buildall") == 0)
        return cmd_buildall(argc - i, argv + i);
    if (strcmp(sub, "missing") == 0)
        return cmd_missing(argc - i, argv + i);

    fprintf(stderr, "rbuild: unknown subcommand \"%s\"\n", sub);
    usage();
    return 1;
}
```

- [ ] **Step 2: Build the full binary**

Run: `cd src/rbuild-1 && make all`
Expected: `rbuild` builds clean.

- [ ] **Step 3: Smoke-test usage and dry-run**

Run: `cd src/rbuild-1 && ./rbuild 2>&1 | head -1; ./rbuild missing 2>&1 | head -1`
Expected: usage text on both (missing has wrong arg count).

Run a dry-run `missing` against a fixture:
```bash
cd src/rbuild-1
printf 'dir /tmp/nope-1.0\n' > /tmp/rb_srclist
mkdir -p /tmp/rb_dst
./rbuild -n missing /tmp/rb_srclist /tmp/rb_dst
```
Expected: `must build nope-1.0.apk using dir /tmp/nope-1.0` (the source dir need not exist for `missing`, since `scan` synthesizes a default control when `dpkg/control` is absent). Clean up: `rm -rf /tmp/rb_srclist /tmp/rb_dst`.

- [ ] **Step 4: Run the full unit-test suite**

Run: `cd src/rbuild-1 && make test`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add -f src/rbuild-1/main.c
git commit -m "rbuild: main dispatch + buildpackage/buildall/missing entrypoints"
```

---

## Task 17: trace-test harness (command-trace comparison vs the Perl)

**Reference:** spec "Command-trace comparison".

**Files:**
- Create: `src/rbuild-1/tests/trace/shim/` — fake tools (one script per tool)
- Create: `src/rbuild-1/tests/trace/fixtures/srclist`
- Create: `src/rbuild-1/tests/trace/fixtures/pkgsrc/foo-1.0/dpkg/control`
- Create: `src/rbuild-1/tests/trace/normalize.sed`
- Create: `src/rbuild-1/tests/trace/run.sh`

**Goal:** run the unmodified Perl `darwin-buildpackage` and `rbuild buildpackage` over the same fixture with `PATH` pointed at the shim dir; capture each tool's issued commands; normalize; and diff the **backend-agnostic** subset (the `chroot ... make ...` invocation and its flags, plus `mkdir`/`rsync` orchestration). The packaging tools legitimately differ (`dpkg-deb` vs `tar`/`gzip`) and are excluded from the compared subset.

- [ ] **Step 1: Create the shim tools**

Create `src/rbuild-1/tests/trace/shim/_log` (shared logger), then one shim per tool. Create `src/rbuild-1/tests/trace/shim/chroot`:

```sh
#!/bin/sh
# Logs "chroot <args>" to $RBUILD_TRACE, then, so the caller's logic can
# proceed, executes the *rest* of the command line through the shim PATH
# when the pattern is "chroot <root> <cmd...>". For trace purposes we only
# need the log line; we do NOT actually chroot.
echo "chroot $*" >> "$RBUILD_TRACE"
exit 0
```

Create identical-pattern shims for each of: `make`, `dpkg-deb`, `apk`, `tar`, `gzip`, `rsync`, `mkdir`, `cp`, `rm`, `rmdir`, `chmod`, `cvs`, `dpkg-deb`. Each is:

```sh
#!/bin/sh
echo "$(basename "$0") $*" >> "$RBUILD_TRACE"
exit 0
```

Make them all executable:
```bash
cd src/rbuild-1/tests/trace/shim
for t in chroot make dpkg-deb apk tar gzip rsync mkdir cp rm rmdir chmod cvs sh; do
  [ -f "$t" ] || printf '#!/bin/sh\necho "%s $*" >> "$RBUILD_TRACE"\nexit 0\n' "$t" > "$t"
done
chmod +x *
```

> **Important `sh` caveat:** several call sites use `sh -c "(cd X && rsync ...)"`. A shim `sh` that only logs would prevent the inner `rsync` from ever being logged. Instead, do NOT shim `sh`; let the real `sh -c` run, but ensure the shim dir is *first* on `PATH` so the inner `rsync`/`cd` resolve to shims. Remove `sh` from the shim set. (Delete the `sh` shim if the loop created it.)

- [ ] **Step 2: Create fixtures**

Create `src/rbuild-1/tests/trace/fixtures/pkgsrc/foo-1.0/dpkg/control`:

```
Package: foo
Maintainer: Test <t@x>
Version: 1.0
Description: Test package
Build-Depends: build-base
```

Create `src/rbuild-1/tests/trace/fixtures/srclist`:

```
dir fixtures/pkgsrc/foo-1.0 all
```

- [ ] **Step 3: Create the normalizer**

Create `src/rbuild-1/tests/trace/normalize.sed` — collapse absolute temp paths and sort-friendly canonicalization:

```sed
s#/private/tmp/roots#ROOTS#g
s#[0-9][0-9]*\.roots#PROJ.roots#g
```

- [ ] **Step 4: Create the driver**

Create `src/rbuild-1/tests/trace/run.sh`:

```sh
#!/bin/sh
# Command-trace comparison: Perl darwin-buildpackage vs rbuild buildpackage.
set -e

here=$(cd "$(dirname "$0")" && pwd)
proj=$(cd "$here/../.." && pwd)     # src/rbuild-1
shim="$here/shim"
perltool="$proj/../buildtools-2/tools/darwin-buildpackage.pl"
perllib="$proj/../buildtools-2/lib"
scriptlib="$proj/../dpkg_scriptlib-1/perl5"

src="$here/fixtures/pkgsrc/foo-1.0"
seed=/tmp/rb_trace_seed
dst=/tmp/rb_trace_dst
rm -rf "$seed" "$dst"; mkdir -p "$seed" "$dst"

# --- rbuild trace ---
RBUILD_TRACE=/tmp/rb_trace_rbuild.log
export RBUILD_TRACE
: > "$RBUILD_TRACE"
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" buildpackage --dir "$src" "$seed" "$dst" ) || true

# --- perl trace ---
RBUILD_TRACE=/tmp/rb_trace_perl.log
export RBUILD_TRACE
: > "$RBUILD_TRACE"
( cd "$here" && PATH="$shim:$PATH" PERL5LIB="$perllib:$scriptlib" \
    perl "$perltool" --dir "$src" "$seed" "$dst" ) || true

# --- compare the backend-agnostic subset: the chroot/make invocation ---
extract() {
  grep -E '^(chroot|make) ' "$1" \
    | sed -f "$here/normalize.sed" \
    | tr ' ' '\n' | grep -E '=' | sort -u
}
extract /tmp/rb_trace_rbuild.log > /tmp/rb_trace_rbuild.flags
extract /tmp/rb_trace_perl.log   > /tmp/rb_trace_perl.flags

echo "=== make/chroot flag diff (rbuild vs perl) ==="
if diff -u /tmp/rb_trace_perl.flags /tmp/rb_trace_rbuild.flags; then
  echo "TRACE MATCH: make flags identical"
else
  echo "TRACE DIFF: make flags differ (review above)"
  exit 1
fi
```

Make it executable:
```bash
chmod +x src/rbuild-1/tests/trace/run.sh
```

- [ ] **Step 5: Run the trace test**

Run: `cd src/rbuild-1 && make trace-test`

Expected: `TRACE MATCH: make flags identical`.

If it reports a diff: the differing `KEY=VALUE` flags are shown. Reconcile by adjusting `builder_buildflags`/`getparams`/`chrootparams` until the `KEY=VALUE` set matches the Perl's for the fixture. (`perl` and both Perl libs must be present; if `perl` is unavailable in the environment, skip this task's execution and note it — the unit tests still gate correctness.)

- [ ] **Step 6: Commit**

```bash
git add -f src/rbuild-1/tests/trace
git commit -m "rbuild: command-trace comparison harness vs Perl oracle"
```

---

## Task 18: README and final verification

**Files:**
- Create: `src/rbuild-1/README.md`

- [ ] **Step 1: Write the README**

Create `src/rbuild-1/README.md`:

```markdown
# rbuild

C89 replacement for the Perl `darwin-buildpackage` / `darwin-buildall` /
`darwin-missing` tools. Produces and consumes apk packages (apk-tools
2.0_pre11) instead of dpkg `.deb`.

## Build

    make            # builds ./rbuild
    make test       # unit tests
    make trace-test # command-trace comparison vs the buildtools-2 Perl
    make install    # installs to $(DSTROOT)/usr/bin/rbuild

## Usage

    rbuild buildpackage [--dir] [--target {all|headers|objs|local}] \
        <source> <repository> <dstdir>
    rbuild buildall <srclist> <repository> <dstdir>
    rbuild missing  <srclist> <dstdir>
    # global: -n / --dry-run

## Notes

- Source type is always `dir`; `--cvs` is rejected (support removed).
- Produces `<name>.apk`, `<name>-hdrs.apk`, `<name>-obj.apk`.
- `.PKGINFO` carries a custom `builddepends` field (apk ignores unknown keys).
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm` on `PATH`.

The `buildtools-2` Perl remains in the tree as the reference oracle used by
`make trace-test`; it will be retired once rbuild is validated.
```

- [ ] **Step 2: Full verification**

Run:
```bash
cd src/rbuild-1 && make clean && make all && make test
```
Expected: builds clean; `ALL TESTS PASSED`.

- [ ] **Step 3: Commit**

```bash
git add -f src/rbuild-1/README.md
git commit -m "rbuild: README + final verification"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- Perl→C89 single binary → Tasks 1-16. ✓
- apk packaging (`.PKGINFO`, `tar`+`gzip`, `<name>-<ver>.apk` naming, digit-delimiter matching) → Tasks 5, 8, 14. ✓
- Sub-packages binary/headers/objects/local → Task 14. ✓
- Object harvesting → Task 14. ✓
- CVS dropped (`--cvs` errors) → Tasks 11, 16. ✓
- Build machinery (getparams/canonparams/chrootparams/buildflags/buildcmd/makeroot/setupdirs/build) → Tasks 9, 10, 12, 13, 15. ✓
- `builddepends` in `.PKGINFO` from Build-Depends → Task 8. ✓
- rsync excludes CVS/.svn/.git → Task 13. ✓
- Error handling (int status, buildall continues on failure, checkret) → Tasks 7, 16. ✓
- Unit tests of pure functions → Tasks 2-11. ✓
- Command-trace comparison via PATH shim → Task 17. ✓
- Makefile install to /usr/bin, C89, POSIX-only → Tasks 1, 15. ✓

**Placeholder scan:** the `package_parse` loop in Task 3 carries an explicit implementer note to prefer a clean two-pass rewrite driven by the provided tests — the tests are concrete, so this is guidance, not a placeholder. All code steps contain complete code.

**Type consistency:** `Params`/`Package` field names, `builder_*`/`exec_*`/`pkginfo_*`/`str_*` signatures are consistent across tasks (declared in Task 3-16 headers and reused verbatim).

## Open items for the implementer

- **`setenv` under `-ansi -pedantic`:** may warn; Task 15 Step 3 gives the `_POSIX_C_SOURCE`/`putenv` fallback.
- **`perl` availability** for `make trace-test` (Task 17): if absent, unit tests still gate correctness; note the skip.
- **Object-harvest string forms** (Task 14): the exact relative-path strings are the highest-risk port; the trace test on a fixture with a `dynamic_obj` file would catch mismatches — consider adding such a fixture if harvesting needs tighter verification.
