#include "TASCore.h"

#include <string.h>

#define TAS_CELL_MAX 0xffffffffUL

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

static TASStatus resolve_property(const TASPropertyReader *reader,
    TASNode owner, const char *name, TASNode *node, int *present)
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long count;
    *present = 0;
    if (!property(reader, owner, name, &bytes, &length))
        return kTASStatusOK;
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

static TASStatus parse_gpio(const TASPropertyReader *reader, TASNode node,
    int needsIRQ, TASGPIODescriptor *gpio)
{
    const unsigned char *bytes;
    TASStatus status;
    status = exact_cells(reader, node, "reg", 2, &bytes);
    if (status != kTASStatusOK)
        return status;
    gpio->address = be32(bytes);
    gpio->mask = be32(bytes + 4);
    if (gpio->mask == 0)
        return kTASStatusMalformed;
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

static TASStatus old_gpio(const TASPropertyReader *reader, const char *path,
    const char *expected, TASNode *node, int *present)
{
    const unsigned char *bytes;
    unsigned long length;
    TASStatus status;
    *present = 0;
    if (!reader->findNode(reader->context, path, node))
        return kTASStatusOK;
    status = string_property(reader, *node, "audio-gpio", &bytes, &length, 0);
    if (status != kTASStatusOK)
        return status;
    if (!property(reader, *node, "audio-gpio", &bytes, &length))
        return kTASStatusOK;
    if (strcmp((const char *)bytes, expected) != 0)
        return kTASStatusMalformed;
    *present = 1;
    return kTASStatusOK;
}

static TASStatus parse_route(const TASPropertyReader *reader, TASNode sound,
    TASRouteKind kind, TASRouteDescriptor *route)
{
    static const char *muteNames[kTASRouteCount] = {
        "platform-headphone-mute", "platform-speaker-mute",
        "platform-lineout-mute"
    };
    static const char *detectNames[kTASRouteCount] = {
        "platform-headphone-detect", "platform-speaker-detect",
        "platform-lineout-detect"
    };
    static const char *mutePaths[kTASRouteCount] = {
        "/mac-io/gpio/headphone-mute", "/mac-io/gpio/speaker-mute",
        "/mac-io/gpio/lineout-mute"
    };
    static const char *detectPaths[kTASRouteCount] = {
        "/mac-io/gpio/headphone-detect", "/mac-io/gpio/speaker-detect",
        "/mac-io/gpio/lineout-detect"
    };
    static const char *oldMuteNames[kTASRouteCount] = {
        "headphone-mute", "speaker-mute", "lineout-mute"
    };
    static const char *oldDetectNames[kTASRouteCount] = {
        "headphone-detect", "speaker-detect", "lineout-detect"
    };
    TASNode muteNode;
    TASNode detectNode;
    int haveMute;
    int haveDetect;
    TASStatus status;
    status = resolve_property(reader, sound, muteNames[kind], &muteNode,
        &haveMute);
    if (status != kTASStatusOK)
        return status;
    if (!haveMute) {
        status = old_gpio(reader, mutePaths[kind], oldMuteNames[kind],
            &muteNode, &haveMute);
        if (status != kTASStatusOK)
            return status;
    }
    status = resolve_property(reader, sound, detectNames[kind], &detectNode,
        &haveDetect);
    if (status != kTASStatusOK)
        return status;
    if (!haveDetect) {
        status = old_gpio(reader, detectPaths[kind], oldDetectNames[kind],
            &detectNode, &haveDetect);
        if (status != kTASStatusOK)
            return status;
    }
    if (!haveMute && !haveDetect) {
        route->present = 0;
        return kTASStatusOK;
    }
    if (!haveMute || !haveDetect)
        return kTASStatusMissing;
    status = parse_gpio(reader, muteNode, 0, &route->mute);
    if (status != kTASStatusOK)
        return status;
    status = parse_gpio(reader, detectNode, 1, &route->detect);
    if (status != kTASStatusOK)
        return status;
    route->present = 1;
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

static TASStatus parse_codec(const TASPropertyReader *reader, TASNode sound,
    TASMachineConfig *config)
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long primary;
    unsigned long second;
    TASNode codec;
    TASNode bus;
    TASStatus status;
    int present;
    status = resolve_property(reader, sound, "platform-tas-codec-ref",
        &codec, &present);
    if (status != kTASStatusOK)
        return status;
    if (!present && !reader->findNode(reader->context, "/mac-io/i2c/deq",
        &codec))
        return kTASStatusMissing;
    status = exact_cells(reader, codec, "reg", 1, &bytes);
    if (status != kTASStatusOK)
        return status;
    status = normalized_i2c(be32(bytes), &primary);
    if (status != kTASStatusOK)
        return status;
    if (property(reader, codec, "i2c-address", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
        status = normalized_i2c(be32(bytes), &second);
        if (status != kTASStatusOK)
            return status;
        if (primary != second)
            return kTASStatusConflict;
    }
    config->i2cAddress = primary;
    if (!reader->getParent(reader->context, codec, &bus))
        return kTASStatusMissing;
    if (property(reader, bus, "AAPL,i2c-port-select", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
    } else {
        status = exact_cells(reader, bus, "reg", 1, &bytes);
        if (status != kTASStatusOK)
            return status;
    }
    config->i2cPort = be32(bytes);
    if (config->i2cPort > 15UL)
        return kTASStatusMalformed;
    return kTASStatusOK;
}

static TASStatus parse_policy(const TASPropertyReader *reader, TASNode sound,
    TASMachineConfig *config)
{
    const unsigned char *bytes;
    unsigned long length;
    unsigned long index;
    TASStatus status;
    status = string_property(reader, sound, "model", &bytes, &length, 0);
    if (status != kTASStatusOK)
        return status;
    if (property(reader, sound, "model", &bytes, &length)) {
        if (length > TAS_MODEL_LENGTH)
            return kTASStatusMalformed;
        memcpy(config->model, bytes, (size_t)length);
    }
    if (property(reader, sound, "layout-id", &bytes, &length)) {
        if (length != 4UL)
            return kTASStatusMalformed;
        config->layoutID = be32(bytes);
    }
    if (!property(reader, sound, "sample-rates", &bytes, &length))
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
    if (property(reader, sound, "platform-anded-reset", &bytes, &length)) {
        if (length != 0)
            return kTASStatusMalformed;
        config->quirks = kTASQuirkANDedReset;
    }
    return kTASStatusOK;
}

static TASStatus parse_machine_config(const TASPropertyReader *reader,
    TASMachineConfig *configuration)
{
    const unsigned char *bytes;
    unsigned long length;
    TASNode i2s;
    TASNode soundBus;
    TASNode sound;
    TASNode parent;
    TASStatus status;
    int route;
    if (reader == 0 || configuration == 0 || reader->getProperty == 0 ||
        reader->findNode == 0 || reader->resolvePhandle == 0 ||
        reader->getParent == 0)
        return kTASStatusMalformed;
    memset(configuration, 0, sizeof(*configuration));
    if (!reader->findNode(reader->context, "/mac-io/i2s", &i2s) ||
        !reader->findNode(reader->context, "/mac-io/i2s/i2s-a",
        &soundBus) ||
        !reader->findNode(reader->context, "/mac-io/i2s/i2s-a/sound",
        &sound))
        return kTASStatusNotMatched;
    if (!reader->getParent(reader->context, soundBus, &parent) ||
        parent != i2s)
        return kTASStatusNotMatched;
    if (!reader->getParent(reader->context, sound, &parent) ||
        parent != soundBus)
        return kTASStatusNotMatched;
    status = string_property(reader, sound, "compatible", &bytes, &length, 1);
    if (status != kTASStatusOK)
        return status;
    if (strcmp((const char *)bytes, "tumbler") == 0)
        configuration->codecKind = kTASCodecTAS3001C;
    else if (strcmp((const char *)bytes, "snapper") == 0)
        configuration->codecKind = kTASCodecTAS3004;
    else
        return kTASStatusNotMatched;
    status = exact_cells(reader, i2s, "reg", 6, &bytes);
    if (status != kTASStatusOK)
        return status;
    status = parse_range(bytes, &configuration->i2s);
    if (status != kTASStatusOK)
        return status;
    status = parse_range(bytes + 8, &configuration->outputDBDMA);
    if (status != kTASStatusOK)
        return status;
    status = parse_range(bytes + 16, &configuration->inputDBDMA);
    if (status != kTASStatusOK)
        return status;
    status = exact_cells_alias(reader, i2s, "interrupts",
        "AAPL,interrupts", 2, &bytes);
    if (status != kTASStatusOK)
        return status;
    configuration->outputIRQ = be32(bytes);
    configuration->inputIRQ = be32(bytes + 4);
    status = parse_codec(reader, sound, configuration);
    if (status != kTASStatusOK)
        return status;
    for (route = 0; route < (int)kTASRouteCount; ++route) {
        status = parse_route(reader, sound, (TASRouteKind)route,
            &configuration->routes[route]);
        if (status != kTASStatusOK)
            return status;
    }
    status = parse_policy(reader, sound, configuration);
    if (status != kTASStatusOK)
        return status;
    if ((configuration->quirks & kTASQuirkANDedReset) != 0 &&
        configuration->routes[kTASRouteLineOut].present)
        return kTASStatusUnsupported;
    return kTASStatusOK;
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
