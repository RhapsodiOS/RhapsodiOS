#ifndef RBUILD_MACHO_H
#define RBUILD_MACHO_H

/* Zero on success; non-code has mask=0 and machine_code=0.
 * One on I/O, malformed recognized code, or unsupported CPU/container.
 * Outputs are unchanged on error. Masks are RB_ARCH_* from architecture.h.
 * Archives must contain consistent code members; only tables are skipped. */
int macho_file_arches(const char *path, unsigned *mask, int *machine_code);

#endif
