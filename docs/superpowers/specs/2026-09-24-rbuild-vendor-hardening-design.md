# rbuild vendoring hardening and superseded thin APKs

Follow-up to `2026-07-24-rbuild-vendor-design.md` (merged as `7f3ca4fe4`,
issue #22). Approved in conversation on 24 September 2026.

## Goal

1. `apk/vendor` rejects values that could point outside the project or SRCROOT.
2. A vendored tarball is scanned before extraction, and rbuild refuses members
   that would land outside SRCROOT.
3. During bootstrap, once a universal APK of a package is published, the thin
   (`-i386`/`-ppc`) APKs it replaces are deleted. The thin walk treats a valid
   universal APK as satisfying its thin request, so it does not rebuild them.

## 1. `apk/vendor` value validation

In `vendor_read()`, after parsing, reject with `rbuild: <path>: invalid <key>
'<value>'`:

| Key | Rule |
|---|---|
| `tarball` | non-empty; no leading `/`; no `..` component; no empty component (`a//b`); no trailing `/` |
| `directory` | non-empty; a single path component: no `/` at all; not `.` or `..` |
| `patches` (when given) | same rules as `tarball` |
| `patchlevel` (when given) | one or more decimal digits, value at most 99 |

"Component" means a `/`-separated segment. Validation lives in one static
helper in `vendor.c` shared by `tarball` and `patches`.

## 2. Tarball member scan before extraction

New `int apk_untar_check(const char *path, const Toolchain *tc)` in `apk.c`,
called by `vendor_apply()` right before `apk_untar()`. It decompresses with the
existing `start_gzip()` and parses 512-byte tar headers in C. It never
extracts anything.

Header handling must match the extractor rbuild actually runs, Rhapsody
`/bin/pax -r` (source in `src/Commands/file_cmds/pax`), not GNU tar. Any header
that pax would read differently from the checker is a way past the check.

- Name: the 100-byte `name` field. When the first 5 magic bytes are `ustar`
  (POSIX `ustar\0` or old-GNU `ustar  \0`, as pax's `ustar_id` compares only
  those 5), and `prefix` (offset 345, 155 bytes) is non-empty, the name is
  `prefix/name`, exactly as pax's `ustar_rd` joins it.
- Every header must be one pax can identify, so pax never resyncs byte by
  byte into member data. Reject:
  - an empty `name` field on a non-zero block;
  - a header whose 5-byte `ustar` status differs from the first header's
    (pax fixes the format from the first header);
  - a `size` or `checksum` field containing a NUL before its first octal digit
    (pax's `asc_ul` would read a different value).
- Size: the octal `size` field. Data blocks are skipped, rounded up to 512.
- Types `L`/`K` (GNU long names) and `x`/`g` (pax extended headers): rejected
  as unsupported. pax extracts them as regular files and ignores their meaning.
- End of archive: two consecutive all-zero blocks, or one zero block at EOF.
  A bad header checksum or a truncated stream is an error.

Member rules. A leading `./` is stripped and a trailing `/` ignored before any
check. The member is rejected when:

- its name is absolute, or contains a `..` component;
- a component-wise prefix of its name equals an earlier symlink member's name,
  meaning the path passes through a symlink;
- it is a symlink (type `2`) whose target is absolute, or whose target,
  resolved lexically from the link's own directory, climbs above the archive
  root. `lib/a -> ../include/b` is allowed; `a -> ../../x` is not;
- it is a hard link (type `1`) whose target is absolute or contains `..`;
- a link target, symlink or hard link, walks through a symlink member
  before its final component. This is checked after the whole archive has been
  read, against every symlink in it, so member order does not matter.

Errors print `rbuild: <tarball>: unsafe member '<name>' (<reason>)` and return
1. Dry-run prints `check members of <path>` and returns 0. With a NULL
toolchain, the tools are `pax` and `gzip` from PATH, as in `apk_untar`.

## 3. Superseded thin APKs in bootstrap

Two changes in `runner.c` `run_entry()`, bootstrap path only (`opt->bootstrap`).

**Covering (thin walk).** When the resolved architecture is thin, for each
artifact of the entry (base, `-hdrs`, `-obj`): if the thin file
`<name>-<ver>-<thin>.apk` is absent and `<name>-<ver>-universal.apk` exists,
use the universal path in place of the thin one for everything that follows:
validation, `already have`, replay into the sysroot, and the state record.
Validation must accept the universal APK for the thin request, through the
existing covering-architecture acceptance in `builder_cache_status` and
`apk_use_arch`. A later check of an existing state record must treat
"recorded thin path, now covered by universal" as current and rewrite it; it
must not be a mismatch error or a rebuild.

**Pruning (universal walk).** When the resolved architecture is universal,
after the entry's artifacts are confirmed valid, whether just built or
`already have`, delete every thin APK in `dstdir` whose pkgname is exactly the
pkgname of a confirmed universal artifact (base, `-hdrs`, `-obj`
independently), at any version. Match with `builder_match_pkgfile()`, which
requires `<name>-<digit>`, so `foo` never matches `foo-hdrs-*`, and select thin
files by their filename token (`-i386.apk` / `-ppc.apk`). Deletion is `unlink`
through `exec_runv("rm", "-f", path)`, printing `remove superseded <path>`; in
dry-run the same line prints and nothing is removed. Pruning never touches
`seeddir` when it differs from `dstdir`, `.invalid` files, or other packages.

Non-bootstrap commands (`buildall`, `buildpackage`, kernel) are unchanged.

## Testing

All builds and tests run on the Rhapsody build box (no compiler on the Windows
host), in the private root `/build/rbuild-vendor`, one SSH session at a time.

- `tests/test_vendor.c`: each rejected value in the table above, plus accepted
  values such as `sub/dir/x.tar.gz`, `patches/series`, and `patchlevel = 0`.
- `tests/test_apk.c`: `apk_untar_check` accepts a normal archive, a v7 (no
  magic) archive, an old-GNU archive, and an in-tree relative symlink. It rejects
  an absolute path, a `..` path, a path through a symlink, an escaping symlink,
  an absolute hard link, GNU `L` and `K` headers, a pax `x` header, an old-GNU
  header with an escaping `prefix`, an empty-name header, a mixed-format archive,
  a NUL-led size field, and a link through a symlink that appears later in the
  archive. Archives come from the existing
  `write_tar` helper, extended only as needed.
- `tests/test_vendor.c`: `vendor_apply` refuses an unsafe tarball, and nothing
  is extracted.
- `tests/bootstrap-resume.sh` (extended) or a new `tests/bootstrap-supersede.sh`:
  1. Thin `bootstrap` then `bootstrap-universal` on the existing fixture: the
     thin APKs of rebuilt packages are gone, and the universal ones exist.
  2. Rerun thin `bootstrap`: no `must build`, `already have …-universal.apk`,
     exit 0, no thin APK reappears.
  3. Rerun `bootstrap-universal`: nothing rebuilt.
  4. Dry-run prints `remove superseded` and removes nothing.
- The full `make test` must pass.
