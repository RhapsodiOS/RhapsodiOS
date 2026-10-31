#include "IntegerString.h"

#include <stdio.h>

char *itoa(int value)
{
    static char temporaryBuffer[12];

    sprintf(temporaryBuffer, "%d", value);
    return temporaryBuffer;
}