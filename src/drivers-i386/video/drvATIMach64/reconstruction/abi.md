# drvATIMach64 ABI recovery

Reference: `ATIMach64DisplayDriver_reloc`, SHA-256
`AA9884B8F9F68DB733237241D88FCC1FF252A59E9B0EA1CD029695F37465EA3C`.
Method signatures below use IDA 9.4 Hex-Rays types and i386 call-site/access
evidence. Objective-C `self` and selector arguments are omitted from the
declarations.

## `ATI` object

Superclass: `IOFrameBufferDisplay`; reference inherited instance extent: 552
bytes. The subclass instance extent is 620 bytes. Ivar order, offsets, and
reference type encodings:

| Offset | Ivar | Encoding |
| ---: | --- | --- |
| 552 | `redTransferTable` | `^I` |
| 556 | `greenTransferTable` | `^I` |
| 560 | `blueTransferTable` | `^I` |
| 564 | `transferTableCount` | `i` |
| 568 | `brightnessLevel` | `i` |
| 572 | `modeNumber` | `i` |
| 576 | `vram` | `^v` |
| 580 | `vramBytes` | `I` |
| 584 | `currentState` | `i` |
| 588 | `isPCI` | `c` |
| 592 | `atiBios` | `@` |
| 596 | `queryData` | `^v` |
| 600 | `queryDataSize` | `I` |
| 604 | `supportsGamma` | `c` |
| 605 | `supportsGrey256` | `c` |
| 608 | `colorConfig` | `i` |
| 612 | `fbMapStyle` | `i` |
| 616 | `ramdacStyle` | `i` |

Recovered handwritten selectors declared in `ATIPrivate.h`:

| Selector | Return and explicit arguments |
| --- | --- |
| `initFromDeviceDescription:` | `id (id)` |
| `free` | `id ()` |
| `enterLinearMode` | `void ()` |
| `revertToVGAMode` | `void ()` |
| `displayModeCount` | `unsigned int ()` |
| `displayModes` | `IODisplayInfo * ()` |
| `displayMemorySize` | `unsigned int ()` |
| `setPendingDisplayMode:` | `char (int)` |
| `getQueryData` | `int ()` |
| `parseModeString:` | `int (const char *)` |
| `updateModeList` | `void ()` |
| `isModeValid:` | `unsigned int (int)` |
| `verifyMemoryMap` | `char ()` |
| `changeHardwareMapping:` | `int (unsigned int)` |
| `changeTableMapping:` | `int (unsigned int)` |
| `setGammaTable` | `id ()` |
| `setBrightness:token:` | `id (int, int)` |
| `setTransferTable:count:` | `id (const unsigned int *, int)` |

## `ATI_BIOS` object and call buffer

Superclass: `Object`; instance extent: 16 bytes. Ivars: `initialized` (`c`) at
4, `segmentBase` (`I`) at 8, and `_priv` (`^v`) at 12. `_priv` points to a 36
byte allocation with four 8-byte saved descriptor slots followed by a 4-byte
saved stack pointer.

`ATIBIOSRegisters` is a 48-byte byte-compatible call buffer. Bytes 0-3 remain
reserved; EAX, EBX, ECX, EDX, EDI, ESI, and EBP are at offsets 4, 8, 12, 16,
20, 24, and 28. Code/data selectors are 16-bit fields at 32/34; ES, flags, and
entry offset are at 36, 40, and 44. The descriptor record is eight bytes
(`limit` at 0 and `base` at 4). See `ATIBIOSTypes.h` for compile-time pins.

`ATI_BIOS.h` declares the recovered BIOS selectors with Hex-Rays return types
and explicit argument widths. The two CRTC loader selectors share a
six-argument signature. BIOS service methods return `int`; setup and restore
methods return `void`; initializers and `free` retain Objective-C object
returns.

## BIOS transition and memory protection

`ATIbios16` rejects entry offsets above `0xffff` before changing the transfer
buffer, then moves the target selector/offset into globals consumed by
`__bios16`. The assembly saves the current stack state, switches to the
16-bit BIOS stack, patches the immediate far-jump operand, and returns through
the continuation after the transfer. `__ATIbios32` saves the caller state,
patches its far-call operand from the 48-byte register buffer, performs the
BIOS call, and copies the returned registers and flags back. Its native test
fixture replaces only this privileged assembly entry; it never executes the
far transfer in a host process.

The code-segment descriptor points at `__bios16` using
`KERNEL_LINEAR_BASE + __bios16`; optional BIOS data and stack descriptors use
the kernel's `VM_MAX_KERNEL_ADDRESS` translation. These values are defined in
`machdep/i386/pmap.h` and `mach/i386/vm_param.h`, and the GDT is exported by
`machdep/i386/gdt.h`. Runtime operand patching is supported by the loader:
`kernload-1/kern_loader/obj.c` applies `vm_protect(..., VM_PROT_ALL)` to the
entire executable mapping. The far operands therefore remain runtime-patched
as in the reference rather than being converted to static relocations.

## Conversion routines

| C symbol | Recovered signature |
| --- | --- |
| `_displayInfoToColorSpace` | `int (const IODisplayInfo *)` |
| `_colorDepthToColorSpace` | `int (int)` |
| `_displayInfoToColorDepth` | `int (const IODisplayInfo *)` |
| `_memSizeToBytes` | `unsigned int (unsigned char)` |

The C spellings omit the Mach-O leading underscore. The first and third
helpers log and panic on unsupported pixel depths. `memSizeToBytes` maps codes
0-4 to 512 KiB, 1 MiB, 2 MiB, 4 MiB, and 6 MiB; all other byte codes return 2
MiB.

## Display record layout

`IODisplayInfo` is 136 bytes under the target i386 ABI. In particular,
`pixelEncoding` begins at 32, `parameters` at 100, and
`modeUnavailableFlag` at 128. The target C compiler is unavailable on this
Windows host, so compile-time assertions and mock C tests are staged in the
project but not yet executed here; the Python fixture checks compare every
mode scalar, CRTC byte, gamma byte, and value-name row to the IDA export.
