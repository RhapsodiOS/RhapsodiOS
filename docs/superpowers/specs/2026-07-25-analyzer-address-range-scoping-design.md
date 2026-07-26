# Analyzer address-range scoping

Teach binrecon to analyze a declared address range of a binary rather than all of
it, so that large images can be reconstructed a subsystem at a time. One new
optional profile field, honoured by all three analyzer adapters.

This unblocks
[2026-07-25-kernel-pci-pcmcia-reconstruction-design.md](2026-07-25-kernel-pci-pcmcia-reconstruction-design.md),
whose analysis phase currently cannot run at all.

## Motivation

binrecon was built for relocatable driver objects of 28–92 KB. Applied to
Apple's 1.4 MB DR2 i386 kernel, the IDA adapter fails:

```
binrecon: ida reference adapter failed: IDA output is invalid: IDA output exceeds maximum JSON size
```

The run ends `complete: false` with an empty `published/`. A full
instruction-level export of every function in a whole kernel exceeds
`_MAX_ANALYSIS_BYTES` (16 MB, `tools/binrecon/binrecon/adapters/ida.py:28`).

The kernel effort needs 24 methods out of roughly 1224 — about 3 KB of code out
of 1.4 MB. Analyzing the other 99.8% is waste that also happens to be fatal.

## 1. Scope

An optional `analysis_scope` field in `profile-v1`, plumbed to the IDA, Ghidra
and angr exporters, each of which skips functions whose entry point falls outside
it. Absent field means analyze everything, exactly as today.

### 1.1 Out of scope

Raising `_MAX_ANALYSIS_BYTES` or any other guard. Those limits exist to contain
malformed analyzer output; the fix here is to produce less, not to permit more.

Changing acceptance semantics, the comparison pipeline, or `scope_analysis`
(which filters an already-produced analysis and stays as it is — it remains the
right tool for narrowing a map within an analysis that was itself producible).

The kernel reconstruction itself. It resumes once this lands.

## 2. Findings that shaped this design

### 2.1 `regions` exists but is the wrong vehicle

`profile-v1.json` already carries a `regions` array whose items are
`{name, address, offset, size, permissions}`. It describes **where bytes live in
the file** and is consumed as a fallback when Mach-O parsing fails — see
`adapters/ida.py:76` and `adapters/angr.py:158`, both of which fall back to
`profile.document.get("regions", ())`.

Overloading it to also mean "which functions to analyze" would couple two
unrelated failure modes: a malformed `regions` entry would then break both file
mapping and analysis scoping, and a profile wanting scope would have to restate
the whole file layout. A separate field keeps each concept independently
verifiable.

### 2.2 Every exporter already receives a JSON side-file

No new command-line arguments are needed:

| Exporter | Argument | Produced by |
| --- | --- | --- |
| IDA | `--mapping` (`ida-mapping-v1`, SHA-256 checked) | `adapters/ida.py:69` `_mapping_manifest` |
| angr | `--layout` | `adapters/angr.py:143` `_layout` |
| Ghidra | `--layout` | `adapters/ghidra.py:269` `_layout` |

angr and Ghidra both call their argument `--layout` but build it from **separate
functions**, so the field must be added in both; they are not a shared document.

### 2.3 The IDA manifest validates an exact key set

`adapters/ida/export_analysis.py:209` rejects the manifest unless
`set(mapping) == {"schema_version", "input", "runs"}`. Adding a key without
relaxing that check makes the exporter reject its own manifest. Producer and
consumer must change together, in one commit.

### 2.4 angr already filters by range

`adapters/angr/export_analysis.py:182` derives `executable` from the layout's
executable sections, passes it to `CFGFast(regions=...)`, and skips functions
failing `in_executable(address)` at line 199. Scoping angr means narrowing that
existing set, not adding a mechanism.

This also means angr's scoping is **not merely a reporting filter** — `CFGFast`
genuinely restricts recovery. See §5.

### 2.5 The other two filter points are single loops

- IDA: `adapters/ida/export_analysis.py:469`, `for address in idautils.Functions():`
- Ghidra: `adapters/ghidra/ExportAnalysis.java:455`, the `FunctionIterator` loop
  that already skips entries failing `getEntryPoint().isMemoryAddress()`

## 3. Design

### 3.1 The profile field

```json
"analysis_scope": [
  { "start": 2085076, "end": 2088160 }
]
```

A list, because a subsystem's functions need not be contiguous. `start` is
inclusive, `end` exclusive; both are integers in the binary's own address space,
matching every other address in a profile. `end` must exceed `start`.

`profile-v1.json` sets `additionalProperties: false`, so the property must be
declared there. It is **not** added to `required`, so every existing profile
remains valid and unchanged.

A function is in scope when its **entry point** lies in any range. Entry point
rather than extent, because that is the address the source map and the ledger key
on, and because a function straddling a boundary should be analyzed whole or not
at all rather than truncated.

### 3.2 Producers

Each of the three producer functions in §2.2 copies the profile's
`analysis_scope` into the document it writes, omitting the key entirely when the
profile has no scope. Omission rather than an empty list, so that "no scope"
and "a scope matching nothing" stay distinguishable — the latter is almost
always a bug.

### 3.3 Consumers

Each exporter skips a function whose entry point is outside the scope, when the
scope is present. When it is absent, behaviour is byte-for-byte what it is today.

`adapters/ida/export_analysis.py:209`'s key-set check gains the optional key.

### 3.4 Recording the scope in the output

