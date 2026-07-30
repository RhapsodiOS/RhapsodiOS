#ifndef _ATA_HD_REGISTRY_CORE_H_
#define _ATA_HD_REGISTRY_CORE_H_

#define ATA_HD_UNITS 32
#define ATA_HD_PARTITIONS 8

#define ATA_HD_REGISTRY_SUCCESS 0
#define ATA_HD_REGISTRY_INVALID -1
#define ATA_HD_REGISTRY_NOT_FOUND -2
#define ATA_HD_REGISTRY_DUPLICATE -3
#define ATA_HD_REGISTRY_BUSY -4
#define ATA_HD_REGISTRY_FULL -5
#define ATA_HD_REGISTRY_OVERFLOW -6

typedef struct ATAHDRegistryCore {
    void *owners[ATA_HD_UNITS];
    unsigned int openCounts[ATA_HD_UNITS][ATA_HD_PARTITIONS];
} ATAHDRegistryCore;

void ATAHDRegistryCoreInit(ATAHDRegistryCore *registry);
int ATAHDRegistryAllocate(ATAHDRegistryCore *registry, void *owner);
void *ATAHDRegistryOwner(const ATAHDRegistryCore *registry,
                         unsigned int unit);
int ATAHDRegistryOpen(ATAHDRegistryCore *registry, unsigned int unit,
                      unsigned int partition);
int ATAHDRegistryClose(ATAHDRegistryCore *registry, unsigned int unit,
                       unsigned int partition);
int ATAHDRegistryRemove(ATAHDRegistryCore *registry, unsigned int unit);

#endif
