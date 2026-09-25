# HFS Plus Long-Name Mangling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every HFS Plus name longer than 255 bytes of UTF-8 a stand-in of at most 255 bytes (`<prefix>#<HEXID><.ext>`, as Mac OS X does), and make readdir, readdirattr, lookup, searchfs and exchangedata all work with it.

**Architecture:** A new `ConvertUnicodeToUTF8Mangled` in `UnicodeWrappers.c` builds the name. The three places that turn catalog names into BSD names call it when the plain conversion reports the name too long. The lookup side already exists (`GetEmbeddedFileID`, `LocateCatalogNodeByMangledName` and its fallbacks); it gets a parser fix, a buffer big enough to compare a long prefix, and one more fallback in `ExchangeFileIDs`. Spec: `docs/superpowers/specs/2026-09-23-hfs-long-name-mangling-design.md`.

**Tech Stack:** C (GCC 2.7.2.1, `-traditional-cpp`) in the Darwin 0.3 kernel `src/kernel-7`; Python 3 and POSIX sh in Git Bash on Windows; the Rhapsody build box (reached through `vm/rhap-remote.ps1`) for every compile and test run.

## Global Constraints

- Work only in the worktree `D:\RhapsodiOS\.claude\worktrees\funny-haslett-e6b79c`, branch `claude/ecstatic-cannon-4ff6b0`. Never touch the main checkout `D:\RhapsodiOS`.
- Commit messages: one line, starting with the subsystem (`kernel: `, `tools: `), describing what the change does. No trailers, no metadata, no `Co-Authored-By`.
- These files hold Mac Roman bytes: `UnicodeWrappers.c` (10), `Catalog.c` (1), `CatalogUtilities.c` (30), `FileIDsServices.c` (13), `HFSUnicodeWrappers.h` (1). Edit them only with the Python scripts given here, which read and write latin-1 and assert that the count of non-ASCII characters is unchanged. Never use an editor tool on them; it re-encodes them silently. `hfs_vnodeops.c` is ASCII.
- Every shell command runs in Git Bash from the worktree root. Environment variables do not persist between commands, so every command that reaches the box sets `RHAP_VM_DIR='D:\RhapsodiOS\vm'` itself (the worktree has no `vm/vm.conf`; it is gitignored and must not be copied).
- Never modify `/build/src`, `/build/tools` or `/build/repo` on the box, nor `/build/state` beyond the logs `rbuild` writes there. Never start anything while another `rbuild` runs there. Private directories are `/build/hfs-name-*` and `/build/hfs-ppc-check-*`, and are removed when done.
- The mangled name is `<prefix>#<HEXID><.ext>`: HEXID is the catalog node ID in upper-case hex with no leading zeros; `.ext` is a dot and 1 to 5 (`kMaxFileExtensionChars`) ASCII letters or digits that end the name, else empty; the whole is at most `maxDstLen - 1` bytes plus a NUL.
- No new compiler warnings in any changed file, compiled for ppc with the kernel's real flags (`ppc-compile-check.sh` checks this).
- Match the surrounding code: tabs, Allman braces and `//` comments in `hfscommon/`. Label every deliberate divergence from xnu-124 in a comment.

## File map

| File | Responsibility |
|---|---|
| `tools/hfs-name-test/box-run.ps1` (new) | Run a shell script on the build box, exit with its status |
| `tools/hfs-name-test/ppc-compile-check.sh` (new) | Compile the changed HFS files for ppc at a base revision and in the working tree; compare warnings and `nm -u` |
| `tools/hfs-name-test/extract.py` (new) | Pull the mangling and parsing functions out of `UnicodeWrappers.c` as plain ASCII |
| `tools/hfs-name-test/mangle_test.c` (new) | The round-trip test: mangle, check, parse back, compare as the lookup does |
| `tools/hfs-name-test/run-tests.sh` (new) | Build and run `mangle_test.c` on the box |
| `src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c` | `EXTENSIONCHAR`, `GetMangledFileIDString`, `GetMangledNameExtension`, `ConvertUnicodeToUTF8Mangled`; the parser fix in `CountFilenameExtensionChars` |
| `src/kernel-7/bsd/hfs/hfscommon/headers/system/HFSUnicodeWrappers.h` | Declares `ConvertUnicodeToUTF8Mangled` |
| `src/kernel-7/bsd/hfs/hfscommon/Catalog/CatalogUtilities.c` | `LocateCatalogNodeByMangledName`: compare the whole prefix |
| `src/kernel-7/bsd/hfs/hfscommon/Catalog/Catalog.c` | `GetCatalogNode`, `IterateCatalogNode`: mangle over-long names |
| `src/kernel-7/bsd/hfs/hfs_vnodeops.c` | `InsertMatch` (searchfs): mangle over-long names |
| `src/kernel-7/bsd/hfs/hfscommon/Catalog/FileIDsServices.c` | `ExchangeFileIDs`: mangled-name fallback |

Before Task 1, record the feature's base for the final check:

```bash
git rev-parse HEAD
```

Write the printed commit down as FEATURE_BASE (it is the commit that added this plan).

---

### Task 1: Build-box compile check

**Files:**
- Create: `tools/hfs-name-test/box-run.ps1`
- Create: `tools/hfs-name-test/ppc-compile-check.sh`

**Interfaces:**
- Produces: `tools/hfs-name-test/box-run.ps1 -ScriptFile <path>` (runs it on the box, prints its output, exits with its status; honours `RHAP_VM_DIR`). `tools/hfs-name-test/ppc-compile-check.sh BASE-REV` (exit 0 when every changed `.c` under `src/kernel-7/bsd/hfs` compiles for ppc with the same warnings as at BASE-REV; prints `nm -u` differences).

- [ ] **Step 1: Create `tools/hfs-name-test/box-run.ps1`**

```powershell
# Run a shell script on the build box and exit with its exit status.
# vm.conf is gitignored, so a worktree has none: set RHAP_VM_DIR to a vm
# directory that has one (such as the main checkout's) to use it instead.
param([Parameter(Mandatory = $true)][string]$ScriptFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:RHAP_VM_DIR) { $script:RhapVmDir = $env:RHAP_VM_DIR }
. (Join-Path $PSScriptRoot '..\..\vm\rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'hfs-name-test'
$ssh = Resolve-RhapTool -Name $cfg.Ssh -Kind 'ssh'
Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody (Get-Content -LiteralPath $ScriptFile -Raw)
$r = $script:RhapLastSshCapture
[Console]::Out.Write($r.Stdout)
if ($r.Stderr) { [Console]::Error.Write($r.Stderr) }
exit $r.ExitCode
```

- [ ] **Step 2: Create `tools/hfs-name-test/ppc-compile-check.sh`**

