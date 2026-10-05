#ifndef TERMINAL_CHUNK_H
#define TERMINAL_CHUNK_H

#include <stddef.h>
#include <stdint.h>

/* PPC reference layout: 12-byte header followed by packed fixed-width elements. */
typedef struct {
    uint16_t growth;
    uint16_t elementSize;
    uint32_t allocated;
    uint32_t count;
    unsigned char elements[1];
} TerminalChunk;

TerminalChunk *ChunkMalloc(uint16_t elementSize, uint16_t growth,
                           uint32_t count, uint32_t minimumCapacity,
                           void *zone);
TerminalChunk *ChunkGrow(TerminalChunk *chunk, uint32_t capacity);
TerminalChunk *ChunkRealloc(TerminalChunk *chunk);
TerminalChunk *ChunkCompress(TerminalChunk *chunk);
TerminalChunk *ChunkCopy(const TerminalChunk *source, TerminalChunk *destination);
TerminalChunk *ChunkDup(const TerminalChunk *source);
TerminalChunk *ChunkAdd(TerminalChunk *chunk, const void *element);
void ChunkFree(TerminalChunk *chunk);

/* The original PPC node fields occupy twelve bytes before text. */
typedef struct {
    uint32_t next;
    uint8_t column;
    uint8_t attributes;
    uint16_t length;
    char text[1];
} TerminalLine32;

/* Host-side view keeps native pointers separate from the on-disk/target node. */
typedef struct TerminalLine {
    struct TerminalLine *next;
    uint8_t column;
    uint8_t attributes;
    uint16_t length;
    char text[1];
} TerminalLine;

TerminalLine *lineCreate(const char *text, uint16_t length,
                         uint8_t column, uint8_t attributes);
TerminalLine *lineCreateInZone(const char *text, uint16_t length,
                               uint8_t column, uint8_t attributes,
                               void *zone);
TerminalLine *newNode(const void *text, size_t length,
                      int8_t column, int8_t attributes, void *zone);
TerminalLine *reallocNode(TerminalLine *line, int length);
TerminalLine *overNode(TerminalLine *line);
void lineFree(TerminalLine *line);
TerminalLine *freeLine(TerminalLine *line);
char *lineToString(const TerminalLine *line, char *output);
uint32_t lineLength(const TerminalLine *line);
int charAt(const TerminalLine *line, int column);
void lineSplit(TerminalLine *line, uint8_t column,
               TerminalLine **left, TerminalLine **right);
void splitLine(TerminalLine *line, uint8_t column,
               TerminalLine **left, TerminalLine **right);
TerminalLine *lineInsert(TerminalLine *insert, TerminalLine *line);
TerminalLine *insertNode(TerminalLine *insert, TerminalLine *line);
TerminalLine *insertChars(TerminalLine *line, uint32_t column,
                          uint32_t count);
TerminalLine *deleteChars(TerminalLine *line, uint32_t column,
                          uint32_t count);
TerminalLine *truncateLine(TerminalLine *line, uint32_t column);
TerminalLine *clearFrom(TerminalLine *line, uint32_t column);
TerminalLine *clearTo(TerminalLine *line, uint32_t column);
TerminalLine *lineTruncate(TerminalLine *line, uint32_t column);
TerminalLine *lineClearTo(TerminalLine *line, uint32_t column);
TerminalLine *lineClearFrom(TerminalLine *line, uint32_t column);
TerminalLine *lineDeleteChars(TerminalLine *line, uint32_t column,
                              uint32_t count);
TerminalLine *lineAppend(TerminalLine *line, TerminalLine *append);
TerminalLine *appendLines(TerminalLine *line, TerminalLine *append);

#endif
