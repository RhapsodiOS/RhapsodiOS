#include "macho.h"
#include "architecture.h"
#include "test.h"
#include <stdlib.h>
#include <unistd.h>

static unsigned char b[4096], x[4096], y[4096];
static char path[128];

static void word(unsigned char *p, unsigned long v, int le) {
    int i;
    for (i = 0; i < 4; i++) p[le ? i : 3-i] = (unsigned char)(v >> (8*i));
}
static unsigned thin(unsigned char *p, unsigned long cpu, int le) {
    memset(p, 0, 28);
    word(p, 0xfeedfaceUL, le); word(p+4, cpu, le);
    word(p+8, 4, le); word(p+12, 1, le);
    return 28;
}
static unsigned fat(unsigned char *p, const unsigned char *a, unsigned na,
                    const unsigned char *c, unsigned nc, int le) {
    unsigned off = nc ? 48 : 28;
    memset(p, 0, off);
    word(p, 0xcafebabeUL, le); word(p+4, nc ? 2 : 1, le);
    word(p+8, 7, le); word(p+16, off, le); word(p+20, na, le);
    memcpy(p+off, a, na);
    if (nc) {
        word(p+28, 18, le); word(p+36, off+na, le);
        word(p+40, nc, le); memcpy(p+off+na, c, nc);
    }
    return off+na+nc;
}
static unsigned member(unsigned char *p, unsigned off, const char *name,
                       const unsigned char *data, unsigned n) {
    char size[32];
    memset(p+off, ' ', 60); memcpy(p+off, name, strlen(name));
    sprintf(size, "%u", n); memcpy(p+off+48, size, strlen(size));
    p[off+58] = '`'; p[off+59] = '\n';
    memcpy(p+off+60, data, n);
    if (n & 1) p[off+60+n] = '\n';
    return off+60+n+(n&1);
}
static void expect(const unsigned char *p, unsigned n, int status, unsigned want) {
    FILE *f = fopen(path, "wb");
    unsigned mask = 99;
    int code = 99;
    CHECK(f != 0);
    if (!f) return;
    CHECK_INT(fwrite(p, 1, n, f), n); CHECK_INT(fclose(f), 0);
    CHECK_INT(macho_file_arches(path, &mask, &code), status);
    if (!status) { CHECK_INT(mask, want); CHECK_INT(code, want != 0); }
}
TEST(test_plain_and_io) {
    unsigned mask; int code;
    expect(b, 0, 0, 0);
    expect((const unsigned char *)"#!/bin/sh\necho hi\n", 18, 0, 0);
    CHECK_INT(macho_file_arches("/no/such/rbuild-macho-file", &mask, &code), 1);
}
TEST(test_thin) {
    int le; unsigned n;
    for (le = 0; le <= 1; le++) {
        n = thin(b, 7, le); expect(b, n, 0, RB_ARCH_I386);
        thin(b, 18, le); expect(b, n, 0, RB_ARCH_PPC);
        expect(b, 4, 1, 0); expect(b, 27, 1, 0);
        thin(b, 12, le); expect(b, n, 1, 0);
        thin(b, 7, le); word(b+20, 8, le); expect(b, n, 1, 0);
        thin(b, 7, le); word(b+16, 1, le); expect(b, n, 1, 0);
        thin(b, 7, le); word(b, 0xfeedfacfUL, le); expect(b, n, 1, 0);
        word(b, 0xcafebabfUL, le); expect(b, n, 1, 0);
    }
}
TEST(test_load_commands) {
    int le;
    for (le = 0; le <= 1; le++) {
        thin(b, 7, le);
        word(b+16, 1, le); word(b+20, 24, le);
        /* An empty LC_SYMTAB with its complete 24-byte command. */
        memset(b+28, 0, 28); word(b+28, 2, le); word(b+32, 24, le);
        expect(b, 52, 0, RB_ARCH_I386);
        word(b+32, 4, le); expect(b, 52, 1, 0);  /* Below command header. */
        word(b+32, 23, le); expect(b, 52, 1, 0); /* Misaligned command. */
        word(b+32, 28, le); expect(b, 52, 1, 0); /* Past sizeofcmds. */
        word(b+32, 20, le); expect(b, 52, 1, 0); /* Unclaimed command bytes. */
        word(b+32, 24, le); word(b+16, 2, le); word(b+20, 28, le);
        expect(b, 56, 1, 0); /* Truncated header of the second command. */
    }
}
TEST(test_fat) {
    unsigned n; int le;
    thin(x, 7, 1); thin(y, 18, 0);
    for (le = 0; le <= 1; le++) {
        n = fat(b, x, 28, y, 28, le); expect(b, n, 0, RB_ARCH_UNIVERSAL);
        expect(b, 7, 1, 0); expect(b, 47, 1, 0); expect(b, n-1, 1, 0);
        word(b+36, 49, le); expect(b, n, 1, 0);
        n = fat(b, x, 28, y, 28, le);
        word(b+28, 7, le); expect(b, n, 1, 0);
        n = fat(b, x, 28, x, 28, le); expect(b, n, 1, 0);
        n = fat(b, x, 28, y, 28, le);
        word(b+16, 8, le); expect(b, n, 1, 0);
        word(b+16, 0xfffffff0UL, le); expect(b, n, 1, 0);
        word(b+4, 0xffffffffUL, le); expect(b, n, 1, 0);
        n = fat(b, x, 28, y, 28, le);
        word(b+8, 12, le); expect(b, n, 1, 0);
        word(b+4, 0, le); expect(b, 8, 1, 0);
        n = fat(b, x, 28, y, 0, le); expect(b, n, 0, RB_ARCH_I386);
        word(b+20, 0, le); expect(b, n, 1, 0);
    }
}
TEST(test_archives) {
    unsigned n, nx, ny;
    thin(y, 7, 1); memcpy(b, "!<arch>\n", 8);
    expect(b, 8, 0, 0);
    n = member(b, 8, "__.SYMDEF", y, 3); expect(b, n, 0, 0);
    n = member(b, n, "one.o/", y, 28); expect(b, n, 0, 1);
    n = member(b, n, "two.o/", y, 28); expect(b, n, 0, 1);
    thin(y, 18, 0); n = member(b, n, "three.o/", y, 28); expect(b, n, 1, 0);
    memcpy(x, "!<arch>\n", 8); thin(b, 7, 1);
    nx = member(x, 8, "i386.o/", b, 28);
    memcpy(y, "!<arch>\n", 8); thin(b, 18, 0);
    ny = member(y, 8, "ppc.o/", b, 28);
    n = fat(b, x, nx, y, ny, 0); expect(b, n, 0, 3);
    n = fat(b, y, ny, x, nx, 0); expect(b, n, 1, 0);
    memcpy(b, "!<arch>\n", 8);
    n = member(b, 8, "bad.o/", (const unsigned char *)"hello", 5);
    expect(b, n, 1, 0); expect(b, n-1, 1, 0);
    n = member(b, 8, "empty.o/", y, 0); expect(b, n, 1, 0);
    thin(y, 7, 1); n = member(b, 8, "ok.o/", y, 28);
    expect(b, n-1, 1, 0); expect(b, 67, 1, 0);
    b[66] = '?'; expect(b, n, 1, 0); b[66] = '`';
    b[56] = '-'; expect(b, n, 1, 0);
    memset(b+56, '9', 10); expect(b, n, 1, 0);
}
TEST(test_archive_names) {
    unsigned n;
    memcpy(b, "!<arch>\n", 8);
    memcpy(y, "a-very-long-object-name.o", 25); thin(y+25, 7, 1);
    n = member(b, 8, "#1/25", y, 53); expect(b, n, 0, 1);
    n = member(b, 8, "#1/99", y, 53); expect(b, n, 1, 0);
    n = member(b, 8, "#1/x", y, 53); expect(b, n, 1, 0);
    memset(y, 0, 24); memcpy(y, "__.SYMDEF SORTED", 16);
    n = member(b, 8, "#1/24", y, 24); expect(b, n, 0, 0);
    n = member(b, 8, "//", (const unsigned char *)"long-object-name.o/\n", 20);
    thin(y, 18, 0); n = member(b, n, "/0", y, 28); expect(b, n, 0, 2);
    b[8+60+20+1] = '9'; expect(b, n, 1, 0);
    n = member(b, 8, "/0", y, 28); expect(b, n, 1, 0);
    n = member(b, 8, "/", y, 3); expect(b, n, 0, 0);
    n = member(b, 8, "/SYM64/", y, 3); expect(b, n, 0, 0);
    n = member(b, 8, "__.SYMDEFbad", y, 3); expect(b, n, 1, 0);
    n = member(b, 8, "__.SYMDEFbad", y, 3); b[17] = 0;
    expect(b, n, 1, 0);
}
TEST(test_nesting) {
    unsigned n; int i;
    n = thin(x, 7, 1);
    for (i = 0; i < 5; i++) {
        n = fat(b, x, n, y, 0, 0); memcpy(x, b, n);
        if (i == 3) expect(b, n, 0, 1);
    }
    expect(b, n, 1, 0);
}
static void run_all(void) {
    sprintf(path, "/tmp/rbuild-test-macho-%ld", (long)getpid());
    RUN(test_plain_and_io); RUN(test_thin); RUN(test_load_commands); RUN(test_fat);
    RUN(test_archives); RUN(test_archive_names); RUN(test_nesting);
    unlink(path);
}
TEST_MAIN()
