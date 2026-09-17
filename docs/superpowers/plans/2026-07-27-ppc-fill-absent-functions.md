# Fill Absent Functions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write five absent functions in Mesh and 53c96, and replace Gem's incorrect multicast CRC with the verified in-tree implementation.

**Architecture:** Gem first — its two functions are transcribed from source already proven to match its binary, so it is the highest-confidence work and validates the double-edit discipline. Then 53c96's single small method, then Mesh's four. A final task remaps all three and runs acceptance.

**Spec:** [2026-07-27-ppc-fill-absent-functions-design.md](../specs/2026-07-27-ppc-fill-absent-functions-design.md)

## Global Constraints

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-fill-gaps"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
DISASM="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad/fillgaps-disasm.txt"
cd $REPO
```

- **There is no PowerPC toolchain. Nothing compiles, and you may not claim it does.** Do not run `make`.
- **Mesh and 53c96 exist in two copies. Every change goes into both**, byte-identically. `tools/ppc_package_check.py` must keep reporting `no divergences` — that is acceptance item 6, and it is the check that catches a half-applied edit.
- **Do not touch `drvPPCATA` or `+[PPCBurgundy probe:]`.** Both are deliberately out of scope; see spec §1.3.
- **Do not write `__udivdi3` or `__divdi3`.** They are libgcc compiler runtime.
- **Match each file's existing style.** These are Apple's sources.
- **Do not modify any binrecon code.** Its suite must stay at **845 passed, 4 skipped**.
- **The disassembly is the authority** — not the function name, not a sibling, not what would be reasonable.
- **A confident guess is a defect; a recorded uncertainty is a result.**
- Commits: `drivers-ppc: ` or `driverkit: ` prefix, one to two lines, no metadata/trailers/emoji. One per task.

### Disciplines carried from the IODisplay spec, all of which paid off there

- **Settle method signatures from the binary's `__OBJC,__meth_var_types` encodings**, not by inferring from instructions. That caught a by-pointer/by-value distinction three sibling methods disagreed on.
- **Resolve every `bl` to an unnamed `sub_XXXX` through `read_macho`'s relocation table.** They are jump islands; IDA's export omits the target. `_objc_msgSend` has been the answer every time so far — confirm, do not assume.
- **Read ivar names and offsets from `__OBJC,__instance_vars`,** not from our headers.
- **Trace every bare constant to a named constant in this tree** before writing it as one.

### The file pairs

| Change | Files that must both be edited |
| --- | --- |
| Mesh's four | `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m` and `src/drivers-ppc/scsi/drvPPCMesh/PPCMesh.drvproj/PPCMesh.lksproj/MESH_DBDMA.m` |
| `maxTransfer` | `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m` and `src/drivers-ppc/scsi/drvPPC53c96/PPC53c96.drvproj/PPC53c96.lksproj/Apple96SCSI.m` |
| Gem's two | `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m` — **single copy**, Gem has no kernel-7 origin |

Confirm `maxTransfer`'s home file by finding where `@implementation Apple96_SCSI` (the primary, uncategorised block) lives before editing.

---

## Task 1: Gem — replace the wrong CRC and add `_crc416`

**Files:** `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m`

This is a **correction with a demonstrated runtime consequence**, and the only change in the series with one. Our `_mace_crc` computes different multicast hash indices than Apple's on all five test vectors, so the driver programs the wrong filter bucket.

- [ ] **Step 1: Re-confirm the transcription premise**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
import json
def g(k):
    a=json.load(open(f'tools/binrecon/out/{k}/published/analysis-reference-ida.json'))
    return {(f.get('names') or [None])[0]: b''.join(bytes.fromhex(i['bytes']) for i in f['instructions']) for f in a['functions'] if f.get('names')}
gem,bm,mc=g('gem-ppc'),g('bmac-ppc'),g('mace-ppc')
for n in ('_crc416','_mace_crc'):
    print(f'{n}: gem==bmac {gem.get(n)==bm.get(n)}  gem==mace {gem.get(n)==mc.get(n)}')
"
```