The emitted analysis records the scope it was produced under. Without this a
scoped analysis is indistinguishable from a whole-binary one, and a later reader
cannot tell "this function does not exist" from "this function was not looked
at" — a distinction the reconstruction ledger depends on.

`analysis-v1.json` also sets `additionalProperties: false`, so this cannot be a
new top-level key. It belongs under the existing `extensions` property, whose
`$defs/extensions` is an open object (`propertyNames` a non-empty string,
`additionalProperties: {}`) — **so recording the scope needs no schema change at
all.**

Each adapter currently writes its own namespace there: `extensions.ida`,
`extensions.angr`, `extensions.ghidra`. The scope instead goes in a shared
`extensions.binrecon` object, identical across all three:

```json
"extensions": {
  "binrecon": { "analysis_scope": [ { "start": 2085076, "end": 2088160 } ] },
  "ida": { ... }
}
```

Shared rather than per-analyzer, so a reader checks one location regardless of
which analyzer produced the document, and so consensus code can compare the three
analyzers' scopes for equality — a mismatch means the adapters disagreed about
what they were asked to do, which is worth catching.

Omitted entirely when the profile has no scope, per §3.2.

## 4. Verification

**The decisive check is the currently-failing run.** The kernel's 24 method
implementations run from `0x1fd0d4` (2085076) to `0x1fdcd4` (2088148), that last
value being the *entry point* of `-[IOPCMCIATuple data]`. Because `end` is
exclusive (§3.1), the scope must extend past it — `{"start": 2085076,
"end": 2088160}` covers all 24 and is the value the kernel profile carries.
A scope ending at 2088148 would silently drop the final method, which is exactly
the off-by-one §5 warns about.

With that scope, `binrecon analyze` on
`C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86` must reach
`complete: true` with all three analyses published, and IDA and Ghidra must each
report the 24 methods whose implementation addresses were already recovered
independently from Objective-C metadata by `binrecon.macho.objc_method_index`.

That cross-check is strong: two analyzers discovering function boundaries by
disassembly, agreeing with a third source derived from runtime metadata.

**The regression check matters as much.** Every existing profile omits
`analysis_scope`, and all three adapters must produce output identical to today
for them. The three completed driver reconstructions
(`drvPCIBus`, `drvPCMCIABus`, `drvEISABus`) and the two Intel bus drivers depend
on it. Re-running an existing driver profile and diffing its published analyses
against a pre-change run is the concrete form of this check.

**Unit-level:** scope parsing and the in-scope predicate are testable without an
analyzer. The full suite must stay green; it was 659 passed, 4 skipped at the
time of writing, though another agent adds tests concurrently, so judge the delta.

## 5. Failure modes

**A scope bug that silently narrows an unscoped run** would produce a passing
analysis containing few or no functions — the most dangerous outcome here,
because `complete: true` would look like success. The absent-field regression
check in §4 is the guard, and the §3.2 omit-when-absent rule keeps the
"no scope" path from ever constructing an empty range.

**angr's scoping changes recovery, not just reporting** (§2.4). `CFGFast` given
`regions=` will resolve control flow leaving the scope differently than a
whole-binary run would. This is acceptable for scoped reconstruction but must be
recorded in the consuming effort's divergence document rather than discovered
later as an unexplained analyzer disagreement.

**Ghidra is Java** — the only adapter needing a compile step, and the one whose
change is hardest to test in isolation.

**A scope that matches nothing** should fail loudly rather than publish an empty
analysis. Treat zero in-scope functions as an error.

**Entry-point semantics are a deliberate choice** (§3.1). A caller who computes a
range from a symbol's address and size, then expects a function ending exactly at
`end` to be included, will be off by one. The inclusive/exclusive convention is
stated in the schema description for that reason.

## 6. Sequencing

**Phase 0 — schema and profile.** Declare `analysis_scope` in `profile-v1.json`,
load it in `profile.py`, and unit-test parsing plus the in-scope predicate.

*Verify:* existing profiles still validate; a profile with a scope round-trips.

**Phase 1 — IDA.** Producer, the §2.3 key-set relaxation, and the line 469 filter,
in one commit since the manifest is self-validating.

*Verify:* the kernel run gets past the size failure and publishes an IDA analysis
containing the 24 expected addresses.

**Phase 2 — angr.** Narrow the existing `executable` set.

*Verify:* published angr analysis is scoped; an unscoped driver profile is
unchanged.

**Phase 3 — Ghidra.** The `FunctionIterator` filter.

*Verify:* published Ghidra analysis contains the 24 expected addresses.

**Phase 4 — end to end.** Full `binrecon analyze` on the kernel, plus the
unscoped-regression check against a completed driver profile.

*Verify:* `complete: true`, three analyses published, IDA and Ghidra both
reporting the 24 methods, and an existing driver profile's output unchanged.

## 7. Deliverables

- `analysis_scope` in `tools/binrecon/binrecon/schema/profile-v1.json` and
  `tools/binrecon/binrecon/profile.py`
- Scope emitted by `adapters/ida.py` `_mapping_manifest`, `adapters/angr.py`
  `_layout`, and `adapters/ghidra.py` `_layout`
- Scope honoured by `adapters/ida/export_analysis.py`,
  `adapters/angr/export_analysis.py`, and `adapters/ghidra/ExportAnalysis.java`
- The scope recorded in the emitted analysis (§3.4)
- Tests for parsing, the predicate, and the absent-field regression
- `tools/binrecon/profiles/kernel-driverkit.json` gains the kernel's scope
