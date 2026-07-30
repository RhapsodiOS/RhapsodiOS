#ifndef _ATA_HD_REGISTRY_H_
#define _ATA_HD_REGISTRY_H_

#import <sys/types.h>
#import <objc/objc.h>
#import <driverkit/return.h>
#import <driverkit/IODisk.h>
#import <driverkit/IODeviceDescription.h>

struct proc;

typedef int (*ata_hd_ioctl_fn)(id disk, dev_t dev,
                               unsigned int cmd, caddr_t data,
                               int flag, struct proc *proc);

BOOL ata_hd_registry_init(void);
BOOL ata_hd_devsw_init(Class diskClass,
                       IODeviceDescription *deviceDescription);
int ata_hd_register(id disk, ata_hd_ioctl_fn transportIoctl,
                    IODevAndIdInfo **mapOut);
IOReturn ata_hd_unregister(unsigned int unit);
IODevAndIdInfo *ata_hd_lookup(dev_t dev);

BOOL ata_hd_map_is_owned(IODevAndIdInfo *map);
BOOL ata_hd_map_set_live(IODevAndIdInfo *map, id disk);
BOOL ata_hd_map_clear_live(IODevAndIdInfo *map, id disk);
BOOL ata_hd_map_set_partition(IODevAndIdInfo *map, id disk,
                              unsigned int partition);
BOOL ata_hd_map_clear_partition(IODevAndIdInfo *map, id disk,
                                unsigned int partition);

#endif
