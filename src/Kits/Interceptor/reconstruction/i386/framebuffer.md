# DR2 i386 framebuffer cross-check

The 140,216-byte DR2 i386 slice confirms the primary PowerPC behavior for the
framebuffer methods implemented in the shared source:

| Function | i386 address | Confirmed behavior |
|---|---:|---|
| `-[NSFramebuffer isMappable]` | `0x47A0873C` | Returns the `isMapped` byte. |
| `-[NSFramebuffer screenBounds]` | `0x47A08750` | Returns pixel width and height with origin `(0,0)`. |
| `-[NSFramebuffer pixelEncoding]`, `driver` | `0x47A08994`, `0x47A089EC` | Lazily convert the fixed C strings with `NSString stringWithCString:` and cache the objects, matching PPC. |
| `-[NSFramebuffer addressForPoint:]` | `0x47A08920` | Null if unmapped; otherwise uses row bytes and integer-truncated coordinates with `bitsPerPixel / 8`. |
| `-[NSFramebuffer retain]`, `release`, `retainCount`, `dealloc` | `0x47A08A64`–`0x47A08A84` | Immortal cached object semantics match the PPC methods. |
| `-[NSFramebuffer canLockWithMode:]`, `lockWithMode:`, `unlock` | `0x47A08A8C`–`0x47A08AA0` | Always lockable; lock and unlock are no-ops. |
| `-[NSFramebuffer _interceptorClient]` | `0x47A08AA8` | Returns the stored client. |
| `_setInstanceForScreen`, `_instanceForScreen` | `0x47A07FC0`, `0x47A08040` | Lazily allocate a screen-count-sized pointer array using the client's screen-count RPC, zero it, and store or retrieve a framebuffer by valid screen index, matching PPC. |
| `-[NSFramebuffer unmapScreen]` | `0x47A08468` | Unmaps plane zero when present through the client's context, then clears plane zero, matching PPC. |
| `-[NSFramebuffer unmapScreen]` | `0x47A08468` | Unmaps plane zero when present through the client's context, then clears plane zero, matching PPC. |

The initializer independently confirms per-screen instance reuse, creation of
an interceptor client, optional mapping, and initialization of the inherited
bitmap fields. Its supported depths are 2, 8, 12, 15, 16, 24, and 32 bits; the
15-bit path uses five samples in a 16-bit pixel, while 12/16-bit paths use four
samples and 16-bit pixels. Runtime behavior and screen-bound calculations have
not yet been compared. The convenience initializer also checks the argument's
class and extracts `NSScreenNumber` from the device description, matching the
PPC implementation.
