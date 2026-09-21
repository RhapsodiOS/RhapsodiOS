# i386 VESA kernel support

Supply the two kernel functions Apple added in OPENSTEP 4.2 User Patch 4 —
`VBEModeInfo2IODisplayInfo` and `FBAllocateVBEConsole` — and connect the
frame-buffer console machinery that already exists in this tree but which
nothing calls.

This is the second of three specs covering the i386 VESA boot path. Spec 1
reconstructed the display driver and is complete; its boot gate is **blocked on
this spec**. Spec 3 owns the booter.

**Spec 1:** [2026-09-21-vbe20displaydriver-reconstruction-design.md](2026-09-21-vbe20displaydriver-reconstruction-design.md)

## Motivation

`drvVBE20DisplayDriver` is reconstructed and byte-identical to Apple's binary,
but it cannot run. `Default.table` marks it `"Boot Driver" = "Yes"`, so the
booter links it against the kernel with `sarld`
([sarld-driver-link-limit.md](../../boot/sarld-driver-link-limit.md)).
`_VBEModeInfo2IODisplayInfo` is undefined in the `_reloc`, nothing in
`src/kernel-7` defines it, and no shipped Rhapsody kernel exports it — so that
link fails, and the failure **cascades into every driver linked afterwards**,
surfacing as `panic: Missing EISA kernel bus class`, which names none of the
cause.

There is a second, independent motivation. i386's boot console
(`bsd/dev/i386/BasicConsole.c`) programs VGA registers directly for 640x480x4
planar at `0xA0000` and ignores `kernBootStruct->video` entirely. ppc does not:
`bsd/dev/ppc/kmDevice.m:150-167` reads the boot video struct and allocates a
frame-buffer console from it. The machinery to do the same on i386 is already
present and compiled — and dead.

## 1. Scope

### 1.1 Reference

The patched OPENSTEP 4.2 kernel, extracted with
`vm/extract-os42-patch.py PATCH DEST ./mach_kernel`.

| Property | Value |
| --- | --- |
| Container | fat, three slices (m68k, i386, sparc) |
| i386 slice | offset 835,584, length 1,117,920 |
| i386 slice SHA-256 | `33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890` |
| `__text` | vmaddr `0x1012D0`, file offset 4,816 |
| `_FBAllocateVBEConsole` | `0x0019ECB8`, 212 bytes |
| `_VBEModeInfo2IODisplayInfo` | `0x0019ED8C` |

Reference binaries stay outside git.

### 1.2 In scope

The two functions, the wiring in `BasicAllocateConsole()`, and the evidence
record. See §2 for what each actually requires.

### 1.3 Out of scope

**The booter.** Spec 3. Nothing here writes `kernBootStruct->video` or the mode
array; this spec only makes the kernel able to *read* them.

**Reproducing the rest of the 4.2 kernel.** We are adding two functions to our
own kernel, not rebuilding Apple's.

**The `_VBE20DisplayDriver_instance` link difference** carried over from spec 1.
It is a Kernel Server link-model artefact, not a kernel export. Spec 1's record
flags it as a possible load-time hazard; gate 3 here is what would reveal it,
and if it does, that is spec 1's finding to act on, not a defect introduced here.

## 2. What is actually missing

Only one of the three pieces is absent code. The rest is connection work.

| Piece | State in this tree |
| --- | --- |
| `VBEModeInfo2IODisplayInfo` | **Absent.** The driver's only kernel dependency. |
| Frame-buffer console | **Present and built.** `bsd/dev/i386/FBConsole.c`, `FBAllocateConsole` at `:1354`, declared `FBConsole.h:47`, built via `conf/files.i386:66`. **Called by nothing.** |
| `FBAllocateVBEConsole` | Absent, but structurally equal to `FBAllocateConsole` plus a boot-struct guard. See §4. |
| Boot-struct → console wiring | Absent on i386. ppc has it at `bsd/dev/ppc/kmDevice.m:150-167`. |

