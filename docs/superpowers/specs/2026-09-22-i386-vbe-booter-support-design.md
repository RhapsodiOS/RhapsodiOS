# i386 VESA booter support and frame-buffer mapping: design

Spec 3 of three. Spec 1 reconstructed OPENSTEP 4.2 User Patch 4's
`VBE20DisplayDriver` (`docs/superpowers/specs/2026-09-21-vbe20displaydriver-reconstruction-design.md`).
Spec 2 added the kernel half it links against, `VBEModeInfo2IODisplayInfo` and
`FBAllocateVBEConsole`, and wired `BasicAllocateConsole()` to try the latter
first (`docs/superpowers/specs/2026-09-21-i386-vbe-kernel-support-design.md`).

Both halves read data that nothing in our tree produces yet. This spec adds the
producers. The booter enters a VBE mode and records it. The kernel maps the
frame buffer and publishes the mapped address. With both in place the
frame-buffer console runs for the first time.

Claims below are marked **[measured]** when read out of a binary, a file or a
boot, and **[inference]** when reasoned from those readings.

## 1. Decisions

Settled with the user before this spec was written:

| Question | Decision |
| --- | --- |
| Fidelity of the booter's VBE code | **Measure first, then byte parity per function**, as in specs 1 and 2. Forced departures are recorded, not hidden. |
| When spec 3 is done | **Kernel frame-buffer console.** The booter enters a VBE mode and fills the mode record and array. The kernel maps the frame buffer. The boot console draws through the frame-buffer console. The driver logs `using VBE mode N` and exports a non-empty mode list. The desktop stays on today's VGA path. |
| Booter size budget | **Measure, then trim boot2.** `boot1`, its 45,056-byte load limit and the disk layout stay as they are. If trimming cannot find the room, stop and bring it back to the user. |
| Gate G5 | **In.** A negative-control boot with the driver linked first. |

Work happens on branch `vbe20-booter`, cut from `vbe20-kernel` in the same
worktree, `.worktrees/vbe20-kernel`. Neither parent branch is merged to master,
so spec 1's driver and spec 2's kernel travel with it.

## 2. Out of scope

- **The Window Server.** The desktop keeps running on `VGA_psdrvr`. The 4.2
  patch ships no Window Server half for this driver; its second binary is a
  Configure.app inspector.
- **Raising `boot1`'s load limit**, and any change to `boot1` or the disk label.
- **The UEFI booter** in `src/bootefi-1`.
- **Hardware.** Every gate runs under QEMU.

## 3. The contract: what the booter and kernel write

The driver and the kernel already read four fixed addresses inside
`KERNBOOTSTRUCT` (`0x11000`). Both hard-code them as integer constants, because
the references do **[measured]**: `VBE20DisplayDriver.m:79-81` and
`FBConsole.c:1510-1511`. They cannot move without losing byte parity, so the
producers write exactly there.

| Address | Offset | What | Written by |
| --- | --- | --- | --- |
| `0x12854` | 6228 | kernel virtual address of the mapped frame buffer | kernel, `pmap_bootstrap` |
| `0x12858` | 6232 | 24-byte `VBEModeRec` for the mode the booter set | booter |
| `0x12870` | 6256 | array of `VBEModeRec`, 0x880 bytes | booter |

All three fall inside Rhapsody's `char _reserved[7500]`, bytes 908 to 8408.
`boot_video` follows at 8408 to 8432 **[measured on the guest with `offsetof`,
spec 1 §3]**.

**Named fields, same offsets.** Both copies of the header gain named fields cut
out of `_reserved`: `src/boot-2/i386/libsa/kernBootStruct.h` and the live
struct in `src/kernel-7/machdep/i386/kernBootStruct.h` (the one after `#else`,
not the dead `#if 0` copy). A negative-array-size `typedef` after each struct
asserts three things:

- the new fields sit at exactly 0x1854, 0x1858 and 0x1870;
- the carved block still totals 7500 bytes;
- so `video`, `pciInfo`, `eisaSlotInfo` and `config` do not move.

This is the reconciliation spec 2 deferred to here. The driver and kernel keep
their constants. The assertions tie those constants to the struct, and a
comment beside each constant names the field it addresses.

