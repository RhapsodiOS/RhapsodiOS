# DR2 i386 Mach IPC cross-check

The DR2 i386 thin image independently confirms the primary PowerPC IPC
contract:

| Routine | Address | Request ID | Request size | Reply ID | Reply size |
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

All synchronous RPCs call `msg_rpc` with the same request and reply maximum
sizes as the PPC bodies. Context setup calls `_port_allocate` and `_getPSPort`
with the same `15000` timeout and package ID `7196`; teardown deallocates the
same context fields. Runtime transport comparison remains pending.

The i386 decompiler confirms the architecture-specific descriptor words:
integer `0x10012002`, eight-integer rectangle `0x10082002`, and port
`0x10012006`. These describe the same name/size/count/inline fields as the PPC
descriptors, with native bitfield byte order accounted for by assigning the
`msg_type_t` fields in C.
