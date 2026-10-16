# Foundation `NSCharacterSet` dictionary conversion

Paired IDA references: Foundation-i386 `NSMakeSetBitmapFromSet` at
`0x42591680` and `NSMakeSetFromDictionary` at `0x42591764`; Foundation-PPC
`NSMakeSetBitmapFromSet` at `0x4255e880` and `NSMakeSetFromDictionary` at
`0x425a8ca8`.

Both dictionary converters read `nsingles`, `nranges`, `singmin`, and
`singmax`, allocate `36 + 4 * nsingles + 8 * nranges` bytes, and populate the
temporary set's values from the flattened `singles` and `ranges` arrays. The
range array begins immediately after the single values. The converter zeroes
the four masks, builds a bitmap, frees the temporary set, compacts the bitmap
back to a set structure, and frees the bitmap. A nil dictionary returns an
empty type-1 set with `singleMin = 0xffff`.

Both bitmap converters read singleton values and range lower bounds as
16-bit values, while range upper bounds are read as 32-bit values. The i386
loop increments a 16-bit register; PPC narrows its increment result to
16 bits. `NSCharacterSetSetCopyToBitmap` now initializes a 16-bit cursor from
the range lower bound and keeps that cursor width during iteration. This
preserves the target loop's wrap behavior for an upper bound of `0xffff`.

No tests or builds were run. `git diff --check` and direct source whitespace
checks are the static verification for this slice.
