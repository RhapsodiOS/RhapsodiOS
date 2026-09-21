# drvVBE20DisplayDriver Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `VBE20DisplayDriver_reloc` — thirteen hand-written functions over 2,324 bytes of `__text` — against Apple's OPENSTEP 4.2 Patch 4 binary, to a parity target fixed by measurement in Task 1.

**Architecture:** Four phases. Phase 0 (Task 1) stages the reference out of the patch tarball, creates the binrecon profile, and measures Rhapsody's `IOFrameBufferDisplay` chain against the reference's `instance_size` of 552 to fix the parity target. Phase 1 (Task 2) runs IDA, confirms the partition and answers the five discovery items; the source map and ledger are generated in Task 7, once source exists for them to point at. Phase 2 (Tasks 3–7) writes `VBE20DisplayDriver.m` in dependency order, rebuilding and comparing after each group. Phase 3 (Tasks 8–9) closes the ledger, runs the QEMU boot gate, and updates the status docs.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` with IDA Professional 9.2, Rhapsody guest `gnumake` / `pb_makefiles` driven by `vm/sync-src.ps1` + `vm/build-i386-video-recon.sh`, QEMU via `vm/graft-kernel.py` / `vm/rhap_inject.py` / `vm/qemu-shot.py`.

**Spec:** [2026-09-21-vbe20displaydriver-reconstruction-design.md](../specs/2026-09-21-vbe20displaydriver-reconstruction-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
PATCH=C:/Users/raynorpat/Downloads/OS42MachUserPatch4.tar
REFDIR=C:/Users/raynorpat/Downloads/test/Drivers/i386/VBE20DisplayDriver.config
REF=C:/Users/raynorpat/Downloads/test/Drivers/i386/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc
REFSHA=9FBC2CAFBDD0124CC63B902161C86BBFEC0EF48D591DDA681A325FF7B68DADED
DRV=src/drivers-i386/video/drvVBE20DisplayDriver
PROJ=src/drivers-i386/video/drvVBE20DisplayDriver/VBE20DisplayDriver.drvproj
LKS=src/drivers-i386/video/drvVBE20DisplayDriver/VBE20DisplayDriver.drvproj/VBE20DisplayDriver_reloc.lksproj
RECON=src/drivers-i386/video/drvVBE20DisplayDriver/reconstruction
LEDGER=src/drivers-i386/video/drvVBE20DisplayDriver/reconstruction/VBE20DisplayDriver_reloc/ledger.json
MAP=src/drivers-i386/video/drvVBE20DisplayDriver/reconstruction/VBE20DisplayDriver_reloc/source-map.json
DIVERGE=src/drivers-i386/video/drvVBE20DisplayDriver/reconstruction/divergences.md
PROFILE=tools/binrecon/profiles/vbe20displaydriver.json
OUTDIR=tools/binrecon/out/vbe20displaydriver
REBUILT=out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc
IDA_REF=tools/binrecon/out/vbe20displaydriver/published/analysis-reference-ida.json
```

Work in a dedicated worktree, not the main checkout. `.worktrees/` is gitignored.

```bash
git worktree add .worktrees/vbe20-recon HEAD
```

Set `REPO` to that worktree and run every command from there. Parallel sessions
sharing the main checkout's git index destroy each other's commits.

- **Never commit** `$REF`, `$REFDIR`, `tools/binrecon/out/`, `out/i386/`, or the throwaway `compare_vbe20.py`.
- **`BINRECON_REFERENCE` must be exported** in every shell that runs `binrecon` or `parity_check.py`.
- **`BINRECON_REBUILT` must be exported** for `binrecon ledger` and `binrecon compare` (a placeholder file is fine before the first rebuild).
- **Python is `$VENVPY`** with `PYTHONPATH=tools/binrecon`.
- **Do not touch** Cirrus, ThinkPad, VGA or any other driver's sources, `driverTools`, compiler flags, or Ghidra/angr enablement. `vm/build-i386-video-recon.sh` may gain a `drvVBE20DisplayDriver` arm and nothing else.
- **Do not modify** `src/kernel-7` or `src/boot-2` anywhere in this plan. `_VBEModeInfo2IODisplayInfo` stays undefined at link time; specs 2 and 3 own it. Task 3 explains how the link still succeeds.
- **Do not invent.** If the disassembly does not show it, it does not get written. Record the gap in `$DIVERGE` instead.
- **Guest unreachable:** stop. Record it in `$DIVERGE`. Do not invent byte diffs and do not advance the ledger.
- **Commits:** `drvVBE20DisplayDriver: `, `vm: `, or `docs: ` prefix, one to two lines, no metadata, ending with the session's `Co-Authored-By` line.
- **Reviewer:** `Pat Raynor`.

### Known signatures (from the reference's ObjC type encodings)

These are decoded from `__OBJC,__meth_var_types` and are not guesses. Use them verbatim.

```objc
- (id)initUnnamedFromDeviceDescription:(IODeviceDescription *)devDesc;  /* category */
- (id)initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)parseVESAModes:(VBEModeRec *)modes size:(unsigned int)size;
- (void)initDisplayInfo:(IODisplayInfo *)info fromVBEModeInfo:(VBEModeRec *)mode;
- (char *)modeStringForDisplayInfo:(IODisplayInfo *)info;
- (unsigned int)atoi:(const char *)s;
- (IOReturn)getCharValues:(unsigned char *)array
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int *)count;
- (void)enterLinearMode;
- (void)revertToVGAMode;
- (char *)descriptionForDisplayInfo:(IODisplayInfo *)info;
- (char *)descriptionForVBEMode:(VBEModeRec *)mode;
- (unsigned int)displayModeCount;
- (IODisplayInfo *)displayModes;
```

### `IODisplayInfo` is layout-identical across releases

The reference encodes it as `{?=iiiii^vii[64c]I^viiiiiiI[1I]}`. That maps
field-for-field onto Rhapsody's `src/driverkit-3/driverkit/displayDefs.h`:

| Encoding | Rhapsody fields |
| --- | --- |
| `iiiii` | `width`, `height`, `totalWidth`, `rowBytes`, `refreshRate` |
| `^v` | `frameBuffer` |
| `ii` | `bitsPerPixel`, `colorSpace` |
| `[64c]` | `pixelEncoding` (`IOPixelEncoding`, `IO_MAX_PIXEL_BITS` 64) |
| `I` | `flags` |
| `^v` | `parameters` |
| `iiiiii` | `memorySize`, `scanRate`, `_reserved1`, `dotClockRate`, `screenWidth`, `screenHeight` |
| `I` | `modeUnavailableFlag` |
| `[1I]` | `_reserved[1]` |

The driver's own debug string in `__cstring` names those seventeen fields in
exactly that order. **Use Rhapsody's `IODisplayInfo` directly. Do not declare a
local copy.**

---

## File Structure

