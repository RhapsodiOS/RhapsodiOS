# Floppy Reconstruction Design

**Date:** 2026-07-28
**Reference:** `C:/Users/raynorpat/Downloads/test/Drivers/ppc/Floppy.config/Floppy_reloc`
**Source:** `src/drivers-ppc/ide/drvPPCSwimFloppy/Floppy.drvproj/Floppy.lksproj`

## 1. Goal

Measure Apple's shipped PowerPC `Floppy` driver against our source, correct a
symbol-naming defect in 136 of its 141 hand-written C functions, write the five
that are genuinely absent, and resolve three redundant duplicate definitions.

At 49,244 bytes and 203 symbols this is the largest driver measured in this
series — roughly 2.5× `PPCSerialPort`. But 136 of the 141 C functions and all 60
Objective-C methods already exist, so the work is comparable in size to
`PPCSerialPort`'s, not to the binary's.

### 1.1 The source was nearly missed

An earlier survey recorded this driver as having **no in-tree source**. That was
wrong: `find src -iname "*Floppy*" | head -1` returned
`src/driverkit-3/Examples/UnixDisk/FloppyDisk.m` — a 175-line DriverKit example —
and the real tree at `src/drivers-ppc/ide/drvPPCSwimFloppy` was never seen.

It holds **11,475 lines across its eight source files** — the four `.m` files hold
**10,754** of them — untouched since the tree move and never measured. (An earlier
draft attributed all 11,475 to the four `.m` files; §2.1's per-file figures below
sum to 10,758, not 11,475.) Its parameter names are `param_1`, `param_2`, so it
came out of a decompiler in an earlier session and was never cleaned up.

This is the fifth ad-hoc survey error in this series, and the reason §4.4 gates
on a tool rather than on a search.

## 2. What the binary contains

`__text` is 49,244 bytes (`0x0`–`0xc05c`) across **203 defined `__TEXT,__text`
symbols**, verified via `binrecon.macho.read_macho`.

| Origin | Count | Disposition |
| --- | --- | --- |
| Build-generated (`FloppyVersion`, `FloppyKernelServerInstance`) | 2 | Recorded and excluded |
| Hand-written Objective-C | 60 | All present; **52 misnamed** — see §3.2 |
| Hand-written C | 141 | 136 misnamed, 5 absent |

`2 + 60 + 141 = 203`. **201 functions are hand-written** — 60 Objective-C and 141
C. That 141-to-60 ratio drives the mapping decision in §4.3.

### 2.1 Classes

```
FloppyDisk           : IODisk           28 methods
FloppyDisk (Internal)                   21 methods
FloppyDisk (Thread)                     10 methods
FloppyController     : IODirectDevice    1 method
FloppyVersion        : IODevice          1 method   (build-generated)
FloppyKernelServerInstance : Object      1 method   (build-generated)
```

The source's file layout matches: `FloppyDisk.m` (8,891 lines, 29 methods),
`FloppyDiskInt.m` (1,031, 23), `FloppyDiskThread.m` (824, 10), `FloppyDiskKern.m`
(12, 0). All four are in `CLASSES`.

**Read ivars from `__OBJC,__instance_vars` during the work**, never by inference.

### 2.2 The C layers

The 141 C functions are legible as layers, which is useful for ordering work:

| Layer | Bytes | Examples |
| --- | --- | --- |
| Other C (cache, format, drive logic) | 17,520 | `_ReadBlocks`, `_InitializeDrive`, `_LookupFormatTable` |
| BSD device entry | 6,536 | `_fdstrategy`, `_fdioctl`, `_Fdopen`, `_fdrToIo` |
| SWIM III HAL | 5,392 | `_SwimIIIStepDrive`, `_HALReadSector`, `_HALFormatTrack` |
| GCR nibblizing | 1,732 | `_NibblizeGCRData`, `_FPYDenibblizeGCRSector` |
| DBDMA | 1,152 | `_StartDBDMA`, `_OpenDBDMAChannel` |

