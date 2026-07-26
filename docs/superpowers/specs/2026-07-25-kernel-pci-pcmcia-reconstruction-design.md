# Binary reconstruction of the kernel PCI and PCMCIA DriverKit layer

Reconstruct the five `libDriver` modules that implement DriverKit's PCI and
PCMCIA support against Apple's shipped DR2 i386 kernel, using the
`tools/binrecon` toolchain. This requires teaching binrecon to read linked
executables and to anchor a source map on Objective-C runtime metadata rather
than on a symbol table.

This continues
[2026-07-25-intel-bus-driver-binary-reconstruction-design.md](2026-07-25-intel-bus-driver-binary-reconstruction-design.md),
which reconstructed `Intel824X0PCI` and `Intel82365PCMCIA`. Those drivers call
directly into this layer — `getPCIConfigData:atRegister:` and
`setPCIConfigData:atRegister:` are the methods `Intel824X0.m` uses, and
`getPCIdevice:function:bus:` is what the newly written `PCIC_PCI` calls — so
verifying it closes the loop under that work.

## Motivation

Nothing has ever checked our DriverKit PCI/PCMCIA layer against Apple's. A
symbol-level comparison done while scoping this work found that our kernel is
missing three of the five modules outright (§2.1), which means the PCMCIA half of
the driver stack we just reconstructed sits on code that is not being built.

## 1. Scope

### 1.1 Targets

| Reference | Path | Size |
| --- | --- | --- |
| Apple DR2 i386 kernel | `C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86` | 1404116 |

Our sources, all under `src/driverkit-3/libDriver/`:

| Module | Classes and categories in the reference | Methods |
| --- | --- | --- |
| `pci/IOPCIDirectDevice.m` | `IODirectDevice(IOPCIDirectDevice)` | 10 (5 class, 5 instance) |
| `pci/IOPCIDeviceDescription.m` | `IOPCIDeviceDescription`, `(Private)` | 3 |
| `pcmcia/IOPCMCIADirectDevice.m` | `IODirectDevice(IOPCMCIADirectDevice)` | 2 |
| `pcmcia/IOPCMCIADeviceDescription.m` | `IOPCMCIADeviceDescription`, `(Private)` | 4 |
| `pcmcia/IOPCMCIATuple.m` | `IOPCMCIATuple`, `(Private)` | 5 |

Twenty-four methods, whose implementations occupy a contiguous region from
`0x1fd0d4` to the last entry point at `0x1fdcd4` — roughly 3 KB of code. Our five
sources total about 21 KB.

The five class methods all belong to `IODirectDevice(IOPCIDirectDevice)`, and one
selector — `isPCIPresent` — exists as **both** a class and an instance method at
different addresses. Any walk that follows only instance method lists undercounts
by five and misses the region's true start; the metadata walk must follow a
class's metaclass method list and a category's class-method list as well.

The reference kernel's SHA-256 is
`BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`.

### 1.2 Out of scope

The rest of the kernel. Only these five modules are reconstructed; the source map
covers their functions, not the kernel's other ~4100 symbols.

The PPC kernel (`mach_kernel`, 2983828 bytes) is big-endian and is not a
comparison target for this i386 work.

Diagnosing why our build omits the three PCMCIA modules (§2.1) is tracked
separately — see §5. No boot testing and no QEMU run.

## 2. Findings that shaped this design

From direct Mach-O parsing during scoping, before any analyzer run.

### 2.1 Our kernel is missing the entire PCMCIA half

Comparing the `__OBJC,__class_names` pools:

| Module | Apple's kernel | Ours |
| --- | --- | --- |
| `IOPCIDeviceDescription.m` | present | present |
| `IOPCIDirectDevice.m` | present | present |
| `IOPCMCIADeviceDescription.m` | present | **absent** |
| `IOPCMCIADirectDevice.m` | present | **absent** |
| `IOPCMCIATuple.m` | present | **absent** |

Apple's kernel also defines `.objc_class_name_IOPCMCIADeviceDescription`,
`.objc_class_name_IOPCMCIATuple`, and the three PCMCIA category symbols. Ours
defines none of them.

This is a build failure, not missing source. All three `.m` files exist in
`src/driverkit-3/libDriver/pcmcia/`; `pcmcia_BUS_MFILES` lists all three;
`i386_KERN_MFILES` includes that variable; and `KERNEL_DIRS` puts `pcmcia` on the
VPATH. Why the objects never reach the kernel could not be determined without a
build.

