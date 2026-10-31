#ifndef TERMINAL_SAVE_PANEL_MODE_H
#define TERMINAL_SAVE_PANEL_MODE_H

typedef enum {
    TerminalSavePanelSaveSet,
    TerminalSavePanelSave,
    TerminalSavePanelSaveAs,
    TerminalSavePanelUnexpectedMode
} TerminalSavePanelTitleMode;

TerminalSavePanelTitleMode terminalSavePanelTitleMode(
    int howMany, int mustPrompt, int sharesFile);

typedef enum {
    TerminalSaveWindowSkip,
    TerminalSaveWindowKeep,
    TerminalSaveWindowAddToSet
} TerminalSaveWindowAction;

TerminalSaveWindowAction terminalSaveWindowAction(
    int howMany, int fileNameMatches);

#endif
