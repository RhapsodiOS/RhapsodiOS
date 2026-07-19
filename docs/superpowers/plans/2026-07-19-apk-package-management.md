# Apk Package Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor Alpine apk-tools 2.0_pre11 into RhapsodiOS, port it to Darwin with Apple-style makefiles, add `.apk` packaging/indexing from `DSTROOT`, and teach ninja to discover projects via `apk/PKGINFO` (pilot packages first; full world migration is a follow-on).

**Architecture:** Freeze apk-tools at commit `72f25038747e54e820941704c0d1cdc6aef3445f` under `src/apk-tools/`. Build with PB `tool.make` like `yacc-1`. Add `ninja/mkapk.sh` to create v2 `.apk` archives (`.PKGINFO` + payload tar.gz) and use `apk index` for `APKINDEX`. `genninja` accepts either `apk/PKGINFO` or legacy `dpkg/control` during migration (dual-read only; each project has one metadata format). Runtime DB paths follow this upstream tree: `var/lib/apk` under `--root`, repos in `/etc/apk/repositories`.

**Tech Stack:** C (apk-tools), Apple/NeXT `tool.make`, ninja/samurai, zlib, POSIX shell (`mkapk.sh`), fixture-based shell tests.

**Spec:** [docs/superpowers/specs/2026-07-19-apk-package-management-design.md](../specs/2026-07-19-apk-package-management-design.md)

**Design doc correction (apply in Task 1):** Pinned pre11 uses **`/var/lib/apk`** (not `/lib/apk`). Update the spec to match the vendor tree.

---

## File structure

| Path | Responsibility |
|------|----------------|
| `src/apk-tools/` | Project root: Apple Makefile, `apk/PKGINFO`, vendored sources |
| `src/apk-tools/*.c`, `*.h` | Upstream apk-tools sources (flat, yacc-style) + local Darwin patches |
| `src/apk-tools/Makefile` | PB `tool.make` build; install `apk` to `/sbin` |
| `src/apk-tools/apk/PKGINFO` | Package metadata for apk itself |
| `ninja/mkapk.sh` | Build one `.apk` from a staging root + PKGINFO |
| `ninja/pkginfo2control.md` | (optional note only — do not create unless needed) |
| `ninja/genninja.c` | Discover `apk/PKGINFO` or `dpkg/control`; parse `pkgname` / `builddepend` / `arch` |
| `ninja/tests/apk-roundtrip.sh` | file:// install round-trip |
| `ninja/tests/apk-deps.sh` | A→B→C dependency fixture |
| `ninja/tests/apk-http.sh` | Same repo over HTTP |
| `ninja/tests/fixtures/` | Tiny package roots for tests |
| `src/zlib/apk/PKGINFO` | Pilot migration off `dpkg/control` |
| `docs/superpowers/specs/2026-07-19-apk-package-management-design.md` | Path fix `/var/lib/apk` |

**Out of scope for this plan (follow-on):** Converting all ~140 `dpkg/control` files; removing `src/dpkg-3`; signed repos; full-world CI.

---

### Task 1: Spec path fix + vendor apk-tools sources

**Files:**
- Modify: `docs/superpowers/specs/2026-07-19-apk-package-management-design.md` (replace `/lib/apk` with `/var/lib/apk` everywhere)
- Create: `src/apk-tools/` (vendored tree)
- Create: `src/apk-tools/VENDOR_SHA` (one-line pin)

- [ ] **Step 1: Fix design doc DB path**

In the design spec, replace every `/lib/apk` with `/var/lib/apk` and note that paths match apk-tools 2.0_pre11 (`database.c`).

- [ ] **Step 2: Vendor upstream at the pinned SHA**

From the repo root (Git Bash or environment with `git` + network):

```bash
git clone --no-checkout https://github.com/alpinelinux/apk-tools.git /tmp/apk-tools-vendor
cd /tmp/apk-tools-vendor
git checkout 72f25038747e54e820941704c0d1cdc6aef3445f
mkdir -p "$OLDPWD/src/apk-tools"
# Copy only source + license/docs needed to build; omit upstream Make.rules as long-term build
cp -R src/* "$OLDPWD/src/apk-tools/"
cp AUTHORS README TODO NEWS "$OLDPWD/src/apk-tools/" 2>/dev/null || true
printf '%s\n' '72f25038747e54e820941704c0d1cdc6aef3445f' > "$OLDPWD/src/apk-tools/VENDOR_SHA"
cd "$OLDPWD"
rm -rf /tmp/apk-tools-vendor
```

