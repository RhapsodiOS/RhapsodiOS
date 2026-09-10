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
    ICHAC97IO *io;
    ICHAC97UInt32 crPort;
    ICHAC97UInt32 i;

    if (controller == 0)
        return kICHAC97InvalidArgument;

    io = &controller->io;
    crPort = controller->nabmbar + ICHAC97_REG_PO_CR;
    io->write8(io->context, crPort, ICHAC97_CR_RR);

    for (i = 0; i < pollCount; i++) {
        if ((io->read8(io->context, crPort) & ICHAC97_CR_RR) == 0U)
            return kICHAC97Success;
        if (io->delayUS != 0)
            io->delayUS(io->context, 10U);
    }
    return kICHAC97Timeout;
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
    ICHAC97IO *io;
    ICHAC97Playback *playback;
    ICHAC97UInt32 base;
    ICHAC97UInt8 sr;
    int result;

    if (controller == 0)
        return kICHAC97InvalidArgument;

    playback = &controller->playback;
    if (playback->bdl == 0 || playback->bdlPhysical == 0U)
        return kICHAC97NotPrepared;

    result = ICHAC97ResetPlayback(controller, 100U);
    if (result != kICHAC97Success)
        return result;

    io = &controller->io;
    base = controller->nabmbar;
    io->write32(io->context, base + ICHAC97_REG_PO_BDBAR, playback->bdlPhysical);
    io->write8(io->context, base + ICHAC97_REG_PO_LVI,
               (ICHAC97UInt8)(ICHAC97_BDL_COUNT - 1U));

    sr = io->read8(io->context, base + ICHAC97_REG_PO_SR);
    io->write8(io->context, base + ICHAC97_REG_PO_SR,
               (ICHAC97UInt8)(sr & ICHAC97_SR_W1C));

    io->write8(io->context, base + ICHAC97_REG_PO_CR,
               (ICHAC97UInt8)(ICHAC97_CR_RPBM | ICHAC97_CR_FEIE |
                              ICHAC97_CR_IOCE));
    playback->running = 1U;
    return kICHAC97Success;
}

void ICHAC97StopPlayback(ICHAC97Controller *controller)
{
    ICHAC97IO *io;
    ICHAC97UInt32 base;
    ICHAC97UInt8 sr;

    if (controller == 0)
        return;

    io = &controller->io;
    base = controller->nabmbar;
    io->write8(io->context, base + ICHAC97_REG_PO_CR, 0U);

    sr = io->read8(io->context, base + ICHAC97_REG_PO_SR);
    io->write8(io->context, base + ICHAC97_REG_PO_SR,
               (ICHAC97UInt8)(sr & ICHAC97_SR_W1C));

    controller->playback.running = 0U;
}

void ICHAC97ChaseLVI(ICHAC97Controller *controller)
{
    ICHAC97IO *io;
    ICHAC97UInt32 base;
    ICHAC97UInt8 civ;

    if (controller == 0)
        return;

    io = &controller->io;
    base = controller->nabmbar;
    civ = io->read8(io->context, base + ICHAC97_REG_PO_CIV);
    io->write8(io->context, base + ICHAC97_REG_PO_LVI,
               (ICHAC97UInt8)((civ - 1U) & (ICHAC97_BDL_COUNT - 1U)));
}

ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller)
{
    ICHAC97IO *io;
    ICHAC97UInt32 base;
    ICHAC97UInt32 globSta;
    ICHAC97UInt16 sr;
    ICHAC97UInt32 service;

    if (controller == 0)
        return 0U;

    io = &controller->io;
    base = controller->nabmbar;
    globSta = io->read32(io->context, base + ICHAC97_REG_GLOB_STA);
    if ((globSta & ICHAC97_GLOB_STA_POINT) == 0U)
        return 0U;

    sr = io->read16(io->context, base + ICHAC97_REG_PO_SR);
    io->write16(io->context, base + ICHAC97_REG_PO_SR,
                sr & ICHAC97_SR_W1C);
    io->write32(io->context, base + ICHAC97_REG_GLOB_STA,
                ICHAC97_GLOB_STA_POINT);

    service = 0U;
    if ((sr & ICHAC97_SR_BCIS) != 0U) {
        controller->playback.completions++;
        ICHAC97ChaseLVI(controller);
        service |= kICHAC97ServiceOutput;
    }
    if ((sr & ICHAC97_SR_FIFOE) != 0U) {
        controller->playback.fifoErrors++;
        service |= kICHAC97ServiceOutputFIFOError;
    }
    controller->pendingService |= service;
    return service;
}

ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller)
{
    ICHAC97UInt32 service;

    if (controller == 0)
        return 0U;

    service = controller->pendingService;
    controller->pendingService = 0U;
    return service;
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
