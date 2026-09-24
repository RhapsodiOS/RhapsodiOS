/*
 * efi_splash.c -- boot-2's Boot Graphics panel for the UEFI loader, and the
 * setMode()/message()/activity-indicator entry points boot-2's libsaio
 * calls.  Follows src/boot-2/i386/boot2/graphics.c (setMode, message,
 * spinActivityIndicator, clearActivityIndicator, loadFont) and copyImage()/
 * blitRow() from src/boot-2/i386/libsaio/console.c, drawing into the mode
 * 0x12 screen efi_gfx.c set up rather than one the BIOS set.  In text mode
 * the screen is efi_gfx.c's console window.
 */
#include "efi.h"
#include "libsaio.h"
#include "kernBootStruct.h"
#include "io_inline.h"
#include "bitmap.h"     /* struct bitmap, TIFF */
#include "font.h"       /* font_t, fontp */
#include "fontio.h"     /* blit_string(), CENTER_H, CENTER_V */
#include "efi_gfx.h"

#ifndef BOOTEFI_PANEL_PATH
#define BOOTEFI_PANEL_PATH  "/usr/standalone/i386/Panel.image"
#endif

/* boot2/graphics.h's panel layout and pixel values. */
#define BOX_W       (panel->width)
#define BOX_H       (panel->height)
#define BOX_X       ((GFX_SCREEN_W - BOX_W) / 2)
#define BOX_Y       ((GFX_SCREEN_H - BOX_H) / 2)
#define BOX_C_X     (GFX_SCREEN_W / 2)
#define MESSAGE_Y   (BOX_Y + BOX_H / 2)
#define CURSOR_W    16
#define CURSOR_H    16
#define CURSOR_X    (BOX_X + (BOX_W - CURSOR_W) / 2)
#define CURSOR_Y    (BOX_Y + 148)
#define TEXT_BG     GFX_LTGRAY
#define TEXT_FG     GFX_BLACK
#define SCREEN_BG   GFX_DKGRAY

#define TEXTBUFSIZE 1536        /* libsaio/console.h */
#define ROWBYTES    (GFX_SCREEN_W / 8)
#define VGA_FB      ((volatile unsigned char *)0xA0000)

extern char *Language;          /* libsaio/localize.c */
extern int PackBitsDecode(TIFF *tif, unsigned char *op, int occ, int s);
extern struct bitmap ns_wait1_bitmap, ns_wait2_bitmap, ns_wait3_bitmap;

static const struct bitmap *indicator_bitmap[4] = {
    &ns_wait1_bitmap, &ns_wait2_bitmap, &ns_wait3_bitmap, 0
};

static int screen_mode = TEXT_MODE;
static const struct bitmap *panel;
static char *textBuf;
static int bufIndex;
static int currentIndicator;
static unsigned long frame_ticks;

static unsigned long rdtsc_lo(void)
{
    unsigned long lo, hi;

    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    return lo;
}

static const unsigned char leftMaskArray[] =
    { 0xff, 0x7f, 0x3f, 0x1f, 0x0f, 0x07, 0x03, 0x01 };

/* libsaio/console.c blitRow(): one row of one plane at any x, shifting the
 * source bytes into place and masking the partial bytes at either end. */
static void blitRow(int x, int y, int w, unsigned char *rowData)
{
    unsigned char *src_p = rowData, prev_byte;
    volatile unsigned char *dst_p, *last_byte;
    unsigned char lmask, rmask;
    int lshift, rshift, last_w;
    volatile unsigned char xx;

    if (w == 0)
        return;
    dst_p = VGA_FB + (x >> 3) + y * ROWBYTES;
    last_byte = VGA_FB + ((x + w) >> 3) + y * ROWBYTES;
    rshift = x & 7;
    lshift = (8 - rshift) & 7;
    last_w = (x + w) & 7;
    lmask = leftMaskArray[rshift];
    rmask = ~leftMaskArray[last_w];

    outb(0x3CE, 8);
    if (dst_p == last_byte) {
        outb(0x3CF, lmask & rmask);
        xx = *dst_p;
        *dst_p = *src_p >> rshift;
    } else {
        outb(0x3CF, lmask);
        xx = *dst_p;
        *dst_p = *src_p >> rshift;
        prev_byte = lshift ? *src_p : 0;
        outb(0x3CF, 0xff);
        for (dst_p++, src_p++; dst_p < last_byte; dst_p++, src_p++) {
            if (lshift)
                *dst_p = (prev_byte << lshift) | (*src_p >> rshift);
            else
                *dst_p = *src_p >> rshift;
            prev_byte = *src_p;
        }
        outb(0x3CF, rmask);
        xx = *dst_p;
        if (lshift)
            *dst_p = (prev_byte << lshift) | (*src_p >> rshift);
        else
            *dst_p = *src_p >> rshift;
    }
    outb(0x3CF, 0xff);
    (void)xx;
}

