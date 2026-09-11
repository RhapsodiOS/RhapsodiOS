# PowerPC SCSI Driver Evidence Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure `drvPPCMesh` and `drvPPCSym8xx` against Apple's shipped Rhapsody binaries, and compare the four `IOSCSIController` drivers as a family.

**Architecture:** Four binrecon profiles drive IDA against four reference Mach-O artifacts. Two `--scope-to-objc` source maps record the machine-checkable correspondence; everything the maps leave out is bucketed so the gap is countable. A synthesis task assembles one report, adds the cross-family `IOSCSIController` comparison, and runs acceptance.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon (`tools/binrecon`), IDA Professional 9.2 headless, Mach-O 32-bit big-endian PowerPC.

**Spec:** [2026-07-27-ppc-scsi-driver-evidence-base-design.md](../specs/2026-07-27-ppc-scsi-driver-evidence-base-design.md)

**Precedent:** the network spec's report at `src/drivers-ppc/reconstruction/report-network.md` and its per-driver documents. The methodology is unchanged; read `src/drivers-ppc/reconstruction/Gem/findings.md` as the model for a per-driver document — it is the most thorough produced so far.

## Global Constraints

Every task's requirements implicitly include this section.

- **This work happens in the `ppc-storage-recon` worktree.** Start every shell with:

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-storage-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO
```

  `$VENVPY` points into the **main checkout** on purpose: `.venv-binrecon` is gitignored and exists only there.

- **Always set** `PYTHONPATH=tools/binrecon` on binrecon invocations.
- **Reference artifacts** live at `C:/Users/raynorpat/Downloads/test/Drivers/ppc/` and stay outside Git.
- **`binrecon analyze` exits 1 for every profile in this plan. Exit 1 is SUCCESS.** Reference-only profiles have no rebuilt artifact, so `normalized-functions` acceptance is unsatisfiable by construction. The pass condition is `"complete": true` plus a published `published/analysis-reference-ida.json`.
- **Never commit anything under `tools/binrecon/out/`.**
- **Do not modify any driver source, any header, or `src/kernel-7/conf/files.ppc`.** This plan measures. If a source looks wrong, record it as a finding.
- **Do not modify binrecon tooling** except under spec §3.5. None is anticipated — both known scanner limitations were pre-checked against both source directories and neither occurs.
- **`--scope-to-objc` is mandatory** on every `source-map` invocation.
- **Map validation must scope the analysis across all four map categories** — `mapped`, `unmapped`, `duplicate_candidates`, `boundary_disputed`.
- **Commit messages:** subsystem prefix (`binrecon: `, `drivers-ppc: `, `docs: `), one to two lines, no metadata, trailers, or emoji.
- **Harness quirk:** the Write tool refuses to create files literally named `findings.md` or `report-scsi.md`. Write to another name and `cp` it into place with Bash.
- **`SCRATCH`** is `C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad`.

### Driver parameter table

| KEY | DIR | Bundle artifact | `_reloc` artifact | `--source-dir` |
| --- | --- | --- | --- | --- |
| `mesh` | `Mesh` | `drvPPCMesh.config/drvPPCMesh` | `drvPPCMesh.config/drvPPCMesh_reloc` | `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI` |
| `sym8xx` | `Sym8xx` | `drvPPCSym8xx.config/drvPPCSym8xx` | `drvPPCSym8xx.config/drvPPCSym8xx_reloc` | `src/kernel-7/bsd/dev/ppc/drvSymbios8xx` |

### Expected artifact sizes

`validate` prints size and SHA-256. Sizes must match; record the hashes it prints.

| Artifact | Size |
| --- | --- |
| `drvPPCMesh` / `drvPPCMesh_reloc` | 8496 / 66712 |
| `drvPPCSym8xx` / `drvPPCSym8xx_reloc` | 8500 / 59128 |

### Established by the preceding specs — apply, do not re-derive

- **Buckets 1 and 2 will be 0 for both.** Statically linked kernel servers, not `MH_EXECUTE` helpers: no crt/dyld routines, no `__picsymbol_stub` section. State it with the reason.
- **Bucket 5 always prints 0 from the script.** Populate by hand from bucket 6, citing file and line. Each driver has roughly 15 C functions in its binary.
- **`read_macho` preserves Objective-C category tags; IDA's exported analysis strips them.** Both drivers are heavily category-fragmented, so this matters here more than anywhere so far:
  ```python
  from binrecon.macho import read_macho
  d = read_macho(r'<path to _reloc>')
  syms = d['symbols'] if isinstance(d, dict) else d.symbols
  ```
- **A name match is not a logic match.** The network spec found `GemEnetPrivate.m`'s `_mace_crc` had a source site under the right name but a different algorithm, producing different multicast hash indices on 5 of 5 vectors. Where a bucket-6 entry is small and self-contained, confirm the logic.
- **Characterise every "extra" and "missing" selector, class-insensitively as well.** A selector may exist in the binary on a sibling class — a placement difference, not a missing implementation. The first spec found exactly that in `drvPPCATA`.
- Libgcc helpers (`__udivdi3`, `__divdi3`) are compiler runtime, not driver source.
- Every driver measured so far has had exactly one address-`0x0` symbol: a method with a source site but no analysis function entry, recorded as a `boundary_disputed` candidate rather than a gap.
- **The plan's source method counts are approximate.** Every network task found more than the plan stated. Re-measure and record the measured number.

### Orientation only — re-measure rather than trusting these

`drvAppleMesh_SCSI`: 71 method definitions across `AppleMesh_SCSI` plus `Hardware`, `HardwarePrivate`, `MeshInterrupt`, `Mesh` and `Private` categories; 4 static C functions. Binary has 72 ObjC methods and 15 defined C functions.

`drvSymbios8xx`: 44 method definitions across `Sym8xxController` plus `Client`, `Execute` and `Init` categories; 0 static C functions. Binary has 46 ObjC methods and 15 defined C functions.

> `drvAppleMesh_SCSI` writes category headers with spaces inside the parentheses — `@implementation AppleMesh_SCSI( Hardware )`. Both scanners tolerate it; expect the spacing when comparing category names.

---

## File Structure

**Created — committed:**

- `tools/binrecon/profiles/{mesh,sym8xx}-ppc.json` and `-bundle-ppc.json`.
- `src/drivers-ppc/reconstruction/{Mesh,Sym8xx}/source-map.json`.
- `src/drivers-ppc/reconstruction/{Mesh,Sym8xx}/findings.md`.
- `src/drivers-ppc/reconstruction/report-scsi.md`.

**Modified — committed:** `tools/binrecon/tests/test_profile.py` — the inventory names 25 today and must name 29.

**Created — not committed:** `tools/binrecon/out/<KEY>-ppc/` and `<KEY>-bundle-ppc/`.

**Modified:** no driver source, no header, no build wiring.

---

## Task 1: Four profiles and the inventory test

**Files:**
- Create: `tools/binrecon/profiles/{mesh,sym8xx}-ppc.json`, `{mesh,sym8xx}-bundle-ppc.json`
- Modify: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: four profiles at `tools/binrecon/profiles/<KEY>-ppc.json` and `<KEY>-bundle-ppc.json`, `output_dir` of `../out/<KEY>-ppc` and `../out/<KEY>-bundle-ppc`. Tasks 2–3 consume these.

- [ ] **Step 1: Confirm the worktree and venv**

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-storage-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO && git branch --show-current && $VENVPY --version && \
  PYTHONPATH=tools/binrecon $VENVPY -m binrecon --help | head -3
```