```sh
#!/bin/sh
# Compile the HFS sources that differ from BASE-REV with the real ppc kernel
# flags on the build box, once as they are at BASE-REV and once as they are in
# the working tree, and compare the two builds' warnings and undefined symbols.
#
# Usage (from anywhere in the repository):
#   tools/hfs-name-test/ppc-compile-check.sh BASE-REV
#
# Needs Python, RHAP_VM_DIR in a worktree (see box-run.ps1), a finished ppc
# kernel build on the box (its chroot under /private/tmp/roots supplies the
# other kernel headers and meta_features.h) and no rbuild running there.
# Exits non-zero if a file fails to compile or its warnings differ from
# BASE-REV's.  Differences in nm -u are reported, not failed.
set -e
[ $# -eq 1 ] || { echo "usage: $0 BASE-REV" >&2; exit 2; }
base=$1
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
hfs=src/kernel-7/bsd/hfs
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

changed=$(git -C "$root" diff --name-only "$base" -- "$hfs" | sed "s|^$hfs/||")
[ -n "$changed" ] || { echo "nothing under $hfs differs from $base"; exit 0; }
sources=$(echo "$changed" | grep '\.c$' || true)

# The working tree's hfs directory, and BASE-REV's copies of the changed files.
# They hold Mac Roman bytes, so both go to the box as uuencoded tars.  Archiving
# a subtree leaves out the root .gitattributes (eol=lf), so a global
# core.autocrlf=true would turn the base files' line endings into CRLF.
mkdir "$work/new"
cp -R "$root/$hfs" "$work/new/hfs"
(cd "$work" && tar --format=ustar -cf new.tar new)	# relative: GNU tar reads "C:/..." as host:path
git -C "$root" -c core.autocrlf=false archive --format=tar --prefix=base/hfs/ "$base:$hfs" $changed > "$work/base.tar"

uu() {
	python -c '
import binascii, sys
data = open(sys.argv[1], "rb").read()
sys.stdout.write("begin 644 %s\n" % sys.argv[2])
for i in range(0, len(data), 45):
    sys.stdout.write(binascii.b2a_uu(data[i:i + 45], backtick=True).decode("ascii"))
sys.stdout.write("`\nend\n")' "$1" "$2"
}

{
	cat <<'EOF'
set -u
if ps -axww | grep -v grep | grep rbuild >/dev/null; then
	echo "an rbuild is running on the box; try again when it has finished"
	exit 1
fi
R=
for r in /private/tmp/roots/kernel-*.roots/kernel-*.root; do
	if [ -f "$r${r%.root}.obj/RELEASE_PPC/meta_features.h" ]; then R=$r; fi
done
if [ -z "$R" ]; then echo "no finished ppc kernel build under /private/tmp/roots"; exit 1; fi
K=${R%.root}
O=$R$K.obj/RELEASE_PPC
W=/build/hfs-ppc-check-$$
mkdir -p $W && cd $W || exit 1
EOF
	echo "cat > new.uu <<'@@HFSPPCCHECK@@'"
	uu "$work/new.tar" new.tar
	echo "@@HFSPPCCHECK@@"
	echo "cat > base.uu <<'@@HFSPPCCHECK@@'"
	uu "$work/base.tar" base.tar
	echo "@@HFSPPCCHECK@@"
	echo "SOURCES='$(echo $sources)'"
	cat <<'EOF'
if ! (uudecode new.uu && uudecode base.uu && tar -xf new.tar && cp -R new base && tar -xf base.tar); then
	echo "could not unpack the sources on the box"; cd /; rm -rf $W; exit 1
fi
status=0
for f in $SOURCES; do
	b=`basename $f .c`
	for v in base new; do
		if ! cc -static -nostdinc -nostdlib -traditional-cpp -fno-builtin -c -g -O2 -MD \
			-imacros $O/meta_features.h -I$O -I$R$K -I$R$K/bsd -I$R$K/bsd/include \
			-I$R$K/machdep -I$R$K/bsd/netat -I$R$K/bsd/netat/h -I$R$K/bsd/netat/at \
			-I$R/System/Library/Frameworks/System.framework/PrivateHeaders \
			-I$R/System/Library/Frameworks/System.framework/Headers \
			-I$R/System/Library/Frameworks/System.framework/Headers/bsd \
			-DNEXT -DTIMEZONE="0" -DPST="0" -DINET -DMACH -DNO_DIRECT_RPC -DNETAT -DDEBUG \
			-DARCH_PRIVATE -D_KERNEL -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DKERNEL_BUILD \
			-D__APPLE__ -DNeXT -D_NEXT_SOURCE -arch ppc -I$R$K/bsd/include -finline \
			-fno-keep-inline-functions -force_cpusubtype_ALL -fwritable-strings -fno-common \
			-msoft-float -mcpu=604 -Dppc -DPPC -Wall -Wno-four-char-constants -fpascal-strings \
			$W/$v/hfs/$f -o $W/$v/$b.o > $W/$v/$b.warn 2>&1; then
			echo "$v/$f: compile FAILED"; cat $W/$v/$b.warn; status=1
		fi
		sed -e "s|$W/$v/hfs/||g" -e 's/:[0-9][0-9]*:/:/' $W/$v/$b.warn > $W/$v/$b.norm
		nm -u $W/$v/$b.o > $W/$v/$b.undef 2>/dev/null || true
	done
	echo "== $f: `grep -c warning $W/new/$b.warn` warning(s)"
	if cmp -s $W/base/$b.norm $W/new/$b.norm; then
		echo "   warnings: same as base"
	else
		echo "   warnings differ from base:"; diff $W/base/$b.norm $W/new/$b.norm; status=1
	fi
	if cmp -s $W/base/$b.undef $W/new/$b.undef; then
		echo "   nm -u: same as base"
	else
		echo "   nm -u differs from base:"; diff $W/base/$b.undef $W/new/$b.undef
	fi
done
cd /; rm -rf $W
exit $status
EOF
} > "$work/box.sh"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/box-run.ps1")" -ScriptFile "$(cygpath -w "$work/box.sh")"
```

- [ ] **Step 3: Run it against e0d32cd9e (the merge before this branch's HFS fixes)**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh e0d32cd9e
```

Expected: either the report shown in Step 6, or exactly `no finished ppc kernel build under /private/tmp/roots` (exit 1), or `an rbuild is running on the box; try again when it has finished` (wait ten minutes and repeat this step). A stray blank first line is the PowerShell host and is harmless. If the report appears, skip to Step 6.

- [ ] **Step 4: Only if there is no ppc kernel build: start a kernel-only ppc build**

