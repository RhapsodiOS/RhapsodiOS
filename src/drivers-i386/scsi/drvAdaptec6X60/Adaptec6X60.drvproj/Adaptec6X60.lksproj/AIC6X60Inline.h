/*
 * Copyright (c) 1992-1998 NeXT Software, Inc.
 *
 * Adaptec AIC-6X60 SCSI controller inline functions.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 */

#import <driverkit/i386/ioPorts.h>

/*
 * The reference HIM/sequencer issues x86 in/out against the register
 * block in AIC6X60Types.h. There are no aic_* mailbox port helpers.
 * repins* / repouts* are named symbols; their prototypes live in
 * AIC6X60ControllerPrivate.h.
 */