Objective-C accounts for 16,912 bytes (34%); C for 32,332 (65%).

### 2.3 The i386 sibling constrains almost nothing

`src/drivers-i386/ide/drvPCFloppy` shares the class name `FloppyController :
IODirectDevice`, which made it look like a strong sibling. Measured, it is not:

- **5 of 141** C functions have a same-name identifier there (`fdrToIo`,
  `fdTimer`, `fdGetSectSizeInfo`, `fdminphys`, `floppyMalloc`) — the shared BSD
  entry layer.
- **29 of 61** selectors appear there — the DriverKit/IODisk method surface.

The hardware layers are unrelated: this driver targets Apple's **SWIM III**, the
i386 one a PC 82077-class controller. The sibling constrains the Objective-C
surface, not the C. Do not reason from it about SWIM III, GCR, or DBDMA.

## 3. The symbol-naming defect

Every C function in the source is defined with a spurious leading underscore:

```c
void _AssignTrackInCache(int param_1)
unsigned int _BSBlockListDescriptorGetExtent(unsigned int param_1, ...)
void _BuildTrackInterleaveTable(int param_1, unsigned int sectorCount)
```

Under the Mach-O ABI the compiler prepends exactly one underscore, so these emit
`__AssignTrackInCache` where Apple's binary carries `_AssignTrackInCache`. The
source name should carry no underscore at all.

**136 of the 141 are affected. None is currently correct.** The other five are
absent entirely (§5).

This is the same defect corrected in `GemEnet` (`_mace_crc` → `mace_crc`) and in
`PPCSerialPort` (50 functions) and `drvPPCGNic` (2) earlier in this series.

### 3.1 Why this rename is more dangerous than PPCSerialPort's

`PPCSerialPort` had **zero** `_`-prefixed identifiers that were not among its 55
functions, so a blanket prefix-strip was safe there. **That is not true here.**

- **157 `_`-prefixed identifiers must not be touched by the C rename** — globals
  and types such as `_BusyFlag`, `_FloppyState`, `_FdBuffer`, `_Floppy_dev`,
  `_FloppySWIMIIIRegs`, and Objective-C selectors such as
  `_rwBlockCount:blockCount:` and `_timerEvent`. A blanket strip corrupts all 157.
  (52 of those selectors are themselves misnamed and are corrected separately in
  §3.2 — but not by the C rename, which must leave them alone.)

  **That is a scoping rule, not a verdict on those 157 spellings.** The
  one-underscore Mach-O rule is **not** function-specific. Of the binary's 306
  symbols, **zero** carry a double underscore, and `_FloppyState`, `_Floppy_dev`,
  `_FloppyIdMap`, `_busyflag`, `_slock`, `_ReadDataPresent`,
  `_PrivDBDMAChannelArea` and `_GRCFloppyDMAChannel` are real **one-underscore
  `__DATA` symbols** — so Apple's source spelled those globals bare too. Our tree
  defines them with the underscore (`unsigned int _FloppyState = 0;`), which emits
  `__FloppyState` and matches nothing. `symbol_name_check.py:46` filters on
  `section == "__TEXT,__text"`, which is why the gate stays green over it.
  Corroboration from the other direction: of the 48 undefined imports, 21 are
  already referenced bare and correct, and exactly one (`_IOExitThread`) is not.
  The data-symbol defect is pre-existing and outside this spec's edit set — it is
  recorded as uncertainty 5 in `findings.md` and must be **scheduled, not
  preserved**.
- **Two prefix hazards**: `_GetDisketteFormat` is a prefix of
  `_GetDisketteFormatType`, and `_MemListDescriptorDataCompare` of
  `_MemListDescriptorDataCompareWithMemory`. Word-bounded `\b_Name\b` is safe
  because the following character is a word character; substring replacement is
  not.
- **1,670 `_`-prefixed tokens** in the source, 5.4× PPCSerialPort's 308.

**The rename must be driven by the exact 141-name list read from the binary's
symbol table, word-bounded, one name at a time.** A blanket transformation over
`_[A-Za-z]\w*` is prohibited.

