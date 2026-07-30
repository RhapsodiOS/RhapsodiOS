#include "TASCore.h"

#include <string.h>

#define TAS_CELL_MAX 0xffffffffUL
#define TAS_KEYLARGO_WINDOW 0x00100000UL
#define TAS_DISCOVERY_LIMIT 16UL

typedef struct {
    TASNode macIO;
    TASNode i2s;
    TASNode soundBus;
    TASNode soundChip;
    TASNode codec;
    TASCodecKind kind;
    const char *compatible;
} TASCandidate;

static unsigned long be32(const unsigned char *bytes)
{
    return ((unsigned long)bytes[0] << 24) |
        ((unsigned long)bytes[1] << 16) |
        ((unsigned long)bytes[2] << 8) | (unsigned long)bytes[3];
}

static int property(const TASPropertyReader *reader, TASNode node,
    const char *name, const unsigned char **bytes, unsigned long *length)
{
    return reader->getProperty(reader->context, node, name, bytes, length);
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
    unsigned long length;
    if (property(reader, node, first, bytes, &length)) {
        if (length != count * 4UL)
            return kTASStatusMalformed;
        return kTASStatusOK;
    }
    return exact_cells(reader, node, second, count, bytes);
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
        count = reader->findNodes(reader->context, names[index], nodes,
            TAS_DISCOVERY_LIMIT);
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
    TASStatus soundStatus;
    TASStatus status;
    int haveRef;
    soundStatus = compatible_kind(reader, soundChip, &soundKind,
        &soundCompatible);
    if (soundStatus != kTASStatusOK &&
        soundStatus != kTASStatusNotMatched)
        return soundStatus;
    status = resolve_ref(reader, soundBus, &codec, &haveRef);
    if (status != kTASStatusOK)
        return status;
    if (!haveRef) {
        status = resolve_ref(reader, soundChip, &codec, &haveRef);
        if (status != kTASStatusOK)
            return status;
    }
    if (haveRef) {
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
    if (status != kTASStatusOK)
        return status;
    if (soundKind != refKind)
        return kTASStatusConflict;
    candidate->codec = codec;
    candidate->kind = soundKind;
    candidate->compatible = soundCompatible;
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
    controllerCount = reader->findNodes(reader->context, "i2s", controllers,
        TAS_DISCOVERY_LIMIT);
    soundCount = reader->findNodes(reader->context, "sound", sounds,
        TAS_DISCOVERY_LIMIT);
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
    count = reader->findNodes(reader->context, "i2c", i2cNodes,
        TAS_DISCOVERY_LIMIT);
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

static TASStatus resolve_gpio_role(const TASPropertyReader *reader,
    TASNode soundBus, TASNode soundChip, const char *primary,
    const char *primaryAlias, const char *legacy, TASNode *node, int *present)
{
    TASNode nodes[2];
    const unsigned char *bytes;
    unsigned long length;
    unsigned long count;
    TASNode owner;
    owner = soundBus;
    *present = 0;
    if (!property(reader, owner, primary, &bytes, &length) &&
        (primaryAlias == 0 ||
        !property(reader, owner, primaryAlias, &bytes, &length))) {
        owner = soundChip;
        if (!property(reader, owner, primary, &bytes, &length) &&
            (primaryAlias == 0 ||
            !property(reader, owner, primaryAlias, &bytes, &length))) {
            count = reader->findPropertyNodes(reader->context, "audio-gpio",
                legacy, nodes, 2);
            if (count == 0)
                return kTASStatusOK;
            if (count != 1UL)
                return kTASStatusAmbiguous;
            *node = nodes[0];
            *present = 1;
            return kTASStatusOK;
        }
    }
    *present = 1;
    if (length != 4UL)
        return kTASStatusMalformed;
    count = reader->resolvePhandle(reader->context, be32(bytes), node);
    if (count == 0)
        return kTASStatusUnresolved;
    if (count != 1UL)
        return kTASStatusAmbiguous;
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
    status = resolve_gpio_role(reader, candidate->soundBus,
        candidate->soundChip, primary, primaryAlias, legacy, &node, &present);
    if (status != kTASStatusOK)
        return status;
    if (!present)
        return kTASStatusMissing;
    return parse_gpio(reader, candidate->macIO, node, 0, gpio);
}

static TASStatus parse_route(const TASPropertyReader *reader,
    const TASCandidate *candidate, TASRouteKind kind,
    TASRouteDescriptor *route)
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
    status = resolve_gpio_role(reader, candidate->soundBus,
        candidate->soundChip, mutePrimary[kind], 0, muteLegacy[kind],
        &muteNode, &haveMute);
    if (status != kTASStatusOK)
        return status;
    status = resolve_gpio_role(reader, candidate->soundBus,
        candidate->soundChip, detectPrimary[kind], 0, detectLegacy[kind],
        &detectNode, &haveDetect);
    if (status != kTASStatusOK)
        return status;
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
    config->rateCount = length / 4UL;
    for (index = 0; index < config->rateCount; ++index) {
        config->rates[index] = be32(bytes + index * 4UL);
        if (config->rates[index] == 0)
            return kTASStatusMalformed;
    }
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
    status = parse_codec_transport(reader, candidate, config);
    if (status != kTASStatusOK)
        return status;
    status = parse_required_gpio(reader, candidate, "platform-hw-reset", 0,
        "audio-hw-reset", &config->hardwareReset);
    if (status != kTASStatusOK)
        return status;
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
            &config->routes[route]);
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
        reader->findNodes == 0 || reader->findPropertyNodes == 0 ||
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
