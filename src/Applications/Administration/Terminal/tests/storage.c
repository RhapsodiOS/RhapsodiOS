#include "../Chunk.h"
#include "../VT100Args.h"
#include "../VT100String.h"
#include "../VT100Parser.h"
#include "../VT100State.h"
#include "../TerminalScreen.h"
#include "../PathCompress.h"
#include "../WordBoundary.h"
#include "../WordSelection.h"
#include "../PasteText.h"
#include "../FindCharacters.h"
#include "../PrintLine.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

TerminalLine *freeLine(TerminalLine *line);
TerminalLine *truncateLine(TerminalLine *line, uint32_t column);
TerminalLine *clearFrom(TerminalLine *line, uint32_t column);
TerminalLine *clearTo(TerminalLine *line, uint32_t column);

typedef struct {
    uint32_t superclass[6];
    int32_t pid;
    uint32_t exitAction;
    char pty[11];
    char ptyPadding;
    uint32_t command;
    int32_t slot;
    char invalidated;
    char padding[3];
} TerminalShellLayout32;

#if defined(_MSC_VER)
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

static void testChunkCopyReferenceOffset(void)
{
    union {
        uint32_t alignment;
        unsigned char bytes[0x94];
    } sourceBacking, destinationBacking;
    TerminalChunk *source = (TerminalChunk *)sourceBacking.bytes;
    TerminalChunk *destination = (TerminalChunk *)destinationBacking.bytes;
    const unsigned char values[] = {0x14, 0xA2, 0x39, 0xE7};

    memset(&sourceBacking, 0, sizeof(sourceBacking));
    memset(&destinationBacking, 0, sizeof(destinationBacking));
    source->growth = 2;
    source->elementSize = 2;
    source->allocated = 2;
    source->count = 2;
    destination->growth = 2;
    destination->elementSize = 2;
    destination->allocated = 2;
    destination->count = 1;
    memcpy(sourceBacking.bytes + 0x90, values, sizeof(values));

    assert(ChunkCopy(source, destination) == destination);
    assert(memcmp(destinationBacking.bytes + 0x90, values,
                  sizeof(values)) == 0);
    assert(destination->count == 1);
}

static void testChunkGrowthAndCompress(void)
{
    TerminalChunk *chunk = ChunkMalloc(1, 4, 0, 2, NULL);
    const unsigned char values[] = {0x00, 0x7f, 0x80, 0xff, 0x35};
    unsigned int i;
    assert(chunk && chunk->allocated == 4 && chunk->count == 0);
    for (i = 0; i < sizeof(values); ++i) {
        chunk = ChunkAdd(chunk, values + i);
        assert(chunk);
    }
    assert(chunk->count == 5 && chunk->allocated == 8);
    assert(memcmp(chunk->elements, values, sizeof(values)) == 0);
    chunk->count = 3;
    chunk = ChunkCompress(chunk);
    assert(chunk && chunk->allocated == 4 && chunk->count == 3);
    ChunkFree(chunk);
}

static void testChunkDupEmpty(void)
{
    TerminalChunk *chunk = ChunkMalloc(1, 4, 0, 2, NULL);
    TerminalChunk *copy;
    assert(chunk);
    copy = ChunkDup(chunk);
    assert(copy && copy->count == 0 && copy->allocated == 0);
    ChunkFree(copy);
    ChunkFree(chunk);
}

static void testChunkFixedWidthElements(void)
{
    uint16_t words[] = {0x0102, 0x80ff, 0xa55a};
    TerminalChunk *chunk = ChunkMalloc(sizeof(words[0]), 2, 0, 0, NULL);
    unsigned int i;
    for (i = 0; i < 3; ++i) {
        chunk = ChunkAdd(chunk, words + i);
        assert(chunk);
    }
    assert(chunk->count == 3 && chunk->allocated == 4);
    assert(memcmp(chunk->elements, words, sizeof(words)) == 0);
    ChunkFree(chunk);
}

static void testChunkAddOverlappingElement(void)
{
    TerminalChunk *chunk = ChunkMalloc(2, 2, 1, 2, NULL);

    assert(chunk != NULL);
    chunk->elements[0] = 0x10;
    chunk->elements[1] = 0x20;
    chunk->elements[2] = 0x30;
    chunk->elements[3] = 0x40;
    chunk = ChunkAdd(chunk, chunk->elements + 1);
    assert(chunk != NULL && chunk->count == 2);
    assert(chunk->elements[2] == 0x20 && chunk->elements[3] == 0x30);
    ChunkFree(chunk);
}

static void testChunkZoneEntryPoint(void)
{
    TerminalChunk *chunk = ChunkMalloc(1, 4, 0, 1, NULL);
    unsigned char value = 0xa5;
    assert(chunk && chunk->allocated == 4);
    chunk = ChunkAdd(chunk, &value);
    assert(chunk && chunk->count == 1 && chunk->elements[0] == value);
    chunk = ChunkCompress(chunk);
    assert(chunk && chunk->allocated == 4);
    ChunkFree(chunk);
}

static void testLineSplitAcrossGap(void)
{
    TerminalLine *first = lineCreate("ab", 2, 0, 1);
    TerminalLine *second = lineCreate("xy", 2, 5, 2);
    TerminalLine *right = NULL;
    char output[16];
    assert(first && second);
    first->next = second;
    lineToString(first, output);
    assert(strcmp(output, "ab   xy") == 0);
    lineSplit(first, 6, &first, &right);
    assert(first && first->length == 2 && first->next && first->next->length == 1);
    assert(right && right->column == 0 && right->length == 1 && right->text[0] == 'y');
    assert(right->next == NULL);
    lineToString(first, output);
    assert(strcmp(output, "ab   x") == 0);
    lineToString(right, output);
    assert(strcmp(output, "y") == 0);
    lineFree(first);
    lineFree(right);
}

static void testLineToStringReturnsLastSpan(void)
{
    TerminalLine *first = lineCreate("ab", 2, 0, 1);
    TerminalLine *second = lineCreate("xy", 2, 5, 2);
    char output[16];
    char *lastSpan;

    assert(first && second);
    first->next = second;
    lastSpan = lineToString(first, output);
    assert(strcmp(output, "ab   xy") == 0);
    assert(lastSpan == output + 5);
    lineFree(first);
}

static void testLineLengthAndFindCharacters(void)
{
    TerminalLine empty = { 0 };
    TerminalLine *line = lineCreate("ab", 2, 0, 1);
    TerminalLine *second = lineCreate("xy", 2, 5, 2);
    char scratch[16];
    assert(line && second);
    line->next = second;
    assert(lineLength(line) == 7);
    assert(terminalFindCharacters(line, 0, " ", 0, scratch, sizeof(scratch)) == 2);
    assert(terminalFindCharacters(line, 4, "xy", 0, scratch, sizeof(scratch)) == 5);
    assert(terminalFindCharacters(line, 99, "y", 1, scratch, sizeof(scratch)) == 6);
    assert(terminalFindCharacters(line, 4, "a", 1, scratch, sizeof(scratch)) == 0);
    assert(terminalFindCharacters(line, 7, "x", 0, scratch, sizeof(scratch)) == -1);
    assert(terminalFindCharacters(line, 0, "z", 0, scratch, sizeof(scratch)) == -1);
    assert(terminalFindCharacters(line, 0, "x", 0, scratch, 2) == -1);
    assert(findCharacters(line, 3, "x", 0) == 5);
    assert(findCharacters(line, 99, "y", 1) == 6);
    assert(findCharacters(line, 4, "a", 1) == 0);
    assert(findCharacters(line, 0, "z", 0) == -1);
    assert(findCharacters(&empty, 0, "", 1) == 0);
    assert(findCharacters(NULL, 0, "x", 0) == -1);
    lineFree(line);
    assert(lineLength(NULL) == 0);
    assert(terminalFindCharacters(NULL, 0, "x", 0, scratch, sizeof(scratch)) == -1);
}

