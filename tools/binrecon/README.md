# Binrecon

Binrecon coordinates IDA, Ghidra, and angr analysis of a reference binary and
its reconstruction. It normalizes analyzer output, reports disagreements,
compares the two artifacts, and maintains a human-reviewed parity ledger.
Reference and rebuilt binaries stay outside Git; only profiles and source code
belong in the repository.

## Install on Windows

Run these commands from the repository root. Python 3.12 is the supported
runtime, and both runtime and test dependencies are pinned.

```powershell
py -3.12 -m venv .venv-binrecon
$binreconPython = '.\.venv-binrecon\Scripts\python.exe'
& $binreconPython -m pip install --upgrade pip
& $binreconPython -m pip install -r tools\binrecon\requirements-dev.txt
$env:PYTHONPATH = 'tools/binrecon'
```

The pinned versions are angr 9.3.0, jsonschema 4.26.0, and pytest 9.1.1.

Install and configure the external analyzers separately:

- IDA Professional 9.2: set `analyzers.ida.executable` to the 32-bit batch
  executable, for example `C:/Program Files/IDA Professional 9.2/idat.exe`,
  and set `version` to `9.2`.
- Ghidra 12.1: set `analyzers.ghidra.executable` to
  `support/analyzeHeadless.bat`, set `version` to `12.1`, and put a Java 21
  `java.exe` on `PATH` or under `JAVA_HOME/bin`. The adapter rejects other
  configured Ghidra versions and Java major versions.
- angr: point `analyzers.angr.executable` at the Python executable in the
  venv, set `version` to `9.3.0`, and use a positive timeout.

Copy [profiles/example.json](profiles/example.json) for a new target and edit
the executable paths if the tools are installed elsewhere. Keep the input
artifacts external and set their paths for the current PowerShell session:

```powershell
$env:BINRECON_REFERENCE = 'C:\path\to\reference\EISABus.config\EISABus'
$env:BINRECON_REBUILT = 'C:\absolute\path\to\rebuilt\EISABus.config'
& $binreconPython -m binrecon validate --profile tools/binrecon/profiles/example.json
```

Only `${BINRECON_REFERENCE}` and `${BINRECON_REBUILT}` are expanded in artifact
paths. An unset variable is an error. Relative paths are resolved from the
profile directory; analyzer executable paths are resolved by the host process,
so run the example from the repository root.

## PowerPC targets

Binrecon reads 32-bit big-endian PowerPC Mach-O (`CPU_TYPE_POWERPC`, 18) in
addition to i386. Set `"architecture": "ppc"` and `"endianness": "big"` in the
profile; the reader picks its byte order from the file header and the IDA
adapter runs `idat -pppc`.

Only IDA analyses PowerPC. The Ghidra and angr adapters are i386-only and
reject a PowerPC profile before starting any subprocess, because they replay
the Mach-O layout and apply relocations themselves, and neither knows how to
encode PowerPC instruction fields.

PowerPC relocations are decoded as paired fixups. `extensions.macho.relocations`
keeps one record per file entry, `PAIR` entries included; the top-level
`relocations` list fuses each principal with its pair into a single record whose
addend is the reconstructed 32-bit value relative to its target. `HA16`'s signed
low half is applied, so `HA16` and `HI16` yield different addends for the same
halves.

The seven PowerPC profiles (`profiles/*-ppc.json`) are reference-only: the
repository cannot build PowerPC drivers today, so there is no rebuilt artifact
to compare against.

## Commands

Show the installed interface at any time with
`& $binreconPython -m binrecon --help` or
`& $binreconPython -m binrecon COMMAND --help`.

Validate the profile, resolve both artifacts, and print their absolute paths,
sizes, and SHA-256 identities:

```powershell
& $binreconPython -m binrecon validate --profile tools/binrecon/profiles/example.json
```

Run all enabled analyzers sequentially, build consensus and comparisons, and
optionally reconcile evidence into a ledger:

```powershell
& $binreconPython -m binrecon analyze --profile tools/binrecon/profiles/example.json `
  --ledger tools/binrecon/out/example/ledger.json `
  --output tools/binrecon/out/example/run-summary.json
```

Without `--output`, `analyze` writes `run-summary.json` under the profile's
`output_dir`. Without `--ledger`, no ledger is changed. Exit code 0 means the
run is complete and the selected acceptance level passes; an analyzed mismatch
or an incomplete run returns 1 while retaining a machine-readable summary.

Build consensus directly from two or more normalized analysis documents.
Repeat `--input` and, when the expected analyzer set differs from the default,
repeat `--expected-analyzer`:

```powershell
& $binreconPython -m binrecon consensus `
  --input ida.analysis.json --input ghidra.analysis.json --input angr.analysis.json `
  --expected-analyzer IDA --expected-analyzer Ghidra --expected-analyzer angr `
  --output consensus.json
