/* Run production adapter methods with port, sleep, and interrupt-service traces. */
#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char kind; unsigned int width, port, value; } Event;
static Event events[128];
static unsigned int ports[65536], eventCount, checks, failures;
static I556SCB simulatedScb;
static BOOL receiveOK = YES, transmitOK = YES;
extern int TestCardIRQ(unsigned int base);

static void check(int condition, const char *message)
{
    ++checks;
    if (!condition) { if (failures < 20) fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
static void record(char kind, unsigned int width, unsigned int port, unsigned int value)
{
    if (eventCount >= 128) { fprintf(stderr, "trace overflow\n"); exit(2); }
    events[eventCount].kind = kind;
    events[eventCount].width = width;
    events[eventCount].port = port;
    events[eventCount++].value = value;
}
static void event(unsigned int index, char kind, unsigned int width,
                  unsigned int port, unsigned int value)
{
    check(index < eventCount, "trace event present");
    if (index < eventCount) {
        check(events[index].kind == kind, "trace operation/order");
        check(events[index].width == width, "trace access width");
        check(events[index].port == port, "trace port address");
        check(events[index].value == value, "trace value");
    }
}
static void resetTrace(void)
{
    eventCount = 0;
    memset(ports, 0, sizeof(ports));
    receiveOK = transmitOK = YES;
}
unsigned char inb(unsigned short port)
{ unsigned char value = ports[port]; record('r', 8, port, value); return value; }
unsigned short inw(unsigned short port)
{ unsigned short value = ports[port]; record('r', 16, port, value); return value; }
unsigned long inl(unsigned short port)
{ record('r', 32, port, ports[port]); return ports[port]; }
void outb(unsigned short port, unsigned char value)
{ record('w', 8, port, value); ports[port] = (ports[port] & 0xffffff00U) | value; }
void outw(unsigned short port, unsigned short value)
{ record('w', 16, port, value); ports[port] = (ports[port] & 0xffff0000U) | value; }
void outl(unsigned short port, unsigned long value)
{ record('w', 32, port, value); ports[port] = value; }
void IOSleep(unsigned int ms) { record('S', 0, 0, ms); }
void IOLog(const char *format, ...) { (void)format; }

@implementation IODevice
@end
@implementation IODirectDevice
@end
@implementation IOEthernet
@end

@interface Intel82556 (AdapterTests)
- configureBase:(unsigned short)base status:(unsigned short)status;
- (unsigned char *)stationAddress;
@end
@implementation Intel82556
- configureBase:(unsigned short)base status:(unsigned short)status
{ ioBase = base; scb_p = &simulatedScb; scb_p->status = status; return self; }
- (unsigned char *)stationAddress { return myAddress.ether_addr_octet; }
- (BOOL)acknowledgeInterrupts:(unsigned short)status
{ record('A', 0, 0, status); return YES; }
- (BOOL)receiveInterruptOccurred:(BOOL)restart
{ record('R', 0, 0, restart); return receiveOK; }
- (BOOL)transmitInterruptOccurred
{ record('T', 0, 0, 0); return transmitOK; }
- (IOReturn)enableAllInterrupts
{ record('E', 0, 0, 0); return 0; }
@end

static void testIRQ(void)
{
    static const unsigned int plx[4] = {5, 9, 10, 11};
    static const unsigned int flea[4] = {3, 7, 12, 15};
    unsigned int i;
    for (i = 0; i < 4; ++i) {
        resetTrace(); ports[0x1430] = 0x40; ports[0x1c88] = 0xa0 | (i << 1);
        check(TestCardIRQ(0x1000) == plx[i], "PLX IRQ table");
        check(eventCount == 2, "PLX IRQ read count");
        event(0, 'r', 8, 0x1430, 0x40); event(1, 'r', 8, 0x1c88, 0xa0 | (i << 1));
        resetTrace(); ports[0x1430] = 0x80 | (i << 1);
        check(TestCardIRQ(0x1000) == flea[i], "FLEA IRQ table");
        check(eventCount == 2, "FLEA IRQ rereads configuration");
        event(0, 'r', 8, 0x1430, 0x80 | (i << 1));
        event(1, 'r', 8, 0x1430, 0x80 | (i << 1));
    }
}

static void testPorts(IntelPRO100EISA *eisa, IntelPRO100PCI *pci)
{
    unsigned int i;
    [eisa configureBase:0x1000 status:0]; [pci configureBase:0x1000 status:0];
    for (i = 0; i < 256; ++i) {
        resetTrace(); ports[0x1430] = i;
        [eisa enableAdapterInterrupts];
        check(eventCount == 2, "EISA enable event count");
        event(0, 'r', 8, 0x1430, i); event(1, 'w', 8, 0x1430, i & 0xdf);
        resetTrace(); ports[0x1430] = i;
        [eisa disableAdapterInterrupts];
        event(0, 'r', 8, 0x1430, i); event(1, 'w', 8, 0x1430, i | 0x20);
    }
    resetTrace(); ports[0x1430] = 0xa5; ports[0x1c88] = 0xff;
    [eisa clearIrqLatch]; check(eventCount == 4, "EISA clear latch count");
    event(0, 'r', 8, 0x1430, 0xa5); event(1, 'w', 8, 0x1430, 0xb5);
    event(2, 'r', 8, 0x1c88, 0xff); event(3, 'w', 8, 0x1c88, 0xef);

    resetTrace(); ports[0x1000] = 0xaabb0020U;
    [pci enableAdapterInterrupts]; check(eventCount == 2, "PCI enable count");
    event(0, 'r', 32, 0x1000, 0xaabb0020U); event(1, 'w', 32, 0x1000, 0xaabb0100U);
    resetTrace(); ports[0x1000] = 0xaabb0100U;
    [pci disableAdapterInterrupts]; event(1, 'w', 32, 0x1000, 0xaabb0020U);
    resetTrace(); ports[0x1000] = 0x12345600U;
    [pci clearIrqLatch]; event(1, 'w', 32, 0x1000, 0x12345610U);

    resetTrace(); [eisa sendChannelAttention]; [pci sendChannelAttention];
    check(eventCount == 2, "channel attention event count");
    event(0, 'w', 8, 0x1000, 0); event(1, 'w', 32, 0x1020, 0);
    resetTrace(); [eisa sendPortCommand:0x123 with:0xabcdefefU];
    [pci sendPortCommand:-2 with:0x12345671U];
    event(0, 'w', 32, 0x1008, 0xabcdefe3U); event(1, 'w', 32, 0x1024, 0x1234567eU);
    [eisa configureBase:0 status:0]; resetTrace(); [eisa sendChannelAttention];
    event(0, 'w', 8, 0, 0); check(eventCount == 1, "no invented zero-base guard");
    [pci configureBase:0xfff0 status:0]; resetTrace(); [pci sendChannelAttention];
    event(0, 'w', 32, 0x10, 0);
    [eisa configureBase:0x1000 status:0]; [pci configureBase:0x1000 status:0];

    resetTrace();
    for (i = 0; i < 6; ++i) ports[0x1c90+i] = 0xa0+i;
    [eisa getEthernetAddress]; check(eventCount == 6, "six station bytes");
    for (i = 0; i < 6; ++i) {
        event(i, 'r', 8, 0x1c90+i, 0xa0+i);
        check([eisa stationAddress][i] == 0xa0+i, "station address byte");
    }
}

static void testPLX(IntelPRO100EISA *eisa, IntelPRO100PCI *pci)
{
    resetTrace(); ports[0x1c88] = 0x28; ports[0x1c89] = 0x18;
    ports[0x1c8a] = 2; ports[0x1c8f] = 0x44;
    [eisa initPLXchip]; check(eventCount == 8, "EISA PLX conditional write enabled");
    event(0, 'r', 8, 0x1c88, 0x28); event(1, 'w', 8, 0x1c88, 0xc0);
    event(2, 'r', 8, 0x1c89, 0x18); event(3, 'w', 8, 0x1c89, 5);
    event(4, 'r', 8, 0x1c8a, 2); event(5, 'w', 8, 0x1c8a, 2);
    event(6, 'r', 8, 0x1c8f, 0x44); event(7, 'w', 8, 0x1c8f, 0x80);
    resetTrace(); [eisa initPLXchip]; check(eventCount == 7, "EISA PLX skips status write when bit clear");
    event(5, 'r', 8, 0x1c8f, 0); event(6, 'w', 8, 0x1c8f, 0x80);
    resetTrace(); ports[0x1000] = 0xaabb0100U; ports[0x1004] = 0xccdd1234U;
    [pci initPLXchip]; check(eventCount == 4, "PCI PLX count");
    event(0, 'r', 32, 0x1000, 0xaabb0100U); event(1, 'w', 32, 0x1000, 0xaabb0028U);
    event(2, 'r', 32, 0x1004, 0xccdd1234U); event(3, 'w', 32, 0x1004, 0xccdd12f1U);
}

static void testDelays(IntelPRO100EISA *eisa, IntelPRO100PCI *pci)
{
    resetTrace(); ports[0x1c8f] = 0xa4;
    [eisa resetPLXchip]; check(eventCount == 5, "EISA reset sequence count");
    event(0, 'r', 8, 0x1c8f, 0xa4); event(1, 'w', 8, 0x1c8f, 0xa6);
    event(2, 'S', 0, 0, 50); event(3, 'r', 8, 0x1c8f, 0xa6); event(4, 'w', 8, 0x1c8f, 0xa4);
    resetTrace(); ports[0x1010] = 0xabcd0123U;
    [pci resetPLXchip]; check(eventCount == 5, "PCI reset sequence count");
    event(0, 'r', 32, 0x1010, 0xabcd0123U); event(1, 'w', 32, 0x1010, 0xabcd1123U);
    event(2, 'S', 0, 0, 50); event(3, 'r', 32, 0x1010, 0xabcd1123U); event(4, 'w', 32, 0x1010, 0xabcd0123U);
    resetTrace(); ports[0x1c89] = 0xff;
    [eisa lockDBRT]; check(eventCount == 8, "EISA DBRT sequence count");
    event(0, 'r', 8, 0x1c89, 0xff); event(1, 'S', 0, 0, 10); event(2, 'w', 8, 0x1c89, 0xfb);
    event(3, 'S', 0, 0, 50); event(4, 'r', 8, 0x1c89, 0xfb); event(5, 'S', 0, 0, 10);
    event(6, 'w', 8, 0x1c89, 0xfd); event(7, 'S', 0, 0, 10);
    resetTrace(); ports[0x1004] = 0xabcdef0fU;
    [pci lockDBRT]; check(eventCount == 8, "PCI DBRT sequence count");
    event(0, 'r', 32, 0x1004, 0xabcdef0fU); event(1, 'S', 0, 0, 10); event(2, 'w', 32, 0x1004, 0xabcdef0bU);
    event(3, 'S', 0, 0, 50); event(4, 'r', 32, 0x1004, 0xabcdef0bU); event(5, 'S', 0, 0, 10);
    event(6, 'w', 32, 0x1004, 0xabcdef0dU); event(7, 'S', 0, 0, 10);
}

static void testInterrupts(id adapter, int eisa)
{
    unsigned int nibble, rx, tx, index;
    int completed;
    for (nibble = 0; nibble < 16; ++nibble)
    for (rx = 0; rx < 2; ++rx)
    for (tx = 0; tx < 2; ++tx) {
        resetTrace(); receiveOK = rx; transmitOK = tx;
        ports[0x1430] = 0x1f; ports[0x1c88] = 0xff; ports[0x1000] = 0xaabb0000U;
        [adapter configureBase:0x1000 status:nibble << 12];
        [adapter interruptOccurred];
        index = 0;
        if (eisa) {
            event(index++, 'r', 8, 0x1430, 0x1f);
            event(index++, 'w', 8, 0x1430, 0x3f);
        }
        event(index++, 'A', 0, 0, nibble << 12);
        completed = 1;
        if (nibble & 5) {
            event(index++, 'R', 0, 0, nibble & 1);
            if (!rx) completed = 0;
        }
        if (completed && (nibble & 10)) {
            event(index++, 'T', 0, 0, 0);
            if (!tx) completed = 0;
        }
        if (completed) {
            if (eisa) {
                event(index++, 'r', 8, 0x1430, 0x3f); event(index++, 'w', 8, 0x1430, 0x3f);
                event(index++, 'r', 8, 0x1c88, 0xff); event(index++, 'w', 8, 0x1c88, 0xef);
                event(index++, 'r', 8, 0x1430, 0x3f); event(index++, 'w', 8, 0x1430, 0x1f);
            } else {
                event(index++, 'r', 32, 0x1000, 0xaabb0000U);
                event(index++, 'w', 32, 0x1000, 0xaabb0010U);
                event(index++, 'E', 0, 0, 0);
            }
        }
        check(eventCount == index, "interrupt gating: no extra service or re-enable");
    }
}

int main(void)
{
    IntelPRO100EISA *eisa = [IntelPRO100EISA alloc];
    IntelPRO100PCI *pci = [IntelPRO100PCI alloc];
    testIRQ(); testPorts(eisa, pci); testPLX(eisa, pci); testDelays(eisa, pci);
    testInterrupts(eisa, 1); testInterrupts(pci, 0);
    [eisa free]; [pci free];
    printf("adapter: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
