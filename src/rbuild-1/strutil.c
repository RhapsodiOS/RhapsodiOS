#include "strutil.h"
#include <string.h>
#include <stdio.h>

void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (p == 0) { fprintf(stderr, "rbuild: out of memory\n"); exit(2); }
    return p;
}

void *xrealloc(void *p, size_t n) {
    void *q = realloc(p, n ? n : 1);
    if (q == 0) { fprintf(stderr, "rbuild: out of memory\n"); exit(2); }
    return q;
}

char *xstrdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *p = (char *) xmalloc(n);
    memcpy(p, s, n);
    return p;
}

void sbuf_init(sbuf *s) {
    s->cap = 16;
    s->len = 0;
    s->buf = (char *) xmalloc(s->cap);
    s->buf[0] = '\0';
}

void sbuf_free(sbuf *s) {
    free(s->buf);
    s->buf = 0;
    s->len = 0;
    s->cap = 0;
}

static void sbuf_reserve(sbuf *s, size_t extra) {
    size_t need = s->len + extra + 1;
    if (need > s->cap) {
        while (s->cap < need) s->cap *= 2;
        s->buf = (char *) xrealloc(s->buf, s->cap);
    }
}

void sbuf_putc(sbuf *s, char c) {
    sbuf_reserve(s, 1);
    s->buf[s->len++] = c;
    s->buf[s->len] = '\0';
}

void sbuf_putn(sbuf *s, const char *str, size_t n) {
    sbuf_reserve(s, n);
    memcpy(s->buf + s->len, str, n);
    s->len += n;
    s->buf[s->len] = '\0';
}

void sbuf_puts(sbuf *s, const char *str) {
    sbuf_putn(s, str, strlen(str));
}

char *sbuf_steal(sbuf *s) {
    char *out = xstrdup(s->buf);
    s->len = 0;
    s->buf[0] = '\0';
    return out;
}

void strlist_init(strlist *l) {
    l->cap = 4;
    l->count = 0;
    l->items = (char **) xmalloc(l->cap * sizeof(char *));
}

void strlist_free(strlist *l) {
    size_t i;
    for (i = 0; i < l->count; i++) free(l->items[i]);
    free(l->items);
    l->items = 0;
    l->count = 0;
    l->cap = 0;
}

void strlist_push_owned(strlist *l, char *s) {
    if (l->count == l->cap) {
        l->cap *= 2;
        l->items = (char **) xrealloc(l->items, l->cap * sizeof(char *));
    }
    l->items[l->count++] = s;
}

void strlist_push(strlist *l, const char *s) {
    strlist_push_owned(l, xstrdup(s));
}
