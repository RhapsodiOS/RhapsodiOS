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

TEST(test_str_ops) {
    char a[] = "line\n";
    char b[] = "MixEd";
    char c[] = "  hi  ";
    CHECK_STR(str_chomp(a), "line");
    str_lowercase(b); CHECK_STR(b, "mixed");
    CHECK_STR(str_trim(c), "hi");
    CHECK_INT(str_has_prefix("foobar", "foo"), 1);
    CHECK_INT(str_has_prefix("foobar", "bar"), 0);
    CHECK_INT(str_has_suffix("x.deb", ".deb"), 1);
    CHECK_INT(str_has_suffix("x.apk", ".deb"), 0);
}

TEST(test_str_split) {
    strlist l;
    strlist_init(&l);
    str_split_ws("  dir   /path/to/src   all ", &l);
    CHECK_INT(l.count, 3);
    CHECK_STR(l.items[0], "dir");
    CHECK_STR(l.items[1], "/path/to/src");
    CHECK_STR(l.items[2], "all");
    strlist_free(&l);

    strlist_init(&l);
    str_split_chars("build-base, gnuzip  libfoo", " ,", &l);
    CHECK_INT(l.count, 3);
    CHECK_STR(l.items[0], "build-base");
    CHECK_STR(l.items[1], "gnuzip");
    CHECK_STR(l.items[2], "libfoo");
    strlist_free(&l);
}

TEST(test_str_cats_pathjoin) {
    char *x = str_cats("a", "-", "b", (char *)0);
    char *y = path_join("/root", "usr/bin");
    CHECK_STR(x, "a-b");
    CHECK_STR(y, "/root/usr/bin");
    free(x); free(y);
}

static void run_all(void) {
    RUN(test_sbuf_appends);
    RUN(test_strlist_push);
    RUN(test_str_ops);
    RUN(test_str_split);
    RUN(test_str_cats_pathjoin);
}

TEST_MAIN()
