# PPCSerialPort Reconstruction Design

**Date:** 2026-07-28
**Reference:** `C:/Users/raynorpat/Downloads/test/Drivers/ppc/PPCSerialPort.config/PPCSerialPort_reloc`
**Source:** `src/drivers-ppc/input/drvPPCSerialPort/PPCSerialPort.drvproj/PPCSerialPort.lksproj`

## 1. Goal

Measure Apple's shipped `PPCSerialPort` against our source, correct a systematic
symbol-naming defect affecting 50 of its 55 hand-written C functions, write the
five that are genuinely absent, and fix the same defect where it also appears in
`drvPPCGNic`.

`PPCSerialPort` was one of three drivers deferred on "glue-stub tooling": on
PowerPC, `--scope-to-objc` was mandatory, and it drops C functions. SCSIServer's
Task 1 was `filter_named_functions.py`'s first PowerPC use and it worked
unmodified, which removes that blocker. This driver is 55 C functions to 17
Objective-C methods, so it is the case that blocker was really about.

## 2. What the binary contains

`__text` is 20,448 bytes (`0x0`–`0x4fe0`) across **76 defined `__TEXT,__text`
symbols**, verified via `binrecon.macho.read_macho`.

| Origin | Count | Disposition |
| --- | --- | --- |
| Build-generated (`PPCSerialPortVersion`, `PPCSerialPortKernelServerInstance`) | 2 | Recorded and excluded |
| Compiler runtime (`__udivdi3`, `__umoddi3`) | 2 | Recorded and excluded |
| Hand-written Objective-C methods | 17 | All present in source |
| Hand-written C | 55 | 50 misnamed, 5 absent |

`2 + 2 + 17 + 55 = 76`. **72 functions are hand-written** — 17 Objective-C and 55
C. That 55-to-17 ratio is why §4.3 drops `--scope-to-objc`.

`__udivdi3` and `__umoddi3` are libgcc's 64-bit division helpers, linked in
rather than written. They get the same treatment the four prior driver specs gave
build-generated classes and SCSIServer gave MIG-generated stubs: recorded,
excluded from the gap list, never written.

### 2.1 Class

```
PPCSerialPort                  : IODirectDevice
PPCSerialPortVersion           : IODevice          (build-generated)
PPCSerialPortKernelServerInstance : Object         (build-generated)
```

One real class, one source file — `PPCSerialPort.m` at 3,138 lines and
`PPCSerialPort.h` at 298.

**Read ivars from `__OBJC,__instance_vars` during the work**, never by inference.

## 3. The symbol-naming defect

**Every C function in `PPCSerialPort.m` is defined with a spurious leading
underscore.** The source reads:

```c
static void _changeState(PPCSerialPort *self, unsigned int newState, unsigned int mask)
static BOOL _allocateRingBuffer(void *queueBase)
static IOReturn _AddBytetoQueue(void *queueBase, unsigned char byte)
```

Under the Mach-O ABI the compiler prepends one underscore, so these emit
`__changeState`, `__allocateRingBuffer`, `__AddBytetoQueue` — while Apple's
binary carries `_changeState`, `_allocateRingBuffer`, `_AddBytetoQueue`. The
source name should carry no underscore at all.

**50 of the 55 are affected. None is currently correct.**

This is the same defect fixed in `GemEnet` earlier in this series, where
`_mace_crc` became `mace_crc` and `crc416` was added. `PPCBurgundy` and
`PPCAwacs` both scored 16/16 once the convention was applied correctly, which is
what establishes the convention as project-wide rather than a local style.

### 3.1 The rename is mechanically safe

Verified before writing this spec:

- **No substring hazards.** No function name in the set is a prefix of another,
  so a word-bounded replace cannot catch a longer name.
- **No unrelated `_`-prefixed identifiers.** Every `_Foo` token in
  `PPCSerialPort.m` is one of these 55 functions.
- **The 14 apparent collisions are benign.** They are string literals inside
  `_MyIOLog("changeState\n\r")` and Objective-C selectors such as
  `- (IOReturn)executeEvent:`. A prefix-strip does not touch either: the literals
  already lack the underscore, and a C function may share a name with a selector.
