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
document, but all 48 of its relocation records come back with the
unclassified kind `"0"`, so `normalize_analysis` can never derive a field
width and aborts on the first (`relocation 0 has missing or conflicting
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

**Five translation units.** The evidence is the compiler's own private-name
numbering plus link order, which is consistent across `__text`, `__const`,
`__data` and `__bss` simultaneously.

The decisive datum is `_xxx.100`, `_xxx.103` and `_xxx.106` at `__bss`
24764/24768/24772. They are not three variables named `xxx` in three files:
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

100 → 168 with no restart, spanning text addresses 228 → 6006. So
**`-[IOVGADisplay _registerWithED]` at 0 through
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

The remaining four boundaries follow from address order and from the sections
each unit contributes:

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
2. **the Kernel Server instance stub** — `__text` 6372 … 6383;
   `__common` `_VGA_instance`. Build-generated (§2.9).
3. **the version stub** — `__text` 6384 … 6395; `__const` `_VGA_VERS_STRING`
   (18928) and `_VGA_VERS_NUM` (19088), both *after* `_ports.168` in
   `__const`, which fixes its position after unit 1 in link order.
   Build-generated. `_VGA_VERS_STRING` is
   `"@(#)PROGRAM:VGA  PROJECT:vga-18  DEVELOPER:root  BUILT:Sat Apr 4 04:34:41 PST 1998"`
   and `_VGA_VERS_NUM` is 14385.
4. **`vidBIOS.m`** — `__text` 6396 … 7551. Contributes no `__data`, no
   `__bss`, no `__const` and no statics of any kind, which is why it leaves no
   trace in the numbering; its position is fixed by address order alone.
5. **`emu486.s`** — `__text` 7552 … 18048; `__data` 24672 … 24764, the
   emulator's 92-byte state block, immediately after unit 1's
   `_mask_array.128` and last in the section. See the `_emu486` subsection for
   why this is assembly.

**Therefore `VGA.lksproj`'s `sources` should name three hand-written files:**
`IOVGADisplay.m`, `vidBIOS.m` and `emu486.s`. Units 2 and 3 are emitted by the
Kernel Server project type and must not be written by hand.

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

**`_emu486` is hand-written i386 assembly, not compiled C.** Six independent
observations, any two of which would be suggestive and all six of which
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
at `0x1E20`, 11 to `0x38F8`, 6 to `0x3A46`, 4 to `0x1E28`, 2 each to `0x2180`
and `0x1E58`, one each to `0x2008` and `0x201B`, and 7 end in `retn`. A
transcription that assumed one uniform handler shape would be wrong.

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

`return &VGA_instance;` — returns the address of the 7948-byte `__common`
symbol `_VGA_instance`. Emitted by the Kernel Server project type from the
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
