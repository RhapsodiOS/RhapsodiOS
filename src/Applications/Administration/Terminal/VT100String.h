#ifndef TERMINAL_VT100_STRING_H
#define TERMINAL_VT100_STRING_H

#include "Chunk.h"

#include <stddef.h>

#define VT100_STRING_LIMIT 0x400u
#define VT100_STRING_DISPLAY_LIMIT 0x51u

typedef enum {
    VT100_STRING_CONTINUE = 0,
    VT100_STRING_COMPLETE,
    VT100_STRING_ERROR
} VT100StringResult;

typedef struct {
    const char *bytes;
    size_t length;
} VT100StringView;

void vt100StringReset(TerminalChunk *text);
VT100StringResult vt100StringConsume(TerminalChunk **text,
                                     unsigned char byte,
                                     VT100StringView *completed);

#endif
