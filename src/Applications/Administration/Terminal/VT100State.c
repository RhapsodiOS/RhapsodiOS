#include "VT100State.h"

void vt100Linefeed(VT100State *state, VT100ScrollUpCallback scrollUp,
                   void *context)
{
    int next;
    int maxRow;

    if (!state)
        return;
    if ((int)state->cursorRow == (int)state->drawCursorOK - 1) {
        if (scrollUp)
            scrollUp(context, 1);
        return;
    }
    next = (int)state->cursorRow + 1;
    maxRow = (int)state->height - 1;
    if (next > maxRow)
        next = maxRow;
    state->cursorRow = (uint8_t)next;
}

void vt100ReverseLinefeed(VT100State *state,
                          VT100ScrollDownCallback scrollDown, void *context)
{
    if (!state)
        return;
    if (state->cursorRow == state->bottom) {
        if (scrollDown)
            scrollDown(context, state->cursorRow, state->drawCursorOK, 1);
        return;
    }
    if (state->cursorRow != 0)
        --state->cursorRow;
}

void vt100DeleteChars(VT100State *state, uint32_t count,
                      VT100DeleteCharsCallback deleteChars, void *context)
{
    if (!state || !deleteChars)
        return;
    if (count == 0)
        count = 1;
    deleteChars(context, state->cursorRow, state->cursorColumn, count);
}

int vt100ResetState(VT100State *state, TerminalChunk *tabs,
                    VT100RefreshCallback refresh,
                    VT100ClearCallback clearTo, void *context)
{
    unsigned int column;

    if (!state || !tabs || tabs->elementSize != 1 ||
        tabs->allocated < state->width)
        return 0;
    if (refresh)
        refresh(context);
    for (column = 0; column < state->width; ++column)
        tabs->elements[column] = (unsigned char)((column & 7u) == 0);
    state->flags = (state->flags & 0xEC7FFFFFu) | 0x10000000u;
    state->videoFlags &= 0x1400FFFFu;
    state->bottom = 0;
    state->drawCursorOK = state->width;
    state->cursorRow = 0;
    state->cursorColumn = 0;
    state->terminalFlags &= 0x0FFF7FFFu;
    if (clearTo)
        clearTo(context, 0, state->width);
    return 1;
}