| File | Responsibility |
| --- | --- |
| `$PROFILE` | binrecon profile; IDA only, matching `cirruslogic-gd5434.json` |
| `$LKS/VBE20DisplayDriver.h` | `VBEModeRec` typedef, class interface, category interface |
| `$LKS/VBE20DisplayDriver.m` | All thirteen hand-written functions, in reference `__text` order |
| `$LKS/Load_Commands.sect` | `Loaded Server` segment content |
| `$LKS/Makefile{,.preamble,.postamble}` | Kernel Server subproject build |
| `$PROJ/Makefile{,.preamble,.postamble}` | Driver bundle build |
| `$PROJ/Default.table` | Verbatim from the patch |
| `$PROJ/English.lproj/Localizable.strings` | Verbatim from the patch |
| `$DRV/Makefile`, `$DRV/Makefile.postamble` | Top-level driver makefiles |
| `$MAP` | Committed `source-map-v1` partition |
| `$LEDGER` | Committed `ledger-v1` parity record |
| `$DIVERGE` | Divergences, discovery answers, measurements |
| `vm/build-i386-video-recon.sh` | Gains one `drvVBE20DisplayDriver` arm |

One source file, because the reference's `__OBJC,__module_info` names exactly
one: `VBE20DisplayDriver.m`. Do not split it.

---

## Task 1: Stage the reference, create the profile, fix the parity target

**Files:**
- Create: `$REFDIR/` (outside the repo, never committed)
- Create: `$PROFILE`
- Create: `$DIVERGE`

**Interfaces:**
- Consumes: nothing.
- Produces: `$REF` on disk at `$REFSHA`; `$PROFILE` validated; a written parity target in `$DIVERGE` that Tasks 3–8 obey.

- [ ] **Step 1: Write the extraction script**

GNU tar and Python `tarfile` both reject this archive: the inner tar uses a
225-byte name field, so every header field sits at +125 from standard. Create
`extract_vbe_ref.py` at the worktree root (do not commit):

```python
"""Extract the VBE20DisplayDriver reference out of OS42MachUserPatch4.tar."""
import gzip, os, re, sys, hashlib

PATCH = sys.argv[1]
DEST = sys.argv[2]
NAME_LEN = 225          # not the standard 100
SIZE_OFF = 249          # standard 124, shifted by +125

def members(buf):
    for m in re.finditer(rb'\./[A-Za-z0-9_./+-]{2,220}', buf):
        i = m.start()
        if i % 512:
            continue
        hdr = buf[i:i + 512]
        name = hdr[:NAME_LEN].split(b'\x00')[0].decode('ascii', 'replace')
        raw = hdr[SIZE_OFF:SIZE_OFF + 12].split(b'\x00')[0].strip()
        if not raw:
            continue
        yield name, int(raw, 8), i + 512

# outer .pkg tar -> inner .tar.Z -> inner tar
outer = open(PATCH, 'rb').read()
inner_z = None
for name, size, off in members(outer):
    if name.endswith('OS42MachUserPatch4.tar.Z'):
        inner_z = outer[off:off + size]
assert inner_z, 'inner tar.Z not found'
inner = gzip.decompress(inner_z)

want = './private/Drivers/i386/VBE20DisplayDriver.config/'
os.makedirs(DEST, exist_ok=True)
for name, size, off in members(inner):
    if not name.startswith(want) or size == 0:
        continue
    rel = name[len(want):]
    out = os.path.join(DEST, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    data = inner[off:off + size]
    open(out, 'wb').write(data)
    print(f'{hashlib.sha256(data).hexdigest().upper()}  {size:8d}  {rel}')
```

- [ ] **Step 2: Run it and verify the reference hash**

```bash
$VENVPY extract_vbe_ref.py "$PATCH" "$REFDIR"
```

Expected: seven files. `VBE20DisplayDriver_reloc` must print size `37984` and
SHA-256 `9FBC2CAFBDD0124CC63B902161C86BBFEC0EF48D591DDA681A325FF7B68DADED`.
`Default.table` must be `482` bytes / `02EF18A5D57FF8DA03543211DB8F12799803B6B2A0A7812114405A4B73C04C15`.

**If the hash differs, stop.** Everything downstream is pinned to it.

- [ ] **Step 3: Create the binrecon profile**

Create `$PROFILE`, identical in shape to `tools/binrecon/profiles/cirruslogic-gd5434.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "drvVBE20DisplayDriver reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": false,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/vbe20displaydriver"
}
```

- [ ] **Step 4: Validate the profile**

```bash
export BINRECON_REFERENCE="$REF"
export BINRECON_REBUILT="$REF"       # placeholder until Task 3 produces a real one
export PYTHONPATH=tools/binrecon
$VENVPY -m binrecon validate --profile "$PROFILE"
```

Expected: exit 0, and the printed reference SHA-256 equals `$REFSHA`.

- [ ] **Step 5: Measure the Rhapsody ivar chain**

> **Done in execution — result recorded here so later tasks need not redo it.**
> The chain is five classes, not four: `IOFrameBufferDisplay : IODisplay :
> IODirectDevice : IODevice : Object`. Subtotals `Object` 4, `IODevice` 260,
> `IODirectDevice` 32, `IODisplay` 212, `IOFrameBufferDisplay` 44 — **total
> 552, equal to the reference.** An earlier draft of this step omitted
> `IODirectDevice` and would have summed 520.

Read the ivar declarations and sum their sizes for i386 (all pointers and `int`
are 4 bytes; `IOPixelEncoding` is `char[64]`):

- `src/driverkit-3/driverkit/IODevice.h`
- `src/driverkit-3/driverkit/IODirectDevice.h`
- `src/driverkit-3/driverkit/IODisplay.h`
- `src/driverkit-3/driverkit/IOFrameBufferDisplay.h`

`IOFrameBufferDisplay` contributes 44 bytes: `priv`, four sample-table
pointers, `_currentDisplayMode`, `_pendingDisplayMode`, `_displayModeCount`,
`_displayModes`, and `_IOFrameBufferDisplay_reserved[2]`.

Compare the total against **552**, the reference's `instance_size`.

- [ ] **Step 6: Record the measurement and fix the target**

Create `$DIVERGE` with the result. If the totals agree:

```markdown
# drvVBE20DisplayDriver divergences

## Measurement: inherited ivar chain (Task 1)

The reference declares no ivars of its own — `__OBJC,__instance_vars` is 0
bytes — so its `instance_size` of 552 measures OPENSTEP 4.2's
`Object` + `IODevice` + `IODirectDevice` + `IODisplay` + `IOFrameBufferDisplay`
chain exactly.

Rhapsody's same chain measures <N> bytes, with per-class subtotals shown.

<N == 552: the chain did not move between releases. Parity target for this
reconstruction is byte-parity throughout.>

<N != 552: the chain moved by <N-552> bytes. Record which functions encode a
shifted offset and target function-parity for those only, citing this entry.>

`IODisplayInfo` is layout-identical across the two releases; see the plan's
Global Constraints for the field-by-field mapping.
```

Keep whichever branch applies; delete the other and the angle brackets.

- [ ] **Step 7: Commit**

```bash
git add "$PROFILE" "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: add the binrecon profile and fix the parity target

Reference staged from OpenStep 4.2 Patch 4; the inherited ivar chain is
measured against the reference's instance_size before any code is written."
```

---

## Task 2: Analyse the reference and commit the partition

**Files:**
- Create: `$MAP`
- Create: `$LEDGER`
- Modify: `$DIVERGE`

**Interfaces:**
- Consumes: `$PROFILE`, `$REF` from Task 1.
- Produces: `$MAP` with fifteen entries covering `__text` 0–2324; `$LEDGER` seeded with every entry `unreviewed`; answers to D1–D5 in `$DIVERGE`.

- [ ] **Step 1: Run IDA over the reference**

