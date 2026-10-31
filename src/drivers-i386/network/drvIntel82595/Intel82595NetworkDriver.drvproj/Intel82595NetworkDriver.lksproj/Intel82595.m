/* Intel 82595 controller, reconstructed from drvIntel82595-21 (i386).
 * Reference addresses and review evidence are in ../../reconstruction. */
#import "Intel82595.h"
#import "i82595io.h"
#import <strings.h>

typedef struct {
    unsigned short command, status, next, length;
} I595PacketHeader;

@implementation Intel82595 (Private)

- (unsigned int)_onboardMemoryAvailable
{
    int available = [self onboardMemoryPresent] - memoryUsed;
    return available < 0 ? 0 : available;
}

- (unsigned short)_allocateOnboardMemory:(unsigned int)size
{
    unsigned short address = [self _memoryRegion:size];
    memoryUsed += size;
    return address;
}

- (BOOL)_mcSetup
{
    queue_head_t *queue = [super multicastQueue];
    enetMulti_t *entry;
    unsigned int count = 0, size, i;
    I595PacketHeader *packet;
    unsigned char mask;
    BOOL receiving = NO, success = YES;

    multicastConfigured = NO;
    if (!multicastEnabled || queue_empty(queue)) return YES;
    queue_iterate(queue, entry, enetMulti_t *, link) count++;
    size = 8 + 6 * count;
    packet = IOMalloc(size);
    if (packet == NULL) return NO;
    bzero(packet, 8);
    packet->command = 3;
    packet->length = 6 * count;
    i = 0;
    queue_iterate(queue, entry, enetMulti_t *, link) {
        bcopy(&entry->address, (char *)packet + 8 + 6 * i, 6);
        i++;
    }
    POINTER(transmitLower + 4096);
    WRITE_WORDS(packet, size);
    if (READ8(0, 1) & 0xc0) {
        COMMAND(10);
        receiving = YES;
    }
    mask = READ8(0, 3);
    WRITE8(0, 3, mask | 15);
    if (!WAIT(0x30, 0, 100)) success = NO;
    else {
        WRITE16(10, transmitLower + 4096);
        COMMAND(3);
        IOSleep(100);
        if (!WAIT(8, 8, 100)) success = NO;
        else {
            if ((inb(ioBase) & 0x3f) != 3) success = NO;
            WRITE8(0, 1, 8);
        }
    }
    IOFree(packet, size);
    multicastConfigured = success;
    WRITE8(0, 3, mask);
    if (receiving) COMMAND(8);
    return success;
}

- (unsigned short)_memoryRegion:(unsigned int)size
{
    if ([self _onboardMemoryAvailable] < size)
        IOPanic("Intel82595: onboard memory exhausted");
    return memoryUsed;
}

- (BOOL)_receiveInterruptOccurred
{
    I595PacketHeader header;
    netbuf_t packet = NULL;
    BOOL bad;
    [self reserveDebuggerLock];
    for (;;) {
        bad = NO;
        POINTER(receiveNext);
        READ_WORDS(&header.command, 2);
        if (!(header.command & 8)) break;
        READ_WORDS(&header.status, 6);
        if ((header.status & 0x2000) && header.length <= 1514) {
            packet = nb_alloc(header.length);
            if (packet != NULL) READ_WORDS(nb_map(packet), header.length);
            else {
                IOLog("%s: unable to allocate a netbuf\n", [self name]);
                [networkInterface incrementInputErrors];
                bad = YES;
            }
        } else {
            [networkInterface incrementInputErrors];
            bad = YES;
        }
        receiveNext = header.next;
        WRITE16(6, (receiveNext == receiveLower ? receiveUpper : receiveNext) - 1);
        if (!bad) {
            if (!promiscuousEnabled && (header.status & 2) &&
                [super isUnwantedMulticastPacket:(ether_header_t *)nb_map(packet)]) nb_free(packet);
            else {
                [self releaseDebuggerLock];
                [networkInterface handleInputPacket:packet extra:0];
                [self reserveDebuggerLock];
            }
        }
    }
    [self releaseDebuggerLock];
    return YES;
}

- (BOOL)_transmitInterruptOccurred
{
    unsigned short status;
    netbuf_t packet;
    if (transmitActive) {
        [self clearTimeout];
        POINTER(transmitLower + 2);
        READ_WORDS(&status, 2);
        if (status & 0x2000) [networkInterface incrementOutputPackets];
        else [networkInterface incrementOutputErrors];
        if (status & 0x20) [networkInterface incrementCollisionsBy:16];
        if (status & 15) [networkInterface incrementCollisionsBy:status & 15];
        if (status & 0x0800) [networkInterface incrementCollisions];
        transmitActive = NO;
    }
    packet = [transmitQueue dequeue];
    if (packet != NULL) [self transmit:packet];
    return YES;
}
@end

@implementation Intel82595

