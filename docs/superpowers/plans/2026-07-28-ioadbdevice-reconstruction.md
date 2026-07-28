# IOADBDevice Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write bodies for the fifteen Objective-C methods and six C functions of Apple's shipped `IOADBDevice`, into the existing stub project.

**Architecture:** Structure first — correct the stub's superclass, declare the real ivars, wire the tree's existing ADB headers. Then the small `IOADBDevice` methods, then `ADBServer`'s, then the C character-device layer, largest last. A final task maps and runs acceptance.

**Spec:** [2026-07-28-ioadbdevice-reconstruction-design.md](../specs/2026-07-28-ioadbdevice-reconstruction-design.md)

## Global Constraints

```bash
REPO="D:/RhapsodiOS/.claude/worktrees/ppc-ioadb-recon"
VENVPY="D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe"
DISASM="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/d97cb28c-f6f2-48c4-b66f-85d46244ce4d/scratchpad/ioadb-disasm.txt"
LKS="src/drivers-ppc/input/drvIOADBDevice/IOADBDevice.drvproj/IOADBDevice.lksproj"
cd $REPO
```

- **There is no PowerPC toolchain and no host C compiler. Nothing compiles, and you may not claim it does.** Do not run `make`.
- **Only the four files under `$LKS`** — `IOADBDevice.{h,m}`, `ADBServer.{h,m}` — may be modified, plus that project's `Makefile` if `CLASSES`/`HFILES` change.
- **Never modify `src/kernel-7/`.** `IOADBBus.h`, `IOADBBusProt.h` and `adb.h` are read-only inputs.
- **Do not modify any binrecon code.** Suite must stay green.
- **The disassembly is the authority** — not the function name, not a sibling, not what would be reasonable. `$DISASM` holds all 21 functions with relocation annotations, regenerable from the published analysis.
- **A confident guess is a defect; a recorded uncertainty is a result.** There is no prior source here to constrain a wrong reading, so this matters more than in any previous spec.
- Commits: `drivers-ppc: ` prefix, one to two lines, no metadata/trailers/emoji. One per task.

### Disciplines, each of which has caught a real defect in this series

- **Settle every method signature from `__OBJC,__meth_var_types`**, never by inferring from instructions.
- **Resolve every `bl` to an unnamed `sub_XXXX` through `read_macho`'s relocation table** — jump islands; IDA's export omits the target.
- **Read class hierarchy and ivars from `__OBJC,__class` / `__OBJC,__instance_vars`**, never by inference. That is what caught the stub error this plan fixes.
- **Trace every bare constant to a named constant in this tree** before writing it as one. This has succeeded three times running.
- **Account for every instruction and every branch in writing.**

### Established before this plan — use, do not re-derive

```
class IOADBDevice : Object     instance_size = 8 (0x8)
    +0x0004  ^v                       _priv
class ADBServer  : IODevice    instance_size = 268 (0x10c)
    +0x0108  {ioadb_state="ioadb"@}   state
```

- **The stub wrongly declares `IOADBDevice : IODevice`.** Task 1 corrects it to `Object`.
- **`+[IOADBDevice GetTable:length:]` is at address 0 with no body** — nothing to write. Fourth occurrence of this pattern in the series.
- **`_initalize` is misspelled in Apple's binary. Reproduce the misspelling.**
- **Undefined externals:** `_IOSetUNIXError`, `_NXZoneCalloc`, `_adb_devices`, `_bzero`, `_enodev`, `_kprintf`, `_objc_msgSend`, `_objc_msgSendSuper`, `_panic`, `_printf`, `_sprintf`, `_strcmp`, `_strlen`, `_strtol`.
- **In-tree declarations to reuse, not redeclare:** `IOADBDeviceState`, `IOADBDeviceInfo`, `kIOADBDeviceAvailable`, `@protocol ADBprotocol` in `src/kernel-7/bsd/dev/ppc/IOADBBus.h` and `IOADBBusProt.h`; `extern struct adb_device adb_devices[]` at `adb.h:127`.

