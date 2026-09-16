#ifndef RBUILD_ARCHITECTURE_H
#define RBUILD_ARCHITECTURE_H

#define RB_ARCH_I386 1U
#define RB_ARCH_PPC 2U
#define RB_ARCH_UNIVERSAL 3U
#define RB_ARCH_POLICY_VERSION "1"

/* Return zero on success; leave output unchanged on invalid input. */
int architecture_parse(const char *label, unsigned *mask);
int architecture_resolve(unsigned source, unsigned operation, unsigned *effective);
/* Return NULL for an invalid mask. */
const char *architecture_label(unsigned mask);
const char *architecture_archs(unsigned mask);
const char *architecture_cflags(unsigned mask);
const char *architecture_filename_token(unsigned mask);
int architecture_path_has_token(const char *path, unsigned mask);

#endif
