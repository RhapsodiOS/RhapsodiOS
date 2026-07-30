#ifndef _ATA_HD_REGISTRY_CORE_H_
#define _ATA_HD_REGISTRY_CORE_H_

#define ATA_HD_UNITS 32
#define ATA_HD_PARTITIONS 8
#define ATA_HD_ASYNC_PINS (ATA_HD_UNITS * 128)

#define ATA_HD_REGISTRY_SUCCESS 0
#define ATA_HD_REGISTRY_INVALID -1
#define ATA_HD_REGISTRY_NOT_FOUND -2
#define ATA_HD_REGISTRY_DUPLICATE -3
#define ATA_HD_BUSY -4
#define ATA_HD_REGISTRY_FULL -5
#define ATA_HD_REGISTRY_OVERFLOW -6
#define ATA_HD_REGISTRY_INACTIVE -7

typedef struct ATAHDRegistryCore {
    void *owners[ATA_HD_UNITS];
    unsigned char active[ATA_HD_UNITS];
    unsigned int openCounts[ATA_HD_UNITS][ATA_HD_PARTITIONS];
} ATAHDRegistryCore;

typedef struct ATAHDAsyncToken {
    unsigned int index;
    unsigned int generation;
} ATAHDAsyncToken;

typedef struct ATAHDAsyncPin {
    void *pending;
    unsigned int unit;
    unsigned int partition;
    unsigned int generation;
    unsigned char active;
} ATAHDAsyncPin;

typedef struct ATAHDAsyncTokenCore {
    ATAHDAsyncPin pins[ATA_HD_ASYNC_PINS];
} ATAHDAsyncTokenCore;

void ATAHDRegistryCoreInit(ATAHDRegistryCore *registry);
int ATAHDRegistryAllocate(ATAHDRegistryCore *registry, void *owner);
void *ATAHDRegistryOwner(const ATAHDRegistryCore *registry,
                         unsigned int unit);
int ATAHDRegistryIsActive(const ATAHDRegistryCore *registry,
                          unsigned int unit);
int ATAHDRegistryActivate(ATAHDRegistryCore *registry, unsigned int unit,
                          void *owner);
int ATAHDRegistryActivateBatch(ATAHDRegistryCore *registry,
                               const unsigned int *units,
                               void *const *owners,
                               unsigned int count);
int ATAHDRegistryOpen(ATAHDRegistryCore *registry, unsigned int unit,
                      unsigned int partition);
int ATAHDRegistryClose(ATAHDRegistryCore *registry, unsigned int unit,
                       unsigned int partition);
int ATAHDRegistryPublishPinnedOpen(ATAHDRegistryCore *registry,
                                   unsigned int unit,
                                   unsigned int partition,
                                   unsigned char *present);
int ATAHDRegistryCloseIfPresent(ATAHDRegistryCore *registry,
                                unsigned int unit, unsigned int partition,
                                unsigned char *present);
int ATAHDRegistryRemove(ATAHDRegistryCore *registry, unsigned int unit);
void ATAHDAsyncTokenCoreInit(ATAHDAsyncTokenCore *tokens);
int ATAHDAsyncTokenReserve(ATAHDAsyncTokenCore *tokens, void *pending,
                           unsigned int unit, unsigned int partition,
                           ATAHDAsyncToken *tokenOut);
int ATAHDAsyncTokenForPending(const ATAHDAsyncTokenCore *tokens,
                              void *pending, ATAHDAsyncToken *tokenOut);
int ATAHDAsyncTokenRelease(ATAHDAsyncTokenCore *tokens,
                           ATAHDAsyncToken token, unsigned int *unitOut,
                           unsigned int *partitionOut);

#endif
