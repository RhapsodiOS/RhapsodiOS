#include "../TerminalServices.h"
#include "../ServiceManager.h"

_Static_assert(sizeof(TerminalServiceRecord) == 28,
    "Terminal service records must match the 28-byte native record");
_Static_assert(sizeof(TerminalServiceSet) == 8,
    "Terminal service sets must match the 32-bit native header");
_Static_assert(sizeof(ServiceManager) == 120,
    "Terminal ServiceManager must match its 32-bit native instance size");
_Static_assert(__builtin_offsetof(ServiceManagerLayout, dirty) == 72,
    "Terminal ServiceManager dirty flag offset");
_Static_assert(__builtin_offsetof(ServiceManagerLayout, origFrame) == 76,
    "Terminal ServiceManager original-frame offset");
_Static_assert(__builtin_offsetof(ServiceManagerLayout, savingCache) == 116,
    "Terminal ServiceManager cache offset");

int main(void)
{
    return 0;
}
