/* RhapsodiOS: C89 and legacy POSIX port. */
#include "compat.h"
struct node;

void loginit(const char *);
void logclose(void);
void logrecord(struct node *);
