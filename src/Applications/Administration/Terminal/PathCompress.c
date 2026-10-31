#include "PathCompress.h"
#include "WindowTitleRuntime.h"

#include <stdlib.h>
#include <string.h>

char *pathCompress(const char *path, char *destination, int suffixLimit)
{
    const char *suffix = path;
    const char *homeDirectory;
    size_t homeLength;
    size_t slashCount = 0;
    const char *cursor;

    if (!path || !destination)
        return NULL;

#if defined(__NeXT__)
    homeDirectory = terminalHomeDirectory();
#else
    homeDirectory = getenv("HOME");
#endif

    if (!homeDirectory)
        homeDirectory = "";

    homeLength = strlen(homeDirectory);
    if (homeLength > 5 && strncmp(homeDirectory, path, homeLength) == 0) {
        suffix = path + homeLength;
        destination[0] = '~';
        destination[1] = '\0';
    } else {
        destination[0] = '\0';
    }

    if ((int)strlen(suffix) > suffixLimit) {
        for (cursor = suffix; (cursor = strchr(cursor, '/')) != NULL; ++cursor)
            ++slashCount;
        if (slashCount > 2) {
            while ((int)strlen(suffix) > suffixLimit && slashCount > 1) {
                const char *slash = strchr(suffix, '/');
                if (!slash)
                    break;
                suffix = slash + 1;
                --slashCount;
            }
            strcpy(destination, ".../");
        }
    }

    return strcat(destination, suffix);
}
