#include "TASCore.h"

#include <string.h>

#define TAS_CELL_MAX 0xffffffffUL
#define TAS_KEYLARGO_WINDOW 0x00100000UL
#define TAS_DISCOVERY_LIMIT 16UL
#define TAS_TRAVERSAL_LIMIT 64UL
#define TAS_I2S_DATA_WORD 0x02000200UL
#define TAS_I2S_MCLK_TO_FS 256UL
#define TAS_I2S_SCLK_TO_FS 64UL

/*
 * Clock sources and valid divisors follow Apple's AudioI2SControl.cpp from
 * AppleOnboardAudio-184.2.5.  Hardware encoding remains an adapter concern.
 */
static const unsigned long tasClockSources[] = {
    18432000UL, 45158400UL, 49152000UL
};

typedef struct {
    TASNode macIO;
    TASNode i2s;
    TASNode soundBus;
    TASNode soundChip;
    TASNode codec;
    TASNode gpio;
    TASCodecKind kind;
    const char *compatible;
} TASCandidate;

static TASStatus find_i2s_clock(unsigned long rate, TASI2SClock *clock)
{
    unsigned long sourceIndex;
    unsigned long source;
    unsigned long divisor;
    unsigned long product;
    if (rate < 32000UL || rate > 48000UL)
        return kTASStatusUnsupported;
    for (sourceIndex = 0; sourceIndex < sizeof(tasClockSources) /
        sizeof(tasClockSources[0]); ++sourceIndex) {
        source = tasClockSources[sourceIndex];
        for (divisor = 1UL; divisor <= 64UL; ++divisor) {
            if (divisor != 1UL && divisor != 3UL && divisor != 5UL &&
                (divisor & 1UL) != 0)
                continue;
            product = TAS_I2S_MCLK_TO_FS * divisor;
            if (rate <= source / product && rate * product == source) {
                clock->rate = rate;
                clock->sourceHz = source;
                clock->mclkDivisor = divisor;
                clock->sclkDivisor = TAS_I2S_MCLK_TO_FS /
                    TAS_I2S_SCLK_TO_FS;
                clock->frameRatio = TAS_I2S_SCLK_TO_FS;
                clock->dataWord = TAS_I2S_DATA_WORD;
                clock->codecSlotBits = 20UL;
                clock->pcmBits = 16UL;
                clock->channels = 2UL;
                return kTASStatusOK;
            }
        }
    }
    return kTASStatusUnsupported;
}

static unsigned long be32(const unsigned char *bytes)
{
    return ((unsigned long)bytes[0] << 24) |
        ((unsigned long)bytes[1] << 16) |
        ((unsigned long)bytes[2] << 8) | (unsigned long)bytes[3];
}

static int property(const TASPropertyReader *reader, TASNode node,
    const char *name, const unsigned char **bytes, unsigned long *length)
{
    const unsigned char *foundBytes;
    unsigned long foundLength;
    foundBytes = 0;
    foundLength = 0;
    if (!reader->getProperty(reader->context, node, name, &foundBytes,
        &foundLength) || (foundLength != 0 && foundBytes == 0))
        return 0;
    *bytes = foundBytes;
    *length = foundLength;
    return 1;
}

static TASStatus exact_cells(const TASPropertyReader *reader, TASNode node,
    const char *name, unsigned long count, const unsigned char **bytes)
{
    unsigned long length;
    if (!property(reader, node, name, bytes, &length))
        return kTASStatusMissing;
    if (length != count * 4UL)
        return kTASStatusMalformed;
    return kTASStatusOK;
}

static TASStatus exact_cells_alias(const TASPropertyReader *reader,
    TASNode node, const char *first, const char *second, unsigned long count,
    const unsigned char **bytes)
{
    const unsigned char *firstBytes;
    const unsigned char *secondBytes;
    unsigned long length;
    unsigned long secondLength;
    int haveFirst;
    int haveSecond;
    haveFirst = property(reader, node, first, &firstBytes, &length);
    haveSecond = property(reader, node, second, &secondBytes, &secondLength);
    if (!haveFirst && !haveSecond)
        return kTASStatusMissing;
    if ((haveFirst && length != count * 4UL) ||
        (haveSecond && secondLength != count * 4UL))
        return kTASStatusMalformed;
    if (haveFirst && haveSecond && memcmp(firstBytes, secondBytes,
        (size_t)(count * 4UL)) != 0)
        return kTASStatusConflict;
    if (haveFirst) {
        *bytes = firstBytes;
        return kTASStatusOK;
    }
    *bytes = secondBytes;
    return kTASStatusOK;
}

static TASStatus string_property(const TASPropertyReader *reader,
    TASNode node, const char *name, const unsigned char **bytes,
    unsigned long *length, int required)
{
    if (!property(reader, node, name, bytes, length))
        return required ? kTASStatusMissing : kTASStatusOK;
    if (*length == 0 || (*bytes)[*length - 1UL] != 0 ||
        strlen((const char *)*bytes) + 1UL != *length)
        return kTASStatusMalformed;
    return kTASStatusOK;
}

static TASStatus parse_range(const unsigned char *bytes, TASRange *range)
{
    range->address = be32(bytes);
    range->length = be32(bytes + 4);
    if (range->length == 0)
        return kTASStatusMalformed;
    if (range->address > TAS_CELL_MAX - (range->length - 1UL))
        return kTASStatusOverflow;
    return kTASStatusOK;
}

