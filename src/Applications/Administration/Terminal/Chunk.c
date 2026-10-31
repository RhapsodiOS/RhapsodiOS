#include "Chunk.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#if defined(__MACH__)
#include <strings.h>
#endif

#define CHUNK_HEADER_SIZE 12u
#define CHUNK_COPY_OFFSET 0x90u /* Observed PPC copy offset. */

#if defined(__NeXT__)
typedef struct _NSZone NSZone;
extern void *NSZoneMalloc(NSZone *zone, unsigned int size);
extern void *NSZoneRealloc(NSZone *zone, void *ptr, unsigned int size);
extern void NSZoneFree(NSZone *zone, void *ptr);
extern NSZone *NSZoneFromPointer(void *ptr);

static void *chunkAllocate(size_t size, void *zone)
{
    return NSZoneMalloc((NSZone *)zone, (unsigned int)size);
}

static void *chunkReallocate(void *ptr, size_t size)
{
    return NSZoneRealloc(NSZoneFromPointer(ptr), ptr, (unsigned int)size);
}

static void chunkRelease(void *ptr)
{
    if (ptr)
        NSZoneFree(NSZoneFromPointer(ptr), ptr);
}

static void *zoneForPointer(const void *ptr)
{
    return NSZoneFromPointer((void *)ptr);
}
#else
static void *chunkAllocate(size_t size, void *zone)
{
    (void)zone;
    return malloc(size);
}

static void *chunkReallocate(void *ptr, size_t size)
{
    return realloc(ptr, size);
}

static void chunkRelease(void *ptr)
{
    free(ptr);
}

static void *zoneForPointer(const void *ptr)
{
    (void)ptr;
    return NULL;
}
#endif

static void *lineAllocate(size_t size, void *zone)
{
    return chunkAllocate(size, zone);
}

static void *lineReallocate(void *ptr, size_t size)
{
    return chunkReallocate(ptr, size);
}

static void lineRelease(void *ptr)
{
    chunkRelease(ptr);
}

static int chunkBytes(uint16_t width, uint32_t capacity, size_t *bytes)
{
    if (width == 0 || capacity > (SIZE_MAX - CHUNK_HEADER_SIZE) / width)
        return 0;
    *bytes = CHUNK_HEADER_SIZE + (size_t)width * capacity;
    return 1;
}

TerminalChunk *ChunkMalloc(uint16_t elementSize, uint16_t growth,
                           uint32_t count, uint32_t minimumCapacity,
                           void *zone)
{
    uint32_t capacity = minimumCapacity > count ? minimumCapacity : count;
    size_t bytes;
    TerminalChunk *chunk;

    if (elementSize == 0 || growth == 0)
        return NULL;
    if (capacity % growth) {
        uint32_t add = growth - capacity % growth;
        if (capacity > UINT32_MAX - add)
            return NULL;
        capacity += add;
    }
    if (!chunkBytes(elementSize, capacity, &bytes))
        return NULL;
    chunk = (TerminalChunk *)chunkAllocate(bytes, zone);
    if (!chunk)
        return NULL;
    chunk->growth = growth;
    chunk->elementSize = elementSize;
    chunk->allocated = capacity;
    chunk->count = count;
    return chunk;
}

TerminalChunk *ChunkGrow(TerminalChunk *chunk, uint32_t capacity)
{
    uint32_t allocated;
    size_t bytes;
    TerminalChunk *grown;

    if (!chunk)
        return NULL;
    allocated = chunk->allocated;
    while (allocated < capacity) {
        if (allocated > UINT32_MAX - chunk->growth)
            return NULL;
        allocated += chunk->growth;
    }
    if (allocated != chunk->allocated) {
        if (!chunkBytes(chunk->elementSize, allocated, &bytes))
            return NULL;
        grown = (TerminalChunk *)chunkReallocate(chunk, bytes);
        if (!grown)
            return NULL;
        chunk = grown;
        chunk->allocated = allocated;
    }
    chunk->count = capacity;
    return chunk;
}

