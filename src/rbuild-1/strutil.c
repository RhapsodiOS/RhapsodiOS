#include "strutil.h"
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>

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

char *str_chomp(char *s) {
    size_t n = strlen(s);
    if (n > 0 && s[n - 1] == '\n') s[n - 1] = '\0';
    return s;
}

void str_lowercase(char *s) {
    for (; *s; s++) *s = (char) tolower((unsigned char) *s);
}

char *str_trim(char *s) {
    char *end;
    while (*s && isspace((unsigned char) *s)) s++;
    if (*s == '\0') return s;
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char) *end)) *end-- = '\0';
    return s;
}

int str_has_prefix(const char *s, const char *prefix) {
    size_t n = strlen(prefix);
    return strncmp(s, prefix, n) == 0;
}

int str_has_suffix(const char *s, const char *suffix) {
    size_t ls = strlen(s), lx = strlen(suffix);
    if (lx > ls) return 0;
    return strcmp(s + (ls - lx), suffix) == 0;
}

static int in_set(char c, const char *set) {
    for (; *set; set++) if (*set == c) return 1;
    return 0;
}

static void split_on(const char *s, const char *seps, strlist *out) {
    const char *p = s;
    while (*p) {
        const char *start;
        while (*p && in_set(*p, seps)) p++;
        if (*p == '\0') break;
        start = p;
        while (*p && !in_set(*p, seps)) p++;
        {
            char *tok = (char *) xmalloc((size_t)(p - start) + 1);
            memcpy(tok, start, (size_t)(p - start));
            tok[p - start] = '\0';
            strlist_push_owned(out, tok);
        }
    }
}

void str_split_ws(const char *s, strlist *out) {
    split_on(s, " \t\n\r\f\v", out);
}

void str_split_chars(const char *s, const char *seps, strlist *out) {
    split_on(s, seps, out);
}

char *str_cats(const char *first, ...) {
    sbuf s;
    va_list ap;
    const char *arg;
    char *out;
    sbuf_init(&s);
    sbuf_puts(&s, first);
    va_start(ap, first);
    while ((arg = va_arg(ap, const char *)) != 0) sbuf_puts(&s, arg);
    va_end(ap);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

char *path_join(const char *a, const char *b) {
    return str_cats(a, "/", b, (char *)0);
}
