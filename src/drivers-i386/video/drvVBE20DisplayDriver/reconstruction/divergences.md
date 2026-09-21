# drvVBE20DisplayDriver divergences

## Conventions for the offsets cited below

`__text N` and `text+N` both mean byte offset `N` from the start of the
reference's `__TEXT,__text` section. That section has address 0, file offset
2328 and size 2324 (`VBE20DisplayDriver_reloc`, SHA-256
`9FBC2CAFBDD0124CC63B902161C86BBFEC0EF48D591DDA681A325FF7B68DADED`, 37984
bytes), so `text+N` is also file offset 2328+N and `__text` address N. Offsets
are of an instruction's first opcode byte.

`boot+N` means byte offset `N` into the 4.2 booter file, which is a headerless
image; its text addresses equal its file offsets, and its data addresses are
file offset + 0x3000 (calibrated in D1). Relocation offsets are `r_address`
values from the section's relocation entries, i.e. the same `__text N` scale.

## Measurement: inherited ivar chain (Task 1)

The reference declares no ivars of its own — `__OBJC,__instance_vars` is 0
bytes — so its `instance_size` of 552 measures OPENSTEP 4.2's
`Object` + `IODevice` + `IODirectDevice` + `IODisplay` + `IOFrameBufferDisplay`
chain exactly. `IODisplay` inherits from `IODirectDevice`, not `IODevice`
(`src/driverkit-3/driverkit/IODisplay.h`: `@interface IODisplay: IODirectDevice`;
`src/driverkit-3/driverkit/IODirectDevice.h`: `@interface IODirectDevice :
IODevice`), so the plan's four-class chain omits one link. Without
`IODirectDevice` the sum is 520, not 552.

Rhapsody's same chain measures 552 bytes. i386 sizes: pointers, `id`, `int`,
enums and `port_t` are 4 bytes, `IOString` is `char[80]`
(`src/driverkit-3/driverkit/driverTypes.h`, `IO_STRING_LENGTH` 80),
`IOPixelEncoding` is `char[64]` (`src/driverkit-3/driverkit/displayDefs.h`,
`IO_MAX_PIXEL_BITS` 64).

Ivars were read from `src/objc-1/Object.h` and, in `src/driverkit-3/driverkit/`,
`IODevice.h`, `IODirectDevice.h`, `IODisplay.h`, `IOFrameBufferDisplay.h` and
`displayDefs.h`.

| Class | Ivars | Bytes | Starts at |
| --- | --- | --- | --- |
| `Object` | `isa` | 4 | 0 |
| `IODevice` | `_unit` 4, `_deviceName` / `_location` / `_deviceKind` 3 x 80, `__deviceDescription` 4, `_IODevice_reserved[3]` 12 | 260 | 4 |
| `IODirectDevice` | six pointer-sized ivars 24, `_IODirectDevice_reserved[2]` 8 | 32 | 264 |
| `IODisplay` | `_display` (`IODisplayInfo`) 136, `_token` 4, `_IODisplay_reserved[18]` 72 | 212 | 296 |
| `IOFrameBufferDisplay` | `priv` 4, four sample-table pointers 16, `_currentDisplayMode` / `_pendingDisplayMode` / `_displayModeCount` 12, `_displayModes` 4, `_IOFrameBufferDisplay_reserved[2]` 8 | 44 | 508 |
| **Total** | | **552** | |

`IODisplayInfo` is 136 bytes: five `int` 20, `frameBuffer` 4, `bitsPerPixel` 4,
`colorSpace` 4, `pixelEncoding` 64, `flags` 4, `parameters` 4, `memorySize` /
`scanRate` / `_reserved1` / `dotClockRate` 16, `screenWidth` / `screenHeight` 8,
`modeUnavailableFlag` 4, `_reserved[1]` 4.

Two measurements in the reference itself agree with this layout:

- `VBE20DisplayDriverVersion : IODevice` has `instance_size` 264, which is
  `Object` 4 + `IODevice` 260.
- `initUnnamedFromDeviceDescription:`, the `UnnamedInitialization` category
  method on `IOFrameBufferDisplay` (IMP 0, first function in `__text`), stores
  to four displacements past `IODevice`'s 264 bytes:

  ```
  __text 0..144, -[IOFrameBufferDisplay(UnnamedInitialization) initUnnamedFromDeviceDescription:]

    text+56   c783 14020000 ffffffff   movl $-1, 0x214(%ebx)   _pendingDisplayMode  (532)
    text+66   c783 10020000 ffffffff   movl $-1, 0x210(%ebx)   _currentDisplayMode  (528)
    text+76   c783 18020000 ffffffff   movl $-1, 0x218(%ebx)   _displayModeCount    (536)
    text+86   c783 1c020000 00000000   movl $0,  0x21c(%ebx)   _displayModes        (540)
  ```

  Offsets are of the first opcode byte (`c7`); each displacement field sits 2
  bytes later. The order is the one `src/driverkit-3/libDriver/Kernel/IOFrameBufferDisplay.m`
  line 748 (`_currentDisplayMode = _pendingDisplayMode = -1;`) and 749
  (`_displayModeCount = -1; _displayModes = NULL;`) compile to.

  With `IOFrameBufferDisplay` starting at 508: 508 + `priv` 4 + four sample
  tables 16 = 528, and 540 + 4 + `_IOFrameBufferDisplay_reserved[2]` 8 = 552. The
  four displacements land exactly on the last four ivars of the 552 layout, so
  this confirms the total from the binary side rather than from header
  arithmetic.

The chain did not move between releases. Parity target for this reconstruction
is byte-parity throughout.

## Observation: two mode lists (Task 1)

`initUnnamedFromDeviceDescription:` writes the *inherited*
`_currentDisplayMode` / `_pendingDisplayMode` / `_displayModeCount` /
`_displayModes` ivars (to -1, -1, -1, 0), while the driver's own `displayModes`
and `displayModeCount` accessors read *file statics* in `__DATA,__data` instead.
The driver therefore maintains its mode list separately from the base class's
storage. Both facts are from the disassembly.

The accessors, from `__OBJC,__inst_meth`:

```
__text 2276, -[VBE20DisplayDriver displayModeCount]   55 89 e5  a1 04 20 00 00  89 ec 5d c3
__text 2288, -[VBE20DisplayDriver displayModes]       55 89 e5  a1 00 20 00 00  89 ec 5d c3
```

Each carries a local relocation (`r_extern` 0, section ordinal 4) at the
`mov eax, [abs]` operand, `__text` 2280 and 2292, into `__DATA,__data`, which is
8 bytes at `0x2000` — exactly two 4-byte slots: `displayModes` at `0x2000`,
`displayModeCount` at `0x2004`.

The only stores to those slots are three, all inside `parseVESAModes:size:`
(`__text` 692..984). These offsets are the ones Task 1's notes recorded
(`0x2cd`, `0x2f5`, `0x341`) and were re-checked by disassembly:

```
  text+717  c705 04200000 00000000   movl $0,   0x2004
  text+757  8915 04200000            movl %edx, 0x2004
  text+833  a3 00200000              movl %eax, 0x2000
```

Every other reference to `0x2000` / `0x2004` in `__text` is a read: elsewhere in
`parseVESAModes:size:`, in `getCharValues:forParameter:count:` (`__text`
1240..1916), and in the two accessors.

For Tasks 3-7: the four inherited-ivar stores above are the only accesses to
ivars beyond `IODevice`'s 264 bytes, so the rebuilt category initialiser must
reproduce those four displacements, and the accessors must be the absolute loads
of the two statics, not ivar reads.

## Unmeasured: `IODisplayInfo` across releases

`IODisplayInfo` being layout-identical across the two releases is an inference,
not a measurement: this repo has no OPENSTEP 4.2 headers to compare against.
What is established is that the reference's ObjC type encoding for it,
`{?=iiiii^vii[64c]I^viiiiiiI[1I]}` (in `__OBJC,__meth_var_types`), maps
field-for-field onto `IODisplayInfo` in `src/driverkit-3/driverkit/displayDefs.h`
(five `int`, `void *`, two enums, `char[64]`, `unsigned`, `void *`, six `int`,
`unsigned`, `unsigned[1]`), and that the 136 bytes this mapping implies is one
of the terms in the 552 total that matches. The encoding carries types and
order, not field names; types and order are what fix the layout.

