# PowerPC Loadable Driver Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Copy nine measured kernel-resident PowerPC drivers into `src/drivers-ppc/` as loadable-driver projects, and scaffold stubs for the two with no in-tree source.

**Architecture:** A divergence-check tool is built first so every later task can verify its own copying. Nine projects are then created in three category batches, each mirroring `src/drivers-ppc/network/drvPPCGem` exactly. Two stub projects follow. A final task updates the README and runs acceptance.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, NeXT Project Builder makefile layout, Mach-O reading via `binrecon.macho`.

**Spec:** [2026-07-27-ppc-loadable-driver-packaging-design.md](../specs/2026-07-27-ppc-loadable-driver-packaging-design.md)

## Global Constraints

- **This work happens in the `ppc-package-recon` worktree.** Start every shell with:

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-package-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO
```

- **There is no PowerPC toolchain.** Nothing here compiles. Do not attempt a build, and do not claim anything builds.
- **Copied `.h`, `.m`, `.c` files must be byte-identical to their origins.** No header banner, no path comment, no reformatting, no line-ending change. Verify by hash.
- **`Default.table` and `DriverInfo` are copied verbatim from the shipped reference bundle** at `C:/Users/raynorpat/Downloads/test/Drivers/ppc/<bundle>.config/`. Do not author them.
- **Do not modify `src/kernel-7/` in any way**, including `conf/files.ppc`. The originals stay exactly where they are.
- **Do not modify any binrecon code.** The suite must stay at **845 passed, 4 skipped**.
- **Commit messages:** subsystem prefix (`drivers-ppc: `, `tools: `, `docs: `), one to two lines, no metadata, trailers, or emoji.
- **Harness quirk:** the Write tool refuses some report-shaped filenames. If it refuses, write elsewhere and `cp` into place with Bash.

### The reference layout

`src/drivers-ppc/network/drvPPCGem` is the in-tree model. Read it before creating anything:

```
<drvName>/
    Makefile
    Makefile.preamble
    dpkg/control
    <Proj>.drvproj/
        Default.table
        DriverInfo
        English.lproj/Localizable.strings
        English.lproj/DriverHelp/.gitkeep
        Makefile
        Makefile.preamble
        Makefile.postamble
        <Proj>.lksproj/
            <copied sources>
            Load_Commands.sect
            Makefile
            Makefile.preamble
            Makefile.postamble
            PB.project