/* libsaio/console.c copyImage(): the two planes of a (possibly PackBits-
 * compressed) planar bitmap.  The kernel's mode 0x12 register set enables
 * set/reset on every plane, which would replace the CPU data; turn it off
 * for the blit and back on for clearRect(). */
void copyImage(const struct bitmap *bitmap, int x, int y)
{
    unsigned char rowbuf[ROWBYTES];
    int i, plane, row_bytes = (bitmap->width + 7) >> 3;
    TIFF tif;

    outb(0x3CE, 1); outb(0x3CF, 0x00);
    for (plane = 0; plane < 2; plane++) {
        tif.tif_rawcp = tif.tif_rawdata = (char *)bitmap->plane_data[plane];
        tif.tif_rawcc = bitmap->plane_len[plane];
        outb(0x3C4, 2); outb(0x3C5, 1 << plane);
        for (i = 0; i < bitmap->height; i++) {
            if (bitmap->packed) {
                PackBitsDecode(&tif, rowbuf, row_bytes, 0);
                blitRow(x, y + i, bitmap->width, rowbuf);
            } else {
                blitRow(x, y + i, bitmap->width,
                        (unsigned char *)tif.tif_rawcp);
                tif.tif_rawcp += row_bytes;
            }
        }
    }
    outb(0x3C4, 2); outb(0x3C5, 0x0f);
    outb(0x3CE, 1); outb(0x3CF, 0x0f);
}

/* graphics.c initMode(): Panel.image and the language's Default.font,
 * each loaded once. */
static int loadAssets(void)
{
    char buf[128];
    int fd, size;
    font_t *font;

    if (panel == 0 && (panel = loadBitmap(BOOTEFI_PANEL_PATH)) == 0) {
        printf("Could not load all bitmaps; using text mode.\n");
        return 0;
    }
    if (fontp)
        return 1;
    sprintf(buf, "/usr/standalone/i386/%s.lproj/Default.font", Language);
    if ((fd = open(buf, 0)) < 0) {
        error("Couldn't open font file %s\n", buf);
        return 0;
    }
    size = file_size(fd);
    font = (font_t *)malloc(size);
    if (read(fd, (char *)font, size) < size) {
        close(fd);
        error("Short read on font file %s\n", buf);
        free(font);
        return 0;
    }
    close(fd);
    fontp = font;
    return 1;
}

int currentMode(void)
{
    return screen_mode;
}

/* graphics.c setMode(): the panel buffers text; going back to text mode
 * redraws the console window and replays it. */
void setMode(int mode)
{
    int i;

    if (screen_mode == mode)
        return;
    if (mode == GRAPHICS_MODE) {
        if (!loadAssets())
            return;
        if (frame_ticks == 0) {
            /* graphics.c spaces frames by 2 ticks of the 18.2 Hz BIOS
             * timer; measure ~110 ms of TSC once instead. */
            unsigned long t = rdtsc_lo();
            gBS->Stall(10000);
            frame_ticks = (rdtsc_lo() - t) * 11;
        }
        textBuf = malloc(TEXTBUFSIZE);
        bufIndex = 0;
        screen_mode = GRAPHICS_MODE;
        clearRect(0, 0, GFX_SCREEN_W, GFX_SCREEN_H, SCREEN_BG);
        copyImage(panel, BOX_X, BOX_Y);
    } else {
        screen_mode = TEXT_MODE;
        efi_win_draw();
        if (textBuf) {
            for (i = 0; i < bufIndex; i++)
                efi_win_putc(textBuf[i]);
            free(textBuf);
            textBuf = 0;
        }
    }
    kernBootStruct->graphicsMode = screen_mode;
    currentIndicator = 0;
}

/* Where efi_console.c's putchar() sends text once the screen is ours. */
void efi_screen_putc(int c)
{
    if (screen_mode == GRAPHICS_MODE) {
        if (textBuf && bufIndex < TEXTBUFSIZE)
            textBuf[bufIndex++] = c;
    } else {
        efi_win_putc(c);
    }
}

void message(char *str, int centered)
{
    if (screen_mode == GRAPHICS_MODE) {
        blit_clear(BOX_W - 16, BOX_C_X, MESSAGE_Y, CENTER_V | CENTER_H,
                   TEXT_BG);
        blit_string(str, BOX_C_X, MESSAGE_Y, TEXT_FG, CENTER_V | CENTER_H);
    } else {
        printf("%s\n", str);
    }
}

void spinActivityIndicator(void)
{
    static unsigned long last;
    unsigned long now;

    if (screen_mode != GRAPHICS_MODE)
        return;
    now = rdtsc_lo();
    if (now - last < frame_ticks)
        return;
    last = now;
    copyImage(indicator_bitmap[currentIndicator], CURSOR_X, CURSOR_Y);
    if (indicator_bitmap[++currentIndicator] == 0)
        currentIndicator = 0;
}

void clearActivityIndicator(void)
{
    if (screen_mode == GRAPHICS_MODE)
        clearRect(CURSOR_X, CURSOR_Y, CURSOR_W, CURSOR_H, TEXT_BG);
}
