#ifndef I595_TEST_SUPPORT_H
#define I595_TEST_SUPPORT_H
#import <objc/Object.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>

typedef int IOReturn;
#define IO_R_SUCCESS 0
typedef struct { unsigned int start, size; } IORange;
typedef struct { unsigned char ether_addr_octet[6]; } enet_addr_t;
typedef struct { char data[14]; } ether_header_t;
typedef struct test_packet { unsigned int size; unsigned short data[800]; } *netbuf_t;
typedef struct queue_entry { struct queue_entry *next, *prev; } queue_head_t, queue_chain_t;
typedef struct { enet_addr_t address; queue_chain_t link; int refCount; } enetMulti_t;
#define queue_empty(q) ((q)->next == (q))
#define queue_iterate(q,e,t,f) for ((e)=(t)(q)->next; (void *)(e)!=(void *)(q); (e)=(t)(e)->f.next)

@interface IODeviceDescription : Object
- (unsigned int)interrupt;
- (unsigned int)numInterrupts;
@end
@interface IOEISADeviceDescription : IODeviceDescription
- (IORange *)portRangeList;
- (unsigned int)numPortRanges;
@end
@interface IOPCMCIADeviceDescription : IOEISADeviceDescription
- (unsigned int)numTuples;
- (id *)tupleList;
@end
@interface IOPCMCIATuple : Object
- (unsigned char)code;
- (unsigned int)length;
- (unsigned char *)data;
@end
@interface IONetwork : Object
- (void)incrementInputErrors;
- (void)incrementInputErrorsBy:(unsigned int)n;
- (void)incrementOutputErrors;
- (void)incrementOutputPackets;
- (void)incrementCollisions;
- (void)incrementCollisionsBy:(unsigned int)n;
- (void)handleInputPacket:(netbuf_t)packet extra:(void *)extra;
@end
@interface IONetbufQueue : Object
{
    netbuf_t packets[32];
    unsigned int used;
}
- initWithMaxCount:(unsigned int)n;
- (void)enqueue:(netbuf_t)packet;
- (netbuf_t)dequeue;
- (unsigned int)count;
@end
@interface IOEthernet : Object
{
    BOOL running;
    queue_head_t multicast;
}
- initFromDeviceDescription:(IODeviceDescription *)description;
- (const char *)name;
- (id)deviceDescription;
- (void)unregisterDevice;
- (void)clearTimeout;
- (void)setRelativeTimeout:(unsigned int)ms;
- (BOOL)isRunning;
- (void)setRunning:(BOOL)value;
- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;
- (IONetwork *)attachToNetworkWithAddress:(enet_addr_t)address;
- (queue_head_t *)multicastQueue;
- (BOOL)isUnwantedMulticastPacket:(ether_header_t *)header;
- (void)reserveDebuggerLock;
- (void)releaseDebuggerLock;
- (void)performLoopback:(netbuf_t)packet;
@end

extern unsigned char regs[3][16], ram[65536];
extern unsigned short ramPointer, stopPointer;
extern int bankNumber, frees, allocFails, inputErrors, inputPackets;
extern int outputPackets, outputErrors, collisions, locks, timeoutValue;
extern int enableResult, probeInits, unwanted, loopbacks, readsFromRam;
extern int ioWrites, pnpCount;
extern unsigned char pnpBytes[40];
extern id deviceDescription;
unsigned char inb(unsigned short port);
unsigned short inw(unsigned short port);
void outb(unsigned short port, unsigned char value);
void outw(unsigned short port, unsigned short value);
void IODelay(unsigned int us);
void IOSleep(unsigned int ms);
void IOLog(const char *fmt, ...);
void IOPanic(const char *message);
void *IOMalloc(unsigned int n);
void IOFree(void *p, unsigned int n);
netbuf_t nb_alloc(unsigned int n);
void nb_free(netbuf_t p);
void *nb_map(netbuf_t p);
unsigned int nb_size(netbuf_t p);
void resetHardware(void);
#endif
