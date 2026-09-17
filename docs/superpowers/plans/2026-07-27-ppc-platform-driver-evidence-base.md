# PowerPC Platform Driver Evidence Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure five PowerPC platform drivers against Apple's shipped Rhapsody binaries, and test whether `drvPPCBurgundy`'s underscore selector convention is project-wide.

**Architecture:** Ten binrecon profiles drive IDA against ten reference Mach-O artifacts. Five `--scope-to-objc` source maps record the machine-checkable correspondence; everything the maps leave out is bucketed so the gap is countable. A synthesis task assembles one report, adds two cross-driver pairings, and runs acceptance.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon (`tools/binrecon`), IDA Professional 9.2 headless, Mach-O 32-bit big-endian PowerPC.

**Spec:** [2026-07-27-ppc-platform-driver-evidence-base-design.md](../specs/2026-07-27-ppc-platform-driver-evidence-base-design.md)

**Precedent:** `src/drivers-ppc/reconstruction/report-scsi.md` and its per-driver documents. The methodology is unchanged; read `src/drivers-ppc/reconstruction/Sym8xx/findings.md` as the model for a per-driver document.

## Global Constraints

Every task's requirements implicitly include this section.

- **This work happens in the `ppc-platform-recon` worktree.** Start every shell with:

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-platform-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO
```

  `$VENVPY` points into the **main checkout** on purpose: `.venv-binrecon` is gitignored and exists only there.

- **Always set** `PYTHONPATH=tools/binrecon` on binrecon invocations.
- **Reference artifacts** live at `C:/Users/raynorpat/Downloads/test/Drivers/ppc/` and stay outside Git.
- **`binrecon analyze` exits 1 for every profile in this plan. Exit 1 is SUCCESS.** Reference-only profiles have no rebuilt artifact, so `normalized-functions` acceptance is unsatisfiable by construction. Pass condition: `"complete": true` plus a published `published/analysis-reference-ida.json`.
- **Never commit anything under `tools/binrecon/out/`.**
- **Do not modify any driver source, any header, or `src/kernel-7/conf/files.ppc`.** This plan measures.
- **Do not modify binrecon tooling** except under spec §3.5. None is anticipated — pre-checks are clean for all five source directories this plan touches.
- **`--scope-to-objc` is mandatory** on every `source-map` invocation.
- **Map validation must scope the analysis across all four map categories** — `mapped`, `unmapped`, `duplicate_candidates`, `boundary_disputed`.
- **The bucket script is now committed** at `tools/binrecon/bucket_functions.py`. Invoke it as `$VENVPY tools/binrecon/bucket_functions.py <analysis.json> <source-map.json>`. **Do not modify it.**
- **Commit messages:** subsystem prefix (`binrecon: `, `drivers-ppc: `, `docs: `), one to two lines, no metadata, trailers, or emoji.
- **Harness quirk:** the Write tool refuses files literally named `findings.md` or `report-platform.md`. Write to another name and `cp` it into place with Bash.

### Driver parameter table

| KEY | DIR | Bundle artifact | `_reloc` artifact | `--source-dir` |
| --- | --- | --- | --- | --- |
| `ohare` | `OHare` | `drvPPCOHare.config/drvPPCOHare` | `drvPPCOHare.config/drvPPCOHare_reloc` | `src/kernel-7/bsd/dev/ppc/drvOHare` |
| `pmu` | `PMU` | `drvPPCPMU.config/drvPPCPMU` | `drvPPCPMU.config/drvPPCPMU_reloc` | `src/kernel-7/bsd/dev/ppc/drvPMU` |
| `awacs` | `Awacs` | `PPCAwacs.config/PPCAwacs` | `PPCAwacs.config/PPCAwacs_reloc` | `src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj` |
| `applepcibus` | `ApplePCIBus` | `IOApplePCIBus.config/IOApplePCIBus` | `IOApplePCIBus.config/IOApplePCIBus_reloc` | `src/driverkit-3/libDriver/ppc` |
| `iodisplay` | `IODisplay` | `IODisplay.config/IODisplay` | `IODisplay.config/IODisplay_reloc` | `src/driverkit-3/libDriver/ppc` |

### Expected artifact sizes

| Artifact | Size |
| --- | --- |
| `drvPPCOHare` / `drvPPCOHare_reloc` | 8496 / 16568 |
| `drvPPCPMU` / `drvPPCPMU_reloc` | 8492 / 41488 |
| `PPCAwacs` / `PPCAwacs_reloc` | 8492 / 38540 |
| `IOApplePCIBus` / `IOApplePCIBus_reloc` | 8500 / 26668 |
| `IODisplay` / `IODisplay_reloc` | 8492 / 32640 |

### Established by the preceding specs — apply, do not re-derive

- **Buckets 1 and 2 will be 0 for all five.** Statically linked kernel servers, not `MH_EXECUTE` helpers. State it with the reason.
- **Bucket 5 always prints 0 from the script.** Populate by hand from bucket 6, citing file and line.
- **`read_macho` preserves Objective-C category tags; IDA's export strips them.** Use it for anything class- or category-related:
  ```python
  from binrecon.macho import read_macho
  d = read_macho(r'<path to _reloc>')
  syms = d['symbols'] if isinstance(d, dict) else d.symbols
  ```
- **A name match is not a logic match.** The network spec found a method with a correct source site but a different algorithm, producing different results on 5 of 5 vectors. Confirm logic for small self-contained bucket-6 entries.
- **Characterise every "extra" and "missing" selector, class-insensitively as well.**
- Libgcc helpers (`__udivdi3`, `__divdi3`) are compiler runtime, not driver source.
- Every driver measured so far reports exactly one address-`0x0` symbol — a `boundary_disputed` candidate, not a gap.
- **The plan's source method counts are approximate.** Every prior task found more than stated. Re-measure and record the measured number.

### `IOApplePCIBus` and `IODisplay` share one source directory

Both pass `src/driverkit-3/libDriver/ppc`, which also serves the deferred `IONDRVSupport`. Each binary maps only its own classes. **Expect a large "extra" set in each `selector_check.py` run** — those are the sibling drivers' methods present in the directory but absent from that binary. They are **not gaps**, and `findings.md` must attribute them to sibling classes explicitly.

---

## File Structure

**Created — committed:**

- `tools/binrecon/profiles/{ohare,pmu,awacs,applepcibus,iodisplay}-ppc.json` and `-bundle-ppc.json`.
- `src/drivers-ppc/reconstruction/{OHare,PMU,Awacs,ApplePCIBus,IODisplay}/source-map.json`.
- `src/drivers-ppc/reconstruction/{OHare,PMU,Awacs,ApplePCIBus,IODisplay}/findings.md`.
- `src/drivers-ppc/reconstruction/report-platform.md`.

**Modified — committed:** `tools/binrecon/tests/test_profile.py` — the inventory names 29 today and must name 39.

**Modified:** no driver source, no header, no build wiring.

---

## Task 1: Ten profiles and the inventory test

**Files:**
- Create: `tools/binrecon/profiles/{ohare,pmu,awacs,applepcibus,iodisplay}-ppc.json` and `-bundle-ppc.json`
- Modify: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Produces: ten profiles with `output_dir` of `../out/<KEY>-ppc` and `../out/<KEY>-bundle-ppc`. Tasks 2–6 consume these.

- [ ] **Step 1: Confirm the worktree and venv**

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-platform-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
cd $REPO && git branch --show-current && $VENVPY --version && \
  PYTHONPATH=tools/binrecon $VENVPY -m binrecon --help | head -3
```

