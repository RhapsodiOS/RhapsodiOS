#ifndef TERMINAL_VT100_ARGS_H
#define TERMINAL_VT100_ARGS_H

#include "Chunk.h"

#include <stdint.h>

typedef enum {
    VT100_ARGS_CONTINUE = 0,
    VT100_ARGS_DISPATCH_CSI,
    VT100_ARGS_DISPATCH_PRIVATE
} VT100ArgsResult;

/* CSI arguments are unsigned 16-bit values in the reference implementation. */
void vt100ArgsReset(TerminalChunk *arguments);
VT100ArgsResult vt100ArgsConsume(TerminalChunk **arguments,
                                 unsigned char byte, int privateMode);

#endif