static int ranges_overlap(const TASRange *first, const TASRange *second)
{
    unsigned long firstEnd;
    unsigned long secondEnd;
    firstEnd = first->address + first->length - 1UL;
    secondEnd = second->address + second->length - 1UL;
    return first->address <= secondEnd && second->address <= firstEnd;
}

static unsigned long find_nodes(const TASPropertyReader *reader,
    const char *name, TASNode *nodes, unsigned long capacity)
{
    TASNode cursor;
    TASNode previous;
    unsigned long count;
    unsigned long traversed;
    if (reader->findNodes != 0) {
        count = reader->findNodes(reader->context, name, nodes, capacity);
        return count > capacity ? capacity + 1UL : count;
    }
    cursor = 0;
    count = 0;
    traversed = 0;
    while (traversed < TAS_TRAVERSAL_LIMIT) {
        previous = cursor;
        if (!reader->findNode(reader->context, name, &cursor))
            return count;
        if (cursor == 0 || cursor == previous)
            return capacity + 1UL;
        ++traversed;
        if (count < capacity)
            nodes[count] = cursor;
        ++count;
        if (count > capacity)
            return capacity + 1UL;
    }
    if (reader->findNode(reader->context, name, &cursor))
        return capacity + 1UL;
    return count;
}

static unsigned long find_property_nodes(const TASPropertyReader *reader,
    const char *name, const char *value, TASNode *nodes,
    unsigned long capacity)
{
    TASNode cursor;
    const unsigned char *bytes;
    unsigned long length;
    unsigned long count;
    unsigned long traversed;
    TASNode previous;
    if (reader->findPropertyNodes != 0) {
        count = reader->findPropertyNodes(reader->context, name, value,
            nodes, capacity);
        return count > capacity ? capacity + 1UL : count;
    }
    cursor = 0;
    count = 0;
    traversed = 0;
    while (traversed < TAS_TRAVERSAL_LIMIT) {
        previous = cursor;
        if (!reader->findNode(reader->context, "*", &cursor))
            return count;
        if (cursor == 0 || cursor == previous)
            return capacity + 1UL;
        ++traversed;
        if (property(reader, cursor, name, &bytes, &length) && length != 0 &&
            bytes[length - 1UL] == 0 &&
            strlen((const char *)bytes) + 1UL == length &&
            strcmp((const char *)bytes, value) == 0) {
            if (count < capacity)
                nodes[count] = cursor;
            ++count;
            if (count > capacity)
                return capacity + 1UL;
        }
    }
    if (reader->findNode(reader->context, "*", &cursor))
        return capacity + 1UL;
    return count;
}

static int node_in(const TASNode *nodes, unsigned long count, TASNode node)
{
    unsigned long index;
    for (index = 0; index < count; ++index) {
        if (nodes[index] == node)
            return 1;
    }
    return 0;
}

static int is_sound_bus(const TASPropertyReader *reader, TASNode node)
{
    static const char *names[] = {
        "i2s-a", "i2s-b", "i2s-c", "i2s-d",
        "i2s-e", "i2s-f", "i2s-g", "i2s-h"
    };
    TASNode nodes[TAS_DISCOVERY_LIMIT];
    unsigned long count;
    unsigned long index;
    for (index = 0; index < sizeof(names) / sizeof(names[0]); ++index) {
        count = find_nodes(reader, names[index], nodes, TAS_DISCOVERY_LIMIT);
        if (count > TAS_DISCOVERY_LIMIT)
            return -1;
        if (node_in(nodes, count, node))
            return 1;
    }
    return 0;
}

static TASStatus compatible_kind(const TASPropertyReader *reader,
    TASNode node, TASCodecKind *kind, const char **compatible)
{
    const unsigned char *bytes;
    unsigned long length;
    TASStatus status;
    status = string_property(reader, node, "compatible", &bytes, &length, 1);
    if (status != kTASStatusOK)
        return status;
    if (strcmp((const char *)bytes, "tumbler") == 0) {
        *kind = kTASCodecTAS3001C;
        *compatible = "tumbler";
        return kTASStatusOK;
    }
    if (strcmp((const char *)bytes, "snapper") == 0) {
        *kind = kTASCodecTAS3004;
        *compatible = "snapper";
        return kTASStatusOK;
    }
    return kTASStatusNotMatched;
}

static TASStatus resolve_ref(const TASPropertyReader *reader, TASNode owner,
    TASNode *codec, int *present)
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long count;
    *present = 0;
    if (!property(reader, owner, "platform-tas-codec-ref", &bytes, &length))
        return kTASStatusOK;
    *present = 1;
    if (length != 4UL)
        return kTASStatusMalformed;
    count = reader->resolvePhandle(reader->context, be32(bytes), codec);
    if (count == 0)
        return kTASStatusUnresolved;
    if (count != 1UL)
        return kTASStatusAmbiguous;
    return kTASStatusOK;
}

