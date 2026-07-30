#ifndef _PEXPERT_KEYLARGO_DISCOVERY_H_
#define _PEXPERT_KEYLARGO_DISCOVERY_H_

typedef struct {
    const unsigned char *bytes;
    unsigned int size;
} PEKeyLargoProperty;

typedef struct {
    unsigned int macIOBase;
    unsigned int macIOSize;
    PEKeyLargoProperty reg;
    PEKeyLargoProperty absoluteAddress;
    PEKeyLargoProperty addressStep;
    PEKeyLargoProperty rate;
} PEKeyLargoDiscoveryInput;

typedef struct {
    unsigned int i2cOffset;
    unsigned int addressStep;
    unsigned int rate;
    unsigned int speed;
} PEKeyLargoDiscovery;

static int
PEKeyLargoRateToSpeed(unsigned int rate, unsigned int *speed)
{
    if (speed == 0)
        return 0;
    if (rate == 100)
        *speed = 0;
    else if (rate == 50)
        *speed = 1;
    else if (rate == 25)
        *speed = 2;
    else
        return 0;
    return 1;
}

static unsigned int
PEKeyLargoCell(const unsigned char *bytes)
{
    return ((unsigned int)bytes[0] << 24) |
        ((unsigned int)bytes[1] << 16) |
        ((unsigned int)bytes[2] << 8) | (unsigned int)bytes[3];
}

static int
PEKeyLargoPropertyPresent(PEKeyLargoProperty property)
{
    return property.bytes != 0 || property.size != 0;
}

static int
PEKeyLargoCellProperty(PEKeyLargoProperty property, unsigned int *value)
{
    if (property.bytes == 0 || property.size != 4)
        return 0;
    *value = PEKeyLargoCell(property.bytes);
    return 1;
}

static int
PEKeyLargoRangeContains(unsigned int size, unsigned int offset,
    unsigned int length)
{
    return length != 0 && offset < size && length <= size - offset;
}

static int
PEKeyLargoParseDiscovery(const PEKeyLargoDiscoveryInput *input,
    PEKeyLargoDiscovery *result)
{
    unsigned int relative;
    unsigned int absolute;
    unsigned int lastOffset;
    int hasRelative;
    int hasAbsolute;

    if (input == 0 || result == 0 || input->macIOSize == 0)
        return 0;
    hasRelative = PEKeyLargoPropertyPresent(input->reg);
    hasAbsolute = PEKeyLargoPropertyPresent(input->absoluteAddress);
    if (!hasRelative && !hasAbsolute)
        return 0;
    if (hasRelative && !PEKeyLargoCellProperty(input->reg, &relative))
        return 0;
    if (hasAbsolute) {
        if (!PEKeyLargoCellProperty(input->absoluteAddress, &absolute) ||
            absolute < input->macIOBase)
            return 0;
        relative = absolute - input->macIOBase;
    }
    if (hasRelative && hasAbsolute &&
        PEKeyLargoCell(input->reg.bytes) != relative)
        return 0;
    if (!PEKeyLargoCellProperty(input->addressStep,
        &result->addressStep) || result->addressStep == 0 ||
        !PEKeyLargoCellProperty(input->rate, &result->rate) ||
        !PEKeyLargoRateToSpeed(result->rate, &result->speed))
        return 0;
    if (result->addressStep > (~0u - relative) / 7)
        return 0;
    lastOffset = relative + 7 * result->addressStep;
    if (!PEKeyLargoRangeContains(input->macIOSize, lastOffset, 1) ||
        !PEKeyLargoRangeContains(input->macIOSize, 0x38, 0x14))
        return 0;
    result->i2cOffset = relative;
    return 1;
}

static int
PEKeyLargoParseMacIO(PEKeyLargoProperty address,
    PEKeyLargoProperty assigned, PEKeyLargoProperty reg,
    unsigned int *base, unsigned int *size)
{
    unsigned int parsedBase = 0;
    unsigned int parsedSize = 0;

    if (base == 0 || size == 0)
        return 0;
    if (PEKeyLargoPropertyPresent(address) &&
        !PEKeyLargoCellProperty(address, &parsedBase))
        return 0;
    if (PEKeyLargoPropertyPresent(assigned)) {
        if (assigned.bytes == 0 || assigned.size != 20 ||
            PEKeyLargoCell(assigned.bytes + 4) != 0 ||
            PEKeyLargoCell(assigned.bytes + 12) != 0)
            return 0;
        if (!PEKeyLargoPropertyPresent(address))
            parsedBase = PEKeyLargoCell(assigned.bytes + 8);
        else if (parsedBase != PEKeyLargoCell(assigned.bytes + 8))
            return 0;
        parsedSize = PEKeyLargoCell(assigned.bytes + 16);
    } else if (PEKeyLargoPropertyPresent(reg)) {
        if (reg.bytes == 0 || reg.size != 8)
            return 0;
        if (!PEKeyLargoPropertyPresent(address))
            parsedBase = PEKeyLargoCell(reg.bytes);
        else if (parsedBase != PEKeyLargoCell(reg.bytes))
            return 0;
        parsedSize = PEKeyLargoCell(reg.bytes + 4);
    } else {
        return 0;
    }
    if (parsedSize == 0 || parsedSize > ~0u - parsedBase)
        return 0;
    *base = parsedBase;
    *size = parsedSize;
    return 1;
}

#endif /* _PEXPERT_KEYLARGO_DISCOVERY_H_ */