## Discovery (Task 2)

IDA Professional 9.2, via `binrecon analyze`, partitions `__text` into exactly
the fifteen functions at exactly the fifteen start addresses the plan's table
names. **Two of the names differ from the plan's**, and both differences are
real, not IDA artefacts:

- entry 0 is printed without its category, as
  `-[IOFrameBufferDisplay initUnnamedFromDeviceDescription:]`; the category
  `UnnamedInitialization` is in `__OBJC,__class_names`+47 and in the
  `__OBJC,__category` record, not in the method list IDA names from.
- entry 2312 is `+[VBE20DisplayDriverVersion driverKitVersionForVBE20DisplayDriver]`,
  not `+[VBE20DisplayDriver ...]`. The binary has **three** classes, named in
  `__OBJC,__class_names` at +0 `VBE20DisplayDriver`, +90
  `VBE20DisplayDriverVersion` and +125
  `VBE20DisplayDriverKernelServerInstance`. `VBE20DisplayDriver`'s metaclass
  (`__OBJC,__meta_class` @16588) carries `methodLists` addend `0x0` -- no class
  methods at all -- while `VBE20DisplayDriverVersion`'s metaclass (@16628) has
  addend `0x4144` and `VBE20DisplayDriverKernelServerInstance`'s (@16668) has
  `0x4158`. Those are the two 20-byte lists in `__OBJC,__cls_meth` (addr
  16708, size 40): the list at 16708 holds `driverKitVersionForVBE20DisplayDriver`
  (types `i8@8:12`, IMP 2312) and the list at 16728 holds `kernelServerInstance`
  (types `^^{?}8@8:12`, IMP 2300). `docs/drivers/video-reconstruction.md:27`
  records this three-class convention.

IDA's sizes are instruction extents and exclude the 4-byte function alignment
padding, so eight of them read 1-3 bytes short of the symbol-to-symbol deltas
in that table (142/545/187/674/7/7/242/98 against 144/548/188/676/8/8/244/100).
The padding is `90` nops -- e.g. `text+689..691` is `90 90 90` before
`parseVESAModes:size:` at 692.

The committed maps in this tree record the instruction extent, so the padding
shows up as a gap between entries. Checked, rather than assumed, across all 56
committed `source-map.json` files by sorting each map's entries and measuring
`next.address - (address + size)`: all **31** i386 maps contain gaps of 1-3
bytes; none of the 25 ppc maps does, which is what a 4-byte-wide instruction
set gives. So the convention holds for every i386 precedent. The last entry
here still ends at 2324.

Answers below are from the reference's disassembly unless a paragraph says
otherwise. Two answers lean on binaries outside the driver -- the 4.2 booter
(D1, `VBEModeRec`) and the 4.2 kernel's i386 slice (D2). Where they do, the
binary is identified by SHA-256 and the evidence is quoted at `boot+N` or at
its kernel virtual address, so it can be re-read without redoing the
disassembly. Neither binary is committed; both come out of
`OS42MachUserPatch4.tar` via `vm/extract-os42-patch.py`.

### D1: where `parseVESAModes:size:` gets its mode array

From two literal immediates in `initFromDeviceDescription:`, neither of which
carries a relocation:

```
  text+654  6880080000       push 880h      ; size  = 2176
  text+659  6870280100       push 12870h    ; modes = 0x12870
  text+664  8B0D3C400000     mov  ecx, ds:[403Ch]  ; __message_refs+40,
                                                   ; "parseVESAModes:size:"
  text+670  51 53            push ecx / push ebx
  text+672  E85BFDFFFF       call _objc_msgSend
```

So `[self parseVESAModes:(VBEModeRec *)0x12870 size:0x880]`. Neither immediate
is relocated, and the contrast that makes that meaningful is inside this same
function: **all seven of its `__cstring` pushes carry a relocation, and these
two pushes do not.**

The seven pushes and their relocations, with the string each resolves to:

| push at | bytes | reloc at | `__cstring` | string |
| --- | --- | --- | --- | --- |
| 294 | `68 1e090000` | 295 | +10 | `VBEDisplay: Error in setMemoryRangeList (%s)\n` |
| 388 | `68 4c090000` | 389 | +56 | `VBEDisplay0` |
| 423 | `68 58090000` | 424 | +68 | `%s: VESA video driver initialization.\n` |
| 460 | `68 7f090000` | 461 | +107 | `%s: Skipping framebuffer initialization (card not in VBE mode).\n` |
| 484 | `68 c0090000` | 485 | +172 | `%s: Driver loaded to export VBE mode list.\n` |
| 580 | `68 ec090000` | 581 | +216 | `%s: Unable to map frame buffer\n` |
| 641 | `68 0c0a0000` | 642 | +248 | `%s: using VBE mode %d\n` |
| **654** | `68 80080000` | **none** | -- | immediate 0x880 |
| **659** | `68 70280100` | **none** | -- | immediate 0x12870 |

Each reloc sits on the push's 4-byte operand, one byte past the `68` opcode.

To reproduce the list: read `__TEXT,__text`'s `reloff` / `nreloc` from the
Mach-O load commands (35096 / 169), decode each 8-byte `relocation_info`, and
keep the entries whose `r_address` falls in 144..692. There are 49; the seven
above are exactly the ones with `r_extern` 0 and `r_symbolnum` 2, the section
ordinal of `__cstring`.

Nothing lands at 655 or 660, so 0x12870 and 0x880 are compile-time constants,
not symbols the link resolves. The same is true of every other reference to
that region: `push 12858h` at 519 and 1732, `lea eax, ds:12870h[eax*8]` at
1687, and the absolute loads at 161, 175, 181, 188 and 616 are all unrelocated.

A single 24-byte record sits immediately before the array, at 0x12858, and is
passed to `initDisplayInfo:fromVBEModeInfo:` at `__text` 519..533. 0x12870 -
0x12858 = 0x18, one record.

The array stride is 24, twice over:

```
  text+740  8B1504200000     mov  edx, ds:[2004h]       ; displayModeCount
  text+746  42               inc  edx
  text+747  8D0452           lea  eax, [edx+edx*2]      ; 3*(count+1)
  text+750  C1E003           shl  eax, 3                ; 24*(count+1)
  text+753  39D8             cmp  eax, ebx              ; against size
  text+755  7311             jnb  <stop>
  ...
  text+852  8D347F           lea  esi, [edi+edi*2]
  text+855  C1E603           shl  esi, 3                ; esi = 24*i
```

and the loop terminates on `word ptr [modes + 24*i + 4] == 0` (`text+730` for
i=0, `text+766` for the rest).

**What fills that memory is the booter, and the stores are located.** This is
the one answer that needed a cross-reference outside the driver.

The booter is the 4.2 one, SHA-256
`925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE`, 44848
bytes, extracted (not committed) with

```
vm/extract-os42-patch.py OS42MachUserPatch4.tar DEST ./usr/standalone/i386/boot
```

**Address calibration.** The image is headerless: text addresses equal file
offsets, data addresses are file offset + 0x3000. The delta is fixed by
resolving four string pointers that the code pushes and finding the strings in
the file -- each pair differs by exactly 0x3000:

| pushed address | string found at file offset | delta | string |
| --- | --- | --- | --- |
| 0xd464 | 42084 (0xa464) | 0x3000 | `VESA not available.\n` |
| 0xc956 | 39254 (0x9956) | 0x3000 | `Usable VBE modes:\n` |
| 0xcc96 | 40086 (0x9c96) | 0x3000 | `/private/Drivers/i386` |
| 0xcc89 | 40073 (0x9c89) | 0x3000 | `/usr/Devices` |

