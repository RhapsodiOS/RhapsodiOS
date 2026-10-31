#ifndef TERMINAL_WORD_SELECTION_H
#define TERMINAL_WORD_SELECTION_H

#include "Chunk.h"

unsigned int wordEnds(const TerminalLine *line, unsigned int column,
                      unsigned int *start, unsigned int *end);
unsigned int nextWord(const TerminalLine *line, unsigned int column);
unsigned int prevWord(const TerminalLine *line, unsigned int column);

#endif
