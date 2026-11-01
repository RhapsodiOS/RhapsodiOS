/* Reconstructed BLFPController methods from the supplied i386 image. */
#import "BusLogicFPSCSI.h"
#import <driverkit/generalFuncs.h>
#import <strings.h>

extern int page_size;
extern void IOFree(void *address, unsigned int size);
extern void *IOMalloc(unsigned int size);
extern int SccbMgr_isr(struct sccb_card *card);
extern void IOGetTimestamp(u32 timestamp[2]);
extern void IOUnscheduleFunc(int (*function)(int), void *argument);
extern int blcTimeout(int message);
extern void IOExitThread(void);
extern void IOScheduleFunc(int (*function)(int), void *argument, int seconds);
extern int msg_send_from_kernel(void *message, int option, int timeout);
extern int IOPhysicalFromVirtual(void *task, u32 virtualAddress, u32 *physicalAddress);
extern int BLCCallback(struct sccb *sccb);
extern void bcopy(const void *source, void *destination, unsigned int length);
extern char *strcpy(char *destination, const char *source);
extern char *strncpy(char *destination, const char *source, unsigned int length);
extern int sprintf(char *destination, const char *format, ...);
extern long strtol(const char *string, char **end, int base);
extern int strcmp(const char *left, const char *right);
extern int IOConvertPort(int port);
extern int task_self(int port);
extern int port_set_backlog_EXTERNAL(int task, int backlog);

struct blfp_message_header {
    u32 bits;
    u32 size;
    u32 remotePort;
    u32 localPort;
    u32 reserved;
    u32 identifier;
};

static const struct blfp_message_header BLCMessageTemplate = {
    0x01000000, 0x18, 0, 0, 0, 0x00232324
};
static const struct blfp_message_header timeoutMsgTemplate = {
    0x01000000, 0x18, 0, 0, 0, 0x00232323
};

struct blfp_io_range { u32 start; u32 size; };
struct blfp_pci_config_space { u8 bytes[256]; };

@interface IODirectDevice : IOSCSIController
+ (int)getPCIConfigSpace:(struct blfp_pci_config_space *)space
    withDeviceDescription:(id)description;
+ (const char *)stringFromReturn:(int)status;
@end

@protocol BLFPConfigDevice
- (int)setInterruptList:(int *)interrupts num:(unsigned int)count;
- (int)setPortRangeList:(struct blfp_io_range *)ranges num:(unsigned int)count;
@end

@protocol BLFPProbeDevice
- (id)configTable;
- (const char *)valueForString:(const char *)key;
- (void)freeString:(const char *)value;
- (unsigned int)numPortRanges;
- (unsigned int)numInterrupts;
- (u16 *)portRangeList;
- (int)interrupt;
@end

int parseConfigSpace(id device, const char *title, unsigned int rangeSize,
                     u16 *baseAddress, u32 *interrupt)
{
    struct blfp_pci_config_space config;
    struct blfp_io_range range;
    u32 *bases = (u32 *)(config.bytes + 16);
    u32 irq;
    int found = 0;
    int status;

    bzero(&config, sizeof(config));
    status = [IODirectDevice getPCIConfigSpace:&config withDeviceDescription:device];
    if (status != 0) {
        IOLog("%s: Can't get configSpace (%s); ABORTING\n", title,
              [IODirectDevice stringFromReturn:status]);
        return 0;
    }
    irq = config.bytes[60];
    *interrupt = irq;
    if (bases[0] == 0 || irq == 0) {
        IOLog("%s: Bogus config info (IRQ %d, Base 0x%x)\n", title, irq,
              (unsigned int)bases);
        return 0;
    }
    for (int i = 0; i <= 5; ++i) {
        if ((bases[i] & 1) != 0) {
            if (found) {
                IOLog("%s: Multiple I/O Port Bases Found\n", title);
                return 0;
            }
            found = 1;
            range.start = bases[i] & 0xfc;
        }
    }
    if (!found) {
        IOLog("%s: No I/O Port Base Found\n", title);
        return 0;
    }
    range.size = rangeSize;
    *baseAddress = (u16)range.start;
    status = [(id<BLFPConfigDevice>)device setInterruptList:(int *)interrupt num:1];
    if (status != 0) {
        IOLog("%s: Can't set interruptList to IRQ %d (%s)\n", title, irq,
              [IODirectDevice stringFromReturn:status]);
        return 0;
    }
    status = [(id<BLFPConfigDevice>)device setPortRangeList:&range num:1];
    if (status != 0) {
        IOLog("%s: Can't set portRangeList to port 0x%x (%s)\n", title,
              range.start, [IODirectDevice stringFromReturn:status]);
        return 0;
    }
    return 1;
}

