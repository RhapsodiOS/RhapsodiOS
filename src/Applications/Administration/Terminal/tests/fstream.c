#include "../FindCharacters.h"

#include <assert.h>
#include <string.h>

static void setLine(TerminalChunk *chunk, uint32_t index, TerminalLine *line)
{
    *(TerminalLine **)(chunk->elements + index * 8u) = line;
}

int main(void)
{
    TerminalChunk *chunk;
    TerminalLine *first;
    TerminalLine *second;
    char *text;
    uint32_t line;
    uint32_t column;

    chunk = ChunkMalloc(8, 2, 2, 2, NULL);
    first = lineCreate("ab", 2, 0, 0);
    second = lineCreate("cd", 2, 0, 0);
    assert(chunk != 0 && first != 0 && second != 0);
    setLine(chunk, 0, first);
    setLine(chunk, 1, second);

    text = openFStream(chunk, 0, 0);
    assert(text != 0 && strcmp(text, "ab") == 0);
    assert(nextGetChar() == 'a');
    assert(nextGetChar() == 'b');
    assert(peekChar() == '\n');
    assert(peekChar() == '\n');
    getPosition(&line, &column);
    assert(line == 0 && column == 2);
    assert(nextGetChar() == '\n');
    getPosition(&line, &column);
    assert(line == 1 && column == 0);
    assert(nextGetChar() == 'c');
    assert(cmpFStream(1, 0) > 0);
    assert(prevGetChar() == 'c');
    assert(prevGetChar() == '\n');
    getPosition(&line, &column);
    assert(line == 0 && column == 2);
    assert(prevGetChar() == 'b');

    assert(seekPos(1, 1) != 0);
    assert(nextGetChar() == 'd');
    assert(peekChar() == 0);
    assert(nextGetChar() == 0);
    assert(seekPos(0, 0) != 0);
    assert(prevGetChar() == 0);
    getPosition(&line, &column);
    assert(line == 1 && column == 2);

    lineFree(first);
    lineFree(second);
    ChunkFree(chunk);
    return 0;
}
