#include "Filer.h"

#include <errno.h>
#include <string.h>
#if defined(_WIN32)
#include <io.h>
#define TERMINAL_WRITE _write
typedef int TerminalWriteResult;
#else
#include <unistd.h>
#define TERMINAL_WRITE write
typedef ssize_t TerminalWriteResult;
#endif

TerminalChunk *filerBufferCreate(void)
{
    return filerBufferCreateInZone(0);
}

TerminalChunk *filerBufferCreateInZone(void *zone)
{
    return ChunkMalloc(1, 0x80, 0, 1, zone);
}

TerminalChunk *filerBufferAppend(TerminalChunk *buffer,
                                 const void *bytes, uint32_t length)
{
    uint32_t count;

    count = buffer->count;
    if (count + length >= buffer->allocated) {
        buffer = ChunkGrow(buffer, count + length);
        buffer->count = count;
    }
    memmove(buffer->elements + buffer->count, bytes, length);
    buffer->count += length;
    return buffer;
}

int tryOutput(TerminalChunk *buffer, int fd)
{
    size_t requested;
    TerminalWriteResult written;
    uint32_t remaining;

    requested = buffer->count;
    if (requested > 100)
        requested = 100;
    written = TERMINAL_WRITE(fd, buffer->elements, (unsigned int)requested);
    if (written > 0) {
        remaining = buffer->count - (uint32_t)written;
        buffer->count = remaining;
        memmove(buffer->elements, buffer->elements + written, remaining);
    } else if (written != 0 && errno == EIO) {
        return -1;
    }
    return 0;
}

int filerBufferTryOutput(TerminalChunk *buffer, int fd)
{
    return tryOutput(buffer, fd);
}

void filerBufferClear(TerminalChunk *buffer)
{
    if (buffer != 0)
        buffer->count = 0;
}
