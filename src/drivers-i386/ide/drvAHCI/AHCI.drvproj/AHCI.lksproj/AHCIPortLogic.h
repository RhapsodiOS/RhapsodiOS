#ifndef RHAPSODIOS_AHCI_PORT_LOGIC_H
#define RHAPSODIOS_AHCI_PORT_LOGIC_H

#include "AHCIRegs.h"
#include "AHCIState.h"

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
#define AHCI_PORT_ARENA_USABLE_BYTES        1920U
#define AHCI_PORT_ARENA_ALLOCATION_BYTES    \
    (AHCI_PORT_ARENA_USABLE_BYTES + 4095U)

#define AHCI_ENGINE_TIMEOUT_MS              500U
#define AHCI_COMRESET_ASSERT_MS             1U
#define AHCI_LINK_TIMEOUT_MS                10000U

#define AHCI_PORT_INITIAL_IE_MASK \
    (AHCI_PXIS_UFS | AHCI_PXIS_PCS | AHCI_PXIS_PRCS | AHCI_PXIS_IPMS | \
     AHCI_PXIS_OFS | AHCI_PXIS_INFS | AHCI_PXIS_IFS | AHCI_PXIS_HBDS | \
     AHCI_PXIS_HBFS | AHCI_PXIS_TFES)

typedef enum {
    AHCI_PORT_SUCCESS = 0,
    AHCI_PORT_BAD_ARGUMENT,
    AHCI_PORT_ADDRESS_ERROR,
    AHCI_PORT_ENGINE_TIMEOUT,
    AHCI_PORT_LINK_TIMEOUT
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
unsigned int AHCIPortCountImplemented(AHCIU32 pi);
int AHCIPortImplemented(AHCIU32 pi, unsigned int port);

#endif