TerminalChunk *ChunkRealloc(TerminalChunk *chunk)
{
    uint32_t capacity;
    size_t bytes;
    TerminalChunk *grown;

    if (!chunk || chunk->allocated > UINT32_MAX - chunk->growth)
        return NULL;
    capacity = chunk->allocated + chunk->growth;
    if (!chunkBytes(chunk->elementSize, capacity, &bytes))
        return NULL;
    grown = (TerminalChunk *)chunkReallocate(chunk, bytes);
    if (!grown)
        return NULL;
    grown->allocated = capacity;
    return grown;
}

TerminalChunk *ChunkCompress(TerminalChunk *chunk)
{
    uint32_t capacity;
    size_t bytes;
    TerminalChunk *shrunk;

    if (!chunk || chunk->growth == 0)
        return NULL;
    capacity = chunk->count;
    if (capacity % chunk->growth) {
        uint32_t add = chunk->growth - capacity % chunk->growth;
        if (capacity > UINT32_MAX - add)
            return NULL;
        capacity += add;
    }
    if (!chunkBytes(chunk->elementSize, capacity, &bytes))
        return NULL;
    shrunk = (TerminalChunk *)chunkReallocate(chunk, bytes);
    if (!shrunk)
        return NULL;
    shrunk->allocated = capacity;
    return shrunk;
}

TerminalChunk *ChunkCopy(const TerminalChunk *source, TerminalChunk *destination)
{
    uint32_t bytes;
    if (!source || !destination)
        return NULL;
    if (destination->allocated < source->count)
        destination = ChunkGrow(destination, source->count);
    if (source->count != 0) {
        bytes = source->count * source->elementSize;
#if defined(__MACH__)
        bcopy((const unsigned char *)source + CHUNK_COPY_OFFSET,
              (unsigned char *)destination + CHUNK_COPY_OFFSET, bytes);
#else
        memmove((unsigned char *)destination + CHUNK_COPY_OFFSET,
                (const unsigned char *)source + CHUNK_COPY_OFFSET, bytes);
#endif
    }
    return destination;
}

TerminalChunk *ChunkDup(const TerminalChunk *source)
{
    TerminalChunk *copy;
    if (!source)
        return NULL;
    copy = ChunkMalloc(source->elementSize, source->growth,
                       source->count, 0, zoneForPointer(source));
    return ChunkCopy(source, copy);
}

TerminalChunk *ChunkAdd(TerminalChunk *chunk, const void *element)
{
    if (!chunk || !element)
        return NULL;
    if (chunk->count == chunk->allocated) {
        chunk = ChunkRealloc(chunk);
        if (!chunk)
            return NULL;
    }
    memmove(chunk->elements + (size_t)chunk->elementSize * chunk->count,
            element, chunk->elementSize);
    ++chunk->count;
    return chunk;
}

void ChunkFree(TerminalChunk *chunk)
{
    chunkRelease(chunk);
}

static size_t lineAllocationSize(uint16_t length)
{
    if (sizeof(void *) == 4)
        return (size_t)length + 12u;
    return offsetof(TerminalLine, text) + (size_t)length + 1u;
}

TerminalLine *reallocNode(TerminalLine *line, int length)
{
    TerminalLine *resized;
    if (sizeof(void *) == 4)
        resized = (TerminalLine *)lineReallocate(line, (size_t)length + 12u);
    else
        resized = (TerminalLine *)lineReallocate(line,
            offsetof(TerminalLine, text) + (size_t)(uint16_t)length + 1u);
    resized->length = (uint16_t)length;
    resized->text[(uint16_t)length] = '\0';
    return resized;
}

static TerminalLine *lineResize(TerminalLine *line, uint16_t length)
{
    return reallocNode(line, length);
}

TerminalLine *lineCreate(const char *text, uint16_t length,
                         uint8_t column, uint8_t attributes)
{
    return lineCreateInZone(text, length, column, attributes, NULL);
}

