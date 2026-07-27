# drvVGA divergences

This document covers both halves of Apple's VGA display driver:

| Binary | Mach-O type | Size | SHA-256 |
| --- | --- | --- | --- |
| `VGA_reloc` | MH_PRELOAD | 71112 | `489D86652B8718237052F10A551FC6615B4B045F6614DCB790CFB73272C15B96` |
| `VGA_psdrvr` | MH_BUNDLE | 26584 | `E785BA22F1121EAAE140A2340C5068AE1FC23EBC3309F02E7705D8775E47C1F4` |

Reference paths, per shell session via `BINRECON_REFERENCE`:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_reloc
C:\Users\raynorpat\Downloads\test\Drivers\i386\VGA.config\VGA_psdrvr
```

**No function in either binary was examined against our source, because our
source is disjoint from Apple's.** Our `VGA.lksproj` implements a class `VGA`
subclassing `IOFrameBufferDisplay`; Apple's `VGA_reloc` implements
`IOVGADisplay`, `IOVGADisplay(VESAMode)` and `vidBIOS`. Our
`VGA_psdrvr.tproj` is a 127-line invented printing API; Apple's `VGA_psdrvr`
is the Window Server's framebuffer and cursor driver. The two share no
symbol, no string and no class name, and both source maps put every reference
function in `unmapped` as a result. This document therefore records **the
reference's behaviour and the divergences of the project around it, not a
function-by-function diff**. There is nothing to diff until Phase 3 writes the
replacements.

## Evidence

### Analyzer coverage differs per binary, and both reductions are deliberate

| Binary | IDA 9.2 | Ghidra 12.1 | angr 9.3.0 |
| --- | --- | --- | --- |
| `VGA_reloc` | yes | yes | **disabled** |
| `VGA_psdrvr` | yes | **disabled** | **disabled** |

`VGA_reloc` — angr is disabled in `tools/binrecon/profiles/vga-reloc.json`.
Its CFGFast recovers a phantom 6-byte function at 7760, inside `_emu486`'s
primary chunk, that misdisassembles bytes IDA and Ghidra both read correctly;
relocation 353 then no longer fits inside its owning instruction and
consensus normalization aborts with `relocation 353 is outside its
instruction`. IDA also had to be forced to `-pmetapc`: this binary's Mach-O
header carries `cpu_subtype = 4` (`CPU_SUBTYPE_486`), for which IDA's loader
auto-selects the legacy `80486p` processor module and the exporter's
`metapc` assertion fails. That fix (`8d8cfd20`) is a no-op for every other
reference binary in this repo, all of which are `cpu_subtype = 3`.

`VGA_psdrvr` — **IDA alone**. angr cannot produce an analysis document for
this bundle at all: its CFG recovery fails outright with `block at address
1882209993 is outside function at address 1882210007`. Ghidra produces a
document, but all 48 of its relocation records come back as `r_type == 0` —
`GENERIC_RELOC_VANILLA`, the only relocation kind an i386 image of this era
emits — which gives `normalize_analysis` nothing to derive a field width
from, so it aborts on the first (`relocation 0 has missing or conflicting
width`). IDA-alone was accepted for this binary specifically because the
Mach-O symbol table independently corroborates the partition: every
symbol-table `__TEXT,__text` entry appears in IDA's function list, the sole
exception being `__mh_bundle_header`, which IDA correctly declines to treat
as a function. The symbol table is linker-emitted ground truth rather than a
fourth analyzer, so this is real corroboration — but it depends on this
binary retaining its full external symbol table and **would not be sufficient
for a stripped binary**.

Ghidra's relocation-kind gap looks like a limitation of its own Mach-O loader
for MH_BUNDLE inputs rather than a defect in `binrecon`'s Ghidra adapter, and
nobody has investigated it. It is recorded here as a candidate for separate
infrastructure work, not something this effort fixes.

IDA drops duplicate names at a single address, which is why `_Start`
disappeared from the psdrvr analysis even though the symbol table carries
both `_Start` and `_VGAStart` at 1882203272.
`tools/binrecon/restore_symbol_aliases.py` now restores dropped aliases from
the binary's own symbol table, and the committed psdrvr source map was
validated against its output.

### Function partition

`VGA_reloc`, 36 entries:

| Bucket | Count |
| --- | --- |
| mapped | 0 |
| unmapped | 36 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Reason classes: 34 `no counterpart in our source`; 2 build-generated
(`+[VGAKernelServerInstance kernelServerInstance]`,
`+[VGAVersion driverKitVersionForVGA]`, emitted by the Kernel Server project
type).

`VGA_psdrvr`, 37 entries:

| Bucket | Count |
| --- | --- |
| mapped | 0 |
| unmapped | 37 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Reason classes: 18 `no counterpart in our source` (hand-written bodies, with
`_Start`/`_VGAStart` merged into one entry); 2 dyld glue routines
(`dyld_stub_binding_helper`, `__dyld_func_lookup`); 17 linker-generated PIC
symbol stubs filling `__TEXT,__picsymbol_stub` (442 bytes, exactly 17 × 26).

**Nothing was moved by hand in either binary.** `mapped` came back empty on
its own in both runs, so there was no false positive to correct in Task 7
Step 4 or Task 8 Step 4.

### The partition rule excludes 2807 bytes of real static code in the psdrvr

The spec's rule is that a function is an entry IDA names (§4.3). For
`VGA_reloc` that rule excludes 69 unnamed fragments totalling 1279 bytes
which are `_emu486`'s per-opcode handlers — not independently
reconstructable functions, so the exclusion is right there.

For `VGA_psdrvr` the same rule excludes **16 unnamed entries totalling 2807
bytes of `__TEXT,__text`'s 7057** — about 40% of the section — and these are
*not* fragments. They are ordinary `static` C functions with full
prologues, their own stack frames, and calls to the named routines. Eleven
of them are the entries of the Window Server driver vector table at
`0x70304018` that `_VGAStart` installs into its screen descriptor's `+0x0C`
field; two of them are the cursor blitters that `_VGASysShowCursor` and
`_VGASysHideCursor` call, and are the direct counterparts of the kernel's
`_VGADisplayCursor` and `_VGARemoveCursor`:

| Address | Size | Role |
| --- | --- | --- |
| `0x70301F58` | 127 | vector-table entry `+0x0C`; fills the screen descriptor's geometry and bounds, writes `_vgaBounds` |
| `0x70301FD8` | 96 | sends `IO_Framebuffer_Register` (see the shared contract below) |
| `0x70302038` | 7 | empty stub, vector-table entry `+0x50` |
| `0x70302040` | 521 | vector-table entry `+0x00`; calls `_vga_at_mode12_bpp2_to_bpp4` |
| `0x7030224C` | 36 | vector-table entry `+0x04` |
| `0x70302270` | 57 | vector-table entry `+0x10` |
| `0x703022AC` | 45 | vector-table entry `+0x14` |
| `0x703022DC` | 29 | vector-table entry `+0x18` |
| `0x703022FC` | 111 | vector-table entry `+0x1C` |
| `0x7030236C` | 223 | vector-table entry `+0x24` |
| `0x7030244C` | 58 | vector-table entry `+0x2C` |
| `0x70302BEC` | 603 | **draw cursor** — called by `_VGASysShowCursor` |
| `0x70302E48` | 481 | **erase cursor** — called by `_VGASysHideCursor` |
| `0x703030F0` | 81 | leaf helper, no calls |
| `0x70303144` | 92 | leaf helper, no calls |
| `0x70303844` | 240 | helper, one internal call |

The remaining 51 bytes of `__text` are inter-function alignment padding.

This is a limitation of the map, not of the analysis: the map's partition is
sound and `load_source_map` accepts it, but a rewrite that implements only
the 37 mapped entries would reproduce 4199 of 7057 `__text` bytes and none of
the cursor drawing. The spec's §1.1 psdrvr table compounds this by deriving
sizes from symbol gaps — it gives `_VGAUnshieldCursor` 1164 bytes where IDA
gives 73, because the gap silently absorbed `0x70302BEC` and `0x70302E48`.
Phase 3a has to cover these sixteen bodies whether or not the map lists them.

### Correction: the partition rule is containment, not naming

§4.3's rule ("a function is an entry IDA names") was drawn from `VGA_reloc`,
where the unnamed entries really are `_emu486`'s per-opcode jump-table
fragments. Applied to `VGA_psdrvr` it excluded 2807 of 7057 `__text` bytes of
ordinary `static` code, including both cursor blitters. The corrected rule
(§4.3, commit `1055b9cd`): a function is any entry not wholly contained
within another entry's extent. A contained entry is a basic block of its
container and is excluded; a standalone unnamed entry is a `static` function
and is included, under a synthesized `sub_<ADDRESS>` name.

`tools/binrecon/filter_contained_fragments.py` implements this and both
source maps were regenerated from its output:

- `VGA_reloc`: 38 entries (36 named + 2 standalone unnamed at `0x3D18`/81
  bytes and `0x3D69`/37 bytes). The other 67 unnamed fragments, 1161 bytes
  total, remain excluded — they lie inside `_emu486`'s extent and stay its
  internals.
- `VGA_psdrvr`: 53 entries (37 named + all 16 unnamed). All sixteen statics
  in the table above, including both cursor blitters and the eleven-entry
  driver vector table, are now covered by the map.

Both regenerated maps still land every entry in `unmapped` — our sources are
still disjoint from Apple's — and `load_source_map` accepts both.

### Baseline and rebuilt build

The driver had never been built in this tree. It builds now.

| Artifact | Task 5 baseline | Task 6 rebuild | Apple's |
| --- | --- | --- | --- |
| `VGA_reloc` | 146724 | 146792 | 71112 |
| `VGA_psdrvr` | 20908 | 20908 | 26584 |

Ours are unstripped; the `VGA_reloc` size difference is expected and is not a
finding. The 68-byte growth between the two runs is `Unload_Commands.sect`
plus its alignment.

All five `Loaded Server` sections match Apple's byte for byte after Task 6:

| Section | Ours | Apple's | Content |
| --- | --- | --- | --- |
| `Server Name` | 3 | 3 | `VGA` |
| `Load Commands` | 164 | 164 | the `WIRE` block |
| `Unload Commands` | 67 | 67 | the termination block |
| `Instance Var` | 12 | 12 | `VGA_instance` |
| `Server Version` | 1 | 1 | `2` |

`Load Commands` reached 164 and `Unload Commands` reached 67, so both of
§2.7's build questions are closed.

`parity_check.py` baseline for `VGA_reloc`, against the still-invented
sources: `missing_strings` 29, `missing_symbols` 28, `extra_strings` 19,
`extra_symbols` 34. That is the number Phase 3b has to drive to zero on the
missing side.

`parity_check.py` cannot read our `VGA_psdrvr` at all — see the open build
defect under Project divergences.

## Shared contract

`VGA_reloc` and `VGA_psdrvr` share a region of memory and a parameter
protocol. This section settles what they must agree on, read from both
binaries' disassembly rather than inferred from the header alone. Everything
below is checked against `src/driverkit-3/driverkit/IOVGAShared.h` as
committed, which both reference binaries were compiled against.

### 1. `VGAShmem_t` layout

**The size the kernel checks matches `IOVGAShared.h` as checked in.** The
check lives in `-[IOVGADisplay _registerWithED]` at address 0 of
`VGA_reloc`, not in `getIntValues:`:

```
     9  mov  edi, [ebp+self]
    12  lea  edx, [ebp+__len]          ; &shmem_size
    15  push edx
    16  lea  edx, [edi+1FCh]           ; &self->priv
    22  push edx
    23  lea  edx, [ebp+var_8]          ; &bounds
    26  push edx
    27  push edi                       ; self
       ...                             ; [[EventDriver instance]
       ...                             ;   registerScreen:bounds:shmem:size:]
    63  mov  esi, eax                  ; token
    65  mov  ebx, [edi+1FCh]           ; shmem
    74  cmp  esi, 0FFFFFFFFh
    77  jz   loc_D4                    ; token == -1 -> IO_R_INVALID_ARG
    83  cmp  [ebp+__len], 1448h        ; shmem_size > sizeof(VGAShmem_t)?
    90  ja   loc_8C                    ; yes -> log, unregister, IO_R_INVALID_ARG
    92  ...  memset(shmem, 0, shmem_size)
   104  mov  byte ptr [ebx+8], 1       ; shmem->cursorShow = 1
   108  mov  edx, [ebp+var_8]
   111  mov  [ebx+30h], edx            ; shmem->screenBounds.minx/maxx
   114  mov  edx, [ebp+var_4]
   117  mov  [ebx+34h], edx            ; shmem->screenBounds.miny/maxy
   120  ...  [self setToken:token]
```

`0x1448` is 5192. Computing `sizeof(VGAShmem_t)` from the committed header —
`int frame` 4, `ev_lock_data_t cursorSema` 4 (`volatile int`), four `char`
flags, six `Bounds`/`Point` members, `Point hotSpot[4]`, then the cursor
union whose largest arm is `struct bm38Cursor` at 4096 + 1024 = 5120 — gives
72 + 5120 = **5192**. Exact match. The header is authoritative and needs no
change.

The comparison is `ja`, i.e. unsigned strictly-greater, so a region *smaller*
than `sizeof(VGAShmem_t)` is accepted; only the `memset` and the field writes
that follow assume it is large enough for the arm actually in use. That is
deliberate — it is the same allowance `IOFrameBufferDisplay` makes for
`StdFBShmem_t`, so that a low-bit-depth driver need not be handed the
5120-byte 24-bit cursor arm.

The failure path logs
`"%s: shmem_size > sizeof (VGAShmem_t)(%d<>%d)\n"` with
`(name, shmem_size, 5192)` — the first `%d` is the region actually handed
over, the second is the compiled-in `sizeof` — then
`[[EventDriver instance] unregisterScreen:token]` and returns
`IO_R_INVALID_ARG` (`0xFFFFFD3E`, -706).

Every offset both binaries touch, and which side touches it:

| Offset | Field | Kernel | Window Server |
| --- | --- | --- | --- |
| `0x00` | `int frame` | writes (`showCursor:`, `moveCursor:`), reads | reads |
| `0x04` | `ev_lock_data_t cursorSema` | `_ev_try_lock` / `_ev_unlock` | `_ev_lock` / `_ev_unlock` |
| `0x08` | `char cursorShow` | reads/writes | reads/writes |
| `0x09` | `char cursorObscured` | reads/writes (`moveCursor:`) | reads/writes (`_VGAObscureCursor`, `_VGARevealCursor`) |
| `0x0A` | `char shieldFlag` | reads | writes (`_VGAShieldCursor`, `_VGAUnshieldCursor`) |
| `0x0B` | `char shielded` | reads/writes | reads/writes |
| `0x0C` | `Bounds saveRect` | reads/writes (blitters) | reads/writes (blitters) |
| `0x14` | `Bounds shieldRect` | reads | writes (`_VGAShieldCursor`) |
| `0x1C` | `Point cursorLoc` | writes (`showCursor:`, `moveCursor:`) | reads |
| `0x20` | `Bounds cursorRect` | reads/writes | reads/writes |
| `0x28` | `Bounds oldCursorRect` | writes, blitters read | writes, blitters read |
| `0x30` | `Bounds screenBounds` | writes (`_registerWithED`), blitters read | not observed |
| `0x38` | `Point hotSpot[4]` | reads | writes (`_VGASetCursor`), reads |
| `0x48` | `cursor` union | reads | writes and reads |

Independent confirmations of the offsets, from code rather than the header:
`[shmem+8] = 1` for `cursorShow`; `[shmem+0x30]`/`[shmem+0x34]` receiving the
8-byte `Bounds` the event driver returned, for `screenBounds`;
`[shmem + frame*4 + 0x38]` for `hotSpot[frame]`; `[shmem+0x1C]`/`[shmem+0x1E]`
for `cursorLoc.x`/`.y`; `[shmem+0x20..0x26]` for the four `cursorRect`
shorts; `[shmem+0x14..0x1A]` for the four `shieldRect` shorts.

**Both sides use the `bm12` arm of the union, and nothing else.** The
addressing is decisive on both sides:

- kernel `_VGADisplayCursor`: `lea edx, [ebx+eax+48h]`,
  `lea ecx, [ebx+eax+148h]`, `lea eax, [ebx+248h]`;
- Window Server `_VGASetCursor`: `frame << 6` added to `shmem + 0x48` and to
  `shmem + 0x148`, then a 64-byte `bcopy` into each; the two blitters do
  `add ebx, 248h` on the shmem pointer.

Against the header, `struct bm12Cursor` at offset 72 gives `image[4][16]` of
`unsigned int` at `0x48` (64 bytes per frame), `mask[4][16]` at `0x148`, and
`save[16]` at `0x248`. All three offsets and the 64-byte per-frame stride
match exactly. The `bm18`/`bm34`/`bm38` arms are never addressed by either
binary; they exist only to fix the union's — and therefore the struct's —
size at 5192.

The consequence for the rewrite: `saveRect` and `cursor.bw.save[16]` are a
single shared scratch pair that **both** sides write. Whichever side last
drew the cursor owns the saved pixels underneath it, and the only thing
serializing that is `cursorSema`. Neither rewrite may treat them as private.

### 2. The `IO_Framebuffer_*` parameter protocol

`IOVGAShared.h` declares the names and their sizes; the binaries show which
side actually sends each one.

**Correction to spec §4.3.** The spec states that every `IO_Framebuffer_*`
name appears in the `__cstring` of both binaries. It does not. `VGA_reloc`'s
`__cstring` carries all seven names. `VGA_psdrvr`'s carries only three —
`IO_Framebuffer_Register`, `IO_Framebuffer_SetDimensions` and
`IOGetDisplayInfo` — plus `Set VGA VESA Mode`. The bundle never sends
`IO_Framebuffer_Map`, `IO_Framebuffer_Unmap`, `IO_Framebuffer_Dimensions` or
`IO_Framebuffer_Unregister`; it maps the frame buffer itself, through
`_IOMapEISADeviceMemory` and `_IOMapEISADevicePorts`. The kernel side
implements all seven regardless, so those four exist for other clients (the
event driver and the console) rather than for this bundle.

Kernel dispatch is a chain of inline string compares in
`-[IOVGADisplay getIntValues:forParameter:count:]` (0x13C4) and
`-[IOVGADisplay setIntValues:forParameter:count:]` (0x157C); anything that
matches nothing falls through to `objc_msgSendSuper`.

| Parameter | Direction | Sent by | Count | Kernel behaviour |
| --- | --- | --- | --- | --- |
| `IO_Framebuffer_Map` | get | nobody in this pair | writes 1 | `values[0] = [self map]`; `*count = 1`; returns `IO_R_SUCCESS`. `-[IOVGADisplay map]` (0x1100) is a stub that returns 0 — the frame buffer is not mapped through this path. |
| `IO_Framebuffer_Unmap` | set | nobody in this pair | not checked | `[self unmap]`; returns `IO_R_SUCCESS`. `-[IOVGADisplay unmap]` (0x110C) walks `[[self deviceDescription] numPortRanges]` and calls `[self releasePortRange:i]` for each. |
| `IO_Framebuffer_Dimensions` | get | nobody in this pair | caller's `*count`, ≤ 3 | `[self displayInfo]`, then copies `width` (`+0`), `height` (`+4`) and `rowBytes` (`+0xC`) into `values`, stopping at the caller's incoming `*count` and setting `*count` to the number actually copied. Returns `IO_R_SUCCESS`. |
| `IOGetDisplayInfo` | get | `_VGAStart` | exactly 3 | Requires `*count == 3`; otherwise `IO_R_INVALID_ARG`. Returns a **hardcoded** triple, not `displayInfo`: `{800, 600, 200}` when the driver's `_svga_bios_mode` global is non-zero, `{640, 480, 160}` otherwise. |
| `IO_Framebuffer_SetDimensions` | set | `_VGAStart` | 3, unchecked | `[self displayInfo]`, then `width = values[0]`, `height = values[1]`, `rowBytes = values[2]`, `bitsPerPixel = 5` (`IO_VGA`). The count argument is never inspected; three ints are always read. |
| `IO_Framebuffer_Register` | get | the static at `0x70301FD8` | 1 | `[self _registerWithED]` (its `IOReturn` is the method's return value), then `[_kmId registerDisplay:self]`. Sets `*count = 0`; if the caller's incoming `*count` was non-zero, sets `*count = 1` and `values[0] = [self token]`. |
| `IO_Framebuffer_Unregister` | set | nobody in this pair | exactly 1 | Requires `count == 1`; otherwise `IO_R_INVALID_ARG`. `[[EventDriver instance] unregisterScreen:values[0]]`; returns `IO_R_SUCCESS`. |
| `Set VGA VESA Mode` | set | `_VGAStart` | exactly 1 | Requires `count == 1`; otherwise `IO_R_INVALID_ARG`. Sends `[self enterSVGAMode:]` with the driver's own `_vesaMode` global — **`values[0]` is read but not used**. Returns `IO_R_SUCCESS`. |

The compare lengths in the reference are `strlen + 1` in every case (19, 21,
26, 17, 29, 24, 26, 18 respectively), so the match is exact including the
terminator; a parameter name that merely shares a prefix does not match.

The Window Server's side of it, all in `_VGAStart` (0x70302488) except where
noted, using `driverServer.h`'s `_IOGetIntValues` /`_IOSetIntValues`
signatures:

1. `_LookupFrameBufferDevicePort("VGADisplay0", "frame buffer")`; on failure
   logs `VGA Driver: can't open framebuffer.` and returns -1.