+ (BOOL)probeIDRegisterAt:(unsigned short)address
{
    unsigned char value, chip, sequence;
    int i;
    outb(address, 0);
    value = inb(address + 2);
    chip = (value >> 2) & 15;
    sequence = value >> 6;
    for (i = 0; i < 3; i++) {
        value = inb(address + 2);
        if (((value >> 2) & 15) != chip) return NO;
        sequence = (sequence + 1) & 3;
        if ((value >> 6) != sequence) return NO;
    }
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)description
{
    if ([super initFromDeviceDescription:description] == nil) return nil;
    ioBase = [(IOEISADeviceDescription *)description portRangeList]->start;
    irq = [(IOEISADeviceDescription *)description interrupt];
    promiscuousEnabled = multicastEnabled = multicastConfigured = transmitActive = NO;
    if ([self resetChip]) {
        myStepping = READ8(2, 10) >> 5;
        if (myStepping > 2) {
            IOLog("%s: i82595 version: %d.\n", [self name], myStepping);
            myStepping = 2;
        }
        if ([self coldInit] && [self resetAndEnable:YES]) {
            IOLog("%s at port 0x%x irq %d\n", [self description], ioBase, irq);
            transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:32];
            networkInterface = [super attachToNetworkWithAddress:myAddress];
            return self;
        }
    }
    [self free];
    return nil;
}

- free
{
    [self clearTimeout];
    [self disableAllInterrupts];
    [self resetChip];
    if (transmitQueue != nil) [transmitQueue free];
    [self unregisterDevice];
    return [super free];
}

- (BOOL)resetAndEnable:(BOOL)enable
{
    [self clearTimeout];
    [self disableAllInterrupts];
    if (![self resetChip]) return NO;
    transmitActive = NO;
    currentBank = 3;
    i595Bank(ioBase, &currentBank, 0);
    if (![self initializeChip] || ![self _mcSetup] ||
        ![self rxInit] || ![self txInit]) return NO;
    if (enable) {
        if ([self enableAllInterrupts] != IO_R_SUCCESS) {
            [self setRunning:NO];
            return NO;
        }
        COMMAND(8);
    }
    [self setRunning:enable];
    return YES;
}

- (BOOL)coldInit { return YES; }
- (const char *)description { return "Intel82595-based Ethernet Adapter"; }

- (BOOL)resetChip
{
    COMMAND(0x1e);
    IODelay(200);
    currentBank = 3;
    i595Bank(ioBase, &currentBank, 0);
    return YES;
}

- (BOOL)initializeChip
{
    unsigned char value;
    int i;
    value = READ8(0, 3);
    WRITE8(0, 3, (value & 0xd0) | 8);
    value = READ8(1, 2);
    WRITE8(1, 2, (value & 15) | 0x80);
    if (![self busConfig]) return NO;
    for (i = 0; i < 6; i++) WRITE8(2, i + 4, myAddress.ether_addr_octet[i]);
    if (!WAIT(0x30, 0, 100)) return NO;
    value = READ8(2, 2);
    value = (value & (myStepping == 2 ? 0xf0 : 0xf8)) |
            (promiscuousEnabled & 1) | 4;
    WRITE8(2, 2, (value & 15) | 0x10);
    if (!WAIT(0x30, 0, 100) || ![self connectorConfig]) return NO;
    IODelay(10000);
    if (!WAIT(0x30, 0, 1000)) return NO;
    COMMAND(0x1e);
    IOSleep(100);
    memoryUsed = 0;
    return YES;
}

- (BOOL)busConfig { return YES; }
- (BOOL)connectorConfig { WRITE8(2, 3, 4); return YES; }

- (BOOL)rxInit
{
    unsigned int size;
    unsigned char value;
    if ([self onboardMemoryPresent] >= 65536) size = 57344;
    else if ([self onboardMemoryPresent] >= 32768) size = 25600;
    else {
        IOLog("%s: unsupported memory configuration\n", [self name]);
        return NO;
    }
    value = READ8(2, 1);
    WRITE8(2, 1, value | 0x80);
    WRITE8(2, 11, 0);
    if (myStepping == 2) { WRITE8(1, 7, 0); WRITE8(0, 8, 0); }
    receiveLower = [self _allocateOnboardMemory:size];
    receiveUpper = receiveLower + size;
    receiveNext = receiveLower;
    WRITE8(1, 8, receiveLower >> 8);
    WRITE8(1, 9, (unsigned short)(receiveUpper - 256) >> 8);
    WRITE16(6, receiveUpper - 256);
    WRITE16(4, receiveLower);
    return YES;
}