```bash
export BINRECON_REFERENCE="$REF"
export BINRECON_REBUILT="$REF"
export PYTHONPATH=tools/binrecon
$VENVPY -m binrecon analyze --profile "$PROFILE" --output "$OUTDIR/run-summary.json"
```

Expected: exit 0 and `$IDA_REF` written.

**Do not point `BINRECON_REBUILT` at `$REF`** for this run. Publication is
all-or-nothing: when the two artifacts are the same file the run fails and
publishes *nothing*, so `$IDA_REF` is never written. Point it at a scratch copy
of the reference outside the repo instead — a different path is enough.

- [ ] **Step 2: Check IDA's partition against the known method offsets**

The ObjC method lists give these `__text` offsets. IDA must agree, modulo
names it cannot know:

| Offset | Size | Function |
| --- | --- | --- |
| 0 | 144 | `-[IOFrameBufferDisplay(UnnamedInitialization) initUnnamedFromDeviceDescription:]` |
| 144 | 548 | `-[VBE20DisplayDriver initFromDeviceDescription:]` |
| 692 | 292 | `-[VBE20DisplayDriver parseVESAModes:size:]` |
| 984 | 20 | `-[VBE20DisplayDriver initDisplayInfo:fromVBEModeInfo:]` |
| 1004 | 188 | `-[VBE20DisplayDriver modeStringForDisplayInfo:]` |
| 1192 | 48 | `-[VBE20DisplayDriver atoi:]` |
| 1240 | 676 | `-[VBE20DisplayDriver getCharValues:forParameter:count:]` |
| 1916 | 8 | `-[VBE20DisplayDriver enterLinearMode]` |
| 1924 | 8 | `-[VBE20DisplayDriver revertToVGAMode]` |
| 1932 | 244 | `-[VBE20DisplayDriver descriptionForDisplayInfo:]` |
| 2176 | 100 | `-[VBE20DisplayDriver descriptionForVBEMode:]` |
| 2276 | 12 | `-[VBE20DisplayDriver displayModeCount]` |
| 2288 | 12 | `-[VBE20DisplayDriver displayModes]` |
| 2300 | 12 | `+[VBE20DisplayDriverKernelServerInstance kernelServerInstance]` |
| 2312 | 12 | `+[VBE20DisplayDriverVersion driverKitVersionForVBE20DisplayDriver]` |

**Fifteen entries.** The 2300 entry was resolved during Task 1: it sits in a
second `__cls_meth` method list the survey parse did not read, and its body is
`55 89 e5 b8 00 00 00 00 89 ec 5d c3` with an external relocation on the
immediate to `_VBE20DisplayDriver_instance`. That also corrects `displayModes`
from 24 bytes to 12. IDA must agree with this table; if it does not, stop and
report rather than adjusting the table to match IDA.

- [ ] ~~**Step 3: Write the source map**~~ — **moved to Task 3.**

> This step was unwritable as specified and is deferred. `source-map-v1`
> requires `source_line` on every `mapped` entry, and its semantic gate
> additionally requires `source_path` to name a file that exists — neither is
> true before Task 3 creates `VBE20DisplayDriver.m`. `binrecon source-map` is
> also a *generator*, not a validator: it takes
> `--binary --source-dir --repo-root --output` and none of the flags this step
> named. Task 3 generates the map from the real source instead. Do not write a
> placeholder all-`unmapped` map: it carries no information and Task 3
> regenerates it.

- [ ] ~~**Step 4: Seed the ledger**~~ — **moved to Task 3**, for the same
reason: `seed_ledger.py` seeds from the map, which does not exist yet.

> When Task 3 runs it, the interface is three arguments, not two:
> `seed_ledger.py MAP REF LEDGER`. The seeded status is **`unexamined`**, not
> `unreviewed`. `rebuilt_sha256` stays absent or null until Task 8 — **never a
> placeholder copy of the reference.**

- [ ] **Step 5: Answer the discovery items**

From the disassembly of the extents above, answer each of D1–D5 in `$DIVERGE`
under a `## Discovery` heading. Record an answer or an explicit "not
determinable from this binary" with the reason. Do not guess.

| | Item | Where to look |
| --- | --- | --- |
| D1 | Where `parseVESAModes:size:` gets its mode array | `initFromDeviceDescription:` at 144, which calls it |
| D2 | `VBEModeInfo2IODisplayInfo`'s signature | The 20-byte forwarder at 984 and the argument setup preceding the call |
| D3 | What `VBEBooterMode` is | Its `__cstring` xrefs |
| D4 | Whether the two 8-byte methods are empty | Extents 1916 and 1924 |
| D5 | Why the driver ships its own `atoi:` | Extent 1192 |

D1 is the one specs 2 and 3 are blocked on. If it is not determinable here, say
so plainly and name the 4.2 kernel i386 slice (SHA-256
`33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890`) and the
4.2 booter (SHA-256 `925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE`)
as the cross-references spec 3 should use.

- [ ] **Step 6: Commit**

```bash
git add "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: answer the five discovery items from the disassembly

Fifteen extents over 2324 bytes of __text confirmed against IDA; the map and
ledger are generated in Task 3, once source exists for them to point at."
```

---

## Task 3: Scaffold the project and land the four trivial methods

**Files:**
- Create: `$DRV/Makefile`, `$DRV/Makefile.postamble`
- Create: `$PROJ/Makefile`, `$PROJ/Makefile.preamble`, `$PROJ/Makefile.postamble`, `$PROJ/DriverInfo`
- Create: `$PROJ/Default.table`, `$PROJ/English.lproj/Localizable.strings` (copied from `$REFDIR`)
- Create: `$LKS/Makefile`, `$LKS/Makefile.preamble`, `$LKS/Makefile.postamble`, `$LKS/Load_Commands.sect`
- Create: `$LKS/VBE20DisplayDriver.h`, `$LKS/VBE20DisplayDriver.m`
- Modify: `vm/build-i386-video-recon.sh`

**Interfaces:**
- Consumes: the partition table and discovery answers from Task 2; the signatures in Global Constraints.
- Produces: `$REBUILT` — a linking `_reloc`; `VBEModeRec` typedef used by Tasks 5–7; `$LKS/VBE20DisplayDriver.m` for later tasks to extend.

This task deliberately covers the four smallest methods so the deliverable is
a *linking binary*, which is the only thing that proves the scaffold works.

- [ ] **Step 1: Copy the verbatim resources**

```bash
mkdir -p "$PROJ/English.lproj"
cp "$REFDIR/Default.table" "$PROJ/Default.table"
cp "$REFDIR/English.lproj/Localizable.strings" "$PROJ/English.lproj/Localizable.strings"
```

Verify `Default.table` still hashes to `02EF18A5D57FF8DA03543211DB8F12799803B6B2A0A7812114405A4B73C04C15`.

- [ ] **Step 2: Write the header**

Create `$LKS/VBE20DisplayDriver.h`. `VBEModeRec` is the 22-byte packed record
from the reference's type encoding `{?=SSSSSCCCCCCCC^v}`, cross-checked against
the driver's own debug format string:

