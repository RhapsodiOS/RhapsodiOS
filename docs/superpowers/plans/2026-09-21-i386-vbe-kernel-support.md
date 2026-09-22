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

### The console comparison: a same-session A/B control

**This gate has been corrected twice, and the second correction was made after
seeing a result — so the justification below is stated on grounds that do not
depend on that result.**

The first revision demanded literal identity. Task 4 showed two boots of the
*same* kernel are not identical, so the second revision substituted a noise
floor measured by booting one pre-Task-4 kernel twice in one morning session.

**That floor was measured the wrong way.** Booting one binary twice cannot see
two things that matter:

- **Rebuild artefacts.** Serial line 4 is the kernel's embedded build stamp
  (`Sun Sep 20 15:00:37 PDT 2026; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386`).
  It differs between *any* two builds of byte-identical source.
- **Cross-session drift.** Task 4's third pass booted the **pre-Task-4 kernel
  again, later the same day**, and it differed from its own morning capture by
  **2,518 pixels** across rows 42..121 — the eight `phantom IRQ 15` lines moved
  and init arrived ~14 guest seconds earlier. The image and the kernel are ruled
  out; the cause is not determined.

**A gate that the known-good control fails is a broken gate.** The pre-Task-4
kernel cannot contain Task 4's change, yet it failed against the morning
baseline. So the baseline was measuring the environment, not the kernel.

**The gate is therefore a same-session A/B:**

1. Boot a **pre-Task-4 control** and the **candidate** back to back, in the
   same session, on the same unmodified image.
2. `serial.log`: diff **excluding line 4** (the build stamp) must be **empty**.
   Sorted is sufficient; unsorted equality is stronger and should be reported.
3. Frames: differences must be confined to the boot-clock digits and of that
   order. Anything outside that region, or materially larger, is real.

**Measured result for Task 4** (controller-verified):

| Comparison | Serial, excl. line 4 | 60 s / 95 s frames |
| --- | --- | --- |
| old kernel, morning vs later (the control) | 0 lines | **2,518 px**, rows 42..121 |
| old vs new, same session, boot 1 | 0 lines, **0 even unsorted** | 30 px, rows 102..121 (clock) |
| old vs new, same session, boot 2 | 0 lines | **0 px — pixel-identical** |

Captures: `vm/shots-t4c-preC/` (control), `vm/shots-t4c-post/`,
`vm/shots-t4c-post2/`. Gitignored and **not durable** across a worktree cleanup.

### The invisibility requirement

**Task 4 changes what every i386 boot uses for its console.** The console is how
failures get reported, so a mistake there is self-concealing. Success criterion:
a boot on which nothing writes `kbs+0x1854` - every boot until spec 3 supplies
that producer, **graphics-mode boots included** - must
produce today's console and output, judged by the same-session A/B control
above. The frame-buffer arm must be unreachable until then. An earlier revision defined this as `video.v_baseAddr == 0`. That is imprecise: `src/boot-2` writes `v_baseAddr` only inside `setMode()`'s `G_MODE_KEY` branch (`boot-2/i386/boot2/graphics.c:189-208`), gated on a `"Graphics Mode"` config key that no shipped config table sets, so `src/boot-2` as configured never enters graphics mode at all. The booter actually on the golden image is Apple's stock v5.0.41.1, not `src/boot-2`, and Task 5 measured (guest memory dump) that it leaves `v_baseAddr` zero even in graphics mode.

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
rbuild kernel --state /build/state --arch i386 --toolchain <profile>   /build/src /build/repo /tmp/<your own dest>
```

**`--toolchain` is required, and `docs/build/rbuild-universal.md:195` omits
it.** Task 3 established why. Without it rbuild falls back to plain `tar`,
which exits 1 on three dangling symlinks in
`file-cmds-1998.10.06-universal.apk` (`usr/bin/{tar,cpio,chgrp}` →
`../../bin/pax`, absent). `file-cmds` is a basedep, so that blocks *every*
build root. `vm/build-src-lib.ps1:498` always passes `--toolchain`; the doc
line is the outlier.

**The stock profile also needs `/usr/local/bin` on its `path=`.** With
`--toolchain` alone, `kernel-7` dies in `installhdrs`: `gcc-darwin.conf`'s
`path=` omits the directory where `bootstrap-cmds` puts `relpath`, so
`MakeInc.dir:69-71`'s ``OBJROOT=`relpath …` `` comes out empty and
`conf/Makefile:358` aborts. Task 3 worked around it with a `/tmp` copy of the
profile — a command-line override, no repo file changed.

Both are provisioning defects, not yours. If either bites differently, report
it; **still do not fall back to `gnumake`.**

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

## Task 4: Wire `BasicAllocateConsole()` - DONE

> **Complete.** Code `e2d02efe8`; verification in `$DIVERGE` under `## Task 4`.
> This section is rewritten to what was actually done. An earlier version
> prescribed a ppc-style `video.v_baseAddr` guard and a literal-identity console
> gate. **Both were wrong. Do not reinstate either.**

