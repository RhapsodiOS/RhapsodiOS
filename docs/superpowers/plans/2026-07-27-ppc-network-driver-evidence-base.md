# PowerPC Network Driver Evidence Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure four in-tree PowerPC network driver sources against Apple's shipped Rhapsody binaries, and compare the five `IOEthernet` drivers as a family.

**Architecture:** Eight binrecon profiles drive IDA against eight reference Mach-O artifacts. Four `--scope-to-objc` source maps record the machine-checkable correspondence; everything the maps leave out is bucketed so the gap is countable. A synthesis task assembles one report, adds the cross-family `IOEthernet` comparison, and runs acceptance.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon (`tools/binrecon`), IDA Professional 9.2 headless, Mach-O 32-bit big-endian PowerPC.

**Spec:** [2026-07-27-ppc-network-driver-evidence-base-design.md](../specs/2026-07-27-ppc-network-driver-evidence-base-design.md)

**Precedent:** [2026-07-27-ppc-driver-evidence-base-design.md](../specs/2026-07-27-ppc-driver-evidence-base-design.md) and its report at `src/drivers-ppc/reconstruction/report.md`. The methodology is unchanged; read `src/drivers-ppc/reconstruction/BMac/findings.md` as the model for a per-driver document.

## Global Constraints

Every task's requirements implicitly include this section.

- **This work happens in the `ppc-network-recon` worktree.** Start every shell with:

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-network-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO
```

  `$VENVPY` points into the **main checkout** on purpose: `.venv-binrecon` is gitignored and exists only there. `PYTHONPATH=tools/binrecon` stays relative and resolves against `$REPO`.

- **Always set** `PYTHONPATH=tools/binrecon` on binrecon invocations.
- **Reference artifacts** live at `C:/Users/raynorpat/Downloads/test/Drivers/ppc/` and stay outside Git. Never copy them into the repo.
- **`binrecon analyze` exits 1 for every profile in this plan. Exit 1 is SUCCESS.** These are reference-only profiles with no rebuilt artifact, so `normalized-functions` acceptance is unsatisfiable by construction. The pass condition is `"complete": true` plus a published `published/analysis-reference-ida.json`. Do not try to make it exit 0, do not invent a rebuilt artifact, do not change the acceptance level.
- **Never commit anything under `tools/binrecon/out/`.** Gitignored generated evidence.
- **Do not modify any driver source, any header, or `src/kernel-7/conf/files.ppc`.** This plan measures. If a source looks wrong, record it as a finding.
- **Do not modify binrecon tooling** except under spec §3.5, which covers only a defect that blocks publication or corrupts the measurement. None is anticipated — see the pre-checks below.
- **`--scope-to-objc` is mandatory** on every `source-map` invocation. Without it the run fails: IDA's PowerPC glue stubs carry no name and `source-map-v1` requires one.
- **Map validation must scope the analysis across all four map categories** — `mapped`, `unmapped`, `duplicate_candidates`, `boundary_disputed`. Omitting any fails validation with `unexpected`.
- **Commit messages:** subsystem prefix (`binrecon: `, `drivers-ppc: `, `docs: `), one to two lines, no metadata, trailers, or emoji.
- **Harness quirk:** the Write tool refuses to create files literally named `findings.md` or `report.md`. Write to another name and `cp` it into place with Bash.
- **`SCRATCH`** is `C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad`.

### Driver parameter table

| KEY | DIR | Bundle artifact | `_reloc` artifact | `--source-dir` |
| --- | --- | --- | --- | --- |
| `gnic` | `GNic` | `drvPPCGNic.config/drvPPCGNic` | `drvPPCGNic.config/drvPPCGNic_reloc` | `src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj` |
| `gem` | `Gem` | `drvPPCGem.config/drvPPCGem` | `drvPPCGem.config/drvPPCGem_reloc` | `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj` |
| `mace` | `Mace` | `drvPPCMace.config/drvPPCMace` | `drvPPCMace.config/drvPPCMace_reloc` | `src/kernel-7/bsd/dev/ppc/drvMaceEnet` |
| `dec21040` | `Dec21040` | `drvPPCDec21040.config/drvPPCDec21040` | `drvPPCDec21040.config/drvPPCDec21040_reloc` | `src/kernel-7/bsd/dev/ppc/drvDECchip21040` |

> **`dec21040`'s source is the kernel PowerPC directory, not the i386 one.**
> `src/drivers-i386/network/drvDECchip21040` also defines `DECchip2104x` and a
> naive search finds it first. Using it would compare a PowerPC binary against
> i386 sources. Use `src/kernel-7/bsd/dev/ppc/drvDECchip21040`, which defines
> all three of the binary's classes.

### Expected artifact sizes

`validate` prints size and SHA-256 for each. Sizes must match; record the hashes it prints into each `findings.md`.

| Artifact | Size |
| --- | --- |
| `drvPPCGNic` / `drvPPCGNic_reloc` | 8496 / 48432 |
| `drvPPCGem` / `drvPPCGem_reloc` | 8492 / 58072 |
| `drvPPCMace` / `drvPPCMace_reloc` | 8496 / 60744 |
| `drvPPCDec21040` / `drvPPCDec21040_reloc` | 8504 / 51872 |

### Established by the previous spec — apply, do not re-derive

- **Buckets 1 and 2 will be 0 for all four.** `_reloc` files are statically linked kernel servers, not `MH_EXECUTE` helpers: no crt/dyld routines, no `__picsymbol_stub` section. State it with the reason; do not omit the buckets.
- **Bucket 5 always prints 0 from the script.** Populate it by hand from bucket 6, citing file and line for each confirmed match.
- **`read_macho` preserves Objective-C category tags; IDA's exported analysis strips them.** If you need to know which category a shipped method belongs to, ask `read_macho`:
  ```python
  from binrecon.macho import read_macho
  d = read_macho(r'<path to _reloc>')
  syms = d['symbols'] if isinstance(d, dict) else d.symbols
  ```
  This is what settled the previous spec's `IdeController` question. It matters most for `dec21040`, which has three classes.
- **A named function with no source site is a real gap.** Compiler-runtime helpers such as `__udivdi3` and `__divdi3` are libgcc, not driver source; classify them as such rather than as open questions.
- **Pre-checks already run, both clean across all four source directories:** zero methods use the semicolon-before-body idiom, and zero signature lines carry a `//` comment. Neither known scanner limitation applies here, so no tool work is anticipated.

