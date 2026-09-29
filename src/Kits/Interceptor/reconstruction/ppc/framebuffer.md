# PowerPC framebuffer evidence

The primary reference is the 145,364-byte PowerPC `Interceptor` dylib. The
following behavior is recovered from IDA 9.4 function records and Hex-Rays
output. Runtime observations remain pending.

| Function | Address | Recovered behavior |
|---|---:|---|
| `-[NSFramebuffer initWithScreen:]` | `0x47A0A628` | Delegates to `initWithScreen:andMapIfPossible:` with mapping enabled. |
| `-[NSFramebuffer initWithScreen:andMapIfPossible:]` | `0x47A0A660` | Resolves the screen number from `NSScreen`, checks validity, then calls the designated initializer; invalid screens release the receiver and return `nil`. |
| `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | `0x47A0A72C` | Reuses a cached framebuffer for an existing screen; otherwise creates an interceptor client, requests framebuffer metadata, optionally maps it, validates color space and pixel depth, then initializes bitmap fields. Failure releases the receiver and returns `nil`. |
| `-[NSFramebuffer unmapScreen]` | `0x47A0A9E0` | If plane zero is non-null, asks the client to unmap that screen/address, then clears plane zero. |
| `-[NSFramebuffer remapScreen]` | `0x47A0AA3C` | Unmaps the old address, refreshes framebuffer metadata, remaps only when previously mapped, and updates bitmap dimensions, sample count, color space, color-space token, and row bytes. |
| `-[NSFramebuffer isMappable]` | `0x47A0AC5C` | Returns `isMapped`. |
| `-[NSFramebuffer addressForPoint:]` | `0x47A0AEC8` | Returns null when unmapped; otherwise offsets plane zero by `bytesPerRow * (int)y + (int)x * bitsPerPixel / 8`. Coordinates are truncated to integers. |
| `-[NSFramebuffer retain]`, `release`, `retainCount`, `dealloc` | `0x47A0B040`–`0x47A0B068` | Framebuffer instances are immortal cached objects: retain returns self, release and dealloc do nothing, and retain count is `-1`. |
| `-[NSFramebuffer canLockWithMode:]`, `lockWithMode:`, `unlock` | `0x47A0B074`–`0x47A0B090` | The predicate always returns true; lock and unlock are no-ops. |

`NSFramebuffer.m` now implements the recovered simple accessors, pixel-address
calculation, immortal-cache ownership methods, and lock methods. The mapping,
metadata-query, remapping, conversion-table, and screen-bounds paths still need
their IPC and driver-facing behavior reconstructed. These source methods have
not been compiled or run on a compatible Rhapsody toolchain.
