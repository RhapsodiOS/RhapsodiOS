#include "strutil.h"
#include "test.h"

TEST(test_sbuf_appends) {
    sbuf s;
    char *out;
    sbuf_init(&s);
    sbuf_puts(&s, "he");
    sbuf_putc(&s, 'l');
    sbuf_putn(&s, "lo world", 2);
    out = sbuf_steal(&s);
    CHECK_STR(out, "hello");
    free(out);
    sbuf_free(&s);
}

TEST(test_strlist_push) {
    strlist l;
    strlist_init(&l);
    strlist_push(&l, "a");
    strlist_push(&l, "b");
    strlist_push_owned(&l, xstrdup("c"));
    CHECK_INT(l.count, 3);
    CHECK_STR(l.items[0], "a");
    CHECK_STR(l.items[2], "c");
    strlist_free(&l);
}

static void run_all(void) {
    RUN(test_sbuf_appends);
    RUN(test_strlist_push);
}

TEST_MAIN()