The pointer the VBE code dereferences is at address 0xda7c, i.e. file offset
43644. **The four bytes there are `00 10 01 00`, little-endian 0x00011000** --
`KERNSTRUCT_ADDR`; `src/boot-2/i386/libsa/kernBootStruct.h` line 175 gives
Rhapsody the same value. So the chain `0xda7c -> file offset 43644 -> 0x11000`
can be re-walked from the file alone, and:

- 0x11000 + 0x1858 = 0x12858, the booter's own current-mode record;
- 0x11000 + 0x1870 = 0x12870, the mode array;
- 0x880 is that array's byte size.

**The stores.** Every field of every 24-byte record is written by one leaf
function at `boot+27556..27702`, through `ecx` = its first argument:

```
  boot+27563  8B4D08       mov  ecx, [ebp+8]        ; destination record
  boot+27566  8B5510       mov  edx, [ebp+10h]      ; VESA ModeInfoBlock
  boot+27569  668B5D0C     mov  bx,  [ebp+0Ch]      ; mode number
  boot+27573  668919       mov  [ecx+00h], bx       ; <- mode number argument
  boot+27579  66895902     mov  [ecx+02h], bx       ; <- MIB+00h ModeAttributes
  boot+27587  66895904     mov  [ecx+04h], bx       ; <- MIB+12h XResolution
  boot+27595  66895906     mov  [ecx+06h], bx       ; <- MIB+14h YResolution
  boot+27603  66895908     mov  [ecx+08h], bx       ; <- MIB+10h BytesPerScanLine
  boot+27610  88590A       mov  [ecx+0Ah], bl       ; <- MIB+19h BitsPerPixel
  boot+27616  88590B       mov  [ecx+0Bh], bl       ; <- MIB+1Bh MemoryModel
  boot+27622  88590C       mov  [ecx+0Ch], bl       ; <- MIB+1Fh RedMaskSize
  boot+27628  88590D       mov  [ecx+0Dh], bl       ; <- MIB+20h RedFieldPosition
  boot+27634  88590E       mov  [ecx+0Eh], bl       ; <- MIB+21h GreenMaskSize
  boot+27640  88590F       mov  [ecx+0Fh], bl       ; <- MIB+22h GreenFieldPosition
  boot+27646  885910       mov  [ecx+10h], bl       ; <- MIB+23h BlueMaskSize
  boot+27652  885911       mov  [ecx+11h], bl       ; <- MIB+24h BlueFieldPosition
  boot+27693  894114       mov  [ecx+14h], eax      ; <- MIB+28h..2Bh PhysBasePtr
```

Fourteen stores, no store to +0x12, and the destination offsets are exactly the
fourteen `VBEModeRec` fields tabulated below. The four bytes at MIB+28h..2Bh
are assembled byte-by-byte at `boot+27655..27693`
(`shl ebx,18h` / `shl eax,10h` / `shl eax,8` / `or`), which is why the record's
+0x14 is a plain 32-bit physical address.

Both regions are filled by that one function:

```
  boot+27852  8B3D7CDA0000   mov  edi, [0xda7c]
  boot+27858  81C770180000   add  edi, 1870h          ; edi = 0x12870
  ...
  boot+27973  57             push edi                 ; destination
  boot+27974  E859FEFFFF     call boot+27556          ; the record writer
  boot+27979  83C718         add  edi, 18h            ; next record

  boot+28058  8B3D7CDA0000   mov  edi, [0xda7c]
  boot+28064  81C758180000   add  edi, 1858h          ; edi = 0x12858
  ...
  boot+28262  57             push edi
  boot+28263  E838FDFFFF     call boot+27556          ; same writer
```

The enumerator at `boot+27704..28030` walks the VESA `VideoModePtr` list
(`cmp word ptr [ebx+esi*2], 0FFFFh` at `boot+27992`) and carries its own bound:

```
  boot+27895  A17CDA0000     mov  eax, [0xda7c]
  boot+27900  0540180000     add  eax, 1840h
  boot+27905  89FA           mov  edx, edi
  boot+27907  29C2           sub  edx, eax
  boot+27909  89D0           mov  eax, edx
  boot+27911  3D97080000     cmp  eax, 897h
  boot+27916  7752           ja   <stop>
```

which stops once `edi - (base + 0x1840) > 0x897`, i.e. once the record index
exceeds 89. That is the same 90-record ceiling the driver-side arithmetic below
derives from 0x880, reached independently.

The routine the previous revision of this document cited -- `boot+2652..2857`,
which prints `"Usable VBE modes:\n"` -- is a **reader**, not the producer: it
contains no store into the region. It is still useful as an independent reading
of the record layout, and is quoted under `VBEModeRec` below.

The driver reads a `KERNBOOTSTRUCT` member by hard-coded absolute address. For
Tasks 3-7 this means the two immediates must be emitted as plain integer
constants -- no `extern`, no symbol, no relocation -- or byte parity is lost.

One arithmetic note, which is arithmetic and not a measurement: the region runs
[0x1858, 0x1870 + 0x880) = [0x1858, 0x20F0). In *Rhapsody's* `KERNBOOTSTRUCT`,
`char _reserved[7500]` spans 0x38C..0x20D8 and `boot_video video` spans
0x20D8..0x20F0, so the 4.2 block ends exactly where Rhapsody's `boot_video`
ends and overruns Rhapsody's `_reserved` by 24 bytes. The two releases' structs
are therefore not identical across that span. Nothing in this reconstruction
depends on the member's name or on Rhapsody's layout; only on the two literals.

Also note 0x880 is not a multiple of 24 (2176 = 24*90 + 16), so the array holds
at most 90 records and the last 16 bytes are slack the driver's bound check
never lets it reach.

### `VBEModeRec` layout

`descriptionForVBEMode:` (`__text` 2176..2274) names every field it prints, and
the push order fixes which offset each name belongs to. The format string is

```
mode num: %d, Attrib: %x, BytesPerScanline: %d, FrameBuffer: %x,
XRes: %d, YRes: %d, BitsPerPixel: %d, MemoryModel: %d,
RGB Mask Sizes: (%d, %d, %d), RGB Field Pos: (%d, %d, %d)
```

(`__cstring`+932, pushed at `text+2250` as `68 b80c0000`), and the pushes, in
reverse order of issue, are +0, +2, +8, +0x14, +4, +6, +0xA, +0xB, +0xC, +0xE,
+0x10, +0xD, +0xF, +0x11.

The pushes themselves, with `edx` = the `VBEModeRec *` argument loaded at
`text+2179` (`8B5510  mov edx, [ebp+10h]`). Issue order is last-argument-first;
the width of each load is what fixes the field widths:

```
  text+2182  0FB64211  movzx eax, byte ptr [edx+11h]    text+2186  50  push eax
  text+2187  0FB6420F  movzx eax, byte ptr [edx+0Fh]    text+2191  50  push eax
  text+2192  0FB6420D  movzx eax, byte ptr [edx+0Dh]    text+2196  50  push eax
  text+2197  0FB64210  movzx eax, byte ptr [edx+10h]    text+2201  50  push eax
  text+2202  0FB6420E  movzx eax, byte ptr [edx+0Eh]    text+2206  50  push eax
  text+2207  0FB6420C  movzx eax, byte ptr [edx+0Ch]    text+2211  50  push eax
  text+2212  0FB6420B  movzx eax, byte ptr [edx+0Bh]    text+2216  50  push eax
  text+2217  0FB6420A  movzx eax, byte ptr [edx+0Ah]    text+2221  50  push eax
  text+2222  0FB74206  movzx eax, word ptr [edx+06h]    text+2226  50  push eax
  text+2227  0FB74204  movzx eax, word ptr [edx+04h]    text+2231  50  push eax
  text+2232  8B4A14    mov   ecx, dword ptr [edx+14h]   text+2235  51  push ecx
  text+2236  0FB74208  movzx eax, word ptr [edx+08h]    text+2240  50  push eax
  text+2241  0FB74202  movzx eax, word ptr [edx+02h]    text+2245  50  push eax
  text+2246  0FB702    movzx eax, word ptr [edx]        text+2249  50  push eax
```

Five `word` loads, eight `byte` loads, one `dword` load. That gives:

