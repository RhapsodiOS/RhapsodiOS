#import "AHCIATAPI.h"
#import "AHCIPort.h"
#import "AHCICommand.h"
#import "AHCIATAPILogic.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/IOMemoryDescriptor.h>
#import <driverkit/kernelDriver.h>
#import <bsd/dev/scsireg.h>
#import <bsd/string.h>

#define AHCI_ATAPI_MAX_TRANSFER_BYTES     131072U
#define AHCI_ATAPI_SECTOR_BYTES           2048U
#define AHCI_SCSI_START_STOP_UNIT         0x1b
#define AHCI_SCSI_PREVENT_ALLOW           0x1e
#define AHCI_ATAPI_MODE_SENSE_MAX_BYTES   259U

typedef struct {
    const unsigned char *cdb;
    unsigned int cdbLength;
    unsigned long long target;
    unsigned long long lun;
    char read;
    int maxTransfer;
    int timeoutLength;
    int ignoreChkcond;
    sc_status_t driverStatus;
    unsigned char scsiStatus;
    int bytesTransferred;
    esense_reply_t senseData;
} AHCIATAPIRequest;

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
    AHCIATAPIIdentity identity;

    if (port == nil || !AHCIATAPIParseIdentity(words, &identity))
        return nil;
    device = [[self alloc] initFromDeviceDescription:description];
    if (device == nil)
        return nil;
    device->_port = port;
    device->_identity = identity;
    device->_packetLength = identity.packetLength;
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
          [device name], device->_packetLength);
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
                  timeout:(unsigned int)timeout
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
                               write ? 1 : 0,
                               _identity.dmaDirSupported ? 1 : 0) != 0)
        return IO_R_INVALID_ARG;
    return [_port executeATA:0xa0 fis:commandFIS packet:acmd
                       buffer:buffer length:byteLength write:write
                       client:client
                      timeout:timeout
                  transferred:actual];
}

- (BOOL)copyKernelBuffer:(void *)source
                  length:(unsigned int)length
                toBuffer:(void *)buffer
                  client:(vm_task_t)client
{
    IOMemoryDescriptor *descriptor;
    unsigned int copied;

    if (length == 0)
        return YES;
    descriptor = [[IOMemoryDescriptor alloc] initWithAddress:buffer
                                                     length:length];
    if (descriptor == nil)
        return NO;
    [descriptor setClient:client];
    copied = [descriptor writeToClient:source count:length];
    [descriptor release];
    return copied == length;
}

