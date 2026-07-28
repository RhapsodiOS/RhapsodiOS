# SCSIServer Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure Apple's shipped `SCSIServer` against `src/drvSCSIServer`, write the nine absent function bodies, and wire `IOTask.m` into the build.

**Architecture:** Measure first, so the gap list is evidence rather than assumption. Verify the MIG `.defs` early, because a mismatch there halts the spec. Then write the four Objective-C construction/teardown methods, then the five C functions, largest last. A final task wires the build, remaps, and runs acceptance.

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

### The nine functions to write

| # | Function | Addr | Size | Task |
| --- | --- | --- | --- | --- |
| 1 | `-[IOSCSISession init]` | `0x0654` | 56 | 3 |
| 2 | `-[IOSCSISession initForDevice:result:]` | `0x068c` | 56 | 3 |
| 3 | `-[SCSIServer initFromDeviceDescription:]` | `0x00e4` | 252 | 3 |
| 4 | `-[IOSCSISession free]` | `0x06c4` | 344 | 3 |
| 5 | `_IODestroyMappedVMTask` | `0x1d98` | 48 | 4 |
| 6 | `_IOTaskPortAllocate` | `0x19bc` | 64 | 4 |
| 7 | `_IOConvertTaskPortToVMTask` | `0x1c98` | 256 | 4 |
| 8 | `_serverThreadFunc` | `0x0a70` | 356 | 4 |
| 9 | `__io_task_notification` | `0x1dc8` | 788 | 4 |

2,220 bytes total. Sizes are next-symbol deltas and include any trailing jump
island; confirm each function's true extent from its `blr` before writing.

Within each task, work smallest first — the small ones establish the idioms the
large ones reuse.

## File Structure

**Created:**
- `$RECON/source-map.json` — map artifact (Task 1)
- `$RECON/ledger.json` — parity ledger (Task 1)
- `$RECON/findings.md` — the measurement, the MIG check, uncertainties (Tasks 1, 2, 5)

**Modified:**
- `$LKS/IOSCSISession.m` — three methods (Task 3)
- `$LKS/SCSIServer.m` — one method (Task 3)
- `$LKS/IOTask.m` — four C functions (Task 4)
- `$LKS/IOTask.h` — declarations for anything newly exposed (Task 4)
- `$LKS/Makefile` — `CLASSES` / `HFILES` (Task 5)

`_serverThreadFunc` and `__io_task_notification` are session/server plumbing, not
task plumbing. Put `_serverThreadFunc` in `IOSCSISession.m` beside the
reservation helpers it works with, and `__io_task_notification` in `IOTask.m`
beside `IOReleaseNotifyForFunc`. Task 4 confirms both placements against what
each function actually references.

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

Expected: exit 0, output under `tools/out/scsiserver-ppc/`. Note the analysis
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
  $ANALYSIS tools/out/scsiserver-ppc/analysis-named.json
```

Expected: exit 0. Re-run the Step 2 snippet against the output; `unnamed` must
now be 0 and `input.sha256` must be unchanged from `$ANALYSIS`.

- [ ] **Step 4: Build the source map — primary route, no `--scope-to-objc`**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map \
  --reference-analysis tools/out/scsiserver-ppc/analysis-named.json \
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
  tools/out/scsiserver-ppc/analysis-named.json \
  $RECON/source-map.json
```

Expected: a bucket table ending in `RECONCILES: yes`. Buckets 1 and 2 are always
empty for a `_reloc` kernel server. Bucket 4 should hold exactly the two
build-generated class methods.

- [ ] **Step 7: Run the PowerPC invariant check**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY tools/binrecon/ppc_invariant_check.py \
  --binary "$REF" --analysis tools/out/scsiserver-ppc/analysis-named.json
```

The tool now distinguishes "no analyzer function and no code" from "no analyzer
function but code is present." Expect the `deviceStyle` line to report **code
present**. Any other violation gets a written explanation — the one violation
deserves more scrutiny than the clean relocations, not less.

- [ ] **Step 8: Write the measurement into findings.md**

Record: the three Step 2 numbers; the route taken in Step 4; the four-category
coverage from Step 5; the bucket table; the invariant-check result; the
`deviceStyle` exclusion and why; and the nine-function gap list confirming this
plan's table. State plainly that nothing was compiled.

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

## Task 3: The four Objective-C methods

**Files:**
- Modify: `$LKS/IOSCSISession.m`, `$LKS/SCSIServer.m`, and the matching `.h` files if a declaration is missing

**Interfaces:**
- Consumes: `$RECON/source-map.json` for addresses; `__OBJC,__meth_var_types` for signatures; `__OBJC,__instance_vars` for ivars.
- Produces: four method bodies. Task 5 remaps and expects them mapped.

These four are the entire construction and teardown path for both classes. Our
source has every operational method but nothing that builds or destroys the
objects.

- [ ] **Step 1: Read the ivars before writing anything**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import struct
P=r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc'
d=read_macho(P); raw=open(P,'rb').read()
secs={s['name']:s for s in d['sections']}
def rd(a,n):
    for s in secs.values():
        if s['address']<=a<s['address']+s['size']:
            o=s['offset']+(a-s['address']); return raw[o:o+n]
def cstr(a):
    b=rd(a,300); return b.split(b'\0')[0].decode('ascii','replace') if b else '?'
c=secs['__OBJC,__class']
for i in range(c['size']//40):
    f=struct.unpack('>10I', rd(c['address']+i*40,40))
    print(f"class {cstr(f[2])} : {cstr(f[1])}  instance_size={f[5]}")
    if f[6]:
        n=struct.unpack('>I', rd(f[6],4))[0]
        for j in range(n):
            nm,tp,off=struct.unpack('>3I', rd(f[6]+4+j*12,12))
            print(f"     +0x{off:04x}  {cstr(tp):<30} {cstr(nm)}")
PY
```