static void testFindMatchingDelimiter(void)
{
    TerminalChunk *rows = ChunkMalloc(8, 2, 2, 2, NULL);
    TerminalChunk *reverseRows;
    TerminalLine *line0 = lineCreate("((x))", 5, 0, 0);
    TerminalLine *line1 = lineCreate("z", 1, 0, 0);
    TerminalLine *reverse0 = lineCreate(")", 1, 0, 0);
    TerminalLine *reverse1 = lineCreate(")", 1, 0, 0);
    TerminalLine *reverse2 = lineCreate("(", 1, 0, 0);
    TerminalDelimiterPoint result;

    assert(rows != NULL && line0 != NULL && line1 != NULL);
    terminalLineSet(rows, 0, line0);
    terminalLineSet(rows, 1, line1);
    assert(terminalFindMatchingDelimiter(rows, 0, 0, 80, "()", 0,
                                         &result) == 1);
    assert(result.line == 0 && result.col == 4);
    assert(terminalFindMatchingDelimiter(rows, 1, 0, 80, "()", 1,
                                         &result) == 1);
    assert(result.line == 0 && result.col == 4);
    assert(terminalFindMatchingDelimiter(rows, 0, 0, 80, "[]", 0,
                                         &result) == 0);
    reverseRows = ChunkMalloc(8, 2, 3, 3, NULL);
    assert(reverseRows != NULL && reverse0 != NULL && reverse1 != NULL &&
           reverse2 != NULL);
    terminalLineSet(reverseRows, 0, reverse0);
    terminalLineSet(reverseRows, 1, reverse1);
    terminalLineSet(reverseRows, 2, reverse2);
    assert(terminalFindMatchingDelimiter(reverseRows, 2, 0, 80, "()", 1,
                                         &result) == 1);
    assert(result.line == 0 && result.col == 0);
    lineFree(reverse0);
    lineFree(reverse1);
    lineFree(reverse2);
    ChunkFree(reverseRows);
    lineFree(line0);
    lineFree(line1);
    ChunkFree(rows);
}

static void testShiftClickEndpoint(void)
{
    assert(terminalShiftClickMovesEnd(0, 80, 1, 10, 1, 20, 1, 15) == 0);
    assert(terminalShiftClickMovesEnd(1, 80, 1, 10, 1, 20, 1, 10) == 0);
    assert(terminalShiftClickMovesEnd(1, 80, 1, 10, 1, 20, 1, 15) == 1);
    assert(terminalShiftClickMovesEnd(1, 80, 1, 10, 1, 20, 1, 16) == 1);
    assert(terminalShiftClickMovesEnd(1, 80, 1, 10, 1, 20, 1, 20) == 1);
    assert(terminalShiftClickMovesEnd(1, 80, 1, 10, 1, 20, 1, 9) == 0);
    assert(terminalShiftClickMovesEnd(3, 80, 2, 0, 4, 70, 3, 79) == 0);
    assert(terminalShiftClickMovesEnd(3, 80, 2, 0, 4, 70, 4, 0) == 1);
    assert(terminalShiftClickMovesEnd(2, 80, 1, 70, 2, 10, 1, 75) == 0);
    assert(terminalShiftClickMovesEnd(2, 80, 1, 70, 2, 10, 2, 5) == 1);
}

static void testDragUpdate(void)
{
    TerminalDelimiterPoint start = { 2, 10 };
    TerminalDelimiterPoint end = { 4, 20 };
    TerminalDelimiterPoint click = { 3, 0 };
    TerminalDragUpdate update;

    terminalDragUpdate(start, end, click, 0, &update);
    assert(update.start.line == 3 && update.start.col == 0);
    assert(update.end.line == 4 && update.end.col == 20);
    assert(update.backwards == 0 && update.highlightCount == 1);
    assert(update.highlights[0].start.line == 2 &&
           update.highlights[0].end.line == 3 &&
           update.highlights[0].isLit == 0);

    click.line = 4;
    click.col = 20;
    terminalDragUpdate(start, end, click, 0, &update);
    assert(update.start.line == 4 && update.start.col == 20);
    assert(update.highlightCount == 1 && update.highlights[0].isLit == 0);

    click.line = 1;
    click.col = 5;
    terminalDragUpdate(start, end, click, 0, &update);
    assert(update.start.line == 1 && update.start.col == 5);
    assert(update.end.line == 4 && update.end.col == 20);
    assert(update.highlights[0].start.line == 1 &&
           update.highlights[0].end.line == 2 &&
           update.highlights[0].isLit == 1);

    click.line = 5;
    click.col = 0;
    terminalDragUpdate(start, end, click, 0, &update);
    assert(update.start.line == 4 && update.start.col == 20);
    assert(update.end.line == 5 && update.end.col == 0);
    assert(update.backwards == 1 && update.highlightCount == 2);
    assert(update.highlights[0].isLit == 0 &&
           update.highlights[1].isLit == 1);

    click.line = 1;
    click.col = 0;
    terminalDragUpdate(end, start, click, 1, &update);
    assert(update.start.line == 1 && update.start.col == 0);
    assert(update.end.line == 4 && update.end.col == 20);
    assert(update.backwards == 0 && update.highlightCount == 2);
    assert(update.highlights[0].isLit == 0 &&
           update.highlights[1].isLit == 1);

    click.line = 3;
    click.col = 0;
    terminalDragUpdate(end, start, click, 1, &update);
    assert(update.start.line == 3 && update.start.col == 0);
    assert(update.end.line == 4 && update.end.col == 20);
    assert(update.backwards == 0 && update.highlightCount == 1);
    assert(update.highlights[0].isLit == 1);

    click.line = 5;
    click.col = 0;
    terminalDragUpdate(end, start, click, 1, &update);
    assert(update.start.line == 4 && update.start.col == 20);
    assert(update.end.line == 5 && update.end.col == 0);
    assert(update.backwards == 1 && update.highlightCount == 1);
    assert(update.highlights[0].isLit == 1);
}

static void testTripleClickRows(void)
{
    const uint8_t wrapped[] = { 1, 1, 0, 0, 1, 0 };
    uint32_t first;
    uint32_t last;

    assert(terminalTripleClickRowRange(wrapped, 1, 6, 1, &first, &last));
    assert(first == 0 && last == 2);
    assert(terminalTripleClickRowRange(wrapped, 1, 6, 4, &first, &last));
    assert(first == 4 && last == 5);
    assert(!terminalTripleClickRowRange(wrapped, 1, 6, 6, &first, &last));

    {
        uint8_t rowSlots[48] = { 0 };
        rowSlots[0] = 1;
        rowSlots[8] = 1;
        rowSlots[32] = 1;
        assert(terminalTripleClickRowRange(rowSlots, 8, 6, 1,
                                            &first, &last));
        assert(first == 0 && last == 2);
        assert(terminalTripleClickRowRange(rowSlots, 8, 6, 4,
                                            &first, &last));
        assert(first == 4 && last == 5);
    }
}
static void testLineCharacterAtColumn(void)
{
    TerminalLine *line = lineCreate("ab", 2, 2, 0);
    TerminalLine *tail = lineCreate("x", 1, 6, 0);
    assert(line && tail);
    line->next = tail;
    assert(charAt(NULL, 0) == -1);
    assert(charAt(line, 1) == -1);
    assert(charAt(line, 2) == 'a');
    assert(charAt(line, 3) == 'b');
    assert(charAt(line, 4) == -1);
    assert(charAt(line, 6) == 'x');
    assert(charAt(line, 7) == -1);
    lineFree(line);
}

