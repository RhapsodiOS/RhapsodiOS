# PowerPC Mach IPC evidence

The primary binary contains six synchronous client RPC stubs, an asynchronous
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
| `_InterceptorMapFrameBuffer` | `7198` | 48 bytes | `7298` | 32 bytes |
| `_InterceptorUnmapFrameBuffer` | `7219` | 40 bytes | `7319` | 32 bytes |
| `_InterceptorMapFrameBuffer` | `7198` | 48 bytes | `7298` | 32 bytes |
| `_InterceptorUnmapFrameBuffer` | `7219` | 40 bytes | `7319` | 32 bytes |

Each call uses `msg_rpc(request, 0, requestSize, 0, 0)`. The context's
`contextPort` is sent as `msg_remote_port`; `replyPort` is `msg_local_port`.
The message header is the historical 24-byte `msg_header_t`; messages set
`msg_size`, `msg_type`, both ports, and the operation ID. The binary validates
the reply ID and either the fixed 32-byte error reply or the operation-specific
success reply. A malformed ID/descriptor returns the raw MIG error values
`-301` or `-300`; transport errors pass through `Interceptor_mig_error`.

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

`InterceptorContext.c` implements the context lifecycle and `InterceptorIPC.c`
implements these RPC stubs,
including the typed descriptors (`0x02200088` for the rectangle,
`0x02200018` for integers, and `0x06200018` for ports in the PPC word view),
success/error reply shapes, and the observed `-300`/`-301` validation errors.
Descriptor fields are assigned individually so the compiler emits the proper
architecture-specific bitfield order. A test transport now captures all six
synchronous requests and the asynchronous ShowCursor request and supplies
successful, server-error, wrong-ID, and send-failure outcomes. Its execution
remains pending until the compatible
historical toolchain is available.

Runtime capture of outgoing messages, malformed replies, and transport
failures remains pending because the compatible Mach guest/toolchain is not
available on this host.
