#include "WordSelection.h"
#include "WordBoundary.h"

#include <stdlib.h>

static int isAsciiAlphaNumeric(int byteValue)
{
    return (byteValue >= '0' && byteValue <= '9') ||
           (byteValue >= 'A' && byteValue <= 'Z') ||
           (byteValue >= 'a' && byteValue <= 'z');
}

unsigned int wordEnds(const TerminalLine *line, unsigned int column,
                      unsigned int *start, unsigned int *end)
{
    unsigned int length = lineLength(line);
    char *text;
    int character;

    if (line == NULL || column >= length) {
        *start = length;
        *end = 0;
        return length;
    }

    text = (char *)malloc((size_t)length + 1);
    if (text == NULL) {
        *start = length;
        *end = 0;
        return length;
    }
    lineToString(line, text);

    *start = column;
    *end = column + 1;
    character = (unsigned char)text[column];
    if (character == ' ') {
        while (*start != 0 && text[*start - 1] == ' ')
            --*start;
        while (*end < length && text[*end] == ' ')
            ++*end;
    } else if (character != '~' ||
               (*end < length &&
                (isAsciiAlphaNumeric((unsigned char)text[*end]) ||
                 text[*end] == '_'))) {
        if (iswordchar(character) || character == '~') {
            if (character != '~') {
                while (*start != 0 && iswordchar((unsigned char)text[*start - 1]))
                    --*start;
            }
            while (*end < length && iswordchar((unsigned char)text[*end]))
                ++*end;

            while (*start < length && iswordchar((unsigned char)text[*start]) &&
                   !isAsciiAlphaNumeric((unsigned char)text[*start]) &&
                   text[*start] != '_')
                ++*start;

            while (*end != 0 && iswordchar((unsigned char)text[*end - 1]) &&
                   !isAsciiAlphaNumeric((unsigned char)text[*end - 1]) &&
                   text[*end - 1] != '_')
                --*end;

            if (*start != 0 && text[*start - 1] == '~')
                --*start;
        }
    }

    free(text);
    if (*end > length) {
        *start = length;
        *end = 0;
    }
    return length;
}

unsigned int nextWord(const TerminalLine *line, unsigned int column)
{
    unsigned int start;
    unsigned int end;

    wordEnds(line, column, &start, &end);
    return end;
}

unsigned int prevWord(const TerminalLine *line, unsigned int column)
{
    unsigned int start;
    unsigned int end;

    wordEnds(line, column, &start, &end);
    return start;
}
