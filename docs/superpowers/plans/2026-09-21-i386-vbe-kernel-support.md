# i386 VESA Kernel Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export `VBEModeInfo2IODisplayInfo` and `FBAllocateVBEConsole` from the i386 kernel and connect the frame-buffer console that is already built but called by nothing, so that spec 1's reconstructed display driver can link and load.

**Architecture:** Five tasks. Task 1 stages the 4.2 kernel reference, creates a binrecon profile and answers the five discovery items — including bounding the target function by its inline jump table, which the sparse symbol table cannot do. Task 2 writes `VBEModeInfo2IODisplayInfo` to byte-parity, the only piece with a byte oracle. Task 3 writes `FBAllocateVBEConsole` as a guard over the existing `FBAllocateConsole`, to structural parity. Task 4 wires `BasicAllocateConsole()` to consult `kernBootStruct->video`, mirroring ppc. Task 5 runs the two boot gates and updates the docs.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` with IDA Professional 9.2, Rhapsody guest `gnumake` driven by `vm/sync-src.ps1` + `vm/build-i386-kernel-ahci.sh`, QEMU via `vm/graft-kernel.py` / `vm/install-driver.py` / `vm/qemu-shot.py`.

**Spec:** [2026-09-21-i386-vbe-kernel-support-design.md](../specs/2026-09-21-i386-vbe-kernel-support-design.md)

## Global Constraints

```text
VENVPY=D:/RhapsodiOS/.venv-binrecon/Scripts/python.exe
PATCH=C:/Users/raynorpat/Downloads/OS42MachUserPatch4.tar
KREF=C:/Users/raynorpat/Downloads/test/OS42/mach_kernel_i386
KREFSHA=33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890
KDIR=src/kernel-7/bsd/dev/i386
RECON=src/kernel-7/reconstruction/vbe
DIVERGE=src/kernel-7/reconstruction/vbe/divergences.md
PROFILE=tools/binrecon/profiles/os42-kernel-vbe.json
KBUILT=vm/install/mach_kernel
DRVREF=C:/Users/raynorpat/Downloads/test/Drivers/i386/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc
DRVBUILT=out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc
```

Work in this worktree, `.worktrees/vbe20-kernel` on branch `vbe20-kernel`. It is
branched from `vbe20-recon`, **which is not merged to master** — spec 1's driver
travels with us so the boot gates can run.

**The main checkout has another session's uncommitted work in it.** Do not
`cd` there, do not check out master, do not merge. `vm/vm.conf` and
`vm/bridge.conf` are already copied into this worktree and are gitignored.

- **Never commit** `$KREF`, the extracted kernel, `tools/binrecon/out/`, `out/i386/`, `vm/install/`, `vm/vm.conf`, `vm/bridge.conf`, or any throwaway harness.
- **Python is `$VENVPY`** with `PYTHONPATH=tools/binrecon`.
- **Do not modify `src/boot-2`.** Spec 3 owns the booter. Nothing here writes `kernBootStruct->video` or the mode array.
- **Do not modify `src/drivers-i386`.** Spec 1 is complete and its driver is the article under test.
- **Do not invent.** If the disassembly does not show it, it does not get written. Record the gap in `$DIVERGE`.
- **Reproduce reference defects verbatim**, labelled in source, as spec 1 did for Apple's `bytesPerScanLine * XResolution` typo.
- Source comments cite **reference** addresses (`0x0019ED8C` style) since our kernel's differ. Task numbers are acceptable in `$DIVERGE` (the plan is committed); references to "the brief" are not (briefs are gitignored scratch).
- **Commits:** `kernel: ` prefix, one to two lines, no metadata beyond the trailer.
- **Reviewer:** `Pat Raynor`.

### The invisibility requirement

**Task 4 changes what every i386 boot uses for its console.** The console is how
failures get reported, so a mistake there is self-concealing. Success criterion:
a boot with `video.v_baseAddr == 0` — which is every boot until spec 3 — must
produce **exactly** today's console and output. The frame-buffer arm must be
unreachable until then.

### Why the compare harness cannot use relocations

Spec 1 masked 32-bit relocated operands read from the Mach-O relocation table.
**A linked kernel is `MH_EXECUTE` and has no relocation table.** Both the
reference and our build are fully linked.

Worse, the jump table is **inline**: `ff2485d8ed1900` is
`jmp [eax*4 + 0x19EDD8]`, and `0x19EDD8` is `0x19ED8C + 76` — 76 bytes into the
function, inside its own extent. Its entries are absolute code addresses that
differ between kernels.

So the harness masks **by pattern**, not by relocation:

1. the `imm32` in the `FF 24 85 <imm32>` dispatch, and
2. the jump-table entries themselves — `N * 4` bytes at the table's offset.

Everything else — prologue, field translation, case bodies, epilogue — is
comparable byte for byte. Task 1 establishes the table's offset and entry count;
Task 2 builds the harness around them.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `$PROFILE` | binrecon profile for the 4.2 i386 kernel slice |
| `$KDIR/FBConsole.c` | Gains both functions (pending D4) |
| `$KDIR/FBConsole.h` | Gains both declarations |
| `$KDIR/BasicConsole.c` | `BasicAllocateConsole()` gains the boot-struct arm |
| `$RECON/divergences.md` | Evidence record: discovery answers, measurements, divergences |
| `docs/kernel/i386-vbe-console.md` | The gate record, written in Task 5 |

Both functions go in `FBConsole.c` because they are adjacent in the reference's
`__text`, which suggests one translation unit — **D4 confirms or refutes this
before Task 2 writes anything.** If D4 refutes it, report rather than guessing at
a new file.

---

### Building the kernel: use `rbuild`, not `build-i386-kernel-ahci.sh`

**This project builds with `rbuild`.** An earlier revision of this plan sent
Task 2 at `vm/build-i386-kernel-ahci.sh`, a straight `gnumake` path, and it
walked into four blockers in a script that is not the normal route. Do not
repeat that.

The documented invocation is `docs/build/rbuild-universal.md:195`:

```sh
rbuild kernel --state /build/state --arch i386   /build/src /build/repo /build/rbuild-i386-kernel-proof
```

Guest `rbuild` is `/build/tools/bin/rbuild`. It produces an APK set —
`kernel-154.5.1-7` and companions — from which the `mach_kernel` is extracted;
`rbuild-universal.md` records `/tmp/kext/mach_kernel` as the extraction point in
its own proof run. Use an independently named destination under `/tmp` so no
canonical runtime, boot image or golden image is touched, as that document's
own acceptance runs do.

`rbuild kernel` takes `kernel-7` from the source tree, so a `vm/sync-src.ps1
-Path kernel-7` still precedes it.

**If `rbuild kernel` fails, report it — do not fall back to `gnumake`.** A
gnumake build is a different path with different flags and a different libcc
resolution, so a binary produced that way is not evidence about the one this
project ships. Task 2's result stands because the *function* was compared
byte-for-byte against the reference, not because its build path was right.

> **Known blockers on the `gnumake` path**, recorded only so nobody mistakes
> them for rbuild problems. Task 2 hit all four and worked around each without
> changing a repo file; a separate session is fixing them.
> `command -v` is absent from the guest's `/bin/sh`; the script never `mkdir`s
> `BUILD/`; the portable AHCI tests fail under `-ansi -pedantic`; and
> `/usr/lib/libcc.a` is PPC-only, with a fat one at
> `/build/bootstrap-root/usr/lib/libcc.a`. **Do not** wire
> `src/kernel-7/conf/libcc_i386_helpers.c` in to dodge the last —
> `vm/tests/test-build-src.ps1:261` asserts it must not be.

---

## Task 1: Stage the reference, profile it, answer the discovery items

**Files:**
- Create: `$KREF` (outside the repo, never committed)
- Create: `$PROFILE`
- Create: `$RECON/divergences.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the bounded extent of `VBEModeInfo2IODisplayInfo` and its jump-table geometry, which Task 2's harness needs; answers to D1-D5.

