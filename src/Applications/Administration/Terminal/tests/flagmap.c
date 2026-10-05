#include "../FlagMap.h"

#include <stdlib.h>

void *NSZoneMalloc(struct _NSZone *zone, unsigned size)
{
    (void)zone;
    return malloc(size);
}

void *NSZoneRealloc(struct _NSZone *zone, void *pointer, unsigned size)
{
    (void)zone;
    return realloc(pointer, size);
}

struct _NSZone *NSZoneFromPointer(void *pointer)
{
    (void)pointer;
    return 0;
}

int main(void)
{
    TerminalFlagMap *map = CreateFlagMapFromZone(0);
    unsigned char *bytes;

    if (map == 0 || map->capacity != 16)
        return 1;
    bytes = map->bytes;
    if (FlagIsSet(map, 0) || FlagIsSet(map, 127) || FlagIsSet(map, 128))
        return 1;
    if (SetFlag(map, 0, 1) != bytes || !FlagIsSet(map, 0))
        return 1;
    SetFlag(map, 7, 1);
    SetFlag(map, 8, 1);
    SetFlag(map, 127, 1);
    if (!FlagIsSet(map, 7) || !FlagIsSet(map, 8) || !FlagIsSet(map, 127))
        return 1;
    if (FlagIsSet(map, 128))
        return 1;

    SetFlag(map, 128, 1);
    if (map->capacity != 32 || !FlagIsSet(map, 128))
        return 1;
    SetFlag(map, 8, 0);
    if (FlagIsSet(map, 8) || !FlagIsSet(map, 7) || !FlagIsSet(map, 127))
        return 1;

    SetFlag(map, 10000, 1);
    if (!FlagIsSet(map, 10000) || map->capacity < 1251)
        return 1;
    bytes = map->bytes;
    if (SetFlag(map, 10001, 1) != (unsigned char *)map ||
            map->bytes != bytes || FlagIsSet(map, 10001))
        return 1;

    FreeFlagMap(map);
    return 0;
}
