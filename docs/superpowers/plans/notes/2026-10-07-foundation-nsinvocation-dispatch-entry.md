# NSInvocation invoke dispatch entry (2026-10-07)

The DR2 i386 -[NSInvocation invoke] body at 0x42526400 and MOSXS PPC
body at 0x4253d840 both fetch selector argument 1 and target argument 0
through getArgument:atIndex:. This matters on PPC: the signature's cached
argument records place self and _cmd at frame offsets 128 and 132, rather
than byte offsets 0 and 4. NSInvocation.m now reads those logical slots
through the accessor.

Both target bodies then check [target isProxy] and
[target willForwardSelector:selector]; when both are true they call
forwardInvocation: with the current invocation and return before entering
the normal dispatch path. The source now follows that branch. The private
willForwardSelector: declaration is local to NSInvocation.m; the method is
implemented by NSProxy and does not change the ABI.

Static paired IDA/source review and git diff --check only; no tests or builds
were run.

## Invocation entry guard parity

The paired `invoke` bodies begin by calling `getArgument:atIndex:` for the
selector and receiver, then perform the proxy check. They do not check the
`signatureValid` bit or reject a null selector. `getArgument:atIndex:` itself
checks for a null frame on both targets (i386 `0x42517698`, PPC `0x42514020`).
Removed the duplicate frame check and the source-only signature-valid and
null-selector checks from `invoke`; frame errors now come from the accessor.
Static paired IDA/source review and `git diff --check` only; no tests or builds
were run.

## PPC dispatch argument size

The PPC invoke body initializes its dispatch size from
signature->_sizeofParams - 128 (0x4253d840); the first 128 bytes of the
signature frame are the PPC register-save area. i386 passes the full
_sizeofParams (0x42526400). The source computes an architecture-specific
dispatch size and uses it for ordinary void, scalar, and floating-point
objc_msgSendv calls.

## Nil-target forwarding behavior

Both i386 `-[NSInvocation invokeWithTarget:]` (`0x42525be4`) and PPC
(`0x425846b8`) only store the supplied target in argument slot 0 and call
`invoke`; neither checks for nil. Neither `invoke` body checks its target for
nil before dispatch. Removed the source's nil-target exceptions from both
entry points. A nil receiver now follows the runtime's nil-message behavior.
Static paired IDA/source review and `git diff --check` only; no tests or builds
were run.

## Aggregate return calling convention

Both switch dispatchers select the return case from the invocation's
`returnValue.type` byte (i386 `0x42526400`, PPC `0x4253d840`), rather than
classifying the raw method-signature encoding again. `NSInvocation.m` now
dispatches from that initialized tag and strips qualifiers only when obtaining
the size of the encoded return type.

The i386 `'{` jump-table entry from `-[NSInvocation invoke]` at `0x42526400`
lands at `0x425268f4`. It checks `_isReturnStructInRegisters` at `0x4252690e`.
Register returns of length eight capture EAX:EDX into the invocation's existing
`structLocation` (`0x42526920`–`0x42526959`); other register returns store EAX
(`0x42526964`–`0x42526996`). For a hidden result, the target puts
`structLocation` in EBX and calls `objc_msgSendv` with receiver, selector,
dispatch size, and the original argument frame (`0x42526998`–`0x425269c1`).

PPC `invoke` (`0x4253d840`) uses the same register-vs-hidden-result split.
The eight-byte branch stores r3/r4 through the existing `structLocation`
(`0x4253dc28`–`0x4253dc3c`); smaller register results store r3
(`0x4253dc68`–`0x4253dc78`). Its hidden-result call passes the result pointer
in r3, receiver in r4, selector in r5, dispatch size in r6, and the original
argument frame in r7 (`0x4253dc7c`–`0x4253dca8`).

`NSInvocation.m` now dispatches from the stored return tag, preserves the
preallocated return storage, captures register-returned aggregates by their
target width, and uses architecture-specific call setup for hidden results.
This replaces the previous source-only prepended-frame hypothesis. Static
paired IDA/source review only; no tests or builds were run.

## Argument fixups and return ownership

The paired `-[NSInvocation invoke]` bodies also build the dispatch frame from
`signature->_sizeofParams` (subtracting the PPC 128-byte register-save area),
then walk argument indices 2 through `numberOfArguments - 1`. For each nonzero
`_fixup[index]`, they subtract that argument record's size from the dispatch
length and write `argumentFrame + info.offset` into the fixup slot. The source
now performs the same target-independent pointer fixups before entering the
dispatch handler.

