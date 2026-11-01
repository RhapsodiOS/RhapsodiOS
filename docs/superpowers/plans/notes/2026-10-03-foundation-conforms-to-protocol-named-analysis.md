# Foundation protocol-name conformance selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDistantObject.json`, and the
project's Objective-C `Protocol` implementation.

## Exact-owner selector gaps

The ABI assigns `_conformsToProtocolNamed:` to both
`Object(NSConformsToProtocolNamed)` and
`NSObject(NSConformsToProtocolNamed)`, with type `c12@8:12r*16`. IDA locates
the NSObject and Object implementations at `0x42569a94` and `0x4256a52c`.
Both copy the C-string argument into the `protocol_name` field of a stack
protocol-shaped value and send `conformsToProtocol:` to the receiver's class
object. The source now defines each method in its exact category owner.

IDA's `__NSClassConformsToProtocol` at `0x42524298` walks the class hierarchy
and each class's adopted protocol list, sending `conformsTo:` from each
registered protocol to the supplied protocol value. The local
`_NSClassConformsToProtocol` helper previously compared protocol pointers
directly. It now uses the same `Protocol -conformsTo:` dispatch, whose source
implementation compares protocol names and recursively checks inherited
protocols.

Static exact-owner and whitespace checks only; no tests or builds were run.

## Legacy `Object` category field initialization

The i386 `-[Object _conformsToProtocolNamed:]` at `0x4256a52c` and PPC
implementation at `0x42577468` both store the argument in the second word of
the stack protocol-shaped value and pass its address without initializing the
first word. The source initializes that word (`class_pointer`) to `Nil`.
This is behaviorally equivalent for this call path: `Protocol -conformsTo:`
reads only the argument's `protocol_name` field, compares its string, and
recurses through registered protocol lists; it does not inspect the first
word. Keep the initialized source value rather than introduce an indeterminate
stack field solely to mirror the omitted store.
