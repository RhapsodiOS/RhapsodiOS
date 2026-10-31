# Foundation stage 1 analysis run (IDA)

Records the Task 10 `binrecon analyze` run that produces
`tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json`,
the analysis of record Tasks 12-15 reconstruct against. Spec §5.2 flags this
run as the most likely place the stage stalls, and §5.5 wants measurements so
later stages can size their groups from data rather than guesswork.

## RESULT: complete, no splitting needed

## Commands run

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe \
  -m binrecon validate --profile tools/binrecon/profiles/foundation-i386.json
```
```
reference C:\Users\raynorpat\Downloads\test\Foundation-i386 size=1630488 sha256=1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6
```

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe \
  -m binrecon module-scope --profile tools/binrecon/profiles/foundation-i386.json \
  --module NSGeometry.m --module NSRange.m --module NSDecimal.m \
  --symbols src/Kits/Foundation/reconstruction/symbols.json
```
stderr: `# 43 ranges`. The 43 ranges are disjoint, sorted by `start`, and sum
to 8,784 bytes; pasted verbatim into the profile's `analysis_scope`.

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe \
  -m binrecon analyze --profile tools/binrecon/profiles/foundation-i386.json
```

Run in the background (redirected to scratch log files) since IDA autoanalysis
against a 5400s `timeout_seconds` budget can exceed a single foreground shell
call's cap. Polled the logs and `tools/binrecon/out/foundation-i386/` every
60-90s rather than assuming a foreground timeout meant failure.

stdout: `analysis complete; analyzers=1 comparisons=0 normalized-functions=FAIL`
(exit code 1). The `FAIL`/exit 1 is expected at this stage: `comparisons=0`
because there is no rebuilt Foundation source yet (Tasks 12-14 write that);
`run-summary.json`'s `"complete":true` is the field this task's success turns
on, and it is true.

## Measurements

- **Wall-clock time:** 128 seconds (2 min 8 s) — started
  `2026-07-26T17:31:03Z`, ended `2026-07-26T17:33:11Z` (UTC, from `date -u`
  bracketing the background command). Far under the profile's
  `timeout_seconds: 5400` budget; the 43-range/8,784-byte scope keeps IDA's
  work small even though the container dylib is 1.6 MB.
- **Published JSON size on disk:** `analysis-reference-ida.json` is
  15,117,955 bytes (~14.4 MiB) despite the 8,784-byte scope — IDA's export
  includes full sections/strings/symbols/relocations/imports context for the
  binary, not just the scoped functions.
- **IDA version:** 9.2 (`C:/Program Files/IDA Professional 9.2/idat.exe`,
  matching the profile's `analyzers.ida.version`).
- **Splitting:** not needed. The single `analyze` invocation across all three
  modules' combined scope succeeded in one pass with no
  `IDA output exceeds maximum JSON size` error.

## Verification (brief Step 6)

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json'))
print(d['input']['sha256'])
print(len(d['functions']), 'functions')
"
```
```
1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6
43 functions
```

Both match the brief's expected values exactly.