Both targets add an exception handler before releasing any previous non-void
return value and invoking the method. A dispatch exception is removed from the
handler stack and re-raised; successful calls retain the returned value and
remove the handler normally. For object-returning `performSelector:` variants,
the target asks the receiver for the invoked method's signature and retains by
that return encoding when available, skipping retain for `void`; otherwise it
uses the invocation signature. `NSInvocation.m` now follows that path. Return
cleanup frees C-string and struct storage and releases typed pointees for
pointer returns as in `invalidate` (i386 `0x425262bc`, PPC `0x425204d0`).
Static paired IDA/source review and whitespace checks only; no tests or builds
were run.

## `NSInvocation -invalidate` architecture-specific return cleanup

Rechecking i386 `0x425262bc` and PPC `0x425204d0` corrects the earlier summary: both targets free allocated storage for typed pointer returns after the non-void pointee path, and both free C-string and struct storage. i386 also calls `_NSParseAndRelease` on typed pointer pointees and struct contents before freeing; PPC frees those return buffers directly. `^v` pointer storage is left untouched on both targets. `NSInvocation.m` now follows this split. Static paired IDA/source comparison only; no tests or builds were run.
## `NSInvocation -description` format and message order

The i386 method at `0x42573d50` and PPC method at `0x4258453c` first obtain the selector with `-selector`, then call `+[NSString stringWithFormat:]` with `<NSInvocation[0x%x] selector: %s signature: %@>`, the invocation, its selector, and its method signature. The source now uses that format and preserves the selector-before-signature read order. Static paired IDA/source review only; no tests or builds were run.
## `NSInvocation -dealloc` cleanup order

The i386 body at `0x4251fe28` and PPC body at `0x42521370` both call `-invalidate`, release a nonnull container, free the argument frame only when its ownership flag is set, release the method signature, then call `NSObject -dealloc`. The current `NSInvocation.m` deallocator follows that order. Static paired IDA/source review only; no tests or builds were run.
## PPC `NSInvocation -setArgument:atIndex:` diagnostic logging

PPC `0x42532ad0` checks the shared logging-depth counter after writing the argument frame and before retaining pointer-bearing values. When nonzero it calls `NSLog` with `Invocation %x setArgument:(%x) atIndex:%d to frame offset %x`, passing the invocation, the first input word, index, and argument-frame offset. i386 `0x42525a38` has no matching log call. The source now emits this diagnostic only in the PPC path and reuses `+[NSInvocation _enableLogging:]`'s counter. Static paired IDA/source review only; no tests or builds were run.
## NSInvocation -setArgument:atIndex: null-location error text

Both targets, i386 0x42525a38 and PPC 0x42532ad0, raise NSInvalidArgumentException with the fixed text "setArgument not supplied with pointer to location" when the argument pointer is null. The source now uses that exact message without adding a method proem. Static paired IDA/source review only; no tests or builds were run.
## `NSInvocation -invoke` logging gate

The i386 body at `0x42526400` and PPC body at `0x4253d840` log after normal dispatch and return-value retention, once the exception handler is removed. With the shared `_enableLogging:` depth nonzero, they call `NSLog` using `invokeWithTarget: return type '%c' value %x`, passing the invocation return-type tag and first 32-bit return-value word. Proxy forwarding returns before this log; a rethrown exception does not reach it. `NSInvocation.m` now follows this placement and gate. Static paired IDA/source review only; no tests or builds were run.

## Full dispatch lifecycle recheck (2026-10-07)

Rechecked the complete i386 `-[NSInvocation invoke]` body at `0x42526400`
and PPC body at `0x4253d840` against the source. Both read selector and target
through `getArgument:atIndex:`, forward proxies only when both `isProxy` and
`willForwardSelector:` succeed, patch nonzero argument fixups before creating
the exception handler, dispatch by the initialized return tag, remove the
handler on success, and rethrow the captured exception on failure. Return
ownership differs by architecture: i386 releases a previous non-void result
inside the handler and retains the successful new result, setting `retainedRet`.
PPC retains each successful non-void result and sets `retainedRet`, without
first releasing a previous result. For object returns from `performSelector:`
variants, PPC consults the invoked method signature when available and skips
retention only for `v`/`V` returns. `invokeWithTarget:` stores the replacement
receiver in argument slot zero and calls `invoke`. Static paired IDA/source
comparison and whitespace validation only; no tests or builds were run.


## Forward trampoline invalid-return path (2026-10-07)

The i386 `-[NSObject(NSForwardInvocation) forward::]` body at `0x42520010`
and PPC body at `0x425254c4` dispatch on the `NSObjCValue.type` returned by
`-[NSInvocation _returnValue]`. Their default branch raises
`NSInternalInconsistencyException` with `*** unknown return type %u`; the
void case is separate. The source previously returned the union's `longValue`
for both `NSObjCNoType` and unrecognized values. It now raises the target
exception for those cases. Static paired IDA/source comparison and
`git diff --check` only; no tests or builds were run.


## Architecture-specific forwarding return lanes (2026-10-07)