This rebuilds the chroot from the box's shared `/build/src/kernel-7` without touching any shared tree. `rbuild kernel` builds only the core sources present in its source root and takes the others' apks from its destination, so the private source root holds just `kernel-7` and the destination gets the other ppc apks from the last ppc build.

```bash
start=$(mktemp) && cat > "$start" <<'EOF'
if ps -axww | grep -v grep | grep rbuild >/dev/null; then echo "an rbuild is running; do not start another"; exit 1; fi
P=/build/hfs-name-ppc
mkdir -p $P/src $P/dst || exit 1
[ -e $P/src/kernel-7 ] || ln -s /build/src/kernel-7 $P/src/kernel-7
cp /build/out-p0-ppc/driverkit-*-ppc.apk /build/out-p0-ppc/drivertools-*-ppc.apk \
   /build/out-p0-ppc/kernload-*-ppc.apk /build/out-p0-ppc/drvpexpert-*-ppc.apk $P/dst/ || exit 1
cd $P || exit 1
trap '' 1
PATH=/build/tools/bin:$PATH nohup rbuild kernel --state /build/state --arch ppc $P/src /build/repo $P/dst > $P/rbuild.log 2>&1 &
sleep 5
echo "started:"; tail -3 $P/rbuild.log
EOF
RHAP_VM_DIR='D:\RhapsodiOS\vm' powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/hfs-name-test/box-run.ps1)" -ScriptFile "$(cygpath -w "$start")"; rm -f "$start"
```

Expected: `started:` and the first lines of the rbuild log.

- [ ] **Step 5: Wait for the build to end**

Repeat every five minutes until no rbuild is running (a kernel-only build takes about fifteen minutes):

```bash
poll=$(mktemp) && cat > "$poll" <<'EOF'
ps -axww | grep -v grep | grep rbuild >/dev/null && echo "rbuild still running" || echo "rbuild finished"
tail -5 /build/hfs-name-ppc/rbuild.log
ls /private/tmp/roots/kernel-*.roots/kernel-*.root/private/tmp/roots/kernel-*.roots/kernel-*.obj/RELEASE_PPC/meta_features.h 2>&1
EOF
RHAP_VM_DIR='D:\RhapsodiOS\vm' powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/hfs-name-test/box-run.ps1)" -ScriptFile "$(cygpath -w "$poll")"; rm -f "$poll"
```

