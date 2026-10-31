#ifndef TERMINAL_SHELLPOLICY_H
#define TERMINAL_SHELLPOLICY_H

int isCommandClean(const char *command, char allowShellCommands,
    const char * const *cleanCommands);

#endif
