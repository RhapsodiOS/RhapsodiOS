# HFS i386 Endian Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `kernel-7`'s HFS and HFS Plus filesystem work read-write on i386, and build `mount_hfs` for i386 so the port can be exercised.

**Architecture:** B-tree nodes are swapped whole between big-endian (disk) and host order at the buffer-cache boundary: on read in `GetBTreeBlock`, on write in `hfs_strategy`. The Master Directory Block and volume header are swapped in place around each use. Allocation-bitmap and B-tree-map words are swapped where they are touched. On ppc every change compiles away, which is proved by comparing the `__TEXT` sections of the ppc HFS objects before and after. A host-side Python package builds and checks HFS images and is anchored on an Apple-mastered volume. A harness boots the i386 guest against those images and reads the guest's report back off a UFS results disk.

**Tech Stack:** C (Darwin 0.3 BSD kernel, Apple cc 2.7.2 with `#pragma options align=mac68k`), Python 3.13 on the Windows host (standard library plus pytest), `rbuild` on the Rhapsody build box, QEMU `qemu-system-i386` driven by `vm/guest-console.py`.

**Spec:** [2026-09-23-hfs-i386-endian-port-design.md](../specs/2026-09-23-hfs-i386-endian-port-design.md)

## Global Constraints

```text
REPO      = D:\RhapsodiOS            (read the untracked vm assets from here)
WORKTREE  = D:\RhapsodiOS\.worktrees\hfs-endian   (branch hfs-endian; all edits here)
ASSETS    = D:/RhapsodiOS/vm         (golden.img, the install floppy, devtools.toast: untracked)
ROOT_IMG  = D:/RhapsodiOS/vm/work/hfs-endian.img   (this plan's own root image)
WORK      = <WORKTREE>/vm/work/hfsle (images, kernels, results; gitignored)
BOX       = root@10.10.0.241, private build root /build/hfsle
```

- **Work only in the worktree.** Several sessions share `D:\RhapsodiOS` and its git index. Create it once:
  `git worktree add -b hfs-endian .worktrees/hfs-endian master`.
- **Every Git Bash shell exports these first:**
  ```bash
  export RHAP_VM_ASSETS=D:/RhapsodiOS/vm
  export RHAP_TEST_IMAGE=D:/RhapsodiOS/vm/work/hfs-endian.img
  export MSYS_NO_PATHCONV=1
  ```
  `RHAP_VM_ASSETS` is how the tools in this plan find the untracked assets from a worktree. `vm/hfs_guest.py` boots its guests on QMP port 4493 so that it does not collide with sessions using `guest-console.py`'s default 4481; set `RHAP_QMP_PORT` to move it. `RHAP_TEST_IMAGE` keeps boots off the shared `vm/work/test.img` (`rhap_inject.check_target` and `guest-console.Guest` both honour it).
- **Edit files under `src/` only with `tools/latin1_replace.py`** (Task 1). Many of these files contain Mac-Roman bytes (`VolumeRequests.c` has 77 such lines, `BTreeAllocate.c` 12, `ConditionalMacros.h` 11, `VolumeAllocation.c` 9), and the Edit tool silently rewrites them. After every edit, `git diff FILE | grep -E '^[+-]' | LC_ALL=C grep -P '[^\x00-\x7F]'` must print nothing.
- **The ppc invariant.** Every kernel change is either a macro that expands to its argument (or to nothing) on big-endian, or code inside `#if BYTE_ORDER == LITTLE_ENDIAN`. There are two exceptions. The `ConditionalMacros.h` correction yields the same values on ppc. `hfs_endian.c`'s layout checks are typedefs and emit no code. Task 13 proves the invariant. If a change cannot keep to it, stop and report; do not accept a difference.
- **No new panics.** Corrupt on-disk data returns `EIO` or `EINVAL`. Every new kernel log line starts with `hfs: `, and the harness treats any such line in the serial log as a failure, because none should appear in a passing run.
- **The build box is shared.** Build only in `/build/hfsle`, and never write `/build/src`, `/build/tools` or `/build/repo`. Start a build only when no other `rbuild` is running, because kernel builds share `/private/tmp/roots/kernel-*.roots`. **If SSH reports that the host key for 10.10.0.241 has changed, stop and ask the user.** It did so while this plan was being written (2026-09-23); do not bypass it.
- **Never `git add -A`.** Stage named paths only.
- **Commits:** prefixes `kernel: ` (src/kernel-7), `hfs: ` (src/hfs-1), `tools: `, `vm: `, `docs: `. One or two lines saying what the change does. CLAUDE.md forbids metadata, so no trailers.

## Facts this plan relies on

Each was checked against the tree while writing the plan.

| Fact | Evidence |
|---|---|
| i386 kernels do not build HFS today | `conf/MASTER.i386:72,74` lack `hfs`; `conf/MASTER.ppc:72` has it |
| No HFS source branches on byte order, CPU or `TARGET_RT_*`, and none has inline asm | grep over `bsd/hfs` |
| `ConditionalMacros.h`'s gcc branch hard-codes `TARGET_CPU_PPC 1`, `TARGET_RT_BIG_ENDIAN 1` | `hfscommon/headers/system/ConditionalMacros.h:486-560` |
| Apple cc implements `#pragma options align=mac68k` on every NeXT target | `cc-1/cc/config/next/nextstep.c:152`, `nextstep.h:161` |
| `UInt64` is a `{hi, lo}` struct in this kernel | `MacOSTypes.h:137-143` (`TYPE_LONGLONG` needs `_LONG_LONG`); code uses `.lo` |
| Every B-tree block read goes through `GetBTreeBlock` | `BTreeScanner.c:396` `ReadMultipleNodes` is Mac-only; the Rhapsody path is `GetNode` (`:311`) |
| B-tree buffers reach the disk without `VOP_BWRITE` | `hfs_btreeio.c` `ReleaseBTreeBlock` calls `bwrite`; `vfs_bio.c:963` `blkflush` calls `bwrite` |
| Every write of an HFS vnode buffer goes through `hfs_strategy` | `VOP_STRATEGY` on the vnode; `hfs_readwrite.c:1125` |
| Map words are big-endian and swapped per use in xnu-124 | xnu-124.7 `BTreeAllocate.c:157,182,251,456` |
| Every MDB and volume-header write goes through `hfs_flushMDB` or `hfs_flushvolumeheader` | `MacOSStubs.c:467` `C_FlushMDB`; `hfs_vnodeops.c:1341` is inside `#if 0` |
| FinderInfo is copied as raw bytes between records and `nodeData` | `CatalogUtilities.c:885-956`, `Catalog.c:1300-1380` |
| A live partition's block device cannot be opened | `bsd/dev/ata_hd_registry.m:585-589` returns `nil` |
| A partition's block size is its label's `dl_secsize`; ATA I/O is in those units | `driverkit-3/libDriver/IODiskPartition.m:1531`; `ata_hd_registry.m:857` |
| HFS addresses the device in 512-byte blocks | `hfs_vfsops.c` `hfs_mountfs`: `size = 512` |
| The i386 labels on golden.img and the floppy say `dl_secsize 1024` | `vm/rhap_image.py` read of both |
| `check_label` checks only the magic number, location and checksum | `driverkit-3/libDriver/label_subr.c:113-128` |
| RELEASE_PPC compiles in neither `MACH_ASSERT` nor `DIAGNOSTIC` | `conf/MASTER:119` (`<test>`), `hfs_dbg.h:205` |
| `pb_makefiles` filters `INCLUDED_ARCHS` per project and suppresses a project left with none | `pb_makefiles-1/recursion.make:75-84` |
| golden.img has no `/sbin/mount_hfs` and no `hfs.fs` | `vm/rhap_image.py golden.img ls /sbin` |
| `devtools.toast` holds an Apple-mastered wrapped HFS+ volume with no attributes B-tree | APM entry 8, sector 968, 1324080 sectors; VH `attributesFile` size 0 |

## File structure

| File | Responsibility |
|---|---|
| `tools/latin1_replace.py` | byte-preserving, whitespace-tolerant replace for legacy sources |
| `tools/hfsimg/hfsfmt.py` | on-disk constants, record layouts, the kernel's key orderings (tables parsed from `UCStringCompareData.h`) |
| `tools/hfsimg/volume.py` | read an HFS / HFS+ / wrapped image: headers, B-trees, catalog, forks |
| `tools/hfsimg/check.py` | consistency checks: B-tree structure and order, node maps, bitmap against extents, catalog counts |
| `tools/hfsimg/content.py` | deterministic file contents and POSIX `cksum` |
| `tools/hfsimg/builder.py` | build HFS / HFS+ / wrapped images from a manifest |
| `tools/hfsimg/scenario.py` | the test manifest, guest scripts, the post-write model, report parsers |
| `tools/hfsimg/macho_text.py` | compare the `__TEXT` sections of two sets of Mach-O objects |
| `vm/hfs_guest.py` | label and results disks, boot the guest, verify its report |
| `src/kernel-7/bsd/hfs/hfs_endian.[ch]` | layout checks; MDB, volume-header and B-tree node swaps |
| `src/kernel-7/bsd/hfs/hfs_btreeio.c`, `hfs_readwrite.c` | the node read and write hooks |
| `src/kernel-7/bsd/hfs/hfs_vfsops.c` | MDB and volume-header swaps around mount and flush |
| `src/kernel-7/bsd/hfs/hfs_vfsutils.c` | attributes-B-tree refusal, FinderInfo fields |
| `src/kernel-7/bsd/hfs/hfscommon/BTree/BTreeAllocate.c` | node-map words |
| `src/kernel-7/bsd/hfs/hfscommon/Misc/VolumeAllocation.c` | allocation-bitmap words |
| `src/hfs-1/hfs_mount/*`, `src/hfs-1/*/Makefile.preamble` | `mount_hfs` endian fix and i386 build |

## The box cycle

Written once here; tasks refer to it by step name.

**Box-sync.** Upload changed projects to the private root. Run it from the worktree, which holds its own `vm/vm.conf` (Task 7):
```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path kernel-7
```
(or `-Path hfs-1`).

**Box-run SCRIPT.** Runs a script on the box and prints its output:
```powershell
powershell -NoProfile -File vm\guest-remote.ps1 -Run vm\work\hfsle\SCRIPT
```

**Box-fetch REMOTE LOCAL.** Copies one file back:
```powershell
powershell -NoProfile -File vm\guest-remote.ps1 -Fetch REMOTE -To LOCAL
```

**Kernel-build ARCH** (`i386` or `ppc`): Box-sync `kernel-7`, then Box-run `kbuild-ARCH.sh` (Task 7 writes it). It returns at once. Box-run `kcheck-ARCH.sh` every few minutes until it prints `rc=`. The build passes when `rc=0`. Any line it prints containing `error` that mentions a `bsd/hfs` file is a failure to fix in the task at hand.

**Kernel-fetch.** After a passing i386 build:
```powershell
powershell -NoProfile -File vm\guest-remote.ps1 -Run vm\work\hfsle\kextract-i386.sh
powershell -NoProfile -File vm\guest-remote.ps1 -Fetch /build/hfsle/x-i386/private/tftpboot/mach_kernel -To vm\work\hfsle\mach_kernel
```

**Graft.** Always from `golden.img`, never from an already-grafted image:
```bash
python vm/graft-kernel.py $RHAP_VM_ASSETS/golden.img vm/work/hfsle/mach_kernel $RHAP_TEST_IMAGE
```

---

### Task 0: Worktree and spec check

**Files:**
- Read: `docs/superpowers/specs/2026-09-23-hfs-i386-endian-port-design.md`

- [ ] **Step 1: Create the worktree**

```bash
cd /d/RhapsodiOS
git worktree add -b hfs-endian .worktrees/hfs-endian master
cd .worktrees/hfs-endian
mkdir -p vm/work/hfsle
```

- [ ] **Step 2: Check for concurrent HFS work**

```bash
git log --oneline master..claude/ecstatic-cannon-4ff6b0 -- src/kernel-7/bsd/hfs | cat
git diff --stat master...claude/ecstatic-cannon-4ff6b0 -- src/kernel-7/bsd/hfs | cat
```

Expected: that branch touches only `hfs_vnodeops.c`, `hfscommon/Catalog/Catalog.c` and `hfscommon/Unicode/UnicodeWrappers.c`, none of which this plan edits. If it now touches any file in the File structure table, rebase onto master after it merges and before Task 8.

- [ ] **Step 3: Confirm the assets are where the tools will look**

```bash
ls -l $RHAP_VM_ASSETS/golden.img $RHAP_VM_ASSETS/devtools.toast $RHAP_VM_ASSETS/install/rhapsody_dr2_x86_InstallationFloppy.img
```

Expected: all three exist. There is no commit in this task.

---

### Task 1: Byte-preserving edit tool

**Files:**
- Create: `tools/latin1_replace.py`
- Test: `tools/tests/test_latin1_replace.py`

**Interfaces:**
- Produces: `python tools/latin1_replace.py FILE [--count N] < PATCH`. PATCH is the old text, a line reading exactly `=====`, then the new text. Every later task edits `src/` with it, as a heredoc:
  ```bash
  python tools/latin1_replace.py FILE <<'EOF'
  old text
  =====
  new text
  EOF
  ```
  Exit 0 means it changed the file. Exit 1 means it changed nothing and printed how many times the old text matched.

- [ ] **Step 1: Write the failing test**

```python
import os
import subprocess
import sys

import latin1_replace

TOOL = os.path.join(os.path.dirname(__file__), "..", "latin1_replace.py")


def run(path, patch, *extra):
    return subprocess.run([sys.executable, TOOL, path] + list(extra),
                          input=patch.encode("utf-8"), capture_output=True)


def test_preserves_mac_roman_bytes_and_crlf(tmp_path):
    p = tmp_path / "f.c"
    p.write_bytes(b"/* \xa5 bullet */\r\n\tfreeWord\t= *pos;\r\nend\r\n")
    r = run(str(p), "freeWord = *pos;\n=====\nfreeWord = SWAP_BE16 (*pos);\n")
    assert r.returncode == 0, r.stderr
    assert p.read_bytes() == b"/* \xa5 bullet */\r\n\tfreeWord = SWAP_BE16 (*pos);\r\nend\r\n"


def test_multi_line_new_text_takes_the_files_line_endings(tmp_path):
    p = tmp_path / "f.c"
    p.write_bytes(b"a;\r\nb;\r\n")
    r = run(str(p), "a;\n=====\nx;\ny;\n")
    assert r.returncode == 0, r.stderr
    assert p.read_bytes() == b"x;\r\ny;\r\nb;\r\n"


def test_count_mismatch_changes_nothing(tmp_path):
    p = tmp_path / "f.c"
    before = b"x = *buffer;\nx = *buffer;\n"
    p.write_bytes(before)
    r = run(str(p), "x = *buffer;\n=====\ny;\n")
    assert r.returncode == 1
    assert b"matches 2 times" in r.stderr
    assert p.read_bytes() == before
    r = run(str(p), "x = *buffer;\n=====\ny;\n", "--count", "2")
    assert r.returncode == 0
    assert p.read_bytes() == b"y;\ny;\n"


def test_whitespace_between_words_is_still_required():
    assert latin1_replace.pattern("int a").search("inta") is None
    assert latin1_replace.pattern("int a").search("int\t a")
    assert latin1_replace.pattern("f (x)").search("f(x)")


def test_patch_needs_a_separator():
    try:
        latin1_replace.split_patch("no separator here\n")
    except ValueError:
        return
    raise AssertionError("expected ValueError")
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `python -m pytest tools/tests/test_latin1_replace.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'latin1_replace'`

- [ ] **Step 3: Write the tool**

```python
"""Replace text in a source file without disturbing any of its other bytes.

Legacy Apple and NeXT sources hold Mac-Roman bytes that are not valid UTF-8,
and editors that decode files as UTF-8 silently rewrite them.  This tool reads
and writes the file as latin-1, so every byte outside the replaced text comes
through unchanged.

    python tools/latin1_replace.py FILE [--count N] < PATCH

PATCH is the old text, a line reading exactly =====, then the new text.
Whitespace in the old text matches any run of whitespace in the file, so
indentation need not be copied exactly.  The new text is written with the
file's own line endings.  Nothing is written unless the old text matches
exactly N times (default 1); every match is replaced.
"""

import re
import sys

SEPARATOR = "====="


def split_patch(text):
    lines = text.replace("\r\n", "\n").split("\n")
    if SEPARATOR not in lines:
        raise ValueError("the patch has no ===== line")
    i = lines.index(SEPARATOR)
    old = "\n".join(lines[:i])
    new = "\n".join(lines[i + 1:])
    if new.endswith("\n"):
        new = new[:-1]
    if not old.split():
        raise ValueError("the old text is empty")
    return old, new


def pattern(old):
    """A regex matching `old` with any whitespace between its tokens."""
    tokens = old.split()
    out = re.escape(tokens[0])
    for prev, tok in zip(tokens, tokens[1:]):
        gap = r"\s+" if (prev[-1].isalnum() or prev[-1] == "_") and \
            (tok[0].isalnum() or tok[0] == "_") else r"\s*"
        out += gap + re.escape(tok)
    return re.compile(out)


def replace(text, old, new, count=1):
    rx = pattern(old)
    found = len(rx.findall(text))
    if found != count:
        raise ValueError("old text matches %d times, expected %d" % (found, count))
    if "\r\n" in text:
        new = new.replace("\n", "\r\n")
    return rx.sub(lambda m: new, text)