2. `device_master_self()` is cached at `0x70304114`; `_IOLookupByDeviceName`
   fills the object number at `0x70304110`. Every later parameter call uses
   that pair.
3. `_IOGetIntValues(master, object, "IOGetDisplayInfo", 3, values, &count)`,
   then `_vga_width = values[0]`, `_vga_height = values[1]`,
   `_vga_rowbytes = values[2]`, `_vga_bpl = values[2] >> 1`. The `>> 1` is
   the whole reason the driver asks for `rowBytes`: at 640×480 the kernel
   answers 160, so one plane's bytes-per-line is 80.
4. `_IOSetIntValues(master, object, "IO_Framebuffer_SetDimensions", values, 3)`
   sends the same three integers straight back, which is what makes the
   kernel set `bitsPerPixel = IO_VGA`.
5. Maps `0xA0000`+`0x20000` with `_IOMapEISADeviceMemory` into `_vgaAddress`,
   the I/O ports with `_IOMapEISADevicePorts`, and allocates
   `_vga_height * _vga_rowbytes` bytes for `_vgaVirtualAddress`.
6. If `_vga_width != 640`, `_IOSetIntValues(..., "Set VGA VESA Mode", &zero, 1)`;
   otherwise `_VGASetStdRegs(5)`.
7. `_fill_64K_plane(0)`, `_set_colormap()`, then
   `_NXRegisterScreen(screen, 0, 0, _vga_width, _vga_height)`.
8. `IO_Framebuffer_Register` is sent separately, by the static at
   `0x70301FD8`, as
   `_IOGetIntValues(master, object, "IO_Framebuffer_Register", 1, &token, &count)`;
   on failure it logs `VGA Driver: can't register screen(%d)`.

So the ordering constraint the two rewrites must preserve is: the kernel's
`IOGetDisplayInfo` answer is what determines every geometry global on the
Window Server side, and `IO_Framebuffer_SetDimensions` is what pushes that
geometry back into `IODisplayInfo` before `IO_Framebuffer_Register` causes
`_registerWithED` to hand out the shared memory.

### 3. The cursor state machine

Both sides implement the same state machine over the same fields. The kernel
half is `-[IOVGADisplay hideCursor:]` (0xC9C),
`-[IOVGADisplay moveCursor:frame:token:]` (0xD00) and
`-[IOVGADisplay showCursor:frame:token:]` (0xF08), with `_VGADisplayCursor`
(0x6D8) and `_VGARemoveCursor` (0xA08) as the blitters. The Window Server
half is `_VGAHideCursor`, `_VGAShowCursor`, `_VGAObscureCursor`,
`_VGARevealCursor`, `_VGAShieldCursor`, `_VGAUnshieldCursor` and
`_VGASetCursor` as the locked entry points, `_VGASysHideCursor`,
`_VGASysShowCursor` and `_VGACheckShield` as the unlocked primitives, and the
two unnamed statics at `0x70302BEC` (draw) and `0x70302E48` (erase) as its
blitters.

**Lock ownership.** `cursorSema` at `+0x04` is the only serialization between
the halves, and each side uses exactly one discipline:

- The kernel imports `_ev_try_lock` and `_ev_unlock` and **never** `_ev_lock`.
  All three of its cursor methods open with
  `_ev_try_lock(&shmem->cursorSema)` and, if it fails, return `self`
  immediately having done nothing at all. The kernel never blocks on the
  Window Server and never queues the update.
- The bundle imports `_ev_lock` and `_ev_unlock` and **never**
  `_ev_try_lock`. All seven of its public cursor entry points take the
  blocking lock.
- `_VGASysHideCursor`, `_VGASysShowCursor` and `_VGACheckShield` touch the
  lock not at all; they are the inner primitives and every caller holds it.
  Their kernel counterparts are the same code inlined into the three
  methods.

The rewrite of either half must not change this: making the kernel block, or
making the Window Server side use `try`, changes the driver's behaviour under
contention.

**`cursorShow` at `+0x08` is a hide-depth counter, not a boolean.** Both
sides implement the identical pair:

```
hide:   if (shmem->cursorShow++ == 0)
            eraseCursor();

show:   if (shmem->cursorShow != 0 && --shmem->cursorShow == 0) {
            recomputeCursorRect();
            drawCursor();
            shmem->oldCursorRect = shmem->cursorRect;
        }
```

`_registerWithED` zeroes the whole region and then sets `cursorShow = 1`, so
the cursor starts hidden at depth 1 and the first `show` reveals it.

**Rect recomputation** is byte-for-byte the same expression on both sides,
and neither side stores the hot spot as two separate shorts — it is read as
one 4-byte `Point` and split with a `sar edx, 16`:

```
p = shmem->hotSpot[shmem->frame];
shmem->cursorRect.minx = shmem->cursorLoc.x - p.x;
shmem->cursorRect.maxx = shmem->cursorRect.minx + 16;
shmem->cursorRect.miny = shmem->cursorLoc.y - p.y;
shmem->cursorRect.maxy = shmem->cursorRect.miny + 16;
```

The `16` is `CURSORWIDTH`/`CURSORHEIGHT` from the header. `oldCursorRect` is
then copied from `cursorRect` as two 4-byte moves, `+0x20`→`+0x28` and
`+0x24`→`+0x2C`, and it is what the erase blitter uses to find the pixels to
restore.

**Shielding.** `shieldFlag` at `+0x0A` and `shielded` at `+0x0B` are one bit
of protocol each, and `shieldRect` at `+0x14` is written only by the Window
Server:

- `_VGAShieldCursor(screen, Bounds *r)`: lock; `shieldFlag = 1`;
  `shielded = 0`; `shieldRect = *r` (two 4-byte moves); `_VGACheckShield`;
  unlock.
- `_VGACheckShield(screen)`: caller-locked. Recomputes the cursor rect into
  registers — note it does **not** write `cursorRect` — and intersects it
  with `shieldRect` using four short compares. `hit = intersects`. If
  `hit != (signed char)shielded`, calls `_VGASysHideCursor` when `hit` is set
  and `_VGASysShowCursor` when it is clear, then stores `shielded = hit`.
- `_VGAUnshieldCursor(screen)`: lock; if `shielded` then `_VGASysShowCursor`;
  `shielded = 0`; `shieldFlag = 0`; unlock.
- The kernel carries the same intersection test inlined in both
  `showCursor:frame:token:` and `moveCursor:frame:token:`, gated on
  `shieldFlag != 0`, and updates `shielded` the same way. So the kernel
  reads `shieldFlag`/`shieldRect` and writes `shielded`; the Window Server
  writes all three.

One asymmetry worth carrying into the rewrite verbatim rather than
"correcting": `_VGAShieldCursor` clears `shielded` to 0 *before* calling
`_VGACheckShield`, so if the cursor was already shielded and the new shield
rect does not intersect it, `_VGACheckShield` sees `hit == shielded == 0` and
does nothing — the cursor stays hidden with `shielded` reading 0. It is
recovered by the next `_VGAUnshieldCursor` only through the `cursorShow`
depth counter, not through `shielded`. Reproduce it as written; if it is a
defect it is Apple's, and changing it changes observable behaviour.

*(This last sentence is corrected below, in the `## VGA_psdrvr` section's
"Correction to the Shared contract's `_VGAShieldCursor` note" — `_VGAUnshieldCursor`
never touches `cursorShow` at all, and nothing in the shield path recovers the
state described here.)*

**Obscuring.** `cursorObscured` at `+0x09`:

- `_VGAObscureCursor`: lock; if `!cursorObscured` then `_VGASysHideCursor`
  and `cursorObscured = 1`; unlock.
- `_VGARevealCursor`: lock; if `cursorObscured` then `cursorObscured = 0` and
  `_VGASysShowCursor`; unlock.
- The kernel un-obscures on its own inside `moveCursor:frame:token:`: after
  the hide step it does
  `if (cursorObscured) { cursorObscured = 0; if (cursorShow) cursorShow--; }`.
  Moving the pointer reveals an obscured cursor, and the kernel does that
  without asking the Window Server. Both sides therefore write this byte.

