# Validation record

## Baseline

- PowerPC reference: 70,852 bytes, SHA-256
  `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179`.
- Resource SHA-256 inventory: `resources.sha256` (12 files).
- Local Downloads search: found only the supplied PowerPC ProcessViewer binary;
  no i386 oracle currently available.
- Binrecon profile validation: passed and resolved the expected reference
  identity.
- Reference-only binrecon analysis: complete; IDA 9.4 analyzed 128 function
  records. No rebuilt comparison ran yet. The summary reports
  `normalized-functions=FAIL` because the profile has no rebuilt artifact; this
  is not a reconstruction mismatch. Output is under ignored
  `tools/binrecon/out/processviewer-ppc`.
- Hex-Rays run: 83 application functions (78 Objective-C methods and five C
  functions), zero decompilation failures. Pseudocode and IDA database remain
  ignored under the same output directory and are indexed in `pseudocode.md`.
- Existing binrecon parser baseline: `pytest tools/binrecon/tests/test_macho.py
  tools/binrecon/tests/test_objc_index.py -q` — 68 passed. The metadata index's
  46 directly decoded names reconcile to all 78 method symbols using class and
  category IMP addresses; no parser change was made.
- The normalized binrecon exporter records instructions, basic blocks,
  references, and import stubs, not pseudocode. A separate Hex-Rays IDAPython
  pass generated the pseudocode. Individual methods still require behavioral
  checks during their implementation tasks.

## Per-architecture completion matrix

| Evidence | PowerPC | i386 |
|---|---|---|
| Reference identity | verified | no reference found |
| Static function inventory | 128 IDA records; ownership under review | pending build evidence |
| ABI / selector inventory | extracted to `abi.md` | pending target compiler/headers |
| Application build | pending | pending |
| Deterministic behavior tests | pending | pending |
| GUI integration | pending | pending |
| Instruction-level parity | pending rebuilt artifact | unavailable without oracle |
