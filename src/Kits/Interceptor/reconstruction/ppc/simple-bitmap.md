# Simple bitmap evidence

Primary PowerPC reference: 145364-byte normal `Interceptor` dylib.

| Function | Address | Recovered behavior |
|---|---:|---|
| `-[NSSimpleBitmap initWithBitmapDataPlanes:...]` | `0x47A0DD54` | Calls superclass `init`, copies `samplesPerPixel` plane pointers without allocating/copying pixel storage, stores dimensions/depth/flags/row bytes and a copied color-space object, and returns the original receiver. |
| `-bitmapData` | `0x47A0DE90` | Returns `data[0]`. |
| `-getBitmapDataPlanes:` | `0x47A0DEA0` | Returns `numberOfPlanes` pointers then clears the remaining entries through index four. |
| `-bytesPerPlane` | `0x47A0DF8C` | Multiplies `bytesPerRow * pixelsHigh`; it does not read the nominal `bytesPerPlane` ivar. |
| `-numberOfPlanes` | `0x47A0DFB0` | Returns `samplesPerPixel` for planar data, otherwise one. |
| `-dealloc` | `0x47A0E004` | Releases the color-space object, then calls superclass `dealloc`; supplied plane storage is not freed. |

The initializer's code-color classification writes `NSRGBColorSpace` for a
matching device RGB name, `NSOneIsWhiteColorSpace` for a matching device white
name, and `NSOneIsBlackColorSpace` otherwise. Exact runtime observations are
still pending because the compatible guest is not configured.

`NSDirectBitmap`'s basic metadata accessors are also implemented in
`NSDirectBitmap.m`. They forward inherited sample/depth/size/color fields,
derive plane count from `isPlanar`, and gate row/plane byte counts on
`isLocked`; an unobscured direct-mapped bitmap reads the row stride from its
framebuffer. Its conversion-table accessors forward to the attached
framebuffer.

The seven public encoding globals resolve to these exact constant strings in
the reference's Objective-C constant-string objects:

| Global | Value |
|---|---|
| `NSInterceptorEightBitPseudoColor` | `PPPPPPPP` |
| `NSInterceptorEightBitGrey` | `WWWWWWWW` |
| `NSInterceptorTwoBitGrey` | `KK` |
| `NSInterceptorFifteenBitRGBColor` | `-RRRRRGGGGGBBBBB` |
| `NSInterceptorSixteenBitRGBColor` | `RRRRRGGGGGGBBBBB` |
| `NSInterceptorTwelveBitRGBColor` | `RRRRGGGGBBBB----` |
| `NSInterceptorThirtyTwoBitRGBColor` | `RRRRRRRRGGGGGGGGBBBBBBBB--------` |

PPC register use shows `CopyLong`, `CopyShort`, and `CopyByte` take source
pointer/row stride, destination pointer/row stride, element count per row, and
row count. Long and short counts are elements, with four- and two-byte strides
per element respectively; byte count is bytes. These functions are implemented
in `NSDirectBitmap.m`, adjacent to the first `NSDirectBitmap` methods in the
reference text. `CopySrcToDst` copies the smaller of the source and destination
row spans for each row; its two callers are in `NSDirectScreen` and
`NSFramebuffer`, and the function is adjacent to the `NSFramebuffer`
implementation, so it is implemented in `NSFramebuffer.m`. This is a static
source-ownership inference. Test coverage exists for strides and row padding,
but runtime execution remains pending.
