#include "TerminalScreen.h"
#include "FindCharacters.h"

#include <limits.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

int terminalFindMatchingDelimiter(const TerminalChunk *lines,
                                 uint32_t startLine, uint8_t startColumn,
                                 uint8_t width, const char *delimiters,
                                 char backwards,
                                 TerminalDelimiterPoint *result)
{
    int depth = 0;
    int line = (int)startLine;
    int column = startColumn;
    int reverse = backwards != 0;
    int position;
    TerminalLine *row;

    if (!lines || !delimiters || !*delimiters || !result ||
        startLine >= lines->count)
        return 0;

    if (!reverse)
        ++column;
    for (;;) {
        row = terminalLineAt(lines, (uint32_t)line);
        position = findCharacters(row, (uint32_t)column, delimiters,
                                  (char)reverse);
        while (position != -1) {
            if ((char)charAt(row, position) == *delimiters) {
                ++depth;
            } else if (depth-- == 0) {
                result->line = (uint32_t)line;
                result->col = (uint8_t)position;
                return 1;
            }

            column = position + (reverse ? -1 : 1);
            if (reverse && (uint8_t)column == 0xFF)
                break;
            position = findCharacters(row, (uint32_t)column, delimiters,
                                      (char)reverse);
        }

        if (reverse) {
            if (line == 0)
                break;
            --line;
            column = (int)width - 1;
        } else {
            ++line;
            if ((uint32_t)line >= lines->count)
                break;
            column = 0;
        }
    }
    return 0;
}

int terminalShiftClickMovesEnd(unsigned int selectionMode,
                               unsigned int width,
                               unsigned int startLine,
                               unsigned int startColumn,
                               unsigned int endLine,
                               unsigned int endColumn,
                               unsigned int clickLine,
                               unsigned int clickColumn)
{
    unsigned int start;
    unsigned int end;
    unsigned int click;

    if (selectionMode == 0)
        return 0;
    if (selectionMode == 3)
        return clickLine >= endLine;

    start = startLine * width + startColumn;
    end = endLine * width + endColumn;
    click = clickLine * width + clickColumn;
    if (click <= start)
        return 0;
    if (click >= end)
        return 1;
    return click - start >= end - click;
}

static int compareDelimiterPoints(TerminalDelimiterPoint left,
                                  TerminalDelimiterPoint right)
{
    if (left.line != right.line)
        return left.line < right.line ? -1 : 1;
    if (left.col != right.col)
        return left.col < right.col ? -1 : 1;
    return 0;
}

static void addHighlight(TerminalDragUpdate *update,
                         TerminalDelimiterPoint start,
                         TerminalDelimiterPoint end, uint8_t isLit)
{
    TerminalHighlightRange *range = &update->highlights[update->highlightCount++];

    range->start = start;
    range->end = end;
    range->isLit = isLit;
}

void terminalDragUpdate(TerminalDelimiterPoint start,
                        TerminalDelimiterPoint end,
                        TerminalDelimiterPoint click, char backwards,
                        TerminalDragUpdate *update)
{
    int clickAfterStart;
    int clickAfterEnd;

    update->start = start;
    update->end = end;
    update->highlightCount = 0;
    update->backwards = backwards != 0;
    clickAfterStart = compareDelimiterPoints(click, start) > 0;
    clickAfterEnd = compareDelimiterPoints(click, end) > 0;

    if (update->backwards) {
        if (clickAfterEnd) {
            addHighlight(update, end, click, 1);
            update->end = click;
        } else if (clickAfterStart) {
            addHighlight(update, click, end, 0);
            update->end = click;
        } else {
            addHighlight(update, start, end, 0);
            addHighlight(update, click, start, 1);
            update->end = click;
        }
    } else if (clickAfterStart) {
        if (compareDelimiterPoints(click, end) <= 0) {
            addHighlight(update, start, click, 0);
            update->start = click;
        } else {
            addHighlight(update, start, end, 0);
            addHighlight(update, end, click, 1);
            update->start = click;
        }
    } else {
        addHighlight(update, click, start, 1);
        update->start = click;
    }

    if (compareDelimiterPoints(update->start, update->end) > 0) {
        TerminalDelimiterPoint swap = update->start;
        update->start = update->end;
        update->end = swap;
        update->backwards = !update->backwards;
    }
}

int terminalTripleClickRowRange(const uint8_t *wrappedRows,
                                size_t stride, uint32_t rowCount,
                                uint32_t clickedRow,
                                uint32_t *firstRow, uint32_t *lastRow)
{
    uint32_t first;
    uint32_t last;

    if (!wrappedRows || stride == 0 || !firstRow || !lastRow ||
        clickedRow >= rowCount)
        return 0;
    first = clickedRow;
    while (first != 0 && wrappedRows[(size_t)(first - 1) * stride] != 0)
        --first;
    last = clickedRow;
    while (last + 1 < rowCount && wrappedRows[(size_t)last * stride] != 0)
        ++last;
    *firstRow = first;
    *lastRow = last;
    return 1;
}

