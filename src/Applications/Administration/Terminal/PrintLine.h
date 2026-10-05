#ifndef TERMINAL_PRINT_LINE_H
#define TERMINAL_PRINT_LINE_H

#include "Chunk.h"

#include <stdio.h>

int terminalPrintLine(FILE *stream, const TerminalLine *line);
int printLine(const TerminalLine *line);

#endif
