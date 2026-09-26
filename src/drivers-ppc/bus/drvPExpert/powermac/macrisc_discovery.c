#include "macrisc_discovery.h"

static unsigned int
macrisc_cell(const unsigned char *bytes)
{
    return ((unsigned int)bytes[0] << 24) |
        ((unsigned int)bytes[1] << 16) |
        ((unsigned int)bytes[2] << 8) | (unsigned int)bytes[3];
}

/*
 * Match one member of a NUL-separated string list.  Every member must end
 * inside the property; the scan stops at the first unterminated member.
 */
int
PEPropertyHasString(PEProperty property, const char *expected)
{
    unsigned int start;
    unsigned int end;
    unsigned int i;

    if (property.bytes == 0 || expected == 0)
        return 0;
    for (start = 0; start < property.size; start = end + 1) {
        for (end = start; end < property.size &&
            property.bytes[end] != 0; end++)
            ;
        if (end == property.size)
            return 0;
        for (i = 0; start + i < end && expected[i] != 0 &&
            property.bytes[start + i] == (unsigned char)expected[i]; i++)
            ;
        if (start + i == end && expected[i] == 0)
            return 1;
    }
    return 0;
}

int
PEReadCell32(PEProperty property, unsigned int index, unsigned int *value)
{
    if (property.bytes == 0 || value == 0 || index >= property.size / 4)
        return 0;
    *value = macrisc_cell(property.bytes + index * 4);
    return 1;
}

/*
 * Read a property that holds exactly one address of one or two cells.  A
 * two-cell address is accepted only when its high cell is zero.
 */
int
PEReadAddress32(PEProperty property, unsigned int cells, unsigned int *value)
{
    unsigned int high;
    unsigned int low;

    if (value == 0 || (cells != 1 && cells != 2) ||
        property.size != cells * 4 ||
        !PEReadCell32(property, cells - 1, &low))
        return 0;
    if (cells == 2 && (!PEReadCell32(property, 0, &high) || high != 0))
        return 0;
    *value = low;
    return 1;
}

/*
 * Later G3/G4 machines by firmware identifier.  This labels the boot log;
 * acceptance comes from the capability checks, so an unlisted compatible
 * machine still boots.
 */
static const char *const macrisc_catalog[] = {
    "PowerMac2,2", "PowerMac3,4", "PowerMac3,5", "PowerMac3,6",
    "PowerMac4,1", "PowerMac4,2", "PowerMac4,4", "PowerMac4,5",
    "PowerMac6,1", "PowerMac6,3", "PowerMac6,4",
    "PowerMac10,1", "PowerMac10,2",
    "PowerBook2,2", "PowerBook3,1", "PowerBook3,2", "PowerBook3,3",
    "PowerBook3,4", "PowerBook3,5",
    "PowerBook4,1", "PowerBook4,2", "PowerBook4,3",
    "PowerBook5,1", "PowerBook5,2", "PowerBook5,3", "PowerBook5,4",
    "PowerBook5,5", "PowerBook5,6", "PowerBook5,7", "PowerBook5,8",
    "PowerBook5,9",
    "PowerBook6,1", "PowerBook6,2", "PowerBook6,3", "PowerBook6,4",
    "PowerBook6,5", "PowerBook6,7", "PowerBook6,8",
    "RackMac1,1", "RackMac1,2"
};

static int
macrisc_string_equal(const char *left, const char *right)
{
    while (*left != 0 && *left == *right) {
        left++;
        right++;
    }
    return *left == *right;
}

static int
macrisc_prefix(const char *string, const char *prefix)
{
    while (*prefix != 0 && *string == *prefix) {
        string++;
        prefix++;
    }
    return *prefix == 0;
}