Expected files under `src/apk-tools/`: `apk.c`, `add.c`, `database.c`, `package.c`, `md5.c`, headers `apk_*.h`, `md5.h`, etc.

- [ ] **Step 3: Verify pin**

```bash
test -f src/apk-tools/VENDOR_SHA
grep -q 72f25038747e54e820941704c0d1cdc6aef3445f src/apk-tools/VENDOR_SHA
test -f src/apk-tools/apk.c
```

Expected: all succeed.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-19-apk-package-management-design.md src/apk-tools
git commit -m "$(cat <<'EOF'
Vendor apk-tools 2.0_pre11 and correct DB path in design spec.

Pin alpinelinux/apk-tools@72f2503 for RhapsodiOS packaging; document var/lib/apk.
EOF
)"
```

---

### Task 2: Apple-style Makefile for apk

**Files:**
- Create: `src/apk-tools/Makefile`
- Create: `src/apk-tools/Makefile.preamble`
- Create: `src/apk-tools/Makefile.postamble`
- Create: `src/apk-tools/PB.project` (minimal stub matching yacc pattern, or omit if `tool.make` allows — prefer matching `yacc-1`)
- Create: `src/apk-tools/apk/PKGINFO`
- Create: `src/apk-tools/dpkg/control` (temporary bridge so genninja finds the project before Task 6)

Model after [`src/yacc-1/Makefile`](../../src/yacc-1/Makefile).

- [ ] **Step 1: Write `apk/PKGINFO`**

Create `src/apk-tools/apk/PKGINFO`:

```
pkgname = apk-tools
pkgver = 2.0_pre11
pkgdesc = Alpine package manager (RhapsodiOS port)
url = https://github.com/alpinelinux/apk-tools
license = GPL-2.0
builddepend = build-base zlib
depend = zlib
```

- [ ] **Step 2: Write temporary `dpkg/control` for discovery**

Create `src/apk-tools/dpkg/control`:

```
Package: apk-tools
Maintainer: RhapsodiOS Developers
Vendor: Alpine Linux
Version: 2.0_pre11
Description: Alpine package manager (RhapsodiOS port)
Build-Depends: build-base, zlib
```

(Removed in Task 7 after genninja reads PKGINFO.)

- [ ] **Step 3: Write Apple Makefile**

Create `src/apk-tools/Makefile` (adapt CFILES to every `.c` present after Task 1; list must match tree):

```make
#
# RhapsodiOS build of apk-tools 2.0_pre11
#

NAME = apk
PROJECTVERSION = 2.8
PROJECT_TYPE = Tool

HFILES = apk_applet.h apk_archive.h apk_blob.h apk_database.h \
         apk_defines.h apk_hash.h apk_io.h apk_package.h apk_state.h md5.h

CFILES = apk.c add.c del.c update.c info.c search.c ver.c index.c \
         fetch.c audit.c state.c database.c package.c archive.c \
         version.c io.c url.c gunzip.c blob.c hash.c md5.c

OTHERSRCS = PROJECT Makefile Makefile.preamble Makefile.postamble \
            VENDOR_SHA AUTHORS README

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = tool.make
NEXTSTEP_INSTALLDIR = /sbin
LIBS = -lz
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)

NEXTSTEP_PB_CFLAGS = -Wall -Wno-error -D_GNU_SOURCE

NEXTSTEP_BUILD_OUTPUT_DIR = /tmp/$(NAME)/Build

NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc
WINDOWS_OBJCPLUS_COMPILER = $(DEVDIR)/gcc
PDO_UNIX_OBJCPLUS_COMPILER = $(NEXTDEV_BIN)/gcc

include $(MAKEFILEDIR)/platform.make
-include Makefile.preamble
include $(MAKEFILEDIR)/$(MAKEFILE)
-include Makefile.postamble
-include Makefile.dependencies
```

Create empty `Makefile.preamble` / `Makefile.postamble` if yacc has useful patterns; set `LIBS = -lz` and ensure install name is `apk` (not `apk-tools`).

- [ ] **Step 4: Commit**

```bash
git add src/apk-tools/Makefile src/apk-tools/Makefile.preamble \
  src/apk-tools/Makefile.postamble src/apk-tools/apk src/apk-tools/dpkg
