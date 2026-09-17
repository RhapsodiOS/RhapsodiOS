/* ICHAC97Controller.h */
#ifndef _ICH_AC97_CONTROLLER_H_
#define _ICH_AC97_CONTROLLER_H_

typedef unsigned char ICHAC97UInt8;
typedef unsigned short ICHAC97UInt16;
typedef unsigned int ICHAC97UInt32;

enum {
    kICHAC97Success = 0,
    kICHAC97InvalidArgument = -1,
    kICHAC97Timeout = -2,
    kICHAC97NotPrepared = -3
};

enum {
    kICHAC97ServiceNone = 0,
    kICHAC97ServiceOutput = 1,
    kICHAC97ServiceOutputFIFOError = 2
};

#define ICHAC97_BDL_COUNT       32U
#define ICHAC97_BD_IOC          0x80000000U
#define ICHAC97_BD_LENGTH_MASK  0x0000ffffU

#define ICHAC97_REG_PO_BDBAR    0x10U
#define ICHAC97_REG_PO_CIV      0x14U
#define ICHAC97_REG_PO_LVI      0x15U
#define ICHAC97_REG_PO_SR       0x16U
#define ICHAC97_REG_PO_CR       0x1bU
#define ICHAC97_REG_GLOB_CNT    0x2cU
#define ICHAC97_REG_GLOB_STA    0x30U
#define ICHAC97_REG_CAS         0x34U

#define ICHAC97_CR_RPBM         0x01U
#define ICHAC97_CR_RR           0x02U
#define ICHAC97_CR_FEIE         0x08U
#define ICHAC97_CR_IOCE         0x10U

#define ICHAC97_SR_DCH         0x01U
#define ICHAC97_SR_LVBCI        0x04U
#define ICHAC97_SR_BCIS         0x08U
#define ICHAC97_SR_FIFOE        0x10U
#define ICHAC97_SR_W1C          0x1cU

#define ICHAC97_GLOB_CNT_COLD   0x00000002U
#define ICHAC97_GLOB_CNT_WARM   0x00000004U
#define ICHAC97_GLOB_STA_POINT  0x00000040U
#define ICHAC97_GLOB_STA_PCR    0x00000100U
#define ICHAC97_GLOB_STA_RCS    0x00008000U
#define ICHAC97_GLOB_STA_S2CR   0x10000000U
#define ICHAC97_CAS_BUSY        0x01U

typedef struct {
    void *context;
    ICHAC97UInt8 (*read8)(void *context, ICHAC97UInt32 port);
    ICHAC97UInt16 (*read16)(void *context, ICHAC97UInt32 port);
    ICHAC97UInt32 (*read32)(void *context, ICHAC97UInt32 port);
    void (*write8)(void *context, ICHAC97UInt32 port, ICHAC97UInt8 value);
    void (*write16)(void *context, ICHAC97UInt32 port, ICHAC97UInt16 value);
    void (*write32)(void *context, ICHAC97UInt32 port, ICHAC97UInt32 value);
    void (*delayUS)(void *context, ICHAC97UInt32 microseconds);
} ICHAC97IO;

typedef struct {
    ICHAC97UInt32 bufferAddress;
    ICHAC97UInt32 controlLength;
} ICHAC97BufferDescriptor;

typedef struct {
    ICHAC97BufferDescriptor *bdl;
    ICHAC97UInt32 bdlPhysical;
    ICHAC97UInt32 bufferPhysical;
    ICHAC97UInt32 bufferBytes;
    ICHAC97UInt32 serviceBytes;
    ICHAC97UInt8 fragmentCount;
    ICHAC97UInt8 running;
    ICHAC97UInt32 completions;
    ICHAC97UInt32 fifoErrors;
} ICHAC97Playback;

typedef struct {
    ICHAC97IO io;
    ICHAC97UInt32 nambar;
    ICHAC97UInt32 nabmbar;
    ICHAC97Playback playback;
    ICHAC97UInt32 pendingService;
    ICHAC97UInt8 casBeenUsed;
} ICHAC97Controller;

void ICHAC97ControllerInit(ICHAC97Controller *controller,
                            const ICHAC97IO *io,
                            ICHAC97UInt32 nambar,
                            ICHAC97UInt32 nabmbar);
int ICHAC97PrepareBDL(ICHAC97Playback *playback,
                      ICHAC97BufferDescriptor *bdl,
                      ICHAC97UInt32 bdlPhysical,
                      ICHAC97UInt32 bufferPhysical,
                      ICHAC97UInt32 bufferBytes,
                      ICHAC97UInt32 serviceBytes);
int ICHAC97ResetPlayback(ICHAC97Controller *controller,
                          ICHAC97UInt32 pollCount);
int ICHAC97ResetLink(ICHAC97Controller *controller,
                     ICHAC97UInt32 pollCount);
int ICHAC97StartPlayback(ICHAC97Controller *controller);
void ICHAC97StopPlayback(ICHAC97Controller *controller);
void ICHAC97ChaseLVI(ICHAC97Controller *controller);
ICHAC97UInt32 ICHAC97ServiceInterrupt(ICHAC97Controller *controller);
ICHAC97UInt32 ICHAC97ConsumeService(ICHAC97Controller *controller);
ICHAC97UInt16 ICHAC97CodecRead(ICHAC97Controller *controller,
                               ICHAC97UInt8 reg);
void ICHAC97CodecWrite(ICHAC97Controller *controller,
                       ICHAC97UInt8 reg,
                       ICHAC97UInt16 value);

#endif