### 3.2 The same defect in the Objective-C half

**Added after Task 3's measurement. §2's table originally read "All present in
source" and §10 called the 60 methods "present but unverified". Both understated
the problem.**

**52 of the 60 Objective-C methods carry a spurious leading underscore on the
selector** — the source declares `- (void)_timerEvent` where Apple's binary
carries `-[FloppyDisk(Internal) timerEvent]`. Distribution: 21 in `FloppyDisk.m`,
21 in `FloppyDiskInt.m`, 10 in `FloppyDiskThread.m`; 185 token occurrences.

Apple's binary carries **zero** underscored selectors, verified across all 62
Objective-C method symbols.

**This is worse than the C defect.** A selector is not a symbol decoration:
`[self _timerEvent]` and `[self timerEvent]` are different messages at runtime, so
the current source would not respond to the selectors Apple's callers send.

**Correction after Task 4.** This section first said "eight source selectors are
legitimately underscored". That was wrong: the eight are the eight already-**bare**
selectors, and **no** legitimately-underscored selector exists — Apple's
`__OBJC,__meth_var_names` holds 130 names and not one begins with an underscore.

The count 52 was also one short. `_fcCmdXfr:driveInfo:`
(`FloppyDiskInt.m:18`, `:668`) is a 53rd instance: the selector table carries
`fcCmdXfr:driveInfo:` bare and no underscored form. It escaped Task 4 because it
belongs to `FloppyController`, whose only `__TEXT,__text` method symbol is
`+probe:`, so it is absent from the symbol-derived list Task 4 worked from. It is
corrected in Task 5.

And the token figure 185 was wrong: **11 of those tokens are ivar references**
(`_innerRetry`, `_outerRetry` — `FloppyDisk.h:25-26` plus nine uses), not
selectors. Renaming them would have altered driver state. The true selector-token
count is **174**.

**How it was missed.** An earlier reading of `selector_check.py`'s output took its
left-hand column for the binary's names when it was showing ours, so a list of
underscored selectors looked like a clean match. The tool was right; the reading
was wrong. That is the sixth time in this series an ad-hoc reading was recorded as
measurement — and the reason §4.4 gates on tools re-run rather than on prose.

The fix is Task 4 of the plan, added after the measurement exposed it.

## 4. Method

### 4.1 The function at `__text` offset 0

**`_fdrToIo` sits at `__text+0`.** Its first word is `9421ffe0`
(`stwu r1,-32(r1)`) — real code. IDA's analysis will have no function entry
there, and `ppc_invariant_check` will report:

```
symbol _fdrToIo at 0x0 is not a function start
```

**That message means only that IDA's function list lacks an entry.** It is not
evidence of an absent body. The opposite reading was recorded across five earlier
specs in this series and retracted in 22 places; `read_macho` also reports
address 0 for *undefined* symbols, which is what made the two cases look alike.

Unlike every prior driver in this series, the address-0 function here is a **C
function, not a `+probe:` method**, so `selector_check.py` cannot confirm it.
Confirm it with `symbol_name_check.py`, which matches C definition sites by name.

Record it as a known exclusion and expect the map to cover 200 of the 201
hand-written functions.

### 4.2 Profiles

**No profile exists.** Create `floppy-ppc.json` and `floppy-bundle-ppc.json`
following `tools/binrecon/profiles/mesh-ppc.json`, changing only `name` and
`output_dir`, and add both to `test_ppc_profile_inventory` in
`tools/binrecon/tests/test_profile.py`, which asserts the full sorted list. They
sort between `dec21040-ppc.json` and `gem-bundle-ppc.json`.

`binrecon analyze` **exits 1 for any reference-only profile** — `cli.py:105`
returns 0 only when acceptance passes, and a profile with no `rebuilt` binary has
nothing to compare. What matters is that the run reports `analysis complete` and
publishes its output.

### 4.3 Mapping

Use the route proven on `SCSIServer` and `PPCSerialPort`:

