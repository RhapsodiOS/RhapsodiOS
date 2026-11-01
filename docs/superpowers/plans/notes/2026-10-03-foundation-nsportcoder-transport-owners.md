# Foundation distributed-object transport selector reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSPortCoder.json`.

IDA confirms the `NSMachPort(NSPortMessageSpeedups)` methods at `0x42528c34`
and `0x42528c78`. The sender forwards the time, stream data, components,
receiver port, and message id to `NSPortMessage` with reserved space `36`; the
reserved-space method returns `36`. These implementations now live under the
ABI category owner in `NSPort.m`. The former generic `NSPort` category body in
`NSPortMessage.m` was removed.

IDA confirms `-[NSStreamData dealloc]` at `0x4256a0dc` raises
`NSInternalInconsistencyException` with `NSStreamData can't dealloc`; the
source now does the same.

The `NSObject(NSDistributedObjects)` methods at `0x4252518c`, `0x42545bec`,
and `0x42567090` return `classForCoder`, substitute a distant-object proxy for
the instance replacement when non-nil, and return the class receiver from the
class replacement method. The existing instance bodies now have the ABI
category owner, and the class method is implemented and declared in
`NSPortCoder.h`.

The focused ABI-owner audit had reported `+[NSConcretePortCoder debugDescription]` as the sole remaining NSPortCoder selector. A 2026-10-04
IDA disassembly and class-record recheck confirmed its class/instance layout
mismatch, and the method is now implemented with those raw reads in
`NSPortCoder.m`; see `2026-10-03-foundation-nsconcreteportcoder-analysis.md`
for the evidence. Static selector and whitespace checks pass. No tests or
builds were run.