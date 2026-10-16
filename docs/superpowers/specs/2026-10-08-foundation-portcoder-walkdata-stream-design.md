# NSPortCoder Typed-Value Walker Stream Design

## Goal

Route `NSConcretePortCoder`'s typed encode/decode methods through the recovered `_NSWalkData` implementation on both i386 and PPC, preserving the stream callback ABI and recursive Objective-C type behavior confirmed in IDA.

## Evidence

The i386 wrappers are `encodeValueOfObjCType:at:` at `0x42513800` and `decodeValueOfObjCType:at:` at `0x42519760`. PPC wrappers are at `0x4250d2d0` and `0x425112e8`. Each passes operation 1 or 0, pointer walking enabled, the `NSPortCoderStream` address, the value address, and the original type string to `_NSWalkData`.

The 32-bit `NSPortCoderStream` and `NSWalkDataArchiveContext` layouts are compatible: `data/storage` at offset 0, cursor at 4, limit/end at 8, start/reserved at 12, function table at 16, callback at 20, and flags/callbackMode at byte 24. Port streams set `flags` to 1, `callback` to the coder, and `functions` to `_NSFastFuncList`. The generic `NSData` archive contexts set callbackMode to 0 and use an `NSMutableData` receiver.

Port stream callback signatures differ from the generic archive function table: byte takes a byte value, fast integer takes an address and width, and C string takes the string pointer itself. Slot 3 (raw data) is called internally by the C-string writer. On PPC, short values are written through byte callback calls in target order (byte 1 then byte 0); i386 writes byte 0 then byte 1. Decode reuses the shared cursor/limit prefix. Object callback mode dispatches to `encodeObject:isBycopy:isByref:` and `decodeRetainedObject`.

## Design

Keep `_NSWalkData` in `NSSerialization.m`. Add stream-mode dispatch selected by the existing context byte at offset 24. In stream mode, treat the context pointer itself as the callback receiver and invoke callback slots using their target signatures. Use the `start` field at offset 12 as the cursor-offset base. For stream bitfields, emit through the fast-integer callback. Preserve the existing storage receiver, uniform callback signatures, cursor base, and byte serialization for callbackMode 0.

Route both `NSConcretePortCoder` typed-value methods through `_NSWalkData(1/0, YES, &streamData.stream, value, type)`. Keep port-coder object callback and qualifier handling inside `_NSWalkData`, as in the target wrappers. Do not change public headers, ABI manifests, or exported symbols.

## Required behavior

1. Preserve stream cursor advancement and encoded bytes for primitive and C-string values.
2. Preserve target byte order for `s` and `S` on both architectures.
3. Dispatch stream callback slots with their distinct signatures and use slot 3 only inside C-string encoding.
4. Preserve callback-mode object decode/encode and per-walk `O`/`R` qualifier state.
5. Recursively walk arrays, structs, pointers, and bitfields using existing `_NSWalkData` logic.
6. Keep generic `NSData` serialization in callbackMode 0 unchanged.

## Verification

Use paired i386/PPC IDA evidence for the wrapper calls, callback signatures, short-value byte order, and stream field offsets. Perform static source review and `git diff --check`. Do not run tests or builds in this reconstruction pass.
