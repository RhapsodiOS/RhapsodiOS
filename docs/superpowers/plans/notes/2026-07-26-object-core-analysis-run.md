# Foundation stage 2a object-core analysis run (IDA)

Records the Task 3 `binrecon analyze` run that produces
`tools/binrecon/out/foundation-i386-object-core/published/analysis-reference-ida.json`,
the analysis of record Tasks 5-10 reconstruct against.

## RESULT: complete, no splitting needed

## Symbol assignment and cross-checks (brief Steps 1, 4)

`NSZone.m`'s 25 C functions were added to
`src/Kits/Foundation/reconstruction/symbols.json` per spec §2.1. Verified:
`count 25 unique 25`, `missing from binary: []`, `claimed twice: []`.

`binrecon symbol-audit` dropped from 373 to exactly **348** unclaimed exported
functions after the assignment, confirming no typo or duplicate.

`module-scope` for the four real modules (`NSObject.m`, `NSProxy.m`,
`NSAutoreleasePool.m`, `NSPrivate.m`) produced **168** ranges.
`NSZone.m` is not a module in the binary, so its 25 C functions' ranges were
computed separately with `function_ranges` against the same symbol list.
Merged and sorted by `start`, the combined `analysis_scope` totals **193**
ranges with 193 unique start addresses (168 + 25), pasted into
`tools/binrecon/profiles/foundation-i386-object-core.json`.

## Commands run

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe \
  -m binrecon validate --profile tools/binrecon/profiles/foundation-i386-object-core.json
```
```
reference C:\Users\raynorpat\Downloads\test\Foundation-i386 size=1630488 sha256=1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6
```

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe \
  -m binrecon analyze --profile tools/binrecon/profiles/foundation-i386-object-core.json
```

The first attempt was launched via the Bash tool's `run_in_background`
option, redirected to scratch log files. That attempt was silently killed
mid-run: `idat.exe` and the analyzer's python process both vanished from the
process list roughly 2 minutes in, with no error written to the redirected
logs, no `published/` output, and the temporary IDA workspace left orphaned
under `tools/binrecon/out/foundation-i386-object-core/` (never cleaned up,
which only happens if the run exits normally). This is consistent with the
background job being tied to, and terminated alongside, the Bash tool's own
call rather than surviving independently. The orphaned workspace and stale
`.binrecon-run.lock` / `.run-summary.json.binrecon-summary.lock` files were
removed (`shutil.rmtree`; the OS-level lock had already released with its
owning process gone) and the run was relaunched as a detached process
(`nohup ... & disown`) so it would not depend on the Bash tool call's own
lifetime. That second attempt ran to completion unattended.

stdout: `analysis complete; analyzers=1 comparisons=0 normalized-functions=FAIL`.
The `FAIL` is expected at this stage: `comparisons=0` because there is no
rebuilt Foundation source yet (Tasks 5-10 write that); `run-summary.json`'s
`"complete":true` is the field this task's success turns on, and it is true.

## Measurements

- **Wall-clock time:** 108 seconds — launched `2026-07-27T00:05:52Z`,
  published output written `2026-07-27T00:07:40Z` (UTC, from the launch
  timestamp and the published file's mtime). Far under the profile's
  `timeout_seconds: 5400` budget. For comparison, stage 1's 43-function/
  8,784-byte scope took 128 s; this run's 193-range scope (4.5x more
  functions) took *less* wall-clock time, consistent with IDA's own
  autoanalysis of the whole 1.6 MB image dominating the cost over the
  per-function export work.
- **Published JSON size on disk:** `analysis-reference-ida.json` is
  15,353,255 bytes (~14.6 MiB), close to stage 1's 15,117,955 bytes for 43
  functions — confirming most of the export's size is fixed per-image
  overhead (sections/strings/symbols/relocations/imports), not per-function.
- **IDA version:** 9.2 (`C:/Program Files/IDA Professional 9.2/idat.exe`,
  matching the profile's `analyzers.ida.version`).
- **Splitting:** not needed. The single `analyze` invocation across all 193
  ranges succeeded in one pass with no `IDA output exceeds maximum JSON size`
  error.

## Verification (brief Step 6)

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/foundation-i386-object-core/published/analysis-reference-ida.json'))
print(d['input']['sha256'])
print(len(d['functions']), 'functions')
"
```
```
1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6
193 functions
```

Both match the brief's expected values exactly.
