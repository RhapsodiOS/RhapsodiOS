# IONDRVSupport Measurement Design

**Date:** 2026-07-28
**Reference:** `C:/Users/raynorpat/Downloads/test/Drivers/ppc/IONDRVSupport.config/IONDRVSupport_reloc`
**Source:** `src/driverkit-3/libDriver/ppc/` — five files, see `IONDRVSupport/findings.md` §4

## 1. Goal

Measure Apple's shipped PowerPC `IONDRVSupport` against its in-tree source and
produce the map, ledger, findings and a verified gap list.

**This spec writes no function bodies.** The gaps fall into four largely
independent subsystems, each of which gets its own spec afterwards. This one
establishes the measurement they will be written against.

### 1.1 Why it is decomposed

The unscoped gap is **16,276 bytes across 45 C functions — 42% of `__text`** —
plus 8 Objective-C methods. For comparison, the three drivers reconstructed
before it had gaps of 6, 5 and 5 functions.

The clusters barely interact:

| Cluster | Functions | Bytes | What it is |
| --- | --- | --- | --- |
| PEF / PCode loader | 25 | 12,060 | `_PEF_OpenContainer`, `_UnpackPartialSection`, `_Instantiate`, `_SatisfyImports` — the Preferred Executable Format loader that instantiates Mac OS NDRV drivers |
| IXMicro acceleration | 7 | 1,948 | `_ixDoBlit`, `_ix3dDoFill`, `_ix3dInterruptHandler` |
| ATI Mach64 acceleration | 5 | 1,420 | `_m64Init`, `_m64DoBlit`, `_m64DoFill` |
| Name Registry shims | 8 | 848 | `__eRegistryEntryIterate`, `__eLMGetPowerMgrVars` |

Every real defect found in this series was caught by a reviewer re-disassembling
the whole change. At 16 KB in one plan that stops being feasible and review
degrades into reading summaries — which is how the address-0 misreading survived
five specs. Splitting keeps each review at a size someone can actually re-derive.

**These counts come from an unscoped run (§3) and are predictions, not inputs.**
The implementation must re-derive them.

## 2. What the binary contains

`__text` is 38,852 bytes across **192 defined `__TEXT,__text` symbols**, verified
via `binrecon.macho.read_macho`.

### 2.1 Classes

```
IONDRVFramebuffer : IOFramebuffer
IOOFFramebuffer   : IOFramebuffer
IOATINDRV         : IONDRVFramebuffer
IOIX3DNDRV        : IONDRVFramebuffer
IOIXMNDRV         : IONDRVFramebuffer
IONDRVSupportVersion              : IODevice   (build-generated)
IONDRVSupportKernelServerInstance : Object     (build-generated)
```

`IOFramebuffer` is the superclass of two of them but is **not** defined in this
binary — it belongs to another. That matters for §3.

**Read ivars from `__OBJC,__instance_vars` during the work**, never by inference.

## 3. The source-scoping problem

**This is the first driver in the series with no dedicated source directory.**
Its sources sit in `src/driverkit-3/libDriver/ppc/` alongside at least three other
binaries' sources.

Three of that directory's eleven `.m` files contribute:

| File | Lines | C definitions | Selectors |
| --- | --- | --- | --- |
| `IONDRVLibraries.m` | 1,116 | 54 | 0 |
| `IONDRVFramebuffer.m` | 2,113 | 8 | 48 |
| `IONDRVInterface.m` | 281 | 5 | 0 |

The other eight belong elsewhere. `IOFramebuffer.m` (1,903 lines) alone
contributes 11 coincidental selector matches — `open`, `free` and similar — because
it is the superclass; `IODeviceTreeBus.m`, `IOMacRiscPCI.m`, `IOPropertyTable.m`
and `IOSmartDisplay.m` add four more.

Run at directory granularity, `selector_check.py` reports **183 extra** and is
useless as a gate.

### 3.1 The fix: teach the checkers to take a file

`source_definitions()` in `tools/binrecon/symbol_name_check.py` does
`Path(source_dir).rglob("*")`, which yields **nothing** for a file path — verified:

```
given a FILE path : 0 definitions
given its DIR     : 152 definitions
```

**Silently returning zero is the dangerous shape**: a scoped gate would read green
while measuring nothing. Extend `source_definitions()` and `selector_check.py` to
accept a file path as well as a directory, with tests, and make the zero case
impossible to reach silently.

`binrecon source-map`'s `--source-dir` is repeatable; confirm whether it accepts a
file, and if not, whether it needs the same treatment or whether repeating it over
the three files suffices.

This is a durable improvement — every future driver whose source is shared needs
it.

### 3.2 The file list is a prediction, not an input

The three-file list above was derived by matching source definitions against the
binary's symbol names. **That method has produced six wrong answers in this
series**, including one that reported this very driver as having no source at all.

Re-derive the list, and cross-check it against the map's own `source_path` values
once the map exists. If a fourth file contributes, say so.

## 4. The Registry exception — the rule inverts here

Eight functions carry a **double** underscore in the binary:

```
__eRegistryEntryIterateCreate    __eRegistryCStrEntryToName
__eRegistryEntryIterateDispose   __eRegistryCStrEntryCreate
__eRegistryEntryIterate          __eGetInterruptFunctions
__eInstallInterruptFunctions     __eLMGetPowerMgrVars
```

Under the Mach-O ABI the compiler prepends exactly one underscore, so a symbol
`__eRegistryEntryIterate` means Apple's source wrote **`_eRegistryEntryIterate`** —
a legitimate leading underscore.

