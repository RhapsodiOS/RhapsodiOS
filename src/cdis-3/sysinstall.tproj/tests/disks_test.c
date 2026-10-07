#include <stdio.h>
#include <string.h>
#include "disks.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
	printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } \
	} while (0)

static void test_dev_disk_name(void)
{
	char name[8];

	CHECK(dev_disk_name(3, 8, name) == 0 && strcmp(name, "hd1") == 0);
	CHECK(dev_disk_name(3, 0, name) == 0 && strcmp(name, "hd0") == 0);
	CHECK(dev_disk_name(6, 17, name) == 0 && strcmp(name, "sd2") == 0);
	CHECK(dev_disk_name(3, 15, name) == 0 && strcmp(name, "hd1") == 0);
	CHECK(dev_disk_name(1, 0, name) == -1);	/* the floppy */
	CHECK(dev_disk_name(0, 0, name) == -1);
}

static void test_disk_controllers(void)
{
	const char *out[2];

	/* EIDE and AHCI both name their disks hdN, so tick both */
	CHECK(disk_controllers("hd0", 1, NULL, out) == 2 &&
	      strcmp(out[0], "EIDE") == 0 && strcmp(out[1], "AHCI") == 0);
	CHECK(disk_controllers("hd1", 0, "Adaptec2940", out) == 1 &&
	      strcmp(out[0], "EIDE") == 0);
	CHECK(disk_controllers("sd0", 1, "Adaptec2940", out) == 1 &&
	      strcmp(out[0], "Adaptec2940") == 0);
	CHECK(disk_controllers("sd0", 0, NULL, out) == 0);
}

int main(void)
{
	test_dev_disk_name();
	test_disk_controllers();
	printf("disks: %d failures\n", failures);
	return failures != 0;
}
