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

Implement and test both newer palette methods on both CPU builds. Compare i386 behavior for them with the newer PowerPC reference, not with their absence in DR2.
