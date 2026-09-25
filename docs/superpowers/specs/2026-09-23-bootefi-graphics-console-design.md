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

### `src/bootefi-1/efi_vga.c`

Gains `efi_vga_set_mode12()`: programs mode 0x12 from the kernel's own
register tables (`BasicConsole.c` `VGASetGraphicsMode()`), clears the same
Cirrus extension registers `efi_vga_reset_text_mode()` clears, and loads the
kernel's 4-grey palette (`paletteVals`, index `i % 4` for all 16 DAC
entries), so colours match the kernel exactly.

### `src/bootefi-1/efi_gfx.c` (new)

The screen and the console window.

- `efi_gfx_init()`: calls `efi_vga_set_mode12()` and draws the empty window.
- `clearRect()`: solid fill through set/reset, a port of the kernel's `rect()`.
  Named and typed as boot-2's `libsaio/font.c` expects.
- Window console: draws the dark grey background and the window with its
  black title bar and "Rhapsody Operating System" title, ported from the
  kernel's `InitWindow()`/`SetTitle()` (size truncated to whole characters,
  origin x aligned down to 8). Renders text with the kernel's `ohlfs12` font,
  handles `
`, ``, `` and `	`, wraps, and scrolls by copying VRAM
  through the latches. The kernel's block cursor is not drawn.

### `src/bootefi-1/efi_splash.c` (new)

The Boot Graphics panel and the entry points boot-2's libsaio calls.

- `setMode(mode)`: entering the panel loads `Panel.image` and
  `<Language>.lproj/Default.font` once, buffers text (`textBuf`/`bufIndex`,
  1536 bytes, as legacy) and draws the panel centred; leaving it redraws the
  window and replays the buffer. Writes `kernBootStruct->graphicsMode`.
- `message()`, `spinActivityIndicator()`, `clearActivityIndicator()`: legacy
  behaviour and positions (`boot2/graphics.h` `MESSAGE_Y`, `CURSOR_X`/`Y`,
  the 4.2 layout: message at the panel's centre over a light grey bar) on the
  panel; in the window, `message()` prints a line and there is no spinner, as
  today. The spin throttle keeps legacy's ~110 ms between frames using
  `rdtsc`, calibrated once against `gBS->Stall`.
- `copyImage()`/`blitRow()`: EFI-side copies of boot-2's `libsaio/console.c`
  versions (that file also defines the BIOS `putchar`/`getc`). `copyImage()`
  turns set/reset off while it blits, since the kernel's register set enables
  it.
- `efi_screen_putc()`: where text goes once the screen is ours, the window
  or the buffer.

### `src/bootefi-1/efi_splash_rule.c` (new)

`efi_want_splash()`, the rule below. Pure, host-tested.

### Reused from `src/boot-2` unmodified

`libsaio/bitmap.c` (`loadBitmap`), `libsaio/unpackbits.c` (PackBits),
`libsaio/font.c` (`blit_string`/`blit_clear`), and `boot2/bitmaps.c` with
`util/ns_wait*_bitmap.h` for the cursor frames. All four compile under the
existing flags.

### `src/bootefi-1/efi_console.c`

- Before `efi_gfx_init()`, `putchar` writes to `ConOut` as today (OVMF mirrors
  it to COM1). After, it writes to COM1 directly (port 0x3F8, bounded poll on
  the LSR transmit-empty bit) and to `efi_screen_putc()`, and never to
  `ConOut`, which would draw over the screen.
- The `setMode` stub, `message()` and the empty activity-indicator stubs are
  removed in favour of the `efi_splash.c` versions.

### `src/bootefi-1/efi_main.c`

- Calls `efi_gfx_init()` first thing, in place of clearing `ConOut`.
- After `loadSystemConfig()`, applies the splash rule and, if it holds, calls
  `setMode(GRAPHICS_MODE)`. If the panel would not load, it is not retried.
- Before handoff, as `boot2/boot.c` does: on errors, `setMode(TEXT_MODE)`,
  print "Errors encountered while starting up the computer.", pause
  `BOOT_TIMEOUT` (10) seconds; then back to the panel if it was chosen, and
  `message("Starting Rhapsody", 0)` in the active style.

### `src/bootefi-1/handoff.c`

After `ExitBootServices`, if graphics are active, skip
`efi_vga_reset_text_mode()` and leave the card in mode 0x12. The reset call is
kept as a fallback, though with `efi_gfx_init()` first in `efi_main` that path
is not currently reached.

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

- `Panel.image` cannot be loaded: stay in the window, `graphicsMode` stays
  `TEXT_MODE`, and print legacy's "Could not load all bitmaps; using text
  mode." The window needs nothing from disk.
- `Default.font` cannot be loaded: stay in the window and report it through
  `error()`, as legacy's `loadFont()` does; like any error, that brings the
  10-second pause before handoff.
- Firmware messages printed before `efi_gfx_init()` stay on the firmware
  console and are overwritten.

## Testing

Under QEMU with IA32 OVMF, `-vga cirrus`, `vm/golden.img` opened with
`-snapshot` (nothing written back), screenshots through QMP:

1. Default `-v` build: every capture is 640x480, and a capture taken while the
   loader runs matches one taken after the kernel has drawn its window
   everywhere outside the text area. COM1 carries the full loader log.
2. Build without `-v` (`Boot Graphics` is already Yes on `golden.img`): the
   panel shows "Starting Rhapsody", and later captures differ only where the
   kernel's wait cursor animates, confirming the card was left in mode 0x12.
3. As 2, with the panel path pointed at a file that does not exist: the loader
   stays in the window and prints the fallback message once.
4. `make test-acpi test-splash` in `src/bootefi-1/tests` pass, and the kernel
   still reaches "root on hd0a".
