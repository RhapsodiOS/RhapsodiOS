#ifndef TERMINAL_VT100_STATE_H
#define TERMINAL_VT100_STATE_H

#include "Chunk.h"

#include <stdint.h>

typedef struct {
    uint32_t flags;
    uint32_t videoFlags;
    uint32_t terminalFlags;
    uint8_t width;
    uint8_t height;
    uint8_t bottom;
    uint8_t drawCursorOK;
    uint8_t cursorRow;
    uint8_t cursorColumn;
} VT100State;

typedef void (*VT100RefreshCallback)(void *context);
typedef void (*VT100ClearCallback)(void *context, uint8_t line, uint8_t column);
typedef void (*VT100ScrollUpCallback)(void *context, uint8_t lines);
typedef void (*VT100ScrollDownCallback)(void *context, uint8_t from,
                                        uint8_t to, uint8_t lines);
typedef void (*VT100DeleteCharsCallback)(void *context, uint8_t row,
                                         uint8_t column, uint32_t count);

/* Models state writes in -[vt100 reset] recovered from the PPC binary. */
void vt100Linefeed(VT100State *state, VT100ScrollUpCallback scrollUp,
                   void *context);
void vt100ReverseLinefeed(VT100State *state,
                          VT100ScrollDownCallback scrollDown, void *context);
void vt100DeleteChars(VT100State *state, uint32_t count,
                      VT100DeleteCharsCallback deleteChars, void *context);

int vt100ResetState(VT100State *state, TerminalChunk *tabs,
                    VT100RefreshCallback refresh,
                    VT100ClearCallback clearTo, void *context);

#endif
