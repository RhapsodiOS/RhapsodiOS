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
