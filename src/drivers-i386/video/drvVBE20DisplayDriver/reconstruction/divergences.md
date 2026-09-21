# drvVBE20DisplayDriver divergences

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
names, with the plan's names. IDA's sizes are instruction extents and exclude
the 4-byte function alignment padding, so eight of them read 1-3 bytes short of
the symbol-to-symbol deltas in that table (142/545/187/674/7/7/242/98 against
144/548/188/676/8/8/244/100). Every committed source map in this tree records
the instruction extent, so the padding shows up as a gap between entries; the
last entry still ends at 2324.

Answers below are from the reference's disassembly unless a paragraph says
otherwise. Where an answer leans on the 4.2 booter, that is stated and the
booter evidence is quoted.

### D1: where `parseVESAModes:size:` gets its mode array

From two literal immediates in `initFromDeviceDescription:`, neither of which
carries a relocation:

```
  text+654  6880080000       push 880h      ; size  = 2176
  text+659  6870280100       push 12870h    ; modes = 0x12870
  text+664  8B0D3C400000     mov  ecx, ds:paParsevesamodes
  text+670  51 53            push ecx / push ebx
  text+672  E85BFDFFFF       call _objc_msgSend
```

So `[self parseVESAModes:(VBEModeRec *)0x12870 size:0x880]`. The relocation
table has entries at 642, 647, 666 and 673 and none at 655 or 660, so 0x12870
and 0x880 are compile-time constants, not a symbol the link resolves. The same
is true of every other reference to that region: `push 12858h` at 519 and 1732,
`lea eax, ds:12870h[eax*8]` at 1687, and the absolute loads at 161, 175, 181,
188 and 616 are all unrelocated.

A single 24-byte record sits immediately before the array, at 0x12858, and is
passed to `initDisplayInfo:fromVBEModeInfo:` at `__text` 519..533. 0x12870 -
0x12858 = 0x18, one record.

The array stride is 24, twice over:

```
  text+740  8B1504200000     mov  edx, ds:__count
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

**What fills that memory is the booter.** This is the one answer that needed a
cross-reference outside the driver. In the 4.2 booter (SHA-256
`925D35B683644CDA6C090B223B00C115F1C83116D466F230B71231B7AB75CBCE`, 44848
bytes, extracted with `vm/extract-os42-patch.py` and not committed), addresses
and file offsets coincide in the text and differ by 0x3000 in the data:

```
  boot+2652  8B1D7CDA0000     mov  ebx, dword ptr [0xda7c]
  boot+2658  8DBB70180000     lea  edi, [ebx + 0x1870]
  boot+2670  6856C90000       push 0xc956                 ; "Usable VBE modes:\n"
  ...
  boot+2835  83C318           add  ebx, 18h               ; stride 24, again
  boot+2838  83854CFFFFFF18   add  dword ptr [ebp-0B4h], 18h

  boot+28058 8B3D7CDA0000     mov  edi, dword ptr [0xda7c]
  boot+28064 81C758180000     add  edi, 1858h