static PECPUFamily
macrisc_cpu_family(unsigned int pvr)
{
    switch (pvr >> 16) {
    case 0x0008:            /* 750, 750CX/CXe/L */
    case 0x7000:            /* 750FX */
    case 0x7002:            /* 750GX */
        return kPECPU750;
    case 0x000c:
        return kPECPU7400;
    case 0x800c:
        return kPECPU7410;
    case 0x8000:            /* 7450 */
    case 0x8001:            /* 7455, 7445 */
    case 0x8002:            /* 7457, 7447 */
    case 0x8003:            /* 7447A */
    case 0x8004:            /* 7448 */
        return kPECPU745x;
    case 0x0039:            /* 970 */
    case 0x003c:            /* 970FX */
    case 0x0044:            /* 970MP */
        return kPECPU970;
    }
    return kPECPUUnknown;
}

/*
 * KeyLargo, Pangea and Intrepid usually all say "Keylargo"; the PCI
 * device-id is what tells them apart, so it is required.
 */
static PEMacIOFamily
macrisc_macio_family(PEProperty compatible, PEProperty deviceID,
    int *malformed)
{
    unsigned int id;

    *malformed = 0;
    if (!PEPropertyHasString(compatible, "Keylargo") &&
        !PEPropertyHasString(compatible, "Pangea") &&
        !PEPropertyHasString(compatible, "Intrepid") &&
        !PEPropertyHasString(compatible, "K2-Keylargo"))
        return kPEMacIOUnknown;
    if (!PEReadAddress32(deviceID, 1, &id)) {
        *malformed = 1;
        return kPEMacIOUnknown;
    }
    switch (id) {
    case 0x22:
        return kPEMacIOKeyLargo;
    case 0x25:
        return kPEMacIOPangea;
    case 0x3e:
        return kPEMacIOIntrepid;
    case 0x41:
        return kPEMacIOK2;
    }
    return kPEMacIOUnknown;
}

/* Copy the first member of a string list; it must fit with its NUL. */
static int
macrisc_copy_model(PEProperty property, char model[PE_MACRISC_MODEL_MAX])
{
    unsigned int i;

    model[0] = 0;
    if (property.bytes == 0)
        return 0;
    for (i = 0; i < property.size && i < PE_MACRISC_MODEL_MAX; i++) {
        model[i] = (char)property.bytes[i];
        if (model[i] == 0)
            return i != 0;
    }
    model[0] = 0;
    return 0;
}

static int
macrisc_model_series(const char *model)
{
    const char *digits;

    if (macrisc_prefix(model, "PowerMac"))
        digits = model + 8;
    else if (macrisc_prefix(model, "PowerBook"))
        digits = model + 9;
    else if (macrisc_prefix(model, "RackMac"))
        digits = model + 7;
    else
        return 0;
    return *digits >= '0' && *digits <= '9';
}

static int
macrisc_model_listed(const char *model)
{
    unsigned int i;

    for (i = 0; i < sizeof(macrisc_catalog) / sizeof(macrisc_catalog[0]);
        i++)
        if (macrisc_string_equal(model, macrisc_catalog[i]))
            return 1;
    return 0;
}

static const char *const macrisc_sawtooth_models[] = {
    "PowerMac3,1", "PowerMac3,2", "PowerMac3,3", "PowerMac5,1",
    "PowerBook2,1"
};

static const char *const macrisc_yosemite_models[] = {
    "iMac", "PowerMac1,1", "PowerMac1,2", "PowerMac2,1", "PowerBook1,1"
};

static int
macrisc_in_list(const char *model, const char *const *list,
    unsigned int count)
{
    unsigned int i;

    for (i = 0; i < count; i++)
        if (macrisc_string_equal(model, list[i]))
            return 1;
    return 0;
}

PEPlatformRoute
PEMacRISCSelectRoute(const char *model, PEMacRISCStatus status)
{
    if (model == 0)
        return kPERouteUnsupported;
    if (macrisc_in_list(model, macrisc_sawtooth_models,
        sizeof(macrisc_sawtooth_models) / sizeof(macrisc_sawtooth_models[0])))
        return kPERouteSawtooth;
    if (macrisc_prefix(model, "AAPL,") ||
        macrisc_in_list(model, macrisc_yosemite_models,
        sizeof(macrisc_yosemite_models) / sizeof(macrisc_yosemite_models[0])))
        return kPERouteLegacy;
    if (status == kPEMacRISCSupported ||
        status == kPEMacRISCCompatibleUnlisted)
        return kPERouteMacRISC;
    return kPERouteUnsupported;
}