```

The `.lksproj/Makefile` is the NeXT Project Builder form with `PROJECT_TYPE = Kernel Server`, `MAKEFILE = kernelserver.make`, `CODE_GEN_STYLE = DYNAMIC`, and `CLASSES` / `HFILES` listing the copied files. Copy `drvPPCGem`'s and change `NAME`, `CLASSES`, `HFILES`.

### The nine drivers

| Bundle | Source dir(s) under `src/kernel-7/bsd/dev/ppc/` | New project | Proj name |
| --- | --- | --- | --- |
| `drvPPCCuda` | `drvCuda` | `input/drvPPCCuda` | `PPCCuda` |
| `drvPPCPMU` | `drvPMU` | `input/drvPPCPMU` | `PPCPMU` |
| `drvPPCOHare` | `drvOHare` | `bus/drvPPCOHare` | `PPCOHare` |
| `drvPPCBMac` | `drvBMacEnet` | `network/drvPPCBMac` | `PPCBMac` |
| `drvPPCMace` | `drvMaceEnet` | `network/drvPPCMace` | `PPCMace` |
| `drvPPCDec21040` | `drvDECchip21040` | `network/drvPPCDec21040` | `PPCDec21040` |
| `drvPPC53c96` | `drvApple96_SCSI` | `scsi/drvPPC53c96` | `PPC53c96` |
| `drvPPCMesh` | `drvAppleMesh_SCSI` | `scsi/drvPPCMesh` | `PPCMesh` |
| `drvPPCSym8xx` | `drvSymbios8xx` | `scsi/drvPPCSym8xx` | `PPCSym8xx` |

`scsi/` is a new category directory.

### Two file-classification rules that will bite

1. **Not every copied file is a source file.** `drvSymbios8xx` contains `Sym8xxScript.lis` and `Sym8xxScript.ss` — SCSI script assembler inputs. **Copy them**, but they must **not** appear in `CLASSES` or `HFILES`. `CLASSES` lists `.m` only; `HFILES` lists `.h` only. Anything else goes in `OTHERSRCS` or is simply present.
2. **`CLASSES`/`HFILES` must be derived by listing the directory**, never by reading a Makefile or guessing. A wrong list produces a project that looks complete and fails at build time, which nothing in this environment can detect.

### Source file counts, for cross-checking

`drvCuda` 4, `drvPMU` 5, `drvOHare` 2, `drvBMacEnet` 8, `drvMaceEnet` 6, `drvDECchip21040` 11, `drvApple96_SCSI` 28, `drvAppleMesh_SCSI` 2, `drvSymbios8xx` 9 source files plus 2 script files (11 total in the directory).

**`drvPPCATA` is not in this plan.** `drvPPCATA` and `drvATADisk` contain conflicting revisions of `IdeCntPublic.h` and `ata_extern.h` — `kControllerTypeCmd646X` is `0x04` in one and `0x01` in the other. Merging them would silently destroy one revision. It gets its own spec; see spec §1.1a. Do not package it here, and do not "resolve" the conflict.

Re-derive rather than trusting these; report any disagreement.

---

## Task 1: The divergence check tool

**Files:**
- Create: `tools/ppc_package_check.py`
- Create: `tools/tests/test_ppc_package_check.py`

**Interfaces:**
- Produces: `tools/ppc_package_check.py`, runnable as `$VENVPY tools/ppc_package_check.py`, exiting 0 with `no divergences` when every packaged source matches its origin, and non-zero listing each difference otherwise. Tasks 2–6 use it to self-verify.

Built first so every packaging task can check its own work as it goes.

- [ ] **Step 1: Write the failing tests**

Create `tools/tests/test_ppc_package_check.py` covering three cases against temporary directory pairs:

1. two trees with identical file contents report no divergence
2. a file whose content differs is reported, naming the file
3. a file present in one tree but not the other is reported, naming the file and which side it is missing from

Use `tmp_path` fixtures; do not depend on the real repository layout.

- [ ] **Step 2: Run them and confirm they fail**

```bash
cd $REPO && PYTHONPATH=tools $VENVPY -m pytest tools/tests/test_ppc_package_check.py -q
```

Expected: failures, because the module does not exist yet.

- [ ] **Step 3: Write the tool**

`tools/ppc_package_check.py` compares each packaged driver's `.lksproj` sources against its `src/kernel-7/bsd/dev/ppc/` origin(s), by SHA-256. It needs a mapping from project to origin directories — the §"The nine drivers" table above. Every project maps to exactly one origin directory.

It reports, per project: files that differ, files present only in the package, files present only in the origin. It prints `no divergences` and exits 0 when clean.

Keep it a single file with no dependencies beyond the standard library. It is a check, not a framework.

- [ ] **Step 4: Confirm the tests pass**

```bash
cd $REPO && PYTHONPATH=tools $VENVPY -m pytest tools/tests/test_ppc_package_check.py -q
```

Expected: all pass.

- [ ] **Step 5: Run it against the current tree**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py
```

Expected at this point: it reports every project as **missing entirely**, since none exist yet. That is correct behaviour and confirms the mapping is wired up. Record the output.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add tools/ppc_package_check.py tools/tests/test_ppc_package_check.py && \
git commit -m "tools: add a divergence check for the packaged PowerPC drivers