git commit -m "$(cat <<'EOF'
Add Apple-style makefile and metadata for apk-tools.

Wire tool.make build with zlib; ship PKGINFO and temporary dpkg/control.
EOF
)"
```

---

### Task 3: Darwin / Libc portability patches

**Files:**
- Modify: `src/apk-tools/apk_defines.h` (`malloc.h` → portable include; GNU `container_of`)
- Modify: `src/apk-tools/*.c` as required for compile (minimal `#ifdef` / include fixes)
- Modify: `src/apk-tools/Makefile` (`NEXTSTEP_PB_CFLAGS`) if flags need adjustment

Known issues from pre11:

1. `#include <malloc.h>` — on Darwin use `<stdlib.h>` (guard).
2. `container_of` uses GNU statement-expression — keep for gcc; if cc rejects, replace with classic offsetof form.
3. Upstream `LIBS := /usr/lib/libz.a` is irrelevant once Apple makefile uses `-lz`.
4. `-nopie` not used in Apple makefile (good).
5. `realpath`, `fchdir`, `chroot` — present on Darwin; verify.
6. Busybox implicit script dependency in `package.c` — leave as-is for v1 (scripts uncommon in seed) or patch to skip busybox auto-dep when name missing; prefer **patch to not add busybox** on RhapsodiOS:

In `apk_pkg_read`, remove or `#ifndef RHAPSODY` the block that adds implicit `busybox` depend when install scripts exist. Define `-DRHAPSODY=1` in `NEXTSTEP_PB_CFLAGS`.

- [ ] **Step 1: Fix `apk_defines.h` includes**

Replace `#include <malloc.h>` with:

```c
#if defined(__APPLE__) || defined(__rhapsody__)
#include <stdlib.h>
#else
#include <malloc.h>
#endif
#include <stddef.h>
```

- [ ] **Step 2: Neutralize busybox auto-dependency**

In `package.c`, wrap the “Add implicit busybox dependency” block:

```c
#if !defined(RHAPSODY)
	/* Add implicit busybox dependency if there is scripts */
	if (ctx.has_install) {
		...
	}
#endif
```

Add `-DRHAPSODY=1` to `NEXTSTEP_PB_CFLAGS`.

- [ ] **Step 3: Attempt build (on Rhapsody/Darwin host or document blocker)**

```bash
# After toolchain/DSTROOT available — same as other tools:
make -C ninja generate
ninja/samurai/samu apk-tools
```

Expected: `apk` binary under OBJROOT / installed to `DSTROOT/sbin/apk`.  
If build host is unavailable in CI, compile-fix the port with whatever host gcc can (syntax-only) and note Darwin link verification for native host.

Fix remaining compile errors **in this task** until `apk.c` and objects build. Common fixes: missing prototypes, `error.h`/`err.h`, `sys/sysmacros.h` absence on Darwin.

- [ ] **Step 4: Commit**

```bash
git add src/apk-tools
git commit -m "$(cat <<'EOF'
Port apk-tools 2.0_pre11 for Darwin/RhapsodiOS.