Expected: `ppc-storage-recon`, `Python 3.13.9`, the binrecon usage banner.

- [ ] **Step 2: Generate the four profiles**

```bash
cd $REPO && $VENVPY - <<'PY'
import json
from pathlib import Path

TEMPLATE = {
    'schema_version': 'profile-v1',
    'name': None,
    'architecture': 'ppc',
    'endianness': 'big',
    'reference': {'path': '${BINRECON_REFERENCE}'},
    'analyzers': {
        'ida': {'enabled': True,
                'executable': 'C:/Program Files/IDA Professional 9.2/idat.exe',
                'timeout_seconds': 900, 'version': '9.2'},
        'ghidra': {'enabled': False,
                   'executable': 'D:/ghidra/support/analyzeHeadless.bat',
                   'timeout_seconds': 900, 'version': '12.1'},
        'angr': {'enabled': False,
                 'executable': '.venv-binrecon/Scripts/python.exe',
                 'timeout_seconds': 900, 'version': '9.3.0'},
    },
    'comparison': {'acceptance': 'normalized-functions',
                   'ignore_metadata': [], 'entry_points': []},
    'output_dir': None,
}

DRIVERS = {'mesh': 'drvPPCMesh', 'sym8xx': 'drvPPCSym8xx'}

out = Path('tools/binrecon/profiles')
for key, driver in DRIVERS.items():
    for suffix, label in (('', 'ppc'), ('-bundle', 'bundle ppc')):
        d = json.loads(json.dumps(TEMPLATE))
        d['name'] = f'{driver} {label} reconstruction'
        d['output_dir'] = f'../out/{key}{suffix}-ppc'
        p = out / f'{key}{suffix}-ppc.json'
        p.write_text(json.dumps(d, indent=2) + '\n')
        print('wrote', p)
PY
```

