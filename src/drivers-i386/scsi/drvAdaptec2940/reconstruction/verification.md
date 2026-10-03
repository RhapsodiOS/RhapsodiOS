# Verification record

Reference-only baseline on 2026-10-02:

- Reference identity: 87,676 bytes, i386 little-endian, SHA-256 `08E6C11EEC125847F485C86250C94C4AFCC025E59CF085B0C8039B94B2E79DF7`; `__TEXT,__text` begins at `0` and is 32,568 bytes.
- `binrecon validate --profile tools/binrecon/profiles/adaptec2940.json`: passed.
- `binrecon analyze ...`: analysis completed with IDA 9.4; expected exit 1 because there is no rebuilt artifact or comparison. The published reference analysis contains 170 functions.
- IDA manual export: pseudocode and disassembly captured for all 170 functions with no decompilation errors. Raw exports and IDA database remain in ignored `tools/binrecon/out/adaptec2940/`.
- `pytest .../tests/test_reconstruction.py -q`: 2 passed.
- `test_reconstruction.py --audit inventory --analysis <published analysis> --repo-root .`: passed; 30 controller methods, 13 SCSIBus methods, 125 C functions and two compiler-generated methods; 170 unique source-map and ledger entries.
- `binrecon.schema.load_source_map` validation with the complete analysis and worktree source tree: passed (10 mapped, 160 unmapped at the baseline).

No compilation, guest execution, functional tests, or parity checks are claimed at this stage. The host's configured VM is PowerPC; it can cross-build i386 but cannot execute the i386 harness. Runtime harness verification requires the documented i386-compatible guest.
