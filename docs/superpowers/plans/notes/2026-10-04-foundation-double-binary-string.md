# Foundation `_NSDoubleToBinaryString`

Reference: Foundation i386 IDA database `703cb6287da7`.

IDA confirms `_NSDoubleToBinaryString(int firstWord, int secondWord,
char *buffer)` at `0x42570020`. It writes the second word first, then the first
word. The first byte of the second word is printed with a space after its leading bit; the next byte
has a space between its nibbles. The remaining six bytes are printed as eight
binary digits each. The return value is the last `sprintf` call's length.

The routine is implemented in `NSDebug.m`, declared in `NSDebug.h`, and
recorded in `NSDebug.json` and `symbols.json`. No tests or builds were run.
