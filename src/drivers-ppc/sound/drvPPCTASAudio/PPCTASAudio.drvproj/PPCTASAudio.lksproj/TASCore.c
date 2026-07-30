#include "TASCore.h"
#include "TASTime.h"

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
            (reader->candidateNode != 0UL &&
            controller != reader->candidateNode) ||
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
        transition->activeMask != state->activeMask ||
        transition->noOp != (state->activeMask != 0UL &&
        state->activeRate == transition->clock.rate))
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
    prepared.generation = state->generation;
    prepared.activeRate = state->activeRate;
    prepared.activeMask = state->activeMask;
    prepared.noOp = state->activeMask != 0UL && state->activeRate == rate;
    if (state->generation == ~0UL && !prepared.noOp)
        return kTASStatusOverflow;
    live = state->activeMask != 0UL && state->activeRate != rate;
    if (live && ((state->quiescedMask & state->activeMask) !=
        state->activeMask || !state->outputsMuted))
        return kTASStatusConflict;
    *transition = prepared;
    return kTASStatusOK;
}

TASStatus TASBuildI2SStopPlan(const TASSharedClock *state,
    const TASI2STransition *transition, unsigned long stopDeadline,
    TASI2SRegisterPlan *plan)
{
    TASI2SRegisterPlan built;
    if (state == 0 || transition == 0 || plan == 0)
        return kTASStatusMalformed;
    if (!valid_transition(state, transition))
        return kTASStatusConflict;
    memset(&built, 0, sizeof(built));
    if (transition->noOp) {
        *plan = built;
        return kTASStatusOK;
    }
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
    if (transition->noOp)
        return kTASStatusMalformed;
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
    if (stopped->transition.noOp) {
        *plan = built;
        return kTASStatusOK;
    }
    plan_step(&built, kTASI2SSetCellClockHeld, 0UL);
    plan_format(&built, &stopped->transition.clock);
    plan_step(&built, kTASI2SWriteDataWord,
        stopped->transition.clock.dataWord);
    plan_step(&built, kTASI2SBarrier, 0UL);
    plan_step(&built, kTASI2SSetCellRunning, 0UL);
    *plan = built;
    return kTASStatusOK;
}

TASStatus TASCommitI2STransition(TASSharedClock *state,
    TASI2SStoppedToken *stopped)
{
    TASSharedClock committed;
    TASI2SStoppedToken consumed;
    if (state == 0 || stopped == 0 || stopped->observedStopped != 1)
        return kTASStatusMalformed;
    if (!valid_transition(state, &stopped->transition))
        return kTASStatusConflict;
    if (stopped->transition.noOp)
        return kTASStatusMalformed;
    committed = *state;
    if (advance_generation(&committed) != kTASStatusOK)
        return kTASStatusOverflow;
    if (committed.activeMask != 0UL)
        committed.activeRate = stopped->transition.clock.rate;
    memset(&consumed, 0, sizeof(consumed));
    *state = committed;
    *stopped = consumed;
    return kTASStatusOK;
}

static int valid_audio_controls(const TASAudioDesiredControls *controls)
{
    return controls != 0 && controls->rate != 0UL &&
        controls->leftVolume <= 0xffffffUL &&
        controls->rightVolume <= 0xffffffUL &&
        controls->inputGain <= 0xffffffUL && controls->inputSource <= 2UL &&
        (controls->userMuted == 0 || controls->userMuted == 1);
}

static int valid_audio_state(const TASAudioState *state)
{
    unsigned long allRoutes;
    allRoutes = kTASAudioRouteSpeaker | kTASAudioRouteHeadphone |
        kTASAudioRouteLineOut;
    return state != 0 && state->generation != 0UL &&
        state->detectGeneration != 0UL &&
        (state->availableRoutes & ~allRoutes) == 0UL &&
        (state->currentRoutes & ~state->availableRoutes) == 0UL &&
        valid_audio_controls(&state->desired) &&
        state->powerState >= kTASPowerReady &&
        state->powerState <= kTASPowerFault;
}

static void audio_plan_init(TASAudioActionPlan *plan)
{
    memset(plan, 0, sizeof(*plan));
}