int blcTimeout(int message)
{
    struct sccb *sccb = (struct sccb *)(unsigned long)(u32)message;
    struct blfp_message_header timeoutMessage = timeoutMsgTemplate;
    int result = message;
    if (sccb->TimeoutScheduled != 0) {
        timeoutMessage.remotePort = sccb->DriverReserved240;
        IOLog("BLC timeout\n");
        result = msg_send_from_kernel(&timeoutMessage, 0, 0);
        if (result != 0)
            IOLog("blcTimeout: msg_send_from_kernel() returned %d\n", result);
    }
    return result;
}

int BLCCallback(struct sccb *sccb)
{
    BLFPController *controller = (BLFPController *)sccb->Controller;
    [controller sccbComplete:sccb reason:0];
    return 0;
}

@implementation BLFPController

+ (int)probe:(id)deviceDescription
{
    id<BLFPProbeDevice> device = (id<BLFPProbeDevice>)deviceDescription;
    id config = [device configTable];
    const char *instance = [config valueForString:"Instance"];
    BLFPController *controller = 0;
    const char *bus;

    if (instance == 0) {
        IOLog("BusLogic: No Instance string in Config Table; aborting\n");
        [config freeString:0];
        goto fail;
    }
    if ((unsigned int)strtol(instance, 0, 10) > 3) {
        IOLog("BusLogic: Instance = %d; Max = %d; aborting\n");
        goto fail;
    }
    [config freeString:instance];
    controller = [self alloc];
    bus = [config valueForString:"Bus Type"];
    if (bus != 0 && strcmp(bus, "EISA") == 0)
        controller->busType = 1;
    else if (bus != 0 && strcmp(bus, "VL") == 0)
        controller->busType = 2;
    else if (bus != 0 && strcmp(bus, "PCI") == 0)
        controller->busType = 3;
    else
        controller->busType = 0;
    if (bus != 0)
        [config freeString:bus];

    if (controller->busType == 3) {
        if (!parseConfigSpace(deviceDescription, "BusLogic", 4,
                              &controller->ioBase, &controller->irq))
            goto fail;
    } else {
        if ([device numPortRanges] == 0) {
            IOLog("BusLogic: can't determine port base!\n");
            goto fail;
        }
        if ([device numInterrupts] != 1) {
            IOLog("BusLogic: %d Interrupts in config table!\n",
                  [device numInterrupts]);
            goto fail;
        }
        controller->ioBase = *[device portRangeList];
        controller->irq = (u32)[device interrupt];
    }
    if ([controller probeForBoard])
        return [controller initFromDeviceDescription:deviceDescription] != 0;
fail:
    if (controller != 0)
        [controller free];
    return 0;
}

