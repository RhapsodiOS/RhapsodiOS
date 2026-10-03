# Task 3 page-boundary helper evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

IDA at `0x1914` (`doesCrossPage`) loads `page_mask`, complements it, masks the starting address and `address + length - 1`, and returns whether those masked values differ. The implementation preserves unsigned 32-bit wraparound and has no special zero-length branch. The test fixture uses `page_mask = 0xfff`; production links the kernel's `page_mask` symbol.

| Address | Length | Expected |
|---:|---:|---|
| `0x1000` | 260 | no crossing |
| `0x1efc` | 260 | no crossing |
| `0x1efd` | 260 | crossing |

The production helper is called directly by the test suite; all three cases pass.
