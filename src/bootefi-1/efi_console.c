/* Console/diagnostic backend for boot-2's reused libsaio/libsa sources.
 * disk.c and sys.c call printf/error/verbose/message/getc/putchar/
 * spinActivityIndicator/sleep; this file supplies them over the EFI Simple
 * Text I/O protocols, except message() and the activity indicator, which
 * draw on the Boot Graphics panel and live in efi_splash.c. Two symbols in
 * the brief's original list are NOT supplied here because sys.c/disk.c
 * already define them: flushdev() (sys.c) and diskActivityHook() (disk.c,
 * which just calls spinActivityIndicator()).
 */
#include <stdarg.h>
#include "efi.h"
#include "io_inline.h"
#include "efi_gfx.h"

/* efi_splash.c: the console window, or the buffer while the panel is up. */
extern void efi_screen_putc(int c);

/* libsa/sprintf.c's va_list formatter into a bounded buffer. */
extern int slvprintf(char *buffer, int len, const char *fmt, va_list arg);

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
        efi_screen_putc(c);
        return;
    }

    if (c == '\n')
        s[i++] = L'\r';
    s[i++] = (CHAR16)c;
    s[i] = 0;
    gST->ConOut->OutputString(gST->ConOut, s);
}

static int vprint(const char *fmt, va_list ap)
{
    char buf[512];
    char *p;

    slvprintf(buf, sizeof(buf), fmt, ap);
    for (p = buf; *p; p++)
        putchar(*p);
    return 0;
}

int printf(const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vprint(fmt, ap);
    va_end(ap);
    return n;
}

int localPrintf(const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = vprint(fmt, ap);
    va_end(ap);
    return n;
}

int errors;

int error(const char *fmt, ...)
{
    va_list ap;
    errors++;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
    return 0;
}

int gVerboseMode = 1;

int verbose(const char *fmt, ...)
{
    va_list ap;
    if (!gVerboseMode)
        return 0;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
    return 0;
}

int getc(void)
{
    EFI_INPUT_KEY key;

    for (;;) {
        EFI_STATUS st = gST->ConIn->ReadKeyStroke(gST->ConIn, &key);
        if (!EFI_ERROR(st)) {
            if (key.UnicodeChar)
                return (int)key.UnicodeChar;
        }
        gBS->Stall(1000);
    }
}

void sleep(int seconds)
{
    gBS->Stall((UINTN)seconds * 1000000);
}

/* choose.c's interactive picker (chooseDriverFromList/chooseSimple) calls
 * gets() to read a typed choice.  Both callers are on the prompting path
 * that loadBootDrivers(0, 0, 0)'s non-prompting arguments never reach, so
 * this loader has no keyboard-line-editing gets() of its own (boot-2's
 * gets.c needs the real-mode time18()/readKeyboardStatus() BIOS calls this
 * EFI build doesn't have) -- a stub that reports "no input" is enough to
 * link and is never exercised. */
int gets(char *buf, int len)
{
    if (len > 0)
        buf[0] = '\0';
    return 0;
}

/* halt() is real-mode assembly in boot-2 (asm.s, not part of this build)
 * with no EFI equivalent; sys.c calls it on an unrecoverable device error.
 * panic() is not called by boot-2 directly, but is pulled in via two
 * "extern __inline" functions in kernel-7's <sys/vnode.h> (vhold()/vref())
 * that gnu89 inline semantics still emit into every translation unit that
 * includes it, even though nothing here calls them. */
void halt(void)
{
    printf("halt()\n");
    for (;;)
        ;
}

void panic(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprint(fmt, ap);
    va_end(ap);
    for (;;)
        ;
}