static void testLineZoneEntryPoint(void)
{
    TerminalLine *line = lineCreateInZone("abcd", 4, 0, 3, NULL);
    TerminalLine *right = NULL;
    assert(line && line->length == 4);
    lineSplit(line, 2, &line, &right);
    assert(line && right && line->length == 2 && right->length == 2);
    line = lineClearTo(line, 0);
    assert(line && line->column == 1 && line->length == 1);
    lineFree(line);
    lineFree(right);
}

static void testLineOverlappingColumns(void)
{
    TerminalLine *first = lineCreate("abcd", 4, 0, 1);
    TerminalLine *second = lineCreate("XY", 2, 2, 2);
    char output[16];
    assert(first && second);
    first->next = second;
    lineToString(first, output);
    assert(strcmp(output, "abcdXY") == 0);
    assert(lineLength(first) == 4);
    lineFree(first);
}

static void testTerminalPrintLine(void)
{
    TerminalLine *first = lineCreate("ab", 2, 0, 1);
    TerminalLine *second = lineCreate("xy", 2, 5, 2);
    FILE *stream = tmpfile();
    char output[32];
    assert(first && second && stream);
    first->next = second;
    assert(terminalPrintLine(stream, first) == 0);
    rewind(stream);
    assert(fgets(output, sizeof(output), stream));
    assert(strcmp(output, "ab   xy\n") == 0);
    fclose(stream);
    lineFree(first);

    first = lineCreate("ab", 2, 0, 1);
    second = lineCreate("XY", 2, 1, 2);
    stream = tmpfile();
    assert(first && second && stream);
    first->next = second;
    assert(terminalPrintLine(stream, first) == 0);
    rewind(stream);
    assert(fgets(output, sizeof(output), stream));
    assert(strcmp(output, "abXY\n") == 0);
    fclose(stream);
    lineFree(first);

    stream = tmpfile();
    assert(stream && terminalPrintLine(stream, NULL) == 0);
    rewind(stream);
    assert(fgets(output, sizeof(output), stream));
    assert(strcmp(output, "\n") == 0);
    fclose(stream);
    assert(terminalPrintLine(NULL, NULL) == -1);
}


static void testLineSplitBoundaries(void)
{
    TerminalLine *line = lineCreate("ab", 2, 2, 1);
    TerminalLine *second = lineCreate("cd", 2, 6, 2);
    TerminalLine *right = NULL;
    assert(line && second);
    line->next = second;
    lineSplit(line, 1, &line, &right);
    assert(line == NULL && right && right->column == 1 && right->next && right->next->column == 5);
    lineFree(right);

    line = lineCreate("ab", 2, 0, 1);
    second = lineCreate("cd", 2, 5, 2);
    assert(line && second);
    line->next = second;
    lineSplit(line, 2, &line, &right);
    assert(line && line->length == 2 && line->next == NULL);
    assert(right && right->column == 3);
    lineFree(line); lineFree(right);
}

static void testLineTruncate(void)
{
    TerminalLine *a = lineCreate("abcd", 4, 2, 0);
    TerminalLine *b = lineCreate("ef", 2, 8, 1);
    char output[16];
    assert(a && b);
    a->next = b;
    a = lineTruncate(a, 4);
    assert(a && !a->next && a->length == 2);
    lineToString(a, output);
    assert(strcmp(output, "  ab") == 0);
    lineFree(a);
}

static void testRecoveredTruncateLine(void)
{
    TerminalLine *line = lineCreate("abcd", 4, 0, 0);
    TerminalLine *tail = lineCreate("xy", 2, 7, 0);
    assert(line && tail);
    line->next = tail;
    line = truncateLine(line, 2);
    assert(line && line->length == 2 && line->next == NULL);
    assert(memcmp(line->text, "ab", 3) == 0);
    assert(truncateLine(line, 0) == NULL);
}

static void testRecoveredClearFrom(void)
{
    TerminalLine *line = lineCreate("abcd", 4, 0, 0);
    TerminalLine *tail = lineCreate("xy", 2, 7, 0);
    assert(line && tail);
    line->next = tail;
    line = clearFrom(line, 2);
    assert(line && line->length == 2 && line->next == NULL);
    assert(memcmp(line->text, "ab", 3) == 0);
    lineFree(line);
}

static void testRecoveredFreeLine(void)
{
    TerminalLine *line = lineCreate("a", 1, 0, 0);
    assert(line != NULL);
    line->next = lineCreate("b", 1, 1, 0);
    assert(line->next != NULL);
    assert(freeLine(line) == NULL);
    assert(freeLine(NULL) == NULL);
}


static void testLineClearAndAppend(void)
{
    TerminalLine *line = lineCreate("abcd", 4, 0, 1);
    TerminalLine *other = lineCreate("ef", 2, 0, 1);
    char output[16];
    assert(line && other);
    line = lineAppend(line, other);
    assert(line && !line->next && line->length == 6);
    assert(strcmp(line->text, "abcdef") == 0);
    line = lineClearTo(line, 2);
    assert(line && line->column == 3 && line->length == 3);
    assert(strcmp(line->text, "def") == 0);
    lineToString(line, output);
    assert(strcmp(output, "   def") == 0);
    line = lineClearFrom(line, 5);
    assert(line && !line->next && line->length == 2);
    assert(strcmp(line->text, "de") == 0);
    lineFree(line);
}

static void testAppendLinesAndSplitLineReferenceEntryPoints(void)
{
    TerminalLine *head = lineCreate("ab", 2, 0, 1);
    TerminalLine *tail = lineCreate("cde", 3, 4, 2);
    TerminalLine *append = lineCreate("fg", 2, 0, 2);
    TerminalLine *appendTail = lineCreate("h", 1, 2, 3);
    TerminalLine *left;
    TerminalLine *right = NULL;
    char text[24];

    assert(head && tail && append && appendTail);
    head->next = tail;
    append->next = appendTail;
    head = appendLines(head, append);
    assert(head && head->next && head->next->next);
    assert(head->next->column == 4 && head->next->length == 5);
    assert(strcmp(head->next->text, "cdefg") == 0);
    assert(head->next->next->column == 9 &&
           head->next->next->attributes == 3);
    lineToString(head, text);
    assert(strcmp(text, "ab  cdefgh") == 0);
    lineFree(head);

    head = lineCreate("ab", 2, 0, 1);
    tail = lineCreate("cd", 2, 0, 2);
    assert(head && tail);
    head = appendLines(head, tail);
    assert(head && head->next && head->next->column == 2);
    assert(head->next->attributes == 2);
    lineFree(head);

    head = lineCreate("ab", 2, 0, 1);
    tail = lineCreate("cde", 3, 4, 2);
    assert(head && tail);
    head->next = tail;
    splitLine(head, 5, &left, &right);
    assert(left && left->next && left->next->length == 1);
    assert(strcmp(left->next->text, "c") == 0 && left->next->next == NULL);
    assert(right && right->column == 0 && right->length == 2);
    assert(strcmp(right->text, "de") == 0);
    lineToString(left, text);
    assert(strcmp(text, "ab  c") == 0);
    lineFree(left);
    lineFree(right);
}

