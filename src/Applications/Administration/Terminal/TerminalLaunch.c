#include "TerminalLaunch.h"

int TerminalCheckWrapperLaunch(const char *directory,
    TerminalChangeDirectoryFunction changeDirectory,
    TerminalProcessNameFunction processName,
    TerminalPathAccessFunction pathAccess)
{
    const char *path;

    if (changeDirectory(directory) == -1)
        return 0;
    path = processName();
    return pathAccess(path, 4) != -1;
}