static TASStatus codec_for_chain(const TASPropertyReader *reader,
    TASNode soundBus, TASNode soundChip, TASCandidate *candidate)
{
    TASCodecKind soundKind;
    TASCodecKind refKind;
    const char *soundCompatible;
    const char *refCompatible;
    TASNode codec;
    TASNode busCodec;
    TASNode chipCodec;
    TASStatus soundStatus;
    TASStatus status;
    int haveBusRef;
    int haveChipRef;
    soundStatus = compatible_kind(reader, soundChip, &soundKind,
        &soundCompatible);
    if (soundStatus != kTASStatusOK &&
        soundStatus != kTASStatusNotMatched)
        return soundStatus;
    status = resolve_ref(reader, soundBus, &busCodec, &haveBusRef);
    if (status != kTASStatusOK)
        return status;
    status = resolve_ref(reader, soundChip, &chipCodec, &haveChipRef);
    if (status != kTASStatusOK)
        return status;
    if (haveBusRef && haveChipRef && busCodec != chipCodec)
        return kTASStatusConflict;
    if (haveBusRef || haveChipRef) {
        codec = haveBusRef ? busCodec : chipCodec;
        status = compatible_kind(reader, codec, &refKind, &refCompatible);
        if (status != kTASStatusOK)
            return status;
        if (soundStatus == kTASStatusOK && soundKind != refKind)
            return kTASStatusConflict;
        candidate->codec = codec;
        candidate->kind = refKind;
        candidate->compatible = refCompatible;
        return kTASStatusOK;
    }
    if (soundStatus != kTASStatusOK)
        return kTASStatusNotMatched;
    if (!reader->findNode(reader->context, "/mac-io/i2c/deq", &codec))
        return kTASStatusNotMatched;
    status = compatible_kind(reader, codec, &refKind, &refCompatible);
    if (status == kTASStatusOK && soundKind != refKind)
        return kTASStatusConflict;
    if (status != kTASStatusOK && status != kTASStatusMissing)
        return kTASStatusConflict;
    candidate->codec = codec;
    candidate->kind = soundKind;
    candidate->compatible = soundCompatible;
    return kTASStatusOK;
}

static TASStatus gpio_for_macio(const TASPropertyReader *reader,
    TASNode macIO, TASNode *gpio)
{
    TASNode nodes[TAS_DISCOVERY_LIMIT];
    TASNode parent;
    unsigned long count;
    unsigned long index;
    unsigned long matches;
    count = find_nodes(reader, "gpio", nodes, TAS_DISCOVERY_LIMIT);
    if (count > TAS_DISCOVERY_LIMIT)
        return kTASStatusAmbiguous;
    matches = 0;
    for (index = 0; index < count; ++index) {
        if (reader->getParent(reader->context, nodes[index], &parent) &&
            parent == macIO) {
            *gpio = nodes[index];
            ++matches;
        }
    }
    if (matches == 0)
        return kTASStatusNotMatched;
    if (matches != 1UL)
        return kTASStatusAmbiguous;
    return kTASStatusOK;
}

static TASStatus discover_candidate(const TASPropertyReader *reader,
    TASCandidate *candidate)
{
    TASNode controllers[TAS_DISCOVERY_LIMIT];
    TASNode sounds[TAS_DISCOVERY_LIMIT];
    TASNode soundBus;
    TASNode controller;
    TASNode macIO;
    TASCandidate found;
    unsigned long controllerCount;
    unsigned long soundCount;
    unsigned long index;
    unsigned long matches;
    TASStatus status;
    controllerCount = find_nodes(reader, "i2s", controllers,
        TAS_DISCOVERY_LIMIT);
    soundCount = find_nodes(reader, "sound", sounds, TAS_DISCOVERY_LIMIT);
    if (controllerCount > TAS_DISCOVERY_LIMIT ||
        soundCount > TAS_DISCOVERY_LIMIT)
        return kTASStatusAmbiguous;
    matches = 0;
    for (index = 0; index < soundCount; ++index) {
        if (!reader->getParent(reader->context, sounds[index], &soundBus) ||
            is_sound_bus(reader, soundBus) != 1 ||
            !reader->getParent(reader->context, soundBus, &controller) ||
            !node_in(controllers, controllerCount, controller) ||
            !reader->getParent(reader->context, controller, &macIO))
            continue;
        memset(&found, 0, sizeof(found));
        found.macIO = macIO;
        found.i2s = controller;
        found.soundBus = soundBus;
        found.soundChip = sounds[index];
        status = codec_for_chain(reader, soundBus, sounds[index], &found);
        if (status == kTASStatusNotMatched)
            continue;
        if (status != kTASStatusOK)
            return status;
        status = gpio_for_macio(reader, macIO, &found.gpio);
        if (status == kTASStatusNotMatched)
            continue;
        if (status != kTASStatusOK)
            return status;
        ++matches;
        *candidate = found;
    }
    if (matches == 0)
        return kTASStatusNotMatched;
    if (matches != 1UL)
        return kTASStatusAmbiguous;
    return kTASStatusOK;
}

static TASStatus normalized_i2c(unsigned long raw, unsigned long *address)
{
    if (raw == 0x68UL || raw == 0x6aUL) {
        *address = raw >> 1;
        return kTASStatusOK;
    }
    if (raw == 0x69UL || raw == 0x6bUL)
        return kTASStatusMalformed;
    if (raw < 0x08UL || raw > 0x77UL)
        return kTASStatusMalformed;
    *address = raw;
    return kTASStatusOK;
}

