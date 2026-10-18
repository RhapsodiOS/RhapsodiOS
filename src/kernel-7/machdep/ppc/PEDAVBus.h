/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef _MACHDEP_PPC_PEDAVBUS_H_
#define _MACHDEP_PPC_PEDAVBUS_H_
#include <mach/kern_return.h>
typedef enum { kPEDAVBusOff, kPEDAVBusReady } PEDAVBusState;
enum { kPEDAVBusKeyLargo=1, kPEDAVBusAmplifierGPIO=1 };
typedef struct { unsigned int family,capabilities; } PEDAVBusInfo;
kern_return_t PEDAVBusGetInfo(unsigned int, PEDAVBusInfo *);
kern_return_t PEDAVBusSetState(unsigned int, PEDAVBusState);
/* GPIO5, exclusively for a firmware Proj7PowerControl audio profile. */
kern_return_t PEDAVBusSetAmplifier(unsigned int, unsigned int);
#endif
