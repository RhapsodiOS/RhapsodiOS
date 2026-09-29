# PowerPC shape evidence

The primary PPC implementation stores regions as signed 16-bit scanline
events. The leading `-32768, 2` pair describes the empty band before the first
region; each following event is a y coordinate, a short-count to the next y
event, and an even list of x edges. `32767` terminates the list. A rectangle is
serialized as the leading empty band, a top event with two x edges, a bottom
event with count two, and the terminator. The enumerator walks y bands, then
x edge pairs from left to right.

`_rect_shape` truncates float coordinates toward zero when storing short
boundaries, normalizes negative width/height by shifting the origin and
negating the extent, and returns the six-byte empty shape when either extent
is exactly zero. It otherwise preserves a rectangle whose distinct float
edges truncate to the same short. Equality compares the serialized short
lists. `offsetShape:` truncates its float offsets toward zero and adjusts all
y events and x edges in place.

The union, intersection, and difference helpers sweep both inputs' y and x
edges, emit only changes in the resulting edge set, and coalesce adjacent y
bands with identical x edges. The implementation in `NSShape.m` follows that
representation. The function-level disassembly supports the format and
coalescing behavior; geometry tests remain unrun without the historical guest.

| Function | Address | Source mapping |
|---|---:|---|
| `_empty_shape` / `_rect_shape` | `0x47A0CA64` / `0x47A0CAA0` | `NSShape.m` |
| `_is_equal_shape` / `_is_empty_shape` | `0x47A0CBFC` / `0x47A0CC68` | `NSShape.m` |
| `_offset_shape` | `0x47A0CCAC` | `NSShape.m` |
| `_union_shape` / `_intersect_shape` / `_difference_shape` | `0x47A0CD0C` / `0x47A0D040` / `0x47A0D33C` | `NSShape.m` |
| `-[NSShape description]` | `0x47A0DA30` | not yet reconstructed |
