# SCSIServer Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure Apple's shipped `SCSIServer` against `src/drvSCSIServer`, fix the divergences a prior session documented but never repaired, write the six absent C function bodies, and wire `IOTask.m` into the build.

**Architecture:** Measure first, so the gap list is evidence rather than assumption. Verify the MIG `.defs` early, because a mismatch there halts the spec. Then fix the documented divergences, then write the six absent C functions, largest last. A final task wires the build, remaps, and runs acceptance.

> **Corrected after Task 1.** This plan originally said "nine absent function
> bodies — four Objective-C, five C." Task 1's measurement showed all four
> Objective-C methods are implemented (old-style `- init` / `- free`, which the
> survey's `grep "^[-+] *("` could not match), and that a sixth C function,
> `_IORequestNotifyForClientTask`, is absent and was missed by an occurrence-count
> check. Task 3 was rewritten accordingly. See spec §3.1.

**Tech Stack:** Python 3.13 in `.venv-binrecon`, binrecon CLI, IDA Professional 9.2 (reference analysis only), Mach-O/PowerPC big-endian.

**Spec:** [2026-07-28-scsiserver-reconstruction-design.md](../specs/2026-07-28-scsiserver-reconstruction-design.md)

## Global Constraints

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-ioadb-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc"
LKS="src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj"
RECON="src/drvSCSIServer/reconstruction/SCSIServer"
cd $REPO
```

- **There is no PowerPC toolchain and no host C compiler. Nothing compiles, and you may not claim it does.** Do not run `make`.
- **Only files under `$LKS` and `$RECON`** may be created or modified, plus `tools/binrecon/` if a tool defect is found.
- **Never modify `src/kernel-7/`.**
- **Do not rewrite `IOSCSISessionMig.defs`.** Task 2 governs; a mismatch is reported, not fixed.
- **The disassembly is the authority** — not the function name, not a sibling, not what would be reasonable.
- **A confident guess is a defect; a recorded uncertainty is a result.**
- Commits: `drvSCSIServer: ` prefix, one to two lines, no metadata/trailers/emoji. One per task.

### Disciplines, each of which has caught a real defect in this series

- **Settle every method signature from `__OBJC,__meth_var_types`**, never by inferring from instructions.
- **Resolve every `bl` to an unnamed `sub_XXXX` through `read_macho`'s relocation table** — PowerPC jump islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's export.
- **Read class hierarchy and ivars from `__OBJC,__class` / `__OBJC,__instance_vars`**, never by inference.
- **Trace every bare constant to a named constant in this tree** before writing it as one.
- **Account for every instruction and every branch in writing.**

### The address-0 rule — read this before interpreting any tool output

`+[SCSIServer deviceStyle]` sits at `__text+0`. Its first word is `9421ffe0`
(`stwu r1,-32(r1)`) — **real code**. IDA's analysis has no function entry there,
so `ppc_invariant_check` will report:

```
symbol +[SCSIServer deviceStyle] at 0x0 is not a function start
```

**That message means only that IDA's function list lacks an entry.** It is not
evidence of an absent body. The opposite reading was recorded across five earlier
specs in this series and had to be retracted in 22 places. `read_macho` also
reports address 0 for *undefined* symbols, which is what made the two cases look
alike.

`+[SCSIServer deviceStyle]` is present at `SCSIServer.m:37`. It is neither a gap
nor a phantom — it is simply outside any map's universe. Record it as a known
exclusion with its reason.

### Established before this plan — use, do not re-derive

From `__OBJC,__class` (field order `isa, super_class, name, version, info, instance_size, ivars, methods, cache, protocols`, 40-byte stride):

```
SCSIServer                     : IODevice   instance_size = 300
IOSCSISession                  : Object     instance_size = 8
SCSIServerVersion              : IODevice   instance_size = 264   (build-generated)
SCSIServerKernelServerInstance : Object     instance_size = 4     (build-generated)
```

`__text` spans `0x0`–`0x35b0` (13,744 bytes) across **69 defined symbols**:

| Origin | Count |
| --- | --- |
| MIG server (`__XIOSCSISession_*` ×18, `_IOSCSISessionMig_server`) | 19 |
| Build-generated (2 classes above) | 2 |
| Hand-written — 13 Objective-C, 35 C | 48 |

**Profiles already exist**: `tools/binrecon/profiles/scsiserver-ppc.json` and
`scsiserver-bundle-ppc.json`, both already in `test_ppc_profile_inventory`. Do
not create profiles and do not edit that test.

### The six functions to write — all C

| # | Function | Addr | Size | Task |
| --- | --- | --- | --- | --- |
| 1 | `_IODestroyMappedVMTask` | `0x1d98` | 48 | 4 |
| 2 | `_IOTaskPortAllocate` | `0x19bc` | 64 | 4 |
| 3 | `_IOConvertTaskPortToVMTask` | `0x1c98` | 256 | 4 |
| 4 | `_serverThreadFunc` | `0x0a70` | 356 | 4 |
| 5 | `_IORequestNotifyForClientTask` | `0x20dc` | 480 | 4 |
| 6 | `__io_task_notification` | `0x1dc8` | 788 | 4 |

Sizes are next-symbol **spans** — IDA's function size plus any trailing 16-byte
jump island. Confirm each function's true extent from its `blr` before writing.

`_IORequestNotifyForClientTask` is declared `extern` at `IOTask.h:105` and called
at `IOSCSISession.m:265`, but never defined. An occurrence-count check found
three hits — a comment, a call, and the declaration — and read them as a
definition.

**No Objective-C method is absent.** All 13 are implemented; Task 3 fixes the
defects in four of them.

Within each task, work smallest first — the small ones establish the idioms the
large ones reuse.

## File Structure

**Created:**
- `$RECON/source-map.json` — map artifact (Task 1)
- `$RECON/ledger.json` — parity ledger (Task 1)
- `$RECON/findings.md` — the measurement, the MIG check, uncertainties (Tasks 1, 2, 5)

**Modified:**
- `$LKS/IOSCSISession.m` — divergence fixes (Task 3)
- `$LKS/SCSIServer.m` — divergence fixes (Task 3)
- `src/drvSCSIServer/reconstruction/divergences.md` — ledger dispositions (Tasks 3, 5)
- `$LKS/IOTask.m` — five C functions; `_serverThreadFunc` goes to `IOSCSISession.m` (Task 4)
- `$LKS/IOTask.h` — declarations for anything newly exposed (Task 4)
- `$LKS/Makefile` — `CLASSES` / `HFILES` (Task 5)

`_serverThreadFunc` is session/server plumbing rather than task plumbing: put it
in `IOSCSISession.m` beside the reservation helpers, and the other five in
`IOTask.m`. Task 4 confirms every placement against what each function actually
references.

**Two pre-existing artifact locations.** A prior session left
`src/drvSCSIServer/reconstruction/{source-map.json,ledger.json,divergences.md}`,
and this plan's `$RECON` is the nested
`src/drvSCSIServer/reconstruction/SCSIServer/`. Both now describe the same
binary. Task 5 consolidates them into one location and says which it kept.

---

## Task 1: Analysis and source map

**Files:**
- Create: `$RECON/source-map.json`, `$RECON/ledger.json`, `$RECON/findings.md`

**Interfaces:**
- Produces: `$RECON/source-map.json`, consumed by Tasks 2–5 for addresses and
  coverage; the recorded mapping route, which Task 5 re-runs verbatim.

- [ ] **Step 1: Run the reference analysis**

```bash
cd $REPO && BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon \
  $VENVPY -m binrecon analyze --profile tools/binrecon/profiles/scsiserver-ppc.json
```

Expected: exit 0, output under `tools/binrecon/out/scsiserver-ppc/`. Note the analysis
JSON path — later steps call it `$ANALYSIS`.

- [ ] **Step 2: Confirm the function count before mapping**

```bash
cd $REPO && $VENVPY -c "
import json,sys
d=json.load(open(sys.argv[1]))
fns=d['functions']
print('functions:', len(fns))
print('unnamed  :', sum(1 for f in fns if not f['names']))
print('lowest   :', hex(min(f['address'] for f in fns)))" $ANALYSIS
```

Expected: a nonzero unnamed count (the jump islands), and `lowest` **greater than
0** — confirming IDA has no entry at `__text+0`, exactly as the address-0 rule
predicts. Record all three numbers in `findings.md`.

- [ ] **Step 3: Filter unnamed functions**

```bash
cd $REPO && $VENVPY tools/binrecon/filter_named_functions.py \
  $ANALYSIS tools/binrecon/out/scsiserver-ppc/analysis-named.json
```

Expected: exit 0. Re-run the Step 2 snippet against the output; `unnamed` must
now be 0 and `input.sha256` must be unchanged from `$ANALYSIS`.

- [ ] **Step 4: Build the source map — primary route, no `--scope-to-objc`**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/binrecon/out/scsiserver-ppc/analysis-named.json \
  --binary "$REF" \
  --source-dir $LKS \
  --repo-root . \
  --objc-methods \
  --output $RECON/source-map.json
```

This is the first use of `filter_named_functions.py` on PowerPC. If it exits 0,
you have C functions and Objective-C methods in one map — continue to Step 5.

**If it fails**, fall back:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis $ANALYSIS \
  --binary "$REF" --source-dir $LKS --repo-root . \
  --objc-methods --scope-to-objc \
  --output $RECON/source-map.json
```

Under the fallback the 35 C functions land in bucket 6 in Step 6 and you triage
each into bucket 5 by hand with its file and line. **Record which route you used
and, if you fell back, the exact error.**

- [ ] **Step 5: Check coverage across all four categories**

```bash
cd $REPO && $VENVPY -c "
import json
m=json.load(open('$RECON/source-map.json'))
for k in ('mapped','unmapped','duplicate_candidates','boundary_disputed'):
    v=m.get(k,[]); print(f'{k}: {len(v)}')
    for e in v[:40]: print('   ', e.get('name') or e)"
```

Do not judge coverage from `mapped` and `unmapped` alone — a previous spec in
this series missed addresses that way. Every `duplicate_candidates` and
`boundary_disputed` entry needs an explanation in `findings.md`.

- [ ] **Step 6: Bucket the functions**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/scsiserver-ppc/analysis-named.json \
  $RECON/source-map.json
```

Expected: a bucket table ending in `RECONCILES: yes`. Buckets 1 and 2 are always
empty for a `_reloc` kernel server. Bucket 4 should hold exactly the two
build-generated class methods.

- [ ] **Step 7: Run the PowerPC invariant check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/binrecon/out/scsiserver-ppc/analysis-named.json
```

The tool now distinguishes "no analyzer function and no code" from "no analyzer
function but code is present." Expect the `deviceStyle` line to report **code
present**. Any other violation gets a written explanation — the one violation
deserves more scrutiny than the clean relocations, not less.

- [ ] **Step 8: Write the measurement into findings.md**

Record: the three Step 2 numbers; the route taken in Step 4; the four-category
coverage from Step 5; the bucket table; the invariant-check result; the
`deviceStyle` exclusion and why; and the gap list your map actually produced —
State plainly that nothing was compiled.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $RECON && \
  git commit -m "drvSCSIServer: map SCSIServer against the shipped binary"
```

---

## Task 2: Verify IOSCSISessionMig.defs against the binary

**Files:**
- Modify: `$RECON/findings.md`
- Read-only: `$LKS/IOSCSISessionMig.defs`

**Interfaces:**
- Consumes: the analysis from Task 1.
- Produces: a per-routine verification table in `findings.md`. **If any routine
  mismatches, this task stops the plan** — see Step 4.

The 19 MIG functions are generated, not hand-written, so they are excluded from
the gap list. But `IOSCSISessionMig.defs` is verified by nothing today, and a
wrong routine there produces a server that mis-decodes every message of that
routine at runtime — no amount of correct `IOSCSISession.m` compensates.

- [ ] **Step 1: List the routines the `.defs` declares**

```bash
cd $REPO && grep -n "^\s*\(routine\|simpleroutine\|subsystem\)" $LKS/IOSCSISessionMig.defs
```

Record the subsystem base number and each routine's name and ordinal. MIG assigns
message IDs sequentially from the subsystem base in declaration order.

- [ ] **Step 2: Read each `__XIOSCSISession_*` stub for its message layout**

For each of the 18 stubs, extract from the disassembly:

- the request message size it checks (`msgh_size` comparison),
- the reply message size it stores,
- the argument count and in/out direction implied by the fields it reads and writes.

Also read `_IOSCSISessionMig_server`'s dispatch table for the routine-number
range it accepts and the order of its entries.

- [ ] **Step 3: Compare and tabulate**

Write a table into `findings.md`: routine name, `.defs` ordinal, binary ordinal,
`.defs` argument signature, binary-observed layout, and agree/differ. All 18 plus
the server function must appear.

- [ ] **Step 4: If anything differs — stop**

Report the specific mismatch: which routine, what the `.defs` says, what the
binary does, and the runtime consequence. **Do not edit
`IOSCSISessionMig.defs`.** Commit the findings and halt the plan; the fix is a
separate change that invalidates the generated half of the build.

If everything agrees, say so explicitly and note the limits: this is a
read-and-compare against declarations, not a regenerate-and-diff. It catches
wrong routine numbers and argument-count or size mismatches; it does not catch
subtle codegen differences. No MIG binary is available here.

- [ ] **Step 5: Commit**

```bash
cd $REPO && git add $RECON/findings.md && \
  git commit -m "drvSCSIServer: verify IOSCSISessionMig.defs against the shipped MIG stubs"
```

---

## Task 3: Fix the divergences the prior session documented

**Files:**
- Modify: `$LKS/SCSIServer.m`, `$LKS/IOSCSISession.m`
- Read: `src/drvSCSIServer/reconstruction/divergences.md` (1,824 lines, the prior session's instruction-level comparison)

**Interfaces:**
- Consumes: `divergences.md`'s findings and ledger; `$RECON/source-map.json`.
- Produces: corrected method bodies. Task 5 re-checks divergences and expects these resolved.

**This task originally read "The four Objective-C methods." That was wrong — all
four are implemented.** They are old-style Objective-C (`- init`, `- free`,
`- initFromDeviceDescription:`) with no parenthesised return type, which the
survey's `grep "^[-+] *("` could not match. The real work is that the prior
session compared them against the disassembly, **found real defects, and never
fixed them** — its ledger still carries them as `unexamined` with Findings
attached, and it names a "Task 12" that never ran.

- [ ] **Step 1: Enumerate every open finding — and re-verify each against the tree**

**`divergences.md` has drifted from the source and cannot be trusted as a
worklist.** A review of an earlier draft of this task established that of four
findings spot-checked, **three had already been fixed** and the fourth's site
list was wrong in both count and line numbers. Every `SCSIServer.m` line number
in it is off by 3.

So Step 1 is the task's foundation, not a formality:

1. List every ledger entry in `divergences.md` whose status is `unexamined`
   **with a Finding attached** — these are claimed defects, distinct from the 51
   entries that are merely unread.
2. For each, **open the current source and check whether it is still true.**
   Record it as `already-fixed`, `still-open`, or `claim-wrong` (the finding
   itself misdescribes the reference).
3. For every `still-open` entry, re-derive the reference behaviour from the
   disassembly yourself before changing anything. Do not act on the finding's
   prose.

Known already-fixed at the time of writing — confirm rather than assume, and
expect to find more:

- `SCSIServer.m:151` already passes `deviceDescription`, not `self`, to
  `registerSCSIController:` (fixed in `c3a70903`).
- `IOSCSISession.m:140` already passes `notify_port` to `IOTaskPortDeallocate()`
  (fixed in `5b4d62ec`).
- `IOSCSISession.m:173` already returns `nil`, not `self`.

Produce the classified list before fixing anything. Its accuracy governs
everything after it — the steps below name candidates, not confirmed defects.

- [ ] **Step 2: Fix whatever Step 1 classified `still-open`**

Work from your own classified list, not from the candidates below. For each
`still-open` entry, re-derive the reference behaviour from the disassembly, then
correct the source.

Two candidate areas Step 1 should have reached a verdict on:

- **`-[SCSIServer initFromDeviceDescription:]` (address 228)** — an extra `IOLog`
  with no counterpart. `divergences.md` says the reference goes straight from
  `[self registerDevice]` / `_server = self` (addresses 368-392) to `mr r3, r31`
  and the epilogue, with no further `bl` and no such string in the reference's
  string table. Check the string table yourself.
- **`-[IOSCSISession free]` (address 1732)** — a cleanup call that
  `divergences.md` says resolves to `IOExitThread()` rather than a callback.
  Resolve the target through the relocation table before changing anything.

- [ ] **Step 3: Decide the `objc_getClass` question on evidence**

Our source fills the `objc_super` structure with a call:
`super_struct.class = objc_getClass("Object");`. `divergences.md` says the
reference instead loads a static reference — `lis r9, stru_5198.ext@ha` /
`lwz r9, stru_5198.ext@l(r9)` / `stw r9, ...` — with no call at all.

**There are five sites, not the four `divergences.md` implies**, and its line
numbers are stale. The current sites are:

```
IOSCSISession.m:151    super_struct.class = objc_getClass("Object");
IOSCSISession.m:227    super_struct.class = objc_getClass("Object");
SCSIServer.m:174       superStruct.class  = objc_getClass("IODevice");
SCSIServer.m:295       objc_msgSend(objc_getClass("IOSCSISession"), @selector(alloc))
SCSIServer.m:359       superStruct.class  = objc_getClass("IODevice");
```

`SCSIServer.m:295` is a different construct — an `alloc` on a named class, not an
`objc_super` fill. Judge it separately; it may be entirely correct.

Verify each site against its own reference address before changing it. If our
tree has no established idiom for a static superclass reference in this position,
**record that as an uncertainty rather than inventing one** — this is a codegen
difference, and writing a construct the tree never uses elsewhere is worse than
leaving it documented.

- [ ] **Step 4: Dispose of the rest**

For every remaining `still-open` finding, either correct the source or, if the
divergence is deliberate, mark it `intentional-mismatch` in the ledger **with the
reason written down** — that disposition exists and `divergences.md` already uses
it for three entries.

For every `already-fixed` and `claim-wrong` entry, update `divergences.md` so the
next reader is not sent after a defect that is not there.

- [ ] **Step 5: Where the evidence is ambiguous, record instead of guessing**

Any finding whose correct resolution you cannot establish from the disassembly
goes into `$RECON/findings.md` as a numbered uncertainty with what you observed
and what you would need. A confident guess is a defect; a recorded uncertainty is
a result.

- [ ] **Step 6: Update the ledger dispositions**

Every entry you fixed moves from `unexamined` to `assembly-matched`, in
`divergences.md`'s ledger table. State the new tally.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add $LKS $RECON src/drvSCSIServer/reconstruction && \
  git commit -m "drvSCSIServer: fix the documented divergences in SCSIServer and IOSCSISession"
```

---

## Task 4: The six C functions

**Files:**
- Modify: `$LKS/IOTask.m`, `$LKS/IOTask.h`, `$LKS/IOSCSISession.m`

**Interfaces:**
- Consumes: `$RECON/source-map.json`; the `_entry` declaration already in `IOTask.m`.
- Produces: six function bodies. Task 5 remaps and expects them mapped.

All six absent functions are C; no Objective-C method is missing. Sizes below are
next-symbol spans including any trailing jump island — confirm each function's
true extent from its `blr` before writing.

- [ ] **Step 1: Write `_IODestroyMappedVMTask` (`0x1d98`, 48 bytes)**

Smallest. Sits directly after `_IOConvertTaskPortToVMTask` — read both before
writing either, since they are likely a matched pair over the same structure.

- [ ] **Step 2: Write `_IOTaskPortAllocate` (`0x19bc`, 64 bytes)**

`IOTask.m` already has `IOTaskPortAllocateName`. Read both and state in a comment
or in findings how they differ; do not assume one wraps the other.

- [ ] **Step 3: Write `_IOConvertTaskPortToVMTask` (`0x1c98`, 256 bytes)**

Reads the `_entry` table. The existing declaration gives `task_port` at `+0x18`
and `port_funcs` at `+0xa4`. **If this function accesses an offset not covered by
that declaration, extend it and record the new offset's evidence** — do not
silently index past the declared fields.

- [ ] **Step 4: Write `_serverThreadFunc` (`0x0a70`, 356 bytes)**

A thread entry point. Determine what it references before choosing its file: if
it touches the reservation helpers or session state it belongs in
`IOSCSISession.m`; if it touches only task plumbing, `IOTask.m`. State the
evidence for the placement you choose.

`IOTask.m`'s existing comments cite a client reference array at `0x4008`–`0x4087`
with `_notifyThread` at `0x4088`. **Those addresses come from an earlier session
and are not verified by this measurement.** If this function reads or writes that
region, verify the bounds against the binary's data sections yourself and correct
the comments if they are wrong.

- [ ] **Step 5: Write `_IORequestNotifyForClientTask` (`0x20dc`, 480 bytes)**

Second largest. Already declared at `IOTask.h:105`:

```c
extern int IORequestNotifyForClientTask(mach_port_t task, mach_port_t notifyPort, mach_port_t *deathPort);
```

and already called at `IOSCSISession.m:265`. **Confirm that declared signature
against the disassembly before writing** — it was written by an earlier session
from the same binary but has never been checked, and both its call site and
`-[IOSCSISession free]` depend on the arity being right. `IOTask.h:88` says it
forks its own thread and never returns; verify that too.

- [ ] **Step 6: Write `__io_task_notification` (`0x1dc8`, 788 bytes)**

Largest function in the plan. A Mach notification handler — expect a dispatch on
notification type with several branches. Enumerate every branch explicitly; a
missed case here is a silently ignored client death.

The leading double underscore is the Mach-O convention for a source symbol named
`_io_task_notification` (one underscore added by the compiler). Name the C
function `_io_task_notification`, matching how `IOTask.m` already names
`IOReferenceClientTask` for the symbol `_IOReferenceClientTask`.

- [ ] **Step 7: Declare anything newly exposed**

Add declarations to `IOTask.h` only for functions another file calls. Keep
internal helpers static, matching how `IOTask.m` already scopes its own.

- [ ] **Step 8: Record uncertainties**

As Task 3 Step 6. Include explicitly whether the `0x4008`/`0x4088` addresses were
confirmed or corrected.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $LKS $RECON/findings.md && \
  git commit -m "drvSCSIServer: write the task-port and notification plumbing"
```

---

## Task 5: Build wiring, remap, acceptance

**Files:**
- Modify: `$LKS/Makefile`, `$RECON/findings.md`, `$RECON/source-map.json`, `src/drivers-ppc/reconstruction/report-scsi.md`

**Interfaces:**
- Consumes: everything from Tasks 1–4.

- [ ] **Step 1: Wire `IOTask` into the build**

`$LKS/Makefile` line 16 currently reads:

```make
CLASSES = SCSIServer.m IOSCSISession.m
```

and line 18:

```make
HFILES = SCSIServer.h IOSCSISession.h
```

Change to:

```make
CLASSES = SCSIServer.m IOSCSISession.m IOTask.m
```

```make
HFILES = SCSIServer.h IOSCSISession.h IOTask.h
```

`IOTask.m` has never been built — it carries five commits of prior work but was
never added here.

**The two build descriptions already disagree.** `$LKS/PB.project` lists
`SCSIServer.m, IOSCSISession.m, IOTask.m` in its `CLASSES`, while the `Makefile`
lists only the first two. The `Makefile` is what builds, so this change is still
required; note the pre-existing disagreement in `findings.md` and say which file
you treated as authoritative. Check whether `PB.project`'s `H_FILES` also needs
`IOTask.h` and make the two consistent.

- [ ] **Step 1b: Consolidate the two reconstruction directories**

A prior session left `src/drvSCSIServer/reconstruction/{source-map.json,
ledger.json,divergences.md}`; this plan wrote to the nested
`src/drvSCSIServer/reconstruction/SCSIServer/`. Both describe the same binary,
and leaving both invites a later reader to trust the stale one.

Consolidate into one directory. Keep `divergences.md` — it is the prior session's
1,824-line instruction-level record and this plan's Task 3 updates it. State in
`findings.md` which location you kept, what you moved, and that no measurement
was re-run in the process.

- [ ] **Step 2: Record the i386 exposure**

`Makefile.preamble` sets `INCLUDED_ARCHS = i386 ppc`, and there is no i386
`SCSIServer` binary in the reference set. `IOTask.m`'s `_entry` offsets (`+0x18`,
`+0xa4`) are PowerPC-derived with no in-tree corroboration — nothing declares
`_entry` or `IOTaskWireMemory` except `IOTask.h` itself.

Write into `findings.md`, plainly: these offsets now enter the i386 build
unverified; a wrong offset wires or unwires the wrong memory rather than failing
at build time. This was a deliberate decision taken during design, not an
oversight.

- [ ] **Step 3: Regenerate the source map**

Re-run **the exact route Task 1 recorded** — primary or fallback, whichever was
used. All six new functions should now map.

- [ ] **Step 4: Re-run bucket reconciliation and the invariant check**

Both commands from Task 1 Steps 6 and 7. Expect `RECONCILES: yes` and the same
single `deviceStyle` line reporting code present.

- [ ] **Step 5: Confirm coverage against acceptance**

The map must cover **47** of the 48 hand-written functions. The 48th is
`+[SCSIServer deviceStyle]`, excluded by construction per the address-0 rule.
Confirm it is present in source independently:

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/selector_check.py \
  "$REF" $LKS
```

`selector_check.py` matches by string rather than by address, so it sees
`deviceStyle` where the map cannot.

- [ ] **Step 6: Run the suite**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests tools/tests -q
```

Expected: `854 passed, 4 skipped` for **both** paths together. `tools/binrecon/tests`
alone gives `851 passed, 4 skipped` — the three-test difference is `tools/tests`.
Quote the command beside the count. `PYTHONPATH` is required; without it collection
fails with 25 errors.

- [ ] **Step 7: Cross-reference from the SCSI report**

Add a short section to `src/drivers-ppc/reconstruction/report-scsi.md` pointing
at `$RECON/findings.md`, noting that SCSIServer's artifacts live under
`src/drvSCSIServer/` because it is a top-level architecture-neutral project
rather than a PPC driver, and giving its headline numbers.

- [ ] **Step 8: Final acceptance statement**

In `findings.md`, state against each of the spec's seven acceptance items whether
it passed, with the evidence. Include the standing constraint: **nothing was
compiled**, so every claim is of correspondence to the binary, never of
buildability.

- [ ] **Step 9: Commit**

```bash
cd $REPO && git add $LKS $RECON src/drivers-ppc/reconstruction/report-scsi.md && \
  git commit -m "drvSCSIServer: build IOTask, remap SCSIServer and record acceptance"
```

---

## Self-Review

**Spec coverage.** §1 goal → Tasks 3–5. §2 partition → Task 1 Steps 2, 6. §2.1
classes and ivars → measured in Task 1. §3 six functions → Task 4; §3.1 → Task 3. §4.1 address-0
→ Global Constraints, Task 1 Steps 2/7, Task 5 Step 5. §4.2 mapping route →
Task 1 Steps 3–4, Task 5 Step 3. §4.3 MIG → Task 2. §4.4 disciplines → Global
Constraints. §5 build wiring → Task 5 Steps 1–2. §6 artifacts → Task 1, Task 5
Step 7. §7 acceptance → Task 5 Steps 4–8. §8 constraints → Global Constraints.
§9 risks → Task 4 Step 4, Task 5 Step 2.

**Naming consistency.** `$RECON` is `src/drvSCSIServer/reconstruction/SCSIServer`
throughout. The C symbol `__io_task_notification` is written as the source
function `_io_task_notification` (Task 4 Step 5), matching the existing
`IOReferenceClientTask`/`_IOReferenceClientTask` convention in the same file.
`analysis-named.json` is produced in Task 1 Step 3 and consumed in Steps 4, 6, 7
and Task 5 Step 4.

**Known soft spot.** `$ANALYSIS` is referenced before its exact path is known —
Task 1 Step 1 instructs the implementer to note it from the `analyze` output,
because the filename depends on the analyzer's run naming. This is deliberate,
not a placeholder.