### Method counts in source, for orientation only

Re-measure rather than trusting these: `GNicEnet` 46 methods / 1 static C, `GemEnet` 47 / 2, `MaceEnet` 46 / 3, `DECchip2104x` family 47 / 4.

---

## File Structure

**Created — committed:**

- `tools/binrecon/profiles/{gnic,gem,mace,dec21040}-ppc.json` and `-bundle-ppc.json` — eight profiles.
- `src/drivers-ppc/reconstruction/{GNic,Gem,Mace,Dec21040}/source-map.json` — the durable measurement.
- `src/drivers-ppc/reconstruction/{GNic,Gem,Mace,Dec21040}/findings.md` — per-driver evidence.
- `src/drivers-ppc/reconstruction/report-network.md` — the synthesis.

**Modified — committed:**

- `tools/binrecon/tests/test_profile.py` — `test_ppc_profile_inventory` asserts the exact PowerPC profile list. It names 17 today and must name 25.

**Created — not committed:** `tools/binrecon/out/<KEY>-ppc/` and `<KEY>-bundle-ppc/`.

**Modified:** no driver source, no header, no build wiring.

---

## Task 1: Eight profiles and the inventory test

**Files:**
- Create: `tools/binrecon/profiles/{gnic,gem,mace,dec21040}-ppc.json`
- Create: `tools/binrecon/profiles/{gnic,gem,mace,dec21040}-bundle-ppc.json`
- Modify: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: eight profiles at `tools/binrecon/profiles/<KEY>-ppc.json` and `<KEY>-bundle-ppc.json`, `output_dir` of `../out/<KEY>-ppc` and `../out/<KEY>-bundle-ppc`. Tasks 2–5 consume these.

- [ ] **Step 1: Confirm the worktree and venv are wired up**

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-network-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO && git branch --show-current && $VENVPY --version && \
  PYTHONPATH=tools/binrecon $VENVPY -m binrecon --help | head -3
