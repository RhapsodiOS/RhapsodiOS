#include "../Filer.h"

#include <assert.h>
#include <fcntl.h>
#include <string.h>
#if defined(_WIN32)
#include <io.h>
#define pipe _pipe
#define read _read
#define close _close
#else
#include <unistd.h>
#endif

static void testBufferGrowthAndAppend(void)
{
    TerminalChunk *buffer;
    char bytes[200];
    unsigned int i;

    for (i = 0; i < sizeof(bytes); ++i)
        bytes[i] = (char)(i & 0xff);
    buffer = filerBufferCreate();
    assert(buffer != 0);
    assert(buffer->elementSize == 1);
    assert(buffer->allocated == 0x80);
    buffer = filerBufferAppend(buffer, bytes, sizeof(bytes));
    assert(buffer->count == sizeof(bytes));
    assert(buffer->allocated >= sizeof(bytes));
    assert(memcmp(buffer->elements, bytes, sizeof(bytes)) == 0);
    ChunkFree(buffer);
}

static void testPartialOutputPreservesSuffix(void)
{
    TerminalChunk *buffer;
    char bytes[150];
    char received[150];
    int descriptors[2];
    unsigned int i;

    for (i = 0; i < sizeof(bytes); ++i)
        bytes[i] = (char)('A' + (i % 26));
#if defined(_WIN32)
    assert(_pipe(descriptors, 512, _O_BINARY) == 0);
#else
    assert(pipe(descriptors) == 0);
#endif
    buffer = filerBufferCreate();
    assert(buffer != 0);
    buffer = filerBufferAppend(buffer, bytes, sizeof(bytes));

    assert(filerBufferTryOutput(buffer, descriptors[1]) == 0);
    assert(buffer->count == 50);
    assert(memcmp(buffer->elements, bytes + 100, 50) == 0);
    assert(read(descriptors[0], received, 100) == 100);
    assert(memcmp(received, bytes, 100) == 0);

    assert(filerBufferTryOutput(buffer, descriptors[1]) == 0);
    assert(buffer->count == 0);
    assert(read(descriptors[0], received, 50) == 50);
    assert(memcmp(received, bytes + 100, 50) == 0);

    close(descriptors[0]);
    close(descriptors[1]);
    ChunkFree(buffer);
}

static void testClearQueue(void)
{
    TerminalChunk *buffer;
    static const char byte = 'x';

    buffer = filerBufferCreate();
    assert(buffer != 0);
    buffer = filerBufferAppend(buffer, &byte, 1);
    assert(buffer->count == 1);
    assert(buffer->elements[0] == (unsigned char)byte);
    filerBufferClear(buffer);
    assert(buffer->count == 0);
    ChunkFree(buffer);
}

int main(void)
{
    testBufferGrowthAndAppend();
    testPartialOutputPreservesSuffix();
    testClearQueue();
    return 0;
}