```objc
/*
 * VBE20DisplayDriver.h - VESA 2.0 display driver.
 */

#import <driverkit/IOFrameBufferDisplay.h>
#import <driverkit/displayDefs.h>

/*
 * One VBE mode as the booter hands it over: a distilled form of the
 * 256-byte VBEModeInfoBlock in boot-2's libsaio/vbe.h, 22 bytes.
 * Field order is the reference's type encoding {?=SSSSSCCCCCCCC^v},
 * named from the driver's own log string.
 */
typedef struct {
    unsigned short	modeNumber;		/* 0x00 */
    unsigned short	modeAttributes;		/* 0x02 */
    unsigned short	xResolution;		/* 0x04 */
    unsigned short	yResolution;		/* 0x06 */
    unsigned short	bytesPerScanline;	/* 0x08 */
    unsigned char	bitsPerPixel;		/* 0x0A */
    unsigned char	memoryModel;		/* 0x0B */
    unsigned char	redMaskSize;		/* 0x0C */
    unsigned char	redFieldPosition;	/* 0x0D */
    unsigned char	greenMaskSize;		/* 0x0E */
    unsigned char	greenFieldPosition;	/* 0x0F */
    unsigned char	blueMaskSize;		/* 0x10 */
    unsigned char	blueFieldPosition;	/* 0x11 */
    void		*frameBuffer;		/* 0x14 */
} VBEModeRec;

@interface VBE20DisplayDriver : IOFrameBufferDisplay
{
    /*
     * No instance variables.  The reference's __OBJC,__instance_vars is
     * zero bytes and its instance_size of 552 is entirely inherited.
     */
}

- (id)initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)parseVESAModes:(VBEModeRec *)modes size:(unsigned int)size;
- (void)initDisplayInfo:(IODisplayInfo *)info fromVBEModeInfo:(VBEModeRec *)mode;
- (char *)modeStringForDisplayInfo:(IODisplayInfo *)info;
- (unsigned int)atoi:(const char *)s;
- (char *)descriptionForDisplayInfo:(IODisplayInfo *)info;
- (char *)descriptionForVBEMode:(VBEModeRec *)mode;

@end

@interface IOFrameBufferDisplay (UnnamedInitialization)
- (id)initUnnamedFromDeviceDescription:(IODeviceDescription *)devDesc;
@end
```

`enterLinearMode`, `revertToVGAMode`, `displayModes`, `displayModeCount` and
`getCharValues:forParameter:count:` are inherited declarations and are not
redeclared here.

**If Task 2's answer to D4 shows the 8-byte methods are not empty, or if the
`VBEModeRec` field order disagrees with the disassembly, fix this header to
match the reference before continuing.**

- [ ] **Step 3: Write the four trivial methods**

Create `$LKS/VBE20DisplayDriver.m`. Order the implementations to match the
reference's `__text` order — this is what lets the ledger's extents line up.
Write only these four now; Tasks 4–7 fill in the rest at their reference
positions.

```objc
/*
 * VBE20DisplayDriver.m - VESA 2.0 display driver.
 *
 * Reconstructed against Apple's VBE20DisplayDriver_reloc from OPENSTEP 4.2
 * User Patch 4.  Function order follows the reference's __text.
 */

#import "VBE20DisplayDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/*
 * The mode list lives in two file statics, not in inherited ivars: the
 * reference's displayModes and displayModeCount each load from
 * __DATA,__data with a local relocation, and __data is exactly 8 bytes.
 * The explicit initialisers are what place them in __data rather than
 * __bss -- the same finding drvVGA recorded for IOVGADisplay.m.
 * parseVESAModes:size: (Task 5) is what writes them.
 */
static IODisplayInfo	*vbeDisplayModes = 0;		/* __data + 0 */
static unsigned int	 vbeDisplayModeCount = 0;	/* __data + 4 */

@implementation VBE20DisplayDriver

/* __text 1916, 8 bytes.  The booter owns the mode; nothing to do here. */
- (void)enterLinearMode
{
}

/* __text 1924, 8 bytes. */
- (void)revertToVGAMode
{
}

/* __text 2276, 12 bytes. */
- (unsigned int)displayModeCount
{
    return vbeDisplayModeCount;
}

/* __text 2288, 12 bytes. */
- (IODisplayInfo *)displayModes
{
    return vbeDisplayModes;
}

@end
```

**Do not write `return _displayModeCount;` / `return _displayModes;`.** Those
inherited ivars exist on Rhapsody's `IOFrameBufferDisplay`, so that version
compiles — and silently fails parity, because the reference reads statics.
Task 1 established this from the relocations; see the spec's §6.

Confirm the static order against `__data` once built: `vbeDisplayModes` must
land at `__data + 0` and `vbeDisplayModeCount` at `__data + 4`. If the compiler
orders them the other way, swap the declarations.

The two build-generated entries in this region,
`+kernelServerInstance` at 2300 and `+driverKitVersionForVBE20DisplayDriver` at
2312, are emitted by the Kernel Server project type and **are not written
here**.

- [ ] **Step 4: Write the build files**

Copy each file from `drvCirrusLogicGD5434` and edit it. Do not write these from
scratch — `pb_makefiles` is unforgiving and the Cirrus set is known-good.

```bash
C=src/drivers-i386/video/drvCirrusLogicGD5434
cp $C/Makefile                                     $DRV/Makefile
cp $C/Makefile.postamble                           $DRV/Makefile.postamble
cp $C/CirrusLogicGD5434.drvproj/Makefile           $PROJ/Makefile
cp $C/CirrusLogicGD5434.drvproj/Makefile.preamble  $PROJ/Makefile.preamble
cp $C/CirrusLogicGD5434.drvproj/Makefile.postamble $PROJ/Makefile.postamble
cp $C/CirrusLogicGD5434.drvproj/DriverInfo         $PROJ/DriverInfo
cp $C/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Makefile           $LKS/Makefile
cp $C/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Makefile.preamble  $LKS/Makefile.preamble
cp $C/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Makefile.postamble $LKS/Makefile.postamble
cp $C/CirrusLogicGD5434.drvproj/CirrusLogicGD5434DisplayDriver.lksproj/Load_Commands.sect $LKS/Load_Commands.sect
```

Then set these values. Everything else stays as copied.

| File | Key | Value |
| --- | --- | --- |
| `$DRV/Makefile` | `NAME` | `VBE20DisplayDriver` |
| `$DRV/Makefile` | `TOOLS` | `VBE20DisplayDriver.drvproj` |
| `$DRV/Makefile` | `GLOBAL_RESOURCES` | `Default.table` |
| `$DRV/Makefile` | `LOCAL_RESOURCES` | `Localizable.strings` |
| `$PROJ/Makefile` | `NAME` | `VBE20DisplayDriver` |
| `$PROJ/Makefile` | `TOOLS` | `VBE20DisplayDriver_reloc.lksproj` |
| `$PROJ/Makefile` | `GLOBAL_RESOURCES` | `Default.table` |
| `$PROJ/Makefile` | `LOCAL_RESOURCES` | `Localizable.strings` |
| `$LKS/Makefile` | `NAME` | `VBE20DisplayDriver` |
| `$LKS/Makefile` | `CLASSES` | `VBE20DisplayDriver.m` |
| `$LKS/Makefile` | `HFILES` | `VBE20DisplayDriver.h` |

`NAME` in `$LKS/Makefile` is what produces `VBE20DisplayDriver_reloc`; the
directory name is cosmetic. Cirrus's `GLOBAL_RESOURCES` and `LOCAL_RESOURCES`
list a dozen `.table`/`.modes`/`.strings` files this driver does not have —
replace those lists wholesale rather than editing them down. Drop `Help` from
`LOCAL_RESOURCES` unless the patch's `English.lproj/Help/` turns out to hold
files; Task 1's extraction reported it as an empty directory.