1. `filter_named_functions.py` over the reference analysis, to drop IDA's unnamed
   jump islands
2. `source-map` with `--objc-methods` and **without** `--scope-to-objc`

**141 of the 201 hand-written functions are C.** Under `--scope-to-objc` the map
would cover 60 of 201 and appear complete.

The map runs **after** the rename. The before-state is recorded in §3 and §5 as
the baseline; mapping first would only produce a 136-function gap list that is
really one naming defect.

Scope validation must consider all four categories — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed` — not `mapped ∪ unmapped` alone.

### 4.4 The gate

`tools/binrecon/symbol_name_check.py`, built during the `PPCSerialPort` spec, is
the acceptance check: for every hand-written C symbol in the binary, a source
definition site must exist whose name is the symbol minus exactly one leading
underscore.

- **Before** the rename: 141 symbols, **141 missing**.
- **After** the rename: **5 missing** — the five in §5.
- **At the end**: **0 missing**, exit 0.

Presence is established by a definition site — never by an occurrence count and
never by a regex over declaration syntax. Five ad-hoc surveys in this series were
recorded as measurement and every one had to be retracted.

### 4.5 Disciplines for the five bodies

Each has caught a real defect in this series:

- Resolve every `bl` through `read_macho`'s relocation table — PowerPC jump
  islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export, and the real
  target comes from the **island's** HI16/LO16 relocation pair.
- Read ivars from `__OBJC,__instance_vars`, never by inference.
- Trace every bare constant to a named constant in this tree before writing it as
  one.
- Account for every instruction and every branch in writing.
- **Reproduce Apple's *form*, not Apple's *defects*.** Where the reference is
  demonstrably buggy, keep correct behaviour and record `intentional-mismatch`
  with its evidence. Standing user ruling; "reproduce by default" statements
  elsewhere in the tree are superseded.
- A confident guess is a defect; a recorded uncertainty is a result.

## 5. The five absent functions

| Function | Addr | Span | Layer |
| --- | --- | --- | --- |
| `_fdminphys` | `0x5b84` | 40 | BSD device entry |
| `_MediaScanTask` | `0xa284` | 60 | Media scan |
| `_TestCacheDirtyState` | `0x9444` | 88 | Track cache |
| `_fd_dev_to_id` | `0x5bac` | 216 | BSD device entry |
| `_OpenDBDMAChannel` | `0x68a8` | 380 | DBDMA |

784 bytes. Spans are next-symbol deltas and include any trailing jump island —
confirm each function's true extent from its `blr` before writing.

`_fdminphys` has a same-name counterpart in the i386 sibling (§2.3) and is the
only one of the five that does; treat that as a hint to check, not as evidence.

## 6. Duplicate definitions and source-only additions

### 6.1 Three redundant duplicates

Three functions are defined twice — external in `FloppyDisk.m` and `static` in a
second file. **Line numbers below are pre-rename; locate them by name.**

```
_getStatusName    FloppyDisk.m:136    (extern)   FloppyDiskThread.m:94   (static)
_GetBusyFlag      FloppyDisk.m:3608   (extern)   FloppyDiskInt.m:125     (static)
_ResetBusyFlag    FloppyDisk.m:6447   (extern)   FloppyDiskInt.m:130     (static)
```

**This is not legal C.** An earlier draft of this section said the `static` copy
merely shadows within its own translation unit, so it compiles and links. It does
not. `FloppyDiskInt.m:7` imports `FloppyDisk.h`, and the `static` definitions at
`FloppyDiskInt.m:125`/`:130` follow the file-scope `extern` prototypes in
`FloppyDisk.h:217`/`:427` within the same translation unit — C99 6.2.2p7
undefined behaviour, which GCC diagnoses. `FloppyDiskThread.m` imports the same
header, where `FloppyDisk.h:118` declares `_getStatusName`, so the third
duplicate has the same shape. Nothing is compiled here, so the period toolchain's
exact behaviour is untested, and per §9 no claim of buildability may be made;
which body the calls in the second file bind to is precisely what the conflict
leaves undefined. Apple's binary also carries **one** symbol for each, and
`static` functions do receive symbol-table entries in a `_reloc` output, so ours
would emit two. The static copies are redundant additions from an earlier pass.

Delete the `static` copies, keep the external definitions, and add declarations
where the second file needs them. Verify against the disassembly that the
surviving body is the one matching Apple's, rather than assuming the external one
is right.

### 6.2 Six source-only debug helpers

`_getStatusName`, `_getDensityName`, `_getIoctlName`, `_getCommandName`,
`_getOpName`, `_getResultName` map codes to strings and have **no counterpart in
Apple's binary**.

Per the decision taken during design, **they stay**, and `findings.md` records
them as source-only additions — roughly 100 lines Apple's driver did not carry.
They are not renamed, because there is no binary symbol to match.

Note that `_getStatusName` is both a source-only addition and one of §6.1's
duplicates; deleting its `static` copy still applies.

## 7. Artifacts

To `src/drivers-ppc/reconstruction/Floppy/`, matching the ten drivers already
there:

- `source-map.json`
- `ledger.json`
- `findings.md`

## 8. Acceptance

1. Two profiles created and `test_ppc_profile_inventory` updated; suite green.
2. All 136 misnamed C functions renamed, with every call site updated, driven by
   the binary's exact name list and word-bounded.
3. **The C rename moved no identifier outside those 136** — in particular none of
   the 157 `_`-prefixed globals, types, or Objective-C selectors. This item
   scopes the C rename only: the 53 misnamed selectors among those 157 are
   renamed under item 5, and the underscored data symbols are left alone because
   correcting them is out of scope (§3.1), **not** because their spelling is
   right.
4. `symbol_name_check.py` reports 141 symbols, **0 missing**, exit 0.
5. All **53** misnamed selectors renamed; `selector_check.py` reports **0
   renames**, 0 duplicates, 2 missing (both build-generated), 0 extra.
6. The source map covers **200** of the 201 hand-written functions. The 201st is
   `_fdrToIo`, excluded by construction per §4.1 — a known exclusion, not a gap.
7. `duplicate_candidates` is 0, or every entry is enumerated with evidence.
8. Bucket reconciliation reports `RECONCILES: yes`, with the two build-generated
   class methods accounted for.
9. All five bodies written, each with an instruction-by-instruction account
   covering every branch.
10. All three redundant `static` copies removed (`getStatusName`, `GetBusyFlag`,
    `ResetBusyFlag`); the six source-only helpers retained and
   recorded.
11. The binrecon suite stays green.

## 9. Constraints

- **No PowerPC toolchain and no host C compiler. Nothing compiles, and no claim of
  buildability may be made** — only of correspondence to the binary. That the
  renamed symbols "would now match" is an argument from the Mach-O naming rule,
  not an observation.
- Do not modify `src/kernel-7/`.
- Do not rename anything outside `drvPPCSwimFloppy`.
- Do not reason from `drvPCFloppy` about SWIM III, GCR, or DBDMA behaviour (§2.3).
- Commits: `drivers-ppc: ` prefix, one to two lines, no metadata or trailers.
- **Work in a dedicated worktree.** Several worktrees are active in this
  repository, and a shared git index lets parallel sessions overwrite each
  other's commits.

## 10. Risks

- **The rename is the main risk.** 136 names against 157 identifiers that must not
  move, in an 8,891-line file. §3.1's preconditions and §4.4's gate exist for
  this; a clean-looking `sed` is not evidence.
- **The 60 Objective-C methods are present, and 52 were misnamed (§3.2).** Even
  after Task 4 corrects the selectors, `selector_check.py` matches by name, not
  behaviour, and this source came from a decompiler. This spec measures naming and
  fills C gaps; it does not certify those 60 bodies. Whatever the map reports
  about them is coverage, not correctness.
- `_OpenDBDMAChannel` at 380 bytes is the largest of the five and sits in the
  DBDMA layer, which the i386 sibling does not constrain at all.
