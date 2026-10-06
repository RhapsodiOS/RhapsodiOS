#include <stdio.h>
#include <string.h>
#include "layout.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
	printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } \
	} while (0)

static void set(struct table *t, int i, int type, int active,
		unsigned long start, unsigned long count)
{
	t->p[i].type = type; t->p[i].active = active;
	t->p[i].start = start; t->p[i].count = count;
}

static int chs_is(unsigned long lba, unsigned h, unsigned s,
		  int a, int b, int c)
{
	unsigned char o[3];
	lba_to_chs(lba, h, s, o);
	return o[0] == a && o[1] == b && o[2] == c;
}

static void test_geometry_matches_build_uefi_image(void)
{
	unsigned h, s;
	lba_geometry(2097152ul, &h, &s);  CHECK(h == 32 && s == 63);
	lba_geometry(4194304ul, &h, &s);  CHECK(h == 128 && s == 63);
	lba_geometry(8388608ul, &h, &s);  CHECK(h == 255 && s == 63);
	lba_geometry(16777216ul, &h, &s); CHECK(h == 255 && s == 63);
}

static void test_chs_matches_build_uefi_image(void)
{
	CHECK(chs_is(2048, 128, 63, 0x20, 0x21, 0x00));
	CHECK(chs_is(133119, 128, 63, 0x41, 0x01, 0x10));
	CHECK(chs_is(133120, 128, 63, 0x41, 0x02, 0x10));
	CHECK(chs_is(4193279ul, 128, 63, 0x7f, 0xbf, 0x07));
	CHECK(chs_is(16771859ul, 255, 63, 0xfe, 0xff, 0xff));
}

static void test_auto_2gb(void)
{
	struct table t;
	CHECK(layout_auto(4194304ul, &t) == 0);
	CHECK(t.p[0].type == 0xEF && t.p[0].active == 0 &&
	      t.p[0].start == 2048 && t.p[0].count == 131072);
	CHECK(t.p[1].type == 0xA7 && t.p[1].active != 0 &&
	      t.p[1].start == 133120 && t.p[1].count == 4060160);
	CHECK(t.p[2].type == 0 && t.p[2].count == 0);
	CHECK(t.p[3].type == 0 && t.p[3].count == 0);
}

static void test_auto_rounds_down_to_a_whole_cylinder(void)
{
	struct table t;
	CHECK(layout_auto(2097152ul + 1000, &t) == 0);
	CHECK(t.p[1].count == 1963520);
}

static void test_auto_refuses_under_1gb(void)
{
	struct table t;
	CHECK(layout_auto(2097151ul, &t) == -1);
	CHECK(layout_auto(2097152ul, &t) == 0);
}

static void test_auto_ignores_an_existing_table(void)
{
	unsigned char boot0[446], mbr[512], mbr2[512];
	struct table old, t, back;
	memset(boot0, 0x90, sizeof boot0);
	memset(&old, 0, sizeof old);
	set(&old, 0, 0x0C, 0x80, 63, 1000000);
	mbr_encode(boot0, 4194304ul, &old, mbr);
	CHECK(mbr_decode(mbr, &t) == 0);
	CHECK(t.p[0].type == 0x0C);
	CHECK(layout_auto(4194304ul, &t) == 0);
	mbr_encode(boot0, 4194304ul, &t, mbr2);
	CHECK(mbr_decode(mbr2, &back) == 0);
	CHECK(back.p[0].type == 0xEF && back.p[1].type == 0xA7);
	CHECK(back.p[2].type == 0 && back.p[2].count == 0);
	CHECK(back.p[3].type == 0 && back.p[3].count == 0);
}

static void test_check_rules(void)
{
	unsigned long total = 4194304ul;
	struct table good, t;

	layout_auto(total, &good);
	CHECK(layout_check(total, &good) == NULL);

	t = good; t.p[1].count = 2286080ul;
	set(&t, 2, 0x07, 0, 2500000ul, 1000);
	CHECK(layout_check(total, &t) == NULL);

	t = good; t.p[1].type = 0x83;
	CHECK(layout_check(total, &t) != NULL);
	t = good; set(&t, 2, 0xA7, 0, 0, 0);
	t.p[2].start = 3000000ul; t.p[2].count = 100;
	t.p[1].count = 2286080ul;
	CHECK(layout_check(total, &t) != NULL);
	t = good; t.p[1].active = 0;
	CHECK(layout_check(total, &t) != NULL);
	t = good; t.p[0].count = 131071;
	CHECK(layout_check(total, &t) != NULL);
	t = good; set(&t, 2, 0x07, 0, 200000ul, 1000);
	CHECK(layout_check(total, &t) != NULL);
	t = good; t.p[1].count -= 1;
	CHECK(layout_check(total, &t) != NULL);
	t = good; t.p[1].count = 2286080ul;
	set(&t, 2, 0xEF, 0, 2500000ul, 1000);
	CHECK(layout_check(total, &t) != NULL);
	t = good; t.p[1].count = 2286080ul;
	set(&t, 2, 0x07, 0, total - 10, 100);
	CHECK(layout_check(total, &t) != NULL);
}

static void test_mbr_roundtrip(void)
{
	unsigned char boot0[446], mbr[512], c[3];
	struct table t, back;
	unsigned long total = 4194304ul;
	unsigned h, s;
	int i;

	for (i = 0; i < 446; i++) boot0[i] = (unsigned char)i;
	layout_auto(total, &t);
	mbr_encode(boot0, total, &t, mbr);
	CHECK(memcmp(mbr, boot0, 446) == 0);
	CHECK(mbr[510] == 0x55 && mbr[511] == 0xAA);
	lba_geometry(total, &h, &s);
	CHECK(mbr[446] == 0x00 && mbr[462] == 0x80);
	lba_to_chs(2048, h, s, c);
	CHECK(memcmp(mbr + 447, c, 3) == 0);
	lba_to_chs(2048 + 131072 - 1, h, s, c);
	CHECK(memcmp(mbr + 451, c, 3) == 0);
	CHECK(mbr[450] == 0xEF && mbr[466] == 0xA7);
	lba_to_chs(133120, h, s, c);
	CHECK(memcmp(mbr + 463, c, 3) == 0);
	CHECK(mbr_decode(mbr, &back) == 0);
	CHECK(memcmp(&back, &t, sizeof t) == 0);
	mbr[511] = 0;
	CHECK(mbr_decode(mbr, &back) == -1);
}

int main(void)
{
	test_geometry_matches_build_uefi_image();
	test_chs_matches_build_uefi_image();
	test_auto_2gb();
	test_auto_rounds_down_to_a_whole_cylinder();
	test_auto_refuses_under_1gb();
	test_auto_ignores_an_existing_table();
	test_check_rules();
	test_mbr_roundtrip();
	printf("layout: %d failures\n", failures);
	return failures != 0;
}
