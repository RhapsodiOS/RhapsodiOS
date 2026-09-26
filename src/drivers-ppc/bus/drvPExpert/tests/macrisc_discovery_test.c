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

typedef struct {
    const char *model;
    unsigned int pvr;
    unsigned int deviceID;
} CatalogCase;

/* Later G3/G4 machines, each with a CPU and Mac-IO its generation ships. */
static const CatalogCase knownLaterModels[] = {
    { "PowerMac2,2", 0x00080000U, 0x22 }, { "PowerMac4,1", 0x00080000U, 0x25 },
    { "PowerMac3,4", 0x800c0000U, 0x22 }, { "PowerMac3,5", 0x80000000U, 0x22 },
    { "PowerMac3,6", 0x80010000U, 0x22 }, { "PowerMac4,2", 0x80000000U, 0x25 },
    { "PowerMac4,4", 0x80010000U, 0x25 }, { "PowerMac4,5", 0x80010000U, 0x25 },
    { "PowerMac6,1", 0x80020000U, 0x3e }, { "PowerMac6,3", 0x80020000U, 0x3e },
    { "PowerMac6,4", 0x80020000U, 0x3e }, { "PowerMac10,1", 0x80030000U, 0x3e },
    { "PowerMac10,2", 0x80030000U, 0x3e }, { "PowerBook2,2", 0x00080000U, 0x22 },
    { "PowerBook3,1", 0x00080000U, 0x22 }, { "PowerBook3,2", 0x800c0000U, 0x22 },
    { "PowerBook3,3", 0x800c0000U, 0x22 }, { "PowerBook3,4", 0x80010000U, 0x22 },
    { "PowerBook3,5", 0x80010000U, 0x22 }, { "PowerBook4,1", 0x00080000U, 0x25 },
    { "PowerBook4,2", 0x00080000U, 0x25 }, { "PowerBook4,3", 0x70000000U, 0x25 },
    { "PowerBook5,1", 0x80010000U, 0x3e }, { "PowerBook5,2", 0x80010000U, 0x3e },
    { "PowerBook5,3", 0x80020000U, 0x3e }, { "PowerBook5,4", 0x80020000U, 0x3e },
    { "PowerBook5,5", 0x80020000U, 0x3e }, { "PowerBook5,6", 0x80030000U, 0x3e },
    { "PowerBook5,7", 0x80030000U, 0x3e }, { "PowerBook5,8", 0x80030000U, 0x3e },
    { "PowerBook5,9", 0x80030000U, 0x3e }, { "PowerBook6,1", 0x80010000U, 0x3e },
    { "PowerBook6,2", 0x80010000U, 0x3e }, { "PowerBook6,3", 0x80010000U, 0x3e },
    { "PowerBook6,4", 0x80020000U, 0x3e }, { "PowerBook6,5", 0x80020000U, 0x3e },
    { "PowerBook6,7", 0x80030000U, 0x3e }, { "PowerBook6,8", 0x80030000U, 0x3e },
    { "RackMac1,1", 0x80010000U, 0x22 }, { "RackMac1,2", 0x80010000U, 0x22 }
};

/* G5 machines: rejected by CPU and host checks, never by name. */
static const char *const g5Models[] = {
    "PowerMac7,2", "PowerMac7,3", "PowerMac8,1", "PowerMac8,2",
    "PowerMac9,1", "PowerMac11,2", "RackMac3,1"
};