### The 21 functions

| Class / kind | Function | Addr | Size | Task |
| --- | --- | --- | --- | --- |
| IOADBDevice | `setState:mask:` | `0x05cc` | 16 | 2 |
| IOADBDevice | `getState` | `0x05dc` | 16 | 2 |
| IOADBDevice | `watchState:mask:` | `0x05ec` | 16 | 2 |
| IOADBDevice | `getADBInfo:` | `0x0484` | 68 | 2 |
| IOADBDevice | `flushADBDevice` | `0x04c8` | 76 | 2 |
| IOADBDevice | `readADBDeviceRegister:buffer:length:` | `0x0514` | 92 | 2 |
| IOADBDevice | `writeADBDeviceRegister:buffer:length:` | `0x0570` | 92 | 2 |
| IOADBDevice | `free` | `0x039c` | 232 | 2 |
| IOADBDevice | `initForDevice:result:` | `0x00e4` | 696 | 2 |
| ADBServer | `+deviceStyle` | `0x08f4` | 16 | 3 |
| ADBServer | `+requiredProtocols` | `0x0904` | 20 | 3 |
| ADBServer | `+serverMajor:` | `0x07d0` | 292 | 3 |
| ADBServer | `getIntValues:forParameter:count:` | `0x0c6c` | 280 | 3 |
| ADBServer | `initFromDeviceDescription:` | `0x0b40` | 300 | 3 |
| ADBServer | `+probe:` | `0x0918` | 552 | 3 |
| C | `_adbServerioctlDispatch` | `0x0fa0` | 236 | 4 |
| C | `_adbServerclose` | `0x0e94` | 268 | 4 |
| C | `_adbServeropen` | `0x0d84` | 272 | 4 |
| C | `_initalize` | `0x05fc` | 468 | 4 |
| C | `_adbServerIoctl` | `0x108c` | 492 | 4 |
| C | `_ioadbDeviceIoctl` | `0x1278` | 760 | 4 |

Within each task, work smallest first — the small ones establish the idioms the large ones reuse.

---

## Task 1: Structure — superclass, ivars, headers

**Files:** `$LKS/IOADBDevice.h`, `$LKS/ADBServer.h`

No method bodies in this task. Get the declarations right first; every later task depends on them.

- [ ] **Step 1: Re-read the class table yourself**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import struct
P=r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOADBDevice.config/IOADBDevice_reloc'
d=read_macho(P); raw=open(P,'rb').read()
secs={s['name']:s for s in d['sections']}
def rd(a,n):
    for s in secs.values():
        if s['address']<=a<s['address']+s['size']:
            o=s['offset']+(a-s['address']); return raw[o:o+n]
def cstr(a):
    b=rd(a,300); return b.split(b'\0')[0].decode('ascii','replace') if b else '?'
