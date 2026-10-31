#include "WordBoundary.h"

static int isAsciiAlphaNumeric(int byteValue)
{
    return (byteValue >= '0' && byteValue <= '9') ||
           (byteValue >= 'A' && byteValue <= 'Z') ||
           (byteValue >= 'a' && byteValue <= 'z');
}

int startsleft(int byteValue)
{
    return isAsciiAlphaNumeric(byteValue) || byteValue == '_' || byteValue == '~';
}

int terminalStartsLeft(int byteValue)
{
    return startsleft(byteValue);
}

int startsright(int byteValue)
{
    return isAsciiAlphaNumeric(byteValue) || byteValue == '_';
}

int terminalStartsRight(int byteValue)
{
    return startsright(byteValue);
}

int iswordchar(int byteValue)
{
    return isAsciiAlphaNumeric(byteValue) || byteValue == '_' ||
           byteValue == '\'' || byteValue == '-';
}

int terminalIsWordCharacter(int byteValue)
{
    return iswordchar(byteValue);
}
int char_offset(unsigned char attributes, char attribute)
{
    unsigned int mask = attributes;
    int offset = 0;

    if ((mask & 3) != 0)
        mask = (mask & 0xFC) | 2;

    switch (mask) {
    case 2:
        return (attribute & 2) != 0 ? 1 : 0;
    case 4:
        return (attribute & 4) != 0 ? 1 : 0;
    case 6:
        if ((attribute & 2) != 0)
            offset = 1;
        return (attribute & 4) != 0 ? offset + 2 : offset;
    case 8:
        return (attribute & 8) != 0 ? 1 : 0;
    case 10:
        if ((attribute & 2) != 0)
            offset = 1;
        return (attribute & 8) != 0 ? offset + 2 : offset;
    case 12:
        if ((attribute & 4) != 0)
            offset = 1;
        return (attribute & 8) != 0 ? offset + 2 : offset;
    case 14:
        if ((attribute & 2) != 0)
            offset = 1;
        if ((attribute & 4) != 0)
            offset += 2;
        return (attribute & 8) != 0 ? offset + 4 : offset;
    default:
        return 0;
    }
}
