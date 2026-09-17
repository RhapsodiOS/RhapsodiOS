# Remove dpkg Source and Perl Buildtools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete `dpkg-3`, `dpkg_scriptlib-1`, and `buildtools-2` from the tree, make `trace-test` rbuild-only APK dry-run, and remove those three packages' APKs from `/build/repo`.

**Architecture:** One cut on a branch from qemu-debug-loop. Rewrite `tests/trace/run.sh` first so tests no longer need Perl `darwin-buildpackage`. Then delete the three source trees, Manifest rows, converter, and `dpkg-deb` shim. A one-shot `vm/remove-repo-dpkg-apks.sh` deletes matching live APKs by `.PKGINFO` `pkgname`.

**Tech Stack:** POSIX `sh` on the Rhapsody guest; PowerShell wrappers on the Windows host; C89 rbuild unchanged.

**Spec:** `docs/superpowers/specs/2026-09-17-remove-dpkg-source-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `src/rbuild-1/tests/trace/run.sh` | rbuild `-n` APK dry-run only |
| `src/rbuild-1/tests/trace/shim/dpkg-deb` | Delete |
| `src/dpkg-3/` | Delete |
| `src/dpkg_scriptlib-1/` | Delete |
| `src/buildtools-2/` | Delete |
| `src/Manifest` | Drop three `dir` rows |
| `tools/convert-dpkg-control-to-pkginfo.py` | Delete |
| `src/rbuild-1/README.md` | Current-policy: no Perl oracle |
| `src/rbuild-1/Makefile` | `trace-test` comment |
| `vm/remove-repo-dpkg-apks.sh` | One-shot `/build/repo` cleanup |
| `vm/remove-repo-dpkg-apks.ps1` | Host wrapper like `rename-repo-apk-arch.ps1` |

Work from the feature worktree. Copy `D:\RhapsodiOS\vm\vm.conf` into the worktree `vm/` if missing (gitignored). Run sync/build from the worktree, never from `D:\RhapsodiOS`.

Do not wipe `/build/repo`. Do not uninstall sysroot `dpkg`. Do not edit `apk-tools-1`. Do not change rbuild C. Do not run host `test-build-src.ps1`.

`extract()` in `run.sh` may keep `perl -ne` as a **text** helper to parse `installhdrs` flags. Do **not** invoke `darwin-buildpackage.pl` or `dpkg_scriptlib`.

---

### Task 1: Rewrite `make trace-test` as rbuild-only APK dry-run

**Files:**
- Modify: `src/rbuild-1/tests/trace/run.sh`
- Delete: `src/rbuild-1/tests/trace/shim/dpkg-deb`
- Modify: `src/rbuild-1/Makefile` (comment on `trace-test` only)

- [ ] **Step 1: Guest RED** — from the worktree, after copying `vm.conf`:

```
powershell -NoProfile -File .\vm\sync-src.ps1 -Path rbuild-1
```

On the guest (via `build-src -Rbuild` is not required yet), or SSH:

```
cd /build/src/rbuild-1 && make trace-test
```

Expected: PASS on the old Perl oracle (baseline). Then delete the Perl block from `run.sh` (leave `extract` of `/tmp/rb_trace_perl.log`) and re-run: FAIL with `TRACE ERROR: failed to extract project make flags`. That proves the Perl half is load-bearing.

- [ ] **Step 2: Replace `run.sh` with this file** (entire contents):

```sh
#!/bin/sh
# rbuild dry-run: universal probes, thin RC_*, no live-host seeds, no build root.
set -e