| Offset | Width | Field |
| --- | --- | --- |
| 0x00 | 2 | mode number |
| 0x02 | 2 | attributes |
| 0x04 | 2 | XResolution |
| 0x06 | 2 | YResolution |
| 0x08 | 2 | bytes per scan line |
| 0x0A | 1 | bits per pixel |
| 0x0B | 1 | memory model |
| 0x0C | 1 | red mask size |
| 0x0D | 1 | red field position |
| 0x0E | 1 | green mask size |
| 0x0F | 1 | green field position |
| 0x10 | 1 | blue mask size |
| 0x11 | 1 | blue field position |
| 0x12 | 2 | padding; never read by the driver, never written by the booter |
| 0x14 | 4 | frame buffer physical address |
| | | total 0x18 = 24 |

**0x12 is struct padding, not an unknown field.** The method's own type encoding
in `__OBJC,__meth_var_types`+48 is `*12@8:12^{?=SSSSSCCCCCCCC^v}16`: the
argument is a pointer to `{ unsigned short x5; unsigned char x8; void *; }`.
Five shorts fill 0..9, eight chars fill 0xA..0x11, and the `void *` needs
4-byte alignment, so the compiler inserts two bytes at 0x12 and places the
pointer at 0x14 -- total 0x18. Nothing is missing from the record. The same
encoding appears in `parseVESAModes:size:`
(`v16@8:12^{?=SSSSSCCCCCCCC^v}16I20`, `__meth_var_types`+229) and as the second
argument of `initDisplayInfo:fromVBEModeInfo:` (`__meth_var_types`+163). The
booter's writer skipping +0x12 (above) confirms it from the producer side.

The booter agrees on the **five** offsets it reads, all in the reader routine at
`boot+2652..2857`. It advances two cursors: `ebx`, set to `record + 6` at
`boot+2697` (`81C376180000  add ebx, 1876h` after `mov ebx,[0xda7c]` at
`boot+2652`), and `edi` = `record + 0`, held in `[ebp-0B4h]`:

```
  boot+2703  807B0506       cmp  byte ptr [ebx+5], 6      ; +0Bh memory model = 6
  boot+2714  807B0608       cmp  byte ptr [ebx+6], 8      ; +0Ch red mask size = 8
  boot+2733  0FB703         movzx eax, word ptr [ebx]     ; +06h YResolution
  boot+2737  0FB743FE       movzx eax, word ptr [ebx-2]   ; +04h XResolution
  boot+2742  8BBD4CFFFFFF   mov  edi, [ebp-0B4h]
  boot+2748  0FB707         movzx eax, word ptr [edi]     ; +00h mode number
  boot+2765  66817BFEE703   cmp  word ptr [ebx-2], 3E7h   ; +04h again
  boot+2786  66813BE703     cmp  word ptr [ebx], 3E7h     ; +06h again
  boot+2835  83C318         add  ebx, 18h                 ; stride 24
  boot+2838  83854CFFFFFF18 add  dword ptr [ebp-0B4h], 18h
```

Memory model 6 is VESA's direct-colour model. Both cursors advance by 24, which
is the stride, read from the consumer side this time.

The field names are the reference's own, from that format string. The booter's
writer independently corroborates them by showing which VESA 2.0
`ModeInfoBlock` field each one is copied from, but the record itself is not a
`ModeInfoBlock` -- it is a 24-byte condensation of one.

### D2: `VBEModeInfo2IODisplayInfo`'s signature

`initDisplayInfo:fromVBEModeInfo:` (`__text` 984..1004) is a pure forwarder:

```
   984  55               push ebp
   985  89E5             mov  ebp, esp
   987  8B4510           mov  eax, [ebp+10h]     ; first method argument, info
   990  50               push eax
   991  8B4514           mov  eax, [ebp+14h]     ; second method argument, mode
   994  50               push eax
   995  E818FCFFFF       call _VBEModeInfo2IODisplayInfo
  1000  89EC             mov  esp, ebp
  1002  5D               pop  ebp
  1003  C3               retn
```

**Which frame slot holds which type** is not taken from the selector's wording.
The method's type encoding, `__OBJC,__meth_var_types`+163, is

```
v16@8:12^{?=iiiii^vii[64c]I^viiiiiiI[1I]}16^{?=SSSSSCCCCCCCC^v}20
```

so `self` is at frame 8, `_cmd` at 12, the `IODisplayInfo *` at 16 and the
`VBEModeRec *` at 20 -- i.e. `[ebp+10h]` is the `IODisplayInfo *` and
`[ebp+14h]` is the `VBEModeRec *`. The call site agrees: at `__text` 504..533
the driver issues

```
   504  8B0D30400000   mov  ecx, ds:[4030h]   ; selector "displayInfo"
   512  E8FBFDFFFF     call _objc_msgSend     ; eax = [self displayInfo]
   517  89C6           mov  esi, eax
   519  6858280100     push 12858h            ;   -> fromVBEModeInfo:
   524  56             push esi               ;   -> initDisplayInfo:
   525  8B0D34400000   mov  ecx, ds:[4034h]   ; "initDisplayInfo:fromVBEModeInfo:"
   531  51             push ecx               ; _cmd
   532  53             push ebx               ; self
   533  E8E6FDFFFF     call _objc_msgSend
```

`objc_msgSend` pushes are right to left, so the earlier push (0x12858, a
`VBEModeRec *` by D3) is the *second* method argument and `[self displayInfo]`
(an `IODisplayInfo *`) is the first. The selector addresses come from
`__OBJC,__message_refs`: +28 is `displayInfo` and +32 is
`initDisplayInfo:fromVBEModeInfo:`.

Arguments to the C function are pushed right to left, so the last push is the
first C argument:

```c
void VBEModeInfo2IODisplayInfo(VBEModeRec *mode, IODisplayInfo *info);
```

**The callee confirms both the order and the return type.** `_VBEModeInfo2IODisplayInfo`
is exported by the OPENSTEP 4.2 kernel: `mach_kernel` from the same patch
package (`vm/extract-os42-patch.py PATCH DEST ./mach_kernel`) is a fat binary
whose i386 slice is at offset 835584, length 1117920, SHA-256
`33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890`; its symbol
table puts `_VBEModeInfo2IODisplayInfo` at `0x0019ED8C`. Its prologue reads

```
  0019ED8C  55          push ebp
  0019ED8D  89E5        mov  ebp, esp
  0019ED8F  57 56 53    push edi / esi / ebx
  0019ED92  8B5D08      mov  ebx, [ebp+8]    ; first C argument
  0019ED95  8B750C      mov  esi, [ebp+0Ch]  ; second C argument
  0019ED98  0FB77B04    movzx edi, word ptr [ebx+4]
  0019ED9C  893E        mov  [esi], edi
```

Over the whole function (`0019ED8C..0019EFA6`) `ebx` is only ever *read*, at
+0, +2, +4, +6, +8, +0Ah, +0Bh, +0Ch, +0Dh, +0Eh, +0Fh, +10h, +11h and +14h --
exactly the fourteen `VBEModeRec` fields tabulated above, and never +12h. `esi`
is only ever *written*, at +0, +4, +8, +0Ch, +10h, +14h, +18h, +1Ch, +20h
onward (the `pixelEncoding` characters), +60h, +64h and +68h -- `IODisplayInfo`
offsets. So the first C argument is the `VBEModeRec *` and the second the
`IODisplayInfo *`, as the forwarder implies, and the record's padding byte is
untouched from this side too.

The return type is **inferred** to be `void`: the function's single exit is the
epilogue at `0019EF9D..0019EFA6` (`8D65F4 5B 5E 5F 89EC 5D C3`), and no path
loads `eax` with a *result* before reaching it -- the two paths that arrive
leave `eax` holding a loop temporary (`[ebx+8]` on one, `[ebx+0Ah]-2` on the
other; see `0019EF93 0FB74308` in the listing above). `eax` is therefore
written, but as scratch, so this is an inference from the absence of a
deliberate return value rather than an observation of none. The Objective-C
wrapper's own encoding begins `v`, and the driver ignores any return, so
nothing in this binary would distinguish `void` from an ignored result.