- (id)initFromDeviceDescription:(id)deviceDescription
{
    id initialized = [super initFromDeviceDescription:deviceDescription];
    id<BLFPProbeDevice> device = (id<BLFPProbeDevice>)deviceDescription;

    if (initialized == 0) {
        [super free];
        return 0;
    }
    self->outstandingQ.links.next = (struct sccb *)&self->outstandingQ.links;
    self->outstandingQ.links.prev = (struct sccb *)&self->outstandingQ.links;
    self->commandQ.links.next = (struct sccb *)&self->commandQ.links;
    self->commandQ.links.prev = (struct sccb *)&self->commandQ.links;
    self->sccbFreeList.links.next = (struct sccb *)&self->sccbFreeList.links;
    self->sccbFreeList.links.prev = (struct sccb *)&self->sccbFreeList.links;
    self->commandLock = [[NXLock alloc] init];
    self->outstandingCount = 0;
    self->interruptPortKern = IOConvertPort([self interruptPort]);
    self->ioThreadRunning = 1;
    self->sccbMgr->flags |= 0x41;
    self->sccbMgr->flags &= (u8)~4;
    if ([self resetHardware] != 0)
        [self free];

    if (self->busType != 3 && self->irq != (u32)[device interrupt]) {
        IOLog("BLFPController: Actual IRQ (%d) doesn't match configured value (%d)!\n",
              [device interrupt], self->irq);
        return [self free];
    }

    [self createSCCBs];
    [self resetStats];
    {
        id config = [device configTable];
        const char *shareLevels = [config valueForString:"Share IRQ Levels"];
        self->levelIRQ = shareLevels != 0 && strcmp(shareLevels, "YES") == 0;
        if (shareLevels != 0)
            [config freeString:shareLevels];
    }
    for (unsigned int lun = 0; lun <= 7; ++lun)
        [self reserveTarget:self->sccbMgr->adapterId lun:lun forOwner:self];
    [self enableAllInterrupts];
    if (port_set_backlog_EXTERNAL(task_self([self interruptPort]), 16) != 0)
        IOLog("%s: error %d on port_set_backlog()\n", [self name], -1);
    [self registerDevice];
    return self;
}

- (unsigned int)maxTransfer
{
    return 16 * page_size;
}

- (int)numberOfTargets
{
    return self->targetsPerBus;
}

- (unsigned int)numQueueSamples
{
    return self->totalCommands;
}

- (unsigned int)sumQueueLengths
{
    return self->queueLenTotal;
}

- (unsigned int)maxQueueLength
{
    return self->maxQueueLen;
}

- (void)resetStats
{
    self->totalCommands = 0;
    self->queueLenTotal = 0;
    self->maxQueueLen = 0;
}

- (int)executeRequest:(id)request buffer:(void *)buffer client:(vm_task_t)client
{
    struct blfp_command_record command;
    bzero(&command, sizeof(command));
    command.command = 0;
    command.request = request;
    command.dataBuffer = buffer;
    command.clientTask = (void *)client;
    [self executeCmdBuf:&command];
    return command.result;
}

- (int)resetSCSIBus
{
    struct blfp_command_record command;
    bzero(&command, sizeof(command));
    command.command = 1;
    [self executeCmdBuf:&command];
    return command.result;
}

- (void)interruptOccurred
{
    if (SccbMgr_my_int(self->cardHandle))
        SccbMgr_isr(self->cardHandle);
    if (self->levelIRQ != 0)
        [self enableAllInterrupts];
}

- (void)interruptOccurredAt:(int)interrupt
{
    IOLog("%s: interruptOccurredAt:%d\n", [self name], interrupt);
}

- (void)otherOccurred:(int)message
{
    IOLog("%s: otherOccurred:%d\n", [self name], message);
}

- (void)receiveMsg
{
    IOLog("%s: receiveMsg\n", [self name]);
    [super receiveMsg];
}

- (int)resetHardware
{
    struct sccb_card *card = SccbMgr_config_adapter(self->sccbMgr);
    if (card == (struct sccb_card *)-1) {
        IOLog("BusLogicFP: SccbMgr_config_adapter FAILURE\n");
        return 1;
    }
    self->cardHandle = card;
    IOLog("BusLogicFP: Resetting SCSI Bus...\n");
    IOSleep(10000);
    return 0;
}