Fix includes, disable Alpine busybox script dependency, build via tool.make.
EOF
)"
```

---

### Task 4: `mkapk.sh` — create v2 `.apk` from staging root

**Files:**
- Create: `ninja/mkapk.sh`
- Test: `ninja/tests/fixtures/mkapk-smoke/` (minimal files)

apk-tools pre11 does **not** build packages; abuild normally does. `.apk` v2 = gzip-compressed ustar with `.PKGINFO` first, then payload files with root-relative paths.

- [ ] **Step 1: Write failing smoke test**

Create `ninja/tests/mkapk-smoke.sh`:

```bash
#!/bin/sh
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
FIX="$ROOT/ninja/tests/fixtures/mkapk-smoke"
OUT="$ROOT/ninja/tests/out"
rm -rf "$OUT"
mkdir -p "$FIX/root/usr/bin" "$OUT"
echo 'hello' > "$FIX/root/usr/bin/hello"
cat > "$FIX/PKGINFO" <<'EOF'
pkgname = hello
pkgver = 1.0.0
pkgdesc = smoke test package
url = http://rhapsody.local/hello
license = MIT
depend =
EOF
"$ROOT/ninja/mkapk.sh" "$FIX/PKGINFO" "$FIX/root" "$OUT/hello-1.0.0.apk"
# Must be gzip
dd if="$OUT/hello-1.0.0.apk" bs=2 count=1 2>/dev/null | od -An -tx1 | grep -q '1f 8b'
# Must contain .PKGINFO
gzip -dc "$OUT/hello-1.0.0.apk" | tar tf - | grep -q '^\.PKGINFO$'
echo OK
```

- [ ] **Step 2: Run test — expect fail**

```bash
chmod +x ninja/tests/mkapk-smoke.sh
sh ninja/tests/mkapk-smoke.sh
```

Expected: FAIL (`mkapk.sh: No such file`).

- [ ] **Step 3: Implement `ninja/mkapk.sh`**

```bash
#!/bin/sh
# mkapk.sh — build an apk-tools 2.x .apk from PKGINFO + staging root
# Usage: mkapk.sh <PKGINFO> <staging-root> <out.apk>
set -e
PKGINFO=$1
ROOT=$2
OUT=$3
if [ ! -f "$PKGINFO" ] || [ ! -d "$ROOT" ] || [ -z "$OUT" ]; then
	echo "usage: $0 <PKGINFO> <staging-root> <out.apk>" >&2
	exit 2
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$PKGINFO" "$TMP/.PKGINFO"
# Payload: copy tree; do not include absolute paths
( cd "$ROOT" && tar cf - . ) | ( cd "$TMP" && tar xf - )
# Prefer .PKGINFO as first member: rewrite archive
(
	cd "$TMP"
	# shellcheck disable=SC2035
	tar cf - .PKGINFO $(ls -A | grep -v '^\.PKGINFO$') | gzip -n > "$OUT"
)
```

Make executable: `chmod +x ninja/mkapk.sh`.

- [ ] **Step 4: Run test — expect pass**

```bash
sh ninja/tests/mkapk-smoke.sh
```

Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add ninja/mkapk.sh ninja/tests/mkapk-smoke.sh ninja/tests/fixtures
git commit -m "$(cat <<'EOF'
Add mkapk.sh to build apk-tools 2.x packages from DSTROOT slices.

Include smoke test verifying gzip .apk with .PKGINFO.
EOF
)"
```

---

### Task 5: file:// round-trip with `apk add --root`

**Files:**
- Create: `ninja/tests/apk-roundtrip.sh`
- Depends on: built `apk` binary (Task 3), `mkapk.sh` (Task 4)

- [ ] **Step 1: Write round-trip test**

```bash
#!/bin/sh
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
APK="${APK:-$ROOT/src/apk-tools/apk}"
# Fallback: DSTROOT
if [ ! -x "$APK" ]; then
	APK="${DSTROOT:-/tmp/rhapsody/dst}/sbin/apk"
fi
test -x "$APK"

WORK="$ROOT/ninja/tests/out/roundtrip"
rm -rf "$WORK"
mkdir -p "$WORK/repo" "$WORK/root" "$WORK/stage/usr/bin"
echo 'roundtrip' > "$WORK/stage/usr/bin/rt"
cat > "$WORK/PKGINFO" <<'EOF'
pkgname = roundtrip
pkgver = 1.0.0
pkgdesc = roundtrip fixture
url = http://rhapsody.local/rt
license = MIT
EOF
"$ROOT/ninja/mkapk.sh" "$WORK/PKGINFO" "$WORK/stage" "$WORK/repo/roundtrip-1.0.0.apk"

# Index (apk index applet — confirm flags from apk index --help)
"$APK" index -o "$WORK/repo/APKINDEX.tar.gz" "$WORK/repo"/*.apk

mkdir -p "$WORK/root/etc/apk"
echo "file://$WORK/repo" > "$WORK/root/etc/apk/repositories"

"$APK" --root "$WORK/root" --initdb add roundtrip
test -f "$WORK/root/usr/bin/rt"
grep -q roundtrip "$WORK/root/usr/bin/rt"
"$APK" --root "$WORK/root" info roundtrip
echo OK
```

