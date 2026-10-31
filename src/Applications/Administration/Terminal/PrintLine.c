#include "PrintLine.h"

int terminalPrintLine(FILE *stream, const TerminalLine *line)
{
    uint32_t outputColumn = 0;

    if (!stream)
        return -1;
    while (line) {
        while (outputColumn < line->column) {
            if (fputc(' ', stream) == EOF)
                return -1;
            ++outputColumn;
        }
        if (line->length &&
            fwrite(line->text, 1, line->length, stream) != line->length)
            return -1;
        outputColumn += line->length;
        line = line->next;
    }
    return fputc('\n', stream) == EOF ? -1 : 0;
}

int printLine(const TerminalLine *line)
{
    unsigned int outputColumn = 0;

    while (line) {
        while (outputColumn < line->column) {
            putchar(' ');
            ++outputColumn;
        }
        printf("%s", line->text);
        outputColumn += line->length;
        line = line->next;
    }
    putchar('\n');
    return 0;
}