- [ ] **Step 1: Extract the i386 slice**

`vm/extract-os42-patch.py` (committed, from spec 1) pulls the fat kernel:

```bash
$VENVPY vm/extract-os42-patch.py "$PATCH" /tmp/os42k ./mach_kernel
```

Expected: `mach_kernel`, 3,399,572 bytes, SHA-256
`6D602AAD16720EA413B90F716E90C83A942961BEECC48663626DE6807DB620EE`.

Then split out the i386 slice to `$KREF`. From the fat header it is at offset
835,584, length 1,117,920, and must hash to `$KREFSHA`. **If it does not, stop
and report** — everything downstream is pinned to it.

- [ ] **Step 2: Create the binrecon profile**

Copy `tools/binrecon/profiles/cirruslogic-gd5434.json` to `$PROFILE` and change
`name` to `OPENSTEP 4.2 kernel, i386 slice (VBE functions)` and `output_dir` to
`../out/os42-kernel-vbe`. Keep IDA enabled, Ghidra and angr disabled.

`BINRECON_REBUILT` has no meaningful value until Task 2 builds a kernel. Point
it at a scratch **copy** of `$KREF` — not `$KREF` itself. Spec 1 found that when
the two artifacts are the same file, publication fails all-or-nothing and no
analysis is written at all.