Adjust `apk index` invocation to match pre11 (`apk index -o …` vs positional) by running `"$APK" index` usage if the first form fails — fix the script to the actual CLI in this task.

Note: `add --initdb` is a global/applet flag in pre11 (`add --initdb`). Use exact pre11 syntax from `add.c`: `apk --root ROOT add --initdb roundtrip` after writing repositories.

- [ ] **Step 2: Run test**

```bash
chmod +x ninja/tests/apk-roundtrip.sh
APK=/path/to/built/apk sh ninja/tests/apk-roundtrip.sh
```

Expected: `OK`. Fix port bugs or index CLI until pass.

- [ ] **Step 3: Commit**

```bash
git add ninja/tests/apk-roundtrip.sh
git commit -m "$(cat <<'EOF'
Add apk file:// install round-trip test.

Prove mkapk + apk index + apk add --root against a disposable root.
EOF
)"
```

---

### Task 6: Teach `genninja` to read `apk/PKGINFO`

**Files:**
- Modify: `ninja/genninja.c` (discovery + parse)
- Modify: `ninja/README.md` (document dual discovery)
- Test: rebuild `genninja` and generate graph including `apk-tools` via PKGINFO

**PKGINFO fields for genninja:**

| PKGINFO key | Maps to |
|-------------|---------|
| `pkgname` | Package name (`pr->pkg`) |
| `builddepend` | Build-Depends (space-separated tokens; also accept commas) |
| `arch` | Architecture (optional; same tokens as today) |

- [ ] **Step 1: Add PKGINFO parsers alongside control**

In `genninja.c`:

1. Add `has_pkginfo()` checking `apk/PKGINFO`.
2. Add `pkginfo_value(buf, key)` for lines `key = value` (skip `#` and blanks).
3. Add `register_project_pkginfo()` mirroring `register_project()` but reading `pkgname` / `builddepend` / `arch`.
4. Change `scan_tree`: if `has_pkginfo`, register via PKGINFO and **do not** also require control; else if `has_control`, use control. Prefer PKGINFO when both exist (migration safety).
5. Update the “looked for */dpkg/control” error string to mention `apk/PKGINFO`.

Sketch for value parse:

```c
static char *pkginfo_value(const char *buf, const char *key)
{
	/* Find line starting with key, then " = ", return malloc'd trimmed value */
	...
}
```

For `builddepend`, reuse `parse_deps` after normalizing commas to spaces.

- [ ] **Step 2: Rebuild generator and smoke**

```bash
make -C ninja generate
# Ensure apk-tools appears even after removing dpkg/control in Task 7
grep apk-tools build.ninja || grep apk_tools build.ninja
```

Expected: `apk-tools` (or dir-based name) present in `build.ninja`.

- [ ] **Step 3: Update `ninja/README.md`**

Document that projects are discovered via `apk/PKGINFO` or legacy `dpkg/control`, and list PKGINFO keys above.

- [ ] **Step 4: Commit**

```bash
git add ninja/genninja.c ninja/README.md
git commit -m "$(cat <<'EOF'
Teach genninja to discover projects from apk/PKGINFO.

Keep dpkg/control as fallback during migration; prefer PKGINFO when both exist.
EOF
)"
```

---

### Task 7: Drop apk-tools onto PKGINFO-only metadata

**Files:**
- Delete: `src/apk-tools/dpkg/control`
- Modify: none else if Task 6 works

- [ ] **Step 1: Remove temporary control**

```bash
rm src/apk-tools/dpkg/control
rmdir src/apk-tools/dpkg 2>/dev/null || true
make -C ninja generate
grep -E 'apk-tools|apk_tools' build.ninja
```

Expected: still present.

- [ ] **Step 2: Commit**

```bash
git add -u src/apk-tools/dpkg
git commit -m "$(cat <<'EOF'
Drop temporary dpkg/control from apk-tools; use PKGINFO only.

Validates genninja PKGINFO discovery on a real project.
EOF
)"
```

---

### Task 8: Pilot-migrate `zlib` to `apk/PKGINFO`

**Files:**
- Create: `src/zlib/apk/PKGINFO`
- Delete: `src/zlib/dpkg/control` (and empty `dpkg/` dir)

- [ ] **Step 1: Write zlib PKGINFO from existing control**