static void testNewNodeReferenceEntryPoint(void)
{
    TerminalLine *line;

    line = newNode("node", 4, 7, 3, NULL);
    assert(line != NULL);
    assert(line->next == NULL);
    assert(line->column == 7);
    assert(line->attributes == 3);
    assert(line->length == 4);
    assert(memcmp(line->text, "node", 4) == 0);
    assert(line->text[4] == '\0');
    line = reallocNode(line, 6);
    assert(line != NULL);
    assert(line->length == 6);
    assert(memcmp(line->text, "node", 4) == 0);
    line->text[4] = 's';
    line->text[5] = '!';
    line->text[6] = '\0';
    line = reallocNode(line, 3);
    assert(line != NULL);
    assert(line->length == 3);
    assert(memcmp(line->text, "nod", 3) == 0);
    assert(line->text[3] == '\0');
    freeLine(line);
    assert(newNode(NULL, 0, 0, 0, NULL) == NULL);
}
static void testLineClearToBoundaries(void)
{
    TerminalLine *first = lineCreate("ab", 2, 0, 1);
    TerminalLine *second = lineCreate("xy", 2, 5, 2);
    assert(first && second);
    first->next = second;
    first = lineClearTo(first, 2);
    assert(first == second && first->column == 5 && first->length == 2);
    lineFree(first);

    first = lineCreate("ab", 2, 0, 1);
    second = lineCreate("xy", 2, 5, 2);
    assert(first && second);
    first->next = second;
    first = lineClearTo(first, 5);
    assert(first && first->column == 6 && first->length == 1);
    assert(first->text[0] == 'y');
    lineFree(first);
}

static void testRecoveredClearTo(void)
{
    TerminalLine *line = lineCreate("ab", 2, 2, 0);
    TerminalLine *tail = lineCreate("xy", 2, 7, 0);
    assert(line && tail);
    line->next = tail;
    line = clearTo(line, 3);
    assert(line && line->column == 4 && line->length == 0);
    assert(line->next == tail && tail->column == 7 && tail->length == 2);
    line = clearTo(line, 7);
    assert(line && line->column == 8 && line->length == 1);
    assert(line->text[0] == 'y' && line->next == NULL);
    assert(clearTo(line, 20) == NULL);
}

static void testLineClearFromBoundaries(void)
{
    TerminalLine *first = lineCreate("ab", 2, 0, 1);
    TerminalLine *second = lineCreate("xy", 2, 5, 2);
    assert(first && second);
    first->next = second;
    first = lineClearFrom(first, 5);
    assert(first && !first->next && first->length == 2);
    assert(strcmp(first->text, "ab") == 0);
    lineFree(first);

    first = lineCreate("ab", 2, 0, 1);
    second = lineCreate("xy", 2, 5, 2);
    assert(first && second);
    first->next = second;
    first = lineClearFrom(first, 1);
    assert(first && !first->next && first->length == 1);
    assert(strcmp(first->text, "a") == 0);
    lineFree(first);

    first = lineCreate("ab", 2, 0, 1);
    second = lineCreate("xy", 2, 5, 2);
    assert(first && second);
    first->next = second;
    first = lineClearFrom(first, 0);
    assert(first == NULL);
}


static void testLineInsertAttributeOverlap(void)
{
    TerminalLine *base = lineCreate("abcd", 4, 0, 1);
    TerminalLine *different = lineCreate("XY", 2, 2, 2);
    char output[16];
    assert(base && different);
    base = lineInsert(different, base);
    assert(base && base->column == 0 && base->length == 2);
    assert(base->next && base->next->column == 2 && base->next->length == 2);
    assert(base->next->next == NULL);
    lineToString(base, output);
    assert(strcmp(output, "abXY") == 0);
    lineFree(base);
}

static void testLineInsertKeepsStyledSuffix(void)
{
    TerminalLine *base = lineCreate("abcdef", 6, 2, 1);
    TerminalLine *middle = lineCreate("XYZ", 3, 4, 2);
    char output[16];
    assert(base && middle);
    base = lineInsert(middle, base);
    assert(base && base->column == 2 && base->length == 2);
    assert(base->next && base->next->column == 4 &&
           base->next->length == 3 && base->next->attributes == 2);
    assert(base->next->next && base->next->next->column == 7 &&
           base->next->next->length == 1 &&
           base->next->next->attributes == 1);
    lineToString(base, output);
    assert(strcmp(output, "  abXYZf") == 0);
    lineFree(base);
}

static void testLineInsertMergesAdjacentMatchingStyles(void)
{
    TerminalLine *existing = lineCreate("cd", 2, 2, 1);
    TerminalLine *incoming = lineCreate("ab", 2, 0, 1);
    char output[16];
    assert(existing && incoming);
    existing = lineInsert(incoming, existing);
    assert(existing && existing->column == 0 && existing->length == 4);
    assert(existing->next == NULL && existing->attributes == 1);
    lineToString(existing, output);
    assert(strcmp(output, "abcd") == 0);
    lineFree(existing);
}

static void testLineInsertOverlap(void)
{
    TerminalLine *base = lineCreate("abcd", 4, 0, 1);
    TerminalLine *same = lineCreate("XY", 2, 2, 1);
    TerminalLine *other = lineCreate("zz", 2, 5, 2);
    char output[16];
    assert(base && same && other);
    base = insertNode(same, base);
    lineToString(base, output);
    assert(strcmp(output, "abXY") == 0);
    base = lineInsert(other, base);
    assert(base->next && base->next->column == 5);
    lineFree(base);
}

static void testOverNodePPCBoundaries(void)
{
    TerminalLine *first;
    TerminalLine *middle;
    TerminalLine *last;
    char output[16];

    first = lineCreate("abc", 3, 0, 1);
    middle = lineCreate("xy", 2, 5, 2);
    assert(first && middle);
    first->next = middle;
    assert(overNode(first) == first && first->next == middle);
    assert(first->length == 3 && middle->column == 5 &&
           middle->length == 2);
    lineFree(first);

    first = lineCreate("abcdefgh", 8, 0, 1);
    middle = lineCreate("x", 1, 2, 2);
    last = lineCreate("tail", 4, 10, 3);
    assert(first && middle && last);
    first->next = middle;
    middle->next = last;
    assert(overNode(first) == first && first->next == last);
    lineFree(first);

    first = lineCreate("abcd", 4, 0, 1);
    middle = lineCreate("XYz", 3, 2, 1);
    assert(first && middle);
    first->next = middle;
    first = overNode(first);
    assert(first && first->next == NULL && first->length == 5);
    lineToString(first, output);
    assert(strcmp(output, "abcdz") == 0);
    lineFree(first);
}

static void testInsertCharsStub(void)
{
    TerminalLine *line = lineCreate("abc", 3, 0, 0);
    assert(line != NULL);
    assert(insertChars(line, 1, 1) == line);
    assert(deleteChars(line, 1, 1) == line);
    assert(line->column == 0 && line->length == 3);
    assert(memcmp(line->text, "abc", 4) == 0);
    lineFree(line);
}

