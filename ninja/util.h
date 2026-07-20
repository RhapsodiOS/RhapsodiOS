#ifndef RHAP_UTIL_H
#define RHAP_UTIL_H
#include <stddef.h>
void die(const char *msg);
void *xmalloc(size_t n);
void *xrealloc(void *p, size_t n);
char *xstrdup(const char *s);
const char *env_or(const char *name, const char *dflt);
void strlower(char *s);
char *strtrim(char *s);
#endif