Expected at the end: `rbuild finished` and a path ending `RELEASE_PPC/meta_features.h`. The build itself may fail later on, for example at `fdesc_vnops.o` (the shared tree predates `master`'s ppc build fixes) or at the final link. That does not matter: the chroot and the generated headers are what the compile check needs, and Step 6 proves they suffice by compiling the base files cleanly. If rbuild has finished and `meta_features.h` does not exist, stop and report BLOCKED with the last 40 lines of `/build/hfs-name-ppc/rbuild.log`.

- [ ] **Step 6: Run the compile check against e0d32cd9e**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh e0d32cd9e
```

Expected (exit 0), for the three files this branch's earlier HFS fixes changed:

```
== hfs_vnodeops.c: 2 warning(s)
   warnings: same as base
   nm -u: same as base
== hfscommon/Catalog/Catalog.c: 0 warning(s)
   warnings: same as base
   nm -u: same as base
== hfscommon/Unicode/UnicodeWrappers.c: 4 warning(s)
   warnings: same as base
   nm -u: same as base
```

(The file order may differ.) Any `compile FAILED` line means the environment is not usable: stop and report BLOCKED with the output.

- [ ] **Step 7: Commit**

```bash
git add tools/hfs-name-test/box-run.ps1 tools/hfs-name-test/ppc-compile-check.sh
git commit -m "tools: add a script that compile-checks HFS changes for ppc on the build box"
```

---

### Task 2: `ConvertUnicodeToUTF8Mangled`

**Files:**
- Create: `tools/hfs-name-test/extract.py`
- Create: `tools/hfs-name-test/mangle_test.c`
- Create: `tools/hfs-name-test/run-tests.sh`
- Modify: `src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c` (new macro after `IsHexDigit`; new functions after `ConvertUnicodeToUTF8`)
- Modify: `src/kernel-7/bsd/hfs/hfscommon/headers/system/HFSUnicodeWrappers.h` (declaration after `ConvertUnicodeToUTF8`'s)

**Interfaces:**
- Consumes: `box-run.ps1`, `ppc-compile-check.sh` (Task 1). `ConvertUnicodeToUTF8(ByteCount srcLen, ConstUniCharArrayPtr srcStr, ByteCount maxDstLen, ByteCount *actualDstLen, unsigned char *dstStr)`, which always NUL-terminates and, when the name does not fit, drops its last whole character and returns `kTECOutputBufferFullStatus`.
- Produces: `OSErr ConvertUnicodeToUTF8Mangled(ByteCount srcLen, ConstUniCharArrayPtr srcStr, ByteCount maxDstLen, ByteCount *actualDstLen, unsigned char *dstStr, HFSCatalogNodeID cnid)`, always `noErr`. Macro `EXTENSIONCHAR(c)`. `tools/hfs-name-test/run-tests.sh` (exit 0 when every case passes).

- [ ] **Step 1: Create `tools/hfs-name-test/extract.py`**

```python
"""Print the parts of UnicodeWrappers.c that mangle_test.c is built from.

UnicodeWrappers.c holds Mac Roman bytes, so it is read as latin-1.  What is
printed must be plain ASCII, because run-tests.sh sends it to the build box
as a heredoc.
"""
import re
import sys

# In dependency order, so that no prototypes are needed.
FUNCTIONS = [
    "HexStringToInteger",
    "CountFilenameExtensionChars",
    "GetEmbeddedFileID",
    "ConvertUnicodeToUTF8",
    "GetMangledFileIDString",
    "GetMangledNameExtension",
    "ConvertUnicodeToUTF8Mangled",
]
MACROS = [
    "kASCIIPiSymbol",
    "kASCIIMicroSign",
    "kASCIIGreekDelta",
    "Is7BitASCII",
    "IsSpecialASCIIChar",
    "IsHexDigit",
    "EXTENSIONCHAR",
]


def main(path):
    src = open(path, "rb").read().decode("latin-1")
    parts = []
    m = re.search(r"kMaxFileExtensionChars\s*=\s*(\d+)", src)
    if not m:
        sys.exit("kMaxFileExtensionChars not found")
    parts.append("enum { kMaxFileExtensionChars = %s };" % m.group(1))
    for name in MACROS:
        m = re.search(r"^#define\s+%s\b.*$" % name, src, re.M)
        if not m:
            sys.exit("macro %s not found" % name)
        parts.append(m.group(0))
    for name in FUNCTIONS:
        # The return-type line, then the name at the start of a line, up to
        # the first "}" in column 0.
        m = re.search(r"^[^\n]*\n%s ?\([\s\S]*?\n\}" % name, src, re.M)
        if not m:
            sys.exit("function %s not found" % name)
        parts.append(m.group(0))
    text = "\n\n".join(parts) + "\n"
    if any(ord(c) > 0x7F for c in text):
        sys.exit("what was extracted is not plain ASCII")
    sys.stdout.write(text)


if __name__ == "__main__":
    main(sys.argv[1])
```

- [ ] **Step 2: Create `tools/hfs-name-test/mangle_test.c`**

The expected prefix lengths follow from the budget: `NAME_MAX + 1` (256) minus the ID string and the extension leaves room for the prefix and its NUL.

```c
/*
 * Test of HFS Plus long-name mangling: ConvertUnicodeToUTF8Mangled, and
 * GetEmbeddedFileID reading its names back (UnicodeWrappers.c).
 *
 * run-tests.sh builds this on the build box, against the real ConvertUTF.c
 * and the functions extract.py takes from UnicodeWrappers.c (extracted.c).
 */
#include <stdio.h>
#include <string.h>
#include "ConvertUTF.h"

typedef short			OSErr;
typedef unsigned long	ByteCount;
typedef unsigned long	ItemCount;
typedef unsigned char	UInt8;
typedef unsigned short	UInt16;
typedef unsigned long	UInt32;
typedef long			SInt32;
typedef unsigned char	Boolean;
typedef unsigned short	UniChar;
typedef const UniChar	*ConstUniCharArrayPtr;
typedef UInt32			HFSCatalogNodeID;

enum { noErr = 0, kTECPartialCharErr = -8753, kTECOutputBufferFullStatus = -8785 };
#define NAME_MAX	255
#define true		1
#define false		0
#define BlockMoveData(src, dst, len)	memmove((dst), (src), (len))

#include "extracted.c"

static int failures;

static void fail(const char *what, const char *why)
{
	printf("FAIL %s: %s\n", what, why);
	failures++;
}

/*
 * The comparison LocateCatalogNodeByMangledName (CatalogUtilities.c) makes,
 * which cannot be linked here because it needs the catalog: the name must
 * carry the node's ID, and the node's real name, converted into NAME_MAX + 1
 * bytes, must start with the mangled name's prefix.
 */
static int matcherAccepts(const UniChar *name, ItemCount n, const unsigned char *mangled,
						  HFSCatalogNodeID cnid)
{
	unsigned char	nodeName[NAME_MAX + 1];
	ByteCount		actualDstLen;
	UInt32			prefixlen;

	if (GetEmbeddedFileID(mangled, &prefixlen) != cnid)
		return 0;
	(void) ConvertUnicodeToUTF8(n * sizeof(UniChar), name, sizeof nodeName, &actualDstLen, nodeName);
	return actualDstLen >= prefixlen && memcmp(nodeName, mangled, prefixlen) == 0;
}

/*
 * Mangle name[0..n) with cnid and check that the result is wantPrefix bytes
 * of the name followed by wantSuffix, then that it reads back.
 */
static void check(const char *what, const UniChar *name, ItemCount n, HFSCatalogNodeID cnid,
				  ByteCount wantPrefix, const char *wantSuffix)
{
	unsigned char	out[NAME_MAX + 1 + 16];
	unsigned char	plain[3 * 255 + 1];
	ByteCount		len, plainLen;
	UInt32			prefixlen;

	memset(out, 0xAA, sizeof out);
	if (ConvertUnicodeToUTF8Mangled(n * sizeof(UniChar), name, NAME_MAX + 1, &len, out, cnid) != noErr)
		{ fail(what, "returned an error"); return; }
	if (memchr(out, 0, NAME_MAX + 1) == NULL)
		{ fail(what, "no NUL in the first NAME_MAX + 1 bytes"); return; }
	if (out[NAME_MAX + 1] != 0xAA)
		{ fail(what, "wrote past NAME_MAX + 1 bytes"); return; }
	if (strlen((char *) out) != len)
		{ fail(what, "actualDstLen is not the length"); return; }
	if (len != wantPrefix + strlen(wantSuffix)) {
		printf("     got %lu bytes, ending \"%s\"\n", len, (char *) out + (len > 24 ? len - 24 : 0));
		fail(what, "wrong length");
		return;
	}
	if (strcmp((char *) out + wantPrefix, wantSuffix) != 0)
		{ fail(what, "wrong file ID or extension"); return; }

	(void) ConvertUnicodeToUTF8(n * sizeof(UniChar), name, sizeof plain, &plainLen, plain);
	if (memcmp(out, plain, wantPrefix) != 0)
		{ fail(what, "the prefix is not the start of the name"); return; }
	if ((plain[wantPrefix] & 0xC0) == 0x80)
		{ fail(what, "the prefix ends inside a character"); return; }

	if (GetEmbeddedFileID(out, &prefixlen) != cnid)
		{ fail(what, "GetEmbeddedFileID read the wrong file ID"); return; }
	if (prefixlen != wantPrefix)
		{ fail(what, "GetEmbeddedFileID read the wrong prefix length"); return; }
	if (!matcherAccepts(name, n, out, cnid))
		{ fail(what, "LocateCatalogNodeByMangledName's comparison rejects it"); return; }
	printf("ok   %s\n", what);
}

int main(void)
{
	UniChar		s[400];
	ItemCount	n, i;

	/* 120 kanji (3 bytes each) + ".txt" = 364 bytes, ID 0x1A2B.  "#1A2B" and
	   ".txt" leave 247 bytes with the NUL: 82 kanji (246) fit.  246 + 9 = 255. */
	n = 0;
	for (i = 0; i < 120; i++) s[n++] = 0x65E5;
	s[n++] = '.'; s[n++] = 't'; s[n++] = 'x'; s[n++] = 't';
	check("kanji name with .txt", s, n, 0x1A2B, 246, "#1A2B.txt");

	/* 100 hiragana, no extension, ID 0x10.  "#10" leaves 253: 84 (252) fit. */
	n = 0;
	for (i = 0; i < 100; i++) s[n++] = 0x3042;
	check("hiragana, no extension, ID 0x10", s, n, 0x10, 252, "#10");

	/* 90 hiragana + ".abcdef": 6 letters is too many for an extension.
	   ID 0x103, which xnu-124 writes "#13".  "#103" leaves 252: 83 (249) fit. */
	n = 0;
	for (i = 0; i < 90; i++) s[n++] = 0x3042;
	s[n++] = '.';
	for (i = 0; i < 6; i++) s[n++] = 'a' + i;
	check("6-letter tail is no extension, ID 0x103", s, n, 0x103, 249, "#103");

	/* 90 hiragana + ".": a trailing dot is no extension.  ID 0x1000:
	   "#1000" leaves 251: 83 (249) fit. */
	n = 0;
	for (i = 0; i < 90; i++) s[n++] = 0x3042;
	s[n++] = '.';
	check("trailing dot is no extension, ID 0x1000", s, n, 0x1000, 249, "#1000");

	/* "aa" + 64 surrogate pairs (4 bytes each) = 258 bytes, ID 0x10.  "#10"
	   leaves 253: "aa" + 62 pairs (250) fit, and a 63rd would end at 254. */
	n = 0;
	s[n++] = 'a'; s[n++] = 'a';
	for (i = 0; i < 64; i++) { s[n++] = 0xD83D; s[n++] = 0xDE00; }
	check("surrogate pair at the cut", s, n, 0x10, 250, "#10");

	/* 300 'z' + ".abcde" (5 letters: the longest extension), ID 0xFFFFFFFF.
	   "#FFFFFFFF" and ".abcde" leave 241: 240 fit, 240 + 15 = 255. */
	n = 0;
	for (i = 0; i < 300; i++) s[n++] = 'z';
	s[n++] = '.';
	for (i = 0; i < 5; i++) s[n++] = 'a' + i;
	check("ASCII name with 5-letter extension, ID 0xFFFFFFFF", s, n, 0xFFFFFFFF, 240, "#FFFFFFFF.abcde");

	printf("%d failure(s)\n", failures);
	return failures != 0;
}
```

- [ ] **Step 3: Create `tools/hfs-name-test/run-tests.sh`**

```sh
#!/bin/sh
# Build and run mangle_test.c on the build box, against the real ConvertUTF.c
# and the functions extract.py takes from UnicodeWrappers.c.
#
# Usage (from anywhere in the repository): tools/hfs-name-test/run-tests.sh
# Needs Python and, in a worktree, RHAP_VM_DIR (see box-run.ps1).
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
u=$root/src/kernel-7/bsd/hfs/hfscommon/Unicode
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python "$here/extract.py" "$u/UnicodeWrappers.c" > "$work/extracted.c"
{
	echo 'T=/build/hfs-name-test-$$'
	echo 'mkdir -p $T && cd $T || exit 1'
	for f in "$u/ConvertUTF.c" "$u/ConvertUTF.h" "$work/extracted.c" "$here/mangle_test.c"; do
		echo "cat > $(basename "$f") <<'@@HFSNAMETEST@@'"
		cat "$f"
		echo '@@HFSNAMETEST@@'
	done
	echo 'cc -Wall -o mangle_test mangle_test.c ConvertUTF.c && ./mangle_test; status=$?'
	echo 'cd /; rm -rf $T; exit $status'
} > "$work/box.sh"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/box-run.ps1")" -ScriptFile "$(cygpath -w "$work/box.sh")"
```

- [ ] **Step 4: Run the test to see it fail**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/run-tests.sh
```

Expected: `macro EXTENSIONCHAR not found`, exit 1.

- [ ] **Step 5: Add the macro and the three functions to `UnicodeWrappers.c`**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c'
s = open(p, 'rb').read().decode('latin-1')
before = sum(1 for c in s if ord(c) > 0x7F)

hexdigit = "#define IsHexDigit(c)\t\t\t\t( ((c) >= (UInt8) '0' && (c) <= (UInt8) '9') || ((c) >= (UInt8) 'A' && (c) <= (UInt8) 'F') )\n"
extchar = "#define EXTENSIONCHAR(c)\t\t\t( ((c) >= 'a' && (c) <= 'z') || ((c) >= 'A' && (c) <= 'Z') || ((c) >= '0' && (c) <= '9') )\n"

anchor = "\treturn noErr;\n}\n\n\nOSErr\nConvertUTF8ToMacRoman("
mangler = r'''//
// A file ID as "#" and upper-case hex without leading zeros, for a mangled
// name.  Returns its length.  (xnu-124's GetFileIDString also drops a 0 that
// follows the leading digit, writing 0x103 as "#13"; this one does not.)
//
static ByteCount
GetMangledFileIDString( HFSCatalogNodeID fileID, char *fileIDStr )
{
	static const char	*translate = "0123456789ABCDEF";
	ByteCount			i;
	SInt32				b;
	char				c;

	fileIDStr[0] = '#';
	i = 1;

	for ( b = 28; b >= 0; b -= 4 )
	{
		c = translate[(fileID >> b) & 0x0F];

		if ( c != '0' || i > 1 || b == 0 )		// skip leading zeros only
			fileIDStr[i++] = c;
	}
	fileIDStr[i] = '\0';

	return i;
}


//
// The extension of a Unicode name as a C string, for a mangled name: a dot and
// 1 to kMaxFileExtensionChars ASCII letters or digits that end the name, or ""
// if it has none.  Returns its length.  (As xnu-124's GetFilenameExtension.)
//
static ByteCount
GetMangledNameExtension( ItemCount length, ConstUniCharArrayPtr unicodeStr, char *extStr )
{
	ItemCount	i;
	ItemCount	extChars;
	ItemCount	maxExtChars;
	UniChar		c;

	extStr[0] = '\0';				// assume there's no extension

	if ( length < 3 )
		return 0;					// "x.y" is the shortest name with an extension

	if ( length < (kMaxFileExtensionChars + 2) )
		maxExtChars = length - 2;	// leave room for a prefix character and the dot
	else
		maxExtChars = kMaxFileExtensionChars;

	for ( extChars = 0; extChars <= maxExtChars; ++extChars )
	{
		c = unicodeStr[length - 1 - extChars];

		if ( c == (UniChar) '.' )
			break;
		if ( !EXTENSIONCHAR(c) )
			return 0;
	}
	if ( extChars == 0 || extChars > maxExtChars )
		return 0;					// it ends in a dot, or no dot is near enough the end

	for ( i = 0; i <= extChars; ++i )	// the dot, then the extension
		extStr[i] = (char) unicodeStr[length - 1 - extChars + i];
	extStr[i] = '\0';

	return i;
}


/*
	Make a name of at most maxDstLen - 1 bytes for a Unicode name too long to
	convert whole: as much of the name as fits, "#" and its file ID in hex, then
	its extension, as in "A long name#1A2B.txt".  GetEmbeddedFileID and
	LocateCatalogNodeByMangledName find the node from it again.  As in xnu-124.
*/
OSErr
ConvertUnicodeToUTF8Mangled(ByteCount srcLen, ConstUniCharArrayPtr srcStr, ByteCount maxDstLen,
							ByteCount *actualDstLen, unsigned char* dstStr, HFSCatalogNodeID cnid)
{
	char		fileIDStr[15];
	char		extStr[15];
	ByteCount	fileIDLen;
	ByteCount	extLen;
	ByteCount	prefixLen;

	fileIDLen = GetMangledFileIDString(cnid, fileIDStr);
	extLen = GetMangledNameExtension(srcLen / sizeof(UniChar), srcStr, extStr);

	// the name without its extension, cut on a whole character to leave room for the rest
	(void) ConvertUnicodeToUTF8(srcLen - extLen * sizeof(UniChar), srcStr,
								maxDstLen - fileIDLen - extLen, &prefixLen, dstStr);

	BlockMoveData(fileIDStr, dstStr + prefixLen, fileIDLen);
	BlockMoveData(extStr, dstStr + prefixLen + fileIDLen, extLen + 1);	// with its NUL
	*actualDstLen = prefixLen + fileIDLen + extLen;

	return noErr;
}
'''

edits = [
	(hexdigit, hexdigit + "\n" + extchar),
	(anchor, "\treturn noErr;\n}\n\n\n" + mangler + "\n\nOSErr\nConvertUTF8ToMacRoman("),
]
for old, new in edits:
	assert s.count(old) == 1, (old, s.count(old))
	s = s.replace(old, new)
assert sum(1 for c in s if ord(c) > 0x7F) == before
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

Expected: `ok src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c`. The mangler copies with `BlockMoveData` (a kernel function in `MacOSStubs.c`), not `strcat`, because this file declares no string functions and an implicit `strcat` would be a new warning.

- [ ] **Step 6: Declare it in `HFSUnicodeWrappers.h`**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfscommon/headers/system/HFSUnicodeWrappers.h'
s = open(p, 'rb').read().decode('latin-1')
before = sum(1 for c in s if ord(c) > 0x7F)

old = ("extern OSErr ConvertUnicodeToUTF8 ( ByteCount srcLen,\n"
	"\t\t\t\t\t\t\t\t\tConstUniCharArrayPtr srcStr,\n"
	"\t\t\t\t\t\t\t\t\tByteCount maxDstLen,\n"
	"\t\t\t\t\t \t\t\t\tByteCount *actualDstLen,\n"
	"\t\t\t\t\t\t\t\t\tunsigned char* dstStr );\n")
new = old + ("\n"
	"extern OSErr ConvertUnicodeToUTF8Mangled ( ByteCount srcLen,\n"
	"\t\t\t\t\t\t\t\t\t\t   ConstUniCharArrayPtr srcStr,\n"
	"\t\t\t\t\t\t\t\t\t\t   ByteCount maxDstLen,\n"
	"\t\t\t\t\t\t\t\t\t\t   ByteCount *actualDstLen,\n"
	"\t\t\t\t\t\t\t\t\t\t   unsigned char* dstStr,\n"
	"\t\t\t\t\t\t\t\t\t\t   HFSCatalogNodeID cnid );\n")

assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)
assert sum(1 for c in s if ord(c) > 0x7F) == before
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