One real but unrelated bug surfaced while checking: `SOURCE_DIRS` at
`src/driverkit-3/libDriver/Makefile:46` omits `pcmcia` where every other list
includes it. That variable feeds only the `tags` and `installsrc` targets
(lines 378 and 394), so it breaks source installation, **not** compilation. It is
not the cause and is recorded here only so it is not rediscovered.

### 2.2 The kernel has no method symbols — this is the design's central problem

The reference kernel's symbol table contains exactly eight PCI/PCMCIA symbols,
all `.objc_class_name_*` or `.objc_category_name_*` absolutes at address 0. There
is not one `-[IOPCMCIATuple data]`-style entry.

This differs fundamentally from the driver `_reloc` files, which carried a named
symbol per method and let `binrecon source-map` anchor address-to-name directly.
A linked executable does not name individual Objective-C method
implementations.

Address-to-name for the kernel is recoverable only from the Objective-C runtime
metadata: walk `__OBJC,__module_info` to each module's symtab, then to its class
and category definitions, then to their method lists, each entry of which is a
`(selector pointer, types pointer, IMP)` triple. This was proven during scoping
and produced the table in §1.1 including every IMP address.

### 2.3 Synthesized names must match the source-side key format exactly

`source_map.source_sites` builds its lookup keys as
`f"{sign}[{current_class} {selector}]"`, where `sign` is `-` or `+` and
`current_class` is `Name` or `Name(Category)` — for example
`-[IOPCMCIATuple data]` and
`-[IODirectDevice(IOPCIDirectDevice) setPCIConfigData:atRegister:]`.

`defined_symbols` yields exactly this shape from a driver's symbol table, which
is why the two sides join. Names synthesized from `__OBJC` metadata must
reproduce it character for character, including the category parenthesisation and
the trailing colons of a keyword selector. Instance methods take `-`; methods
found on a class's metaclass or in a category's class-method list take `+`.

### 2.4 binrecon rejects linked executables

`binrecon/macho.py:132` accepts only `MH_OBJECT`, `MH_PRELOAD` and `MH_BUNDLE`.
Both i386 kernels are `MH_EXECUTE` (file type 2), so `validate`, `analyze` and
`source-map` all fail at the front door.

Accepting the new file type is a one-line change, but a linked executable's
layout differs from a relocatable object in ways the rest of the reader must
tolerate: it carries a `__PAGEZERO` segment with a 4096-byte `vmsize` and no file
content, and its segments carry real virtual addresses rather than starting at
zero. Both must be verified rather than assumed.

## 3. The tooling changes

### 3.1 `MH_EXECUTE` support in `macho.py`

Add the file type to the accepted set. Verify the existing section and symbol
extraction handles a zero-file-size segment and non-zero segment addresses, and
fix what does not.

### 3.2 An Objective-C method index in `macho.py`

Add a function that, given a path, returns `{address: sorted([names])}` for every
Objective-C method implementation in the image, with names in the §2.3 format.

It is a **separate function, not an addition to `read_macho`'s document.** The
document carries a `schema_version` and is validated; adding a key risks breaking
that validation for every existing caller, and no existing caller needs the
index. This is the smaller change and the one that cannot regress the drivers.

### 3.3 A scoped analysis, to satisfy the exact-partition rule

`schema._validate_source_map_context` requires **exact set equality** between the
source map's addresses and the reference analysis's functions
(`schema.py:253`); anything else raises `source map partition mismatch`. A
19-method map validated against a whole-kernel analysis would therefore be
rejected with thousands of missing addresses.

The resolution is to scope the *analysis*, not to weaken the validator. Derive a
filtered analysis document from the published one, retaining only the functions
belonging to the five modules, and validate the source map against that.

This is sound because:

- `validate_analysis_semantics` iterates `document["functions"]` and validates
  each record independently. It does not require the function list to cover
  `__TEXT,__text`, so a filtered document is still a valid `analysis-v1`.
- `input.sha256` is untouched, so the map's `reference_sha256` still matches the
  real kernel identity and the loader's hash check still binds the map to the
  actual binary.
- The exact-partition guarantee survives *within the declared scope*, which is
  the property worth keeping. Relaxing the validator would weaken a check that
  has protected three completed reconstructions.

