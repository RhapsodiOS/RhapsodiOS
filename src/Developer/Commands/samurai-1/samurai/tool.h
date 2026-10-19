/* RhapsodiOS: C89 and legacy POSIX port. */
#include "compat.h"
struct tool {
	const char *name;
	int (*run)(int, char *[]);
};

const struct tool *toolget(const char *);