```

Expected: `ppc-network-recon`, `Python 3.13.9`, and the binrecon usage banner.

- [ ] **Step 2: Generate the eight profiles**

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

DRIVERS = {'gnic': 'drvPPCGNic', 'gem': 'drvPPCGem',
           'mace': 'drvPPCMace', 'dec21040': 'drvPPCDec21040'}

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

Expected: eight `wrote tools/binrecon/profiles/...` lines.

- [ ] **Step 3: Validate all eight against the real artifacts**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && while read -r slug rel; do
  BINRECON_REFERENCE="$REF/$rel" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon validate --profile "tools/binrecon/profiles/$slug.json"
done <<'EOF'
gnic-ppc drvPPCGNic.config/drvPPCGNic_reloc
gnic-bundle-ppc drvPPCGNic.config/drvPPCGNic
gem-ppc drvPPCGem.config/drvPPCGem_reloc
gem-bundle-ppc drvPPCGem.config/drvPPCGem
mace-ppc drvPPCMace.config/drvPPCMace_reloc
mace-bundle-ppc drvPPCMace.config/drvPPCMace
dec21040-ppc drvPPCDec21040.config/drvPPCDec21040_reloc
dec21040-bundle-ppc drvPPCDec21040.config/drvPPCDec21040
EOF
```

Expected: eight `reference ... size=... sha256=...` lines. **Check every size against the Global Constraints table.** A mismatch is a stop condition — report BLOCKED. Save this output; Tasks 2–5 need the hashes.

- [ ] **Step 4: Update the profile inventory test**

`tools/binrecon/tests/test_profile.py::test_ppc_profile_inventory` asserts the exact sorted list of `*-ppc.json` profiles. It names 17; it must name 25. Regenerate the list:

```bash
cd $REPO && $VENVPY -c "
from pathlib import Path
names = sorted(p.name for p in Path('tools/binrecon/profiles').glob('*-ppc.json'))
print(len(names))
for i in range(0, len(names), 2):
    print('        ' + ' '.join(f'\"{n}\",' for n in names[i:i+2]))
"
```

Replace the list in the assertion with that output. Do **not** weaken the test into a subset or count check — asserting the exact inventory is the point, and it failing on a new profile is correct behaviour.

