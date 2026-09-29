# Interceptor release differences

The DR2 i386 and PowerPC slices have identical sets of 232 named Objective-C method symbols. Compared with the newer primary PowerPC framework, the only additional named Objective-C methods are:

- `+[NSDirectPalette defaultColorPalette]`
- `+[NSDirectPalette defaultGrayPalette]`

DR2 has no named Objective-C method symbol missing from the newer image. This symbol comparison does not prove that shared method bodies, C exports, data layouts, protocol descriptors, or IPC behavior are identical. Those remain to be checked.

Static body review has also found one shared-method behavior difference:
`-[NSFramebuffer screenBounds]` reports origin `(1,1)` in the primary PPC
framework and `(0,0)` in DR2 i386, with pixel dimensions in both. The shared
source preserves this observed CPU distinction. Runtime confirmation remains
pending.

`+[NSDirectPalette defaultColorPalette]` and `+[NSDirectPalette defaultGrayPalette]` are compiled for PowerPC only, matching the newer reference's method inventory. DR2 i386 has only `defaultPalette`; its implementation uses the 256-color table. The PowerPC palette source has separate pseudo-color and grayscale defaults. Runtime comparison remains pending.