static TASStatus audio_action(TASAudioActionPlan *plan,
    TASAudioActionOperation operation, unsigned long value,
    unsigned long deadline)
{
    TASAudioAction *action;
    if (plan->count >= TAS_AUDIO_ACTION_MAX)
        return kTASStatusOverflow;
    action = &plan->actions[plan->count++];
    memset(action, 0, sizeof(*action));
    action->operation = operation;
    action->value = value;
    action->deadline = deadline;
    return kTASStatusOK;
}

static TASStatus audio_mute_all(const TASAudioState *state,
    TASAudioActionPlan *plan)
{
    TASStatus status;
    if ((state->quirks & kTASQuirkANDedReset) != 0UL)
        return audio_action(plan, kTASAudioAssertAndedReset, 1UL, 0UL);
    if ((state->availableRoutes & kTASAudioRouteSpeaker) != 0UL) {
        status = audio_action(plan, kTASAudioMuteSpeaker, 1UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    if ((state->availableRoutes & kTASAudioRouteHeadphone) != 0UL) {
        status = audio_action(plan, kTASAudioMuteHeadphone, 1UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    if ((state->availableRoutes & kTASAudioRouteLineOut) != 0UL) {
        status = audio_action(plan, kTASAudioMuteLineOut, 1UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    return kTASStatusOK;
}

static unsigned long audio_normalize_detects(const TASAudioState *state,
    unsigned long detects)
{
    unsigned long normalized;
    normalized = 0UL;
    if ((state->availableRoutes & kTASAudioRouteHeadphone) != 0UL &&
        (detects & 1UL) != 0UL)
        normalized |= 1UL;
    if ((state->availableRoutes & kTASAudioRouteLineOut) != 0UL &&
        (detects & 2UL) != 0UL)
        normalized |= 2UL;
    return normalized;
}

static unsigned long audio_target_routes(const TASAudioState *state,
    unsigned long detects)
{
    unsigned long routes;
    if (state->desired.userMuted)
        return 0UL;
    routes = 0UL;
    if ((detects & 1UL) != 0UL)
        routes |= kTASAudioRouteHeadphone;
    if ((detects & 2UL) != 0UL)
        routes |= kTASAudioRouteLineOut;
    if (routes == 0UL &&
        (state->availableRoutes & kTASAudioRouteSpeaker) != 0UL)
        routes = kTASAudioRouteSpeaker;
    return routes & state->availableRoutes;
}

static TASStatus audio_reserve(TASAudioState *state, TASAudioTokenKind kind,
    TASAudioToken *token)
{
    if (state->transitionBlocked || state->generation == ~0UL) {
        state->transitionBlocked = 1;
        return kTASStatusOverflow;
    }
    if (state->transitionPending)
        return kTASStatusConflict;
    ++state->generation;
    state->transitionPending = 1;
    memset(token, 0, sizeof(*token));
    token->kind = kind;
    token->generation = state->generation;
    token->detectGeneration = state->detectGeneration;
    token->sourceDetectGeneration = state->detectGeneration;
    token->sourceDesiredDetects = state->desiredDetects;
    token->sourceDebounceDeadline = state->debounceDeadline;
    token->sourceCandidateDetects = state->candidateDetects;
    token->sourcePower = state->powerState;
    token->sourceStartsBlocked = state->startsBlocked;
    token->sourceDebouncePending = state->debouncePending;
    token->sourceDebounceScheduled = state->debounceScheduled;
    token->sourceCandidateValid = state->candidateValid;
    token->sourceDetectBlocked = state->detectBlocked;
    return kTASStatusOK;
}

TASStatus TASAudioStateInit(TASAudioState *state, unsigned long routes,
    TASCodecKind codec, unsigned long quirks,
    const TASAudioDesiredControls *controls)
{
    unsigned long allRoutes;
    allRoutes = kTASAudioRouteSpeaker | kTASAudioRouteHeadphone |
        kTASAudioRouteLineOut;
    if (state == 0 || !valid_audio_controls(controls) ||
        (routes & ~allRoutes) != 0UL || routes == 0UL ||
        (codec != kTASCodecTAS3001C && codec != kTASCodecTAS3004) ||
        (quirks & ~((unsigned long)kTASQuirkANDedReset)) != 0UL)
        return kTASStatusMalformed;
    if ((quirks & kTASQuirkANDedReset) != 0UL &&
        (routes & kTASAudioRouteLineOut) != 0UL)
        return kTASStatusUnsupported;
    memset(state, 0, sizeof(*state));
    state->desired = *controls;
    state->availableRoutes = routes;
    state->codecKind = codec;
    state->quirks = quirks;
    state->generation = 1UL;
    state->detectGeneration = 1UL;
    state->powerState = kTASPowerReady;
    state->outputsMuted = 1;
    return kTASStatusOK;
}

TASStatus TASAudioSetDesiredControls(TASAudioState *state,
    const TASAudioDesiredControls *controls)
{
    if (!valid_audio_state(state) || !valid_audio_controls(controls))
        return kTASStatusMalformed;
    if (state->transitionPending || state->powerState == kTASPowerWaking)
        return kTASStatusConflict;
    if (state->transitionBlocked || state->generation == ~0UL) {
        state->transitionBlocked = 1;
        return kTASStatusOverflow;
    }
    state->desired = *controls;
    ++state->generation;
    return kTASStatusOK;
}

static TASStatus audio_build_route(const TASAudioState *state,
    unsigned long target, TASAudioActionPlan *plan)
{
    TASStatus status;
    audio_plan_init(plan);
    status = audio_mute_all(state, plan);
    if (status != kTASStatusOK) return status;
    if ((state->quirks & kTASQuirkANDedReset) != 0UL && target != 0UL) {
        status = audio_action(plan, kTASAudioReleaseAndedReset, 0UL, 0UL);
        if (status != kTASStatusOK) return status;
        status = audio_action(plan, kTASAudioCodecReset, 1UL, 0UL);
        if (status != kTASStatusOK) return status;
        status = audio_action(plan, kTASAudioCodecRestore, 1UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    if (target == 0UL)
        return kTASStatusOK;
    status = audio_action(plan, kTASAudioSetOutputMux, target, 0UL);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioSetCodecRoute, target, 0UL);
    if (status != kTASStatusOK) return status;
    if ((target & kTASAudioRouteSpeaker) != 0UL) {
        status = audio_action(plan, kTASAudioUnmuteSpeaker, 0UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    if ((target & kTASAudioRouteHeadphone) != 0UL) {
        status = audio_action(plan, kTASAudioUnmuteHeadphone, 0UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    if ((target & kTASAudioRouteLineOut) != 0UL)
        return audio_action(plan, kTASAudioUnmuteLineOut, 0UL, 0UL);
    return kTASStatusOK;
}

static TASStatus audio_prepare_route(TASAudioState *state,
    unsigned long detects, int waking, TASAudioActionPlan *plan,
    TASAudioToken *token)
{
    TASStatus status;
    TASAudioActionPlan built;
    unsigned long normalized;
    unsigned long target;
    if (!valid_audio_state(state) || plan == 0 || token == 0)
        return kTASStatusMalformed;
    if ((!waking && (state->powerState != kTASPowerReady ||
        state->startsBlocked)) || (waking &&
        state->powerState != kTASPowerWaking))
        return kTASStatusConflict;
    normalized = audio_normalize_detects(state, detects);
    target = audio_target_routes(state, normalized);
    status = audio_build_route(state, target, &built);
    if (status != kTASStatusOK)
        return status;
    status = audio_reserve(state, waking ? kTASAudioTokenWakeRoute :
        kTASAudioTokenRoute, token);
    if (status != kTASStatusOK)
        return status;
    state->desiredDetects = normalized;
    *plan = built;
    token->targetRoutes = target;
    token->targetPower = kTASPowerReady;
    token->actionCount = plan->count;
    return kTASStatusOK;
}

TASStatus TASAudioPrepareRoute(TASAudioState *state, unsigned long detects,
    TASAudioActionPlan *plan, TASAudioToken *token)
{
    return audio_prepare_route(state, detects, 0, plan, token);
}

TASStatus TASAudioRecordDetectISR(TASAudioState *state,
    unsigned long detects, unsigned long *generation)
{
    if (!valid_audio_state(state) || generation == 0)
        return kTASStatusMalformed;
    if (state->detectBlocked || state->detectGeneration == ~0UL) {
        state->detectBlocked = 1;
        return kTASStatusOverflow;
    }
    ++state->detectGeneration;
    state->desiredDetects = audio_normalize_detects(state, detects);
    state->debouncePending = 1;
    state->debounceScheduled = 0;
    state->debounceDeadline = 0UL;
    state->candidateValid = 0;
    *generation = state->detectGeneration;
    return kTASStatusOK;
}

TASStatus TASAudioBuildDebounceSchedule(TASAudioState *state,
    unsigned long generation, unsigned long deadline,
    TASAudioActionPlan *plan)
{
    if (!valid_audio_state(state) || plan == 0)
        return kTASStatusMalformed;
    if (state->detectBlocked || !state->debouncePending ||
        generation != state->detectGeneration ||
        (state->startsBlocked && state->powerState != kTASPowerWaking) ||
        (state->powerState != kTASPowerReady &&
        state->powerState != kTASPowerWaking))
        return kTASStatusConflict;
    state->debounceDeadline = deadline;
    state->debounceScheduled = 1;
    audio_plan_init(plan);
    return audio_action(plan, kTASAudioScheduleDebounce, generation,
        deadline);
}

TASStatus TASAudioPrepareDebounceSample(TASAudioState *state,
    unsigned long generation, unsigned long now, TASAudioActionPlan *plan,
    TASAudioToken *token)
{
    if (!valid_audio_state(state) || plan == 0 || token == 0)
        return kTASStatusMalformed;
    if (state->detectBlocked || !state->debouncePending ||
        generation != state->detectGeneration ||
        (state->startsBlocked && state->powerState != kTASPowerWaking) ||
        (state->powerState != kTASPowerReady &&
        state->powerState != kTASPowerWaking))
        return kTASStatusConflict;
    if (!state->debounceScheduled ||
        !TASTimeDue(now, state->debounceDeadline))
        return kTASStatusTimeout;
    audio_plan_init(plan);
    if (audio_action(plan, kTASAudioSampleDetects, generation,
        state->debounceDeadline) != kTASStatusOK)
        return kTASStatusOverflow;
    memset(token, 0, sizeof(*token));
    token->kind = kTASAudioTokenDebounce;
    token->detectGeneration = generation;
    token->actionCount = 1UL;
    token->deadline = state->debounceDeadline;
    return kTASStatusOK;
}

TASStatus TASAudioApplyDetectSample(TASAudioState *state,
    const TASAudioToken *sample, unsigned long detects, unsigned long now,
    TASAudioActionPlan *plan, TASAudioToken *token)
{
    TASAudioState changed;
    TASStatus status;
    unsigned long normalized;
    unsigned long deadline;
    TASAudioActionPlan scheduled;
    TASAudioToken empty;
    if (!valid_audio_state(state) || sample == 0 || plan == 0 || token == 0)
        return kTASStatusMalformed;
    if (sample->kind != kTASAudioTokenDebounce ||
        sample->detectGeneration != state->detectGeneration ||
        sample->deadline != state->debounceDeadline ||
        !state->debouncePending)
        return kTASStatusConflict;
    if (!TASTimeDue(now, sample->deadline))
        return kTASStatusTimeout;
    normalized = audio_normalize_detects(state, detects);
    if (!state->candidateValid || state->candidateDetects != normalized) {
        if (!TASTimeAdd(now, TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &deadline) ||
            state->detectGeneration == ~0UL)
            return kTASStatusOverflow;
        changed = *state;
        ++changed.detectGeneration;
        changed.candidateDetects = normalized;
        changed.candidateValid = 1;
        changed.debouncePending = 1;
        changed.debounceScheduled = 1;
        changed.debounceDeadline = deadline;
        audio_plan_init(&scheduled);
        status = audio_action(&scheduled, kTASAudioScheduleDebounce,
            changed.detectGeneration, deadline);
        if (status != kTASStatusOK)
            return status;
        memset(&empty, 0, sizeof(empty));
        *state = changed;
        *plan = scheduled;
        *token = empty;
        return kTASStatusUnresolved;
    }
    changed = *state;
    changed.debouncePending = 0;
    changed.debounceScheduled = 0;
    changed.debounceDeadline = 0UL;
    changed.candidateValid = 0;
    status = audio_prepare_route(&changed, normalized,
        changed.powerState == kTASPowerWaking, plan, token);
    if (status == kTASStatusOK)
        *state = changed;
    return status;
}

static void audio_invalidate_debounce(TASAudioState *state)
{
    state->debouncePending = 0;
    state->debounceScheduled = 0;
    state->debounceDeadline = 0UL;
    state->candidateValid = 0;
    if (state->detectGeneration == ~0UL)
        state->detectBlocked = 1;
    else
        ++state->detectGeneration;
}

static TASStatus audio_build_sleep(TASAudioState *state,
    unsigned long deadline,
    TASAudioActionPlan *plan)
{
    TASStatus status;
    status = audio_action(plan, kTASAudioBlockStarts, 1UL, 0UL);
    if (status != kTASStatusOK) return status;
    status = audio_mute_all(state, plan);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioStopOutputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioResetOutputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioStopInputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioResetInputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    if ((state->quirks & kTASQuirkANDedReset) == 0UL) {
        status = audio_action(plan, state->codecKind == kTASCodecTAS3004 ?
            kTASAudioCodecAnalogLowPower : kTASAudioCodecMuteLowPower,
            1UL, deadline);
        if (status != kTASStatusOK) return status;
    }
    status = audio_action(plan, kTASAudioDisableDetectIRQs, 1UL, 0UL);
    if (status != kTASStatusOK) return status;
    if ((state->quirks & kTASQuirkANDedReset) == 0UL) {
        status = audio_action(plan, kTASAudioAssertReset, 1UL, 0UL);
        if (status != kTASStatusOK) return status;
    }
    return audio_action(plan, kTASAudioGateI2SCell, 1UL, 0UL);
}

static TASStatus audio_build_wake(TASAudioState *state,
    unsigned long deadline,
    TASAudioActionPlan *plan)
{
    TASAudioAction *volume;
    TASStatus status;
    if ((state->quirks & kTASQuirkANDedReset) == 0UL) {
        status = audio_mute_all(state, plan);
        if (status != kTASStatusOK) return status;
    }
    status = audio_action(plan, kTASAudioEnableI2SCellClock, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    if ((state->quirks & kTASQuirkANDedReset) != 0UL) {
        status = audio_action(plan, kTASAudioReleaseAndedReset, 0UL, 0UL);
    } else
        status = audio_action(plan, kTASAudioReleaseReset, 0UL, 0UL);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioApplyI2SRate,
        state->desired.rate, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioCodecReset, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioCodecRestore, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioRebuildOutputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioRebuildInputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioEnableDetectIRQs, 1UL, 0UL);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioScheduleDebounce,
        state->detectGeneration, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioRestoreVolume,
        state->desired.leftVolume, deadline);
    if (status != kTASStatusOK) return status;
    volume = &plan->actions[plan->count - 1UL];
    volume->value2 = state->desired.rightVolume;
    status = audio_action(plan, kTASAudioRestoreInputSource,
        state->desired.inputSource, deadline);
    if (status != kTASStatusOK) return status;
    return audio_action(plan, kTASAudioRestoreInputGain,
        state->desired.inputGain, deadline);
}

TASStatus TASAudioPreparePower(TASAudioState *state, TASPowerState power,
    unsigned long deadline, TASAudioActionPlan *plan, TASAudioToken *token)
{
    TASStatus status;
    TASAudioState changed;
    TASAudioActionPlan built;
    if (!valid_audio_state(state) || plan == 0 || token == 0 ||
        power < kTASPowerReady ||
        power > kTASPowerOff)
        return kTASStatusMalformed;
    if ((power == kTASPowerReady) ==
        (state->powerState == kTASPowerReady))
        return kTASStatusConflict;
    if (state->powerState == kTASPowerWaking)
        return kTASStatusConflict;
    if (state->rollbackPending)
        return kTASStatusConflict;
    changed = *state;
    changed.startsBlocked = 1;
    if (power == kTASPowerReady)
        changed.powerState = kTASPowerWaking;
    changed.transitionDeadline = deadline;
    audio_invalidate_debounce(&changed);
    audio_plan_init(&built);
    if (power == kTASPowerReady)
        status = audio_build_wake(&changed, deadline, &built);
    else
        status = audio_build_sleep(&changed, deadline, &built);
    if (status != kTASStatusOK)
        return status;
    status = audio_reserve(&changed, kTASAudioTokenPower, token);
    if (status != kTASStatusOK)
        return status;
    token->sourceDetectGeneration = state->detectGeneration;
    token->sourceDesiredDetects = state->desiredDetects;
    token->sourceDebounceDeadline = state->debounceDeadline;
    token->sourceCandidateDetects = state->candidateDetects;
    token->sourcePower = state->powerState;
    token->sourceStartsBlocked = state->startsBlocked;
    token->sourceDebouncePending = state->debouncePending;
    token->sourceDebounceScheduled = state->debounceScheduled;
    token->sourceCandidateValid = state->candidateValid;
    token->sourceDetectBlocked = state->detectBlocked;
    token->targetRoutes = 0UL;
    token->targetPower = power;
    token->actionCount = built.count;
    token->deadline = deadline;
    if (power == kTASPowerReady) {
        changed.debouncePending = 1;
        changed.debounceScheduled = 1;
        changed.debounceDeadline = deadline;
    }
    *state = changed;
    *plan = built;
    return kTASStatusOK;
}

static int audio_token_current(const TASAudioState *state,
    const TASAudioToken *token, int allowDetectChange)
{
    return state->transitionPending && token->generation == state->generation &&
        token->deadline == state->transitionDeadline &&
        token->kind != kTASAudioTokenNone &&
        (allowDetectChange || token->kind == kTASAudioTokenRollback ||
        token->detectGeneration == state->detectGeneration);
}

TASStatus TASAudioAuthorizeAction(const TASAudioState *state,
    TASAudioToken *token, unsigned long index)
{
    if (!valid_audio_state(state) || token == 0)
        return kTASStatusMalformed;
    if (!audio_token_current(state, token, 0) || token->actionInFlight ||
        index != token->nextAction || index >= token->actionCount)
        return kTASStatusConflict;
    token->actionInFlight = 1;
    return kTASStatusOK;
}

TASStatus TASAudioCompleteAction(const TASAudioState *state,
    TASAudioToken *token, unsigned long index)
{
    if (!valid_audio_state(state) || token == 0)
        return kTASStatusMalformed;
    if (!audio_token_current(state, token, 0) || !token->actionInFlight ||
        index != token->nextAction || index >= token->actionCount)
        return kTASStatusConflict;
    token->actionInFlight = 0;
    ++token->nextAction;
    ++token->completedCount;
    return kTASStatusOK;
}

static int audio_token_complete(const TASAudioState *state,
    const TASAudioToken *token)
{
    return audio_token_current(state, token, 0) && !token->actionInFlight &&
        token->nextAction == token->actionCount &&
        token->completedCount == token->actionCount;
}

TASStatus TASAudioCommitTransition(TASAudioState *state,
    TASAudioToken *token)
{
    TASAudioToken consumed;
    if (!valid_audio_state(state) || token == 0)
        return kTASStatusMalformed;
    if (!audio_token_complete(state, token))
        return kTASStatusConflict;
    if (token->kind == kTASAudioTokenRoute ||
        token->kind == kTASAudioTokenWakeRoute) {
        state->currentRoutes = token->targetRoutes;
        state->routeValid = 1;
        state->hardwareValid = 1;
        state->outputsMuted = token->targetRoutes == 0UL;
        state->outputsMuteKnown = 1;
        if ((state->quirks & kTASQuirkANDedReset) != 0UL)
            state->andedResetState = token->targetRoutes == 0UL ?
                kTASAndedResetAsserted : kTASAndedResetReleased;
        if (token->kind == kTASAudioTokenWakeRoute) {
            state->powerState = kTASPowerReady;
            state->startsBlocked = 0;
        }
    } else if (token->kind == kTASAudioTokenPower) {
        state->streamsRunning = 0;
        state->dmaStoppedKnown = 1;
        state->currentRoutes = 0UL;
        state->routeValid = 0;
        state->outputsMuted = 1;
        state->outputsMuteKnown = 1;
        if ((state->quirks & kTASQuirkANDedReset) != 0UL)
            state->andedResetState = token->targetPower == kTASPowerReady ?
                kTASAndedResetReleased : kTASAndedResetAsserted;
        if (token->targetPower == kTASPowerReady) {
            state->powerState = kTASPowerWaking;
            state->hardwareValid = 1;
            state->startsBlocked = 1;
        } else {
            state->powerState = token->targetPower;
            state->hardwareValid = 0;
            state->startsBlocked = 1;
        }
    } else
        return kTASStatusMalformed;
    state->transitionPending = 0;
    state->transitionDeadline = 0UL;
    memset(&consumed, 0, sizeof(consumed));
    *token = consumed;
    return kTASStatusOK;
}

TASStatus TASAudioCancelTransition(TASAudioState *state,
    TASAudioToken *token)
{
    TASAudioToken consumed;
    int detectUnchanged;
    if (!valid_audio_state(state) || token == 0)
        return kTASStatusMalformed;
    if (!audio_token_current(state, token, 1) ||
        token->kind == kTASAudioTokenRollback || token->actionInFlight ||
        token->nextAction != 0UL || token->completedCount != 0UL)
        return kTASStatusConflict;
    if (token->kind == kTASAudioTokenWakeRoute &&
        (token->detectGeneration == state->detectGeneration ||
        !state->debouncePending ||
        state->powerState != kTASPowerWaking || !state->startsBlocked))
        return kTASStatusConflict;
    if (state->generation == ~0UL)
        return kTASStatusOverflow;
    detectUnchanged = token->detectGeneration == state->detectGeneration;
    if (token->kind == kTASAudioTokenPower) {
        state->powerState = token->sourcePower;
        state->startsBlocked = token->sourceStartsBlocked;
        if (detectUnchanged) {
            state->detectGeneration = token->sourceDetectGeneration;
            state->debouncePending = token->sourceDebouncePending;
            state->debounceScheduled = token->sourceDebounceScheduled;
            state->debounceDeadline = token->sourceDebounceDeadline;
            state->candidateValid = token->sourceCandidateValid;
            state->candidateDetects = token->sourceCandidateDetects;
            state->detectBlocked = token->sourceDetectBlocked;
        }
    }
    if (detectUnchanged)
        state->desiredDetects = token->sourceDesiredDetects;
    ++state->generation;
    state->transitionPending = 0;
    state->transitionDeadline = 0UL;
    memset(&consumed, 0, sizeof(consumed));
    *token = consumed;
    return kTASStatusOK;
}

static TASStatus audio_build_rollback(const TASAudioState *state,
    unsigned long deadline, TASAudioActionPlan *plan)
{
    TASStatus status;
    audio_plan_init(plan);
    status = audio_mute_all(state, plan);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioStopOutputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioResetOutputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    status = audio_action(plan, kTASAudioStopInputDMA, 0UL, deadline);
    if (status != kTASStatusOK) return status;
    return audio_action(plan, kTASAudioResetInputDMA, 0UL, deadline);
}

static TASStatus audio_start_rollback(TASAudioState *state,
    unsigned long deadline, TASAudioActionPlan *plan, TASAudioToken *token)
{
    TASAudioActionPlan built;
    TASAudioState changed;
    TASStatus status;
    if (state->generation == ~0UL)
        return kTASStatusOverflow;
    status = audio_build_rollback(state, deadline, &built);
    if (status != kTASStatusOK)
        return status;
    changed = *state;
    ++changed.generation;
    changed.transitionPending = 1;
    changed.transitionDeadline = deadline;
    changed.rollbackPending = 1;
    changed.powerState = kTASPowerFault;
    changed.startsBlocked = 1;
    changed.currentRoutes = 0UL;
    changed.routeValid = 0;
    changed.hardwareValid = 0;
    changed.outputsMuteKnown = 0;
    changed.dmaStoppedKnown = 0;
    changed.andedResetState = kTASAndedResetUnknown;
    memset(token, 0, sizeof(*token));
    token->kind = kTASAudioTokenRollback;
    token->generation = changed.generation;
    token->detectGeneration = changed.detectGeneration;
    token->deadline = deadline;
    token->actionCount = built.count;
    *state = changed;
    *plan = built;
    return kTASStatusOK;
}

TASStatus TASAudioFailTransition(TASAudioState *state, TASAudioToken *failed,
    unsigned long cleanupDeadline, TASAudioActionPlan *plan,
    TASAudioToken *rollback)
{
    TASAudioToken consumed;
    TASAudioState changed;
    TASStatus status;
    if (!valid_audio_state(state) || failed == 0 || plan == 0 ||
        rollback == 0)
        return kTASStatusMalformed;
    if (!audio_token_current(state, failed, 1) ||
        failed->kind == kTASAudioTokenRollback ||
        (!failed->actionInFlight && failed->completedCount == 0UL))
        return kTASStatusConflict;
    changed = *state;
    changed.transitionPending = 0;
    changed.transitionDeadline = 0UL;
    if (failed->detectGeneration == changed.detectGeneration) {
        changed.debouncePending = 0;
        changed.debounceScheduled = 0;
        changed.debounceDeadline = 0UL;
        changed.candidateValid = 0;
    }
    status = audio_start_rollback(&changed, cleanupDeadline, plan, rollback);
    if (status != kTASStatusOK)
        return status;
    *state = changed;
    memset(&consumed, 0, sizeof(consumed));
    *failed = consumed;
    return kTASStatusOK;
}

TASStatus TASAudioPrepareRollback(TASAudioState *state,
    unsigned long deadline, TASAudioActionPlan *plan, TASAudioToken *token)
{
    if (!valid_audio_state(state) || plan == 0 || token == 0)
        return kTASStatusMalformed;
    if (!state->rollbackPending || state->transitionPending ||
        state->powerState != kTASPowerFault)
        return kTASStatusConflict;
    return audio_start_rollback(state, deadline, plan, token);
}

TASStatus TASAudioCommitRollback(TASAudioState *state, TASAudioToken *token)
{
    TASAudioToken consumed;
    if (!valid_audio_state(state) || token == 0)
        return kTASStatusMalformed;
    if (token->kind != kTASAudioTokenRollback ||
        !audio_token_complete(state, token))
        return kTASStatusConflict;
    state->outputsMuted = 1;
    state->outputsMuteKnown = 1;
    state->streamsRunning = 0;
    state->dmaStoppedKnown = 1;
    state->rollbackPending = 0;
    state->transitionPending = 0;
    state->transitionDeadline = 0UL;
    if ((state->quirks & kTASQuirkANDedReset) != 0UL)
        state->andedResetState = kTASAndedResetAsserted;
    memset(&consumed, 0, sizeof(consumed));
    *token = consumed;
    return kTASStatusOK;
}

TASStatus TASAudioAbortRollback(TASAudioState *state, TASAudioToken *token)
{
    TASAudioToken consumed;
    if (!valid_audio_state(state) || token == 0)
        return kTASStatusMalformed;
    if (token->kind != kTASAudioTokenRollback ||
        !audio_token_current(state, token, 1))
        return kTASStatusConflict;
    state->transitionPending = 0;
    state->transitionDeadline = 0UL;
    state->rollbackPending = 1;
    state->outputsMuteKnown = 0;
    state->dmaStoppedKnown = 0;
    memset(&consumed, 0, sizeof(consumed));
    *token = consumed;
    return kTASStatusOK;
}
