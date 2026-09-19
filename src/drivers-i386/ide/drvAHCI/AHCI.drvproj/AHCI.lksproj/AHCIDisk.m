#import "AHCIDisk.h"
#import "AHCIDiskInternal.h"
#import "AHCIPort.h"
#import "AHCIController.h"
#import <bsd/dev/ata_hd_registry.h>
#import <driverkit/generalFuncs.h>
#import <bsd/stdio.h>
#import <bsd/string.h>

@implementation AHCIDisk

+ (AHCIDisk *)publishForPort:(AHCIPort *)port
           deviceDescription:(IODeviceDescription *)description
{
    AHCIDisk *disk;

    disk = [[self alloc] initFromDeviceDescription:description];
    if (disk == nil)
        return nil;
    if (![disk initResourcesForPort:port] || ![disk identifyDevice]) {
        [disk free];
        return nil;
    }
    if (![disk publish]) {
        [disk free];
        return nil;
    }
    IOLog("%s: %s, %u 512-byte sectors, serial %s, firmware %s\n",
          [disk name], disk->_identify.model, disk->_identify.capacity,
          disk->_identify.serial, disk->_identify.firmware);
    return disk;
}

- (BOOL)publish
{
    IODevAndIdInfo *devAndIdInfo;
    int globalUnit;
    unsigned int unit;
    id disks[1];
    unsigned int units[1];
    char name[12];

    globalUnit = ata_hd_register(self, 0, &devAndIdInfo);
    if (globalUnit < 0)
        return NO;
    _hdUnit = globalUnit;
    if (!ata_hd_set_flush(_hdUnit, self, AHCIDiskTransportFlush))
        return NO;
    unit = (unsigned int)globalUnit;
    [self setDevAndIdInfo:devAndIdInfo];
    [self setUnit:unit];
    sprintf(name, "hd%u", unit);
    [self setName:name];
    [self setDeviceKind:"AHCIDisk"];
    [self setIsPhysical:YES];
    [self setRemovable:NO];
    [self setBlockSize:AHCI_DISK_SECTOR_BYTES];
    [self setDiskSize:_identify.capacity];
    [self setDriveName:_identify.model];
    [self setFormattedInternal:YES];
    [self setLastReadyState:IO_Ready];
    if ([self registerDevice] == nil) {
        _deviceRegistered = YES;
        _publicationPinned = YES;
        IOLog("AHCIDisk: publication state is uncertain; retaining hd%u.\n",
              unit);
        [self portBecameNotReady];
        return YES;
    }
    _deviceRegistered = YES;
    disks[0] = self;
    units[0] = unit;
    if (!ata_hd_activate_units(units, disks, 1U)) {
        _publicationPinned = YES;
        IOLog("AHCIDisk: activation failed; retaining hd%u inactive.\n",
              unit);
        [self portBecameNotReady];
        return YES;
    }
    return YES;
}

static Protocol *protocols[] = {
    @protocol(AHCIControllerPublic),
    nil
};

+ (Protocol **)requiredProtocols
{
    return protocols;
}

+ (IODeviceStyle)deviceStyle
{
    return IO_IndirectDevice;
}

- (IOReturn)readAt:(unsigned int)block
            length:(unsigned int)length
            buffer:(unsigned char *)buffer
      actualLength:(unsigned int *)actualLength
            client:(vm_task_t)client
{
    return [self deviceRwCommon:AHCI_DISK_READ block:block length:length
                            buffer:buffer client:client pending:0
                      actualLength:actualLength];
}

- (IOReturn)readAsyncAt:(unsigned int)block
                 length:(unsigned int)length
                 buffer:(unsigned char *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client
{
    return [self deviceRwCommon:AHCI_DISK_READ block:block length:length
                            buffer:buffer client:client pending:pending
                      actualLength:0];
}

- (IOReturn)writeAt:(unsigned int)block
             length:(unsigned int)length
             buffer:(unsigned char *)buffer
       actualLength:(unsigned int *)actualLength
             client:(vm_task_t)client
{
    return [self deviceRwCommon:AHCI_DISK_WRITE block:block length:length
                            buffer:buffer client:client pending:0
                      actualLength:actualLength];
}

- (IOReturn)writeAsyncAt:(unsigned int)block
                  length:(unsigned int)length
                  buffer:(unsigned char *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
    return [self deviceRwCommon:AHCI_DISK_WRITE block:block length:length
                            buffer:buffer client:client pending:pending
                      actualLength:0];
}

- (void)synchronizeCache
{
    IOReturn result;

    result = [self flushCache];
    if (result != IO_R_SUCCESS)
        IOLog("%s: cache flush failed (%s)\n", [self name],
              [self stringFromReturn:result]);
}

- (IOReturn)updatePhysicalParameters
{
    return IO_R_SUCCESS;
}

- (void)abortRequest
{
}

- (void)diskBecameReady
{
}

- (IOReturn)isDiskReady:(BOOL)prompt
{
    (void)prompt;
    return [self lastReadyState] == IO_Ready ? IO_R_SUCCESS : IO_R_NO_DISK;
}

- (IODiskReadyState)updateReadyState
{
    return [self lastReadyState];
}

- (IOReturn)ejectPhysical
{
    return IO_R_UNSUPPORTED;
}

- (int)deviceOpen:(unsigned int)intentions
{
    (void)intentions;
    return 0;
}

- (void)deviceClose
{
}

- property_IOUnit:(char *)result length:(unsigned int *)maxLength
{
    (void)maxLength;
    sprintf(result, "%d", _hdUnit);
    return self;
}

@end