Implemented the return dispatch from the i386 `0x42520010` and PPC
`0x425254c4` bodies in `NSObject(NSForwardInvocation) -forward::`. Float and
double results are placed in x87 `ST(0)` on i386 and `f1` on PPC. The i386
path calls `_structure_addr()` before dispatch, copies small aggregate results
to the two integer return words, and copies large aggregates to the hidden
result buffer. PPC reads its hidden aggregate destination from `argFrame +
128`; the return value remains in `r3/r4` as in the target epilogue. Scalar
integer, pointer, object, and selector values now use the matching low return
words, and unknown tags raise the target exception. The category's `q` method
encoding is unchanged. Static paired IDA/source comparison and
`git diff --check` only; no tests or builds were run.


## `setReturnValue:` keeps the initialized dispatch tag (2026-10-07)

DR2 i386 `-[NSInvocation setReturnValue:]` (`0x42573f68`) and MOSXS PPC
(`0x42540bec`) call `skipQualifiers2` on the signature type, then dispatch
on the invocation's existing `returnValue.type` field. The target setter
does not replace that tag with the raw signature byte. `NSInvocation.m` now
preserves the normalized tag established by initialization and copies only
the value storage, keeping `C`/`i` signatures on their internal char/long
dispatch paths. Static paired IDA/source review and `git diff --check` only;
no tests or builds were run.


## Return-value coder helpers (2026-10-07)

The paired `encodeReturnValueWithCoder:` bodies (i386 `0x42557650`, PPC
`0x425394f4`) encode the typed result from the invocation storage (the
`structLocation` pointer for compound returns), then encode argument records
from index 2. The paired decoder bodies (i386 `0x4252d328`, PPC
`0x425249d4`) select the result lane from the existing normalized tag and
decode the same argument records. They do not encode or consume an extra
integer type tag in these helpers. `NSInvocation.m` now matches these paths;
the ordinary `encodeWithCoder:` / `_postInitWithCoder:` entry points share
the reconstructed argument-record helpers. Static paired IDA/source review
and `git diff --check` only; no tests or builds were run.

## Overlap-safe return-value copies (2026-10-08)

PPC IDA `-[NSInvocation setReturnValue:]` at `0x42540bec` calls `_memmove`
for both scalar and aggregate return storage. Updated the corresponding two
source copies from `memcpy` to `memmove`, preserving behavior when the input
overlaps the invocation's existing return storage. The retained-argument and
invalidation ownership paths were also checked against both target bodies and
showed no mismatch. Static source and whitespace checks only; no tests or
builds were run.

## Approved full dispatch lifecycle recheck (2026-10-08)

After approval to implement the full lifecycle correction, re-decompiled the
current i386 `-[NSInvocation invoke]` (`0x42526400`) and PPC body
(`0x4253d840`) in the live IDA databases and compared them with `NSInvocation.m`.
The source preserves their shared accessor/proxy/fixup/exception flow and
`invokeWithTarget:` slot update. That comparison had incorrectly overlooked
PPC's post-dispatch `_NSParseAndRetain` and retained-return flag; the 2026-10-08
correction below now implements it. Static paired IDA/source comparison only;
no tests or builds were run.

## Float return extraction correction (2026-10-08)

The paired initializers classify `f` and `d` return encodings into distinct
`NSObjCFloatType` and `NSObjCDoubleType` tags, and `invoke` dispatches from the
stored tag. `NSInvocationDispatchMessage` previously called both cases through
a `double` return prototype, then copied only four bytes for a float. That
copies part of a double representation rather than a float representation.
Split the calls so the float case uses a `float` return prototype and copies
`sizeof(float)`, while the double case uses `double`. `git diff --check` passed;
no tests or builds were run.

## PPC narrow integer return extraction (2026-10-08)

The PPC `-[NSInvocation invoke]` switch at `0x4253d840` stores char returns
with `stb r3, 8(r9)` and short returns with `sth r3, 8(r9)`; its long and
pointer cases use `stw r3`, and its 64-bit case stores `r3` and `r4`. The
previous source fallback read all non-floating scalar results through an
`unsigned long long` and copied the first `NSGetSizeAndAlignment` bytes. On
big-endian PPC that selects the high bytes of the 64-bit value for char and
short. Added `unsigned char` and `unsigned short` dispatch calls so those
results are narrowed from the target's low bits before storing. No tests or
builds were run.

## Overlap-safe return-value copies (2026-10-08)

PPC IDA `-[NSInvocation setReturnValue:]` at `0x42540bec` calls `_memmove`
for both scalar and aggregate return storage. Updated the corresponding two
source copies from `memcpy` to `memmove`, preserving behavior when the input
overlaps the invocation's existing return storage. The retained-argument and
invalidation ownership paths were also checked against both target bodies and
showed no mismatch. Static source and whitespace checks only; no tests or
builds were run.
