/*  Behavioural tests for the zone and page functions in NSZone.m, stage 2a
    of the Foundation reconstruction.  These are ordinary C over plain
    memory and need no Objective-C runtime.  */

#import <Foundation/NSZone.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_page_size_is_a_power_of_two(void)
{
    unsigned size = NSPageSize();

    CHECK(size > 0);
    CHECK((size & (size - 1)) == 0);
    CHECK((1U << NSLogPageSize()) == size);
}

static void test_rounding_to_page_size(void)
{
    unsigned page = NSPageSize();

    CHECK(NSRoundUpToMultipleOfPageSize(0) == 0);
    CHECK(NSRoundUpToMultipleOfPageSize(1) == page);
    CHECK(NSRoundUpToMultipleOfPageSize(page) == page);
    CHECK(NSRoundUpToMultipleOfPageSize(page + 1) == 2 * page);

    CHECK(NSRoundDownToMultipleOfPageSize(0) == 0);
    CHECK(NSRoundDownToMultipleOfPageSize(page - 1) == 0);
    CHECK(NSRoundDownToMultipleOfPageSize(page) == page);
    CHECK(NSRoundDownToMultipleOfPageSize(page + 1) == page);
}

static void test_default_zone_exists(void)
{
    CHECK(NSDefaultMallocZone() != 0);
}

static void test_malloc_from_the_default_zone(void)
{
    NSZone *zone = NSDefaultMallocZone();
    char *block = (char *)NSZoneMalloc(zone, 64);

    CHECK(block != 0);
    memset(block, 0x5A, 64);
    CHECK(block[0] == 0x5A && block[63] == 0x5A);
    NSZoneFree(zone, block);
}

static void test_calloc_zeroes(void)
{
    NSZone *zone = NSDefaultMallocZone();
    unsigned char *block = (unsigned char *)NSZoneCalloc(zone, 16, 4);
    int i, nonzero;

    CHECK(block != 0);
    nonzero = 0;
    for (i = 0; i < 64; i++)
        if (block[i] != 0)
            nonzero++;
    CHECK(nonzero == 0);
    NSZoneFree(zone, block);
}

static void test_realloc_preserves_contents(void)
{
    NSZone *zone = NSDefaultMallocZone();
    char *block = (char *)NSZoneMalloc(zone, 16);

    strcpy(block, "preserved");
    block = (char *)NSZoneRealloc(zone, block, 128);
    CHECK(block != 0);
    CHECK(strcmp(block, "preserved") == 0);
    NSZoneFree(zone, block);
}

static void test_created_zone_round_trip(void)
{
    NSZone *zone = NSCreateZone(NSPageSize(), NSPageSize(), 1);
    void *block;

    CHECK(zone != 0);
    block = NSZoneMalloc(zone, 32);
    CHECK(block != 0);
    NSZoneFree(zone, block);
    NSRecycleZone(zone);
}

static void test_zone_from_pointer_finds_the_owning_zone(void)
{
    NSZone *zone = NSDefaultMallocZone();
    void *block = NSZoneMalloc(zone, 32);

    CHECK(NSZoneFromPointer(block) == zone);
    NSZoneFree(zone, block);
}

static void test_memory_pages_round_trip(void)
{
    unsigned page = NSPageSize();
    void *pages = NSAllocateMemoryPages(page * 2);
    void *copy;

    CHECK(pages != 0);
    memset(pages, 0x33, page * 2);

    copy = NSAllocateMemoryPages(page * 2);
    CHECK(copy != 0);
    NSCopyMemoryPages(pages, copy, page * 2);
    CHECK(((unsigned char *)copy)[0] == 0x33);
    CHECK(((unsigned char *)copy)[page * 2 - 1] == 0x33);

    NSDeallocateMemoryPages(pages, page * 2);
    NSDeallocateMemoryPages(copy, page * 2);
}

static void test_real_memory_available_is_plausible(void)
{
    CHECK(NSRealMemoryAvailable() > 0);
}

int main(void)
{
    test_page_size_is_a_power_of_two();
    test_rounding_to_page_size();
    test_default_zone_exists();
    test_malloc_from_the_default_zone();
    test_calloc_zeroes();
    test_realloc_preserves_contents();
    test_created_zone_round_trip();
    test_zone_from_pointer_finds_the_owning_zone();
    test_memory_pages_round_trip();
    test_real_memory_available_is_plausible();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
