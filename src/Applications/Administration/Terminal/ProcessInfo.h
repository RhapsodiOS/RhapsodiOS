#ifndef TERMINAL_PROCESSINFO_H
#define TERMINAL_PROCESSINFO_H

#define TERMINAL_PROCESS_COMMAND_LENGTH 16

typedef struct TerminalProcessInfo {
    int pid;
    int processGroup;
    int terminalProcessGroup;
    int terminalDevice;
    int isRunnable;
    char command[TERMINAL_PROCESS_COMMAND_LENGTH];
} TerminalProcessInfo;

void get_process_info_from_pid(int pid, TerminalProcessInfo *output);

#endif
