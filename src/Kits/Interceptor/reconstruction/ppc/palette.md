# PowerPC palette evidence

`NSDirectPalette` stores a mutable copy of its input array and an optional
cached `NSData` machine palette in its private eight-byte state. Changing one
or more colors releases the cached data. `init` builds the reference's 256
entries: the six-level RGB cube with its duplicate black removed, ten
single-channel values for each primary, ten gray values, and white.

The newer PPC image adds `defaultColorPalette` and `defaultGrayPalette`.
`currentPalette` selects between them from `NSDirectScreen`'s pixel encoding,
and falls back to the color palette for an unrecognized encoding. The raw
palette packs gamma-corrected red, green, and blue plus gamma-corrected
luminance into a native 32-bit word. The recovered constants are gamma 1.8,
scale 255, offset 0.499999, and luminance weights 0.30 red, 0.59 green, and
0.11 blue. Build and runtime confirmation remain pending.