cls=secs['__OBJC,__class']
for i in range(cls['size']//40):
    c=struct.unpack('>10I', rd(cls['address']+i*40,40))
    print(f"class {cstr(c[2])} : {cstr(c[1])}   instance_size={c[5]} (0x{c[5]:x})")
    if c[6]:
        cnt=struct.unpack('>I', rd(c[6],4))[0]
        for j in range(cnt):
            nm,tp,off=struct.unpack('>3I', rd(c[6]+4+j*12,12))
            print(f"     +0x{off:04x}  {cstr(tp):<28} {cstr(nm)}")
PY
```

The `objc_class` field order is `isa, super_class, name, version, info, instance_size, ivars, methods, cache, protocols` — index 1 is the superclass, index 2 the name. Getting these two swapped produces plausible nonsense; confirm your output matches the spec's §2.2 block before continuing.

- [ ] **Step 2: Correct `IOADBDevice`'s superclass and declare its ivar**

`IOADBDevice.h:33` currently says `: IODevice`. The binary says `: Object`. Change it, and declare the single ivar `void *_priv` so the layout matches `instance_size = 8` (isa at `+0`, `_priv` at `+4`).

- [ ] **Step 3: Declare `ADBServer`'s ivar**

`ADBServer : IODevice` is already right. Add the `state` ivar at `+0x108`, of struct type `ioadb_state`. Its encoding `{ioadb_state="ioadb"@}` gives the struct tag and one field named `ioadb` of type `@` (an object). Declare the struct with that field; **any further fields you add must come from observed usage in the disassembly**, and each one recorded as derived.

- [ ] **Step 4: Wire in the tree's existing declarations**

Include `IOADBBus.h` / `IOADBBusProt.h` for `IOADBDeviceState`, `IOADBDeviceInfo`, `kIOADBDeviceAvailable` and `@protocol ADBprotocol`, and `adb.h` for `adb_devices[]`. **Do not redeclare any of them.** If an include path is awkward from this project, record the problem rather than duplicating the declaration.

- [ ] **Step 5: Verify the declarations against the binary**

```bash
cd $REPO && grep -n "@interface\|_priv\|ioadb_state\|#import\|#include" $LKS/IOADBDevice.h $LKS/ADBServer.h
```

`IOADBDevice : Object` with `void *_priv`; `ADBServer : IODevice` with `state`; the ADB headers included, nothing redeclared.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add $LKS && git commit -m "drivers-ppc: correct IOADBDevice's superclass and declare both classes' ivars

The class table gives IOADBDevice : Object, not the IODevice the stub assumed."
```

---

## Task 2: The nine `IOADBDevice` methods

**Files:** `$LKS/IOADBDevice.m`, `$LKS/IOADBDevice.h`

Work in the table's order — the three 16-byte accessors first, `initForDevice:result:` (696 B) last.

- [ ] **Step 1: Read all nine listings** in `$DISASM` before writing anything. The three 16-byte methods are almost certainly one-line forwards or returns; establish what they forward to, and that idiom will recur.

- [ ] **Step 2: Settle all nine signatures from the type encodings**

```bash
cd $REPO && PYTHONPATH=tools/binrecon $VENVPY - <<'PY'
from binrecon.macho import read_macho
import struct
P=r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOADBDevice.config/IOADBDevice_reloc'
d=read_macho(P); raw=open(P,'rb').read()
secs={s['name']:s for s in d['sections']}
def rd(a,n):
    for s in secs.values():
        if s['address']<=a<s['address']+s['size']:
            o=s['offset']+(a-s['address']); return raw[o:o+n]
def cstr(a):
    b=rd(a,300); return b.split(b'\0')[0].decode('ascii','replace') if b else '?'
for sec in ('__OBJC,__inst_meth','__OBJC,__cls_meth'):
    s=secs.get(sec)
    if not s: continue
    cnt=struct.unpack('>I', rd(s['address']+4,4))[0]
    print(f'--- {sec} ({cnt}) ---')
    for j in range(cnt):
        nm,tp,imp=struct.unpack('>3I', rd(s['address']+8+j*12,12))
        print(f'  {cstr(nm):<44} {cstr(tp):<24} 0x{imp:x}')
PY
```

Record every signature. Mapping checks only the selector, never the argument types — a wrong type passes unnoticed, so the encoding is the only authority.

- [ ] **Step 3: Write the nine bodies**, smallest first.

- [ ] **Step 4: Account for every instruction and branch** in all nine. Put the mapping in your report.

- [ ] **Step 5: Check the file structure**

```bash
cd $REPO && grep -c "^@implementation\|^@end" $LKS/IOADBDevice.m
grep -nE "^[-+][[:space:]]*\(" $LKS/IOADBDevice.m
```

Nine method definitions; `@implementation`/`@end` balanced.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add $LKS && git commit -m "drivers-ppc: write IOADBDevice's nine methods

Reconstructed from IOADBDevice_reloc; not compile-verified."
```

---

## Task 3: The six `ADBServer` methods

**Files:** `$LKS/ADBServer.m`, `$LKS/ADBServer.h`

Smallest first; `+probe:` (552 B) last — it is the largest method in the driver.

- [ ] **Step 1: Read all six listings.** `+deviceStyle` and `+requiredProtocols` are 16 and 20 bytes and will be near-constant returns; whatever `+requiredProtocols` returns is a protocol list whose contents come from `__OBJC,__protocol` or a `__TEXT,__const` table — resolve it, do not guess.

- [ ] **Step 2: Settle all six signatures** from the type encodings dumped in Task 2 Step 2.

- [ ] **Step 3: Write the six bodies**, smallest first. `initFromDeviceDescription:` and `+probe:` will use `_objc_msgSendSuper`; resolve each `bl` through the relocation table and distinguish `msgSend` from `msgSendSuper` — they mean different things and the island addresses differ.

- [ ] **Step 4: Account for every instruction and branch** in all six. `+probe:` at 552 B is where a dropped branch hides.

- [ ] **Step 5: Check the file structure**, as Task 2 Step 5 — six method definitions, balanced blocks.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add $LKS && git commit -m "drivers-ppc: write ADBServer's six methods

Reconstructed from IOADBDevice_reloc; not compile-verified."
```

---

## Task 4: The six C functions

**Files:** `$LKS/IOADBDevice.m`, `$LKS/ADBServer.m` — place each beside the class it serves, outside any `@implementation` block.

`_adbServeropen`, `_adbServerclose`, `_adbServerioctlDispatch`, `_adbServerIoctl` and `_ioadbDeviceIoctl` form a UNIX character-device interface; `_initalize` is the driver's setup path. Smallest first; `_ioadbDeviceIoctl` (760 B) is the largest function in the driver.

- [ ] **Step 1: Read all six listings.** These are C, so there are no type encodings — **signatures must be derived from the disassembly and from their call sites**, and each recorded as derived. Look at how `_adbServerioctlDispatch` calls the others; the dispatch table shape constrains the signatures.

- [ ] **Step 2: Establish the ioctl command constants**

Every `ioctl` command value must be traced to a named constant in this tree — check `src/kernel-7/bsd/dev/ppc/adb.h`, `IOADBBus.h`, `IOADBBusProt.h` and the `sys/ioctl.h` family. **If no name is found, write the literal with a comment saying so.** Do not invent an `ADBIOC_`-style name.

- [ ] **Step 3: Write the six bodies**, smallest first.

- [ ] **Step 4: Account for every instruction and branch** in all six.

- [ ] **Step 5: Confirm placement and the misspelling**

```bash
cd $REPO && grep -n "initalize\|initialize" $LKS/*.m
grep -n "^@implementation\|^@end\|^static\|^[a-z].*(" $LKS/IOADBDevice.m $LKS/ADBServer.m | head -30
```

`_initalize` must keep Apple's spelling. Every C function must sit outside `@implementation` blocks.

- [ ] **Step 6: Commit**

```bash
cd $REPO && git add $LKS && git commit -m "drivers-ppc: write IOADBDevice's six C functions

The character-device layer and driver setup path; not compile-verified."
```

---

## Task 5: Map, de-stub, and acceptance

- [ ] **Step 1: Remove every stub declaration**

```bash
cd $REPO && grep -rn -i "stub" $LKS/ src/drivers-ppc/input/drvIOADBDevice/dpkg/control
```

Every file that still says "every method body is empty" or similar must be rewritten to describe what it now is: a reconstruction from the shipped binary, not compile-verified. `dpkg/control`'s `STUB` marker goes too. **A file claiming to be a stub when it is not is worse than no note.**

- [ ] **Step 2: Update `CLASSES` / `HFILES` if the file set changed**

```bash
cd $REPO && ls $LKS/*.m $LKS/*.h; grep -n "^CLASSES\|^HFILES" $LKS/Makefile
```

Derive from the directory listing, never from the Makefile.

- [ ] **Step 3: Generate the source map**

```bash
cd $REPO && mkdir -p src/drivers-ppc/reconstruction/IOADBDevice && \
PYTHONPATH=tools/binrecon $VENVPY -m binrecon source-map --objc-methods --scope-to-objc \
  --reference-analysis tools/binrecon/out/ioadbdevice-ppc/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/IOADBDevice.config/IOADBDevice_reloc" \
  --source-dir "$LKS" --repo-root . \
  --output src/drivers-ppc/reconstruction/IOADBDevice/source-map.json
```

- [ ] **Step 4: Confirm all fifteen mapped**

```bash
cd $REPO && $VENVPY -c "
import json
m=json.load(open('src/drivers-ppc/reconstruction/IOADBDevice/source-map.json'))
print('mapped',len(m['mapped']),'unmapped',len(m['unmapped']),'dup',len(m['duplicate_candidates']),'disputed',len(m['boundary_disputed']))
for u in m['unmapped']: print('  ', u['reference_names'][0])
"
```

Expected: **15 mapped**, unmapped only `+[IOADBDevice GetTable:length:]` and the two build-generated accessors. **If a method you wrote did not map, its selector is wrong** — a real defect. Report BLOCKED.

- [ ] **Step 5: Bucket reconciliation and map load**

```bash
cd $REPO && $VENVPY tools/binrecon/bucket_functions.py \
  tools/binrecon/out/ioadbdevice-ppc/published/analysis-reference-ida.json \
  src/drivers-ppc/reconstruction/IOADBDevice/source-map.json
```

Must print `RECONCILES: yes`. Resolve the six C functions from bucket 6 to bucket 5 by hand, citing file and line. Then verify the map loads under four-category scoping, as every prior spec does.

- [ ] **Step 6: Write `findings.md`**

`src/drivers-ppc/reconstruction/IOADBDevice/findings.md`, following `src/drivers-ppc/reconstruction/Mesh/findings.md` for structure. Cover: artifacts with SHA-256, correspondence, map validation, buckets, unmapped detail, the class layout and the stub superclass correction, the six C functions, and **every uncertainty and every invented name**.

**State plainly that nothing is compile-verified**, and that for a driver with no prior in-tree source this gap is wider than in any preceding spec.

- [ ] **Step 7: Answer the calibration question**

Spec §4.1 exists to inform the `DEC21x4Ethernet` decision. Record, as measured facts: how many functions were written, how many were found unwritable and why, how many uncertainties remain, and how many defects the reviews caught. **This is the deliverable that decides whether 55 KB more is worth attempting.**

- [ ] **Step 8: Run the checks**

```bash
cd $REPO && $VENVPY tools/ppc_package_check.py && \
  PYTHONPATH=tools/binrecon $VENVPY -m pytest tools/binrecon/tests -q
```

`no divergences`; the suite green. The new profile adds one entry to the inventory test — update `test_ppc_profile_inventory`'s list if it fails on that, and **do not weaken the assertion**.

- [ ] **Step 9: Walk spec §4's nine acceptance items** with output. **Do not claim anything compiles, links, loads or is behaviourally correct.**

- [ ] **Step 10: Commit**

```bash
cd $REPO && git add src/drivers-ppc tools/binrecon && \
git commit -m "drivers-ppc: map IOADBDevice and record the reconstruction findings"
```

---

## Notes for the executing agent

- **Nothing compiles here.** Do not attempt a build or claim one would succeed.
- **There is no prior source for this driver.** Nothing constrains a wrong reading except the disassembly, so record uncertainty rather than resolving it by plausibility.
- **Argument names, local names and struct field names are invented** — say so, do not imply they were recovered.
- **`_initalize` keeps Apple's misspelling.**
- **Distinguish `_objc_msgSend` from `_objc_msgSendSuper`** — different islands, different meaning.
- **The largest three functions are `_ioadbDeviceIoctl` (760 B), `initForDevice:result:` (696 B) and `+probe:` (552 B).** That is where a dropped branch hides.
