/* Shim: bsd/machine/ansi.h #include "i386/ansi.h", which this checkout's
 * src/CoreOS/kernel-7 tree does not ship (raw project source, not an assembled
 * SDK). src/CoreOS/architecture-1/i386/ansi.h is the same BSD ansi.h; forward to
 * it rather than editing src/CoreOS/kernel-7 or src/boot-2. */
#include "architecture/i386/ansi.h"
