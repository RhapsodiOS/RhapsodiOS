/* Copyright (c) 2026 RhapsodiOS Project. */
#include "ScreamerPCM.h"

ScreamerStatus ScreamerPCMCorrect(void *buffer, unsigned long bytes,
    unsigned int invertRight, unsigned int copyLeftToRight)
{
    unsigned char *sample=(unsigned char *)buffer;
    unsigned int right;
    if((bytes && !buffer) || bytes%4 || invertRight>1 || copyLeftToRight>1)
        return kScreamerInvalid;
    if(!invertRight && !copyLeftToRight) return kScreamerOK;
    while(bytes) {
        if(copyLeftToRight) {
            sample[2]=sample[0];
            sample[3]=sample[1];
        }
        if(invertRight) {
            right=((unsigned int)sample[2]<<8)|sample[3];
            right=right==0x8000U ? 0x7fffU : (0x10000U-right)&0xffffU;
            sample[2]=(unsigned char)(right>>8);
            sample[3]=(unsigned char)right;
        }
        sample+=4;
        bytes-=4;
    }
    return kScreamerOK;
}