`Load_Commands.sect` must reproduce the reference's `Loaded Server` segment:
`Server Name` 18 bytes, `Load Commands` 164 bytes, `Instance Var` 27 bytes,
`Server Version` 1 byte. Read those four sections out of `$REF` and match them:

```bash
$VENVPY -c "
import struct
d=open('$REF','rb').read()
off=28; ncmds=struct.unpack('<I',d[16:20])[0]
for _ in range(ncmds):
    cmd,cs=struct.unpack('<2I',d[off:off+8])
    if cmd==1:
        seg=d[off+8:off+24].split(b'\x00')[0].decode()
        n=struct.unpack('<I',d[off+48:off+52])[0]; so=off+56
        for i in range(n):
            sn=d[so:so+16].split(b'\x00')[0].decode()
            sz,fo=struct.unpack('<II',d[so+36:so+44])
            if seg=='Loaded Server': print(repr(sn), sz, repr(d[fo:fo+sz]))
            so+=68
    off+=cs
"
```

- [ ] **Step 5: Add the build arm**

In `vm/build-i386-video-recon.sh`, add to the `case` block, keeping POSIX sh:

```sh
	drvVBE20DisplayDriver)
		build_reloc VBE20DisplayDriver drvVBE20DisplayDriver VBE20DisplayDriver.drvproj || fail=1
		;;
```

Do not add it to the default `TARGETS` list; it is built by name.

