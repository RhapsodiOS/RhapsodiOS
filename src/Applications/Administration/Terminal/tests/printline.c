#include "../PrintLine.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <io.h>
#define dup _dup
#define dup2 _dup2
#define close _close
#define fileno _fileno
#else
#include <unistd.h>
#endif

static void beginCapture(FILE *capture, int *savedOutput)
{
    fflush(stdout);
    *savedOutput = dup(fileno(stdout));
    assert(*savedOutput >= 0);
    assert(dup2(fileno(capture), fileno(stdout)) >= 0);
}

static void endCapture(int savedOutput)
{
    fflush(stdout);
    assert(dup2(savedOutput, fileno(stdout)) >= 0);
    close(savedOutput);
}

int main(void)
{
    static const char embeddedText[] = { 'A', '\0', 'B' };
    static const char expected[] = "ab  xy\n\nabcdXY\nA Z\n";
    TerminalLine *first;
    TerminalLine *second;
    TerminalLine *embedded;
    FILE *capture = tmpfile();
    int savedOutput;
    char actual[sizeof(expected)];
    size_t count;

    assert(capture);
    beginCapture(capture, &savedOutput);

    first = lineCreate("ab", 2, 0, 0);
    second = lineCreate("xy", 2, 4, 0);
    assert(first && second);
    first->next = second;
    assert(printLine(first) == 0);
    lineFree(first);
    assert(printLine(NULL) == 0);

    first = lineCreate("abcd", 4, 0, 0);
    second = lineCreate("XY", 2, 2, 0);
    assert(first && second);
    first->next = second;
    assert(printLine(first) == 0);
    lineFree(first);

    embedded = lineCreate(embeddedText, 3, 0, 0);
    second = lineCreate("Z", 1, 4, 0);
    assert(embedded && second);
    embedded->next = second;
    assert(printLine(embedded) == 0);
    lineFree(embedded);

    endCapture(savedOutput);
    rewind(capture);
    count = fread(actual, 1, sizeof(actual), capture);
    assert(count == sizeof(expected) - 1);
    assert(memcmp(actual, expected, count) == 0);
    fclose(capture);
    return 0;
}
