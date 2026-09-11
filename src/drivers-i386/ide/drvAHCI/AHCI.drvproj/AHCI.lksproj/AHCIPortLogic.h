#ifndef RHAPSODIOS_AHCI_PORT_LOGIC_H
#define RHAPSODIOS_AHCI_PORT_LOGIC_H

#include "AHCIRegs.h"
#include "AHCIState.h"
#include "AHCICommand.h"

#define AHCI_PORT_COMMAND_LIST_OFFSET       0U
#define AHCI_PORT_COMMAND_LIST_BYTES        1024U
#define AHCI_PORT_RECEIVED_FIS_OFFSET       1024U
#define AHCI_PORT_RECEIVED_FIS_BYTES        256U
#define AHCI_PORT_COMMAND_TABLE_OFFSET      1280U
#define AHCI_PORT_COMMAND_TABLE_HEADER_BYTES 128U
#define AHCI_PORT_COMMAND_TABLE_PRD_BYTES   (32U * 16U)
#define AHCI_PORT_COMMAND_TABLE_BYTES       \
    (AHCI_PORT_COMMAND_TABLE_HEADER_BYTES + \
     AHCI_PORT_COMMAND_TABLE_PRD_BYTES)
#define AHCI_PORT_IDENTIFY_OFFSET            2048U
#define AHCI_PORT_IDENTIFY_BYTES             512U
#define AHCI_PORT_ARENA_USABLE_BYTES         2560U
#define AHCI_PORT_ARENA_ALLOCATION_BYTES    \
    (AHCI_PORT_ARENA_USABLE_BYTES + 4095U)

#define AHCI_ENGINE_TIMEOUT_MS              500U
#define AHCI_COMRESET_ASSERT_MS             1U
#define AHCI_LINK_TIMEOUT_MS                10000U
#define AHCI_TFD_TIMEOUT_MS                 10000U
#define AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS   10000U
#define AHCI_TFD_ERR                        0x01U
#define AHCI_TFD_DRQ                        0x08U
#define AHCI_TFD_BSY                        0x80U
#define AHCI_MAX_TRANSFER_BYTES             (128U * 1024U)

#define AHCI_PORT_INITIAL_IE_MASK \
    (AHCI_PXIS_DHRS | AHCI_PXIS_PSS | AHCI_PXIS_DSS | AHCI_PXIS_SDBS | \
     AHCI_PXIS_DPS | AHCI_PXIS_UFS | AHCI_PXIS_PCS | AHCI_PXIS_PRCS | \
     AHCI_PXIS_IPMS | \
     AHCI_PXIS_OFS | AHCI_PXIS_INFS | AHCI_PXIS_IFS | AHCI_PXIS_HBDS | \
     AHCI_PXIS_HBFS | AHCI_PXIS_TFES)

typedef enum {
    AHCI_PORT_SUCCESS = 0,
    AHCI_PORT_BAD_ARGUMENT,
    AHCI_PORT_ADDRESS_ERROR,
    AHCI_PORT_ENGINE_TIMEOUT,
    AHCI_PORT_LINK_TIMEOUT,
    AHCI_PORT_COMMAND_TIMEOUT,
    AHCI_PORT_COMMAND_ERROR
} AHCIPortResult;

typedef int (*AHCIPortTranslate)(void *context,
                                 unsigned long virtualAddress,
                                 AHCIU32 *physicalAddress);

typedef struct {
    unsigned long virtualBase;
    AHCIU32 physicalBase;
    unsigned int commandListOffset;
    unsigned int commandListBytes;
    unsigned int receivedFISOffset;
    unsigned int receivedFISBytes;
    unsigned int commandTableOffset;
    unsigned int commandTableBytes;
    unsigned int identifyOffset;
    unsigned int identifyBytes;
    unsigned int usableBytes;
} AHCIPortArena;

typedef AHCIU32 (*AHCIPortRead)(void *context, AHCIU32 offset);
typedef void (*AHCIPortWrite)(void *context, AHCIU32 offset,
                              AHCIU32 value);
typedef void (*AHCIPortDelay)(void *context, unsigned int milliseconds);
typedef void (*AHCIPortBarrier)(void *context);

typedef struct {
    void *context;
    AHCIPortRead read;
    AHCIPortWrite write;
    AHCIPortDelay delay;
    AHCIPortBarrier barrier;
} AHCIPortOps;

AHCIPortResult AHCIPortPrepareArena(unsigned long rawVirtual,
                                    unsigned int rawBytes,
                                    unsigned int pageBytes,
                                    AHCIPortTranslate translate,
                                    void *translateContext,
                                    AHCIPortArena *arena);
AHCIPortResult AHCIPortInitializeHardware(const AHCIPortOps *ops,
                                          unsigned int port,
                                          AHCIU32 capabilities,
                                          const AHCIPortArena *arena,
                                          AHCIDeviceKind *kind);
AHCIPortResult AHCIPortStopHardware(const AHCIPortOps *ops,
                                    unsigned int port);
AHCIPortResult AHCIPortRecoverHardware(const AHCIPortOps *ops,
                                       unsigned int port,
                                       const AHCIPortArena *arena);
AHCIPortResult AHCIPortRecoveryIdentify(
    const AHCIPortOps *ops, unsigned int port, const AHCIPortArena *arena,
    AHCICommandHeader *commandList, unsigned char *commandTable,
    unsigned short *identifyData, AHCIDeviceKind kind);
unsigned int AHCIPortCountImplemented(AHCIU32 pi);
int AHCIPortImplemented(AHCIU32 pi, unsigned int port);
unsigned int AHCIPortCollectImplemented(AHCIU32 pi, unsigned char *ports,
                                        unsigned int capacity);
int AHCIPortArenaMayRelease(AHCIPortResult stopResult);
AHCIPortResult AHCIPortBuildSegments(unsigned long virtualAddress,
                                     unsigned int length,
                                     unsigned int pageBytes,
                                     AHCIPortTranslate translate,
                                     void *translateContext,
                                     AHCISegment *segments,
                                     unsigned int capacity,
                                     unsigned int *segmentCount);
int AHCIPortBuildSlot(AHCICommandHeader *header, unsigned char *table,
                      AHCIU32 tablePhysical, const unsigned char fis[20],
                      const unsigned char *packet,
                      unsigned int packetLength,
                      const AHCISegment *segments,
                      unsigned int segmentCount,
                      unsigned int transferBytes,
                      unsigned char write, unsigned char atapi);
void AHCICopyVolatileBytes(unsigned char *destination,
                           const volatile unsigned char *source,
                           unsigned int count);

#endif