Two further facts, from the driver:

- Its output element is 136 bytes. `parseVESAModes:size:` allocates the array
  with `calloc(count, 0x88)` at `__text` 816..828 -- `6888000000 push 88h` at
  816, `8B0D04200000 mov ecx, ds:[2004h]` at 821, `51 push ecx` at 827,
  `E8BFFCFFFF call` at 828 with the external relocation naming `_calloc` at
  829 -- and indexes it by `136*i` (`shl ebx,4; add ebx,edi; shl ebx,3` at
  867..874). 136 is `sizeof(IODisplayInfo)`, which corroborates Task 1's layout
  from a third direction.
- **It is what writes the VBE mode number into `IODisplayInfo.parameters`, the
  field at +0x64.** The store is in the kernel function:

  ```
    0019EF89  0FB73B    movzx edi, word ptr [ebx]        ; VBEModeRec +00h, mode number
    0019EF8C  897E64    mov  dword ptr [esi+64h], edi    ; IODisplayInfo +64h
  ```

  The driver side is consistent and, on its own, could only have inferred this.
  Recorded so a later reader need not redo it: **`__text` contains 30
  memory-write instructions in total, and none has displacement 0x64** -- the
  full set of write targets is `ds:[2000h]` (1), `ds:[2004h]` (2), `[eax]` (4),
  nine distinct `[ebp-n]` locals (16), `[ebx]` (1), `[ebx+210h/214h/218h/21Ch]`
  (4, the inherited-ivar stores of Task 1), `[esi]` (1) and `[esi+14h]` (1). To
  reproduce: disassemble each of the fifteen functions from its start address
  and collect every instruction with a written memory operand. Since the parsed
  array comes from `calloc`, +0x64 would otherwise have stayed zero, and
  `getCharValues:` reads it back as `VBEModeNumber<n>` (`__text` 1525,
  `8B54D064  mov edx, [eax+edx*8+64h]`) and `VBECurrentMode` (`__text` 1343,
  `8B4064  mov eax, [eax+64h]`), both formatted `%d`.
  `descriptionForDisplayInfo:` prints the same field under the label
  `parameters=%x`.

### D3: what `VBEBooterMode` is

An `IOParameterName` `getCharValues:forParameter:count:` answers, in two forms.
A shared prologue at `__text` 1636..1660 matches the 13-character prefix and
then splits on the character after it:

```
  1636  6A0D           push 0Dh
  1638  68070B0000     push 0B07h              ; __cstring+499 "VBEBooterMode"
  1643  53             push ebx                ; parameterName
  1644  E88FF9FFFF     call _strncmp
  1652  85C0           test eax, eax
  1654  7571           jne  1769               ; no match -> common tail
  1656  807B0D00       cmp  byte ptr [ebx+0Dh], 0
  1660  7446           je   1732               ; NUL -> bare form
```

The common tail at 1769 returns the answer buffer if it was filled and
otherwise falls into `[super getCharValues:forParameter:count:]` at 1852
(`cmp byte ptr [ebp-200h], 0` at 1769, `je 1852` at 1776).

- **the numeric form `"VBEBooterMode<N>"` is `__text` 1662..1727** -- the
  fall-through, taken when the byte at +13 is not NUL. It returns
  `[self descriptionForVBEMode:(VBEModeRec *)(0x12870 + 24*N)]`, with `N` from
  `[self atoi:parameterName+13]` (`8D430D lea eax,[ebx+0Dh]` at 1662, selector
  `__message_refs`+44 at 1666) and the address formed at 1684..1687 by
  `8D0449 lea eax,[ecx+ecx*2]` / `8D04C570280100 lea eax,[eax*8+12870h]`;
- **the bare form `"VBEBooterMode"` is `__text` 1732..1766** -- the branch
  target of the `je` at 1660. It returns
  `[self descriptionForVBEMode:(VBEModeRec *)0x12858]` (`6858280100 push 12858h`
  at 1732) -- the mode the booter left the adapter in.

It is a debugging read-out of the booter's raw VBE data, distinct from the
driver's own `VBEMode<N>` / `VBEModeNumber<N>` / `VBEModeDescription<N>`
parameters, which index the parsed `IODisplayInfo` array instead.

The numeric form is **not** bounds-checked. This is an absence, so here is what
was looked for and what is there instead. The other three indexed parameters
each place a guard between the `atoi:` call and the use of its result:

```
  1417  390D04200000   cmp  ds:[2004h], ecx    ; VBEModeDescription<N>
  1423  0F8654010000   jbe  1769
  1501  390D04200000   cmp  ds:[2004h], ecx    ; VBEModeNumber<N>
  1507  0F8600010000   jbe  1769
  1601  390D04200000   cmp  ds:[2004h], ecx    ; VBEMode<N>
  1607  0F869C000000   jbe  1769
```

The same stretch of `VBEBooterMode<N>` runs straight through with no compare
and no branch:

```
  1677  E86EF9FFFF     call _objc_msgSend      ; eax = [self atoi:name+13]
  1682  89C1           mov  ecx, eax
  1684  8D0449         lea  eax, [ecx+ecx*2]
  1687  8D04C570280100 lea  eax, [eax*8+12870h]
  1694  50             push eax
```

So it reads 24*N bytes past 0x12870 for any N. Reproduce it that way -- the
absence of the check is the reference's behaviour, not an oversight to be
corrected.

The parameter names, in the order the method tests them, are `VBEModeCount`,
`VBECurrentMode`, `VBEModeDescription`, `VBEModeNumber`, `VBEMode`,
`VBEBooterMode`; anything else falls through to
`[super getCharValues:forParameter:count:]` at `__text` 1852..1896.

### D4: are the two 8-byte methods empty

Yes. Both are a bare frame with no body, 7 bytes of instructions plus one byte
of alignment padding:

```
  text+1916  -[VBE20DisplayDriver enterLinearMode]   55 89 E5 89 EC 5D C3
  text+1924  -[VBE20DisplayDriver revertToVGAMode]   55 89 E5 89 EC 5D C3
```

`push ebp; mov ebp,esp; mov esp,ebp; pop ebp; ret`. No argument is touched, no
call is made, nothing is stored. The two `__inst_meth` entries at `__OBJC`
16804 and 16816 name them `revertToVGAMode` and `enterLinearMode` and both
point at the same type encoding, `__meth_var_types`+123 = `v8@8:12`: void
return, `self` and `_cmd` only.

What the disassembly establishes is only that: two empty method bodies, present
in the instance method list. *Why* they were written is not determinable from
the binary, and the obvious guess is wrong in one respect worth recording --
`IOFrameBufferDisplay` already supplies empty implementations of both
(`src/driverkit-3/libDriver/Kernel/IOFrameBufferDisplay.m` lines 1138 and 1146,
declared in `driverkit/IOFrameBufferDisplay.h` lines 76 and 83 as methods
"implemented by subclasses in a device specific way"), so these two override
nothing that would otherwise do anything -- though that is read from *this
tree's* Rhapsody `driverkit-3`, not from 4.2's `IOFrameBufferDisplay`, which is
not available here. Tasks 3-7 need only reproduce them as
empty; no rationale is claimed.

### D5: why the driver ships its own `atoi:`

`__text` 1192..1240 is a bare decimal accumulator over `unsigned int`:

```
  1198  31D2             xor  edx, edx
  1208  8A01             mov  al, [ecx]
  1210  04D0             add  al, 0D0h            ; c - '0'
  1212  3C09             cmp  al, 9
  1214  7712             ja   <done>              ; stop at first non-digit
  1216  8D04D2           lea  eax, [edx+edx*8]
  1219  01D0             add  eax, edx            ; 10*acc
  1221  0FBE11           movsx edx, byte ptr [ecx]
  1224  8D5402D0         lea  edx, [edx+eax-30h]
  1228  41               inc  ecx
```

No sign, no leading whitespace, no base prefix, no overflow handling, no
`errno` -- narrower than C's `atoi`, which is all its four call sites need
(they parse the digits after a fixed parameter-name prefix).