```

Compare a reference/rebuilt analysis pair. `--require` overrides the profile's
`exact-image`, `exact-sections`, or `normalized-functions` acceptance level;
`--text-output -` writes the concise report to stdout:

```powershell
& $binreconPython -m binrecon compare --profile tools/binrecon/profiles/example.json `
  --reference-analysis reference.analysis.json `
  --rebuilt-analysis rebuilt.analysis.json --output comparison.json `
  --text-output comparison.txt --require normalized-functions
```

Inspect a ledger or make one reviewed transition. Addresses accept Python-style
integers such as `0x1000`. `--source-path` and `--source-line` must be supplied
together; an intentional mismatch also requires a reviewed state, a reason,
and a reviewer.

```powershell
& $binreconPython -m binrecon ledger --profile tools/binrecon/profiles/example.json `
  --ledger tools/binrecon/out/example/ledger.json
& $binreconPython -m binrecon ledger --profile tools/binrecon/profiles/example.json `
  --ledger tools/binrecon/out/example/ledger.json --address 0x1000 `
  --status signature-confirmed --source-path src/example.c --source-line 42
```

Validate a checked-in source map against a saved reference analysis and the
repository's source files with the semantic loader API. This checks the exact
function partition, names, full function sizes, source-line bounds, and
explicit boundary overlaps in addition to the closed `source-map-v1` schema:

```powershell
@'
from pathlib import Path
from binrecon.schema import load_json, load_source_map

repo_root = Path.cwd()
analysis = load_json(Path('path/to/reference.analysis.json'))
load_source_map(
    Path('path/to/source-map.json'),
    reference_analysis=analysis,
    repo_root=repo_root,
)
'@ | & $binreconPython -
```

The reference analysis is generated evidence and remains outside Git. The
loader validates it as `analysis-v1`, requires its input SHA-256 to exactly
match the source map, and checks its complete function partition. Passing only
the source-map path performs schema and context-free semantic validation; the
full reference analysis and repository root enable the stronger reconstruction
review checks shown above.

## Outputs and safety guarantees

The example resolves `../out/example` relative to its `profiles` directory, so
generated data lands in `tools/binrecon/out/example`, which is ignored by Git.
Successful orchestration publishes analyzer JSON, per-artifact consensus, and
per-analyzer comparisons below `published/`; the summary records relative paths
and SHA-256 hashes for those files. The ledger records evidence but never
automatically advances a human-reviewed status.

Each run holds cross-process locks, invokes analyzers sequentially, and writes
to a unique staging directory. Adapter output must be a private regular file,
match the normalized schema and configured architecture/endianness, and carry
the captured input identity before it can replace published output. Summary and
ledger writes use flushed temporary files plus atomic replacement; output paths
that alias the profile, artifacts, analyses, or ledger are rejected. A failed
or timed-out run cannot report passing acceptance: its summary is marked
`complete: false`, `acceptance.passed: false`, and includes a bounded diagnostic.
Temporary analyzer output is never accepted as evidence merely because a file
from an earlier run exists.

## Analyzer limits

- IDA and Ghidra function discovery, names, and decompilation are analyzer
  claims, not truth. Consensus preserves disagreement rather than voting away
  conflicting boundaries.
- Ghidra first tries its Mach-O loader. When that loader rejects a legacy input,
  the adapter can fall back to deterministic raw i386 import using parsed Mach-O
  sections. Java 21 and Ghidra 12.1 remain mandatory.
- angr uses `CFGFast`; unsupported indirect control flow and loader issues are
  recorded in CFG errors. Bounded symbolic checks may return `unsupported` or
  `limit-reached`; neither is success.
- Normalized-function acceptance is relocation-aware, but literal constants,
  access widths, calls, and control-flow shape still must agree. It does not
  imply exact section layout or byte-for-byte image identity.

## Writing the reconstructed source

Guidance from reconstructing i386 kernel loadable servers (`drvEISABus`,
`drvEIDE`). These are about the source you write from the analysis, not about
the analyzers.

**Reference Objective-C classes directly. Never `objc_getClass("Name")`.**
Write `[[KernBusItemResource alloc] init...]`, not
`[[objc_getClass("KernBusItemResource") alloc] init...]`.

A direct reference becomes a link-time class reference the loader resolves; the
string lookup is a runtime call that returns **nil** for a class that lives in
the kernel rather than in the module. `[nil alloc]` then propagates nil silently
and the failure surfaces far away from its cause. In `drvEISABus` this made
every bus resource nil, so each driver's later lookup failed with
`IRQ Levels: Couldn't locate resource object`, no disk driver could attach, and
the boot ended at `ufs_mountroot failed: 19` — with nothing pointing back at the
bus driver.

