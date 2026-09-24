# bootefi Graphics Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the UEFI loader draw its output in the kernel's "Rhapsody Operating System" console window from its first line, and show boot-2's Boot Graphics panel instead when the legacy rule for it holds, so the screen carries straight on into the kernel.

**Architecture:** The loader programs VGA mode 0x12 itself, with the kernel's own register tables and grey palette, and never writes to `ConOut` again; its text goes to COM1 directly and to the screen. `efi_gfx.c` ports the kernel's window drawing, so the kernel's redraw after handoff is pixel-identical. `efi_splash.c` ports boot-2's panel code over the same screen and leaves it in mode 0x12 for the kernel. A pure `efi_want_splash()` decides between the two.

**Tech Stack:** C (gnu89), clang cross-targeting `i386-unknown-windows`, `lld-link`; QEMU 10 for Windows with its bundled IA32 edk2 firmware; Python 3 + Pillow for screenshot checks.

**Spec:** `docs/superpowers/specs/2026-09-23-bootefi-graphics-console-design.md`

## Global Constraints

- `src/boot-2` and `src/kernel-7` are not edited. Their files are only compiled (boot-2) or `#include`d (the kernel's `ohlfs12.h`).
- Commit messages: one or two short lines, prefixed `bootefi: `, describing behaviour, not files. **No trailers, no Co-Authored-By, no metadata** (`CLAUDE.md` §5).
- Boot tests never write to a disk image: `efi_shot.py` opens `vm/golden.img` with `snapshot=on` (`CLAUDE.md` §6).
- Work in a git worktree on branch `bootefi-graphics-console` (`superpowers:using-git-worktrees`). Other sessions share this repository's index.
- Only `src/bootefi-1/bootefi_memory_override.h` in this project holds non-ASCII bytes; no task touches it.
- Match the surrounding style: 4-space indent, `/* */` comments, gnu89.

## Test Harness (Windows, already in the session scratchpad)

`SP=C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/3be4cbcc-c8eb-47a0-93ce-a9dd1c435552/scratchpad`

`W=$(cd src/bootefi-1 && pwd -W)`, run from the worktree root: the Windows path of the worktree's `src/bootefi-1`.

| File | Use |
|---|---|
| `$SP/build-bootefi.sh SRCDIR BUILDDIR [VAR=value ...]` | Builds `BOOTIA32.EFI` on this Windows box: adds `$SP/inc` (the `vendor_includes` symlink targets, which Windows checks out as text files), downgrades new-clang pointer errors, pins `BOOT2`/`KERNEL7`/`CCTOOLS` to `D:/RhapsodiOS/src/...`. Extra compiler flags go in the `EXTRA_CFLAGS` environment variable. Never pass `LINK=` (make exports it and lld-link reads `$LINK` as arguments). Object files do not rebuild when a `-D` changes, so use a fresh `BUILDDIR` per variant. |
| `python $SP/efi_shot.py EFI OUTDIR T1,T2,...` | Boots `EFI` against `vm/golden.img` (snapshot) under i440FX + IA32 edk2 + `-vga cirrus`, ESP served from `OUTDIR/esp`; COM1 → `OUTDIR/com1.log`; QMP screenshots at T seconds → `OUTDIR/shot-<T>s.png`. Takes about T_max + 15 s. |
| `python $SP/check_window.py OUTDIR BOOTER_SHOT KERNEL_SHOT` | PASS when every shot is 640x480 and the two shots match outside the window's text area. |
| `python $SP/check_splash.py OUTDIR EARLY_SHOT LATE_SHOT` | PASS when every shot is 640x480, neither has the window's title bar, and the two differ only inside the wait-cursor box. |

Host tests build natively: `cd src/bootefi-1/tests && PATH="/c/Program Files/LLVM/bin:$PATH" make CC=clang BUILD=$SP/<dir> test-acpi test-splash`. (`ufs_host_test` needs a macOS host; it is not run here.)

Timing on this machine under TCG: the loader runs from about 2 s to 15 s after QEMU starts; by 30 s the kernel owns the screen.

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `src/bootefi-1/efi_splash_rule.h`, `.c` | create | `efi_want_splash()`: the Boot Graphics rule. Pure. |
| `src/bootefi-1/tests/efi_splash_rule_test.c` | create | Host test for the rule. |
| `src/bootefi-1/tests/Makefile` | modify | Build and run it (`test-splash`). |
| `src/bootefi-1/efi_vga.c` | modify | Add `efi_vga_set_mode12()`: the kernel's mode 0x12 registers and palette. |
| `src/bootefi-1/efi_gfx.h`, `.c` | create | Screen init, `clearRect()`, the kernel-style console window. |
| `src/bootefi-1/efi_splash.c` | create | Boot Graphics panel, `setMode()`, `message()`, activity indicator, text buffering. |
| `src/bootefi-1/efi_console.c` | modify | `putchar` to COM1 + screen once graphics are up; drop stubs `efi_splash.c` replaces. |
| `src/bootefi-1/efi_main.c` | modify | Start graphics first; pick the panel after config load; boot-2's error pause and "Starting Rhapsody". |
| `src/bootefi-1/handoff.c` | modify | Leave the card in mode 0x12 at handoff. |
| `src/bootefi-1/Makefile` | modify | New sources and four boot-2 sources. |

Task order: 1 → 2 → 3. Task 3 needs Task 1's rule and Task 2's screen.

---

### Task 1: Boot Graphics rule

The one piece of new decision logic. Pure strings in, int out; host-tested.

**Files:**
- Create: `src/bootefi-1/efi_splash_rule.h`
- Create: `src/bootefi-1/efi_splash_rule.c`
- Create: `src/bootefi-1/tests/efi_splash_rule_test.c`
- Modify: `src/bootefi-1/tests/Makefile`

**Interfaces:**
- Consumes: nothing.
- Produces: `int efi_want_splash(const char *bootString, int bootGraphics, int errors);` in `efi_splash_rule.h`. Non-zero means show the panel. Task 3 calls it.

- [ ] **Step 1: Write the failing test**

Create `src/bootefi-1/tests/efi_splash_rule_test.c`:

```c
/* Host test for the UEFI loader's Boot Graphics rule.  Pure strings: no
 * firmware, no EFI types, no boot-2 headers. */
#include <stdio.h>

#include "efi_splash_rule.h"

static int failures;

static void check(const char *name, int got, int want)
{
    if (got != want) {
        printf("FAIL %s: got %d want %d\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

int main(void)
{
    check("default_verbose", efi_want_splash("rootdev=hd0a -v", 1, 0), 0);
    check("no_flags", efi_want_splash("rootdev=hd0a", 1, 0), 1);
    check("empty_string", efi_want_splash("", 1, 0), 1);
    check("graphics_off", efi_want_splash("rootdev=hd0a", 0, 0), 0);
    check("errors", efi_want_splash("rootdev=hd0a", 1, 1), 0);
    check("single_user", efi_want_splash("rootdev=hd0a -s", 1, 0), 1);
    check("combined_sv", efi_want_splash("rootdev=hd0a -sv", 1, 0), 0);
    check("separate_s_v", efi_want_splash("-s -v rootdev=hd0a", 1, 0), 0);
    check("tab_separated", efi_want_splash("rootdev=hd0a\t-v", 1, 0), 0);
    check("v_inside_word", efi_want_splash("rootdev=dev-v", 1, 0), 1);

    if (failures) {
        printf("%d failed\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
```

In `src/bootefi-1/tests/Makefile`, replace

```make
all: $(BUILD)/ufs_host_test $(BUILD)/efi_pci_acpi_test
```

with

```make
all: $(BUILD)/ufs_host_test $(BUILD)/efi_pci_acpi_test \
     $(BUILD)/efi_splash_rule_test
```

and replace

```make
test-acpi: $(BUILD)/efi_pci_acpi_test
	$(BUILD)/efi_pci_acpi_test
```

with (recipe lines start with a TAB)

```make
test-acpi: $(BUILD)/efi_pci_acpi_test
	$(BUILD)/efi_pci_acpi_test

# The Boot Graphics rule is pure C too; same strict flags.
$(BUILD)/efi_splash_rule_test: efi_splash_rule_test.c ../efi_splash_rule.c \
		../efi_splash_rule.h | $(BUILD)
	$(CC) $(ACPI_TEST_CFLAGS) -o $@ efi_splash_rule_test.c ../efi_splash_rule.c

test-splash: $(BUILD)/efi_splash_rule_test
	$(BUILD)/efi_splash_rule_test
```

and replace `.PHONY: all clean test-acpi` with `.PHONY: all clean test-acpi test-splash`.

- [ ] **Step 2: Run it to see it fail**

Run: `cd src/bootefi-1/tests && PATH="/c/Program Files/LLVM/bin:$PATH" make CC=clang BUILD=$SP/t1 test-splash`
Expected: FAIL — `make` stops with `No rule to make target '../efi_splash_rule.c'` (or clang's `'efi_splash_rule.h' file not found`).

- [ ] **Step 3: Implement the rule**

Create `src/bootefi-1/efi_splash_rule.h`:

```c
/* efi_splash_rule.h -- when the UEFI loader shows the Boot Graphics panel. */
#ifndef EFI_SPLASH_RULE_H
#define EFI_SPLASH_RULE_H

/* Non-zero when the panel should be shown: the "Boot Graphics" config key
 * is set, no errors have been reported, and bootString carries no -v
 * flag (a '-' word containing 'v', as in "-v" or "-sv"). */
int efi_want_splash(const char *bootString, int bootGraphics, int errors);

#endif
```

Create `src/bootefi-1/efi_splash_rule.c`:

```c
/*
 * efi_splash_rule.c -- boot-2's Boot Graphics rule, adapted to a loader
 * with no boot prompt.  boot-2 (src/boot-2/i386/boot2/boot.c) shows the
 * panel when "Boot Graphics" is Yes, nothing was typed at the prompt and
 * no errors were reported; typing -v is how a user asks for text.  Here
 * the compile-time boot string stands in for the typed line.  Pure: no
 * EFI or boot-2 dependencies, host-tested by tests/efi_splash_rule_test.c.
 */
#include "efi_splash_rule.h"

static int is_space(char c)
{
    return c == ' ' || c == '\t';
}

static int has_verbose_flag(const char *s)
{
    while (*s) {
        while (is_space(*s))
            s++;
        if (*s == '-') {
            for (s++; *s && !is_space(*s); s++)
                if (*s == 'v')
                    return 1;
        } else {
            while (*s && !is_space(*s))
                s++;
        }
    }
    return 0;
}

int efi_want_splash(const char *bootString, int bootGraphics, int errors)
{
    return bootGraphics && errors == 0 && !has_verbose_flag(bootString);
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd src/bootefi-1/tests && PATH="/c/Program Files/LLVM/bin:$PATH" make CC=clang BUILD=$SP/t1 test-splash test-acpi`
Expected: ten `ok   ...` lines then `all passed` for the rule, and the existing ACPI test also ends `all passed`.

- [ ] **Step 5: Commit**

```bash
git add src/bootefi-1/efi_splash_rule.h src/bootefi-1/efi_splash_rule.c \
        src/bootefi-1/tests/efi_splash_rule_test.c src/bootefi-1/tests/Makefile
git commit -m "bootefi: add boot-2's Boot Graphics rule, with the boot string standing in for the prompt"
```

---

### Task 2: Draw the loader's output in the kernel's console window

After this task every boot shows the kernel-style window from the first loader line, and the card stays in mode 0x12 through handoff. `graphicsMode` is still always `TEXT_MODE`, so the kernel redraws the same window itself.

**Files:**
- Modify: `src/bootefi-1/efi_vga.c` (append)
- Create: `src/bootefi-1/efi_gfx.h`
- Create: `src/bootefi-1/efi_gfx.c`
- Modify: `src/bootefi-1/efi_console.c`
- Modify: `src/bootefi-1/efi_main.c`
- Modify: `src/bootefi-1/handoff.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces (declared in `efi_gfx.h`, used by Task 3): `void efi_gfx_init(void);`, `int efi_gfx_active(void);`, `void efi_win_draw(void);`, `void efi_win_putc(int c);`, `void clearRect(int x, int y, int w, int h, int c);`, and the macros `GFX_BLACK` 0, `GFX_DKGRAY` 1, `GFX_LTGRAY` 2, `GFX_WHITE` 3, `GFX_SCREEN_W` 640, `GFX_SCREEN_H` 480. `efi_vga.c` gains `void efi_vga_set_mode12(void);`.

- [ ] **Step 1: See the check fail on today's loader**

```bash
sh $SP/build-bootefi.sh $W $SP/t2_before
python $SP/efi_shot.py $SP/t2_before/BOOTIA32.EFI $SP/t2_before_run 5,45
python $SP/check_window.py $SP/t2_before_run shot-5s.png shot-45s.png
```

Expected: `FAIL shot-5s.png is 800x600, not 640x480` then `FAILED` — the loader is still on the firmware's text console.

- [ ] **Step 2: Add the mode 0x12 register set to `efi_vga.c`**

Append to the end of `src/bootefi-1/efi_vga.c` (it already defines `outb`/`inb`, `MISC_OUTPUT`, `SEQ_ADDR`/`SEQ_DATA`, `CRTC_ADDR`/`CRTC_DATA`, `GC_ADDR`/`GC_DATA`, `AC_ADDR`/`AC_DATA`, `INPUT_STATUS1`):

```c

/*
 * Standard VGA mode 0x12 (640x480, planar) exactly as the kernel's console
 * programs it: VGASetGraphicsMode() and paletteVals[] in
 * src/kernel-7/bsd/dev/i386/BasicConsole.c. Only planes 0 and 1 are
 * displayed (attribute register 0x12 = 0x03), and every DAC entry holds one
 * of the four NeXT greys, so pixel values 0..3 are black, dark grey, light
 * grey and white.
 */
static const unsigned char mode12_seq[5] = { 0x03, 0x21, 0x0f, 0x00, 0x06 };

static const unsigned char mode12_crtc[25] = {
    0x5f, 0x4f, 0x50, 0x82, 0x54, 0x80, 0x0b, 0x3e, 0x00, 0x40,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x59, 0xea, 0x8c, 0xdf, 0x28,
    0x00, 0xe7, 0x04, 0xe3, 0xff
};

static const unsigned char mode12_ac[21] = {
    0x00, 0x01, 0x02, 0x03, 0x00, 0x01, 0x02, 0x03,
    0x00, 0x01, 0x02, 0x03, 0x00, 0x01, 0x02, 0x03,
    0x01, 0x00, 0x03, 0x00, 0x00
};

static const unsigned char mode12_gc[9] = {
    0x00, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff
};

static const unsigned char mode12_grey[4] = { 0, 21, 42, 63 };

void efi_vga_set_mode12(void)
{
    unsigned i;

    outb(SEQ_ADDR, 0x01); outb(SEQ_DATA, mode12_seq[1]); /* screen off */
    (void)inb(INPUT_STATUS1);
    outb(AC_ADDR, 0x00);                /* palette to the CPU: video off */

    outb(MISC_OUTPUT, 0xE3);
    outb(INPUT_STATUS1, 0x00);          /* feature control (colour port) */

    for (i = 0; i < 5; i++) {
        outb(SEQ_ADDR, i);
        outb(SEQ_DATA, mode12_seq[i]);
    }
    outb(SEQ_ADDR, 0x00); outb(SEQ_DATA, 0x03);

    /* The same three Cirrus extension registers efi_vga_reset_text_mode()
     * clears, for the same reason: OVMF's GOP mode leaves them set, and
     * with them set the 0xA0000 aperture and the CRTC start address do
     * not behave like standard VGA. */
    outb(SEQ_ADDR, 0x07); outb(SEQ_DATA, 0x00);

    outb(CRTC_ADDR, 0x11); outb(CRTC_DATA, 0x00); /* unlock CRTC 0-7 */
    for (i = 0; i < 25; i++) {
        outb(CRTC_ADDR, i);
        outb(CRTC_DATA, mode12_crtc[i]);
    }
    outb(CRTC_ADDR, 0x1B); outb(CRTC_DATA, 0x00);
    outb(CRTC_ADDR, 0x1D); outb(CRTC_DATA, 0x00);

    (void)inb(INPUT_STATUS1);
    for (i = 0; i < 21; i++) {
        outb(AC_ADDR, i);
        outb(AC_DATA, mode12_ac[i]);
    }

    for (i = 0; i < 9; i++) {
        outb(GC_ADDR, i);
        outb(GC_DATA, mode12_gc[i]);
    }

    for (i = 0; i < 16; i++) {
        outb(0x3C8, i);
        outb(0x3C9, mode12_grey[i % 4]);
        outb(0x3C9, mode12_grey[i % 4]);
        outb(0x3C9, mode12_grey[i % 4]);
    }

    (void)inb(INPUT_STATUS1);
    outb(AC_ADDR, 0x20);                /* palette back to the VGA */
    outb(SEQ_ADDR, 0x01); outb(SEQ_DATA, mode12_seq[1] & ~0x20); /* on */
}
```

- [ ] **Step 3: Create `efi_gfx.h`**

```c
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
```

- [ ] **Step 4: Create `efi_gfx.c`**

```c
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
#include "kernBootStruct.h"
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
```

- [ ] **Step 5: Send text to COM1 and the window once graphics are up (`efi_console.c`)**

Replace

```c
#include <stdarg.h>
#include "efi.h"
```

with

```c
#include <stdarg.h>
#include "efi.h"
#include "kernBootStruct.h"
#include "io_inline.h"
#include "efi_gfx.h"
```

Replace

```c
void putchar(int c)
{
    CHAR16 s[3];
    int i = 0;

    if (c == '\n')
```

with

```c
/* 16550 at COM1: wait (bounded) for the transmit holding register. */
static void com1_putc(int c)
{
    int spin;

    for (spin = 0; spin < 100000 && !(inb(0x3FD) & 0x20); spin++)
        ;
    outb(0x3F8, c);
}

void putchar(int c)
{
    CHAR16 s[3];
    int i = 0;

    if (efi_gfx_active()) {
        /* The card is in VGA mode 0x12 now and ConOut would draw over it.
         * OVMF mirrors ConOut to COM1, so keep the serial log going by
         * writing COM1 directly. */
        if (c == '\n')
            com1_putc('\r');
        com1_putc(c);
        efi_win_putc(c);
        return;
    }

    if (c == '\n')
```

- [ ] **Step 6: Start graphics first (`efi_main.c`)**

Replace

```c
extern int efi_pci_init(void);
```

with

```c
extern int efi_pci_init(void);
extern void efi_gfx_init(void);
```

Replace

```c
    gBS = systab->BootServices;
    gST->ConOut->ClearScreen(gST->ConOut);
```

with

```c
    gBS = systab->BootServices;
    efi_gfx_init();
```

- [ ] **Step 7: Keep mode 0x12 through handoff (`handoff.c`)**

Replace

```c
extern void efi_vga_reset_text_mode(void);
```

with

```c
extern void efi_vga_reset_text_mode(void);
extern int efi_gfx_active(void);
```

Replace

```c
            __asm__ volatile("cli");
            efi_vga_reset_text_mode();
```

with

```c
            __asm__ volatile("cli");
            /* With the screen in mode 0x12 the kernel's console carries
             * on from it: its text window redraws itself there, and the
             * Boot Graphics panel must survive untouched. */
            if (!efi_gfx_active())
                efi_vga_reset_text_mode();
```

- [ ] **Step 8: Build `efi_gfx.c` (`Makefile`)**

Replace

```make
EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_memory.c efi_vga.c \
            efi_pci.c handoff.c $(BOOT2_SRCS)
```

with

```make
EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_memory.c efi_vga.c \
            efi_gfx.c efi_pci.c handoff.c $(BOOT2_SRCS)
```

- [ ] **Step 9: Build and check for new warnings**

Run: `sh $SP/build-bootefi.sh $W $SP/t2 2>&1 | grep -E "^(efi_gfx|efi_vga|efi_console|efi_main|handoff)\.c:[0-9]+:[0-9]+: (warning|error)"; ls -la $SP/t2/BOOTIA32.EFI`
Expected: no diagnostic lines; `BOOTIA32.EFI` exists (about 37 KB).

- [ ] **Step 10: Boot it and run the window check**

```bash
python $SP/efi_shot.py $SP/t2/BOOTIA32.EFI $SP/t2_run 5,45
python $SP/check_window.py $SP/t2_run shot-5s.png shot-45s.png
grep -a -c "boot drivers linked" $SP/t2_run/com1.log
```

Expected: `PASS`; the grep prints `1` (the loader's log reached COM1). Look at `$SP/t2_run/shot-5s.png`: the loader's memory-map lines inside the "Rhapsody Operating System" window, black on white, on the dark grey screen. Look at `shot-45s.png`: kernel text in the same window.

- [ ] **Step 11: Commit**

```bash
git add src/bootefi-1/efi_vga.c src/bootefi-1/efi_gfx.h src/bootefi-1/efi_gfx.c \
        src/bootefi-1/efi_console.c src/bootefi-1/efi_main.c \
        src/bootefi-1/handoff.c src/bootefi-1/Makefile
git commit -m "bootefi: draw the loader's output in the kernel's console window, in VGA mode 0x12"
```

---

### Task 3: Boot Graphics panel

Adds boot-2's panel (Panel.image, "Starting Rhapsody", the spinning wait cursor) when `efi_want_splash()` holds, and hands off in `GRAPHICS_MODE` so the kernel keeps it.

**Files:**
- Create: `src/bootefi-1/efi_splash.c`
- Modify: `src/bootefi-1/efi_console.c`
- Modify: `src/bootefi-1/efi_main.c`
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Consumes: `efi_want_splash()` (Task 1); `clearRect()`, `efi_win_draw()`, `efi_win_putc()`, `GFX_*` (Task 2); from boot-2: `loadBitmap()` (`libsaio/bitmap.c`), `PackBitsDecode()` (`libsaio/unpackbits.c`), `fontp`/`blit_string()`/`blit_clear()` (`libsaio/font.c`), `ns_wait1_bitmap`..`ns_wait3_bitmap` (`boot2/bitmaps.c`), `Language` (`libsaio/localize.c`, already linked).
- Produces: `void setMode(int mode);`, `int currentMode(void);`, `void message(char *str, int centered);`, `void spinActivityIndicator(void);`, `void clearActivityIndicator(void);`, `void copyImage(const struct bitmap *, int, int);` (the signatures `libsaio/saio_internal.h` and boot-2's callers use), and `void efi_screen_putc(int c);` for `efi_console.c`.

- [ ] **Step 1: See the splash check fail on Task 2's build**

```bash
sh $SP/build-bootefi.sh $W $SP/t3_before "BOOTEFI_BOOT_STRING=\"rootdev=hd0a\""
python $SP/efi_shot.py $SP/t3_before/BOOTIA32.EFI $SP/t3_before_run 30,45
python $SP/check_splash.py $SP/t3_before_run shot-30s.png shot-45s.png
```

Expected: `FAIL shot-30s.png: (100,24) is (0, 0, 0), expected the dark grey background` (the title bar is there), then `FAILED`.

- [ ] **Step 2: Create `efi_splash.c`**

```c
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
#define VGA_FB      ((unsigned char *)0xA0000)

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
    unsigned char *src_p = rowData, *dst_p, *last_byte, prev_byte;
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
```

Note: `screen_mode` is a static here, not `kernBootStruct->graphicsMode`, on purpose — `putchar` runs before `efi_init_bootstruct()` zeroes that struct, when it still holds garbage.

- [ ] **Step 3: Route text through `efi_splash.c` and drop the stubs (`efi_console.c`)**

Replace the header comment's first sentence

```c
 * disk.c and sys.c call printf/error/verbose/message/getc/putchar/
 * spinActivityIndicator/sleep; this file supplies all of them over the EFI
 * Simple Text I/O protocols. Two symbols in the brief's original list are
```

with

```c
 * disk.c and sys.c call printf/error/verbose/message/getc/putchar/
 * spinActivityIndicator/sleep; this file supplies them over the EFI Simple
 * Text I/O protocols, except message() and the activity indicator, which
 * draw on the Boot Graphics panel and live in efi_splash.c. Two symbols in
 * the brief's original list are
```

Replace

```c
#include "efi_gfx.h"
```

with

```c
#include "efi_gfx.h"

/* efi_splash.c: the console window, or the buffer while the panel is up. */
extern void efi_screen_putc(int c);
```

In `putchar`, replace `        efi_win_putc(c);` with `        efi_screen_putc(c);`.

Delete these three definitions (and the blank line after each):

```c
void message(char *str, int n)
{
    printf("%s\n", str);
}
```

```c
void spinActivityIndicator(void) { }
void clearActivityIndicator(void) { }
```

```c
/* stringTable.c's loadOtherConfigs() calls setMode() only on its "Query"
 * prompt, to put boot-2's graphics panel back into text mode.  This console
 * is always text, so there is nothing to switch. */
void setMode(int mode) { (void)mode; }
```

- [ ] **Step 4: Choose the panel after the config loads (`efi_main.c`)**

Replace

```c
#include "sarld.h"	/* sa_rld_t */
```

(a TAB before the comment) with

```c
#include "sarld.h"	/* sa_rld_t */
#include "efi_splash_rule.h"
```

Replace

```c
extern void efi_gfx_init(void);
```

with

```c
extern void efi_gfx_init(void);

/* efi_console.c; error() counts into it. */
extern int errors;

/* efi_splash.c: the Boot Graphics panel and the calls that draw on it. */
extern void setMode(int mode);
extern int currentMode(void);
extern void message(char *str, int centered);
extern void clearActivityIndicator(void);

#define BOOT_TIMEOUT 10     /* src/boot-2/i386/boot2/boot.h */
```

Replace

```c
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    gImageHandle = image;
```

with

```c
efi_main(EFI_HANDLE image, EFI_SYSTEM_TABLE *systab)
{
    int wantSplash;

    gImageHandle = image;
```

Replace

```c
    printf("loadSystemConfig: %d\n", loadSystemConfig(0, 0));

```

with

```c
    printf("loadSystemConfig: %d\n", loadSystemConfig(0, 0));

    /* boot2/boot.c decides on the Boot Graphics panel once the config
     * is loaded and puts it up straight away; see efi_splash_rule.c. */
    wantSplash = efi_want_splash(kernBootStruct->bootString,
                                 getBoolForKey("Boot Graphics"), errors);
    if (wantSplash) {
        setMode(GRAPHICS_MODE);
        /* No panel to go back to if it would not load. */
        wantSplash = currentMode() == GRAPHICS_MODE;
    }

```

Replace

```c
    removeLinkEditSegment((struct mach_header *)kernBootStruct->kaddr);
    printf("Starting Rhapsody\n");
```

with

```c
    /* boot2/boot.c: show what went wrong in text, then return to the
     * panel for the handoff. */
    if (errors) {
        setMode(TEXT_MODE);
        localPrintf("Errors encountered while starting up the computer.\n");
        localPrintf("Pausing %d seconds...\n", BOOT_TIMEOUT);
        sleep(BOOT_TIMEOUT);
    }
    if (wantSplash)
        setMode(GRAPHICS_MODE);
    message("Starting Rhapsody", 0);

    removeLinkEditSegment((struct mach_header *)kernBootStruct->kaddr);
    clearActivityIndicator();
```

- [ ] **Step 5: Build the new sources (`Makefile`)**

Replace

```make
              $(BOOT2)/libsaio/sys.c
```

(the last line of `BOOT2_SRCS`) with

```make
              $(BOOT2)/libsaio/sys.c \
              $(BOOT2)/libsaio/bitmap.c \
              $(BOOT2)/libsaio/unpackbits.c \
              $(BOOT2)/libsaio/font.c \
              $(BOOT2)/boot2/bitmaps.c
```

Replace

```make
            efi_gfx.c efi_pci.c handoff.c $(BOOT2_SRCS)
```

with

```make
            efi_gfx.c efi_splash.c efi_splash_rule.c efi_pci.c handoff.c \
            $(BOOT2_SRCS)
```

Replace

```make
VPATH := $(BOOT2)/libsaio:$(BOOT2)/libsa
```

with

```make
VPATH := $(BOOT2)/libsaio:$(BOOT2)/libsa:$(BOOT2)/boot2
```

- [ ] **Step 6: Build all three variants**

```bash
sh $SP/build-bootefi.sh $W $SP/t3_v 2>&1 | grep -E "^efi_[a-z_]+\.c:[0-9]+:[0-9]+: (warning|error)"
sh $SP/build-bootefi.sh $W $SP/t3_s "BOOTEFI_BOOT_STRING=\"rootdev=hd0a\"" >/dev/null 2>&1
EXTRA_CFLAGS='-DBOOTEFI_PANEL_PATH=\"/usr/standalone/i386/NoSuch.image\"' \
    sh $SP/build-bootefi.sh $W $SP/t3_np "BOOTEFI_BOOT_STRING=\"rootdev=hd0a\"" >/dev/null 2>&1
ls -la $SP/t3_v/BOOTIA32.EFI $SP/t3_s/BOOTIA32.EFI $SP/t3_np/BOOTIA32.EFI
```

Expected: no `efi_*.c` diagnostic lines (the warnings boot-2's own `bitmap.c`, `unpackbits.c` and `font.c` print are theirs and expected); three `BOOTIA32.EFI` files of about 40 KB.

- [ ] **Step 7: Boot the panel variant**

```bash
python $SP/efi_shot.py $SP/t3_s/BOOTIA32.EFI $SP/t3_s_run 11,30,45
python $SP/check_splash.py $SP/t3_s_run shot-30s.png shot-45s.png
grep -a -c "Errors encountered" $SP/t3_s_run/com1.log
```

Expected: `PASS`; the grep prints `0`. Look at `shot-11s.png` (the panel while drivers load, spinner showing) and `shot-30s.png` (the panel with "Starting Rhapsody" in black at its centre over a light grey bar, the kernel's cursor below). The bar reaching a few pixels past the panel's left edge and over its right border is boot-2's own layout and expected.

- [ ] **Step 8: Boot the verbose variant (regression)**

```bash
python $SP/efi_shot.py $SP/t3_v/BOOTIA32.EFI $SP/t3_v_run 5,45
python $SP/check_window.py $SP/t3_v_run shot-5s.png shot-45s.png
```

Expected: `PASS`. `shot-45s.png` shows kernel text including `root on hd0a` (or the ATA timeout lines after it, the known `docs/kernel/i8259-spurious-slave-irq.md` failure).

- [ ] **Step 9: Boot the missing-panel variant**

```bash
python $SP/efi_shot.py $SP/t3_np/BOOTIA32.EFI $SP/t3_np_run 12,45
python $SP/check_window.py $SP/t3_np_run shot-12s.png shot-45s.png
grep -a -c "Could not load all bitmaps; using text mode." $SP/t3_np_run/com1.log
```

Expected: `PASS`; the grep prints `1` (tried once, not again at handoff).

- [ ] **Step 10: Host tests**

Run: `cd src/bootefi-1/tests && PATH="/c/Program Files/LLVM/bin:$PATH" make CC=clang BUILD=$SP/t3_tests test-acpi test-splash`
Expected: both end `all passed`.

- [ ] **Step 11: Commit**

```bash
git add src/bootefi-1/efi_splash.c src/bootefi-1/efi_console.c \
        src/bootefi-1/efi_main.c src/bootefi-1/Makefile
git commit -m "bootefi: show boot-2's Boot Graphics panel when the config asks for it and -v is not set"
```
