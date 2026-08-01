#include <stdio.h>
#include <stdlib.h>

#include "ata_hd_root.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                        \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void check_valid(const char *name, unsigned int expectedUnit,
                        unsigned int expectedPartition)
{
    unsigned int unit;
    unsigned int partition;

    unit = 99;
    partition = 99;
    CHECK(ATAHDParseRoot(name, &unit, &partition) == 0);
    CHECK(unit == expectedUnit);
    CHECK(partition == expectedPartition);
}

static void check_invalid(const char *name)
{
    unsigned int unit;
    unsigned int partition;

    unit = 99;
    partition = 99;
    CHECK(ATAHDParseRoot(name, &unit, &partition) != 0);
    CHECK(unit == 99);
    CHECK(partition == 99);
}

static void test_valid_roots(void)
{
    check_valid("hd0a", 0, 0);
    check_valid("hd9h", 9, 7);
    check_valid("hd10a", 10, 0);
    check_valid("hd31h", 31, 7);
    check_valid("hd0", 0, 0);
    check_valid("hd31", 31, 0);
}

static void test_invalid_roots(void)
{
    check_invalid("hd32a");
    check_invalid("hd-1a");
    check_invalid("hd100a");
    check_invalid("hd00a");
    check_invalid("hd01a");
    check_invalid("hd000a");
    check_invalid("hd0i");
    check_invalid("hd0A");
    check_invalid("hd0aa");
    check_invalid("hd0a ");
    check_invalid("HD0a");
    check_invalid("hd");
    check_invalid(NULL);
}

static void test_invalid_outputs(void)
{
    unsigned int value;

    value = 99;
    CHECK(ATAHDParseRoot("hd0a", NULL, &value) != 0);
    CHECK(value == 99);
    CHECK(ATAHDParseRoot("hd0a", &value, NULL) != 0);
}

int main(void)
{
    test_valid_roots();
    test_invalid_roots();
    test_invalid_outputs();

    if (failures != 0) {
        fprintf(stderr, "ata_hd_root_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ata_hd_root_test: all tests passed\n");
    return EXIT_SUCCESS;
}