Both lines must read `True True`. **If either is False the transcription premise fails** — this becomes a reconstruction, not a transcription. Stop and report BLOCKED.

- [ ] **Step 2: Read both donor implementations**

```bash
cd $REPO && sed -n '/^static.*crc416/,/^}/p' src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m
sed -n '/^static.*mace_crc/,/^}/p' src/kernel-7/bsd/dev/ppc/drvBMacEnet/BMacEnetPrivate.m
sed -n '/^static.*crc416/,/^}/p' src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m
sed -n '/^static.*mace_crc/,/^}/p' src/kernel-7/bsd/dev/ppc/drvMaceEnet/MaceEnetPrivate.m
```

Both donors should be equivalent. **If BMac's and Mace's differ from each other, say which you chose and why** — do not pick silently.

- [ ] **Step 3: Read what Gem currently has**

```bash
cd $REPO && grep -n "mace_crc\|crc416\|ENET_CRCPOLY" src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m
sed -n '/^static.*_mace_crc/,/^}/p' src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m
```

Note its exact name, signature and every caller — the callers' argument types must still work after replacement, or the callers change too.

- [ ] **Step 4: Replace `_mace_crc` and add `_crc416`**

Transcribe the donor implementations, adapted only as far as Gem's naming requires (its statics carry a leading underscore where BMac's do not — check, and follow Gem's local convention). Any constant the donor uses, such as `ENET_CRCPOLY`, must be defined or reachable in Gem's file; add it in the donor's spelling if absent.

**Delete the old `_mace_crc` body entirely.** Leaving it as dead code or a renamed variant is a defect.

- [ ] **Step 5: Verify the callers still line up**

```bash
cd $REPO && grep -n "_mace_crc\|_crc416" src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/*.m
```

Every call site must match the new signature. The donor takes `unsigned short *`; if Gem's callers pass something else, resolve it and record what you did.

- [ ] **Step 6: Confirm the hash now matches Apple's**

Implement both the new Gem version and Apple's donor in a throwaway script and compare on these five addresses — this is the measured evidence the fix works:

```
01:00:5E:00:00:01   33:33:00:00:00:01   FF:FF:FF:FF:FF:FF   00:00:00:00:00:00   01:23:45:67:89:AB
```

All five must now agree. Before the fix, 0 of 5 did. Put the table in your report.

- [ ] **Step 7: Commit**

```bash
cd $REPO && git add src/drivers-ppc/network/drvPPCGem && \
git commit -m "drivers-ppc: fix GemEnet's multicast CRC and add the missing crc416

Our _mace_crc computed different hash indices than Apple's on every tested
address; replaced with the implementation BMac and Mace already share."
```

---

## Task 2: 53c96 — `maxTransfer`

**Files:** `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m` **and** its `src/drivers-ppc/scsi/drvPPC53c96/…` copy.

`-[Apple96_SCSI maxTransfer]`, 40 bytes at `0x260`. Listing in `$DISASM`.

- [ ] **Step 1: Check the class hierarchy before writing any ivar access**

