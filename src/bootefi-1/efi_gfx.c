/*
 * efi_gfx.c -- The UEFI loader's screen: VGA mode 0x12, drawn with direct
 * port and memory I/O, with a console window that looks exactly like the
 * one the kernel draws once it starts.
 *
 * The window is a port of src/kernel-7/bsd/dev/i386/VGAConsole.c: rect(),
 * BltChar(), InitWindow()'s border, SetTitle()'s title bar and FBPutC()'s
 * scrolling, at the kernel's TEXT_WIN_WIDTH x TEXT_WIN_HEIGHT and with its
 * ohlfs12 font, so the screen does not change when the kernel takes over.
 * The kernel's block cursor is not drawn.
 */
#include "efi.h"
#include "io_inline.h"
#include "efi_gfx.h"

#define DRIVER_PRIVATE
#include <bsd/dev/i386/ohlfs12.h>  /* ohlfs12[96][CHAR_H], CHAR_W, CHAR_H */
#undef DRIVER_PRIVATE

extern void efi_vga_set_mode12(void);

#define VGA_FB      ((volatile unsigned char *)0xA0000)
#define ROWBYTES    (GFX_SCREEN_W / 8)
#define SEQ_ADDR    0x3C4
#define SEQ_DATA    0x3C5
#define GC_ADDR     0x3CE
#define GC_DATA     0x3CF

/* VGAConsPriv.h's TEXT_WIN_WIDTH/HEIGHT and VGAConsole.c's margins. */
#define TEXT_WIN_WIDTH  600
#define TEXT_WIN_HEIGHT 450
#define BG_MARGIN       2
#define FG_MARGIN       1
#define TOTAL_MARGIN    (BG_MARGIN + FG_MARGIN)

/* InitWindow(): size truncated to whole characters, centred, x aligned
 * down to a byte.  SetTitle() then takes the top two rows for the title
 * bar. */
#define WIN_W       ((TEXT_WIN_WIDTH / CHAR_W) * CHAR_W)
#define WIN_H       ((TEXT_WIN_HEIGHT / CHAR_H) * CHAR_H)
#define WIN_X       (((GFX_SCREEN_W - WIN_W) / 2) & ~7)
#define WIN_Y       ((GFX_SCREEN_H - WIN_H) / 2)
#define TITLE_H     (CHAR_H * 2)
#define TEXT_Y      (WIN_Y + TITLE_H)
#define COLS        (WIN_W / CHAR_W)
#define ROWS        ((WIN_H - TITLE_H) / CHAR_H)
#define TAB_SIZE    8

/* mach_title in src/kernel-7/bsd/dev/i386/kmDevice.m. */
static const char title[] = "Rhapsody Operating System";

static int active;
static int row, col;

static const unsigned char leftMask[8] =
    { 0xff, 0x7f, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01 };
static const unsigned char rightMask[8] =
    { 0x00, 0x80, 0xc0, 0xe0, 0xf0, 0xf8, 0xfc, 0xfe };

static void gc_write(int index, int value)
{
    outb(GC_ADDR, index);
    outb(GC_DATA, value);
}

/* VGAConsole.c rect(): set/reset supplies the colour on all four planes,
 * the bit mask register clips the partial bytes at either end. */
void clearRect(int x, int y, int w, int h, int c)
{
    int first = x >> 3;
    int mid = ((x + w) >> 3) - first - 1;
    unsigned char lmask = leftMask[x & 7];
    unsigned char rmask = rightMask[(x + w) & 7];
    volatile unsigned char *rowp = VGA_FB + y * ROWBYTES + first;
    volatile unsigned char latch;
    int k;

    outb(SEQ_ADDR, 2); outb(SEQ_DATA, 0x0f);
    gc_write(1, 0x0f);
    gc_write(0, c);
    outb(GC_ADDR, 8);
    if (mid == -1) {
        outb(GC_DATA, lmask & rmask);
        for (; --h >= 0; rowp += ROWBYTES) {
            latch = *rowp;
            *rowp = 0xff;
        }
    } else {
        for (; --h >= 0; rowp += ROWBYTES) {
            volatile unsigned char *p = rowp;

            outb(GC_DATA, lmask);
            latch = *p;
            *p++ = 0xff;
            outb(GC_DATA, 0xff);
            for (k = mid; --k >= 0;)
                *p++ = 0xff;
            outb(GC_DATA, rmask);
            latch = *p;
            *p = 0xff;
        }
    }
    outb(GC_DATA, 0xff);
    (void)latch;
}

/* VGAConsole.c BltChar(): erase the cell, then the glyph row by row as the
 * bit mask over a set/reset fill. */
static void blt_char(int x, int y, int ch, int fg, int bg)
{
    volatile unsigned char *p = VGA_FB + y * ROWBYTES + (x >> 3);
    volatile unsigned char latch;
    const char *glyph;
    int r;

    clearRect(x, y, CHAR_W, CHAR_H, bg);
    /* ohlfs12 only covers 0x20..0x7f; skip higher bytes rather than read
     * past the table. */
    if (ch < ' ' || ch > 0x7f)
        return;
    glyph = ohlfs12[ch - ' '];
    gc_write(0, fg);
    outb(GC_ADDR, 8);
    for (r = 0; r < CHAR_H; r++, p += ROWBYTES) {
        outb(GC_DATA, (unsigned char)glyph[r]);
        latch = *p;
        *p = 0xff;
    }
    outb(GC_DATA, 0xff);
    (void)latch;
}

