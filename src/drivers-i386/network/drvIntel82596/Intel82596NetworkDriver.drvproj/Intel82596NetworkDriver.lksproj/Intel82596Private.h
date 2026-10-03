#ifndef _INTEL82596_PRIVATE_H_
#define _INTEL82596_PRIVATE_H_

#import "Intel82596.h"

@interface Intel82596 (Private)
- (netbuf_t)_recAllocateNetbuf;
- (BOOL)_abortReceiveUnit;
- (BOOL)_init596;
- (BOOL)_initRfdList;
- (BOOL)_initTcbList;
- (void *)_memAlloc:(unsigned int)size;
- (BOOL)_resetAndSelfTest;
- (void)_scheduleReset;
- (BOOL)_startCommandUnit;
- (BOOL)_startReceiveUnit;
- (void)_transmitPacket:(netbuf_t)packet;
- (BOOL)_waitCu:(unsigned int)timeout;
- (BOOL)_waitScb;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)setIOBase:(unsigned short)base;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)command with:(unsigned int)value;
- (void)clearIrqLatch;
@end

void _resetFunc(id driver);
netbuf_t getNetBuffer(void *pool);
unsigned int IOIsPhysicallyContiguous(unsigned int address, unsigned int size);
void *IOMallocPage(unsigned int size, void **allocation, unsigned int *allocationSize);
void *IOMallocNonCached(unsigned int size, void **allocation, unsigned int *allocationSize);

#endif
