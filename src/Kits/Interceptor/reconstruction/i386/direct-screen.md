# DR2 i386 `NSDirectScreen`

Reference: `Frameworks/Interceptor.framework/Versions/A/Interceptor`, opened
in IDA as the DR2 i386 image. Relevant functions include `initWithScreen:` at
`0x47A046AC`, `setPalette:` at `0x47A06D8C`,
`setPaletteAtNextBlankingInterval:` at `0x47A06E80`, `_loadPalette:` at
`0x47A07C30`, and `shieldDisplay`/`unshieldDisplay` at `0x47A06F90` /
`0x47A0748C`.

`initWithScreen:` allocates a 0x7c-byte private state, initializes the
framebuffer, creates the Interceptor context, obtains device access tokens,
stores the master port and IO object number at words 17 and 18, and creates the
initial palette at word 8. `IO_Framebuffer_Dimensions` fills word 27 when the
IO query succeeds. The screen mode cache is cleared separately.

Palette support is cached in byte 66: `0xff` means unknown, and only an
8-bits-per-pixel screen supports setting a palette. The first successful
check sends asynchronous `DamagedPalette` (message 7216). `_loadPalette:`
passes the palette's packed machine values to `_IOSetIntValues` with parameter
`IOSetTransferTable`. A successful load posts
`NSDirectScreenDidChangePaletteNotification` when a fade is not in progress.
Both public palette setters perform the same load sequence, with the selector
name used in their exception reason.

The mode list is cached in private word 4. The framework reads the current
mode, obtains the mode count, queries each `IOGetDisplayModeInfo:<index>`
record, skips unavailable entries, and constructs dictionaries from the
resolution, depth, row-byte, frequency, and safe/default fields. If the
current-mode query fails, it builds a one-entry fallback from the framebuffer.
Option filtering compares every requested key/value pair, and
`bestModeForOptions:` returns the first match or the first available mode.
`bestModeForFormat:width:height:` prefers safe modes, then an exact encoding
and resolution; its fallback picks the first qualifying larger mode using the
same width/height comparison present in the binary.
`switchToDisplayMode:` requires shielding, unmaps the framebuffer, selects and
commits the requested mode through `IOSelectPendingDisplayMode` and
`IOCommitToPendingDisplayMode`, refreshes framebuffer dimensions, remaps, and
posts the display-mode notification. Gamma changes use the capability bit at
private word 27 and transfer tables through `IOSetTransferTable`.

The source implements the recovered shield/unshield sequence: create and
raise a full-screen borderless window, preserve and suppress auto-dimming,
load the selected palette, switch modes if necessary, copy framebuffer data,
and toggle byte 120. Unshield reverses the mode, palette, window, and
brightness changes. Window-server runtime behavior is not yet verified.

Fade operations update the palette through the same transfer-table path. The
DR2 i386 timer callbacks apply the final palette when the duration expires;
the reference callbacks do not interpolate intermediate palettes. Fade start
and completion notifications bracket the synchronous run-loop timer sequence.

`_canLockWithMode:` forwards to the framebuffer. `_lockWithMode:` and
`_unlock` both require byte 120 to indicate a shielded display before
forwarding to the framebuffer; an unshielded call raises
`NSDirectScreenDisplayIsUnshieldedException` using the invoked selector.
The obsolete `colorSpace` and `data` accessors alias `colorSpaceName` and
`bitmapData`.
