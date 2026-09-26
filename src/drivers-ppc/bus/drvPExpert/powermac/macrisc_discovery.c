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