**What it does.** `BasicAllocateConsole()` calls `FBAllocateVBEConsole()`
unconditionally and first, returning that console when non-NULL; otherwise it
falls through to the unchanged `bzero` / 640 / 480 / `VGAAllocateConsole` tail.
The vestigial `kernbootstruct` local stays declared and unused; the reference
does not use it either.

**Why that shape.** 4.2 has this function: `_BasicAllocateConsole` at
`0x00197C58`, 72 bytes. Our pre-Task-4 function was it minus exactly nine bytes
(`e8 rel32` + `85 c0` + `75 2b`). It calls `FBAllocateVBEConsole` with no
boot-struct test and touches no `KERNBOOTSTRUCT`.

**Why no `v_baseAddr` guard.** The primary reason stands on its own: it is not
the reference's shape. The "it would have been live" rationale is overstated —
`src/boot-2` writes `kernBootStruct->video.v_baseAddr` only inside `setMode()`'s
`G_MODE_KEY` branch (`boot-2/i386/boot2/graphics.c:189-208`), gated on a
`"Graphics Mode"` config key that no shipped config table sets, so `src/boot-2`
as configured never enters graphics mode at all. The booter actually on the
golden image is Apple's stock v5.0.41.1, and Task 5 measured (guest memory
dump) that it leaves `v_baseAddr` zero even in graphics mode. So the guard
would not have been live today either way; the reference-shape argument is
what actually rules it out.

**Verified:** 72 bytes, all 60 unmasked bytes identical to the reference, with
the three `e8` `rel32` operands (at fn+11/32/58; the opcodes are at fn+10/31/57)
resolving to `_FBAllocateVBEConsole`, `_bzero`, `_VGAAllocateConsole`. Both
kernel symbols defined; Task 2's extent still MATCHes. Console indistinguishable
from a same-session control.

**Not yet verified:** a **graphics-mode (non-`-v`) boot**. It is the default.
`src/boot-2` would write `v_baseAddr` there only if a `"Graphics Mode"` config
key were set, which no shipped config table does; and the booter actually on
the golden image is Apple's stock v5.0.41.1, which Task 5 measured leaves
`v_baseAddr` zero even in graphics mode regardless. On paper the wiring is
covered either way, since `FBAllocateVBEConsole` reads `kbs+0x1854`/`0x185C`
rather than `video` and the booter `bzero`s `_reserved`, but it was never
booted. Task 5 covers it.

---

## Task 5: Boot gates and documentation

**Files:**
- Create: `docs/kernel/i386-vbe-console.md`
- Modify: `$DIVERGE`, `src/drivers-i386/README`
- Modify: `docs/superpowers/specs/2026-09-21-vbe20displaydriver-reconstruction-design.md` (spec 1's blocked-gate notice)

**Interfaces:**
- Consumes: everything above, plus spec 1's `$DRVBUILT`.
- Produces: the evidence that spec 1's reconstruction and this kernel agree.

### Before any boot

- Record `git status src/kernel-7` at the moment of `vm/sync-src.ps1`. The sync
  copies the **working tree**, not a commit, and the byte oracles cover only three
  functions, so a dirty tree would go unnoticed.
- Hash `golden.img` and record it. Task 4 attributed its cross-session drift
  "not the image" on mtime alone; a hash is the stronger claim.
- **Every comparison is a same-session A-B-A**: control, candidate, control, back
  to back. One control cannot catch drift *within* a session.

### The comparison, tightened

The same-session gate was accepted in Task 4, but its first wording would let
four things through. Use this form:

1. **Serial line 4: mask only the date.** Line 4 is the kernel's `version[]`,
   e.g. `Tue Sep 22 13:46:24 PDT 2026; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386`.
   The date must differ between builds; the **config and version string must
   not**. Excluding the whole line would hide a wrong config.
2. **Serial, everything else: unsorted identity**, allowing only the named race.
   The IDE probe block (`Registering: hc0`, `hd0: ...`) and the `intr: phantom
   IRQ 15` lines may swap position. Any other reordering is a finding.
3. **Frames: a fixed mask, not a judgement.** Mask the boot-clock digit cells in
   rows 102..121. Everything outside the mask must be pixel-identical.

- [ ] **Step 1: Gate 2 - `sarld` links the driver, on positive evidence**

Build the image with **both** the new kernel and spec 1's driver:

```bash
cd vm
MSYS_NO_PATHCONV=1 python graft-kernel.py golden.img <new kernel> work/kern.img
MSYS_NO_PATHCONV=1 python install-driver.py work/kern.img \
    ../out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config work/test.img
```

`install-driver.py` allocates the bundle and registers it in `Boot Drivers`.
**`rhap_inject.py` cannot create a bundle.** Name the final image
`vm/work/test.img`, since `rhap_inject.check_target` refuses any other path.
Hash-verify the installed `_reloc` against `$DRVBUILT` before booting.

**Do not pass this gate on the absence of an error.** The booter prints
`Error occurred while linking driver ...` to its own screen, which the kernel
scrolls away, and capture times are fixed `--at` offsets. Task 4 measured about
15 guest seconds of unexplained drift between sessions, enough to land a capture
after the booter screen has gone and turn "no link error seen" into a pass for
the wrong reason.

Pass it on **positive** evidence instead, from the kernel's serial log:

- the driver's own messages appear (Gate 3's lines below). A driver that never
  linked cannot print them.
