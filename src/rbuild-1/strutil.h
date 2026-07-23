#ifndef RBUILD_STRUTIL_H
#define RBUILD_STRUTIL_H

#include <stddef.h>
#include <stdlib.h>

void *xmalloc(size_t n);
void *xrealloc(void *p, size_t n);
char *xstrdup(const char *s);

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
} sbuf;

void sbuf_init(sbuf *s);
void sbuf_free(sbuf *s);
void sbuf_putc(sbuf *s, char c);
void sbuf_puts(sbuf *s, const char *str);
void sbuf_putn(sbuf *s, const char *str, size_t n);
char *sbuf_steal(sbuf *s);   /* NUL-terminated malloc'd copy; resets s */

typedef struct {
    char **items;
    size_t count;
    size_t cap;
} strlist;

void strlist_init(strlist *l);
void strlist_free(strlist *l);
void strlist_push(strlist *l, const char *s);       /* copies */
void strlist_push_owned(strlist *l, char *s);       /* takes ownership */

#endif
