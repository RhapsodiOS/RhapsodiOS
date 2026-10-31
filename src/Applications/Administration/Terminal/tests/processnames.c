#include <assert.h>
#include <string.h>

#include "../ProcessNames.h"

int main(void)
{
    const char *cleanCommands[] = { "make", 0 };
    char names[TERMINAL_PROCESS_NAME_CAPACITY]
        [TERMINAL_PROCESS_NAME_RECORD_SIZE] = {{0}};
    TerminalProcessInfo process = { 40, 40, 40, 0x402, 1, "sh" };
    int count = 0;

    assert(terminal_append_process_name(&process, 2, 0, cleanCommands,
        names, &count) == 1);
    assert(count == 1 && strcmp(names[0], "sh") == 0);

    process.terminalDevice = 0x502;
    assert(terminal_append_process_name(&process, 2, 0, cleanCommands,
        names, &count) == 0);
    process.terminalDevice = 0x402;

    process.pid++;
    assert(terminal_append_process_name(&process, 2, 0, cleanCommands,
        names, &count) == 0);
    assert(count == 1);

    process.command[0] = 'm';
    process.command[1] = 'a';
    process.command[2] = 'k';
    process.command[3] = 'e';
    process.command[4] = '\0';
    assert(terminal_append_process_name(&process, 2, 0, cleanCommands,
        names, &count) == 0);

    process.command[0] = 'z';
    process.command[1] = 's';
    process.command[2] = 'h';
    process.command[3] = '\0';
    process.terminalDevice++;
    assert(terminal_append_process_name(&process, 2, 0, cleanCommands,
        names, &count) == 0);

    process.terminalDevice--;
    process.isRunnable = 0;
    assert(terminal_append_process_name(&process, 2, 0, cleanCommands,
        names, &count) == 0);
    process.isRunnable = 1;
    process.pid = -1;
    assert(terminal_append_process_name(&process, 0x40002, 0, cleanCommands,
        names, &count) == 0);

    return 0;
}