Expected: `ok src/kernel-7/bsd/hfs/hfscommon/headers/system/HFSUnicodeWrappers.h`.

- [ ] **Step 7: Run the test to see it pass**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/run-tests.sh
```

Expected (exit 0), with no compiler warnings before it:

```
ok   kanji name with .txt
ok   hiragana, no extension, ID 0x10
ok   6-letter tail is no extension, ID 0x103
ok   trailing dot is no extension, ID 0x1000
ok   surrogate pair at the cut
ok   ASCII name with 5-letter extension, ID 0xFFFFFFFF
0 failure(s)
```

- [ ] **Step 8: Compile-check for ppc**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh HEAD
```

Expected (exit 0):

```
== hfscommon/Unicode/UnicodeWrappers.c: 4 warning(s)
   warnings: same as base
   nm -u differs from base:
> _BlockMoveData
```

(The file's only other `BlockMoveData` call is under `#if TARGET_OS_MAC`, so the reference is new; the diff may show it with a line-number header such as `12a13`.)

- [ ] **Step 9: Commit**

```bash
git add tools/hfs-name-test/extract.py tools/hfs-name-test/mangle_test.c tools/hfs-name-test/run-tests.sh
git commit -m "tools: add a build-box test for HFS Plus long-name mangling"
git add src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c src/kernel-7/bsd/hfs/hfscommon/headers/system/HFSUnicodeWrappers.h
git commit -m "kernel: add ConvertUnicodeToUTF8Mangled to name HFS Plus files too long for a 255-byte UTF-8 name"
```

---

### Task 3: Parse a mangled name whose prefix ends in a dot and letters

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c` (`CountFilenameExtensionChars`)
- Modify: `tools/hfs-name-test/mangle_test.c` (one more case)

**Interfaces:**
- Consumes: `EXTENSIONCHAR(c)` (Task 2).
- Produces: `CountFilenameExtensionChars` counts only ASCII letters and digits; `GetEmbeddedFileID` is otherwise unchanged.

- [ ] **Step 1: Add the case to `mangle_test.c`**

Insert before the line `	printf("%d failure(s)\n", failures);`:

```c
	/* 249 'x' + ".ab" + 20 'y' (no extension: 22 letters follow the dot), ID
	   0x1A.  "#1A" leaves 253: the prefix is 249 'x' + ".ab" (252), so the name
	   ends ".ab#1A".  A parser that counts any printable ASCII as an extension
	   character takes "ab#1A" for one and never finds the file ID. */
	n = 0;
	for (i = 0; i < 249; i++) s[n++] = 'x';
	s[n++] = '.'; s[n++] = 'a'; s[n++] = 'b';
	for (i = 0; i < 20; i++) s[n++] = 'y';
	check("dot just before the file ID", s, n, 0x1A, 252, "#1A");

```

- [ ] **Step 2: Run the test to see it fail**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/run-tests.sh
```

Expected (exit 1): the six earlier cases `ok`, then:

```
FAIL dot just before the file ID: GetEmbeddedFileID read the wrong file ID
1 failure(s)
```

- [ ] **Step 3: Count only letters and digits**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c'
s = open(p, 'rb').read().decode('latin-1')
before = sum(1 for c in s if ord(c) > 0x7F)

old = "\t\tif ( Is7BitASCII(c) || IsSpecialASCIIChar(c) )\n\t\t\t++extChars;\n"
new = ("\t\tif ( EXTENSIONCHAR(c) )\t\t// letters and digits, as GetMangledNameExtension copies (xnu-124)\n"
	"\t\t\t++extChars;\n")

assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)
assert sum(1 for c in s if ord(c) > 0x7F) == before
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

