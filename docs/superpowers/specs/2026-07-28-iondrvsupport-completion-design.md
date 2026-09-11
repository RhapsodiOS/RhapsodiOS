# IONDRVSupport Completion Design

**Date:** 2026-07-28
**Reference:** `C:/Users/raynorpat/Downloads/test/Drivers/ppc/IONDRVSupport.config/IONDRVSupport_reloc`
**Source:** `src/driverkit-3/libDriver/ppc/` — five files, see §2.1
**Predecessor:** [2026-07-28-iondrvsupport-measurement-design.md](2026-07-28-iondrvsupport-measurement-design.md)

## 1. Goal

Close out `IONDRVSupport`: verify the 20 inherited function bodies against the
reference, correct the 12 over-underscored names, flatten the ATI class split to
match the binary, remove three duplicate definitions, and write the one genuinely
absent function.

The measurement spec that precedes this one predicted 45 missing C functions and
proposed decomposing the follow-on work into four sub-projects. The measurement
reduced that to **one** genuine absent-source gap; this single spec replaces all
four.

## 2. What the measurement established

Not re-litigated here. Re-derive anything you doubt, but do not spend the spec's
budget reproducing it.

- Map: **165 mapped, 23 unmapped, 3 duplicate_candidates, 0 boundary_disputed**
  = 191, the full named-function count. `RECONCILES: yes`. Ledger 191 entries,
  165 citations verified.
- `-[IONDRVFramebuffer doControl:params:]` sits at `__text+0` with real code
  (`7c0802a6`) and no IDA entry — a known exclusion, not a gap, not a phantom.
- The `symbol_name_check.py` scanner has since been fixed (two defects: a name's
  first character eaten at column 0, and a 4-line brace lookahead). The gate now
  reports **124 hand-written C symbols, 13 missing** — the 12 of §4 plus
  `_eLMGetPowerMgrVars` of §7.

### 2.1 The five contributing files

`IONDRVFramebuffer.m`, `IONDRVLibraries.m`, `IONDRVInterface.m`,
`IOPEFInternals.c`, `IOPEFLoader.c` — five of the seventeen `.m`/`.c` files in
`src/driverkit-3/libDriver/ppc/`. The other twelve belong to other binaries.

This is the only driver in the series without a dedicated source directory. Scope
every checker to these five files; a directory argument silently pulls in three
other binaries' sources.

## 3. Verification comes first, and may halt this spec

