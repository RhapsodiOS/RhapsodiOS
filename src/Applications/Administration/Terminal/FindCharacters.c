#include "FindCharacters.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

unsigned char terminalFindIgnoreCase;

int compareStrings(const char **left, const char **right)
{
    return -strcmp(*left, *right);
}
char *strindex(const char *text, const char *needle)
{
    const char *candidate;

    if (!text || !needle || !*text || !*needle)
        return NULL;
    for (candidate = text; *candidate; ++candidate) {
        const char *left = candidate;
        const char *right = needle;
        while (*left && *right && *left == *right) {
            ++left;
            ++right;
        }
        if (!*right)
            return (char *)candidate;
    }
    return NULL;
}

char *strrindex(const char *text, const char *needle)
{
    char *last = NULL;
    char *match;

    while ((match = strindex(text, needle)) != NULL) {
        last = match;
        text = match + 1;
    }
    return last;
}

static unsigned char lowerTerminalChar(char value)
{
    return (unsigned char)tolower((unsigned char)value);
}

char *striindex(const char *text, const char *needle)
{
    const char *candidate;

    if (!text || !needle || !*text || !*needle)
        return NULL;
    for (candidate = text; *candidate; ++candidate) {
        const char *left = candidate;
        const char *right = needle;
        while (*left && *right &&
               lowerTerminalChar(*left) == lowerTerminalChar(*right)) {
            ++left;
            ++right;
        }
        if (!*right)
            return (char *)candidate;
    }
    return NULL;
}

char *stririndex(const char *text, const char *needle)
{
    char *last = NULL;
    char *match;

    while ((match = striindex(text, needle)) != NULL) {
        last = match;
        text = match + 1;
    }
    return last;
}

int terminalFindCharacters(const TerminalLine *line, uint32_t start,
                           const char *characters, int backwards,
                           char *scratch, size_t scratchCapacity)
{
    uint32_t length;
    uint32_t index;

    if (!line || !characters || !scratch)
        return -1;
    length = lineLength(line);
    if ((size_t)length + 1u > scratchCapacity)
        return -1;
    lineToString(line, scratch);
    if (backwards) {
        index = start;
        if (index > length - (length != 0))
            index = length - (length != 0);
        if (length == 0 || index >= length)
            return -1;
        for (;;) {
            if (strchr(characters, (unsigned char)scratch[index]))
                return (int)index;
            if (index == 0)
                break;
            --index;
        }
        return -1;
    }
    if (start >= length)
        return -1;
    for (index = start; index < length; ++index) {
        if (strchr(characters, (unsigned char)scratch[index]))
            return (int)index;
    }
    return -1;
}

int findCharacters(const TerminalLine *line, uint32_t start,
                   const char *characters, char backwards)
{
    uint32_t length = lineLength(line);
    char *scratch;
    int position;

    if (!line)
        return -1;
    scratch = (char *)malloc((size_t)length + 1u);
    if (!scratch)
        return -1;
    lineToString(line, scratch);

    if (backwards) {
        position = (int)start;
        if (start > length - 1u)
            position = (int)(length - 1u);
        if (position >= 0) {
            while (strchr(characters, scratch[position]) == NULL) {
                if (--position < 0) {
                    free(scratch);
                    return -1;
                }
            }
            free(scratch);
            return position;
        }
    } else if (start < length) {
        position = (int)start;
        while (strchr(characters, scratch[position]) == NULL) {
            if ((uint32_t)++position >= length) {
                free(scratch);
                return -1;
            }
        }
        free(scratch);
        return position;
    }

    free(scratch);
    return -1;
}

static const TerminalChunk *fstream;
static uint32_t fstreamLine;
static unsigned char fstreamColumn;
static unsigned char fstreamLength;
static char *fstreamText;
static size_t fstreamCapacity;

static TerminalLine *fstreamLineAt(uint32_t index)
{
    return *(TerminalLine **)(fstream->elements + (size_t)index * 8u);
}

static unsigned char fstreamContinues(uint32_t index)
{
#if UINTPTR_MAX > UINT32_MAX
    /* Native host test chunks store a full pointer in each eight-byte slot. */
    (void)index;
    return 0;
#else
    return fstream->elements[(size_t)index * 8u + 4u];
#endif
}

static char *fstreamLoadLine(uint32_t index)
{
    uint32_t length;
    size_t required;

    length = lineLength(fstreamLineAt(index));
    required = (size_t)length + 1u;
    if (required > fstreamCapacity) {
        char *replacement = (char *)realloc(fstreamText, required);
        if (replacement == 0)
            return 0;
        fstreamText = replacement;
        fstreamCapacity = required;
    }
    lineToString(fstreamLineAt(index), fstreamText);
    fstreamLength = (unsigned char)length;
    return fstreamText;
}

char *seekPos(uint32_t line, unsigned char column)
{
    fstreamLine = line;
    fstreamColumn = column;
    return fstreamLoadLine(line);
}

char *openFStream(const TerminalChunk *lines, uint32_t line,
                  unsigned char column)
{
    fstream = lines;
    return seekPos(line, column);
}

int nextGetChar(void)
{
    unsigned char continues;
    unsigned char column;
    int separator;
    uint32_t count;

    if (fstreamColumn >= fstreamLength) {
        count = fstream->count;
        if (fstreamLine == count - 1u) {
            continues = 0;
            separator = 0;
            fstreamLine = 0;
        } else {
            continues = fstreamContinues(fstreamLine);
            separator = 10;
            ++fstreamLine;
        }
        fstreamColumn = 0;
        if (fstreamLoadLine(fstreamLine) == 0)
            return 0;
        if (continues == 0)
            return separator;
    }
    column = fstreamColumn++;
    return (unsigned char)fstreamText[column];
}

int prevGetChar(void)
{
    unsigned char continues;
    int separator;

    if (fstreamColumn == 0) {
        if (fstreamLine != 0) {
            separator = 10;
            --fstreamLine;
            continues = fstreamContinues(fstreamLine);
        } else {
            separator = 0;
            fstreamLine = fstream->count - 1u;
            continues = 0;
        }
        if (fstreamLoadLine(fstreamLine) == 0)
            return 0;
        fstreamColumn = fstreamLength;
        if (continues == 0)
            return separator;
    }
    return (unsigned char)fstreamText[--fstreamColumn];
}

int peekChar(void)
{
    if (fstreamColumn >= fstreamLength) {
        if (fstreamLine == fstream->count - 1u)
            return 0;
        if (fstreamContinues(fstreamLine) == 0)
            return 10;
        ++fstreamLine;
        fstreamColumn = 0;
        if (fstreamLoadLine(fstreamLine) == 0)
            return 0;
    }
    return (unsigned char)fstreamText[fstreamColumn];
}

void seekFStream(void)
{
}

void getPosition(uint32_t *line, uint32_t *column)
{
    if (fstreamColumn >= fstreamLength &&
        fstreamLine + 1u < fstream->count &&
        fstreamContinues(fstreamLine) != 0) {
        ++fstreamLine;
        fstreamColumn = 0;
        fstreamLoadLine(fstreamLine);
    }
    if (line != 0)
        *line = fstreamLine;
    if (column != 0)
        *column = fstreamColumn >= fstreamLength
            ? fstreamLength : fstreamColumn;
}

int cmpFStream(uint32_t line, uint32_t column)
{
    uint32_t currentLine;
    uint32_t currentColumn;

    getPosition(&currentLine, &currentColumn);
    if (currentLine < line)
        return -1;
    if (currentLine > line)
        return 1;
    if (currentColumn < column)
        return -1;
    return currentColumn > column;
}