What the binary shows, and all it shows: **the reference's undefined symbol
list contains no integer-parsing routine at all**, so within this binary there
was nothing to call. The complete set of externals this kernel server imports
is

```
_IOLog  _calloc  _sprintf  _strcat  _strcpy  _strncmp  _strncpy
_page_mask  _objc_getOrigClass  _objc_msgSend  _objc_msgSendSuper
_VBEModeInfo2IODisplayInfo  _VBE20DisplayDriver_instance
.objc_class_name_Object  .objc_class_name_IODevice
.objc_class_name_IODisplay  .objc_class_name_IOFrameBufferDisplay
```

Seventeen symbols, every `nlist` entry whose type field is `N_UNDF`: four
superclass references, the kernel-server instance pointer, and twelve
functions/data. Among the twelve are `sprintf` and four `str*` routines
(`_strcat`, `_strcpy`, `_strncmp`, `_strncpy`), but no
`atoi`, `strtol`, `strtoul` or `sscanf`. Whether the 4.2 kernel exported one
and Apple chose not to use it is not determinable from this binary; what is
determinable is that this driver links against none.

It is an Objective-C method rather than a static C function, so its four uses
go through `objc_msgSend` with `__OBJC,__message_refs`+44 (`__text` 1396, 1480,
1580, 1666). Tasks 3-7 must keep it a method; a static C function would change
every one of those call sites.

### Reproduced reference defect: the frame-buffer length uses XResolution

**`initFromDeviceDescription:` sizes the frame buffer with the wrong
dimension.** At `__text` 181..195 it computes

```
  181  0FB70560280100   movzx eax, word ptr ds:12860h   ; +8  bytesPerScanLine
  188  0FB7155C280100   movzx edx, word ptr ds:1285Ch   ; +4  XResolution
  195  0FAFC2           imul  eax, edx
```

that is, `bytesPerScanLine * XResolution`, where the frame buffer's extent is
`bytesPerScanLine * YResolution`. Both operands are absolute loads out of the
booter's current-mode record at 0x12858: 0x12860 is that record's +8 and
0x1285C its +4. The field identification comes from `descriptionForVBEMode:`
above, is corroborated by the booter's writer, and is corroborated a third time
by the kernel: `_VBEModeInfo2IODisplayInfo` computes `IODisplayInfo.memorySize`
for the same record as

```
  0019EF8F  0FB75306   movzx edx, word ptr [ebx+06h]   ; YResolution
  0019EF93  0FB74308   movzx eax, word ptr [ebx+08h]   ; bytesPerScanLine
  0019EF97  0FAFD0     imul  edx, eax
  0019EF9A  895668     mov   [esi+68h], edx
```

-- the same product with +6, where the driver uses +4.

**What consumes the product.** It is not dead; it becomes the mapped length.
`_page_mask` (one of the driver's undefined symbols listed under D5, with
external relocations at `__text` 200, 218 and 226) is used to build a
page-aligned base and a page-rounded length in two stack slots:

```
  198  8B0D00000000   mov  ecx, ds:_page_mask    ; reloc at 200
  204  F7D1           not  ecx
  206  894DEC         mov  [ebp-14h], ecx        ; ~page_mask
  209  21F9           and  ecx, edi              ; edi = frame buffer phys addr (+14h, loaded at 175)
  211  894DF8         mov  [ebp-08h], ecx        ; base   = phys & ~page_mask
  214  89FA           mov  edx, edi
  216  231500000000   and  edx, ds:_page_mask    ; reloc at 218
  222  01D0           add  eax, edx              ; the product + offset-in-page
  224  030500000000   add  eax, ds:_page_mask    ; reloc at 226
  230  2345EC         and  eax, [ebp-14h]
  233  8945FC         mov  [ebp-04h], eax        ; length = round-up(product + offset)
```

That `{base, length}` pair is then handed to two methods:

```
  253  6A01           push 1
  255  8D45F8         lea  eax, [ebp-08h]
  258  50             push eax
  259  8B0D1C400000   mov  ecx, ds:[401Ch]       ; "setMemoryRangeList:num:"
  267  E8F0FEFFFF     call _objc_msgSend         ; [devDesc setMemoryRangeList:&range num:1]
  ...
  538  8B4DFC         mov  ecx, [ebp-04h]        ; length
  541  51             push ecx
  542  8B4DF8         mov  ecx, [ebp-08h]        ; base
  545  51             push ecx
  546  8B0D38400000   mov  ecx, ds:[4038h]       ; "mapFrameBufferAtPhysicalAddress:length:"
  554  E8D1FDFFFF     call _objc_msgSend
```

(`__OBJC,__message_refs`+8 is `setMemoryRangeList:num:` and +36 is
`mapFrameBufferAtPhysicalAddress:length:`; the failure path of the first logs
`__cstring`+10, `VBEDisplay: Error in setMemoryRangeList (%s)\n`, and of the
second `__cstring`+216, `%s: Unable to map frame buffer\n`.)

So the consequence is a real over-map: for every landscape mode the driver
reserves and maps more physical memory than the mode occupies (at 640x480x8,
409600 bytes instead of 307200), and for a portrait mode it would map too
little.

**This is a reproduced reference defect. Task 4 must emit `+4` here, verbatim,
and must not substitute `+6`.** Byte parity is the acceptance criterion for
this reconstruction; correcting the arithmetic would change `0FB7155C280100`
into `0FB7155E280100` and fail it. If the defect is ever to be fixed, that is a
separate, later, deliberately-recorded divergence -- not something Task 4
decides.

### Other observations recorded while answering the above

**`__DATA,__bss` is three static buffers**, 1104 bytes total, and the
relocations fix their boundaries exactly: `+0` is the `modeStringForDisplayInfo:`
buffer, `+80` the `descriptionForDisplayInfo:` buffer, `+592` the
`descriptionForVBEMode:` buffer. So 80, 512 and 512 bytes, declared in that
order.

**`descriptionForDisplayInfo:` skips offset 0x70.** It prints +0x60, +0x64,
+0x68, +0x6C, then +0x74, +0x78, +0x7C, +0x80 -- `flags`, `parameters`,
`memorySize`, `scanRate`, `dotClockRate`, `screenWidth`, `screenHeight`,
`modeUnavailableFlag`. The gap at 0x70 is `_reserved1`, exactly where
`src/driverkit-3/driverkit/displayDefs.h` puts it. Independent confirmation of
Task 1's `IODisplayInfo` mapping, from the reference's own code rather than
from the encoding string.

Its two switches also pin the enum orderings: `bitsPerPixel` 0..5 select
`IO_2BitsPerPixel`, `IO_8BitsPerPixel`, `IO_12BitsPerPixel`,
`IO_15BitsPerPixel`, `IO_24BitsPerPixel`, `IO_VGA` through a jump table at
`__text` 1960 (six entries, relocated to 1984/1992/2000/2008/2016/2024), and
`colorSpace` 0/1/2/5 select `IO_OneIsBlackColorSpace`, `IO_OneIsWhiteColorSpace`,
`IO_RGBColorSpace`, `IO_CMYKColorSpace`.

**`getCharValues:` compares its first two names inline and the rest by call.**
`VBEModeCount` and `VBECurrentMode` are matched with `repe cmpsb` over 13 and 15
bytes -- the name plus its terminator, i.e. an exact match -- while
`VBEModeDescription`, `VBEModeNumber`, `VBEMode` and `VBEBooterMode` call
`_strncmp` with 18, 13, 7 and 13, the name without its terminator, i.e. a
prefix match. The most likely source form is `strcmp` for the first two (which
the compiler expands inline) and `strncmp` for the rest, but that is an
inference about the source, not a fact about the binary; what the binary fixes
is that the first two must compile to an inline compare and the other four to a
call.

**`+driverKitVersionForVBE20DisplayDriver` returns 0x1A4** (420),
build-generated, and `+kernelServerInstance` loads external
`_VBE20DisplayDriver_instance` through the relocation at `__text` 2304, as
Task 1 found.

## Scaffold and first link (Task 3)

