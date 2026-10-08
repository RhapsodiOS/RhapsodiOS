#include <assert.h>
#include "../ProcessIdentity.h"

static int setreuidCalls;
static unsigned int requestedRealUID;
static unsigned int requestedEffectiveUID;

int terminalTestSetreuid(unsigned int realUID, unsigned int effectiveUID)
{
    ++setreuidCalls;
    requestedRealUID = realUID;
    requestedEffectiveUID = effectiveUID;
    return 40 + setreuidCalls;
}

int main(void)
{
    TerminalSaveProcessIdentity(501u, 0u, 20u);
    assert(TerminalRealUID() == 501u);
    assert(TerminalRealGID() == 20u);

    assert(become_root() == 41);
    assert(setreuidCalls == 1);
    assert(requestedRealUID == 501u);
    assert(requestedEffectiveUID == 0u);

    assert(become_user() == 42);
    assert(setreuidCalls == 2);
    assert(requestedRealUID == 0u);
    assert(requestedEffectiveUID == 501u);
    return 0;
}
