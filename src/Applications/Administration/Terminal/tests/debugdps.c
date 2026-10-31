#include "../DebugDPS.h"

#import <AppKit/dpsfriends.h>

#include <assert.h>
#include <stdint.h>
#include <string.h>

static DPSContextRec context;
static DPSProcsRec procedures;
static unsigned char captured[128];
static unsigned int capturedLength;

DPSContext DPSGetCurrentContext(void)
{
    return &context;
}

static void captureSequence(DPSContext current, const void *bytes,
                            unsigned int length)
{
    (void)current;
    assert(length <= sizeof(captured));
    memcpy(captured, bytes, length);
    capturedLength = length;
}

static unsigned int readWord(unsigned int offset)
{
    return ((unsigned int)captured[offset] << 24) |
           ((unsigned int)captured[offset + 1] << 16) |
           ((unsigned int)captured[offset + 2] << 8) |
           captured[offset + 3];
}

int main(void)
{
    int activeApp = 0x12345678;
    unsigned int pointerWord;

    procedures.BinObjSeqWrite = captureSequence;
    context.procs = &procedures;

    debugActivate();
    assert(capturedLength == 58);
    assert(captured[0] == 0x80 && captured[1] == 0x04);
    assert(readWord(8) == 0x00000116);
    assert(memcmp(captured + 36, "winexecdoShellActivate", 22) == 0);

    debugDeactivate(activeApp);
    assert(capturedLength == 52);
    assert(captured[0] == 0x80 && captured[1] == 0x03);
    assert(readWord(8) == 0x12345678);
    assert(memcmp(captured + 28, "winexecdoShellDeactivate", 24) == 0);

    getActiveApp(&activeApp);
    pointerWord = (unsigned int)(uintptr_t)&activeApp;
    assert(capturedLength == 36);
    assert(captured[0] == 0x80 && captured[1] == 0x02);
    assert(readWord(16) == pointerWord);
    assert(memcmp(captured + 20, "currentactiveapp", 16) == 0);

    TermCaret(1.25, -2.5, 3.75);
    assert(capturedLength == 119);
    assert(captured[0] == 0x80 && captured[1] == 0x0D);
    assert(readWord(40) == 0x3FA00000);
    assert(readWord(48) == 0xC0200000);
    assert(readWord(72) == 0x40700000);

    TermUnderline(4.5, 5.5, 6.5);
    assert(capturedLength == 60);
    assert(captured[0] == 0x80 && captured[1] == 0x07);
    assert(readWord(8) == 0x40900000);
    assert(readWord(16) == 0x40B00000);
    assert(readWord(32) == 0x40D00000);

    return 0;
}
