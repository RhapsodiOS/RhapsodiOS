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
Plain `init` raises `NSGenericException`; `minDepthForGray:andColor:` stores
the global depth thresholds used when creating a bitmap for a rectangle.
Deallocation detaches the rectangle target, releases its client, framebuffer,
and window, frees its buffer in the object's zone, then calls superclass
`dealloc`, matching PPC.
`getBitmapDataPlanes:` follows the same state rules: it clears all outputs while
unlocked, returns the buffer and inherited planes in buffered mode, or returns
the direct screen address and clears the remaining four planes.
Its lock methods match PPC: they pin a rectangle, service pending updates,
select buffered drawing when the direct region is not fully visible, and
release a pinned rectangle on direct-mapped unlock. Direct mapping requires a
single screen and a mappable framebuffer with matching depth greater than
seven bits per pixel.

The i386 rectangle update and backing-store resize bodies agree with PPC:
packed rows are aligned to eight bytes, screen changes remap the framebuffer,
and stale intercepted rectangles are removed before direct-versus-buffered
selection. The i386 initializer uses `isTotallyVisible` for the initial
unobscured state; the PPC binary invokes its equivalent visibility selector.
The reconstruction shares that selector through `NSInterceptedRect`'s public
`isTotallyVisible` method.
The public window-update and deferred-state methods also match PPC: globalize
the window number, obtain the screen number from the screen device description,
retain/release the window, and replay either window-backed or saved geometry.
Buffered window backing disables direct mapping.
Rectangle initialization starts the client thread, maps the selected screen,
applies configured minimum gray or RGB depths, aligns row storage, chooses the
copy routine for supported pixel widths, and delegates to the shared rectangle
update. `setDirectMapped:` applies the same framebuffer and window-backing
eligibility checks as PPC.
The recovered `_flushInShape:` copies each clipped screen-space shape rectangle
from its corresponding buffer offset back to the framebuffer.

Its simple accessors use the same field offsets: `bitmapData` at `0x47A0B0BC`,
`getBitmapDataPlanes:` at `0x47A0B0CC`, `bytesPerPlane` at `0x47A0B184`,
`numberOfPlanes` at `0x47A0B198`, and `dealloc` at `0x47A0B1E0`.

The copy routines independently confirm the PPC calling contract. `_CopyLong`
at `0x47A00CE0`, `_CopyShort` at `0x47A00F00`, and `_CopyByte` at
`0x47A0115C` receive source pointer/padding, destination pointer/padding, element
count, and row count. `_CopySrcToDst` at `0x47A07E78` copies the smaller row
span for each row. The typed copy routines take extra row-padding bytes after
the copied elements, rather than total row widths; the PPC body confirms the
same contract. These bodies are implemented in the shared source units;
their tests are authored but await a compatible i386 runtime.

The i386 `flushIn:` and `flush` paths match the PPC reconstruction: they require
a lock and buffered drawing or draw-to-buffer, clip direct-mapped copies to the
screen shape/view clip, and route buffered rectangles through `CompositeBits`.
`setBuffered:` snapshots before enabling buffering and flushes before switching
back to direct drawing. The 7200 request is 112 bytes and contains the four
integer fields, an out-of-line pixel payload (`height * bytesPerRow` bytes),
and five dimension/format fields in the same descriptor order as PPC.

Invalidation and window-free callbacks clear the unobscured state and mark the
bitmap for a deferred update. Screen-change callbacks record the new screen
only when the old screen is the currently mapped one; buffering changes always
request a deferred refresh, matching the PPC bodies.

Move callbacks hold the bitmap locked across the server move, then offset both
the cached screen region and optional view clip, recompute visibility, and send
the delegate's `rectDidMove:` notification before releasing that lock state.