int terminalClearScrollbackRange(const uint8_t *wrappedRows, size_t stride,
                                 uint32_t rowCount, uint32_t screenHeight,
                                 uint32_t cursorY, uint32_t *firstRow,
                                 uint32_t *lastRow)
{
    uint32_t screenStart;
    uint32_t first;
    uint32_t last;

    if (!wrappedRows || stride == 0 || !firstRow || !lastRow ||
        screenHeight == 0 || rowCount < screenHeight ||
        cursorY >= screenHeight)
        return 0;

    screenStart = rowCount - screenHeight;
    first = screenStart + cursorY;
    if (first > screenStart) {
        do {
            uint32_t previous = first - 1;
            if (wrappedRows[(size_t)previous * stride] == 0)
                break;
            --first;
            if (previous <= screenStart)
                break;
        } while (1);
    }

    last = screenStart + cursorY;
    while (last < rowCount && wrappedRows[(size_t)last * stride] != 0)
        ++last;

    *firstRow = first;
    *lastRow = last;
    return 1;
}

static int validRegion(const TerminalLineSlot *rows, uint32_t rowCount,
                       uint32_t from, uint32_t to, uint32_t count)
{
    return rows && from <= to && to <= rowCount && count <= to - from;
}

int terminalScrollLinesUp(TerminalLineSlot *rows, uint32_t rowCount,
                          uint32_t from, uint32_t to, uint32_t count)
{
    uint32_t i;
    if (!validRegion(rows, rowCount, from, to, count))
        return 0;
    if (count == 0)
        return 1;
    for (i = from; i < from + count; ++i) {
        lineFree(rows[i].line);
        rows[i].line = NULL;
    }
    memmove(rows + from, rows + from + count,
            (size_t)(to - from - count) * sizeof(*rows));
    memset(rows + to - count, 0, (size_t)count * sizeof(*rows));
    return 1;
}

int terminalScrollLinesDown(TerminalLineSlot *rows, uint32_t rowCount,
                            uint32_t from, uint32_t to, uint32_t count)
{
    uint32_t i;
    if (!validRegion(rows, rowCount, from, to, count))
        return 0;
    if (count == 0)
        return 1;
    for (i = to - count; i < to; ++i) {
        lineFree(rows[i].line);
        rows[i].line = NULL;
    }
    memmove(rows + from + count, rows + from,
            (size_t)(to - from - count) * sizeof(*rows));
    memset(rows + from, 0, (size_t)count * sizeof(*rows));
    return 1;
}

static int reserveRows(TerminalLineBuffer *buffer, uint32_t requested)
{
    uint32_t capacity;
    size_t bytes;
    TerminalLineSlot *rows;

    if (requested <= buffer->capacity)
        return 1;
    capacity = buffer->capacity;
    while (capacity < requested) {
        if (capacity > UINT32_MAX - buffer->growth)
            return 0;
        capacity += buffer->growth;
    }
    if ((size_t)capacity > (size_t)-1 / sizeof(*rows))
        return 0;
    bytes = (size_t)capacity * sizeof(*rows);
    rows = (TerminalLineSlot *)realloc(buffer->rows, bytes);
    if (!rows)
        return 0;
    memset(rows + buffer->capacity, 0,
           (size_t)(capacity - buffer->capacity) * sizeof(*rows));
    buffer->rows = rows;
    buffer->capacity = capacity;
    return 1;
}

int terminalLineBufferInit(TerminalLineBuffer *buffer, uint32_t height,
                           uint32_t growth)
{
    if (!buffer || growth == 0)
        return 0;
    buffer->rows = NULL;
    buffer->count = 0;
    buffer->capacity = 0;
    buffer->height = height;
    buffer->topLine = 0;
    buffer->growth = growth;
    return 1;
}

int terminalLineBufferAppend(TerminalLineBuffer *buffer, TerminalLine *line,
                             uint32_t metadata)
{
    if (!buffer || buffer->count == UINT32_MAX ||
        !reserveRows(buffer, buffer->count + 1u))
        return 0;
    buffer->rows[buffer->count].line = line;
    buffer->rows[buffer->count].metadata = metadata;
    ++buffer->count;
    return 1;
}

int terminalLineBufferScrollUp(TerminalLineBuffer *buffer, uint32_t from,
                               uint32_t to, uint32_t count,
                               int preserveScrollback)
{
    uint32_t oldCount;
    uint32_t base;
    uint32_t newCount;

    if (!buffer || !validRegion(buffer->rows, buffer->count, from, to, count) ||
        buffer->height > buffer->count || to > buffer->height)
        return 0;
    if (!preserveScrollback)
        return terminalScrollLinesUp(buffer->rows, buffer->count,
                                     from, to, count);
    if (count == 0)
        return 1;
    if (buffer->count > UINT32_MAX - count)
        return 0;
    oldCount = buffer->count;
    newCount = oldCount + count;
    base = newCount - buffer->height;
    if (!reserveRows(buffer, newCount))
        return 0;
    if (buffer->topLine == oldCount - buffer->height)
        buffer->topLine += count;
    buffer->count = newCount;

    /* Preserve the visible screen at its new bottom-aligned location. */
    memmove(buffer->rows + base, buffer->rows + base - count,
            (size_t)buffer->height * sizeof(*buffer->rows));
    /* Retain the lines displaced at the start of the scroll region. */
    memmove(buffer->rows + base - count,
            buffer->rows + base + from,
            (size_t)count * sizeof(*buffer->rows));
    memmove(buffer->rows + base + from,
            buffer->rows + base + from + count,
            (size_t)(to - from - count) * sizeof(*buffer->rows));
    memset(buffer->rows + base + to - count, 0,
           (size_t)count * sizeof(*buffer->rows));
    return 1;
}

