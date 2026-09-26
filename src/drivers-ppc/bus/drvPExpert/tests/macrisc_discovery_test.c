#include <stdio.h>
#include <string.h>

#include "../powermac/macrisc_discovery.h"

static int failures;

#define CHECK(x) do { \
    if (!(x)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); \
        failures++; \
    } \
} while (0)

static PEProperty
prop(const unsigned char *p, unsigned int n)
{
    PEProperty value;

    value.bytes = p;
    value.size = n;
    return value;
}

static void
test_strings(void)
{
    /* Real MacRISC2/3 roots list the plain "MacRISC" member as well. */
    static const unsigned char list[] =
        "PowerBook3,4\0MacRISC2\0MacRISC\0Power Macintosh\0";
    static const unsigned char bad[] = { 'M', 'a', 'c' };
    static const unsigned char tail[] = { 'A', 0, 'B' };

    CHECK(PEPropertyHasString(prop(list, sizeof(list)), "MacRISC2"));
    CHECK(PEPropertyHasString(prop(list, sizeof(list)), "MacRISC"));
    CHECK(PEPropertyHasString(prop(list, sizeof(list)), "Power Macintosh"));
    CHECK(!PEPropertyHasString(prop(list, sizeof(list)), "MacRIS"));
    CHECK(!PEPropertyHasString(prop(list, sizeof(list)), "Power"));
    CHECK(!PEPropertyHasString(prop(bad, sizeof(bad)), "Mac"));
    CHECK(PEPropertyHasString(prop(tail, sizeof(tail)), "A"));
    CHECK(!PEPropertyHasString(prop(tail, sizeof(tail)), "B"));
    CHECK(!PEPropertyHasString(prop(0, 0), "A"));
}

static void
test_cells(void)
{
    static const unsigned char one[] = { 0x80, 0, 0, 0 };
    static const unsigned char two[] = { 0, 0, 0, 0, 0x80, 0, 0, 0 };
    static const unsigned char high[] = { 0, 0, 0, 1, 0x80, 0, 0, 0 };
    static const unsigned char three[] = { 0, 0, 0, 0, 0, 0, 0, 0,
        0x80, 0, 0, 0 };
    unsigned int value;

    CHECK(PEReadCell32(prop(one, 4), 0, &value));
    CHECK(value == 0x80000000U);
    CHECK(PEReadCell32(prop(two, 8), 1, &value));
    CHECK(value == 0x80000000U);
    CHECK(!PEReadCell32(prop(two, 8), 2, &value));
    CHECK(!PEReadCell32(prop(two, 8), 0x40000000U, &value));
    CHECK(!PEReadCell32(prop(one, 3), 0, &value));
    CHECK(!PEReadCell32(prop(one, 4), 0, 0));
    CHECK(!PEReadCell32(prop(0, 4), 0, &value));

    CHECK(PEReadAddress32(prop(one, 4), 1, &value));
    CHECK(value == 0x80000000U);
    CHECK(PEReadAddress32(prop(two, 8), 2, &value));
    CHECK(value == 0x80000000U);
    CHECK(!PEReadAddress32(prop(two, 8), 1, &value));
    CHECK(!PEReadAddress32(prop(one, 4), 2, &value));
    value = 7;
    CHECK(!PEReadAddress32(prop(high, 8), 2, &value));
    CHECK(value == 7);
    CHECK(!PEReadAddress32(prop(three, 12), 3, &value));
    CHECK(!PEReadAddress32(prop(one, 4), 0, &value));
    CHECK(!PEReadAddress32(prop(one, 4), 1, 0));
}

int
main(void)
{
    test_strings();
    test_cells();
    if (failures)
        return 1;
    printf("MacRISC discovery tests passed\n");
    return 0;
}
