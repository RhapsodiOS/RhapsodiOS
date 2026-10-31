#ifndef TERMINAL_SERVICE_MANAGER_STATE_H
#define TERMINAL_SERVICE_MANAGER_STATE_H

#include <string.h>

typedef struct {
    int changeEnabled;
    int removeEnabled;
    int saveEnabled;
} TerminalServiceManagerDirtiness;

static int TerminalServiceManagerEffectiveDirty(int requestedDirty,
    int hasSelection)
{
    return requestedDirty != 0 && hasSelection != 0;
}

static unsigned char TerminalServiceManagerAccumulateCellFlag(
    unsigned char currentFlags, int selected, unsigned char tag)
{
    return selected ? (unsigned char)(currentFlags | tag) : currentFlags;
}

static int TerminalServiceManagerSettingsError(int selectionFlags,
    int executionType, int returnsResult)
{
    return selectionFlags != 0 ||
        (executionType == 32 && returnsResult != 0) ? 0 : 8;
}

static int TerminalServiceManagerCellMatchesFlags(unsigned char tag,
    unsigned char flags)
{
    return (tag & flags) != 0;
}

static unsigned char TerminalServiceManagerRoutingFlags(
    unsigned char windowFlags, unsigned char resultFlags)
{
    return (windowFlags & 1) != 0 && (resultFlags & 0xFD) != 0 ? 3 : 0;
}

static void TerminalServiceManagerFormatKey(char key, char string[2])
{
    string[0] = key == ' ' ? '\0' : key;
    string[1] = '\0';
}

static int TerminalServiceManagerShellOptionsEnabled(unsigned char flags)
{
    return (flags & 2) == 0;
}

static int TerminalServiceManagerExecutionPopupTag(unsigned char flags)
{
    return (flags & 1) != 0 ? 32 : 64;
}

static int TerminalServiceManagerExecutionPopupTagForWindowType(
    unsigned char windowType, unsigned char routingFlags)
{
    (void)routingFlags;
    return TerminalServiceManagerExecutionPopupTag(windowType);
}

static void TerminalServiceManagerGetExecutionBoxArguments(int executionType,
    unsigned char *windowType, unsigned char *routingFlags)
{
    *windowType = executionType == 32 ? 1 : 4;
    *routingFlags = 4;
}

static int TerminalServiceManagerShouldWarnAboutStrangeness(
    unsigned char selectionFlags, unsigned char selectionOptions)
{
    return (selectionFlags & 4) != 0 && (selectionOptions & 2) != 0;
}

static void TerminalServiceManagerCopyCommand(char *destination,
    const char *source)
{
    strcpy(destination, source);
}

static void TerminalServiceManagerGetDirtiness(int dirty, int hasSelection,
    TerminalServiceManagerDirtiness *state)
{
    state->changeEnabled = dirty != 0 && hasSelection != 0;
    state->removeEnabled = hasSelection != 0;
    state->saveEnabled = dirty == 0 && hasSelection != 0;
}

#endif
