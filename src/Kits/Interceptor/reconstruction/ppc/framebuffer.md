# PowerPC framebuffer evidence

The primary reference is the 145,364-byte PowerPC `Interceptor` dylib. The
following behavior is recovered from IDA 9.4 function records and Hex-Rays
output. Runtime observations remain pending.

| Function | Address | Recovered behavior |
|---|---:|---|
| `-[NSFramebuffer initWithScreen:]` | `0x47A0A628` | Delegates to `initWithScreen:andMapIfPossible:` with mapping enabled. |
| `-[NSFramebuffer initWithScreen:andMapIfPossible:]` | `0x47A0A660` | Checks that the argument is an `NSScreen`, reads `NSScreenNumber` from `deviceDescription`, and delegates by screen number; invalid screens release the receiver and return `nil`. |
| `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | `0x47A0A72C` | Reuses a cached framebuffer for an existing screen; otherwise creates an interceptor client, requests framebuffer metadata, optionally maps it, validates color space and pixel depth, then initializes bitmap fields. Failure releases the receiver and returns `nil`. |
| `_setInstanceForScreen`, `_instanceForScreen` | `0x47A0A50C`, `0x47A0A5BC` | Lazily allocate a screen-count-sized pointer array using the client's screen-count RPC, zero it, and store or retrieve a framebuffer by valid screen index. |
| `-[NSFramebuffer unmapScreen]` | `0x47A0A9E0` | If plane zero is non-null, asks the client to unmap that screen/address, then clears plane zero. |
| `-[NSFramebuffer remapScreen]` | `0x47A0AA3C` | Unmaps the old address, refreshes framebuffer metadata, remaps only when previously mapped, and updates bitmap dimensions, sample count, color space, color-space token, and row bytes. |
| `-[NSFramebuffer isMappable]` | `0x47A0AC5C` | Returns `isMapped`. |
| `-[NSFramebuffer conversionTable]`, `inverseConversionTable` | `0x47A0AD58`, `0x47A0AE10` | Lazily fetch RGB conversion tables for 5- and 8-bit samples; 5-bit PPC wrappers return error 6 and leave the cache null, matching the binary stubs. |
| `-[NSFramebuffer screenBounds]` | `0x47A0AC70` | Returns the framebuffer pixel width and height as an `NSRect` size with origin `(1,1)`. The origin comes from the unique `1.0f` constant at file offset `0x10EB4`; the adjacent double is the `2^52` integer-to-floating-point conversion constant. |
| `-[NSFramebuffer pixelEncoding]`, `driver` | `0x47A0AF58`, `0x47A0AFBC` | Lazily wrap the fixed C strings in `NSString` using `stringWithCString:` and cache the resulting object. |
| `-[NSFramebuffer addressForPoint:]` | `0x47A0AEC8` | Returns null when unmapped; otherwise offsets plane zero by `bytesPerRow * (int)y + (int)x * bitsPerPixel / 8`. Coordinates are truncated to integers. |
| `-[NSFramebuffer retain]`, `release`, `retainCount`, `dealloc` | `0x47A0B040`–`0x47A0B068` | Framebuffer instances are immortal cached objects: retain returns self, release and dealloc do nothing, and retain count is `-1`. |
| `-[NSFramebuffer canLockWithMode:]`, `lockWithMode:`, `unlock` | `0x47A0B074`–`0x47A0B090` | The predicate always returns true; lock and unlock are no-ops. |

`NSFramebuffer.m` now implements both convenience initializers, the per-screen
cache, metadata-based bitmap setup, remap/unmap, conversion-table accessors,
pixel-address calculation, ownership methods, and lock methods. Framebuffer
metadata, map/unmap, and conversion-table RPCs are implemented in
`InterceptorIPC.c`. Source/runtime verification on a compatible Rhapsody
toolchain remains pending.
