/* Executes selected production methods; hardware and kernel services are mocked. */
#import "Intel82556.h"
#import <driverkit/generalFuncs.h>
#import <mach/mach_interface.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned int page_size = 8192, page_mask = 8191;
static unsigned int checks, failures, delays, delayTotal, clearAfter;
static unsigned int physCalls, failPhysical, buffersFreed;
static int clearCommand;
static I556SCB *delayScb;
static void check(int ok, const char *message)
{
    ++checks;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); ++failures; }
}
void IODelay(unsigned int us)
{
    ++delays; delayTotal += us;
    if (clearAfter && delays == clearAfter) {
        if (clearCommand) delayScb->command = 0;
        else delayScb->status = 0;
    }
}
void IOSleep(unsigned int ms) { (void)ms; }
void IOScheduleFunc(IOThreadFunc f, void *arg, int seconds)
{ (void)f; (void)arg; (void)seconds; }
void *IOMalloc(int size) { return malloc(size); }
void IOFree(void *memory, int size) { (void)size; free(memory); }
void IOLog(const char *format, ...) { (void)format; }
void IOPanic(const char *message) { fprintf(stderr, "PANIC: %s\n", message); exit(2); }
vm_task_t IOVmTaskSelf(void) { return (vm_task_t)0; }
IOReturn IOPhysicalFromVirtual(vm_task_t task, vm_address_t address, vm_offset_t *physical)
{
    (void)task;
    if (++physCalls == failPhysical) return -1;
    *physical = address + 0x01000000;
    return 0;
}
typedef struct { char *data; unsigned int size; } CoreBuffer;
netbuf_t nb_alloc(unsigned int size)
{
    CoreBuffer *b = malloc(sizeof(*b));
    b->data = malloc(size); b->size = size;
    return (netbuf_t)b;
}
char *nb_map(netbuf_t b) { return ((CoreBuffer *)b)->data; }
unsigned int nb_size(netbuf_t b) { return ((CoreBuffer *)b)->size; }
void nb_free(netbuf_t b)
{
    if (!b) return;
    ++buffersFreed;
    free(((CoreBuffer *)b)->data); free(b);
}
/* Superclasses supply only object allocation/layout and the diagnostic name.
 * No real DriverKit service is linked or used by these selected methods. */
@implementation IODevice
- (const char *)name { return "Intel82556-test"; }
@end
@implementation IODirectDevice
@end
@implementation IOEthernet
@end

@interface I556CoreTest : Intel82556
{
@public
    int complete;
    unsigned short completionStatus;
    unsigned int attentions, restarts;
    unsigned short submitted;
    unsigned char submittedConfig[28];
}
- setup;
- dispose;
- (I556SCB *)scb;
- (I556Command *)command;
- (I556TCB *)tcbs;
- (I556RFD *)rfds;
- (I556TCB *)debugTcb;
- (void *)debugBuffer;
- (I556RFD *)receiveHead;
- (I556RFD *)receiveTail;
- (void)setRate:(int)rate promiscuous:(BOOL)promiscuous;
- (void)resetSimulation;
@end

@implementation I556CoreTest
- setup
{
    scb_p = calloc(1, sizeof(*scb_p));
    cbl_p = calloc(1, sizeof(*cbl_p));
    cbl_paddr = 0x12340000;
    tcbList_p = calloc(16, sizeof(*tcbList_p));
    rfdList_p = calloc(64, sizeof(*rfdList_p));
    KDB_tcb_p = calloc(1, sizeof(*KDB_tcb_p));
    KDB_tcb_p->physical = 0x22340000;
    KDB_tcb_p->tbd[0].physical = 0x22340020;
    KDB_buf_p = calloc(1, 1514);
    KDB_buf_paddr = 0x32340000;
    [self resetSimulation];
    return self;
}
- dispose
{
    int i;
    for (i = 0; i < 64; ++i) nb_free(rfdList_p[i].netbuf);
    for (i = 0; i < 16; ++i) nb_free(tcbList_p[i].netbuf);
    free(scb_p); free(cbl_p); free(tcbList_p); free(rfdList_p);
    free(KDB_tcb_p); free(KDB_buf_p);
    return [super free];
}
- (I556SCB *)scb { return scb_p; }
- (I556Command *)command { return cbl_p; }
- (I556TCB *)tcbs { return tcbList_p; }
- (I556RFD *)rfds { return rfdList_p; }
- (I556TCB *)debugTcb { return KDB_tcb_p; }
- (void *)debugBuffer { return KDB_buf_p; }
- (I556RFD *)receiveHead { return headRfd; }
- (I556RFD *)receiveTail { return tailRfd; }
- (void)setRate:(int)rate promiscuous:(BOOL)promiscuous
{ dataRate = rate; promiscuousEnabled = promiscuous; }
- (void)resetSimulation
{
    complete = 1; completionStatus = 0xa000;
    attentions = restarts = 0; submitted = 0;
    delays = delayTotal = clearAfter = 0;
    physCalls = failPhysical = 0;
    delayScb = scb_p; scb_p->status = scb_p->command = 0;
}
- (void)sendChannelAttention
{
    ++attentions; submitted = scb_p->command;
    if (complete) {
        if (scb_p->command == 0x100 && scb_p->commandList == cbl_paddr) {
            memcpy(submittedConfig, cbl_p, sizeof(submittedConfig));
            cbl_p->header.status = completionStatus;
        }
        scb_p->command = 0;
    }
}
- (netbuf_t)_recAllocateNetbuf { return nb_alloc(1518); }
- (BOOL)_abortReceiveUnit { ++restarts; return YES; }
- (BOOL)_startReceiveUnit { scb_p->status = 0x40; return YES; }
@end