- (BOOL)txInit
{
    unsigned int size;
    unsigned char value;
    if ([self onboardMemoryPresent] >= 65536) size = 7168;
    else if ([self onboardMemoryPresent] >= 32768) size = 5120;
    else {
        IOLog("%s: unsupported memory configuration\n", [self name]);
        return NO;
    }
    value = READ8(2, 1);
    if (myStepping == 2) value &= 0xfe;
    WRITE8(2, 1, value & 0xdf);
    transmitLower = [self _allocateOnboardMemory:size];
    transmitUpper = transmitLower + size;
    WRITE8(1, 10, transmitLower >> 8);
    WRITE8(1, 11, (unsigned short)(transmitUpper - 256) >> 8);
    return YES;
}

- (unsigned int)onboardMemoryPresent { return 65536; }

- (IOReturn)enableAllInterrupts
{
    unsigned char value = READ8(1, 1);
    WRITE8(1, 1, value | 0x80);
    return [super enableAllInterrupts];
}

- (void)disableAllInterrupts
{
    unsigned char value;
    [super disableAllInterrupts];
    value = READ8(1, 1);
    WRITE8(1, 1, value & 0x7f);
}

- (void)interruptOccurred
{
    unsigned char status = READ8(0, 1);
    while (status & 15) {
        WRITE8(0, 1, status);
        if ((status & 2) && ![self _receiveInterruptOccurred]) break;
        if ((status & 4) && ![self _transmitInterruptOccurred]) break;
        if (status & 1) {
            [networkInterface incrementInputErrorsBy:READ8(2, 11)];
            WRITE8(2, 11, 0);
        }
        status = READ8(0, 1);
    }
}

- (void)timeoutOccurred
{
    netbuf_t packet;
    if ([self isRunning] && [self resetAndEnable:YES]) {
        packet = [transmitQueue dequeue];
        if (packet != NULL) [self transmit:packet];
    }
    if (![self isRunning] && [transmitQueue count]) {
        transmitActive = NO;
        while ((packet = [transmitQueue dequeue]) != NULL) nb_free(packet);
    }
}

- (void)transmit:(netbuf_t)packet
{
    I595PacketHeader header;
    if (transmitActive) { [transmitQueue enqueue:packet]; return; }
    transmitActive = YES;
    [self performLoopback:packet];
    bzero(&header, 8);
    header.command = 4;
    header.length = nb_size(packet) & 0x7fff;
    POINTER(transmitLower);
    WRITE_WORDS(&header, 8);
    WRITE_WORDS(nb_map(packet), nb_size(packet));
    nb_free(packet);
    WAIT(0x30, 0, 100);
    WRITE16(10, transmitLower);
    COMMAND(4);
    [self setRelativeTimeout:3000];
}

- (BOOL)enablePromiscuousMode
{
    if (promiscuousEnabled) return YES;
    promiscuousEnabled = YES;
    return [self resetAndEnable:[self isRunning]];
}

- (void)disablePromiscuousMode
{
    if (promiscuousEnabled) {
        promiscuousEnabled = NO;
        [self resetAndEnable:[self isRunning]];
    }
}

- (void)addMulticastAddress:(enet_addr_t *)address
{
    multicastEnabled = YES;
    if (![self _mcSetup]) IOLog("%s: add multicast address failed\n", [self name]);
}

- (void)removeMulticastAddress:(enet_addr_t *)address
{
    if (![self _mcSetup]) IOLog("%s: remove multicast address failed\n", [self name]);
}

- (void)receivePacket:(void *)packet length:(unsigned int *)length timeout:(unsigned int)timeout
{
    int remaining = timeout * 1000;
    I595PacketHeader header;
    POINTER(receiveNext);
    READ_WORDS(&header.command, 2);
    while (!(header.command & 8)) {
        if (remaining <= 0) { *length = 0; return; }
        IODelay(50);
        remaining -= 50;
        POINTER(receiveNext);
        READ_WORDS(&header.command, 2);
    }
    READ_WORDS(&header.status, 6);
    /* Like the reference, a bad descriptor leaves the caller's length intact. */
    if ((header.status & 0x2000) && header.length <= 1514) {
        *length = header.length;
        READ_WORDS(packet, *length);
    }
    receiveNext = header.next;
    WRITE16(6, (receiveNext == receiveLower ? receiveUpper : receiveNext) - 1);
}

- (void)sendPacket:(void *)packet length:(unsigned int)length
{
    I595PacketHeader header;
    if (transmitActive) {
        while (!(READ8(0, 1) & 4)) ;
        WRITE8(0, 1, 4);
    }
    if (length < 64) length = 64;
    bzero(&header, 8);
    header.command = 4;
    header.length = length & 0x7fff;
    POINTER(transmitLower);
    WRITE_WORDS(&header, 8);
    WRITE_WORDS(packet, length);
    WAIT(0x30, 0, 100);
    WRITE16(10, transmitLower);
    COMMAND(4);
    if (!transmitActive) {
        while (!(READ8(0, 1) & 4)) ;
        WRITE8(0, 1, 4);
    }
}
@end
