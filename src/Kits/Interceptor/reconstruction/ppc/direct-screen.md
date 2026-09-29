# PowerPC `NSDirectScreen`

Reference: `Frameworks/Interceptor.framework/Versions/A/Interceptor`, opened
in IDA as the PowerPC image. Relevant functions include `shieldDisplay` at
`0x47A092C0`, `unshieldDisplay` at `0x47A09838`, `setPalette:` at
`0x47A0905C`, `setPaletteAtNextBlankingInterval:` at `0x47A09170`, and
`_loadPalette:` at `0x47A09F94`.

The private state uses the same 0x7c-byte layout and palette-support sentinel
at byte 66 as the DR2 i386 image. Palette loading passes packed palette values
to `_IOSetIntValues` with `IOSetTransferTable`; successful loads post
`NSDirectScreenDidChangePaletteNotification` when a fade is not in progress.
The public setters use their own selector names in failure exceptions.

The mode list is cached in private word 4. The framework queries the current
mode and mode count, reads each `IOGetDisplayModeInfo:<index>` record, skips
unavailable entries, and builds mode dictionaries from resolution, depth,
row-byte, refresh-rate, and safe/default fields. If querying the current mode
fails, it creates a fallback dictionary from the framebuffer. Option matching
compares requested key/value pairs, and `bestModeForOptions:` selects the
first match or the first available mode.
`bestModeForFormat:width:height:` prefers safe modes, then an exact encoding
and resolution; its fallback picks the first qualifying larger mode using the
same width/height comparison present in the binary.
`switchToDisplayMode:` requires shielding, unmaps the framebuffer, selects and
commits the requested mode through `IOSelectPendingDisplayMode` and
`IOCommitToPendingDisplayMode`, refreshes framebuffer dimensions, remaps, and
posts the display-mode notification. Gamma changes use the capability bit at
private word 27 and transfer tables through `IOSetTransferTable`.

PowerPC `shieldDisplay` and `unshieldDisplay` follow the same overall state
transitions as DR2 i386. The shield path saves brightness in the double at
private offset 56, loads the palette, marks byte 120 shielded, switches mode
when needed, then copies the framebuffer to the backing store. The backing
store allocator reserves two page-size margins and returns a pointer one page
into the allocation; destruction frees the original base address. The source
implements the recovered window and brightness sequence, pending runtime
verification against a compatible guest.

`_canLockWithMode:` forwards to the framebuffer. `_lockWithMode:` and
`_unlock` require byte 120 to indicate a shielded display before forwarding;
an unshielded call raises `NSDirectScreenDisplayIsUnshieldedException` with
the invoked selector.
The obsolete `colorSpace` and `data` accessors alias `colorSpaceName` and
`bitmapData`.

Fade operations update the palette through the same transfer-table path.
PowerPC timer callbacks apply intermediate palette blends before the final
palette at the end of the fade. Fade start and completion notifications
bracket the synchronous run-loop timer sequence.