**At most 89 records. This is a forced divergence.** 4.2 accepts up to 90
records. The driver's bound gives that count (`0x880 = 24 * 90 + 16`), and so
does the 4.2 booter's own enumerator, independently: it stops once the record
index exceeds 89 (`cmp eax, 897h` at `boot+27911`) **[measured, spec 1's record
`src/drivers-i386/video/drvVBE20DisplayDriver/reconstruction/divergences.md`]**.
In our layout, record 89 (the 90th) spans 8392 to 8416 and would overwrite
`boot_video.v_baseAddr` and `v_display`. The invariant is therefore:
**the booter writes nothing at or beyond offset 8408.** At most 89 records go
in (indices 0 to 88). Index 89 is left as the booter's `bzero` left it, so the
driver's scan reads `modes[89].xResolution` at offset 8396 as zero and stops at
89 **[inference from the driver's loop, `VBE20DisplayDriver.m:235-239`]**.

**Write order.** `getKernBootStruct()` (`src/boot-2/i386/libsaio/bootstruct.c:79`,
called from `boot2/boot.c:414`) `bzero`s the whole struct at `:84`. A booter
write that runs before it is silently erased and looks like "the guard never
passes". The kernel's write runs long after it and is safe.

**The large-memory branch.** `worktree-i386-large-memory` plans to cut
`memMapCount` and `memMap[]` from the **front** of `_reserved`, 388 bytes at 908
to 1296 (`docs/superpowers/plans/2026-09-20-i386-large-memory.md` on that
branch, its Task 3 Steps 2-3; `BOOT_MEMMAP_MAX` is 32 and each range 12 bytes). It does not overlap 6228 to 8408. It has not been implemented yet
**[measured: that branch's two headers do not differ from master]**. Whichever
branch merges second must merge the two carve-outs and update the other's
7500-byte assertion.

## 4. The booter

### 4.1 What is known before measurement

**The 4.2 booter** is `./usr/standalone/i386/boot` from the patch: 44,848 bytes,
SHA-256 `925D35B6…75CBCE`. It is headerless, and it prints itself as
`OPENSTEP boot v40.13.1.2` **[measured]**. Extract it with
`vm/extract-os42-patch.py`.

**It loads at `0x3000`, the same address as ours.** Every one of twelve
VBE-related strings is referenced as an absolute address at base `0x3000`, and
none at bases 0, `0x1000` or `0x2000` **[measured]**. The 32-bit operands that
name them, by file offset:

| String | Operand at |
| --- | --- |
| `VBE Mode` (config key) | `0x3D6`, `0x403` |
| `VBE Check` | `0xA15` |
| `Usable VBE modes:\n` | `0xA6F` |
| `The VBE video driver can not be used with this display adapter.\n` | `0xB2F` |
| `Boot Graphics` | `0xBD2` |
| `VESA not available.\n` | `0x6DB0` |
| `VBE mode %d not supported.\n` | `0x6DDF` |
| `No usable VBE mode. Reverting to VGA.\n` | `0x6DF7` |
| `Using VBE Mode %d.\n` | `0x6E0F` |
| `Error in setting mode. VESA VBE error #%d\n` | `0x6E48` |
| `Error in setting palette. VESA VBE error #%d\n` | `0x6EA4` |

So the VBE code sits in two places. Near the top of the image is the key, the
`VBE Check` listing and the adapter warning. Around `boot+0x6B00..0x6F00` are
mode set, palette and messages. Spec 1's record has already mapped part of the
second region **[measured there]**:

- one record writer at `boot+27556` (`0x6BA4`) makes fourteen stores, one per
  `VBEModeRec` field;
- the enumerator at `boot+27704..28030` walks the BIOS's `VideoModePtr` list
  and calls the writer once per record, starting at `kbs+0x1870`;
- a later call writes the current mode's record at `kbs+0x1858`;
- both reach the struct through a global pointer at `0xDA7C`.

`boot+2652..2857`, which prints `Usable VBE modes:`, only reads the array.

**Our booter.** `src/boot-2` builds to 44,576 bytes against a limit of 45,056,
with 480 to spare (`docs/boot/sarld-driver-link-limit.md`). The limit is
physical. `boot1` loads 88 sectors to `0:0x3000` and has moved itself to
`0xE000`, which is exactly where 88 sectors end; its stack sits at `0:0xFFF0`
(`boot1.s:38-40, 54, 76, 84, 209-210`). Apple's stock v5.0.41.1 booter, which is
on `golden.img` today, is only 39,616 bytes
(`docs/superpowers/plans/2026-09-20-i386-large-memory.md`, "Image slack"). So
our build carries about 5 KB that Apple's did not.

**Our booter's VBE path is dead today.** `setMode()` enters graphics only when
a `"Graphics Mode"` key is set (`graphics.c:189-190`), and no config sets it.
`set_linear_video_mode()` accepts only `VESAVersion == 0x200` (`vbe.c:66`), and
it returns `void`, so its caller records success even when it failed
(`graphics.c:198-208`). 4.2 replaces this path with the `VBE Mode` key and the
messages above.

### 4.2 Task 1 measures

Each item has a stated use. Nothing here is written down as fact until it is
measured.

1. **Inventory of 4.2's VBE functions**: extents, calls, strings, and every
   store into `KERNBOOTSTRUCT`. Gives the list of functions to reconstruct.
2. **Their size built with our compiler.** Gives the byte budget trimming must
   find.
3. **Where our extra ~5 KB comes from**, against Apple's 39,616-byte booter:
   per-object sizes, compiler flags, dead code. Gives the trimming candidates.
4. **Where 4.2 reads `VBE Mode`**: the system config, the driver's own table, or
   both. Spec 1's `Default.table` sets `"VBE Mode" = "257"`. Decides what a test
   image must configure.
5. **4.2's version test** against `VESAVersion`. Decides whether the version
   check is a forced divergence.
6. **What QEMU's VGA BIOS reports** on `-vga cirrus` and `-vga std`: VBE version,
   modes with linear frame buffers, and mode 257 in particular. Picks the G2
   adapter.
7. **Whether 4.2 enters VBE mode on a `-v` boot.** Decides which console G2
   observes, scrolling text or the graphics-mode panel.
8. **Whether 4.2 writes a zero terminator record** after the last mode. If it
   does, the terminator also counts against the 8408 invariant.
9. **Which depths `FBConsole.c` can draw.** Mode 257 is 8 bits per pixel. G2's
   mode must be one the console supports.
10. **What 4.2 does after `Reverting to VGA`**: which video mode it sets, and
    whether it sets `graphicsMode`. Our booter has no non-VBE graphics mode:
    `setMode()` falls to text mode whenever its key is absent
    (`graphics.c:209-211`). Gives G3 its expected output.

### 4.3 Reconstruction

For each function in the inventory, the per-function rule from specs 1 and 2
applies. Build it with our compiler and compare it with the reference, masking
only what must differ: absolute addresses of strings, globals and call targets,
which the reconstruction's layout moves. Then record one outcome in the
evidence record:

- **Byte parity**: every unmasked byte matches; or
- **Structural parity**: the same operations in the same order, with an exact
  count of the bytes that cannot match and why; or
- **Forced divergence**: the behaviour itself differs, with the reason on the
  line in both source and record.

Expected forced divergences:

- the 89-record cap (§3);
- the version check, if item 5 shows 4.2 accepts exactly 2.0 and item 6 shows
  QEMU reports anything else.

Reference defects are reproduced and labelled, as specs 1 and 2 did.

The existing `"Graphics Mode"` path goes, replaced by 4.2's. It has never run,
because no config sets its key. That includes its `kernBootStruct->video`
stores (`graphics.c:203-208`). Nothing i386 under `src/` reads `video`
**[measured: every `v_baseAddr` reader in the tree is ppc]**, and 4.2's booter is
not known to write it.

### 4.4 Trimming

The trim comes out of what item 3 finds. The rules:

- Nothing reconstructed for this spec is trimmed.
- Every removal says what it removes and why nothing needs it.
- The build's existing size check, which reads `LOADSZ` out of `boot1.s`, stays
  the arbiter.
- **Stop and bring it back to the user if trimming cannot make room without
  removing something that runs.**

## 5. The kernel: mapping the frame buffer

`pmap_bootstrap` in the 4.2 kernel writes `0x12854` at `0x0018F1B4`
(`mov ds:[0x12854],ecx`) **[measured, spec 2 Task 1]**. That the value is the
*mapped virtual* address of the linear frame buffer is **[inference]**: spec 2
never read the code that computes `ecx`. Task 1 reads it before anything
depends on it: where the physical address and length come from, how the
mapping is made, and what happens when there is no mode.

The mapping is reconstructed under the same per-function rule. Byte parity is
unlikely, because it sits inside a large function that differs between the two
kernels. The expected outcome is structural parity, recorded as
`FBAllocateVBEConsole`'s was.

**No mode record, no mapping.** When `kbs+0x1858`'s `xResolution` is zero, the
kernel maps nothing and leaves `0x12854` zero. So a boot with the stock booter,
or with our booter on an adapter without VBE, behaves exactly as spec 2 left it
(gate G4).

**`FBAllocateConsole` runs for the first time.** On i386 it has never
executed: spec 2's arm was unreachable by design. Nothing about the console
code itself is assumed to work.

## 6. Putting our booter on a test image

**Copying the file is not enough.** `boot1` does not load
`/usr/standalone/i386/boot`. It reads the NeXT label at sector 15, takes
`dl_boot0_blkno[0]`, and loads 88 sectors from there (`boot1.s:60-68,
185-210`). The file also has too little room: its slot on `golden.img` holds
39,936 bytes, and our booter is 44,576.

So Task 1 measures both boot-area copies on `golden.img`: where each starts and
how much room each has. A small `vm/` tool then writes our `boot2` into both.
The tool:

- works only on `vm/work/test.img`, through the existing
  `rhap_inject.check_target` guard;
- refuses a booter that does not fit the measured room;
- reads both copies back and checks their hash.

**The boot area of `golden.img`**, measured during planning and re-measured
in spec 3 Task 3 (2026-09-22). `golden.img` is SHA-256
`E1968E3EF57F3060AA01CEAB8B4D5C49C067E6ACC5F8626EBABEEFE0E663879F`.

- **The label and the partition table [measured].** The NeXT label is at
  sector 15 (byte 7,680). There is no fdisk partition: the MBR's four entries
  are zero.
- **The label's geometry [measured].** `d_secsize` is 1,024, `d_front` is
  160, and `d_boot0_blkno` is (32, 96).
- **The two boot copies [measured].**
  - They start at bytes 32,768 and 98,304. Each slot is 65,536 bytes: the
    second one runs to the end of the front porch, at 163,840.
  - Both hold the stock `/usr/standalone/i386/boot`, followed by zeros. That
    booter is v5.0.41.1: 39,616 bytes, SHA-256
    `AA06C3C5BFE56C79573E36D20C662DA10CA67D0CEC5BE17F13A5B562F6B5F2C2`.
- **The file is not what boots [measured].**
  - `boot1` reads `d_boot0_blkno[0]` from the label.
  - The file's own slot is 39,936 bytes, too small for our 44,576-byte
    booter anyway.
- **Both slots hold 45,056 bytes [measured].** 45,056 is `boot1`'s
  `LOADSZ` limit. So §8's deployment risk does not arise.
- **The 4.2 booter loads at `0x3000` [measured].** All twelve VBE string
  operands resolve at that base, and none at 0, `0x1000` or `0x2000`.
- **Writing a booter [measured].** `vm/install-booter.py` writes both
  copies. Task 3 used it to install our booter and the 4.2 booter, and read
  both slots back.
- **Proof of which booter ran [measured].**
  - It is the banner on the 5-second frame: ours prints `Rhapsody boot
    v5.0.2`, the stock booter `Rhapsody boot v5.0.41.1`.
  - Our `VBE Check` prompt cannot serve until the reconstruction adds it.
  - The details are in `src/boot-2/reconstruction/vbe/divergences.md`.

**Every boot proves which booter ran.** The capture must show something only
our build prints. The `VBE Check` prompt serves. The stock booter has no such
string.

The booter is built with `rbuild`, as `vm/build-i386-booter.sh` does, and the
kernel with `rbuild kernel --toolchain <profile>`. Neither is built with a
direct `gnumake`.

## 7. Gates

Every comparison is a same-session A-B-A (control, candidate, control), on a
temporary image, with the image's hash recorded. The same comparison rules as
spec 2 apply:

- serial line 4 has only its build date masked;
- the IDE-probe and `phantom IRQ 15` lines may swap position;
- frames have only the boot-clock digits masked.

- **G1. Nothing changes without a VBE mode.** Control: our booter built from
  this branch's base. Candidate: our booter with this spec. Both run with no
  `VBE Mode` key set. The two must match everywhere except where §6 requires
  them to differ (the proof of which booter ran). A guest memory dump shows
  `kbs+0x1854` through `+0x20D8` all zero.
- **G2. The VBE path.** Run on the adapter item 6 picked, with the driver
  installed and `VBE Mode` set. Five checks:
  - the booter's panel is drawn in the VBE mode;
  - a memory dump shows `kbs+0x1854` non-zero, the record at `0x1858` naming
    mode N, 1 to 89 records from `0x1870`, and the record after the last one
    zero;
  - serial shows `Using VBE Mode N`, the driver's `using VBE mode N`, and one
    `VBE mode ... is width=` line per record;
  - the kernel console renders through the frame-buffer console, at the mode's
    size rather than VGA's, in whichever console mode item 7 says 4.2 used;
  - nothing at or beyond offset 8408 is written by the VBE code: `boot_video`
    (8408 to 8432) matches G1's dump.
- **G3. Fallback.** Two cases: `VBE Mode` names a mode the BIOS does not offer,
  and an adapter with no usable VBE. The booter must print 4.2's message for
  each case, and the boot must continue on the VGA console with no mode record
  written.
- **G4. The kernel alone.** The new kernel with the stock booter must reproduce
  spec 2's result: the driver's `Skipping framebuffer initialization` line, and
  VGA console output matching a spec 2 kernel in the same session.
- **G5. Link order.** A kernel without `_VBEModeInfo2IODisplayInfo`, with the
  driver listed **first** in `Boot Drivers`. `install-driver.py` always appends,
  so the list has to be reordered. This turns spec 2's "does not cascade at any
  position" from an inference into a measurement. Record the result whichever
  way it falls. A cascade here is a finding about `sarld`, not a failure of
  this spec.

The record of these gates goes in `docs/kernel/i386-vbe-console.md`, extending
spec 2's gate record. It includes the hashes, since the captures cannot be
regenerated.

## 8. Risks

- **The alert console moves too.** `kmDevice.m:85` and `:962` (`kmAlertConsole`)
  also call `BasicAllocateConsole()`, so they get a frame-buffer console once
  `0x12854` has a producer. Panic output changes appearance on VBE boots. Record
  this. One forced-panic boot is optional.
- **An early hang with no console.** A mapping mistake in `pmap_bootstrap` can
  hang before any console exists. Serial capture is the backstop, and the
  mapping is reachable only when the booter wrote a mode (§5).
- **First run of the frame-buffer console code** (§5). A defect there is not a
  defect in the reconstruction until shown to be.
- **Trimming** may take more judgement than expected. The stop rule in §4.4
  covers it.
- **The merge with the large-memory branch** (§3).
- **Deployment** depends on Task 1's boot-area measurement. If the copies
  cannot hold 45,056 bytes, stop and report. Do not move them.

## 9. Evidence records

- `src/boot-2/reconstruction/vbe/divergences.md`, new. Booter functions, the
  size budget and the trim. It follows the conventions of spec 2's record:
  `[measured]` and `[inference]` on the line, `boot+N` file offsets, and
  retracted text labelled in place rather than deleted.
- `src/kernel-7/reconstruction/vbe/divergences.md`, extended with the
  `pmap_bootstrap` mapping.
- `docs/kernel/i386-vbe-console.md`, extended with G1 to G5.
- Status rows in `docs/drivers/video-reconstruction.md` and
  `src/drivers-i386/README` for the driver's `using VBE mode` path.