Expected: four `wrote tools/binrecon/profiles/...` lines.

- [ ] **Step 3: Validate all four**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && while read -r slug rel; do
  BINRECON_REFERENCE="$REF/$rel" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon validate --profile "tools/binrecon/profiles/$slug.json"
done <<'EOF'
mesh-ppc drvPPCMesh.config/drvPPCMesh_reloc
mesh-bundle-ppc drvPPCMesh.config/drvPPCMesh
sym8xx-ppc drvPPCSym8xx.config/drvPPCSym8xx_reloc
sym8xx-bundle-ppc drvPPCSym8xx.config/drvPPCSym8xx
EOF
```

Expected: four `reference ... size=... sha256=...` lines. **Check every size against the Global Constraints table.** A mismatch is a stop condition. **Record all four hashes in your report** — Tasks 2 and 3 need them and there is no other record.

- [ ] **Step 4: Update the inventory test**

`test_ppc_profile_inventory` asserts the exact sorted list of `*-ppc.json`. It names 25; it must name 29. Regenerate:

```bash
cd $REPO && $VENVPY -c "
from pathlib import Path
names = sorted(p.name for p in Path('tools/binrecon/profiles').glob('*-ppc.json'))
print(len(names))
for i in range(0, len(names), 2):
    print('        ' + ' '.join(f'\"{n}\",' for n in names[i:i+2]))
"
```

Replace the assertion's list with that output. **Do not weaken the test** into a subset, count, or glob check — asserting the exact inventory is the point.

- [ ] **Step 5: Run the suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: **830 passed, 4 skipped**. The baseline before this task is 826; the +4 is correct, because `test_ppc_profiles_are_reference_only_ida_runs` is parametrized over the profile glob and each new profile adds a passing instance.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add tools/binrecon/profiles/*-ppc.json tools/binrecon/tests/test_profile.py && \
git commit -m "binrecon: add four PowerPC profiles for the SCSI drivers

Covers the bundle stub and kernel-server _reloc of drvPPCMesh and drvPPCSym8xx."
```

---

## Task 2: Mesh — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/Mesh/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Mesh/findings.md`

**Interfaces:**
- Consumes: `mesh-ppc.json`, `mesh-bundle-ppc.json` from Task 1; `$SCRATCH/bucket_functions.py`, invoked as `$VENVPY <script> <analysis.json> <source-map.json>`, printing a bucket table and `RECONCILES: yes|no`. **Do not modify the script.** If missing, report NEEDS_CONTEXT.
- Produces: `src/drivers-ppc/reconstruction/Mesh/{source-map.json,findings.md}` for Task 4.