TerminalLine *lineCreateInZone(const char *text, uint16_t length,
                               uint8_t column, uint8_t attributes,
                               void *zone)
{
    TerminalLine *line;
    if (length == 0 || !text)
        return NULL;
    line = (TerminalLine *)lineAllocate(lineAllocationSize(length), zone);
    if (!line)
        return NULL;
    line->next = NULL;
    line->column = column;
    line->attributes = attributes;
    line->length = length;
    memcpy(line->text, text, length);
    line->text[length] = '\0';
    return line;
}

TerminalLine *newNode(const void *text, size_t length,
                      int8_t column, int8_t attributes, void *zone)
{
    TerminalLine *line;
    size_t allocationSize;

    if (length == 0)
        return NULL;
    if (sizeof(void *) == 4)
        allocationSize = length + 12u;
    else
        allocationSize = offsetof(TerminalLine, text) + length + 1u;
    line = (TerminalLine *)lineAllocate(allocationSize, zone);
    if (!line)
        return NULL;
    line->next = NULL;
    line->column = (uint8_t)column;
    line->attributes = (uint8_t)attributes;
    line->length = (uint16_t)length;
    memcpy(line->text, text, length);
    line->text[length] = '\0';
    return line;
}

TerminalLine *freeLine(TerminalLine *line)
{
    while (line) {
        TerminalLine *next = line->next;
        lineRelease(line);
        line = next;
    }
    return NULL;
}

void lineFree(TerminalLine *line)
{
    (void)freeLine(line);
}

char *lineToString(const TerminalLine *line, char *output)
{
    unsigned int end = 0;
    char *result = (char *)line;

    while (line) {
        while (end < line->column) {
            *output++ = ' ';
            ++end;
        }
        result = strcpy(output, line->text);
        output += line->length;
        end += line->length;
        line = line->next;
    }
    *output = '\0';
    return result;
}

uint32_t lineLength(const TerminalLine *line)
{
    uint32_t length = 0;
    while (line) {
        length = (uint32_t)line->column + line->length;
        line = line->next;
    }
    return length;
}

int charAt(const TerminalLine *line, int column)
{
    while (line) {
        int start = line->column;
        if (start > column)
            return -1;
        if (column < start + line->length)
            return (unsigned char)line->text[column - start];
        line = line->next;
    }
    return -1;
}

void splitLine(TerminalLine *line, uint8_t column,
               TerminalLine **left, TerminalLine **right)
{
    TerminalLine *tail;
    if (!line) {
        if (left) *left = NULL;
        if (right) *right = NULL;
        return;
    }
    if (column < line->column) {
        for (tail = line; tail; tail = tail->next)
            tail->column = (uint8_t)(tail->column - column);
        if (left) *left = NULL;
        if (right) *right = line;
        return;
    }
    if ((uint32_t)line->column + line->length > column) {
        uint16_t prefix = (uint16_t)(column - line->column);
        TerminalLine *suffix = newNode(line->text + prefix,
            (uint16_t)(line->length - prefix), (int8_t)column,
            (int8_t)line->attributes, zoneForPointer(line));
        if (!suffix) {
            if (left) *left = line;
            if (right) *right = NULL;
            return;
        }
        suffix->next = line->next;
        line->next = NULL;
        line->length = prefix;
        line->text[prefix] = '\0';
        for (tail = suffix; tail; tail = tail->next)
            tail->column = (uint8_t)(tail->column - column);
        if (left) *left = line;
        if (right) *right = suffix;
        return;
    }
    {
        TerminalLine *leftTail = NULL;
        TerminalLine *rightHead = NULL;
        splitLine(line->next, column, &leftTail, &rightHead);
        line->next = leftTail;
        if (left) *left = line;
        if (right) *right = rightHead;
    }
}

void lineSplit(TerminalLine *line, uint8_t column,
               TerminalLine **left, TerminalLine **right)
{
    splitLine(line, column, left, right);
}

