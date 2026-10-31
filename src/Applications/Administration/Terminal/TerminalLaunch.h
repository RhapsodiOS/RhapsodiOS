#ifndef TERMINAL_LAUNCH_H
#define TERMINAL_LAUNCH_H

typedef int (*TerminalChangeDirectoryFunction)(const char *path);
typedef const char *(*TerminalProcessNameFunction)(void);
typedef int (*TerminalPathAccessFunction)(const char *path, int mode);

int TerminalCheckWrapperLaunch(const char *directory,
    TerminalChangeDirectoryFunction changeDirectory,
    TerminalProcessNameFunction processName,
    TerminalPathAccessFunction pathAccess);

#endif
