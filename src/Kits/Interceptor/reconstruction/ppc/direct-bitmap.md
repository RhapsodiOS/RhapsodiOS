# PowerPC direct-bitmap selectors

`-[NSDirectBitmap _viewClipShape:]` returns the cached view-clip shape. The
PPC `flush` selector forwards a rectangle covering the full pixel dimensions
to `flushIn:`; the reconstructed source uses the equivalent zero-origin
rectangle. These bodies were cross-checked against the DR2 i386 slice.
