# DR2 i386 direct-bitmap selectors

`-[NSDirectBitmap flush]` forwards a zero-origin rectangle whose width and
height are the bitmap's full pixel dimensions to `flushIn:`. The
`_viewClipShape:` compatibility selector returns the stored view-clip shape.
Both source methods match the i386 bodies and the PPC slice.