- [ ] **Step 5: Run the full suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: **826 passed, 4 skipped**. The baseline before this task is 818; the +8 is correct and expected, because `test_ppc_profiles_are_reference_only_ida_runs` is parametrized over the `*-ppc.json` glob, so each new profile adds a passing test instance. `test_ppc_profile_inventory` now covers 25 profiles.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add tools/binrecon/profiles/*-ppc.json tools/binrecon/tests/test_profile.py && \
git commit -m "binrecon: add eight PowerPC profiles for the network drivers

Covers the bundle stub and kernel-server _reloc of drvPPCGNic, drvPPCGem,
drvPPCMace and drvPPCDec21040."
```

---

## Task 2: GNic — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/GNic/source-map.json`
- Create: `src/drivers-ppc/reconstruction/GNic/findings.md`

**Interfaces:**
- Consumes: `gnic-ppc.json`, `gnic-bundle-ppc.json` from Task 1; `$SCRATCH/bucket_functions.py`, invoked as `$VENVPY <script> <analysis.json> <source-map.json>`, printing a bucket table and `RECONCILES: yes|no`.
- Produces: `src/drivers-ppc/reconstruction/GNic/{source-map.json,findings.md}` for Task 6.

Source: `src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj` — class `GNicEnet`, 46 method definitions, 1 static C function.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "gnic-ppc drvPPCGNic.config/drvPPCGNic_reloc" "gnic-bundle-ppc drvPPCGNic.config/drvPPCGNic"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

Expected: two `normalized-functions=FAIL` lines, each with `exit=1`. **Exit 1 is success.**

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['gnic-ppc','gnic-bundle-ppc']:
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
for pair in "gnic-ppc drvPPCGNic.config/drvPPCGNic_reloc" "gnic-bundle-ppc drvPPCGNic.config/drvPPCGNic"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both. Record any symbol/function-start mismatch as a `boundary_disputed` candidate; it is not a failure.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/GNic && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/gnic-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGNic.config/drvPPCGNic_reloc" \
  --source-dir src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/GNic/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/GNic/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

There are no pre-measured expected numbers. Whatever the tools report is the finding. `duplicate_candidates` must be 0 **or** every entry enumerated with its cause in `findings.md`.

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/gnic-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/GNic/source-map.json
```

Expected: `RECONCILES: yes`, with buckets 1 and 2 at 0. `RECONCILES: no` is a **stop condition** — report BLOCKED with the output.

Resolve every `6-fn-no-source-site` entry by grepping `src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj` for the symbol. Confirmed definitions move to bucket 5 with file and line in `findings.md`. A libgcc helper (`__udivdi3`, `__divdi3`) is classified as compiler runtime, not an open question. An entry you cannot classify is recorded as open **with what you tried**.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGNic.config/drvPPCGNic_reloc" \
  src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj
```

Record verbatim. Missing/extra selectors or a nonzero exit are findings, not failures. **Characterise every "extra" entry** — the previous spec's review caught extras mislabelled as naming artifacts when most were genuinely absent from the binary. Check class-insensitively too: a selector may exist in the binary on a different class.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/GNic/source-map.json'
a = load_json(Path('tools/binrecon/out/gnic-ppc/published/analysis-reference-ida.json'))
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

Expected: an `analysis functions N -> scoped M` line then `load_source_map OK`. The analysis is scoped first because the map does not claim the unnamed jump islands and `load_source_map` enforces an exact partition.

- [ ] **Step 9: Write `findings.md`**

`src/drivers-ppc/reconstruction/GNic/findings.md`, following `src/drivers-ppc/reconstruction/BMac/findings.md` for structure and tone. Sections:

1. `## Artifacts` — both artifacts with size and the SHA-256 `validate` printed.
2. `## Correspondence` — mapped, unmapped, duplicate_candidates, boundary_disputed; total functions; named vs unnamed.
3. `## Map validation` — Step 8 output, and one sentence on why the analysis is scoped first.
4. `## Buckets` — the Step 6 table, including the explicit statement that buckets 1 and 2 are empty **because this is a statically linked kernel server with no `__picsymbol_stub` section and no crt/dyld routines**.
5. `## Unmapped detail` — each unmapped entry with size, classified as build-generated or a real gap.
6. `## Invariant check` — Step 3 output; violations must be 0.
7. `## Selector check` — Step 7 output verbatim, plus your characterisation of every extra and missing entry.
8. `## Bundle stub` — what the bundle analysis contains, from observed output.

**Every number must come from output you observed.** Do not assert a cause you did not measure; if you cannot identify why something is unmapped, say so and say what you tried.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/GNic && \
git commit -m "drivers-ppc: measure drvPPCGNic against its shipped binary

Source map and bucket reconciliation for the GNicEnet driver."
```

---

## Task 3: Gem — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/Gem/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Gem/findings.md`

**Interfaces:**
- Consumes: `gem-ppc.json`, `gem-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py` (unchanged, do not modify).
- Produces: `src/drivers-ppc/reconstruction/Gem/{source-map.json,findings.md}` for Task 6.

Source: `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj` — class `GemEnet`, 47 method definitions, 2 static C functions.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "gem-ppc drvPPCGem.config/drvPPCGem_reloc" "gem-bundle-ppc drvPPCGem.config/drvPPCGem"; do
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
for k in ['gem-ppc','gem-bundle-ppc']:
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
for pair in "gem-ppc drvPPCGem.config/drvPPCGem_reloc" "gem-bundle-ppc drvPPCGem.config/drvPPCGem"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Gem && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/gem-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGem.config/drvPPCGem_reloc" \
  --source-dir src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Gem/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/Gem/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

`duplicate_candidates` must be 0 or every entry enumerated with its cause.

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/gem-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Gem/source-map.json
```

Expected: `RECONCILES: yes`, buckets 1 and 2 at 0. `RECONCILES: no` is a stop condition.

Resolve every bucket-6 entry against `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj`, moving confirmed matches to bucket 5 with file and line.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGem.config/drvPPCGem_reloc" \
  src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj
```

Record verbatim and characterise every extra and missing entry, class-insensitively as well.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Gem/source-map.json'
a = load_json(Path('tools/binrecon/out/gem-ppc/published/analysis-reference-ida.json'))
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

`src/drivers-ppc/reconstruction/Gem/findings.md`, the same eight sections as Task 2 Step 9: Artifacts, Correspondence, Map validation, Buckets, Unmapped detail, Invariant check, Selector check, Bundle stub. Every number from observed output.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Gem && \
git commit -m "drivers-ppc: measure drvPPCGem against its shipped binary

Source map and bucket reconciliation for the GemEnet driver."
```

---

## Task 4: Mace — analyses, source map, buckets

**Files:**
- Create: `src/drivers-ppc/reconstruction/Mace/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Mace/findings.md`

**Interfaces:**
- Consumes: `mace-ppc.json`, `mace-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py`.
- Produces: `src/drivers-ppc/reconstruction/Mace/{source-map.json,findings.md}` for Task 6.

Source: `src/kernel-7/bsd/dev/ppc/drvMaceEnet` — class `MaceEnet`, 46 method definitions, 3 static C functions. This driver builds into the kernel via `conf/files.ppc`, unlike GNic and Gem which are already loadable-driver projects; that difference is part of the packaging finding.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "mace-ppc drvPPCMace.config/drvPPCMace_reloc" "mace-bundle-ppc drvPPCMace.config/drvPPCMace"; do
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
for k in ['mace-ppc','mace-bundle-ppc']:
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
for pair in "mace-ppc drvPPCMace.config/drvPPCMace_reloc" "mace-bundle-ppc drvPPCMace.config/drvPPCMace"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Mace && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/mace-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCMace.config/drvPPCMace_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvMaceEnet \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Mace/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/Mace/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/mace-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Mace/source-map.json
```

Expected: `RECONCILES: yes`, buckets 1 and 2 at 0.

Resolve every bucket-6 entry against `src/kernel-7/bsd/dev/ppc/drvMaceEnet`, moving confirmed matches to bucket 5 with file and line.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCMace.config/drvPPCMace_reloc" \
  src/kernel-7/bsd/dev/ppc/drvMaceEnet
```

Record verbatim and characterise every extra and missing entry.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Mace/source-map.json'
a = load_json(Path('tools/binrecon/out/mace-ppc/published/analysis-reference-ida.json'))
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

`src/drivers-ppc/reconstruction/Mace/findings.md`, the same eight sections as Task 2 Step 9. Add a note in `## Artifacts` that this driver's source builds into the kernel via `src/kernel-7/conf/files.ppc` under `mk_hasdrivers`, while the shipped artifact is a loadable kernel server.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Mace && \
git commit -m "drivers-ppc: measure drvPPCMace against its shipped binary

Source map and bucket reconciliation for the MaceEnet driver."
```

---

## Task 5: Dec21040 — analyses, source map, buckets, three classes

**Files:**
- Create: `src/drivers-ppc/reconstruction/Dec21040/source-map.json`
- Create: `src/drivers-ppc/reconstruction/Dec21040/findings.md`

**Interfaces:**
- Consumes: `dec21040-ppc.json`, `dec21040-bundle-ppc.json` (Task 1); `$SCRATCH/bucket_functions.py`.
- Produces: `src/drivers-ppc/reconstruction/Dec21040/{source-map.json,findings.md}` for Task 6.

Source: `src/kernel-7/bsd/dev/ppc/drvDECchip21040` — **three** classes, `DECchip21040`, `DECchip21041` and `DECchip2104x` (plus a `DECchip2104x (Private)` category), 47 method definitions, 4 static C functions.

> **Use the kernel PowerPC directory, not `src/drivers-i386/network/drvDECchip21040`.** The i386 tree also defines `DECchip2104x` and a naive search finds it first; using it would compare a PowerPC binary against i386 source. Do not touch the i386 tree.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "dec21040-ppc drvPPCDec21040.config/drvPPCDec21040_reloc" "dec21040-bundle-ppc drvPPCDec21040.config/drvPPCDec21040"; do
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
for k in ['dec21040-ppc','dec21040-bundle-ppc']:
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
for pair in "dec21040-ppc drvPPCDec21040.config/drvPPCDec21040_reloc" "dec21040-bundle-ppc drvPPCDec21040.config/drvPPCDec21040"; do
  set -- $pair
  echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Dec21040 && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/dec21040-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCDec21040.config/drvPPCDec21040_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvDECchip21040 \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Dec21040/source-map.json
```

Expected: no output, exit 0.

- [ ] **Step 5: Report the map counts and the per-class split**

```bash
cd $REPO && $VENVPY -c "
import json, re, collections
d=json.load(open('src/drivers-ppc/reconstruction/Dec21040/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
c=collections.Counter()
for e in d['mapped']:
    m=re.match(r'^[-+]\[([A-Za-z0-9_]+)', e['reference_names'][0])
    if m: c[m.group(1)] += 1
print('mapped per class:', dict(c))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

The per-class split answers §4.2: how the three classes divide the binary.

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad" && \
$VENVPY "$SCRATCH/bucket_functions.py" \
  tools/binrecon/out/dec21040-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Dec21040/source-map.json
```

Expected: `RECONCILES: yes`, buckets 1 and 2 at 0.

Resolve every bucket-6 entry against `src/kernel-7/bsd/dev/ppc/drvDECchip21040`. With three classes and a category, a name may appear on more than one class — when a bucket-6 entry is ambiguous, use `read_macho` to read the category tag from the binary (IDA's export strips it):

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
d = read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCDec21040.config/drvPPCDec21040_reloc')
syms = d['symbols'] if isinstance(d, dict) else d.symbols
for s in syms:
    n = s.get('name') or ''
    if n.startswith(('-[', '+[')): print(f\"{s.get('address'):>7} {n}\")
" | head -60
```

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCDec21040.config/drvPPCDec21040_reloc" \
  src/kernel-7/bsd/dev/ppc/drvDECchip21040
```

Record verbatim. With three classes, check every extra and missing entry **class-insensitively as well** — a selector may exist in the binary on a sibling class, which is a placement difference rather than a missing implementation. The previous spec found exactly that pattern in `drvPPCATA`.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Dec21040/source-map.json'
a = load_json(Path('tools/binrecon/out/dec21040-ppc/published/analysis-reference-ida.json'))
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

`src/drivers-ppc/reconstruction/Dec21040/findings.md`, the eight sections from Task 2 Step 9, plus:

9. `## Three classes` — the Step 5 per-class split, which selectors belong to which class, and whether any selector appears on more than one. Note that this driver's source builds into the kernel via `conf/files.ppc`.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Dec21040 && \
git commit -m "drivers-ppc: measure drvPPCDec21040 against its shipped binary

Maps all three DECchip classes against the kernel PowerPC source."
```

---

## Task 6: Synthesis — `report-network.md`, family comparison, acceptance

**Files:**
- Create: `src/drivers-ppc/reconstruction/report-network.md`

**Interfaces:**
- Consumes: all four `src/drivers-ppc/reconstruction/{GNic,Gem,Mace,Dec21040}/{findings.md,source-map.json}`, plus the previously committed `BMac/findings.md` and `BMac/source-map.json`.
- Produces: `src/drivers-ppc/reconstruction/report-network.md`, the spec's deliverable.

- [ ] **Step 1: Re-verify all four maps load**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map

PAIRS = [('GNic','gnic-ppc'), ('Gem','gem-ppc'),
         ('Mace','mace-ppc'), ('Dec21040','dec21040-ppc')]
for d, key in PAIRS:
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

Expected: four `OK` lines. This is acceptance item 3.

- [ ] **Step 2: Collect the summary table**

```bash
cd $REPO && $VENVPY - <<'PY'
import json

PAIRS = [('GNic','gnic-ppc'), ('Gem','gem-ppc'),
         ('Mace','mace-ppc'), ('Dec21040','dec21040-ppc')]
print(f"{'driver':10} {'total':>6} {'mapped':>7} {'unmap':>6} {'dup':>4} {'disp':>5} {'mapB':>8} {'unmapB':>8}")
for d, key in PAIRS:
    a = json.load(open(f'tools/binrecon/out/{key}/published/analysis-reference-ida.json'))
    m = json.load(open(f'src/drivers-ppc/reconstruction/{d}/source-map.json'))
    mb = sum(e['size'] for e in m['mapped'])
    ub = sum(e['size'] for e in m['unmapped'])
    print(f"{d:10} {len(a['functions']):6} {len(m['mapped']):7} {len(m['unmapped']):6} "
          f"{len(m['duplicate_candidates']):4} {len(m['boundary_disputed']):5} {mb:8} {ub:8}")
PY
```

Paste into `report-network.md` §1.

- [ ] **Step 3: Build the `IOEthernet` family comparison**

Five drivers: the four measured here plus `BMac` from the previous spec. Derive the selector sets from the five committed source maps.

```bash
cd $REPO && $VENVPY - <<'PY'
import json, re, collections

DRIVERS = ['GNic', 'Gem', 'Mace', 'Dec21040', 'BMac']
sel = {}
for d in DRIVERS:
    m = json.load(open(f'src/drivers-ppc/reconstruction/{d}/source-map.json'))
    s = set()
    for cat in ('mapped', 'unmapped'):
        for e in m[cat]:
            for n in e['reference_names']:
                mt = re.match(r'^[-+]\[[A-Za-z0-9_]+(?:\([A-Za-z0-9_]+\))? (.+)\]$', n)
                if mt:
                    s.add(mt.group(1))
    sel[d] = s
    print(f'{d:10} {len(s)} selectors')

counts = collections.Counter()
for d in DRIVERS:
    counts.update(sel[d])

universal = sorted(k for k, v in counts.items() if v == len(DRIVERS))
print(f'\nimplemented by all {len(DRIVERS)}: {len(universal)}')
for k in universal: print('   ', k)

print('\nper-driver only:')
for d in DRIVERS:
    only = sorted(k for k in sel[d] if counts[k] == 1)
    print(f'  {d}: {len(only)}')
    for k in only: print('     ', k)

print('\nmissing a selector the other four share:')
for d in DRIVERS:
    others = [x for x in DRIVERS if x != d]
    shared_by_others = set.intersection(*(sel[x] for x in others))
    gap = sorted(shared_by_others - sel[d])
    print(f'  {d}: {len(gap)}')
    for k in gap: print('     ', k)
PY
```

This output is §4.6. **Bound the analysis to exactly these four questions** — spec §5.1 names family-comparison sprawl as the likeliest overrun. Anything further is a recorded follow-on question, not chased.

- [ ] **Step 4: Write `report-network.md`**

Six parts matching spec §4:

1. `## 1. Correspondence` — Step 2's table plus the named/unnamed split per driver. Each row reconciles: mapped + unmapped + buckets = total.
2. `## 2. Class inventory` — binary versus source per driver, including how `Dec21040`'s three classes divide its binary.
3. `## 3. Non-Objective-C remainder` — the bucket tables from all four `findings.md`, and `selector_check.py` output per driver. **State explicitly that buckets 1 and 2 are empty across all four, because these are statically linked kernel servers with no crt/dyld routines and no `__picsymbol_stub` section.**
4. `## 4. Findings` — each with its reference evidence, citing the per-driver `findings.md`. Include the packaging gap: `drvMaceEnet` and `drvDECchip21040` build into the kernel via `src/kernel-7/conf/files.ppc` under `mk_hasdrivers`, while `drvPPCGNic` and `drvPPCGem` are already loadable-driver projects under `src/drivers-ppc` — yet all four shipped artifacts are loadable kernel servers.
5. `## 5. Decomposition proposal` — the per-driver specs to follow, ranked by **actionable divergence with runtime consequence**, with "a documented, evidenced cause is a result, not work" as the tie-breaker. This is the criterion the previous report settled on.
6. `## 6. The IOEthernet family` — Step 3's output, covering all five drivers and stating for each of the four measured here whether it is missing any selector the other four share. Cross-reference `report.md` for `drvPPCBMac`, which is not re-measured.

Every number must trace to output you ran.

- [ ] **Step 5: Run the binrecon test suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: green, **826 passed, 4 skipped**, with `test_ppc_profile_inventory` covering 25 profiles. (818 was the pre-Task-1 baseline; the eight new profiles each add a parametrized test instance.) Acceptance item 6.

- [ ] **Step 6: Confirm no generated evidence is staged**

```bash
cd $REPO && git status --porcelain | grep -c "tools/binrecon/out/" || echo "0 - clean"
```

Expected: `0 - clean`.

- [ ] **Step 7: Walk the acceptance list**

Confirm each of spec §5's eight items against observed output and record the evidence in a final `## Acceptance` section of `report-network.md`. Any item that cannot be satisfied is stated plainly with what was tried. **Do not claim an item you did not observe.**

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/report-network.md && \
git commit -m "drivers-ppc: report the PowerPC network driver evidence base

Correspondence, bucket reconciliation and the five-driver IOEthernet family
comparison."
```

---

## Notes for the executing agent

- **Exit 1 from `analyze` is success.** It happens eight times. Do not try to make it exit 0.
- **Never commit `tools/binrecon/out/`.**
- **Never edit driver source.** If a divergence looks trivially fixable, record it.
- **Every number in a `findings.md` or the report must come from output you observed.** Reviewers on the previous spec caught several claims that were plausible but contradicted by the binary — check before you write.
- **`RECONCILES: no` is a stop condition.**
- **Characterise "extra" selectors carefully.** The previous spec's review found extras mislabelled as naming artifacts when most were genuinely absent, and two more that existed on a different class. Check class-insensitively before concluding.