- (int)probeForBoard
{
    char model[4];
    char family[80];
    u32 raw = (u32)IOMalloc(128);
    u32 infoAddress = raw;
    int boardType = self->busType;

    if (doesCrossPage(raw, SCCB_MGR_INFO_SIZE))
        infoAddress += SCCB_MGR_INFO_SIZE;
    self->sccbMgrRaw = (void *)raw;
    self->sccbMgr = (struct sccb_mgr_info *)infoAddress;
    bzero(self->sccbMgr, SCCB_MGR_INFO_SIZE);
    self->sccbMgr->ioBase = self->ioBase;
    self->sccbMgr->present = 0;
    self->sccbMgr->interruptVector = (u8)self->irq;
    self->sccbMgr->owner = self;
    switch (boardType) {
    case 1: self->sccbMgr->busType = 2; break;
    case 2: self->sccbMgr->busType = 4; break;
    case 3: self->sccbMgr->busType = 3; break;
    case 0: self->sccbMgr->busType = 1; break;
    default: break;
    }
    if (SccbMgr_sense_adapter(self->sccbMgr) != 0) {
        IOLog("BusLogic: SCCB Manager reports error (0x%x) on sense_adapter()\n");
        return 0;
    }
    if (self->sccbMgr->present == 0) {
        IOLog("BusLogic: Board not found at port 0x%x\n", self->ioBase);
        return 0;
    }
    self->targetsPerBus = (self->sccbMgr->flags & 2) ? 16 : 8;
    if (self->sccbMgr->family == 1)
        strcpy(family, "Crossbow");
    else if (self->sccbMgr->family == 2)
        strcpy(family, "FlashPoint");
    else
        sprintf(family, "Unknown Family (%d)", self->sccbMgr->family);
    strncpy(model, (const char *)self->sccbMgr->cardModel, 3);
    model[3] = 0;
    IOLog("BusLogic %s Model %s at port 0x%x\n", family, model, self->ioBase);
    IOLog("   %d Targets per Bus; Host ID = %d\n", self->targetsPerBus,
          self->sccbMgr->adapterId);
    return 1;
}

- (id)free
{
    if (self->ioThreadRunning != 0) {
        struct blfp_command_record command;
        bzero(&command, sizeof(command));
        command.command = 2;
        [self executeCmdBuf:&command];
    }
    if (self->commandLock != 0)
        [(NXConditionLock *)self->commandLock free];
    if (self->sccbMgrRaw != 0)
        IOFree(self->sccbMgrRaw, 128);
    return [super free];
}

- (struct sccb *)allocSccb
{
    struct sccb_queue_links *head = &self->sccbFreeList.links;
    struct sccb *sentinel = (struct sccb *)head;
    struct sccb *next;
    struct sccb *following;

    if (head->next == sentinel)
        [self createSCCBs];
    next = head->next;
    following = next->QueueLinks.next;
    if (sentinel == following)
        head->prev = following;
    else
        following->QueueLinks.prev = sentinel;
    head->next = following;
    bzero(next, SCCB_SIZE);
    return (struct sccb *)next;
}

- (void)freeSccb:(struct sccb *)sccb
{
    struct sccb_queue_links *head = &self->sccbFreeList.links;
    struct sccb *sentinel = (struct sccb *)head;
    struct sccb *previous = head->prev;

    if (sentinel == previous)
        head->next = sccb;
    else
        previous->QueueLinks.next = sccb;
    sccb->QueueLinks.prev = previous;
    sccb->QueueLinks.next = sentinel;
    head->prev = sccb;
}

- (void)createSCCBs
{
    u32 start = (u32)IOMalloc((unsigned int)page_size);
    u32 current = start;
    u32 last = start + (u32)page_size - SCCB_SIZE;

    while (last > current) {
        if (!doesCrossPage(current, SCCB_SIZE)) {
            struct sccb *sccb = (struct sccb *)current;
            struct sccb_queue_links *head = &self->sccbFreeList.links;
            struct sccb *sentinel = (struct sccb *)head;
            struct sccb *previous = head->prev;
            bzero(sccb, SCCB_SIZE);
            if (sentinel == previous)
                head->next = sccb;
            else
                previous->QueueLinks.next = sccb;
            sccb->QueueLinks.prev = previous;
            sccb->QueueLinks.next = sentinel;
            head->prev = sccb;
        }
        current += SCCB_SIZE;
    }
}

- (void)cmdComplete:(struct blfp_command_record *)command
{
    if (command->request != 0) {
        u32 timestamp[2];
        u32 startLow = (u32)command->timestamp;
        u32 startHigh = (u32)(command->timestamp >> 32);
        u32 borrow;
        u32 *request = (u32 *)command->request;
        IOGetTimestamp(timestamp);
        borrow = timestamp[0] < startLow;
        request[10] = timestamp[0] - startLow;
        request[11] = timestamp[1] - startHigh - borrow;
    }
    if (command->sccb != 0) {
        [self freeSccb:command->sccb];
        command->sccb = 0;
    }
    [(id<BLFPConditionLockInterface>)command->conditionLock lock];
    [(id<BLFPConditionLockInterface>)command->conditionLock unlockWith:1];
}