int
PEMacRISCHostSupported(PEProperty hostCompatible)
{
    return PEPropertyHasString(hostCompatible, "uni-north");
}

PEMacRISCStatus
PEMacRISCClassify(const PEMacRISCIdentityInput *input, PECPUFamily *cpu,
    PEMacIOFamily *macIO, char model[PE_MACRISC_MODEL_MAX])
{
    int macIOMalformed;
    int modelValid;

    if (input == 0 || cpu == 0 || macIO == 0 || model == 0)
        return kPEMacRISCMalformed;
    modelValid = macrisc_copy_model(input->model, model);
    *cpu = macrisc_cpu_family(input->pvr);
    *macIO = macrisc_macio_family(input->macIOCompatible,
        input->macIODeviceID, &macIOMalformed);

    if (!modelValid)
        return kPEMacRISCMalformed;
    if (*cpu == kPECPUUnknown || *cpu == kPECPU970)
        return kPEMacRISCUnsupportedCPU;
    if (!PEMacRISCHostSupported(input->hostCompatible))
        return kPEMacRISCUnsupportedHost;
    if (PEPropertyHasString(input->rootCompatible, "MacRISC4") ||
        (!PEPropertyHasString(input->rootCompatible, "MacRISC") &&
        !PEPropertyHasString(input->rootCompatible, "MacRISC2") &&
        !PEPropertyHasString(input->rootCompatible, "MacRISC3")))
        return kPEMacRISCNotMatched;
    if (macIOMalformed)
        return kPEMacRISCMalformed;
    if (*macIO != kPEMacIOKeyLargo && *macIO != kPEMacIOPangea &&
        *macIO != kPEMacIOIntrepid)
        return kPEMacRISCUnsupportedMacIO;
    if (!macrisc_model_series(model))
        return kPEMacRISCNotMatched;
    return macrisc_model_listed(model) ? kPEMacRISCSupported :
        kPEMacRISCCompatibleUnlisted;
}

void
PEMacRISCPlatformInit(PEMacRISCPlatform *platform)
{
    unsigned char *bytes;
    unsigned int i;

    bytes = (unsigned char *)platform;
    for (i = 0; i < sizeof(*platform); i++)
        bytes[i] = 0;
    platform->dbdma.curio = -1;
    platform->dbdma.mesh = -1;
    platform->dbdma.floppy = -1;
    platform->dbdma.ethernetTx = -1;
    platform->dbdma.ethernetRx = -1;
    platform->dbdma.sccATx = -1;
    platform->dbdma.sccARx = -1;
    platform->dbdma.sccBTx = -1;
    platform->dbdma.sccBRx = -1;
    platform->dbdma.audioOut = -1;
    platform->dbdma.audioIn = -1;
    platform->dbdma.ata0 = -1;
    platform->dbdma.ata1 = -1;
    for (i = 0; i < PE_MACRISC_MAX_SOURCES; i++)
        platform->sourceSense[i] = PE_MACRISC_SENSE_UNKNOWN;
}

static int
macrisc_range_valid(unsigned int base, unsigned int length)
{
    return length != 0 && length - 1 <= ~0U - base;
}

int
PEMacRISCSetResource(PEResource *resource, unsigned int base,
    unsigned int length)
{
    if (resource == 0 || !macrisc_range_valid(base, length))
        return 0;
    resource->present = 1;
    resource->base = base;
    resource->length = length;
    return 1;
}