```
pkgname = zlib
pkgver = 1.1.3
pkgdesc = Zip compression library
url = http://www.cdrom.com/pub/infozip/zlib/
license = zlib
builddepend = build-base
depend =
```

- [ ] **Step 2: Remove `src/zlib/dpkg/control`, regenerate**

```bash
rm src/zlib/dpkg/control
make -C ninja generate
# zlib must still be in the graph; apk-tools builddepend on zlib must resolve
grep zlib build.ninja
```

Expected: zlib edges present; no genninja unknown-dep warnings for `zlib`.

- [ ] **Step 3: Commit**

```bash
git add src/zlib/apk src/zlib/dpkg
git commit -m "$(cat <<'EOF'
Migrate zlib package metadata from dpkg/control to apk/PKGINFO.

First non-apk pilot for the genninja PKGINFO path.
EOF
)"
```

---

### Task 9: Dependency-solving fixture test

**Files:**
- Create: `ninja/tests/apk-deps.sh`
- Create: `ninja/tests/fixtures/deps/{A,B,C}/`

- [ ] **Step 1: Create packages A→B→C**

PKGINFO examples:

- C: `pkgname = depc` / no depend  
- B: `pkgname = depb` / `depend = depc`  
- A: `pkgname = depa` / `depend = depb`  

Each stages a distinct file under `usr/share/deps/{a,b,c}`.

- [ ] **Step 2: Test script**

```bash
#!/bin/sh
set -e
# build three apks, index, apk add --root depa
# assert files for a,b,c installed
# apk add missing-dep-pkg must fail (create pkg needing "nosuch")
# assert no partial install of that pkg
echo OK
```

Implement fully in the task (expand the sketch to real commands like Task 5).

- [ ] **Step 3: Run until pass; commit**

```bash
git add ninja/tests/apk-deps.sh ninja/tests/fixtures/deps
git commit -m "$(cat <<'EOF'
Add apk dependency resolution fixture tests.

Cover A→B→C pull and unmet-dependency abort without partial install.
EOF
)"
```

---

### Task 10: HTTP delivery test

**Files:**
- Create: `ninja/tests/apk-http.sh`

- [ ] **Step 1: Write test using Python or busybox httpd**

Prefer Python (often on build hosts):

```bash
#!/bin/sh
set -e
ROOT=...
WORK=.../out/http
# reuse roundtrip repo
python3 -m http.server --directory "$WORK/repo" 8765 &
PID=$!
trap 'kill $PID' EXIT
echo "http://127.0.0.1:8765/" > "$WORK/root/etc/apk/repositories"
"$APK" --root "$WORK/root" update
"$APK" --root "$WORK/root" add roundtrip
test -f "$WORK/root/usr/bin/rt"
echo OK
```

If pre11 `update` + HTTP fetch fails on Darwin (URL backend), fix `url.c`/`io.c` in this task (minimal patches).

- [ ] **Step 2: Run until pass; commit**

```bash
git add ninja/tests/apk-http.sh src/apk-tools  # if url patches needed
git commit -m "$(cat <<'EOF'
Add HTTP repo delivery test for apk update/add.

Prove the same APKINDEX tree works over http:// and file://.
EOF
)"
```

---

### Task 11: Conflict / integrity tests

**Files:**
- Create: `ninja/tests/apk-conflict.sh`

- [ ] **Step 1: Two packages installing the same path**

Build `conflict-a` and `conflict-b` both shipping `usr/bin/clash`. Install A, then `apk add conflict-b` must fail (non-zero).  

Tamper: flip a byte in an `.apk` after indexing; `apk add` must reject.

- [ ] **Step 2: Run until pass; commit**

```bash
git add ninja/tests/apk-conflict.sh
git commit -m "$(cat <<'EOF'
Add apk file-conflict and corrupt-package rejection tests.

Match design error-handling for conflicts and checksum failures.
EOF
)"
```

---

### Task 12: Publish helper + document seed workflow

**Files:**
- Create: `ninja/publish-apk-repo.sh`
- Modify: `ninja/README.md` (packaging section)

- [ ] **Step 1: Write publisher**