- (void)sccbComplete:(struct sccb *)sccb reason:(int)reason
{
    struct blfp_command_record *command =
        (struct blfp_command_record *)sccb->CommandRecord;
    u32 *request = (u32 *)command->request;
    u32 status;

    if (sccb->TimeoutScheduled != 0) {
        sccb->TimeoutScheduled = 0;
        IOUnscheduleFunc(blcTimeout, sccb);
    }
    if (reason == 1) {
        request[7] = 5;
    } else if (reason == 2) {
        request[7] = 20;
    } else if (reason == 0) {
        struct sccb_queue_links *head = &self->outstandingQ.links;
        struct sccb *sentinel = (struct sccb *)head;
        struct sccb *next = sccb->QueueLinks.next;
        struct sccb *previous = sccb->QueueLinks.prev;
        if (sentinel == previous)
            head->next = next;
        else
            previous->QueueLinks.next = next;
        if (sentinel == next)
            head->prev = previous;
        else
            next->QueueLinks.prev = previous;
        --self->outstandingCount;
        ((u8 *)request)[32] = sccb->TargetStatus;
        switch (sccb->HostStatus) {
        case 0:
        case 12:
        case 18:
            request[9] = command->transferred - sccb->DataLength;
            if (((u8 *)request)[32] == 0)
                request[7] = 0;
            else if (((u8 *)request)[32] == 2)
                request[7] = 2;
            else
                request[7] = 13;
            break;
        case 17:
            request[7] = 1;
            break;
        case 52:
            IOLog("%s: Host Adapter Parity Error\n", [self name]);
            request[7] = 21;
            break;
        case 53:
            IOLog("%s: SCSI Bus Reset Detected\n", [self name]);
            request[7] = 20;
            break;
        default:
            IOLog("BLC interrupt: bad status 0x%x\n", sccb->HostStatus);
            request[7] = 22;
            break;
        }
    }
    status = request[7];
    command->result = (int)status;
    [self cmdComplete:command];
}

- (int)executeCmdBuf:(struct blfp_command_record *)command
{
    struct blfp_message_header message = BLCMessageTemplate;
    int result = 0;
    int sendResult;
    NXConditionLock *conditionLock = [[NXConditionLock alloc] initWith:0];
    command->conditionLock = conditionLock;

    [(id<BLFPConditionLockInterface>)self->commandLock lock];
    {
        struct blfp_queue_head *head = &self->commandQ;
        struct blfp_command_record *sentinel =
            (struct blfp_command_record *)&head->links;
        struct blfp_command_record *previous =
            (struct blfp_command_record *)head->links.prev;
        command->queue.next = (struct sccb *)sentinel;
        command->queue.prev = (struct sccb *)previous;
        if (sentinel == previous)
            head->links.next = (struct sccb *)command;
        else
            previous->queue.next = (struct sccb *)command;
        head->links.prev = (struct sccb *)command;
    }
    [(id<BLFPLockInterface>)self->commandLock unlock];

    message.remotePort = self->interruptPortKern;
    sendResult = msg_send_from_kernel(&message, 0, 0);
    if (sendResult != 0) {
        IOLog("%s: msg_send_from_kernel() returned %d\n", [self name], sendResult);
        result = -703;
    } else {
        [(id<BLFPConditionLockInterface>)conditionLock lockWhen:1];
    }
    [conditionLock free];
    return result;
}