First guest build of the scaffold: `make exit=0`, `VBE20DisplayDriver.m` compiled
to `VBE20DisplayDriver.i386.o`, `kl_ld` produced `VBE20DisplayDriver_reloc`
(92316 bytes, SHA-256
`D7F8125A3DFD864BE2244D59A08CEA74B4EC848B45C2C9BAAB75F58BC27740AD`, an unstripped
`-g` build with 1173 stab entries; the reference is stripped, 37984 bytes, 22
symbol entries and no stabs). That size gap is expected and is not a finding.
drvVGA and drvCirrus recorded the same unstripped-versus-stripped difference:
`src/drivers-i386/video/drvVGA/reconstruction/divergences.md`, section "Baseline
and rebuilt build" ("the `VGA_reloc` size difference is expected and is not a
finding"), and
`src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md`,
section "Build and parity" (the extra symbols on our side are "debug artefacts of
an unstripped guest build"). Only the four smallest methods are written; the
other nine functions are missing. How the hash, symbol counts and every offset
below were obtained is under "Reproducing these measurements" at the end of this
section.

**The four methods are byte-identical to the reference.**
`enterLinearMode` and `revertToVGAMode` (`5589e589ec5dc390`, 8 bytes each) match
`__text` 1916..1932 exactly. `displayModeCount` and `displayModes` (12 bytes
each) match `__text` 2276..2300 exactly, including the operands `a1 04200000` and
`a1 00200000`: `vbeDisplayModes` landed at `__data + 0` and `vbeDisplayModeCount`
at `__data + 4` with the declaration order used in `VBE20DisplayDriver.m`, and `__data` is 8
bytes at `0x2000` in both binaries. The 12-byte extents also line up: in the
rebuilt `__text` the four sit at 0x00, 0x08, 0x10, 0x1C and the two
Kernel-Server-generated entries follow at 0x28 and 0x34, the same 12-byte
strides the reference has at 2300 and 2312.

**The reconstruction plan's `VBEModeRec` field order disagreed with the disassembly, and the
header follows the disassembly.** The brief listed `bytesPerScanline` before
`xResolution`/`yResolution` and grouped the three mask sizes before the three
field positions. `descriptionForVBEMode:`'s pushes (see `VBEModeRec` layout
above) put XRes at +4, YRes at +6, BytesPerScanline at +8, and interleave the
colour bytes as red size +0xC, red position +0xD, green size +0xE, green position
+0xF, blue size +0x10, blue position +0x11. The type encoding
`{?=SSSSSCCCCCCCC^v}` fixes only widths and count, so both orders compile, but
only the disassembly's order makes a later `mode->yResolution` load the word at
+6. The header also now says 22 bytes of fields / 24 with padding, not "22
bytes"; the struct is not packed and the pointer forces two bytes at 0x12.
Nothing in this task reads a field, so this changes no bytes yet.

**`_VBEModeInfo2IODisplayInfo` is not in the rebuilt symbol table, and cannot be
yet.** The plan expected it as an undefined external (type `0x01`) at this stage. The
only reference to it in the reference binary is the forwarder
`initDisplayInfo:fromVBEModeInfo:` (Task 5). None of the four methods written in
Task 3 calls it, so the compiler has nothing to emit. Inventing a call to make
the symbol appear would corrupt the parity target, so none was written. What the
link does establish: `kl_ld` leaves undefined externals unresolved rather than
failing -- the rebuilt `_reloc` carries `.objc_class_name_IODevice`,
`.objc_class_name_IOFrameBufferDisplay` and `.objc_class_name_Object` as type
`0x01`, and links cleanly. The undefined-external check belongs to Task 5, after
the forwarder exists. In the reference the symbol is index 11, type `0x01`.

### Evidence that the scaffold matches the reference

Two things beyond the four method bodies were checked byte for byte, because
they are what shows the project files (rather than the source) are right.

- **The whole `Loaded Server` segment is identical.** Each of its four sections
  was extracted from both binaries by the section's file offset and size, and
  the bytes compared: `Server Name` (18 bytes, `VBE20DisplayDriver`) at
  `0x6000`, `Load Commands` (164 bytes, the `WIRE` block; SHA-256
  `78FEAAD1F976BAF28AFE83EC73EC4393BA16F514FEB3EED3E67609FB29FFED7F`) at
  `0x6012`, `Instance Var` (27 bytes, `VBE20DisplayDriver_instance`) at
  `0x60B6` and `Server Version` (1 byte, `2`) at `0x60D1`. All four are equal,
  as are the addresses and sizes. The segment's whole 8192-byte file image
  (`vmsize` and `filesize` both 8192 in both files) is also equal, so the
  padding matches too; that image hashes
  `5FAB75726D09D0788182E9932FE6722290EF99756525EE2D8BC6FC624E121A7A`. This is
  the scaffold's `Load_Commands.sect` (copied unchanged from drvCirrus) and the
  project `NAME` producing this segment; it is a stronger result than matching
  the section sizes alone.
- **`English.lproj/Localizable.strings` is byte-identical to the reference's.**
  The tree's copy, `git show HEAD:` of it, and the reference's
  `English.lproj/Localizable.strings` all hash
  `C2FDA3A61DAE9401149166FBC3E913AB4D605D222AFB109619D4D824AA54AF5A`
  (SHA-256, 87 bytes), and `cmp` reports the two files identical.

### Link differences visible in the first `_reloc`, not caused by any source

These concern build-generated code that the source cannot change, so they are
recorded here for whoever reaches the Kernel Server functions.

- **`_VBE20DisplayDriver_instance`.** In the reference it is an *unallocated
  common*: symbol 10, `N_UNDF | N_EXT` (`n_type` 0x01), `n_sect` 0, `n_value`
  4, and `+kernelServerInstance` reaches it through an `r_extern` relocation
  (`mov eax, 0`, relocation at `__text` 2304 against symbol 10). Our `kl_ld`
  link allocates it as a 4-byte `__DATA,__common` slot at `0x2008` and the same
  instruction is `mov eax, 0x2008` with a section-relative relocation. The
  generated source declares it as an uninitialised file-scope `kern_server_t`
  (`src/driverTools-1/KernelServerProjectType/CreateKLLDInstance.sh:71`), i.e. a
  C common, so the difference is in what each link did with the common, not in
  the source. *Measured:* the reference symbol is in no section, so the
  reference's `__bss` (1104 bytes at `0x2008`) cannot contain it, and the nine
  local relocations from `__text` into `__bss` start at exactly three offsets,
  +0, +80 and +592, the three static buffers Task 2 found. *Inferred, not
  shown:* that those three buffers fill `__bss` and nothing else does. The third
  buffer's 512 bytes is `1104 - 592`, the remainder to the end of the section,
  not a boundary any relocation marks. So "the reference's `__bss` is exactly the
  three static buffers" is consistent with an unallocated instance common but is
  not demonstrated by it. *Unidentified:* why our `kl_ld` allocates the common
  and the reference's link did not; no link flag was tried in Task 3.