here=$(cd "$(dirname "$0")" && pwd)
proj=$(cd "$here/../.." && pwd)
shim="$here/shim"
chmod a+x "$shim"/*
src="$here/fixtures/pkgsrc/foo-1.0"
thin_src="$here/fixtures/pkgsrc/thin-1.0"
seed=/tmp/rb_trace_seed
dst=/tmp/rb_trace_dst
rm -rf "$seed" "$dst"
mkdir -p "$seed" "$dst"

# Empty APKs are planning fixtures for rbuild -n, never validated artifacts.
basedeps="cc cctools gnumake pb-makefiles coreosmakefiles project-makefiles \
zsh tcsh file-cmds text-cmds shell-cmds developer-cmds awk grep gnutar \
patch-cmds libsystem libc-hdrs architecture-hdrs kernel-hdrs csu objc4-hdrs \
files basic-cmds bootstrap-cmds system-cmds"
for d in $basedeps; do
  : > "$seed/$d-1.0-universal.apk"
done

projroot=/private/tmp/roots/foo-1.0-1.0.roots
thinroot=/private/tmp/roots/thin-1.0-1.0.roots
rm -rf "$projroot" "$thinroot"

RBUILD_TRACE=/tmp/rb_trace_rbuild.log
export RBUILD_TRACE
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" -n buildpackage \
    --dir --target all "$src" "$seed" "$dst" ) >"$RBUILD_TRACE" 2>&1
if test -e "$projroot"; then
  echo "TRACE ERROR: rbuild dry-run created its build root"
  exit 1
fi
for forbidden in /usr/lib/dyld /lib/crt1.o /usr/bin/strip.real /build/bin; do
  if grep "$forbidden" "$RBUILD_TRACE" >/dev/null 2>&1; then
    echo "TRACE ERROR: rbuild referenced live-host bootstrap seed: $forbidden"
    exit 1
  fi
done
for arch in i386 ppc; do
  for stage in compile link; do
    grep "^probe $arch $stage$" "$RBUILD_TRACE" >/dev/null
  done
done

extract() {
  perl -ne 'if (/((?:chroot|make) .*\binstallhdrs)\s*$/) {
      print "$1\n"; exit;
    }' "$1" \
    | sed -f "$here/normalize.sed" \
    | perl -ne 'while (/"([^"]*)"|(\S+)/g) {
          my $t = defined($1) ? $1 : $2;
          print "$t\n" if $t =~ /=/;
        }'
}

RBUILD_TRACE=/tmp/rb_trace_thin.log
export RBUILD_TRACE
( cd "$here" && PATH="$shim:$PATH" "$proj/rbuild" -n buildpackage \
    --dir --target all "$thin_src" "$seed" "$dst" ) >"$RBUILD_TRACE" 2>&1
extract "$RBUILD_TRACE" > /tmp/rb_trace_thin.flags
if test ! -s /tmp/rb_trace_thin.flags; then
  echo "TRACE ERROR: failed to extract thin project make flags"
  exit 1
fi
grep '^RC_ARCHS=i386$' /tmp/rb_trace_thin.flags >/dev/null
grep '^RC_i386=YES$' /tmp/rb_trace_thin.flags >/dev/null
grep '^RC_ppc=$' /tmp/rb_trace_thin.flags >/dev/null
expected='RC_CFLAGS=-arch i386  -Dunix -D__unix -D__unix__ -DNX_COMPILER_RELEASE_3_0=300 -DNX_COMPILER_RELEASE_3_1=310 -DNX_COMPILER_RELEASE_3_2=320 -DNX_COMPILER_RELEASE_3_3=330 -DNX_CURRENT_COMPILER_RELEASE=520 -DNS_TARGET=52 -DNS_TARGET_MAJOR=5 -DNS_TARGET_MINOR=2 -DNeXT -D__NeXT -D__NeXT__ -D_NEXT_SOURCE'
actual=$(grep '^RC_CFLAGS=' /tmp/rb_trace_thin.flags)
test "$actual" = "$expected"
grep '^probe i386 compile$' "$RBUILD_TRACE" >/dev/null
grep '^probe i386 link$' "$RBUILD_TRACE" >/dev/null
if grep '^probe ppc ' "$RBUILD_TRACE" >/dev/null || test -e "$thinroot"; then
  echo "TRACE ERROR: thin plan selected PPC or wrote its build root"
  exit 1
fi
echo "TRACE MATCH: universal probes and thin policy verified (rbuild APK dry-run)"
```

- [ ] **Step 3: Delete** `src/rbuild-1/tests/trace/shim/dpkg-deb`

- [ ] **Step 4: Guest GREEN**

```
powershell -NoProfile -File .\vm\sync-src.ps1 -Path rbuild-1
```

Then on guest `cd /build/src/rbuild-1 && make trace-test`

Expected: `TRACE MATCH: universal probes and thin policy verified (rbuild APK dry-run)` and exit 0. Must not mention Perl oracle. Must not require `dpkg-deb` on PATH.

Grep the new `run.sh`: no `buildtools-2`, `dpkg_scriptlib`, `dpkg-deb`, or `.deb`.

- [ ] **Step 5: Commit**

```
git add src/rbuild-1/tests/trace/run.sh
git rm src/rbuild-1/tests/trace/shim/dpkg-deb
git commit -m "rbuild: drop Perl oracle from make trace-test"
```

---

### Task 2: Delete dpkg, dpkg-scriptlib, buildtools, and the converter

**Files:**
- Delete: `src/dpkg-3/` (entire tree)
- Delete: `src/dpkg_scriptlib-1/` (entire tree)
- Delete: `src/buildtools-2/` (entire tree)
- Modify: `src/Manifest`
- Delete: `tools/convert-dpkg-control-to-pkginfo.py`

- [ ] **Step 1: Drop Manifest rows** — delete these three lines from `src/Manifest` (keep surrounding rows):

```
dir     buildtools-2          all
```

```
dir     dpkg_scriptlib-1      all
dir     dpkg-3                all
```

- [ ] **Step 2: Remove trees**

```
git rm -r src/dpkg-3 src/dpkg_scriptlib-1 src/buildtools-2
git rm tools/convert-dpkg-control-to-pkginfo.py
```

- [ ] **Step 3: Verify**

```
git grep -n "dpkg-3\|dpkg_scriptlib-1\|buildtools-2" -- src/Manifest src/rbuild-1
```

Expected: no hits in those paths. (`git grep dpkg -- src/rbuild-1` may still hit README "instead of dpkg `.deb`" until Task 3.)

`Test-Path src/dpkg-3` / `src/dpkg_scriptlib-1` / `src/buildtools-2` must be false.

- [ ] **Step 4: Commit**

```
git commit -m "tree: remove dpkg, dpkg-scriptlib, and Perl buildtools"
```

Do not keep the directories “just in case.”

---

### Task 3: Current-policy docs

**Files:**
- Modify: `src/rbuild-1/README.md`
- Modify: `src/rbuild-1/Makefile` (one-line comment above `trace-test:`)

- [ ] **Step 1: README Usage line 11**

From:

```
    make trace-test # planned universal flags vs Perl; thin/dry-run assertions
```

To:

```
    make trace-test # rbuild APK dry-run: universal probes and thin RC_*
```

- [ ] **Step 2: Replace the Perl oracle paragraph** (lines 81–85) with:

```
`make trace-test` is an rbuild `-n` dry-run against empty APK seeds: universal
i386+ppc probes, thin `RC_*` policy, no build root, no live-host bootstrap
seeds. Empty dependency archives are planning fixtures, not valid packages;
actual payload validation and native builds are tested separately.
```

Keep the opening “C89 replacement for the Perl …” history sentence; that is what rbuild replaced, not a claim that Perl still runs.

- [ ] **Step 3: Makefile** — immediately above `trace-test: rbuild` add:

```
# rbuild APK dry-run: universal probes and thin RC_*
```

- [ ] **Step 4: Commit**

```
git commit -m "rbuild: document trace-test as APK dry-run"
```

Do not edit historical specs/plans under `docs/superpowers/`.

---

### Task 4: One-shot `/build/repo` APK removal helper

**Files:**
- Create: `vm/remove-repo-dpkg-apks.sh`
- Create: `vm/remove-repo-dpkg-apks.ps1`

- [ ] **Step 1: Write `vm/remove-repo-dpkg-apks.sh`**

```sh
#!/bin/sh
# Remove /build/repo APKs whose .PKGINFO pkgname is dpkg, dpkg-scriptlib,
# buildtools, or those names plus -hdrs / -obj. No full repo wipe.
set -e
repo=${1-/build/repo}
if test "$1" = "--self-test"; then
    t=/tmp/rb-remove-dpkg-apks-self
    rm -rf "$t"
    mkdir -p "$t"
    printf 'not gzip' > "$t/broken-1-universal.apk"
    if "$0" "$t" >/tmp/rb-remove-dpkg-ok.out 2>/tmp/rb-remove-dpkg-ok.err; then
        echo "self-test: expected fail on non-gzip APK" >&2
        exit 1
    fi
    test -f "$t/broken-1-universal.apk"
    rm -f "$t/broken-1-universal.apk"
    printf 'pkgname = dpkg\n' | gzip > "$t/dpkg-1.4.1.0.2-universal.apk"
    printf 'pkgname = grep\n' | gzip > "$t/grep-2.1-universal.apk"
    printf 'pkgname = buildtools-hdrs\n' | gzip > "$t/buildtools-hdrs-0.1-universal.apk"
    "$0" "$t" >/tmp/rb-remove-dpkg-ok.out
    test ! -f "$t/dpkg-1.4.1.0.2-universal.apk"
    test -f "$t/grep-2.1-universal.apk"
    test ! -f "$t/buildtools-hdrs-0.1-universal.apk"
    grep 'removed=2' /tmp/rb-remove-dpkg-ok.out >/dev/null
    rm -rf "$t"
    echo "self-test: PASS"
    exit 0
fi
if test ! -d "$repo"; then
    echo "remove-repo-dpkg-apks: missing directory $repo" >&2
    exit 1
fi
n=0
for f in "$repo"/*.apk; do
    test -f "$f" || continue
    case "$f" in
        *.apk.invalid) continue ;;
    esac
    name=`gzip -dc "$f" | tr '\000' '\012' | grep '^pkgname =' | sed -n '1p' | sed 's/^pkgname = //'`
    if test -z "$name"; then
        echo "remove-repo-dpkg-apks: cannot read pkgname from $f" >&2
        exit 1
    fi
    case "$name" in
        dpkg|dpkg-scriptlib|buildtools|dpkg-hdrs|dpkg-obj|dpkg-scriptlib-hdrs|dpkg-scriptlib-obj|buildtools-hdrs|buildtools-obj)
            rm -f "$f"
            echo "removed `basename "$f"`"
            n=`expr "$n" + 1`
            ;;
    esac
done
echo "remove-repo-dpkg-apks: removed=$n"
```

Use Unix LF. `chmod +x` in git: `git update-index --chmod=+x` after add if Windows stages `100644`.

- [ ] **Step 2: `--self-test` RED then GREEN**

```
py -3 -c "print('skip')" 
```

Host may lack `gzip` in PATH. Prefer running `--self-test` on the guest after copy, or Git-bash gzip. If host has no gzip, skip host self-test and run it on the guest in Step 4.

Expected GREEN: `self-test: PASS`

Missing directory:

```
sh vm/remove-repo-dpkg-apks.sh /no-such-repo
```

Expected: exit 1, `missing directory`.

- [ ] **Step 3: Write `vm/remove-repo-dpkg-apks.ps1`** (mirror `vm/rename-repo-apk-arch.ps1`):

```powershell
#Requires -Version 5.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'remove-repo-dpkg-apks'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'remove-repo-dpkg-apks'

$body = Get-Content -Raw (Join-Path $PSScriptRoot 'remove-repo-dpkg-apks.sh')
$ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
exit $ec
```

- [ ] **Step 4: Commit** (do **not** run against live `/build/repo` until Task 5)

```
git add vm/remove-repo-dpkg-apks.sh vm/remove-repo-dpkg-apks.ps1
git commit -m "vm: remove leftover dpkg and buildtools APKs from the repo"
```

---

### Task 5: Guest verification and live repo cleanup

**Files:** none new (run commands)

- [ ] **Step 1: Sync worktree** (source deletes need `-All` so `/build/src` loses `dpkg-3` etc.)

```
powershell -NoProfile -File .\vm\sync-src.ps1 -All
```

Expected: `sync-src: complete`, exit 0.

- [ ] **Step 2: Rbuild**

```
powershell -NoProfile -File .\vm\build-src.ps1 -Rbuild
```

Expected: `ALL TESTS PASSED`, bootstrap scripts PASS, `build-src: complete (rbuild)`, exit 0.

- [ ] **Step 3: Guest `make trace-test`**

SSH or a one-off remote:

```
cd /build/src/rbuild-1 && make trace-test
```

Expected: `TRACE MATCH: universal probes and thin policy verified (rbuild APK dry-run)`, exit 0.

- [ ] **Step 4: Self-test then live remove**

```
powershell -NoProfile -File .\vm\remove-repo-dpkg-apks.ps1
```

The `.ps1` streams the `.sh` with no args, so it targets `/build/repo`. First, optionally SSH `sh /path` — the wrapper sends the script body, which is the live path not `--self-test`.

Run self-test over SSH first:

```
# after scp of the script, or inline:
sh -s -- --self-test < vm/remove-repo-dpkg-apks.sh
```

Then:

```
powershell -NoProfile -File .\vm\remove-repo-dpkg-apks.ps1
```

Expected: `removed=N` (N may be 0 if never published). Confirm other APKs remain (`ls /build/repo/*.apk | wc` still large). Do not `rm -rf /build/repo`.

- [ ] **Step 5: Tree grep on the worktree**

```
git grep -n "buildtools-2\|dpkg_scriptlib-1\|dpkg-3\|dpkg-deb" -- src/rbuild-1 src/Manifest
```

Expected: no hits (README may still say “instead of dpkg `.deb`” — that is allowed).

- [ ] **Step 6: Commit only if Step 4 required a script fix**; otherwise no extra commit. Report guest PASS lines in the task report.

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| Delete three source trees | 2 |
| Manifest rows gone | 2 |
| No rbuild refs to those trees / `dpkg-deb` | 1–3 |
| Delete converter | 2 |
| trace-test rbuild-only APK | 1, 5 |
| README / Makefile current policy | 3 |
| Repo helper + whitelist pkgnames | 4 |
| Guest Rbuild + trace-test | 5 |
| Remove matching live APKs, no full wipe | 5 |
| No sysroot uninstall | 5 (do not) |
| Branch from qemu-debug-loop | worktree |

## Out of scope

- Sysroot uninstall of `dpkg`
- World/bootstrap rebuild
- Host `test-build-src.ps1`
- Historical spec/plan rewrites
- `apk-tools-1` / `apk/pkginfo` schema
