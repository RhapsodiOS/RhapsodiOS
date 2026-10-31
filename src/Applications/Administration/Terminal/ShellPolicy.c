#include "ShellPolicy.h"

#include <string.h>

int isCommandClean(const char *command, char allowShellCommands,
    const char * const *cleanCommands)
{
    const char *baseName = command;
    const char *slash = strrchr(command, '/');
    unsigned short index;

    if (command[0] == '-')
        return 1;
    if (slash != 0)
        baseName = slash + 1;

    if (allowShellCommands != 0) {
        size_t length;

        if (strcmp(baseName, "su") == 0 ||
                strcmp(baseName, "su.wheel") == 0 ||
                strcmp(baseName, "su.nowheel") == 0)
            return 1;
        if (strcmp(baseName, "rsh") == 0)
            return 0;
        length = strlen(baseName);
        if (length >= 2 && length <= 5 &&
                baseName[length - 2] == 's' && baseName[length - 1] == 'h')
            return 1;
    }

    if (cleanCommands == 0 || cleanCommands[0] == 0)
        return 0;
    index = 0;
    while (cleanCommands[index] != 0) {
        if (strcmp(baseName, cleanCommands[index]) == 0)
            return 1;
        index = (unsigned short)(index + 1);
    }
    return 0;
}
