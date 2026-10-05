#include "../ServiceManagerState.h"
#include <assert.h>
#include <string.h>

int main(void)
{
    assert(TerminalServiceManagerEffectiveDirty(1, 0) == 0);
    assert(TerminalServiceManagerEffectiveDirty(1, 1) == 1);
    assert(TerminalServiceManagerEffectiveDirty(0, 1) == 0);

    TerminalServiceManagerDirtiness controls;
    TerminalServiceManagerGetDirtiness(1, 1, &controls);
    assert(controls.changeEnabled == 1);
    assert(controls.removeEnabled == 1);
    assert(controls.saveEnabled == 0);

    TerminalServiceManagerGetDirtiness(0, 1, &controls);
    assert(controls.changeEnabled == 0);
    assert(controls.removeEnabled == 1);
    assert(controls.saveEnabled == 1);

    TerminalServiceManagerGetDirtiness(1, 0, &controls);
    assert(controls.changeEnabled == 0);
    assert(controls.removeEnabled == 0);
    assert(controls.saveEnabled == 0);

    assert(TerminalServiceManagerAccumulateCellFlag(0, 1, 4) == 4);
    assert(TerminalServiceManagerAccumulateCellFlag(1, 1, 4) == 5);
    assert(TerminalServiceManagerAccumulateCellFlag(1, 0, 4) == 1);
    assert(TerminalServiceManagerSettingsError(1, 32, 0) == 0);
    assert(TerminalServiceManagerSettingsError(0, 32, 1) == 0);
    assert(TerminalServiceManagerSettingsError(0, 64, 1) == 8);
    assert(TerminalServiceManagerSettingsError(0, 32, 0) == 8);
    assert(TerminalServiceManagerCellMatchesFlags(4, 5) == 1);
    assert(TerminalServiceManagerCellMatchesFlags(2, 5) == 0);
    assert(TerminalServiceManagerCellMatchesFlags(0, 255) == 0);
    assert(TerminalServiceManagerRoutingFlags(1, 4) == 3);
    assert(TerminalServiceManagerRoutingFlags(1, 0) == 0);
    assert(TerminalServiceManagerRoutingFlags(0, 255) == 0);
    assert(TerminalServiceManagerRoutingFlags(1, 2) == 0);
    assert(TerminalServiceManagerRoutingFlags(1, 0x82) == 3);
    assert(TerminalServiceManagerShellOptionsEnabled(0) == 1);
    assert(TerminalServiceManagerShellOptionsEnabled(1) == 1);
    assert(TerminalServiceManagerShellOptionsEnabled(2) == 0);
    assert(TerminalServiceManagerShellOptionsEnabled(3) == 0);
    assert(TerminalServiceManagerExecutionPopupTag(0) == 64);
    assert(TerminalServiceManagerExecutionPopupTag(1) == 32);
    assert(TerminalServiceManagerExecutionPopupTag(2) == 64);
    assert(TerminalServiceManagerExecutionPopupTag(3) == 32);
    assert(TerminalServiceManagerExecutionPopupTagForWindowType(1, 4) == 32);
    assert(TerminalServiceManagerExecutionPopupTagForWindowType(4, 4) == 64);
    {
        unsigned char windowType;
        unsigned char routingFlags;
        TerminalServiceManagerGetExecutionBoxArguments(32, &windowType,
            &routingFlags);
        assert(windowType == 1 && routingFlags == 4);
        TerminalServiceManagerGetExecutionBoxArguments(64, &windowType,
            &routingFlags);
        assert(windowType == 4 && routingFlags == 4);
    }
    assert(TerminalServiceManagerShouldWarnAboutStrangeness(4, 2) == 1);
    assert(TerminalServiceManagerShouldWarnAboutStrangeness(4, 0) == 0);
    assert(TerminalServiceManagerShouldWarnAboutStrangeness(0, 2) == 0);
    {
        char originalCommand[32] = "run original command";
        char copiedCommand[32];
        TerminalServiceManagerCopyCommand(copiedCommand, originalCommand);
        originalCommand[0] = 'X';
        assert(strcmp(copiedCommand, "run original command") == 0);
    }
    {
        char keyString[2];
        TerminalServiceManagerFormatKey('K', keyString);
        assert(keyString[0] == 'K' && keyString[1] == '\0');
        TerminalServiceManagerFormatKey(' ', keyString);
        assert(keyString[0] == '\0' && keyString[1] == '\0');
    }
    return 0;
}
