# DR2 i386 shape cross-check

The DR2 i386 reference confirms the same signed-short event representation:
`_empty_shape` at `0x47A0A0DC` writes `-32768, 2, 32767`, and `_rect_shape` at
`0x47A0A100` builds the same scanline form as PPC. `_union_shape`,
`_intersect_shape`, and `_difference_shape` allocate an initial 0x40-byte
output buffer and grow it while walking the two inputs, consistent with the
PPC sweep and adjacent-band merge. `-[NSShape initFromRect:]` is at
`0x47A0AAD8`; `-[_NSShapeEnumerator nextRect]` at `0x47A0AEF8` walks each
band's x-edge pairs and advances to the next y event after the last pair.

This is static cross-architecture evidence only. No runtime comparison or
rebuilt i386 execution is available on the current host.

The i386 `-[NSShape description]` uses the same class/address header,
tab-indented rectangle lines, and closing `);` as the PPC image. `NSShape.m`
contains the shared implementation; runtime output comparison remains
pending.