- (void)threadExecuteRequest:(struct blfp_command_record *)command
{
    struct sccb *sccb = [self allocSccb];

    command->sccb = sccb;
    if ([self sccbFromCmd:command] != 0) {
        [self cmdComplete:command];
        return;
    }
    *(u32 *)((u8 *)sccb + 240) = self->interruptPortKern;
    IOScheduleFunc(blcTimeout, sccb, ((u32 *)command->request)[5]);
    sccb->TimeoutScheduled = 1;
    {
        struct sccb_queue_links *head = &self->outstandingQ.links;
        struct sccb *sentinel = (struct sccb *)head;
        struct sccb *previous = head->prev;
        if (sentinel == previous)
            head->next = sccb;
        else
            previous->QueueLinks.next = sccb;
        sccb->QueueLinks.prev = previous;
        sccb->QueueLinks.next = sentinel;
        head->prev = sccb;
    }
    ++self->outstandingCount;
    if (self->outstandingCount > self->maxQueueLen)
        self->maxQueueLen = self->outstandingCount;
    self->queueLenTotal += self->outstandingCount;
    ++self->totalCommands;
    SccbMgr_start_sccb(self->cardHandle, sccb);
}

- (int)sccbFromCmd:(struct blfp_command_record *)command
{
    u8 *request = (u8 *)command->request;
    struct sccb *sccb = command->sccb;
    u8 group = request[2] & 0xe0;
    u8 control;
    u32 address = (u32)command->dataBuffer;
    u32 length = *(u32 *)(request + 16);
    u32 pages = 0;
    u32 physical;
    u32 senseAddress = *(u32 *)(request + 56);
    unsigned int cdbLength;
    unsigned int segments;

    sccb->Controller = self;
    switch (group) {
    case 0x00:
        cdbLength = 6;
        control = request[7];
        break;
    case 0x20:
    case 0x40:
        cdbLength = 10;
        control = request[11];
        break;
    case 0xa0:
        cdbLength = 12;
        control = request[13];
        break;
    case 0xc0:
        cdbLength = (request[27] & 0xf0) ? request[27] >> 4 : 6;
        control = 0;
        break;
    case 0xe0:
        cdbLength = (request[27] & 0xf0) ? request[27] >> 4 : 10;
        control = 0;
        break;
    default:
        *(u32 *)(request + 28) = 7;
        return 1;
    }
    if ((control & 3) != 0) {
        *(u32 *)(request + 28) = 7;
        return 1;
    }

    if (length != 0) {
        u32 pageEnd = (address + length + page_mask) & ~page_mask;
        u32 firstPage = address & ~page_mask;
        pages = (pageEnd - firstPage) / (u32)page_size;
    }
    bcopy(request + 2, sccb->Cdb, 12);
    sccb->CdbLength = (u8)cdbLength;
    sccb->ControlByte = request[14] == 0 ? 16 : 8;
    sccb->TargID = request[0];
    sccb->Lun = request[1];

    if (IOPhysicalFromVirtual(command->clientTask, senseAddress,
                              &sccb->SensePointer) != 0) {
        IOLog("%s: Can't get physical address of sense buffer\n", [self name]);
        sccb->RequestSenseLength = 1;
    } else {
        sccb->RequestSenseLength = 26;
    }
    sccb->CommandRecord = command;
    command->transferred = 0;
    IOGetTimestamp((u32 *)&command->timestamp);

    if (pages == 0) {
        sccb->DataLength = 0;
        sccb->DataPointer = 0;
        sccb->OperationCode = 3;
    } else if (pages == 1) {
        if (IOPhysicalFromVirtual(command->clientTask, address, &physical) != 0)
            goto physical_error;
        sccb->DataPointer = (void *)physical;
        sccb->DataLength = length;
        sccb->OperationCode = 3;
        command->transferred = length;
    } else {
        u32 remaining = length;
        segments = pages > SG_ELEMENT_COUNT ? SG_ELEMENT_COUNT : pages;
        for (unsigned int i = 0; i < segments; ++i) {
            u32 chunk = ((address + (u32)page_size - 1) & ~page_mask) - address;
            if (remaining <= chunk)
                chunk = remaining;
            if (IOPhysicalFromVirtual(command->clientTask, address,
                                      &physical) != 0)
                goto physical_error;
            sccb->SGEntries[i].length = chunk;
            sccb->SGEntries[i].address = physical;
            command->transferred += chunk;
            address += chunk;
            remaining -= chunk;
        }
        sccb->DataPointer = sccb->SGEntries;
        sccb->DataLength = segments * sizeof(struct sccb_sg_entry);
        sccb->OperationCode = 4;
    }
    sccb->SccbCallback = BLCCallback;
    sccb->SccbIOPort = self->ioBase;
    return 0;

physical_error:
    IOLog("%s: Can't get physical address\n", [self name]);
    *(u32 *)(request + 28) = 14;
    return 1;
}