The shipped modules do not call `objc_getClass` at all. Two cheap checks:

```bash
# rebuilt module should have no objc_getClass, matching the reference
python -c "print(b'objc_getClass' in open('EISABus_reloc','rb').read())"

# every class the reference links must also be linked by the rebuild
python -c "
r=open('rebuilt','rb').read(); o=open('reference','rb').read()
for n in [b'KernBusItemResource', b'KernBusRangeResource', b'KernBusMemoryRange']:
    s=b'.objc_class_name_'+n
    print(n.decode(), 'rebuilt=', s in r, 'reference=', s in o)
"
```

A class present in the reference's `.objc_class_name_*` symbols but absent from
the rebuild's means a link-time reference was replaced by a runtime lookup.
Classes defined *inside* the module keep their symbol either way, so the
symptom appears only for classes owned by the kernel — which is precisely the
case that fails at runtime. Run this comparison before boot-testing a
reconstructed module; it is far cheaper than reading a boot log.

**Do not double-initialise.** `[[[X alloc] initFrom:...] init]` re-runs `-init`
on an already-initialised object. The pattern shows up when a decompiled
constructor chain is transcribed literally; write `[[X alloc] initFrom:...]`.

Run the complete test suite with:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& $binreconPython -m pytest tools/binrecon/tests -q
```

## PowerPC acceptance run

`validate` and `analyze` against the real reference binaries, one run per
PowerPC profile:

| Profile | Reference file | Size | `analyze` exit |
|---|---|---|---|
| scsiserver-ppc | `SCSIServer.config/SCSIServer_reloc` | 51044 | 1 (reference-only) |
| scsiserver-bundle-ppc | `SCSIServer.config/SCSIServer` | 8496 | 1 (reference-only) |
| scsitape-ppc | `SCSITape.config/SCSITape_reloc` | 47624 | 1 (reference-only) |
| scsitape-bundle-ppc | `SCSITape.config/SCSITape` | 8492 | 1 (reference-only) |
| scsitape-preload-ppc | `SCSITape.config/PreLoad` | 9060 | 1 (reference-only) |
| scsitape-postload-ppc | `SCSITape.config/PostLoad` | 21520 | 1 (reference-only) |
| stblocksize-ppc | `SCSITape.config/stblocksize` | 13408 | 1 (reference-only) |

Exit 1 marked "reference-only" is expected: these profiles have no rebuilt
artifact, so `normalized-functions` acceptance can never pass. Success for a
reference-only profile means `complete: true` plus a published
`analysis-reference-ida.json`, not exit 0. All seven runs meet that bar: IDA
loaded each artifact, and the exporter's mapping-manifest and fixup checks
accepted its output.

`scsitape-ppc` did not always publish cleanly. It first failed with `IDA
export failed: malformed fixup target at 0x2e34`: IDA's PPC loader logs the
relocation at `__text+0x2e34` in `SCSITape_reloc` as an "Unhandled relocation
type" (a `PPC_RELOC_SECTDIFF`-derived switch table in `__TEXT,__const`), and
the exporter's own fixup-integrity check rejected the 32-bit wrap of that
scattered section-difference fixup as if it were corruption rather than a
legitimate negative displacement. Commit `12a64a6c` fixed the exporter to
accept this case, and a later hardening pass replaced the fix's masking
arithmetic with an explicit sign-extend-then-range-check so a fixup target
that genuinely leaves the 32-bit address space is still rejected rather than
silently wrapped into range. `scsitape-ppc` now completes and publishes
`analysis-reference-ida.json` like the other six.

Re-running `ppc_invariant_check.py --binary ... --analysis ...` against the
published analyses finds one symbol/function-start mismatch in each of
`scsiserver-ppc` and `scsitape-ppc`: `+[SCSIServer deviceStyle]` and
`+[SCSITape deviceStyle]`, respectively, are local symbols at address 0 with
no corresponding IDA function (the earliest function IDA found in each
starts at 0x10). Both are candidates for a future reconstruction's
`boundary_disputed` bucket, not a relocation-decoder defect — all 20
scattered/difference-form relocations and all HI16/HA16-LO16 pairs in both
binaries still agree.

`binrecon source-map --objc-methods --scope-to-objc` runs to completion
against `scsiserver-ppc`'s analysis (0 mapped, 14 unmapped Objective-C
methods). Without `--scope-to-objc` it fails: IDA's PPC linker glue stub for
external calls (`_objc_msgSend`, `_IOLog`, ...) has no name, and
`source-map-v1` requires every analyzed function to have one.

Full suite: 746 passed, 4 skipped (741 baseline + 3 tests from the SECTDIFF
fix + 1 test pinning the range-check hardening + 1 test pinning that the
displacement's sign is taken from the fixup's upper word, not bit 31 of the
low word).