TerminalLine *overNode(TerminalLine *node)
{
    while (node && node->next) {
        TerminalLine *next = node->next;
        uint32_t end = (uint32_t)node->column + node->length;
        uint32_t nextEnd = (uint32_t)next->column + next->length;
        uint32_t tailLength;

        if (end < next->column) break;

        if (end >= nextEnd) {
            node->next = next->next;
            next->next = NULL;
            lineRelease(next);
            continue;
        }

        if (node->attributes == next->attributes) {
            uint16_t oldLength = node->length;
            uint16_t mergedLength = (uint16_t)(nextEnd - node->column);
            TerminalLine *resized = lineResize(node, mergedLength);

            if (!resized)
                break;
            node = resized;
            tailLength = nextEnd - end;
            memcpy(node->text + oldLength,
                   next->text + (end - next->column), tailLength);
            node->length = mergedLength;
            node->text[mergedLength] = '\0';
            node->next = next->next;
            next->next = NULL;
            lineRelease(next);
            continue;
        }

        if (end > next->column) {
            uint32_t skip = end - next->column;
            tailLength = nextEnd - end;
            memmove(next->text, next->text + skip, tailLength);
            next->column = (uint8_t)end;
            {
                TerminalLine *resized = lineResize(next,
                                                   (uint16_t)tailLength);
                if (resized)
                    node->next = next = resized;
                else {
                    next->length = (uint16_t)tailLength;
                    next->text[tailLength] = '\0';
                }
            }
        }
        break;
    }
    return node;
}

TerminalLine *insertNode(TerminalLine *incoming, TerminalLine *existing)
{
    uint32_t incomingEnd;
    uint32_t existingEnd;
    uint32_t prefixLength;
    uint32_t suffixLength;
    uint32_t offset;
    TerminalLine *next;
    TerminalLine *suffix;
    TerminalLine *resized;

    if (!incoming) return existing;
    if (!existing) return incoming;

    incomingEnd = (uint32_t)incoming->column + incoming->length;
    existingEnd = (uint32_t)existing->column + existing->length;

    if (existing->column >= incoming->column) {
        incoming->next = existing;
        return overNode(incoming);
    }

    if (incoming->column > existingEnd) {
        existing->next = insertNode(incoming, existing->next);
        return existing;
    }

    if (incomingEnd < existingEnd &&
        incoming->attributes != existing->attributes) {
        prefixLength = incoming->column - existing->column;
        suffixLength = existingEnd - incomingEnd;
        suffix = newNode(existing->text + prefixLength + incoming->length,
                         (uint16_t)suffixLength, (int8_t)incomingEnd,
                         (int8_t)existing->attributes,
                         zoneForPointer(existing));
        if (!suffix) {
            lineFree(incoming);
            return existing;
        }
        next = existing->next;
        resized = lineResize(existing, (uint16_t)prefixLength);
        if (!resized) {
            lineFree(suffix);
            lineFree(incoming);
            return existing;
        }
        existing = resized;
        existing->next = incoming;
        incoming->next = suffix;
        suffix->next = next;
        return existing;
    }

    if (incoming->attributes == existing->attributes) {
        offset = incoming->column - existing->column;
        next = existing->next;
        if (incomingEnd > existingEnd) {
            resized = lineResize(existing,
                                 (uint16_t)(incomingEnd - existing->column));
            if (!resized) {
                lineFree(incoming);
                return existing;
            }
            existing = resized;
        }
        memcpy(existing->text + offset, incoming->text, incoming->length);
        if (incomingEnd > existingEnd)
            existing->length = (uint16_t)(incomingEnd - existing->column);
        existing->text[existing->length] = '\0';
        existing->next = next;
        lineFree(incoming);
        return overNode(existing);
    }

    prefixLength = incoming->column - existing->column;
    next = existing->next;
    resized = lineResize(existing, (uint16_t)prefixLength);
    if (!resized) {
        lineFree(incoming);
        return existing;
    }
    existing = resized;
    existing->next = incoming;
    incoming->next = next;
    incoming = overNode(incoming);
    existing->next = incoming;
    return existing;
}

