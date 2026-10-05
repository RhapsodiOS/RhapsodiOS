#ifndef TERMINAL_PROCESSNAMES_H
#define TERMINAL_PROCESSNAMES_H

#include "ProcessInfo.h"

#define TERMINAL_PROCESS_NAME_CAPACITY 10
#define TERMINAL_PROCESS_NAME_RECORD_SIZE 17

int terminal_append_process_name(const TerminalProcessInfo *process,
    int terminalDevice, char allowShellCommands,
    const char * const *cleanCommands,
    char names[TERMINAL_PROCESS_NAME_CAPACITY][TERMINAL_PROCESS_NAME_RECORD_SIZE],
    int *count);

#endif
