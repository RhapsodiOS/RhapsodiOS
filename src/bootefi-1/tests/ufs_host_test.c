/* Extract one file from a Rhapsody disk image using boot2's own UFS reader.
 * usage: ufs_host_test IMAGE DEVSPEC PATH   e.g. ... hybrid.img 'hd(0,a)' /mach_kernel */
/* No <fcntl.h>/<unistd.h> here: this file is compiled with open/read/close
 * renamed to sa_open/sa_read/sa_close (see the tests Makefile), and those
 * headers' own declarations of the real open()/read()/close() would be
 * renamed right along with them, silently aliasing our sa_* calls onto the
 * real libc symbols.  host_devread.c (compiled separately, without the
 * rename) does the one real open(2) via host_open_image(). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "saio.h"

extern int host_fd;
extern int host_open_image(const char *path);

/* boot2's sys.c reads kernBootStruct for the default device and numIDEs. */
#include "kernBootStruct.h"
static KERNBOOTSTRUCT host_bootstruct;
KERNBOOTSTRUCT *kernBootStruct = &host_bootstruct;

int main(int argc, char **argv)
{
    char spec[256], buf[65536];
    int fd, n;

    if (argc != 4) {
        fprintf(stderr, "usage: %s IMAGE DEVSPEC PATH\n", argv[0]);
        return 2;
    }
    if (host_open_image(argv[1]) < 0) {
        perror(argv[1]);
        return 1;
    }
    /* hd() opens are rejected outright when numIDEs is zero (sys.c). */
    kernBootStruct->numIDEs = 1;

    snprintf(spec, sizeof(spec), "%s%s", argv[2], argv[3]);
    fd = sa_open(spec, 0);
    if (fd < 0) {
        fprintf(stderr, "open(%s) failed\n", spec);
        return 1;
    }
    while ((n = sa_read(fd, buf, sizeof(buf))) > 0)
        fwrite(buf, 1, n, stdout);
    sa_close(fd);
    return 0;
}