- **The one real hazard is not one.** `unsigned int watchState;` is a local in
  `-[PPCSerialPort dequeueData:]`, and that scope never calls the C function
  `_watchState`, so nothing is shadowed.

### 3.2 The same defect in drvPPCGNic

`src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj/GNicEnet.m`:

```c
GNicEnet.m:32   unsigned int _ReadGNicRegister(int base, unsigned int offset_and_size)
GNicEnet.m:66   void _WriteGNicRegister(int base, unsigned int offset_and_size, unsigned int value)
```

The binary carries `_ReadGNicRegister` and `_WriteGNicRegister`. Both of GNic's
two hand-written C functions are affected, in a driver whose report currently
reads as complete. They are fixed here, and GNic's existing source map is
re-run to confirm the two now map.

### 3.3 How this defect was found, and why the spec does not trust that

The 50 were found by an ad-hoc regex over source definitions. **That regex also
reported two defects in `drvPPCGem` that do not exist** — Gem's source correctly
reads `static unsigned int crc416(...)` and `static unsigned int mace_crc(...)`,
fixed earlier in this series.

A survey that produces false positives may also produce false negatives, and this
series has already recorded two ad-hoc surveys as measurement and had to retract
both (see the SCSIServer spec §3.1). So §4.4 requires a real check rather than
reuse of the survey.

## 4. Method

### 4.1 The function at `__text` offset 0

**`+[PPCSerialPort probe:]` sits at `__text+0`.** Its first word is `7c0802a6`
(`mflr r0`) — real code. IDA's analysis will have no function entry there, and
`ppc_invariant_check` will report:

```
symbol +[PPCSerialPort probe:] at 0x0 is not a function start
```

**That message means only that IDA's function list lacks an entry.** It is not
evidence of an absent body. The opposite reading was recorded across five earlier
specs in this series and retracted in 22 places; `read_macho` also reports
address 0 for *undefined* symbols, which is what made the two cases look alike.

`probe:` is present in our source. Record it as a known exclusion — not a gap,
not a phantom — and expect the map to cover 71 of the 72 hand-written functions.

### 4.2 Profiles

Unlike SCSIServer, **no profile exists.** Create `ppcserialport-ppc.json` and
`ppcserialport-bundle-ppc.json` following the pattern of
`tools/binrecon/profiles/mesh-bundle-ppc.json`, and add both to
`test_ppc_profile_inventory` in `tools/binrecon/tests/test_profile.py`, which
asserts the full sorted list.

### 4.3 Mapping

Use the primary route SCSIServer proved on PowerPC:

1. `filter_named_functions.py` over the reference analysis, to drop IDA's unnamed
   jump islands
2. `source-map` with `--objc-methods` and **without** `--scope-to-objc`

**55 of the 72 hand-written functions are C.** Under `--scope-to-objc` the map
would cover 17 of 72 and appear complete — the failure mode that spec was written to
avoid.

The map runs **after** the rename. The before-state is already measured and is
recorded in §3 and §5 as the baseline; re-measuring it first would only produce a
50-function gap list that is really one naming defect.

