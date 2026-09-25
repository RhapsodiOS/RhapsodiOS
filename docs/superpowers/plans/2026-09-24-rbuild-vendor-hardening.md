# rbuild Vendoring Hardening + Superseded Thin APKs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Implement `docs/superpowers/specs/2026-09-24-rbuild-vendor-hardening-design.md`.

**Architecture:** Value checks in `vendor_read()`. A C tar-header scanner, `apk_untar_check()`, in `apk.c`, called by `vendor_apply()` before extraction. In `runner.c` `run_entry()`, covering (thin walk) and pruning (universal walk), bootstrap path only.

**Tech Stack:** C89, `cc -Wall -O`, GNU Make 3.74, home-grown `tests/test.h`, shell integration tests.

## Global Constraints

- Worktree `D:\RhapsodiOS\.claude\worktrees\rbuild-hardening`, branch `rbuild-hardening`. Never commit from `D:\RhapsodiOS`. Never use bare `git stash`.
- No C compiler on Windows. Build and test on the box as described in `.superpowers/sdd/box-rules.md` in the worktree, with ONE box session at a time and no background box jobs.
- C89: declarations at the top of a block, `/* */` comments. Match surrounding style.
- Every subprocess goes through `exec.h`, so dry-run prints and does not run. No `sh -c`.
- Return 0 on success, non-zero on failure. Errors go to stderr prefixed `rbuild: `.
- GNU Make 3.74: edit variable lines in place; never define a variable twice.
- Commit messages: `rbuild: <behavior>`, one or two lines, **no trailers or metadata**.
- A task is done when `/bin/make CC=/usr/bin/cc clean test` on the box ends `ALL TESTS PASSED`, all integration scripts pass, and there are no new compiler warnings. The one pre-existing warning is `builder.c` "assignment discards `const'" in the probe code.

---

### Task 1: `apk/vendor` value validation

**Files:** `src/rbuild-1/vendor.c`, `src/rbuild-1/tests/test_vendor.c`

Implement spec §1 exactly. Write the failing tests first. The table-driven test writes one `apk/vendor` per case, using the existing `write_file` helper and `/tmp/rbtest_vd`, and checks `vendor_read` returns 1 for every reject case and 0 for:
- `tarball = sub/dir/x.tar.gz`, `directory = zlib`;
- `patches = patches/series`;
- `patchlevel = 0`.

Reject cases:

| Key | Rejected values |
|---|---|
| `tarball` | empty, `/abs.tar.gz`, `../x.tar.gz`, `a/../x.tar.gz`, `a//x.tar.gz`, `x/` |
| `directory` | empty, `a/b`, `.`, `..` |
| `patches` | empty, `/p`, `p/../q`, `p/` |
| `patchlevel` | empty, `-1`, `1a`, `100` |

Commit: `rbuild: reject unsafe or malformed apk/vendor values`

### Task 2: Tarball member scan before extraction

**Files:** `src/rbuild-1/apk.c`, `src/rbuild-1/apk.h`, `src/rbuild-1/vendor.c`, `src/rbuild-1/tests/test_apk.c`, `src/rbuild-1/tests/test_vendor.c`

Implement spec §2 exactly:
- Add `apk_untar_check()` next to `apk_untar()`, reusing `start_gzip()` and the `wait_child()` helpers.
- Call it in `vendor_apply()` immediately before `apk_untar()`.
- Extend `write_tar` in `tests/test_apk.c` only as far as needed, e.g. a flag for a POSIX `prefix` or for type `L` data.
- Add a `vendor_apply` test with an unsafe tarball: it must return 1 and leave no `<srcroot>/<directory>`.

Commit: `rbuild: refuse vendored tarball members that would land outside SRCROOT`

### Task 3: Superseded thin APKs in bootstrap

**Files:** `src/rbuild-1/runner.c`; tests in `src/rbuild-1/tests/bootstrap-resume.sh`, or a new `tests/bootstrap-supersede.sh` wired into the `test:` target like the others; `src/rbuild-1/README.md`, one short paragraph under Architecture.

Implement spec §3 exactly. Before coding, read `run_entry`, `check_state`, `write_state`, and `replay` in `runner.c`, plus `builder_cache_status` and `apk_use_arch`, to confirm that the covering acceptance holds for a thin request against a universal file. The integration test covers the four scenarios in the spec's Testing section, building on the `univ/rt` + `univ/later` fixture in `tests/bootstrap-resume.sh` (around lines 598-662).

Commit: `rbuild: prune thin APKs superseded by universal ones during bootstrap`
