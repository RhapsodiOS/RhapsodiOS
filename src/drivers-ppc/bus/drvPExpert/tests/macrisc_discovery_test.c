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

static unsigned int
append(unsigned char *buffer, unsigned int used, const char *string)
{
    unsigned int length;

    length = (unsigned int)strlen(string) + 1;
    memcpy(buffer + used, string, length);
    return used + length;
}

static void
put_cell(unsigned char cell[4], unsigned int value)
{
    cell[0] = (unsigned char)(value >> 24);
    cell[1] = (unsigned char)(value >> 16);
    cell[2] = (unsigned char)(value >> 8);
    cell[3] = (unsigned char)value;
}

typedef struct {
    unsigned char root[160];
    unsigned char host[32];
    unsigned char macIO[32];
    unsigned char deviceID[4];
    PEMacRISCIdentityInput input;
} IdentityFixture;

static void
identity(IdentityFixture *f, const char *model, const char *generation,
    unsigned int pvr, const char *host, const char *macIO,
    unsigned int deviceID)
{
    unsigned int used;

    used = append(f->root, 0, model);
    used = append(f->root, used, generation);
    used = append(f->root, used, "MacRISC");
    used = append(f->root, used, "Power Macintosh");
    f->input.model = prop(f->root, used);
    f->input.rootCompatible = prop(f->root, used);
    f->input.hostCompatible = prop(f->host, append(f->host, 0, host));
    f->input.macIOCompatible = prop(f->macIO, append(f->macIO, 0, macIO));
    put_cell(f->deviceID, deviceID);
    f->input.macIODeviceID = prop(f->deviceID, 4);
    f->input.pvr = pvr;
}

typedef struct {
    const char *model;
    const char *generation;
    unsigned int pvr;
    const char *host;
    const char *macIO;
    unsigned int deviceID;
    PEMacRISCStatus expected;
} ModelCase;

static void
test_classify_rows(void)
{
    static const ModelCase cases[] = {
        { "PowerMac2,2", "MacRISC2", 0x00080000U, "uni-north", "Keylargo",
            0x22, kPEMacRISCSupported },
        { "PowerMac4,2", "MacRISC2", 0x80010000U, "uni-north", "Keylargo",
            0x25, kPEMacRISCSupported },
        { "PowerMac6,3", "MacRISC3", 0x80020000U, "uni-north", "Keylargo",
            0x3e, kPEMacRISCSupported },
        { "PowerBook4,3", "MacRISC2", 0x70000000U, "uni-north", "Keylargo",
            0x25, kPEMacRISCSupported },
        { "PowerBook3,4", "MacRISC2", 0x80010000U, "uni-north", "Keylargo",
            0x22, kPEMacRISCSupported },
        { "PowerMac10,1", "MacRISC3", 0x80030000U, "uni-north", "Keylargo",
            0x3e, kPEMacRISCSupported },
        { "RackMac1,1", "MacRISC2", 0x80010000U, "uni-north", "Keylargo",
            0x22, kPEMacRISCSupported },
        { "PowerMac7,2", "MacRISC4", 0x00390000U, "u3", "K2-Keylargo",
            0x41, kPEMacRISCUnsupportedCPU },
        { "PowerMac3,9", "MacRISC2", 0x80010000U, "bandit", "Keylargo",
            0x22, kPEMacRISCUnsupportedHost },
        { "PowerBook9,8", "MacRISC2", 0x80010000U, "uni-north", "Keylargo",
            0x41, kPEMacRISCUnsupportedMacIO },
        { "Unknown1,1", "MacRISC2", 0x80010000U, "uni-north", "Keylargo",
            0x22, kPEMacRISCNotMatched }
    };
    IdentityFixture f;
    PECPUFamily cpu;
    PEMacIOFamily macIO;
    char model[PE_MACRISC_MODEL_MAX];
    unsigned int i;

    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        identity(&f, cases[i].model, cases[i].generation, cases[i].pvr,
            cases[i].host, cases[i].macIO, cases[i].deviceID);
        if (PEMacRISCClassify(&f.input, &cpu, &macIO, model) !=
            cases[i].expected) {
            printf("FAIL classify row %s\n", cases[i].model);
            failures++;
        }
        CHECK(strcmp(model, cases[i].model) == 0);
    }
}

static void
test_classify_details(void)
{
    static const unsigned char unterminated[] = { 'P', 'o', 'w' };
    IdentityFixture f;
    PECPUFamily cpu;
    PEMacIOFamily macIO;
    char model[PE_MACRISC_MODEL_MAX];
    unsigned char longModel[80];

    identity(&f, "PowerBook9,9", "MacRISC2", 0x80020000U, "uni-north",
        "Keylargo", 0x3e);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCCompatibleUnlisted);
    CHECK(cpu == kPECPU745x);
    CHECK(macIO == kPEMacIOIntrepid);

    identity(&f, "PowerBook6,7", "MacRISC4", 0x80020000U, "uni-north",
        "Keylargo", 0x3e);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCNotMatched);

    identity(&f, "PowerMac4,4", "MacRISC2", 0x800c0000U, "uni-north",
        "Pangea", 0x25);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCCompatibleUnlisted);
    CHECK(cpu == kPECPU7410);
    CHECK(macIO == kPEMacIOPangea);

    identity(&f, "PowerMac2,2", "MacRISC2", 0x00080000U, "uni-north",
        "Keylargo", 0x22);
    f.input.macIODeviceID = prop(f.deviceID, 3);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCMalformed);
    f.input.macIODeviceID = prop(0, 0);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCMalformed);

    identity(&f, "PowerMac2,2", "MacRISC2", 0x00040000U, "uni-north",
        "Keylargo", 0x22);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCUnsupportedCPU);
    CHECK(cpu == kPECPUUnknown);

    identity(&f, "PowerMacG4", "MacRISC2", 0x80010000U, "uni-north",
        "Keylargo", 0x22);
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCNotMatched);

    identity(&f, "PowerMac2,2", "MacRISC2", 0x00080000U, "uni-north",
        "Keylargo", 0x22);
    f.input.model = prop(unterminated, sizeof(unterminated));
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCMalformed);
    CHECK(model[0] == 0);
    memset(longModel, 'A', sizeof(longModel));
    longModel[sizeof(longModel) - 1] = 0;
    f.input.model = prop(longModel, sizeof(longModel));
    CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
        kPEMacRISCMalformed);
    CHECK(PEMacRISCClassify(0, &cpu, &macIO, model) == kPEMacRISCMalformed);
}

int
main(void)
{
    test_strings();
    test_cells();
    test_classify_rows();
    test_classify_details();
    if (failures)
        return 1;
    printf("MacRISC discovery tests passed\n");
    return 0;
}
