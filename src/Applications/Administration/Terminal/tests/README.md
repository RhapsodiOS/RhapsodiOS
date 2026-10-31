# Terminal native tests

`make -C tests` builds and runs host-side tests for chunk/line storage,
delimiter search, stdout line printing, the Filer output queue, FStream
cursor/peek transitions, DPS debug packet serialization, word-selection
ranges, signed integer formatting, shell
command tokenization/policy, process and ServiceManager dirty-state policies,
per-PID process metadata extraction, and saved process identity/UID switching. Pass
`ARCH_FLAGS='-arch ppc'` or `-arch i386` only in a guest toolchain that supports
those targets. Host success validates C storage and queue semantics; it does
not validate the Objective-C runtime, target ABI, app link, or reference parity.

The `processinfo` test exercises the per-PID sysctl query and output-copy path
with a host stub. The `identity` test checks the saved real UID/GID and both
`setreuid` argument orders with a host stub.

`serviceabi.m` is an Objective-C compile-time ABI fixture. Run it with the
recovered framework headers and both `powerpc-apple-rhapsody` and
`i386-apple-rhapsody` Clang targets; its assertions cover the service record,
service-set header, `ServiceCache`, and `ServiceManager` instance layouts. It
does not require a link or runtime.


The `servicemanagerstate` test checks the recovered selection/dirty-state
policy that controls the Change, Remove, and Save buttons.

The `storage` test also exercises nested delimiter matching across screen rows, including reverse row wrap and misses.

The `storage` test covers shift-click endpoint selection, including mode-specific comparisons, midpoint ties, and row boundaries.

The storage test covers drag-selection endpoint transitions and triple-click expansion across rows connected by soft wraps, using the reconstructed row-slot stride.
The `storage` test checks the `_appendLines` and `_splitLine` paths with styled, multi-node lines, including an adjacent merge and a split within a linked node.

The `storage` test exercises PPC `ChunkCopy` with padded buffers to verify its
observed `+0x90` copy offset and unchanged destination count. It uses only an
empty `ChunkDup`: a nonempty duplicate passes allocator results to that
out-of-payload offset in the reference and would reproduce its memory overrun.
