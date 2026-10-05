#include <stdio.h>

#include "../SavePanelMode.h"

static int check(int howMany, int mustPrompt, int sharesFile,
    TerminalSavePanelTitleMode expected)
{
    TerminalSavePanelTitleMode actual;

    actual = terminalSavePanelTitleMode(howMany, mustPrompt, sharesFile);
    if (actual != expected) {
        fprintf(stderr, "save panel mode mismatch: howMany=%d prompt=%d shared=%d\n",
            howMany, mustPrompt, sharesFile);
        return 0;
    }
    return 1;
}

int main(void)
{
    if (!check(1, 0, 1, TerminalSavePanelSaveSet) ||
        !check(1, 0, 0, TerminalSavePanelSave) ||
        !check(2, 1, 0, TerminalSavePanelSaveAs) ||
        !check(0, 1, 0, TerminalSavePanelSaveAs) ||
        !check(0, 0, 0, TerminalSavePanelSave) ||
        !check(3, 0, 0, TerminalSavePanelUnexpectedMode) ||
        !check(-1, 0, 0, TerminalSavePanelUnexpectedMode))
        return 1;

    if (terminalSaveWindowAction(1, 1) != TerminalSaveWindowKeep ||
        terminalSaveWindowAction(1, 0) != TerminalSaveWindowSkip ||
        terminalSaveWindowAction(2, 1) != TerminalSaveWindowKeep ||
        terminalSaveWindowAction(2, 0) != TerminalSaveWindowAddToSet)
        return 1;

    puts("savepanelmode: ok");
    return 0;
}
