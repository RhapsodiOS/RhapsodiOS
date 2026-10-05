#include "../ShellPolicy.h"

int main(void)
{
    const char *clean[] = { "sh", "zsh", 0 };
    const char *empty[] = { 0 };

    if (!isCommandClean("-c", 0, empty))
        return 1;
    if (!isCommandClean("/bin/sh", 0, clean))
        return 1;
    if (isCommandClean("/usr/bin/bash", 0, clean))
        return 1;
    if (!isCommandClean("/usr/bin/bash", 1, 0))
        return 1;
    if (!isCommandClean("/bin/su.wheel", 1, 0))
        return 1;
    if (!isCommandClean("/bin/su.nowheel", 1, 0))
        return 1;
    if (!isCommandClean("/bin/su", 1, 0))
        return 1;
    if (isCommandClean("/bin/rsh", 1, 0))
        return 1;
    if (!isCommandClean("/bin/foosh", 1, 0))
        return 1;
    if (isCommandClean("/bin/longshellsh", 1, 0))
        return 1;
    if (isCommandClean("/bin/foosh", 0, 0))
        return 1;
    if (isCommandClean("/bin/bash", 0, empty))
        return 1;
    return 0;
}