- [ ] **Step 4: Run the test to see it pass**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/run-tests.sh
```

Expected (exit 0): seven `ok` lines, the last `ok   dot just before the file ID`, then `0 failure(s)`.

- [ ] **Step 5: Compile-check for ppc**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh HEAD
```

Expected (exit 0):

```
== hfscommon/Unicode/UnicodeWrappers.c: 4 warning(s)
   warnings: same as base
   nm -u: same as base
```

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfscommon/Unicode/UnicodeWrappers.c tools/hfs-name-test/mangle_test.c
git commit -m "kernel: count only letters and digits as a mangled name's extension, so a dot before its file ID parses"
```

---

### Task 4: Compare all of a long mangled name's prefix

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfscommon/Catalog/CatalogUtilities.c` (`LocateCatalogNodeByMangledName`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `LocateCatalogNodeByMangledName` converts the node's name into `NAME_MAX + 1` bytes, so a prefix of up to 252 bytes can match. Its signature is unchanged.

The function needs the catalog, so it cannot be linked into the host test. `mangle_test.c`'s `matcherAccepts` already makes the comparison with a `NAME_MAX + 1` buffer; this task makes the kernel do the same, and the compile check verifies it.

- [ ] **Step 1: Enlarge the buffer**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfscommon/Catalog/CatalogUtilities.c'
s = open(p, 'rb').read().decode('latin-1')
before = sum(1 for c in s if ord(c) > 0x7F)

edits = [
	("\tunsigned char\t\tnodeName[64];\n",
	 "\tunsigned char\t\tnodeName[NAME_MAX + 1];\t// all of a long mangled name's prefix is compared (xnu-124 stops at 58 bytes)\n"),
	("\t\t\t\t\t\t\t\t\t64,\n\t\t\t\t\t\t\t\t\t&actualDstLen,\n\t\t\t\t\t\t\t\t\tnodeName);\n",
	 "\t\t\t\t\t\t\t\t\tsizeof(nodeName),\n\t\t\t\t\t\t\t\t\t&actualDstLen,\n\t\t\t\t\t\t\t\t\tnodeName);\n"),
]
for old, new in edits:
	assert s.count(old) == 1, (old, s.count(old))
	s = s.replace(old, new)
assert sum(1 for c in s if ord(c) > 0x7F) == before
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

- [ ] **Step 2: Compile-check for ppc**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh HEAD
```

Expected (exit 0): `== hfscommon/Catalog/CatalogUtilities.c`, `warnings: same as base`, `nm -u: same as base`.

- [ ] **Step 3: Run the host test**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/run-tests.sh
```

Expected: seven `ok` lines and `0 failure(s)`.

- [ ] **Step 4: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfscommon/Catalog/CatalogUtilities.c
git commit -m "kernel: compare all of a long mangled name's prefix when looking it up"
```

---

### Task 5: Mangle over-long names in readdir, lookup and searchfs

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfscommon/Catalog/Catalog.c` (`GetCatalogNode`, `IterateCatalogNode`)
- Modify: `src/kernel-7/bsd/hfs/hfs_vnodeops.c` (`InsertMatch`)

**Interfaces:**
- Consumes: `ConvertUnicodeToUTF8Mangled` (Task 2).
- Produces: `GetCatalogNode` and `GetCatalogOffspring` return `noErr` with a mangled `nodeSpec->name` for an HFS Plus name too long for `NAME_MAX + 1` bytes; `InsertMatch` packs the mangled name. In both `Catalog.c` functions `CopyCatalogNodeData` now runs before the name conversion (the two steps are independent).

- [ ] **Step 1: Edit `Catalog.c`**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfscommon/Catalog/Catalog.c'
s = open(p, 'rb').read().decode('latin-1')
before = sum(1 for c in s if ord(c) > 0x7F)

first = ("\t//--- Fill out universal data record (first: a mangled name needs the node ID)\n"
	"\tCopyCatalogNodeData(volume, %s, nodeData);\n\n")

edits = [
	# GetCatalogNode: fill in nodeData before the name ...
	("\t//--- Fill out universal data record...\n\tCopyCatalogNodeData(volume, record, nodeData);\n\n", ""),
	("\t//--- Fill out the FSSpec (output)\n",
	 first % "record" + "\t//--- Fill out the FSSpec (output)\n"),
	# ... and mangle an HFS Plus name too long for a BSD name
	("\t\t\t\t\t\t\t\t\t\t  nodeSpec->name);\n\t\t}\n\t}\n\telse // classic HFS\n",
	 "\t\t\t\t\t\t\t\t\t\t  nodeSpec->name);\n"
	 "\t\t\tif (result == kTECOutputBufferFullStatus)\t// too long for a BSD name: mangle it\n"
	 "\t\t\t\tresult = ConvertUnicodeToUTF8Mangled(key->hfsPlus.nodeName.length * sizeof(UniChar),\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t\t key->hfsPlus.nodeName.unicode,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t\t NAME_MAX + 1,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t\t &actualDstLen,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t\t nodeSpec->name,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t\t nodeData->nodeID);\n"
	 "\t\t}\n\t}\n\telse // classic HFS\n"),

	# IterateCatalogNode: the same two changes
	("\t//--- Fill out universal data record...\n\tCopyCatalogNodeData(volume, offspringData, nodeData);\n\n", ""),
	("\t//--- Fill out the FSSpec...\n",
	 first % "offspringData" + "\t//--- Fill out the FSSpec...\n"),
	("\t\t\t\t\t\t\t\t\t  nodeSpec->name);\n\t}\n\telse /* hfs name */\n",
	 "\t\t\t\t\t\t\t\t\t  nodeSpec->name);\n"
	 "\t\tif (result == kTECOutputBufferFullStatus)\t// too long for a BSD name: mangle it\n"
	 "\t\t\tresult = ConvertUnicodeToUTF8Mangled(offspringName->ustr.length * sizeof(UniChar),\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t offspringName->ustr.unicode,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t NAME_MAX + 1,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t &actualDstLen,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t nodeSpec->name,\n"
	 "\t\t\t\t\t\t\t\t\t\t\t\t nodeData->nodeID);\n"
	 "\t}\n\telse /* hfs name */\n"),
]
for old, new in edits:
	assert s.count(old) == 1, (old, s.count(old))
	s = s.replace(old, new)
assert sum(1 for c in s if ord(c) > 0x7F) == before
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

- [ ] **Step 2: Edit `hfs_vnodeops.c`**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfs_vnodeops.c'
s = open(p, 'rb').read().decode('latin-1')
assert all(ord(c) <= 0x7F for c in s)

old = ("\t\t\t\t\t\t\t\t\t\t&actualDstLen,\n"
	"\t\t\t\t\t\t\t\t\t\tcatalogInfo.spec.name);\n"
	"\t\t } else {\n")
new = ("\t\t\t\t\t\t\t\t\t\t&actualDstLen,\n"
	"\t\t\t\t\t\t\t\t\t\tcatalogInfo.spec.name);\n"
	"\t\t\tif ( err == kTECOutputBufferFullStatus )\t/* too long for a BSD name: mangle it */\n"
	"\t\t\t\terr = ConvertUnicodeToUTF8Mangled(\tkey->hfsPlus.nodeName.length * sizeof(UniChar),\n"
	"\t\t\t\t\t\t\t\t\t\t\t\tkey->hfsPlus.nodeName.unicode,\n"
	"\t\t\t\t\t\t\t\t\t\t\t\tsizeof(catalogInfo.spec.name),\n"
	"\t\t\t\t\t\t\t\t\t\t\t\t&actualDstLen,\n"
	"\t\t\t\t\t\t\t\t\t\t\t\tcatalogInfo.spec.name,\n"
	"\t\t\t\t\t\t\t\t\t\t\t\tcatalogInfo.nodeData.nodeID );\n"
	"\t\t } else {\n")

assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

- [ ] **Step 3: Review the diff**

```bash
git diff -- src/kernel-7/bsd/hfs/hfscommon/Catalog/Catalog.c src/kernel-7/bsd/hfs/hfs_vnodeops.c
```

Expected: in each of `GetCatalogNode` and `IterateCatalogNode`, `CopyCatalogNodeData` moves to just before `//--- Fill out the FSSpec`, and a seven-line `if (result == kTECOutputBufferFullStatus)` call follows the HFS Plus `ConvertUnicodeToUTF8`; in `InsertMatch`, the same follows its HFS Plus conversion, before `} else {`. Nothing else changes.

- [ ] **Step 4: Compile-check for ppc**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh HEAD
```

Expected (exit 0):

```
== hfs_vnodeops.c: 2 warning(s)
   warnings: same as base
   nm -u differs from base:
> _ConvertUnicodeToUTF8Mangled
== hfscommon/Catalog/Catalog.c: 0 warning(s)
   warnings: same as base
   nm -u differs from base:
> _ConvertUnicodeToUTF8Mangled
```

(Order may differ; each diff may carry a line-number header.)

- [ ] **Step 5: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfscommon/Catalog/Catalog.c src/kernel-7/bsd/hfs/hfs_vnodeops.c
git commit -m "kernel: list, look up and search HFS Plus names too long for a BSD name by their mangled names"
```

---

### Task 6: Let exchangedata find files by their mangled names

**Files:**
- Modify: `src/kernel-7/bsd/hfs/hfscommon/Catalog/FileIDsServices.c` (`ExchangeFileIDs`, HFS Plus branch)

**Interfaces:**
- Consumes: `LocateCatalogNodeByMangledName(const ExtendedVCB *volume, HFSCatalogNodeID folderID, const unsigned char *name, CatalogKey *keyPtr, CatalogRecord *dataPtr, UInt32 *hintPtr)` (existing, `CatalogUtilities.c`). It fills `keyPtr` with the node's real key, which `ExchangeFileIDs` later reuses for its second lookup and for `ReplaceBTreeRecord`.
- Produces: no new interface.

- [ ] **Step 1: Add the fallback for both files**

```bash
python - <<'PY'
p = 'src/kernel-7/bsd/hfs/hfscommon/Catalog/FileIDsServices.c'
s = open(p, 'rb').read().decode('latin-1')
before = sum(1 for c in s if ord(c) > 0x7F)

edits = []
for who, dirID, name in (('src', 'srcID', 'srcName'), ('dest', 'destID', 'destName')):
	lookup = f"\t\terr = LocateCatalogNodeByKey( vcb, {who}Hint, &{who}Key, &{who}Data, &{who}Hint );\n"
	rest = f"\t\tReturnIfError( err );\n\t\n\t\tif ( {who}Data.recordType != kHFSPlusFileRecord )\n"
	fallback = (f"\t\tif ( err == cmNotFound )\t\t//\tthe vnode may hold a mangled name\n"
		f"\t\t\terr = LocateCatalogNodeByMangledName( vcb, {dirID}, {name}, &{who}Key, &{who}Data, &{who}Hint );\n")
	edits.append((lookup + rest, lookup + fallback + rest))

for old, new in edits:
	assert s.count(old) == 1, (old, s.count(old))
	s = s.replace(old, new)
assert sum(1 for c in s if ord(c) > 0x7F) == before
open(p, 'wb').write(s.encode('latin-1'))
print('ok', p)
PY
```

- [ ] **Step 2: Compile-check for ppc**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh HEAD
```

Expected (exit 0):

```
== hfscommon/Catalog/FileIDsServices.c: N warning(s)
   warnings: same as base
   nm -u differs from base:
> _LocateCatalogNodeByMangledName
```

(N is whatever the base has; only "same as base" matters.)

- [ ] **Step 3: Commit**

```bash
git add src/kernel-7/bsd/hfs/hfscommon/Catalog/FileIDsServices.c
git commit -m "kernel: let exchangedata find files by their mangled HFS Plus names"
```

---

### Task 7: Whole-feature check and cleanup

**Files:** none changed.

- [ ] **Step 1: Run the host test**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/run-tests.sh
```

Expected: seven `ok` lines and `0 failure(s)`.

- [ ] **Step 2: Compile-check the whole feature against FEATURE_BASE**

```bash
RHAP_VM_DIR='D:\RhapsodiOS\vm' sh tools/hfs-name-test/ppc-compile-check.sh FEATURE_BASE
```

(Replace FEATURE_BASE with the commit recorded before Task 1.) Expected (exit 0): all five `.c` files `warnings: same as base`; `nm -u` gains exactly `_BlockMoveData` in `UnicodeWrappers.c`, `_ConvertUnicodeToUTF8Mangled` in `Catalog.c` and `hfs_vnodeops.c`, `_LocateCatalogNodeByMangledName` in `FileIDsServices.c`, and nothing in `CatalogUtilities.c`.

- [ ] **Step 3: Remove the private build directory, if Task 1 created one**

```bash
clean=$(mktemp) && printf 'rm -rf /build/hfs-name-ppc; ls -d /build/hfs-name-* 2>&1\n' > "$clean"
RHAP_VM_DIR='D:\RhapsodiOS\vm' powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/hfs-name-test/box-run.ps1)" -ScriptFile "$(cygpath -w "$clean")"; rm -f "$clean"
```

Expected: `ls: /build/hfs-name-*: No such file or directory`. Leave the chroot under `/private/tmp/roots` in place; it is shared.

- [ ] **Step 4: Confirm the branch is clean and list the commits**

```bash
git status --short && git log --oneline FEATURE_BASE..HEAD
```

Expected: no output from `git status`; seven commits (Task 1: one, Task 2: two, Tasks 3 to 6: one each).
