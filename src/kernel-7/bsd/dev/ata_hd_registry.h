#ifndef _ATA_HD_REGISTRY_H_
#define _ATA_HD_REGISTRY_H_

#import <sys/types.h>
#import <objc/objc.h>
#import <driverkit/return.h>
#import <driverkit/IODisk.h>
#import <driverkit/IODeviceDescription.h>

struct proc;

typedef IOReturn (*ata_hd_ioctl_fn)(id disk, dev_t dev,
                                    unsigned int cmd, caddr_t data,
                                    int flag, struct proc *proc);

BOOL ata_hd_devsw_init(Class diskClass,
                       IODeviceDescription *deviceDescription);
int ata_hd_register(id disk, ata_hd_ioctl_fn transportIoctl,
                    IODevAndIdInfo **mapOut);
IOReturn ata_hd_unregister(unsigned int unit);
IODevAndIdInfo *ata_hd_lookup(dev_t dev);

#endif
