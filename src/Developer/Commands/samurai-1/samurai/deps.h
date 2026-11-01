/* RhapsodiOS: C89 and legacy POSIX port. */
#include "compat.h"
struct edge;

void depsinit(const char *);
void depsclose(void);
void depsload(struct edge *);
void depsrecord(struct edge *);