Expected: `ppc-platform-recon`, `Python 3.13.9`, the binrecon usage banner.

- [ ] **Step 2: Generate the ten profiles**

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

DRIVERS = {'ohare': 'drvPPCOHare', 'pmu': 'drvPPCPMU', 'awacs': 'PPCAwacs',
           'applepcibus': 'IOApplePCIBus', 'iodisplay': 'IODisplay'}

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

Expected: ten `wrote tools/binrecon/profiles/...` lines.

- [ ] **Step 3: Validate all ten**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && while read -r slug rel; do
  BINRECON_REFERENCE="$REF/$rel" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon validate --profile "tools/binrecon/profiles/$slug.json"
done <<'EOF'
ohare-ppc drvPPCOHare.config/drvPPCOHare_reloc
ohare-bundle-ppc drvPPCOHare.config/drvPPCOHare
pmu-ppc drvPPCPMU.config/drvPPCPMU_reloc
pmu-bundle-ppc drvPPCPMU.config/drvPPCPMU
awacs-ppc PPCAwacs.config/PPCAwacs_reloc
awacs-bundle-ppc PPCAwacs.config/PPCAwacs
applepcibus-ppc IOApplePCIBus.config/IOApplePCIBus_reloc
applepcibus-bundle-ppc IOApplePCIBus.config/IOApplePCIBus
iodisplay-ppc IODisplay.config/IODisplay_reloc
iodisplay-bundle-ppc IODisplay.config/IODisplay
EOF
```

Expected: ten `reference ... size=... sha256=...` lines. **Check every size against the table above.** A mismatch is a stop condition. **Record all ten hashes in your report** — Tasks 2–6 need them and there is no other record.

- [ ] **Step 4: Update the inventory test**

`test_ppc_profile_inventory` asserts the exact sorted list of `*-ppc.json`. It names 29; it must name 39. Regenerate:

```bash
cd $REPO && $VENVPY -c "
from pathlib import Path
names = sorted(p.name for p in Path('tools/binrecon/profiles').glob('*-ppc.json'))
print(len(names))
for i in range(0, len(names), 2):
    print('        ' + ' '.join(f'\"{n}\",' for n in names[i:i+2]))
