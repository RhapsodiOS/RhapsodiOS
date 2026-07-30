#ifndef _PPC_DBDMA_AUDIO_H_
#define _PPC_DBDMA_AUDIO_H_

#define PPC_DBDMA_DESCRIPTOR_BYTES 16UL
#define PPC_DBDMA_MAX_RING_BYTES 4096UL
#define PPC_DBDMA_MAX_TRANSFER 65535UL

typedef enum {
    kPPCDBDMAOK = 0,
    kPPCDBDMAInvalid,
    kPPCDBDMAMisaligned,
    kPPCDBDMAUnmappable,
    kPPCDBDMAOverflow,
    kPPCDBDMAOversized,
    kPPCDBDMATimeout,
    kPPCDBDMAFault
} PPCDBDMAStatus;

typedef enum {
    kPPCDBDMAInput = 0,
    kPPCDBDMAOutput = 1
} PPCDBDMADirection;

typedef enum {
    kPPCDBDMAEmpty = 0,
    kPPCDBDMAReady,
    kPPCDBDMARunning,
    kPPCDBDMAFaulted
} PPCDBDMAState;

enum {
    kPPCDBDMARegControl = 0,
    kPPCDBDMARegStatus = 1,
    kPPCDBDMARegCommandPtr = 3
};

enum {
    kPPCDBDMARun = 0x00008000UL,
    kPPCDBDMAPause = 0x00004000UL,
    kPPCDBDMAFlushBit = 0x00002000UL,
    kPPCDBDMAWake = 0x00001000UL,
    kPPCDBDMADead = 0x00000800UL,
    kPPCDBDMAActive = 0x00000400UL
};

typedef struct {
    unsigned long operation;
    unsigned long address;
    unsigned long dependency;
    unsigned long result;
} PPCDBDMADescriptor;

typedef struct {
    void *logical;
    unsigned long physical;
    unsigned long bytes;
} PPCDBDMAStorage;

typedef PPCDBDMAStatus (*PPCDBDMATranslate)(void *context,
    const void *virtualAddress, unsigned long *physicalAddress,
    unsigned long *contiguousBytes);
typedef unsigned long (*PPCDBDMARegisterRead)(void *context,
    unsigned long reg);
typedef void (*PPCDBDMARegisterWrite)(void *context, unsigned long reg,
    unsigned long value);
typedef unsigned long (*PPCDBDMANow)(void *context);

typedef struct {
    void *context;
    PPCDBDMATranslate translate;
    void *registerContext;
    PPCDBDMARegisterRead readRegister;
    PPCDBDMARegisterWrite writeRegister;
    PPCDBDMANow now;
} PPCDBDMAOps;

typedef struct {
    unsigned char *descriptors;
    unsigned long descriptorPhysical;
    unsigned long storageBytes;
    unsigned long descriptorCount;
    unsigned long dataDescriptorCount;
    unsigned long consumer;
    unsigned long faultStatus;
    PPCDBDMADirection direction;
    PPCDBDMAState state;
} PPCDBDMARing;

typedef struct {
    unsigned long descriptors;
    unsigned long bytes;
    unsigned long lastStatus;
    unsigned long lastResidual;
    int spurious;
    int fault;
} PPCDBDMACompletion;

typedef struct {
    PPCDBDMAStatus status;
    int sharedClockInvalidated;
} PPCDBDMATransition;

PPCDBDMAStatus PPCDBDMABuildRing(PPCDBDMARing *ring,
    const PPCDBDMAStorage *storage, PPCDBDMADirection direction,
    const void *buffer, unsigned long bufferBytes,
    unsigned long periodBytes, const PPCDBDMAOps *ops);
PPCDBDMAStatus PPCDBDMALoadDescriptor(const PPCDBDMARing *ring,
    unsigned long index, PPCDBDMADescriptor *descriptor);
PPCDBDMAStatus PPCDBDMAServiceCompletions(PPCDBDMARing *ring,
    PPCDBDMACompletion *completion);

unsigned long PPCDBDMASetControl(unsigned long mask);
unsigned long PPCDBDMAClearControl(unsigned long mask);
PPCDBDMATransition PPCDBDMAStartRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline);
PPCDBDMATransition PPCDBDMAStopRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline);
PPCDBDMATransition PPCDBDMAFlushRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline);
PPCDBDMATransition PPCDBDMAResetRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline);

#endif