TerminalLine *lineInsert(TerminalLine *incoming, TerminalLine *existing)
{
    return insertNode(incoming, existing);
}

TerminalLine *insertChars(TerminalLine *line, uint32_t column,
                          uint32_t count)
{
    (void)column;
    (void)count;
    return line;
}

TerminalLine *lineTruncate(TerminalLine *line, uint32_t column)
{
    return truncateLine(line, column);
}

TerminalLine *truncateLine(TerminalLine *line, uint32_t column)
{
    unsigned int end;
    if (!line) return NULL;
    if (column <= line->column) return freeLine(line);
    end = (unsigned int)line->column + line->length;
    if (column >= end) {
        line->next = truncateLine(line->next, column);
        return line;
    }
    line = lineResize(line, (uint16_t)(column - line->column));
    line->next = freeLine(line->next);
    return line;
}

TerminalLine *lineClearTo(TerminalLine *line, uint32_t column)
{
    return clearTo(line, column);
}

TerminalLine *clearTo(TerminalLine *line, uint32_t column)
{
    while (line) {
        uint32_t end = (uint32_t)line->column + line->length;
        if (line->column > column) return line;
        if (column < end) {
            uint32_t skip = column - line->column + 1;
            uint16_t remaining = (uint16_t)(line->length - skip);
            memmove(line->text, line->text + skip, remaining);
            line = lineResize(line, remaining);
            if (!line)
                return NULL;
            line->column = (uint8_t)(column + 1);
            return line;
        }
        {
            TerminalLine *next = line->next;
            lineRelease(line);
            line = next;
        }
    }
    return NULL;
}

TerminalLine *lineClearFrom(TerminalLine *line, uint32_t column)
{
    return clearFrom(line, column);
}

TerminalLine *clearFrom(TerminalLine *line, uint32_t column)
{
    if (!line) return NULL;
    if (line->column >= column) return freeLine(line);
    if (column < (uint32_t)line->column + line->length) {
        line->next = freeLine(line->next);
        return lineResize(line, (uint16_t)(column - line->column));
    }
    line->next = clearFrom(line->next, column);
    return line;
}

TerminalLine *lineDeleteChars(TerminalLine *line, uint32_t column,
                              uint32_t count)
{
    return deleteChars(line, column, count);
}

TerminalLine *deleteChars(TerminalLine *line, uint32_t column,
                          uint32_t count)
{
    (void)column;
    (void)count;
    return line;
}

TerminalLine *appendLines(TerminalLine *line, TerminalLine *append)
{
    TerminalLine *tail = line;
    TerminalLine *previous = NULL;
    uint32_t offset = 0;
    if (line) {
        while (tail->next) { previous = tail; tail = tail->next; }
        offset = (uint32_t)tail->column + tail->length;
    }
    if (!append) return line;
    {
        TerminalLine *node;
        for (node = append; node; node = node->next)
            node->column = (uint8_t)(node->column + offset);
    }
    if (!line) return append;
    if ((uint32_t)tail->column + tail->length == append->column &&
        tail->attributes == append->attributes &&
        (uint32_t)tail->length + append->length <= UINT16_MAX) {
        uint16_t oldLength = tail->length;
        uint16_t appendLength = append->length;
        TerminalLine *rest = append->next;
        TerminalLine *grown = lineResize(tail, (uint16_t)(oldLength + appendLength));
        if (!grown) return line;
        memcpy(grown->text + oldLength, append->text, appendLength + 1u);
        grown->next = rest;
        lineRelease(append);
        if (previous) previous->next = grown;
        else line = grown;
    } else {
        tail->next = append;
    }
    return line;
}

TerminalLine *lineAppend(TerminalLine *line, TerminalLine *append)
{
    return appendLines(line, append);
}
