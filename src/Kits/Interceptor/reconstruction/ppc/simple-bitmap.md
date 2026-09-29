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
Calling plain `init` raises `NSGenericException`; callers must provide a
rectangle and window. The class-level `minDepthForGray:andColor:` setter stores
the minimum gray and RGB depths consumed by rectangle initialization.
When the requested depth differs from the framebuffer depth, `pixelEncoding`
selects the matching 2-bit gray, 8-bit gray, 12-bit RGB, 15-bit RGB, or 32-bit
RGB encoding token; `pixelEncodings` returns a copied one-element array.
Its lazily allocated backing store contains the row stride times pixel height
plus four extra rows and is zero-filled. `bitmapData` is available only while
locked; it returns that buffer in buffered modes, or marks the screen dirty and
returns the framebuffer address at the intercepted screen rectangle's origin
in direct mode.
`getBitmapDataPlanes:` clears all five outputs while unlocked. When locked in a
buffered mode it returns the backing buffer and inherited extra planes; in
direct mode it returns the screen-origin address, clears planes one through
four, and marks the screen dirty.
Locking pins the intercepted rectangle, services a pending state update while
temporarily releasing that rectangle, selects buffered drawing unless the
direct framebuffer is unobscured, and records the locked state. Try-lock
rejects a nested lock; unlock clears the state and releases a pinned rectangle
for direct-mapped operation.
Direct mapping is eligible only on a single-screen system when the framebuffer
is mappable, exceeds seven bits per pixel, and matches the bitmap's pixel
depth.
When a rectangle moves to another screen, `_mapFramebufferForScreen:` releases
the previous framebuffer, creates and maps the requested screen framebuffer in
the bitmap's zone, records the screen number, and chooses read/write, write-only,
or read-only access in that order according to the modes the framebuffer allows.
`_updateBackingStoreForRect:` frees an existing lazy buffer, rounds the new
packed row size up to an 8-byte boundary, and reinitializes the simple-bitmap
metadata with empty planes while preserving depth and color-space settings.
`_updateForRect:inWinNum:onScreen:` ignores updates while locked, removes stale
window-server interception state when geometry changes, remaps on screen changes,
and marks a depth mismatch if the existing bitmap format differs from the new
framebuffer. A matching, eligible framebuffer creates an intercepted rectangle
and selects direct mapping; other cases discard interception state and select
buffered drawing. Both branches resize storage when dimensions change.
`_initForRect:inWinNum:onScreen:` rejects empty rectangles, records the geometry,
starts an interceptor client thread when needed, maps the screen, and chooses a
bitmap format from the framebuffer plus the configured gray/RGB minimum depths.
It aligns packed rows to eight bytes, selects the byte/short/long copy routine
for 8/16/32-bit pixels, then performs the final rectangle update. The public
initializer retains its window, globalizes its window number, derives the screen
number from `NSScreenNumber`, and disables direct mapping for buffered windows.
`setDirectMapped:` checks eligibility and the window backing mode; turning direct
mapping off removes the intercepted rectangle and forces buffered state.
The public `updateForRect:inWindow:` converts the window number to its global
form, reads `NSScreenNumber` from the window screen's device description, and
retains the new window while releasing the old one before delegating. When that
screen matches the mapped screen, it uses the pending `newScreen` value.
`updateState` replays the saved rectangle through this public path when a window
is retained, and disables direct mapping for buffered windows; without a window
it replays the saved global window and pending screen identifiers directly.
Deallocation detaches the intercepted rectangle's target, releases the client,
framebuffer, and window, frees the lazily allocated buffer from the object's
zone, and then calls superclass `dealloc`.

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