- every Boot Driver that registered in the control boot still registers, so
  there is no cascade. List them from the control's `serial.log` and check each.

If you also capture the booter screen, **confirm its driver-loading lines are
actually in the frame** before reading anything from it. A frame that does not
show them is inconclusive, not a pass.

- [ ] **Step 2: Gate 3 - the driver loads**

From the same boot's `serial.log`:

```
%s: VESA video driver initialization.
%s: Skipping framebuffer initialization (card not in VBE mode).
Registering: VBEDisplay0
```

The `%s` is the driver's own `name`; match on the fixed text.

**The "Skipping framebuffer initialization" path is correct**, for two
independent reasons from spec 1: the booter never enters a VBE mode, and the 4.2
mode-array offsets land in `_reserved`, which the booter `bzero`s.

If the driver *links* but fails to *load*, look first at the
`_VBE20DisplayDriver_instance` difference spec 1 recorded: the reference leaves
it an unallocated common, our `kl_ld` allocates it. **Do not misdiagnose that as
a source defect in the reconstruction.**

- [ ] **Step 3: The graphics-mode boot**

Every boot so far used `mach_kernel -v`. Graphics mode is the **default**, and
the only path on which the booter writes `video.v_baseAddr`. Run one same-session
A-B-A **without `-v`** and apply the frame comparison. Both kernels should show
the booter's graphics panel and behave identically.

Use `--keys-at 8`. `--keys-at 3.0` truncates the boot string to `mach_ke`.

> **Corrected by the run (2026-09-22).** Typing `mach_kernel` + Return
> *without* `-v` still boots in text mode. Only an untouched countdown gives
> the graphics panel, so the graphics-mode boots send **no keys**.
>
> The booter on `golden.img` is Apple's stock v5.0.41.1, not `src/boot-2`,
> and it leaves `video.v_baseAddr` zero even in graphics mode. That was
> measured with a guest memory dump.
>
> The phantom-IRQ race in rule 2 above is also wider than stated: the eight
> `intr: phantom IRQ 15` lines float around `Power management is enabled.`
> too, between boots of the same kernel.
>
> See `docs/kernel/i386-vbe-console.md`.

- [ ] **Step 4: Write the gate record**

Create `docs/kernel/i386-vbe-console.md` in the shape of
`docs/drivers/drvVGA-boot-gate.md`: procedure, hashes, captured output, and an
explicit "what this does and does not establish" section. It does **not**
establish that the frame-buffer console works; nothing has exercised that arm.

State plainly that captures are **not regenerable**: the build stamp changes on
every rebuild, and cross-session drift means the same boot cannot be reproduced
later. The committed hashes are the only durable trace.

- [ ] **Step 5: Unblock spec 1's gate notice**

Amend spec 1's design doc section 8 to record that this spec landed and what the
gates produced. Leave spec 1's plan Task 9 block in place but note the result
beside it. Update the `drvVBE20DisplayDriver` row in `src/drivers-i386/README`,
which says the gate is blocked and must not be run.

- [ ] **Step 6: Commit**

```bash
git add docs/kernel/ docs/superpowers/ src/drivers-i386/README "$DIVERGE"
git commit -m "kernel: record the VBE boot gates

sarld links the reconstructed driver against the new kernel and it
registers as VBEDisplay0; the framebuffer path still waits on the booter."
```

---

## Follow-on

**`BasicAllocateConsole` has two more callers in our tree**, `kmDevice.m:85` and
`kmDevice.m:962` (the alert console, `kmAlertConsole`). Today both fall through to
VGA. Once spec 3 supplies the `kbs+0x1854` producer, **each will get a frame-buffer
console**, not just the boot console. Task 4 scanned 4.2 for callers of
`FBAllocateVBEConsole`, not our tree for callers of `BasicAllocateConsole`.

Spec 3 (the booter) is unblocked by Task 1's D2 answer and by Task 3's recorded
mode-record address question. Its two hard problems are already known:

- The 4.2 mode-array offsets `0x12854`/`0x12858` land inside Rhapsody's
  `_reserved[7500]` (908..8408). Spec 3 must either fix that offset as ABI or add
  real members and accept the driver's and kernel's hard-coded addresses as a
  recorded divergence — **and whatever it chooses, the driver and the kernel must
  agree**, or they will read different places.
- `0x1870 + 0x880` is 8432, exactly the end of `boot_video` in our layout, so the
  declared array overlaps `video`.
