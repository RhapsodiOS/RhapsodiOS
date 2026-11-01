/*
 * The operation record queued on IOFloppyDisk's operation thread.
 *
 * Forty bytes, allocated with IOMalloc(0x28).  The layout is fixed by the
 * existing code, which indexed it as operation[0] through operation[9];
 * see reconstruction/operation-record.md for the evidence behind each name.
 *
 * link occupies words 8 and 9, in that order, which is exactly
 * queue_chain_t's { next, prev } -- so the Mach queue macros operate on
 * this record directly.
 */

#ifndef _FLOPPYOPERATION_H_
#define _FLOPPYOPERATION_H_

#import <kernserv/queue.h>
#import <objc/objc.h>

typedef struct floppyOperation {
	unsigned int	type;			/* 1 = write cylinder, 4 = abort */
	unsigned int	cylinder;		/* queue sort key */
	unsigned int	flag2;			/* 0 or 1 */
	id		lock3;
	id		completionLock;		/* NXConditionLock */
	unsigned int	capacity;
	unsigned int	result;
	id		lock7;
	queue_chain_t	link;			/* words 8 and 9: next, prev */
} floppyOperation_t;

#endif /* _FLOPPYOPERATION_H_ */
