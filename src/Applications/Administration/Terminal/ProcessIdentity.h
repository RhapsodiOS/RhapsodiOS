#ifndef TERMINAL_PROCESSIDENTITY_H
#define TERMINAL_PROCESSIDENTITY_H

void TerminalSaveProcessIdentity(unsigned int realUID,
    unsigned int effectiveUID, unsigned int realGID);
unsigned int TerminalRealUID(void);
unsigned int TerminalRealGID(void);
int become_root(void);
int become_user(void);

#endif
