#import "AHCIATAPI.h"
#import "AHCIPort.h"
#import "AHCICommand.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <bsd/dev/scsireg.h>
#import <bsd/string.h>

#define AHCI_ATAPI_MAX_TRANSFER_BYTES     131072U
#define AHCI_ATAPI_SECTOR_BYTES           2048U
#define AHCI_SCSI_START_STOP_UNIT         0x1b
#define AHCI_SCSI_PREVENT_ALLOW           0x1e

static unsigned int AHCIATAPICDBLength(const IOSCSIRequest *request)
{
    unsigned char opcode;

    if (request->cdbLength != 0)
        return request->cdbLength;
    opcode = request->cdb.cdb_opcode;
    switch (opcode & 0xe0) {
    case 0x00:
    case 0xc0:
        return 6;
    case 0x20:
    case 0x40:
    case 0xe0:
        return 10;
    case 0xa0:
        return 12;
    default:
        return 0;
    }
}

static int AHCIATAPISupportedOpcode(unsigned char opcode)
{
    return opcode == C6OP_INQUIRY || opcode == C6OP_TESTRDY ||
           opcode == C6OP_REQSENSE || opcode == C10OP_READCAPACITY ||
           opcode == C10OP_READEXTENDED || opcode == C6OP_MODESENSE ||
           opcode == AHCI_SCSI_START_STOP_UNIT ||
           opcode == AHCI_SCSI_PREVENT_ALLOW;
}

static void AHCIATAPISetSense(esense_reply_t *sense, unsigned char key,
                              unsigned char asc, unsigned char ascq)
{
    unsigned char *bytes;

    bzero(sense, sizeof(*sense));
    bytes = (unsigned char *)sense;
    bytes[0] = 0x70;
    bytes[2] = key;
    bytes[7] = 10;
    bytes[12] = asc;
    bytes[13] = ascq;
}

@implementation AHCIATAPIController

+ (IODeviceStyle)deviceStyle
{
    return IO_IndirectDevice;
}

+ (AHCIATAPIController *)publishForPort:(AHCIPort *)port
                      identifyWords:(const unsigned short *)words
                 deviceDescription:(IODeviceDescription *)description
{
    AHCIATAPIController *device;
    unsigned int packetLength;
    unsigned int peripheralType;

    if (port == nil || words == 0)
        return nil;
    peripheralType = (words[0] >> 8) & 0x1fU;
    packetLength = (words[0] & 3U) == 1U ? 16U : 12U;
    if ((peripheralType != 5U && peripheralType != 7U) ||
        ((words[0] & 3U) != 0U && (words[0] & 3U) != 1U))
        return nil;
    device = [[self alloc] initFromDeviceDescription:description];
    if (device == nil)
        return nil;
    device->_port = port;
    device->_packetLength = packetLength;
    device->_stateLock = [NXLock new];
    if (device->_stateLock == nil) {
        [device free];
        return nil;
    }
    device->_online = YES;
    if ([device registerDevice] == nil) {
        [device free];
        return nil;
    }
    device->_deviceRegistered = YES;
    IOLog("%s: ATAPI optical device, %u-byte packets, target 0 lun 0\n",
          [device name], packetLength);
    return device;
}

- (BOOL)beginRequest
{
    BOOL allowed;

    [_stateLock lock];
    allowed = _online && !_destroying;
    if (allowed)
        ++_activeRequests;
    [_stateLock unlock];
    return allowed;
}

- (void)endRequest
{
    [_stateLock lock];
    if (_activeRequests != 0)
        --_activeRequests;
    [_stateLock unlock];
}

