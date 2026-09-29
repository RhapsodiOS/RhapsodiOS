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

All three RPCs call `msg_rpc` with the same request and reply maximum sizes as
the PPC bodies. Context setup calls `_port_allocate` and `_getPSPort` with the
same `15000` timeout and package ID `7196`; teardown deallocates the same
context fields. Runtime transport comparison remains pending.