static void
test_catalog(void)
{
    IdentityFixture f;
    PECPUFamily cpu;
    PEMacIOFamily macIO;
    char model[PE_MACRISC_MODEL_MAX];
    unsigned int i;

    for (i = 0; i < sizeof(knownLaterModels) / sizeof(knownLaterModels[0]);
        i++) {
        identity(&f, knownLaterModels[i].model, "MacRISC2",
            knownLaterModels[i].pvr, "uni-north", "Keylargo",
            knownLaterModels[i].deviceID);
        if (PEMacRISCClassify(&f.input, &cpu, &macIO, model) !=
            kPEMacRISCSupported) {
            printf("FAIL catalog %s\n", knownLaterModels[i].model);
            failures++;
        }
    }
    for (i = 0; i < sizeof(g5Models) / sizeof(g5Models[0]); i++) {
        identity(&f, g5Models[i], "MacRISC4", 0x003c0000U, "u3-ht",
            "K2-Keylargo", 0x41);
        CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
            kPEMacRISCUnsupportedCPU);
        /* A G4 on U3 still fails on the host bridge. */
        f.input.pvr = 0x80020000U;
        CHECK(PEMacRISCClassify(&f.input, &cpu, &macIO, model) ==
            kPEMacRISCUnsupportedHost);
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

    identity(&f, "PowerMac4,9", "MacRISC2", 0x800c0000U, "uni-north",
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

/* A complete, valid descriptor for one KeyLargo-family Mac-IO. */
static void
platform_fixture(PEMacRISCPlatform *p, PEMacIOFamily family)
{
    PEMacRISCPlatformInit(p);
    strcpy(p->model, "RackMac1,1");
    p->cpuFamily = kPECPU745x;
    p->macIOFamily = family;
    p->cpuCount = 2;
    p->bootCPU = 0;
    p->pvr = 0x80010201U;
    p->cpuClockHz = 1000000000U;
    p->busClockHz = 133333333U;
    p->timebaseHz = 33333333U;
    CHECK(PEMacRISCSetResource(&p->macIO, 0x80000000U, 0x80000U));
    CHECK(PEMacRISCSetResource(&p->mpic, 0x80040000U, 0x40000U));
    CHECK(PEMacRISCSetResource(&p->via, 0x80016000U, 0x2000U));
    CHECK(PEMacRISCSetResource(&p->serial, 0x80012000U, 0x1000U));
    CHECK(PEMacRISCSetResource(&p->nvram, 0xfff80000U, 0x20000U));
    CHECK(PEMacRISCSetResource(&p->mesh, 0x80010000U, 0x1000U));
    CHECK(PEMacRISCSetResource(&p->floppy, 0x80015000U, 0x1000U));
    CHECK(PEMacRISCSetResource(&p->audio, 0x80011000U, 0x1000U));
    CHECK(PEMacRISCSetResource(&p->ethernet, 0x80014000U, 0x1000U));
    CHECK(PEMacRISCSetResource(&p->ata0, 0x8001f000U, 0x1000U));
    CHECK(PEMacRISCSetResource(&p->ata1, 0x80020000U, 0x1000U));
    p->mpicSources = 64;
    p->hasPMU = 1;
    p->hasCascade = 1;
    p->cascadeSource = 25;
    p->cascadeWidth = 7;
    p->hasPMUInterrupt = 1;
    p->pmuInterruptSource = 47;
}

static void
test_descriptor(void)
{
    static const PEMacIOFamily families[] = {
        kPEMacIOKeyLargo, kPEMacIOPangea, kPEMacIOIntrepid
    };
    PEMacRISCPlatform p;
    unsigned int i;

    for (i = 0; i < sizeof(families) / sizeof(families[0]); i++) {
        platform_fixture(&p, families[i]);
        CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
        CHECK(p.macIO.base == 0x80000000U && p.macIO.length == 0x80000U);
        CHECK(p.mpic.base == 0x80040000U && p.mpicSources == 64);
        CHECK(p.cpuCount == 2 && p.bootCPU == 0);
        CHECK(p.dbdma.curio == -1 && p.dbdma.ata1 == -1);
    }

    platform_fixture(&p, kPEMacIOKeyLargo);
    p.mesh.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.floppy.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.audio.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.ethernet.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.ata1.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.hasPMUInterrupt = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformValid);
}

static void
test_descriptor_failures(void)
{
    PEMacRISCPlatform p;

    CHECK(PEMacRISCValidate(0) == kPEPlatformMissingMacIO);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.macIO.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingMacIO);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.macIO.length = 0x80000001U;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadMacIORange);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.mpic.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingMPIC);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.mpic.base = 0xf4000000U;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadMPICRange);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.mpicSources = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadMPICCount);
    p.mpicSources = 65;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadMPICCount);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.cpuCount = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingCPU);
    p.cpuCount = 5;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadCPUCount);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.cpuClockHz = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadClock);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.busClockHz = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadClock);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.timebaseHz = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadClock);
    p.timebaseHz = 0x80000000U;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadClock);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.via.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingVIA);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.hasPMU = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingVIA);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.cascadeWidth = 8;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadCascade);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.cascadeSource = 64;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadCascade);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.hasCascade = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadCascade);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.pmuInterruptSource = 25;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadCascade);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.serial.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingSerial);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.nvram.present = 0;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingNVRAM);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.nvram.base = 0xffffe000U;
    p.nvram.length = 0x2000;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformMissingNVRAM);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.ata0.base = 0x8007f800U;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadRange);
    platform_fixture(&p, kPEMacIOKeyLargo);
    p.dbdma.mesh = 32;
    CHECK(PEMacRISCValidate(&p) == kPEPlatformBadRange);
}

static void
test_setters(void)
{
    PEResource resource;
    PEDBDMAChannels channels;
    PEMacRISCPlatform p;

    resource.present = 0;
    CHECK(!PEMacRISCSetResource(&resource, 0x80000000U, 0));
    CHECK(!PEMacRISCSetResource(&resource, 0xfffff000U, 0x2000U));
    CHECK(!resource.present);
    CHECK(PEMacRISCSetResource(&resource, 0xfffff000U, 0x1000U));
    CHECK(resource.present && resource.base == 0xfffff000U);
    CHECK(!PEMacRISCSetResource(0, 0, 1));

    PEMacRISCPlatformInit(&p);
    channels = p.dbdma;
    CHECK(PEMacRISCSetDBDMA(&channels, "ata0", 11));
    CHECK(channels.ata0 == 11);
    CHECK(PEMacRISCSetDBDMA(&channels, "ata0", 11));
    CHECK(!PEMacRISCSetDBDMA(&channels, "ata0", 10));
    CHECK(channels.ata0 == 11);
    CHECK(!PEMacRISCSetDBDMA(&channels, "scc-a-tx", 32));
    CHECK(channels.sccATx == -1);
    CHECK(!PEMacRISCSetDBDMA(&channels, "modem", 3));
    CHECK(PEMacRISCSetDBDMA(&channels, "audio-in", 9));
    CHECK(channels.audioIn == 9 && channels.audioOut == -1);
}

int
main(void)
{
    test_strings();
    test_cells();
    test_classify_rows();
    test_classify_details();
    test_catalog();
    test_descriptor();
    test_descriptor_failures();
    test_setters();
    if (failures)
        return 1;
    printf("MacRISC discovery tests passed\n");
    return 0;
}
