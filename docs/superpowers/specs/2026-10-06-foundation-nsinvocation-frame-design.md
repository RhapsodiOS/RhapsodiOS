# Foundation `NSInvocation` Argument-Frame Design

## Goal

Reconstruct the PPC and i386 `NSInvocation` construction paths so inline
argument frames, separately allocated frames, coder construction, and forwarded
runtime frames follow the ownership and copy behavior observed in the two
Foundation binaries.

## Evidence

The current MOSXS PPC Foundation database confirms:

- `+[NSInvocation newInvocationWithMethodSignature:]` at `0x42523884`
  calls `NSAllocateObject` with `frameLength` extra bytes, stores the inline
  frame address at `object + class.instance_size`, then calls
  `initWithMethodSignature:` and returns the initialized object.
- `+[NSInvocation invocationWithMethodSignature:]` at `0x4258220c` calls the
  new factory and autoreleases its result.
- `+[NSInvocation newInvocationWithCoder:]` at `0x4253b844` uses the same
  inline extra-byte allocation, then calls `_postInitWithCoder:...` and returns
  that result without autoreleasing it. `-[NSInvocation initWithCoder:]`
  calls `_preInitWithCoder:...` and then `_postInitWithCoder:...` on its
  existing receiver.
- `-[NSInvocation initWithMethodSignature:]` at `0x42525774` retains the
  signature and calls `_establishArgumentFrame` only if the frame pointer is
  null, without calling superclass `init`. It initializes the return-value tag
  from the method return encoding; struct returns receive zeroed return
  storage. A nil signature follows the target's superclass-deallocation path
  and returns nil.
- `_establishArgumentFrame` at `0x425868e8` allocates `frameLength` bytes from
  `[self zone]`, zeroes them, stores the pointer, and sets bit `0x08000000` in
  the flags word at offset 28.
- `-[NSInvocation dealloc]` at `0x42521370` frees the frame only when that bit
  is set. Inline bytes in the object tail are therefore not freed.
- `-[NSInvocation _setArgFrame:]` at `0x42523908` copies the supplied frame
  into the invocation's existing frame for `frameLength` bytes; it does not
  replace the frame pointer.
- The PPC coder factories allocate inline frame storage before post-init. The
  instance coder path establishes an owned frame when the caller supplied no
  inline frame.

The current DR2 i386 database confirms:

- `+[NSInvocation invocationWithMethodSignature:]` at `0x4251fbb0` performs
  the inline allocation directly, calls `initWithMethodSignature:`, and
  autoreleases the result. The i386 image has no
  `newInvocationWithMethodSignature:` selector.
- `+[NSInvocation newInvocationWithCoder:]` at `0x425511c8` uses inline
  extra-byte allocation and returns the post-initialized result without
  autoreleasing it. `-[NSInvocation initWithCoder:]` calls the pre/post-init
  helpers on its existing receiver.
- `-[NSInvocation initWithMethodSignature:]` at `0x4252298c` has the same
  preserve-if-preinstalled-frame and return-type initialization behavior and
  does not call superclass `init`. A nil signature follows the
  superclass-deallocation path and returns nil.
- `_establishArgumentFrame` at `0x425757f4` allocates from `[self zone]`,
  zeroes the frame, and sets bit `0x10` in the flags byte at offset 28.
- `-[NSInvocation dealloc]` at `0x4251fe28` frees the frame only when that
  ownership bit is set.
- `-[NSInvocation _setArgFrame:]` at `0x4251faf0` walks the signature's
  argument records and copies each value into the existing frame through
  `setArgument:atIndex:`. A nonzero fixup points to a pointer slot in the
  incoming frame, which the implementation dereferences to get the argument
  address; zero or absent fixups use the cached argument offset.
- The i386 coder factories also allocate inline storage before post-init;
  `initWithCoder:` can instead establish a separately owned frame.

The source currently allocates a separate frame unconditionally in
`initWithMethodSignature:`, frees it when `externalArgFrame` is clear, and
implements `_setArgFrame:` by replacing the frame pointer. These operations
conflict with both targets' inline-frame lifecycle. The ivar name
`externalArgFrame` is ABI-visible and will stay unchanged; source comments will
explain that the bit represents target frame ownership (set means the frame is
freed).

## Design

### Factories and initialization

- Keep `+[NSInvocation invocationWithMethodSignature:]` as an autoreleased
  factory on both architectures.
- On PPC, make that wrapper call a PPC-only
  `+[NSInvocation newInvocationWithMethodSignature:]`. The new factory
  allocates `frameLength` tail bytes, points `argumentFrame` at the first byte
  after the class instance when allocation succeeds, calls
  `initWithMethodSignature:`, and returns the retained result. The PPC method
  type encoding is `@8@4:8@12`.
