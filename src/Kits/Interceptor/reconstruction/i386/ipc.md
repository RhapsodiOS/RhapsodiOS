# DR2 i386 Mach IPC cross-check

The DR2 i386 thin image independently confirms the primary PowerPC IPC
contract:

| Routine | Address | Request ID | `msg_rpc` reply capacity | Reply ID | Reply size |
|---|---:|---:|---:|---:|---:|
| `_InterceptorCreateRemoteContext` | `0x47A0B3DC` | — | — | — | — |
| `_InterceptorCreateContext` | `0x47A0B454` | — | — | — | — |
| `_InterceptorDestroyContext` | `0x47A0B464` | — | — | — | — |
| `_InterceptorAddRect` | `0x47A0C0DC` | `0x1C23` | 76 | `0x1C87` | 32 |
| `_InterceptorRemoveRect` | `0x47A0C1E8` | `0x1C24` | 40 | `0x1C88` | 32 |
| `_InterceptorSetNotifyPort` | `0x47A0C2C0` | `0x1C25` | 40 | `0x1C89` | 32 |
| `_InterceptorScreenCount` | `0x47A0C4D4` | `7207` | 24 | `7307` | 32 |
| `_InterceptorHideCursor` | `0x47A0C59C` | `7208` | 24 | `7308` | 32 |
| `_InterceptorShowCursor` | `0x47A0C664` | `7209` | 24 | `7309` | 32 |
| `_InterceptorShowCursorAsync` | `0x47A0CBF8` | `7218` | 24 | — | — |
| `_InterceptorMapFrameBuffer` | `0x47A0B9B8` | `7198` | 48 | `7298` | 32-error / 48-success |
| `_InterceptorUnmapFrameBuffer` | `0x47A0CC44` | `7219` | 40 | `7319` | 32-error / 40-success |
| `_InterceptorFrameBufferInfo` | `0x47A0BD6C` | `7201` | 272 | `7301` | 32-byte error / 272-byte success |
| `_InterceptorGetDeviceAccessTokens` | `0x47A0CAE4` | `7217` | 64-byte reply capacity (`msg_size` 32) | `7317` | 32-byte error / 64-byte success |
| `_InterceptorGetBM34ToBM35Table` | `0x47A0BAB8` | `7199` | 56 | `7299` | 32-byte error / 56-byte success |
| `_InterceptorGetBM35ToBM34Table` | `0x47A0C3A8` | `7206` | 56 | `7306` | 32-byte error / 56-byte success |
| `_InterceptorGetBM256ToBM38Table` | `0x47A0C72C` | `7210` | 48 | `7310` | 32-byte error / 48-byte success |
| `_InterceptorGetBM38ToBM256Table` | `0x47A0C808` | `7211` | 48 | `7311` | 32-byte error / 48-byte success |
| `_InterceptorEnableFrameBufferMapping` | — | `7196` | 40 | `7296` | 32-byte error / 40-byte success |
| `_InterceptorDisableFrameBufferMapping` | — | `7197` | 40 | `7297` | 32-byte error / 40-byte success |
| `_OldInterceptorSetNotifyPort` | — | `7202` | 40 | `7302` | 32 |

All synchronous RPCs call `msg_rpc` with the same request and reply maximum
sizes as the PPC bodies. Context setup allocates a 12-byte record and reply
port, then calls the local `getPSPort` helper with the same `15000` timeout and
package ID `7196`; teardown deallocates the same context fields. The source
implements the bootstrap `WindowServer` lookup, netname fallback, and
32-byte rendezvous request. Runtime transport comparison remains pending.

The i386 decompiler confirms the architecture-specific descriptor words:
integer `0x10012002`, eight-integer rectangle `0x10082002`, and port
`0x10012006`. These describe the same name/size/count/inline fields as the PPC
descriptors, with native bitfield byte order accounted for by assigning the
`msg_type_t` fields in C.

The 16-bit conversion tables use out-of-line long-form descriptors with counts
4096 and 32768. The byte-table RPCs use the observed short descriptors
`0x01002002` and `0x04000808`; source validates the returned descriptor before
exposing the server-owned table address.

The access-token reply carries a MIG status pair and an operation result pair,
followed by port, integer, and port descriptor/value pairs, returning the
master port, IO object number, and device port. The wrapper is at
`0x47A0B75C`; both PPC and i386 independently
confirm request/reply IDs `7217`/`7317` and the same output order.

The i386 bodies independently confirm the asynchronous `FlushRect`,
`AddDirtyRect`, and `FlushDirtyRects` packets at IDs `7212`, `7213`, and
`7214`. The rectangle messages contain one window-number descriptor and one
four-integer descriptor in a 52-byte message; flushing pending dirty regions
sends only a window number in a 32-byte message. The reconstructed source and
transport test cover these descriptors and payloads for both architectures.

The DR2 i386 image also confirms legacy framebuffer-mapping requests at IDs
`7196`/`7296` and `7197`/`7297`: each has a 116-byte request, an inline
80-byte driver-name long descriptor, and 40-byte reply capacity. The legacy
`_OldInterceptorSetNotifyPort` request uses ID `7202`, reply ID `7302`, a
32-byte request, and one port descriptor/value pair. These layouts match the
PowerPC image and are covered by the reconstructed source and packet tests.