This method reads an ivar at `+0x268`. IODisplay's reconstruction was blocked because our class derived from `Object` while Apple's derived from `IODevice`, with ~260 bytes of ivars ours lacked.

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY -c "
from binrecon.macho import read_macho
d=read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPC53c96.config/drvPPC53c96_reloc')
print([s.get('name') for s in d['symbols'] if (s.get('name') or '').startswith('.objc_class_name_')])
"
grep -n "@interface Apple96_SCSI" src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/*.h
```

Read the shipped class's `super_class` and `instance_size` from `__OBJC,__class`, and the ivar at `+0x268` from `__OBJC,__instance_vars`, and compare against our `@interface`. **If the layouts disagree, this method is not writable** — record it as such per spec §3.3 and skip to Task 3.

- [ ] **Step 2: Write it**

The disassembly: a load from a relocation targeting `_page_size`, a load of the ivar at `+0x268`, `mullw`, return. The three `crmove lt, lt` are no-ops. Settle the return type from the `__OBJC,__meth_var_types` encoding.

- [ ] **Step 3: Apply to both copies and confirm they are identical**

```bash
cd $REPO && A=src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m
B=src/drivers-ppc/scsi/drvPPC53c96/PPC53c96.drvproj/PPC53c96.lksproj/Apple96SCSI.m
cmp -s "$A" "$B" && echo "identical OK" || echo "DIVERGED"
$VENVPY tools/ppc_package_check.py
```

Must print `identical OK` and `no divergences`.

- [ ] **Step 4: Account for every instruction**, including the no-ops. Put it in your report.

- [ ] **Step 5: Commit**

```bash
cd $REPO && git add src/kernel-7/bsd/dev/ppc/drvApple96_SCSI src/drivers-ppc/scsi/drvPPC53c96 && \
git commit -m "drivers-ppc: write Apple96_SCSI maxTransfer

Reconstructed from drvPPC53c96_reloc; not compile-verified."
```

---

## Task 3: Mesh — the four absent methods

**Files:** `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m` **and** its `src/drivers-ppc/scsi/drvPPCMesh/…` copy.

| Method | Category | Size |
| --- | --- | --- |
| `ResetHardware:reason:` | `(Hardware)` | 76 B |
| `ResetMESH:reason:` | `(Mesh)` | 348 B |
| `IssueAbort` | `(Mesh)` | 352 B |
| `killActiveCommandAndResetBus:reason:` | `(Private)` | 92 B |

All four listings are in `$DISASM`. **`ResetMESH:reason:` and `IssueAbort` are the two largest functions written anywhere in this series** — they are where a dropped branch is most likely to hide.

- [ ] **Step 1: Check the class hierarchy and ivar layout**, as Task 2 Step 1, against `drvPPCMesh_reloc` and `@interface AppleMesh_SCSI` in `MESH_DBDMA.h`. Any method reading an ivar our class lacks is **not writable** — record and skip that one, exactly as `findADBDisplayInfoForType:` was.

- [ ] **Step 2: Write `ResetHardware:reason:` first** — the smallest, and already legible: it forwards its own arguments to `ResetMESH:reason:`, then sends `abortAllCommands:` with `0x14` (20), then returns 0. **Trace `0x14` to a named constant** before writing it as one; if none exists, write the literal with a comment saying so.

- [ ] **Step 3: Write `killActiveCommandAndResetBus:reason:`** (92 B).

- [ ] **Step 4: Write `ResetMESH:reason:`** (348 B) and **`IssueAbort`** (352 B), one at a time, each from its own listing.

- [ ] **Step 5: Account for every instruction in all four**, every branch edge included. For the two large ones this is the substance of the task, not a formality.

- [ ] **Step 6: Apply to both copies and confirm identical**

```bash
cd $REPO && A=src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m
B=src/drivers-ppc/scsi/drvPPCMesh/PPCMesh.drvproj/PPCMesh.lksproj/MESH_DBDMA.m
cmp -s "$A" "$B" && echo "identical OK" || echo "DIVERGED"
$VENVPY tools/ppc_package_check.py
```

- [ ] **Step 7: Confirm each method landed in the right category block**

```bash
cd $REPO && grep -n "@implementation\|@end\|ResetHardware:reason:\|ResetMESH:reason:\|IssueAbort\|killActiveCommandAndResetBus" src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m | head -40
```

`ResetHardware:reason:` belongs in `(Hardware)`, `ResetMESH:reason:` and `IssueAbort` in `(Mesh)`, `killActiveCommandAndResetBus:reason:` in `(Private)`. A method in the wrong block would still map — the source map ignores categories — so **this check is the only thing that catches it.**

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI src/drivers-ppc/scsi/drvPPCMesh && \
git commit -m "drivers-ppc: write AppleMesh_SCSI's four absent methods

Reconstructed from drvPPCMesh_reloc; not compile-verified."
```

---

## Task 4: Remap and acceptance

- [ ] **Step 1: Regenerate all three source maps**

```bash
cd $REPO && REF="C:/Users/raynorpat/Downloads/test/Drivers/ppc" && \
while read -r key bin dir out; do
  PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map --objc-methods --scope-to-objc \
    --reference-analysis tools/binrecon/out/$key/published/analysis-reference-ida.json \
    --binary "$REF/$bin" --source-dir "$dir" --repo-root . \
    --output "src/drivers-ppc/reconstruction/$out/source-map.json"
done <<'EOF'
mesh-ppc drvPPCMesh.config/drvPPCMesh_reloc src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI Mesh
53c96-ppc drvPPC53c96.config/drvPPC53c96_reloc src/kernel-7/bsd/dev/ppc/drvApple96_SCSI 53c96
gem-ppc drvPPCGem.config/drvPPCGem_reloc src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj Gem
EOF
```

- [ ] **Step 2: Confirm the counts moved as expected**

```bash
cd $REPO && $VENVPY -c "
import json
for d in ('Mesh','53c96','Gem'):
    m=json.load(open(f'src/drivers-ppc/reconstruction/{d}/source-map.json'))
    print(f'{d}: mapped {len(m[\"mapped\"])} unmapped {len(m[\"unmapped\"])} dup {len(m[\"duplicate_candidates\"])}')
    for u in m['unmapped']: print('   ', u['reference_names'][0])
"
```

Expected: **Mesh unmapped 6 → 2**, **53c96 3 → 2**, **Gem stays 2** (its two are C functions, outside `--scope-to-objc`). Every remaining unmapped entry must be a build-generated accessor. **If a method you wrote did not map, its selector does not match the binary** — a real signature defect. Report BLOCKED.

If a method was found unwritable in Task 2 or 3, its expected count differs; state the actual outcome against the reason.

- [ ] **Step 3: Re-run bucket reconciliation for all three**

```bash
cd $REPO && for p in "mesh-ppc Mesh" "53c96-ppc 53c96" "gem-ppc Gem"; do set -- $p
  echo "=== $2 ==="
  $VENVPY tools/binrecon/bucket_functions.py \
    tools/binrecon/out/$1/published/analysis-reference-ida.json \
    src/drivers-ppc/reconstruction/$2/source-map.json | grep -E "^total|mapped:|6-|RECONCILES"
done
```

All three must print `RECONCILES: yes`. Gem's `_crc416` should now resolve to source by hand — move it from bucket 6 to bucket 5 in the findings.

- [ ] **Step 4: Verify all three maps load**

Use the four-category scoping (`mapped`, `unmapped`, `duplicate_candidates`, `boundary_disputed`), as every prior spec does.

- [ ] **Step 5: Update the three `findings.md`**

Correspondence, buckets and unmapped-detail sections. For **Gem**, record the multicast correction prominently: what was wrong, the measured 0-of-5 disagreement, the runtime consequence, and that it is now transcribed from BMac/Mace's verified implementation. For **Mesh** and **53c96**, record what was written, carry forward every uncertainty, and record anything found unwritable.

**State plainly that everything written is not compile-verified.**

- [ ] **Step 6: Run the checks**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py && \
  PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

Expected: `no divergences` and **845 passed, 4 skipped**.

- [ ] **Step 7: Walk spec §4's eight acceptance items** with output. **Do not claim anything compiles, links, loads or is behaviourally correct.** Gem's pair carries a stronger claim than the rest — transcribed from source verified against its own binaries — but it is still not a compiled one.

- [ ] **Step 8: Commit**

```bash
cd $REPO && git add src/drivers-ppc/reconstruction && \
git commit -m "drivers-ppc: remap Mesh, 53c96 and Gem after filling their absent functions"
```

---

## Notes for the executing agent

- **Nothing compiles here.** Do not attempt a build or claim one would succeed.
- **Mesh and 53c96 must be edited in both copies.** `ppc_package_check.py` catches a half-applied edit; run it after every task that touches them.
- **Gem is a transcription, not a reconstruction** — its confidence comes from the byte-identity check in Task 1 Step 1. If that check fails, everything downstream changes.
- **Delete Gem's old `_mace_crc`.** A renamed or commented-out copy is a defect.
- **Category placement is only checked by Task 3 Step 7** — the source map will happily map a method in the wrong category block.
- **`ResetMESH:reason:` and `IssueAbort` are the largest bodies in the series.** That is where a dropped branch hides.
