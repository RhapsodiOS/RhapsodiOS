#ifndef _INTEL82596_PRIVATE_H_
#define _INTEL82596_PRIVATE_H_

#import "Intel82596.h"

@interface Intel82596 (Private)
- (netbuf_t)_recAllocateNetbuf;
- (char)_abortReceiveUnit;
- (char)_init596;
- (char)_initRfdList;
- (char)_initTcbList;
- (void *)_memAlloc:(unsigned int)size;
- (char)_resetAndSelfTest;
- (void)_scheduleReset;
- (char)_startCommandUnit;
- (char)_startReceiveUnit;
- (void)_transmitPacket:(netbuf_t)packet;
- (char)_waitCu:(unsigned int)timeout;
- (char)_waitScb;
- (char)resetAndEnable:(char)enable;
- (void)setIOBase:(unsigned short)base;
- (void)sendChannelAttention;
- (void)sendPortCommand:(int)command with:(unsigned int)value;
- (void)clearIrqLatch;
@end

id _resetFunc(id driver);
netbuf_t getNetBuffer(void *pool);
unsigned int IOIsPhysicallyContiguous(unsigned int address, unsigned int size);
void *IOMallocPage(unsigned int size, void **allocation, unsigned int *allocationSize);
void *IOMallocNonCached(unsigned int size, void **allocation, unsigned int *allocationSize);

#endif
