#ifndef TERMINAL_SCREEN_H
#define TERMINAL_SCREEN_H

#include "Chunk.h"


#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t line;
    uint32_t metadata;
} TerminalLineSlot32;

typedef struct {
    TerminalLine *line;
    uint32_t metadata;
} TerminalLineSlot;

typedef struct {
    uint32_t line;
    uint8_t wrapped;
    uint8_t reserved[3];
} TerminalChunkLineEntry32;

/* The FieldView chunk stores the reference's 4-byte pointer plus wrap word. */
#if defined(__ppc__) || defined(__i386__)
typedef char TerminalChunkLinePointerMustBe32Bits[(sizeof(void *) == 4) ? 1 : -1];
#endif

static inline TerminalLine *terminalLineAt(const TerminalChunk *rows,
                                           uint32_t index)
{
    return *(TerminalLine *const *)(rows->elements + (size_t)index * 8);
}

static inline void terminalLineSet(TerminalChunk *rows, uint32_t index,
                                   TerminalLine *line)
{
    *(TerminalLine **)(rows->elements + (size_t)index * 8) = line;
}

static inline uint8_t terminalLineIsWrapped(const TerminalChunk *rows,
                                            uint32_t index)
{
    return rows->elements[(size_t)index * 8 + 4];
}

static inline void terminalLineSetWrapped(TerminalChunk *rows, uint32_t index,
                                          uint8_t wrapped)
{
    rows->elements[(size_t)index * 8 + 4] = wrapped;
}

typedef struct {
    TerminalLineSlot *rows;
    uint32_t count;
    uint32_t capacity;
    uint32_t height;
    uint32_t topLine;
    uint32_t growth;
} TerminalLineBuffer;

typedef struct {
    uint32_t line;
    uint8_t col;
} TerminalDelimiterPoint;

typedef struct {
    TerminalDelimiterPoint start;
    TerminalDelimiterPoint end;
    uint8_t isLit;
} TerminalHighlightRange;

typedef struct {
    TerminalDelimiterPoint start;
    TerminalDelimiterPoint end;
    TerminalHighlightRange highlights[2];
    uint8_t highlightCount;
    uint8_t backwards;
} TerminalDragUpdate;

int terminalFindMatchingDelimiter(const TerminalChunk *lines,
                                 uint32_t startLine,
                                 uint8_t startColumn, uint8_t width,
                                 const char *delimiters, char backwards,
                                 TerminalDelimiterPoint *result);
int terminalShiftClickMovesEnd(unsigned int selectionMode,
                               unsigned int width,
                               unsigned int startLine,
                               unsigned int startColumn,
                               unsigned int endLine,
                               unsigned int endColumn,
                               unsigned int clickLine,
                               unsigned int clickColumn);
void terminalDragUpdate(TerminalDelimiterPoint start,
                        TerminalDelimiterPoint end,
                        TerminalDelimiterPoint click, char backwards,
                        TerminalDragUpdate *update);
int terminalTripleClickRowRange(const uint8_t *wrappedRows,
                                size_t stride, uint32_t rowCount,
                                uint32_t clickedRow,
                                uint32_t *firstRow, uint32_t *lastRow);
int terminalClearScrollbackRange(const uint8_t *wrappedRows, size_t stride,
                                 uint32_t rowCount, uint32_t screenHeight,
                                 uint32_t cursorY, uint32_t *firstRow,
                                 uint32_t *lastRow);

int terminalLineBufferInit(TerminalLineBuffer *buffer, uint32_t height,
                           uint32_t growth);
int terminalLineBufferAppend(TerminalLineBuffer *buffer, TerminalLine *line,
                             uint32_t metadata);
int terminalLineBufferScrollUp(TerminalLineBuffer *buffer, uint32_t from,
                               uint32_t to, uint32_t count,
                               int preserveScrollback);
int terminalLineBufferScrollDown(TerminalLineBuffer *buffer, uint32_t from,
                                 uint32_t to, uint32_t count);
TerminalChunk *terminalLineBufferScrollUpRows(TerminalChunk *rows,
                                              uint32_t oldCount,
                                              uint32_t height, uint32_t from,
                                              uint32_t to, uint32_t lines);
TerminalChunk *terminalLineBufferClearRows(TerminalChunk *rows,
                                           uint32_t oldCount,
                                           uint32_t height, uint32_t from,
                                           uint32_t to);
int terminalLineBufferPruneTo(TerminalLineBuffer *buffer, uint32_t keepCount);
void terminalLineBufferDestroy(TerminalLineBuffer *buffer);

typedef struct {
    uint32_t firstLine;
    uint32_t secondLine;
    int active;
} TerminalSelection;

typedef void (*TerminalSelectionClearCallback)(void *context);

int terminalSelectionPrune(TerminalSelection *selection,
                           uint32_t removedCount,
                           TerminalSelectionClearCallback clearCallback,
                           void *context);

int terminalScrollLinesUp(TerminalLineSlot *rows, uint32_t rowCount,
                          uint32_t from, uint32_t to, uint32_t count);
int terminalScrollLinesDown(TerminalLineSlot *rows, uint32_t rowCount,
                            uint32_t from, uint32_t to, uint32_t count);

#endif
