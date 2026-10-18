/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef _MACHDEP_PPC_PEDAVBUS_H_
#define _MACHDEP_PPC_PEDAVBUS_H_
#include <mach/kern_return.h>
typedef enum { kPEDAVBusOff, kPEDAVBusReady } PEDAVBusState;
enum { kPEDAVBusKeyLargo=1, kPEDAVBusPangea=2,
    kPEDAVBusPaddington=3, kPEDAVBusAmplifierGPIO=1, kPEDAVBusInputMux=2 };
typedef struct { unsigned int family,capabilities; } PEDAVBusInfo;
kern_return_t PEDAVBusGetInfo(unsigned int, PEDAVBusInfo *);
kern_return_t PEDAVBusSetState(unsigned int, PEDAVBusState);
/* GPIO5, exclusively for a firmware Proj7PowerControl audio profile. */
kern_return_t PEDAVBusSetAmplifier(unsigned int, unsigned int);
/* Heathrow Proj9 byte mux: 0 clears selection, 1 selects internal microphone.
 * The caller owns the source-specific settling delays between writes. */
kern_return_t PEDAVBusSetInputMux(unsigned int, unsigned int);
#endif
