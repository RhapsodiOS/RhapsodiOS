#include <stdio.h>
#include <string.h>

#include "../powermac/chips/keylargo_discovery.h"
#include "../powermac/chips/keylargo_model.h"

static int failures;

#define CHECK(expr) do { \
    if (!(expr)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); \
        failures++; \
    } \
} while (0)

static void
put_cell(unsigned char cell[4], unsigned int value)
{
    cell[0] = (unsigned char)(value >> 24);
    cell[1] = (unsigned char)(value >> 16);
    cell[2] = (unsigned char)(value >> 8);
    cell[3] = (unsigned char)value;
}

static PEKeyLargoProperty
property(const unsigned char *bytes, unsigned int size)
{
    PEKeyLargoProperty result;

    result.bytes = bytes;
    result.size = size;
    return result;
}

static void
test_relative_and_absolute_i2c(void)
{
    unsigned char reg[4], absolute[4], step[4], rate[4];
    PEKeyLargoDiscoveryInput input;
    PEKeyLargoDiscovery result;

    put_cell(reg, 0x18000);
    put_cell(absolute, 0x80018000);
    put_cell(step, 0x10);
    put_cell(rate, 100);
    memset(&input, 0, sizeof(input));
    input.macIOBase = 0x80000000;
    input.macIOSize = 0x80000;
    input.reg = property(reg, sizeof(reg));
    input.addressStep = property(step, sizeof(step));
    input.rate = property(rate, sizeof(rate));
    CHECK(PEKeyLargoParseDiscovery(&input, &result));
    CHECK(result.i2cOffset == 0x18000);
    CHECK(result.addressStep == 0x10);
    CHECK(result.rate == 100);
    CHECK(result.speed == 0);

    input.reg = property(0, 0);
    input.absoluteAddress = property(absolute, sizeof(absolute));
    CHECK(PEKeyLargoParseDiscovery(&input, &result));
    CHECK(result.i2cOffset == 0x18000);
}

static void
test_supported_i2c_rates(void)
{
    unsigned char reg[4], step[4], rate[4];
    PEKeyLargoDiscoveryInput input;
    PEKeyLargoDiscovery result;
    static const unsigned int rates[] = { 100, 50, 25 };
    static const unsigned int speeds[] = { 0, 1, 2 };
    unsigned int index;

    put_cell(reg, 0x18000);
    put_cell(step, 0x10);
    memset(&input, 0, sizeof(input));
    input.macIOBase = 0x80000000;
    input.macIOSize = 0x80000;
    input.reg = property(reg, sizeof(reg));
    input.addressStep = property(step, sizeof(step));
    input.rate = property(rate, sizeof(rate));
    for (index = 0; index < sizeof(rates) / sizeof(rates[0]); index++) {
        put_cell(rate, rates[index]);
        CHECK(PEKeyLargoParseDiscovery(&input, &result));
        CHECK(result.rate == rates[index]);
        CHECK(result.speed == speeds[index]);
    }
    put_cell(rate, 75);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    put_cell(rate, 400);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
}

static void
test_exact_sizes_and_ranges(void)
{
    unsigned char reg[8], absolute[4], step[4], rate[4];
    PEKeyLargoDiscoveryInput input;
    PEKeyLargoDiscovery result;
    PEKeyLargoProperty *items[3];
    unsigned int index;

    put_cell(reg, 0x18000);
    put_cell(step, 0x10);
    put_cell(rate, 100);
    memset(&input, 0, sizeof(input));
    input.macIOBase = 0x80000000;
    input.macIOSize = 0x80000;
    input.reg = property(reg, 4);
    input.addressStep = property(step, 4);
    input.rate = property(rate, 4);
    items[0] = &input.reg;
    items[1] = &input.addressStep;
    items[2] = &input.rate;
    for (index = 0; index < 3; index++) {
        unsigned int saved = items[index]->size;
        items[index]->size = 3;
        CHECK(!PEKeyLargoParseDiscovery(&input, &result));
        items[index]->size = saved;
    }
    input.reg.size = sizeof(reg);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    input.reg.size = 4;
    put_cell(reg, 0x7fff1);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    put_cell(reg, 0xffffffffU);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    put_cell(reg, 0x18000);
    put_cell(step, 0xffffffffU);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    put_cell(step, 0);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    put_cell(step, 0x10);
    put_cell(rate, 0);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));

    put_cell(rate, 100);
    put_cell(absolute, 0x7fffffff);
    input.reg = property(0, 0);
    input.absoluteAddress = property(absolute, 4);
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
    input.absoluteAddress.size = 3;
    CHECK(!PEKeyLargoParseDiscovery(&input, &result));
}

static void
test_mac_io_size_properties(void)
{
    unsigned char address[4], assigned[20], reg[8];
    unsigned int base, size;

    memset(assigned, 0, sizeof(assigned));
    put_cell(address, 0x80000000);
    put_cell(assigned + 8, 0x80000000);
    put_cell(assigned + 16, 0x80000);
    CHECK(PEKeyLargoParseMacIO(property(address, 4),
        property(assigned, 20), property(0, 0), &base, &size));
    CHECK(base == 0x80000000 && size == 0x80000);
    put_cell(reg, 0x80000000);
    put_cell(reg + 4, 0x100000);
    CHECK(PEKeyLargoParseMacIO(property(0, 0), property(0, 0),
        property(reg, 8), &base, &size));
    CHECK(base == 0x80000000 && size == 0x100000);
    CHECK(!PEKeyLargoParseMacIO(property(address, 3),
        property(assigned, 20), property(0, 0), &base, &size));
    CHECK(!PEKeyLargoParseMacIO(property(address, 4),
        property(assigned, 19), property(0, 0), &base, &size));
    put_cell(assigned + 12, 1);
    CHECK(!PEKeyLargoParseMacIO(property(address, 4),
        property(assigned, 20), property(0, 0), &base, &size));
}

static void
test_legacy_mac_io_fallback_model(void)
{
    CHECK(PEKeyLargoUsesLegacyMacIOSpan("PowerMac3,1"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerMac3,2"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerMac3,3"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerMac5,1"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerBook2,1"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerMac4,1"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerMac7,2"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan("PowerMac3,10"));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan(""));
    CHECK(!PEKeyLargoUsesLegacyMacIOSpan(0));
}

int
main(void)
{
    test_relative_and_absolute_i2c();
    test_supported_i2c_rates();
    test_exact_sizes_and_ranges();
    test_mac_io_size_properties();
    test_legacy_mac_io_fallback_model();
    if (failures != 0)
        return 1;
    printf("KeyLargo discovery tests passed\n");
    return 0;
}
