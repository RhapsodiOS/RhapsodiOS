#include "AdaptecU2CHIMPrivate.h"
#include <machdep/ppc/pmap.h>

#define SCB_LOAD_LE32(address, value) \
    __asm__ ("lwbrx %0,0,%1" : "=r" (value) : "r" (address) : "memory")
#define SCB_STORE_LE32(address, value) \
    __asm__ volatile ("stwbrx %0,0,%1" : : "r" (value), "r" (address) : "memory")

unsigned char SCSIhStandard64ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[38];
}

unsigned char SCSIhSwapping32ObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[28];
}

unsigned char SCSIhStandardAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[5];
}

unsigned char SCSIhSwappingAdvObtainNextScbNum(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    return hiob->scb->virtualAddress[11];
}

void SCSIhStandard64UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[38] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 64);
}

void SCSIhSwapping32UpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[28] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 32);
}

void SCSIhStandardAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[5] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 64);
}

void SCSIhSwappingAdvUpdateNextScbNum(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number)
{
    hiob->scb->virtualAddress[11] = number;
    flush_cache((vm_offset_t)hiob->scb->virtualAddress, 64);
}

unsigned int SCSIhStandard64ObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    unsigned int address;
    SCB_LOAD_LE32(hiob->scb->virtualAddress + 40, address);
    return address;
}

unsigned int SCSIhStandardAdvObtainNextScbAddress(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob)
{
    unsigned int address;
    SCB_LOAD_LE32(hiob->scb->virtualAddress + 32, address);
    return address;
}

void SCSIhStandard64UpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    SCB_STORE_LE32(scb + 40, busAddress);
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandardAdvUpdateNextScbAddress(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    SCB_STORE_LE32(scb + 32, busAddress);
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandard64UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[35] |= 8;
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhStandardAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[0] |= 16;
    flush_cache((vm_offset_t)scb, 64);
}

void SCSIhSwapping32UpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[0] |= 8;
    flush_cache((vm_offset_t)scb, 32);
}

void SCSIhSwappingAdvUpdateAbortBitHostMem(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob)
{
    unsigned char *scb = hiob->scb->virtualAddress;
    scb[38] |= 16;
    flush_cache((vm_offset_t)scb, 64);
}