void efi_win_draw(void)
{
    int i, len;

    /* Init(): WipeScreen() in the dark grey baseground. */
    clearRect(0, 0, GFX_SCREEN_W, GFX_SCREEN_H, GFX_DKGRAY);

    /* InitWindow(): black outer line, white inner margin, white window. */
    clearRect(WIN_X - TOTAL_MARGIN, WIN_Y - TOTAL_MARGIN,
              WIN_W + TOTAL_MARGIN * 2, FG_MARGIN, GFX_BLACK);
    clearRect(WIN_X - BG_MARGIN, WIN_Y - BG_MARGIN,
              WIN_W + BG_MARGIN * 2, BG_MARGIN, GFX_WHITE);
    clearRect(WIN_X - BG_MARGIN, WIN_Y + WIN_H,
              WIN_W + BG_MARGIN * 2, BG_MARGIN, GFX_WHITE);
    clearRect(WIN_X - TOTAL_MARGIN, WIN_Y + WIN_H + BG_MARGIN,
              WIN_W + TOTAL_MARGIN * 2, FG_MARGIN, GFX_BLACK);
    clearRect(WIN_X - TOTAL_MARGIN, WIN_Y - TOTAL_MARGIN,
              FG_MARGIN, WIN_H + TOTAL_MARGIN * 2, GFX_BLACK);
    clearRect(WIN_X - BG_MARGIN, WIN_Y - BG_MARGIN,
              BG_MARGIN, WIN_H + BG_MARGIN * 2, GFX_WHITE);
    clearRect(WIN_X + WIN_W, WIN_Y - BG_MARGIN,
              BG_MARGIN, WIN_H + BG_MARGIN * 2, GFX_WHITE);
    clearRect(WIN_X + WIN_W + BG_MARGIN, WIN_Y - TOTAL_MARGIN,
              FG_MARGIN, WIN_H + TOTAL_MARGIN * 2, GFX_BLACK);
    clearRect(WIN_X, WIN_Y, WIN_W, WIN_H, GFX_WHITE);

    /* SetTitle(): black bar, title centred in white half a row down, then
     * the bevel lines around it. */
    clearRect(WIN_X, WIN_Y, WIN_W, TITLE_H - BG_MARGIN, GFX_BLACK);
    for (len = 0; title[len]; len++)
        ;
    for (i = 0; i < len; i++)
        blt_char(WIN_X + ((COLS - len) / 2 + i) * CHAR_W, WIN_Y + CHAR_H / 2,
                 title[i], GFX_WHITE, GFX_BLACK);
    clearRect(WIN_X - BG_MARGIN, WIN_Y - BG_MARGIN,
              WIN_W + BG_MARGIN * 2, BG_MARGIN, GFX_LTGRAY);
    clearRect(WIN_X - BG_MARGIN, WIN_Y + TITLE_H - TOTAL_MARGIN - BG_MARGIN,
              WIN_W + BG_MARGIN * 2, BG_MARGIN, GFX_DKGRAY);
    for (i = 0; i < BG_MARGIN; i++)
        clearRect(WIN_X - BG_MARGIN + i, WIN_Y - BG_MARGIN + i,
                  1, TITLE_H - 1 - i * 2, GFX_LTGRAY);
    for (i = 1; i <= BG_MARGIN; i++)
        clearRect(WIN_X + WIN_W + i - 1, WIN_Y - i,
                  1, TITLE_H - 1 - (BG_MARGIN - i) * 2, GFX_DKGRAY);
    clearRect(WIN_X - TOTAL_MARGIN, WIN_Y + TITLE_H - FG_MARGIN - BG_MARGIN,
              WIN_W + TOTAL_MARGIN * 2, FG_MARGIN, GFX_BLACK);

    row = col = 0;
}

/* FBPutC()'s scroll: write mode 1 copies all four planes a byte at a time
 * through the latches. */
static void scroll(void)
{
    volatile unsigned char *dst = VGA_FB + TEXT_Y * ROWBYTES + (WIN_X >> 3);
    volatile unsigned char *src = dst + CHAR_H * ROWBYTES;
    int y, i;

    gc_write(5, 0x01);
    for (y = CHAR_H; y < ROWS * CHAR_H; y++, src += ROWBYTES, dst += ROWBYTES)
        for (i = 0; i < COLS; i++)
            dst[i] = src[i];
    gc_write(5, 0x00);
    clearRect(WIN_X, TEXT_Y + (ROWS - 1) * CHAR_H, WIN_W, CHAR_H, GFX_WHITE);
}

void efi_win_putc(int c)
{
    int n;

    switch (c) {
    case '\r':
        col = 0;
        break;
    case '\n':
        col = 0;
        row++;
        break;
    case '\b':
        if (col)
            col--;
        break;
    case '\t':
        for (n = TAB_SIZE - col % TAB_SIZE; n > 0; n--)
            efi_win_putc(' ');
        return;
    default:
        blt_char(WIN_X + col * CHAR_W, TEXT_Y + row * CHAR_H, c & 0xff,
                 GFX_BLACK, GFX_WHITE);
        col++;
        break;
    }
    if (col >= COLS) {
        col = 0;
        row++;
    }
    if (row >= ROWS) {
        row = ROWS - 1;
        scroll();
    }
}

void efi_gfx_init(void)
{
    efi_vga_set_mode12();
    active = 1;
    efi_win_draw();
}

int efi_gfx_active(void)
{
    return active;
}
