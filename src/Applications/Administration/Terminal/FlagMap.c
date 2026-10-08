#include "FlagMap.h"

#include <stdlib.h>
#include <string.h>

#if defined(__OBJC__)
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#define FLAGMAP_ASSERT_FAILURE(functionName, sourceLine, message) \
    [[NSAssertionHandler currentHandler] \
        handleFailureInFunction:[NSString stringWithCString:functionName] \
        file:[NSString stringWithCString:"FlagMap.m"] \
        lineNumber:sourceLine \
        description:message]
#endif

extern void *NSZoneMalloc(struct _NSZone *zone, unsigned size);
extern void *NSZoneRealloc(struct _NSZone *zone, void *pointer,
    unsigned size);
extern struct _NSZone *NSZoneFromPointer(void *pointer);

TerminalFlagMap *CreateFlagMapFromZone(struct _NSZone *zone)
{
    TerminalFlagMap *map;

    map = (TerminalFlagMap *)NSZoneMalloc(zone, sizeof(*map));
#if defined(__OBJC__)
    if (map == NULL)
        FLAGMAP_ASSERT_FAILURE("CreateFlagMapFromZone", 21, @"Malloc flagmap");
#endif
    map->bytes = (unsigned char *)NSZoneMalloc(zone, 16);
#if defined(__OBJC__)
    if (map->bytes == NULL)
        FLAGMAP_ASSERT_FAILURE("CreateFlagMapFromZone", 22, @"Malloc flagmap");
#endif
    memset(map->bytes, 0, 16);
    map->capacity = 16;
    return map;
}

void FreeFlagMap(TerminalFlagMap *map)
{
    free(map->bytes);
    free(map);
}

int FlagIsSet(const TerminalFlagMap *map, unsigned int index)
{
    if (index >= 8u * (unsigned int)map->capacity)
        return 0;
    return (map->bytes[index >> 3] >> (index & 7)) & 1;
}

unsigned char *SetFlag(TerminalFlagMap *map, unsigned int index,
    unsigned char value)
{
    if (index <= 0x2710u) {
        unsigned int offset;
        unsigned char mask;

        while (index >= 8u * (unsigned int)map->capacity) {
            map->capacity = (unsigned short)(map->capacity + 16);
            map->bytes = (unsigned char *)NSZoneRealloc(
                NSZoneFromPointer(map->bytes), map->bytes, map->capacity);
#if defined(__OBJC__)
            if (map->bytes == NULL)
                FLAGMAP_ASSERT_FAILURE("SetFlag", 64, @"Realloc flagmap");
#endif
            memset(map->bytes + map->capacity - 16, 0, 16);
        }
        offset = index >> 3;
        mask = (unsigned char)(1 << (index & 7));
        map->bytes[offset] &= (unsigned char)~mask;
        if (value != 0)
            map->bytes[offset] |= mask;
        return map->bytes;
    }
    return (unsigned char *)map;
}
