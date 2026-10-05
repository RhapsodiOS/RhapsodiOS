#include "SavePanelMode.h"

TerminalSavePanelTitleMode terminalSavePanelTitleMode(
    int howMany, int mustPrompt, int sharesFile)
{
    if (howMany == 1)
        return sharesFile ? TerminalSavePanelSaveSet : TerminalSavePanelSave;
    if (howMany > 1)
        return howMany == 2 ? TerminalSavePanelSaveAs :
            TerminalSavePanelUnexpectedMode;
    if (howMany == 0)
        return mustPrompt ? TerminalSavePanelSaveAs : TerminalSavePanelSave;
    return TerminalSavePanelUnexpectedMode;
}

TerminalSaveWindowAction terminalSaveWindowAction(
    int howMany, int fileNameMatches)
{
    if (fileNameMatches)
        return TerminalSaveWindowKeep;
    return howMany == 1 ? TerminalSaveWindowSkip :
        TerminalSaveWindowAddToSet;
}
