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

int main(void)
{
	test_dev_disk_name();
	printf("disks: %d failures\n", failures);
	return failures != 0;
}
