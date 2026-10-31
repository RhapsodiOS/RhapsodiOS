#ifndef TERMINAL_WINDOW_TITLE_H
#define TERMINAL_WINDOW_TITLE_H

char *winTitle(const char *command, const char *pty,
               int columns, int rows, int options, char debugging,
               const char *customTitle, const char *fileName);

#endif
