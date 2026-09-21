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
