/* Shim: bsd/sys/param.h #include <machine/limits.h>, which this checkout's
 * src/kernel-7 tree does not ship under bsd/machine (raw project source,
 * not an assembled SDK). src/architecture-1/i386/limits.h is the matching
 * machine-limits header; forward to it rather than editing src/kernel-7 or
 * src/boot-2. */
#include "architecture/i386/limits.h"