**Cursor bitmaps.** `_VGASetCursor(screen, bitmap, hotSpot, frame, flagp)`
is the only writer of `cursor.bw.image` and `cursor.bw.mask`. It converts the
incoming bitmap with `_BM12Convert8to2`, `_BM12Convert16to2` or
`_BM12Convert32to2`, chosen by a jump table on a 16-bit format field at
offset `0x0C` of the bitmap descriptor (value 1 skips the conversion and uses
the descriptor's own planes at `+0x20`/`+0x24`), takes the lock,
optionally hides the cursor (when `*flagp == 0`), writes
`hotSpot[frame]` as one 4-byte store, `bcopy`s 64 bytes into
`image[frame]` and 64 into `mask[frame]`, re-shows, and unlocks. The kernel
only ever reads those two arrays. `save[16]` at `+0x248`, by contrast, is
written by both sides' blitters, as noted in §1.

## Project divergences

These are the findings that are not per-function.

**`Display.modes` deleted.** Our project shipped one and listed it in the
top-level `Makefile`'s `GLOBAL_RESOURCES`. Apple's `VGA.config` contains no
`Display.modes` at all. Deleted in Task 4 and removed from
`GLOBAL_RESOURCES`. Accepted.

**`English.lproj/Info.rtf` retained.** Apple ships none. Left in place per
the spec's §4.2 carve-out and recorded here rather than deleted; it is inert
and harmless, but it is a file our `VGA.config` stages and Apple's does not.

**`English.lproj/Help/VGA.rtfd` is a stub.** `Default.table` names
`"Help File" = "VGA.rtfd"`, and Apple ships both
`English.lproj/Help/VGA.rtfd` and `English.lproj/Help/TableOfContents.rtf`
with real text. Task 6 authored `Help/VGA.rtfd/TXT.rtf` as a stub so that the
table key resolves. Reproducing Apple's Help prose is not reconstruction.
`TableOfContents.rtf` is still absent.

**`Default.table` and `SVGABIOS.table` differ from Apple's in one line
break.** After Task 6, and excluding `"Driver Version"` which Apple's build
emits, the only remaining difference in either file is that Apple's copy runs
two keys together on one line:

```
"Help File" = "VGA.rtfd";"Server Name" = "VGA";
```

where ours keeps them on separate lines. No key and no value differs.
Accepted, and Task 6 Step 9 confirmed it is the only remaining textual
difference in both tables.

**`Loaded Server,Server Version` holds `2` and ours now matches.** The spec's
§2.7 recorded this as an open question because the project then declared
`PROJECTVERSION = 1.0`. The restructured project declares
`PROJECTVERSION = 2.6` in `VGA.drvproj/VGA.lksproj/Makefile`, and the build
emitted a 1-byte `Server Version` section containing `2` — Apple's byte
exactly. The section is written by `kl_ld`, which is a guest binary with no
checked-in source, and `src/driverTools-1/KernelServerProjectType/kernelserver.make`
names no version variable, so the derivation (apparently the major component
of `PROJECTVERSION`) is inferred from the observed output rather than read
from a rule. Recorded as observed, not as proven.

**The `VGA` version bundle was not produced.** Apple's `VGA.config` contains
a third Mach-O, `VGA`, 16672 bytes, MH_BUNDLE, whose only content is
`_VGA_VERS_STRING` and `_VGA_VERS_NUM` in `__TEXT,__const`. §1.2 expected the
restructured Driver-project build to emit an equivalent without anyone
writing code. It did not: neither Task 5's baseline nor Task 6's rebuild
staged a `VGA` file, and `out/i386/drvVGA/VGA.config` contains only
`Default.table`, `DriverInfo`, `English.lproj`, `SVGABIOS.table`,
`VGA_psdrvr` and `VGA_reloc`. This is the build finding §1.2 anticipated, and
it is unresolved.

**Open build defect: our `VGA_psdrvr` links as MH_EXECUTE.** Apple's is
MH_BUNDLE (type 8); ours comes out Mach-O type 2, because the link command
`VGA_psdrvr.tproj` generates carries no `-bundle` flag. `read_macho` rejects
type 2, so `parity_check.py` cannot read our build of the psdrvr and no
string or symbol parity numbers exist for it. Separately, `bundle.make`
wraps the output in a `VGA_psdrvr.bundle/` directory even though
`VGA_psdrvr.tproj/Makefile` sets `BUNDLE_EXTENSION` empty, so the artifact
lands at `VGA.config/VGA_psdrvr.bundle/VGA_psdrvr` on the guest and has to be
lifted out when staging. Nothing in the remaining report-pass tasks is
blocked by either, but **Phase 3a's verification is**: neither §4.5's item 3
nor item 4 can run against `VGA_psdrvr` until the link produces a bundle.

**No `mapped` false positive was moved by hand** in either binary. See the
Function partition section above.

---

Per-function findings for `VGA_reloc` and `VGA_psdrvr` follow, appended by
the two later report-pass tasks.

## VGA_reloc

Reference `__TEXT,__text` is 18048 bytes at address 0. The source map
partitions it into 38 functions: the 36 IDA names and two standalone unnamed
fragments at 15640 and 15721. Everything below was read from the reference
disassembly; no counterpart exists in our source, so nothing here is a diff.

### Evidence and coverage for this section

**Two analyzers, not three.** angr is disabled for this profile (see Evidence,
above), so every claim below rests on IDA 9.2 and Ghidra 12.1 plus the Mach-O
symbol table, `__OBJC` metadata and relocation table read directly. Where that
reduction bears on a finding it is stated in the finding.

IDA and Ghidra agree exactly — same address, same size, same block count, same
instruction count — on **33 of the 38** entries. The five exceptions:

| Address | Symbol | Disagreement |
| --- | --- | --- |
| 468 | `_select_read_segment` | same size and instruction count; IDA 8 basic blocks, Ghidra 6 |
| 572 | `_select_write_segment` | same size and instruction count; IDA 7 basic blocks, Ghidra 6 |
| 6372 | `+[VGAKernelServerInstance kernelServerInstance]` | **Ghidra does not recover it at all**; IDA and the symbol table both do |
| 7552 | `_emu486` | IDA 8088 bytes / 1431 instructions; Ghidra 6931 / 1408 |
| 15640 | `sub_00003D18` | IDA 81 bytes / 37 instructions; Ghidra 17 bytes / 5, then treats the sixteen `setcc` stubs as separate bodies |

The two `_select_*_segment` splits are cosmetic — IDA splits the
`if (colr_mode)` diamond one edge finer. The other three are recorded per
function below.

**A dependency worth stating plainly.** Both blocks of C helpers
(`_SetET4000Brightness`, the four `_select_*`, the two converters, the two
cursor blitters) are `outb`-heavy, and `outb` in
`src/driverkit-3/driverkit/i386/ioPorts.h` is a `static __inline__` carrying
`static int xxx;` and the `outb %2,%1; lock; incl %0` asm. That header is
checked in unchanged and is the reason the reference's `lock inc ds:_xxx.100`
after every `out` is not something the rewrite has to reproduce by hand — it
falls out of calling `outb()`. Likewise `IOVGADisplayPrivate.h`'s
`vga_reg_out` / `vga_reg__in` macros reproduce the reference's
read-index / mask / write-index / access-data sequences exactly, register mask
for register mask. Both headers are load-bearing for Phase 3b.

### Where Apple's translation-unit boundaries fall

**Four translation units, and the binary names them outright.**
`__OBJC,__module_info` is 48 bytes: three 16-byte `objc_module` records
(`{version, size, char *name, struct objc_symtab *symtab}`), each carrying a
`name` pointer into `__OBJC,__class_names`. Read directly, the three names
are `IOVGADisplay.m`, `VGA_instance.m` and `vidBIOS.m`. `__OBJC,__symbols` is
56 bytes, which is exactly three 12-byte `objc_symtab` headers plus five
4-byte class/category `defs` pointers (`3*12 + 4*5 = 56`), and those five
defs split 1 class + 1 category for `IOVGADisplay.m`'s symtab, 2 classes for
`VGA_instance.m`'s, and 1 class for `vidBIOS.m`'s — exactly the four
`__OBJC,__class` records below, with none left over.

**`VGAVersion` and `VGAKernelServerInstance` are both defined by
`VGA_instance.m`, one translation unit, not two.** What earlier passes
counted as two separate build-generated stubs — `__text` 6372–6383 and
6384–6395 — is a single unit spanning 6372–6395.

So there are four translation units: `IOVGADisplay.m` (`__text` 0–6371),
`VGA_instance.m` (`__text` 6372–6395, build-generated), `vidBIOS.m` (`__text`
6396–7551), and the emulator's assembly (`__text` 7552 onward).

This is corroborated, not established, by the compiler's own private-name
numbering plus link order, which is consistent across `__text`, `__const`,
`__data` and `__bss` simultaneously. `_xxx.100`, `_xxx.103` and `_xxx.106` at
`__bss` 24764/24768/24772 are not three variables named `xxx` in three files:
they are the `static int xxx;` inside `outb()`, `outw()` and `outl()` in
`src/driverkit-3/driverkit/i386/ioPorts.h`, emitted once per translation unit
that includes that header. **There is exactly one such triple in the whole
binary**, and every `out` instruction in `__text` — from `_SetET4000Brightness`
at 228 to `_VGARemoveCursor` at 2658 — increments `_xxx.100`, the `outb` copy.
Only `outb` is ever called, which is why `.103` and `.106` are emitted but
carry no relocation pointing at them.

gcc's private-name counter (`var_labelno` in `varasm.c`) is a per-compilation
counter that never resets, so within one `.o` the suffixes rise monotonically
with source order and across `.o`s they restart. Every numbered static in this
binary forms one rising sequence, and its order agrees with the address order
of the functions that reference it:

| Static | Section | Referenced from | Suffix |
| --- | --- | --- | --- |
| `_xxx.100` (`outb`) | `__bss` 24764 | 228 … 2658 | 100 |
| `_xxx.103` (`outw`) | `__bss` 24768 | nothing | 103 |
| `_xxx.106` (`outl`) | `__bss` 24772 | nothing | 106 |
| `_vramBuf.125` | `__bss` 24776 | `_VGADisplayCursor` (1752) | 125 |
| `_mask_array.128` | `__data` 24604 | `_VGARemoveCursor` (2568) | 128 |
| `_vramBuf.129` | `__bss` 24784 | `_VGARemoveCursor` (2568) | 129 |
| `_ports.168` | `__const` 18920 | `-[IOVGADisplay(VESAMode) int10:]` (5944) | 168 |

100 → 168 with no restart, spanning text addresses 228 → 6006, corroborating
that **`-[IOVGADisplay _registerWithED]` at 0 through
`-[IOVGADisplay(VESAMode) didBootWithDefaultConfig]` at 6220 are one file.**
The unnumbered file-scope statics `_svga_bios_mode`, `_vesaMode`, `_bios`,
`_nextVGAUnit` and `_nameBuf`, and the exported globals `_colr_mode`,
`_curr_read_plane`, `_curr_write_plane`, `_curr_read_segment` and
`_curr_write_segment`, all sit in that same file's `__data`/`__bss` run
(24576–24672 and 24764–24820) and are referenced only from within it.

That the class and its `(VESAMode)` category share a file is independently
corroborated by `__OBJC`: `__cat_inst_meth` at 32768 precedes `__message_refs`
at 32812, i.e. the category's method list was emitted by the same compilation
that emitted the class's selector references.

**The strongest independent proof that `IOVGADisplay.m` is one file** is
neither of the above: the nine C helpers are interleaved between
Objective-C method bodies in `__text` — C from 228 to 3227, Objective-C from
3228 to 6111, `_find_parameter` at 6112, then the `(VESAMode)` category from
6220. A linker concatenating whole object-file contributions cannot produce
that interleaving across separate files; it only falls out of one
compilation emitting all of it in source order.

The remaining three boundaries follow from address order and from the
sections each unit contributes:

1. **`IOVGADisplay.m`** — `__text` 0 … 6371; `__const` `_ports.168`;
   `__data` `_svga_bios_mode` … `_mask_array.128` (24576–24672);
   `__bss` `_xxx.100` … `_nameBuf` (24764–24820). Implements
   `@implementation IOVGADisplay`, `@implementation IOVGADisplay(VESAMode)`,
   the nine C functions, and the five exported console globals. `_registerWithED`
   is first in source order and `allocateConsoleInfo` last, which is exactly
   the reverse of `__inst_meth`'s list order — gcc's ObjC front end builds
   method lists by prepending, so list order is reverse source order, and here
   it is also reverse address order. The C helpers sit between
   `_registerWithED` and `hideCursor:` in the file.
2. **`VGA_instance.m`** — `__text` 6372 … 6395; `__common` `_VGA_instance`;
   `__const` `_VGA_VERS_STRING` (18928) and `_VGA_VERS_NUM` (19088), both
   *after* `_ports.168` in `__const`, consistent with linking after unit 1.
   Build-generated (§2.9), from the `.lksproj`'s `NAME` and
   `DriverKitVersion`, and confirmed as one unit by `__module_info` and
   `__symbols` above. `_VGA_VERS_STRING` is
   `"@(#)PROGRAM:VGA  PROJECT:vga-18  DEVELOPER:root  BUILT:Sat Apr 4 04:34:41 PST 1998"`
   and `_VGA_VERS_NUM` is 14385.
3. **`vidBIOS.m`** — `__text` 6396 … 7551. Contributes no `__data`, no
   `__bss`, no `__const` and no statics of any kind, which is why it leaves no
   trace in the numbering; its position is fixed by address order alone.

The fourth unit, the assembly at `__text` 7552 … 18048 (`__data` 24672 …
24764, the emulator's 92-byte state block, immediately after unit 1's
`_mask_array.128` and last in the section), is not named by `__module_info`:
that section covers Objective-C compilation units only, so it cannot
arbitrate whether the assembly is a separate object file or an `asm()` blob
embedded inside `vidBIOS.m`. That it *is* hand-written assembly is solid —
see the `_emu486` subsection's seven independent observations. That it is a
*separate file*, conventionally named `emu486.s`, is a reasonable inference
from `vidBIOS.m`'s C body ending cleanly at 7551 with no interior asm
markers, not a fact any metadata section states outright.

**Therefore `VGA.lksproj`'s `sources` should name three hand-written files:**
`IOVGADisplay.m`, `vidBIOS.m` and the assembly file (`emu486.s`, by
inference). The `VGA_instance.m` unit is emitted by the Kernel Server project
type and must not be written by hand.

### The four classes in `__OBJC,__class`

160 bytes, four 40-byte `struct objc_class` records, read directly from the
section:

| Offset | Class | Superclass | `instance_size` | ivars | methods |
| --- | --- | --- | --- | --- | --- |
| 32952 | `IOVGADisplay` | `IODisplay` | 544 | 2 (`priv` at 508, `_IOVGADisplay_reserved[8]` at 512) | 13 instance |
| 32992 | `VGAVersion` | `IODevice` | 264 | none | none (one class method) |
| 33032 | `VGAKernelServerInstance` | `Object` | 4 | none | none (one class method) |
| 33072 | `vidBIOS` | `Object` | 16 | 3 (`biosStackVirtual` 4, `biosStackPhysical` 8, `lowMem` 12) | 6 instance |

`__meta_class` mirrors it at 33112, also 160 bytes, and carries the three class
methods (`+probe:` on `IOVGADisplay`, `+driverKitVersionForVGA` on
`VGAVersion`, `+kernelServerInstance` on `VGAKernelServerInstance`).
`IOVGADisplay(VESAMode)` is a category, recorded in the separate 20-byte
`__OBJC,__category` section pointing at `__cat_inst_meth`, and correctly does
**not** consume one of the four class records. `IOVGADisplay`'s 544-byte
`instance_size` and its two ivars match
`src/driverkit-3/driverkit/IOVGADisplay.h` as checked in: `IODisplay`'s
instance size is 508, then `void *priv` and `unsigned int _IOVGADisplay_reserved[8]`.
The header needs no change.

### What `vidBIOS` is for

`vidBIOS` is the real-mode BIOS-call class, and `_emu486` is its engine. Its
six methods are recovered from `__OBJC,__inst_meth` at 33496 (the symbol table
names none of them). With the `__meth_var_types` encodings decoded, the
interface is:

```objc
@interface vidBIOS : Object
{
    void         *biosStackVirtual;    /* +4  */
    unsigned int  biosStackPhysical;   /* +8  */
    unsigned int  lowMem;              /* +12 */
}
- init;
- free;
- (int)int10:(const emu486regs_t *)inregs      /* r^{?=IIIIIIIIIIIIIIII} */
     outregs:(emu486regs_t *)outregs           /*  ^{?=IIIIIIIIIIIIIIII} */
     iorange:(const IORange *)ranges           /* r^{?=II}               */
       ionum:(int)nranges;
- (int)int10:(const emu486regs_t *)inregs
     outregs:(emu486regs_t *)outregs
     iorange:(const IORange *)ranges
       ionum:(int)nranges
     smmport:(unsigned int)smmport;            /* I */
- (unsigned int)scratchSegment;
- (void *)realToVirtual:(unsigned int)segment :(unsigned int)offset;
@end
```

**The register block both `int10:` methods pass and receive** is an untagged
struct of sixteen `unsigned int` — encoding `{?=IIIIIIIIIIIIIIII}`, 64 bytes.
Its layout is fixed by two independent pieces of evidence that agree: the four
`IOLog` calls on the failure path of the five-argument method, and `_emu486`'s
own 8-bit register pointer table `off_4390` at 17296, which holds
`{&r[0].b0, &r[1].b0, &r[2].b0, &r[3].b0, &r[0].b1, &r[1].b1, &r[2].b1, &r[3].b1}` —
the x86 `al cl dl bl ah ch dh bh` encoding. The order is plain modrm register
numbering followed by `eip`, `eflags` and the six segment registers:

| Index | Byte offset | Field |
| --- | --- | --- |
| 0 | 0x00 | `eax` |
| 1 | 0x04 | `ecx` |
| 2 | 0x08 | `edx` |
| 3 | 0x0C | `ebx` |
| 4 | 0x10 | `esp` |
| 5 | 0x14 | `ebp` |
| 6 | 0x18 | `esi` |
| 7 | 0x1C | `edi` |
| 8 | 0x20 | `eip` |
| 9 | 0x24 | `eflags` |
| 10 | 0x28 | `es` |
| 11 | 0x2C | `cs` |
| 12 | 0x30 | `ss` |
| 13 | 0x34 | `ds` |
| 14 | 0x38 | `fs` |
| 15 | 0x3C | `gs` |

`iorange`/`ionum` is a plain `IORange` vector (`{unsigned start; unsigned size;}`,
`driverTypes.h:96`), turned into an 8192-byte permit bitmap, one bit per I/O
port. `smmport` is a single I/O port number that the emulator treats specially;
the four-argument wrapper passes 0x10000, one past the top of the 16-bit port
space, meaning "none". The `VGADisplay: vidBIOS failed` string in `__cstring`
is logged by `-[IOVGADisplay initFromDeviceDescription:]`, not by `vidBIOS`
itself, when `[[vidBIOS alloc] init]` comes back nil.

### `_emu486`

**`_emu486` is hand-written i386 assembly, not compiled C.** Seven independent
observations, any two of which would be suggestive and all seven of which
together are not:

1. **No frame pointer.** It opens `push ebx / push esi / push edi` and reads
   its arguments as `[esp+0Ch+arg_N]`. Every one of the other 37 functions in
   this binary opens `push ebp / mov ebp, esp`.
2. **Its 92 bytes of `__data` at 24672–24764 carry no symbol at all.** A C
   file-scope static would be emitted as `_name`, a function-scope static as
   `_name.N`; both are `N_SECT` locals and both survive in this binary (there
   are seven of them). A datum with *no* symbol was labelled with an
   `L`-prefixed assembler-local label, which NeXT's `as` does not emit to the
   symbol table. That is an assembly-source signature.
3. **It executes `daa`, `das`, `aaa` and `aas`.** gcc emits none of these
   ever. The emulator implements the guest's BCD instructions by loading the
   guest's flags into the host with `mov ah, [flags] / sahf` and then running
   the host's own BCD instruction. That is a hand-written technique.
4. **`pushf` / `popf`** to capture and restore host flags around the
   interpreter loop.
5. **Register-argument internal subroutines.** `sub_3893`, `sub_38A1`,
   `sub_38AE` and `sub_38BC` are `call`ed with their inputs already in `esi`
   and `edx` and return in `eax`/`edi`, and several of them `pop ecx` to
   discard their own return address and long-jump to the error exit. No C
   calling convention is involved.
6. **Table-driven computed jumps** — `jmp ds:jpt_1E45[edx*4]` on the raw
   opcode byte, `jmp ds:off_43B0[edx]` on a masked modrm `/reg` field,
   `jmp ds:off_4190[ecx]` on a rotated modrm.
7. **The 92-byte state block is all zeros, yet lives in `__DATA,__data`
   rather than `__bss`.** The bytes at `__data` 24672–24764 are entirely
   `0x00`. A zero-initialised C static of any scope — file, function, or
   block — is emitted into `__bss` (or `__common`); explicit zero bytes
   placed in the initialized-data section is a `.data` plus `.space N`
   assembler idiom, not something a C compiler emits.

**Entry contract**, read from `-[vidBIOS int10:outregs:iorange:ionum:smmport:]`
at 7157–7190 and from the prologue at 7552:

```c
int emu486(void         *lowMemBase,   /* [esp+0x10] -> state 0x6060 */
           const regs_t *inregs,       /* [esp+0x14] copied to 0x6070, 16 dwords */
           regs_t       *outregs,      /* [esp+0x18] written on exit             */
           const char   *pagePerm,     /* [esp+0x1C] -> 0x6064, 256 bytes        */
           const char   *ioPerm,       /* [esp+0x20] -> 0x6068, 8192 bytes       */
           unsigned int  smmport);     /* [esp+0x24] -> 0x606C                   */
```

`lowMemBase` is the caller's virtual mapping of guest physical 0. `pagePerm`
is one byte per 4 KB page of the low 1 MB: nonzero means the guest may touch
it. The caller enables page 0, pages 0xA0–0xFF, and the pages of the BIOS
stack. `ioPerm` is one bit per I/O port, set means permitted.

**State block, 92 bytes at `__data` 24672–24764**, all of it unnamed:

| Address | Role |
| --- | --- |
| 0x6060 (24672) | `lowMemBase` |
| 0x6064 (24676) | `pagePerm` |
| 0x6068 (24680) | `ioPerm` |
| 0x606C (24684) | `smmport` |
| 0x6070 (24688) | `regs[16]`, the 64-byte block above; `0x6090` is `eip`, `0x6094` `eflags`, `0x6098`…`0x60AC` `es cs ss ds fs gs` |
| 0x60B0 (24752) | unreferenced, 4 bytes |
| 0x60B4 (24756) | current-instruction descriptor. Byte 0 is the effective data segment expressed as a byte offset from `es` in the register block — 0x00 `es`, 0x04 `cs`, 0x08 `ss`, 0x0C `ds`, and 0x18 as a "no segment, address is already linear" sentinel. Byte 1 is set to the same value by every segment-override prefix but defaults to `ss` where byte 0 defaults to `ds`, so it is (inferred) the segment used for `bp`-relative addressing. Byte 3 is or-ed into the modrm dispatch index by `sub_38BC`. The whole-instruction reset at 7732 stores 0x0000080C |
| 0x60B8 (24760) | host `EFLAGS` saved at entry, masked with `0xFFFFF700` |

On entry the six segment registers are converted in place from real-mode
selectors to host linear addresses (`shl 4`, `add lowMemBase`); on exit the
conversion is undone (`sub lowMemBase`, `shr 4`) and the 64-byte block is
copied to `outregs`. `esi` holds the linear instruction pointer throughout and
`bl` holds the current operand size in bytes, 2 or 4 — so this is a 386-class
real-mode interpreter that honours the 0x66 prefix, which is what the "486"
in its name refers to.

**Termination and error codes.** The main loop compares the linear `esi`
against `lowMemBase` and finishes when they are equal — that is, when the guest
returns to `0000:0000`, which is why
`-[vidBIOS int10:outregs:iorange:ionum:smmport:]` writes two zero words at the
top of the BIOS stack before entering. Normal termination returns 0. Otherwise
the return value is a tagged word:

| Value | Meaning | Raised at |
| --- | --- | --- |
| `0x01000000` | unimplemented or invalid opcode | 7756 |
| `0x02000000 \| offset` | data access to a page `pagePerm` does not allow; `offset` is the guest physical address | `sub_38BC`, 14646 |
| `0x03000000 \| port` | I/O access to a port `ioPerm` does not allow | `sub_00003D69`, 15744 |
| `0x04000000` | effective address ≥ 0x10000, i.e. real-mode offset overflow | `sub_38BC`, 14665 |

The caller logs these as `%s: emu486 error %08x before %04x:%04x` with `cs:eip`
and then dumps all sixteen registers.

**Dispatch structure.** Byte 0 of the instruction indexes `jpt_1E45` at 15760,
a full 256-entry table of 146 distinct targets. Group opcodes re-dispatch on
the modrm `/reg` field through `off_43B0`/`off_43B4` and friends; effective
addresses are computed by a 64-entry `(mod,rm)` table `off_4190` at 16784 (and
its 32-bit twin `off_4290` at 17040); 8-bit register operands resolve through
`off_4390` at 17296. Condition codes go through `sub_00003D18`. Everything from
15760 to the end of `__text` at 18048 — **2288 bytes** — is table data claimed
by no function.

**Is it transcribable? Yes, and more cleanly than the spec's §6 feared** —
because it does not need decompiling. It is assembly, so Phase 3b transcribes
it as assembly, one `.s` file, which is an exact and mechanical operation
rather than a reconstruction. What the §6 risk correctly identified survives in
a narrower form: **no analyzer's interior boundaries can be trusted**, so the
transcription must be driven from a linear disassembly of 7552–18048 with the
jump tables decoded to recover the labels, not from any analyzer's function
list. IDA calls the primary chunk 8088 bytes and carves 67 unnamed fragments
totalling 1161 bytes out of 7912–15206 inside it; Ghidra calls the primary
chunk 6931 bytes and fragments along entirely different boundaries; angr
misdisassembled six bytes at 7760 and had to be switched off. Those 67
fragments are not functions and are excluded from the partition — they are the
per-opcode handlers, and of the 67 only 34 return to the shared dispatch point
at `0x1E20`, 11 to `0x38F8`, 6 to `0x3A46`, 4 to `0x1E28`, 2 to `0x2180`, one
each to `0x1E58`, `0x2008` and `0x201B`, and 7 end in `retn`. A transcription
that assumed one uniform handler shape would be wrong.

The two fragments the partition *does* keep, at 15640 and 15721, lie past
`_emu486`'s IDA extent and are described as findings 37 and 38.

---

### Per-function findings

Addresses are decimal, as in the source map. `shmem` throughout is the
`VGAShmem_t` settled in the Shared contract section above; the field offsets
used here are that section's.

**1. `-[IOVGADisplay _registerWithED]` — 0, 227 bytes.**

```c
- (IOReturn)_registerWithED
{
    Bounds bounds; unsigned int len;
    int token = [[EventDriver instance] registerScreen:self bounds:&bounds
                                                 shmem:&priv size:&len];
    VGAShmem_t *shmem = priv;
    if (token == -1) return IO_R_INVALID_ARG;                        /* 0xFFFFFD3E */
    if (len > 0x1448) {                                              /* 5192 */
        IOLog("%s: shmem_size > sizeof (VGAShmem_t)(%d<>%d)\n", [self name], len, 5192);
        [[EventDriver instance] unregisterScreen:token];
        return IO_R_INVALID_ARG;
    }
    memset(shmem, 0, len);
    shmem->cursorShow  = 1;
    shmem->screenBounds = bounds;                                    /* two 4-byte stores */
    [self setToken:token];
    return IO_R_SUCCESS;
}
```

`priv` is ivar offset 508 (`0x1FC`). The `0x1448` literal is the compiled
`sizeof(VGAShmem_t)` and matches the checked-in header exactly; the analysis is
in the Shared contract section and is not repeated. Our rewrite must produce
this method, hand out the shared region, and start the cursor hidden at
depth 1.

**2. `_SetET4000Brightness` — 228, 237 bytes.**

Writes the four-entry BW palette through the DAC index/data ports 0x3C8/0x3C9,
each entry scaled by `level/64` and written three times (R, G, B):

```c
static void SetET4000Brightness(int level)
{
    outb(0x3C8, WHITE_INDEX);       /* 3 */
    v = (level * 64 - level) >> 6;                  /* level * 63 / 64 */
    outb(0x3C9, v); outb(0x3C9, v); outb(0x3C9, v);
    outb(0x3C8, LIGHT_GRAY_INDEX);  /* 2 */
    t = level * 3;  v = t >> 2;                     /* level * 48 / 64 */
    outb(0x3C9, v); outb(0x3C9, v); outb(0x3C9, v);
    outb(0x3C8, DARK_GRAY_INDEX);   /* 1 */
    v = (t * 5) >> 5;                               /* level * 30 / 64 */
    outb(0x3C9, v); outb(0x3C9, v); outb(0x3C9, v);
    outb(0x3C8, BLACK_INDEX);       /* 0 */
    outb(0x3C9, 0); outb(0x3C9, 0); outb(0x3C9, 0);
}
```

The four multipliers are 63, 48, 30 and 0, which are exactly
`WHITE_PALETTE_VALUE`, `LIGHT_GRAY_PALETTE_VALUE`, `DARK_GRAY_PALETTE_VALUE`
and `BLACK_PALETTE_VALUE` from `IOVGADisplayPrivate.h`. gcc turned each
`level * K / 64` into shifts and `lea`s; the rewrite should write the constants
and let the compiler do that again. The DAC ports are written raw, not through
the `vga_reg_out` macros. `static`, no symbol export.

**3. `_select_read_segment` — 468, 103 bytes.**

```c
void select_read_segment(char seg)
{
    char tmp;
    if (colr_mode) vga_reg__in(COLR_CRT, 0x36, tmp);
    else           vga_reg__in(MONO_CRT, 0x36, tmp);
    if (tmp & 0x10) return;                       /* segment select locked out */
    tmp = inb(0x3CD);
    outb(0x3CD, (tmp & 0x0F) | (seg << 4));       /* ET4000 Segment Select, high nibble */
    curr_read_segment = seg;
}
```

The reference's instruction sequence is `in` on 0x3D4 or 0x3B4, `and 0xC0`,
`or 0x36`, `out` on the same port, `in` on 0x3D5 — which is
`vga_reg__in(reg, 0x36, tmp)` expanded with `reg_MSK = COLR_CRT_MSK = 0x3F` and
with `READ_MONO_CRT_DATA` and `READ_COLR_CRT_DATA` both being 0x3D5, exactly as
the checked-in header defines them. Global, exported for the console.

**4. `_select_write_segment` — 572, 102 bytes.**

Identical to finding 3 except that the Segment Select write is
`(tmp & 0xF0) | (seg & 0x0F)` — the low nibble — and it sets
`curr_write_segment`. Global.

**5. `_select_read_plane` — 676, 110 bytes.**

```c
void select_read_plane(char plane)
{
    char tmp;
    vga_reg__in (GDC, 0x04, tmp);                       /* Read Map Select, 0x3CE/0x3CF */
    vga_reg_out (GDC, 0x04, (tmp & 0xFC) | (plane & 3));
    curr_read_plane = plane;
}
```

The two macro expansions each re-read and re-write the GDC index register,
which is why the reference touches 0x3CE twice. `GDC_MSK` is 0x0F, giving the
`and 0xF0 / or 0x04` pair. Global.

**6. `_select_write_plane` — 788, 127 bytes.**

```c
void select_write_plane(char plane)
{
    char tmp;
    vga_reg__in (SEQ, 0x02, tmp);                              /* Map Mask, 0x3C4/0x3C5 */
    vga_reg_out (SEQ, 0x02, (tmp & 0xF0) | (1 << (plane & 3)));
    curr_write_plane = plane;
}
```

`SEQ_MSK` is 0x07, giving `and 0xF8 / or 0x02`. Note the argument is a plane
*number* converted to a one-hot mask, unlike `select_read_plane`, which takes a
number the hardware wants as a number. Global.

**7. `_vga_read_bpp4planar_to_bpp2packed32` — 916, 407 bytes.**

`void vga_read_bpp4planar_to_bpp2packed32(unsigned short *fb, unsigned int *dst)`.
Reads sixteen pixels' worth of planes 1 and 0 and interleaves them into one
32-bit 2-bits-per-pixel word:

```c
select_read_plane(1);  hi = (unsigned short)~*fb;
select_read_plane(0);  lo = (unsigned short)~*fb;
/* pixel k of the low byte  -> bits 2k, 2k+1
   pixel k of the high byte -> bits 16+2k, 16+2k+1 */
*dst = scatter_odd(hi) | scatter_even(lo);
```

The two scatters are fully unrolled: sixteen `and` / `shl`-or-`shr` / `or`
triples each, with shift counts 2,5,8,11,14,17,20,23 for source bits 15..8 and
−6,−3,0,3,6,9,12,15 for source bits 7..0 in the plane-1 pass, and one less in
each case in the plane-0 pass. Both planes are bitwise complemented — VGA's
1-is-set convention against the NeXT 2-bit gray ramp. Global; the Window
Server's `_read_bpp4planar_to_bpp2packed` is the same transform on the other
side of the shared contract. A rewrite may write the loop and accept a large
`intentional-mismatch`, or transcribe the unrolled form; the shift table above
is the whole content either way.

**8. `_vga_write_bpp2packed32_to_bpp4planar` — 1324, 428 bytes.**

`void vga_write_bpp2packed32_to_bpp4planar(unsigned int *src, unsigned short *fb)`.
The exact inverse of finding 7: masks the source with `0xAAAA`/`0x5555` in each
16-bit half, gathers each half into a byte, complements it, and stores the two
bytes as one 16-bit word — first with plane 1 selected, then with plane 0.
Also global, also fully unrolled. The shift counts are finding 7's minus one
throughout. **The frame-buffer pointer is the first argument of the reader and
the second of the writer** — `read(fb, &packed)` against `write(&packed, fb)` —
which the call sites in findings 9 and 10 depend on and which a rewrite must
not tidy into a consistent order.

**9. `_VGADisplayCursor` — 1752, 816 bytes.**

`void VGADisplayCursor(IODisplayInfo *di, VGAShmem_t *shmem)` — the kernel's
draw-cursor blitter, called from `moveCursor:frame:token:` and
`showCursor:frame:token:`.

Structure:

1. Saves `curr_read_segment` and `curr_read_plane` and reads back the SEQ Map
   Mask register (index 2) into a local.
2. Copies `cursorRect` and `screenBounds` to locals, clips `cursorRect` against
   `screenBounds` on both `y` edges, snaps `minx` down to a 16-pixel boundary
   (`(minx - screenBounds.minx) & ~0x0F`), and sets `maxx = minx + 32`.
3. Writes the clipped rectangle back as `shmem->saveRect` (`+0x0C`/`+0x10`).
4. Computes the shift pair `shift = (cursorRect.minx & 0x0F) * 2` and
   `32 - shift`, and the three cursor pointers
   `image = &shmem->cursor.bw.image[frame][0]` (`shmem + frame*64 + 0x48`),
   `mask = &shmem->cursor.bw.mask[frame][0]` (`+ 0x148`) and
   `save = &shmem->cursor.bw.save[0]` (`shmem + 0x248`), each advanced by the
   number of rows clipped off the top.
5. Frame-buffer addressing: `wordsPerRow = di->width >> 4`,
   `rowsPerBank = 0x10000 / wordsPerRow`, and for each row
   `bank = y / rowsPerBank`, `addr = 0xA0000 + 2*((y % rowsPerBank) * wordsPerRow)
   + 2*((minx - screenBounds.minx) >> 4)`. The bank is pushed through
   `select_write_segment` and `select_read_segment` on entry and again whenever
   the row crosses a bank boundary.
6. Per row, up to two 32-bit columns: read the frame buffer with
   `vga_read_bpp4planar_to_bpp2packed32`, store the untouched value into
   `save[]`, then `value = (value & ~(mask << shift)) | (image << shift)` for
   the left column and the `>> (32-shift)` form for the right, and write back
   with `vga_write_bpp2packed32_to_bpp4planar`.
7. Restores the SEQ Map Mask, and restores the segment and plane registers.

**A reference quirk to reproduce, not correct.** Step 1 saves
`curr_read_segment` and `curr_read_plane` into *two* locals each, and step 7
feeds one copy to `select_read_segment`/`select_read_plane` and the other to
`select_write_segment`/`select_write_plane`. `curr_write_segment` and
`curr_write_plane` are never read. So the blitter restores the write registers
from the *read* registers' saved values. Both blitters do this.

`_vramBuf.125` is a two-element `static unsigned int` scratch that the
converters write through; the second element is addressed as `_vramBuf.125+4`.

**10. `_VGARemoveCursor` — 2568, 660 bytes.**

`void VGARemoveCursor(IODisplayInfo *di, VGAShmem_t *shmem)` — the erase
blitter. Same save/restore discipline, same banked addressing (computed from
`saveRect` rather than `cursorRect`), and the same two-column-per-row loop, but
the write is `value = (value & ~m) | (save[i] & m)` where `m` is an edge mask:

```c
leading  = mask_array[shmem->oldCursorRect.minx - shmem->saveRect.minx];
trailing = ~mask_array[16 - (shmem->saveRect.maxx - shmem->oldCursorRect.maxx)];
```

`_mask_array.128` at `__data` 24604 is 17 `unsigned int`, 68 bytes:
`mask_array[i] = 0xFFFFFFFFu << (2*i)`, i.e. 0xFFFFFFFF, 0xFFFFFFFC,
0xFFFFFFF0, 0xFFFFFFC0, 0xFFFFFF00 … 0x00000000. It is two-bits-per-pixel
granular, which is why the index is a pixel count and the shift is `2*i`.
Whether each column is touched at all is gated on two flags computed once from
`saveRect` versus `oldCursorRect`. `_vramBuf.129` is this function's own
two-element scratch, distinct from finding 9's.

The 92 bytes of `__data` at 24672 that IDA attributes to `_mask_array.128` by
gap are **not** part of it — they are `_emu486`'s state block, and the array's
real length is 17 entries.

**11. `-[IOVGADisplay hideCursor:]` — 3228, 100 bytes.**

```c
- hideCursor:(int)token
{
    VGAShmem_t *shmem = priv;
    if (!ev_try_lock(&shmem->cursorSema)) return self;   /* returns self having done nothing */
    IODisplayInfo *di = [self displayInfo];
    if (shmem->cursorShow++ == 0)
        VGARemoveCursor(di, shmem);
    ev_unlock(&shmem->cursorSema);
    return self;
}
```

`token` is accepted and never read. The `try`-and-give-up discipline and the
hide-depth counter are settled in the Shared contract section.

**12. `-[IOVGADisplay moveCursor:frame:token:]` — 3328, 517 bytes.**

```c
- moveCursor:(Point *)p frame:(int)frame token:(int)token
{
    VGAShmem_t *shmem = priv;
    if (!ev_try_lock(&shmem->cursorSema)) return self;
    shmem->frame     = frame;
    shmem->cursorLoc = *p;
    if (shmem->cursorShow++ == 0)
        VGARemoveCursor([self displayInfo], shmem);
    if (shmem->cursorObscured) {                 /* moving reveals an obscured cursor */
        shmem->cursorObscured = 0;
        if (shmem->cursorShow) shmem->cursorShow--;
    }
    if (shmem->shieldFlag) {
        /* recompute the rect into registers only -- cursorRect is NOT written here */
        hit = intersects(rect, shmem->shieldRect);
        if (hit != (signed char)shmem->shielded) {
            shmem->shielded = hit;
            if (hit) {
                if (shmem->cursorShow++ == 0) VGARemoveCursor(di, shmem);
            } else {
                /* the show tail, emitted inline here as well as below */
            }
        }
    }
    if (shmem->cursorShow && --shmem->cursorShow == 0) {          /* the show tail */
        Point h = shmem->hotSpot[shmem->frame];
        shmem->cursorRect.minx = shmem->cursorLoc.x - h.x;
        shmem->cursorRect.maxx = shmem->cursorRect.minx + 16;
        shmem->cursorRect.miny = shmem->cursorLoc.y - h.y;
        shmem->cursorRect.maxy = shmem->cursorRect.miny + 16;
        VGADisplayCursor([self displayInfo], shmem);
        shmem->oldCursorRect = shmem->cursorRect;
    }
    ev_unlock(&shmem->cursorSema);
    return self;
}
```

The rect recomputation and the `hotSpot[frame]` read-as-one-`Point`-and-`sar 16`
idiom are settled in the Shared contract section. gcc emitted the show tail
twice — once inside the shield branch and once at the end — so the reference
has two copies of the `VGADisplayCursor` call plus the `oldCursorRect` copy;
that is code duplication from the optimiser, not two different behaviours.
`token` is again unread.

**13. `-[IOVGADisplay showCursor:frame:token:]` — 3848, 453 bytes.**

The same body as finding 12 minus the initial hide and the un-obscure step:
sets `frame` and `cursorLoc`, runs the shield test if `shieldFlag`, then the
show tail. `token` unread. Same duplicated show tail.

**14. `-[IOVGADisplay generateNameAndUnit:]` — 4304, 47 bytes.**

```c
- (const char *)generateNameAndUnit:(unsigned int *)unit
{
    *unit = nextVGAUnit++;
    sprintf(nameBuf, "VGADisplay%d", *unit);
    return nameBuf;
}
```

`_nextVGAUnit` and `_nameBuf` (20 bytes at 24800) are file statics. The name is
what `_VGAStart` in the psdrvr looks up as `"VGADisplay0"`.

**15. `-[IOVGADisplay map]` — 4352, 9 bytes.**

`return 0;`. A stub that exists so that the `IO_Framebuffer_Map` parameter has
something to call. See the Shared contract section: the frame buffer is not
mapped through this path.

**16. `-[IOVGADisplay unmap]` — 4364, 84 bytes.**

```c
- (void)unmap
{
    unsigned n = [[self deviceDescription] numPortRanges];
    for (unsigned i = 0; i < n; i++)
        [self releasePortRange:i];
}
```

The loop is unsigned (`jnb`/`jb`), so `n == 0` releases nothing.

**17. `+[IOVGADisplay probe:]` — 4448, 144 bytes.**

```c
+ (BOOL)probe:(IODeviceDescription *)dd
{
    unsigned unit;
    id self_ = [[self alloc] initFromDeviceDescription:dd];
    const char *name = [self_ generateNameAndUnit:&unit];
    [self_ setUnit:unit];
    [self_ setName:name];
    [self_ setDeviceKind:"frame buffer"];
    [self_ registerDevice];
    return YES;
}
```

**`probe:` returns YES unconditionally and never checks the result of
`initFromDeviceDescription:`.** If the allocation or init fails it sends four
more messages to nil and still reports success. Reproduce as written.

**18. `-[IOVGADisplay free]` — 4592, 41 bytes.**

`return [super free];`. Nothing else; the shared region and the `vidBIOS`
instance are not released.

**19. `-[IOVGADisplay initFromDeviceDescription:]` — 4636, 358 bytes.**

```c
- initFromDeviceDescription:(IODeviceDescription *)dd
{
    if (![super initFromDeviceDescription:dd]) return nil;
    const char *s = [[dd configTable] valueForStringKey:"SVGA Mode"];
    if (s && strncmp(s, "Yes", 4) == 0)
        svga_bios_mode = 1;
    else {
        svga_bios_mode = 0;
        if ([self didBootWithDefaultConfig] == YES)
            svga_bios_mode = 0;
    }
    if (svga_bios_mode == 1) {
        bios = [[vidBIOS alloc] init];
        if (bios == nil) {
            IOLog("VGADisplay: vidBIOS failed\n");
            svga_bios_mode = 0;
        }
    }
    if (svga_bios_mode == 0)
        IOLog("VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)\n");
    else {
        IOLog("VGADisplay: Mode Selected: 800 x 600 @ 60 Hz (BW:2)\n");
        s = [[dd configTable] valueForStringKey:"SVGA VESA BIOS Mode"];
        if (s) {
            vesaMode = strtol(s, 0, 16);
            IOLog("VGADisplay: VESA mode selected: 0x%x\n", vesaMode);
        }
    }
    return self;
}
```

The `strncmp` is 4 bytes, so the terminator is compared and `"Yesterday"` does
not match. Two findings sit inside this method:

- **`didBootWithDefaultConfig` is dead.** It is consulted only in the branch
  where `svga_bios_mode` has just been set to 0, and its only effect is to set
  it to 0 again. The boot-with-`config=Default` escape hatch therefore never
  suppresses SVGA mode in the shipped driver. The branch structure is
  unambiguous — the call is inside the `else`, and the store it guards is
  redundant. Phase 3b should reproduce the shape, because reproducing the
  intent would change behaviour.
- The three boot-log lines are the strings the gating boot test in §4.5 greps
  for.

**20. `-[IOVGADisplay setBrightness:token:]` — 4996, 64 bytes.**

```c
- setBrightness:(int)level token:(int)t
{
    if ((unsigned)level > 64)
        IOLog("%s: Invalid arg to setBrightness:%d\n", [self name], level);
    SetET4000Brightness(level);
    return self;
}
```

**The validity check logs but does not guard** — control falls into
`SetET4000Brightness` on both paths. The comparison is unsigned, so a negative
level is also out of range. `t` is unread.

**21. `-[IOVGADisplay getIntValues:forParameter:count:]` — 5060, 437 bytes.**

Four inline `cmpsb` string compares in this order —
`IO_Framebuffer_Map` (19 bytes), `IO_Framebuffer_Dimensions` (26),
`IOGetDisplayInfo` (17), `IO_Framebuffer_Register` (24) — each with the
terminator included, then `objc_msgSendSuper` for anything else. Behaviour per
parameter is tabulated in the Shared contract section and not repeated. Two
details that section states and this disassembly confirms literally: the
`IOGetDisplayInfo` triples are the immediates `{0x320, 0x258, 0xC8}` and
`{0x280, 0x1E0, 0xA0}`, hardcoded and not read from `displayInfo`; and
`IO_Framebuffer_Dimensions` copies `min(*count, 3)` of
`{width, height, rowBytes}` from `[self displayInfo]` at offsets 0, 4 and 0x0C.

**22. `-[IOVGADisplay setIntValues:forParameter:count:]` — 5500, 295 bytes.**

The same shape with four compares — `IO_Framebuffer_Unmap` (21),
`IO_Framebuffer_SetDimensions` (29), `IO_Framebuffer_Unregister` (26),
`Set VGA VESA Mode` (18) — then `objc_msgSendSuper`. Again tabulated in the
Shared contract section. Literal confirmations: `SetDimensions` writes
`displayInfo->bitsPerPixel = 5` (`IO_VGA`) at offset 0x18 and never inspects
`count`; `Set VGA VESA Mode` requires `count == 1`, then sends
`[self enterSVGAMode:vesaMode]` using the driver's own global and discarding
`values[0]`.

**23. `-[IOVGADisplay allocateConsoleInfo]` — 5796, 29 bytes.**

`return VGAAllocateConsole([self displayInfo]);` — a tail call to the
undefined-and-kernel-resolved `_VGAAllocateConsole`, which lives in
`src/kernel-7/bsd/dev/i386/VGAConsole.c`. The return type encoding is
`^{?=^?^?^?^?^?^?^?^v}`, a pointer to a seven-function-pointer-plus-`void *`
struct, i.e. `IOConsoleInfo *`. This is the reason the five `_curr_*`/`colr_mode`
globals and the six `_select_*`/converter/blitter functions are exported rather
than `static`: the kernel console links against them.

**24. `-[IOVGADisplay(VESAMode) enterSVGAMode:]` — 5828, 114 bytes.**

```c
- (void)enterSVGAMode:(unsigned int)mode
{
    emu486regs_t r;
    memset(&r, 0, 64);
    r.eax = 0x4F02;                 /* VESA BIOS: set SuperVGA video mode */
    r.ebx = mode;
    [self int10:&r];
    if ((unsigned short)r.eax != 0x004F) {
        IOLog("%s: BIOS mode change returned %04x\n", [self name], (unsigned short)r.eax);
        IOSleep(5000);
    }
}
```

The five-second sleep is on the failure path only, and is there so the operator
can read the message before the console is repainted.

**25. `-[IOVGADisplay(VESAMode) int10:]` — 5944, 166 bytes.**

```c
- (int)int10:(emu486regs_t *)regs
{
    id dd = [self deviceDescription];
    unsigned n = [dd numPortRanges];
    IORange ranges[n + 1];                       /* alloca, (n+1)*8 bytes */
    ranges[0] = ports;                           /* static const {0, 0x10000} */
    memcpy(&ranges[1], [dd portRangeList], n * 8);
    return [bios int10:regs outregs:regs iorange:ranges ionum:n + 1];
}
```

The same register block is passed as both `inregs` and `outregs`, which is why
`enterSVGAMode:` reads its result back out of the block it filled in.
`_ports.168` at `__const` 18920 is `{start = 0, size = 0x10000}` — every I/O
port permitted — so the device's own port ranges from the config table are
additive and, given range 0, redundant. That is the reference's choice; the
plumbing is there so a narrower `ports` would work.

**One compiler artifact to note.** The reference copies **nine** bytes out of
`_ports.168` — two `mov` dwords and one `mov` byte — where `IORange` is eight.
The ninth byte read lands on `_VGA_VERS_STRING[0]` and the ninth byte written
lands on `ranges[1].start`, which the `memcpy` on the next line immediately
overwrites, so it is behaviourally dead. A rewrite that writes
`ranges[0] = ports;` against the eight-byte `IORange` in `driverTypes.h` will
emit two moves rather than three; record that as `intentional-mismatch` at
Phase 3b rather than trying to reproduce it.

**26. `_find_parameter` — 6112, 106 bytes.**

```c
static char *find_parameter(const char *key, char *s)
{
    int len = strlen(key);
    while (*s) {
        if (strncmp(s, key, len) == 0) {
            s += len;
            while (*s == ' ' || *s == '\t') s++;
            return *s ? s : 0;
        }
        s++;
    }
    return 0;
}
```

`strlen` is the inline `repne scasb` form. The returned pointer is positioned
on the first non-blank character after the key, which for a boot string is the
`=`.

**27. `-[IOVGADisplay(VESAMode) didBootWithDefaultConfig]` — 6220, 149 bytes.**

```c
- (BOOL)didBootWithDefaultConfig
{
    KERNBOOTSTRUCT *kbs = KERNSTRUCT_ADDR;                     /* 0x11000 */
    if (kbs->magicCookie != KERNBOOTMAGIC) return NO;          /* *(int *)0x110A4 */
    char *p = find_parameter("config", kbs->bootString);       /* 0x11002 */
    if (!p) return NO;
    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    if (*p != '=') return NO;
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    if (strncmp(p, "Default", 7) != 0) return NO;
    p += 7;
    return (*p == 0 || *p == ' ' || *p == '\t' || *p == '\n') ? YES : NO;
}
```

The two literal addresses confirm `src/kernel-7/machdep/i386/kernBootStruct.h`
exactly: `KERNSTRUCT_ADDR` is 0x11000, `bootString` is at offset 2 and
`magicCookie` at offset 0xA4 — 164, i.e. `2 + 160` rounded up to a 4-byte
boundary. The blank test is compiled as `(unsigned char)(c - 9) <= 1` plus a
separate compare against 0x20, so the accepted set is tab, newline and space.
As finding 19 records, this method's answer never changes anything.

**28. `+[VGAKernelServerInstance kernelServerInstance]` — 6372, 12 bytes.**

`return &VGA_instance;` — returns the address of the 4-byte `__common`
symbol `_VGA_instance`: `__DATA,__common` is 4 bytes, address 24820–24824,
holding exactly this one symbol. 7948 is `32768 − 24820`, the gap to the
next section (`__OBJC,__cat_inst_meth`) — a gap-derived size, the same
failure mode this document warns about elsewhere (the spec's §1.1 psdrvr
sizes, above). The method's own type encoding, `^^{?}8@8:12`, corroborates a
4-byte pointee: `_VGA_instance` is itself a pointer, and `&_VGA_instance` is
a pointer to a pointer. Emitted by the Kernel Server project type from the
`.lksproj`'s `NAME`, together with the `Instance Var` section that names it.
`intentional-mismatch` in the ledger, not hand-written source.

**Coverage note.** This is the one entry Ghidra does not recover at all. IDA
recovers it and the Mach-O symbol table names it at 6372 with the next symbol
at 6384, so its extent is not in doubt; but with angr disabled this entry rests
on IDA plus the symbol table rather than on two analyzers.

**29. `+[VGAVersion driverKitVersionForVGA]` — 6384, 12 bytes.**

`return 500;` (`0x1F4`). Also emitted by the project type, from
`DriverKitVersion`. `intentional-mismatch`.

**30. `-[vidBIOS init]` — 6396, 267 bytes.**

```c
- init
{
    biosStackVirtual = IOMallocLow(page_size);
    if (!biosStackVirtual) {
        IOLog("%s: can't allocate low memory region\n", [self name]);
        goto fail;
    }
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), biosStackVirtual, &biosStackPhysical)) {
        IOLog("%s: failed to wire down low memory region\n", [self name]);
        biosStackPhysical = 0;
        goto fail;
    }
    if (biosStackPhysical & 0xFFF00000) {
        IOLog("%s: can't allocate memory region in the lower 1MB\n", [self name]);
        goto fail;
    }
    if (IOMapPhysicalIntoIOTask(0, 0x100000, &lowMem)) {
        IOLog("%s: can't map lower 1MB\n", [self name]);
        lowMem = 0;
        goto fail;
    }
    return [super init];
fail:
    return [self free];                      /* nil */
}
```

Every failure path funnels to `[self free]`, whose return value is `nil`, so a
failed `init` is what makes `initFromDeviceDescription:` log
`VGADisplay: vidBIOS failed`. The `0xFFF00000` test is the guarantee the
emulator relies on: the BIOS stack must be inside the first megabyte so that a
real-mode `ss:sp` can address it.

**31. `-[vidBIOS free]` — 6664, 107 bytes.**

```c
- free
{
    if (biosStackVirtual) { IOFreeLow(biosStackVirtual, page_size); biosStackVirtual = 0; }
    if (lowMem) { IOUnmapPhysicalFromIOTask(lowMem, 0x100000); lowMem = 0; }
    return [super free];
}
```

Idempotent, which is what lets `init` call it on any failure path.

**32. `-[vidBIOS int10:outregs:iorange:ionum:smmport:]` — 6772, 696 bytes.**

The five-argument BIOS call. In order:

1. Builds a 256-byte page-permission array on the stack: zero it, then enable
   page 0, pages 0xA0 through 0xFF, and every page from
   `biosStackPhysical >> 12` to `(biosStackPhysical + page_size) >> 12`. So the
   guest may touch the IVT/BDA page, the 384 KB of video RAM and BIOS ROM, and
   its own stack, and nothing else.
2. `IOMalloc(0x2000)` for the I/O permission bitmap. If `iorange` is `NULL` it
   is filled with 0xFF — every port permitted. Otherwise it is zeroed and one
   bit is set per port in each of the `ionum` ranges, skipping any port above
   0xFFFF.
3. Copies the 64-byte `inregs` block to a stack local.
4. Sets the local's `eip` from `*(unsigned short *)(lowMem + 0x40)` and its
   `cs` from `*(unsigned short *)(lowMem + 0x42)` — real-mode interrupt vector
   0x10, read straight out of the mapped IVT.
5. Sets `ss = biosStackPhysical >> 4` and `esp = page_size - 8`, and zeroes the
   two dwords at the top of that stack. Those zeroes are the fake far return
   address `0000:0000` that `_emu486` uses as its termination condition.
6. `err = emu486(lowMem, &local, outregs, pagePerm, ioPerm, smmport);`
7. On non-zero `err`, logs four lines: the error and `cs:eip`, then `eax ebx
   ecx edx`, then `esi edi ebp esp`, then `ds es fs gs ss`, all read from
   `outregs`.
8. `IOFree(ioPerm, 0x2000)` on both paths; returns `err`.

The four `IOLog` argument lists are what fix the register block layout, above.
Note that step 4 reads the *live* interrupt vector table of the machine the
kernel is running on, so this only works because `lowMem` maps physical 0.

**33. `-[vidBIOS int10:outregs:iorange:ionum:]` — 7468, 44 bytes.**

Forwards to finding 32 with `smmport = 0x10000`, one past the top of the port
space. A tail call with the arguments re-pushed; gcc did not turn it into a
jump because the selector differs.

**34. `-[vidBIOS scratchSegment]` — 7512, 16 bytes.**

`return biosStackPhysical >> 4;` — the BIOS stack page expressed as a real-mode
segment, for a caller that wants a scratch buffer the emulated BIOS can
address. Nothing in this binary calls it; it is part of the class's published
interface.

**35. `-[vidBIOS realToVirtual::]` — 7528, 22 bytes.**

`return (void *)(lowMem + (segment << 4) + offset);` — converts a real-mode
`seg:off` to a pointer the kernel can dereference. Also uncalled within this
binary.

**36. `_emu486` — 7552, 8088 bytes (IDA) inside a 10496-byte extent.**

Described in full in the `_emu486` subsection above: entry contract, state
block, segment conversion, termination condition, four error codes, dispatch
structure and the assembly-source evidence. For the ledger this is one entry at
7552 with IDA's 8088-byte size, which is what the source map records; the 67
unnamed interior fragments (1161 bytes, 7912–15206) are its per-opcode handlers
and are excluded from the partition by the containment rule, and the 2288 bytes
from 15760 to 18048 are its dispatch tables and are claimed by no function at
all.

**Coverage note.** This is the entry where the reduced analyzer set matters
most. Ghidra gives the primary chunk 6931 bytes against IDA's 8088 and
fragments the remainder along different boundaries; angr agreed with IDA on
7552/8088 but produced a phantom six-byte function at 7760 that
misdisassembled bytes both other tools read correctly, which is why it is
disabled. The size in the source map and the ledger is IDA's. No analyzer's
interior boundaries should be trusted, and Phase 3b must work from a linear
disassembly with the tables decoded.

**37. `sub_00003D18` — 15640, 81 bytes.**

The condition-code evaluator. A standalone function past `_emu486`'s IDA
extent, so the partition keeps it:

```
  and dl, 0Fh                      ; dl = the tttn field of the guest instruction
  push [regs.eflags] ; popf        ; load the guest's flags into the host
  jmp  jpt_3D22[edx*4]             ; -> one of sixteen 4-byte setcc stubs
```

`jpt_3D22` at 17984 is a perfectly regular table, `15657 + 4*i`, and the
sixteen stubs are `setcc al ; ret` in condition order:
`o no b nb z nz be nbe s ns p ?? l nl le nle`.

**A one-byte bug in the reference.** Entry 11, which must be `setnp`
(`0F 9B C0`), is `setno` (`0F 91 C0`) — the same encoding as entry 1. So guest
`JNP`/`JPO`, `SETNP`/`SETPO` and `LOOPNP` are evaluated as "not overflow".
Verified against the raw bytes at file offset 18165, not just IDA's rendering,
and corroborated by the table's own regularity: the stub at 15701 is exactly
where entry 11's slot points. A video BIOS is unlikely to branch on parity, so
the bug is probably why it survived. Phase 3b should transcribe it as written
and record the deviation here rather than silently fixing it; fixing it changes
behaviour on a code path Apple's binary never exercised.

**Coverage note.** IDA gives this 81 bytes and 37 instructions; Ghidra gives 17
bytes and 5, taking only the dispatch head and treating the sixteen stubs as
separate bodies. The source map and ledger use IDA's 81, which is the extent
that reaches the last `ret`.

**38. `sub_00003D69` — 15721, 37 bytes.**

The I/O permission check, also standalone past `_emu486`'s extent:

```c
/* dx = port */
if (ioPerm[(port >> 3) & ~3] & (1u << (port & 31))) return;   /* permitted */
pop the return address;
emu486_fail(0x03000000 | port);
```

Implemented as a dword load at `ioPerm + ((port >> 3) & ~3)` followed by
`bt ecx, edx`, which is why the mask is `~3` rather than the byte index. On
denial it discards its own return address and long-jumps to `_emu486`'s exit
path at `loc_1E58`, so the caller never resumes. Every `in`/`out` handler in
the emulator calls it first.

### Reason classes for the source map

All 38 entries are `unmapped`. Two reason classes:

- **build-generated** (2): findings 28 and 29, emitted by the Kernel Server
  project type from the `.lksproj`'s `NAME` and `DriverKitVersion`.
- **no counterpart in our source** (36): everything else. Our `VGA.lksproj`
  implements a class `VGA` subclassing `IOFrameBufferDisplay`; Apple's
  implements `IOVGADisplay`, `IOVGADisplay(VESAMode)` and `vidBIOS` over an
  assembly real-mode emulator. There is no name, string or structure in common.

---

## VGA_psdrvr

Reference `__TEXT,__text` is 7057 bytes at `0x70301F34` (1882201908). The source
map partitions it plus `__TEXT,__picsymbol_stub` into 53 functions: 19
hand-written symbols over 18 bodies, 2 dyld glue routines, 17 linker-generated
PIC stubs and 16 unnamed `static` bodies. Everything below was read from the
reference disassembly and from the Mach-O load commands, symbol table,
relocation table and section bytes read directly out of the file. No counterpart
exists in our source, so nothing here is a diff.

### Evidence and coverage for this section

**One analyzer, not two or three.** angr cannot produce an analysis document for
this bundle at all — CFG recovery aborts with `block at address 1882209993 is
outside function at address 1882210007` — and all 48 of Ghidra 12.1's relocation
records come back as `r_type == 0` — `GENERIC_RELOC_VANILLA`, the only
relocation kind an i386 image of this era emits — which gives
`normalize_analysis` nothing to derive a field width from, so it aborts on the
first one. Both are disabled in
`tools/binrecon/profiles/vga-psdrvr.json`. **Every function claim below rests on
IDA 9.2 alone.** That is a weaker evidentiary base than the `VGA_reloc` section
above, and it is stated here once rather than repeated per finding.

Three things compensate, and each is used explicitly where a claim would
otherwise rest on IDA alone:

1. **The Mach-O symbol table is linker-emitted ground truth.** It carries 52
   symbols: 3 local, 26 external defined, 23 undefined. Every external defined
   `__TEXT,__text` symbol appears in IDA's function list at the same address,
   and IDA's list contains no named text function the symbol table does not
   have. The only symbol-table `__text` entry IDA declines to call a function is
   `__mh_bundle_header`, which is the bundle header rather than code; the source
   map follows IDA and omits it, which is why the map has 53 entries and not 54.
2. **The section table arithmetic closes all but 8 bytes.** `__picsymbol_stub`
   is 442 bytes = 17 × 26; `__const` is 444 bytes, and all but 8 of them are
   claimed — 360 by the five register tables identified below, 8 by the
   cursor layer's `Bounds` and 68 by its 17-entry mask table, with 8 zero
   bytes between those last two attributed to no object; `__common` is 32
   bytes and the seven globals account for all 32; `__bss` is 131124 bytes and
   the two 65536-byte conversion tables plus 52 bytes of scalars account for
   all of it. Only those 8 `__const` bytes are left over anywhere.
3. **The kernel half is an independent second copy of the same code.** The two
   cursor blitters, the two planar/packed converters, the two plane selectors
   and the palette values exist on both sides of the driver, compiled from what
   is plainly shared source. Where a psdrvr claim has a `VGA_reloc` counterpart
   it is cross-checked against it below, and in every case the two agree. That
   is a stronger check than a second disassembler on the same bytes would be.

**A correction to the spec's `__TEXT` base.** §1.1 says the bundle prebinds
`__TEXT` at `0x70320000`. `LC_SEGMENT __TEXT` gives `vmaddr 0x70300000`,
`vmsize 0x4000`; the offsets in §1.1's psdrvr table are consistent with
`0x70300000` and only the prose is wrong.

**A correction to the published `__picsymbol_stub` size.** The analysis document
records 443 bytes. The load command says 442, which is exactly 17 × 26. The extra
byte is an artefact of how the section list was derived and is cosmetic; the
`442 = 17 × 26` identity in the Evidence section above is correct.

### Local symbols were stripped, and that changes one of the `_emu486` tests

The symbol table has exactly **three** local symbols — `dyld_stub_binding_helper`,
`__dyld_func_lookup` and `__mh_bundle_header` — and all three are emitted by the
linker itself. There is no `_name.N` private static, no `L`-prefixed label, no
file symbol and no local name for any of the 16 unnamed function bodies. By
contrast `VGA_reloc` retains seven numbered statics and every one of its `static`
C functions by name.

So **this bundle was linked with local symbols stripped** (`ld -x` or equivalent),
and two consequences follow that Phase 3a has to hold on to:

- The 16 `static` bodies are unnamed *because of the link*, not because they are
  anything unusual. The source map's `sub_<ADDRESS>` names are synthesized and
  correspond to nothing in Apple's source.
- **The second of the seven `_emu486` tests does not transfer.** In `VGA_reloc`,
  92 bytes of unsymbolised `__DATA,__data` was evidence of hand-written assembly
  because that binary keeps its local data symbols. Here *all* file-scope statics
  are unsymbolised, so the absence of a symbol on a `__data` or `__bss` object
  proves nothing at all. The unnamed `static int` at `__data` `0x70304088` and
  the two unnamed 65536-byte `__bss` tables at `0x70304138` and `0x70314138` are
  ordinary C statics whose names the link removed, not an assembler idiom.

The remaining `_emu486` tests do transfer, and they were applied to all 53
entries:

| Test | Result |
| --- | --- |
| Frame pointer | All 34 compiled bodies — the 18 named and all 16 unnamed — open `push ebp / mov ebp, esp` and close `mov esp, ebp / pop ebp / retn`. The 2 dyld glue routines and the 17 PIC stubs have no frame and no prologue at all. |
| Instruction selection | No `daa`, `das`, `aaa`, `aas`, `pushf`, `popf`, `sahf`, `lahf`, `into`, `bound`, `xlat`, string instruction other than the single `movsd` run gcc emits for a 36-byte struct copy, or segment-override prefix appears anywhere in `__text`. |
| Calling convention | Every internal call passes arguments on the stack and returns in `eax`; there is no register-argument subroutine and no `pop ecx`-to-discard-a-return-address anywhere. |
| Zero data in `__data` | Present (`0x70304088`), but as shown above it is not diagnostic in a binary whose local symbols are stripped. |

**Conclusion: all 16 unnamed `static` bodies are compiled C, and so are all 18
named ones. Nothing in this binary is hand-written assembly.** The only bytes
that are not compiled from a source file are the 2 dyld glue routines (20 + 14)
and the 17 PIC stubs (442), and those are the linker's and dyld's, which is why
all 19 are `intentional-mismatch` in the ledger.

The 51 bytes of `__text` not claimed by any of the 53 entries are inter-function
alignment padding: gcc's function alignment plus the `nop` runs it emits before
hot loop heads.

### Where Apple's translation-unit boundaries fall

**There is no `__OBJC` segment in this binary at all.** The load commands list
`__TEXT` (4 sections), `__DATA` (6 sections) and `__LINKEDIT`, and nothing else.
There is no `__module_info`, no `__symbols`, no `__class` and no
`__meth_var_types`. This is plain C, not Objective-C, so the section that named
`IOVGADisplay.m`, `VGA_instance.m` and `vidBIOS.m` outright in `VGA_reloc` has no
analogue here, and the private-name numbering argument is unavailable too because
the link stripped the numbered statics. **Everything in this subsection is
inference from section layout and linkage, and is marked as such.**

One deduction is solid and does not depend on layout. **A function body with no
external symbol had internal linkage.** The strip removed local symbols only;
every symbol with `N_EXT` survived, and the 26 external defined symbols are
exactly the 19 function names and the 7 globals. So each of the 16 unnamed
bodies was `static`, and therefore each is reachable only from within its own
translation unit. Chaining that:

- `sub_70302BEC` is called only by `_VGASysShowCursor` and `sub_70302E48` only by
  `_VGASysHideCursor`, so both cursor blitters are in the same unit as the two
  `Sys` primitives.
- `sub_703030F0` is called only by `_read_bpp4planar_to_bpp2packed`;
  `sub_70303144` by `_write_bpp2packed_to_bpp4planar` and
  `_vga_at_mode12_bpp2_to_bpp4`; `sub_70303844` by
  `_vga_at_mode12_bpp2_to_bpp4`. So those four statics and the three converters
  are one unit.
- The eleven driver-vector statics are never called by name; their addresses
  appear only in the unnamed `__data` object at `0x70304018`. That object has no
  symbol either, so it also had internal linkage, so the unit that wrote its
  initializer is the unit that defines all eleven — a cross-file initializer
  would have required them to be `extern`.
- `_VGAStart` takes the address of that same unnamed `__data` object with a
  PIC-relative `lea`, which likewise requires it to be in the same unit.

That leaves three candidate units — the device-vector layer, the cursor layer and
the VGA hardware layer — and one piece of layout evidence collapses them into
one. `__DATA,__data` is 152 bytes and holds, in address order: the linker's
mach-header cell, the five-entry bitmap-class table used by the device layer, the
21-entry driver vector table, three zero words, four address cells used by the
device layer and `_VGAStart`, **the hardware layer's `static int` guard at
`0x70304088`**, and three more address cells used by both layers. A static linker
concatenates whole `__data` contributions per object file; it cannot interleave
one file's guard variable between another file's tables. The guard is in the
middle, so the device layer and the hardware layer contributed to the same
`__data` block, i.e. they are one object file. The cursor layer's `__text` run
(`0x70302708`–`0x70303028`) lies *between* the device layer's
(`0x70301F58`–`0x70302704`) and the hardware layer's
(`0x7030302C`–`0x70303AC4`), and a linker cannot interleave another file's text
into the middle of one file's contribution either.

**Therefore `VGA_psdrvr` is one C translation unit**, `__text` `0x70301F58`
through `0x70303AC4`, and `VGA_psdrvr.tproj`'s `sources` should name exactly one
hand-written file. This is a deduction from section layout plus linkage, not
something any metadata section states, and it should be revisited if Phase 3a
finds the single file unwieldy — but splitting it would change the `__data`
layout and is therefore visible in the artifact.

Weak corroboration, offered as corroboration only: `__cstring`'s 15 entries fall
in the order their users appear in `__text` (the two strings `sub_70301FD8` at
`0x70301FD8` uses come first, then the thirteen `_VGAStart` at `0x70302488` uses,
in the order `_VGAStart` reaches them), and `__const`'s five tables fall in the
order their users appear in `__text` (the cursor layer's two, then the hardware
layer's three). Both are what a single compilation emitting in source order
produces; neither excludes separate files.

### The seven `__DATA,__common` globals

`__common` is 32 bytes at `0x70324138` and holds all seven, each `N_SECT | N_EXT`
— C tentative definitions at file scope with no initializer and no `static`, and
all seven are **exported**, so the Window Server can read them. Sizes are the
address deltas, and they sum to exactly 32.

| Address | Symbol | Size | Type | First written by |
| --- | --- | --- | --- | --- |
| `0x70324138` | `_vga_width` | 4 | `int` | `_VGAStart`, step 3 |
| `0x7032413C` | `_vga_height` | 4 | `int` | `_VGAStart`, step 3 |
| `0x70324140` | `_vga_rowbytes` | 4 | `int` | `_VGAStart`, step 3 |
| `0x70324144` | `_vga_bpl` | 4 | `int` | `_VGAStart`, step 3 |
| `0x70324148` | `_vgaBounds` | 8 | `Bounds` | `sub_70301F58` — **not** `_VGAStart` |
| `0x70324150` | `_vgaAddress` | 4 | `vm_address_t` | `_VGAStart`, step 5 (zeroed, then filled by the RPC) |
| `0x70324154` | `_vgaVirtualAddress` | 4 | `void *` | `_VGAStart`, step 5 |

Type evidence, from code rather than from the deltas:

- `_vga_width`, `_vga_height`, `_vga_rowbytes` and `_vga_bpl` are written with
  32-bit `mov [eax], ecx` and read with 32-bit loads everywhere except at the
  `_NXRegisterScreen` call, where `_VGAStart` narrows two of them with
  `movsx eax, word ptr [eax]`. A 4-byte store settles the width; the `movsx` is
  a conversion at the call, so `NXRegisterScreen`'s prototype takes `short`
  coordinates. All four are `int`.
- `_vgaBounds` is written by `sub_70301F58` as two 32-bit stores taken straight
  from the screen device's own bounds field, and read by
  `_vga_at_mode12_bpp2_to_bpp4` as four `short`s at `+0`, `+2`, `+4`, `+6` and
  compared against a caller's `Bounds`. It is a `Bounds`,
  `{minx, maxx, miny, maxy}`, matching `IOVGAShared.h` — and the field order is
  independently confirmed by the clip in `_vga_at_mode12_bpp2_to_bpp4`, which
  takes the maximum at `+0`/`+4` and the minimum at `+2`/`+6`.
- `_vgaAddress` is passed to `_IOMapEISADeviceMemory` as its `vm_offset_t *addr`
  argument, so it is a `vm_address_t`. `_get_addr_range` reads it and adds
  `0x10000`, i.e. it is the base of the 128 KB device mapping of physical
  `0xA0000`.
- `_vgaVirtualAddress` receives `_os_malloc`'s return value and is handed to the
  `bm12` imaging machine as the storage for a 2-bit-per-pixel shadow of the
  screen, so it is a `void *`.

**The one that is easy to get wrong is `_vgaBounds`.** It is written by the
vector-table static at `0x70301F58`, which the Window Server calls *after*
`_VGAStart` has already returned and registered the screen. Until then it is
zero, and `_vga_at_mode12_bpp2_to_bpp4` clips every rectangle against it, so any
flush that happens before the screen device is initialized clips to nothing.

The code never touches the seven directly. It loads their addresses out of 4-byte
cells and dereferences those, and the cells live in two places: seven in
`__DATA,__data` at `0x70304078`–`0x70304094` (skipping the guard at
`0x70304088`), and five more in `__DATA,__nl_symbol_ptr` at
`0x703040E8`–`0x70304100`. Five of the seven globals have a cell in both, and
`_vga_height` and `_vga_rowbytes` have one only in `__data`. A single function
(`_vga_at_mode12_bpp2_to_bpp4`) loads through cells of both kinds. Why the NeXT
toolchain emitted two indirection mechanisms for the same tentative definitions
is **not determined**; it is a `-dynamic` PIC artefact of the era and it does not
constrain the rewrite, which just writes `vga_width` and lets the compiler pick.

### `_VGAStart`: the Window Server's entry contract

`_Start` and `_VGAStart` are both `N_SECT | N_EXT` at `0x70302488` (1882203272),
size 637. IDA drops the duplicate name, which is why the analysis document shows
only `_VGAStart`; `tools/binrecon/restore_symbol_aliases.py` puts `_Start` back
and the committed source map carries both names on the one entry, as Task 8 Step
6 decided.

**What the alias is for.** The Window Server loads a `*_psdrvr` bundle and looks
up one fixed entry point. `_Start` is that fixed name — it is what the loader
resolves, and it is the same in every display bundle. `_VGAStart` is the
descriptive name the source gives the function. The binary cannot say which of
the two the C definition used and which is the alias: both are `N_EXT` with
`n_desc == 0` at the same value, and the external symbol list is sorted
alphabetically, so nothing in the file distinguishes them. Phase 3a must emit
both, and the two must be a single body — not a wrapper — because a wrapper
would add a call and change the size.

The full sequence, with every argument. `master` is the cached
`device_master_self()` at `__bss` `0x70304114` and `object` is the
`IOObjectNumber` at `__bss` `0x70304110`; both are file-scope statics the strip
unnamed. `values[3]` and `count` are stack locals, and `kind` is an 80-byte
`IOString` buffer — the frame is exactly `4 + 4 + 80 + 12 = 100` bytes, which is
the `sub esp, 64h`.

```c
int VGAStart(NXScreen *screen)                     /* also exported as Start */
{
    port_t          port;
    IOString        kind;
    unsigned int    values[3], count;
    IOReturn        r;

    port = LookupFrameBufferDevicePort("VGADisplay0", "frame buffer");
    if (port == 0) {
        os_fprintf(os_stderr, "VGA Driver: can't open framebuffer.\n");
        return -1;
    }

    master = device_master_self();
    r = _IOLookupByDeviceName(master, "VGADisplay0", &object, &kind);
    if (r) { os_fprintf(os_stderr, "VGA Driver: can't find VGA display (%d).\n", r);
             return -1; }

    r = _IOGetIntValues(master, object, "IOGetDisplayInfo", 3, values, &count);
    if (r) { os_fprintf(os_stderr, "VGA Driver: can't set display info (%d).\n", r);
             return -1; }
    vga_width    = values[0];
    vga_height   = values[1];
    vga_rowbytes = values[2];
    vga_bpl      = values[2] >> 1;

    r = _IOSetIntValues(master, object, "IO_Framebuffer_SetDimensions", values, 3);
    if (r) { os_fprintf(os_stderr, "VGA Driver: can't set display info (%d).\n", r);
             return -1; }

    vgaAddress = 0;
    r = _IOMapEISADeviceMemory(port, task_self(), 0xA0000, 0x20000,
                               &vgaAddress, YES, IO_WriteThrough);
    if (r) { os_fprintf(os_stderr, "VGA Driver: can't map display memory (%d).\n", r);
             return -1; }

    r = _IOMapEISADevicePorts(port, thread_self());
    if (r) { os_fprintf(os_stderr, "VGA Driver: can't map display ports (%d).\n", r);
             return -1; }

    vgaVirtualAddress = os_malloc(vga_height * vga_rowbytes);
    if (vgaVirtualAddress == 0) {
        os_fprintf(os_stderr, "VGA Driver: can't allocate virtual display (%d).\n", r);
        return -1;                                  /* r is 0 here — see below */
    }

    if (values[0] != 640) {
        values[0] = 0;
        r = _IOSetIntValues(master, object, "Set VGA VESA Mode", values, 1);
        if (r) { os_fprintf(os_stderr, "VGA Driver:  can't talk to VGA (%d).\n", r);
                 return -1; }
    } else {
        VGASetStdRegs(5);                           /* 640x480x16, mode 0x12 */
    }

    fill_64K_plane(0);
    set_colormap();
    screen->name = "VGA";                           /* +0x08 */
    screen->ops  = &vgaDriverVector;                /* +0x0C, the table at 0x70304018 */
    NXRegisterScreen(screen, 0, 0, (short)vga_width, (short)vga_height);
    return 0;
}
```

Everything in that listing is checkable against the reference. The
`driverServer.h` prototypes as checked in match argument for argument:
`_IOGetIntValues` takes six arguments with `maxCount` fourth and
`unsigned int *returnedCount` sixth, `_IOSetIntValues` takes five with `count`
last, `_IOLookupByDeviceName` takes four with `IOString *deviceKind` last, and
`_IOMapEISADeviceMemory` takes seven ending `BOOL anywhere, IOCache cache` — the
reference passes `1, 1`, and `IO_WriteThrough` is 1 in `driverTypes.h`'s
`IOCache` enum. `IOString` is `char[IO_STRING_LENGTH]`, and the 80-byte hole in
the frame is exactly that buffer.

Three things about it are worth carrying into the rewrite verbatim.

**`task_self()` is a load, not a call.** The reference reads the argument as
`mov eax, [esi + disp] / mov eax, [eax] / push eax` — a PIC-relative load of
`__nl_symbol_ptr`'s cell for the data symbol `_task_self_`, dereferenced once,
with no `call` anywhere near it. That is exactly what the Mach macro
`task_self()` expands to, so the listing's `task_self()` is correct — but a
rewrite that instead emitted an actual call to a `task_self()` function would
produce different bytes with nothing in this document to flag the mismatch
except this note.

**A defect in the `os_malloc` failure path.** Every other failure prints the
`IOReturn` it just received. The `os_malloc` one prints `ebx`, which at that
point still holds the *successful* return of `_IOMapEISADevicePorts`, i.e. zero.
`VGA Driver: can't allocate virtual display (0).` is the only message this driver
can ever produce for that case. It is Apple's bug, it is observable, and Phase 3a
should reproduce it — the C that produces it is passing the stale `r`, as above.

**The `640` test reads `values[0]`, not `vga_width`.** They are equal at that
point, so the behaviour is the same, but the compiled code compares the stack
slot (`cmp [ebp+var_C], 280h`) rather than reloading the global. Writing
`vga_width != 640` would produce a different instruction and a different size.

The error tail is shared: all seven failure paths converge on a single
`os_fprintf(os_stderr, fmt, r)` and `return -1`, which is why the format strings
are the only thing that differs between them.

### The driver vector table at `0x70304018`

`_VGAStart` stores `&0x70304018` into its screen argument's `+0x0C`. The object
there is 21 pointer slots, 84 bytes, and it is what the Window Server calls the
driver through. Slots `+0x08`, `+0x20` and `+0x4C` are null in the file and carry
no relocation, so the driver genuinely implements 18 of 21 operations.

| Slot | Target | Size | Role |
| --- | --- | --- | --- |
| `+0x00` | `sub_70302040` | 521 | composite, then flush the dirty rect |
| `+0x04` | `sub_7030224C` | 36 | release the offscreen bitmap |
| `+0x08` | null | — | not implemented |
| `+0x0C` | `sub_70301F58` | 127 | initialize the screen device; writes `_vgaBounds` |
| `+0x10` | `sub_70302270` | 57 | fill a rect, then flush it |
| `+0x14` | `sub_703022AC` | 45 | set the offscreen bitmap's origin |
| `+0x18` | `sub_703022DC` | 29 | one-argument op on the offscreen bitmap |
| `+0x1C` | `sub_703022FC` | 111 | create an offscreen bitmap at a given depth |
| `+0x20` | null | — | not implemented |
| `+0x24` | `sub_7030236C` | 223 | convert the offscreen bitmap to another depth |
| `+0x28` | `sub_70301FD8` | 96 | send `IO_Framebuffer_Register` |
| `+0x2C` | `sub_7030244C` | 58 | read back five bitmap parameters |
| `+0x30` | `_VGASetCursor` | 554 | |
| `+0x34` | `_VGAHideCursor` | 44 | |
| `+0x38` | `_VGAShowCursor` | 44 | |
| `+0x3C` | `_VGAObscureCursor` | 66 | |
| `+0x40` | `_VGARevealCursor` | 63 | |
| `+0x44` | `_VGAShieldCursor` | 78 | |
| `+0x48` | `_VGAUnshieldCursor` | 73 | |
| `+0x4C` | null | — | not implemented |
| `+0x50` | `sub_70302038` | 7 | empty stub, `{ }` |

Slot `+0x28` is the only reason `IO_Framebuffer_Register` is sent at all, and it
is sent *after* `_VGAStart` returns, which is the ordering the Shared contract
section records.

**The screen-device record the vector entries receive.** Its layout is the Window
Server's, not this driver's, and no header for it exists in this tree. What the
reference touches, read from the disassembly:

| Offset | Width | Use |
| --- | --- | --- |
| `+0x01` | byte | bit 0 written by `sub_703022FC` and `sub_7030236C`: "offscreen depth differs from the screen's" |
| `+0x0C` | 4 | the screen's own bitmap; written by `sub_70301F58` |
| `+0x10` | 8 | screen `Bounds`, `{minx, maxx, miny, maxy}`; read by everything |
| `+0x18` | 4 | cached `screen->bitmap->[0x0C]` |
| `+0x1C` | 4 | the offscreen bitmap, created and released by slots `+0x1C`/`+0x04` |
| `+0x20` | 4 | written 0 by `sub_70301F58` |
| `+0x24` | 4 | written 1 by `sub_70301F58` — the depth index |
| `+0x28` | 4 | `VGAShmem_t *`; filled by the Window Server, read by every cursor entry |
| `+0x2C` | 4 | shared-memory size the driver requests; see below |

**`_VGAStart`'s argument and the vector entries' argument are not the same
layout.** `_VGAStart` writes `+0x08` and `+0x0C` with the name and the vector
table; `sub_70301F58` writes `+0x0C` with a bitmap. Either the Window Server
copies the descriptor `_VGAStart` filled into a separate screen-device record
before it starts calling the vector, or it caches the vector pointer and then
lets slot `+0x0C` overwrite it. The binary does not say which. **Inference, not
fact**, and it matters to Phase 3a only in that the two argument types must be
declared separately.

### The four `__bm*` symbols are not cursor blitters

`__bm12`, `__bm18`, `__bm34` and `__bm38` are **undefined external data symbols**
(`N_UNDF | N_EXT`, `n_desc == 0`, no `__imp_` alias, no PIC stub). They are
imported from the Window Server, not defined here and not called through the stub
table; they are the four imaging-machine class objects the Window Server exports,
one per pixel format. The spec's and the task brief's description of them as "the
four cursor blitters" is wrong, and this is recorded as a correction. The cursor
blitters are `sub_70302BEC` and `sub_70302E48`.

**How one is selected.** `__DATA,__data` `0x70304004`–`0x70304014` is a
five-entry table whose relocations resolve to
`{_bm12, _bm12, _bm18, _bm34, _bm38}` at load. `sub_703022FC` clamps its depth
argument to `0 <= d <= 4` (`d < 0` becomes 0, `d > 4` becomes 4) and indexes the
table with it; `sub_7030236C` indexes the same table with its own argument,
unclamped. Index 0 and index 1 both give `_bm12`, so a request for the lowest two
depths gets the 2-bit machine.

The correspondence to `IOVGAShared.h`'s cursor union is by pixel format, and the
header's member order is the same as the table's:

| Table index | Class | `VGAShmem_t` union member | Arm |
| --- | --- | --- | --- |
| 0, 1 | `_bm12` | `cursor.bw` | `struct bm12Cursor`, 2 bits/pixel |
| 2 | `_bm18` | `cursor.bw8` | `struct bm18Cursor`, 8-bit gray |
| 3 | `_bm34` | `cursor.rgb` | `struct bm34Cursor`, 16-bit RGB |
| 4 | `_bm38` | `cursor.rgb24` | `struct bm38Cursor`, 32-bit RGB |

Only `_bm12` is ever dereferenced for the screen itself or for the cursor:
`sub_70301F58` and `_VGASetCursor` both load it through the single
`__nl_symbol_ptr` cell at `0x703040F8` rather than through the table, and no code
path can reach the other three for the screen bitmap. `_bm18`, `_bm34` and
`_bm38` exist only so that the Window Server can ask this driver for an
*offscreen* bitmap at another depth through vector slots `+0x1C` and `+0x24`.
That is why the Shared contract's finding — that both halves use the `bw` arm and
nothing else — holds even though four classes are imported.

### The shared-memory size this side asks for, and a `save[]` finding

`sub_70301F58` sets the screen device's `+0x2C` to `0x48`, creates the screen
bitmap, then adds `0x240` to it. `0x48` is `offsetof(VGAShmem_t, cursor)` and
`0x240` is `sizeof(struct bm12Cursor)` — 256 + 256 + 64 — from `IOVGAShared.h` as
checked in. So the Window Server side declares it needs **648 bytes** of shared
memory, not 5192.

That is consistent with, and independently confirms, the Shared contract's
reading of the kernel's `ja` test: `-[IOVGADisplay _registerWithED]` rejects a
region *larger* than `sizeof(VGAShmem_t)` and accepts anything smaller, precisely
so that a 2-bit driver need not be handed the 5120-byte 24-bit cursor arm.
648 < 5192.

**The draw blitter writes past `cursor.bw.save`; the erase blitter only reads
past it.** `save` is `unsigned int save[16]`, 64 bytes at `+0x248`. Both
`sub_70302BEC` (draw) and `sub_70302E48` (erase) advance the save pointer by 4
bytes once for the left 16-pixel column and once for the right one, on every
scan line, for up to 16 lines — 32 words, 128 bytes — but only the draw
blitter stores into it: it reads the framebuffer and does `mov [edx], edi`
through the save pointer before advancing it. The erase blitter only consumes
what is there — `and ecx, [ebx]` / `and edx, [ebx]` then `add ebx, 4` — and
writes the framebuffer, never `save` itself. Over-read and over-write are
different defect classes. The kernel half splits the same way:
`_VGADisplayCursor` (draw) at `VGA_reloc` 1752 takes `lea eax, [ebx+248h]` and
then `add ecx, 4` in both branches, including the `shift == 0` branch that
advances without writing, and stores through it; `_VGARemoveCursor` (erase)
advances the matching pointer and only reads through it. So the write/read
split is not an asymmetry between the halves — draw writes, erase reads, on
both sides — and both were compiled from the same arithmetic.

Either `struct bm12Cursor.save` was `[32]` in the header Apple compiled against
and the checked-in `[16]` is a different revision, or Apple overruns it by 64
bytes. The binary argues for the second: `sub_70301F58`'s `0x240` is
`sizeof(struct bm12Cursor)` with `save[16]`; with `save[32]` it would be `0x280`.
Widening `save` would not change `sizeof(VGAShmem_t)` — that is pinned at 5192 by
the `bm38` arm and by the kernel's compiled-in constant — but it would change the
648, and that number is in the artifact. A further corroboration: with
`save[32]`, `sizeof(struct bm12Cursor)` would be `0x280` and the request would be
`0x2C8`, which is exactly the 128 bytes the blitters actually touch past
`+0x248` — a `save[32]` header would size the request to cover the real
footprint precisely. That coincidence does not undercut the rejection above; it
strengthens it. `sub_70301F58` observably asks for `0x240`/`0x288`, not
`0x280`/`0x2C8`, so Apple's binary was compiled against `save[16]` and simply
overruns it, rather than against a wider array this project's header failed to
capture. **Reproduce the arithmetic as written and leave `IOVGAShared.h`
alone**; §1.4 puts the header out of scope, and changing it would not change
either binary.

**What the 64-byte overrun actually hits.** The Window Server's own request is
exactly `0x288` (648) bytes — `sub_70301F58`'s `0x48 + 0x240` — and `save[16]`
ends at exactly that offset, `0x248 + 0x40 = 0x288`. The blitters' 128-byte
touch runs from `0x248` to `0x2C8`, so the excess 64 bytes, `0x288`–`0x2C8`,
land past the end of the shared-memory region the driver itself asked for and
past what `-[IOVGADisplay _registerWithED]` memsets to zero on registration. It
does **not** land in the union's unused `bm18`/`bm34`/`bm38` padding: that
padding only exists in a `VGAShmem_t` allocated at its full 5192-byte size, and
this driver's registered block is 648 bytes, not 5192. Whatever the event
driver placed in memory immediately after this screen's 648-byte block is what
actually gets touched — a fact the rewrite has to carry forward rather than
paper over by assuming the union's other arms absorb it.

This is recorded as an addition to the Shared contract's §1, which says that
`saveRect` and `cursor.bw.save[16]` are a shared scratch pair but does not say how
much of `save` the blitters actually touch.

### Correction to the Shared contract's `_VGAShieldCursor` note

The Shared contract's §3 records the `_VGAShieldCursor` asymmetry and it is
**confirmed against the disassembly**: `_VGAShieldCursor` at `0x70302B50` sets
`shieldFlag = 1`, then `shielded = 0`, then copies `shieldRect`, then calls
`_VGACheckShield`. If the cursor was already shielded (and therefore already
hidden, `cursorShow == 1`) and the new shield rect does not intersect it,
`_VGACheckShield` computes `hit == 0`, finds `hit == shielded`, and does nothing.

The Shared contract then says the state "is recovered by the next
`_VGAUnshieldCursor` only through the `cursorShow` depth counter". **That is wrong
and is corrected here.** `_VGAUnshieldCursor` at `0x70302BA0` is

```c
ev_lock(&shmem->cursorSema);
if (shmem->shielded) VGASysShowCursor(screen);
shmem->shielded   = 0;
shmem->shieldFlag = 0;
ev_unlock(&shmem->cursorSema);
```

It never touches `cursorShow` itself; the only thing that would decrement it is
the `_VGASysShowCursor` call it skips. So after the losing sequence the cursor is
left hidden at depth 1 with `shielded == 0` and `shieldFlag == 0`, and **nothing
in the shield path ever recovers it** — it takes an unrelated `_VGAShowCursor` or
`_VGARevealCursor`, or another shield that does intersect followed by an
unshield. Reproduce it as written; it is Apple's, it is observable, and changing
it changes behaviour.

### Lock ownership, settled

Confirmed from both symbol tables. `VGA_psdrvr` imports `_ev_lock` and
`_ev_unlock` and has no undefined symbol named `_ev_try_lock`; `VGA_reloc`
imports `_ev_try_lock` and `_ev_unlock` and has none named `_ev_lock`. So:

- **The Window Server owns `cursorSema` in the blocking sense.** All seven public
  cursor entry points — `_VGASetCursor`, `_VGAHideCursor`, `_VGAShowCursor`,
  `_VGAObscureCursor`, `_VGARevealCursor`, `_VGAShieldCursor`,
  `_VGAUnshieldCursor` — open with `ev_lock(&shmem->cursorSema)` and close with
  `ev_unlock`. Each of the seven recomputes `shmem` from `screen->[0x28]` for the
  unlock rather than caching it, which is a compiler artefact, not semantics.
  Under contention the Window Server **waits**.
- **The kernel never waits.** Its three cursor methods take `ev_try_lock` and
  return immediately having done nothing if it fails, dropping the update.
- `_VGASysHideCursor`, `_VGASysShowCursor`, `_VGACheckShield` and the two blitters
  touch the lock not at all. They are the inner primitives; every caller holds it.
  `_VGACheckShield` is exported even though nothing outside the bundle should call
  it — it is exported because everything in this file is.

The consequence for the rewrite is that the two halves are **not**
interchangeable. Making the bundle use `try` would silently drop Window Server
cursor updates; making the kernel block would let a stalled Window Server hang the
event thread.

---

### Per-function findings

Addresses are decimal, as in the source map, with the hex form in the heading.
`shmem` throughout is the `VGAShmem_t` settled in the Shared contract section
above and the field offsets are that section's. `dev` is the screen-device record
tabulated under "The driver vector table" above.

**1. `dyld_stub_binding_helper` — 1882201908 (`0x70301F34`), 20 bytes.**

```
call $+5 ; pop eax
push dword [eax + (0x70304000 - 0x70301F39)]      ; &__mh_bundle_header
mov  eax,  dword [eax + (0x70304098 - 0x70301F39)]; __dyld[0]
jmp  eax
```

Linker-generated. `__DATA,__data + 0` holds `&__mh_bundle_header` and is the
module cookie dyld wants; `__DATA,__dyld` is eight zero bytes in the file that
dyld fills in at load. No frame pointer. `intentional-mismatch`.

**2. `__dyld_func_lookup` — 1882201928 (`0x70301F48`), 14 bytes.**

```
call $+5 ; pop eax ; mov eax, [eax + 0x2163] ; jmp eax
```

Linker-generated, no frame pointer, `intentional-mismatch`. Worth one note for
whoever reads the bytes later: `eax` is `0x70301F4D` and the displacement resolves
to `0x703040B0`, which is `__la_symbol_ptr + 0x10`, not `__dyld + 4` as the
conventional form of this stub uses. The `__dyld` section is only 8 bytes and
`dyld_stub_binding_helper` above uses `__dyld + 0` correctly. Nothing in this
bundle calls `__dyld_func_lookup`, so the discrepancy is inert; it is recorded
because a rewrite that produced a different byte here would be right to.

**3. `sub_70301F58` — 1882201944 (`0x70301F58`), 127 bytes. Vector slot `+0x0C`.**

```c
static void VGAInitScreen(NXScreenDev *dev)
{
    dev->flags2    = 0;                                 /* +0x20 */
    dev->shmemSize = offsetof(VGAShmem_t, cursor);      /* +0x2C = 0x48 */
    dev->bitmap    = bm12->newBitmap(bm12, &dev->bounds, vgaVirtualAddress, 0,
                                     (dev->bounds.maxy - dev->bounds.miny) * vga_rowbytes,
                                     vga_rowbytes, 1, 0);
    dev->depth     = 1;                                 /* +0x24 */
    dev->shmemSize += sizeof(struct bm12Cursor);        /* += 0x240, total 648 */
    vgaBounds      = dev->bounds;                       /* two 4-byte stores */
}
```

`bm12->newBitmap` is the imaging class's method at vtable offset `0x3C`; the same
slot is called by `_VGASetCursor` with a 16×16 `Bounds`, which is what fixes its
signature. The storage handed over is `_vgaVirtualAddress`, the `os_malloc`'d
shadow, at `_vga_rowbytes` bytes per line — 160 at 640×480, i.e. two bits per
pixel. **This is the single most important structural fact about this driver: the
Window Server never draws into VGA memory. It draws into a packed 2-bit shadow
with the stock `bm12` machine, and the driver converts dirty rectangles into the
four-plane framebuffer afterwards.** The only writer of `_vgaBounds`.

**4. `sub_70301FD8` — 1882202072 (`0x70301FD8`), 96 bytes. Vector slot `+0x28`.**

```c
static void VGARegisterScreen(void)
{
    unsigned int token, count = 1;
    IOReturn r = _IOGetIntValues(master, object, "IO_Framebuffer_Register",
                                 1, &token, &count);
    if (r)
        os_fprintf(os_stderr, "VGA Driver: can't register screen(%d)\n", r);
}
```

The returned token is read into a stack slot and then discarded — the bundle never
uses it. On the kernel side this is what runs `-[IOVGADisplay _registerWithED]`
and hands out the shared region, so the ordering constraint in the Shared
contract's §2 is: geometry first, in `_VGAStart`; registration later, here, when
the Window Server initializes the screen device.

**5. `sub_70302038` — 1882202168 (`0x70302038`), 7 bytes. Vector slot `+0x50`.**

`push ebp / mov ebp, esp / mov esp, ebp / pop ebp / retn`. An empty C function.
It has a frame pointer, so it is compiled C and not a linker-generated no-op.

**6. `sub_70302040` — 1882202176 (`0x70302040`), 521 bytes. Vector slot `+0x00`.**

The compositing entry, and the largest of the vector statics. It takes an
operation record and a `Bounds *`, copies 36 bytes of the record onto its stack
with a `movsd` run, selects a source bitmap from the record's `+0x00` or `+0x04`
according to the low nibble of `+0x08`, dispatches on a tag byte that is `0x67`
(`'g'`) or `0x70` (`'p'`), calls the imaging machine's method at vtable `+0x20`
and then either `+0x1C` on the destination or `+0x0C` followed by `+0x1C` on a
temporary, releases up to two temporaries by decrementing their 16-bit refcount at
`+0x0E` and calling `+0x10` at zero, and finishes with

```c
vga_at_mode12_bpp2_to_bpp4(dirtyRect);
```

The `'g'`/`'p'` tag and the operation record's layout are the Window Server's, not
this driver's, and no header for them exists in this tree. The rewrite has to
reproduce the field offsets exactly and can name them only descriptively. The
refcount protocol — 16-bit count at `+0x0E`, `free` at class vtable `+0x10` — is
the same in slots `+0x04`, `+0x24` and in `_VGASetCursor`, so it is the imaging
machine's convention and not a local idiom.

**7. `sub_7030224C` — 1882202700 (`0x7030224C`), 36 bytes. Vector slot `+0x04`.**

```c
static void VGAFreeOffscreen(NXScreenDev *dev)
{
    if (dev->offscreen && --dev->offscreen->refcount == 0)
        dev->offscreen->isa->free(dev->offscreen);
}
```

**8. `sub_70302270` — 1882202736 (`0x70302270`), 57 bytes. Vector slot `+0x10`.**

```c
static void VGAFillRect(NXScreenDev *dev, int which, int arg, Bounds *r, int arg2)
{
    bitmap *bm = (which == 1) ? dev->cached : dev->offscreen;
    bm->isa->fill(bm, arg, r, arg2);          /* class vtable +0x24 */
    vga_at_mode12_bpp2_to_bpp4(r);
}
```

The flush is unconditional even when the target was the offscreen bitmap, which is
a wasted conversion in that case; reproduce it.

**9. `sub_703022AC` — 1882202796 (`0x703022AC`), 45 bytes. Vector slot `+0x14`.**

```c
static void VGASetOffscreenOrigin(NXScreenDev *dev, short x, short y)
{
    if (dev->offscreen)
        dev->offscreen->isa->setOrigin(dev->offscreen, x, y);   /* +0x2C */
}
```

Both arguments are read as 16-bit and sign-extended before the call, so the
prototype takes `short`.

**10. `sub_703022DC` — 1882202844 (`0x703022DC`), 29 bytes. Vector slot `+0x18`.**

```c
static void VGAOffscreenOp18(NXScreenDev *dev)
{
    if (dev->offscreen)
        dev->offscreen->isa->method28(dev->offscreen, 1);       /* +0x28 */
}
```

The constant `1` is the only argument and is never varied.

**11. `sub_703022FC` — 1882202876 (`0x703022FC`), 111 bytes. Vector slot `+0x1C`.**

```c
static void VGANewOffscreen(NXScreenDev *dev, void *a, int which, int depth, void *b)
{
    dev->cached = dev->bitmap->field0C;                /* +0x18 */
    if (which == 1) return;
    if (depth < 0)      depth = 0;
    else if (depth > 4) depth = 4;
    class = bmClasses[depth];                          /* the table at 0x70304004 */
    dev->offscreen = class->newBitmap2(class, a, b);   /* class vtable +0x0C */
    dev->flags = (dev->flags & ~1) |
                 (dev->cached->format != dev->offscreen->format);  /* both at +0x0C */
}
```

This and finding 12 are the only two readers of the five-entry `__bm*` table, and
they are the reason `_bm18`, `_bm34` and `_bm38` are imported at all.

**12. `sub_7030236C` — 1882202988 (`0x7030236C`), 223 bytes. Vector slot `+0x24`.**

Converts the offscreen bitmap to the class at `bmClasses[index]`. It returns
immediately if the requested index equals the current bitmap's `format` field
(`+0x0C`), or if the current bitmap's class is already the requested one, or if
its fourth argument is 1. Otherwise it creates a bitmap of the new class, calls
the old class's method at `+0x20` to get a converter, runs the new bitmap's
`+0x1C` method with six arguments, releases both temporaries through the same
refcount protocol as finding 6, installs the new bitmap in `dev->offscreen` and
recomputes the `+0x01` format-differs bit exactly as finding 11 does. Its index
argument is **not** clamped, unlike finding 11's — a caller passing an index above
4 reads past the five-entry table. Reproduce that too.

**13. `sub_7030244C` — 1882203212 (`0x7030244C`), 58 bytes. Vector slot `+0x2C`.**

```c
static int VGAGetOffscreenParams(NXScreenDev *dev)
{
    int a, b, c, d, e;
    if (!dev->offscreen) return 0;
    return dev->offscreen->isa->getParams(dev->offscreen, &a, &b, &c, &d, &e);
}
```

Five out-parameters, all `int`, all discarded by this function — it is a pure
pass-through of the callee's return value, and the stack cleanup is folded into
the `mov esp, ebp` epilogue rather than an `add esp`.

**14. `_Start`, `_VGAStart` — 1882203272 (`0x70302488`), 637 bytes.**

Decompiled in full under "the Window Server's entry contract" above, including
the `os_malloc` failure-path defect and the `_Start` alias. Not repeated here.

**15. `_VGASysHideCursor` — 1882203912 (`0x70302708`), 29 bytes.**

```c
void VGASysHideCursor(NXScreenDev *dev)          /* caller holds cursorSema */
{
    VGAShmem_t *sh = dev->shmem;
    if (sh->cursorShow++ == 0)
        VGARemoveCursorBlit(dev);                /* sub_70302E48 */
}
```

The post-increment is compiled as `mov dl,[eax+8] / inc byte [eax+8] / test dl,dl`,
so the counter is incremented unconditionally and the old value decides. Matches
the Shared contract's `hide` half exactly, and matches the kernel's inlined copy
in `-[IOVGADisplay hideCursor:]`.

**16. `_VGASysShowCursor` — 1882203944 (`0x70302728`), 107 bytes.**

```c
void VGASysShowCursor(NXScreenDev *dev)          /* caller holds cursorSema */
{
    VGAShmem_t *sh = dev->shmem;
    if (sh->cursorShow == 0) return;
    if (--sh->cursorShow != 0) return;
    Point p = sh->hotSpot[sh->frame];            /* one 4-byte load */
    sh->cursorRect.minx = sh->cursorLoc.x - p.x;
    sh->cursorRect.maxx = sh->cursorRect.minx + CURSORWIDTH;
    sh->cursorRect.miny = sh->cursorLoc.y - p.y; /* p.y via sar ecx, 16 */
    sh->cursorRect.maxy = sh->cursorRect.miny + CURSORHEIGHT;
    VGADisplayCursorBlit(dev);                   /* sub_70302BEC */
    sh->oldCursorRect = sh->cursorRect;          /* +0x20 -> +0x28, +0x24 -> +0x2C */
}
```

Byte for byte the Shared contract's `show` half. `hotSpot[frame]` is addressed as
`[edx + ecx*4 + 0x38]`, confirming the `Point hotSpot[4]` at `+0x38`, and the y
component is recovered with `sar ecx, 16` rather than a second 16-bit load —
neither half stores the hot spot as two shorts.

**17. `_VGACheckShield` — 1882204052 (`0x70302794`), 178 bytes.**

```c
void VGACheckShield(NXScreenDev *dev)            /* caller holds cursorSema */
{
    VGAShmem_t *sh = dev->shmem;
    Point p = sh->hotSpot[sh->frame];
    short minx = sh->cursorLoc.x - p.x, maxx = minx + 16;
    short miny = sh->cursorLoc.y - p.y, maxy = miny + 16;
    int hit = 0;
    if (sh->shieldRect.maxx > minx && sh->shieldRect.minx < maxx &&
        sh->shieldRect.maxy > miny && sh->shieldRect.miny < maxy)
        hit = 1;
    if (hit != (signed char)sh->shielded) {
        if (hit) VGASysHideCursor(dev); else VGASysShowCursor(dev);
        sh->shielded = hit;
    }
}
```

Confirms the Shared contract: it recomputes the cursor rectangle into registers
and **does not** write `shmem->cursorRect`. The four comparisons are 16-bit and
strict on the max side, so an empty or edge-touching intersection counts as a
miss. `shielded` is read with `movsx byte`, i.e. as `signed char`, which is why
the contract writes the comparison that way.

**18. `_VGASetCursor` — 1882204232 (`0x70302848`), 554 bytes.**

```c
void VGASetCursor(NXScreenDev *dev, bitmap *src, Point hot, int frame, int *flagp)
{
    unsigned int  imageBuf[16], maskBuf[16];       /* 64 bytes each, on the stack */
    void         *image = imageBuf, *mask = maskBuf;
    bitmap       *tmp;
    int           hide;

    tmp = bm12->newBitmap(bm12, &cursorBounds16x16, imageBuf, maskBuf, 64, 4, 0, 0);
    switch (src->format) {                          /* short at src->+0x0C */
    case 1:  image = src->plane0; mask = src->plane1; break;   /* +0x20, +0x24 */
    case 2:  BM12Convert8to2 (tmp, src, 0x00100000, 0x00100000,
                              src->f4, src->f8, 0, 0); break;
    case 3:  BM12Convert16to2(tmp, src, /* same six */ ); break;
    case 4:  BM12Convert32to2(tmp, src, /* same six */ ); break;
    default: break;                                 /* nothing converted */
    }
    ev_lock(&dev->shmem->cursorSema);
    hide = (*flagp == 0);
    if (hide) VGASysHideCursor(dev);
    dev->shmem->hotSpot[frame] = hot;               /* one 4-byte store */
    bcopy(image, &dev->shmem->cursor.bw.image[frame], 64);
    bcopy(mask,  &dev->shmem->cursor.bw.mask [frame], 64);
    if (hide) VGASysShowCursor(dev);
    ev_unlock(&dev->shmem->cursorSema);
    if (--tmp->refcount == 0) tmp->isa->free(tmp);
}
```

The dispatch is a four-entry jump table at `0x703028E8` on `src->format - 1`, with
`ja` to the default for anything outside 1…4. Case 1 uses the source descriptor's
own planes untouched; the default case falls through with `image`/`mask` still
pointing at the **uninitialized** stack buffers, so a bad `format` copies 128
bytes of stack garbage into the shared cursor. That is Apple's, and it is
reachable only from the Window Server.

The destination addressing is `shmem + frame*64 + 0x48` and
`shmem + frame*64 + 0x148`, and the copies are 64 bytes — `image[4][16]` and
`mask[4][16]` of `unsigned int` in `struct bm12Cursor`. Together with the kernel's
`lea edx, [ebx+eax+48h]` / `lea ecx, [ebx+eax+148h]`, that pins the `bw` arm on
both sides, as the Shared contract's §1 says.

The three converters are the only reason the bundle imports `_BM12Convert8to2`,
`_BM12Convert16to2` and `_BM12Convert32to2` at all, and their argument list is
identical in all three arms — only the callee differs. `0x00100000` is the
`__const` word at `0x70303E44`, which read as a `Bounds` is `{0, 16, 0, 16}`.

**19. `_VGAHideCursor` — 1882204788 (`0x70302A74`), 44 bytes.**

```c
void VGAHideCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    VGASysHideCursor(dev);
    ev_unlock(&dev->shmem->cursorSema);
}
```

**20. `_VGAShowCursor` — 1882204832 (`0x70302AA0`), 44 bytes.** The same, around
`VGASysShowCursor`. Both recompute `dev->shmem` for the unlock.

**21. `_VGAObscureCursor` — 1882204876 (`0x70302ACC`), 66 bytes.**

```c
void VGAObscureCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    if (!dev->shmem->cursorObscured) {
        VGASysHideCursor(dev);
        dev->shmem->cursorObscured = 1;
    }
    ev_unlock(&dev->shmem->cursorSema);
}
```

**22. `_VGARevealCursor` — 1882204944 (`0x70302B10`), 63 bytes.**

```c
void VGARevealCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    if (dev->shmem->cursorObscured) {
        dev->shmem->cursorObscured = 0;
        VGASysShowCursor(dev);
    }
    ev_unlock(&dev->shmem->cursorSema);
}
```

Note the order: obscure hides *then* sets the flag; reveal clears the flag *then*
shows. The asymmetry is in the compiled code and is visible in the sizes, 66
against 63.

**23. `_VGAShieldCursor` — 1882205008 (`0x70302B50`), 78 bytes.**

```c
void VGAShieldCursor(NXScreenDev *dev, Bounds *r)
{
    ev_lock(&dev->shmem->cursorSema);
    dev->shmem->shieldFlag = 1;
    dev->shmem->shielded   = 0;
    dev->shmem->shieldRect = *r;              /* two 4-byte stores, +0x14, +0x18 */
    VGACheckShield(dev);
    ev_unlock(&dev->shmem->cursorSema);
}
```

The defect is the `shielded = 0` before `VGACheckShield`; see the correction
subsection above. Single basic block, 31 instructions — there is no conditional in
it at all.

**24. `_VGAUnshieldCursor` — 1882205088 (`0x70302BA0`), 73 bytes.**

```c
void VGAUnshieldCursor(NXScreenDev *dev)
{
    ev_lock(&dev->shmem->cursorSema);
    if (dev->shmem->shielded) VGASysShowCursor(dev);
    dev->shmem->shielded   = 0;
    dev->shmem->shieldFlag = 0;
    ev_unlock(&dev->shmem->cursorSema);
}
```

73 bytes, against the 1164 §1.1's gap-derived table gives it. The 1091-byte
difference is exactly `sub_70302BEC` (603) plus `sub_70302E48` (481) plus 7 bytes
of alignment, which is the whole reason the sixteen statics had to be recovered.

**25. `sub_70302BEC` — 1882205164 (`0x70302BEC`), 603 bytes. Draw the cursor.**

The direct counterpart of the kernel's `_VGADisplayCursor` (`VGA_reloc` 1752, 816
bytes). Called only by `_VGASysShowCursor`.

```c
static void VGADisplayCursorBlit(NXScreenDev *dev)
{
    VGAShmem_t *sh  = dev->shmem;
    Bounds      c   = sh->cursorRect;                 /* two 4-byte loads */
    Bounds      scr = dev->bounds;

    if (scr.miny > c.miny) c.miny = scr.miny;         /* clip vertically */
    if (scr.maxy < c.maxy) c.maxy = scr.maxy;
    /* snap horizontally to a 16-pixel column and take two columns */
    x0 = scr.minx + ((sh->cursorRect.minx - scr.minx) & ~15);
    sh->saveRect.minx = x0;      sh->saveRect.maxx = x0 + 32;
    sh->saveRect.miny = c.miny;  sh->saveRect.maxy = c.maxy;

    shift  = (sh->cursorRect.minx & 15) * 2;          /* 2 bits per pixel */
    rshift = 32 - shift;
    rows   = c.miny - sh->cursorRect.miny;            /* rows clipped off the top */
    img    = &sh->cursor.bw.image[sh->frame][rows];
    msk    = &sh->cursor.bw.mask [sh->frame][rows];
    save   = &sh->cursor.bw.save[0];
    leftOK  = (scr.minx <= x0);
    rightOK = (x0 + 32 <= scr.maxx);

    words = vga_bpl >> 1;                             /* 16-pixel words per line */
    lines = 0x10000 / vga_bpl;                        /* lines per 64 KB window  */
    get_addr_range(&p);
    row   = c.miny - scr.miny;
    p    += ((row % lines) * words + ((x0 - scr.minx) >> 4)) * 2;

    for (y = row; y < c.maxy - scr.miny; y++) {
        if (leftOK) {
            v = read_bpp4planar_to_bpp2packed(p);
            *save++ = v;
            v = (v & ~(*msk << shift)) | (*img << shift);
            write_bpp2packed_to_bpp4planar(v, p);
        }
        if (rightOK) {
            if (shift == 0) save++;                   /* nothing spills over */
            else {
                v = read_bpp4planar_to_bpp2packed(p + 2);
                *save++ = v;
                v = (v & ~(*msk >> rshift)) | (*img >> rshift);
                write_bpp2packed_to_bpp4planar(v, p + 2);
            }
        }
        p += vga_bpl; img++; msk++;
    }
}
```

The kernel's copy is the same algorithm with three differences, all of which are
kernel-side needs the bundle does not have: it saves and restores the sequencer
map mask and the current read/write plane and segment around the loop; it calls
`_select_read_segment` / `_select_write_segment` at each 64 KB boundary and gets
its frame-buffer pointer as a literal `0xA0000` rather than through
`_get_addr_range`; and it computes the words-per-line as `displayInfo->width >> 4`
where the bundle uses `vga_bpl >> 1`. Those are the same number, 40 at 640 wide.
The mask/image shift arithmetic, the `save` stride, the `shift == 0` special case
and the two-column clip are identical instruction for instruction.

Compiled C: frame pointer, stack arguments, no unusual instruction.

**26. `sub_70302E48` — 1882205768 (`0x70302E48`), 481 bytes. Erase the cursor.**

The counterpart of the kernel's `_VGARemoveCursor` (`VGA_reloc` 2568, 660 bytes).
Called only by `_VGASysHideCursor`.

```c
static void VGARemoveCursorBlit(NXScreenDev *dev)
{
    VGAShmem_t  *sh  = dev->shmem;
    Bounds       scr = dev->bounds;
    Bounds       s   = sh->saveRect;                  /* what the draw pass wrote */
    unsigned int maskL = 0, maskR = 0;

    col   = (s.minx - scr.minx) >> 4;
    words = vga_bpl >> 1;
    lines = 0x10000 / vga_bpl;
    get_addr_range(&p);
    p    += (((s.miny - scr.miny) % lines) * words + col) * 2;
    shift = (sh->cursorRect.minx & 15) * 2;
    save  = &sh->cursor.bw.save[0];

    leftOK  = (s.minx >= scr.minx);
    rightOK = (scr.maxx >= s.maxx);
    if (leftOK)  maskL =  leftMask[sh->oldCursorRect.minx - s.minx];
    if (rightOK) maskR = ~leftMask[16 - (s.maxx - sh->oldCursorRect.maxx)];

    for (y = s.miny - scr.miny; y < s.maxy - scr.miny; y++) {
        if (leftOK) {
            v = read_bpp4planar_to_bpp2packed(p);
            v = (v & ~maskL) | (maskL & *save++);
            write_bpp2packed_to_bpp4planar(v, p);
        }
        if (rightOK) {
            if (shift == 0) save++;
            else {
                v = read_bpp4planar_to_bpp2packed(p + 2);
                v = (v & ~maskR) | (maskR & *save++);
                write_bpp2packed_to_bpp4planar(v, p + 2);
            }
        }
        p += vga_bpl;
    }
}
```

`leftMask` is the 17-entry table at `__TEXT,__const` `0x70303E54`,
`leftMask[k] == ~0u << (2*k)`: `0xFFFFFFFF, 0xFFFFFFFC, 0xFFFFFFF0, 0xFFFFFFC0,
0xFFFFFF00, …, 0xC0000000, 0x00000000`. **The kernel has a byte-identical copy** —
`_mask_array.128` at `VGA_reloc` `__data` 24604, 68 bytes, all seventeen values
the same — and uses it in `_VGARemoveCursor` with the same two index expressions.
That is the strongest single cross-check in this section: two independently
compiled binaries, the same 68-byte table in different sections, the same two
subscripts.

This is where `oldCursorRect` earns its keep. The erase pass restores only the
columns the *previous* draw actually covered, which is why the draw pass copies
`cursorRect` into `oldCursorRect` after blitting and why both halves must keep
doing so.

Compiled C.

**27. `_set_colormap` — 1882206252 (`0x7030302C`), 196 bytes.**

```c
void set_colormap(void)
{
    for (i = 0; i <= 255; i++) {                 /* every entry bright red */
        outb(0x3C8, i);
        outb(0x3C9, 0x3F); outb(0x3C9, 0); outb(0x3C9, 0);
    }
    outb(0x3C8, 3); outb(0x3C9, 0x3F); outb(0x3C9, 0x3F); outb(0x3C9, 0x3F);
    outb(0x3C8, 2); outb(0x3C9, 0x30); outb(0x3C9, 0x30); outb(0x3C9, 0x30);
    outb(0x3C8, 1); outb(0x3C9, 0x1E); outb(0x3C9, 0x1E); outb(0x3C9, 0x1E);
    outb(0x3C8, 0); outb(0x3C9, 0);    outb(0x3C9, 0);    outb(0x3C9, 0);
}
```

Only four of the sixteen mode-0x12 pixel values are ever produced by this driver,
so entries 4…255 are painted bright red as a deliberate tell: anything that shows
up red came from a plane this driver does not write. The four grays are 63, 48, 30
and 0, which are `WHITE_PALETTE_VALUE`, `LIGHT_GRAY_PALETTE_VALUE`,
`DARK_GRAY_PALETTE_VALUE` and `BLACK_PALETTE_VALUE` from
`IOVGADisplayPrivate.h`, in the same index order the kernel's
`_SetET4000Brightness` uses. **Index 3 is white and index 0 is black**, which is
the inverse of NeXT's 2-bit gray, and that is why the two conversion tables of
finding 35 complement every byte.

**Note on `outb` in this binary.** Every `out` and `in` is followed by
`lock incl -4(%ebp)` — the dummy `"=m"` operand of the inline `outb` is an
*automatic*, not the `static int xxx;` that `driverkit/i386/ioPorts.h` declares
and that produces `lock incl _xxx.100` throughout `VGA_reloc`. So the user-space
half was compiled against a different `outb`, and Phase 3a must not reach for the
driverkit header here or it will emit a static and a relocation the reference does
not have.

**28. `sub_703030F0` — 1882206448 (`0x703030F0`), 81 bytes.**

```c
static void select_read_plane(int plane)
{
    outb(0x3CE, 4);                            /* GC index 4, Read Map Select */
    v = (inb(0x3CF) & 0xFC) | (plane & 3);
    outb(0x3CE, 4);
    outb(0x3CF, v);
}
```

The kernel's `_select_read_plane` (`VGA_reloc` 676, 110 bytes) is the same
read-modify-write; the size difference is the kernel copy caching the value in
`_curr_read_plane`, which the bundle has no need for. Leaf, no calls, compiled C.

**29. `sub_70303144` — 1882206532 (`0x70303144`), 92 bytes.**

```c
static void select_write_plane(int plane)
{
    outb(0x3C4, 2);                            /* SEQ index 2, Map Mask */
    v = (inb(0x3C5) & 0xF0) | (1 << (plane & 3));
    outb(0x3C4, 2);
    outb(0x3C5, v);
}
```

Note the asymmetry with finding 28 and reproduce it: the read selector takes a
plane *number*, the write selector turns the number into a one-hot *mask*, so only
one plane is ever written at a time. The kernel's `_select_write_plane`
(`VGA_reloc` 788, 127 bytes) does the same. Leaf, compiled C.

**30. `_get_addr_range` — 1882206624 (`0x703031A0`), 117 bytes.**

```c
void get_addr_range(void **out)
{
    outb(0x3CE, 6);                            /* GC index 6, Miscellaneous */
    switch ((inb(0x3CF) & 0x0C) >> 2) {        /* memory map select */
    case 0: case 1: *out = vgaAddress;             break;   /* 0xA0000 */
    case 2: case 3: *out = vgaAddress + 0x10000;   break;   /* 0xB0000 */
    }
}
```

A four-entry jump table at `0x703031E0` with two distinct targets. This is the
bundle's replacement for the kernel's `_select_read_segment` /
`_select_write_segment` pair: it has a 128 KB mapping of `0xA0000` and never
bank-switches, so it only needs to know where the aperture currently is. Map
select 3 is `0xB8000`–`0xBFFFF` on real hardware and this returns `0xB0000` for
it, a 32 KB error; mode 0x12 uses select 1, so the path is dead. Reproduce it.

**31. `_fill_64K_plane` — 1882206744 (`0x70303218`), 120 bytes.**

```c
void fill_64K_plane(short value)
{
    outb(0x3C4, 2);
    saved = inb(0x3C5);                        /* save the map mask */
    get_addr_range(&p);
    for (row = 0; row <= 0xC7; row++)          /* 200 */
        for (col = 0; col <= 0x13F; col++)     /* 320 */
            { *(short *)p = value; p += 2; }
    outb(0x3C4, 2);
    outb(0x3C5, saved);                        /* restore it */
}
```

It saves and restores the map mask but never changes it, so the fill goes to
whatever planes are currently enabled — all four, because `_VGAStart` calls it
right after `VGASetStdRegs(5)` leaves SEQ[2] at `0x0F`. The save/restore is
vestigial. 320 × 200 × 2 = 128000 bytes, which overruns the 64 KB the name
promises, but not the mapping: `_VGAStart`'s `_IOMapEISADeviceMemory` call maps
128 KB (`0x20000`) at `0xA0000`, and the whole 128000-byte write stays inside
it, so nothing faults. The excess 62464 bytes spill into the `0xB0000` window
of that same mapping rather than being discarded by the hardware or landing in
planar VGA memory beyond it. Called once, with 0, and that is what clears
planes 2 and 3 for good — nothing in this driver ever writes them again.

**32. `_vga_at_mode12_bpp2_to_bpp4` — 1882206864 (`0x70303290`), 932 bytes.**

The flush. This is the largest body in the binary and the one every drawing
operation ends with.

```c
void vga_at_mode12_bpp2_to_bpp4(Bounds *r)
{
    if (!tablesBuilt) build_tables();                  /* the guard at 0x70304088 */

    x0 = max(vgaBounds.minx, r->minx);  x1 = min(vgaBounds.maxx, r->maxx);
    y0 = max(vgaBounds.miny, r->miny);  y1 = min(vgaBounds.maxy, r->maxy);
    if (x1 < x0 || y0 > y1) return;
    x0 -= vgaBounds.minx; x1 -= vgaBounds.minx;
    y0 -= vgaBounds.miny; y1 -= vgaBounds.miny;

    first = x0 >> 4;
    n     = (x1 >> 4) - first + ((x1 & ~15) != x1);    /* 16-pixel words to convert */
    words = vga_width >> 4;                            /* words per screen line     */
    outb(0x3C4, 2); saved = inb(0x3C5);                /* save the map mask         */

    src = (unsigned int   *)vgaVirtualAddress + y0 * words + first;
    get_addr_range(&p);
    dst = (unsigned short *)p                 + y0 * words + first;

    for (y = y0; y <= y1; y++) {
        select_write_plane(0);
        for (i = 0; i < n; i++) {
            v = src[i];
            dst[i] = (evenTable[(v >> 16) & 0x5555] << 8) | evenTable[v & 0x5555];
        }
        select_write_plane(1);
        for (i = 0; i < n; i++) {
            v = src[i];
            dst[i] = (oddTable[(v >> 16) & 0xAAAA] << 8) | oddTable[v & 0xAAAA];
        }
        select_write_plane(0);
        src += words; dst += words;
    }
    outb(0x3C4, 2); outb(0x3C5, saved);
}
```

gcc peeled the first row, so the two inner loops appear twice in the disassembly;
the peeled copy loads the table bases from the PIC register directly and the
rolled copy caches them in locals. That is why the body is 932 bytes for what is a
twenty-line function.

Three facts to carry into the rewrite. The source stride is `vga_width >> 4`
32-bit words, which is `vga_rowbytes` bytes and matches the `bm12` shadow's row
pitch. The destination stride is the same count of 16-bit words, which is
`vga_bpl` bytes. And **only planes 0 and 1 are ever written**, which is what makes
the driver 2 bits deep on 4-plane hardware and what `_set_colormap`'s red entries
are guarding.

**33. `_read_bpp4planar_to_bpp2packed` — 1882207796 (`0x70303634`), 402 bytes.**

```c
unsigned int read_bpp4planar_to_bpp2packed(const void *addr)
{
    select_read_plane(1);
    hi = spread(~*(unsigned short *)addr);   /* bit b -> bit 2b+1 */
    select_read_plane(0);
    lo = spread(~*(unsigned short *)addr);   /* bit b -> bit 2b   */
    return hi | lo;
}
```

Reads sixteen pixels' worth of planes 1 and 0, complements each 16-bit word, and
interleaves them into one 32-bit value of sixteen 2-bit pixels, plane 0 supplying
the low bit of each pair. gcc unrolled both spreads into 16 `and`/shift/`or`
triples each, which is the whole 402 bytes; the two shift schedules differ by one
because the destination bit is `2b` in one and `2b+1` in the other. The complement
is the NeXT-2-bit-gray-to-VGA-index inversion of finding 27. Single basic block.
The kernel's `_vga_read_bpp4planar_to_bpp2packed32` (`VGA_reloc` 916, 407 bytes) is
the same function with an out-parameter instead of a return value, which is
exactly the five-byte difference.

**34. `_write_bpp2packed_to_bpp4planar` — 1882208200 (`0x703037C8`), 124 bytes.**

```c
void write_bpp2packed_to_bpp4planar(unsigned int v, void *addr)
{
    select_write_plane(1);
    *(unsigned short *)addr = (oddTable [(v >> 16) & 0xAAAA] << 8) | oddTable [v & 0xAAAA];
    select_write_plane(0);
    *(unsigned short *)addr = (evenTable[(v >> 16) & 0x5555] << 8) | evenTable[v & 0x5555];
}
```

The inverse of finding 33, and 278 bytes shorter because it uses the two 64 KB
lookup tables instead of unrolled shifts. The kernel's
`_vga_write_bpp2packed32_to_bpp4planar` (`VGA_reloc` 1324, 428 bytes) does the same
job with unrolled shifts and no tables — **the two halves genuinely diverge here**,
and the divergence is a deliberate space/time trade the user-space half can afford
and the kernel cannot. Do not harmonize them.

`oddTable` is `0x70314138`, `evenTable` is `0x70304138`, both in `__bss`, both
built by finding 35. Neither is referenced anywhere else except finding 32.

**35. `sub_70303844` — 1882208324 (`0x70303844`), 240 bytes.**

```c
static void build_tables(void)
{
    for (c = 0; c <= 0xFFFF; c++) {
        evenTable[c] = ~gather_even(c);   /* bits 14,12,10,8,6,4,2,0 -> bits 0..7 */
        oddTable [c] = ~gather_odd (c);   /* bits 15,13,11,9,7,5,3,1 -> bits 0..7 */
    }
    tablesBuilt++;
}
```

Two 65536-byte tables, 131072 bytes, which is all of `__bss` bar 52 bytes. The
guard is the unnamed `static int` at `__DATA,__data` `0x70304088`; it is
incremented, not set, so a second call would leave it at 2 — but the only test is
against zero and the only caller is finding 32. Both gathers are fully unrolled,
which is the 240 bytes, and both results are complemented for the reason in
finding 27.

The remaining 52 bytes of `__bss`, `0x70304104`–`0x70304137`, hold the
`IOObjectNumber` at `0x70304110` and the `device_master_self()` port at
`0x70304114`. The other 44 bytes are not referenced by any instruction IDA
recovered; they are file-scope statics whose names the strip removed, and Phase 3a
will find out what they are only by writing the source and comparing sizes.

Compiled C: frame pointer, no unusual instruction, ordinary stack discipline.

**36. `_VGASetStdRegs` — 1882208564 (`0x70303934`), 401 bytes.**

```c
int VGASetStdRegs(int mode)
{
    if (mode > 5) return 1;
    inb(0x3DA);  outb(0x3C0, 0);                       /* reset AC flip-flop, blank */
    outb(0x3C2, miscTable[mode]);                      /* Miscellaneous Output      */
    for (i = 0; i <= 4;    i++) { outb(0x3C4, i); outb(0x3C5, seqTable [mode][i]); }
    outb(0x3C4, 0); outb(0x3C5, 3);                    /* release sequencer reset   */
    outb(0x3D4, 0x11); outb(0x3D5, 0);                 /* unprotect CRTC 0..7       */
    for (i = 0; i <= 0x18; i++) { outb(0x3D4, i); outb(0x3D5, crtcTable[mode][i]); }
    inb(0x3DA);
    for (i = 0; i <= 0x13; i++) { outb(0x3C0, i); outb(0x3C0, acTable  [mode][i]); }
    for (i = 0; i <= 8;    i++) { outb(0x3CE, i); outb(0x3CF, gcTable  [mode][i]); }
    inb(0x3DA);  outb(0x3C0, 0x20);                    /* unblank                   */
    return 0;
}
```

The five tables occupy 360 of the 444 bytes of `__TEXT,__const`, from `0x70303E98`
to `0x70304000`, with no slack:

| Address | Bytes | Table |
| --- | --- | --- |
| `0x70303E98` | 6 | `miscTable[6]` = `EB EB EB 2F 67 E3` |
| `0x70303E9E` | 30 | `seqTable[6][5]` |
| `0x70303EBC` | 150 | `crtcTable[6][25]` |
| `0x70303F52` | 120 | `acTable[6][20]` |
| `0x70303FCA` | 54 | `gcTable[6][9]` |

Mode 5 is `0xE3 / 03 01 0F 00 06 / …`, which is 640×480×16 — BIOS mode 0x12 — and
it is the only mode `_VGAStart` ever asks for. Mode 4 is `0x67 / 01 00 03 00 02`,
the 80×25 text mode. `mode < 0` is not checked and would read before the tables;
only `> 5` returns the error, and the error value is 1, not an `IOReturn`.

The remaining 84 bytes of `__const`, `0x70303E44`–`0x70303E97`, are the cursor
layer's: the 16×16 `Bounds` `{0, 16, 0, 16}` at `0x70303E44` (8 bytes) used by
`_VGASetCursor` (finding 18), then 8 zero bytes at `0x70303E4C`–`0x70303E53`
attributed to no object, then the 17-entry left-edge mask table at
`0x70303E54` used by `sub_70302E48` (finding 26). Not every byte of `__const`
is accounted for — those 8 bytes are the one gap; what *is* claimed is the
five register tables above plus these two cursor objects, `Bounds` and the
mask table, as the closing summary below states.

**37–53. The seventeen PIC symbol stubs — 1882209417 (`0x70303C89`) through
1882209833 (`0x70303E29`), 14 bytes each as IDA names them, 26 bytes each in
fact.**

| # | Address | Symbol | # | Address | Symbol |
| --- | --- | --- | --- | --- | --- |
| 37 | `0x70303C89` | `_NXRegisterScreen` | 46 | `0x70303D73` | `_os_fprintf` |
| 38 | `0x70303CA3` | `_os_malloc` | 47 | `0x70303D8D` | `__IOGetIntValues` |
| 39 | `0x70303CBD` | `__IOMapEISADevicePorts` | 48 | `0x70303DA7` | `_ev_unlock` |
| 40 | `0x70303CD7` | `_thread_self` | 49 | `0x70303DC1` | `_bcopy` |
| 41 | `0x70303CF1` | `__IOMapEISADeviceMemory` | 50 | `0x70303DDB` | `_ev_lock` |
| 42 | `0x70303D0B` | `__IOSetIntValues` | 51 | `0x70303DF5` | `_BM12Convert32to2` |
| 43 | `0x70303D25` | `__IOLookupByDeviceName` | 52 | `0x70303E0F` | `_BM12Convert16to2` |
| 44 | `0x70303D3F` | `_device_master_self` | 53 | `0x70303E29` | `_BM12Convert8to2` |
| 45 | `0x70303D59` | `_LookupFrameBufferDevicePort` | | | |

Every one has the identical shape

```
call $+5 ; pop eax ; mov edx, [eax + disp] ; jmp edx
```

where `disp` reaches the matching `__DATA,__la_symbol_ptr` cell.
`__picsymbol_stub` is 442 bytes and the stubs start 26 apart, so each carries a
further 12 bytes that IDA does not name: the lazy half, which the
`__la_symbol_ptr` cell points at until dyld rebinds it. The file's
`__la_symbol_ptr` values are `stub + 14` for all seventeen, which is that lazy
half's address, exactly as expected for a bundle that has never been loaded.

All seventeen are `intentional-mismatch` in the ledger, with the linker and dyld
named as their generator: `ld` synthesizes one stub and one lazy pointer per
lazily-bound external function, and they will reappear in our build only as a side
effect of the source calling `os_fprintf`, `ev_lock` and the rest. There is no
source to write for them.

The four imports that are **not** in this list — `_bm12`, `_bm18`, `_bm34`,
`_bm38` — are undefined *data*, bound through `__nl_symbol_ptr` and `__data`
relocations rather than through stubs, along with `_os_stderr` and `_task_self_`.
That is why `__picsymbol_stub` has 17 entries for 23 undefined symbols.

### What Phase 3a has to reproduce, in one place

- One C translation unit, `__text` `0x70301F58`–`0x70303AC4`, 34 compiled bodies,
  no assembly.
- Two exported names on one body (`_Start`, `_VGAStart`), 19 exported function
  symbols in total, and 7 exported `__common` globals.
- A 21-slot vector table in `__DATA,__data` at `+0x18` with three null slots, and
  a five-entry `__bm*` class table before it.
- The `_VGAStart` call order and its seven `__cstring` failure paths verbatim,
  including the stale-`r` `os_malloc` message.
- The blocking `ev_lock` discipline on all seven public cursor entry points and
  none on the three primitives.
- `_VGAShieldCursor`'s `shielded = 0` before `_VGACheckShield`, unchanged.
- Both blitters' `save` stride of two words per scan line, unchanged.
- 444 bytes of `__const` in five VGA register tables plus the 16×16 `Bounds` and
  the 17-entry mask table; 131072 bytes of `__bss` in two built-at-runtime tables.
- An `outb` whose dummy operand is an automatic, not `driverkit`'s `static int`.
