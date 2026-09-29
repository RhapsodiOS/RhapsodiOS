# PowerPC Mach IPC evidence

The primary binary contains synchronous client RPC stubs, an asynchronous
ShowCursor request, and the context/port lifecycle functions. DR2 i386 has the
same rectangle RPC IDs, sizes, reply IDs, and context acquisition arguments;
see `../i386/ipc.md`.

| Routine | Request ID | Request size | Reply ID | Reply size |
|---|---:|---:|---:|---:|
| `_InterceptorAddRect` | `0x1C23` | 76 bytes | `0x1C87` | 32 bytes |
| `_InterceptorRemoveRect` | `0x1C24` | 40 bytes | `0x1C88` | 32 bytes |
| `_InterceptorSetNotifyPort` | `0x1C25` | 40 bytes | `0x1C89` | 32 bytes |
| `_InterceptorScreenCount` | `7207` | 24 bytes | `7307` | 32 bytes |
| `_InterceptorHideCursor` | `7208` | 24 bytes | `7308` | 32 bytes |
| `_InterceptorShowCursor` | `7209` | 24 bytes | `7309` | 32 bytes |
| `_InterceptorMapFrameBuffer` | `7198` | 48 bytes | `7298` | 32-byte error / 48-byte success |
| `_InterceptorUnmapFrameBuffer` | `7219` | 40 bytes | `7319` | 32-byte error / 40-byte success |
| `_InterceptorFrameBufferInfo` | `7201` | 272 bytes | `7301` | 32-byte error / 272-byte success |
| `_InterceptorGetDeviceAccessTokens` | `7217` | 64-byte send buffer (`msg_size` 32) | `7317` | 32-byte error / 64-byte success |
| `_InterceptorGetBM34ToBM35Table` | `7199` | 56 bytes | `7299` | 32-byte error / 56-byte success |
| `_InterceptorGetBM35ToBM34Table` | `7206` | 56 bytes | `7306` | 32-byte error / 56-byte success |
| `_InterceptorGetBM256ToBM38Table` | `7210` | 48 bytes | `7310` | 32-byte error / 48-byte success |
| `_InterceptorGetBM38ToBM256Table` | `7211` | 48 bytes | `7311` | 32-byte error / 48-byte success |

Each call uses `msg_rpc(request, 0, requestSize, 0, 0)`. The context's
`contextPort` is sent as `msg_remote_port`; `replyPort` is `msg_local_port`.
The message header is the historical 24-byte `msg_header_t`; messages set
`msg_size`, `msg_type`, both ports, and the operation ID. The binary validates
the reply ID and either the fixed 32-byte error reply or the operation-specific
success reply. A malformed ID/descriptor returns the raw MIG error values
`-301` or `-300`; transport errors pass through `Interceptor_mig_error`.

The request-size column records the `msg_rpc` send-buffer size. Map sends 48
bytes with `msg_size` set to 40; unmap sends 40 bytes with `msg_size` set to
48. FrameBufferInfo sends a 272-byte receive buffer with `msg_size` set to 32
and contains the screen integer descriptor and screen number. Its successful
272-byte reply carries an 80-byte driver string, seven integer metadata pairs,
a 64-byte pixel encoding, and one additional integer. The source validates the
long-form string descriptors and each integer descriptor before copying their
corresponding outputs.

`_InterceptorGetDeviceAccessTokens` sends an integer descriptor and screen
number. Its 64-byte success reply contains a MIG status pair and an operation
result pair, then port, integer, and port descriptor/value pairs; these return
the master port, IO object number, and device port. PPC and DR2 i386 use the same request/reply IDs
and field order with their native integer (`0x02200018` / `0x10012002`) and
port (`0x06200018` / `0x10012006`) descriptor words. A nonzero screen may also
receive the standard 32-byte MIG error reply.

The table RPCs return server-owned out-of-line arrays. The two 16-bit table
messages carry long-form descriptors (4096 and 32768 entries); the byte-table
messages use architecture-specific short descriptors and return their address
in the final word. PPC's public 5-bit conversion-table wrappers return error 6
without sending an RPC, matching their 16-byte stubs. Its lower-level MIG
functions remain present and parse the same requests as the i386 implementations.

`_InterceptorAddRect` serializes all eight integer fields of
`InterceptedRectangle` and copies all eight returned fields back on success.
RemoveRect sends the unique ID. SetNotifyPort sends notification and exception
ports. The type descriptors, reply checks, and error paths are present in both
architectures. The public notification constants are not used as RPC request
IDs.

`_InterceptorCreateRemoteContext` allocates and zeroes a 12-byte context,
allocates a reply port into field 1, then calls `getPSPort(0, 0, replyPort,
15000, 7196)` for the server/context port. Field 2 starts null. On failure it
frees the context; this path does not deallocate a reply port allocated before
`getPSPort` fails. `_InterceptorDestroyContext` deallocates the reply port and
context port, deallocates the notify port only when nonzero, zeroes all 12
bytes, and frees the context. This sequence is binary-observed and retained
even where cleanup appears asymmetric.

The simple screen/cursor RPCs send only the 24-byte message header, with the
context and reply ports in the same header fields. Successful replies contain
the MIG status descriptor/value followed by one integer result; error replies
contain only the MIG status. `_InterceptorShowCursorAsync` sends request `7218`
to the context port without waiting for a reply, and the high-level
`InterceptorShowCursor` wrapper returns zero after queuing it.

`InterceptorContext.c` implements the context lifecycle, bootstrap/netname
Window Server lookup, and rendezvous RPC. `_rendezvousPort` exposes the
resolved server port to the notifier. `InterceptorIPC.c` implements these RPC stubs,
including the typed descriptors (`0x02200088` for the rectangle,
`0x02200018` for integers, and `0x06200018` for ports in the PPC word view),
conversion-table RPCs, success/error reply shapes, and the observed `-300`/`-301`
validation errors.
Descriptor fields are assigned individually so the compiler emits the proper
architecture-specific bitfield order. A test transport captures the synchronous
requests, including framebuffer map/unmap/metadata, and the asynchronous
ShowCursor request; it supplies
successful, server-error, wrong-ID, and send-failure outcomes. Its execution
remains pending until the compatible
historical toolchain is available.

Runtime capture of outgoing messages, malformed replies, and transport
failures remains pending because the compatible Mach guest/toolchain is not
available on this host.

The binary also contains asynchronous `FlushRect`, `AddDirtyRect`, and
`FlushDirtyRects` notifications. IDs `7212`, `7213`, and `7214` carry a window
number followed by four rectangle integers, a window number and four rectangle
integers, and only a window number, respectively. The first two messages are
52 bytes with integer descriptors for one and four values; the last is 32
bytes with one integer descriptor. The source implements these packets in
`InterceptorIPC.c` and includes transport assertions in `tests/ipc.c`.