Commit `6f3d886c` ("driverkit: Add hardware blit and fill code for Mach64, Rage
128, and IMS video cards for PPC") wrote **20 function bodies**:

- the 8 `IOATIMACH64NDRV` methods, 996 bytes of reference extent
- the 12 blit/fill functions of §4, 3,000 bytes

**These are in-repo reconstruction, not recovered Apple source, and none has ever
been compared against the disassembly.** Apple's own `.m` implements only
`IOATINDRV`, with the single method `getStartupMode:depth:`.

Verify each of the 20 instruction-by-instruction against the reference **before
anything is renamed or moved**. Resolve every `bl` through the island's HI16/LO16
relocation pair; account for every branch.

**If they diverge materially, stop and report.** Rewriting 4 KB of bodies is a
different spec from renaming them, and this one is scoped for renaming. Halting
is a correct outcome, not a failure — the same condition the SCSIServer spec's
MIG check carried, and it exists so a bad result cannot be absorbed silently.

A body existing is not a body being correct. That distinction has caught a real
defect in every driver in this series.

## 4. The twelve over-underscored functions

All `static` in `IONDRVFramebuffer.m`, all emitting a doubled underscore:

| Source (wrong) | Binary symbol | Line |
| --- | --- | --- |
| `_m64WaitForIdle` | `_m64WaitForIdle` | 1227 |
| `_m64WaitForFIFO` | `_m64WaitForFIFO` | 1245 |
| `_m64Init` | `_m64Init` | 1270 |
| `_m64DoFill` | `_m64DoFill` | 1341 |
| `_m64DoBlit` | `_m64DoBlit` | 1368 |
| `_ixDoBlit` | `_ixDoBlit` | 1628 |
| `_ixDoFill` | `_ixDoFill` | 1637 |
| `_ixIdleEngine` | `_ixIdleEngine` | 1674 |
| `_ix3dDoBlit` | `_ix3dDoBlit` | 1870 |
| `_ix3dDoFill` | `_ix3dDoFill` | 1879 |
| `_ix3dIdleEngine` | `_ix3dIdleEngine` | 1897 |
| `_ix3dInterruptHandler` | `_ix3dInterruptHandler` | 1959 |

The Mach-O ABI prepends exactly one underscore, so `_m64WaitForIdle` in source
emits `__m64WaitForIdle`, which this binary has never contained. Apple's spelling
was `m64WaitForIdle`.

Line numbers are pre-change; locate by name.

### 4.1 The hazard that makes this rename different

**This is the first driver in the series carrying both underscore cases at once,
in the same file.**

Alongside the twelve above, the binary carries **59 `__e*` symbols** whose
leading underscore in source is **correct**. The family is much broader than the
Registry — it spans Registry entry iteration, ATI helpers, and the absolute-time
routines: `__eRegistryEntryIterate`, `__eRegistryCStrEntryCreate`,
`__eATIIsAllInOne`, `__eATISetMBRES`, `__eAbsoluteToNanoseconds`,
`__eAddAbsoluteToAbsolute`, `__eGetInterruptFunctions`,
`__eInstallInterruptFunctions`, and `__eLMGetPowerMgrVars` of §7, among others.

Each is written `_eRegistryEntryIterate` in source and emits
`__eRegistryEntryIterate`, which is exactly what the binary carries. **58 of the
59 map on that spelling today**; the 59th is §7's, the only one absent.

Five earlier specs stripped a leading underscore from every C name. **Applying
that reflex to the `_e*` family would break 58 working functions** — nearly half
this binary's hand-written C surface, and almost five times the number this spec
is meant to rename.

The rename must be driven by the binary's exact symbol list, one name at a time,
word-bounded. A blanket transformation over `_[A-Za-z]\w*` is prohibited.

## 5. Flattening the ATI class split

The binary has a single flat `IOATINDRV : IONDRVFramebuffer` carrying nine
methods. Our tree splits it into `IOATINDRV` plus `IOATIMACH64NDRV` and
`IOATIRAGE128NDRV`, so eight symbols Apple never emitted are emitted, and
`selector_check.py` reports 12 `extra` that no scoping can remove.

The history, verified against `git show 19ffee9a`:

- Apple's Darwin 0.3 header **does** declare `@interface IOATIMACH64NDRV : IOATINDRV` — but empty.
- Apple's `.m` has **no** `@implementation IOATIMACH64NDRV` at all.
- `IOATIRAGE128NDRV` is **not** Apple's; `6f3d886c` added it.

**The decision, taken during design:**

1. **Move the eight bodies into `IOATINDRV`**, so the source emits the symbols
   Apple shipped.
2. **Keep Apple's empty `IOATIMACH64NDRV` declaration** in the header. It is
   genuinely Apple's and costs nothing.
3. **Leave `IOATIRAGE128NDRV` alone.** Added hardware support is a separate
   question from symbol correspondence; deleting a working Rage 128 path to lower
   a count would be the wrong trade.

Expect `extra` to fall from 12 to about 3 — `IOATIRAGE128NDRV`'s method plus the
methods with no reference counterpart. Report the actual figure and enumerate
what remains.

**This step depends on §3.** If the eight bodies do not match the reference,
flattening moves wrong code into the right class. Do not proceed past a material
divergence.

## 6. The three duplicate definitions

`StdIntHandler`, `StdIntEnabler` and `StdIntDisabler` are each defined
**non-`static` in two files**:

```
IONDRVFramebuffer.m:602-612      IONDRVLibraries.m:809-819
```

Both are in the same link unit, so this is a **duplicate-symbol link error** —
not the benign `static`-shadows-`extern` pattern seen on Floppy. The binary
carries one symbol each.

Delete one copy. **The map's `source_path` for each symbol says which file
Apple's definition belongs to** — use that rather than choosing. Note that
`IONDRVLibraries.m:822-824` builds `TVector` structures from all three, so that
file needs at least declarations after the change.

Verify against the disassembly that the surviving body matches, rather than
assuming the two copies are identical.

## 7. The one absent function

`_eLMGetPowerMgrVars`, at `0x5fd8`, 136-byte span. The only symbol in this binary
with no definition site anywhere under `src/`.

**Its leading underscore is correct.** It belongs to the 59-strong `_e*`
family of §4.1, so the source name is `_eLMGetPowerMgrVars` and the emitted
symbol is `__eLMGetPowerMgrVars`. Writing it bare would be the defect this spec
otherwise exists to remove — the two cases sit three sections apart and point
opposite ways.

Span is a next-symbol delta and includes any trailing jump island; confirm the
true extent from its `blr`.

## 8. Disciplines

Each has caught a real defect in this series:

- Resolve every `bl` through `read_macho`'s relocation table — PowerPC jump
  islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export, and the real
  target comes from the **island's** HI16/LO16 pair.
- Read ivars from `__OBJC,__instance_vars`, never by inference.
- Trace every bare constant to a named in-tree constant before writing it as one.
- Account for every instruction and every branch in writing.
- Establish presence by a definition site — never an occurrence count, never a
  regex over declaration syntax.
- Verify a rename by a whole-file token-multiset diff, not a line-based check; a
  line-based check produced seven false positives on Floppy.
- **Reproduce Apple's *form*, not Apple's *defects*.** Where the reference is
  demonstrably buggy, keep correct behaviour and record `intentional-mismatch`
  with its evidence. Standing user ruling.
- A confident guess is a defect; a recorded uncertainty is a result.

## 9. Acceptance

1. All 20 inherited bodies verified against the reference instruction-by-
   instruction, with every branch accounted for — or the spec halted per §3 with
   the divergence reported.
2. The 12 renamed, driven by the binary's exact symbol list, word-bounded.
3. **No `_e*` function renamed.** All 58 that map today still emit their double
   underscore and still map; the 59th is §7's, written with its underscore.
4. `symbol_name_check.py` over the five scoped files reports **124 hand-written C
   symbols, 0 missing**, exit 0.
5. The eight ATI bodies moved into `IOATINDRV`; Apple's empty
   `IOATIMACH64NDRV` declaration retained; `IOATIRAGE128NDRV` untouched.
6. `selector_check.py`'s `extra` falls from 12, with every remaining entry
   enumerated and dispositioned.
7. The three duplicate definitions resolved, the surviving body verified against
   the disassembly, and `IONDRVLibraries.m`'s `TVector` construction still
   compiles in principle — declarations present.
8. `_eLMGetPowerMgrVars` written with its correct leading underscore, with an
   instruction-by-instruction account.
9. Map and ledger regenerated; `duplicate_candidates` falls to 0; buckets report
   `RECONCILES: yes`; every ledger citation verified against the new map.
10. `findings.md` updated with the verification result for all 20, the rename,
    the flattening, and the provenance of what `6f3d886c` contributed.
11. The binrecon suite stays green.

## 10. Constraints

- **No PowerPC toolchain and no host C compiler. Nothing compiles, and no claim
  of buildability may be made** — only of correspondence to the binary. Removing
  the duplicate removes a known link error; that is not a claim the tree links.
- Do not modify `src/kernel-7/`.
- Modify only the five files of §2.1 and the artifacts under
  `src/drivers-ppc/reconstruction/IONDRVSupport/`.
- Do not rename anything outside the 12 of §4.
- Commits: `driverkit: ` for source under `src/driverkit-3/`, `drivers-ppc: ` for
  the reconstruction artifacts. One to two lines, no metadata or trailers.
- **Work in a dedicated worktree.** Several worktrees are active in this
  repository, and another session has committed to `qemu-debug-loop` twice during
  this work.

## 11. Risks

- **The two opposite underscore cases in one driver.** §4.1 is the single most
  likely place for this spec to do damage: renaming an `_e*` shim would break a
  working function and the gate would not catch it, because the bare spelling
  would then be "missing" rather than wrong.
- **§3 may halt the spec.** That is by design, and the estimate assumes it does
  not — if the 20 bodies diverge, the remaining work is a rewrite, not a rename.
- The eight ATI bodies are moved on the strength of §3's verification. If that
  verification is shallow, §5 relocates unverified code into the class the binary
  says should hold it, which is worse than leaving it where it is.
- `IONDRVFramebuffer.m` is 2,113 lines and every part of this spec except §7
  touches it.
