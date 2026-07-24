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

/* str_chomp/str_trim/str_lowercase mutate the caller's buffer in place and
   return a pointer INTO it (str_trim may point past the start) — do not free
   the result; it is not separately allocated. */
char *str_chomp(char *s);
void str_lowercase(char *s);
char *str_trim(char *s);
int str_has_prefix(const char *s, const char *prefix);
int str_has_suffix(const char *s, const char *suffix);
void str_split_ws(const char *s, strlist *out);
void str_split_chars(const char *s, const char *seps, strlist *out);
/* str_cats/path_join return a fresh malloc'd buffer the caller must free. */
char *str_cats(const char *first, ...);
char *path_join(const char *a, const char *b);

#endif
