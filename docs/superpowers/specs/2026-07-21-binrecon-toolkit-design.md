# Binrecon multi-analyzer reconstruction toolkit design

**Date:** 2026-07-21  
**Status:** Approved  
**First consumer:** EISABus binary reconstruction

## Summary

Create a reusable, driver-neutral toolkit under `tools/binrecon/` for reconstructing legacy binaries from source. The toolkit inventories binaries, imports independent analysis from IDA and Ghidra, supplements it with targeted angr analysis, compares rebuilt functions and images against a reference, and records progress in a machine-readable parity ledger.

The bytes of the reference artifact remain authoritative. Analyzer output is evidence, not truth.

## Goals

1. Produce repeatable manifests for 32-bit Mach-O sections, symbols, relocations, Objective-C metadata, functions, basic blocks, calls, and data references.
2. Normalize IDA, Ghidra, and angr results into one versioned JSON schema.
3. Report analyzer disagreements instead of silently selecting one result.
4. Compare reference and rebuilt functions while separating relocation-dependent operands from literal instruction differences.
5. Compare sections and complete images byte-for-byte and by SHA-256.
6. Maintain a parity ledger that records the evidence and status for every reconstructed function.
7. Keep the core reusable for other kernel servers and drivers without embedding EISA or PnP semantics.

## Non-goals

- Build a new decompiler or disassembler.
- Automatically turn pseudocode into compilable source.
- Prove whole-kernel semantic equivalence.
- Symbolically execute privileged BIOS transitions, DriverKit, Objective-C runtime dispatch, or hardware I/O end-to-end.
- Commit proprietary reference binaries or analyzer databases.
- Generalize beyond capabilities exercised by the EISABus reconstruction until another driver requires them.

## Repository layout

| Path | Responsibility |
|------|----------------|
| `tools/binrecon/` | Driver-neutral command-line entry point and shared schema |
| `tools/binrecon/adapters/ida/` | IDAPython export of functions, instructions, xrefs, and Objective-C metadata |
| `tools/binrecon/adapters/ghidra/` | Headless Ghidra scripts for independent program and decompiler exports |
| `tools/binrecon/adapters/angr/` | CFG and bounded symbolic-analysis exports |
| `tools/binrecon/compare/` | Relocation-aware function, section, and image comparison |
| `tools/binrecon/schema/` | Versioned JSON schema and validation |
| `tools/binrecon/tests/` | Tool tests using redistributable synthetic fixtures |
| `tools/binrecon/profiles/` | Example profile schema; real driver profiles may live with their driver |

## Profile contract

A profile identifies:

- Reference and rebuilt artifact paths supplied at runtime.
- CPU architecture, endianness, preferred image base, and executable sections.
- Enabled analyzers and their executable or environment locations.
- Analyzer version constraints recorded in each result.
- Symbol aliases, known entry points, and ranges that contain code or data.
- Comparison rules for relocations, absolute addresses, padding, and ignored build metadata.
- Paths for normalized manifests, disagreement reports, and the parity ledger.

Profiles contain no credentials and do not require reference artifacts to be copied into the repository.

## Normalized analysis schema

Each adapter emits the same core entities:

- Input identity: size, SHA-256, architecture, analyzer name, analyzer version, and invocation.
- Segments and sections: names, addresses, file offsets, sizes, permissions, and hashes.
- Symbols and relocations: names, addresses, binding, relocation kind, addend, and target.
- Functions: address, size, names, aliases, calling convention, return behavior, and confidence.
- Basic blocks and edges: ranges, successors, edge kind, and owning function.
- Instructions: address, bytes, mnemonic, operands, normalized operands, and referenced relocations.
- References: calls, imports, strings, data references, selectors, classes, categories, and methods.
- Optional intermediate views: Ghidra P-code, angr VEX summaries, and decompiler text.

Analyzer-specific fields live under a namespaced extension object so core consumers do not depend on one analyzer.

## Analyzer roles

### IDA

IDA is the primary mapping source for the existing workflow. A deterministic IDAPython export records recognized functions, legacy Objective-C metadata, disassembly, cross-references, imports, and optional decompiler output. IDA names are preserved as aliases rather than assumed to be canonical.

### Ghidra

Ghidra runs headlessly with repository-owned post-analysis scripts. It supplies an independent opinion on function boundaries, control-flow graphs, data types, references, P-code, and decompiler output. Temporary projects are disposable; normalized exports are the durable result.

### angr

angr loads the Mach-O image through CLE when supported and uses an explicitly configured flat i386 image otherwise. `CFGFast` is the default CFG pass. `CFGEmulated`, backward slicing, and symbolic execution are limited to selected functions with bounded inputs and execution limits.

angr targets pure or bounded logic such as checksums, identifier conversion, resource parsing, matching, and allocation search. External calls, Objective-C dispatch, allocations, locks, BIOS transitions, and port I/O use explicit hooks or terminate the analysis path.

## Consensus and disagreements

The toolkit computes agreement by address and byte range, not by analyzer-assigned name. A disagreement report records differences in:

- Function starts, ends, and overlapping ownership.
- Basic-block boundaries and successor edges.
- Direct and indirect call targets.
- Code-versus-data classification.
- Stack variables, arguments, calling conventions, and return behavior.
- Objective-C selectors and method ownership.

Disagreements are mandatory review items in the parity ledger. No majority vote changes reference bytes or source automatically.

## Comparison model

Function comparison has three layers:

1. Raw bytes and instruction decoding.
2. Relocation-normalized instructions, preserving literal constants and access widths.
3. Control-flow shape, call targets, and referenced data.

Image comparison reports section ordering, addresses, sizes, contents, relocation tables, symbols, strings, padding, and complete SHA-256. Every mismatch is classified as code, relocation, symbol/string ordering, layout, padding, or metadata.

## Parity ledger

Each source-mapped function has one status:

- `unexamined`
- `signature-confirmed`
- `control-flow-confirmed`
- `assembly-matched`
- `intentional-mismatch`

An entry contains reference range, source location, analyzer agreement, comparison artifacts, reviewer note, and the exact reference/rebuilt hashes used. `intentional-mismatch` requires a reason and does not satisfy byte-identical acceptance.

## Dependency and failure policy

IDA, Ghidra, and angr are optional adapters but all three are required for the EISABus baseline. Their versions and invocations are recorded in manifests. The CLI fails clearly when a profile requires an unavailable adapter. A failed or timed-out analyzer produces an explicit incomplete result; it never reuses stale output as current evidence.

The current workstation has IDA Professional 9.2. Ghidra and angr are not currently installed, so setup, pinning, and smoke verification are explicit implementation work.

## Verification

1. Schema validation rejects incomplete or version-incompatible manifests.
2. Synthetic i386 fixtures verify section extraction, relocations, functions, and normalization.
3. Mutated fixtures prove the comparator distinguishes relocations from literal code changes.
4. IDA and Ghidra exports of the same fixture normalize to common functions and blocks.
5. angr CFG output agrees on the fixture and bounded symbolic checks terminate deterministically.
6. The EISABus profile produces a complete three-analyzer disagreement report and parity ledger without copying its reference binaries into the repository.

## Success criteria

- One command defined by the EISABus profile runs all available required adapters and comparisons.
- Outputs are deterministic for identical inputs and pinned analyzer versions.
- Analyzer disagreements are visible and traceable to addresses and bytes.
- Function comparison supports the EISABus reference and rebuilt images.
- Section and whole-image reports identify every byte mismatch category.
- A second driver can define a new profile without changing toolkit core code.

