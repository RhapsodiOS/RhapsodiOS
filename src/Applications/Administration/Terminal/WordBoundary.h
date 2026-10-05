#ifndef TERMINAL_WORD_BOUNDARY_H
#define TERMINAL_WORD_BOUNDARY_H

int startsleft(int byteValue);
int startsright(int byteValue);
int iswordchar(int byteValue);
int terminalStartsLeft(int byteValue);
int terminalStartsRight(int byteValue);
int terminalIsWordCharacter(int byteValue);
int char_offset(unsigned char attributes, char attribute);

#endif