- (void)timeoutOccurred
{
    u32 nowWords[2];
    blfp_u64 now;
    int expired = 0;
    struct sccb_queue_links *head = &self->outstandingQ.links;
    struct sccb *sentinel = (struct sccb *)head;
    struct sccb *sccb = head->next;

    IOGetTimestamp(nowWords);
    now = ((blfp_u64)nowWords[1] << 32) | nowWords[0];
    while (sccb != sentinel) {
        struct sccb *next = sccb->QueueLinks.next;
        struct blfp_command_record *command =
            (struct blfp_command_record *)sccb->CommandRecord;
        u32 timeoutSeconds = ((u32 *)command->request)[5];
        blfp_u64 deadline = command->timestamp + 1000000000ULL * timeoutSeconds;

        if (now >= deadline) {
            struct sccb *previous = sccb->QueueLinks.prev;
            if (sentinel == next)
                head->prev = previous;
            else
                next->QueueLinks.prev = previous;
            if (sentinel == previous)
                head->next = next;
            else
                previous->QueueLinks.next = next;
            --self->outstandingCount;
            [self sccbComplete:sccb reason:1];
            expired = 1;
        }
        sccb = next;
    }
    if (expired)
        [self threadResetBus:0];
}

- (void)threadResetBus:(struct blfp_command_record *)command
{
    struct sccb_queue_links *head = &self->outstandingQ.links;
    struct sccb *sentinel = (struct sccb *)head;

    while (head->next != sentinel) {
        struct sccb *sccb = head->next;
        struct sccb *next = sccb->QueueLinks.next;
        if (sentinel == next)
            head->prev = sccb->QueueLinks.prev;
        else
            next->QueueLinks.prev = sccb->QueueLinks.prev;
        head->next = next;
        --self->outstandingCount;
        [self sccbComplete:sccb reason:2];
    }
    {
        int status = [self resetHardware];
        if (command != 0) {
            command->result = status ? 22 : 0;
            [(id<BLFPConditionLockInterface>)command->conditionLock lock];
            [(id<BLFPConditionLockInterface>)command->conditionLock unlockWith:1];
        }
    }
    if (self->levelIRQ != 0)
        [self enableAllInterrupts];
}

- (void)commandRequestOccurred
{
    struct blfp_queue_head *head = &self->commandQ;
    struct blfp_command_record *sentinel =
        (struct blfp_command_record *)&head->links;

    [(id<BLFPConditionLockInterface>)self->commandLock lock];
    if ((struct blfp_command_record *)head->links.next != sentinel) {
        do {
            struct blfp_command_record *command =
                (struct blfp_command_record *)head->links.next;
            struct blfp_command_record *next =
                (struct blfp_command_record *)command->queue.next;
            struct blfp_command_record *previous =
                (struct blfp_command_record *)command->queue.prev;
            if (sentinel == next)
                head->links.prev = (struct sccb *)previous;
            else
                next->queue.prev = (struct sccb *)previous;
            if (sentinel == previous)
                head->links.next = (struct sccb *)next;
            else
                previous->queue.next = (struct sccb *)next;
            [(id<BLFPLockInterface>)self->commandLock unlock];
            switch (command->command) {
            case 1:
                [self threadResetBus:command];
                break;
            case 0:
                [self threadExecuteRequest:command];
                break;
            case 2:
                [(id<BLFPConditionLockInterface>)command->conditionLock lock];
                [(id<BLFPConditionLockInterface>)command->conditionLock unlockWith:1];
                IOExitThread();
                break;
            default:
                break;
            }
            [(id<BLFPConditionLockInterface>)self->commandLock lock];
        } while ((struct blfp_command_record *)head->links.next != sentinel);
    }
    [(id<BLFPLockInterface>)self->commandLock unlock];
}

@end
