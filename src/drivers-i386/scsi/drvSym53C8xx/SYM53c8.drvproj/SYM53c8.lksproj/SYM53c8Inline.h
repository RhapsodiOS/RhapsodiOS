/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Inline.h - Host C does not PIO the 53C8xx.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 *
 * Named __text has zero in/out (divergences.md). Chip access is the
 * firmware window at HBA+4 and the CAMcore vtable at HBA+0x100. IDA has
 * no sym_* register accessors; the BusLogic PIO helpers are deleted.
 */

#import "SYM53c8Types.h"
