# `NSPortCoder` Fast Writer Table Design

## Goal

Reconstruct the exported `_NSFastFuncList` data object and connect
`NSConcretePortCoder`'s writer stream to its four IDA-confirmed callbacks on
both DR2 i386 and MOSXS PPC.

## Target evidence

Both Foundation images export `_NSFastFuncList` as four function pointers in
this order: fast byte, fast integer, C string, and raw data. The i386 table is
at `0x42602480`; the PPC table is at `0x426263ac`. PPC entries resolve to
`_encodeFastByte`, `_encodeFastInt`, `_encodeFastCharStar`, and
`_encodeFastData` at `0x4250cb94`, `0x4250d0e8`, `0x425133d8`, and
`0x4252c0dc`. The callback context stores cursor, end, allocation base, and
table pointer at offsets 4, 8, 12, and 16. The integer callback's return ABI
differs by target: i386 returns the encoded byte count, while PPC returns a
pointer. The byte, string, and data callbacks return pointers. The string
callback writes a presence byte, a length including the terminal NUL, and the
string bytes through the corresponding table entries.

Both targets serialize integer payloads little-endian. i386 copies its native
little-endian bytes; PPC reverses bytes from its big-endian native values, and
its read helper reverses the payload back into the native value. The reader's
zero-length marker remains valid on both targets.

The i386 IDA callers read the table through the pointer slot from
`encodeObject:isBycopy:isByref:`, `initWithConnection:components:msgid:`, and
`encodeDataObject:`. In the current source, `NSPortCoderFastFunctions` has
eight read/write entries, is assigned to the stream's table field, and is not
used for dispatch; writer helpers call one another directly.

## Design

Define the exported four-entry table in `NSPortCoder.m` with an
architecture-specific integer callback return type. Reuse the existing writer
algorithms for capacity growth, compact signed integers, C strings, and raw
byte spans; adapt integer byte order and callback returns to each target. Keep
the direct read helpers and their validation behavior, including PPC's
little-endian payload reversal. Set the stream's function-table field to
`_NSFastFuncList` and route the writer helpers through its four slots. Do not
route read operations through the four-entry writer table or change unrelated
serialization behavior.

The source's existing eight-entry table can be removed if a final source
search confirms it has no remaining users after the writer dispatch is
connected. Do not preserve a second table solely for compatibility with the
current implementation: the target stream field points to the exported
four-entry table.

## Scope

- Modify `NSPortCoder.m`.
- Add `_NSFastFuncList` to the shared `NSPortCoder` ABI data-symbol list,
  `symbols.json`, and `ownership.json`.
- Keep the source owner `NSPortCoder.m`; the export exists in both target
  architectures, so no PPC-only manifest entry is required unless the
  architecture-specific inventory reports a signature or availability
  difference.
- Compare every callback and confirmed call site with both IDA databases.
- Run JSON and whitespace checks only; no tests or builds.

## Review constraints

- Confirm each callback's exact source-level return type and argument width
  from IDA before implementation.
- Preserve the target's context offsets and allocation-zone lookup.
- Preserve the all-zero integer encoding already corrected in
  `NSPortCoderWriteFastInt`.
- Keep read-side helpers and serialized byte order unchanged.
