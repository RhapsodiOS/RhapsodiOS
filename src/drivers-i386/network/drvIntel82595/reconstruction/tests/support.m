#import "support.h"

unsigned char regs[3][16], ram[65536], pnpBytes[40];
unsigned short ramPointer, stopPointer;
int bankNumber, frees, allocFails, inputErrors, inputPackets;
int outputPackets, outputErrors, collisions, locks, timeoutValue;
int enableResult, probeInits, unwanted, loopbacks, readsFromRam;
int ioWrites, pnpCount;
id deviceDescription;
static unsigned char idCounter;

void resetHardware(void)
{
    memset(regs, 0, sizeof(regs)); memset(ram, 0, sizeof(ram));
    bankNumber = ramPointer = stopPointer = 0;
    frees = allocFails = inputErrors = inputPackets = 0;
    outputPackets = outputErrors = collisions = locks = timeoutValue = 0;
    enableResult = probeInits = unwanted = loopbacks = readsFromRam = 0;
    ioWrites = pnpCount = idCounter = 0;
}
unsigned char inb(unsigned short port)
{
    if (port == 0x302 && bankNumber == 0) return 0x14 | ((idCounter++ & 3) << 6);
    return regs[bankNumber][port - 0x300];
}
unsigned short inw(unsigned short port)
{
    unsigned short value;
    assert(port == 0x30e);
    value = ram[ramPointer] | (ram[(unsigned short)(ramPointer + 1)] << 8);
    ramPointer += 2; readsFromRam++;
    return value;
}
void outb(unsigned short port, unsigned char value)
{
    ioWrites++;
    if (port == 0x279) { assert(pnpCount < 40); pnpBytes[pnpCount++] = value; return; }
    if (port == 0x300) {
        bankNumber = value >> 6;
        assert(bankNumber < 3);
        regs[bankNumber][0] = value;
        if ((value & 31) == 3 || (value & 31) == 14) regs[0][1] |= 8;
        if ((value & 31) == 4) regs[0][1] |= 4;
        return;
    }
    if (port == 0x301 && bankNumber == 0) regs[0][1] &= ~value;
    else regs[bankNumber][port - 0x300] = value;
}
void outw(unsigned short port, unsigned short value)
{
    ioWrites++;
    assert(bankNumber == 0);
    if (port == 0x30c) ramPointer = value;
    else if (port == 0x30e) {
        ram[ramPointer] = value; ram[(unsigned short)(ramPointer + 1)] = value >> 8;
        ramPointer += 2;
    } else if (port == 0x306) stopPointer = value;
}
void IODelay(unsigned int us) { (void)us; }
void IOSleep(unsigned int ms) { (void)ms; }
void IOLog(const char *fmt, ...) { (void)fmt; }
void IOPanic(const char *message) { fprintf(stderr, "%s\n", message); abort(); }
void *IOMalloc(unsigned int n) { if (allocFails) return NULL; return malloc(n); }
void IOFree(void *p, unsigned int n) { (void)n; free(p); }
netbuf_t nb_alloc(unsigned int n)
{
    netbuf_t p;
    if (allocFails) return NULL;
    p = calloc(1, sizeof(*p)); p->size = n; return p;
}
void nb_free(netbuf_t p) { frees++; free(p); }
void *nb_map(netbuf_t p) { return p->data; }
unsigned int nb_size(netbuf_t p) { return p->size; }

@implementation IODeviceDescription
- (unsigned int)interrupt { return 5; }
- (unsigned int)numInterrupts { return 1; }
@end
@implementation IOEISADeviceDescription
- (IORange *)portRangeList { static IORange range = {0x300, 16}; return &range; }
- (unsigned int)numPortRanges { return 1; }
@end
@implementation IOEthernet
- initFromDeviceDescription:(IODeviceDescription *)description
{ multicast.next = multicast.prev = &multicast; return self; }
- free { frees++; return [super free]; }
- (const char *)name { return "test"; }
- (id)deviceDescription { return deviceDescription; }
- (void)unregisterDevice {}
- (void)clearTimeout { timeoutValue = 0; }
- (void)setRelativeTimeout:(unsigned int)ms { timeoutValue = ms; }
- (BOOL)isRunning { return running; }
- (void)setRunning:(BOOL)value { running = value; }
- (IOReturn)enableAllInterrupts { return enableResult; }
- (void)disableAllInterrupts {}
- (IONetwork *)attachToNetworkWithAddress:(enet_addr_t)address { return [IONetwork new]; }
- (queue_head_t *)multicastQueue { return &multicast; }
- (BOOL)isUnwantedMulticastPacket:(ether_header_t *)header { return unwanted; }
- (void)reserveDebuggerLock { locks++; }
- (void)releaseDebuggerLock { locks--; }
- (void)performLoopback:(netbuf_t)packet { loopbacks++; }
@end
@implementation IONetwork
- (void)incrementInputErrors { inputErrors++; }
- (void)incrementInputErrorsBy:(unsigned int)n { inputErrors += n; }
- (void)incrementOutputErrors { outputErrors++; }
- (void)incrementOutputPackets { outputPackets++; }
- (void)incrementCollisions { collisions++; }
- (void)incrementCollisionsBy:(unsigned int)n { collisions += n; }
- (void)handleInputPacket:(netbuf_t)packet extra:(void *)extra
{ assert(locks == 0); inputPackets++; nb_free(packet); }
@end
@implementation IONetbufQueue
- initWithMaxCount:(unsigned int)n { used = 0; return self; }
- (void)enqueue:(netbuf_t)packet { assert(used < 32); packets[used++] = packet; }
- (netbuf_t)dequeue
{
    netbuf_t p; unsigned int i;
    if (!used) return NULL;
    p = packets[0]; used--;
    for (i = 0; i < used; i++) packets[i] = packets[i + 1];
    return p;
}
- (unsigned int)count { return used; }
@end
