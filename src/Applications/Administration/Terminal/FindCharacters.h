#ifndef TERMINAL_FIND_CHARACTERS_H
#define TERMINAL_FIND_CHARACTERS_H

#include "Chunk.h"

int terminalFindCharacters(const TerminalLine *line, uint32_t start,
                           const char *characters, int backwards,
                           char *scratch, size_t scratchCapacity);
int findCharacters(const TerminalLine *line, uint32_t start,
                   const char *characters, char backwards);

int compareStrings(const char **left, const char **right);
char *strindex(const char *text, const char *needle);
char *strrindex(const char *text, const char *needle);
char *striindex(const char *text, const char *needle);
char *stririndex(const char *text, const char *needle);

extern unsigned char terminalFindIgnoreCase;

char *openFStream(const TerminalChunk *lines, uint32_t line,
                  unsigned char column);
char *seekPos(uint32_t line, unsigned char column);
int nextGetChar(void);
int prevGetChar(void);
int peekChar(void);
void seekFStream(void);
void getPosition(uint32_t *line, uint32_t *column);
int cmpFStream(uint32_t line, uint32_t column);

#endif
