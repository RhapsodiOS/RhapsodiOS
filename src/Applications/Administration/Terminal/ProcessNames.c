#include "ProcessNames.h"

#include "ShellPolicy.h"

#include <string.h>

int terminal_append_process_name(const TerminalProcessInfo *process,
    int terminalDevice, char allowShellCommands,
    const char * const *cleanCommands,
    char names[TERMINAL_PROCESS_NAME_CAPACITY][TERMINAL_PROCESS_NAME_RECORD_SIZE],
    int *count)
{
    int index;

    if (!process->isRunnable || process->pid <= 0 ||
            (((unsigned int)process->terminalDevice >> 8) & 0xff) != 4 ||
            ((unsigned int)process->terminalDevice & 0xff) !=
                (unsigned int)terminalDevice ||
            isCommandClean(process->command, allowShellCommands,
                cleanCommands))
        return 0;

    for (index = 0; index < *count; ++index) {
        if (strcmp(names[index], process->command) == 0)
            return 0;
    }

    if (*count >= TERMINAL_PROCESS_NAME_CAPACITY)
        return 0;

    strncpy(names[*count], process->command,
        TERMINAL_PROCESS_NAME_RECORD_SIZE - 1);
    names[*count][TERMINAL_PROCESS_NAME_RECORD_SIZE - 1] = '\0';
    ++*count;
    return 1;
}
