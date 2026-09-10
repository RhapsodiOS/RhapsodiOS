#include <string.h>
#include "ICHAC97Controller.h"

void ICHAC97ControllerInit(ICHAC97Controller *controller,
                            const ICHAC97IO *io,
                            ICHAC97UInt32 nambar,
                            ICHAC97UInt32 nabmbar)
{
    if (controller == 0 || io == 0)
        return;
    memset(controller, 0, sizeof(*controller));
    controller->io = *io;
    controller->nambar = nambar;
    controller->nabmbar = nabmbar;
}

int ICHAC97PrepareBDL(ICHAC97Playback *playback,
                      ICHAC97BufferDescriptor *bdl,
                      ICHAC97UInt32 bdlPhysical,
                      ICHAC97UInt32 bufferPhysical,
                      ICHAC97UInt32 bufferBytes,
                      ICHAC97UInt32 serviceBytes)
{
    ICHAC97UInt32 nFrags;
    ICHAC97UInt32 samples;
    ICHAC97UInt32 i;

    if (playback == 0 || bdl == 0 || bufferBytes == 0U ||
        serviceBytes == 0U || (serviceBytes & 1U) != 0U ||
        (bufferBytes % serviceBytes) != 0U)
        return kICHAC97InvalidArgument;
    nFrags = bufferBytes / serviceBytes;
    samples = serviceBytes / 2U;
    if (nFrags == 0U || nFrags > ICHAC97_BDL_COUNT ||
        samples == 0U || samples > ICHAC97_BD_LENGTH_MASK)
        return kICHAC97InvalidArgument;

    memset(bdl, 0, sizeof(*bdl) * ICHAC97_BDL_COUNT);
    for (i = 0; i < ICHAC97_BDL_COUNT; i++) {
        bdl[i].bufferAddress = bufferPhysical + (i % nFrags) * serviceBytes;
        bdl[i].controlLength = ICHAC97_BD_IOC | samples;
    }
    memset(playback, 0, sizeof(*playback));
    playback->bdl = bdl;
    playback->bdlPhysical = bdlPhysical;
    playback->bufferPhysical = bufferPhysical;
    playback->bufferBytes = bufferBytes;
    playback->serviceBytes = serviceBytes;
    playback->fragmentCount = (ICHAC97UInt8)nFrags;
    return kICHAC97Success;
}

int ICHAC97ResetPlayback(ICHAC97Controller *controller,
                          ICHAC97UInt32 pollCount)
{
    (void)controller;
    (void)pollCount;
    return kICHAC97NotPrepared;
}

int ICHAC97ResetLink(ICHAC97Controller *controller,
                     ICHAC97UInt32 pollCount)
{
    (void)controller;
    (void)pollCount;
    return kICHAC97NotPrepared;
}

int ICHAC97StartPlayback(ICHAC97Controller *controller)
{
    (void)controller;
    return kICHAC97NotPrepared;
}

void ICHAC97StopPlayback(ICHAC97Controller *controller)
{
    (void)controller;
}

void ICHAC97ChaseLVI(ICHAC97Controller *controller)
{
    (void)controller;
}

ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller)
{
    (void)controller;
    return 0U;
}

ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller)
{
    (void)controller;
    return 0U;
}

ICHAC97UInt16 ICHAC97CodecRead(ICHAC97Controller *controller,
                               ICHAC97UInt8 reg)
{
    (void)controller;
    (void)reg;
    return (ICHAC97UInt16)0xffffU;
}

void ICHAC97CodecWrite(ICHAC97Controller *controller,
                       ICHAC97UInt8 reg,
                       ICHAC97UInt16 value)
{
    (void)controller;
    (void)reg;
    (void)value;
}