`BasicAllocateConsole()` at `BasicConsole.c:241` still declares
`KERNBOOTSTRUCT *kernbootstruct = KERNSTRUCT_ADDR;` and never uses it, then
hands `VGAAllocateConsole` a hard-coded 640x480. That unused declaration is a
vestige of the hook this spec restores.

## 3. `VBEModeInfo2IODisplayInfo`

```c
void VBEModeInfo2IODisplayInfo(VBEModeRec *mode, IODisplayInfo *info);
```

The signature is spec 1's D2, established from the method's type encoding, the
call site's push order and the callee's own prologue. The return type is
**inferred** `void`: no path loads `eax` with a result, though `eax` is written
as scratch.

It is a **leaf** — field translation plus a jump table on `bitsPerPixel`, no
calls. Its opening:

```
0019ED8C  55 89E5              push ebp; mov ebp,esp
0019ED8F  57 56 53             push edi/esi/ebx
0019ED92  8B5D08               mov  ebx,[ebp+8]      ; mode
0019ED95  8B750C               mov  esi,[ebp+0Ch]    ; info
0019ED98  0FB77B04  893E       movzx edi,[ebx+4];  mov [esi],    edi   ; xResolution -> width
0019ED9E  0FB77B06  897E04     movzx edi,[ebx+6];  mov [esi+4],  edi   ; yResolution -> height
          0FB77B04  897E08     movzx edi,[ebx+4];  mov [esi+8],  edi   ; xResolution -> totalWidth
          0FB77B08  897E0C     movzx edi,[ebx+8];  mov [esi+0Ch],edi   ; bytesPerScanline -> rowBytes
          C746100000 0000      mov  [esi+10h],0                        ; refreshRate = 0
          8B7B14    897E14     mov  edi,[ebx+14h]; mov [esi+14h],edi   ; frameBuffer
          0FB6430A             movzx eax,[ebx+0Ah]                     ; bitsPerPixel
          83C0FE 83F81E        add  eax,-2; cmp eax,1Eh
          0F87C0000000         ja   <default>
          FF2485D8ED1900       jmp  [eax*4 + 0x19EDD8]                 ; jump table
```

`mov [esi+10h],0` is `info->refreshRate = 0`. **That is why the driver hardcodes
`Refresh:0Hz`** in `modeStringForDisplayInfo:` — spec 1's Task 6 recorded the
literal as faithful but unexplained. It is explained here: the kernel never sets
a refresh rate.

Note the field mapping confirms spec 1's `VBEModeRec` layout independently:
`xResolution` at `+4`, `yResolution` at `+6`, `bytesPerScanline` at `+8`,
`bitsPerPixel` at `+0x0A`, `frameBuffer` at `+0x14`.

## 4. `FBAllocateVBEConsole`

212 bytes at `0x0019ECB8`. Decoded:

```
5589E5 81EC88000000      push ebp; mov ebp,esp; sub esp,0x88   ; 136 = sizeof(IODisplayInfo)
57 56 53                 push edi/esi/ebx
66833D5C28010000 7409    cmpw ds:[0x1285C],0 ; je  -> return NULL
833D5428010000   7509    cmp  ds:[0x12854],0 ; jne -> continue
31C0 E99F000000          xor eax,eax; jmp 0x19ED7D             ; return NULL
8DB578FFFFFF 56          lea esi,[ebp-0x88]; push esi          ; the local IODisplayInfo
6858280100               push 0x12858                          ; the VBEModeRec
E89B000000               call _VBEModeInfo2IODisplayInfo
6A20 E844670000          push 32;  call _IOMalloc              ; sizeof(IOConsoleInfo)
68E4000000 E82A670000    push 228; call _IOMalloc              ; sizeof(ConsoleRep)
6A20 53 E828670000       push 32; push ebx; call _IOFree       ; failure path
C703A8EF1900             mov [ebx],      0x19EFA8              ; Free
C74304 7CDF1900          mov [ebx+4],    0x19DF7C              ; Init
C74308 CCEF1900          mov [ebx+8],    0x19EFCC              ; Restore
C7430C 3CE21900          mov [ebx+0Ch],  0x19E23C              ; DrawRect
C74310 CCE71900          mov [ebx+10h],  0x19E7CC              ; EraseRect
C74314 50F01900          mov [ebx+14h],  0x19F050              ; PutC
C74318 68F01900          mov [ebx+18h],  0x19F068              ; GetSize
8B7B1C 83C704            mov edi,[ebx+1Ch]; add edi,4          ; priv + 4
FC B922000000 F3A5       cld; mov ecx,34; rep movsd            ; copy 136 bytes = the IODisplayInfo
```