The filter is driven by the IMP set recovered by the §2.2 metadata walk — whose
result is tabulated in §1.1 — rather than by a hand-typed address list, so it
cannot silently drift from the metadata.

### 3.4 Wiring it into the builder

`source_map.build_source_map` calls `defined_symbols(macho_document)` once and
consults it per address. The new index merges into that same mapping, so a
kernel-derived name and a symbol-table name are indistinguishable downstream.

The merge must be additive: where both sources name an address, keep both names
rather than preferring one. That preserves the existing driver behaviour exactly
and is what the `duplicate_candidates` bucket exists to surface.

## 4. The two passes

Unchanged in shape from the driver effort.

**Report pass.** Analyze the reference kernel; build `source-map.json` scoped to
the 24 methods; disassembly-diff each against our source; write `divergences.md`
and a `ledger-v1` ledger. A function that matches gets the strongest status the
evidence supports; a function that diverges stays `unexamined` and is written up.

**Fix pass.** Apply the findings. Ledger statuses advance to the level the new
evidence supports, or become `intentional-mismatch` with a reason and reviewer.

**Artifacts**, per the established layout:

```
src/driverkit-3/libDriver/reconstruction/
    source-map.json
    ledger.json
    divergences.md
```

One profile at `tools/binrecon/profiles/kernel-driverkit.json`, reference-only,
`output_dir` `../out/kernel-driverkit`.

## 5. Failure modes

**The source map is partial by design — resolved, see §3.3.** Every prior source
map partitioned every function in its binary; this one covers 24 methods out of a
1.4 MB kernel. `load_source_map` does require an exact partition, so the scoping
is expressed by filtering the *analysis* rather than by loosening the check. The
residual risk is that the filter's address range is drawn wrongly and silently
omits a method, which the §6 Phase 0 check against the §1.1 IMP list is there to
catch.

**Analyzer cost.** The kernel is 1.4 MB against the drivers' 28–39 KB. IDA,
Ghidra and angr will take substantially longer, and angr's `CFGFast` will produce
far more noise. The 900-second timeouts in the existing profiles may need
raising.

**No method symbols means no independent check on the metadata walk.** For the
drivers, the symbol table corroborated every mapping. Here the `__OBJC` walk is
the only source of truth, so a bug in it produces confidently wrong mappings.
Cross-check the recovered IMPs against the analyzers' independently discovered
function boundaries; they should coincide.

**The PCMCIA half cannot be parity-checked against our kernel** until the build
gap in §2.1 is closed, because those three modules are absent from our binary.
The report pass is unaffected — it compares Apple's binary against our source.

**Struct-return and calling-convention assumptions** carried over from the driver
work remain unverified without a build host.

## 6. Sequencing

**Phase 0 — tooling.** `MH_EXECUTE` acceptance, the Objective-C method index, the
analysis scoping of §3.3, and the builder wiring, each test-first.

*Verify:* the existing suite stays green (currently 650 passed, 4 skipped);
`binrecon validate` resolves the kernel and prints its identity; the new index
reproduces the 24 methods and IMPs recorded in §1.1, including the five class methods.

**Phase 1 — analysis.** Run the three analyzers over the reference kernel.

*Verify:* `complete: true`, a populated `published/`, and IDA/Ghidra function
boundaries that coincide with the §1.1 IMPs.

**Phase 2 — report pass.** Source map, disassembly diff, `divergences.md`,
ledger.

*Verify:* `load_source_map` passes; all 24 methods carry a ledger entry.

**Phase 3 — fix pass.** Apply the findings.

*Verify:* the three §4 checks from the driver effort, to the extent a build host
allows.

**Phase 4 — the build gap.** Record what is known about §2.1 in the divergence
document and decide whether fixing it belongs here or in its own effort. Fix the
`SOURCE_DIRS` omission, which is independent and safe.

## 7. Deliverables

- `src/driverkit-3/libDriver/reconstruction/{source-map.json,ledger.json,divergences.md}`
- `tools/binrecon/profiles/kernel-driverkit.json`
- `MH_EXECUTE` support and the Objective-C method index in `binrecon.macho`,
  wired into `binrecon.source_map`, with tests
- Analysis scoping (§3.3), so a source map may cover a declared subset of a large
  binary without weakening the exact-partition check, with tests
- `src/driverkit-3/libDriver/Makefile` `SOURCE_DIRS` corrected
