/* Shim: boot2 sources sometimes spell this <bsd/sys/types.h>. The repo's
 * own src/kernel-7/bsd/sys/types.h is missing its machine/i386/ansi.h
 * dependency on this host, so redirect to the host SDK's sys/types.h. */
#include <sys/types.h>
