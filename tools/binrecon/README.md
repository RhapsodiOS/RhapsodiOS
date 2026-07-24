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

Run the complete test suite with:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
& $binreconPython -m pytest tools/binrecon/tests -q
```
