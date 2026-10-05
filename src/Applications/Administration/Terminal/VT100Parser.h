#ifndef TERMINAL_VT100_PARSER_H
#define TERMINAL_VT100_PARSER_H

#include "VT100Args.h"

#include <stdint.h>

typedef struct {
    TerminalChunk *arguments;
    unsigned char privateMode;
    unsigned char collectingCSI;
    unsigned char command;
} VT100Parser;

void vt100ParserInit(VT100Parser *parser, TerminalChunk *arguments);
VT100ArgsResult vt100ParserBeginCSI(VT100Parser *parser,
                                    unsigned char firstByte);
VT100ArgsResult vt100ParserConsumeCSI(VT100Parser *parser,
                                      unsigned char byte);

#endif