- [ ] **Step 6: Build on the guest**

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path drivers-i386/video/drvVBE20DisplayDriver
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool $cfg.Ssh
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-video-recon.sh > /tmp/bvideo.sh && sh /tmp/bvideo.sh drvVBE20DisplayDriver'
if ($ec -ne 0) { throw "guest build ssh exit $ec" }
$dst = 'out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$sshHost = "$($cfg.User)@$($cfg.Host)"
$opts = ($script:RhapLegacySshOptions -join ' ')
$remoteTar = "cd /build/out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config && tar cf - VBE20DisplayDriver_reloc"
Invoke-RhapSshAskPass -Cfg $cfg -Action {
    cmd /c "ssh $opts $sshHost `"$remoteTar`" | tar xf - -C $dst"
    if ($LASTEXITCODE -ne 0) { throw "tar pull exit $LASTEXITCODE" }
}
```

If the guest `vm/build-i386-video-recon.sh` is stale, copy that one file across
the same way the Cirrus finish plan does — not `sync-src.ps1 -All`.

Expected: `make exit=0`, `compiled … VBE20DisplayDriver.o`, `relocatable link
produced …VBE20DisplayDriver_reloc`, and `$REBUILT` exists.

- [ ] ~~**Step 7: Confirm the kernel symbol stays undefined**~~ — **moved to Task 5.**

> Unsatisfiable here. Nothing in Task 3's four methods references
> `_VBEModeInfo2IODisplayInfo`, so it cannot appear in the symbol table at all;
> only Task 5's `initDisplayInfo:fromVBEModeInfo:` forwarder will pull it in.
> **Do not write a stub to make it appear.** The link model is already proven
> by the undefined externals that *are* present — `.objc_class_name_IODevice`,
> `_IOFrameBufferDisplay` and `_Object` are all type `0x01` and the link
> succeeded, so `kl_ld` leaves undefined externals alone as expected.

<details><summary>Original step (run it in Task 5)</summary>

```bash
$VENVPY -c "
import struct
d=open('$REBUILT','rb').read()
off=28; ncmds=struct.unpack('<I',d[16:20])[0]
for _ in range(ncmds):
    cmd,cs=struct.unpack('<2I',d[off:off+8])
    if cmd==2:
        so,n,stro,strs=struct.unpack('<4I',d[off+8:off+24])
        for i in range(n):
            e=so+i*12; strx,ty,sect,desc,val=struct.unpack('<IBBHI',d[e:e+12])
            nm=d[stro+strx:].split(b'\x00')[0].decode()
            if 'VBE' in nm or ty&0x0e==0: print(f'{nm:42s} type=0x{ty:02x}')
    off+=cs
"
```

Expected: `_VBEModeInfo2IODisplayInfo` present with type `0x01` (undefined
external). A relocatable `_reloc` link does not resolve undefined externals, so
this is correct and expected — spec 2 supplies the definition. **If the link
fails on it instead, stop and report; the Kernel Server link flags are wrong.**

</details>

- [ ] **Step 8: Commit**

```bash
git add "$DRV" vm/build-i386-video-recon.sh
git commit -m "drvVBE20DisplayDriver: scaffold the project and land the trivial methods

Project wrapper, header with the 22-byte VBEModeRec, the four smallest
methods and a guest build arm; the _reloc links with the kernel's
VBEModeInfo2IODisplayInfo still undefined."
```

---

## Task 4: `initFromDeviceDescription:` and the category initialiser

**Files:**
- Modify: `$LKS/VBE20DisplayDriver.m`
- Modify: `$MAP` (source-line bounds)

**Interfaces:**
- Consumes: `VBEModeRec` and the class interface from Task 3; D1's answer from Task 2.
- Produces: the driver's init path, calling `parseVESAModes:size:` (Task 5).

These two are one task because the category initialiser at `__text` 0 exists
only to serve `initFromDeviceDescription:` at 144, and a reviewer cannot
sensibly accept one without the other.

- [ ] **Step 1: Disassemble both extents**

```bash
$VENVPY -c "
import json
a=json.load(open('$IDA_REF'))
for f in a['functions']:
    if f['address'] in (0,144):
        print(f['address'], f.get('name'), f['size'])
        for ins in f.get('instructions',[]):
            print(f\"  {ins['address']:5d} {ins.get('text','')}\")
"
```

- [ ] **Step 2: Write both functions**

Add to `$LKS/VBE20DisplayDriver.m`, placing the category implementation
**before** `@implementation VBE20DisplayDriver` so its code lands at `__text` 0,
and `initFromDeviceDescription:` as the first method inside the class
implementation so it lands at 144.

Write what the disassembly shows. The strings it must reference, from the
reference's `__cstring`, are:

```
%s: VESA video driver initialization.
%s: Skipping framebuffer initialization (card not in VBE mode).
%s: Driver loaded to export VBE mode list.
%s: Unable to map frame buffer
%s: using VBE mode %d
%s: No VBE modes found.
VBEDisplay: Error in setMemoryRangeList (%s)
VBEDisplay0
VBEMode
VBEBooterMode
```

> **Reproduce Apple's defect verbatim.** Task 2 found that
> `initFromDeviceDescription:` sizes the frame buffer as
> `bytesPerScanLine * XResolution` where the correct term is `YResolution`.
> It is a typo in the reference and it is **in scope to reproduce exactly** —
> this tree reproduces reference defects rather than fixing them, as drvVGA
> does for `probe:` returning YES unconditionally. Do not "fix" it, and record
> it in `$DIVERGE` as a reproduced reference defect so a later reader does not
> mistake it for ours.
>
> Task 2 also noted `VBEBooterMode<N>` is unbounded where the other three
> indexed parameters are guarded. Check whether that belongs to this extent or
> to `getCharValues:` (Task 7) and record it with the same treatment.

- [ ] **Step 3: Rebuild on the guest**

Repeat Task 3 Step 6 verbatim.

Expected: `make exit=0` and a fresh `$REBUILT`.

- [ ] **Step 4: Compare the two extents**

Create `compare_vbe20.py` at the worktree root (do not commit). It masks 32-bit
relocation operands, the same idea as `compare_thinkpad.py` in the ThinkPad
plan:

```python
"""Masked instruction-stream compare for drvVBE20DisplayDriver.

Reads __text out of both Mach-O files and zeroes every 32-bit relocated
operand before comparing, so __cstring addresses -- which legitimately
differ between the reference and our build -- do not read as deltas.

Handles BOTH relocation forms.  A scattered entry sets bit 31 of the first
word and packs its address and length there; a reader that always takes the
length from the second word leaves scattered operands unmasked and reports
false diffs.  The reference carries three scattered relocations in __text,
so the naive form fails on initFromDeviceDescription: specifically.
"""
import struct, sys

# reference __text offsets; each size is the delta to the next entry
EXTENTS = {
    0: "-[IOFrameBufferDisplay(UnnamedInitialization) initUnnamedFromDeviceDescription:]",
    144: "-[VBE20DisplayDriver initFromDeviceDescription:]",
    692: "-[VBE20DisplayDriver parseVESAModes:size:]",
    984: "-[VBE20DisplayDriver initDisplayInfo:fromVBEModeInfo:]",
    1004: "-[VBE20DisplayDriver modeStringForDisplayInfo:]",
    1192: "-[VBE20DisplayDriver atoi:]",
    1240: "-[VBE20DisplayDriver getCharValues:forParameter:count:]",
    1916: "-[VBE20DisplayDriver enterLinearMode]",
    1924: "-[VBE20DisplayDriver revertToVGAMode]",
    1932: "-[VBE20DisplayDriver descriptionForDisplayInfo:]",
    2176: "-[VBE20DisplayDriver descriptionForVBEMode:]",
    2276: "-[VBE20DisplayDriver displayModeCount]",
    2288: "-[VBE20DisplayDriver displayModes]",
    2300: "+[VBE20DisplayDriverKernelServerInstance kernelServerInstance]",
    2312: "+[VBE20DisplayDriverVersion driverKitVersionForVBE20DisplayDriver]",
}
BOUNDS = sorted(EXTENTS) + [2324]

def text(path):
    d = open(path, "rb").read()
    off, ncmds = 28, struct.unpack("<I", d[16:20])[0]
    for _ in range(ncmds):
        cmd, cs = struct.unpack("<2I", d[off:off + 8])
        if cmd == 1:                                   # LC_SEGMENT
            nsects = struct.unpack("<I", d[off + 48:off + 52])[0]
            so = off + 56
            for _ in range(nsects):
                name = d[so:so + 16].split(b"\0")[0].decode()
                addr, size, foff, _al, roff, nrel = struct.unpack(
                    "<6I", d[so + 32:so + 56])
                if name == "__text":
                    rels = []
                    for k in range(nrel):
                        w0, w1 = struct.unpack("<2I", d[roff + k * 8:roff + k * 8 + 8])
                        if w0 & 0x80000000:            # scattered
                            rels.append((w0 & 0x00FFFFFF, (w0 >> 28) & 3))
                        else:
                            rels.append((w0, (w1 >> 25) & 3))
                    return d[foff:foff + size], rels
                so += 68
        off += cs
    raise SystemExit("no __TEXT,__text in " + path)

def mask(buf, rels):
    b = bytearray(buf)
    for addr, length in rels:
        if length == 2 and addr + 4 <= len(b):         # 32-bit operand
            b[addr:addr + 4] = b"\0\0\0\0"
    return bytes(b)

ref, refrel = text(sys.argv[1])
new, newrel = text(sys.argv[2])
ref, new = mask(ref, refrel), mask(new, newrel)
only = [int(x) for x in sys.argv[3:]] or sorted(EXTENTS)
for i, start in enumerate(sorted(EXTENTS)):
    if start not in only:
        continue
    end = BOUNDS[i + 1]
    if end > len(new):
        print("%5d %-28s %s" % (start, "NOT YET BUILT", EXTENTS[start]))
        continue
    a, b = ref[start:end], new[start:end]
    n = sum(x != y for x, y in zip(a, b))
    verdict = "MATCH" if a == b else "DIFF (%d bytes)" % n
    print("%5d %-28s %s" % (start, verdict, EXTENTS[start]))
```

Run it for this task's two extents:

```bash
export PYTHONPATH=tools/binrecon
$VENVPY compare_vbe20.py "$REF" "$REBUILT" 0 144
```

Expected: `MATCH` for both under a byte-parity target. Under a function-parity
target these two still target byte-parity — neither reads an ivar.

- [ ] **Step 5: Iterate until both match, or record why not**

If an extent differs, re-read the disassembly and correct the source. If a
delta survives and its cause is understood and compiler-only, record it in
`$DIVERGE` with the instruction-level evidence and mark it for
`control-flow-confirmed` in Task 8. **Do not mark it matched.**

- [ ] **Step 6: Commit**

`$MAP` is generated once from the complete source in Task 7; there is nothing
to update here.

```bash
git add "$LKS/VBE20DisplayDriver.m" "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: reconstruct the init path

The unnamed-initialisation category at __text 0 and
initFromDeviceDescription: at 144."
```

---

## Task 5: `parseVESAModes:size:`, `initDisplayInfo:fromVBEModeInfo:`, `atoi:`

**Files:**
- Modify: `$LKS/VBE20DisplayDriver.m`
- Modify: `$MAP`

**Interfaces:**
- Consumes: `VBEModeRec` from Task 3; D1 and D2 from Task 2.
- Produces: the mode-list parse that `initFromDeviceDescription:` calls, and the `_VBEModeInfo2IODisplayInfo` call site — the sole kernel dependency, which spec 2 implements against.

Grouped because all three concern turning the booter's mode array into
`IODisplayInfo` records. `atoi:` belongs here: it parses the `"VBE Mode"` table
value that selects from that array.

- [ ] **Step 1: Disassemble extents 692, 984 and 1192**

Reuse Task 4 Step 1's command with `(692, 984, 1192)`.

- [ ] **Step 2: Write the three functions**

Add them to `$LKS/VBE20DisplayDriver.m` in `__text` order: `parseVESAModes:size:`
after `initFromDeviceDescription:`, then `initDisplayInfo:fromVBEModeInfo:`,
then `modeStringForDisplayInfo:`'s slot is left for Task 6, then `atoi:`.

`initDisplayInfo:fromVBEModeInfo:` is 20 bytes and is expected to be a straight
forward to the kernel:

```objc
/* __text 984, 20 bytes. */
- (void)initDisplayInfo:(IODisplayInfo *)info fromVBEModeInfo:(VBEModeRec *)mode
{
    VBEModeInfo2IODisplayInfo(mode, info);
}
```

**Argument order and types come from D2, not from this sketch.** Declare the
extern to match what the disassembly shows, above `@implementation`:

```objc
extern void VBEModeInfo2IODisplayInfo(VBEModeRec *mode, IODisplayInfo *info);
```

- [ ] **Step 3: Rebuild on the guest**

Repeat Task 3 Step 6 verbatim.

- [ ] **Step 4: Compare**

```bash
$VENVPY compare_vbe20.py "$REF" "$REBUILT" 692 984 1192
```

Expected: `MATCH` for all three.

- [ ] **Step 5: Iterate or record**

As Task 4 Step 5.

- [ ] **Step 6: Commit**

```bash
git add "$LKS/VBE20DisplayDriver.m" "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: reconstruct the mode-list parse

parseVESAModes:size:, the VBEModeInfo2IODisplayInfo forwarder and the
driver's own atoi:."
```

---

## Task 6: The three description builders

**Files:**
- Modify: `$LKS/VBE20DisplayDriver.m`
- Modify: `$MAP`

**Interfaces:**
- Consumes: `VBEModeRec`, `IODisplayInfo` from Task 3.
- Produces: `modeStringForDisplayInfo:`, `descriptionForDisplayInfo:` and `descriptionForVBEMode:`, which `getCharValues:forParameter:count:` (Task 7) calls.

- [ ] **Step 1: Disassemble extents 1004, 1932 and 2176**

Reuse Task 4 Step 1's command with `(1004, 1932, 2176)`.

- [ ] **Step 2: Write the three functions**

These are `sprintf`/`strcat`/`strcpy`-heavy. The literals they assemble, from
the reference's `__cstring`, are:

```
Height:%d Width:%d Refresh:0Hz ColorSpace:
RGB:     256/8     444/16     555/16     888/32     BW:     2     8
IO_2BitsPerPixel    IO_8BitsPerPixel   IO_12BitsPerPixel
IO_15BitsPerPixel   IO_24BitsPerPixel  IO_VGA
IO_OneIsBlackColorSpace   IO_OneIsWhiteColorSpace
IO_RGBColorSpace          IO_CMYKColorSpace
width=%d height=%d totalWidth=%d rowBytes=%d refreshRate=%d frameBuffer=%x bitsPerPixel=%s colorSpace=%s pixelEncoding=%s flags=%x parameters=%x memorySize=%d scanRate=%d dotClockRate=%d screenWidth=%d screenHeight=%d modeUnavailableFlag=%x
mode num: %d, Attrib: %x, BytesPerScanline: %d, FrameBuffer: %x,
XRes: %d, YRes: %d, BitsPerPixel: %d, MemoryModel: %d,
RGB Mask Sizes: (%d, %d, %d), RGB Field Pos: (%d, %d, %d)
```

The last two are single strings with embedded newlines. Reproduce them exactly,
newlines included — `parity_check.py` in Task 8 compares the string table.

- [ ] **Step 3: Rebuild on the guest**

Repeat Task 3 Step 6 verbatim.

- [ ] **Step 4: Compare**

```bash
$VENVPY compare_vbe20.py "$REF" "$REBUILT" 1004 1932 2176
```

Expected: `MATCH` for all three. These are the functions where register
allocation is most likely to differ; see the spec's §9.

- [ ] **Step 5: Iterate or record**

As Task 4 Step 5.

- [ ] **Step 6: Commit**

```bash
git add "$LKS/VBE20DisplayDriver.m" "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: reconstruct the description builders

modeStringForDisplayInfo:, descriptionForDisplayInfo: and
descriptionForVBEMode:."
```

---

## Task 7: `getCharValues:forParameter:count:`

**Files:**
- Modify: `$LKS/VBE20DisplayDriver.m`
- Modify: `$MAP`

**Interfaces:**
- Consumes: all three description builders from Task 6.
- Produces: the four driver parameters the Configure.app inspector reads.

676 bytes, the largest single function, and the last one. It gets its own task
because a reviewer can meaningfully accept Task 6 and reject this.

- [ ] **Step 1: Disassemble extent 1240**

Reuse Task 4 Step 1's command with `(1240,)`.

- [ ] **Step 2: Write the function**

It dispatches on `parameterName` against these four `__cstring` literals and
fills `array`/`count`:

```
VBEModeCount   VBECurrentMode   VBEModeDescription   VBEModeNumber
```

The inspector half calls `getCharValues:forParameter:objectNumber:count:` for
exactly these four, which corroborates the set.

- [ ] **Step 3: Rebuild on the guest**

Repeat Task 3 Step 6 verbatim.

- [ ] **Step 4: Compare the whole partition**

```bash
$VENVPY compare_vbe20.py "$REF" "$REBUILT"
```

Expected: every extent reported, `MATCH` for all thirteen hand-written ones
under a byte-parity target.

- [ ] **Step 5: Iterate or record**

As Task 4 Step 5.

- [ ] **Step 6: Generate the source map and seed the ledger**

All thirteen functions exist now, so the map can finally be produced. Task 2
deferred this because `source-map-v1` requires a `source_line` on every
`mapped` entry *and* a `source_path` naming a real file.

`binrecon source-map` is a **generator**, not a validator — it derives the map
from the binary and the source tree, and takes none of the flags earlier drafts
of this plan named:

```bash
$VENVPY -m binrecon source-map --binary "$REF"   --source-dir "$LKS" --repo-root . --output "$MAP"
$VENVPY tools/binrecon/seed_ledger.py "$MAP" "$REF" "$LEDGER"
```

`seed_ledger.py` takes **three** arguments: map, reference, ledger.

Expected: fifteen entries covering `__text` 0–2324 with no gaps, every ledger
entry at status **`unexamined`**, `reference_sha256` equal to `$REFSHA`, and
`rebuilt_sha256` absent or null. **Never seed `rebuilt_sha256` with a copy of
the reference hash** — Task 8 fills it from the real rebuild.

- [ ] **Step 7: Commit**

```bash
git add "$LKS/VBE20DisplayDriver.m" "$MAP" "$LEDGER" "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: reconstruct getCharValues:forParameter:count:

The four VBE driver parameters the Configure.app inspector reads."
```

---

## Task 8: Close the parity ledger

**Files:**
- Modify: `$LEDGER`, `$DIVERGE`

**Interfaces:**
- Consumes: `$REBUILT` from Task 7; every comparison result from Tasks 4–7.
- Produces: a ledger with no `unreviewed` entries and real hashes on both sides.

- [ ] **Step 1: Run the string and symbol parity check**

```bash
export BINRECON_REFERENCE="$REF"
export BINRECON_REBUILT="$REBUILT"
export PYTHONPATH=tools/binrecon
$VENVPY tools/binrecon/parity_check.py "$REF" "$REBUILT"
```

Expected: no reference string or text symbol missing from our build. Extras on
our side are expected — guest builds are unstripped — and are not findings.

- [ ] **Step 2: Run the full binrecon comparison**

```bash
$VENVPY -m binrecon analyze --profile "$PROFILE" \
  --ledger "$LEDGER" --output "$OUTDIR/run-summary.json"
$VENVPY -m binrecon compare --profile "$PROFILE" \
  --reference-analysis "$IDA_REF" \
  --rebuilt-analysis "$OUTDIR/published/analysis-rebuilt-ida.json" \
  --output "$OUTDIR/comparison.json" --text-output - \
  --require normalized-functions
```

- [ ] **Step 3: Ledger every entry**

For each of the thirteen hand-written extents, make one reviewed transition:

```bash
$VENVPY -m binrecon ledger --profile "$PROFILE" --ledger "$LEDGER" \
  --address 0x<addr> --status assembly-matched \
  --source-path "$LKS/VBE20DisplayDriver.m" --source-line <line>
```

### Three build-generated divergences are exempt — decided, do not re-litigate

Task 3's first link surfaced these at `__text` 2300..2324 and in the version
data. No source change can close them, and closing two of them would be wrong.

| Divergence | Ruling |
| --- | --- |
| `+driverKitVersionForVBE20DisplayDriver` returns `0x1F4` (500) where the reference returns `0x1A4` (420) | **Exempt, and must stay.** That is `IO_DRIVERKIT_VERSION` from `src/driverkit-3/driverkit/IODevice.h:45` — 500 in Rhapsody, 420 in DriverKit 4.2. It is the cross-release difference appearing exactly where it should. Forcing 420 would falsify the build. |
| `_VBE20DisplayDriver_instance` is an unallocated common in the reference (undefined, `n_value` 4, external reloc); our link allocates it in `__common` at `0x2008` | **Exempt at ledger level, but flag it.** A build-generated Kernel Server symbol. It *may* matter at load time — Task 9's boot gate is what would reveal it. Record the possibility in `$DIVERGE` so a load failure there is not misdiagnosed. |
| Version string `PROGRAM:VBE20DisplayDriver_reloc` under `_VBE20DisplayDriver_reloc_vers` (160 bytes) versus our 112-byte `…VersionString` | **Exempt, worth one look.** Generated from the project name at build time. If a `VERS_OFILE` or project-name setting closes it cheaply, take it; do not spend a phase on it. |

Ledger all three `control-flow-confirmed` citing this table, not `assembly-matched`.

Status vocabulary, matching Cirrus and ThinkPad:

| Status | When |
| --- | --- |
| `assembly-matched` | masked instruction streams identical |
| `control-flow-confirmed` | a delta whose cause is understood and recorded in `$DIVERGE` |

An intentional mismatch also requires a reason and `--reviewer "Pat Raynor"`.
The two build-generated entries are not ledgered against source.

- [ ] **Step 4: Verify the ledger is complete**

```bash
$VENVPY -m binrecon ledger --profile "$PROFILE" --ledger "$LEDGER"
```

Expected: no entry `unreviewed`; `reference_sha256` equals `$REFSHA`;
`rebuilt_sha256` is the real hash of `$REBUILT` and **not** a copy of the
reference.

- [ ] **Step 5: Commit**

```bash
git add "$LEDGER" "$DIVERGE"
git commit -m "drvVBE20DisplayDriver: close the parity ledger

Every __text extent reviewed against the reference with real hashes on
both sides."
```

---

## Task 9: Boot gate and status docs

**Files:**
- Modify: `src/drivers-i386/README`
- Modify: `docs/drivers/video-reconstruction.md`
- Create: `docs/drivers/drvVBE20DisplayDriver-boot-gate.md`

**Interfaces:**
- Consumes: `$REBUILT` from Task 7, ledgered in Task 8.
- Produces: evidence the driver loads, and accurate status lines.

- [ ] **Step 1: Stage the bundle**

The `_reloc` alone is not enough — `install-driver.py` installs a directory.
The guest build already staged one at
`out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config` containing the
`_reloc`, `Default.table` and `English.lproj`. Confirm it, and that the
`_reloc` there hashes the same as `$REBUILT`.

**Do not use `rhap_inject.py put` to create the bundle.** It has only
`set-key` and `put`, both of which repoint an *existing* directory entry;
neither can create a path. `VBE20DisplayDriver.config` does not exist in
`golden.img`.

- [ ] **Step 2: Build the test image**

`vm/install-driver.py SRC_IMAGE DRIVER_DIR OUT_IMAGE` allocates the new bundle,
writes `Instance0.table` from `Default.table` when the bundle ships none — ours
ships none — and registers the name in the `Boot Drivers` key of
`/private/Drivers/i386/System.config/Instance0.table`. That matches this
driver's `"Boot Driver" = "Yes"`.

Graft our kernel first, because `graft-kernel.py` rebuilds its output from
`golden.img` and would discard an earlier driver install:

```bash
cd vm
MSYS_NO_PATHCONV=1 python graft-kernel.py golden.img install/mach_kernel work/kern.img
MSYS_NO_PATHCONV=1 python install-driver.py work/kern.img \
    ../out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config work/test.img
```

`install-driver.py` produces a fresh clone per run, so `rhap_inject.py`'s
`check_target` — which allows writes only to exactly `vm/work/test.img` — may
refuse a follow-up `set-key` against a differently-named output. Name the final
image `work/test.img`, as above, if any `set-key` is needed afterwards.

- [ ] **Step 3: Hash-verify before booting**

Extract the installed `_reloc` back out of `work/test.img` and compare its
hash against `$REBUILT`. The bus retest's PCIC near-miss showed a refused
injection still produces a plausible-looking boot of somebody else's driver.
**This step is not optional.**

- [ ] **Step 4: Boot and capture**

```bash
python qemu-shot.py work/test.img shots-vbe20 --at 30,60,95 --keys "mach_kernel -v\n"
```

- [ ] **Step 5: Check the expected output**

Look for these two `__cstring` entries reaching the console, plus registration:

```
%s: VESA video driver initialization.
%s: Skipping framebuffer initialization (card not in VBE mode).
Registering: VBEDisplay0
```

The `%s` is the driver's `name`; match on the fixed text, not the prefix.

**The "Skipping framebuffer initialization" path is the expected and correct
result for this spec.** The booter never enters a VBE mode — `"Graphics Mode"`
is set in no config table, so `boot2/graphics.c`'s `setMode()` falls through to
text. Spec 3 makes the `%s: using VBE mode %d` path reachable and gates it
there. Reaching this line still proves load, initialisation, config-table read
and registration.

If the driver does not appear at all, check two things before suspecting the
reconstruction:

1. **Did the root device come up?** Drivers are instantiated only after it, and
   `drvEIDE-issues.md` documents a failure that looks like a display problem
   but is not. The grafted kernel in Step 2 is what clears it.
2. **Is `Boot Drivers` registration enough?** `install-driver.py` registers the
   name there, which matches `"Boot Driver" = "Yes"`. The drvVGA gate instead
   used the `Active Drivers` key. If the bundle loads but never instantiates,
   add it to `Active Drivers` as well:

```bash
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img \
    set-key /private/Drivers/i386/System.config/Instance0.table \
    "Active Drivers" "VBE20DisplayDriver PS2Mouse NE2K"
```

`set_table_key` never allocates, so the replacement value must fit the existing
fragment count. Record in the gate document which key actually worked — it is
the first Boot-Driver-declaring display driver this tree has gated.

- [ ] **Step 6: Write the gate record**

Create `docs/drivers/drvVBE20DisplayDriver-boot-gate.md` in the shape of
`drvVGA-boot-gate.md`: the procedure, the hashes, the captured output, and an
explicit "what this does and does not establish" section naming the framebuffer
path as unexercised.

- [ ] **Step 7: Update the status docs**

Add a row to the coverage table in `docs/drivers/video-reconstruction.md` with
the real partition and mapped counts, and a line to the `video` section of
`src/drivers-i386/README`. Both must state the reference is OPENSTEP 4.2, not
Rhapsody — this is the only driver in the tree reconstructed across releases.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/README docs/drivers/
git commit -m "drvVBE20DisplayDriver: record the boot gate and update status

The driver loads, initialises and registers as VBEDisplay0; the framebuffer
path waits on the booter and kernel specs."
```

---

## Follow-on

Specs 2 and 3 are unblocked by this plan's Task 2 (D1 and D2) and are gated on
nothing else here. The reference binaries they need are already staged by
Task 1's extraction script — widen its `want` prefix to pull
`./mach_kernel` and `./usr/standalone/i386/boot`.
