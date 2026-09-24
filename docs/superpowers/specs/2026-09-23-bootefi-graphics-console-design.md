# bootefi graphics console design

## Goal

Make `src/bootefi-1` draw its boot output the way a legacy boot looks,
instead of printing through the firmware's `ConOut` text console:

- **Window console** (default, and whenever booting verbose): the kernel's
  600x450 "Rhapsody Operating System" window on a dark grey screen, drawn from
  the first booter message, so the look does not change at kernel handoff.
- **Splash** (when the legacy rule for boot graphics holds): boot-2's
  `Panel.image` with a centred "Starting Rhapsody" message and the spinning
  wait cursor, left on screen for the kernel to keep animating.

## Background

- The window in a legacy boot is drawn by the kernel, not the booter:
  `src/kernel-7/bsd/dev/i386/VGAConsole.c` programs VGA mode 0x12 and draws
  the window (`InitWindow`, `TEXT_WIN_WIDTH` 600, `TEXT_WIN_HEIGHT` 450,
  title `mach_title` from `kmDevice.m`) with its compiled-in `ohlfs12` font.
  It does this whenever `kernBootStruct->graphicsMode` is `TEXT_MODE`.
- With `graphicsMode` set to `GRAPHICS_MODE`, `kminit()` (`km.m`) initializes
  the console with `initScreen` false: the kernel does not reprogram or
  redraw anything, and animates its wait cursor into the planar VGA memory at
  0xA0000. The legacy splash only survives handoff because boot-2 left the card
  in mode 0x12 with the panel drawn (`boot2/graphics.c` `setMode`).
- `bootefi-1` today prints through `ConOut`, hands off with `TEXT_MODE`, and
  resets the card to text mode 3 after `ExitBootServices`
  (`efi_vga_reset_text_mode()` in `handoff.c`).

## Approach

Draw directly to VGA mode 0x12 with port and memory I/O from the start of
`efi_main`, using the same planar drawing boot-2 and the kernel use. Once the
card is in mode 0x12 the booter no longer writes to `ConOut` (the firmware's
GOP console would scribble over the shared video memory); booter text goes to
COM1 instead, which the kernel's serial driver takes over once drivers load.

This needs VGA-compatible hardware. The kernel console already does, so the
booter adds no new requirement. Hardware that is not VGA-compatible is out of
scope; no probing is added.

Rejected: drawing through GOP and reprogramming mode 0x12 at handoff (two
renderers, no portability gain past handoff); drawing through GOP and always
handing off in `TEXT_MODE` (the splash would vanish at handoff, unlike legacy).

## Components

### `src/bootefi-1/efi_gfx.c` (new)

Owns the screen in mode 0x12.

- `efi_gfx_init()`: programs mode 0x12 from standard register tables, as
  `efi_vga.c` does for mode 3, including clearing the Cirrus extension state
  `efi_vga.c` already handles. Loads the kernel's 4-grey palette
  (`BasicConsole.c` `paletteVals`, index `i % 4` for all 16 registers), so
  colours match the kernel exactly.
- Planar primitives `clearRect`, `copyImage`, `blitRow`, `setPixel`: EFI-side
  copies of boot-2's `libsaio/console.c` versions. That file cannot be compiled
  here because it also defines the BIOS `putchar`/`getc`, and `src/boot-2` is
  not edited.
- Window console: draws the dark grey background and the centred window with
  its black title bar and "Rhapsody Operating System" title, geometry following
  the kernel's `InitWindow` (size truncated to whole characters, origin x
  aligned down to 8). Renders text with a copy of the kernel's `ohlfs12` font,
  handles `\n`, `\r`, `\b` and `\t`, and scrolls by copying VRAM planes.
- Splash: draws `Panel.image` centred and provides `message()`,
  `spinActivityIndicator()` and `clearActivityIndicator()` with legacy
  behaviour and positions (`boot2/graphics.h` `MESSAGE_Y`, `CURSOR_X`/`Y`).
  The spin throttle keeps legacy's ~1/9 s minimum between frames using `rdtsc`,
  calibrated once against `gBS->Stall` in `efi_gfx_init()`.
- `setMode(mode)`: switches between splash and window. Entering the splash
  buffers text (`textBuf`/`bufIndex`, as legacy); leaving it redraws the window
  and replays the buffer.

### Reused from `src/boot-2` unmodified

`libsaio/bitmap.c` (`loadBitmap`), `libsaio/unpackbits.c` (PackBits),
`libsaio/font.c` (`blit_string`/`blit_clear` with `Default.font`), and
`boot2/bitmaps.c` with `util/ns_wait*_bitmap.h` for the cursor frames. Each is
added to `BOOT2_SRCS` if it compiles under the existing clang flags; any that
does not gets a small EFI-side replacement, recorded in a comment in the
Makefile like the existing `memset.c` note.

### `src/bootefi-1/efi_console.c`

- `putchar` writes every character to COM1 (port 0x3F8, polled on the LSR
  transmit-empty bit). Before `efi_gfx_init()` it also writes to `ConOut`;
  after, it writes to the window console instead (or the buffer while the
  splash is up).
- The `setMode` stub, `message()` and the empty activity-indicator stubs are
  removed in favour of the `efi_gfx.c` versions.

### `src/bootefi-1/efi_main.c`

- Calls `efi_gfx_init()` first thing.
- After `loadSystemConfig()`, applies the splash rule below and, if it holds,
  loads `Panel.image` and `Default.font` and calls `setMode(GRAPHICS_MODE)`.
- Before handoff, on errors while the splash is up: `setMode(TEXT_MODE)`,
  print "Errors encountered while starting up the computer." and pause
  `BOOT_TIMEOUT` seconds, as `boot2/boot.c` does.
- Shows `message("Starting Rhapsody")` in the active style.

### `src/bootefi-1/handoff.c`

After `ExitBootServices`, if graphics are active, skip
`efi_vga_reset_text_mode()` and leave the card in mode 0x12. The reset stays
for the path where graphics never started.

## Splash rule

The splash is shown only when all of these hold after `loadSystemConfig()`:

1. `getBoolForKey("Boot Graphics")` is true.
2. The boot string has no `-v` flag. (On legacy, typing anything at the prompt,
   such as `-v`, disables graphics; EFI has no prompt, so the compile-time
   `BOOTEFI_BOOT_STRING` stands in for it.)
3. `errors == 0`.

Then `kernBootStruct->graphicsMode` is `GRAPHICS_MODE`; otherwise it stays
`TEXT_MODE`. The default boot string contains `-v`, so a default build always
shows the window.

## Failure handling

- `Panel.image` or `Default.font` cannot be loaded: stay in the window,
  `graphicsMode` stays `TEXT_MODE`, and print legacy's
  "Could not load all bitmaps; using text mode." The window needs nothing from
  disk.
- Firmware messages printed before `efi_gfx_init()` stay on the firmware
  console and are overwritten.

## Testing

Under QEMU with OVMF, `-vga cirrus` and `-serial stdio`, on a temporary copy of
the disk image:

1. Default `-v` build: the window appears from the first booter line; screenshots
   before and after handoff show the same window continuing with kernel text.
   COM1 carries the full booter log, matching today's `ConOut` output.
2. Build without `-v`, with `Boot Graphics` = Yes: the panel shows
   "Starting Rhapsody" and, after handoff, the kernel's wait cursor animates in
   it, confirming the card was left in mode 0x12.
3. As 2, with `Panel.image` removed: the booter falls back to the window and
   prints the fallback message.
4. The host tests in `src/bootefi-1/tests` still pass, and boot still reaches
   `vfs_mountroot`.