static void testVT100Arguments(void)
{
    TerminalChunk *args = ChunkMalloc(2, 4, 0, 1, NULL);
    uint16_t *values;
    unsigned int i;
    assert(args && args->allocated == 4);
    vt100ArgsReset(args);
    assert(args->count == 1);
    assert(vt100ArgsConsume(&args, '1', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, '2', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, ';', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, '3', 0) == VT100_ARGS_CONTINUE);
    values = (uint16_t *)args->elements;
    assert(args->count == 2 && values[0] == 12 && values[1] == 3);
    assert(vt100ArgsConsume(&args, 'm', 0) == VT100_ARGS_DISPATCH_CSI);
    assert(vt100ArgsConsume(&args, 'h', 1) == VT100_ARGS_DISPATCH_PRIVATE);
    vt100ArgsReset(args);
    for (i = 0; i < 4; ++i)
        assert(vt100ArgsConsume(&args, ';', 0) == VT100_ARGS_CONTINUE);
    assert(args->allocated == 8 && args->count == 5);
    values = (uint16_t *)args->elements;
    for (i = 0; i < args->count; ++i)
        assert(values[i] == 0);
    vt100ArgsReset(args);
    assert(vt100ArgsConsume(&args, '6', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, '5', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, '5', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, '3', 0) == VT100_ARGS_CONTINUE);
    assert(vt100ArgsConsume(&args, '6', 0) == VT100_ARGS_CONTINUE);
    assert(((uint16_t *)args->elements)[0] == 0);
    ChunkFree(args);
}

static void testVT100StringCollection(void)
{
    TerminalChunk *text = ChunkMalloc(1, 4, 0, 4, NULL);
    VT100StringView view;
    unsigned int i;
    assert(text);
    vt100StringReset(text);
    assert(vt100StringConsume(&text, 'A', &view) == VT100_STRING_CONTINUE);
    assert(vt100StringConsume(&text, 0x1b, &view) == VT100_STRING_COMPLETE);
    assert(view.length == 1 && view.bytes[0] == 'A' && view.bytes[1] == 0);
    vt100StringReset(text);
    for (i = 0; i < VT100_STRING_DISPLAY_LIMIT; ++i)
        assert(vt100StringConsume(&text, 'x', &view) == VT100_STRING_CONTINUE);
    assert(vt100StringConsume(&text, 0x07, &view) == VT100_STRING_COMPLETE);
    assert(view.length == VT100_STRING_DISPLAY_LIMIT - 1u);
    assert(memcmp(view.bytes, "...", 3) == 0);
    assert(view.bytes[view.length] == 0);
    vt100StringReset(text);
    for (i = 0; i < VT100_STRING_LIMIT; ++i)
        assert(vt100StringConsume(&text, 'y', &view) == VT100_STRING_CONTINUE);
    assert(vt100StringConsume(&text, 'z', &view) == VT100_STRING_COMPLETE);
    assert(view.length == VT100_STRING_DISPLAY_LIMIT - 1u);
    assert(memcmp(view.bytes, "...", 3) == 0);
    assert(view.bytes[3] == 'y' && view.bytes[view.length - 1] == 'y');
    assert(view.bytes[view.length] == 0);
    ChunkFree(text);
}

static void testVT100CSIState(void)
{
    TerminalChunk *args = ChunkMalloc(2, 4, 0, 1, NULL);
    VT100Parser parser;
    uint16_t *values;
    assert(args);
    vt100ParserInit(&parser, args);
    assert(vt100ParserBeginCSI(&parser, '2') == VT100_ARGS_CONTINUE);
    assert(parser.collectingCSI && !parser.privateMode);
    assert(vt100ParserConsumeCSI(&parser, ';') == VT100_ARGS_CONTINUE);
    assert(vt100ParserConsumeCSI(&parser, '4') == VT100_ARGS_CONTINUE);
    assert(vt100ParserConsumeCSI(&parser, 'H') == VT100_ARGS_DISPATCH_CSI);
    assert(!parser.collectingCSI && parser.command == 'H');
    values = (uint16_t *)args->elements;
    assert(args->count == 2 && values[0] == 2 && values[1] == 4);
    assert(vt100ParserBeginCSI(&parser, '?') == VT100_ARGS_CONTINUE);
    assert(parser.collectingCSI && parser.privateMode && args->count == 1);
    assert(vt100ParserConsumeCSI(&parser, '1') == VT100_ARGS_CONTINUE);
    assert(vt100ParserConsumeCSI(&parser, 'h') == VT100_ARGS_DISPATCH_PRIVATE);
    assert(parser.command == 'h' && !parser.collectingCSI);
    assert(((uint16_t *)args->elements)[0] == 1);
    ChunkFree(args);
}

typedef struct {
    unsigned int calls;
    uint8_t first;
    uint8_t second;
    uint8_t third;
} ScrollResult;

static void recordScrollUp(void *context, uint8_t lines)
{
    ScrollResult *result = (ScrollResult *)context;
    ++result->calls;
    result->first = lines;
}

static void recordScrollDown(void *context, uint8_t from, uint8_t to,
                             uint8_t lines)
{
    ScrollResult *result = (ScrollResult *)context;
    ++result->calls;
    result->first = from;
    result->second = to;
    result->third = lines;
}

static void recordDeleteChars(void *context, uint8_t row, uint8_t column,
                              uint32_t count)
{
    ScrollResult *result = (ScrollResult *)context;
    ++result->calls;
    result->first = row;
    result->second = column;
    result->third = (uint8_t)count;
}

static void testVT100DeleteDispatch(void)
{
    VT100State state;
    ScrollResult result;
    TerminalLine *line = lineCreate("abcdef", 6, 0, 1);
    TerminalLine *same;
    memset(&state, 0, sizeof(state));
    memset(&result, 0, sizeof(result));
    assert(line);
    state.cursorRow = 7;
    state.cursorColumn = 3;
    vt100DeleteChars(&state, 0, recordDeleteChars, &result);
    assert(result.calls == 1 && result.first == 7 && result.second == 3 &&
           result.third == 1);
    vt100DeleteChars(&state, 4, recordDeleteChars, &result);
    assert(result.calls == 2 && result.third == 4);
    same = lineDeleteChars(line, 2, 2);
    assert(same == line && same->length == 6 &&
           memcmp(same->text, "abcdef", 6) == 0);
    lineFree(line);
}

static void testVT100Linefeeds(void)
{
    VT100State state;
    ScrollResult result;
    memset(&state, 0, sizeof(state));
    memset(&result, 0, sizeof(result));
    state.height = 24;
    state.drawCursorOK = 24;
    state.cursorRow = 22;
    vt100Linefeed(&state, recordScrollUp, &result);
    assert(state.cursorRow == 23 && result.calls == 0);
    vt100Linefeed(&state, recordScrollUp, &result);
    assert(state.cursorRow == 23 && result.calls == 1 && result.first == 1);
    state.cursorRow = 5;
    vt100Linefeed(&state, recordScrollUp, &result);
    assert(state.cursorRow == 6 && result.calls == 1);
    state.bottom = 4;
    state.drawCursorOK = 20;
    state.cursorRow = 4;
    vt100ReverseLinefeed(&state, recordScrollDown, &result);
    assert(state.cursorRow == 4 && result.calls == 2);
    assert(result.first == 4 && result.second == 20 && result.third == 1);
    state.cursorRow = 1;
    vt100ReverseLinefeed(&state, recordScrollDown, &result);
    assert(state.cursorRow == 0 && result.calls == 2);
    vt100ReverseLinefeed(&state, recordScrollDown, &result);
    assert(state.cursorRow == 0 && result.calls == 2);
    state.height = 0;
    vt100Linefeed(&state, recordScrollUp, &result);
    assert(state.cursorRow == 255 && result.calls == 2);
}