- [ ] **Step 3: D1 — bound `VBEModeInfo2IODisplayInfo` by its jump table**

The symbol table is sparse: the next *named* symbol after `0x0019ED8C` is
`_PCPatoi`, 7,484 bytes on. That is not the function's size.

The dispatch is at function offset 69: `FF 24 85 D8 ED 19 00`, so the table base
is `0x0019EDD8` = function offset 76. Preceding it, `83 F8 1E` (`cmp eax,0x1Eh`)
with `ja` gives **31 table entries**, so the table occupies offsets 76..200.
The case bodies follow.

Establish the function's real end: the last case body's `ret`, or the start of
the next function. Record:

- the function's total size,
- the jump table's offset within it (expected 76) and its entry count (expected 31),
- each table entry's target, as a function-relative offset.

**Do not take the expected values on trust — derive them.** They are this
plan's reading, not a measurement.

- [ ] **Step 4: D2 — identify `0x12854`**

`FBAllocateVBEConsole` guards on two words:

```
66833D5C28010000  cmpw ds:[0x1285C],0    ; VBEModeRec+4 = xResolution
833D5428010000    cmp  ds:[0x12854],0    ; four bytes BEFORE the record
```

Both must be non-zero to proceed. `0x12858` is the `VBEModeRec` (spec 1's D1).
Find every other reference to `0x12854` in the kernel slice and in the 4.2
booter (`vm/extract-os42-patch.py PATCH DEST ./usr/standalone/i386/boot`) and
say what it is. Spec 3 has to write it.

If it is not determinable, say so plainly with what you ruled out.

- [ ] **Step 5: D3, D4, D5 — the console structures**

- **D3:** `sizeof(ConsoleRep)` in our tree versus the reference's `IOMalloc(228)`. `ConsoleRep` is at `$KDIR/FBConsole.c:135`. **Measure with `offsetof` on the guest, not by hand** — spec 1's hand layout of a struct was 12 bytes out and the guest compiler settled it.
- **D4:** Whether `FBAllocateVBEConsole` and `VBEModeInfo2IODisplayInfo` sit in the FBConsole translation unit. Check the functions immediately before `0x0019ECB8` and after the D1 end: if they are FBConsole siblings, that settles it.
- **D5:** Whether the reference's `ConsoleRep` puts `display` at offset 4. The `rep movsd` writes 136 bytes to `priv + 4`; ours assigns `((ConsolePtr)cso->priv)->display`.

- [ ] **Step 6: Write the evidence record**

Create `$RECON/divergences.md` with a Conventions header (define how you cite
addresses) and a Task 1 section carrying D1-D5 with their evidence. The standard:
a reader arriving months later, writing spec 3, can re-check every conclusion
from cited addresses and byte sequences without redoing the disassembly.

Mark every inference as an inference. Spec 1's final review found an inference
that had hardened into an assertion across task sections and propagated out of
the repo; that is the failure mode to avoid from the start.

- [ ] **Step 7: Commit**

```bash
git add "$PROFILE" "$RECON"
git commit -m "kernel: profile the 4.2 VBE functions and answer the discovery items

Bounds VBEModeInfo2IODisplayInfo by its inline jump table, which the sparse
symbol table cannot do."
```

---

## Task 2: `VBEModeInfo2IODisplayInfo`

**Files:**
- Modify: `$KDIR/FBConsole.c`, `$KDIR/FBConsole.h`
- Modify: `$DIVERGE`

**Interfaces:**
- Consumes: D1's extent and jump-table geometry, D4's translation-unit answer.
- Produces: the exported symbol that unblocks spec 1's driver link; `VBEModeRec` as the kernel now spells it.

This is the only piece with a byte oracle. Get it right before anything depends
on it.

- [ ] **Step 1: Disassemble the full extent**

From `$KREF` at `0x0019ED8C`, for D1's size. The opening is known:

```
55 89E5                push ebp; mov ebp,esp
57 56 53               push edi/esi/ebx
8B5D08                 mov  ebx,[ebp+8]      ; mode
8B750C                 mov  esi,[ebp+0Ch]    ; info
0FB77B04  893E         movzx edi,[ebx+4];  mov [esi],    edi   ; xResolution -> width
0FB77B06  897E04       movzx edi,[ebx+6];  mov [esi+4],  edi   ; yResolution -> height
0FB77B04  897E08       movzx edi,[ebx+4];  mov [esi+8],  edi   ; xResolution -> totalWidth
0FB77B08  897E0C       movzx edi,[ebx+8];  mov [esi+0Ch],edi   ; bytesPerScanline -> rowBytes
C746100000 0000        mov  [esi+10h],0                        ; refreshRate = 0
8B7B14    897E14       mov  edi,[ebx+14h]; mov [esi+14h],edi   ; frameBuffer
0FB6430A               movzx eax,[ebx+0Ah]                     ; bitsPerPixel
83C0FE 83F81E          add  eax,-2; cmp eax,1Eh
0F87C0000000           ja   <default>
FF2485D8ED1900         jmp  [eax*4 + 0x19EDD8]
```

The 31 case bodies are what you have to read. They set `bitsPerPixel`,
`colorSpace` and `pixelEncoding` per VBE depth.

- [ ] **Step 2: Declare `VBEModeRec` in the kernel**

The driver declares its own copy; the kernel needs one too. Use spec 1's layout
verbatim — it is confirmed twice over, by the driver's type encoding and by this
function's own field offsets:

```c
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
```

24 bytes with padding at `0x12`-`0x13`.

- [ ] **Step 3: Write the function**

Use Rhapsody's `IODisplayInfo` directly (`driverkit/displayDefs.h`); do not
declare a local copy. `info->refreshRate = 0` is the reference's own behaviour,
not an omission — **comment it as such**, because it is the reason spec 1's
driver prints `Refresh:0Hz` and a maintainer may otherwise "fix" it.

A `switch` on `bitsPerPixel` is what produces a jump table. If your first
attempt emits a compare chain instead, that is a shape difference to solve by
reading the reference's dispatch, not by contorting the source.

- [ ] **Step 4: Build the kernel**

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path kernel-7
. .\vm\rhap-remote.ps1
$cfg = Get-RhapVmConfig
$ssh = Resolve-RhapTool $cfg.Ssh
$ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand 'tr -d "\r" < /build/source/vm/build-i386-kernel-ahci.sh > /tmp/bk.sh && sh /tmp/bk.sh'
if ($ec -ne 0) { throw "guest kernel build ssh exit $ec" }
```

then pull `vm/install/mach_kernel` back. Spec 1's Task 3 report records that the
documented tar pull fails and that `ssh -T` with stdout redirected, then
`tar xf`, works. **The guest's copy of the build script may be stale** — stream
the current one to `/tmp` and run that rather than overwriting the shared copy.

Expected: a kernel that builds and whose symbol table now carries
`_VBEModeInfo2IODisplayInfo`.

- [ ] **Step 5: Build the compare harness**

Create `compare_kvbe.py` at the worktree root (**do not commit**). It must:

1. find `_VBEModeInfo2IODisplayInfo` in each kernel's symbol table (the
   reference's is at `0x0019ED8C`; ours will differ),
2. slice D1's size from each,
3. mask the `imm32` in the `FF 24 85 <imm32>` dispatch,
4. mask the jump table — D1's entry count × 4 bytes at D1's table offset,
5. report MATCH or the differing byte offsets.

**There is no relocation table to mask from** — both kernels are `MH_EXECUTE`.
Masking is by pattern only. Do not copy spec 1's `compare_vbe20.py` approach; it
reads relocations and will silently mask nothing here.

- [ ] **Step 6: Compare and iterate**

```bash
$VENVPY compare_kvbe.py "$KREF" "$KBUILT"
```

Expected: MATCH. If a delta survives and you understand its cause, record it in
`$DIVERGE` with instruction-level evidence and leave it — **do not mark it
matched.** A recorded, understood delta is acceptable; a silently wrong byte is
not.

- [ ] **Step 7: Commit**

```bash
git add "$KDIR/FBConsole.c" "$KDIR/FBConsole.h" "$DIVERGE"
git commit -m "kernel: add VBEModeInfo2IODisplayInfo

The VBE-to-IODisplayInfo translation the 4.2 patch added; sets refreshRate
to zero, which is why the VBE driver prints Refresh:0Hz."
```

---

## Task 3: `FBAllocateVBEConsole`

**Files:**
- Modify: `$KDIR/FBConsole.c`, `$KDIR/FBConsole.h`
- Modify: `$DIVERGE`

**Interfaces:**
- Consumes: `VBEModeInfo2IODisplayInfo` from Task 2; D3 and D5's structure answers.
- Produces: the console allocator Task 4 calls.

**Structural parity, not byte-parity.** Five `rel32` calls and seven absolute
vtable pointers into a kernel whose addresses all differ. Do not chase bytes.

- [ ] **Step 1: Re-read the reference and our `FBAllocateConsole`**

The reference's 212 bytes are decoded in the spec's §4. Our
`FBAllocateConsole` is at `$KDIR/FBConsole.c:1354`. Confirm for yourself that
the seven vtable stores at `[ebx+0]`..`[ebx+0x18]` correspond to
`Free, Init, Restore, DrawRect, EraseRect, PutC, GetSize` in our
`IOConsoleInfo` (`$KDIR/ConsoleSupport.h`), and that `IOMalloc(32)` equals its
size.

- [ ] **Step 2: Write it as a guard, not a transcription**

The shape, with both operands supplied from Task 1's record rather than from
this plan — **D2 names the first, and the mode-record address is the open
question below**:

```c
IOConsoleInfo *
FBAllocateVBEConsole(void)
{
    IODisplayInfo	info;

    /* Reference 0x0019ECB8: both words must be non-zero to proceed. */
    if (<D2's word> == 0 || <mode record>->xResolution == 0)
	return NULL;

    /*
     * No bzero: the reference passes the local UNINITIALISED.  Verified -
     * 0x0019ECB8's prologue has no rep stos and no call before the
     * VBEModeInfo2IODisplayInfo at +52.  VBEModeInfo2IODisplayInfo's
     * default: arm ORs into modeUnavailableFlag, so on an unrecognised
     * depth it ORs into stack residue.  That is the reference's behaviour;
     * reproduce it and label it, do not add a bzero to "fix" it.
     */
    VBEModeInfo2IODisplayInfo(<mode record>, &info);
    return FBAllocateConsole(&info);
}
```

Fill both from `$DIVERGE`.

**D2 is answered, and the guard will never pass.** `0x12854` is the kernel
virtual address of the mapped VESA framebuffer, written by `pmap_bootstrap` in
the 4.2 kernel. **Spec 3 owns adding that mapping**, so on our side nothing
writes it yet and this function will always return NULL.

That is expected and correct. Write the guard as the reference has it, comment
that its producer arrives with spec 3, and record it in `$DIVERGE`. **Do not
write a placeholder producer**, do not stub the address, and do not weaken the
guard to make the function appear live. **How
that address is spelled in our tree is the open question**: spec 1's driver
hard-codes `0x12858` because 4.2's `KERNBOOTSTRUCT` put it there, and spec 1
established that in *our* struct that offset lands inside `_reserved[7500]`
(908..8408), which `getKernBootStruct()` has `bzero`'d.

**Do not invent a new `KERNBOOTSTRUCT` member here.** Spec 3 owns that decision.
Use the same hard-coded address the driver uses, comment it with the same
caveat, and record in `$DIVERGE` that spec 3 must reconcile the two — they have
to agree or the driver and kernel will read different places.

If the reference's guard structure differs from the sketch above once you have
read it properly, follow the reference.

- [ ] **Step 3: Build, and confirm the symbol is exported**

Repeat Task 2 Step 4. Then confirm `_FBAllocateVBEConsole` is in the built
kernel's symbol table as a defined symbol.

**Do not expect a byte comparison to pass.** If you run one, it is to *document*
the divergence, not to gate on it.

- [ ] **Step 4: Record the structural correspondence**

In `$DIVERGE`: the reference's seven vtable stores against our seven assignments,
the two `IOMalloc` sizes against `sizeof(IOConsoleInfo)` and D3's
`sizeof(ConsoleRep)`, and the guard. State plainly that byte-parity was not a
target here and why.

- [ ] **Step 5: Commit**

```bash
git add "$KDIR/FBConsole.c" "$KDIR/FBConsole.h" "$DIVERGE"
git commit -m "kernel: add FBAllocateVBEConsole

A boot-struct guard over the existing FBAllocateConsole; the reference's
own shape, not a transcription of its 212 bytes."
```

---

## Task 4: Wire `BasicAllocateConsole()`

**Files:**
- Modify: `$KDIR/BasicConsole.c`
- Modify: `$DIVERGE`

**Interfaces:**
- Consumes: `FBAllocateVBEConsole` from Task 3.
- Produces: the first i386 boot path that reads `kernBootStruct->video`.

**This is the task that can break every boot.** Read the invisibility
requirement in Global Constraints before writing anything.

- [ ] **Step 1: Read both sides**

Ours, `$KDIR/BasicConsole.c:241`:

```c
IOConsoleInfo *BasicAllocateConsole()
{
    IODisplayInfo di;
    KERNBOOTSTRUCT *kernbootstruct = KERNSTRUCT_ADDR;   /* declared, never used */

    bzero(&di, sizeof(di));
    di.width = 640;
    di.height = 480;
    return( VGAAllocateConsole(&di) );
}
```

ppc's, `src/kernel-7/bsd/dev/ppc/kmDevice.m:150-167`, is the shape to mirror:
test the boot framebuffer, build an `IODisplayInfo`, allocate a frame-buffer
console, fall back when it returns NULL.

There is **no reference** for our version — 4.2's `BasicAllocateConsole` is not
ours. Justify from ppc's shape and say so in the record.

- [ ] **Step 2: Write the boot-struct arm**

Try `FBAllocateVBEConsole()` first; on NULL, fall through to **exactly today's
code path, unchanged**. `FBAllocateVBEConsole` already returns NULL when the
boot struct does not describe a VBE mode, so the guard lives there rather than
being duplicated here.

Do not delete the vestigial `kernbootstruct` declaration — it becomes used.

- [ ] **Step 3: Build and prove invisibility**

Build per Task 2 Step 4. Then boot the **unmodified** image — no driver
injected, no config changes:

```bash
cd vm
MSYS_NO_PATHCONV=1 python graft-kernel.py golden.img install/mach_kernel work/test.img
python qemu-shot.py work/test.img shots-kvbe-invis --at 30,60,95 --keys "mach_kernel -v\n"
```

**Compare the console output against a run with the pre-Task-4 kernel.** They
must be identical: same text, same console. `video.v_baseAddr` is zero on this
image, so the frame-buffer arm must never be entered.

If the outputs differ at all, stop. Either the fallback is not exactly the old
path, or the guard is letting the new arm run. **Do not proceed to Task 5 with a
changed baseline** — Task 5's gates cannot be read against a moving one.

- [ ] **Step 4: Commit**

```bash
git add "$KDIR/BasicConsole.c" "$DIVERGE"
git commit -m "kernel: let BasicAllocateConsole use the booter's framebuffer

Mirrors what ppc already does; falls back to the existing VGA console
whenever the boot struct names no framebuffer, which is every boot until
the booter sets one."
```

---

## Task 5: Boot gates and documentation

**Files:**
- Create: `docs/kernel/i386-vbe-console.md`
- Modify: `$DIVERGE`, `src/drivers-i386/README`
- Modify: `docs/superpowers/specs/2026-09-21-vbe20displaydriver-reconstruction-design.md` (spec 1's blocked-gate notice)

**Interfaces:**
- Consumes: everything above, plus spec 1's `$DRVBUILT`.
- Produces: the evidence that spec 1's reconstruction and this kernel agree.

- [ ] **Step 1: Gate 2 — `sarld` links the driver**

This is the gate that matters most. Build the image with **both** the new kernel
and spec 1's driver:

```bash
cd vm
MSYS_NO_PATHCONV=1 python graft-kernel.py golden.img install/mach_kernel work/kern.img
MSYS_NO_PATHCONV=1 python install-driver.py work/kern.img \
    ../out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config work/test.img
```

`install-driver.py` allocates the bundle and registers it in `Boot Drivers`,
matching `"Boot Driver" = "Yes"`. **`rhap_inject.py` cannot create the bundle** —
it has only `set-key` and `put`, both of which repoint an existing entry.

Hash-verify the installed `_reloc` against `$DRVBUILT` before booting. Spec 1
records a near-miss where a refused injection produced a plausible-looking boot
of somebody else's driver.

Boot and read the **booter's** output, before the kernel scrolls it away. Gate 2
passes when there is **no** `Error occurred while linking driver VBE20DisplayDriver`
and no cascade into the drivers linked after it.

- [ ] **Step 2: Gate 3 — the driver loads**

From the same boot, look for:

```
%s: VESA video driver initialization.
%s: Skipping framebuffer initialization (card not in VBE mode).
Registering: VBEDisplay0
```

The `%s` is the driver's own `name`; match on the fixed text.

**The "Skipping framebuffer initialization" path is the correct result**, for
two independent reasons from spec 1: the booter never enters a VBE mode, and the
4.2 mode-array offsets land in `_reserved`, which is `bzero`'d. The
`using VBE mode %d` path needs spec 3.

If the driver *links* but fails to *load*, look at the
`_VBE20DisplayDriver_instance` difference spec 1 recorded — the reference leaves
it an unallocated common, our `kl_ld` allocates it. Spec 1 flagged it as a
possible load-time hazard and this is the first test of it. **Do not misdiagnose
it as a source defect in the reconstruction.**

- [ ] **Step 3: Write the gate record**

Create `docs/kernel/i386-vbe-console.md` in the shape of
`docs/drivers/drvVGA-boot-gate.md`: the procedure, the hashes, the captured
output, and an explicit "what this does and does not establish" section. It does
**not** establish that the frame-buffer console works — nothing has exercised
that arm.

- [ ] **Step 4: Unblock spec 1's gate notice**

Spec 1's design doc and plan both carry a `BLOCKED ON SPEC 2` notice on gate 3.
Amend the spec's §8 to record that this spec landed and what the gate produced.
Leave the plan's Task 9 block in place but note the result beside it.

Update the `drvVBE20DisplayDriver` row in `src/drivers-i386/README`: it currently
says the boot gate is blocked and must not be run. That is no longer true.

- [ ] **Step 5: Commit**

```bash
git add docs/kernel/ docs/superpowers/ src/drivers-i386/README "$DIVERGE"
git commit -m "kernel: record the VBE boot gates

sarld links the reconstructed driver against the new kernel and it
registers as VBEDisplay0; the framebuffer path still waits on the booter."
```

---

## Follow-on

Spec 3 (the booter) is unblocked by Task 1's D2 answer and by Task 3's recorded
mode-record address question. Its two hard problems are already known:

- The 4.2 mode-array offsets `0x12854`/`0x12858` land inside Rhapsody's
  `_reserved[7500]` (908..8408). Spec 3 must either fix that offset as ABI or add
  real members and accept the driver's and kernel's hard-coded addresses as a
  recorded divergence — **and whatever it chooses, the driver and the kernel must
  agree**, or they will read different places.
- `0x1870 + 0x880` is 8432, exactly the end of `boot_video` in our layout, so the
  declared array overlaps `video`.
