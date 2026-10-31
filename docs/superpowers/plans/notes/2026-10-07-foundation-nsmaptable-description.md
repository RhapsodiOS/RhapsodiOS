# `NSStringFromMapTable` reconstruction

Paired IDA decompilation of DR2 i386 (`0x425637bc`) and MOSXS PPC
(`0x4256de94`) confirms that `NSStringFromMapTable` returns
`<NSMapTable: 0x%x> {}` for an empty table. For nonempty tables, it allocates
an autoreleased mutable string with capacity `count << 6`, appends
`<NSMapTable: 0x%x> {`, and visits occupied buckets in descending order.

For each pair, the key is appended first, then ` = `, then the value, then
`;\n`. A configured describe callback's result is inserted directly at the
current end of the string without a nil fallback. Without a callback the raw
pointer is formatted as `0x%x`. The closing `}` follows the final entry
separator, with no extra newline. `NSMapTable.m` previously used a different
brace/newline layout, `%p`, and nil-description fallbacks; it now follows both
target implementations. The i386 disassembly confirms the capacity shift by
six (`shl edx, 6`), matching PPC's `count << 6`.

Static paired IDA/source review only; no tests or builds were run.