- (IOReturn)performPacket:(const unsigned char *)cdb
                   length:(unsigned int)cdbLength
                   buffer:(void *)buffer
              byteLength:(unsigned int)byteLength
                    write:(BOOL)write
                   client:(vm_task_t)client
              transferred:(unsigned int *)actual
{
    unsigned char packetCDB[16];
    unsigned char commandFIS[20];
    unsigned char acmd[16];

    if (cdbLength == 0 || cdbLength > _packetLength)
        return IO_R_INVALID_ARG;
    bzero(packetCDB, sizeof(packetCDB));
    bcopy(cdb, packetCDB, cdbLength);
    if (AHCIBuildPacketCommand(commandFIS, acmd, packetCDB,
                               _packetLength, byteLength,
                               write ? 1 : 0) != 0)
        return IO_R_INVALID_ARG;
    return [_port executeATA:0xa0 fis:commandFIS packet:acmd
                       buffer:buffer length:byteLength write:write
                       client:client
                      timeout:AHCI_ATAPI_PACKET_TIMEOUT_SECONDS
                  transferred:actual];
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
                       buffer:(void *)buffer
                       client:(vm_task_t)client
{
    unsigned char *cdb;
    unsigned char senseCDB[12];
    esense_reply_t sense;
    unsigned int cdbLength;
    unsigned int blocks;
    unsigned int actual;
    unsigned int senseActual;
    IOReturn result;
    IOReturn senseResult;

    if (scsiReq == 0)
        return SR_IOST_CMDREJ;
    scsiReq->bytesTransferred = 0;
    scsiReq->scsiStatus = STAT_CHECK;
    scsiReq->driverStatus = SR_IOST_CMDREJ;
    if (scsiReq->target != 0 || scsiReq->lun != 0 ||
        scsiReq->maxTransfer < 0 ||
        (unsigned int)scsiReq->maxTransfer >
            AHCI_ATAPI_MAX_TRANSFER_BYTES ||
        (scsiReq->maxTransfer != 0 && buffer == 0))
        return SR_IOST_CMDREJ;
    cdb = (unsigned char *)&scsiReq->cdb.cdb_opcode;
    cdbLength = AHCIATAPICDBLength(scsiReq);
    if (!AHCIATAPISupportedOpcode(cdb[0]) || cdbLength == 0 ||
        cdbLength > _packetLength)
        return SR_IOST_CMDREJ;
    if (scsiReq->maxTransfer != 0 && !scsiReq->read)
        return SR_IOST_CMDREJ;
    if ((cdb[0] == C6OP_TESTRDY ||
         cdb[0] == AHCI_SCSI_START_STOP_UNIT ||
         cdb[0] == AHCI_SCSI_PREVENT_ALLOW) &&
        scsiReq->maxTransfer != 0)
        return SR_IOST_CMDREJ;
    if (cdb[0] == C10OP_READEXTENDED) {
        blocks = ((unsigned int)cdb[7] << 8) | cdb[8];
        if (blocks > AHCI_ATAPI_MAX_TRANSFER_BYTES /
                     AHCI_ATAPI_SECTOR_BYTES ||
            (unsigned int)scsiReq->maxTransfer !=
                blocks * AHCI_ATAPI_SECTOR_BYTES)
            return SR_IOST_CMDREJ;
    }
    if (![self beginRequest]) {
        AHCIATAPISetSense(&scsiReq->senseData, SENSE_NOTREADY,
                          0x3a, 0x00);
        scsiReq->driverStatus = SR_IOST_CHKSV;
        return SR_IOST_CHKSV;
    }
    result = [self performPacket:cdb length:cdbLength buffer:buffer
                      byteLength:(unsigned int)scsiReq->maxTransfer
                           write:NO client:client
                     transferred:&actual];
    scsiReq->bytesTransferred = (int)actual;
    if (result == IO_R_SUCCESS) {
        scsiReq->scsiStatus = STAT_GOOD;
        scsiReq->driverStatus = SR_IOST_GOOD;
        [self endRequest];
        return SR_IOST_GOOD;
    }
    if (result == IO_R_IO &&
        AHCIATAPIShouldRequestSense(cdb[0],
                                    scsiReq->ignoreChkcond)) {
        bzero(senseCDB, sizeof(senseCDB));
        senseCDB[0] = C6OP_REQSENSE;
        senseCDB[4] = (unsigned char)sizeof(sense);
        bzero(&sense, sizeof(sense));
        senseActual = 0;
        senseResult = [self performPacket:senseCDB length:6 buffer:&sense
                               byteLength:sizeof(sense) write:NO
                                    client:IOVmTaskSelf()
                               transferred:&senseActual];
        if (AHCIATAPISenseDataValid(senseResult == IO_R_SUCCESS,
                                    senseActual)) {
            scsiReq->senseData = sense;
            if (sense.er_sensekey == SENSE_NOTREADY ||
                sense.er_sensekey == SENSE_UNITATTENTION)
                scsiReq->scsiStatus = STAT_CHECK;
            scsiReq->driverStatus = SR_IOST_CHKSV;
            [self endRequest];
            return SR_IOST_CHKSV;
        }
        if (senseResult == IO_R_OFFLINE)
            result = IO_R_OFFLINE;
    }
    if (result == IO_R_OFFLINE) {
        AHCIATAPISetSense(&scsiReq->senseData, SENSE_NOTREADY,
                          0x3a, 0x00);
        scsiReq->driverStatus = SR_IOST_CHKSV;
    } else if (result == IO_R_TIMEOUT) {
        scsiReq->driverStatus = SR_IOST_IOTO;
    } else if (result == IO_R_IO) {
        scsiReq->driverStatus = SR_IOST_CHKSNV;
    } else {
        scsiReq->driverStatus = SR_IOST_HW;
    }
    [self endRequest];
    return scsiReq->driverStatus;
}

- (BOOL)reidentifyFromWords:(const unsigned short *)words
{
    unsigned int packetLength;
    unsigned int peripheralType;

    if (words == 0)
        return NO;
    peripheralType = (words[0] >> 8) & 0x1fU;
    packetLength = (words[0] & 3U) == 1U ? 16U : 12U;
    return (peripheralType == 5U || peripheralType == 7U) &&
           packetLength == _packetLength;
}

- (void)portBecameNotReady
{
    [_stateLock lock];
    _online = NO;
    [_stateLock unlock];
}

- (void)portBecameReady
{
    [_stateLock lock];
    if (!_destroying)
        _online = YES;
    [_stateLock unlock];
}

- (int)numberOfTargets
{
    return 1;
}

- (unsigned)maxTransfer
{
    return AHCI_ATAPI_MAX_TRANSFER_BYTES;
}

- (sc_status_t)resetSCSIBus
{
    return SR_IOST_GOOD;
}

- free
{
    unsigned int active;

    if ([self numReserved] != 0)
        return self;
    if (_stateLock != nil) {
        [_stateLock lock];
        _destroying = YES;
        _online = NO;
        active = _activeRequests;
        [_stateLock unlock];
        while (active != 0) {
            IOSleep(1);
            [_stateLock lock];
            active = _activeRequests;
            [_stateLock unlock];
        }
        [_stateLock free];
        _stateLock = nil;
    }
    _port = nil;
    _deviceRegistered = NO;
    return [super free];
}

- property_IODeviceClass:(char *)classes length:(unsigned int *)maxLength
{
    (void)maxLength;
    strcpy(classes, IOClassATAPIController);
    return self;
}

- property_IODeviceType:(char *)types length:(unsigned int *)maxLength
{
    (void)maxLength;
    strcat(types, " " IOTypeATAPI);
    return self;
}

@end