**This is `FBAllocateConsole` with a boot-struct guard in front.** Our
`IOConsoleInfo` (`bsd/dev/i386/ConsoleSupport.h`) is seven function pointers
followed by `void *priv` — **exactly 32 bytes**, matching the `IOMalloc(32)`,
and the slot order matches the seven stores at `[ebx+0]`…`[ebx+0x18]` one for
one: `Free, Init, Restore, DrawRect, EraseRect, PutC, GetSize`. Our
`FBAllocateConsole` (`FBConsole.c:1354`) fills the same seven, `IOMalloc`s a
`ConsoleRep` for `priv`, and copies the display into it.

The two guards read `0x1285C` as a word and `0x12854` as a dword. `0x12858` is
the `VBEModeRec` (spec 1's D1), so `0x1285C` is `+4` into it — `xResolution`.
What `0x12854` is, four bytes *before* the record, is discovery item D2.

**Implement it as a guard over the existing `FBAllocateConsole`, not as a
transcription.** Transcribing would duplicate 1,400 lines of console machinery
we already have, to reach a byte target that is unreachable anyway (§6).

## 5. The i386 wiring

ppc's `kmDevice.m:150-167` is the shape to mirror:

```c
if (framebufferArgs->v_baseAddr) {
    bzero(&bootDisplayInfo, sizeof(bootDisplayInfo));
    bootDisplayInfo.width      = framebufferArgs->v_width;
    bootDisplayInfo.height     = framebufferArgs->v_height;
    bootDisplayInfo.totalWidth = framebufferArgs->v_rowBytes;
    /* ... */
    basicConsole = BasicAllocateConsole(&bootDisplayInfo);
}
if (basicConsole == NULL)
    basicConsole = serialConsole;
```

i386's `BasicAllocateConsole()` gains the equivalent: consult
`kernBootStruct->video`, and when it names a framebuffer, build an
`IODisplayInfo` and allocate a frame-buffer console instead of the hard-coded
VGA one. **The existing VGA path stays as the fallback** — it is what runs today
and what runs whenever the booter has not set a mode, which is every boot until
spec 3.

There is no reference for this function: 4.2's `BasicAllocateConsole` is not
ours. It is justified from ppc's shape, not transcribed.

## 6. Parity policy

Spec 1's method does not transfer, and saying why matters more than the policy
itself. There we rebuilt a whole shipped binary and diffed it; here we add
functions to a kernel we build ourselves, whose every other address differs.

| Piece | Target | Why |
| --- | --- | --- |
| `VBEModeInfo2IODisplayInfo` | **Byte-parity**, 32-bit relocated operands masked | A leaf. No calls; only the jump-table base and its entries relocate. A genuine correctness oracle. |
| `FBAllocateVBEConsole` | **Structural parity** | Five `rel32` calls and seven absolute vtable pointers into a kernel whose addresses all differ. Byte-parity is *unreachable*, not merely hard. |
| The wiring | **No parity target** | No reference exists for it. |

One of three pieces has a byte oracle. **The boot gate therefore carries
proportionally more weight here than it did in spec 1** — which is acceptable,
because this spec is what creates the gate.

**Do not reuse spec 1's relocation-aware masking.** An earlier revision of this
section said the reference kernel carries scattered relocations and to mask from
them. That is wrong: the i386 slice is `MH_EXECUTE`, `nreloc` is 0 in *every*
section and there is no `LC_DYSYMTAB`. Our built kernel is likewise linked, so a
relocation-driven mask silently masks nothing here.

Mask **by pattern** instead, as the plan describes: the `imm32` of the
`FF 24 85 <imm32>` dispatch, and the inline jump table's entries. Task 1
measured both - the dispatch is at function offset **68**, so its operand sits
at **71**, and the table is 31 entries at offset 76.

## 7. Discovery items

Answered from the disassembly. None may be invented.

| | Item | Why it matters |
| --- | --- | --- |
| D1 | The real extent of `VBEModeInfo2IODisplayInfo` | The symbol table is sparse — the next *named* symbol is 7,484 bytes on. Bound it via the jump table at `0x19EDD8`, not by symbol delta. |
| D2 | ~~What `0x12854` is~~ **Answered in Task 1, as a tightly-constrained inference — not a flat reading.** *Measured:* `pmap_bootstrap` writes it at `0x0018F1B4`, and `FBAllocateVBEConsole` reads it at `+57` into `IODisplayInfo.frameBuffer`, **overwriting** the physical address. *Inferred:* that the value is the mapped framebuffer's kernel virtual address — the reading that makes a pixel-writing console work, but the mapping code itself was not read. The 4.2 booter does not reference it. | This row previously said spec 3 has to write it. That was wrong, and it leaves the guard without a producer - see section 11. |
| D3 | `sizeof(ConsoleRep)` in our tree versus the reference's 228 | If they differ, the console's private layout differs, which bears on §4's "same structure" claim. `ConsoleRep` is at `FBConsole.c:135`; measure with `offsetof` on the guest, not by hand — spec 1's hand layout of a struct was 12 bytes out. |
| D4 | Whether both functions live in the FBConsole translation unit | They are adjacent in `__text`, which suggests one source file. Decides where our definitions go. |
| D5 | Whether the reference's `ConsoleRep` puts `display` at offset 4 | The `rep movsd` writes to `priv + 4`. Ours assigns `((ConsolePtr)cso->priv)->display`. |

## 8. Verification gates

| Gate | Check |
| --- | --- |
| 0 | `VBEModeInfo2IODisplayInfo`'s extent byte-identical to the reference, masked |
| 1 | The kernel builds on the Rhapsody guest and exports both symbols |
| 2 | **`sarld` links `VBE20DisplayDriver_reloc`** against the new kernel without error |
| 3 | Boot under QEMU: the driver loads, initialises and registers as `VBEDisplay0` |

**Gate 2 is the one that matters most.** It is the first direct evidence that
spec 1's reconstruction and this kernel agree on the contract — and it is
precisely the failure spec 1 is blocked on. It can be read from the booter's own
output before the kernel takes over.

**Gate 3 still reaches only the "card not in VBE mode" path.** Two independent
reasons, both from spec 1: the booter never enters a VBE mode, and the 4.2
mode-array offsets land inside Rhapsody's `_reserved[7500]` (908..8408), which
`getKernBootStruct()` has `bzero`'d. The driver will read zeros. Expected
output:

```
%s: VESA video driver initialization.
%s: Skipping framebuffer initialization (card not in VBE mode).
Registering: VBEDisplay0
```

The `%s: using VBE mode %d` path becomes reachable only after spec 3.

A boot gate here is also the first test of the console wiring — but only its
*fallback* arm, since `video.v_baseAddr` will be zero. The frame-buffer arm
cannot be exercised until spec 3 either.

## 9. Risks

**The console wiring is the only piece that can break a working boot.** The two
new functions are additive: nothing calls them until something does. Changing
`BasicAllocateConsole()` changes what every i386 boot uses for its console. A
mistake there turns a working boot into a silent one, and the console is how
failures get reported — so a failure there is self-concealing. The fallback path
must be preserved exactly, and the new arm must be reachable only when
`video.v_baseAddr` is non-zero, which is never until spec 3.

**`FBAllocateConsole` has never run.** It is compiled but dead, so this spec is
the first time its code executes. Bugs in it are Apple's or this tree's, latent
since 1999, and they will surface as *our* regression.

**Gate 3 may reveal the `_VBE20DisplayDriver_instance` hazard** that spec 1 could
not test. If the driver fails to *load* rather than to link, look there first —
spec 1's record documents the difference and warns against misdiagnosing it as a
source defect.

## 10. Success criteria

1. Both symbols exported by the built kernel, with `VBEModeInfo2IODisplayInfo`'s
   extent byte-identical to the reference under masking.
2. `sarld` links the spec 1 driver without error, and no driver linked after it
   is disturbed.
3. The driver loads under QEMU and logs the three lines of §8.
4. A boot with no VBE mode set behaves exactly as it does today — same console,
   same output. The wiring must be invisible until spec 3.
5. D1 through D5 answered in the evidence record, or explicitly recorded as
   not determinable with the reason.

## 11. Open: the framebuffer mapping has no owner

Task 1 answered D2 and the answer moved work between specs.

`0x12854` holds — **on a tightly-constrained inference, not a flat reading** —
the kernel virtual address of the mapped VESA linear framebuffer.

**What is measured.** In the 4.2 kernel it is written once, by `pmap_bootstrap`
at `0x0018F1B4` (`mov ds:[0x12854],ecx`). `FBAllocateVBEConsole` reads it at
`+57` and **overwrites** `IODisplayInfo.frameBuffer` with it, replacing the
*physical* address `VBEModeInfo2IODisplayInfo` had just copied out of the mode
record.

**What is inferred.** That the value is specifically a *mapped virtual* address.
It is the reading that makes sense — a console writing pixels needs one, and
`pmap_bootstrap` is where mapping happens — but Task 1 did not read the mapping
code that produces `ecx`. Spec 3 should confirm it before depending on it.

That makes sense: the booter records a physical address, and a console that
writes pixels needs a mapped virtual one.

**The 4.2 booter never references `0x12854`.** Task 1 verified this by sweeping
every 4-byte value in `[0x1800,0x1900)` of the booter. So it is kernel-private,
and this spec's earlier D2 row — "spec 3 has to write it" — was wrong.

**No task in this spec maps the framebuffer.** `FBAllocateVBEConsole`'s second
guard therefore has no producer on our side: it will read whatever our kernel
happens to have at that address, which is nothing, and the function will always
return NULL.

This does not block any of this spec's gates. Gate 2 (`sarld` links the driver)
and gate 3 (the driver loads) need only `VBEModeInfo2IODisplayInfo`.
`FBAllocateVBEConsole` is reached only from the Task 4 wiring, whose guard
cannot pass until spec 3 supplies a mode anyway. But it does mean the console
half of this spec is **present and shaped correctly, and inert**.

Adding the mapping means touching `pmap_bootstrap` — early kernel
initialisation, the riskiest code in the tree, and unexercised by any gate here.
That is why it is called out rather than absorbed.

**Decided: spec 3 owns it.** It lands alongside the booter work that produces
the physical address, so the framebuffer path arrives and is exercised as one
piece rather than half here and half there. Early-init changes stay out of a
spec that cannot test them.

**Consequence for this spec, stated plainly.** `FBAllocateVBEConsole` ships
correct in shape and **inert**: its second guard reads an address nothing
writes, so it always returns NULL, so the Task 4 wiring always falls through to
the existing VGA console. That is indistinguishable from the behaviour the
invisibility requirement (§9) demands anyway, and it is the honest description
of what this spec delivers. Do not write a placeholder producer to make it look
live.
