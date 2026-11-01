#include <stdio.h>
#include <string.h>
#include "ScreamerPCM.h"

static unsigned int checks, failures;
#define CHECK(x) do { ++checks; if (!(x)) { ++failures; \
    fprintf(stderr,"%s:%d: %s\n",__FILE__,__LINE__,#x); } } while (0)

int main(void)
{
    static const unsigned char samples[] = {
        0x12,0x34,0x80,0x00, 0xfe,0xdc,0x80,0x01,
        0x80,0x00,0xff,0xff, 0x7f,0xff,0x00,0x00,
        0x00,0x00,0x00,0x01, 0xff,0xff,0x7f,0xfe,
        0x00,0x01,0x7f,0xff
    };
    static const unsigned char inverted[] = {
        0x12,0x34,0x7f,0xff, 0xfe,0xdc,0x7f,0xff,
        0x80,0x00,0x00,0x01, 0x7f,0xff,0x00,0x00,
        0x00,0x00,0xff,0xff, 0xff,0xff,0x80,0x02,
        0x00,0x01,0x80,0x01
    };
    static const unsigned char mono[] = {
        0x12,0x34,0x12,0x34, 0xfe,0xdc,0xfe,0xdc,
        0x80,0x00,0x80,0x00, 0x7f,0xff,0x7f,0xff,
        0x00,0x00,0x00,0x00, 0xff,0xff,0xff,0xff,
        0x00,0x01,0x00,0x01
    };
    static const unsigned char monoInverted[] = {
        0x12,0x34,0xed,0xcc, 0xfe,0xdc,0x01,0x24,
        0x80,0x00,0x7f,0xff, 0x7f,0xff,0x80,0x01,
        0x00,0x00,0x00,0x00, 0xff,0xff,0x00,0x01,
        0x00,0x01,0xff,0xff
    };
    unsigned char guarded[sizeof(samples)+2];
    unsigned char before[sizeof(guarded)];
    unsigned char *buffer;
    unsigned long size;

    memset(guarded,0xa5,sizeof(guarded));
    buffer=guarded+1;
    memcpy(buffer,samples,sizeof(samples));
    CHECK(ScreamerPCMCorrect(buffer,sizeof(samples),0,0)==kScreamerOK);
    CHECK(memcmp(buffer,samples,sizeof(samples))==0);
    CHECK(ScreamerPCMCorrect(buffer,sizeof(samples),1,0)==kScreamerOK);
    CHECK(memcmp(buffer,inverted,sizeof(inverted))==0);
    CHECK(guarded[0]==0xa5 && guarded[sizeof(guarded)-1]==0xa5);
    memcpy(buffer,samples,sizeof(samples));
    CHECK(ScreamerPCMCorrect(buffer,sizeof(samples),0,1)==kScreamerOK);
    CHECK(memcmp(buffer,mono,sizeof(mono))==0);
    memcpy(buffer,samples,sizeof(samples));
    CHECK(ScreamerPCMCorrect(buffer,sizeof(samples),1,1)==kScreamerOK);
    CHECK(memcmp(buffer,monoInverted,sizeof(monoInverted))==0);
    CHECK(guarded[0]==0xa5 && guarded[sizeof(guarded)-1]==0xa5);

    memcpy(before,guarded,sizeof(guarded));
    for(size=1;size<sizeof(samples);++size) {
        if(size%4==0) continue;
        CHECK(ScreamerPCMCorrect(buffer,size,1,1)==kScreamerInvalid);
        CHECK(memcmp(guarded,before,sizeof(guarded))==0);
    }
    CHECK(ScreamerPCMCorrect(buffer,sizeof(samples),2,0)==kScreamerInvalid);
    CHECK(memcmp(guarded,before,sizeof(guarded))==0);
    CHECK(ScreamerPCMCorrect(buffer,sizeof(samples),0,2)==kScreamerInvalid);
    CHECK(memcmp(guarded,before,sizeof(guarded))==0);
    CHECK(ScreamerPCMCorrect(0,4,0,0)==kScreamerInvalid);
    CHECK(ScreamerPCMCorrect(0,4,1,1)==kScreamerInvalid);
    CHECK(ScreamerPCMCorrect(0,0,1,1)==kScreamerOK);
    CHECK(ScreamerPCMCorrect(buffer,0,1,1)==kScreamerOK);
    CHECK(memcmp(guarded,before,sizeof(guarded))==0);
    printf("Screamer PCM: %u checks, %u failures\n",checks,failures);
    return failures ? 1 : 0;
}