Compares each packaged source against its kernel-7 origin by hash."
```

---

## Task 2: Package Cuda, PMU and OHare

**Files:** Create `src/drivers-ppc/input/drvPPCCuda/`, `input/drvPPCPMU/`, `bus/drvPPCOHare/` per the reference layout.

**Interfaces:** Consumes `tools/ppc_package_check.py` from Task 1. Produces three projects for Task 6's acceptance.

Sources: `drvCuda` (4 files), `drvPMU` (5), `drvOHare` (2). Reference bundles `drvPPCCuda.config`, `drvPPCPMU.config`, `drvPPCOHare.config`.

- [ ] **Step 1: Read the reference project**

```bash
cd $REPO && find src/drivers-ppc/network/drvPPCGem -type f | sort && \
  cat src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/Makefile
```

Note every file and reproduce the structure exactly.

- [ ] **Step 2: Create the three projects**

For each: create the directory tree, copy the sources byte-for-byte from `src/kernel-7/bsd/dev/ppc/<origin>/`, copy `Default.table` and `DriverInfo` verbatim from `C:/Users/raynorpat/Downloads/test/Drivers/ppc/<bundle>.config/`, and write the makefiles modelled on `drvPPCGem`'s with `NAME`, `CLASSES` and `HFILES` set from the actual directory listing.

Where the reference bundle has no `DriverInfo`, omit it — do not invent one. Where it has `English.lproj/Localizable.strings`, copy that too.

- [ ] **Step 3: Verify the copies are byte-identical**

```bash
cd $REPO && $VENVPY - <<'PY'
import hashlib, pathlib
PAIRS = [
    ('src/drivers-ppc/input/drvPPCCuda/PPCCuda.drvproj/PPCCuda.lksproj',
     ['src/kernel-7/bsd/dev/ppc/drvCuda']),
    ('src/drivers-ppc/input/drvPPCPMU/PPCPMU.drvproj/PPCPMU.lksproj',
     ['src/kernel-7/bsd/dev/ppc/drvPMU']),
    ('src/drivers-ppc/bus/drvPPCOHare/PPCOHare.drvproj/PPCOHare.lksproj',
     ['src/kernel-7/bsd/dev/ppc/drvOHare']),
]
def h(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
bad = 0
for pkg, origins in PAIRS:
    src = {}
    for o in origins:
        for f in pathlib.Path(o).iterdir():
            if f.is_file(): src[f.name] = h(f)
    got = {f.name: h(f) for f in pathlib.Path(pkg).iterdir()
           if f.is_file() and f.suffix in ('.h', '.m', '.c', '.lis', '.ss')}
    missing = set(src) - set(got); extra = set(got) - set(src)
    diff = [n for n in set(src) & set(got) if src[n] != got[n]]
    print(f'{pkg}: origin {len(src)} packaged {len(got)} missing {sorted(missing)} extra {sorted(extra)} differing {sorted(diff)}')
    bad += len(missing) + len(diff)
print('OK' if bad == 0 else f'PROBLEMS: {bad}')
PY
```

Expected: `missing []`, `differing []`, and `OK`. `extra` should be empty too.

- [ ] **Step 4: Verify CLASSES and HFILES against the directory**

```bash
cd $REPO && for p in input/drvPPCCuda/PPCCuda.drvproj/PPCCuda.lksproj \
                     input/drvPPCPMU/PPCPMU.drvproj/PPCPMU.lksproj \
                     bus/drvPPCOHare/PPCOHare.drvproj/PPCOHare.lksproj; do
  d="src/drivers-ppc/$p"; echo "=== $p ==="
  echo "  .m on disk : $(cd $d && ls *.m 2>/dev/null | tr '\n' ' ')"
  echo "  CLASSES    : $(grep '^CLASSES' $d/Makefile | sed 's/CLASSES = //')"
  echo "  .h on disk : $(cd $d && ls *.h 2>/dev/null | tr '\n' ' ')"
  echo "  HFILES     : $(grep '^HFILES' $d/Makefile | sed 's/HFILES = //')"
done
```

Each pair must match exactly, in content if not order. **Compare the lists, do not eyeball the Makefile alone** — this is the failure mode nothing else can catch.

- [ ] **Step 5: Run the divergence check**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py
```

Expected: these three report clean; the other seven still report as missing.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add src/drivers-ppc/input/drvPPCCuda src/drivers-ppc/input/drvPPCPMU src/drivers-ppc/bus/drvPPCOHare && \
git commit -m "drivers-ppc: package Cuda, PMU and OHare as loadable drivers

Copies the kernel-resident sources into Project Builder kernel-server layout."
```

---

## Task 3: Package BMac, Mace and Dec21040

**Files:** Create `src/drivers-ppc/network/drvPPCBMac/`, `network/drvPPCMace/`, `network/drvPPCDec21040/`.

**Interfaces:** Consumes `tools/ppc_package_check.py`. Produces three projects for Task 6.

Sources: `drvBMacEnet` (8 files), `drvMaceEnet` (6), `drvDECchip21040` (11). Reference bundles `drvPPCBMac.config`, `drvPPCMace.config`, `drvPPCDec21040.config`.

> **`drvPPCATA` is deliberately not here.** `drvPPCATA` and `drvATADisk` carry conflicting revisions of `IdeCntPublic.h` and `ata_extern.h`; merging them would destroy one. It has its own spec. Do not add it, and do not attempt to reconcile the headers.

- [ ] **Step 1: Create the three projects**

Same procedure as Task 2 Step 2: create the tree, copy sources byte-for-byte from `src/kernel-7/bsd/dev/ppc/<origin>/`, copy `Default.table` and `DriverInfo` verbatim from the shipped bundle, and write the makefiles modelled on `drvPPCGem`'s with `NAME`, `CLASSES` and `HFILES` set from the actual directory listing.

- [ ] **Step 2: Verify the copies are byte-identical**

Use the Task 2 Step 3 script with these pairs:

```
('src/drivers-ppc/network/drvPPCBMac/PPCBMac.drvproj/PPCBMac.lksproj',
 ['src/kernel-7/bsd/dev/ppc/drvBMacEnet']),
('src/drivers-ppc/network/drvPPCMace/PPCMace.drvproj/PPCMace.lksproj',
 ['src/kernel-7/bsd/dev/ppc/drvMaceEnet']),
('src/drivers-ppc/network/drvPPCDec21040/PPCDec21040.drvproj/PPCDec21040.lksproj',
 ['src/kernel-7/bsd/dev/ppc/drvDECchip21040']),
```

Expected: `missing []`, `differing []`, `extra []`, and `OK`.

- [ ] **Step 3: Verify CLASSES and HFILES against the directory**

```bash
cd $REPO && for p in network/drvPPCBMac/PPCBMac.drvproj/PPCBMac.lksproj                      network/drvPPCMace/PPCMace.drvproj/PPCMace.lksproj                      network/drvPPCDec21040/PPCDec21040.drvproj/PPCDec21040.lksproj; do
  d="src/drivers-ppc/$p"; echo "=== $p ==="
  echo "  .m on disk : $(cd $d && ls *.m 2>/dev/null | tr '
' ' ')"
  echo "  CLASSES    : $(grep '^CLASSES' $d/Makefile | sed 's/CLASSES = //')"
  echo "  .h on disk : $(cd $d && ls *.h 2>/dev/null | tr '
' ' ')"
  echo "  HFILES     : $(grep '^HFILES' $d/Makefile | sed 's/HFILES = //')"
done
```

Each pair must match exactly in content. **Compare the lists; do not eyeball the Makefile alone.**

- [ ] **Step 4: Run the divergence check**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py
```

Expected: six projects clean, three still missing.

- [ ] **Step 5: Commit**

```bash
cd $REPO && git add src/drivers-ppc/network/drvPPCBMac   src/drivers-ppc/network/drvPPCMace src/drivers-ppc/network/drvPPCDec21040 && git commit -m "drivers-ppc: package BMac, Mace and Dec21040 as loadable drivers

Copies the kernel-resident Ethernet sources into kernel-server layout."
```

---

## Task 4: Package the three SCSI drivers

**Files:** Create `src/drivers-ppc/scsi/drvPPC53c96/`, `scsi/drvPPCMesh/`, `scsi/drvPPCSym8xx/`. `scsi/` is a new category directory.

**Interfaces:** Consumes `tools/ppc_package_check.py`. Produces three projects for Task 6.

Sources: `drvApple96_SCSI` (28), `drvAppleMesh_SCSI` (2 — `MESH_DBDMA.h` and `.m`, the whole 71-method driver in one file), `drvSymbios8xx` (9 source + 2 script). Reference bundles `drvPPC53c96.config`, `drvPPCMesh.config`, `drvPPCSym8xx.config`.

> **`drvSymbios8xx` contains `Sym8xxScript.lis` and `Sym8xxScript.ss`** — SCSI script assembler inputs, not C or Objective-C. **Copy them**, but they must not appear in `CLASSES` or `HFILES`. Put them in `OTHERSRCS` alongside the makefiles, or leave them present and unlisted; do not invent a build rule for them.

- [ ] **Step 1: Create the three projects**

Same procedure as Task 2 Step 2.

- [ ] **Step 2: Verify the copies are byte-identical**

Use the Task 2 Step 3 script with:

```
('src/drivers-ppc/scsi/drvPPC53c96/PPC53c96.drvproj/PPC53c96.lksproj',
 ['src/kernel-7/bsd/dev/ppc/drvApple96_SCSI']),
('src/drivers-ppc/scsi/drvPPCMesh/PPCMesh.drvproj/PPCMesh.lksproj',
 ['src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI']),
('src/drivers-ppc/scsi/drvPPCSym8xx/PPCSym8xx.drvproj/PPCSym8xx.lksproj',
 ['src/kernel-7/bsd/dev/ppc/drvSymbios8xx']),
```

Expected: `missing []`, `differing []`, `OK`. Sym8xx's origin count is 11 including the two script files.

- [ ] **Step 3: Verify CLASSES and HFILES, and that the script files are excluded**

```bash
cd $REPO && d=src/drivers-ppc/scsi/drvPPCSym8xx/PPCSym8xx.drvproj/PPCSym8xx.lksproj
echo ".m on disk : $(cd $d && ls *.m | tr '\n' ' ')"
echo "CLASSES    : $(grep '^CLASSES' $d/Makefile | sed 's/CLASSES = //')"
echo ".h on disk : $(cd $d && ls *.h | tr '\n' ' ')"
echo "HFILES     : $(grep '^HFILES' $d/Makefile | sed 's/HFILES = //')"
echo "script files present: $(cd $d && ls *.lis *.ss 2>/dev/null | tr '\n' ' ')"
echo "script files in CLASSES/HFILES (must be empty): $(grep -E '^(CLASSES|HFILES)' $d/Makefile | grep -oE '[A-Za-z0-9_]+\.(lis|ss)')"
```

The last line must print nothing. Then do the same `CLASSES`/`HFILES` comparison for the other two projects.

- [ ] **Step 4: Run the divergence check**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py
```

Expected: **all ten projects clean, `no divergences`, exit 0.**

- [ ] **Step 5: Commit**

```bash
cd $REPO && git add src/drivers-ppc/scsi && \
git commit -m "drivers-ppc: package the three PowerPC SCSI drivers as loadable drivers

Adds the scsi category with 53c96, Mesh and Sym8xx."
```

---

## Task 5: Stub projects for IOADBDevice and DEC21x4Ethernet

**Files:** Create `src/drivers-ppc/input/drvIOADBDevice/`, `src/drivers-ppc/network/drvDEC21x4Ethernet/`.

**Interfaces:** Produces two stub projects for Task 6.

Neither has any in-tree source. Both were measured only as binaries.

| Bundle | Classes and method counts |
| --- | --- |
| `IOADBDevice` | `ADBServer` 6, `IOADBDevice` 10 |
| `DEC21x4Ethernet` | `DEC21x4` 38 |

- [ ] **Step 1: Extract the exact selector lists from the binaries**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import re, collections
BASE = r'C:/Users/raynorpat/Downloads/test/Drivers/ppc'
pat = re.compile(r'^([-+])\[([A-Za-z0-9_]+)(?:\(([A-Za-z0-9_ ]+)\))? (.+)\]$')
for name, path in [('IOADBDevice','IOADBDevice.config/IOADBDevice_reloc'),
                   ('DEC21x4Ethernet','DEC21x4Ethernet.config/DEC21x4Ethernet_reloc')]:
    d = read_macho(f'{BASE}/{path}')
    syms = d['symbols'] if isinstance(d, dict) else d.symbols
    byc = collections.defaultdict(list)
    for s in syms:
        m = pat.match(s.get('name') or '')
        if m and s.get('address') is not None:
            byc[(m.group(2), m.group(3))].append((m.group(1), m.group(4)))
    print(f'=== {name} ===')
    for (cls, cat) in sorted(byc):
        if 'KernelServerInstance' in cls or cls.endswith('Version'): continue
        print(f'--- {cls}{"("+cat+")" if cat else ""} ({len(byc[(cls,cat)])}) ---')
        for sign, sel in sorted(byc[(cls, cat)]):
            print(f'  {sign} {sel}')
PY
```

Record this output verbatim in your report — it is the specification for the stubs.

- [ ] **Step 2: Determine each class's superclass**

The binaries' `.objc_class_name_*` symbols name every linked class. Use that plus the `Default.table` `Class Names` to decide what each stub inherits from. If the superclass cannot be determined from the binary, **say so and inherit from `IODirectDevice`**, recording the uncertainty — do not guess silently.

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
for n,p in [('IOADBDevice','IOADBDevice.config/IOADBDevice_reloc'),
            ('DEC21x4Ethernet','DEC21x4Ethernet.config/DEC21x4Ethernet_reloc')]:
    d=read_macho(rf'C:/Users/raynorpat/Downloads/test/Drivers/ppc/{p}')
    print(n, sorted(s['name'].replace('.objc_class_name_','') for s in d['symbols'] if (s.get('name') or '').startswith('.objc_class_name_')))
"
cat "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOADBDevice.config/Default.table"
cat "C:/Users/raynorpat/Downloads/test/Drivers/ppc/DEC21x4Ethernet.config/Default.table"
```

- [ ] **Step 3: Create the two stub projects**

Full §"reference layout" structure. `Default.table` and any `DriverInfo` copied verbatim from the shipped bundle.

Headers declare each class with its real superclass and **every** selector from Step 1. The `.m` files define every one of those selectors with a body that **returns a zero value of the declared return type and does nothing else** — no `IOLog`, no parameter checks, no invented logic.

Each `.m` and `.h` opens with a comment stating plainly: the class and selector list was extracted from the shipped binary's Objective-C metadata, **no source for this driver exists in the tree**, and **every method body is empty**. Add `STUB` to the `dpkg/control` description.

- [ ] **Step 4: Verify every selector is present**

```bash
cd $REPO && for f in src/drivers-ppc/input/drvIOADBDevice/*/*/*.m \
                     src/drivers-ppc/network/drvDEC21x4Ethernet/*/*/*.m; do
  echo "$f: $(grep -cE '^[-+][[:space:]]*\(' $f) method definitions"
done
```

Totals must be `ADBServer` 6 + `IOADBDevice` 10 = 16, and `DEC21x4` 38. Compare the actual selector names against Step 1's list, not just the counts.

- [ ] **Step 5: Confirm every stub file declares itself a stub**

```bash
cd $REPO && for f in $(find src/drivers-ppc/input/drvIOADBDevice src/drivers-ppc/network/drvDEC21x4Ethernet -name '*.m' -o -name '*.h'); do
  grep -qi "stub" "$f" && echo "OK   $f" || echo "MISSING STUB NOTE  $f"
done
```

Every line must read `OK`.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add src/drivers-ppc/input/drvIOADBDevice src/drivers-ppc/network/drvDEC21x4Ethernet && \
git commit -m "drivers-ppc: scaffold stub projects for IOADBDevice and DEC21x4Ethernet

Class and selector lists extracted from the shipped binaries; all bodies empty."
```

---

## Task 6: README and acceptance

**Files:** Modify `src/drivers-ppc/README`.

- [ ] **Step 1: Update the README**

List the ten new projects under their categories and the two stubs, marking the stubs clearly as stubs with no implementation. Follow the file's existing style. Note that the ten are **copies** of sources that also remain under `src/kernel-7/bsd/dev/ppc/`, and point at `tools/ppc_package_check.py`.

- [ ] **Step 2: Run the divergence check**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py; echo "exit=$?"
```

Expected: `no divergences`, `exit=0`. Acceptance item 6.

- [ ] **Step 3: Run the check tool's own tests and the binrecon suite**

```bash
cd $REPO && PYTHONPATH=tools $VENVPY -m pytest tools/tests/test_ppc_package_check.py -q && \
  PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: check tests pass; binrecon **845 passed, 4 skipped**. This spec touches no binrecon code, so any change there is a regression.

- [ ] **Step 4: Verify the full layout of all eleven projects**

```bash
cd $REPO && for p in input/drvPPCCuda input/drvPPCPMU bus/drvPPCOHare \
    network/drvPPCBMac network/drvPPCMace network/drvPPCDec21040 \
    scsi/drvPPC53c96 scsi/drvPPCMesh scsi/drvPPCSym8xx \
    input/drvIOADBDevice network/drvDEC21x4Ethernet; do
  d="src/drivers-ppc/$p"
  miss=""
  for f in Makefile Makefile.preamble dpkg/control; do
    [ -f "$d/$f" ] || miss="$miss $f"
  done
  for f in $(ls -d $d/*.drvproj 2>/dev/null); do
    for g in Default.table Makefile Makefile.preamble Makefile.postamble; do
      [ -f "$f/$g" ] || miss="$miss $(basename $f)/$g"
    done
    for l in $(ls -d $f/*.lksproj 2>/dev/null); do
      for g in Makefile Makefile.preamble Makefile.postamble PB.project Load_Commands.sect; do
        [ -f "$l/$g" ] || miss="$miss $(basename $l)/$g"
      done
    done
  done
  [ -z "$miss" ] && echo "OK   $p" || echo "MISSING $p:$miss"
done
```

Every line must read `OK`. Acceptance item 1.

- [ ] **Step 5: Confirm `src/kernel-7` is untouched**

```bash
cd $REPO && git diff --name-only HEAD~6..HEAD -- src/kernel-7 | head; echo "(empty = untouched)"
```

Adjust the range to cover every commit this plan made. Must be empty.

- [ ] **Step 6: Walk the acceptance list**

Confirm each of spec §4's eight items against observed output, and record the evidence. **Do not claim an item you did not observe. Do not claim anything builds** — there is no PowerPC toolchain, and spec §4's "Not claimed" paragraph governs.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add src/drivers-ppc/README && \
git commit -m "drivers-ppc: list the packaged PowerPC drivers and stubs in the README"
```

---

## Notes for the executing agent

- **Nothing here compiles, and nothing may claim to.** There is no PowerPC toolchain.
- **Copied sources must be byte-identical.** No banners, no comments, no reformatting. It is what makes the divergence check meaningful.
- **`CLASSES`/`HFILES` come from listing the directory**, never from reading a Makefile. A wrong list is undetectable in this environment.
- **`Default.table` and `DriverInfo` are Apple's files** — copy them, do not author or "correct" them, even where they look odd (`drvPPCDec21040` declares only one of its three classes).
- **Never modify `src/kernel-7/`.**
- **A stub must be unmistakable as a stub** — in its header comment, in every `.m`, and in `dpkg/control`.