static TASStatus parse_port_property(const TASPropertyReader *reader,
    TASNode node, int allowReg, unsigned long *port)
{
    const unsigned char *bytes;
    unsigned long length;
    TASStatus status;
    if (property(reader, node, "AAPL,i2c-port-select", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
    } else {
        if (!allowReg)
            return kTASStatusMissing;
        status = exact_cells(reader, node, "reg", 1, &bytes);
        if (status != kTASStatusOK)
            return status;
    }
    *port = be32(bytes);
    if (*port > 15UL)
        return kTASStatusMalformed;
    return kTASStatusOK;
}

static TASStatus parse_codec_transport(const TASPropertyReader *reader,
    const TASCandidate *candidate, TASMachineConfig *config)
{
    TASNode i2cNodes[TAS_DISCOVERY_LIMIT];
    TASNode parent;
    TASNode i2c;
    TASNode oldCodec;
    const unsigned char *bytes;
    unsigned long length;
    unsigned long count;
    unsigned long primary;
    unsigned long second;
    int havePrimary;
    TASStatus status;
    havePrimary = 0;
    if (property(reader, candidate->codec, "reg", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
        status = normalized_i2c(be32(bytes), &primary);
        if (status != kTASStatusOK)
            return status;
        havePrimary = 1;
    }
    if (property(reader, candidate->codec, "i2c-address", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
        status = normalized_i2c(be32(bytes), &second);
        if (status != kTASStatusOK)
            return status;
        if (havePrimary && primary != second)
            return kTASStatusConflict;
        primary = second;
        havePrimary = 1;
    }
    if (!havePrimary)
        return kTASStatusMissing;
    config->i2cAddress = primary;
    count = find_nodes(reader, "i2c", i2cNodes, TAS_DISCOVERY_LIMIT);
    if (count == 0 || count > TAS_DISCOVERY_LIMIT ||
        !reader->getParent(reader->context, candidate->codec, &parent))
        return kTASStatusNotMatched;
    if (node_in(i2cNodes, count, parent)) {
        if (!reader->findNode(reader->context, "/mac-io/i2c/deq",
            &oldCodec) || oldCodec != candidate->codec)
            return kTASStatusNotMatched;
        if (!reader->getParent(reader->context, parent, &i2c) ||
            i2c != candidate->macIO)
            return kTASStatusNotMatched;
        return parse_port_property(reader, candidate->codec, 0,
            &config->i2cPort);
    }
    if (!reader->getParent(reader->context, parent, &i2c) ||
        !node_in(i2cNodes, count, i2c))
        return kTASStatusNotMatched;
    if (!reader->getParent(reader->context, i2c, &oldCodec) ||
        oldCodec != candidate->macIO)
        return kTASStatusNotMatched;
    return parse_port_property(reader, parent, 1, &config->i2cPort);
}

static int node_under_gpio(const TASPropertyReader *reader, TASNode node,
    TASNode gpio)
{
    TASNode parent;
    unsigned long traversed;
    traversed = 0;
    while (node != gpio && traversed < TAS_TRAVERSAL_LIMIT) {
        if (!reader->getParent(reader->context, node, &parent) ||
            parent == 0 || parent == node)
            return 0;
        node = parent;
        ++traversed;
    }
    return node == gpio;
}

static TASStatus merge_gpio_property(const TASPropertyReader *reader,
    TASNode owner, const char *name, TASNode gpio, TASNode *node, int *present)
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long count;
    TASNode resolved;
    if (name == 0 || !property(reader, owner, name, &bytes, &length))
        return kTASStatusOK;
    if (length != 4UL)
        return kTASStatusMalformed;
    count = reader->resolvePhandle(reader->context, be32(bytes), &resolved);
    if (count == 0)
        return kTASStatusUnresolved;
    if (count != 1UL)
        return kTASStatusAmbiguous;
    if (!node_under_gpio(reader, resolved, gpio))
        return kTASStatusNotMatched;
    if (*present && *node != resolved)
        return kTASStatusConflict;
    *node = resolved;
    *present = 1;
    return kTASStatusOK;
}

static TASStatus resolve_gpio_role(const TASPropertyReader *reader,
    const TASCandidate *candidate, const char *primary,
    const char *primaryAlias, const char *legacy, TASNode *node, int *present)
{
    TASNode nodes[2];
    unsigned long count;
    TASStatus status;
    *present = 0;
    status = merge_gpio_property(reader, candidate->soundBus, primary,
        candidate->gpio, node, present);
    if (status != kTASStatusOK)
        return status;
    status = merge_gpio_property(reader, candidate->soundBus, primaryAlias,
        candidate->gpio, node, present);
    if (status != kTASStatusOK)
        return status;
    status = merge_gpio_property(reader, candidate->soundChip, primary,
        candidate->gpio, node, present);
    if (status != kTASStatusOK)
        return status;
    status = merge_gpio_property(reader, candidate->soundChip, primaryAlias,
        candidate->gpio, node, present);
    if (status != kTASStatusOK)
        return status;
    count = find_property_nodes(reader, "audio-gpio", legacy, nodes, 2);
    if (count > 1UL)
        return kTASStatusConflict;
    if (count == 1UL) {
        if (!node_under_gpio(reader, nodes[0], candidate->gpio))
            return kTASStatusNotMatched;
        if (*present && *node != nodes[0])
            return kTASStatusConflict;
        *node = nodes[0];
        *present = 1;
    }
    return kTASStatusOK;
}

static TASStatus macio_base(const TASPropertyReader *reader, TASNode macIO,
    unsigned long *base)
{
    const unsigned char *bytes;
    TASStatus status;
    status = exact_cells(reader, macIO, "AAPL,address", 1, &bytes);
    if (status != kTASStatusOK)
        return status;
    *base = be32(bytes);
    return kTASStatusOK;
}

static TASStatus parse_gpio(const TASPropertyReader *reader, TASNode macIO,
    TASNode node, int needsIRQ, TASGPIODescriptor *gpio)
{
    const unsigned char *regBytes;
    const unsigned char *addressBytes;
    const unsigned char *bytes;
    unsigned long regLength;
    unsigned long addressLength;
    unsigned long base;
    unsigned long absolute;
    int haveReg;
    int haveAddress;
    TASStatus status;
    haveReg = property(reader, node, "reg", &regBytes, &regLength);
    haveAddress = property(reader, node, "AAPL,address", &addressBytes,
        &addressLength);
    if (haveReg && haveAddress)
        return kTASStatusConflict;
    if (!haveReg && !haveAddress)
        return kTASStatusMissing;
    if (haveReg) {
        if (regLength != 4UL)
            return kTASStatusMalformed;
        gpio->offset = be32(regBytes);
    } else {
        if (addressLength != 4UL)
            return kTASStatusMalformed;
        status = macio_base(reader, macIO, &base);
        if (status != kTASStatusOK)
            return status;
        absolute = be32(addressBytes);
        if (absolute < base)
            return kTASStatusOverflow;
        gpio->offset = absolute - base;
    }
    if (gpio->offset >= TAS_KEYLARGO_WINDOW)
        return kTASStatusOverflow;
    status = exact_cells(reader, node, "audio-gpio-active-state", 1, &bytes);
    if (status != kTASStatusOK)
        return status;
    if (be32(bytes) > 1UL)
        return kTASStatusMalformed;
    gpio->activeHigh = be32(bytes) != 0;
    gpio->hasIRQ = 0;
    gpio->irq = 0;
    if (needsIRQ) {
        status = exact_cells_alias(reader, node, "interrupts",
            "AAPL,interrupts", 1, &bytes);
        if (status != kTASStatusOK)
            return status;
        gpio->hasIRQ = 1;
        gpio->irq = be32(bytes);
    }
    return kTASStatusOK;
}

static TASStatus parse_required_gpio(const TASPropertyReader *reader,
    const TASCandidate *candidate, const char *primary,
    const char *primaryAlias, const char *legacy, TASGPIODescriptor *gpio)
{
    TASNode node;
    TASStatus status;
    int present;
    status = resolve_gpio_role(reader, candidate, primary, primaryAlias,
        legacy, &node, &present);
    if (status != kTASStatusOK)
        return status;
    if (!present)
        return kTASStatusMissing;
    return parse_gpio(reader, candidate->macIO, node, 0, gpio);
}

static TASStatus parse_route(const TASPropertyReader *reader,
    const TASCandidate *candidate, TASRouteKind kind,
    unsigned long quirks, TASRouteDescriptor *route)
{
    static const char *mutePrimary[kTASRouteCount] = {
        "platform-headphone-mute", "platform-lineout-mute"
    };
    static const char *detectPrimary[kTASRouteCount] = {
        "platform-headphone-detect", "platform-lineout-detect"
    };
    static const char *muteLegacy[kTASRouteCount] = {
        "headphone-mute", "line-output-mute"
    };
    static const char *detectLegacy[kTASRouteCount] = {
        "headphone-detect", "line-output-detect"
    };
    TASNode muteNode;
    TASNode detectNode;
    TASStatus status;
    int haveMute;
    int haveDetect;
    status = resolve_gpio_role(reader, candidate, mutePrimary[kind], 0,
        muteLegacy[kind],
        &muteNode, &haveMute);
    if (status != kTASStatusOK)
        return status;
    status = resolve_gpio_role(reader, candidate, detectPrimary[kind], 0,
        detectLegacy[kind],
        &detectNode, &haveDetect);
    if (status != kTASStatusOK)
        return status;
    if (kind == kTASRouteHeadphone &&
        (quirks & kTASQuirkANDedReset) != 0) {
        if (!haveMute)
            return kTASStatusMissing;
        status = parse_gpio(reader, candidate->macIO, muteNode, 0,
            &route->mute);
        if (status != kTASStatusOK)
            return status;
        if (!haveDetect) {
            route->present = 0;
            return kTASStatusOK;
        }
        status = parse_gpio(reader, candidate->macIO, detectNode, 1,
            &route->detect);
        if (status != kTASStatusOK)
            return status;
        route->present = 1;
        return kTASStatusOK;
    }
    if (!haveMute && !haveDetect) {
        route->present = 0;
        return kTASStatusOK;
    }
    if (!haveMute || !haveDetect)
        return kTASStatusMissing;
    status = parse_gpio(reader, candidate->macIO, muteNode, 0, &route->mute);
    if (status != kTASStatusOK)
        return status;
    status = parse_gpio(reader, candidate->macIO, detectNode, 1,
        &route->detect);
    if (status != kTASStatusOK)
        return status;
    route->present = 1;
    return kTASStatusOK;
}

static TASStatus parse_policy(const TASPropertyReader *reader,
    TASNode soundChip, TASMachineConfig *config)
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long index;
    unsigned long accepted;
    unsigned long previous;
    unsigned long rate;
    TASI2SClock clock;
    int duplicate;
    int have44100;
    TASStatus status;
    status = string_property(reader, soundChip, "model", &bytes, &length, 0);
    if (status != kTASStatusOK)
        return status;
    if (property(reader, soundChip, "model", &bytes, &length)) {
        if (length > TAS_MODEL_LENGTH)
            return kTASStatusMalformed;
        memcpy(config->model, bytes, (size_t)length);
    }
    if (property(reader, soundChip, "layout-id", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
        config->layoutID = be32(bytes);
    }
    if (!property(reader, soundChip, "sample-rates", &bytes, &length))
        return kTASStatusMissing;
    if (length == 0 || (length & 3UL) != 0 ||
        length > TAS_MAX_RATES * 4UL)
        return kTASStatusMalformed;
    accepted = 0;
    have44100 = 0;
    for (index = 0; index < length / 4UL; ++index) {
        rate = be32(bytes + index * 4UL);
        if (rate == 0)
            return kTASStatusMalformed;
        if (find_i2s_clock(rate, &clock) != kTASStatusOK)
            continue;
        duplicate = 0;
        for (previous = 0; previous < accepted; ++previous) {
            if (config->rates[previous] == rate)
                duplicate = 1;
        }
        if (!duplicate) {
            config->rates[accepted] = rate;
            ++accepted;
        }
        if (rate == 44100UL)
            have44100 = 1;
    }
    config->rateCount = accepted;
    if (!have44100)
        return kTASStatusUnsupported;
    return kTASStatusOK;
}

static TASStatus parse_quirks(const TASPropertyReader *reader,
    TASNode soundChip, TASMachineConfig *config)
{
    const unsigned char *bytes;
    unsigned long length;
    if (property(reader, soundChip, "has-anded-reset", &bytes, &length)) {
        if (length != 0)
            return kTASStatusMalformed;
        config->quirks = kTASQuirkANDedReset;
    }
    return kTASStatusOK;
}

static TASStatus parse_candidate(const TASPropertyReader *reader,
    const TASCandidate *candidate, TASMachineConfig *config)
{
    const unsigned char *bytes;
    TASStatus status;
    int route;
    config->codecKind = candidate->kind;
    memcpy(config->codecCompatible, candidate->compatible,
        strlen(candidate->compatible) + 1UL);
    status = exact_cells(reader, candidate->soundBus, "reg", 1, &bytes);
    if (status != kTASStatusOK)
        return status;
    config->i2sCell = be32(bytes);
    if (config->i2sCell > 7UL)
        return kTASStatusMalformed;
    status = exact_cells(reader, candidate->i2s, "reg", 6, &bytes);
    if (status != kTASStatusOK)
        return status;
    status = parse_range(bytes, &config->i2s);
    if (status != kTASStatusOK)
        return status;
    status = parse_range(bytes + 8, &config->outputDBDMA);
    if (status != kTASStatusOK)
        return status;
    status = parse_range(bytes + 16, &config->inputDBDMA);
    if (status != kTASStatusOK)
        return status;
    if (ranges_overlap(&config->i2s, &config->outputDBDMA) ||
        ranges_overlap(&config->i2s, &config->inputDBDMA) ||
        ranges_overlap(&config->outputDBDMA, &config->inputDBDMA))
        return kTASStatusConflict;
    status = exact_cells_alias(reader, candidate->i2s, "interrupts",
        "AAPL,interrupts", 6, &bytes);
    if (status != kTASStatusOK)
        return status;
    config->codecInterrupt.number = be32(bytes);
    config->codecInterrupt.sense = be32(bytes + 4);
    config->outputInterrupt.number = be32(bytes + 8);
    config->outputInterrupt.sense = be32(bytes + 12);
    config->inputInterrupt.number = be32(bytes + 16);
    config->inputInterrupt.sense = be32(bytes + 20);
    if (config->codecInterrupt.number == 0 ||
        config->outputInterrupt.number == 0 ||
        config->inputInterrupt.number == 0)
        return kTASStatusMalformed;
    if (config->codecInterrupt.number == config->outputInterrupt.number ||
        config->codecInterrupt.number == config->inputInterrupt.number ||
        config->outputInterrupt.number == config->inputInterrupt.number)
        return kTASStatusConflict;
    status = parse_codec_transport(reader, candidate, config);
    if (status != kTASStatusOK)
        return status;
    if ((candidate->kind == kTASCodecTAS3001C &&
        config->i2cAddress != 0x34UL) ||
        (candidate->kind == kTASCodecTAS3004 &&
        config->i2cAddress != 0x35UL))
        return kTASStatusMalformed;
    status = parse_quirks(reader, candidate->soundChip, config);
    if (status != kTASStatusOK)
        return status;
    if ((config->quirks & kTASQuirkANDedReset) == 0) {
        status = parse_required_gpio(reader, candidate, "platform-hw-reset",
            0, "audio-hw-reset", &config->hardwareReset);
        if (status != kTASStatusOK)
            return status;
    }
    status = parse_required_gpio(reader, candidate, "platform-amp-mute", 0,
        "amp-mute", &config->amplifierMute);
    if (status != kTASStatusOK)
        return status;
    status = parse_required_gpio(reader, candidate,
        "platform-codec-input-data-mux", "platform-codec-input-data-mu",
        "codec-input-data-mux", &config->inputMux);
    if (status != kTASStatusOK)
        return status;
    for (route = 0; route < (int)kTASRouteCount; ++route) {
        status = parse_route(reader, candidate, (TASRouteKind)route,
            config->quirks, &config->routes[route]);
        if (status != kTASStatusOK)
            return status;
    }
    status = parse_policy(reader, candidate->soundChip, config);
    if (status != kTASStatusOK)
        return status;
    if ((config->quirks & kTASQuirkANDedReset) != 0 &&
        config->routes[kTASRouteLineOut].present)
        return kTASStatusUnsupported;
    return kTASStatusOK;
}

static TASStatus parse_machine_config(const TASPropertyReader *reader,
    TASMachineConfig *configuration)
{
    TASCandidate candidate;
    TASStatus status;
    if (reader == 0 || reader->getProperty == 0 || reader->findNode == 0 ||
        reader->resolvePhandle == 0 || reader->getParent == 0)
        return kTASStatusMalformed;
    memset(configuration, 0, sizeof(*configuration));
    status = discover_candidate(reader, &candidate);
    if (status != kTASStatusOK)
        return status;
    return parse_candidate(reader, &candidate, configuration);
}

TASStatus TASParseMachineConfig(const TASPropertyReader *reader,
    TASMachineConfig *configuration)
{
    TASMachineConfig parsed;
    TASStatus status;
    if (configuration == 0)
        return kTASStatusMalformed;
    status = parse_machine_config(reader, &parsed);
    if (status == kTASStatusOK)
        *configuration = parsed;
    return status;
}

TASStatus TASSelectI2SClock(const TASMachineConfig *configuration,
    unsigned long rate, TASI2SClock *clock)
{
    TASI2SClock selected;
    unsigned long index;
    int advertised;
    TASStatus status;
    if (configuration == 0 || clock == 0)
        return kTASStatusMalformed;
    if (configuration->rateCount > TAS_MAX_RATES)
        return kTASStatusMalformed;
    advertised = 0;
    for (index = 0; index < configuration->rateCount; ++index) {
        if (configuration->rates[index] == rate)
            advertised = 1;
    }
    if (!advertised)
        return kTASStatusUnsupported;
    status = find_i2s_clock(rate, &selected);
    if (status == kTASStatusOK)
        *clock = selected;
    return status;
}

void TASSharedClockInit(TASSharedClock *state)
{
    if (state != 0) {
        memset(state, 0, sizeof(*state));
        state->generation = 1UL;
    }
}

static unsigned long stream_mask(TASStreamDirection direction)
{
    return direction == kTASStreamOutput ? kTASStreamMaskOutput :
        kTASStreamMaskInput;
}

static unsigned long mask_count(unsigned long mask)
{
    return (mask & kTASStreamMaskOutput ? 1UL : 0UL) +
        (mask & kTASStreamMaskInput ? 1UL : 0UL);
}

static int valid_shared_clock(const TASSharedClock *state)
{
    if (state == 0 || state->generation == 0UL ||
        (state->activeMask & ~(unsigned long)(kTASStreamMaskOutput |
        kTASStreamMaskInput)) != 0UL ||
        (state->quiescedMask & ~state->activeMask) != 0UL ||
        state->referenceCount != mask_count(state->activeMask) ||
        ((state->activeMask == 0UL) != (state->activeRate == 0UL)) ||
        (state->outputsMuted != 0 && state->outputsMuted != 1))
        return 0;
    return 1;
}

static TASStatus advance_generation(TASSharedClock *state)
{
    if (state->generation == ~0UL)
        return kTASStatusOverflow;
    ++state->generation;
    return kTASStatusOK;
}

TASStatus TASAcquireI2SStream(const TASMachineConfig *configuration,
    TASSharedClock *state, TASStreamDirection direction, unsigned long rate,
    TASI2SClock *clock)
{
    TASSharedClock acquired;
    TASI2SClock selected;
    TASStatus status;
    unsigned long mask;
    if (state == 0 || clock == 0 || (direction != kTASStreamOutput &&
        direction != kTASStreamInput))
        return kTASStatusMalformed;
    if (!valid_shared_clock(state))
        return kTASStatusMalformed;
    status = TASSelectI2SClock(configuration, rate, &selected);
    if (status != kTASStatusOK)
        return status;
    if (state->activeMask != 0UL && state->activeRate != rate)
        return kTASStatusConflict;
    acquired = *state;
    mask = stream_mask(direction);
    if ((acquired.activeMask & mask) != 0UL)
        return kTASStatusConflict;
    if (advance_generation(&acquired) != kTASStatusOK)
        return kTASStatusOverflow;
    acquired.activeMask |= mask;
    acquired.quiescedMask &= ~mask;
    acquired.activeRate = rate;
    ++acquired.referenceCount;
    *state = acquired;
    *clock = selected;
    return kTASStatusOK;
}

TASStatus TASReleaseI2SStream(TASSharedClock *state,
    TASStreamDirection direction)
{
    TASSharedClock released;
    unsigned long mask;
    if (state == 0 || (direction != kTASStreamOutput &&
        direction != kTASStreamInput))
        return kTASStatusMalformed;
    if (!valid_shared_clock(state))
        return kTASStatusMalformed;
    if (state->activeMask == 0UL)
        return kTASStatusConflict;
    released = *state;
    mask = stream_mask(direction);
    if ((released.activeMask & mask) == 0UL)
        return kTASStatusConflict;
    if (advance_generation(&released) != kTASStatusOK)
        return kTASStatusOverflow;
    released.activeMask &= ~mask;
    released.quiescedMask &= ~mask;
    --released.referenceCount;
    if (released.referenceCount == 0UL)
        released.activeRate = 0UL;
    *state = released;
    return kTASStatusOK;
}

TASStatus TASSetI2SStreamQuiesced(TASSharedClock *state,
    TASStreamDirection direction, int quiesced)
{
    TASSharedClock changed;
    unsigned long mask;
    if (state == 0 || (direction != kTASStreamOutput &&
        direction != kTASStreamInput) || (quiesced != 0 && quiesced != 1))
        return kTASStatusMalformed;
    if (!valid_shared_clock(state))
        return kTASStatusMalformed;
    mask = stream_mask(direction);
    if ((state->activeMask & mask) == 0UL)
        return kTASStatusConflict;
    if (((state->quiescedMask & mask) != 0UL) == (quiesced != 0))
        return kTASStatusOK;
    changed = *state;
    if (advance_generation(&changed) != kTASStatusOK)
        return kTASStatusOverflow;
    if (quiesced)
        changed.quiescedMask |= mask;
    else
        changed.quiescedMask &= ~mask;
    *state = changed;
    return kTASStatusOK;
}

TASStatus TASSetI2SOutputsMuted(TASSharedClock *state, int muted)
{
    TASSharedClock changed;
    if (state == 0 || (muted != 0 && muted != 1))
        return kTASStatusMalformed;
    if (!valid_shared_clock(state))
        return kTASStatusMalformed;
    if (state->outputsMuted == muted)
        return kTASStatusOK;
    changed = *state;
    if (advance_generation(&changed) != kTASStatusOK)
        return kTASStatusOverflow;
    changed.outputsMuted = muted;
    *state = changed;
    return kTASStatusOK;
}

static void plan_step(TASI2SRegisterPlan *plan,
    TASI2SPlanOperation operation, unsigned long value)
{
    plan->steps[plan->count].operation = operation;
    plan->steps[plan->count].value = value;
    ++plan->count;
}

static void plan_format(TASI2SRegisterPlan *plan, const TASI2SClock *clock)
{
    TASI2SPlanStep *step;
    plan_step(plan, kTASI2SConfigureFormat, 0UL);
    step = &plan->steps[plan->count - 1UL];
    step->sourceHz = clock->sourceHz;
    step->mclkDivisor = clock->mclkDivisor;
    step->sclkDivisor = clock->sclkDivisor;
    step->frameRatio = clock->frameRatio;
    step->codecSlotBits = clock->codecSlotBits;
    step->pcmBits = clock->pcmBits;
    step->channels = clock->channels;
}

static int valid_transition(const TASSharedClock *state,
    const TASI2STransition *transition)
{
    TASI2SClock expected;
    int live;
    if (!valid_shared_clock(state) || transition == 0 ||
        find_i2s_clock(transition->clock.rate, &expected) != kTASStatusOK ||
        memcmp(&transition->clock, &expected, sizeof(expected)) != 0 ||
        transition->generation != state->generation ||
        transition->activeRate != state->activeRate ||
        transition->activeMask != state->activeMask)
        return 0;
    live = state->activeMask != 0UL &&
        state->activeRate != transition->clock.rate;
    if (live && ((state->quiescedMask & state->activeMask) !=
        state->activeMask || !state->outputsMuted))
        return 0;
    return 1;
}

TASStatus TASPrepareI2STransition(const TASMachineConfig *configuration,
    const TASSharedClock *state, unsigned long rate,
    TASI2STransition *transition)
{
    TASI2STransition prepared;
    TASStatus status;
    int live;
    if (configuration == 0 || state == 0 || transition == 0)
        return kTASStatusMalformed;
    if (!valid_shared_clock(state))
        return kTASStatusMalformed;
    status = TASSelectI2SClock(configuration, rate, &prepared.clock);
    if (status != kTASStatusOK)
        return status;
    live = state->activeMask != 0UL && state->activeRate != rate;
    if (live && ((state->quiescedMask & state->activeMask) !=
        state->activeMask || !state->outputsMuted))
        return kTASStatusConflict;
    prepared.generation = state->generation;
    prepared.activeRate = state->activeRate;
    prepared.activeMask = state->activeMask;
    *transition = prepared;
    return kTASStatusOK;
}

TASStatus TASBuildI2SStopPlan(const TASSharedClock *state,
    const TASI2STransition *transition, unsigned long stopDeadline,
    TASI2SRegisterPlan *plan)
{
    TASI2SRegisterPlan built;
    if (state == 0 || transition == 0 || plan == 0 ||
        stopDeadline == 0UL)
        return kTASStatusMalformed;
    if (!valid_transition(state, transition))
        return kTASStatusConflict;
    memset(&built, 0, sizeof(built));
    plan_step(&built, kTASI2SRequestClockStop, 0UL);
    plan_step(&built, kTASI2SAwaitClockStopped, stopDeadline);
    *plan = built;
    return kTASStatusOK;
}

TASStatus TASObserveI2SClockStopped(const TASSharedClock *state,
    const TASI2STransition *transition, int clocksStopped,
    TASI2SStoppedToken *stopped)
{
    TASI2SStoppedToken observed;
    if (state == 0 || transition == 0 || stopped == 0 ||
        (clocksStopped != 0 && clocksStopped != 1))
        return kTASStatusMalformed;
    if (!valid_transition(state, transition))
        return kTASStatusConflict;
    if (!clocksStopped)
        return kTASStatusTimeout;
    observed.transition = *transition;
    observed.observedStopped = 1;
    *stopped = observed;
    return kTASStatusOK;
}

TASStatus TASBuildI2SFormatPlan(const TASSharedClock *state,
    const TASI2SStoppedToken *stopped, TASI2SRegisterPlan *plan)
{
    TASI2SRegisterPlan built;
    if (state == 0 || stopped == 0 || plan == 0 ||
        stopped->observedStopped != 1)
        return kTASStatusMalformed;
    if (!valid_transition(state, &stopped->transition))
        return kTASStatusConflict;
    memset(&built, 0, sizeof(built));
    plan_step(&built, kTASI2SSetCellClockHeld, 0UL);
    plan_format(&built, &stopped->transition.clock);
    plan_step(&built, kTASI2SWriteDataWord,
        stopped->transition.clock.dataWord);
    plan_step(&built, kTASI2SBarrier, 0UL);
    plan_step(&built, kTASI2SSetCellRunning, 0UL);
    *plan = built;
    return kTASStatusOK;
}