static int *
macrisc_dbdma_field(PEDBDMAChannels *channels, const char *role)
{
    if (macrisc_string_equal(role, "curio"))
        return &channels->curio;
    if (macrisc_string_equal(role, "mesh"))
        return &channels->mesh;
    if (macrisc_string_equal(role, "floppy"))
        return &channels->floppy;
    if (macrisc_string_equal(role, "ethernet-tx"))
        return &channels->ethernetTx;
    if (macrisc_string_equal(role, "ethernet-rx"))
        return &channels->ethernetRx;
    if (macrisc_string_equal(role, "scc-a-tx"))
        return &channels->sccATx;
    if (macrisc_string_equal(role, "scc-a-rx"))
        return &channels->sccARx;
    if (macrisc_string_equal(role, "scc-b-tx"))
        return &channels->sccBTx;
    if (macrisc_string_equal(role, "scc-b-rx"))
        return &channels->sccBRx;
    if (macrisc_string_equal(role, "audio-out"))
        return &channels->audioOut;
    if (macrisc_string_equal(role, "audio-in"))
        return &channels->audioIn;
    if (macrisc_string_equal(role, "ata0"))
        return &channels->ata0;
    if (macrisc_string_equal(role, "ata1"))
        return &channels->ata1;
    return 0;
}

int
PEMacRISCSetDBDMA(PEDBDMAChannels *channels, const char *role,
    unsigned int channel)
{
    int *field;

    if (channels == 0 || role == 0 || channel > 31)
        return 0;
    field = macrisc_dbdma_field(channels, role);
    if (field == 0 || (*field != -1 && *field != (int)channel))
        return 0;
    *field = (int)channel;
    return 1;
}

static int
macrisc_inside(const PEResource *outer, const PEResource *inner)
{
    return inner->base >= outer->base &&
        inner->length <= outer->length &&
        inner->base - outer->base <= outer->length - inner->length;
}

static int
macrisc_optional_valid(const PEMacRISCPlatform *platform,
    const PEResource *resource)
{
    return !resource->present ||
        (macrisc_range_valid(resource->base, resource->length) &&
        macrisc_inside(&platform->macIO, resource));
}

static int
macrisc_channel_valid(int channel)
{
    return channel >= -1 && channel <= 31;
}

static int
macrisc_dbdma_valid(const PEDBDMAChannels *c)
{
    return macrisc_channel_valid(c->curio) &&
        macrisc_channel_valid(c->mesh) &&
        macrisc_channel_valid(c->floppy) &&
        macrisc_channel_valid(c->ethernetTx) &&
        macrisc_channel_valid(c->ethernetRx) &&
        macrisc_channel_valid(c->sccATx) &&
        macrisc_channel_valid(c->sccARx) &&
        macrisc_channel_valid(c->sccBTx) &&
        macrisc_channel_valid(c->sccBRx) &&
        macrisc_channel_valid(c->audioOut) &&
        macrisc_channel_valid(c->audioIn) &&
        macrisc_channel_valid(c->ata0) &&
        macrisc_channel_valid(c->ata1);
}

static int
macrisc_required_valid(const PEMacRISCPlatform *platform,
    const PEResource *resource)
{
    return resource->present && macrisc_optional_valid(platform, resource);
}

