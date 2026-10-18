/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef _PEXPERT_DAVBUS_AUDIO_H_
#define _PEXPERT_DAVBUS_AUDIO_H_
#include <mach/boolean.h>
#include <machdep/ppc/PEDAVBus.h>
enum { kPEAudioMuxNone, kPEAudioMuxI2S0, kPEAudioMuxDAVbus };
typedef struct {
    void *context;
    unsigned int controllerBase, family;
    unsigned int *owner, *saved, *active;
    unsigned int (*readFCR1)(void *);
    kern_return_t (*writeFCR1)(void *, unsigned int);
    void (*lock)(void *);
    void (*unlock)(void *);
    void (*barrier)(void *);
    boolean_t (*inInterruptContext)(void *);
} PEDAVBusTransport;
void PEDAVBusBindTransport(const PEDAVBusTransport *);
kern_return_t PEDAVBusSetStateCore(const PEDAVBusTransport *, PEDAVBusState);
#endif
