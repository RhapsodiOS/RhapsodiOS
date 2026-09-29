# DR2 i386 palette evidence

DR2 exposes `defaultPalette` and `currentPalette`; it does not contain the two
newer default palette methods. Its default uses the same 256-entry Mac color
table. The current-palette path uses `NSFramebuffer` and recognizes the
eight-bit pseudo-color encoding, otherwise creating an empty palette after
logging the unsupported encoding.

Machine palette words contain gamma-corrected RGB and `0xff` in the low byte.
Because the words are serialized in native byte order, the raw `NSData` byte
order differs from the PPC luminance-bearing entries. Runtime confirmation
remains pending.
