# DR2 i386 framebuffer cross-check

The 140,216-byte DR2 i386 slice confirms the primary PowerPC behavior for the
framebuffer methods implemented in the shared source:

| Function | i386 address | Confirmed behavior |
|---|---:|---|
| `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | `0x47A08158` | Reuses cached instances, acquires metadata, optionally maps the display, validates color space and pixel depth, and initializes the inherited bitmap fields. |
| `-[NSFramebuffer remapScreen]` | `0x47A084AC` | Unmaps the old address, refreshes metadata, remaps only if previously mapped, then updates address and bitmap fields, matching PPC. |
| `-[NSFramebuffer isMappable]` | `0x47A0873C` | Returns the `isMapped` byte. |
| `-[NSFramebuffer conversionTable]`, `inverseConversionTable` | `0x47A087D8`, `0x47A0887C` | Lazily fetch the matching 5-bit or 8-bit RGB conversion table and cache its server-provided address. |
| `-[NSFramebuffer screenBounds]` | `0x47A08750` | Returns pixel width and height with origin `(0,0)`. |
| `-[NSFramebuffer pixelEncoding]`, `driver` | `0x47A08994`, `0x47A089EC` | Lazily convert the fixed C strings with `NSString stringWithCString:` and cache the objects, matching PPC. |
| `-[NSFramebuffer addressForPoint:]` | `0x47A08920` | Null if unmapped; otherwise uses row bytes and integer-truncated coordinates with `bitsPerPixel / 8`. |
| `-[NSFramebuffer retain]`, `release`, `retainCount`, `dealloc` | `0x47A08A64`–`0x47A08A84` | Immortal cached object semantics match the PPC methods. |
| `-[NSFramebuffer canLockWithMode:]`, `lockWithMode:`, `unlock` | `0x47A08A8C`–`0x47A08AA0` | Always lockable; lock and unlock are no-ops. |
| `-[NSFramebuffer _interceptorClient]` | `0x47A08AA8` | Returns the stored client. |
| `_setInstanceForScreen`, `_instanceForScreen` | `0x47A07FC0`, `0x47A08040` | Lazily allocate a screen-count-sized pointer array using the client's screen-count RPC, zero it, and store or retrieve a framebuffer by valid screen index, matching PPC. |
| `-[NSFramebuffer unmapScreen]` | `0x47A08468` | Unmaps plane zero when present through the client's context, then clears plane zero, matching PPC. |

The shared source implements the cache-backed initializer, mapping decision,
remap sequence, color-space selection, and bitmap metadata setup. Supported pixel depths are
2, 8, 12, 15, 16, 24, and 32 bits. It maps 12/16-bit modes to four bits per
sample in 16-bit pixels, 15-bit modes to five bits per sample in 16-bit pixels,
and 24/32-bit modes to eight bits per sample in 32-bit pixels. Samples per
pixel come from the reported color-space code. The convenience initializer also
checks the argument's class and extracts `NSScreenNumber` from the device
description, matching PPC.