- **Version string: cause unidentified.** The reference's `__const` holds one
  160-byte object, symbol `_VBE20DisplayDriver_reloc_vers`: a 118-character
  string with no trailing newline, then zero bytes to 160.

  ```
  @(#)PROGRAM:VBE20DisplayDriver_reloc  PROJECT:drvVBE20DisplayDriver-1  DEVELOPER:cfriesen  BUILT:NO DATE SET (-B used)
  ```

  Ours is 112 bytes: a 101-character string plus a trailing newline (symbol
  `_VBE20DisplayDriverVersionString`, `0x40`), then an 8-byte double 1.0 (symbol
  `_VBE20DisplayDriverVersionNumber`, `0xA8`).

  ```
  @(#)PROGRAM:VBE20DisplayDriver  PROJECT:VBE20DisplayDriver-1  DEVELOPER:root  BUILT:09/20/26 10:43:45
  ```

  What differs: the symbol name; the `PROGRAM` field (`_reloc` suffix); the
  `PROJECT` field (`drv` prefix); `DEVELOPER`; `BUILT` (a `-B` placeholder
  against a real date); the trailing newline; and the object shape (one
  160-byte string against a string plus a double). `DEVELOPER` and `BUILT` are
  build-environment values (the builder's user name, and the clock or a `-B`
  placeholder), not anything the driver source controls; drvCirrus recorded the
  same about its own version bytes
  (`src/drivers-i386/video/drvCirrusLogicGD5434/reconstruction/divergences.md`,
  section "What is not reconstructed").

  **The cause of the rest is unidentified. Do not edit `VERSIONING_SYSTEM` on
  this evidence.** Our version symbols come from `VERSIONING_SYSTEM =
  apple-generic`, copied from Cirrus, so that setting is the obvious suspect,
  but the reference's own string uses the same four-field
  `PROGRAM / PROJECT / DEVELOPER / BUILT` layout as ours, so the setting is
  unlikely to explain the differences. What was ruled out, and what was not:

  - The layout is not a difference; both are that four-field format.
  - `next-sgs` does not reproduce the reference. `src/pb_makefiles-1/next-sgs.make`
    names the symbol `_<name>_VERS_STRING`, which is what drvCirrus's
    *reference* carries (`.../drvCirrusLogicGD5434/reconstruction/divergences.md`,
    section "Static storage"); this reference's `_<name>_vers` is a third
    convention.
  - `src/Commands/bootstrap_cmds/vers_string.csh` reproduces two things: its `-B`
    flag prints exactly `NO DATE SET (-B used)`, and its `-c` mode declares a
    160-byte `SGS_VERS[160]` array, the size of this object. But `-c` puts a
    trailing `\n` in the string, which the reference lacks. drvCirrus's
    reference string does have that newline and a real date, so the two
    references were not made the same way.
  - So the leading suspect is a different generation of the version tool, or a
    different symbol-naming step (the `_vers` suffix and the missing newline).
    That is a lead, not a finding: it was not tested, and the cause is
    unidentified. The related record for drvCirrus's version symbols is the
    paragraph "Task 3, `VERSIONING_SYSTEM` retries" in the same Cirrus file
    (`apple-generic` produced `..VersionString` / `..VersionNumber`; the
    SGS-named symbols stayed unmet).
- **`+driverKitVersionForVBE20DisplayDriver`'s constant: the cross-release
  difference, and it must stay.** The reference returns `0x1A4` = 420
  (`b8 a4010000` at `__text` 2315, immediate at 2316..2319); the rebuilt method
  returns `0x1F4` = 500 (`b8 f4010000` at `0x37`, immediate at `0x38..0x3B`). It
  is the only differing byte in that method (`a4` against `f4`). The method is
  emitted by the Kernel Server project type, not by any source of ours:
  `src/driverTools-1/KernelServerProjectType/CreateKLLDInstance.sh` (lines 95-97)
  generates `+driverKitVersionFor<name>` as `return IO_DRIVERKIT_VERSION;`, and
  `IO_DRIVERKIT_VERSION` is `500` (`0x1F4`) at
  `src/driverkit-3/driverkit/IODevice.h:45`. In DriverKit 4.2 it was `420`
  (`0x1A4`), which is the reference's constant. The 4.2 header is not in this
  tree; the 420 side rests on the reference's own constant and on the
  maintainer's ruling below. So the difference is the cross-release difference
  appearing exactly where it should. **Ruling (maintainer, Task 3 review): it
  must stay.** Forcing 420 would falsify the build. The ledger entry for this
  method is `control-flow-confirmed`, never `assembly-matched`. The ruling covers
  this method only; the instance-common difference above has not been ruled on.

### Scaffold choices not dictated by the reference

- `DriverInfo` `DRIVER_NAME` is `"VBE20DisplayDriver"`. The plan's table did not
  list it, but leaving Cirrus's value would put the wrong installer name in this
  driver. `DEFAULT_DRIVER_VERSION` is left as copied.
- `English.lproj/Help/` is an empty directory in the patch, so `Help` is not in
  `LOCAL_RESOURCES` and no directory was created for it.
- `English.lproj/DisplayInspector.nib` is in the reference bundle and is not
  reproduced here; spec section 2 puts the inspector out of scope.
- The section ordinals inside the `__text` relocations differ (`__data` is
  section 3 in the rebuilt file, 4 in the reference) only because `__cstring` is
  not yet emitted; they converge once the functions that own string literals
  exist.

### Guest tooling notes

- The guest's `/build/source/vm/build-i386-video-recon.sh` was stale (5241
  bytes, no VBE20 arm). The current script was streamed into `/tmp` on the guest
  and run from there, leaving the shared guest copy alone.
- The documented tar pull (`ssh ... | tar xf -` through `cmd /c` with
  `Invoke-RhapRemote`-style `-tt`) failed with "This does not look like a tar
  archive". Running `ssh -T` with stdout redirected to a file by `Start-Process`
  and extracting from the file worked and gave a byte-exact 92316-byte `_reloc`.

### Reproducing these measurements

Every symbol, section, relocation and hash cited in this section was read with
a short Python script that uses only `struct` and `hashlib` (no binrecon, no IDA)
on the two files below. Nothing here needs the guest.

- **Reference:** `VBE20DisplayDriver_reloc`, 37984 bytes, SHA-256
  `9FBC2CAFBDD0124CC63B902161C86BBFEC0EF48D591DDA681A325FF7B68DADED`
  (Conventions, above).
- **Rebuilt:** `out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc`,
  92316 bytes, SHA-256
  `D7F8125A3DFD864BE2244D59A08CEA74B4EC848B45C2C9BAAB75F58BC27740AD`. `out/` is
  gitignored, so this file is not in the repository. The hash identifies this one
  build only: `__const` embeds the build time (`BUILT:09/20/26 10:43:45`), so
  rebuilding identical source gives a different hash. Compare the extents and
  bytes instead, not the hash.
- **Symbol dump.** Both are 32-bit little-endian Mach-O files with a 28-byte
  header; `ncmds` is the `uint32` at byte 16. Walk the load commands
  (`cmd`, `cmdsize` at each step). `LC_SEGMENT` (`cmd` 1) has the segment header
  at +8 (56 bytes to the first section) and then 68 bytes per section
  (`sectname`, `segname`, `addr`, `size`, `offset`, `align`, `reloff`, `nreloc`,
  `flags`, two reserved), which gives every section's address, size, file offset
  and relocation table. `LC_SYMTAB` (`cmd` 2) gives `symoff`, `nsyms`, `stroff`,
  `strsize` at +8. Each `nlist` is 12 bytes, `struct.unpack('<IBBHI')` =
  `n_strx, n_type, n_sect, n_desc, n_value`, and the name is the NUL-terminated
  string at `stroff + n_strx`. Entries with `n_type & 0xE0` set are stabs and
  were skipped. That leaves 22 entries in the reference (it has no stabs) and 17
  in the rebuilt file (which has 1173 stabs, 1190 entries in all). The type
  values quoted above are `n_type` verbatim: `0x0E` local in a section, `0x0F`
  external in a section, `0x03` absolute external, `0x01` undefined external
  (with a nonzero `n_value`, a common).
- **Relocations.** Each entry is 8 bytes at `reloff`, two `uint32`. If bit 31 of
  the first word is set it is scattered (the reference has three, all into
  `__OBJC`, none into `__bss`). Otherwise the first word is `r_address` and the
  second is `r_symbolnum` (low 24 bits), `r_pcrel` (bit 24), `r_length`
  (bits 25-26), `r_extern` (bit 27), `r_type` (bits 28-31). For a local
  relocation (`r_extern` 0), `r_symbolnum` is the target section's ordinal,
  counted from 1 across all sections in load order (`__bss` is 5 in the
  reference), and the 4-byte operand at `r_address` is the target address. The
  three `__bss` offsets, +0, +80 and +592, are those operands minus `0x2008`
  over the nine local relocations whose `r_symbolnum` is 5.
- **Comparing sections.** `Loaded Server` bytes were compared as
  `file[offset:offset+size]` for each section, and the segment as
  `file[fileoff:fileoff+filesize]` from the `LC_SEGMENT` header.
