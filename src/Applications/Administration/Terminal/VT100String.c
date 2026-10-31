#include "VT100String.h"

VT100StringResult vt100StringConsume(TerminalChunk **text,
                                     unsigned char byte,
                                     VT100StringView *completed)
{
    TerminalChunk *chunk;
    uint32_t index;
    size_t offset;

    if (!text || !*text || !completed)
        return VT100_STRING_ERROR;
    chunk = *text;
    if (chunk->elementSize != 1 || chunk->count >= chunk->allocated)
        return VT100_STRING_ERROR;
    index = chunk->count;
    chunk->elements[index] = byte;
    chunk->count = index + 1;
    if (chunk->count == chunk->allocated) {
        chunk = ChunkRealloc(chunk);
        if (!chunk) {
            --(*text)->count;
            return VT100_STRING_ERROR;
        }
        *text = chunk;
    }
    if (byte >= 32 && chunk->count <= VT100_STRING_LIMIT)
        return VT100_STRING_CONTINUE;

    chunk->elements[chunk->count - 1] = 0;
    if (chunk->count > VT100_STRING_DISPLAY_LIMIT) {
        offset = (size_t)chunk->count - VT100_STRING_DISPLAY_LIMIT;
        chunk->elements[offset] = '.';
        chunk->elements[offset + 1] = '.';
        chunk->elements[offset + 2] = '.';
    } else {
        offset = 0;
    }
    completed->bytes = (const char *)chunk->elements + offset;
    completed->length = chunk->count - 1 - offset;
    return VT100_STRING_COMPLETE;
}

void vt100StringReset(TerminalChunk *text)
{
    if (text)
        text->count = 0;
}