Source: `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI` — `AppleMesh_SCSI : IOSCSIController < IOPower >` plus five categories. The most category-fragmented driver measured so far.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "mesh-ppc drvPPCMesh.config/drvPPCMesh_reloc" "mesh-bundle-ppc drvPPCMesh.config/drvPPCMesh"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each `exit=1`. **Exit 1 is success.**

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['mesh-ppc','mesh-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected: both `complete= True published= True`.

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "mesh-ppc drvPPCMesh.config/drvPPCMesh_reloc" "mesh-bundle-ppc drvPPCMesh.config/drvPPCMesh"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Mesh && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/mesh-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCMesh.config/drvPPCMesh_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Mesh/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts and the per-category split**

```bash
cd $REPO && $VENVPY -c "
import json, re, collections
d=json.load(open('src/drivers-ppc/reconstruction/Mesh/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
c=collections.Counter()
for e in d['mapped']:
    m=re.match(r'^[-+]\[([A-Za-z0-9_]+)(?:\(([A-Za-z0-9_ ]+)\))?', e['reference_names'][0])
    if m: c[(m.group(2) or '').strip() or '(primary)'] += 1
print('mapped per category:', dict(c))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

The per-category split answers §4.2. **IDA's export strips category tags**, so if this comes back with everything under `(primary)`, get the real split from `read_macho` instead:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
import re, collections
d = read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCMesh.config/drvPPCMesh_reloc')
syms = d['symbols'] if isinstance(d, dict) else d.symbols
c = collections.Counter()
for s in syms:
    m = re.match(r'^[-+]\[([A-Za-z0-9_]+)(?:\(([A-Za-z0-9_ ]+)\))? ', s.get('name') or '')
    if m: c[(m.group(2) or '').strip() or '(primary)'] += 1
print(dict(c))
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/mesh-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Mesh/source-map.json
```

Expected: `RECONCILES: yes`, buckets 1 and 2 at 0. `RECONCILES: no` is a **stop condition** — report BLOCKED.

Resolve every bucket-6 entry against `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI`, moving confirmed matches to bucket 5 with file and line. Where an entry is small and self-contained, confirm the logic and not merely the name.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCMesh.config/drvPPCMesh_reloc" \
  src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI
```

Record verbatim and characterise every extra and missing entry, class-insensitively as well.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Mesh/source-map.json'
a = load_json(Path('tools/binrecon/out/mesh-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: the scoped line then `load_source_map OK`.

- [ ] **Step 9: Write `findings.md`**

`src/drivers-ppc/reconstruction/Mesh/findings.md`, following `src/drivers-ppc/reconstruction/Gem/findings.md` for structure and tone. Sections:

1. `## Artifacts` — both artifacts with size and the SHA-256 from Task 1. Note that this driver builds into the kernel via `src/kernel-7/conf/files.ppc` under `mk_hasdrivers` while the shipped artifact is a loadable kernel server.
2. `## Correspondence` — mapped, unmapped, duplicate_candidates, boundary_disputed; total functions; named vs unnamed.
3. `## Map validation` — Step 8 output and why the analysis is scoped first.
4. `## Buckets` — the Step 6 table, with the explicit statement that buckets 1 and 2 are empty and why.
5. `## Unmapped detail` — each unmapped entry with size, classified.
6. `## Invariant check` — Step 3 output.
7. `## Selector check` — Step 7 output verbatim plus your characterisation of every extra and missing entry.
8. `## Bundle stub` — what the bundle analysis contains.
9. `## Categories` — the Step 5 split, which category each method belongs to, and how you obtained it.

**Every number must come from output you observed.**

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Mesh && \
git commit -m "drivers-ppc: measure drvPPCMesh against its shipped binary

Source map and bucket reconciliation for the AppleMesh_SCSI driver."
```

---

## Task 3: Sym8xx — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/Sym8xx/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Sym8xx/findings.md`

**Interfaces:**
- Consumes: `sym8xx-ppc.json`, `sym8xx-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py`, unchanged.
- Produces: `src/drivers-ppc/reconstruction/Sym8xx/{source-map.json,findings.md}` for Task 4.

Source: `src/kernel-7/bsd/dev/ppc/drvSymbios8xx` — `Sym8xxController : IOSCSIController` plus `Client`, `Execute` and `Init` categories.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "sym8xx-ppc drvPPCSym8xx.config/drvPPCSym8xx_reloc" "sym8xx-bundle-ppc drvPPCSym8xx.config/drvPPCSym8xx"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each `exit=1`. Success.

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['sym8xx-ppc','sym8xx-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

Expected: both `complete= True published= True`.

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "sym8xx-ppc drvPPCSym8xx.config/drvPPCSym8xx_reloc" "sym8xx-bundle-ppc drvPPCSym8xx.config/drvPPCSym8xx"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Sym8xx && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/sym8xx-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCSym8xx.config/drvPPCSym8xx_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvSymbios8xx \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Sym8xx/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts and the per-category split**

```bash
cd $REPO && $VENVPY -c "
import json, re, collections
d=json.load(open('src/drivers-ppc/reconstruction/Sym8xx/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

For the category split use `read_macho`, since IDA's export strips category tags:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
import re, collections
d = read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCSym8xx.config/drvPPCSym8xx_reloc')
syms = d['symbols'] if isinstance(d, dict) else d.symbols
c = collections.Counter()
for s in syms:
    m = re.match(r'^[-+]\[([A-Za-z0-9_]+)(?:\(([A-Za-z0-9_ ]+)\))? ', s.get('name') or '')
    if m: c[(m.group(2) or '').strip() or '(primary)'] += 1
print(dict(c))
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/sym8xx-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Sym8xx/source-map.json
```

Expected: `RECONCILES: yes`, buckets 1 and 2 at 0.

Resolve every bucket-6 entry against `src/kernel-7/bsd/dev/ppc/drvSymbios8xx`. Note this directory has **0 static C functions** in source, so any named C function in the binary is either non-static, a libgcc helper, or a genuine gap — investigate rather than assuming.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCSym8xx.config/drvPPCSym8xx_reloc" \
  src/kernel-7/bsd/dev/ppc/drvSymbios8xx
```

Record verbatim and characterise every extra and missing entry, class-insensitively as well.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Sym8xx/source-map.json'
a = load_json(Path('tools/binrecon/out/sym8xx-ppc/published/analysis-reference-ida.json'))
m = json.load(open(MAP))
covered = set()
for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    covered |= {e['address'] for e in m[cat]}
before = len(a['functions'])
a['functions'] = [f for f in a['functions'] if f['address'] in covered]
print('analysis functions', before, '-> scoped', len(a['functions']))
load_source_map(Path(MAP), reference_analysis=a, repo_root=Path.cwd())
print('load_source_map OK')
"
```

Expected: the scoped line then `load_source_map OK`.

- [ ] **Step 9: Write `findings.md`**

`src/drivers-ppc/reconstruction/Sym8xx/findings.md`, the same nine sections as Task 2 Step 9, with `## Categories` covering `Client`, `Execute` and `Init`. Every number from observed output.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Sym8xx && \
git commit -m "drivers-ppc: measure drvPPCSym8xx against its shipped binary

Source map and bucket reconciliation for the Sym8xxController driver."
```

---

## Task 4: Synthesis — `report-scsi.md`, family comparison, acceptance

**Files:**
- Create: `src/drivers-ppc/reconstruction/report-scsi.md`

**Interfaces:**
- Consumes: `src/drivers-ppc/reconstruction/{Mesh,Sym8xx}/{findings.md,source-map.json}`, plus the committed `53c96/` and `ATA/` artifacts from the five-driver spec.
- Produces: `src/drivers-ppc/reconstruction/report-scsi.md`.

- [ ] **Step 1: Re-verify both maps load**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map

for d, key in [('Mesh','mesh-ppc'), ('Sym8xx','sym8xx-ppc')]:
    mp = f'src/drivers-ppc/reconstruction/{d}/source-map.json'
    a = load_json(Path(f'tools/binrecon/out/{key}/published/analysis-reference-ida.json'))
    m = json.load(open(mp))
    covered = set()
    for cat in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
        covered |= {e['address'] for e in m[cat]}
    before = len(a['functions'])
    a['functions'] = [f for f in a['functions'] if f['address'] in covered]
    load_source_map(Path(mp), reference_analysis=a, repo_root=Path.cwd())
    print(f'{d} OK ({before} functions -> {len(a["functions"])} scoped)')
PY
```

Expected: two `OK` lines. Acceptance item 3.

- [ ] **Step 2: Collect the summary table**

```bash
cd $REPO && $VENVPY - <<'PY'
import json
print(f"{'driver':10} {'total':>6} {'mapped':>7} {'unmap':>6} {'dup':>4} {'disp':>5} {'mapB':>8} {'unmapB':>8}")
for d, key in [('Mesh','mesh-ppc'), ('Sym8xx','sym8xx-ppc')]:
    a = json.load(open(f'tools/binrecon/out/{key}/published/analysis-reference-ida.json'))
    m = json.load(open(f'src/drivers-ppc/reconstruction/{d}/source-map.json'))
    mb = sum(e['size'] for e in m['mapped']); ub = sum(e['size'] for e in m['unmapped'])
    print(f"{d:10} {len(a['functions']):6} {len(m['mapped']):7} {len(m['unmapped']):6} "
          f"{len(m['duplicate_candidates']):4} {len(m['boundary_disputed']):5} {mb:8} {ub:8}")
PY
```

- [ ] **Step 3: Build the `IOSCSIController` family comparison**

Four drivers. Derive selector sets from each `_reloc`'s **symbol table** via `read_macho`, not from the source maps — a source map cannot carry an address-`0x0` symbol, and the network spec established that the two derivations differ.

`drvPPCATA` carries three classes, so filter it to `AtapiController`.

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import re, collections

BASE = r'C:/Users/raynorpat/Downloads/test/Drivers/ppc'
TARGETS = [
    ('Mesh',    'drvPPCMesh.config/drvPPCMesh_reloc',       {'AppleMesh_SCSI'}),
    ('Sym8xx',  'drvPPCSym8xx.config/drvPPCSym8xx_reloc',   {'Sym8xxController'}),
    ('53c96',   'drvPPC53c96.config/drvPPC53c96_reloc',     {'Apple96_SCSI'}),
    ('ATA',     'drvPPCATA.config/drvPPCATA_reloc',         {'AtapiController'}),
]
pat = re.compile(r'^[-+]\[([A-Za-z0-9_]+)(?:\([A-Za-z0-9_ ]+\))? (.+)\]$')
sel = {}
for name, path, classes in TARGETS:
    d = read_macho(f'{BASE}/{path}')
    syms = d['symbols'] if isinstance(d, dict) else d.symbols
    s = set()
    for x in syms:
        m = pat.match(x.get('name') or '')
        if m and m.group(1) in classes:
            s.add(m.group(2))
    sel[name] = s
    print(f'{name:8} {len(s)} selectors')

names = [t[0] for t in TARGETS]
counts = collections.Counter()
for n in names:
    counts.update(sel[n])

universal = sorted(k for k, v in counts.items() if v == len(names))
print(f'\nimplemented by all {len(names)}: {len(universal)}')
for k in universal: print('   ', k)

print(f'\nunion: {len(counts)}   distribution by driver-count:',
      dict(collections.Counter(counts.values())))

print('\nper-driver only:')
for n in names:
    only = sorted(k for k in sel[n] if counts[k] == 1)
    print(f'  {n}: {len(only)}')
    for k in only: print('     ', k)

print('\nmissing a selector the other three share:')
for n in names:
    others = [x for x in names if x != n]
    shared = set.intersection(*(sel[x] for x in others))
    gap = sorted(shared - sel[n])
    print(f'  {n}: {len(gap)}')
    for k in gap: print('     ', k)
PY
```

This is §4.6. **Bound the analysis to exactly these four questions.** Anything further is a recorded follow-on, not chased.

> **Expect a lopsided family, and characterise it correctly.** A dry run of this
> extraction gives `Apple96_SCSI` 90 selectors, `AppleMesh_SCSI` 70,
> `Sym8xxController` 45 and `AtapiController` **20**. `AtapiController` is a
> much thinner class than the other three — it drives ATAPI devices through the
> IDE controller rather than a full SCSI HBA — so it will appear to be "missing"
> a large number of selectors the others share.
>
> **That is Apple's own design, not a reconstruction gap**, and both sides of the
> comparison are Apple's shipped binaries, so a "missing" selector means Apple's
> `AtapiController` genuinely does not implement it. Say so explicitly. The
> network report made the equivalent call correctly for `drvPPCDec21040`'s 11;
> follow that precedent. Question 4's result for `Mesh` and `Sym8xx` is the part
> that carries reconstruction signal, because those are the two being measured.

- [ ] **Step 4: Write `report-scsi.md`**

Six parts matching spec §4:

1. `## 1. Correspondence` — Step 2's table plus the named/unnamed split. Each row reconciles.
2. `## 2. Class inventory` — binary versus source, including how each driver's categories divide its binary, and how you obtained the split.
3. `## 3. Non-Objective-C remainder` — bucket tables and `selector_check.py` output per driver. **State explicitly that buckets 1 and 2 are empty across both and why.**
4. `## 4. Findings` — each with its reference evidence, citing the per-driver `findings.md`. Include the packaging gap: both sources build into the kernel via `src/kernel-7/conf/files.ppc` under `mk_hasdrivers`, while both shipped artifacts are loadable kernel servers.
5. `## 5. Decomposition proposal` — ranked by **actionable divergence with runtime consequence**, with "a documented, evidenced cause is a result, not work" as the tie-breaker.
6. `## 6. The IOSCSIController family` — Step 3's output covering all four drivers, stating for each of the two measured here whether it is missing any selector the other three share. Cross-reference `report.md` for `Apple96_SCSI` and `AtapiController`, which are **not** re-measured.

Every number must trace to output you ran.

- [ ] **Step 5: Run the suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: **830 passed, 4 skipped**. Acceptance item 6.

- [ ] **Step 6: Confirm no generated evidence is staged**

```bash
cd $REPO && git status --porcelain | grep -c "tools/binrecon/out/" || echo "0 - clean"
```

Expected: `0 - clean`.

- [ ] **Step 7: Walk the acceptance list**

Confirm each of spec §5's eight items against observed output and record the evidence in a final `## Acceptance` section. Any item that cannot be satisfied is stated plainly with what was tried. **Do not claim an item you did not observe.**

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/report-scsi.md && \
git commit -m "drivers-ppc: report the PowerPC SCSI driver evidence base

Correspondence, bucket reconciliation and the four-driver IOSCSIController
family comparison."
```

---

## Notes for the executing agent

- **Exit 1 from `analyze` is success.** It happens four times.
- **Never commit `tools/binrecon/out/`.**
- **Never edit driver source.** Record divergences; do not fix them.
- **Every number must come from output you observed.** Reviewers on the preceding specs caught several claims that were plausible but contradicted by the binary.
- **`RECONCILES: no` is a stop condition.**
- **Use `read_macho` for anything category-related.** IDA's export strips category tags, and both drivers here are heavily category-fragmented.
- **A name match is not a logic match** — the network spec's `_mace_crc` finding turned on exactly that distinction.