"
```

Replace the assertion's list. **Do not weaken the test** into a subset, count or glob check.

- [ ] **Step 5: Run the suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: **845 passed, 4 skipped**. The baseline is 835; the +10 is correct, because `test_ppc_profiles_are_reference_only_ida_runs` is parametrized over the profile glob.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add tools/binrecon/profiles/*-ppc.json tools/binrecon/tests/test_profile.py && \
git commit -m "binrecon: add ten PowerPC profiles for the platform drivers

Covers the bundle stub and kernel-server _reloc of drvPPCOHare, drvPPCPMU,
PPCAwacs, IOApplePCIBus and IODisplay."
```

---

## Task 2: OHare

**Files:** Create `src/drivers-ppc/reconstruction/OHare/{source-map.json,findings.md}`

**Interfaces:** Consumes `ohare-ppc.json`, `ohare-bundle-ppc.json` (Task 1) and `tools/binrecon/bucket_functions.py`. Produces `OHare/{source-map.json,findings.md}` for Task 7.

Source: `src/kernel-7/bsd/dev/ppc/drvOHare` — `AppleOHare : IODirectDevice`. The **smallest driver in the series**: the binary carries two real methods, `+[AppleOHare probe:]` and `-[AppleOHare initFromDeviceDescription:]`, and `ohare.m` appears to define only the first. If so, that is a one-method gap. A very small result is legitimate, not a failed measurement.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "ohare-ppc drvPPCOHare.config/drvPPCOHare_reloc" "ohare-bundle-ppc drvPPCOHare.config/drvPPCOHare"; do
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
for k in ['ohare-ppc','ohare-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "ohare-ppc drvPPCOHare.config/drvPPCOHare_reloc" "ohare-bundle-ppc drvPPCOHare.config/drvPPCOHare"; do
  set -- $pair; echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

Expected: 0 relocation violations for both.

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/OHare && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/ohare-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCOHare.config/drvPPCOHare_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvOHare \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/OHare/source-map.json
```

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/OHare/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/ohare-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/OHare/source-map.json
```

Expected `RECONCILES: yes`, buckets 1 and 2 at 0. `RECONCILES: no` is a **stop condition** — report BLOCKED. Resolve every bucket-6 entry against `src/kernel-7/bsd/dev/ppc/drvOHare`.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCOHare.config/drvPPCOHare_reloc" \
  src/kernel-7/bsd/dev/ppc/drvOHare
```

Record verbatim; characterise every extra and missing entry, class-insensitively as well.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/OHare/source-map.json'
a = load_json(Path('tools/binrecon/out/ohare-ppc/published/analysis-reference-ida.json'))
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

- [ ] **Step 9: Write `findings.md`**

`src/drivers-ppc/reconstruction/OHare/findings.md`, following `src/drivers-ppc/reconstruction/Sym8xx/findings.md`. Sections: `## Artifacts` (sizes and SHA-256 from Task 1; note this driver builds into the kernel via `conf/files.ppc` under `mk_hasdrivers`), `## Correspondence`, `## Map validation`, `## Buckets` (with buckets 1 and 2 stated empty and why), `## Unmapped detail`, `## Invariant check`, `## Selector check`, `## Bundle stub`. **Every number from output you observed.**

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/OHare && \
git commit -m "drivers-ppc: measure drvPPCOHare against its shipped binary

Source map and bucket reconciliation for the AppleOHare driver."
```

---

## Task 3: PMU

**Files:** Create `src/drivers-ppc/reconstruction/PMU/{source-map.json,findings.md}`

**Interfaces:** Consumes `pmu-ppc.json`, `pmu-bundle-ppc.json` and `tools/binrecon/bucket_functions.py`. Produces `PMU/{source-map.json,findings.md}` for Task 7.

Source: `src/kernel-7/bsd/dev/ppc/drvPMU` — `ApplePMU : IODirectDevice <ADBservice, RTCservice, NVRAMservice, PowerService>`. Task 7 pairs this against the already-measured `AppleCuda`, which declares `<ADBservice, RTCservice>` on the same superclass, so **record the full selector list** — Task 7 needs it.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "pmu-ppc drvPPCPMU.config/drvPPCPMU_reloc" "pmu-bundle-ppc drvPPCPMU.config/drvPPCPMU"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['pmu-ppc','pmu-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "pmu-ppc drvPPCPMU.config/drvPPCPMU_reloc" "pmu-bundle-ppc drvPPCPMU.config/drvPPCPMU"; do
  set -- $pair; echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/PMU && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/pmu-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCPMU.config/drvPPCPMU_reloc" \
  --source-dir src/kernel-7/bsd/dev/ppc/drvPMU \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/PMU/source-map.json
```

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/PMU/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/pmu-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/PMU/source-map.json
```

Expected `RECONCILES: yes`. Resolve every bucket-6 entry against `src/kernel-7/bsd/dev/ppc/drvPMU`.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCPMU.config/drvPPCPMU_reloc" \
  src/kernel-7/bsd/dev/ppc/drvPMU
```

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/PMU/source-map.json'
a = load_json(Path('tools/binrecon/out/pmu-ppc/published/analysis-reference-ida.json'))
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

- [ ] **Step 9: Write `findings.md`**

`src/drivers-ppc/reconstruction/PMU/findings.md`, the same eight sections as Task 2 Step 9, plus `## Protocol selectors` — the full list of selectors this binary implements, which Task 7 pairs against `AppleCuda`. Note the driver builds into the kernel under `mk_hasdrivers`.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/PMU && \
git commit -m "drivers-ppc: measure drvPPCPMU against its shipped binary

Source map and bucket reconciliation for the ApplePMU driver."
```

---

## Task 4: Awacs

**Files:** Create `src/drivers-ppc/reconstruction/Awacs/{source-map.json,findings.md}`

**Interfaces:** Consumes `awacs-ppc.json`, `awacs-bundle-ppc.json` and `tools/binrecon/bucket_functions.py`. Produces `Awacs/{source-map.json,findings.md}` for Task 7.

Source: `src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj` — `PPCAwacs : IOAudio`.

> **This is a RhapsodiOS reimplementation, not Apple source.** `PPCSound.m` carries both `Copyright (c) 1999 Apple Computer, Inc.` and `Copyright (c) 2025 RhapsodiOS Project`, and **17 of its 38 method definitions are underscore-prefixed**. The other reimplementation in the tree, `drvPPCBurgundy`, renamed **all 16** of its private selectors with an underscore prefix, matching only 21 of 40 reference selectors by name.
>
> **Task 7 tests whether that convention is project-wide.** Your `## Selector check` section is the evidence: for every "missing" reference selector, state whether an underscore-prefixed source selector corresponds to it. **Do not assume the pattern repeats** — a refutation is as valuable as a confirmation, and a large gap here is the expected shape either way, not a failure.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "awacs-ppc PPCAwacs.config/PPCAwacs_reloc" "awacs-bundle-ppc PPCAwacs.config/PPCAwacs"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['awacs-ppc','awacs-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "awacs-ppc PPCAwacs.config/PPCAwacs_reloc" "awacs-bundle-ppc PPCAwacs.config/PPCAwacs"; do
  set -- $pair; echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/Awacs && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/awacs-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/PPCAwacs.config/PPCAwacs_reloc" \
  --source-dir src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/Awacs/source-map.json
```

- [ ] **Step 5: Report the map counts**

```bash
cd $REPO && $VENVPY -c "
import json
d=json.load(open('src/drivers-ppc/reconstruction/Awacs/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/awacs-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/Awacs/source-map.json
```

Expected `RECONCILES: yes`. Resolve bucket-6 entries against the `.lksproj` directory.

- [ ] **Step 7: Selector check, and the rename test**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/PPCAwacs.config/PPCAwacs_reloc" \
  src/drivers-ppc/sound/drvPPCAwacs/PPCAwacs.drvproj/PPCAwacs.lksproj
```

Then test the underscore hypothesis explicitly: for each reference selector reported missing, check whether `_<selector>` exists among our definitions, and vice versa for extras. Report the count that correspond under that transformation and the count that do not. **Keep renames separate from exact matches in every total** — the Burgundy report's arithmetic (`21 exact + 16 renamed + 3 missing = 40 reference`) is the model.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/Awacs/source-map.json'
a = load_json(Path('tools/binrecon/out/awacs-ppc/published/analysis-reference-ida.json'))
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

- [ ] **Step 9: Write `findings.md`**

The eight sections from Task 2 Step 9, plus `## Reimplementation note` covering the dual copyright and the underscore-rename result from Step 7, with renames counted separately from exact matches throughout.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/Awacs && \
git commit -m "drivers-ppc: measure PPCAwacs against its shipped binary

Tests whether Burgundy's underscore selector convention repeats in the second
RhapsodiOS audio reimplementation."
```

---

## Task 5: ApplePCIBus

**Files:** Create `src/drivers-ppc/reconstruction/ApplePCIBus/{source-map.json,findings.md}`

**Interfaces:** Consumes `applepcibus-ppc.json`, `applepcibus-bundle-ppc.json` and `tools/binrecon/bucket_functions.py`. Produces `ApplePCIBus/{source-map.json,findings.md}` for Task 7.

Source: `src/driverkit-3/libDriver/ppc` — **shared with `IODisplay` (Task 6) and the deferred `IONDRVSupport`.** This binary's seven classes are `IOPCIBridge`, `IOGracklePCIBridge`, `IOMacRiscPCIBridge`, `IOMacRiscVCIBridge`, `IOPCIDevice`, `IODeviceTreeBus`, `IOTreeDevice`.

> **Expect a large "extra" selector set.** The directory holds the sibling drivers' sources too. Those extras are **not gaps** — attribute them to sibling classes explicitly in `findings.md`. Determine which class each belongs to with `read_macho` against the relevant binary, not by guessing from the name.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "applepcibus-ppc IOApplePCIBus.config/IOApplePCIBus_reloc" "applepcibus-bundle-ppc IOApplePCIBus.config/IOApplePCIBus"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['applepcibus-ppc','applepcibus-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "applepcibus-ppc IOApplePCIBus.config/IOApplePCIBus_reloc" "applepcibus-bundle-ppc IOApplePCIBus.config/IOApplePCIBus"; do
  set -- $pair; echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/ApplePCIBus && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/applepcibus-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOApplePCIBus.config/IOApplePCIBus_reloc" \
  --source-dir src/driverkit-3/libDriver/ppc \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/ApplePCIBus/source-map.json
```

- [ ] **Step 5: Report the map counts and per-class split**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json, re, collections
d=json.load(open('src/drivers-ppc/reconstruction/ApplePCIBus/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
from binrecon.macho import read_macho
b = read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOApplePCIBus.config/IOApplePCIBus_reloc')
syms = b['symbols'] if isinstance(b, dict) else b.symbols
c = collections.Counter()
for s in syms:
    m = re.match(r'^[-+]\[([A-Za-z0-9_]+)(?:\([A-Za-z0-9_ ]+\))? ', s.get('name') or '')
    if m: c[m.group(1)] += 1
print('binary classes:', dict(c))
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/applepcibus-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/ApplePCIBus/source-map.json
```

Expected `RECONCILES: yes`. Resolve bucket-6 entries against `src/driverkit-3/libDriver/ppc`.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOApplePCIBus.config/IOApplePCIBus_reloc" \
  src/driverkit-3/libDriver/ppc
```

Record verbatim. **Every "extra" must be attributed** — to a sibling driver's class, or recorded as a genuine unexplained extra. Do not leave the set uncharacterised.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/ApplePCIBus/source-map.json'
a = load_json(Path('tools/binrecon/out/applepcibus-ppc/published/analysis-reference-ida.json'))
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

- [ ] **Step 9: Write `findings.md`**

The eight sections from Task 2 Step 9, plus `## Shared source directory` — that `src/driverkit-3/libDriver/ppc` also serves `IODisplay` and the deferred `IONDRVSupport`, the per-class split from Step 5, and the attribution of every extra selector. Note this is framework code, not a driver project.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/ApplePCIBus && \
git commit -m "drivers-ppc: measure IOApplePCIBus against its shipped binary

Maps seven PCI bridge and device-tree classes from the shared driverkit-3
PowerPC directory."
```

---

## Task 6: IODisplay

**Files:** Create `src/drivers-ppc/reconstruction/IODisplay/{source-map.json,findings.md}`

**Interfaces:** Consumes `iodisplay-ppc.json`, `iodisplay-bundle-ppc.json` and `tools/binrecon/bucket_functions.py`. Produces `IODisplay/{source-map.json,findings.md}` for Task 7.

Source: `src/driverkit-3/libDriver/ppc` — the same directory Task 5 used. This binary's classes are `IOSmartDisplay`, `IOSmartADBDisplay`, `IOSmartDDCDisplay`. The same "extras are siblings, not gaps" caveat applies.

- [ ] **Step 1: Run both analyses**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "iodisplay-ppc IODisplay.config/IODisplay_reloc" "iodisplay-bundle-ppc IODisplay.config/IODisplay"; do
  set -- $pair
  BINRECON_REFERENCE="$REF/$2" PYTHONPATH=tools/binrecon \
    $VENVPY -m binrecon analyze --profile "tools/binrecon/profiles/$1.json" \
    --output "tools/binrecon/out/$1/run-summary.json"
  echo "exit=$? profile=$1"
done
```

- [ ] **Step 2: Verify complete and published**

```bash
cd $REPO && $VENVPY -c "
import json, pathlib
for k in ['iodisplay-ppc','iodisplay-bundle-ppc']:
    s=json.load(open(f'tools/binrecon/out/{k}/run-summary.json'))
    a=pathlib.Path(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json')
    print(k, 'complete=',s['complete'], 'published=',a.exists())
    assert s['complete'] is True and a.exists(), k
"
```

- [ ] **Step 3: Invariant check on both**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
for pair in "iodisplay-ppc IODisplay.config/IODisplay_reloc" "iodisplay-bundle-ppc IODisplay.config/IODisplay"; do
  set -- $pair; echo "=== $1 ==="
  PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
    --binary "$REF/$2" --analysis "tools/binrecon/out/$1/published/analysis-reference-ida.json"
done
```

- [ ] **Step 4: Build the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/IODisplay && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IODisplay.config/IODisplay_reloc" \
  --source-dir src/driverkit-3/libDriver/ppc \
  --repo-root . \
  --output src/drivers-ppc/reconstruction/IODisplay/source-map.json
```

- [ ] **Step 5: Report the map counts and per-class split**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json, re, collections
d=json.load(open('src/drivers-ppc/reconstruction/IODisplay/source-map.json'))
print('mapped',len(d['mapped']),'unmapped',len(d['unmapped']),
      'dup',len(d['duplicate_candidates']),'disputed',len(d['boundary_disputed']))
for u in d['unmapped']: print('  unmapped:', u['reference_names'], u['size'])
for e in d['duplicate_candidates']: print('  DUPLICATE:', e['reference_names'])
from binrecon.macho import read_macho
b = read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/IODisplay.config/IODisplay_reloc')
syms = b['symbols'] if isinstance(b, dict) else b.symbols
c = collections.Counter()
for s in syms:
    m = re.match(r'^[-+]\[([A-Za-z0-9_]+)(?:\([A-Za-z0-9_ ]+\))? ', s.get('name') or '')
    if m: c[m.group(1)] += 1
print('binary classes:', dict(c))
"
```

- [ ] **Step 6: Bucket and reconcile**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/IODisplay/source-map.json
```

Expected `RECONCILES: yes`.

- [ ] **Step 7: Selector check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IODisplay.config/IODisplay_reloc" \
  src/driverkit-3/libDriver/ppc
```

**Every "extra" must be attributed** to a sibling class or recorded as genuinely unexplained.

- [ ] **Step 8: Verify the map loads**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map
MAP = 'src/drivers-ppc/reconstruction/IODisplay/source-map.json'
a = load_json(Path('tools/binrecon/out/iodisplay-ppc/published/analysis-reference-ida.json'))
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

- [ ] **Step 9: Write `findings.md`**

The eight sections from Task 2 Step 9, plus `## Shared source directory` as in Task 5.

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/IODisplay && \
git commit -m "drivers-ppc: measure IODisplay against its shipped binary

Maps the three IOSmartDisplay classes from the shared driverkit-3 PowerPC
directory."
```

---

## Task 7: Synthesis — `report-platform.md`, two pairings, acceptance

**Files:** Create `src/drivers-ppc/reconstruction/report-platform.md`

**Interfaces:** Consumes all five `{OHare,PMU,Awacs,ApplePCIBus,IODisplay}/{findings.md,source-map.json}`, plus the committed `Burgundy/` and `Cuda/` artifacts from the first spec.

- [ ] **Step 1: Re-verify all five maps load**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
import json
from pathlib import Path
from binrecon.schema import load_json, load_source_map

PAIRS = [('OHare','ohare-ppc'), ('PMU','pmu-ppc'), ('Awacs','awacs-ppc'),
         ('ApplePCIBus','applepcibus-ppc'), ('IODisplay','iodisplay-ppc')]
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

Expected: five `OK` lines. Acceptance item 3.

- [ ] **Step 2: Collect the summary table**

```bash
cd $REPO && $VENVPY - <<'PY'
import json
PAIRS = [('OHare','ohare-ppc'), ('PMU','pmu-ppc'), ('Awacs','awacs-ppc'),
         ('ApplePCIBus','applepcibus-ppc'), ('IODisplay','iodisplay-ppc')]
print(f"{'driver':13} {'total':>6} {'mapped':>7} {'unmap':>6} {'dup':>4} {'disp':>5} {'mapB':>8} {'unmapB':>8}")
for d, key in PAIRS:
    a = json.load(open(f'tools/binrecon/out/{key}/published/analysis-reference-ida.json'))
    m = json.load(open(f'src/drivers-ppc/reconstruction/{d}/source-map.json'))
    mb = sum(e['size'] for e in m['mapped']); ub = sum(e['size'] for e in m['unmapped'])
    print(f"{d:13} {len(a['functions']):6} {len(m['mapped']):7} {len(m['unmapped']):6} "
          f"{len(m['duplicate_candidates']):4} {len(m['boundary_disputed']):5} {mb:8} {ub:8}")
PY
```

- [ ] **Step 3: The two pairings**

Derive selector sets from each `_reloc`'s symbol table via `read_macho`, filtered to the module's own classes.

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import re
BASE = r'C:/Users/raynorpat/Downloads/test/Drivers/ppc'
pat = re.compile(r'^[-+]\[([A-Za-z0-9_]+)(?:\([A-Za-z0-9_ ]+\))? (.+)\]$')

def sels(path, classes):
    d = read_macho(f'{BASE}/{path}')
    syms = d['symbols'] if isinstance(d, dict) else d.symbols
    out = set()
    for x in syms:
        m = pat.match(x.get('name') or '')
        if m and m.group(1) in classes:
            out.add(m.group(2))
    return out

awacs = sels('PPCAwacs.config/PPCAwacs_reloc', {'PPCAwacs'})
burg  = sels('drvPPCBurgundy.config/drvPPCBurgundy_reloc', {'PPCBurgundy'})
pmu   = sels('drvPPCPMU.config/drvPPCPMU_reloc', {'ApplePMU'})
cuda  = sels('drvPPCCuda.config/drvPPCCuda_reloc', {'AppleCuda'})

print('--- IOAudio pairing ---')
print(f'Awacs {len(awacs)}  Burgundy {len(burg)}')
print(f'  shared: {len(awacs & burg)}'); print('   ', sorted(awacs & burg))
print(f'  Awacs only: {len(awacs - burg)}'); print(f'  Burgundy only: {len(burg - awacs)}')

print('\n--- IODirectDevice ADB/RTC pairing ---')
print(f'PMU {len(pmu)}  Cuda {len(cuda)}')
print(f'  shared: {len(pmu & cuda)}'); print('   ', sorted(pmu & cuda))
print(f'  PMU only: {len(pmu - cuda)}'); print('   ', sorted(pmu - cuda))
print(f'  Cuda only: {len(cuda - pmu)}'); print('   ', sorted(cuda - pmu))
PY
```

Combine with Awacs's underscore-rename result from Task 4 Step 7 and Burgundy's committed 16 renames to answer §4.6's convention question.

**Bounded to spec §4.6's stated questions.** Anything further is a recorded follow-on.

- [ ] **Step 4: Write `report-platform.md`**

Six parts matching spec §4:

1. `## 1. Correspondence` — Step 2's table plus named/unnamed split. Each row reconciles.
2. `## 2. Class inventory` — binary versus source, including how `ApplePCIBus`'s seven and `IODisplay`'s three classes divide their binaries, and how the split was obtained.
3. `## 3. Non-Objective-C remainder` — bucket tables and `selector_check.py` output per driver. **State that buckets 1 and 2 are empty across all five and why.** For the two `driverkit-3` drivers, state that the large extra sets are sibling classes from the shared directory, not gaps.
4. `## 4. Findings` — each with its reference evidence, citing the per-driver `findings.md`. Include the packaging gap.
5. `## 5. Decomposition proposal` — ranked by **actionable divergence with runtime consequence**, tie-broken by "a documented, evidenced cause is a result, not work".
6. `## 6. Two pairings` — Step 3's output. State plainly whether the underscore convention is **project-wide or driver-local**, and what `ApplePMU` and `AppleCuda` share as `ADBservice`/`RTCservice` providers. Cross-reference `report.md`; `drvPPCBurgundy` and `drvPPCCuda` are **not** re-measured.

Every number must trace to output you ran.

- [ ] **Step 5: Run the suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: **845 passed, 4 skipped**. If it differs, record the discrepancy rather than substituting silently.

- [ ] **Step 6: Confirm no generated evidence is staged**

```bash
cd $REPO && git status --porcelain | grep -c "tools/binrecon/out/" || echo "0 - clean"
```

- [ ] **Step 7: Walk the acceptance list**

Confirm each of spec §5's eight items against observed output and record the evidence in a final `## Acceptance` section. **Do not claim an item you did not observe.**

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction/report-platform.md && \
git commit -m "drivers-ppc: report the PowerPC platform driver evidence base

Correspondence, bucket reconciliation, and the IOAudio and ADB/RTC pairings."
```

---

## Notes for the executing agent

- **Exit 1 from `analyze` is success.** It happens ten times.
- **Never commit `tools/binrecon/out/`.** **Never edit driver source.**
- **Every number must come from output you observed.** Reviewers on the preceding specs repeatedly caught claims that were plausible but contradicted by the binary.
- **`RECONCILES: no` is a stop condition.**
- **Use `read_macho` for anything class- or category-related** — IDA's export strips category tags.
- **The two `driverkit-3` drivers share a source directory.** Large extra sets are expected and must be attributed to sibling classes, never left as bare gaps.
