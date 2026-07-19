/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SMC Elite16 Ultra Private definitions.
 *
 * HISTORY
 *
 * Mar 1998
 *	Created.
 */

#import "SMCElite16Ultra.h"

@interface SMCElite16Ultra(Private)

- (SMCUltra_len_t)_memAvail;
- (SMCUltra_off_t)_memRegion:(SMCUltra_len_t)length;
- (SMCUltra_off_t)_memAlloc:(SMCUltra_len_t)length;
- (void)_initializeHardware;
- (void)_receiveInitialize;
- (void)_transmitInitialize;
- (void)_initializeSoftware;
- (void)_receivePacket;
- (void)_transmitPacket:(netbuf_t)pkt;
- (void)_transmitCompleted;
- (void)_handleError;

@end