static void testVT100ResetState(void)
{
    VT100State state;
    TerminalChunk *tabs = ChunkMalloc(1, 8, 0, 16, NULL);
    unsigned int i;
    assert(tabs);
    tabs->count = 16;
    state.flags = 0xffffffffu;
    state.videoFlags = 0xffffffffu;
    state.terminalFlags = 0xffffffffu;
    state.width = 16;
    state.height = 24;
    state.bottom = 9;
    state.drawCursorOK = 12;
    state.cursorRow = 7;
    state.cursorColumn = 6;
    assert(vt100ResetState(&state, tabs, 0, 0, 0));
    assert(state.flags == ((0xffffffffu & 0xEC7FFFFFu) | 0x10000000u));
    assert(state.videoFlags == 0x1400ffffu);
    assert(state.terminalFlags == 0x0fff7fffu);
    assert(state.bottom == 0 && state.drawCursorOK == 16);
    assert(state.cursorRow == 0 && state.cursorColumn == 0);
    assert(tabs->count == 16);
    for (i = 0; i < 16; ++i)
        assert(tabs->elements[i] == (unsigned char)((i & 7u) == 0));
    state.width = 17;
    assert(!vt100ResetState(&state, tabs, 0, 0, 0));
    ChunkFree(tabs);
}

static void testTerminalChunkLineEntryLayout(void)
{
    TerminalChunkLineEntry32 entry;
    memset(&entry, 0, sizeof(entry));
    entry.line = 0x12345678u;
    entry.wrapped = 1;
    assert(sizeof(entry) == 8);
    assert(offsetof(TerminalChunkLineEntry32, wrapped) == 4);
    assert(((unsigned char *)&entry)[4] == 1);
    assert(((unsigned char *)&entry)[5] == 0);
    assert(((unsigned char *)&entry)[6] == 0);
    assert(((unsigned char *)&entry)[7] == 0);
}

static void testTerminalLineScrolling(void)
{
    TerminalLineSlot rows[6];
    unsigned int i;
    memset(rows, 0, sizeof(rows));
    assert(sizeof(TerminalLineSlot32) == 8);
    for (i = 0; i < 6; ++i) {
        char text[2];
        text[0] = (char)('A' + i);
        text[1] = '\0';
        rows[i].line = lineCreate(text, 1, 0, (uint8_t)i);
        rows[i].metadata = 100u + i;
        assert(rows[i].line);
    }
    assert(terminalScrollLinesUp(rows, 6, 1, 5, 2));
    assert(rows[0].line->text[0] == 'A' && rows[0].metadata == 100);
    assert(rows[1].line->text[0] == 'D' && rows[1].metadata == 103);
    assert(rows[2].line->text[0] == 'E' && rows[2].metadata == 104);
    assert(rows[3].line == NULL && rows[3].metadata == 0);
    assert(rows[4].line == NULL && rows[4].metadata == 0);
    assert(rows[5].line->text[0] == 'F' && rows[5].metadata == 105);
    rows[3].line = lineCreate("x", 1, 0, 7);
    rows[3].metadata = 107;
    rows[4].line = lineCreate("y", 1, 0, 8);
    rows[4].metadata = 108;
    assert(rows[3].line && rows[4].line);
    assert(terminalScrollLinesDown(rows, 6, 1, 5, 2));
    assert(rows[0].line->text[0] == 'A' && rows[0].metadata == 100);
    assert(rows[1].line == NULL && rows[1].metadata == 0);
    assert(rows[2].line == NULL && rows[2].metadata == 0);
    assert(rows[3].line->text[0] == 'D' && rows[3].metadata == 103);
    assert(rows[4].line->text[0] == 'E' && rows[4].metadata == 104);
    assert(rows[5].line->text[0] == 'F' && rows[5].metadata == 105);
    assert(terminalScrollLinesUp(rows, 6, 2, 4, 0));
    assert(!terminalScrollLinesDown(rows, 6, 3, 2, 1));
    assert(!terminalScrollLinesUp(rows, 6, 0, 7, 1));
    for (i = 0; i < 6; ++i)
        lineFree(rows[i].line);
}

static void testTerminalScrollbackGrowth(void)
{
    TerminalLineBuffer buffer;
    TerminalChunk *rows;
    unsigned int i;

    rows = ChunkMalloc(8, 4, 8, 8, NULL);
    assert(rows);
    for (i = 0; i < rows->count; ++i) {
        uint32_t pair[2];
        pair[0] = i + 1;
        pair[1] = 100 + i;
        memcpy(rows->elements + (size_t)i * 8, pair, sizeof(pair));
    }
    rows = terminalLineBufferScrollUpRows(rows, 8, 4, 1, 4, 1);
    assert(rows && rows->count == 9);
    assert(((uint32_t *)(rows->elements + 4 * 8))[0] == 6);
    assert(((uint32_t *)(rows->elements + 4 * 8))[1] == 105);
    assert(((uint32_t *)(rows->elements + 5 * 8))[0] == 5);
    assert(((uint32_t *)(rows->elements + 6 * 8))[0] == 7);
    assert(((uint32_t *)(rows->elements + 7 * 8))[0] == 8);
    assert(((uint32_t *)(rows->elements + 8 * 8))[0] == 0);
    ChunkFree(rows);

    rows = ChunkMalloc(8, 4, 8, 8, NULL);
    assert(rows);
    for (i = 0; i < rows->count; ++i) {
        uint32_t pair[2];
        pair[0] = i + 1;
        pair[1] = 100 + i;
        memcpy(rows->elements + (size_t)i * 8, pair, sizeof(pair));
    }
    rows = terminalLineBufferClearRows(rows, 8, 4, 1, 3);
    assert(rows && rows->count == 10);
    assert(((uint32_t *)(rows->elements + 4 * 8))[0] == 6);
    assert(((uint32_t *)(rows->elements + 5 * 8))[0] == 7);
    assert(((uint32_t *)(rows->elements + 6 * 8))[0] == 5);
    assert(((uint32_t *)(rows->elements + 7 * 8))[0] == 0);
    assert(((uint32_t *)(rows->elements + 8 * 8))[0] == 0);
    assert(((uint32_t *)(rows->elements + 9 * 8))[0] == 8);
    ChunkFree(rows);

    assert(terminalLineBufferInit(&buffer, 4, 4));
    for (i = 0; i < 8; ++i) {
        char text[2];
        text[0] = (char)('A' + i);
        text[1] = '\0';
        assert(terminalLineBufferAppend(&buffer,
            lineCreate(text, 1, 0, (uint8_t)i), 200u + i));
    }
    buffer.topLine = 4;
    assert(terminalLineBufferScrollUp(&buffer, 1, 4, 1, 1));
    assert(buffer.count == 9 && buffer.capacity == 12 && buffer.topLine == 5);
    assert(buffer.rows[4].line->text[0] == 'F' && buffer.rows[4].metadata == 205);
    assert(buffer.rows[5].line->text[0] == 'E' && buffer.rows[5].metadata == 204);
    assert(buffer.rows[6].line->text[0] == 'G' && buffer.rows[6].metadata == 206);
    assert(buffer.rows[7].line->text[0] == 'H' && buffer.rows[7].metadata == 207);
    assert(buffer.rows[8].line == NULL && buffer.rows[8].metadata == 0);
    buffer.topLine = 1;
    assert(terminalLineBufferScrollUp(&buffer, 1, 4, 1, 1));
    assert(buffer.count == 10 && buffer.topLine == 1);
    assert(buffer.rows[9].line == NULL);
    assert(!terminalLineBufferScrollUp(&buffer, 0, 4, 5, 1));
    assert(!terminalLineBufferScrollUp(&buffer, 0, 5, 1, 1));
    assert(!terminalLineBufferScrollDown(&buffer, 0, 10, 11));
    terminalLineBufferDestroy(&buffer);
    assert(buffer.rows == NULL && buffer.count == 0);

    assert(terminalLineBufferInit(&buffer, 4, 4));
    for (i = 0; i < 8; ++i) {
        char text[2];
        text[0] = (char)('a' + i);
        text[1] = '\0';
        assert(terminalLineBufferAppend(&buffer,
            lineCreate(text, 1, 0, (uint8_t)i), 500u + i));
    }
    buffer.topLine = 2;
    assert(terminalLineBufferScrollUp(&buffer, 1, 3, 1, 0));
    assert(buffer.count == 8 && buffer.topLine == 2);
    assert(buffer.rows[0].line->text[0] == 'a' && buffer.rows[0].metadata == 500);
    assert(buffer.rows[1].line->text[0] == 'c' && buffer.rows[1].metadata == 502);
    assert(buffer.rows[2].line == NULL && buffer.rows[2].metadata == 0);
    assert(buffer.rows[3].line->text[0] == 'd' && buffer.rows[3].metadata == 503);
    assert(buffer.rows[4].line->text[0] == 'e' && buffer.rows[4].metadata == 504);
    terminalLineBufferDestroy(&buffer);
}

