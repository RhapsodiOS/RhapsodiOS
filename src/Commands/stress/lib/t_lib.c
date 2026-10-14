#include <errno.h>
#include <stdio.h>
#include <string.h>
#include "stress.h"

#define CHECK(c) do { if (!(c)) { printf("t_lib: FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

static unsigned char big[4096], win[100];

int
main(void)
{
	struct st_rng a, b, c;
	unsigned long v;
	int i;

	CHECK(st_mix(0) == 0);			/* the mix fixes 0; seeds avoid it */
	CHECK(st_mix(1) != 1);
	CHECK(st_strhash("") == 0x811c9dc5UL);
	/* determinism: same seed/test/idx -> same stream; different idx -> different */
	st_rng_init(&a, 1234, "cow", 0);
	st_rng_init(&b, 1234, "cow", 0);
	st_rng_init(&c, 1234, "cow", 1);
	CHECK(st_rand(&a) == st_rand(&b));
	CHECK(st_rand(&a) != st_rand(&c));
	for (i = 0; i < 1000; i++) {
		v = st_range(&a, 5, 9);
		CHECK(v >= 5 && v <= 9);
	}
	/* patterns: offset-addressable, unaligned windows agree with the whole */
	st_fill(big, 4096, 77, 0);
	st_fill(win, 100, 77, 13);
	CHECK(memcmp(big + 13, win, 100) == 0);
	CHECK(st_check(big, 4096, 77, 0) == -1);
	big[1234] ^= 0x40;
	CHECK(st_check(big, 4096, 77, 0) == 1234);
	CHECK(st_check(big, 4096, 78, 0) == 0);	/* wrong key fails at once */
	/* known vector pins the byte order for ppc too */
	CHECK(st_mix(1) == 0x688990c0UL);
	CHECK(st_mix(0x9e3779baUL) == 0x9f505634UL);	/* key 1, offset 0: (1 ^ 0) + 0x9e3779b9 */
	st_fill(win, 4, 1, 0);
	CHECK(win[0] == 0x34 && win[1] == 0x56 && win[2] == 0x50 && win[3] == 0x9f);
	/* where (o >> 2) == key the word must not be zero, or NUL holes hide */
	st_fill(win, 4, 5, 5 * 4);
	CHECK(win[0] | win[1] | win[2] | win[3]);
	CHECK(strcmp(st_errname(ENOSYS), "ENOSYS") == 0);
	CHECK(strcmp(st_errname(9999), "E9999") == 0);
	printf("t_lib: ok\n");
	return 0;
}
