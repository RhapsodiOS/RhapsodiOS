/* efi_gfx.h -- the UEFI loader's VGA mode 0x12 screen (efi_gfx.c). */
#ifndef EFI_GFX_H
#define EFI_GFX_H

/* Pixel values; efi_vga_set_mode12() loads these four greys. */
#define GFX_BLACK   0
#define GFX_DKGRAY  1
#define GFX_LTGRAY  2
#define GFX_WHITE   3

#define GFX_SCREEN_W    640
#define GFX_SCREEN_H    480

/* Switch the card to mode 0x12 and draw the empty console window. */
void efi_gfx_init(void);

/* Non-zero once efi_gfx_init() has run. */
int efi_gfx_active(void);

/* Redraw the screen as an empty console window, cursor at the top left. */
void efi_win_draw(void);

/* Draw one character in the console window: '\n' starts a new line,
 * '\r', '\b' and '\t' move the cursor, the window scrolls at the bottom. */
void efi_win_putc(int c);

/* Fill a rectangle with a pixel value.  The name and arguments are the ones
 * boot-2's libsaio/font.c calls. */
void clearRect(int x, int y, int w, int h, int c);

#endif
