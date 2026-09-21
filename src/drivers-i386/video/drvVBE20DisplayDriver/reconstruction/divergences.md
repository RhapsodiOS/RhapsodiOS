# drvVBE20DisplayDriver divergences

## Measurement: inherited ivar chain (Task 1)

The reference declares no ivars of its own — `__OBJC,__instance_vars` is 0
bytes — so its `instance_size` of 552 measures OPENSTEP 4.2's
`Object` + `IODevice` + `IODirectDevice` + `IODisplay` + `IOFrameBufferDisplay`
chain exactly. `IODisplay` inherits from `IODirectDevice`, not `IODevice`
(`IODisplay.h`: `@interface IODisplay: IODirectDevice`; `IODirectDevice.h`:
`@interface IODirectDevice : IODevice`), so the plan's four-class chain omits
one link. Without `IODirectDevice` the sum is 520, not 552.

Rhapsody's same chain measures 552 bytes. i386 sizes: pointers, `id`, `int`,
enums and `port_t` are 4 bytes, `IOString` is `char[80]`
(`driverTypes.h`, `IO_STRING_LENGTH` 80), `IOPixelEncoding` is `char[64]`.

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
- `initUnnamedFromDeviceDescription:` (the category method at `__text` 0) stores
  `-1` at `+0x214`, `-1` at `+0x210`, `-1` at `+0x218` and `0` at `+0x21c`. In
  the layout above those are `_pendingDisplayMode` (532), `_currentDisplayMode`
  (528), `_displayModeCount` (536) and `_displayModes` (540), in the order
  `IOFrameBufferDisplay.m` line 748 (`_currentDisplayMode = _pendingDisplayMode
  = -1;`) and 749 (`_displayModeCount = -1; _displayModes = NULL;`) compile to.

The chain did not move between releases. Parity target for this reconstruction
is byte-parity throughout.

`displayModes` and `displayModeCount` do not read inherited ivars: they return
the file statics at `__data` `0x2000` and `0x2004`, which `parseVESAModes:size:`
fills. The one function that touches inherited ivars is
`initUnnamedFromDeviceDescription:`, and its four displacements match
Rhapsody's.

`IODisplayInfo` is layout-identical across the two releases; see the plan's
Global Constraints for the field-by-field mapping.