- On i386, keep the allocation, inline-frame pointer setup, initializer call,
  and autorelease in `invocationWithMethodSignature:` itself. Do not export a
  new factory selector on i386.
- In `initWithMethodSignature:`, retain the signature and preserve a
  preinstalled frame. If no frame exists, use one shared source helper matching
  `_establishArgumentFrame`: allocate from `[self zone]`, zero the
  bytes, and set the ownership bit. Read the signature's private `_types`
  pointer directly because this reconstruction's `methodReturnType` accessor
  allocates a copy. Initialize the return-value tag for the target's recognized
  encodings and raise `NSInternalInconsistencyException` with the target's
  unknown-return format otherwise. Allocate and zero return storage for struct
  returns; invalidation releases its object contents, frees the buffer, and
  clears the pointer. On a nil signature, use the target's
  superclass-deallocation path and return nil. Keep the current source's
  `signatureValid` initialization because its invoke path consumes that
  source-only validity field. Leave `refCount` at zero: the target's retain
  methods pass its 24-bit stored count through the internal reference-count
  helpers, which report stored count plus one.
- In `dealloc`, follow the target cleanup order: invalidate (which releases a
  retained object return value), release the container, free the frame only
  when the ownership bit is set, release the signature, then call superclass
  deallocation. Both target deallocators pass `NULL` to `NSZoneFree`.
- The source reconstruction implements retain/release using the invocation's
  `refCount` field through `_NSIncrementInternalRefCount`,
  `_NSDecrementInternalRefCountWasZero`, and `_NSInternalRefCount`, with mask
  `0xFFFFFF` and no external lock. The stored count remains zero on both
  signature and coder construction, matching the target's initial count of
  one.
- Both source coder initializers also initialize the return-value tag from the
  decoded signature and allocate zeroed storage for struct returns, matching
  `_postInitWithCoder:`'s target behavior.

### Coder and forwarded frames

- Keep the current coder stream protocol and validation behavior in this
  slice. Make `newInvocationWithCoder:` allocate the inline tail frame and
  return its post-initialized object retained, as the target does. In
  `initWithCoder:`, establish an owned destination frame when needed and decode
  the frame bytes into that storage. Make `_postInitWithCoder:...` use the same
  owned-frame helper only when no inline frame was preinstalled. These changes
  choose inline or owned destination storage consistently without replacing an
  inline pointer.
- Implement PPC `_setArgFrame:` as a `frameLength` byte copy into the existing
  destination frame.
- Implement i386 `_setArgFrame:` using the signature's measured argument
  offsets and sizes, forwarding each argument through
  `setArgument:atIndex:` as the target does. A nonzero fixup is an indirect
  pointer slot; zero or absent fixups use the cached offset.
- The `NSInvocationBuilder -forward::` call site continues to pass the runtime
  frame through `_setArgFrame:`. Its destination remains owned by the
  invocation or embedded in the object tail; the supplied runtime frame is
  never adopted or freed.

The exact target distributed-object coder wire format and its argument
marshalling remain a separate reconstruction. Existing source comments already
record that the current stage uses a local coder stream because its NSPortCoder
consumer is not yet reconstructed. This design changes only frame allocation,
copying, and ownership within those existing coder entry points.

### ABI and reconstruction records

- Add `newInvocationWithMethodSignature:` with PPC type encoding
  `@8@4:8@12` to a PPC-only `NSInvocation` ABI overlay.
- Keep the shared `NSInvocation` ABI record architecture-neutral and preserve
  its current 36-byte instance layout and ivar offsets.
- Keep the i386 selector set unchanged. Add the PPC selector owner/source
  mapping and record the architecture difference in `divergences.md`.

## Scope boundaries

- Do not change `NSInvocationBuilder` allocation or `forward::` behavior beyond
  the `_setArgFrame:` interaction required by the target frame-copy contract.
- Do not change invocation dispatch or argument type classification outside
  the constructor's return-value initialization. Reuse constructor-allocated
  struct return storage in `setReturnValue:` so this storage is not leaked.
- Do not reconstruct the distributed-object coder wire protocol or NSPortCoder
  dependencies in this slice.
- Preserve unrelated existing changes in `NSInvocation.m` and reconstruction
  metadata.

## Verification

- Compare each edited branch against the PPC and i386 IDA bodies listed above,
  including inline pointer calculation, frame zeroing, ownership-bit tests,
  return-type tags, coder destination selection, and argument-frame copy rules.
- Parse the shared and PPC ABI JSON records and verify the new selector appears
  only in the PPC overlay, with one source owner.
- Run `git diff --check` for the changed slice and inspect project source
  registration. Do not add or run tests or builds in this reconstruction pass.
