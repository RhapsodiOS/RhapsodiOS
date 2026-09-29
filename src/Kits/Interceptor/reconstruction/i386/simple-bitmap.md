# DR2 i386 simple bitmap cross-check

The DR2 i386 reference confirms the PowerPC interpretation of the
`NSSimpleBitmap` initializer and accessors. Its initializer at `0x47A0AFB8`
copies plane pointers, stores the supplied dimensions/format, copies the color
space, classifies device RGB as code 2 and device white as code 1, and returns
the original receiver. `bytesPerPlane` multiplies row bytes by pixel height;
`numberOfPlanes` returns samples per pixel only for planar data. The i386
reference has the same class layout as the PPC primary reference.

The `NSDirectBitmap` metadata accessors are shared across the two binaries.
They expose inherited bitmap fields, derive plane count for planar data, gate
row/plane sizes on the lock state, and forward conversion-table lookups to the
attached framebuffer. Its backing store is lazily allocated with four extra
rows and cleared to zero. `bitmapData` requires a lock and returns either that
buffer or the direct framebuffer address for the intercepted screen rectangle.
On a depth mismatch, `pixelEncoding` selects the recovered gray/RGB token for
the effective sample depth, and `pixelEncodings` returns a copied one-item
array.
`getBitmapDataPlanes:` follows the same state rules: it clears all outputs while
unlocked, returns the buffer and inherited planes in buffered mode, or returns
the direct screen address and clears the remaining four planes.
Its lock methods match PPC: they pin a rectangle, service pending updates,
select buffered drawing when the direct region is not fully visible, and
release a pinned rectangle on direct-mapped unlock.

Its simple accessors use the same field offsets: `bitmapData` at `0x47A0B0BC`,
`getBitmapDataPlanes:` at `0x47A0B0CC`, `bytesPerPlane` at `0x47A0B184`,
`numberOfPlanes` at `0x47A0B198`, and `dealloc` at `0x47A0B1E0`.

The copy routines independently confirm the PPC calling contract. `_CopyLong`
at `0x47A00CE0`, `_CopyShort` at `0x47A00F00`, and `_CopyByte` at
`0x47A0115C` receive source pointer/stride, destination pointer/stride, element
count, and row count. `_CopySrcToDst` at `0x47A07E78` copies the smaller row
span for each row. These bodies are implemented in the shared source units;
their tests are authored but await a compatible i386 runtime.