static void testTerminalScrollbackPrune(void)
{
    TerminalLineBuffer buffer;
    unsigned int i;
    assert(terminalLineBufferInit(&buffer, 4, 4));
    for (i = 0; i < 10; ++i) {
        char text[2];
        text[0] = (char)('A' + i);
        text[1] = '\0';
        assert(terminalLineBufferAppend(&buffer,
            lineCreate(text, 1, 0, (uint8_t)i), 300u + i));
    }
    buffer.topLine = 8;
    assert(terminalLineBufferPruneTo(&buffer, 4));
    assert(buffer.count == 4 && buffer.topLine == 2);
    for (i = 0; i < 4; ++i) {
        assert(buffer.rows[i].line->text[0] == (char)('G' + i));
        assert(buffer.rows[i].metadata == 306u + i);
    }
    terminalLineBufferDestroy(&buffer);

    assert(terminalLineBufferInit(&buffer, 4, 4));
    for (i = 0; i < 10; ++i) {
        char text[2];
        text[0] = (char)('A' + i);
        text[1] = '\0';
        assert(terminalLineBufferAppend(&buffer,
            lineCreate(text, 1, 0, (uint8_t)i), 400u + i));
    }
    buffer.topLine = 2;
    assert(terminalLineBufferPruneTo(&buffer, 7));
    assert(buffer.count == 7 && buffer.topLine == UINT32_MAX);
    for (i = 0; i < 7; ++i) {
        assert(buffer.rows[i].line->text[0] == (char)('D' + i));
        assert(buffer.rows[i].metadata == 403u + i);
    }
    for (i = 7; i < 10; ++i)
        assert(buffer.rows[i].line == NULL && buffer.rows[i].metadata == 0);
    assert(!terminalLineBufferPruneTo(&buffer, 8));
    terminalLineBufferDestroy(&buffer);
}

static void recordSelectionClear(void *context)
{
    unsigned int *calls = (unsigned int *)context;
    ++*calls;
}

static void testTerminalSelectionPrune(void)
{
    TerminalSelection selection;
    unsigned int clearCalls = 0;
    selection.firstLine = 4;
    selection.secondLine = 8;
    selection.active = 1;
    assert(terminalSelectionPrune(&selection, 4, recordSelectionClear,
                                  &clearCalls));
    assert(selection.active && selection.firstLine == 0 &&
           selection.secondLine == 4 && clearCalls == 0);

    selection.firstLine = 3;
    selection.secondLine = 5;
    selection.active = 1;
    assert(terminalSelectionPrune(&selection, 4, recordSelectionClear,
                                  &clearCalls));
    assert(!selection.active && selection.firstLine == 3 &&
           selection.secondLine == 5 && clearCalls == 1);

    selection.firstLine = 7;
    selection.secondLine = 2;
    selection.active = 1;
    assert(terminalSelectionPrune(&selection, 4, recordSelectionClear,
                                  &clearCalls));
    assert(!selection.active && clearCalls == 2);

    selection.firstLine = 7;
    selection.secondLine = 9;
    selection.active = 0;
    assert(terminalSelectionPrune(&selection, 4, recordSelectionClear,
                                  &clearCalls));
    assert(!selection.active && selection.firstLine == 7 &&
           selection.secondLine == 9 && clearCalls == 2);
    assert(!terminalSelectionPrune(NULL, 4, recordSelectionClear, &clearCalls));
}

static void testTerminalPathCompress(void)
{
    char result[256];
#if defined(_WIN32)
    _putenv_s("HOME", "/Users/ray");
#else
    setenv("HOME", "/Users/ray", 1);
#endif
    assert(strcmp(pathCompress("/Users/ray/a", result, 20), "~/a") == 0);
    assert(strcmp(pathCompress("/Users/raymond/a", result, 20),
                  "~mond/a") == 0);
#if defined(_WIN32)
    _putenv_s("HOME", "/home/user");
#else
    setenv("HOME", "/home/user", 1);
#endif
    assert(strcmp(pathCompress("/one/two/three/four/file", result, 12),
                  ".../four/file") == 0);
    assert(strcmp(pathCompress("/one/two/longfilename", result, 4),
                  ".../two/longfilename") == 0);
    assert(pathCompress(NULL, result, 4) == NULL);
}

static void testTerminalPasteTextPreparation(void)
{
    char text[] = "a\nb\n";
    char unchanged[] = "a\nb";

    assert(terminalPasteTextPrepare(NULL, 1) == 0);
    assert(terminalPasteTextPrepare("", 1) == 0);
    assert(terminalPasteTextPrepare(text, 1) == 4);
    assert(strcmp(text, "a\rb\r") == 0);
    assert(terminalPasteTextPrepare(unchanged, 0) == 3);
    assert(strcmp(unchanged, "a\nb") == 0);
}

static void testTerminalWordBoundaryPredicates(void)
{
    unsigned int byteValue;
    int alphanumeric;

    assert(terminalStartsLeft('A') && terminalStartsLeft('7'));
    assert(terminalStartsLeft('_') && terminalStartsLeft('~'));
    assert(!terminalStartsLeft('-') && !terminalStartsLeft('/'));
    assert(terminalStartsRight('z') && terminalStartsRight('0'));
    assert(terminalStartsRight('_'));
    assert(!terminalStartsRight('~') && !terminalStartsRight('-'));
    assert(terminalIsWordCharacter('M') && terminalIsWordCharacter('4'));
    assert(terminalIsWordCharacter('_') && terminalIsWordCharacter('\'') &&
           terminalIsWordCharacter('-'));
    assert(!terminalIsWordCharacter('~') && !terminalIsWordCharacter('/'));
    assert(!terminalStartsRight(0x80) && !terminalStartsRight(0xFF));
    assert(!terminalIsWordCharacter(0x80) && !terminalIsWordCharacter(0xFF));
    assert(!startsleft(0x80) && startsleft('_') && startsleft('~'));
    assert(!startsright(0xFF) && startsright('_') && !startsright('~'));
    assert(!iswordchar(0x80) && iswordchar('\'') && iswordchar('-'));
    assert(!startsleft(-1) && !startsright(256) && !iswordchar(-128));

    for (byteValue = 0; byteValue <= 0xFF; ++byteValue) {
        alphanumeric = (byteValue >= '0' && byteValue <= '9') ||
                       (byteValue >= 'A' && byteValue <= 'Z') ||
                       (byteValue >= 'a' && byteValue <= 'z');
        assert(startsleft((int)byteValue) ==
               (alphanumeric || byteValue == '_' || byteValue == '~'));
        assert(startsright((int)byteValue) ==
               (alphanumeric || byteValue == '_'));
        assert(iswordchar((int)byteValue) ==
               (alphanumeric || byteValue == '_' || byteValue == '\'' ||
                byteValue == '-'));
    }
}