PEPlatformError
PEMacRISCValidate(const PEMacRISCPlatform *platform)
{
    if (platform == 0 || !platform->macIO.present)
        return kPEPlatformMissingMacIO;
    if (!macrisc_range_valid(platform->macIO.base, platform->macIO.length))
        return kPEPlatformBadMacIORange;
    if (!platform->mpic.present)
        return kPEPlatformMissingMPIC;
    if (!macrisc_required_valid(platform, &platform->mpic))
        return kPEPlatformBadMPICRange;
    if (platform->mpicSources == 0 ||
        platform->mpicSources > PE_MACRISC_MAX_SOURCES)
        return kPEPlatformBadMPICCount;
    if (platform->cpuCount == 0)
        return kPEPlatformMissingCPU;
    if (platform->cpuCount > PE_MACRISC_MAX_CPUS)
        return kPEPlatformBadCPUCount;
    if (platform->cpuClockHz == 0 || platform->busClockHz < 1000000U ||
        platform->timebaseHz == 0 || platform->timebaseHz > 0x7fffffffU)
        return kPEPlatformBadClock;
    if (!macrisc_required_valid(platform, &platform->via) ||
        (!platform->hasPMU && !platform->hasCUDA))
        return kPEPlatformMissingVIA;
    if (!platform->hasCascade ||
        platform->cascadeSource >= platform->mpicSources ||
        platform->cascadeWidth == 0 ||
        platform->cascadeWidth > PE_MACRISC_MAX_CASCADE ||
        (platform->hasPMUInterrupt &&
        (platform->pmuInterruptSource >= platform->mpicSources ||
        platform->pmuInterruptSource == platform->cascadeSource)))
        return kPEPlatformBadCascade;
    if (!macrisc_required_valid(platform, &platform->serial))
        return kPEPlatformMissingSerial;
    /* The Core99 flash code reads two 8 KB banks from the NVRAM base. */
    if (!platform->nvram.present ||
        !macrisc_range_valid(platform->nvram.base, 0x4000))
        return kPEPlatformMissingNVRAM;
    if (!macrisc_optional_valid(platform, &platform->mesh) ||
        !macrisc_optional_valid(platform, &platform->floppy) ||
        !macrisc_optional_valid(platform, &platform->audio) ||
        !macrisc_optional_valid(platform, &platform->ethernet) ||
        !macrisc_optional_valid(platform, &platform->ata0) ||
        !macrisc_optional_valid(platform, &platform->ata1) ||
        !macrisc_dbdma_valid(&platform->dbdma))
        return kPEPlatformBadRange;
    return kPEPlatformValid;
}

static unsigned int
macrisc_base(const PEResource *resource)
{
    return resource->present ? resource->base : 0;
}

int
PEMacRISCPublish(const PEMacRISCPlatform *platform,
    PEMacRISCPublishedIO *published)
{
    if (published == 0 || PEMacRISCValidate(platform) != kPEPlatformValid)
        return 0;
    published->ioBase = platform->macIO.base;
    published->ioSize = platform->macIO.length;
    published->interruptBase = platform->mpic.base;
    /* KeyLargo-family DBDMA channel 0 sits at Mac-IO offset 0x8000. */
    published->dmaBase = platform->macIO.base + 0x8000U;
    published->viaBase = platform->via.base;
    published->serialBase = platform->serial.base;
    published->meshBase = macrisc_base(&platform->mesh);
    published->floppyBase = macrisc_base(&platform->floppy);
    published->audioBase = macrisc_base(&platform->audio);
    published->ethernetBase = macrisc_base(&platform->ethernet);
    published->nvramAddress = platform->nvram.base;
    published->nvramData = 0;           /* flash NVRAM has no data port */
    published->ata0Base = macrisc_base(&platform->ata0);
    published->ata1Base = macrisc_base(&platform->ata1);
    return 1;
}

int
PEMacRISCComputeClockConversion(const PEMacRISCPlatform *platform,
    unsigned int *numerator, unsigned int *denominator,
    unsigned int *period824)
{
    unsigned int timebase;
    unsigned int whole;
    unsigned int remainder;
    unsigned int fraction;
    unsigned int bit;

    if (platform == 0 || numerator == 0 || denominator == 0 ||
        period824 == 0 || platform->busClockHz < 1000000U ||
        platform->timebaseHz == 0 || platform->timebaseHz > 0x7fffffffU)
        return 0;
    timebase = platform->timebaseHz;
    whole = 1000000000U / timebase;
    if (whole > 255U)
        return 0;
    /* Long division for the 24 fraction bits; C89 has no long long. */
    remainder = 1000000000U % timebase;
    fraction = 0;
    for (bit = 0; bit < 24; bit++) {
        remainder <<= 1;
        fraction <<= 1;
        if (remainder >= timebase) {
            remainder -= timebase;
            fraction |= 1U;
        }
    }
    *numerator = 4000U;
    *denominator = platform->busClockHz / 1000000U;
    *period824 = (whole << 24) | fraction;
    return 1;
}