int terminalLineBufferScrollDown(TerminalLineBuffer *buffer, uint32_t from,
                                 uint32_t to, uint32_t count)
{
    if (!buffer || buffer->height > buffer->count ||
        !validRegion(buffer->rows, buffer->count, from, to, count))
        return 0;
    return terminalScrollLinesDown(buffer->rows, buffer->count,
                                   from, to, count);
}

TerminalChunk *terminalLineBufferScrollUpRows(TerminalChunk *rows,
                                              uint32_t oldCount,
                                              uint32_t height, uint32_t from,
                                              uint32_t to, uint32_t lines)
{
    uint32_t oldBase;
    uint32_t newBase;
    uint32_t newCount;
    unsigned char *elements;

    if (!rows || rows->elementSize != 8 || rows->count != oldCount ||
        height > oldCount || to > height || from > to || lines > to - from ||
        oldCount > UINT32_MAX - lines)
        return NULL;
    if (lines == 0)
        return rows;

    newCount = oldCount + lines;
    rows = ChunkGrow(rows, newCount);
    if (!rows)
        return NULL;
    oldBase = oldCount - height;
    newBase = newCount - height;
    elements = rows->elements;

    memmove(elements + (size_t)newBase * 8,
            elements + (size_t)oldBase * 8,
            (size_t)height * 8);
    memmove(elements + (size_t)oldBase * 8,
            elements + (size_t)(newBase + from) * 8,
            (size_t)lines * 8);
    memmove(elements + (size_t)(newBase + from) * 8,
            elements + (size_t)(newBase + from + lines) * 8,
            (size_t)(to - from - lines) * 8);
    memset(elements + (size_t)(newBase + to - lines) * 8, 0,
           (size_t)lines * 8);
    return rows;
}

TerminalChunk *terminalLineBufferClearRows(TerminalChunk *rows,
                                           uint32_t oldCount,
                                           uint32_t height, uint32_t from,
                                           uint32_t to)
{
    uint32_t count;
    uint32_t oldBase;
    uint32_t newBase;
    unsigned char *elements;

    if (!rows || rows->elementSize != 8 || rows->count != oldCount ||
        height > oldCount || to > height || from > to ||
        oldCount > UINT32_MAX - (to - from))
        return NULL;
    count = to - from;
    if (count == 0)
        return rows;
    rows = ChunkGrow(rows, oldCount + count);
    if (!rows)
        return NULL;
    oldBase = oldCount - height;
    newBase = rows->count - height;
    elements = rows->elements;
    memmove(elements + (size_t)newBase * 8,
            elements + (size_t)oldBase * 8, (size_t)height * 8);
    memmove(elements + (size_t)oldBase * 8,
            elements + (size_t)(newBase + from) * 8, (size_t)count * 8);
    memset(elements + (size_t)(newBase + from) * 8, 0,
           (size_t)count * 8);
    return rows;
}

int terminalLineBufferPruneTo(TerminalLineBuffer *buffer, uint32_t keepCount)
{
    uint32_t removeCount;
    uint32_t i;

    if (!buffer || keepCount > buffer->count)
        return 0;
    removeCount = buffer->count - keepCount;
    for (i = 0; i < keepCount; ++i) {
        if (i < removeCount)
            lineFree(buffer->rows[i].line);
        buffer->rows[i] = buffer->rows[i + removeCount];
    }
    for (i = keepCount; i < buffer->count; ++i) {
        if (i < removeCount)
            lineFree(buffer->rows[i].line);
        buffer->rows[i].line = NULL;
        buffer->rows[i].metadata = 0;
    }
    buffer->count -= removeCount;
    buffer->topLine -= removeCount;
    return 1;
}

int terminalSelectionPrune(TerminalSelection *selection,
                           uint32_t removedCount,
                           TerminalSelectionClearCallback clearCallback,
                           void *context)
{
    if (!selection)
        return 0;
    if (!selection->active)
        return 1;
    if (selection->firstLine >= removedCount &&
        selection->secondLine >= removedCount) {
        selection->firstLine -= removedCount;
        selection->secondLine -= removedCount;
        return 1;
    }
    selection->active = 0;
    if (clearCallback)
        clearCallback(context);
    return 1;
}

void terminalLineBufferDestroy(TerminalLineBuffer *buffer)
{
    uint32_t i;
    if (!buffer)
        return;
    for (i = 0; i < buffer->count; ++i)
        lineFree(buffer->rows[i].line);
    free(buffer->rows);
    buffer->rows = NULL;
    buffer->count = 0;
    buffer->capacity = 0;
}
