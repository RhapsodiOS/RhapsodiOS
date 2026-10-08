#include "VT100Args.h"

void vt100ArgsReset(TerminalChunk *arguments)
{
    if (!arguments || arguments->elementSize != sizeof(uint16_t) ||
        arguments->allocated == 0)
        return;
    arguments->count = 1;
    ((uint16_t *)arguments->elements)[0] = 0;
}

VT100ArgsResult vt100ArgsConsume(TerminalChunk **arguments,
                                 unsigned char byte, int privateMode)
{
    TerminalChunk *chunk;
    uint16_t *values;
    uint32_t index;

    if (!arguments || !*arguments)
        return privateMode ? VT100_ARGS_DISPATCH_PRIVATE : VT100_ARGS_DISPATCH_CSI;
    chunk = *arguments;
    if (byte >= '0' && byte <= '9') {
        if (chunk->elementSize != sizeof(uint16_t) || chunk->count == 0)
            return VT100_ARGS_CONTINUE;
        index = chunk->count - 1;
        values = (uint16_t *)chunk->elements;
        values[index] = (uint16_t)(values[index] * 10u + (byte - '0'));
        return VT100_ARGS_CONTINUE;
    }
    if (byte == ';') {
        if (chunk->elementSize != sizeof(uint16_t) ||
            chunk->count == UINT32_MAX)
            return VT100_ARGS_CONTINUE;
        index = chunk->count;
        if (index == chunk->allocated) {
            chunk = ChunkRealloc(chunk);
            if (!chunk)
                return VT100_ARGS_CONTINUE;
            *arguments = chunk;
        }
        chunk->count = index + 1;
        ((uint16_t *)chunk->elements)[index] = 0;
        return VT100_ARGS_CONTINUE;
    }
    return privateMode ? VT100_ARGS_DISPATCH_PRIVATE : VT100_ARGS_DISPATCH_CSI;
}