`SCSIServer`'s `instance_size` is 300 and `IOSCSISession`'s is 8, so `SCSIServer`
carries substantial state and `IOSCSISession` exactly one 4-byte ivar. Compare
what this prints against what `SCSIServer.h` and `IOSCSISession.h` currently
declare, and record any divergence — a missing or misordered ivar makes every
offset in these four methods wrong.

- [ ] **Step 2: Settle the four signatures from the type strings**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import struct
P=r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc'
d=read_macho(P); raw=open(P,'rb').read()
secs={s['name']:s for s in d['sections']}
def rd(a,n):
    for s in secs.values():
        if s['address']<=a<s['address']+s['size']:
            o=s['offset']+(a-s['address']); return raw[o:o+n]
def cstr(a):
    b=rd(a,300); return b.split(b'\0')[0].decode('ascii','replace') if b else '?'
for nm in ('__OBJC,__inst_meth','__OBJC,__cls_meth','__OBJC,__cat_inst_meth','__OBJC,__cat_cls_meth'):
    s=secs.get(nm)
    if not s: continue
    a=s['address']; end=a+s['size']
    while a < end:
        _,cnt=struct.unpack('>2I', rd(a,8))
        for j in range(cnt):
            sel,types,imp=struct.unpack('>3I', rd(a+8+j*12,12))
            print(f"  {cstr(sel):<42} {cstr(types):<24} imp=0x{imp:x}")
        a += 8 + cnt*12
PY
```

Type encodings are authoritative: `^I` is a pointer to unsigned int where `I` is
the value, `l` is long, `*` is `char *`, `r*` is `const char *`, `c` is BOOL, `@`
is `id`. Getting `^I` wrong for `I` produces code that compiles and corrupts
memory.

- [ ] **Step 3: Write `-[IOSCSISession init]` (`0x0654`, 56 bytes)**

Smallest first. Disassemble the 56 bytes, resolve every `bl` through the
relocation table, and write the body. Produce an instruction-by-instruction
account covering every branch.

- [ ] **Step 4: Write `-[IOSCSISession initForDevice:result:]` (`0x068c`, 56 bytes)**

Same size as `init`; check whether it shares a tail or an island with it. The
`result:` parameter is an out-pointer — confirm its type from the encoding in
Step 2, not from the name.

- [ ] **Step 5: Write `-[SCSIServer initFromDeviceDescription:]` (`0x00e4`, 252 bytes)**

Note this begins immediately after `+[SCSIServer deviceStyle]`'s region. Confirm
its true start from its own prologue rather than trusting the `0xe4` boundary.
`SCSIServer`'s 300-byte instance means this likely initializes many ivars; each
offset must trace to a named ivar from Step 1.

- [ ] **Step 6: Write `-[IOSCSISession free]` (`0x06c4`, 344 bytes)**

Largest in this task. Teardown mirrors construction: expect it to undo what
`initForDevice:result:` and `initServerWithTask:sendPort:` set up, and to call
into the reservation helpers (`blastAllReservations`) and the task plumbing.
Resolve each call target rather than assuming the mirror.

- [ ] **Step 7: Record uncertainties**

Anything you could not settle from evidence goes into `$RECON/findings.md` as a
numbered uncertainty with what you observed and what you would need. Do not
resolve an ambiguity by picking the plausible option silently.

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add $LKS $RECON/findings.md && \
  git commit -m "drvSCSIServer: write the construction and teardown methods for both classes"
```

---

## Task 4: The five C functions

**Files:**
- Modify: `$LKS/IOTask.m`, `$LKS/IOTask.h`, `$LKS/IOSCSISession.m`

**Interfaces:**
- Consumes: `$RECON/source-map.json`; the `_entry` declaration already in `IOTask.m`.
- Produces: five function bodies. Task 5 remaps and expects them mapped.

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

- [ ] **Step 5: Write `__io_task_notification` (`0x1dc8`, 788 bytes)**

Largest function in the plan. A Mach notification handler — expect a dispatch on
notification type with several branches. Enumerate every branch explicitly; a
missed case here is a silently ignored client death.

The leading double underscore is the Mach-O convention for a source symbol named
`_io_task_notification` (one underscore added by the compiler). Name the C
function `_io_task_notification`, matching how `IOTask.m` already names
`IOReferenceClientTask` for the symbol `_IOReferenceClientTask`.

- [ ] **Step 6: Declare anything newly exposed**

Add declarations to `IOTask.h` only for functions another file calls. Keep
internal helpers static, matching how `IOTask.m` already scopes its own.

- [ ] **Step 7: Record uncertainties**

As Task 3 Step 7. Include explicitly whether the `0x4008`/`0x4088` addresses were
confirmed or corrected.

- [ ] **Step 8: Commit**

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
used. All nine new functions should now map.

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

Expected: `854 passed, 4 skipped`. `PYTHONPATH` is required — without it
collection fails with 25 errors.

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
classes and ivars → Task 3 Step 1. §3 nine functions → Tasks 3, 4. §4.1 address-0
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