```bash
#!/bin/sh
# publish-apk-repo.sh DSTROOT REPO_DIR PKGINFO_PATH [PKGINFO_PATH...]
# For each PKGINFO, determine pkgname/pkgver, stage files from DSTROOT
# according to a file list sibling apk/files (optional) or full DSTROOT
# for pilot — for v1 pilots, accept explicit staging dirs.
set -e
```

For v1, keep the interface honest and small:

```bash
# Usage: publish-apk-repo.sh <repo-dir> <pkginfo> <stage-root> [<pkginfo> <stage-root> ...]
# Runs mkapk for each pair, then: apk index -o "$repo/APKINDEX.tar.gz" "$repo"/*.apk
```

Atomic index: write `APKINDEX.tar.gz.new`, then `mv`.

- [ ] **Step 2: Document in README**

Document repo layout `$REPO/rhapsody/$ARCH/`, `file://` and `http://` usage, `apk add -u` upgrades, and that full world packaging is follow-on.

- [ ] **Step 3: Commit**

```bash
git add ninja/publish-apk-repo.sh ninja/README.md
git commit -m "$(cat <<'EOF'
Add apk repo publish helper and document packaging workflow.

Atomic APKINDEX replace; same tree for media and HTTP.
EOF
)"
```

---

### Task 13: Conversion helper for remaining packages (script only)

**Files:**
- Create: `ninja/dpkg-control-to-pkginfo.sh`

Does **not** bulk-delete all controls in this plan. Converts one `dpkg/control` to stdout as PKGINFO for manual/pilot use.

- [ ] **Step 1: Implement converter**

```bash
#!/bin/sh
# Usage: dpkg-control-to-pkginfo.sh path/to/dpkg/control > apk/PKGINFO
# Maps Package→pkgname, Version→pkgver, Description→pkgdesc,
# URL→url, Build-Depends→builddepend (commas to spaces).
# Emits empty depend= for runtime (filled by humans).
```

Include a smoke: convert `src/yacc-1/dpkg/control` and show expected keys.

- [ ] **Step 2: Commit**

```bash
git add ninja/dpkg-control-to-pkginfo.sh
git commit -m "$(cat <<'EOF'
Add dpkg/control to apk/PKGINFO conversion helper.

Supports incremental metadata migration without a world cutover.
EOF
)"
```

---

### Task 14: Final verification checklist

**Files:** none (run only)

- [ ] **Step 1: Run all apk tests**

```bash
sh ninja/tests/mkapk-smoke.sh
APK=... sh ninja/tests/apk-roundtrip.sh
APK=... sh ninja/tests/apk-deps.sh
APK=... sh ninja/tests/apk-http.sh
APK=... sh ninja/tests/apk-conflict.sh
make -C ninja generate
```

Expected: all `OK`; genninja warns only for truly unknown deps.

- [ ] **Step 2: Confirm success criteria vs spec**

- [ ] apk builds and installs to DSTROOT  
- [ ] file:// and http:// install with deps  
- [ ] PKGINFO discovery works (apk-tools, zlib)  
- [ ] mkapk + index publish path documented  
- [ ] No claim of full-tree metadata migration  

- [ ] **Step 3: Commit any leftover doc fixes; stop for follow-on plan**

Follow-on plan (not this document): mass-migrate `dpkg/control` → `apk/PKGINFO`, wire ninja package edges for world `.apk` production, bootstrap seed set, retire `src/dpkg-3`.

---

## Self-review (author)

| Spec requirement | Task |
|------------------|------|
| Vendor pin 72f2503 | Task 1 |
| Apple-style makefiles | Task 2 |
| Darwin port / zlib link | Tasks 2–3 |
| `/etc/apk/repositories`, DB under root | Tasks 5+ (pre11 `var/lib/apk`) |
| Package builder + APKINDEX | Tasks 4, 12 |
| Dual file:// + HTTP | Tasks 5, 10 |
| Full dep resolution tests | Task 9 |
| Error handling conflicts/integrity | Task 11 |
| genninja metadata bridge | Tasks 6–8 |
| Replace format (no dual-write per project) | Tasks 7–8; converter Task 13 |
| Bootstrap seed | Deferred follow-on (publish helper documents path) |
| Escape hatch purpose-built apk | Not needed unless Task 3 blocked |

Placeholder scan: no TBD steps; index CLI flag nuance resolved inside Task 5 against real binary.
