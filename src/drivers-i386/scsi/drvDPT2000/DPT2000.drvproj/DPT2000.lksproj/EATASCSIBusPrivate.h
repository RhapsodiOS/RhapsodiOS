/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATASCSIBusPrivate.h - EATASCSIBus(PrivateMethods).
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc (SCSIBus.m category).
 */

#ifndef _EATASCSIBUSPRIVATE_H
#define _EATASCSIBUSPRIVATE_H

#import <driverkit/scsiTypes.h>


@interface EATASCSIBus(PrivateMethods)

- initSCSIBus:deviceDescription channel:(unsigned)channel;
- (sc_status_t)flushCacheForTarget:(unsigned char)target
			       lun:(unsigned char)lun;
- (void)flushAllCache;

@end

#endif /* _EATASCSIBUSPRIVATE_H */