```

and the global at address 0xda7c (file offset 43644) is initialised to
0x00011000, which is `KERNSTRUCT_ADDR` -- `src/boot-2/i386/libsa/kernBootStruct.h`
line 175 gives Rhapsody the same value. So:

- 0x11000 + 0x1858 = 0x12858, the booter's own current-mode record;
- 0x11000 + 0x1870 = 0x12870, the mode array;
- 0x880 is that array's byte size.

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

and the pushes, in reverse order of issue, are +0, +2, +8, +0x14, +4, +6, +0xA,
+0xB, +0xC, +0xE, +0x10, +0xD, +0xF, +0x11. That gives:

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
| 0x12 | 2 | never read anywhere in `__text` |
| 0x14 | 4 | frame buffer physical address |
| | | total 0x18 = 24 |

The booter agrees on the three offsets it touches: `cmp byte ptr [ebx+5], 6`
and `cmp byte ptr [ebx+6], 8` with `ebx` = element + 6 are the memory model
(6 = direct colour) at +0xB and the red mask size at +0xC, and `[ebx-2]` /
`[ebx]` are XRes at +4 and YRes at +6.

The field names are the reference's own, from that format string. They are not
inferred from the VESA 2.0 `ModeInfoBlock`, which this record is not -- it is a
24-byte condensation of it.

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

Arguments are pushed right to left, so the last push is the first C argument:

```c
VBEModeInfo2IODisplayInfo(VBEModeRec *mode, IODisplayInfo *info);
```

The argument *order* is established; the *return type* is not. `eax` is never
examined after the call and the Objective-C method's own encoding makes it
`void`, so the C function may return anything. Declare it `void` unless the 4.2
kernel says otherwise.

Two further facts about it, both from the driver:

- Its output element is 136 bytes. `parseVESAModes:size:` allocates the array
  with `calloc(count, 0x88)` at `__text` 816..828 and indexes it by
  `136*i` (`shl ebx,4; add ebx,edi; shl ebx,3` at 867..874). 136 is
  `sizeof(IODisplayInfo)`, which corroborates Task 1's layout from a third
  direction.
- It writes the VBE mode number into `IODisplayInfo.parameters`, the field at
  +0x64. `descriptionForDisplayInfo:` prints `[edx+64h]` under the label
  `parameters=%x`; `getCharValues:` answers `VBEModeNumber<n>` with
  `displayModes[n]` at +0x64 formatted `%d` (`__text` 1525) and `VBECurrentMode`
  with `[[self displayInfo] + 64h]` the same way (`__text` 1343). The driver
  never writes that field itself, so the external function must.

### D3: what `VBEBooterMode` is

An `IOParameterName` `getCharValues:forParameter:count:` answers, in two forms
(`__text` 1636..1727 and 1732..1766):

- exactly `"VBEBooterMode"` (`cmp byte ptr [ebx+0Dh], 0` at 1656 takes this
  branch) returns `[self descriptionForVBEMode:(VBEModeRec *)0x12858]` -- the
  mode the booter left the adapter in;
- `"VBEBooterMode<N>"` returns
  `[self descriptionForVBEMode:(VBEModeRec *)(0x12870 + 24*N)]`, with `N` from
  `[self atoi:parameterName+13]` and the address formed by
  `lea eax,[ecx+ecx*2]; lea eax, ds:12870h[eax*8]` at 1684..1687.

It is a debugging read-out of the booter's raw VBE data, distinct from the
driver's own `VBEMode<N>` / `VBEModeNumber<N>` / `VBEModeDescription<N>`
parameters, which index the parsed `IODisplayInfo` array instead.

The numeric form is **not** bounds-checked. The other three indexed parameters
all guard with `cmp ds:__count, ecx; jbe <fail>` (`__text` 1417, 1501, 1601);
`VBEBooterMode<N>` has no such guard, so it reads 24*N bytes past 0x12870 for
any N. Reproduce it that way -- the absence of the check is the reference's
behaviour, not an oversight to be corrected.

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
return, `self` and `_cmd` only. They exist to override `IOFrameBufferDisplay`'s
versions with nothing -- on a VBE linear-framebuffer adapter there is no mode
switch to make.

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

The reason it is hand-written rather than called: **the reference's undefined
symbol list contains no integer-parsing routine at all.** The complete set of
externals this kernel server imports is

```
_IOLog  _calloc  _sprintf  _strcat  _strcpy  _strncmp  _strncpy
_page_mask  _objc_getOrigClass  _objc_msgSend  _objc_msgSendSuper
_VBEModeInfo2IODisplayInfo
```

-- `sprintf` and five `str*` routines, but no `atoi`, `strtol`, `strtoul` or
`sscanf`. Whether the 4.2 kernel exported one and Apple chose not to use it is
not determinable from this binary; what is determinable is that this driver
links against none.

It is an Objective-C method rather than a static C function, so its four uses
go through `objc_msgSend` with `__OBJC,__message_refs`+44 (`__text` 1396, 1480,
1580, 1666). Tasks 3-7 must keep it a method; a static C function would change
every one of those call sites.

### Other observations recorded while answering the above

**`initFromDeviceDescription:` sizes the frame buffer with the wrong
dimension.** At `__text` 181..195 it computes

```
  181  0FB70560280100   movzx eax, word ptr ds:12860h   ; +8  bytesPerScanLine
  188  0FB7155C280100   movzx edx, word ptr ds:1285Ch   ; +4  XResolution
  195  0FAFC2           imul  eax, edx
```

that is, `bytesPerScanLine * XResolution`, where the frame buffer's extent is
`bytesPerScanLine * YResolution`. For every landscape mode this over-maps (at
640x480x8: 409600 instead of 307200) and for a portrait mode it would under-map.
The field identification comes from `descriptionForVBEMode:` above and is
corroborated by the booter. This is the reference's behaviour and must be
reproduced verbatim; do not substitute +6.

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
