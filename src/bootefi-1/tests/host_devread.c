/* POSIX file-backed replacement for the BIOS layer under boot2's disk.c.
 * disk.c itself is compiled unchanged; we supply only what it calls.
 * Prototypes here are matched to src/boot-2/i386/libsaio/saio_internal.h,
 * which disk.c (transitively, via libsaio.h) also sees. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BPS 512

/* intbuf's backing store: sized to hold at least BIOS_LEN (0x2400) so
 * N_CACHE_SECS worth of sectors fit.  Not static: disk.c's own `intbuf`
 * is initialized to its address at file scope (see host_bios_addr.h), so
 * it must still be a real symbol by the time disk.c is compiled. */
char intbuf_backing[16 * 512];

/* disk.c indexes this by (biosdev - 0x80) to choose the LBA path. */
unsigned char uses_ebios[8] = {1, 1, 1, 1, 1, 1, 1, 1};

int host_fd = -1;

/* Real open(2) on the image file; ufs_host_test.c's own open()/read()/close()
 * calls are remapped to sa_open/sa_read/sa_close (via -D) so they reach
 * boot2's sys.c instead of colliding with these libc names. */
int host_open_image(const char *path)
{
    host_fd = open(path, O_RDONLY);
    return host_fd;
}

/* Read nsecs sectors starting at secno into disk.c's cache buffer. */
int ebiosread(int biosdev, long secno, int nsecs)
{
    ssize_t want = (ssize_t)nsecs * BPS;
    ssize_t n = pread(host_fd, intbuf_backing, want, (off_t)secno * BPS);

    if (n < 0)
        return -1;
    if (n < want)                       /* short read past end: zero-fill */
        memset(intbuf_backing + n, 0, want - n);
    return 0;
}

/* The CHS path is unreachable because uses_ebios is always set. */
int biosread(int dev, int cyl, int head, int sec, int nsecs)
{
    return -1;
}

/* devopen() only checks this for non-zero; the geometry feeds the CHS path. */
unsigned int get_diskinfo(int biosdev)
{
    return 0x3F | (0x0F << 8);
}

void turnOffFloppy(void) { }
void spinActivityIndicator(void) { }
void clearActivityIndicator(void) { }

/* halt() is real-mode assembly on boot2 (asm.s) that stops the CPU; on the
 * host, a fatal boot2 error just ends the test process. */
void halt(void) { exit(1); }

/* ptol() (partition letter -> number) is normally pulled from
 * src/boot-2/i386/libsa/string1.c, but that file also (re)defines
 * strlen/strcmp/strcpy/... with old K&R signatures that conflict with the
 * host <string.h> prototypes once it's dragged in transitively (e.g. for
 * size_t).  Reproduced verbatim here rather than pull in the whole file. */
int ptol(char *str)
{
    register int c = *str;

    if (c <= '7' && c >= '0')
        c -= '0';
    else if (c <= 'h' && c >= 'a')
        c -= 'a';
    else c = 0;
    return c;
}

#include <stdarg.h>
int error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    return 0;
}
int verbose(const char *fmt, ...) { return 0; }
