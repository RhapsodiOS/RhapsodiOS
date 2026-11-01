# Foundation `NSInvocation` Distributed-Object Wire Design

## Goal

Replace the local `NSCoder` stream currently used by `NSInvocation` with the
distributed-object argument protocol observed in the DR2 i386 and MOSXS PPC
Foundation binaries. Preserve the frame allocation and ownership behavior
already reconstructed in the preceding `NSInvocation` slice.

## IDA evidence

### i386 (`Foundation-i386`)

- `-[NSInvocation encodeWithCoder:]`: `0x4252b37c`.
- `-[NSInvocation initWithCoder:]`: `0x42573dc0`.
- `+[NSInvocation _preInitWithCoder:signature:valid:wireSignature:target:selector:argCount:]`:
  `0x42551260`.
- `-[NSInvocation _postInitWithCoder:signature:valid:wireSignature:target:selector:argCount:]`:
  `0x42549a80`.
- `+[NSInvocation newInvocationWithCoder:]`: `0x425511c8`.

### PPC (`Foundation`)

- `-[NSInvocation encodeWithCoder:]`: `0x42525104`.
- `-[NSInvocation initWithCoder:]`: `0x425845d4`.
- `+[NSInvocation _preInitWithCoder:signature:valid:wireSignature:target:selector:argCount:]`:
  `0x4253bc3c`.
- `-[NSInvocation _postInitWithCoder:signature:valid:wireSignature:target:selector:argCount:]`:
  `0x4253c678`.
- `+[NSInvocation newInvocationWithCoder:]`: `0x4253b844`.

The selector set and method encodings already exist in the shared and PPC ABI
records. The implementation should not add selectors or change the 36-byte
instance layout.

## Wire format

`encodeWithCoder:` emits the following header in order:

1. Target, encoded as `@`.
2. Method argument count, encoded as `I`.
3. Selector, encoded as `:`.
4. Method type string, encoded as `*`.
5. The `NSObjCValue.type` return tag, encoded as `i` from the start of the
   `returnValue` ivar.

Arguments begin at index 2 and follow the method signature's argument records.
For ordinary types, encode the argument value using its recorded ObjC type
string. For pointer arguments (`^T`), encode a `c` flag that is true when the
pointer is null; when non-null, encode the value at the pointer using `T`.
The target's type-dispatch switch determines how to marshal the ordinary
scalar, object, aggregate, and pointer cases; use the coder's existing typed
value methods for the actual bytes.

The i386 IDA string operands resolve the fifth header type to `i` and the
pointer-presence type to `c`. `NSPortCoder` already implements the required
typed operations: `@` routes through `encodeObject:isBycopy:isByref:` or
`decodeRetainedObject`, integer encodings use its compact integer stream, and
other encodings use `NSGetSizeAndAlignment` followed by raw bytes. No
`NSPortCoder` changes are needed for this slice.

## Receive path

`_preInitWithCoder:...` decodes the first four fields above. It creates a
`NSMethodSignature` from the decoded C type string, asks the target for its
current signature, and compares the signatures by identity. On a match it
returns the target signature and sets `valid`. Otherwise it logs the
incompatibility when both signatures exist, releases the target signature,
returns the decoded wire signature, and clears `valid`. It frees the temporary
decoded C string through `NSZoneFromPointer`/`NSZoneFree`.

`_postInitWithCoder:...` decodes the `i` return tag into the `returnValue`
storage. It allocates and zeroes return storage for compound return types,
establishes an owned argument frame only if no inline frame was preinstalled,
sets the selector and target in argument slots 1 and 0, and decodes arguments
from index 2 onward.

For a non-null pointer argument, allocate storage sized for `T`, retain its
backing `NSMutableData` in the invocation's container array, set the argument
slot to the storage bytes, then decode `T` into those bytes. Preserve the
target-specific pointer cleanup: i386 calls `_NSParseAndAutorelease` on the
decoded pointee representation; PPC calls `autorelease_pointers` for the
current argument record and frame. The null flag leaves the pointer slot null.

The paired i386 and PPC pre-init bodies decode the same four header fields,
perform the same target-versus-wire signature identity check, and free the
temporary C type string through its pointer zone. The paired post-init bodies
decode the `i` return tag, initialize compound-return storage, establish the
frame when absent, set selector/target slots, and iterate arguments from index
2. PPC obtains each argument into aligned temporary storage and copies it into
the invocation frame via `setArgument:atIndex:`; i386 decodes directly into
the measured argument offset. Keep those architecture-specific frame paths.

The PPC ordinary-argument scratch is 16-byte-aligned stack storage, matching
the target's temporary decode buffer; it is not zone-allocated and must not be
freed. For a decoded non-null pointer argument, keep the pointee alive through
the container-backed `NSMutableData`, run the PPC pointer-autorelease walk,
and copy the pointer slot into the invocation frame with
`setArgument:atIndex:`. The PPC null-flag branch reaches that setter without
writing the stack pointer slot used as its source; the source reconstruction
initializes that slot to null to preserve the encoded null value instead of
propagating indeterminate stack contents. Keep the pointer slot in the
enclosing argument-loop scope so it remains valid through the post-branch
`setArgument:atIndex:` call on both targets. PPC uses only the record/frame
`autorelease_pointers` walk; keep `_NSParseAndAutorelease` on the i386 branch.
PPC uses only the record/frame `autorelease_pointers` walk; keep
`_NSParseAndAutorelease` on the i386 branch.

`setArgument:atIndex:` also implements the architecture-specific ownership
rules represented by `retainedArgs`: i386 uses `_NSParseAndRelease` and
`_NSParseAndRetain` around the frame copy, while PPC walks nested argument
records, releasing object and C-string slots before replacement and retaining
them afterward. PPC expands struct arguments through their child records and
writes an 8-byte float argument from its 4-byte source as a double. The coder
sets `retainedArgs` after installing target and selector, then clears it around
each PPC setter call so decoded values are not retained twice. `retainArguments`
walks object-bearing arguments and `invalidate` releases them in reverse order.
Both targets route `setArgument:atIndex:-1` to `setReturnValue:`.

`initWithCoder:` runs pre-init followed by post-init on its existing receiver.
`newInvocationWithCoder:` runs the same pre-init, allocates `frameLength`
inline tail bytes, installs the inline frame pointer, then post-initializes and
returns the retained invocation. `NSPortCoder` already dispatches decoded
`NSInvocation` objects through this factory and encodes objects by invoking
`encodeWithCoder:`.

## Scope

- Update the `NSInvocation` coder methods and private helper paths needed for
  the IDA wire protocol. Build the PPC nested argument records and PPC frame
  offsets in `NSMethodSignature.m`, because `NSInvocation` consumes those
  records for struct scattering and ownership walks.
- Keep the existing inline/owned frame selection and `_setArgFrame:` behavior
  from the approved frame-ownership slice.
- Preserve the ABI ivars, selectors, and existing `NSPortCoder` wire-byte
  primitives.
- Do not change invocation dispatch or the separate return-value coding
  selectors.
- Update reconstruction divergence notes only after implementation confirms
  the target behavior.

## Verification

- Compare both targets' type-dispatch cases before coding.
- Perform a static source review against the five header fields, each argument
  path, and pointer storage lifetime.
- Run `git diff --check` and the static source-to-ABI selector inventory for
  `NSInvocation`; do not add or run tests or builds.
- Object-level ABI verification remains unavailable without a Foundation
  build.