static void testCharacterAttributeOffsets(void)
{
    unsigned int attributes;
    unsigned int selected;
    unsigned int expected;
    unsigned int offset;

    for (attributes = 0; attributes < 16; ++attributes) {
        for (selected = 0; selected < 16; ++selected) {
            switch (attributes & 3) {
            case 0: expected = attributes; break;
            default: expected = (attributes & 0xFC) | 2; break;
            }
            offset = 0;
            switch (expected) {
            case 2: offset = (selected & 2) != 0 ? 1 : 0; break;
            case 4: offset = (selected & 4) != 0 ? 1 : 0; break;
            case 6:
                offset = (selected & 2) != 0 ? 1 : 0;
                if ((selected & 4) != 0)
                    offset += 2;
                break;
            case 8: offset = (selected & 8) != 0 ? 1 : 0; break;
            case 10:
                offset = (selected & 2) != 0 ? 1 : 0;
                if ((selected & 8) != 0)
                    offset += 2;
                break;
            case 12:
                offset = (selected & 4) != 0 ? 1 : 0;
                if ((selected & 8) != 0)
                    offset += 2;
                break;
            case 14:
                offset = (selected & 2) != 0 ? 1 : 0;
                if ((selected & 4) != 0)
                    offset += 2;
                if ((selected & 8) != 0)
                    offset += 4;
                break;
            }
            assert(char_offset((unsigned char)attributes, (char)selected) ==
                   (int)offset);
        }
    }
    assert(char_offset(1, 0x02) == 1);
    assert(char_offset(14, 0x0E) == 7);
    assert(char_offset(0, 0x0E) == 0);
}

static void testTerminalWordSelection(void)
{
    TerminalLine *line;
    unsigned int start;
    unsigned int end;

    line = lineCreate("foo-bar", 7, 0, 0);
    assert(wordEnds(line, 3, &start, &end) == 7 && start == 0 && end == 7);
    assert(nextWord(line, 3) == 7 && prevWord(line, 3) == 0);
    lineFree(line);

    line = lineCreate("'foo-'", 6, 0, 0);
    wordEnds(line, 2, &start, &end);
    assert(start == 1 && end == 4);
    lineFree(line);

    line = lineCreate("~foo", 4, 0, 0);
    wordEnds(line, 0, &start, &end);
    assert(start == 0 && end == 4);
    wordEnds(line, 1, &start, &end);
    assert(start == 0 && end == 4);
    lineFree(line);

    line = lineCreate("  foo ", 6, 0, 0);
    wordEnds(line, 1, &start, &end);
    assert(start == 0 && end == 2);
    lineFree(line);

    line = lineCreate("abc", 3, 0, 0);
    assert(wordEnds(line, 3, &start, &end) == 3 && start == 3 && end == 0);
    lineFree(line);
    assert(wordEnds(NULL, 2, &start, &end) == 0 && start == 0 && end == 0);
}


static void testCompareStrings(void)
{
    const char *first = "alpha";
    const char *second = "beta";
    const char *same = "alpha";

    assert(compareStrings(&first, &second) > 0);
    assert(compareStrings(&second, &first) < 0);
    assert(compareStrings(&first, &same) == 0);
}
static void testTerminalStringSearch(void)
{
    char text[] = "ababa";

    assert(strindex(text, "aba") == text);
    assert(strindex(text, "bab") == text + 1);
    assert(strindex(text, "ac") == NULL);
    assert(strindex(text, "") == NULL);
    assert(strindex(NULL, "a") == NULL);
    assert(strindex(text, NULL) == NULL);
    assert(strrindex(text, "aba") == text + 2);
    assert(strrindex(text, "") == NULL);
}

static void testTerminalCaseInsensitiveStringSearch(void)
{
    char text[] = "aBaBa";

    assert(striindex(text, "ABA") == text);
    assert(striindex(text, "bab") == text + 1);
    assert(striindex(text, "xyz") == NULL);
    assert(striindex(text, "") == NULL);
    assert(stririndex(text, "ABA") == text + 2);
}

int main(void)
{
    assert(offsetof(TerminalShellLayout32, pid) == 24);
    assert(offsetof(TerminalShellLayout32, pty) == 32);
    assert(offsetof(TerminalShellLayout32, command) == 44);
    assert(offsetof(TerminalShellLayout32, invalidated) == 52);
    assert(sizeof(TerminalShellLayout32) == 56);
    assert(sizeof(TerminalChunk) == 16);
    assert(offsetof(TerminalChunk, elements) == 12);
    assert(offsetof(TerminalLine32, text) == 8);
    assert(sizeof(TerminalLine32) == 12);
    testChunkCopyReferenceOffset();
    testChunkGrowthAndCompress();
    testChunkDupEmpty();
    testChunkFixedWidthElements();
    testChunkAddOverlappingElement();
    testChunkZoneEntryPoint();
    testLineSplitAcrossGap();
    testLineToStringReturnsLastSpan();
    testLineLengthAndFindCharacters();
    testLineCharacterAtColumn();
    testFindMatchingDelimiter();
    testShiftClickEndpoint();
    testDragUpdate();
    testTripleClickRows();
    testLineZoneEntryPoint();
    testLineOverlappingColumns();
    testTerminalPrintLine();
    testLineSplitBoundaries();
    testLineTruncate();
    testRecoveredTruncateLine();
    testRecoveredClearFrom();
    testRecoveredFreeLine();
    testLineClearAndAppend();
    testAppendLinesAndSplitLineReferenceEntryPoints();
    testNewNodeReferenceEntryPoint();
    testLineClearToBoundaries();
    testRecoveredClearTo();
    testLineClearFromBoundaries();
    testLineInsertOverlap();
    testLineInsertAttributeOverlap();
    testLineInsertKeepsStyledSuffix();
    testLineInsertMergesAdjacentMatchingStyles();
    testOverNodePPCBoundaries();
    testInsertCharsStub();
    testVT100Arguments();
    testVT100StringCollection();
    testVT100CSIState();
    testVT100ResetState();
    testVT100Linefeeds();
    testVT100DeleteDispatch();
    testTerminalChunkLineEntryLayout();
    testTerminalLineScrolling();
    testTerminalScrollbackGrowth();
    testTerminalScrollbackPrune();
    testTerminalSelectionPrune();
    testTerminalPathCompress();
    testTerminalPasteTextPreparation();
    testTerminalWordBoundaryPredicates();
    testCharacterAttributeOffsets();
    testTerminalWordSelection();
    testCompareStrings();
    testTerminalStringSearch();
    testTerminalCaseInsensitiveStringSearch();
    return 0;
}
