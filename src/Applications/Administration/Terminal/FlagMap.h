#ifndef TERMINAL_FLAGMAP_H
#define TERMINAL_FLAGMAP_H

typedef struct TerminalFlagMap {
    unsigned char *bytes;
    unsigned short capacity;
} TerminalFlagMap;

struct _NSZone;

TerminalFlagMap *CreateFlagMapFromZone(struct _NSZone *zone);
void FreeFlagMap(TerminalFlagMap *map);
int FlagIsSet(const TerminalFlagMap *map, unsigned int index);
unsigned char *SetFlag(TerminalFlagMap *map, unsigned int index,
    unsigned char value);

#endif
