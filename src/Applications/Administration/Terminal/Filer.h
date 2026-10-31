#ifndef TERMINAL_FILER_H
#define TERMINAL_FILER_H

#include "Chunk.h"

TerminalChunk *filerBufferCreate(void);
TerminalChunk *filerBufferCreateInZone(void *zone);
TerminalChunk *filerBufferAppend(TerminalChunk *buffer,
                                 const void *bytes, uint32_t length);
int tryOutput(TerminalChunk *buffer, int fd);
int filerBufferTryOutput(TerminalChunk *buffer, int fd);
void filerBufferClear(TerminalChunk *buffer);

#endif
