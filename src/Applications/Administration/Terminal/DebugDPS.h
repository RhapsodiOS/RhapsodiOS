#ifndef TERMINAL_DEBUG_DPS_H
#define TERMINAL_DEBUG_DPS_H

void debugActivate(void);
void debugDeactivate(int activeApp);
void getActiveApp(int *activeApp);
void TermCaret(double x, double y, double height);
void TermUnderline(double x, double y, double width);

#endif
