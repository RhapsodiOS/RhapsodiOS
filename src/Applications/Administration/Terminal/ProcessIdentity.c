#include "ProcessIdentity.h"

#ifndef TERMINAL_PROCESSIDENTITY_TEST
#include <unistd.h>
#else
extern int terminalTestSetreuid(unsigned int realUID,
    unsigned int effectiveUID);
#define setreuid terminalTestSetreuid
#endif

static unsigned int realUID;
static unsigned int effectiveUID;
static unsigned int realGID;

void TerminalSaveProcessIdentity(unsigned int savedRealUID,
    unsigned int savedEffectiveUID, unsigned int savedRealGID)
{
    realUID = savedRealUID;
    effectiveUID = savedEffectiveUID;
    realGID = savedRealGID;
}

unsigned int TerminalRealUID(void)
{
    return realUID;
}

unsigned int TerminalRealGID(void)
{
    return realGID;
}

int become_root(void)
{
    return setreuid(realUID, effectiveUID);
}

int become_user(void)
{
    return setreuid(effectiveUID, realUID);
}