static void test_waits(I556CoreTest *d)
{
    [d resetSimulation];
    check([d _waitScb] && delays == 0, "SCB ready returns without delay");
    [d scb]->command = 1; clearAfter = 3; clearCommand = 1;
    check([d _waitScb] && delays == 3, "SCB polls until hardware clears command");
    [d resetSimulation]; [d scb]->command = 1;
    check(![d _waitScb] && delays == 65535 && delayTotal == 65535,
          "SCB timeout performs exactly 65535 one-microsecond polls");
    [d resetSimulation]; [d scb]->status = 0x300;
    check([d _waitCu:1] && delays == 0, "CU state three is inactive");
    [d scb]->status = 0x200; clearAfter = 4; clearCommand = 0;
    check([d _waitCu:1] && delays == 4, "CU state two waits for inactive state");
    [d resetSimulation]; [d scb]->status = 0x200;
    check(![d _waitCu:2] && delays == 2000 && delayTotal == 2000,
          "CU millisecond timeout converts to microsecond polling bound");
    [d resetSimulation];
    check(![d _waitCu:0] && delays == 0, "zero CU timeout follows reference failure path");
}
static void test_acknowledgement(I556CoreTest *d)
{
    [d resetSimulation];
    check(![d acknowledgeInterrupts:0x0fff] && d->attentions == 0,
          "acknowledgement ignores noninterrupt status bits");
    check([d acknowledgeInterrupts:0xa123] && d->submitted == 0xa000 && delays == 1,
          "ack submits only high four status bits then waits for clear");
    [d resetSimulation]; d->complete = 0;
    check(![d acknowledgeInterrupts:0xf000] && delays == 2000,
          "acknowledgement has bounded hardware-clear timeout");
    [d resetSimulation]; [d scb]->command = 1;
    check(![d acknowledgeInterrupts:0xf000] && d->attentions == 0 && delays == 65535,
          "busy SCB prevents acknowledgement submission");
}
static void test_configuration(I556CoreTest *d)
{
    static const unsigned char expected[28] = {
        0,0,2,0x80, 0xff,0xff,0xff,0xff,
        0x14,0xc8,0x20,0x0e,3,0x80,0x2e,0,
        0x60,0,2,0x89,0,0x40,0xf7,0,0x3f,5,0x3a,0
    };
    [d resetSimulation]; [d setRate:1 promiscuous:YES];
    memset([d command], 0xff, sizeof(I556Command));
    check([d config] && d->submitted == 0x100 && [d scb]->commandList == 0x12340000,
          "configuration submits command-list physical address and CU start");
    check(memcmp(d->submittedConfig, expected, sizeof(expected)) == 0,
          "configuration bytes match reference for 100 Mbps promiscuous mode");
    [d resetSimulation]; [d setRate:0 promiscuous:NO];
    check([d config] && d->submittedConfig[12] == 2 && d->submittedConfig[19] == 0x88,
          "configuration encodes 10 Mbps and nonpromiscuous mode");
    [d resetSimulation]; d->completionStatus = 0x8000;
    check(![d config], "completed unsuccessful configuration returns false");
    [d resetSimulation]; d->complete = 0;
    check(![d config] && delays == 2000 && delayTotal == 2000000,
          "configuration completion timeout is two seconds");
}
static void test_rings(I556CoreTest *d)
{
    int i, valid;
    unsigned int freed;
    I556TCB *t;
    I556RFD *r;
    [d resetSimulation]; t = [d tcbs];
    t[5].netbuf = nb_alloc(64); freed = buffersFreed;
    check([d _initTcbList] && buffersFreed == freed + 1,
          "TCB reset releases outstanding packet ownership");
    valid = 1;
    for (i = 0; i < 16; ++i) {
        if (t[i].next != (i == 15 ? 0 : &t[i+1]) ||
            t[i].physical != (unsigned int)&t[i] + 0x01000000 ||
            t[i].tbd[0].physical != (unsigned int)&t[i].tbd[0] + 0x01000000 ||
            t[i].tbd[1].physical != (unsigned int)&t[i].tbd[1] + 0x01000000)
            valid = 0;
    }
    check(valid, "sixteen TCBs and both TBDs have correct links and physical addresses");
    [d resetSimulation]; failPhysical = 2;
    check(![d _initTcbList] && physCalls == 2,
          "TBD address translation failure aborts initialization");
    [d resetSimulation];
    check([d _initRfdList], "receive descriptor initialization succeeds");
    r = [d rfds]; valid = 1;
    for (i = 0; i < 64; ++i) {
        I556RFD *next = &r[(i + 1) % 64];
        if (r[i].next != next || r[i].rbd.next != &next->rbd ||
            r[i].link != next->physical || r[i].rbd.link != next->rbd.physical ||
            r[i].rbdAddress != (i == 0 ? r[0].rbd.physical : ~0U) ||
            r[i].command != (i == 63 ? 0x8008 : 8) ||
            r[i].rbd.size != 1518 || r[i].rbd.end != (i == 63) ||
            r[i].rbd.buffer != (unsigned int)nb_map(r[i].netbuf) + 0x01000000)
            valid = 0;
    }
    check(valid && [d receiveHead] == r && [d receiveTail] == r + 63,
          "sixty-four RFD/RBD entries form a receive ring with one end marker");
    freed = buffersFreed;
    check([d _initRfdList] && buffersFreed == freed + 64,
          "receive ring reset releases all old netbufs before replacing them");
}
static void test_debugger(I556CoreTest *d)
{
    unsigned char input[1600], output[1600];
    unsigned int length, i;
    I556RFD *r;
    I556TCB *t;
    for (i = 0; i < sizeof(input); ++i) input[i] = (unsigned char)i;
    [d resetSimulation];
    [d sendPacket:input length:10]; t = [d debugTcb];
    check(t->command == 0x800c && t->tbd[0].count == 0x8040 &&
          t->tbdAddress == 0x22340020 && t->tbd[0].buffer == 0x32340000 &&
          [d scb]->commandList == 0x22340000,
          "debugger transmit clamps short frame to 64 and submits dedicated descriptors");
    check(memcmp([d debugBuffer], input, 64) == 0,
          "debugger preserves original minimum-length copy behavior");
    [d resetSimulation]; [d sendPacket:input length:1600];
    check(t->tbd[0].count == (0x8000 | 1514) &&
          memcmp([d debugBuffer], input, 1514) == 0,
          "debugger transmit caps payload copy at 1514 bytes");
    [d resetSimulation]; [d scb]->status = 0x40; r = [d receiveHead];
    r->status = 0xa000; r->rbd.status = 0x8044;
    memcpy(nb_map(r->netbuf), input, 68);
    memset(output, 0xff, sizeof(output)); length = 999;
    [d receivePacket:output length:&length timeout:1];
    check(length == 68 && memcmp(output, input, 68) == 0 && output[68] == 0xff,
          "debugger receive copies reported length including CRC without overwriting next byte");
    check([d receiveHead] == r + 1 && [d receiveTail] == r && r->status == 0 &&
          r->rbd.status == 0 && r->rbd.end == 1 && r->rbdAddress == ~0U,
          "debugger receive returns descriptor to tail and clears completion state");
    [d resetSimulation]; [d scb]->status = 0x40; length = 999;
    [d receivePacket:output length:&length timeout:1];
    check(length == 0 && delays == 20 && delayTotal == 1000 && d->restarts == 0,
          "ready receive unit times out after twenty 50-microsecond polls without restart");
}
int main(void)
{
    I556CoreTest *d = [[I556CoreTest alloc] setup];
    test_waits(d); test_acknowledgement(d); test_configuration(d); test_rings(d);
    test_debugger(d); [d dispose];
    if (failures) { fprintf(stderr, "core: %u/%u checks failed\n", failures, checks); return 1; }
    printf("core: %u reference-derived behavioral checks passed\n", checks);
    return 0;
}