unsigned int
PEMacRISCPMUInterruptList(const PEMacRISCPlatform *platform,
    unsigned int output[2])
{
    if (output == 0 || PEMacRISCValidate(platform) != kPEPlatformValid ||
        !platform->hasPMU || !platform->hasCascade ||
        !platform->hasPMUInterrupt)
        return 0;
    output[0] = platform->mpicSources + 2;      /* VIA1 child PMAC_DEV_VIA1 */
    output[1] = platform->pmuInterruptSource;
    return 2;
}

static const char *
macrisc_cpu_name(PECPUFamily cpu)
{
    switch (cpu) {
    case kPECPU750:     return "750";
    case kPECPU7400:    return "7400";
    case kPECPU7410:    return "7410";
    case kPECPU745x:    return "745x";
    case kPECPU970:     return "970";
    default:            break;
    }
    return "unknown";
}

static const char *
macrisc_macio_name(PEMacIOFamily macIO)
{
    switch (macIO) {
    case kPEMacIOKeyLargo:  return "KeyLargo";
    case kPEMacIOPangea:    return "Pangea";
    case kPEMacIOIntrepid:  return "Intrepid";
    case kPEMacIOK2:        return "K2";
    default:                break;
    }
    return "unknown";
}

static const char *
macrisc_error_name(PEPlatformError error)
{
    switch (error) {
    case kPEPlatformMissingMacIO:   return "missing Mac-IO";
    case kPEPlatformBadMacIORange:  return "malformed Mac-IO range";
    case kPEPlatformMissingMPIC:    return "missing MPIC";
    case kPEPlatformBadMPICRange:   return "malformed MPIC range";
    case kPEPlatformBadMPICCount:   return "bad MPIC source count";
    case kPEPlatformMissingCPU:     return "missing CPU";
    case kPEPlatformBadCPUCount:    return "too many CPUs";
    case kPEPlatformBadClock:       return "bad firmware clocks";
    case kPEPlatformBadCascade:     return "bad VIA cascade";
    case kPEPlatformMissingVIA:     return "missing VIA";
    case kPEPlatformMissingSerial:  return "missing SCC";
    case kPEPlatformMissingNVRAM:   return "missing flash NVRAM";
    case kPEPlatformBadRange:       return "malformed resource range";
    default:                        break;
    }
    return "malformed device tree";
}

static unsigned int
macrisc_append(char *buffer, unsigned int size, unsigned int used,
    const char *text)
{
    while (*text != 0 && used + 1 < size)
        buffer[used++] = *text++;
    if (used < size)
        buffer[used] = 0;
    return used;
}

unsigned int
PEMacRISCFormatDiagnostic(char *buffer, unsigned int size,
    const PEMacRISCPlatform *platform, PEMacRISCStatus status,
    PEPlatformError error)
{
    unsigned int used;

    if (buffer == 0 || size == 0 || platform == 0)
        return 0;
    used = macrisc_append(buffer, size, 0, "MacRISC: ");
    used = macrisc_append(buffer, size, used,
        platform->model[0] != 0 ? platform->model : "unknown");
    if (status == kPEMacRISCSupported)
        used = macrisc_append(buffer, size, used, " accepted: cpu=");
    else if (status == kPEMacRISCCompatibleUnlisted)
        used = macrisc_append(buffer, size, used,
            " accepted as unlisted compatible: cpu=");
    else if (status == kPEMacRISCMalformed)
        return macrisc_append(buffer, size,
            macrisc_append(buffer, size, used, " rejected: "),
            macrisc_error_name(error));
    else
        used = macrisc_append(buffer, size, used, " rejected: cpu=");
    used = macrisc_append(buffer, size, used,
        macrisc_cpu_name(platform->cpuFamily));
    if (status != kPEMacRISCSupported &&
        status != kPEMacRISCCompatibleUnlisted)
        used = macrisc_append(buffer, size, used,
            platform->hostSupported ? " host=uni-north" :
            " host=unsupported");
    used = macrisc_append(buffer, size, used, " mac-io=");
    return macrisc_append(buffer, size, used,
        macrisc_macio_name(platform->macIOFamily));
}