Scope validation must consider all four categories — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed` — not `mapped ∪ unmapped` alone.

### 4.4 Verifying the rename actually fixed the symbols

Because §3.3's survey is not trustworthy, the acceptance check is a direct
comparison, not a re-run of the survey: for every hand-written C symbol in the
binary, confirm a definition site exists in the source whose name is the symbol
minus exactly one leading underscore. Run it over both `PPCSerialPort` and
`drvPPCGNic`.

Presence must be established by a definition site — not by an occurrence count
and not by a regex over declaration syntax. That rule is what §3.3 and the
SCSIServer spec's §3.1 both cost.

### 4.5 Disciplines for the five bodies

Each has caught a real defect in this series:

- Settle every signature from `__OBJC,__meth_var_types` where Objective-C is
  involved, never by inferring from instructions.
- Resolve every `bl` through `read_macho`'s relocation table — PowerPC jump
  islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export, and the real
  target comes from the island's HI16/LO16 relocation pair.
- Read ivars from `__OBJC,__instance_vars`, never by inference.
- Trace every bare constant to a named constant in this tree before writing it as
  one.
- Account for every instruction and every branch in writing.

**Reproduce Apple's *form*, not Apple's *defects*.** Where the reference is
demonstrably buggy, keep correct behaviour and record `intentional-mismatch` with
its evidence. This is a standing user ruling that settled a real contradiction in
the tree; `divergences.md:370`-style "reproduce by default" statements are
superseded.

## 5. The five absent functions

| Function | Addr | Span | Note |
| --- | --- | --- | --- |
| `_dataLatTOHandler` | `0x1e3c` | 96 | No mention anywhere in source |
| `_frameTOHandler` | `0x1e9c` | 172 | No mention anywhere in source |
| `_delayTOHandler` | `0x1f48` | 176 | No mention anywhere in source |
| `_heartBeatTOHandler` | `0x1ff8` | 228 | No mention anywhere in source |
| `_activatePort` | `0x0bb0` | 284 | Called 4× in source, never defined |

956 bytes. Spans are next-symbol deltas and include any trailing jump island;
confirm each function's true extent from its `blr` before writing.

The four `TOHandler` functions are expected to be `IOScheduleFunc` timeout
callbacks — **expected, not established.** Confirm each one's registration site
and signature from the disassembly before writing it; do not infer the signature
from the name.

`activatePort`'s four call sites constrain its signature and give a starting
point that the four handlers lack.

## 6. Artifacts

To `src/drivers-ppc/reconstruction/PPCSerialPort/`, matching the nine drivers
already there — `PPCSerialPort` is a `drivers-ppc` driver, unlike SCSIServer,
which is a top-level architecture-neutral project and keeps its artifacts under
`src/drvSCSIServer/`.

- `source-map.json`
- `ledger.json`
- `findings.md`

## 7. Acceptance

1. Two profiles created and `test_ppc_profile_inventory` updated; suite green.
2. All 50 `PPCSerialPort` functions and both `GNic` functions renamed, with every
   call site updated.
3. §4.4's definition-site check passes for both drivers: every hand-written C
   symbol in each binary has a source definition whose name is the symbol minus
   one leading underscore.
4. The source map covers **71** of the 72 hand-written functions. The 72nd is
   `+[PPCSerialPort probe:]`, excluded by construction per §4.1 — a known
   exclusion, not a gap — confirmed present by `selector_check.py`, which matches
   by string rather than address.
5. `duplicate_candidates` is 0, or every entry is enumerated with evidence.
6. Bucket reconciliation reports `RECONCILES: yes`, with `__udivdi3`/`__umoddi3`
   and the two build-generated class methods accounted for.
7. All five bodies written, each with an instruction-by-instruction account
   covering every branch.
8. GNic's existing source map re-run; its two functions now map.
9. The binrecon suite stays green.

## 8. Constraints

- **No PowerPC toolchain and no host C compiler. Nothing compiles, and no claim
  of buildability may be made** — only of correspondence to the binary. That the
  renamed symbols "would now match" is an argument from the Mach-O naming rule,
  not an observation.
- Do not modify `src/kernel-7/`.
- Do not rename anything in a driver outside `drvPPCSerialPort` and `drvPPCGNic`.
- Commits: `drivers-ppc: ` prefix, one to two lines, no metadata or trailers.

## 9. Risks

- **A 50-function rename is where a careless pass breaks a call site.** §3.1
  establishes the mechanical preconditions, but the change must be verified by
  §4.4's check, not assumed from a clean `sed`.
- The four `TOHandler` functions have **no source counterpart at all** — not even
  a call site — so nothing in the tree constrains a wrong reading of them. This is
  the greenfield condition that made the IOADBDevice spec expensive.
- §3.3's survey may have missed instances of the naming defect in other drivers.
  This spec fixes the two it found and does not claim the tree is clean; a
  project-wide sweep was considered and deliberately deferred.