def main(argv):
    args = argv[1:]
    count = 1
    if "--count" in args:
        i = args.index("--count")
        count = int(args[i + 1])
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    path = args[0]
    with open(path, encoding="latin-1", newline="") as f:
        text = f.read()
    try:
        old, new = split_patch(sys.stdin.read())
        result = replace(text, old, new, count)
    except ValueError as e:
        print("%s: %s" % (path, e), file=sys.stderr)
        return 1
    with open(path, "w", encoding="latin-1", newline="") as f:
        f.write(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests**

Run: `python -m pytest tools/tests/test_latin1_replace.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add tools/latin1_replace.py tools/tests/test_latin1_replace.py
git commit -m "tools: add a byte-preserving replace for sources that hold Mac-Roman bytes"
```

---

### Task 2: HFS image reader

**Files:**
- Create: `tools/hfsimg/hfsfmt.py`, `tools/hfsimg/volume.py`
- Test: `tools/hfsimg/tests/conftest.py`, `tools/hfsimg/tests/test_reader.py`

**Interfaces:**
- Produces: `hfsfmt` constants, `relstring_compare(a, b)`, `unicode_compare(a, b)`, `fold_unicode(units)`, `MDB(bytes)`, `VolumeHeader(bytes)`, `ForkData`, `Extent`.
- Produces: `volume.Volume(path, offset=0)` with `.plus`, `.wrapper` (an `MDB` or None), `.vh` / `.mdb`, `.block_size`, `.total_blocks`, `.free_blocks`, `.catalog` and `.extents` (`BTree`), `.entries() -> {cnid: Entry}`, `.walk() -> [(path, Entry)]` (paths start with `/`), `.read_file(entry) -> bytes`, `.fork_extents(fork, file_id, fork_type)`, `.special_fork(file_id)`, `.read_at(off, n)`, `.block_offset(n)`, `.vol_base`, `.threads`. `Entry` has `.cnid .parent .name .is_dir .valence .data .rsrc .thread .thread_expected`. `volume.FormatError`.
- The key-ordering tables are parsed at runtime from `src/kernel-7/bsd/hfs/hfscommon/Unicode/UCStringCompareData.h`, so the tools order keys exactly as the kernel does.

- [ ] **Step 1: Write the failing tests**

`tools/hfsimg/tests/conftest.py`:

```python
import os
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))

import hfsfmt  # noqa: E402

TOAST = os.path.join(os.environ.get("RHAP_VM_ASSETS") or os.path.join(hfsfmt.REPO, "vm"),
                     "devtools.toast")
TOAST_OFFSET = 968 * 512


@pytest.fixture
def toast_location():
    """(path, byte offset) of the HFS partition in vm/devtools.toast."""
    if not os.path.exists(TOAST):
        pytest.skip("vm/devtools.toast is not present")
    return TOAST, TOAST_OFFSET


@pytest.fixture
def toast():
    """The Apple-mastered wrapped HFS Plus volume on the Developer Tools CD."""
    if not os.path.exists(TOAST):
        pytest.skip("vm/devtools.toast is not present")
    import volume
    v = volume.Volume(TOAST, TOAST_OFFSET)
    yield v
    v.close()
```

`tools/hfsimg/tests/test_reader.py`:

```python
import hfsfmt


def test_relstring_folds_case_but_not_length():
    assert hfsfmt.relstring_compare(b"abc", b"ABC") == 0
    assert hfsfmt.relstring_compare(b"abc", b"ABD") == -1
    assert hfsfmt.relstring_compare(b"ab", b"abc") == -1
    assert hfsfmt.relstring_compare(b"b", b"A") == 1


def test_unicode_compare_folds_case_and_skips_ignorables():
    assert hfsfmt.unicode_compare([0x41], [0x61]) == 0
    assert hfsfmt.unicode_compare([0x200C, 0x61], [0x61]) == 0     # ZWNJ is ignorable
    assert hfsfmt.unicode_compare([0x0000], [0x7A]) == 1            # NUL folds to 0xFFFF
    assert hfsfmt.unicode_compare([0x61], [0x62]) == -1
    assert hfsfmt.unicode_compare([0x61, 0x62], [0x61]) == 1


def test_the_apple_volume_reads(toast):
    assert toast.plus and toast.wrapper is not None
    assert toast.wrapper.al_blk_siz == 73728
    assert (toast.block_size, toast.total_blocks, toast.free_blocks) == (4096, 165402, 82748)
    assert (toast.vh.file_count, toast.vh.folder_count) == (120, 51)
    assert (toast.catalog.node_size, toast.catalog.tree_depth, toast.catalog.leaf_records) == (4096, 2, 344)
    walk = toast.walk()
    assert len(walk) == 171
    assert sum(1 for p, e in walk if not e.is_dir) == 120


def test_the_apple_volume_file_contents(toast):
    files = dict((p, e) for p, e in toast.walk() if not e.is_dir)
    pdf = toast.read_file(files["/About AppleScript Studio.pdf"])
    assert len(pdf) == 52179
    assert pdf.startswith(b"%PDF")
```

The expected numbers come from the Apple volume itself: 120 files and 51 folders are the volume header's own counts, and 344 leaf records in a depth-2 catalog with 4096-byte nodes. U+0000 folds to 0xFFFF in the kernel's table, which is how `\0\0\0\0HFS+ Private Data` sorts last.

- [ ] **Step 2: Run them to make sure they fail**

Run: `python -m pytest tools/hfsimg/tests/test_reader.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'hfsfmt'`

- [ ] **Step 3: Write `tools/hfsimg/hfsfmt.py`**

```python
"""HFS and HFS Plus on-disk constants, key ordering and record layouts.

Everything on disk is big-endian.  Layouts follow Inside Macintosh: Files
(HFS) and Apple Technical Note TN1150 (HFS Plus).  Name ordering uses the
kernel's own tables, parsed out of UCStringCompareData.h, so these tools and
kernel-7 cannot disagree about which key sorts first.
"""

import os
import re
import struct

REPO = os.environ.get("HFSIMG_REPO") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TABLES = os.path.join(REPO, "src", "kernel-7", "bsd", "hfs", "hfscommon",
                      "Unicode", "UCStringCompareData.h")

HFS_SIG = 0x4244            # 'BD'
HFSPLUS_SIG = 0x482B        # 'H+'
HFSPLUS_VERSION = 4

ROOT_PARENT_ID = 1
ROOT_FOLDER_ID = 2
EXTENTS_ID = 3
CATALOG_ID = 4
BADBLOCK_ID = 5
ALLOCATION_ID = 6
STARTUP_ID = 7
ATTRIBUTES_ID = 8
FIRST_USER_ID = 16

LEAF, INDEX, HEADER, MAP = -1, 0, 1, 2

HFS_FOLDER, HFS_FILE = 0x0100, 0x0200
HFS_FOLDER_THREAD, HFS_FILE_THREAD = 0x0300, 0x0400
HP_FOLDER, HP_FILE, HP_FOLDER_THREAD, HP_FILE_THREAD = 1, 2, 3, 4

DATA_FORK, RSRC_FORK = 0x00, 0xFF

UNMOUNTED_BIT = 1 << 8      # kHFSVolumeUnmountedMask

MAC_EPOCH_DELTA = 2082844800   # seconds from 1904-01-01 to 1970-01-01


def u8(b, o):
    return b[o]


def s8(b, o):
    return struct.unpack_from(">b", b, o)[0]


def u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def s16(b, o):
    return struct.unpack_from(">h", b, o)[0]


def u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def u64(b, o):
    return struct.unpack_from(">Q", b, o)[0]


_tables = {}


def _table(name):
    if name not in _tables:
        text = open(TABLES, encoding="latin-1").read()
        m = re.search(name + r"\[\]\s*=\s*\{(.*?)\};", text, re.S)
        body = re.sub(r"//[^\n]*|/\*.*?\*/", "", m.group(1), flags=re.S)
        _tables[name] = [int(x, 16) for x in re.findall(r"0x[0-9A-Fa-f]+", body)]
    return _tables[name]


def fold_unicode(units):
    """The character sequence FastUnicodeCompare actually compares: each
    UTF-16 unit case-folded through gLowerCaseTable, ignorables dropped."""
    t = _table("gLowerCaseTable")
    out = []
    for c in units:
        sub = t[c >> 8]
        if sub:
            c = t[sub + (c & 0xFF)]
        if c:
            out.append(c)
    return out


def unicode_compare(a, b):
    """FastUnicodeCompare (UnicodeWrappers.c): -1, 0 or 1."""
    fa, fb = fold_unicode(a), fold_unicode(b)
    return (fa > fb) - (fa < fb)


def relstring_compare(a, b):
    """FastRelString (UnicodeWrappers.c) over two Mac Roman byte strings."""
    t = _table("gCompareTable")
    best = (len(a) > len(b)) - (len(a) < len(b))
    for x, y in zip(a, b):
        if x != y:
            sx, sy = t[x], t[y]
            if sx != sy:
                return 1 if sx > sy else -1
    return best


def cmp(a, b):
    return (a > b) - (a < b)


class Extent(object):
    __slots__ = ("start", "count")

    def __init__(self, start, count):
        self.start, self.count = start, count

    def __repr__(self):
        return "Extent(%d, %d)" % (self.start, self.count)


def hfs_extents(b, o):
    """An HFSExtentRecord: three (UInt16 start, UInt16 count)."""
    return [Extent(u16(b, o + 4 * i), u16(b, o + 4 * i + 2)) for i in range(3)]


def plus_extents(b, o):
    """An HFSPlusExtentRecord: eight (UInt32 start, UInt32 count)."""
    return [Extent(u32(b, o + 8 * i), u32(b, o + 8 * i + 4)) for i in range(8)]


class ForkData(object):
    """HFSPlusForkData, or the HFS equivalent assembled from a file record."""

    def __init__(self, logical_size, total_blocks, extents, clump=0):
        self.logical_size = logical_size
        self.total_blocks = total_blocks
        self.extents = extents
        self.clump = clump


def plus_fork(b, o):
    return ForkData(u64(b, o), u32(b, o + 12), plus_extents(b, o + 16), u32(b, o + 8))


class MDB(object):
    """HFSMasterDirectoryBlock, 162 bytes at volume offset 1024."""

    def __init__(self, b):
        self.raw = bytes(b[:162])
        self.sig = u16(b, 0)
        self.cr_date = u32(b, 2)
        self.ls_mod = u32(b, 6)
        self.atrb = u16(b, 10)
        self.nm_fls = u16(b, 12)
        self.vbm_st = u16(b, 14)
        self.alloc_ptr = u16(b, 16)
        self.nm_al_blks = u16(b, 18)
        self.al_blk_siz = u32(b, 20)
        self.clp_siz = u32(b, 24)
        self.al_bl_st = u16(b, 28)
        self.nxt_cnid = u32(b, 30)
        self.free_bks = u16(b, 34)
        self.vn = bytes(b[37:37 + b[36]])
        self.vol_bk_up = u32(b, 64)
        self.v_seq_num = u16(b, 68)
        self.wr_cnt = u32(b, 70)
        self.xt_clp_siz = u32(b, 74)
        self.ct_clp_siz = u32(b, 78)
        self.nm_rt_dirs = u16(b, 82)
        self.fil_cnt = u32(b, 84)
        self.dir_cnt = u32(b, 88)
        self.fndr_info = bytes(b[92:124])
        self.embed_sig = u16(b, 124)
        self.embed_start = u16(b, 126)
        self.embed_count = u16(b, 128)
        self.xt_fl_size = u32(b, 130)
        self.xt_ext_rec = hfs_extents(b, 134)
        self.ct_fl_size = u32(b, 146)
        self.ct_ext_rec = hfs_extents(b, 150)


class VolumeHeader(object):
    """HFSPlusVolumeHeader, 512 bytes at volume offset 1024."""

    def __init__(self, b):
        self.raw = bytes(b[:512])
        self.sig = u16(b, 0)
        self.version = u16(b, 2)
        self.attributes = u32(b, 4)
        self.last_mounted_version = bytes(b[8:12])
        self.create_date = u32(b, 16)
        self.modify_date = u32(b, 20)
        self.backup_date = u32(b, 24)
        self.checked_date = u32(b, 28)
        self.file_count = u32(b, 32)
        self.folder_count = u32(b, 36)
        self.block_size = u32(b, 40)
        self.total_blocks = u32(b, 44)
        self.free_blocks = u32(b, 48)
        self.next_allocation = u32(b, 52)
        self.rsrc_clump = u32(b, 56)
        self.data_clump = u32(b, 60)
        self.next_catalog_id = u32(b, 64)
        self.write_count = u32(b, 68)
        self.encodings_bitmap = u64(b, 72)
        self.finder_info = bytes(b[80:112])
        self.allocation_file = plus_fork(b, 112)
        self.extents_file = plus_fork(b, 192)
        self.catalog_file = plus_fork(b, 272)
        self.attributes_file = plus_fork(b, 352)
        self.startup_file = plus_fork(b, 432)
```

- [ ] **Step 4: Write `tools/hfsimg/volume.py`**

```python
"""Read-only access to an HFS, HFS Plus or wrapped HFS Plus volume image."""

import struct

from hfsfmt import (
    HFS_SIG, HFSPLUS_SIG, EXTENTS_ID, CATALOG_ID, ALLOCATION_ID, STARTUP_ID,
    ATTRIBUTES_ID, ROOT_FOLDER_ID, LEAF, INDEX, HEADER, MAP,
    HFS_FOLDER, HFS_FILE, HFS_FOLDER_THREAD, HFS_FILE_THREAD,
    HP_FOLDER, HP_FILE, HP_FOLDER_THREAD, HP_FILE_THREAD, DATA_FORK, RSRC_FORK,
    MDB, VolumeHeader, ForkData, Extent, hfs_extents, plus_extents, plus_fork,
    u8, s8, u16, s16, u32, unicode_compare, relstring_compare, cmp)


class FormatError(Exception):
    pass


class Node(object):
    """One B-tree node: descriptor, record offsets and raw bytes."""

    def __init__(self, num, raw):
        self.num = num
        self.raw = raw
        self.flink = u32(raw, 0)
        self.blink = u32(raw, 4)
        self.kind = s8(raw, 8)
        self.height = u8(raw, 9)
        self.nrecs = u16(raw, 10)
        size = len(raw)
        if 14 + 2 * (self.nrecs + 1) > size:
            raise FormatError("node %d: %d records cannot fit" % (num, self.nrecs))
        # offsets[i] is the start of record i; offsets[nrecs] is free space
        self.offsets = [u16(raw, size - 2 * (i + 1)) for i in range(self.nrecs + 1)]

    def record(self, i):
        return self.raw[self.offsets[i]:self.offsets[i + 1]]


class BTree(object):
    """A catalog or extents B-tree, read whole into memory."""

    def __init__(self, vol, file_id, data):
        self.vol = vol
        self.file_id = file_id
        self.data = data
        if len(data) < 512:
            raise FormatError("B-tree %d: file is %d bytes" % (file_id, len(data)))
        h = data[14:14 + 106]
        self.tree_depth = u16(h, 0)
        self.root_node = u32(h, 2)
        self.leaf_records = u32(h, 6)
        self.first_leaf = u32(h, 10)
        self.last_leaf = u32(h, 14)
        self.node_size = u16(h, 18)
        self.max_key_length = u16(h, 20)
        self.total_nodes = u32(h, 22)
        self.free_nodes = u32(h, 26)
        self.clump_size = u32(h, 32)
        self.btree_type = u8(h, 36)
        self.attributes = u32(h, 38)
        if self.node_size not in (512, 1024, 2048, 4096, 8192, 16384, 32768):
            raise FormatError("B-tree %d: node size %d" % (file_id, self.node_size))

    def node(self, n):
        ns = self.node_size
        if n >= self.total_nodes or (n + 1) * ns > len(self.data):
            raise FormatError("B-tree %d: node %d out of range" % (self.file_id, n))
        return Node(n, self.data[n * ns:(n + 1) * ns])

    # --- keys -----------------------------------------------------------
    def split(self, rec):
        """(key bytes including its length field, data bytes) of a record."""
        if self.vol.plus:
            klen = u16(rec, 0)
            return rec[:2 + klen], rec[2 + klen:]
        klen = u8(rec, 0)
        return rec[:1 + klen], rec[(klen + 2) & ~1:]

    def key_value(self, key):
        """A comparable tuple for a key, following the kernel's compare."""
        if self.file_id == EXTENTS_ID:
            if self.vol.plus:
                return (u32(key, 4), u8(key, 2), u32(key, 8))
            return (u32(key, 2), u8(key, 1), u16(key, 6))
        if self.vol.plus:
            n = u16(key, 6)
            return (u32(key, 2), tuple(struct.unpack_from(">%dH" % n, key, 8)))
        return (u32(key, 2), bytes(key[7:7 + key[6]]))

    def compare(self, a, b):
        """-1/0/1 for two key_value tuples, as the kernel orders them."""
        if self.file_id == EXTENTS_ID:
            return cmp(a, b)
        if a[0] != b[0]:
            return cmp(a[0], b[0])
        if self.vol.plus:
            return unicode_compare(list(a[1]), list(b[1]))
        return relstring_compare(a[1], b[1])

    def leaf_records_iter(self):
        """Yield (key_value, key bytes, data bytes) in leaf-chain order."""
        n = self.first_leaf
        seen = set()
        while n:
            if n in seen:
                raise FormatError("B-tree %d: leaf chain loops at %d" % (self.file_id, n))
            seen.add(n)
            node = self.node(n)
            for i in range(node.nrecs):
                k, d = self.split(node.record(i))
                yield self.key_value(k), k, d
            n = node.flink


class Entry(object):
    """A catalog file or folder."""

    def __init__(self, cnid, parent, name, is_dir):
        self.cnid, self.parent, self.name, self.is_dir = cnid, parent, name, is_dir
        self.valence = 0
        self.data = None
        self.rsrc = None
        self.thread = None      # (type, parent, name) from the thread record
        self.thread_expected = True


class Volume(object):
    def __init__(self, path, offset=0):
        self.f = open(path, "rb")
        self.path = path
        self.base = offset
        self.wrapper = None
        head = self.read_at(offset + 1024, 512)
        sig = u16(head, 0)
        if sig == HFSPLUS_SIG:
            self._init_plus(offset, head)
        elif sig == HFS_SIG:
            mdb = MDB(head)
            if mdb.embed_sig == HFSPLUS_SIG:
                self.wrapper = mdb
                plus_base = (offset + mdb.al_bl_st * 512
                             + mdb.embed_start * mdb.al_blk_siz)
                self._init_plus(plus_base, self.read_at(plus_base + 1024, 512))
            else:
                self._init_hfs(offset, mdb)
        else:
            raise FormatError("no HFS signature at %d (found 0x%04x)" % (offset + 1024, sig))
        self._overflow = None
        self.extents = BTree(self, EXTENTS_ID, self.read_fork(self.special_fork(EXTENTS_ID), EXTENTS_ID))
        self.catalog = BTree(self, CATALOG_ID, self.read_fork(self.special_fork(CATALOG_ID), CATALOG_ID))

    def close(self):
        self.f.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def read_at(self, off, n):
        self.f.seek(off)
        b = self.f.read(n)
        if len(b) != n:
            raise FormatError("short read at %d" % off)
        return b

    def _init_plus(self, base, head):
        self.plus = True
        self.vh = VolumeHeader(head)
        if self.vh.sig != HFSPLUS_SIG:
            raise FormatError("embedded volume has no H+ signature")
        self.vol_base = base
        self.block_size = self.vh.block_size
        self.total_blocks = self.vh.total_blocks
        self.free_blocks = self.vh.free_blocks
        self.alloc_base = base

    def _init_hfs(self, base, mdb):
        self.plus = False
        self.mdb = mdb
        self.vol_base = base
        self.block_size = mdb.al_blk_siz
        self.total_blocks = mdb.nm_al_blks
        self.free_blocks = mdb.free_bks
        self.alloc_base = base + mdb.al_bl_st * 512

    def block_offset(self, n):
        return self.alloc_base + n * self.block_size

    # --- forks ----------------------------------------------------------
    def special_fork(self, file_id):
        if self.plus:
            return {EXTENTS_ID: self.vh.extents_file, CATALOG_ID: self.vh.catalog_file,
                    ALLOCATION_ID: self.vh.allocation_file,
                    STARTUP_ID: self.vh.startup_file,
                    ATTRIBUTES_ID: self.vh.attributes_file}[file_id]
        m = self.mdb
        size, ext = {EXTENTS_ID: (m.xt_fl_size, m.xt_ext_rec),
                     CATALOG_ID: (m.ct_fl_size, m.ct_ext_rec)}[file_id]
        return ForkData(size, sum(e.count for e in ext), ext)

    def overflow_extents(self, file_id, fork_type):
        """Extents-overflow records for one fork, in startBlock order."""
        if file_id == EXTENTS_ID:
            return []
        out = []
        for kv, key, data in self.extents.leaf_records_iter():
            if kv[0] == file_id and kv[1] == fork_type:
                ext = plus_extents(data, 0) if self.plus else hfs_extents(data, 0)
                out.append((kv[2], ext))
        return out

    def fork_extents(self, fork, file_id, fork_type=DATA_FORK):
        """Every extent of a fork, first record plus overflow, in order."""
        exts = [e for e in fork.extents if e.count]
        for start, ext in self.overflow_extents(file_id, fork_type):
            if start != sum(e.count for e in exts):
                raise FormatError("file %d fork %d: overflow record at block %d, expected %d"
                                  % (file_id, fork_type, start, sum(e.count for e in exts)))
            exts.extend(e for e in ext if e.count)
        return exts

    def read_fork(self, fork, file_id, fork_type=DATA_FORK):
        if file_id == EXTENTS_ID or not hasattr(self, "extents"):
            exts = [e for e in fork.extents if e.count]
        else:
            exts = self.fork_extents(fork, file_id, fork_type)
        chunks = []
        for e in exts:
            chunks.append(self.read_at(self.block_offset(e.start), e.count * self.block_size))
        data = b"".join(chunks)
        if len(data) < fork.logical_size:
            raise FormatError("file %d: fork holds %d bytes, logical size %d"
                              % (file_id, len(data), fork.logical_size))
        return data[:fork.logical_size]

    # --- catalog --------------------------------------------------------
    def entries(self):
        """Every catalog file and folder, keyed by CNID."""
        ents = {}
        threads = {}
        for kv, key, d in self.catalog.leaf_records_iter():
            parent, name = kv
            rtype = s16(d, 0)
            if self.plus:
                if rtype == HP_FOLDER:
                    e = Entry(u32(d, 8), parent, name, True)
                    e.valence = u32(d, 4)
                elif rtype == HP_FILE:
                    e = Entry(u32(d, 8), parent, name, False)
                    e.data, e.rsrc = plus_fork(d, 88), plus_fork(d, 168)
                elif rtype in (HP_FOLDER_THREAD, HP_FILE_THREAD):
                    n = u16(d, 8)
                    threads[parent] = (rtype, u32(d, 4),
                                       tuple(struct.unpack_from(">%dH" % n, d, 10)))
                    continue
                else:
                    raise FormatError("catalog record type %d" % rtype)
            else:
                if rtype == HFS_FOLDER:
                    e = Entry(u32(d, 6), parent, name, True)
                    e.valence = u16(d, 4)
                elif rtype == HFS_FILE:
                    e = Entry(u32(d, 20), parent, name, False)
                    e.thread_expected = bool(d[2] & 0x02)    # kHFSThreadExistsMask
                    e.data = ForkData(u32(d, 26), 0, hfs_extents(d, 74))
                    e.rsrc = ForkData(u32(d, 36), 0, hfs_extents(d, 86))
                elif rtype in (HFS_FOLDER_THREAD, HFS_FILE_THREAD):
                    threads[parent] = (rtype, u32(d, 10), bytes(d[15:15 + d[14]]))
                    continue
                else:
                    raise FormatError("catalog record type 0x%04x" % rtype)
            ents[e.cnid] = e
        for cnid, t in threads.items():
            if cnid in ents:
                ents[cnid].thread = t
        self.threads = threads
        return ents

    def name_str(self, name):
        if self.plus:
            return struct.pack(">%dH" % len(name), *name).decode("utf-16-be")
        return name.decode("mac_roman")

    def walk(self):
        """Yield (path, Entry) for everything under the root, sorted by path."""
        ents = self.entries()
        kids = {}
        for e in ents.values():
            kids.setdefault(e.parent, []).append(e)
        out = []

        def rec(cnid, prefix):
            for e in kids.get(cnid, []):
                p = prefix + "/" + self.name_str(e.name)
                out.append((p, e))
                if e.is_dir:
                    rec(e.cnid, p)
        rec(ROOT_FOLDER_ID, "")
        return sorted(out, key=lambda t: t[0])

    def read_file(self, entry):
        return self.read_fork(entry.data, entry.cnid, DATA_FORK)
```

- [ ] **Step 5: Run the tests**

Run: `python -m pytest tools/hfsimg/tests/test_reader.py -v`
Expected: 4 passed. If the two toast tests are skipped, `RHAP_VM_ASSETS` is not exported. Fix that; a skip here is not a pass.

- [ ] **Step 6: Commit**

```bash
git add tools/hfsimg/hfsfmt.py tools/hfsimg/volume.py tools/hfsimg/tests/conftest.py tools/hfsimg/tests/test_reader.py
git commit -m "tools: read HFS, HFS Plus and wrapped volume images, ordering keys with the kernel's own tables"
```

---

### Task 3: HFS consistency checker

**Files:**
- Create: `tools/hfsimg/check.py`
- Test: `tools/hfsimg/tests/test_check.py`

**Interfaces:**
- Consumes: `volume.Volume`, `volume.FormatError` (Task 2).
- Produces: `check.check(volume) -> [str]`. An empty list means consistent; each string names one problem.

- [ ] **Step 1: Write the failing test**

```python
import struct

import pytest

import check
import volume


class Patched(volume.Volume):
    """A volume whose reads see some bytes replaced."""
    patches = {}

    def read_at(self, off, n):
        b = bytearray(volume.Volume.read_at(self, off, n))
        for at, data in self.patches.items():
            for i, x in enumerate(data):
                if off <= at + i < off + n:
                    b[at + i - off] = x
        return bytes(b)


def test_the_apple_volume_is_consistent(toast):
    assert check.check(toast) == []


def _catalog_node_offset(v, node):
    return v.block_offset(v.vh.catalog_file.extents[0].start) + node * v.catalog.node_size


def _cases(v):
    vh = v.vol_base + 1024
    leaf = v.catalog.first_leaf
    node = v.catalog.node(leaf)
    at = _catalog_node_offset(v, leaf)
    bitmap = v.block_offset(v.vh.allocation_file.extents[0].start) + 20000 // 8
    return {
        "bitmap misses 1 owned blocks": {bitmap: bytes([v.read_at(bitmap, 1)[0] ^ 0x80])},
        "volume header counts 121 files": {vh + 32: struct.pack(">I", v.vh.file_count + 1)},
        "not cleanly unmounted": {vh + 4: struct.pack(">I", v.vh.attributes & ~0x100)},
        "keys out of order": {at + node.offsets[1] + 2: struct.pack(">I", 1)},
        "freeNodes 1007": {_catalog_node_offset(v, 0) + 14 + 26:
                           struct.pack(">I", v.catalog.free_nodes + 1)},
        "blink 77": {at + 4: struct.pack(">I", 77)},
    }


@pytest.mark.parametrize("expect", ["bitmap misses 1 owned blocks", "volume header counts 121 files",
                                    "not cleanly unmounted", "keys out of order",
                                    "freeNodes 1007", "blink 77"])
def test_each_kind_of_damage_is_reported(toast, toast_location, expect):
    Patched.patches = _cases(toast)[expect]
    damaged = Patched(*toast_location)
    try:
        problems = check.check(damaged)
    finally:
        damaged.close()
    assert any(expect in p for p in problems), problems
```

The damage tests matter as much as the clean one: a checker that reports nothing on a real Apple volume is only evidence if it demonstrably reports each kind of damage the kernel's writes could cause.

- [ ] **Step 2: Run it to make sure it fails**

Run: `python -m pytest tools/hfsimg/tests/test_check.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'check'`

- [ ] **Step 3: Write `tools/hfsimg/check.py`**

```python
"""Consistency checks for an HFS or HFS Plus volume image.

check(volume) returns a list of human-readable problems; an empty list means
the volume is consistent.  It checks what the kernel's writes can break: B-tree
structure, key order, node maps, the allocation bitmap against every extent,
folder valences, thread records and the volume counts.
"""

from hfsfmt import (
    EXTENTS_ID, CATALOG_ID, ALLOCATION_ID, STARTUP_ID, ATTRIBUTES_ID,
    BADBLOCK_ID, ROOT_FOLDER_ID, ROOT_PARENT_ID, LEAF, INDEX, HEADER, MAP,
    DATA_FORK, RSRC_FORK, UNMOUNTED_BIT, u16, u32)
from volume import FormatError


def _map_bits(tree, problems):
    """The node allocation map: header record 2, then chained map nodes."""
    tag = "B-tree %d" % tree.file_id
    hdr = tree.node(0)
    bits = bytearray(hdr.record(2))
    n = hdr.flink
    seen = {0}
    while n:
        if n in seen:
            problems.append("%s: map node chain loops at %d" % (tag, n))
            break
        seen.add(n)
        node = tree.node(n)
        if node.kind != MAP:
            problems.append("%s: node %d in the map chain has kind %d" % (tag, n, node.kind))
            break
        bits += node.record(0)
        n = node.flink
    used = set(i for i in range(min(tree.total_nodes, len(bits) * 8))
               if bits[i >> 3] & (0x80 >> (i & 7)))
    return used, seen


def check_btree(tree, problems):
    tag = "B-tree %d" % tree.file_id
    ns = tree.node_size
    if tree.total_nodes * ns != len(tree.data):
        problems.append("%s: totalNodes*nodeSize %d != file size %d"
                        % (tag, tree.total_nodes * ns, len(tree.data)))
    hdr = tree.node(0)
    if hdr.kind != HEADER or hdr.nrecs != 3:
        problems.append("%s: node 0 is not a 3-record header node" % tag)
        return
    used, map_nodes = _map_bits(tree, problems)
    if tree.free_nodes != tree.total_nodes - len(used):
        problems.append("%s: freeNodes %d, map says %d"
                        % (tag, tree.free_nodes, tree.total_nodes - len(used)))

    def node_ok(node):
        offs = node.offsets
        if offs[0] != 14:
            problems.append("%s: node %d first record at %d" % (tag, node.num, offs[0]))
            return False
        for i in range(node.nrecs):
            if offs[i + 1] <= offs[i]:
                problems.append("%s: node %d offsets not increasing at %d" % (tag, node.num, i))
                return False
        if offs[node.nrecs] > ns - 2 * (node.nrecs + 1):
            problems.append("%s: node %d records overlap the offset table" % (tag, node.num))
            return False
        return True

    reached = set(map_nodes)
    leaves = []
    total_leaf_records = 0
    if tree.root_node == 0:
        if tree.leaf_records or tree.tree_depth:
            problems.append("%s: empty tree with leafRecords/treeDepth set" % tag)
    else:
        # walk down from the root: (node number, expected height, lower bound key)
        stack = [(tree.root_node, tree.tree_depth, None)]
        while stack:
            num, height, first_key = stack.pop()
            if num in reached:
                problems.append("%s: node %d reached twice" % (tag, num))
                continue
            reached.add(num)
            node = tree.node(num)
            if node.height != height:
                problems.append("%s: node %d height %d, expected %d" % (tag, num, node.height, height))
            want = LEAF if height == 1 else INDEX
            if node.kind != want:
                problems.append("%s: node %d kind %d, expected %d" % (tag, num, node.kind, want))
                continue
            if not node_ok(node):
                continue
            keys = []
            for i in range(node.nrecs):
                k, d = tree.split(node.record(i))
                keys.append((tree.key_value(k), d))
            for i in range(1, len(keys)):
                if tree.compare(keys[i - 1][0], keys[i][0]) >= 0:
                    problems.append("%s: node %d keys out of order at record %d" % (tag, num, i))
            if first_key is not None and keys and tree.compare(first_key, keys[0][0]) != 0:
                problems.append("%s: node %d first key differs from its index key" % (tag, num))
            if node.kind == LEAF:
                leaves.append(num)
                total_leaf_records += node.nrecs
            else:
                for kv, d in reversed(keys):
                    stack.append((u32(d, 0), height - 1, kv))
    if total_leaf_records != tree.leaf_records:
        problems.append("%s: header leafRecords %d, tree holds %d"
                        % (tag, tree.leaf_records, total_leaf_records))
    # the leaf chain must visit the same leaves, in key order, doubly linked
    chain = []
    n, prev = tree.first_leaf, 0
    while n and len(chain) <= len(leaves):
        node = tree.node(n)
        if node.blink != prev:
            problems.append("%s: leaf %d blink %d, expected %d" % (tag, n, node.blink, prev))
        chain.append(n)
        prev, n = n, node.flink
    if sorted(chain) != sorted(leaves):
        problems.append("%s: leaf chain %s does not match the tree's leaves %s"
                        % (tag, chain[:8], sorted(leaves)[:8]))
    if leaves and chain and chain[-1] != tree.last_leaf:
        problems.append("%s: lastLeafNode %d, chain ends at %d" % (tag, tree.last_leaf, chain[-1]))
    prev_key = None
    for kv, k, d in tree.leaf_records_iter():
        if prev_key is not None and tree.compare(prev_key, kv) >= 0:
            problems.append("%s: leaf chain keys out of order" % tag)
            break
        prev_key = kv
    if reached != used:
        extra, missing = sorted(used - reached), sorted(reached - used)
        if extra:
            problems.append("%s: map marks unused nodes %s" % (tag, extra[:8]))
        if missing:
            problems.append("%s: map misses used nodes %s" % (tag, missing[:8]))


def _claim(owner, exts, claimed, problems, total):
    for e in exts:
        for b in range(e.start, e.start + e.count):
            if b >= total:
                problems.append("%s: block %d beyond the volume" % (owner, b))
                return
            if b in claimed:
                problems.append("%s: block %d also belongs to %s" % (owner, b, claimed[b]))
                return
            claimed[b] = owner


def check_allocation(vol, ents, problems):
    total = vol.total_blocks
    claimed = {}
    specials = [EXTENTS_ID, CATALOG_ID]
    if vol.plus:
        specials += [ALLOCATION_ID, STARTUP_ID, ATTRIBUTES_ID]
    for fid in specials:
        fork = vol.special_fork(fid)
        _claim("special file %d" % fid, vol.fork_extents(fork, fid), claimed, problems, total)
    for e in ents.values():
        if e.is_dir:
            continue
        for fork, ftype in ((e.data, DATA_FORK), (e.rsrc, RSRC_FORK)):
            exts = vol.fork_extents(fork, e.cnid, ftype)
            blocks = sum(x.count for x in exts)
            if blocks * vol.block_size < fork.logical_size:
                problems.append("file %d fork %d: %d blocks hold less than %d bytes"
                                % (e.cnid, ftype, blocks, fork.logical_size))
            _claim("file %d fork %d" % (e.cnid, ftype), exts, claimed, problems, total)
    if vol.plus:
        # blocks holding the first 1536 bytes and the last 1024 bytes of the volume
        bs = vol.block_size
        reserved = set(range(0, (1536 + bs - 1) // bs))
        end = total * bs
        reserved |= set(range((end - 1024) // bs, total))
        for b in reserved:
            if b in claimed:
                problems.append("reserved block %d belongs to %s" % (b, claimed[b]))
            claimed.setdefault(b, "volume header area")
        bitmap = vol.read_fork(vol.vh.allocation_file, ALLOCATION_ID)
    else:
        m = vol.mdb
        nbytes = (total + 7) // 8
        bitmap = vol.read_at(vol.vol_base + m.vbm_st * 512, nbytes)
    set_bits = set(b for b in range(total) if bitmap[b >> 3] & (0x80 >> (b & 7)))
    orphan = sorted(set_bits - set(claimed))
    lost = sorted(set(claimed) - set_bits)
    if orphan:
        problems.append("bitmap marks %d unowned blocks, first %s" % (len(orphan), orphan[:8]))
    if lost:
        problems.append("bitmap misses %d owned blocks, first %s" % (len(lost), lost[:8]))
    if vol.free_blocks != total - len(set_bits):
        problems.append("free block count %d, bitmap says %d"
                        % (vol.free_blocks, total - len(set_bits)))


def check_catalog(vol, ents, problems):
    children = {}
    for e in ents.values():
        children.setdefault(e.parent, []).append(e)
    if ROOT_FOLDER_ID not in ents or ents[ROOT_FOLDER_ID].parent != ROOT_PARENT_ID:
        problems.append("catalog: no root folder")
    for e in ents.values():
        if e.thread is None:
            if e.thread_expected:
                problems.append("catalog: CNID %d has no thread record" % e.cnid)
        elif e.thread[1] != e.parent or e.thread[2] != e.name:
            problems.append("catalog: CNID %d thread record disagrees with its key" % e.cnid)
        if e.is_dir and e.valence != len(children.get(e.cnid, [])):
            problems.append("catalog: folder %d valence %d, holds %d"
                            % (e.cnid, e.valence, len(children.get(e.cnid, []))))
        if e.cnid != ROOT_FOLDER_ID and e.parent not in ents:
            problems.append("catalog: CNID %d parent %d missing" % (e.cnid, e.parent))
    for cnid in vol.threads:
        if cnid not in ents:
            problems.append("catalog: thread record for missing CNID %d" % cnid)
    files = sum(1 for e in ents.values() if not e.is_dir)
    folders = sum(1 for e in ents.values() if e.is_dir) - 1
    max_id = max(ents) if ents else 0
    if vol.plus:
        vh = vol.vh
        if vh.file_count != files or vh.folder_count != folders:
            problems.append("volume header counts %d files %d folders, catalog has %d/%d"
                            % (vh.file_count, vh.folder_count, files, folders))
        if vh.next_catalog_id <= max_id:
            problems.append("nextCatalogID %d not above %d" % (vh.next_catalog_id, max_id))
    else:
        m = vol.mdb
        root_kids = children.get(ROOT_FOLDER_ID, [])
        if m.fil_cnt != files or m.dir_cnt != folders:
            problems.append("MDB counts %d files %d folders, catalog has %d/%d"
                            % (m.fil_cnt, m.dir_cnt, files, folders))
        if m.nm_fls != sum(1 for e in root_kids if not e.is_dir) or \
                m.nm_rt_dirs != sum(1 for e in root_kids if e.is_dir):
            problems.append("MDB root counts disagree with the catalog")
        if m.nxt_cnid <= max_id:
            problems.append("drNxtCNID %d not above %d" % (m.nxt_cnid, max_id))


def check(vol):
    problems = []
    try:
        attrs = vol.vh.attributes if vol.plus else vol.mdb.atrb
        if not attrs & UNMOUNTED_BIT:
            problems.append("volume was not cleanly unmounted")
        check_btree(vol.extents, problems)
        check_btree(vol.catalog, problems)
        ents = vol.entries()
        check_catalog(vol, ents, problems)
        check_allocation(vol, ents, problems)
    except FormatError as e:
        problems.append("format error: %s" % e)
    return problems
```

- [ ] **Step 4: Run the tests**

Run: `python -m pytest tools/hfsimg/tests/test_check.py -v`
Expected: 7 passed (the clean Apple volume and six kinds of damage).

- [ ] **Step 5: Commit**

```bash
git add tools/hfsimg/check.py tools/hfsimg/tests/test_check.py
git commit -m "tools: check HFS volumes for B-tree, node-map, bitmap and catalog damage"
```

---

### Task 4: Image builder, contents and the test scenario

**Files:**
- Create: `tools/hfsimg/content.py`, `tools/hfsimg/builder.py`, `tools/hfsimg/scenario.py`
- Test: `tools/hfsimg/tests/test_builder.py`, `tools/hfsimg/tests/test_scenario.py`

**Interfaces:**
- Consumes: `hfsfmt`, `volume.Volume`, `check.check`.
- Produces: `content.data(name, size) -> bytes`, `content.cksum(bytes) -> int`, `content.GUEST_PERL`.
- Produces: `builder.BUILDERS = {"hfs": build_hfs, "hfsplus": build_plus, "wrapped": build_wrapped}`. Each takes `(manifest, size_bytes)` and returns the volume bytes, with no disk label.
- Produces: `scenario.base_manifest()`, `scenario.tree(manifest) -> {path: size or None}`, `scenario.expected_after_write(manifest)`, `scenario.content_name(path)`, `scenario.write_script(device)`, `scenario.read_script(device, read_only=False, sample=None)`, `scenario.parse_list(text)`, `scenario.parse_sums(text)`, `scenario.expected_sums(tree, name_of)`, `scenario.MOUNT_POINT`, `scenario.BIG_SIZE`, `scenario.new_file_size(i)`.

- [ ] **Step 1: Write the failing tests**

`tools/hfsimg/tests/test_builder.py`:

```python
import unicodedata

import pytest

import builder
import check
import content
import scenario
import volume

SIZE = 40 * 1024 * 1024


def nfc(s):
    return unicodedata.normalize("NFC", s)


@pytest.fixture(params=["hfsplus", "hfs", "wrapped"])
def built(request, tmp_path):
    path = tmp_path / ("%s.img" % request.param)
    path.write_bytes(builder.BUILDERS[request.param](scenario.base_manifest(), SIZE))
    v = volume.Volume(str(path))
    yield request.param, v
    v.close()


def test_built_volume_is_consistent(built):
    assert check.check(built[1]) == []


def test_built_volume_holds_the_manifest(built):
    flavour, v = built
    walk = v.walk()
    got = dict((nfc(p[1:]), None if e.is_dir else e.data.logical_size) for p, e in walk)
    assert got == scenario.tree(scenario.base_manifest())
    for p, e in walk:
        if not e.is_dir:
            assert v.read_file(e) == content.data(nfc(p[1:]), e.data.logical_size), p


def test_built_volume_exercises_the_interesting_paths(built):
    flavour, v = built
    assert v.catalog.tree_depth >= 2
    assert v.extents.leaf_records >= 1          # frag.bin overflows its record
    assert v.total_blocks > 4096                # more than one bitmap I/O block
    assert (v.wrapper is not None) == (flavour == "wrapped")
    assert v.plus == (flavour != "hfs")


def test_hfs_plus_names_are_stored_decomposed(tmp_path):
    path = tmp_path / "p.img"
    path.write_bytes(builder.build_plus(scenario.base_manifest(), SIZE))
    with volume.Volume(str(path)) as v:
        names = [e.name for e in v.entries().values()]
    assert (0x0065, 0x0301) in [n[3:5] for n in names if len(n) > 4]


def test_cksum_matches_posix():
    assert content.cksum(b"") == 4294967295
    assert content.cksum(b"hello\n") == 3015617425
    assert content.cksum(b"a") == 1220704766


def test_content_is_the_name_repeated():
    assert content.data("ab", 7) == b"ab\nab\na"
    assert content.data("x", 0) == b""
```

`tools/hfsimg/tests/test_scenario.py`:

```python
import scenario


def test_write_model():
    t = scenario.expected_after_write(scenario.base_manifest())
    assert "frag.bin" not in t and "w/d19" not in t and "w/f025" not in t
    assert t["w/r010"] == scenario.new_file_size(10)
    assert t["w/d00/f011"] == scenario.new_file_size(11)
    assert t["w/big"] == scenario.BIG_SIZE and t["top.txt"] == 5000
    assert t["w/d05/x"] == 100 and t["w/d05"] is None
    assert scenario.content_name("w/r010") == "w/f010"
    assert scenario.content_name("top.txt") == "top.txt"


def test_write_script_mirrors_the_model():
    s = scenario.write_script("/dev/hd1a")
    assert "/mnt/mount_hfs /dev/hd1a /mnt/h" in s
    assert "expr $i \\* 1499 % 30000" in s
    assert "mv w/f010 w/r010" in s and "rm frag.bin" in s
    assert "P w/big %d" % scenario.BIG_SIZE in s
    assert s.rstrip().endswith("sync")


def test_read_script_options():
    assert "/mnt/mount_hfs -o ro /dev/hd1a" in scenario.read_script("/dev/hd1a", read_only=True)
    s = scenario.read_script("/dev/hd1a", sample=["a b", "c"])
    assert "cksum './a b'; cksum './c'" in s


def test_parsers():
    assert scenario.parse_list(".\n./a\n./a/b c\n") == {"a", "a/b c"}
    assert scenario.parse_sums("1 2 ./a b\n3 4 ./c\n") == {"a b": (1, 2), "c": (3, 4)}
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `python -m pytest tools/hfsimg/tests/test_builder.py tools/hfsimg/tests/test_scenario.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'builder'`

- [ ] **Step 3: Write `tools/hfsimg/content.py`**

```python
"""Deterministic file contents and POSIX cksum, mirrored by the guest script.

A file's contents are its name followed by a newline, repeated and cut to
length.  The guest regenerates the same bytes with the one-line perl in
GUEST_PERL, so nothing large ever has to cross the serial console.
"""

GUEST_PERL = ("perl -e 'print substr(($ARGV[0].\"\\n\") x "
              "(int($ARGV[1]/(1+length $ARGV[0]))+1), 0, $ARGV[1])'")


def data(name, size):
    unit = name.encode("utf-8") + b"\n"
    return (unit * (size // len(unit) + 1))[:size]


def _crc_table():
    table = []
    for i in range(256):
        c = i << 24
        for _ in range(8):
            c = ((c << 1) ^ 0x04C11DB7) if c & 0x80000000 else (c << 1)
        table.append(c & 0xFFFFFFFF)
    return table


_TABLE = _crc_table()


def cksum(b):
    """The CRC printed by POSIX cksum(1)."""
    crc = 0
    for x in b:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _TABLE[(crc >> 24) ^ x]
    n = len(b)
    while n:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _TABLE[(crc >> 24) ^ (n & 0xFF)]
        n >>= 8
    return (~crc) & 0xFFFFFFFF
```

- [ ] **Step 4: Write `tools/hfsimg/builder.py`**

```python
"""Build HFS, HFS Plus and wrapped HFS Plus volume images from a manifest.

A manifest is a list of ("dir", path) and ("file", path, size) entries with
"/"-separated paths relative to the volume root; parents come before their
children.  File contents come from content.data(path, size).  A ("frag",
path, size, pieces) entry makes a file whose data is split into that many
separate extents, to force extents-overflow records.
"""

import functools
import struct
import unicodedata

import content
from hfsfmt import (
    HFS_SIG, HFSPLUS_SIG, HFSPLUS_VERSION, ROOT_PARENT_ID, ROOT_FOLDER_ID,
    EXTENTS_ID, CATALOG_ID, FIRST_USER_ID, LEAF, INDEX, HEADER,
    HFS_FOLDER, HFS_FILE, HFS_FOLDER_THREAD, HFS_FILE_THREAD,
    HP_FOLDER, HP_FILE, HP_FOLDER_THREAD, HP_FILE_THREAD, DATA_FORK,
    UNMOUNTED_BIT, unicode_compare, relstring_compare, cmp)

DATE = 3029529600            # 2000-01-01 00:00:00 in Mac time
BIG_KEYS, VAR_INDEX_KEYS = 0x2, 0x4


def _cmp_key(plus, is_catalog):
    def compare(a, b):
        if not is_catalog:
            return cmp(a, b)
        if a[0] != b[0]:
            return cmp(a[0], b[0])
        if plus:
            return unicode_compare(list(a[1]), list(b[1]))
        return relstring_compare(a[1], b[1])
    return compare


class TreeSpec(object):
    """Everything needed to lay out one B-tree file."""

    def __init__(self, plus, is_catalog, node_size, total_nodes):
        self.plus, self.is_catalog = plus, is_catalog
        self.node_size, self.total_nodes = node_size, total_nodes
        if plus:
            self.max_key = 516 if is_catalog else 10
            self.attributes = BIG_KEYS | (VAR_INDEX_KEYS if is_catalog else 0)
        else:
            self.max_key = 37 if is_catalog else 7
            self.attributes = 0


def _index_key(spec, key):
    """HFS index keys are padded to the maximum key length; HFS Plus
    catalog index keys are variable length, extents keys are fixed."""
    if spec.plus:
        return key
    k = bytes([spec.max_key]) + key[1:] + b"\0" * (spec.max_key + 1 - len(key))
    return k + b"\0" * (len(k) & 1)


def _node(kind, height, records, flink, blink, size):
    buf = bytearray(size)
    struct.pack_into(">IIbBHH", buf, 0, flink, blink, kind, height, len(records), 0)
    off = 14
    for i, r in enumerate(records):
        buf[off:off + len(r)] = r
        struct.pack_into(">H", buf, size - 2 * (i + 1), off)
        off += len(r)
    struct.pack_into(">H", buf, size - 2 * (len(records) + 1), off)
    return buf


def _fits(records, size):
    return 14 + sum(len(r) for r in records) + 2 * (len(records) + 1) <= size


def _layout(spec, records):
    """Pack sorted records into leaf and index nodes numbered from 1.
    Returns (nodes, used, depth, root, first_leaf, last_leaf, nrecords)."""
    ns = spec.node_size
    compare = _cmp_key(spec.plus, spec.is_catalog)
    records = sorted(records, key=functools.cmp_to_key(lambda a, b: compare(a[0], b[0])))
    nodes = {}                      # number -> bytearray
    next_num = [1]

    def pack_level(recs, kind, height):
        """recs: list of (first key, record bytes). Returns [(num, first key)]."""
        groups, cur = [], []
        for first, r in recs:
            if cur and not _fits([x[1] for x in cur] + [r], ns):
                groups.append(cur)
                cur = []
            cur.append((first, r))
        if cur:
            groups.append(cur)
        nums = list(range(next_num[0], next_num[0] + len(groups)))
        next_num[0] += len(groups)
        for i, g in enumerate(groups):
            flink = nums[i + 1] if i + 1 < len(groups) else 0
            blink = nums[i - 1] if i else 0
            nodes[nums[i]] = _node(kind, height, [r for _, r in g], flink, blink, ns)
        return [(nums[i], g[0][0]) for i, g in enumerate(groups)]

    depth = root = first_leaf = last_leaf = 0
    if records:
        level = pack_level([(key, key + data) for _, key, data in records], LEAF, 1)
        first_leaf, last_leaf = level[0][0], level[-1][0]
        depth = 1
        while len(level) > 1:
            depth += 1
            level = pack_level([(k, _index_key(spec, k) + struct.pack(">I", n))
                                for n, k in level], INDEX, depth)
        root = level[0][0]
    return nodes, next_num[0], depth, root, first_leaf, last_leaf, len(records)


def build_tree(spec, records, clump):
    """records: list of (sort value, key bytes, data bytes), any order.
    Returns the B-tree file bytes (total_nodes * node_size)."""
    ns = spec.node_size
    nodes, used, depth, root, first_leaf, last_leaf, nrec = _layout(spec, records)
    if used > spec.total_nodes:
        raise ValueError("B-tree needs %d nodes, has %d" % (used, spec.total_nodes))
    map_bytes = ns - 14 - 106 - 128 - 8
    if spec.total_nodes > map_bytes * 8:
        raise ValueError("B-tree too large for a header-only node map")
    header = struct.pack(">HIIIIHHIIHIBBI64x", depth, root, nrec, first_leaf,
                         last_leaf, ns, spec.max_key, spec.total_nodes,
                         spec.total_nodes - used, 0, clump, 0, 0, spec.attributes)
    bitmap = bytearray(map_bytes)
    for i in range(used):
        bitmap[i >> 3] |= 0x80 >> (i & 7)
    nodes[0] = _node(HEADER, 0, [header, b"\0" * 128, bytes(bitmap)], 0, 0, ns)
    out = bytearray(spec.total_nodes * ns)
    for n, b in nodes.items():
        out[n * ns:(n + 1) * ns] = b
    return bytes(out)


class _Alloc(object):
    """Sequential allocation-block allocator with a bitmap."""

    def __init__(self, total):
        self.total = total
        self.bits = bytearray((total + 7) // 8)
        self.next = 0

    def mark(self, start, count):
        for b in range(start, start + count):
            self.bits[b >> 3] |= 0x80 >> (b & 7)

    def take(self, count, gap=0):
        start = self.next
        if start + count > self.total:
            raise ValueError("volume full")
        self.mark(start, count)
        self.next = start + count + gap
        return start

    def used(self):
        return sum(bin(x).count("1") for x in self.bits)


def _names(manifest):
    """Assign CNIDs and parents. Returns list of dicts in manifest order."""
    ids = {"": ROOT_FOLDER_ID}
    out = []
    cnid = FIRST_USER_ID
    for ent in manifest:
        kind, path = ent[0], ent[1]
        parent, _, name = path.rpartition("/")
        item = {"kind": kind, "path": path, "name": name, "parent": ids[parent],
                "cnid": cnid, "size": ent[2] if kind != "dir" else 0,
                "pieces": ent[3] if kind == "frag" else 1}
        ids[path] = cnid
        cnid += 1
        out.append(item)
    return out, cnid


def _place_files(items, alloc, block_size):
    """Allocate every file's data; returns {cnid: [(start, count), ...]}."""
    placed = {}
    for it in items:
        if it["kind"] == "dir" or it["size"] == 0:
            placed[it["cnid"]] = []
            continue
        blocks = (it["size"] + block_size - 1) // block_size
        pieces = min(it["pieces"], blocks)
        exts = []
        for p in range(pieces):
            n = blocks // pieces + (1 if p < blocks % pieces else 0)
            exts.append((alloc.take(n, gap=1 if pieces > 1 else 0), n))
        placed[it["cnid"]] = exts
    return placed


# --------------------------------------------------------------------------
# HFS Plus

def _uni(name):
    """HFS Plus stores names in decomposed Unicode (TN1150)."""
    raw = unicodedata.normalize("NFD", name).encode("utf-16-be")
    return struct.unpack(">%dH" % (len(raw) // 2), raw)


def _plus_key(parent, name):
    units = _uni(name)
    body = struct.pack(">IH", parent, len(units)) + struct.pack(">%dH" % len(units), *units)
    return (parent, units), struct.pack(">H", len(body)) + body


def _plus_fork(size, exts, block_size):
    rec = list(exts[:8]) + [(0, 0)] * (8 - len(exts[:8]))
    total = sum(c for _, c in exts)
    return struct.pack(">QII", size, 0, total) + b"".join(struct.pack(">II", s, c) for s, c in rec)


def _plus_overflow(cnid, exts):
    """Extents-overflow records for extents beyond the first eight."""
    out = []
    done = sum(c for _, c in exts[:8])
    rest = exts[8:]
    while rest:
        chunk, rest = rest[:8], rest[8:]
        key = struct.pack(">HBBII", 10, DATA_FORK, 0, cnid, done)
        data = b"".join(struct.pack(">II", s, c) for s, c in chunk) + b"\0" * 8 * (8 - len(chunk))
        out.append(((cnid, DATA_FORK, done), key, data))
        done += sum(c for _, c in chunk)
    return out


def build_plus(manifest, size, volname="HFSPlusTest", block_size=4096,
               catalog_nodes=None, catalog_slack=8):
    """An HFS Plus volume image of `size` bytes."""
    total = size // block_size
    items, next_cnid = _names(manifest)
    alloc = _Alloc(total)
    alloc.take(1)                                   # boot blocks + volume header
    alloc.mark(total - 1, 1)                        # alternate volume header
    bitmap_blocks = ((total + 7) // 8 + block_size - 1) // block_size
    a_start = alloc.take(bitmap_blocks)
    x_nodes, x_ns = 16, 1024
    x_blocks = x_nodes * x_ns // block_size
    x_start = alloc.take(x_blocks)
    kids = {}
    for it in items:
        kids[it["parent"]] = kids.get(it["parent"], 0) + 1
    c_ns = 4096
    # records need file extents, which need the catalog placed first: size it
    # from a trial layout with dummy extents
    def catalog_records(placed):
        out = []
        sv, k = _plus_key(ROOT_PARENT_ID, volname)
        out.append((sv, k, _plus_folder(ROOT_FOLDER_ID, kids.get(ROOT_FOLDER_ID, 0))))
        sv, k = _plus_key(ROOT_FOLDER_ID, "")
        out.append((sv, k, _plus_thread(HP_FOLDER_THREAD, ROOT_PARENT_ID, volname)))
        for it in items:
            sv, k = _plus_key(it["parent"], it["name"])
            if it["kind"] == "dir":
                out.append((sv, k, _plus_folder(it["cnid"], kids.get(it["cnid"], 0))))
                tt = HP_FOLDER_THREAD
            else:
                exts = placed[it["cnid"]]
                out.append((sv, k, _plus_file(it["cnid"], it["size"], exts, block_size)))
                tt = HP_FILE_THREAD
            sv, k = _plus_key(it["cnid"], "")
            out.append((sv, k, _plus_thread(tt, it["parent"], it["name"])))
        return out
    trial = catalog_records({it["cnid"]: [] for it in items})
    need = _count_nodes(TreeSpec(True, True, c_ns, 1 << 20), trial)
    if catalog_nodes is None:
        catalog_nodes = need + catalog_slack
        per_block = max(1, block_size // c_ns)
        catalog_nodes += (-catalog_nodes) % per_block
    c_blocks = catalog_nodes * c_ns // block_size
    c_start = alloc.take(c_blocks)
    placed = _place_files(items, alloc, block_size)
    recs = catalog_records(placed)
    ovf = []
    for it in items:
        ovf += _plus_overflow(it["cnid"], placed.get(it["cnid"], []))
    ext_tree = build_tree(TreeSpec(True, False, x_ns, x_nodes), ovf, x_ns * 4)
    cat_tree = build_tree(TreeSpec(True, True, c_ns, catalog_nodes), recs, c_ns * 4)
    img = bytearray(total * block_size)
    img[a_start * block_size:a_start * block_size + len(alloc.bits)] = alloc.bits
    img[x_start * block_size:x_start * block_size + len(ext_tree)] = ext_tree
    img[c_start * block_size:c_start * block_size + len(cat_tree)] = cat_tree
    for it in items:
        if it["kind"] != "dir" and it["size"]:
            data = content.data(it["path"], it["size"])
            pos = 0
            for s, c in placed[it["cnid"]]:
                chunk = data[pos:pos + c * block_size]
                img[s * block_size:s * block_size + len(chunk)] = chunk
                pos += c * block_size
    files = sum(1 for it in items if it["kind"] != "dir")
    folders = sum(1 for it in items if it["kind"] == "dir")
    vh = struct.pack(">HHI4sIIIIIIIIIIIIIIIQ32x", HFSPLUS_SIG, HFSPLUS_VERSION,
                     UNMOUNTED_BIT, b"8.10", 0, DATE, DATE, 0, DATE, files, folders,
                     block_size, total, total - alloc.used(), alloc.next,
                     block_size * 4, block_size * 4, next_cnid, 0, 1)
    assert len(vh) == 112
    vh += _plus_fork(bitmap_blocks * block_size, [(a_start, bitmap_blocks)], block_size)
    vh += _plus_fork(len(ext_tree), [(x_start, x_blocks)], block_size)
    vh += _plus_fork(len(cat_tree), [(c_start, c_blocks)], block_size)
    vh += _plus_fork(0, [], block_size) * 2
    vh = vh.ljust(512, b"\0")
    img[1024:1536] = vh
    img[len(img) - 1024:len(img) - 512] = vh
    return bytes(img)


def _plus_folder(cnid, valence):
    return struct.pack(">hHIIIIIII16x16x16xII", HP_FOLDER, 0, valence, cnid,
                       DATE, DATE, DATE, DATE, 0, 0, 0)


def _plus_file(cnid, size, exts, block_size):
    head = struct.pack(">hHIIIIIII16x16x16xII", HP_FILE, 0x0002, 0, cnid,
                       DATE, DATE, DATE, DATE, 0, 0, 0)
    return head + _plus_fork(size, exts, block_size) + _plus_fork(0, [], block_size)


def _plus_thread(ttype, parent, name):
    units = _uni(name)
    return struct.pack(">hhIH", ttype, 0, parent, len(units)) + \
        struct.pack(">%dH" % len(units), *units)


def _count_nodes(spec, records):
    return _layout(spec, records)[1]


# --------------------------------------------------------------------------
# HFS

def _roman(name):
    return name.encode("mac_roman")


def _hfs_key(parent, name):
    n = _roman(name)
    body = struct.pack(">BIB", 0, parent, len(n)) + n
    k = bytes([len(body)]) + body
    return (parent, n), k + b"\0" * (len(k) & 1)


def _hfs_ext(exts):
    rec = list(exts[:3]) + [(0, 0)] * (3 - len(exts[:3]))
    return b"".join(struct.pack(">HH", s, c) for s, c in rec)


def _hfs_overflow(cnid, exts):
    out = []
    done = sum(c for _, c in exts[:3])
    rest = exts[3:]
    while rest:
        chunk, rest = rest[:3], rest[3:]
        key = struct.pack(">BBIH", 7, DATA_FORK, cnid, done)
        out.append(((cnid, DATA_FORK, done), key, _hfs_ext(chunk)))
        done += sum(c for _, c in chunk)
    return out


def _hfs_folder(cnid, valence):
    return struct.pack(">hHHIIII16x16x16x", HFS_FOLDER, 0, valence, cnid, DATE, DATE, 0)


def _hfs_file(cnid, size, exts, block_size):
    phys = sum(c for _, c in exts) * block_size
    return (struct.pack(">hbb16xIHII", HFS_FILE, 0x02, 0, cnid, 0, size, phys)
            + struct.pack(">HIIIII16xH", 0, 0, 0, DATE, DATE, 0, 0)
            + _hfs_ext(exts[:3]) + _hfs_ext([]) + b"\0\0\0\0")


def _hfs_thread(ttype, parent, name):
    n = _roman(name)
    return struct.pack(">h8xIB", ttype, parent, len(n)) + n + b"\0" * (31 - len(n))


def build_hfs(manifest, size, volname="HFSTest", block_size=1024, catalog_slack=16):
    """An HFS (standard) volume image of `size` bytes."""
    sectors = size // 512
    vbm_st = 3
    # allocation blocks start after the bitmap; leave the last two sectors
    # (alternate MDB and one spare) outside the allocation area
    total = (sectors - vbm_st - 2) * 512 // block_size
    bitmap_sectors = (total + 4095) // 4096
    al_bl_st = vbm_st + bitmap_sectors
    total = min(total, (sectors - al_bl_st - 2) * 512 // block_size, 65535)
    items, next_cnid = _names(manifest)
    alloc = _Alloc(total)
    x_ns, x_nodes = 512, 16
    x_blocks = x_nodes * x_ns // block_size
    x_start = alloc.take(x_blocks)
    kids = {}
    for it in items:
        kids[it["parent"]] = kids.get(it["parent"], 0) + 1

    def catalog_records(placed):
        out = []
        sv, k = _hfs_key(ROOT_PARENT_ID, volname)
        out.append((sv, k, _hfs_folder(ROOT_FOLDER_ID, kids.get(ROOT_FOLDER_ID, 0))))
        sv, k = _hfs_key(ROOT_FOLDER_ID, "")
        out.append((sv, k, _hfs_thread(HFS_FOLDER_THREAD, ROOT_PARENT_ID, volname)))
        for it in items:
            sv, k = _hfs_key(it["parent"], it["name"])
            if it["kind"] == "dir":
                out.append((sv, k, _hfs_folder(it["cnid"], kids.get(it["cnid"], 0))))
                tt = HFS_FOLDER_THREAD
            else:
                out.append((sv, k, _hfs_file(it["cnid"], it["size"], placed[it["cnid"]], block_size)))
                tt = HFS_FILE_THREAD
            sv, k = _hfs_key(it["cnid"], "")
            out.append((sv, k, _hfs_thread(tt, it["parent"], it["name"])))
        return out
    c_ns = 512
    trial = catalog_records({it["cnid"]: [] for it in items})
    catalog_nodes = _count_nodes(TreeSpec(False, True, c_ns, 1 << 12), trial) + catalog_slack
    catalog_nodes += (-catalog_nodes) % max(1, block_size // c_ns)
    c_blocks = catalog_nodes * c_ns // block_size
    c_start = alloc.take(c_blocks)
    placed = _place_files(items, alloc, block_size)
    ovf = []
    for it in items:
        ovf += _hfs_overflow(it["cnid"], placed.get(it["cnid"], []))
    ext_tree = build_tree(TreeSpec(False, False, x_ns, x_nodes), ovf, x_ns * 4)
    cat_tree = build_tree(TreeSpec(False, True, c_ns, catalog_nodes), catalog_records(placed), c_ns * 4)
    img = bytearray(sectors * 512)
    base = al_bl_st * 512
    img[vbm_st * 512:vbm_st * 512 + len(alloc.bits)] = alloc.bits
    img[base + x_start * block_size:base + x_start * block_size + len(ext_tree)] = ext_tree
    img[base + c_start * block_size:base + c_start * block_size + len(cat_tree)] = cat_tree
    for it in items:
        if it["kind"] != "dir" and it["size"]:
            data = content.data(it["path"], it["size"])
            pos = 0
            for s, c in placed[it["cnid"]]:
                chunk = data[pos:pos + c * block_size]
                img[base + s * block_size:base + s * block_size + len(chunk)] = chunk
                pos += c * block_size
    root_files = sum(1 for it in items if it["parent"] == ROOT_FOLDER_ID and it["kind"] != "dir")
    root_dirs = sum(1 for it in items if it["parent"] == ROOT_FOLDER_ID and it["kind"] == "dir")
    files = sum(1 for it in items if it["kind"] != "dir")
    folders = sum(1 for it in items if it["kind"] == "dir")
    vn = _roman(volname)
    mdb = struct.pack(">HIIHHHHHIIHIHB27s", HFS_SIG, DATE, DATE, UNMOUNTED_BIT, root_files,
                      vbm_st, 0, total, block_size, block_size * 4, al_bl_st,
                      next_cnid, total - alloc.used(), len(vn), vn)
    mdb += struct.pack(">IHIIIHII32xHHH", 0, 0, 0, block_size * 4, block_size * 4,
                       root_dirs, files, folders, 0, 0, 0)
    mdb += struct.pack(">I", len(ext_tree)) + _hfs_ext([(x_start, x_blocks)])
    mdb += struct.pack(">I", len(cat_tree)) + _hfs_ext([(c_start, c_blocks)])
    assert len(mdb) == 162, len(mdb)
    img[1024:1024 + 162] = mdb
    img[len(img) - 1024:len(img) - 1024 + 162] = mdb
    return bytes(img)


# --------------------------------------------------------------------------
# HFS Plus wrapped in HFS

def build_wrapped(manifest, size, volname="WrappedTest", wrapper_block=4096, **kw):
    """An HFS wrapper whose one allocated extent is an HFS Plus volume."""
    sectors = size // 512
    vbm_st = 3
    total = (sectors - vbm_st - 2) * 512 // wrapper_block
    bitmap_sectors = (total + 4095) // 4096
    al_bl_st = vbm_st + bitmap_sectors
    total = (sectors - al_bl_st - 2) * 512 // wrapper_block
    embed_start, embed_count = 0, total
    plus = build_plus(manifest, embed_count * wrapper_block, volname=volname, **kw)
    img = bytearray(sectors * 512)
    bits = bytearray(bitmap_sectors * 512)
    for b in range(embed_count):
        bits[b >> 3] |= 0x80 >> (b & 7)
    img[vbm_st * 512:vbm_st * 512 + len(bits)] = bits
    off = al_bl_st * 512 + embed_start * wrapper_block
    img[off:off + len(plus)] = plus
    vn = _roman(volname)
    mdb = struct.pack(">HIIHHHHHIIHIHB27s", HFS_SIG, DATE, DATE,
                      0x8300, 0,
                      vbm_st, 0, total, wrapper_block, wrapper_block, al_bl_st,
                      FIRST_USER_ID, 0, len(vn), vn)
    mdb += struct.pack(">IHIIIHII32xHHH", 0, 0, 0, wrapper_block, wrapper_block,
                       0, 0, 0, HFSPLUS_SIG, embed_start, embed_count)
    mdb += struct.pack(">I", 0) + _hfs_ext([]) + struct.pack(">I", 0) + _hfs_ext([])
    assert len(mdb) == 162
    img[1024:1024 + 162] = mdb
    img[len(img) - 1024:len(img) - 1024 + 162] = mdb
    return bytes(img)


BUILDERS = {"hfs": build_hfs, "hfsplus": build_plus, "wrapped": build_wrapped}
```

Design notes, so a reviewer can check them:
- HFS Plus names are stored decomposed, as TN1150 requires and as the kernel's lookups assume. A precomposed `é` would appear in a directory listing but be impossible to `stat`.
- Catalog sizing leaves only a few free nodes (8 for HFS Plus, 16 for HFS). The write test's 150 new files therefore force the kernel to extend the catalog B-tree, which exercises `ExtendBTreeFile` and the node map.
- `frag.bin` is split into 12 extents, more than the 8 an HFS Plus file record holds (3 for HFS), so every flavour has extents-overflow records.

- [ ] **Step 5: Write `tools/hfsimg/scenario.py`**

```python
"""The test volumes, the guest scripts that exercise them, and what the
volumes must look like afterwards.

The guest runs a plain /bin/sh script from the results disk mounted at /mnt.
It mounts the HFS volume at /mnt/h and writes everything it has to report
into /mnt/out.txt, /mnt/list.txt and /mnt/sums.txt.
"""

import content

MOUNT_POINT = "/mnt/h"


def base_manifest():
    """The volume every built-image test starts from."""
    man = [("dir", "d1"), ("dir", "d1/sub"),
           ("file", "top.txt", 100),
           ("file", "café.txt", 33),
           ("frag", "frag.bin", 200000, 12),
           ("file", "big.bin", 3000000),
           ("file", "empty", 0)]
    for i in range(120):
        man.append(("file", "d1/f%03d" % i, (i * 37) % 5000))
    for i in range(20):
        man.append(("dir", "d1/sub/dd%02d" % i))
    return man


def tree(manifest):
    """{path: None for a folder, size for a file} for a manifest."""
    out = {}
    for ent in manifest:
        out[ent[1]] = None if ent[0] == "dir" else ent[2]
    return out


# --- the write test ---------------------------------------------------------

NEW_FILES = 150
NEW_DIRS = 20
BIG_SIZE = 20 * 1024 * 1024


def new_file_size(i):
    return (i * 1499) % 30000


def expected_after_write(manifest):
    """The tree write_script leaves behind, starting from `manifest`."""
    t = tree(manifest)
    t["w"] = None
    for i in range(NEW_FILES):
        t["w/f%03d" % i] = new_file_size(i)
    for i in range(NEW_DIRS):
        t["w/d%02d" % i] = None
        t["w/d%02d/x" % i] = 100
    t["w/r010"] = t.pop("w/f010")
    t["w/d00/f011"] = t.pop("w/f011")
    for i in range(20, 30):
        del t["w/f%03d" % i]
    del t["w/d19/x"]
    del t["w/d19"]
    t["w/big"] = BIG_SIZE
    t["top.txt"] = 5000
    del t["frag.bin"]
    return t


def content_name(path):
    """The name each file's contents were generated from.  Renamed and moved
    files keep the contents they were written with."""
    return {"w/r010": "w/f010", "w/d00/f011": "w/f011"}.get(path, path)


_PERL = content.GUEST_PERL


def write_script(device):
    lines = [
        "O=/mnt/out.txt",
        "echo BEGIN > $O",
        "/mnt/mount_hfs %s %s >> $O 2>&1; echo \"mount rc=$?\" >> $O" % (device, MOUNT_POINT),
        "cd %s || exit 1" % MOUNT_POINT,
        "P() { %s \"$1\" $2 > \"$1\"; }" % _PERL,
        "mkdir w",
        "i=0",
        "while [ $i -lt %d ]; do n=`printf %%03d $i`; P w/f$n `expr $i \\* 1499 %% 30000`; i=`expr $i + 1`; done"
        % NEW_FILES,
        "i=0",
        "while [ $i -lt %d ]; do n=`printf %%02d $i`; mkdir w/d$n; P w/d$n/x 100; i=`expr $i + 1`; done"
        % NEW_DIRS,
        "mv w/f010 w/r010",
        "mv w/f011 w/d00/f011",
        "i=20",
        "while [ $i -lt 30 ]; do rm w/f0$i; i=`expr $i + 1`; done",
        "rm w/d19/x",
        "rmdir w/d19",
        "P w/big %d" % BIG_SIZE,
        "P top.txt 5000",
        "rm frag.bin",
        "echo \"ops done\" >> $O",
    ] + _report_lines() + _finish_lines()
    return "\n".join(lines) + "\n"


def read_script(device, read_only=False, sample=None):
    """Mount, list, checksum (every file, or only `sample`), unmount."""
    opt = "-o ro " if read_only else ""
    lines = [
        "O=/mnt/out.txt",
        "echo BEGIN > $O",
        "/mnt/mount_hfs %s%s %s >> $O 2>&1; echo \"mount rc=$?\" >> $O" % (opt, device, MOUNT_POINT),
        "cd %s || exit 1" % MOUNT_POINT,
    ] + _report_lines(sample) + _finish_lines()
    return "\n".join(lines) + "\n"


def _report_lines(sample=None):
    if sample is None:
        sums = "find . -type f -print | sort | while read f; do cksum \"$f\"; done > /mnt/sums.txt"
    else:
        sums = "(" + "; ".join("cksum './%s'" % p for p in sample) + ") > /mnt/sums.txt"
    return [
        "find . -print | sort > /mnt/list.txt",
        sums,
        "echo \"report done\" >> $O",
    ]


def _finish_lines():
    return [
        "cd /",
        "umount %s >> $O 2>&1; echo \"umount rc=$?\" >> $O" % MOUNT_POINT,
        "sync",
        "echo END >> $O",
        "sync",
    ]


# --- reading the guest's report ----------------------------------------------

def parse_list(text):
    """Paths from `find . -print`, without the leading "./", "." dropped."""
    out = set()
    for line in text.splitlines():
        if line in (".", "./", ""):
            continue
        out.add(line[2:] if line.startswith("./") else line)
    return out


def parse_sums(text):
    """{path: (crc, size)} from cksum lines."""
    out = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        crc, size, path = line.split(None, 2)
        if path.startswith("./"):
            path = path[2:]
        out[path] = (int(crc), int(size))
    return out


def expected_sums(t, name_of=lambda p: p):
    """{path: (crc, size)} for every file of a tree of generated contents."""
    return dict((p, (content.cksum(content.data(name_of(p), s)), s))
                for p, s in t.items() if s is not None)
```

- [ ] **Step 6: Run every hfsimg test**

Run: `python -m pytest tools/hfsimg/tests -v`
Expected: 27 passed: 4 reader, 7 check, 12 builder (three tests run once per flavour, plus three more) and 4 scenario.

- [ ] **Step 7: Commit**

```bash
git add tools/hfsimg/content.py tools/hfsimg/builder.py tools/hfsimg/scenario.py tools/hfsimg/tests/test_builder.py tools/hfsimg/tests/test_scenario.py
git commit -m "tools: build HFS, HFS Plus and wrapped test volumes and model the guest write test"
```

---

### Task 5: Mach-O `__TEXT` comparison

**Files:**
- Create: `tools/hfsimg/macho_text.py`
- Test: `tools/hfsimg/tests/test_macho_text.py`

**Interfaces:**
- Produces: `python tools/hfsimg/macho_text.py BEFORE_DIR AFTER_DIR [--new NAME.o ...]`. It prints `identical` and exits 0 when every `__TEXT` section (bytes and relocations) of every object matches. Task 13 uses it.

- [ ] **Step 1: Write the failing test**

```python
import struct

import macho_text


def macho(text=b"\x38\x60\x00\x01\x4e\x80\x00\x20", data=b"\x00\x00\x00\x07",
          reloc=b"\x00\x00\x00\x04\x00\x00\x00\x01"):
    """A minimal big-endian MH_OBJECT: one LC_SEGMENT holding __TEXT,__text
    (with one relocation) and __DATA,__data."""
    ncmds, cmdsize = 1, 56 + 2 * 68
    text_off = 28 + cmdsize
    data_off = text_off + len(text)
    reloff = data_off + len(data)
    hdr = struct.pack(">7I", 0xfeedface, 18, 0, 1, ncmds, cmdsize, 0)
    seg = struct.pack(">II16s8I", 1, cmdsize, b"", 0, len(text) + len(data),
                      text_off, len(text) + len(data), 7, 7, 2, 0)
    s1 = struct.pack(">16s16s9I", b"__text", b"__TEXT", 0, len(text), text_off,
                     2, reloff, 1, 0x80000400, 0, 0)
    s2 = struct.pack(">16s16s9I", b"__data", b"__DATA", len(text), len(data),
                     data_off, 2, 0, 0, 0, 0, 0)
    return hdr + seg + s1 + s2 + text + data + reloc


def write(tmp_path, name, blob):
    p = tmp_path / name
    p.write_bytes(blob)
    return str(p)


def test_reads_only_text_sections(tmp_path):
    secs = macho_text.text_sections(write(tmp_path, "a.o", macho()))
    assert list(secs) == ["__text"]
    assert secs["__text"][0] == b"\x38\x60\x00\x01\x4e\x80\x00\x20"


def test_identical_and_data_only_changes_pass(tmp_path):
    a = write(tmp_path, "a.o", macho())
    b = write(tmp_path, "b.o", macho(data=b"\x00\x00\x00\x08"))
    assert macho_text.compare(a, b) == []


def test_code_and_relocation_changes_fail(tmp_path):
    a = write(tmp_path, "a.o", macho())
    b = write(tmp_path, "b.o", macho(text=b"\x38\x60\x00\x02\x4e\x80\x00\x20"))
    c = write(tmp_path, "c.o", macho(reloc=b"\x00\x00\x00\x00\x00\x00\x00\x01"))
    assert macho_text.compare(a, b) == ["section __text bytes differ"]
    assert macho_text.compare(a, c) == ["section __text relocations differ"]


def test_directories(tmp_path):
    before, after = tmp_path / "before", tmp_path / "after"
    before.mkdir()
    after.mkdir()
    (before / "x.o").write_bytes(macho())
    (after / "x.o").write_bytes(macho())
    (after / "hfs_endian.o").write_bytes(macho())
    assert macho_text.compare_dirs(str(before), str(after), ["hfs_endian.o"]) == []
    assert macho_text.compare_dirs(str(before), str(after)) == \
        ["hfs_endian.o: new object not expected"]
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `python -m pytest tools/hfsimg/tests/test_macho_text.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'macho_text'`

- [ ] **Step 3: Write `tools/hfsimg/macho_text.py`**

```python
"""Compare the __TEXT sections of two sets of Mach-O object files.

Proves a change left the ppc kernel's code untouched: every section whose
segment is __TEXT (code, literal strings, constants) must match byte for
byte, relocations included.

    python macho_text.py BEFORE_DIR AFTER_DIR [--new NAME.o ...]

Compares every .o in BEFORE_DIR with the same name in AFTER_DIR.  Objects
only in AFTER_DIR are errors unless named with --new.  Exits 0 when all match.
"""

import os
import struct
import sys

LC_SEGMENT = 1
S_ZEROFILL = 1


def text_sections(path):
    """{section name: (bytes, relocation bytes)} for every __TEXT section."""
    with open(path, "rb") as f:
        b = f.read()
    magic = b[:4]
    if magic == b"\xfe\xed\xfa\xce":
        e = ">"
    elif magic == b"\xce\xfa\xed\xfe":
        e = "<"
    else:
        raise ValueError("%s is not a 32-bit Mach-O file" % path)
    ncmds = struct.unpack_from(e + "I", b, 16)[0]
    off = 28
    out = {}
    for _ in range(ncmds):
        cmd, size = struct.unpack_from(e + "II", b, off)
        if cmd == LC_SEGMENT:
            nsects = struct.unpack_from(e + "I", b, off + 48)[0]
            s = off + 56
            for _ in range(nsects):
                sect = b[s:s + 16].split(b"\0")[0].decode("ascii")
                seg = b[s + 16:s + 32].split(b"\0")[0].decode("ascii")
                addr, sz, fileoff, align, reloff, nreloc, flags = \
                    struct.unpack_from(e + "7I", b, s + 32)
                if seg == "__TEXT":
                    data = b"" if (flags & 0xFF) == S_ZEROFILL else b[fileoff:fileoff + sz]
                    out[sect] = (data, b[reloff:reloff + 8 * nreloc])
                s += 68
        off += size
    return out


def compare(before, after):
    """Differences between two objects' __TEXT sections, as strings."""
    a, b = text_sections(before), text_sections(after)
    out = []
    for name in sorted(set(a) | set(b)):
        if name not in a or name not in b:
            out.append("section %s exists in only one object" % name)
        elif a[name][0] != b[name][0]:
            out.append("section %s bytes differ" % name)
        elif a[name][1] != b[name][1]:
            out.append("section %s relocations differ" % name)
    return out


def compare_dirs(before_dir, after_dir, new=()):
    problems = []
    names_a = set(n for n in os.listdir(before_dir) if n.endswith(".o"))
    names_b = set(n for n in os.listdir(after_dir) if n.endswith(".o"))
    for n in sorted(names_a - names_b):
        problems.append("%s: missing after the change" % n)
    for n in sorted(names_b - names_a - set(new)):
        problems.append("%s: new object not expected" % n)
    for n in sorted(names_a & names_b):
        for d in compare(os.path.join(before_dir, n), os.path.join(after_dir, n)):
            problems.append("%s: %s" % (n, d))
    return problems


def main(argv):
    args = argv[1:]
    new = []
    if "--new" in args:
        i = args.index("--new")
        new = args[i + 1:]
        args = args[:i]
    if len(args) != 2:
        print(__doc__)
        return 2
    problems = compare_dirs(args[0], args[1], new)
    for p in problems:
        print(p)
    print("identical" if not problems else "%d differences" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests**

Run: `python -m pytest tools/hfsimg/tests/test_macho_text.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add tools/hfsimg/macho_text.py tools/hfsimg/tests/test_macho_text.py
git commit -m "tools: compare the __TEXT sections of two builds' object files"
```

---

### Task 6: Guest harness, host side

**Files:**
- Create: `vm/hfs_guest.py`
- Test: `vm/test_hfs_guest.py`

**Interfaces:**
- Consumes: `tools/hfsimg` (Tasks 2-4), `vm/rhap_image.py`, `vm/ufs_build.py`, `vm/ufs_extract.py`, `vm/guest-console.py` (`Guest(outdir, extra=...)`, `.line`, `.shot`, `.close`).
- Produces the commands used by Tasks 14-16:
  - `python vm/hfs_guest.py build hfs|hfsplus|wrapped OUT.img`: a labelled 40 MB test disk
  - `python vm/hfs_guest.py toast OUT.img`: the Apple volume, labelled
  - `python vm/hfs_guest.py check IMG`: prints the problems and exits 0 when there are none
  - `python vm/hfs_guest.py run toast|read|write|reread OUTDIR HFS_IMG MOUNT_HFS [--before BEFORE_IMG]`: boots, then prints `PASS` or one `FAIL: ...` line per problem; exits 0 on `PASS`
- Device nodes are `HFS_DEV = "/dev/hd1a"` and `RESULTS_DEV = "/dev/hd2a"`. Task 14 confirms both.

- [ ] **Step 1: Write the failing test**

```python
"""Host-side tests for hfs_guest.py; nothing here boots a guest."""

import os
import struct

import pytest

import hfs_guest as hg

if not os.path.exists(hg.TEMPLATE):
    pytest.skip("installation floppy template is not present", allow_module_level=True)

import content      # noqa: E402  (from tools/hfsimg, put on sys.path by hfs_guest)
import rhap_image   # noqa: E402
import scenario     # noqa: E402


@pytest.fixture
def hfsplus(tmp_path):
    path = str(tmp_path / "hfsplus.img")
    hg.build_image("hfsplus", path)
    return path


def test_every_label_copy_says_512_byte_sectors(hfsplus):
    with open(hfsplus, "rb") as f:
        img = f.read(hg.label_front())
    copies = [off for off in rhap_image.LABEL_OFFSETS if img[off:off + 4] == b"dlV3"]
    assert copies
    for off in copies:
        secsize, = struct.unpack_from(">i", img, off + hg.LABEL_SECSIZE)
        front, = struct.unpack_from(">h", img, off + hg.LABEL_FRONT)
        p_size, = struct.unpack_from(">i", img, off + 194)
        assert (secsize, front * 512, p_size) == (512, hg.label_front(), hg.VOLUME_SIZE // 512)


def test_labelled_volume_opens_and_checks(hfsplus):
    assert hg.main(["x", "check", hfsplus]) == 0


def test_results_disk_round_trip(tmp_path):
    binary = tmp_path / "mount_hfs"
    binary.write_bytes(b"\xce\xfa\xed\xfe" + b"\0" * 4000)
    disk = str(tmp_path / "results.img")
    hg.results_disk(disk, "echo hi\n", str(binary))
    assert hg.read_results(disk) == {"out.txt": None, "list.txt": None, "sums.txt": None}
    with rhap_image.Image(disk) as img:
        assert img.read_file(img.inode(img.resolve("/run.sh"))) == b"echo hi\n"
        assert img.read_file(img.inode(img.resolve("/mount_hfs")))[:4] == b"\xce\xfa\xed\xfe"


def _simulated_guest(path):
    """What a correct guest would report for a read of `path`."""
    with hg.open_volume(path) as v:
        walk = v.walk()
        listing = "\n".join(sorted(["."] + ["." + p for p, e in walk]))
        sums = "\n".join("%d %d .%s" % (content.cksum(v.read_file(e)), e.data.logical_size, p)
                         for p, e in sorted(walk) if not e.is_dir)
    return {"out.txt": "BEGIN\nmount rc=0\nreport done\numount rc=0\nEND\n",
            "list.txt": listing, "sums.txt": sums}


def test_verify_accepts_a_correct_read(hfsplus, tmp_path):
    assert hg.verify("read", str(tmp_path), hfsplus, _simulated_guest(hfsplus)) == []


def test_verify_rejects_wrong_output(hfsplus, tmp_path):
    good = _simulated_guest(hfsplus)
    bad_sum = dict(good, **{"sums.txt": good["sums.txt"].replace("top.txt", "top.txx")})
    assert any("checksums differ" in p for p in hg.verify("read", str(tmp_path), hfsplus, bad_sum))
    no_end = dict(good, **{"out.txt": "BEGIN\nmount rc=0\n"})
    assert any("'END'" in p for p in hg.verify("read", str(tmp_path), hfsplus, no_end))
    (tmp_path / "serial.log").write_text("panic: hfs_swap\n")
    assert any("serial" in p for p in hg.verify("read", str(tmp_path), hfsplus, good))
```

- [ ] **Step 2: Run it to make sure it fails**

Run from `vm/`: `python -m pytest test_hfs_guest.py -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'hfs_guest'`

- [ ] **Step 3: Write `vm/hfs_guest.py`**

```python
"""Boot the i386 guest against an HFS volume and check what it did.

An HFS test needs three IDE disks: the per-session root image (index 0, the
RHAP_TEST_IMAGE that guest-console.Guest boots), the HFS volume under test
(index 1) and a small UFS results disk (index 2).  The block device of a
disk's live partition cannot be opened (bsd/dev/ata_hd_registry.m returns
nil for it), so the HFS volume sits in partition a behind a NeXT disk label
copied from the installation floppy.

The results disk carries run.sh, the i386 mount_hfs and the mount point h.
The guest mounts it at /mnt, runs /mnt/run.sh and leaves out.txt, list.txt
and sums.txt on it; the host reads them back with rhap_image after qemu exits.

Usage:
    python hfs_guest.py build FLAVOUR OUT_IMG      hfs, hfsplus or wrapped
    python hfs_guest.py toast OUT_IMG              the devtools.toast HFS volume
    python hfs_guest.py check IMG                  consistency-check a labelled image
    python hfs_guest.py run MODE OUTDIR HFS_IMG MOUNT_HFS [--before BEFORE_IMG]
        MODE: toast (read-only mount of the toast volume), read, write, reread
"""

import importlib.util
import os
import sys
import time
import struct
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools", "hfsimg"))

import rhap_image           # noqa: E402
import ufs_build            # noqa: E402
import ufs_extract          # noqa: E402
import builder              # noqa: E402
import check as hfscheck    # noqa: E402
import content              # noqa: E402
import scenario             # noqa: E402
import volume               # noqa: E402

# The floppy template and devtools.toast are untracked, so a worktree has
# neither; RHAP_VM_ASSETS points at the vm/ directory that does.
ASSETS = os.environ.get("RHAP_VM_ASSETS") or HERE
TEMPLATE = os.path.join(ASSETS, "install", "rhapsody_dr2_x86_InstallationFloppy.img")
TOAST = os.path.join(ASSETS, "devtools.toast")
TOAST_PART = (968, 1324080)         # Apple_HFS partition: first sector, sectors
HFS_DEV = "/dev/hd1a"
RESULTS_DEV = "/dev/hd2a"
VOLUME_SIZE = 40 * 1024 * 1024
TOAST_SAMPLE_MAX = 2 * 1024 * 1024


LABEL_SECSIZE = 92          # dl_secsize, int
LABEL_FRONT = 112           # dl_front, short, in dl_secsize units


def label_front():
    """Byte offset of partition a in a disk built from the floppy's label."""
    with rhap_image.Image(TEMPLATE) as img:
        return img.part_start


def wrap_label(hfs):
    """A disk image: the floppy's label area, relabelled for 512-byte
    sectors, then `hfs` as partition a.

    HFS addresses the device in 512-byte blocks (hfs_mountfs sets
    hfs_phys_block_size to 512), and a partition's block size is the label's
    dl_secsize (IODiskPartition.m _initPartition).  The floppy's label says
    1024, so every copy is rewritten to 512 with dl_front doubled, which
    leaves partition a at the same byte offset."""
    part = label_front()
    if len(hfs) % 512:
        raise ValueError("volume is not a whole number of 512-byte sectors")
    with open(TEMPLATE, "rb") as f:
        image = bytearray(f.read(part))
    found = 0
    for off in range(0, part, 512):
        if image[off:off + 4] != ufs_build.LABEL_MAGIC:
            continue
        secsize = struct.unpack_from(">i", image, off + LABEL_SECSIZE)[0]
        front = struct.unpack_from(">h", image, off + LABEL_FRONT)[0]
        struct.pack_into(">i", image, off + LABEL_SECSIZE, 512)
        struct.pack_into(">h", image, off + LABEL_FRONT, front * secsize // 512)
        found += 1
    if not found:
        raise ValueError("no NeXT label in the template")
    image += hfs
    ufs_build.patch_labels(image, part, len(hfs) // 512)
    return bytes(image)


def open_volume(path):
    return volume.Volume(path, label_front())


def build_image(flavour, out):
    hfs = builder.BUILDERS[flavour](scenario.base_manifest(), VOLUME_SIZE)
    with open(out, "wb") as f:
        f.write(wrap_label(hfs))


def toast_image(out):
    first, count = TOAST_PART
    with open(TOAST, "rb") as f:
        f.seek(first * 512)
        hfs = f.read(count * 512)
    with open(out, "wb") as f:
        f.write(wrap_label(hfs))


def results_disk(path, script, mount_hfs):
    N = ufs_extract.Node
    with open(mount_hfs, "rb") as f:
        binary = f.read()
    nodes = [N("/", "dir", 0o40755, 0, 0, 0, None),
             N("/h", "dir", 0o40755, 0, 0, 0, None),
             N("/mount_hfs", "reg", 0o100755, 0, 0, 0, binary),
             N("/run.sh", "reg", 0o100644, 0, 0, 0, script.encode("utf-8"))]
    with open(path, "wb") as f:
        f.write(ufs_build.build(TEMPLATE, nodes))


def read_results(path):
    out = {}
    with rhap_image.Image(path) as img:
        for name in ("out.txt", "list.txt", "sums.txt"):
            ino = img.resolve("/" + name)
            out[name] = None if ino is None else \
                img.read_file(img.inode(ino)).decode("utf-8", "replace")
    return out


def _guest_console():
    spec = importlib.util.spec_from_file_location(
        "guest_console", os.path.join(HERE, "guest-console.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def boot(outdir, hfs_img, results_img, timeout):
    """Boot single-user, run /mnt/run.sh, wait for END or the timeout."""
    gc = _guest_console()
    drive = "file=%s,format=raw,if=ide,index=%d,media=disk,snapshot=off"
    # a QMP port of its own: guest-console's default (4481) is shared by
    # every other session that boots a guest
    port = int(os.environ.get("RHAP_QMP_PORT", "4493"))
    g = gc.Guest(outdir, port=port, extra=("-drive", drive % (hfs_img, 1),
                                           "-drive", drive % (results_img, 2)))
    try:
        time.sleep(6)
        g.line("-s")
        time.sleep(135)
        g.line("mount %s /mnt" % RESULTS_DEV)
        time.sleep(5)
        g.line("sh /mnt/run.sh")
        deadline = time.time() + timeout
        while time.time() < deadline:
            time.sleep(15)
            try:
                r = read_results(results_img)
            except Exception:
                continue
            if r["out.txt"] and "END" in r["out.txt"].split():
                break
        g.shot("end")
    finally:
        g.close()
    return read_results(results_img)


def nfc(s):
    return unicodedata.normalize("NFC", s)


def expectation(mode, hfs_img):
    """(expected tree, content name function, cksum sample or None, script)."""
    if mode == "toast":
        with open_volume(hfs_img) as v:
            walk = v.walk()
        expected = dict((p[1:], None if e.is_dir else e.data.logical_size)
                        for p, e in walk if "\x00" not in p)
        sample = sorted(p for p, s in expected.items()
                        if s is not None and s <= TOAST_SAMPLE_MAX)
        return expected, None, sample, scenario.read_script(HFS_DEV, read_only=True, sample=sample)
    if mode == "read":
        expected = scenario.tree(scenario.base_manifest())
        return expected, scenario.content_name, None, scenario.read_script(HFS_DEV)
    if mode == "reread":
        expected = scenario.expected_after_write(scenario.base_manifest())
        return expected, scenario.content_name, None, scenario.read_script(HFS_DEV)
    if mode == "write":
        expected = scenario.expected_after_write(scenario.base_manifest())
        return expected, scenario.content_name, None, scenario.write_script(HFS_DEV)
    raise ValueError("mode must be toast, read, reread or write")


def verify(mode, outdir, hfs_img, results, before=None):
    """Every problem with a finished run, as a list of strings."""
    expected, name_of, sample, _ = expectation(mode, hfs_img)
    expected = dict((nfc(p), s) for p, s in expected.items())
    problems = []
    out = results["out.txt"] or ""
    for want in ("mount rc=0", "report done", "umount rc=0", "END"):
        if want not in out:
            problems.append("guest never reported %r; out.txt: %r" % (want, out))
    serial_log = os.path.join(outdir, "serial.log")
    if os.path.exists(serial_log):
        with open(serial_log, "rb") as f:
            serial = f.read().decode("latin-1")
        for line in serial.splitlines():
            if "panic" in line or line.startswith("hfs: "):
                problems.append("serial: " + line)
    listed = set(nfc(p) for p in scenario.parse_list(results["list.txt"] or ""))
    listed = set(p for p in listed if "HFS+ Private Data" not in p)
    if listed != set(expected):
        problems.append("guest listing differs: missing %s, unexpected %s"
                        % (sorted(set(expected) - listed)[:10], sorted(listed - set(expected))[:10]))
    sums = dict((nfc(p), v) for p, v in scenario.parse_sums(results["sums.txt"] or "").items())
    with open_volume(hfs_img) as v:
        walk = [(nfc(p[1:]), e) for p, e in v.walk()]
        if mode == "toast":
            files = dict((p, e) for p, e in walk if not e.is_dir)
            if set(sums) != set(sample):
                problems.append("guest checksummed %d files, expected %d" % (len(sums), len(sample)))
            for p, (crc, size) in sums.items():
                data = v.read_file(files[p]) if p in files else b""
                if (content.cksum(data), len(data)) != (crc, size):
                    problems.append("guest cksum of %s differs from the host's" % p)
            return problems
        want = scenario.expected_sums(expected, name_of)
        if sums != want:
            bad = sorted(p for p in set(sums) | set(want) if sums.get(p) != want.get(p))
            problems.append("guest checksums differ for %s" % bad[:10])
        problems += ["image: " + p for p in hfscheck.check(v)]
        got = dict((p, None if e.is_dir else e.data.logical_size) for p, e in walk)
        if got != expected:
            bad = sorted(p for p in set(got) | set(expected) if got.get(p, -1) != expected.get(p, -1))
            problems.append("image tree differs from the expected one at %s" % bad[:10])
        for p, e in walk:
            if not e.is_dir and p in expected and \
                    v.read_file(e) != content.data(name_of(p), e.data.logical_size):
                problems.append("image contents of %s are wrong" % p)
    if before is not None:
        problems += compare_wrapper(before, hfs_img)
    return problems


def compare_wrapper(before, after):
    """A wrapped volume's HFS wrapper must come through untouched."""
    part = label_front()
    out = []
    with open(before, "rb") as a, open(after, "rb") as b:
        a.seek(part + 1024)
        b.seek(part + 1024)
        if a.read(512) != b.read(512):
            out.append("wrapper MDB changed")
        a.seek(-1024, 2)
        b.seek(-1024, 2)
        if a.read(512) != b.read(512):
            out.append("alternate wrapper MDB changed")
    return out


def run(mode, outdir, hfs_img, mount_hfs, before=None, timeout=1800):
    os.makedirs(outdir, exist_ok=True)
    results_img = os.path.join(outdir, "results.img")
    script = expectation(mode, hfs_img)[3]
    results_disk(results_img, script, mount_hfs)
    results = boot(outdir, hfs_img, results_img, timeout)
    problems = verify(mode, outdir, hfs_img, results, before)
    for p in problems:
        print("FAIL: " + p)
    print("PASS" if not problems else "FAILED: %d problems" % len(problems))
    return 0 if not problems else 1


def main(argv):
    if len(argv) >= 4 and argv[1] == "build":
        build_image(argv[2], argv[3])
        return 0
    if len(argv) == 3 and argv[1] == "toast":
        toast_image(argv[2])
        return 0
    if len(argv) == 3 and argv[1] == "check":
        with open_volume(argv[2]) as v:
            problems = hfscheck.check(v)
        for p in problems:
            print(p)
        print("%d problems" % len(problems))
        return 1 if problems else 0
    if len(argv) >= 6 and argv[1] == "run":
        before = argv[argv.index("--before") + 1] if "--before" in argv else None
        return run(argv[2], argv[3], argv[4], argv[5], before)
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run the tests**

Run from `vm/`: `python -m pytest test_hfs_guest.py -v`
Expected: 5 passed. With `RHAP_VM_ASSETS` unset in a worktree, the module is skipped instead, and that is not a pass.

- [ ] **Step 5: Commit**

```bash
git add vm/hfs_guest.py vm/test_hfs_guest.py
git commit -m "vm: build labelled HFS test disks and a results disk, boot the guest and check its report"
```

---

### Task 7: Box setup and baselines

No source changes. This task sets up the private build root, captures the ppc HFS objects of unmodified `master` for Task 13, and learns whether `hfs-1` builds today.

**Files:**
- Create (gitignored): `vm/vm.conf` in the worktree, and `vm/work/hfsle/{setup,kbuild-i386,kbuild-ppc,kcheck-i386,kcheck-ppc,kextract-i386,objs-ppc,pbuild-hfs,pcheck-hfs}.sh`

- [ ] **Step 1: Point the worktree's box tools at the private root**

```bash
cp /d/RhapsodiOS/vm/vm.conf vm/vm.conf
sed -i 's#^RemoteRoot=.*#RemoteRoot=/build/hfsle#' vm/vm.conf
grep RemoteRoot vm/vm.conf
```

Expected: `RemoteRoot=/build/hfsle`.

- [ ] **Step 2: Write the box scripts**

`vm/work/hfsle/setup.sh`:

```sh
#!/bin/sh
# Private source root: kernel-7 and hfs-1 are real directories (synced from
# the host); every other project is a symlink into the shared tree.
R=/build/hfsle
mkdir -p $R/src
cd $R/src || exit 1
for e in /build/src/*; do
    n=`basename $e`
    case $n in
    kernel-7|hfs-1) ;;
    *) [ -e $n ] || ln -s $e $n ;;
    esac
done
ls -ld kernel-7 hfs-1 2>&1
echo SETUP_DONE
```

`vm/work/hfsle/kbuild-i386.sh`, and `kbuild-ppc.sh` identical but with `ARCH=ppc`:

```sh
#!/bin/sh
# Start a detached kernel build from the private root.  Refuses to start
# while any other rbuild runs: every kernel build shares /private/tmp/roots.
ARCH=i386
R=/build/hfsle
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
if ps -axww | grep -v grep | grep 'rbuild ' > /dev/null; then
    echo BUSY; ps -axww | grep -v grep | grep 'rbuild '; exit 3
fi
rm -rf $R/out-$ARCH $R/kernel-$ARCH.rc
mkdir -p $R/out-$ARCH
touch $R/stamp-$ARCH
cat > $R/kbuild-$ARCH.run <<EOF
#!/bin/sh
PATH=$PATH; export PATH
rbuild kernel --state /build/state --arch $ARCH $R/src /build/repo $R/out-$ARCH > $R/kernel-$ARCH.log 2>&1
echo \$? > $R/kernel-$ARCH.rc
EOF
chmod +x $R/kbuild-$ARCH.run
trap '' 1
nohup $R/kbuild-$ARCH.run > /dev/null 2>&1 < /dev/null &
echo STARTED
```

`vm/work/hfsle/kcheck-i386.sh`, and `kcheck-ppc.sh` with `ARCH=ppc`:

```sh
#!/bin/sh
ARCH=i386
R=/build/hfsle
if [ ! -f $R/kernel-$ARCH.rc ]; then echo RUNNING; tail -3 $R/kernel-$ARCH.log; exit 2; fi
echo rc=`cat $R/kernel-$ARCH.rc`
grep -n 'rror' $R/kernel-$ARCH.log | tail -40
ls -l $R/out-$ARCH
```

`vm/work/hfsle/kextract-i386.sh`:

```sh
#!/bin/sh
R=/build/hfsle
rm -rf $R/x-i386 && mkdir -p $R/x-i386 && cd $R/x-i386 || exit 1
gzip -dc $R/out-i386/kernel-*-i386.apk | tar xf - ./private/tftpboot/mach_kernel || exit 1
ls -l private/tftpboot/mach_kernel
cksum private/tftpboot/mach_kernel
```

`vm/work/hfsle/objs-ppc.sh`. Set `LABEL` to `before` here and `after` in Task 13:

```sh
#!/bin/sh
# Copy the 32 HFS objects of the ppc build that just finished.
LABEL=before
R=/build/hfsle
f=`find / -name hfs_btreeio.o -newer $R/stamp-ppc 2>/dev/null | head -1`
[ -n "$f" ] || { echo "NO_OBJECTS newer than the ppc build stamp"; exit 1; }
OBJ=`dirname $f`
echo OBJ=$OBJ
rm -rf $R/objs-$LABEL && mkdir -p $R/objs-$LABEL
for o in hfs_btreeio hfs_lockf hfs_lookup hfs_readwrite hfs_vfsops hfs_vfsutils \
         hfs_vhash hfs_vnodeops MacOSStubs BTree BTreeAllocate BTreeMiscOps \
         BTreeNodeOps BTreeScanner BTreeTreeOps CatSearch Catalog CatalogIterators \
         CatalogUtilities FileIDsServices Attributes BTreeWrapper FileExtentMapping \
         FileMgrInit GenericMRUCache HFSInstrumentation HFSUtilities VolumeAllocation \
         VolumeCheck VolumeRequests ConvertUTF UnicodeWrappers hfs_endian; do
    [ -f $OBJ/$o.o ] && cp $OBJ/$o.o $R/objs-$LABEL/ || echo "absent: $o.o"
done
cd $R && tar cf objs-$LABEL.tar objs-$LABEL && ls -l objs-$LABEL.tar
ls objs-$LABEL | wc -l
```

`vm/work/hfsle/pbuild-hfs.sh`:

```sh
#!/bin/sh
# Build the hfs-1 package (universal) from the private root, detached.
R=/build/hfsle
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
if ps -axww | grep -v grep | grep 'rbuild ' > /dev/null; then echo BUSY; exit 3; fi
rm -rf $R/out-hfs $R/hfs.rc && mkdir -p $R/out-hfs $R/state-hfs
cat > $R/pbuild-hfs.run <<EOF
#!/bin/sh
PATH=$PATH; export PATH
rbuild buildpackage --state $R/state-hfs --dir --target all $R/src/hfs-1 /build/repo $R/out-hfs > $R/hfs.log 2>&1
echo \$? > $R/hfs.rc
EOF
chmod +x $R/pbuild-hfs.run
trap '' 1
nohup $R/pbuild-hfs.run > /dev/null 2>&1 < /dev/null &
echo STARTED
```

`vm/work/hfsle/pcheck-hfs.sh`:

```sh
#!/bin/sh
R=/build/hfsle
if [ ! -f $R/hfs.rc ]; then echo RUNNING; tail -3 $R/hfs.log; exit 2; fi
echo rc=`cat $R/hfs.rc`
tail -30 $R/hfs.log
ls -l $R/out-hfs
A=`ls $R/out-hfs/hfs-*.apk 2>/dev/null | head -1`
[ -n "$A" ] || { echo NO_APK; exit 1; }
rm -rf $R/x-hfs && mkdir -p $R/x-hfs && cd $R/x-hfs
gzip -dc $A | tar tvf - | grep sbin/
gzip -dc $A | tar xf - ./sbin/mount_hfs && lipo -info sbin/mount_hfs
```

- [ ] **Step 3: Create the private root and sync the two projects**

Box-run `setup.sh`. Expected: `SETUP_DONE`, with `kernel-7` and `hfs-1` absent (they are not symlinked).
Then Box-sync `kernel-7` and Box-sync `hfs-1`. Box-run `setup.sh` again. Expected: `kernel-7` and `hfs-1` are now directories.

- [ ] **Step 4: Baseline ppc build and object capture**

Kernel-build `ppc` from this unmodified tree. When `rc=0`, Box-run `objs-ppc.sh` with `LABEL=before`, then Box-fetch `/build/hfsle/objs-before.tar` to `vm/work/hfsle/objs-before.tar`, and extract it:

```bash
tar xf vm/work/hfsle/objs-before.tar -C vm/work/hfsle
ls vm/work/hfsle/objs-before | wc -l
```

Expected: 32 objects (no `hfs_endian.o` yet). If the ppc build fails to link, check whether the failure is in the final link only. The P0 series recorded a missing `pexpertpowermac.o`, since fixed by `6ee132891`. The objects are still usable if every `bsd/hfs` object was compiled. Record that in the Task 17 report.

- [ ] **Step 5: Baseline hfs-1 package build**

Box-run `pbuild-hfs.sh`, then Box-run `pcheck-hfs.sh` until it prints `rc=`. Record which of these happened:
- `rc=0`, and `lipo -info` prints `ppc` only. This is the expected baseline, since `INCLUDED_ARCHS = ppc`.
- `rc≠0`. Record the failing subproject from `hfs.log`. If it is not `hfs_mount`, Task 12 uses its fallback.

There is no commit in this task.

---

### Task 8: Build HFS for i386, layout checks, ConditionalMacros

**Files:**
- Create: `src/kernel-7/bsd/hfs/hfs_endian.h`, `src/kernel-7/bsd/hfs/hfs_endian.c`
- Modify: `src/kernel-7/conf/MASTER.i386:72,74`, `src/kernel-7/conf/files:337`, `src/kernel-7/bsd/hfs/hfscommon/headers/system/ConditionalMacros.h:526-560`

**Interfaces:**
- Produces: `hfs_endian.h` with `SWAP_BE16(x)`, `SWAP_BE32(x)`, `SWAP_MDB(p)` and `SWAP_VH(p)` for every file that includes it. On ppc they are identities or empty. On i386 they map to `NXSwapBig*ToHost`, `hfs_swap_MDB` and `hfs_swap_VolumeHeader`. The swap functions themselves arrive in Task 9; this task gives `hfs_endian.c` its layout checks only.

- [ ] **Step 1: Write `hfs_endian.h`**

```c
/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 2000 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * hfs_endian.h
 *
 * HFS and HFS Plus are big-endian on disk.  On a big-endian host every
 * macro here is an identity or empty, so the ppc kernel compiles exactly as
 * it did before these macros existed.  Adapted from xnu-124.7
 * bsd/hfs/hfs_endian.h.
 */
#ifndef __HFS_ENDIAN_H__
#define __HFS_ENDIAN_H__

#include <machine/endian.h>

#if BYTE_ORDER == BIG_ENDIAN

#define SWAP_BE16(x)	(x)
#define SWAP_BE32(x)	(x)
#define SWAP_MDB(mdb)
#define SWAP_VH(vh)

#elif BYTE_ORDER == LITTLE_ENDIAN

#include <machine/byte_order.h>
#include "hfscommon/headers/BTreesInternal.h"
#include "hfscommon/headers/HFSVolumes.h"

#define SWAP_BE16(x)	NXSwapBigShortToHost(x)
#define SWAP_BE32(x)	NXSwapBigLongToHost(x)
#define SWAP_MDB(mdb)	hfs_swap_MDB(mdb)
#define SWAP_VH(vh)	hfs_swap_VolumeHeader(vh)

struct buf;

/* Whole-struct swaps; each is its own inverse. */
void	hfs_swap_MDB(HFSMasterDirectoryBlock *mdb);
void	hfs_swap_VolumeHeader(HFSPlusVolumeHeader *vh);

/*
 * B-tree nodes.  Each validates the whole node before changing a byte and
 * returns non-zero, leaving the node untouched, if it is not a valid node.
 */
int	hfs_swap_BTNode(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost);
int	hfs_btnode_to_host(BlockDescriptor *block, int isHFSPlus, UInt32 fileID);
int	hfs_btnode_to_disk(struct buf *bp, FCB *fcb, int isHFSPlus, UInt32 fileID);

#else
#error Unknown byte order
#endif

#endif /* __HFS_ENDIAN_H__ */
```

- [ ] **Step 2: Write `hfs_endian.c` with a deliberately wrong check first**

Write the file below, but with the MDB size check reading `== 161`. This proves the check mechanism fails the build on a wrong layout.

```c
/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 2000 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * hfs_endian.c
 *
 * Byte order for the HFS and HFS Plus volume formats, adapted from
 * xnu-124.7 bsd/hfs/hfs_endian.c.  The layout checks compile on every
 * architecture and emit no code; the swapping code exists only on
 * little-endian hosts.
 */

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/buf.h>
#include <sys/errno.h>

#include "hfs.h"
#include "hfs_endian.h"
#include "hfscommon/headers/BTreesPrivate.h"

/*
 * On-disk layout checks.  Apple's cc packs these structs with
 * #pragma options align=mac68k.  Each line fails to compile (a negative
 * array size) if a struct does not have the size or field offset that the
 * format defines (Inside Macintosh: Files; Technical Note TN1150).
 */
#define HFS_CHECK(name, cond)	typedef char hfs_check_##name[(cond) ? 1 : -1]
#define HFS_OFF(type, field)	((unsigned long)&((type *)0)->field)

HFS_CHECK(uint64, sizeof(UInt64) == 8);
HFS_CHECK(hfs_extent, sizeof(HFSExtentDescriptor) == 4);
HFS_CHECK(plus_extent, sizeof(HFSPlusExtentDescriptor) == 8);
HFS_CHECK(plus_fork, sizeof(HFSPlusForkData) == 80);

HFS_CHECK(mdb, sizeof(HFSMasterDirectoryBlock) == 161);
HFS_CHECK(mdb_alblksiz, HFS_OFF(HFSMasterDirectoryBlock, drAlBlkSiz) == 20);
HFS_CHECK(mdb_nxtcnid, HFS_OFF(HFSMasterDirectoryBlock, drNxtCNID) == 30);
HFS_CHECK(mdb_vn, HFS_OFF(HFSMasterDirectoryBlock, drVN) == 36);
HFS_CHECK(mdb_volbkup, HFS_OFF(HFSMasterDirectoryBlock, drVolBkUp) == 64);
HFS_CHECK(mdb_wrcnt, HFS_OFF(HFSMasterDirectoryBlock, drWrCnt) == 70);
HFS_CHECK(mdb_filcnt, HFS_OFF(HFSMasterDirectoryBlock, drFilCnt) == 84);
HFS_CHECK(mdb_fndrinfo, HFS_OFF(HFSMasterDirectoryBlock, drFndrInfo) == 92);
HFS_CHECK(mdb_embedsig, HFS_OFF(HFSMasterDirectoryBlock, drEmbedSigWord) == 124);
HFS_CHECK(mdb_xtflsize, HFS_OFF(HFSMasterDirectoryBlock, drXTFlSize) == 130);
HFS_CHECK(mdb_ctextrec, HFS_OFF(HFSMasterDirectoryBlock, drCTExtRec) == 150);

HFS_CHECK(vh, sizeof(HFSPlusVolumeHeader) == 512);
HFS_CHECK(vh_blocksize, HFS_OFF(HFSPlusVolumeHeader, blockSize) == 40);
HFS_CHECK(vh_encodings, HFS_OFF(HFSPlusVolumeHeader, encodingsBitmap) == 72);
HFS_CHECK(vh_finderinfo, HFS_OFF(HFSPlusVolumeHeader, finderInfo) == 80);
HFS_CHECK(vh_allocation, HFS_OFF(HFSPlusVolumeHeader, allocationFile) == 112);
HFS_CHECK(vh_extents, HFS_OFF(HFSPlusVolumeHeader, extentsFile) == 192);
HFS_CHECK(vh_catalog, HFS_OFF(HFSPlusVolumeHeader, catalogFile) == 272);
HFS_CHECK(vh_startup, HFS_OFF(HFSPlusVolumeHeader, startupFile) == 432);

HFS_CHECK(node, sizeof(BTNodeDescriptor) == 14);
HFS_CHECK(header, sizeof(HeaderRec) == 120);
HFS_CHECK(header_nodesize, HFS_OFF(HeaderRec, nodeSize) == 32);
HFS_CHECK(header_clumpsize, HFS_OFF(HeaderRec, clumpSize) == 46);
HFS_CHECK(header_attributes, HFS_OFF(HeaderRec, attributes) == 52);

HFS_CHECK(hfs_extent_key, sizeof(HFSExtentKey) == 8);
HFS_CHECK(hfs_extent_key_start, HFS_OFF(HFSExtentKey, startBlock) == 6);
HFS_CHECK(plus_extent_key, sizeof(HFSPlusExtentKey) == 12);
HFS_CHECK(hfs_catalog_key, sizeof(HFSCatalogKey) == 38);
HFS_CHECK(hfs_catalog_key_name, HFS_OFF(HFSCatalogKey, nodeName) == 6);
HFS_CHECK(plus_catalog_key, sizeof(HFSPlusCatalogKey) == 518);
HFS_CHECK(plus_catalog_key_name, HFS_OFF(HFSPlusCatalogKey, nodeName) == 6);

HFS_CHECK(hfs_folder, sizeof(HFSCatalogFolder) == 70);
HFS_CHECK(hfs_folder_id, HFS_OFF(HFSCatalogFolder, folderID) == 6);
HFS_CHECK(hfs_file, sizeof(HFSCatalogFile) == 102);
HFS_CHECK(hfs_file_id, HFS_OFF(HFSCatalogFile, fileID) == 20);
HFS_CHECK(hfs_file_datalen, HFS_OFF(HFSCatalogFile, dataLogicalSize) == 26);
HFS_CHECK(hfs_file_dataext, HFS_OFF(HFSCatalogFile, dataExtents) == 74);
HFS_CHECK(hfs_thread, sizeof(HFSCatalogThread) == 46);
HFS_CHECK(hfs_thread_parent, HFS_OFF(HFSCatalogThread, parentID) == 10);

HFS_CHECK(plus_folder, sizeof(HFSPlusCatalogFolder) == 88);
HFS_CHECK(plus_folder_perm, HFS_OFF(HFSPlusCatalogFolder, permissions) == 32);
HFS_CHECK(plus_file, sizeof(HFSPlusCatalogFile) == 248);
HFS_CHECK(plus_file_datafork, HFS_OFF(HFSPlusCatalogFile, dataFork) == 88);
HFS_CHECK(plus_thread, sizeof(HFSPlusCatalogThread) == 520);
HFS_CHECK(plus_thread_parent, HFS_OFF(HFSPlusCatalogThread, parentID) == 4);
```

- [ ] **Step 3: Enable HFS on i386 and compile `hfs_endian.c` everywhere**

```bash
python tools/latin1_replace.py src/kernel-7/conf/MASTER.i386 <<'EOF'
ffs cd9660 compat_43 revfs nbc]
=====
ffs hfs cd9660 compat_43 revfs nbc]
EOF
python tools/latin1_replace.py src/kernel-7/conf/MASTER.i386 <<'EOF'
ffs cd9660 compat_43 diagnostic revfs nbc]
=====
ffs hfs cd9660 compat_43 diagnostic revfs nbc]
EOF
python tools/latin1_replace.py src/kernel-7/conf/files <<'EOF'
bsd/hfs/hfs_btreeio.c				optional hfs
=====
bsd/hfs/hfs_btreeio.c				optional hfs
bsd/hfs/hfs_endian.c				optional hfs
EOF
```

- [ ] **Step 4: Correct the gcc branch of ConditionalMacros.h**

```bash
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfscommon/headers/system/ConditionalMacros.h <<'EOF'
#endif

#define TARGET_CPU_PPC  		1
#define TARGET_CPU_68K  		0
#define TARGET_CPU_X86  		0
=====
#endif

#if defined(__i386__)
#define TARGET_CPU_PPC  		0
#define TARGET_CPU_68K  		0
#define TARGET_CPU_X86  		1
#else
#define TARGET_CPU_PPC  		1
#define TARGET_CPU_68K  		0
#define TARGET_CPU_X86  		0
#endif
EOF
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfscommon/headers/system/ConditionalMacros.h <<'EOF'
	#define TARGET_RT_LITTLE_ENDIAN		0
	#define TARGET_RT_BIG_ENDIAN		1
	#define PRAGMA_IMPORT				0
	#define PRAGMA_STRUCT_ALIGN			1
	#define PRAGMA_ONCE					0
=====
#if defined(__i386__)
	#define TARGET_RT_LITTLE_ENDIAN		1
	#define TARGET_RT_BIG_ENDIAN		0
#else
	#define TARGET_RT_LITTLE_ENDIAN		0
	#define TARGET_RT_BIG_ENDIAN		1
#endif
	#define PRAGMA_IMPORT				0
	#define PRAGMA_STRUCT_ALIGN			1
	#define PRAGMA_ONCE					0
EOF
```

If the second replace reports more than one match, another compiler branch has the same five lines. Run `grep -n 'PRAGMA_ONCE' src/kernel-7/bsd/hfs/hfscommon/headers/system/ConditionalMacros.h`, add the preceding `#define TYPE_BOOL` or `#define DEBUG_BUILD` line of the gcc branch (its block starts at `#elif defined(__GNUC__)`, about line 486) to the old text, and retry. Do not use `--count`.

Then check the byte rule on all three edited files:

```bash
git diff src/kernel-7/conf src/kernel-7/bsd/hfs | grep -E '^[+-]' | LC_ALL=C grep -P '[^\x00-\x7F]'; echo "non-ascii lines changed: $?"
```

Expected: `non-ascii lines changed: 1`, meaning grep found none.

- [ ] **Step 5: Build i386 and see the wrong check fail**

Kernel-build `i386`. Expected: `rc` non-zero, and `kcheck-i386.sh` shows an error in `hfs_endian.c` about a negative array size (for example `size of array 'hfs_check_mdb' is negative`). No other `hfs_endian.c` check may fail. Any other error in a `bsd/hfs` file is the real work of this step: fix it in the file named, keep to the ppc invariant, and note each fix in the commit message.

- [ ] **Step 6: Correct the check and build both architectures**

```bash
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfs_endian.c <<'EOF'
HFS_CHECK(mdb, sizeof(HFSMasterDirectoryBlock) == 161);
=====
HFS_CHECK(mdb, sizeof(HFSMasterDirectoryBlock) == 162);
EOF
```

Kernel-build `i386`, then Kernel-build `ppc`. Expected: `rc=0` for both. If a *different* layout check fails on i386, the mac68k pragma is not doing what the spec assumed. Stop and report the failing check with its struct: every later task depends on these layouts.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfs_endian.h src/kernel-7/bsd/hfs/hfs_endian.c src/kernel-7/conf/MASTER.i386 src/kernel-7/conf/files src/kernel-7/bsd/hfs/hfscommon/headers/system/ConditionalMacros.h
git commit -m "kernel: build HFS on i386, prove its on-disk struct layouts at compile time, and stop ConditionalMacros claiming i386 is a big-endian PowerPC"
```

---

### Task 9: MDB, volume-header and B-tree node swaps

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfs_endian.c` (append the little-endian section)

**Interfaces:**
- Produces, on little-endian only:
  - `void hfs_swap_MDB(HFSMasterDirectoryBlock *)` and `void hfs_swap_VolumeHeader(HFSPlusVolumeHeader *)`, each its own inverse
  - `int hfs_btnode_to_host(BlockDescriptor *block, int isHFSPlus, UInt32 fileID)`, which returns 0 or `EINVAL`
  - `int hfs_btnode_to_disk(struct buf *bp, FCB *fcb, int isHFSPlus, UInt32 fileID)`, which returns 0, `EINVAL` or `EIO`
  - `int hfs_swap_BTNode(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost)`
  - Both node functions validate the whole node before changing a byte.

- [ ] **Step 1: Append the swap code**

Append to `src/kernel-7/bsd/hfs/hfs_endian.c`. `hfs_endian.c` is a new file with only ASCII bytes, so a plain append is safe:

```bash
cat >> src/kernel-7/bsd/hfs/hfs_endian.c <<'EOF'

#if BYTE_ORDER == LITTLE_ENDIAN

/*
 * The first record of a node always starts right after the 14-byte node
 * descriptor, so the last UInt16 of a valid node (its first offset) reads
 * 0x000e in host order and 0x0e00 while still in disk order.
 */
#define kNodeInHostOrder	0x000e
#define kNodeInDiskOrder	0x0e00

/* Swap a field in place, but only on the second (swapping) pass. */
#define SW16(x)	do { if (swap) (x) = SWAP_BE16(x); } while (0)
#define SW32(x)	do { if (swap) (x) = SWAP_BE32(x); } while (0)

static void
swap_hfs_extents(HFSExtentDescriptor *e, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		e[i].startBlock = SWAP_BE16(e[i].startBlock);
		e[i].blockCount = SWAP_BE16(e[i].blockCount);
	}
}

static void
swap_plus_extents(HFSPlusExtentDescriptor *e, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		e[i].startBlock = SWAP_BE32(e[i].startBlock);
		e[i].blockCount = SWAP_BE32(e[i].blockCount);
	}
}

/* UInt64 is a {hi, lo} struct here, stored big-endian as hi then lo. */
static void
swap_uint64(UInt64 *v)
{
	v->hi = SWAP_BE32(v->hi);
	v->lo = SWAP_BE32(v->lo);
}

static void
swap_fork(HFSPlusForkData *f)
{
	swap_uint64(&f->logicalSize);
	f->clumpSize = SWAP_BE32(f->clumpSize);
	f->totalBlocks = SWAP_BE32(f->totalBlocks);
	swap_plus_extents(f->extents, kHFSPlusExtentDensity);
}

/*
 * drVN is a Pascal string, and drFndrInfo, like all Finder information,
 * stays big-endian in memory.
 */
void
hfs_swap_MDB(HFSMasterDirectoryBlock *mdb)
{
	mdb->drSigWord = SWAP_BE16(mdb->drSigWord);
	mdb->drCrDate = SWAP_BE32(mdb->drCrDate);
	mdb->drLsMod = SWAP_BE32(mdb->drLsMod);
	mdb->drAtrb = SWAP_BE16(mdb->drAtrb);
	mdb->drNmFls = SWAP_BE16(mdb->drNmFls);
	mdb->drVBMSt = SWAP_BE16(mdb->drVBMSt);
	mdb->drAllocPtr = SWAP_BE16(mdb->drAllocPtr);
	mdb->drNmAlBlks = SWAP_BE16(mdb->drNmAlBlks);
	mdb->drAlBlkSiz = SWAP_BE32(mdb->drAlBlkSiz);
	mdb->drClpSiz = SWAP_BE32(mdb->drClpSiz);
	mdb->drAlBlSt = SWAP_BE16(mdb->drAlBlSt);
	mdb->drNxtCNID = SWAP_BE32(mdb->drNxtCNID);
	mdb->drFreeBks = SWAP_BE16(mdb->drFreeBks);
	mdb->drVolBkUp = SWAP_BE32(mdb->drVolBkUp);
	mdb->drVSeqNum = SWAP_BE16(mdb->drVSeqNum);
	mdb->drWrCnt = SWAP_BE32(mdb->drWrCnt);
	mdb->drXTClpSiz = SWAP_BE32(mdb->drXTClpSiz);
	mdb->drCTClpSiz = SWAP_BE32(mdb->drCTClpSiz);
	mdb->drNmRtDirs = SWAP_BE16(mdb->drNmRtDirs);
	mdb->drFilCnt = SWAP_BE32(mdb->drFilCnt);
	mdb->drDirCnt = SWAP_BE32(mdb->drDirCnt);
	mdb->drEmbedSigWord = SWAP_BE16(mdb->drEmbedSigWord);
	swap_hfs_extents(&mdb->drEmbedExtent, 1);
	mdb->drXTFlSize = SWAP_BE32(mdb->drXTFlSize);
	swap_hfs_extents(mdb->drXTExtRec, kHFSExtentDensity);
	mdb->drCTFlSize = SWAP_BE32(mdb->drCTFlSize);
	swap_hfs_extents(mdb->drCTExtRec, kHFSExtentDensity);
}

/* finderInfo stays big-endian in memory. */
void
hfs_swap_VolumeHeader(HFSPlusVolumeHeader *vh)
{
	vh->signature = SWAP_BE16(vh->signature);
	vh->version = SWAP_BE16(vh->version);
	vh->attributes = SWAP_BE32(vh->attributes);
	vh->lastMountedVersion = SWAP_BE32(vh->lastMountedVersion);
	vh->reserved = SWAP_BE32(vh->reserved);
	vh->createDate = SWAP_BE32(vh->createDate);
	vh->modifyDate = SWAP_BE32(vh->modifyDate);
	vh->backupDate = SWAP_BE32(vh->backupDate);
	vh->checkedDate = SWAP_BE32(vh->checkedDate);
	vh->fileCount = SWAP_BE32(vh->fileCount);
	vh->folderCount = SWAP_BE32(vh->folderCount);
	vh->blockSize = SWAP_BE32(vh->blockSize);
	vh->totalBlocks = SWAP_BE32(vh->totalBlocks);
	vh->freeBlocks = SWAP_BE32(vh->freeBlocks);
	vh->nextAllocation = SWAP_BE32(vh->nextAllocation);
	vh->rsrcClumpSize = SWAP_BE32(vh->rsrcClumpSize);
	vh->dataClumpSize = SWAP_BE32(vh->dataClumpSize);
	vh->nextCatalogID = SWAP_BE32(vh->nextCatalogID);
	vh->writeCount = SWAP_BE32(vh->writeCount);
	swap_uint64(&vh->encodingsBitmap);
	swap_fork(&vh->allocationFile);
	swap_fork(&vh->extentsFile);
	swap_fork(&vh->catalogFile);
	swap_fork(&vh->attributesFile);
	swap_fork(&vh->startupFile);
}

/*
 * The header record only; the node's user record and map record are left
 * alone (map words are swapped where BTreeAllocate.c uses them).
 */
static void
swap_header(HeaderRec *h)
{
	h->treeDepth = SWAP_BE16(h->treeDepth);
	h->rootNode = SWAP_BE32(h->rootNode);
	h->leafRecords = SWAP_BE32(h->leafRecords);
	h->firstLeafNode = SWAP_BE32(h->firstLeafNode);
	h->lastLeafNode = SWAP_BE32(h->lastLeafNode);
	h->nodeSize = SWAP_BE16(h->nodeSize);
	h->maxKeyLength = SWAP_BE16(h->maxKeyLength);
	h->totalNodes = SWAP_BE32(h->totalNodes);
	h->freeNodes = SWAP_BE32(h->freeNodes);
	h->clumpSize = SWAP_BE32(h->clumpSize);
	h->attributes = SWAP_BE32(h->attributes);
}

/*
 * One HFS Plus record in [rec, end).  With swap == 0 this only checks that
 * the record fits its slot; with swap == 1 it swaps it.  Lengths and types
 * are read in host order whichever way the bytes are going (toHost).
 * Finder information (userInfo, finderInfo) is never swapped.
 */
static int
swap_plus_record(UInt8 *rec, UInt8 *end, int isIndex, UInt32 fileID, int toHost, int swap)
{
	UInt16 keyLength, n, j;
	SInt16 type;
	UInt8 *data;

	if (rec + sizeof(UInt16) > end)
		return EINVAL;
	keyLength = *(UInt16 *)rec;
	if (toHost)
		keyLength = SWAP_BE16(keyLength);
	data = rec + sizeof(UInt16) + keyLength;
	if (data > end)
		return EINVAL;

	if (fileID == kHFSExtentsFileID) {
		HFSPlusExtentKey *key = (HFSPlusExtentKey *)rec;

		if (keyLength != kHFSPlusExtentKeyMaximumLength)
			return EINVAL;
		SW16(key->keyLength);
		SW32(key->fileID);
		SW32(key->startBlock);
		if (isIndex)
			goto pointer;
		if (data + sizeof(HFSPlusExtentRecord) > end)
			return EINVAL;
		if (swap)
			swap_plus_extents((HFSPlusExtentDescriptor *)data, kHFSPlusExtentDensity);
		return 0;
	}
	if (fileID != kHFSCatalogFileID)
		return EINVAL;

	{
		HFSPlusCatalogKey *key = (HFSPlusCatalogKey *)rec;

		if (keyLength < 6)
			return EINVAL;
		n = key->nodeName.length;
		if (toHost)
			n = SWAP_BE16(n);
		if (n > kHFSPlusMaxFileNameChars || 6 + 2 * n > keyLength)
			return EINVAL;
		SW16(key->keyLength);
		SW32(key->parentID);
		SW16(key->nodeName.length);
		for (j = 0; j < n; j++)
			SW16(key->nodeName.unicode[j]);
	}
	if (isIndex)
		goto pointer;

	if (data + sizeof(SInt16) > end)
		return EINVAL;
	type = *(SInt16 *)data;
	if (toHost)
		type = SWAP_BE16(type);
	switch (type) {
	case kHFSPlusFolderRecord: {
		HFSPlusCatalogFolder *r = (HFSPlusCatalogFolder *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW16(r->flags);
		SW32(r->valence);
		SW32(r->folderID);
		SW32(r->createDate);
		SW32(r->contentModDate);
		SW32(r->attributeModDate);
		SW32(r->accessDate);
		SW32(r->backupDate);
		SW32(r->permissions.ownerID);
		SW32(r->permissions.groupID);
		SW32(r->permissions.permissions);
		SW32(r->permissions.specialDevice);
		SW32(r->textEncoding);
		break;
	}
	case kHFSPlusFileRecord: {
		HFSPlusCatalogFile *r = (HFSPlusCatalogFile *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW16(r->flags);
		SW32(r->fileID);
		SW32(r->createDate);
		SW32(r->contentModDate);
		SW32(r->attributeModDate);
		SW32(r->accessDate);
		SW32(r->backupDate);
		SW32(r->permissions.ownerID);
		SW32(r->permissions.groupID);
		SW32(r->permissions.permissions);
		SW32(r->permissions.specialDevice);
		SW32(r->textEncoding);
		if (swap) {
			swap_fork(&r->dataFork);
			swap_fork(&r->resourceFork);
		}
		break;
	}
	case kHFSPlusFolderThreadRecord:
	case kHFSPlusFileThreadRecord: {
		HFSPlusCatalogThread *r = (HFSPlusCatalogThread *)data;

		if (data + 10 > end)
			return EINVAL;
		n = r->nodeName.length;
		if (toHost)
			n = SWAP_BE16(n);
		if (n > kHFSPlusMaxFileNameChars || data + 10 + 2 * n > end)
			return EINVAL;
		SW32(r->parentID);
		SW16(r->nodeName.length);
		for (j = 0; j < n; j++)
			SW16(r->nodeName.unicode[j]);
		break;
	}
	default:
		return EINVAL;
	}
	SW16(*(SInt16 *)data);
	return 0;

pointer:
	if (data + sizeof(UInt32) > end)
		return EINVAL;
	SW32(*(UInt32 *)data);
	return 0;
}

/* One HFS record in [rec, end); see swap_plus_record. */
static int
swap_hfs_record(UInt8 *rec, UInt8 *end, int isIndex, UInt32 fileID, int toHost, int swap)
{
	UInt8 keyLength;
	SInt16 type;
	UInt8 *data;

	if (rec + 1 > end)
		return EINVAL;
	keyLength = rec[0];
	data = rec + ((keyLength + 2) & ~1);
	if (data > end)
		return EINVAL;

	if (fileID == kHFSExtentsFileID) {
		HFSExtentKey *key = (HFSExtentKey *)rec;

		if (keyLength != kHFSExtentKeyMaximumLength)
			return EINVAL;
		SW32(key->fileID);
		SW16(key->startBlock);
		if (isIndex)
			goto pointer;
		if (data + sizeof(HFSExtentRecord) > end)
			return EINVAL;
		if (swap)
			swap_hfs_extents((HFSExtentDescriptor *)data, kHFSExtentDensity);
		return 0;
	}
	if (fileID != kHFSCatalogFileID)
		return EINVAL;

	{
		HFSCatalogKey *key = (HFSCatalogKey *)rec;

		if (keyLength < 6 || key->nodeName[0] > kHFSMaxFileNameChars ||
		    6 + key->nodeName[0] > keyLength)
			return EINVAL;
		SW32(key->parentID);
	}
	if (isIndex)
		goto pointer;

	if (data + sizeof(SInt16) > end)
		return EINVAL;
	type = *(SInt16 *)data;
	if (toHost)
		type = SWAP_BE16(type);
	switch (type) {
	case kHFSFolderRecord: {
		HFSCatalogFolder *r = (HFSCatalogFolder *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW16(r->flags);
		SW16(r->valence);
		SW32(r->folderID);
		SW32(r->createDate);
		SW32(r->modifyDate);
		SW32(r->backupDate);
		break;
	}
	case kHFSFileRecord: {
		HFSCatalogFile *r = (HFSCatalogFile *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW32(r->fileID);
		SW16(r->dataStartBlock);
		SW32(r->dataLogicalSize);
		SW32(r->dataPhysicalSize);
		SW16(r->rsrcStartBlock);
		SW32(r->rsrcLogicalSize);
		SW32(r->rsrcPhysicalSize);
		SW32(r->createDate);
		SW32(r->modifyDate);
		SW32(r->backupDate);
		SW16(r->clumpSize);
		if (swap) {
			swap_hfs_extents(r->dataExtents, kHFSExtentDensity);
			swap_hfs_extents(r->rsrcExtents, kHFSExtentDensity);
		}
		break;
	}
	case kHFSFolderThreadRecord:
	case kHFSFileThreadRecord: {
		HFSCatalogThread *r = (HFSCatalogThread *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW32(r->parentID);
		break;
	}
	default:
		return EINVAL;
	}
	SW16(*(SInt16 *)data);
	return 0;

pointer:
	if (data + sizeof(UInt32) > end)
		return EINVAL;
	SW32(*(UInt32 *)data);
	return 0;
}

/*
 * Offset of record i (i == numRecords gives the start of free space), read
 * from the offset table at the end of the node in host order.
 */
static UInt16
record_offset(UInt8 *base, UInt32 size, UInt16 i, int toHost)
{
	UInt16 off = ((UInt16 *)(base + size))[-1 - (int)i];

	return toHost ? SWAP_BE16(off) : off;
}

static int
swap_node(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost, int swap)
{
	BTNodeDescriptor *desc = (BTNodeDescriptor *)block->buffer;
	UInt8 *base = (UInt8 *)block->buffer;
	UInt32 size = block->blockSize;
	UInt16 count, i, off, prev;
	int err;

	count = desc->numRecords;
	if (toHost)
		count = SWAP_BE16(count);
	if (sizeof(BTNodeDescriptor) + (count + 1) * sizeof(UInt16) > size)
		return EINVAL;
	prev = 0;
	for (i = 0; i <= count; i++) {
		off = record_offset(base, size, i, toHost);
		if (i == 0 ? off != sizeof(BTNodeDescriptor) : off <= prev)
			return EINVAL;
		prev = off;
	}
	if (prev > size - (count + 1) * sizeof(UInt16))
		return EINVAL;

	switch (desc->type) {
	case kLeafNode:
	case kIndexNode:
		for (i = 0; i < count; i++) {
			UInt8 *rec = base + record_offset(base, size, i, toHost);
			UInt8 *end = base + record_offset(base, size, i + 1, toHost);

			err = isHFSPlus
			    ? swap_plus_record(rec, end, desc->type == kIndexNode, fileID, toHost, swap)
			    : swap_hfs_record(rec, end, desc->type == kIndexNode, fileID, toHost, swap);
			if (err)
				return err;
		}
		break;
	case kHeaderNode:
		if (count < 1 || record_offset(base, size, 1, toHost) < sizeof(HeaderRec))
			return EINVAL;
		if (swap)
			swap_header((HeaderRec *)base);
		break;
	case kMapNode:
		break;
	default:
		return EINVAL;
	}

	/* The descriptor and offset table go last: the records above used them. */
	if (swap) {
		desc->fLink = SWAP_BE32(desc->fLink);
		desc->bLink = SWAP_BE32(desc->bLink);
		desc->numRecords = SWAP_BE16(desc->numRecords);
		for (i = 0; i <= count; i++) {
			UInt16 *p = &((UInt16 *)(base + size))[-1 - (int)i];

			*p = SWAP_BE16(*p);
		}
	}
	return 0;
}

/*
 * Swap a whole node.  The first pass only validates; nothing changes unless
 * the whole node is valid.
 */
int
hfs_swap_BTNode(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost)
{
	int err;

	err = swap_node(block, isHFSPlus, fileID, toHost, 0);
	if (err == 0)
		(void) swap_node(block, isHFSPlus, fileID, toHost, 1);
	return err;
}

/*
 * A node just obtained through GetBTreeBlock: put it in host order unless it
 * already is.  BTOpenPath first reads the header node at kMinNodeSize, before
 * it knows the real node size, uses only the header record and then trashes
 * the buffer; that short read has no offset table to go by, so only its
 * header record is swapped.
 */
int
hfs_btnode_to_host(BlockDescriptor *block, int isHFSPlus, UInt32 fileID)
{
	BTNodeDescriptor *desc = (BTNodeDescriptor *)block->buffer;
	HeaderRec *header = (HeaderRec *)block->buffer;
	UInt16 last = *(UInt16 *)((UInt8 *)block->buffer + block->blockSize - sizeof(UInt16));

	if (desc->type == kHeaderNode && block->blockSize >= sizeof(HeaderRec) &&
	    header->nodeSize != block->blockSize &&
	    SWAP_BE16(header->nodeSize) != block->blockSize) {
		swap_header(header);
		return 0;
	}
	if (last == kNodeInDiskOrder)
		return hfs_swap_BTNode(block, isHFSPlus, fileID, 1);
	return 0;	/* already host order, or not a node: CheckNode decides */
}

/*
 * A B-tree buffer about to be written: put it in disk order if it is in host
 * order.  A buffer that is not exactly one node of this tree is refused.
 */
int
hfs_btnode_to_disk(struct buf *bp, FCB *fcb, int isHFSPlus, UInt32 fileID)
{
	BlockDescriptor block;
	BTreeControlBlockPtr btcb = (BTreeControlBlockPtr)fcb->fcbBTCBPtr;
	UInt16 last = *(UInt16 *)((UInt8 *)bp->b_data + bp->b_bcount - sizeof(UInt16));

	if (last != kNodeInHostOrder)
		return 0;	/* already disk order, or not a node (ClearBTNodes writes zeros) */
	if (btcb == NULL || bp->b_bcount != btcb->nodeSize)
		return EIO;
	block.buffer = bp->b_data;
	block.blockHeader = bp;
	block.blockSize = bp->b_bcount;
	block.blockReadFromDisk = 0;
	return hfs_swap_BTNode(&block, isHFSPlus, fileID, 0);
}

#endif /* BYTE_ORDER == LITTLE_ENDIAN */
EOF
```

Review points for this code:
- Lengths are always read in host order (the `toHost` argument), whichever way the bytes are going.
- `swap_node` runs twice: once with `swap = 0` to validate, then with `swap = 1`. A node that fails validation is never touched.
- The offset table and node descriptor are swapped last, after every record has used them.
- Map records and the header node's user and map records are not swapped; Task 10 swaps map words where they are used.
- FinderInfo (`userInfo`, `finderInfo`) is never swapped.

- [ ] **Step 2: Build both architectures**

Kernel-build `i386`, then Kernel-build `ppc`. Expected: `rc=0` for both, and no warnings from `hfs_endian.c` in either log (`grep -n 'hfs_endian' /build/hfsle/kernel-*.log` through a Box-run one-liner, or read `kcheck`'s output).

- [ ] **Step 3: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfs_endian.c
git commit -m "kernel: add validating byte swaps for the HFS master directory block, volume header and B-tree nodes"
```

---

### Task 10: Swap B-tree nodes at the buffer-cache boundary

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfs_btreeio.c` (`GetBTreeBlock`)
- Modify: `src/kernel-7/bsd/hfs/hfs_readwrite.c` (`hfs_strategy`, about line 1177)
- Modify: `src/kernel-7/bsd/hfs/hfscommon/BTree/BTreeAllocate.c` (`AllocateNode`, `FreeNode`, `ExtendBTree`)

**Interfaces:**
- Consumes: `hfs_btnode_to_host`, `hfs_btnode_to_disk` and `SWAP_BE16` (Tasks 8-9).

- [ ] **Step 1: Read hook in `GetBTreeBlock`**

```bash
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfs_btreeio.c <<'EOF'
#include "hfscommon/headers/BTreesInternal.h"
=====
#include "hfscommon/headers/BTreesInternal.h"
#include "hfs_endian.h"
EOF
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfs_btreeio.c <<'EOF'
        block->blockReadFromDisk = (bp->b_flags & B_CACHE) == 0;	/* not found in cache ==> came from disk */
    } else {
=====
        block->blockReadFromDisk = (bp->b_flags & B_CACHE) == 0;	/* not found in cache ==> came from disk */
#if BYTE_ORDER == LITTLE_ENDIAN
        /*
         * B-tree nodes are big-endian on disk and in host order while they
         * sit in the buffer cache: swap this one unless that already happened.
         * A node that is not a valid node is thrown away, never swapped.
         */
        if (!(options & kGetEmptyBlock) &&
            hfs_btnode_to_host(block, VTOVCB(vp)->vcbSigWord == kHFSPlusSigWord,
                               H_FILEID(VTOH(vp))) != 0) {
            printf("hfs: B-tree %lu node %lu is not a valid node\n",
                   (u_long)H_FILEID(VTOH(vp)), (u_long)blockNum);
            bp->b_flags |= B_INVAL;
            brelse(bp);
            block->blockHeader = NULL;
            block->buffer = NULL;
            retval = EIO;
        }
#endif
    } else {
EOF
```

- [ ] **Step 2: Write hook in `hfs_strategy`**

```bash
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfs_readwrite.c <<'EOF'
#include	"hfs_dbg.h"
=====
#include	"hfs_dbg.h"
#include	"hfs_endian.h"
EOF
python tools/latin1_replace.py src/kernel-7/bsd/hfs/hfs_readwrite.c <<'EOF'
    vp = hp->h_devvp;
    bp->b_dev = vp->v_rdev;
=====
#if BYTE_ORDER == LITTLE_ENDIAN
    /*
     * Put B-tree nodes back in disk order on their way out.  Every write of
     * a B-tree buffer comes through here, whether bwrite, bawrite, a delayed
     * write or blkflush started it; the buffer stays busy until the I/O is
     * done, and the next GetBTreeBlock swaps it back to host order.
     */
    if (!(bp->b_flags & B_READ) &&
        (H_FILEID(hp) == kHFSExtentsFileID || H_FILEID(hp) == kHFSCatalogFileID)) {
        retval = hfs_btnode_to_disk(bp, VTOFCB(vp),
                                    VTOVCB(vp)->vcbSigWord == kHFSPlusSigWord, H_FILEID(hp));
        if (retval) {
            printf("hfs: not writing B-tree %lu block %ld: it is not a valid node\n",
                   (u_long)H_FILEID(hp), (long)bp->b_lblkno);
            bp->b_error = retval;
            bp->b_flags |= B_ERROR;
            biodone(bp);
            return (retval);
        }
    }
#endif
    vp = hp->h_devvp;
    bp->b_dev = vp->v_rdev;
EOF
```

- [ ] **Step 3: Node-map words in `BTreeAllocate.c`**

```bash
F=src/kernel-7/bsd/hfs/hfscommon/BTree/BTreeAllocate.c
python tools/latin1_replace.py $F <<'EOF'
#include "../headers/BTreesPrivate.h"
=====
#include "../headers/BTreesPrivate.h"
#include "../../hfs_endian.h"

/* Node-map words stay big-endian in memory; each is swapped where it is used. */
#define		M_SWAP_BE16_ClearBitNum(integer,bitNumber)	((integer) &= SWAP_BE16(~(1<<(bitNumber))))
#define		M_SWAP_BE16_SetBitNum(integer,bitNumber)	((integer) |= SWAP_BE16(1<<(bitNumber)))
EOF
python tools/latin1_replace.py $F <<'EOF'
freeWord = *pos;
=====
freeWord	= SWAP_BE16 (*pos);
EOF
python tools/latin1_replace.py $F <<'EOF'
*pos |= mask;
=====
*pos |= SWAP_BE16 (mask);
EOF
python tools/latin1_replace.py $F <<'EOF'
M_ClearBitNum (*mapPos, bitOffset);
=====
M_SWAP_BE16_ClearBitNum (*mapPos, bitOffset);
EOF
python tools/latin1_replace.py $F <<'EOF'
M_SetBitNum (*mapPos, bitInWord);
=====
M_SWAP_BE16_SetBitNum (*mapPos, bitInWord);
EOF
git diff $F | grep -E '^[+-]' | LC_ALL=C grep -P '[^\x00-\x7F]'; echo "non-ascii lines changed: $?"
```

Expected: every replace exits 0, and the last line prints `non-ascii lines changed: 1`. On ppc these macros expand to exactly the tokens they replace, which Task 13 verifies.

- [ ] **Step 4: Build both architectures**

Kernel-build `i386`, then Kernel-build `ppc`. Expected: `rc=0` for both.

- [ ] **Step 5: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfs_btreeio.c src/kernel-7/bsd/hfs/hfs_readwrite.c src/kernel-7/bsd/hfs/hfscommon/BTree/BTreeAllocate.c
git commit -m "kernel: keep HFS B-tree nodes in host order in the buffer cache, swapping on read and on the way to disk"
```

---

### Task 11: MDB and volume header, attributes B-tree, FinderInfo

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfs_vfsops.c` (`hfs_mountfs`, `hfs_flushMDB`, `hfs_flushvolumeheader`)
- Modify: `src/kernel-7/bsd/hfs/hfs_vfsutils.c` (`hfs_MountHFSPlusVolume`, the symlink FinderInfo at about line 1077, `finderFlags` at about line 1293)

**Interfaces:**
- Consumes: `SWAP_MDB`, `SWAP_VH`, `SWAP_BE16`, `SWAP_BE32` (Tasks 8-9).

- [ ] **Step 1: `hfs_mountfs`**

```bash
F=src/kernel-7/bsd/hfs/hfs_vfsops.c
python tools/latin1_replace.py $F <<'EOF'
#include "hfs_dbg.h"
=====
#include "hfs_dbg.h"
#include "hfs_endian.h"
EOF
python tools/latin1_replace.py $F <<'EOF'
    mdbp = (HFSMasterDirectoryBlock*) ((char *)bp->b_data + IOBYTEOFFSETFORBLK(kMasterDirectoryBlock, size));
=====
    mdbp = (HFSMasterDirectoryBlock*) ((char *)bp->b_data + IOBYTEOFFSETFORBLK(kMasterDirectoryBlock, size));
    SWAP_MDB(mdbp);		/* to host order; every path below swaps it back before releasing bp */
EOF
python tools/latin1_replace.py $F <<'EOF'
		DBG_VFS(("hfs_mountfs: mounting wrapper-less HFS-Plus volume...\n"));
        retval = hfs_MountHFSPlusVolume(hfsmp, (HFSPlusVolumeHeader*) bp->b_data, 0, p);
=====
		DBG_VFS(("hfs_mountfs: mounting wrapper-less HFS-Plus volume...\n"));
		SWAP_MDB(mdbp);		/* it is a volume header, not an MDB */
		SWAP_VH((HFSPlusVolumeHeader*) bp->b_data);
        retval = hfs_MountHFSPlusVolume(hfsmp, (HFSPlusVolumeHeader*) bp->b_data, 0, p);
		SWAP_VH((HFSPlusVolumeHeader*) bp->b_data);
EOF
python tools/latin1_replace.py $F <<'EOF'
		brelse(bp);
		bp = NULL;		/* done with MDB, go grab Volume Header */
=====
		SWAP_MDB(mdbp);
		brelse(bp);
		bp = NULL;		/* done with MDB, go grab Volume Header */
EOF
python tools/latin1_replace.py $F <<'EOF'
		retval = hfs_MountHFSPlusVolume(hfsmp, vhp, embBlkOffset, p);
    }
=====
		SWAP_VH(vhp);
		retval = hfs_MountHFSPlusVolume(hfsmp, vhp, embBlkOffset, p);
		SWAP_VH(vhp);
    }
EOF
python tools/latin1_replace.py $F <<'EOF'
		retval = hfs_MountHFSVolume( hfsmp, mdbp, p);
	}
=====
		retval = hfs_MountHFSVolume( hfsmp, mdbp, p);
		SWAP_MDB(mdbp);
	}
EOF
```

Check the result by reading `hfs_mountfs` from the MDB `bread` down to `brelse(bp); bp = NULL;` after the three-way branch. Each of the three branches must leave the buffer in disk order before it is released: the wrapperless branch, the wrapped branch (both the MDB buffer and the volume-header buffer), and the plain HFS branch. The `BestBlockSizeFit(mdbp->drAlBlkSiz, ...)` line before the branch reads host order.

- [ ] **Step 2: `hfs_flushMDB`**

```bash
F=src/kernel-7/bsd/hfs/hfs_vfsops.c
python tools/latin1_replace.py $F <<'EOF'
	mdb = (HFSMasterDirectoryBlock *)((char *)bp->b_data + IOBYTEOFFSETFORBLK(kMasterDirectoryBlock, size));

	VCB_LOCK(vcb);
=====
	mdb = (HFSMasterDirectoryBlock *)((char *)bp->b_data + IOBYTEOFFSETFORBLK(kMasterDirectoryBlock, size));
	SWAP_MDB(mdb);		/* to host order; back to disk order before it is written */

	VCB_LOCK(vcb);
EOF
python tools/latin1_replace.py $F <<'EOF'
	mdb->drCTClpSiz	= fcb->fcbClmpSize;
	VCB_UNLOCK(vcb);
=====
	mdb->drCTClpSiz	= fcb->fcbClmpSize;
	VCB_UNLOCK(vcb);

	SWAP_MDB(mdb);
EOF
```

- [ ] **Step 3: `hfs_flushvolumeheader` and its wrapper MDB**

```bash
F=src/kernel-7/bsd/hfs/hfs_vfsops.c
python tools/latin1_replace.py $F <<'EOF'
	volumeHeader = (HFSPlusVolumeHeader *)((char *)bp->b_data +
					IOBYTEOFFSETFORBLK((vcb->hfsPlusIOPosOffset / 512) + kMasterDirectoryBlock, size));
=====
	volumeHeader = (HFSPlusVolumeHeader *)((char *)bp->b_data +
					IOBYTEOFFSETFORBLK((vcb->hfsPlusIOPosOffset / 512) + kMasterDirectoryBlock, size));
	SWAP_VH(volumeHeader);		/* to host order; back to disk order before it is written */
EOF
python tools/latin1_replace.py $F <<'EOF'
			mdb = (HFSMasterDirectoryBlock *)((char *)bp2->b_data + IOBYTEOFFSETFORBLK(kMasterDirectoryBlock, kMDBSize));
			if ( mdb->drCrDate != vcb->vcbCrDate )
			  {
				mdb->drCrDate = vcb->vcbCrDate;		/* ppick up the new create date */
				(void) bwrite(bp2);					/* write out the changes */
			  }
			else
			  {
				brelse(bp2);						/* just release it */
			  }
=====
			mdb = (HFSMasterDirectoryBlock *)((char *)bp2->b_data + IOBYTEOFFSETFORBLK(kMasterDirectoryBlock, kMDBSize));
			SWAP_MDB(mdb);
			if ( mdb->drCrDate != vcb->vcbCrDate )
			  {
				mdb->drCrDate = vcb->vcbCrDate;		/* ppick up the new create date */
				SWAP_MDB(mdb);
				(void) bwrite(bp2);					/* write out the changes */
			  }
			else
			  {
				SWAP_MDB(mdb);
				brelse(bp2);						/* just release it */
			  }
EOF
python tools/latin1_replace.py $F <<'EOF'
		volumeHeader->attributesFile.totalBlocks = fcb->fcbPLen / vcb->blockSize;
	  }

    if (waitfor != MNT_WAIT)
=====
		volumeHeader->attributesFile.totalBlocks = fcb->fcbPLen / vcb->blockSize;
	  }

	SWAP_VH(volumeHeader);

    if (waitfor != MNT_WAIT)
EOF
```

- [ ] **Step 4: Refuse an attributes B-tree, and the FinderInfo fields**

```bash
F=src/kernel-7/bsd/hfs/hfs_vfsutils.c
python tools/latin1_replace.py $F <<'EOF'
#include "hfscommon/headers/BTreesPrivate.h"
=====
#include "hfscommon/headers/BTreesPrivate.h"
#include "hfs_endian.h"
EOF
python tools/latin1_replace.py $F <<'EOF'
	/*
	 * Set up Attribute B-tree vnode (optional)...
	 */
=====
#if BYTE_ORDER == LITTLE_ENDIAN
	/*
	 * hfs_endian.c knows the catalog and extents record formats only;
	 * refuse a volume that has an attributes B-tree rather than read its
	 * nodes in the wrong byte order.
	 */
	if (vhp->attributesFile.logicalSize.hi != 0 || vhp->attributesFile.logicalSize.lo != 0) {
		printf("hfs: can't mount an HFS Plus volume that has an attributes B-tree on this CPU\n");
		retval = EINVAL;
		goto ErrorExit;
	}
#endif

	/*
	 * Set up Attribute B-tree vnode (optional)...
	 */
EOF
python tools/latin1_replace.py $F <<'EOF'
((struct FInfo *)(&nodeData->finderInfo))->fdType = kSymLinkFileType;
=====
((struct FInfo *)(&nodeData->finderInfo))->fdType = SWAP_BE32(kSymLinkFileType);	/* FinderInfo stays big-endian */
EOF
python tools/latin1_replace.py $F <<'EOF'
((struct FInfo *)(&nodeData->finderInfo))->fdCreator = kSymLinkCreator;
=====
((struct FInfo *)(&nodeData->finderInfo))->fdCreator = SWAP_BE32(kSymLinkCreator);
EOF
python tools/latin1_replace.py $F <<'EOF'
((struct FInfo *)(&nodeData->finderInfo))->fdFlags |= kIsAlias;
=====
((struct FInfo *)(&nodeData->finderInfo))->fdFlags |= SWAP_BE16(kIsAlias);
EOF
python tools/latin1_replace.py $F <<'EOF'
finderFlags 	= ((struct FInfo *)(&catalogInfo->nodeData.finderInfo))->fdFlags;
=====
finderFlags 	= SWAP_BE16(((struct FInfo *)(&catalogInfo->nodeData.finderInfo))->fdFlags);
EOF
git diff src/kernel-7/bsd/hfs/hfs_vfsops.c $F | grep -E '^[+-]' | LC_ALL=C grep -P '[^\x00-\x7F]'; echo "non-ascii lines changed: $?"
```

Expected: every replace exits 0, then `non-ascii lines changed: 1`.

Confirm that `ErrorExit` in `hfs_MountHFSPlusVolume` releases the vnodes set up so far: read from `ErrorExit:` to the end of the function. If it does not, stop and report rather than leak them.

- [ ] **Step 5: Make sure no other FinderInfo field is interpreted**

```bash
grep -rn 'fdType\|fdCreator\|fdFlags\|frFlags\|fdLocation\|frLocation' src/kernel-7/bsd/hfs --include=*.c | grep -v '^\S*:\s*//'
```

Expected: only the four lines just edited, plus `VolumeCheck.c:498`, which is a comment. Any other hit reads or writes FinderInfo as a number and needs the same treatment; add it to this task.

- [ ] **Step 6: Build both architectures**

Kernel-build `i386`, then Kernel-build `ppc`. Expected: `rc=0` for both.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfs_vfsops.c src/kernel-7/bsd/hfs/hfs_vfsutils.c
git commit -m "kernel: swap the HFS master directory block and volume header around mount and flush, and refuse attributes B-trees on little-endian hosts"
```

---

### Task 12: Allocation-bitmap words

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfscommon/Misc/VolumeAllocation.c` (the 34 sites counted below)

- [ ] **Step 1: Include the header**

```bash
F=src/kernel-7/bsd/hfs/hfscommon/Misc/VolumeAllocation.c
python tools/latin1_replace.py $F <<'EOF'
#include "../../hfs_dbg.h"
=====
#include "../../hfs_dbg.h"
#include "../../hfs_endian.h"
EOF
```

- [ ] **Step 2: Swap every bitmap word load, store and masked compare**

Each replace gives the exact number of sites it must hit; the tool changes nothing if the count is wrong.

```bash
F=src/kernel-7/bsd/hfs/hfscommon/Misc/VolumeAllocation.c
r() { python tools/latin1_replace.py $F --count "$1"; }
r 2 <<'EOF'
temp = ~(*currentWord);
=====
temp = SWAP_BE32 (~(*currentWord));
EOF
r 3 <<'EOF'
currentWord = *buffer;
=====
currentWord = SWAP_BE32 (*buffer);
EOF
r 2 <<'EOF'
*buffer = currentWord;
=====
*buffer = SWAP_BE32 (currentWord);
EOF
r 2 <<'EOF'
(*currentWord & bitMask) != 0
=====
(*currentWord & SWAP_BE32 (bitMask)) != 0
EOF
r 4 <<'EOF'
*currentWord |= bitMask;
=====
*currentWord |= SWAP_BE32 (bitMask);
EOF
r 2 <<'EOF'
*currentWord = bitMask;
=====
*currentWord = SWAP_BE32 (bitMask);
EOF
r 4 <<'EOF'
(*currentWord & bitMask) != bitMask
=====
(*currentWord & SWAP_BE32 (bitMask)) != SWAP_BE32 (bitMask)
EOF
r 2 <<'EOF'
*currentWord &= ~bitMask;
=====
*currentWord &= SWAP_BE32 (~bitMask);
EOF
r 1 <<'EOF'
*currentWord != kAllBitsSetInWord
=====
*currentWord != SWAP_BE32 (kAllBitsSetInWord)
EOF
r 1 <<'EOF'
*currentWord != bitMask
=====
*currentWord != SWAP_BE32 (bitMask)
EOF
r 5 <<'EOF'
tempWord = *currentWord;
=====
tempWord = SWAP_BE32 (*currentWord);
EOF
git diff $F | grep -E '^[+-]' | LC_ALL=C grep -P '[^\x00-\x7F]'; echo "non-ascii lines changed: $?"
```

Expected: every replace exits 0, then `non-ascii lines changed: 1`. That is 28 replacements plus the include; the other 6 of the 34 sites are the `*currentWord != 0` and `*currentWord = 0;` compares and stores, which are endian-neutral and deliberately left alone. Cross-check against xnu-124.7's `VolumeAllocation.c`, whose 21 `SWAP_BE32` sites all have a counterpart here. `BlockVerifyAllocated` has no xnu-124 counterpart.

- [ ] **Step 3: Build both architectures**

Kernel-build `i386`, then Kernel-build `ppc`. Expected: `rc=0` for both.

- [ ] **Step 4: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfscommon/Misc/VolumeAllocation.c
git commit -m "kernel: swap HFS allocation-bitmap words where they are read and written"
```

---

### Task 13: Prove the ppc kernel's HFS code is unchanged

**Files:**
- Create (gitignored): `vm/work/hfsle/objs-after/`

- [ ] **Step 1: Capture the objects of the current ppc build**

The last Kernel-build `ppc` (Task 12 Step 3) is the one to capture. If any build ran since, run Kernel-build `ppc` again. Set `LABEL=after` in `objs-ppc.sh`, Box-run it, then:

```powershell
powershell -NoProfile -File vm\guest-remote.ps1 -Fetch /build/hfsle/objs-after.tar -To vm\work\hfsle\objs-after.tar
```

```bash
tar xf vm/work/hfsle/objs-after.tar -C vm/work/hfsle
python tools/hfsimg/macho_text.py vm/work/hfsle/objs-before vm/work/hfsle/objs-after --new hfs_endian.o
```

Expected: `identical`, exit 0. Every difference printed is a violation of the ppc invariant. Find the edit responsible (compare the object's source diff) and fix it before going on. Do not widen `--new`. Also check that `hfs_endian.o`'s `__text` section is empty:

```bash
python -c "import sys; sys.path.insert(0,'tools/hfsimg'); import macho_text as m; print(m.text_sections('vm/work/hfsle/objs-after/hfs_endian.o'))"
```

Expected: `{}`, or only empty sections.

- [ ] **Step 2: Record the result**

Append a line to `vm/work/hfsle/notes.txt` with the date and `ppc __TEXT identical across 32 HFS objects`. There is no commit in this step; the evidence goes into the spec's Outcome in Task 17.

---

### Task 14: `mount_hfs` for i386

**Files:**
- Create: `src/hfs-1/hfs_mount/hfs_endian.h`
- Modify: `src/hfs-1/hfs_mount/mount_hfs.c` (`getVolumeCreateDate`), `src/hfs-1/hfs_mount/Makefile` (`HFILES`), `src/hfs-1/hfs_mount/PB.project` (`H_FILES`)
- Modify: `src/hfs-1/Makefile.preamble` (drop `INCLUDED_ARCHS`), and `src/hfs-1/hfs_glue/Makefile.preamble`, `src/hfs-1/hfs_util/Makefile.preamble`, `src/hfs-1/hfs_newfs/Makefile.preamble` (add it)

- [ ] **Step 1: The endian header**

`src/hfs-1/hfs_mount/hfs_endian.h`:

```c
/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 2000 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * hfs_endian.h -- HFS and HFS Plus are big-endian on disk.  mount_hfs reads
 * a few fields straight off the device; these convert them to host order.
 * After diskdev_cmds-143 mount_hfs.tproj/hfs_endian.h.
 */
#ifndef __MOUNT_HFS_ENDIAN_H__
#define __MOUNT_HFS_ENDIAN_H__

#include <architecture/byte_order.h>

#define SWAP_BE16(x)	NXSwapBigShortToHost(x)
#define SWAP_BE32(x)	NXSwapBigLongToHost(x)

#endif /* __MOUNT_HFS_ENDIAN_H__ */
```

- [ ] **Step 2: Swap the four on-disk reads**

```bash
F=src/hfs-1/hfs_mount/mount_hfs.c
python tools/latin1_replace.py $F <<'EOF'
#include "HFSVolumes.h"
=====
#include "HFSVolumes.h"
#include "hfs_endian.h"
EOF
python tools/latin1_replace.py $F <<'EOF'
	if ((mdbPtr->drSigWord == kHFSSigWord)  &&  (mdbPtr->drEmbedSigWord == kHFSPlusSigWord)) {
		/* Embedded volume*/
		volume_create_time = mdbPtr->drCrDate;
	} else if (mdbPtr->drSigWord == kHFSPlusSigWord ) {
		HFSPlusVolumeHeader * volHdrPtr = (HFSPlusVolumeHeader *) bufPtr;

		volume_create_time = volHdrPtr->createDate;
=====
	if ((SWAP_BE16(mdbPtr->drSigWord) == kHFSSigWord)  &&  (SWAP_BE16(mdbPtr->drEmbedSigWord) == kHFSPlusSigWord)) {
		/* Embedded volume*/
		volume_create_time = SWAP_BE32(mdbPtr->drCrDate);
	} else if (SWAP_BE16(mdbPtr->drSigWord) == kHFSPlusSigWord ) {
		HFSPlusVolumeHeader * volHdrPtr = (HFSPlusVolumeHeader *) bufPtr;

		volume_create_time = SWAP_BE32(volHdrPtr->createDate);
EOF
python tools/latin1_replace.py src/hfs-1/hfs_mount/Makefile <<'EOF'
HFILES = mount_hfs.h
=====
HFILES = mount_hfs.h hfs_endian.h
EOF
python tools/latin1_replace.py src/hfs-1/hfs_mount/PB.project <<'EOF'
H_FILES = (mount_hfs.h);
=====
H_FILES = (mount_hfs.h, hfs_endian.h);
EOF
grep -n 'drSigWord\|drEmbedSigWord\|drCrDate\|createDate' $F
```

Expected: every on-disk field read that the grep prints is wrapped in `SWAP_BE16` or `SWAP_BE32`.

- [ ] **Step 3: Let only `hfs_mount` build for i386**

```bash
python tools/latin1_replace.py src/hfs-1/Makefile.preamble <<'EOF'

INCLUDED_ARCHS = ppc
OTHER_RECURSIVE_VARIABLES += INCLUDED_ARCHS
=====
EOF
for d in hfs_glue hfs_util hfs_newfs; do
    printf '\n# Built for ppc only; hfs_mount alone also builds for i386.\nINCLUDED_ARCHS = ppc\n' >> src/hfs-1/$d/Makefile.preamble
done
tail -3 src/hfs-1/hfs_glue/Makefile.preamble src/hfs-1/hfs_util/Makefile.preamble src/hfs-1/hfs_newfs/Makefile.preamble
```

Appending with `printf` is safe here because these three files are pure ASCII (checked while planning).

- [ ] **Step 4: Build the package**

Box-sync `hfs-1`. Box-run `pbuild-hfs.sh`, then Box-run `pcheck-hfs.sh` until `rc=` appears. Expected: `rc=0`, and `lipo -info sbin/mount_hfs` lists `i386` (with `ppc`).

**Fallback,** only if Task 7 Step 5 found the unchanged `hfs-1` failing in a subproject other than `hfs_mount`. In the private root only, make the aggregate build `hfs_mount` alone. This is not committed:

```sh
cd /build/hfsle/src/hfs-1 && sed -e 's/^TOOLS = .*/TOOLS = hfs_mount/' -e '/^LIBRARIES/d' Makefile > Makefile.new && mv Makefile.new Makefile
```

Put that line in a script, Box-run it, then rerun Step 4. Record the fallback in `notes.txt`.

- [ ] **Step 5: Fetch the binary**

```powershell
powershell -NoProfile -File vm\guest-remote.ps1 -Fetch /build/hfsle/x-hfs/sbin/mount_hfs -To vm\work\hfsle\mount_hfs
```

```bash
ls -l vm/work/hfsle/mount_hfs && od -A x -t x1 -N 8 vm/work/hfsle/mount_hfs
```

Expected: a file tens of kilobytes long, starting `ca fe ba be` (fat) or `ce fa ed fe` (i386 thin).

- [ ] **Step 6: Commit**

```bash
git add src/hfs-1/hfs_mount/hfs_endian.h src/hfs-1/hfs_mount/mount_hfs.c src/hfs-1/hfs_mount/Makefile src/hfs-1/hfs_mount/PB.project src/hfs-1/Makefile.preamble src/hfs-1/hfs_glue/Makefile.preamble src/hfs-1/hfs_util/Makefile.preamble src/hfs-1/hfs_newfs/Makefile.preamble
git commit -m "hfs: read the volume create date in disk byte order and build mount_hfs for i386"
```

---

### Task 15: First boot: device gates and the Apple volume (T1)

**Files:**
- Create (gitignored): `vm/work/hfsle/toast.img`, `vm/work/hfsle/t1/`

- [ ] **Step 1: Kernel and root image**

Kernel-build `i386` if the last one predates Task 12. Then Kernel-fetch, then Graft. Expected: `graft-kernel.py` prints the donor, the old and new kernel sizes, and a non-negative headroom.

- [ ] **Step 2: Gate run with a built volume**

The first boot uses a known-good built volume, so a failure is about the devices, not the Apple volume:

```bash
python vm/hfs_guest.py build hfsplus vm/work/hfsle/gate.img
python vm/hfs_guest.py run read vm/work/hfsle/gate vm/work/hfsle/gate.img vm/work/hfsle/mount_hfs
```

Then read `vm/work/hfsle/gate/end.png`, `vm/work/hfsle/gate/serial.log` and the harness output. The gates pass when:
- `out.txt` exists on the results disk. This proves `/dev/hd2a` mounted and `snapshot=off` kept the guest's writes.
- `mount rc=0`. This proves `/dev/hd1a` exists and the 512-byte label was accepted.

If `mount` of the results disk fails, the screenshot shows the error. Try `/dev/hd1b`, then `/dev/hd3a`: edit `RESULTS_DEV` in `vm/hfs_guest.py`, rerun, and commit the corrected constant in Step 5. If `mount_hfs` reports `Device not configured` or `Invalid argument`, check the serial log for the label being rejected before touching the kernel.

This run is also the first real test of the port (T3). If it gets past the gates but reports problems, go to Task 16 Step 3.

- [ ] **Step 3: T1, read-only mount of the Apple volume**

```bash
python vm/hfs_guest.py toast vm/work/hfsle/toast.img
python vm/hfs_guest.py run toast vm/work/hfsle/t1 vm/work/hfsle/toast.img vm/work/hfsle/mount_hfs
```

Expected: `PASS`. The guest lists all 171 entries (minus the private folder), and the `cksum` of every file of 2 MB or less matches the host's reading of the same bytes. On `FAILED`, work through the printed problems:
- `mount rc` non-zero: the serial log has the kernel's reason. A `hfs: B-tree ... not a valid node` line means the read-side swap rejected a node the Apple volume really contains, which is a bug in `hfs_endian.c`'s validation.
- Listing differences with correct counts: name conversion. Compare NFC and NFD forms first.
- Checksum differences: extent mapping. Check the fork's extents against `volume.fork_extents`.

- [ ] **Step 4: Confirm the host still reads the image cleanly**

```bash
python vm/hfs_guest.py check vm/work/hfsle/toast.img
```

Expected: `0 problems`. The mount was read-only, so the kernel wrote nothing.

- [ ] **Step 5: Commit any harness correction**

Commit only if Step 2 had to change the device constants:

```bash
git add vm/hfs_guest.py
git commit -m "vm: use the device nodes the i386 guest actually gives the HFS test disks"
```

---

### Task 16: Read and write tests (T2-T8)

**Files:**
- Create (gitignored): `vm/work/hfsle/{hfs,hfsplus,wrapped}.img`, `.before` copies, and one results directory per run

- [ ] **Step 1: T2-T4, fresh volumes, read**

```bash
for f in hfs hfsplus wrapped; do
    python vm/hfs_guest.py build $f vm/work/hfsle/$f.img
    python vm/hfs_guest.py run read vm/work/hfsle/r-$f vm/work/hfsle/$f.img vm/work/hfsle/mount_hfs || echo "T-read $f FAILED"
done
```

Expected: three `PASS` lines. `read` mounts read-write, so the kernel rewrites the volume header or MDB at mount and unmount, and may update access times in the catalog. The harness therefore also runs `check` on the image afterwards, which exercises the write path's node and header swaps before any file is created.

- [ ] **Step 2: T5-T7, write**

```bash
for f in hfs hfsplus wrapped; do
    python vm/hfs_guest.py build $f vm/work/hfsle/$f.img
    cp vm/work/hfsle/$f.img vm/work/hfsle/$f.before
    python vm/hfs_guest.py run write vm/work/hfsle/w-$f vm/work/hfsle/$f.img vm/work/hfsle/mount_hfs --before vm/work/hfsle/$f.before || echo "T-write $f FAILED"
done
```

Expected: three `PASS` lines. `--before` makes the harness require the wrapped volume's HFS wrapper MDB and alternate MDB to be byte-identical afterwards. For the plain volumes those sectors are the volume's own and are covered by `check`. The write test takes several minutes per volume because the guest runs `perl` 171 times on an emulated Pentium. The harness waits up to 30 minutes for `END`.

- [ ] **Step 3: If a run fails**

Keep the image. It is the evidence. Run `python vm/hfs_guest.py check IMG` to see the damage, and read `serial.log` for `hfs: ` lines. Map the damage to a component:

| Symptom | Look at |
|---|---|
| keys out of order, wrong offsets, bad node kinds | `hfs_endian.c` record swaps (Task 9) |
| node-map or `freeNodes` mismatch | `BTreeAllocate.c` map words (Task 10) |
| bitmap and extents disagree, free count wrong | `VolumeAllocation.c` (Task 12) |
| volume counts, `nextCatalogID`, unmounted bit | `hfs_flushMDB` / `hfs_flushvolumeheader` (Task 11) |
| wrapper MDB changed | the wrapper block in `hfs_flushvolumeheader` |

Fix in the owning task's files, rebuild (Kernel-build `i386`, Kernel-fetch, Graft), rebuild the test image, and rerun the failing test. After any kernel change, rerun Task 13 as well.

- [ ] **Step 4: T8, cold-cache reread**

```bash
for f in hfs hfsplus wrapped; do
    python vm/hfs_guest.py run reread vm/work/hfsle/rr-$f vm/work/hfsle/$f.img vm/work/hfsle/mount_hfs || echo "T-reread $f FAILED"
done
```

Expected: three `PASS` lines. This is a fresh boot reading back what the kernel itself wrote in Step 2.

- [ ] **Step 5: Record the results**

Append each test's name and PASS or FAIL, with the date, to `vm/work/hfsle/notes.txt`. There is no commit here; Task 17 turns the notes into the Outcome.

---

### Task 17: Outcome and merge

**Files:**
- Modify: `docs/superpowers/specs/2026-09-23-hfs-i386-endian-port-design.md` (append `## Outcome`)

- [ ] **Step 1: Final regression run**

Run the whole host suite:

```bash
python -m pytest tools/tests tools/hfsimg/tests -q
(cd vm && python -m pytest test_hfs_guest.py -q)
```

Expected: everything passes. This plan's tests are 36 of them; the rest, such as `test_ppc_package_check.py`, were already there. Then 5 passed.

- [ ] **Step 2: Write the Outcome**

Append `## Outcome` to the spec. Record:
- the date and branch
- the ppc `__TEXT` result of Task 13, with the object count
- each of T1-T8 with PASS or FAIL
- any deviation from this plan: device nodes, the hfs-1 fallback, fixes made in Task 16
- the scope limit named in the spec (512-byte-sector partitions only) as the recommended next piece of work

- [ ] **Step 3: Commit and merge**

```bash
git add docs/superpowers/specs/2026-09-23-hfs-i386-endian-port-design.md
git commit -m "docs: record the outcome of the HFS i386 endian port"
```

Then merge `hfs-endian` into `master` the way the other `.worktrees/` branches were merged, with a merge commit, after checking that `master` has not moved underneath the HFS files (`git log master -- src/kernel-7/bsd/hfs src/hfs-1`).