- (sc_status_t)executeCommonRequest:(AHCIATAPIRequest *)request
                             buffer:(void *)buffer
                             client:(vm_task_t)client
{
    unsigned char senseCDB[12];
    unsigned char translatedCDB[12];
    unsigned char atapiModeData[AHCI_ATAPI_MODE_SENSE_MAX_BYTES];
    unsigned char scsiModeData[255];
    unsigned int blocks;
    unsigned int actual;
    unsigned int senseActual;
    unsigned int packetBytes;
    unsigned int packetCDBLength;
    unsigned int packetTimeout;
    unsigned int modeBytes;
    const unsigned char *packetCDB;
    void *packetBuffer;
    vm_task_t packetClient;
    BOOL modeSense;
    BOOL emulatePageTwo;
    IOReturn result;
    IOReturn senseResult;
    esense_reply_t sense;

    request->bytesTransferred = 0;
    request->scsiStatus = STAT_CHECK;
    request->driverStatus = SR_IOST_CMDREJ;
    bzero(&request->senseData, sizeof(request->senseData));
    if (request->target != 0 || request->lun != 0 ||
        request->maxTransfer < 0 ||
        (unsigned int)request->maxTransfer >
            AHCI_ATAPI_MAX_TRANSFER_BYTES ||
        (request->maxTransfer != 0 && buffer == 0) ||
        request->cdbLength == 0 || request->cdbLength > _packetLength)
        return SR_IOST_CMDREJ;
    if (request->maxTransfer != 0 && !request->read)
        return SR_IOST_CMDREJ;
    if ((request->cdb[0] == C6OP_TESTRDY ||
         request->cdb[0] == AHCI_SCSI_START_STOP_UNIT ||
         request->cdb[0] == AHCI_SCSI_PREVENT_ALLOW) &&
        request->maxTransfer != 0)
        return SR_IOST_CMDREJ;
    if (request->cdb[0] == C10OP_READEXTENDED) {
        blocks = ((unsigned int)request->cdb[7] << 8) |
                 request->cdb[8];
        if (blocks > AHCI_ATAPI_MAX_TRANSFER_BYTES /
                     AHCI_ATAPI_SECTOR_BYTES ||
            (unsigned int)request->maxTransfer !=
                blocks * AHCI_ATAPI_SECTOR_BYTES)
            return SR_IOST_CMDREJ;
    }
    if (request->cdb[0] == AHCI_ATAPI_READ_16) {
        blocks = ((unsigned int)request->cdb[12] << 8) |
                 request->cdb[13];
        if (request->cdb[10] != 0 || request->cdb[11] != 0 ||
            blocks > AHCI_ATAPI_MAX_TRANSFER_BYTES /
                     AHCI_ATAPI_SECTOR_BYTES ||
            (unsigned int)request->maxTransfer !=
                blocks * AHCI_ATAPI_SECTOR_BYTES)
            return SR_IOST_CMDREJ;
    }

    packetCDB = request->cdb;
    packetCDBLength = request->cdbLength;
    packetBytes = (unsigned int)request->maxTransfer;
    packetBuffer = buffer;
    packetClient = client;
    modeSense = request->cdb[0] == C6OP_MODESENSE;
    emulatePageTwo = modeSense &&
                     (request->cdb[2] & 0x3fU) == 2U;
    if (modeSense && !emulatePageTwo) {
        if (!AHCIATAPITranslateModeSense6(request->cdb,
                                           packetBytes, translatedCDB,
                                           &packetBytes))
            return SR_IOST_CMDREJ;
        packetCDB = translatedCDB;
        packetCDBLength = 10;
        packetBuffer = atapiModeData;
        packetClient = IOVmTaskSelf();
    }
    if (emulatePageTwo &&
        !AHCIATAPIEmulateModeSensePage2(request->cdb, scsiModeData,
                                        packetBytes, &modeBytes))
        return SR_IOST_CMDREJ;

    if (![self beginRequest]) {
        AHCIATAPISetSense(&request->senseData, SENSE_NOTREADY,
                          0x3a, 0x00);
        request->driverStatus = SR_IOST_CHKSV;
        return SR_IOST_CHKSV;
    }
    if (emulatePageTwo) {
        if (![self copyKernelBuffer:scsiModeData length:modeBytes
                           toBuffer:buffer client:client]) {
            request->driverStatus = SR_IOST_HW;
            goto finish;
        }
        request->bytesTransferred = (int)modeBytes;
        request->scsiStatus = STAT_GOOD;
        request->driverStatus = SR_IOST_GOOD;
        goto finish;
    }

    actual = 0;
    packetTimeout = AHCIATAPIPacketTimeout(request->timeoutLength);
    result = [self performPacket:packetCDB length:packetCDBLength
                          buffer:packetBuffer byteLength:packetBytes
                           write:NO client:packetClient
                         timeout:packetTimeout transferred:&actual];
    if (result == IO_R_SUCCESS && modeSense) {
        if (!AHCIATAPIRemapModeSense10(atapiModeData, actual,
                                        scsiModeData,
                                        (unsigned int)request->maxTransfer,
                                        &modeBytes) ||
            ![self copyKernelBuffer:scsiModeData length:modeBytes
                           toBuffer:buffer client:client]) {
            request->driverStatus = SR_IOST_HW;
            goto finish;
        }
        actual = modeBytes;
    }
    request->bytesTransferred = (int)actual;
    if (result == IO_R_SUCCESS) {
        request->scsiStatus = STAT_GOOD;
        request->driverStatus = SR_IOST_GOOD;
        goto finish;
    }
    if (result == IO_R_IO &&
        AHCIATAPIShouldRequestSense(request->cdb[0],
                                    request->ignoreChkcond)) {
        bzero(senseCDB, sizeof(senseCDB));
        senseCDB[0] = C6OP_REQSENSE;
        senseCDB[4] = (unsigned char)sizeof(sense);
        bzero(&sense, sizeof(sense));
        senseActual = 0;
        senseResult = [self performPacket:senseCDB length:6 buffer:&sense
                               byteLength:sizeof(sense) write:NO
                                    client:IOVmTaskSelf()
                                   timeout:AHCI_ATAPI_PACKET_TIMEOUT_SECONDS
                               transferred:&senseActual];
        if (AHCIATAPISenseDataValid(senseResult == IO_R_SUCCESS,
                                    senseActual)) {
            request->senseData = sense;
            request->driverStatus = SR_IOST_CHKSV;
            goto finish;
        }
        if (senseResult == IO_R_OFFLINE)
            result = IO_R_OFFLINE;
    }
    if (result == IO_R_OFFLINE) {
        AHCIATAPISetSense(&request->senseData, SENSE_NOTREADY,
                          0x3a, 0x00);
        request->driverStatus = SR_IOST_CHKSV;
    } else if (result == IO_R_TIMEOUT) {
        request->driverStatus = SR_IOST_IOTO;
    } else if (result == IO_R_IO) {
        request->driverStatus = SR_IOST_CHKSNV;
    } else {
        request->driverStatus = SR_IOST_HW;
    }

finish:
    [self endRequest];
    return request->driverStatus;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
                       buffer:(void *)buffer
                       client:(vm_task_t)client
{
    AHCIATAPIRequest request;
    sc_status_t status;

    if (scsiReq == 0)
        return SR_IOST_CMDREJ;
    scsiReq->bytesTransferred = 0;
    scsiReq->scsiStatus = STAT_CHECK;
    scsiReq->driverStatus = SR_IOST_CMDREJ;
    bzero(&request, sizeof(request));
    request.cdb = (const unsigned char *)&scsiReq->cdb.cdb_opcode;
    request.cdbLength = AHCIATAPIValidateCDBLength(request.cdb[0],
        scsiReq->cdbLength, sizeof(scsiReq->cdb));
    if (request.cdbLength == 0)
        return SR_IOST_CMDREJ;
    request.target = scsiReq->target;
    request.lun = scsiReq->lun;
    request.read = scsiReq->read;
    request.maxTransfer = scsiReq->maxTransfer;
    request.timeoutLength = scsiReq->timeoutLength;
    request.ignoreChkcond = scsiReq->ignoreChkcond;
    status = [self executeCommonRequest:&request buffer:buffer client:client];
    scsiReq->bytesTransferred = request.bytesTransferred;
    scsiReq->scsiStatus = request.scsiStatus;
    scsiReq->driverStatus = request.driverStatus;
    scsiReq->senseData = request.senseData;
    return status;
}

- (sc_status_t)executeSCSI3Request:(IOSCSI3Request *)scsiReq
                            buffer:(void *)buffer
                            client:(vm_task_t)client
{
    AHCIATAPIRequest request;
    sc_status_t status;

    if (scsiReq == 0)
        return SR_IOST_CMDREJ;
    scsiReq->bytesTransferred = 0;
    scsiReq->scsiStatus = STAT_CHECK;
    scsiReq->driverStatus = SR_IOST_CMDREJ;
    bzero(&request, sizeof(request));
    request.cdb = (const unsigned char *)&scsiReq->cdb.cdb_opcode;
    request.cdbLength = AHCIATAPIValidateCDBLength(request.cdb[0],
        scsiReq->cdbLength, sizeof(scsiReq->cdb));
    if (request.cdbLength == 0)
        return SR_IOST_CMDREJ;
    request.target = scsiReq->target;
    request.lun = scsiReq->lun;
    request.read = scsiReq->read;
    request.maxTransfer = scsiReq->maxTransfer;
    request.timeoutLength = scsiReq->timeoutLength;
    status = [self executeCommonRequest:&request buffer:buffer client:client];
    scsiReq->bytesTransferred = request.bytesTransferred;
    scsiReq->scsiStatus = request.scsiStatus;
    scsiReq->driverStatus = request.driverStatus;
    scsiReq->senseData = request.senseData;
    return status;
}

- (BOOL)reidentifyFromWords:(const unsigned short *)words
{
    AHCIATAPIIdentity identity;

    if (!AHCIATAPIParseIdentity(words, &identity))
        return NO;
    return AHCIATAPIIdentityMatches(&_identity, &identity) ? YES : NO;
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
    return [_port resetATAPIDevice:self] ? SR_IOST_GOOD : SR_IOST_HW;
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