**The rule applied to five drivers today must not be applied to these eight.**
Five specs in a row have stripped a leading underscore from every C name; that
reflex is wrong here, and `symbol_name_check.py` will correctly report these as
"missing" against a bare spelling that must never be written.

Record the exception explicitly in `findings.md`, and check whether the checker
needs to distinguish "source name legitimately starts with `_`" from "source name
is over-underscored" before a later spec writes these eight.

## 5. The function at `__text` offset 0

`-[IONDRVFramebuffer doControl:params:]` sits at `__text+0`. Its first word is
`7c0802a6` (`mflr r0`) — real code. IDA's function list will have no entry there.

`ppc_invariant_check` will report it as "not a function start", which means only
that IDA's list lacks an entry. It is **not** evidence of an absent body. The
opposite reading was recorded across five earlier specs in this series and
retracted in 22 places.

Unlike Floppy — where the address-0 function was a C function — this one **is** an
Objective-C method, so `selector_check.py` can confirm it once §3.1's scoping fix
lands.

## 6. Method

### 6.1 Profiles

Create `iondrvsupport-ppc.json` and `iondrvsupport-bundle-ppc.json` following
`tools/binrecon/profiles/mesh-ppc.json`, changing only `name` and `output_dir`,
and add both to `test_ppc_profile_inventory`, which asserts the full sorted list.
They sort between `iodisplay-ppc.json` and `mace-bundle-ppc.json`.

`binrecon analyze` **exits 1 for any reference-only profile** — `cli.py:105`
returns 0 only when acceptance passes, and a profile with no `rebuilt` binary has
nothing to compare. What matters is that the run reports `analysis complete` and
publishes its output.

### 6.2 Mapping

Use the route proven on `SCSIServer`, `PPCSerialPort` and `Floppy`:

1. `filter_named_functions.py` over the reference analysis, to drop IDA's unnamed
   jump islands
2. `source-map` with `--objc-methods` and **without** `--scope-to-objc`, scoped to
   the three files of §3

Scope validation must consider all four categories — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed` — not `mapped ∪ unmapped` alone.

### 6.3 Establish presence by a definition site

Never by an occurrence count, never by a regex over declaration syntax, never by
`find | head -1`. Six ad-hoc surveys in this series were recorded as measurement
and every one had to be retracted.

## 7. Artifacts

To `src/drivers-ppc/reconstruction/IONDRVSupport/`, matching the eleven drivers
already there, even though the source lives under `driverkit-3`.

- `source-map.json`
- `ledger.json`
- `findings.md`

## 8. Acceptance

1. Two profiles created and `test_ppc_profile_inventory` updated; suite green.
2. `source_definitions()` and `selector_check.py` accept a file path, with tests;
   the silent-zero case is unreachable.
3. The scoped file list re-derived independently and cross-checked against the
   map's `source_path` values.
4. The source map built over the scoped files, with every `unmapped`,
   `duplicate_candidates` and `boundary_disputed` entry explained.
5. `selector_check.py`'s `extra` count falls from its unscoped 183 to the
   irreducible remainder, and every remaining entry is enumerated with its
   disposition. **Amended after Task 3: "0 extra" is unachievable and was the
   wrong target.** 12 remain — 8 `IOATIMACH64NDRV` and 1 `IOATIRAGE128NDRV`
   methods, because our tree splits the binary's flat `IOATINDRV` into a base
   class plus subclasses, and 3 methods with no symbol-table counterpart. That is a
   class-hierarchy divergence to record, not a scoping failure to fix; the
   classes live in `IONDRVFramebuffer.m`, which is unambiguously in scope, so no
   file-level scoping can change the count.
6. `-[IONDRVFramebuffer doControl:params:]` recorded as a known exclusion per §5 —
   not a gap, not a phantom — and confirmed present by `selector_check.py`.
7. Bucket reconciliation reports `RECONCILES: yes`, with the two build-generated
   class methods accounted for.
8. The ledger seeded against the final map, with every citation verified.
9. The four clusters of §1.1 enumerated in `findings.md` with each function's
   address and size, so the follow-on specs can be written from evidence.
10. The Registry `__e*` exception recorded per §4, with a note on whether the
    checker needs to distinguish the two underscore cases.
11. The binrecon suite stays green.

## 9. Constraints

- **No PowerPC toolchain and no host C compiler. Nothing compiles, and no claim of
  buildability may be made** — only of correspondence to the binary.
- **Write no function bodies and rename nothing.** This spec measures.
- Do not modify `src/kernel-7/`.
- Do not modify any source under `src/driverkit-3/` — the follow-on specs do that.
- Commits: `binrecon: ` for the tooling change, `drivers-ppc: ` for the artifacts.
  One to two lines, no metadata or trailers.
- **Work in a dedicated worktree.** Several worktrees are active in this
  repository, and a shared git index lets parallel sessions overwrite each
  other's commits.

## 10. Risks

- **The scoped file list is the spec's foundation and it is my own derivation.**
  §3.2 requires it be re-derived and cross-checked; if it is wrong, every count
  downstream is wrong.
- The counts in §1.1 come from an unscoped run and will move once scoping lands.
  They are predictions.
- `IOPEFInternals.h` (937 lines) already declares the PEF structures. Whether they
  match the binary is a question for the PEF spec, not this one — do not
  investigate it here beyond noting the file exists.
- Five specs of reflex point the wrong way on §4's eight Registry functions.
