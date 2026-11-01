#ifndef _HIM6X60_H_
#define _HIM6X60_H_

#import "AIC6X60Types.h"

/*
 * Public HIM entry points. Argument counts and widths are from IDA
 * of _HIM6X60Initialize / _HIM6X60ISR / _HIM6X60QueueSCB /
 * _HIM6X60AbortSCB (ebp+arg_0 / arg_4 / arg_8).
 */

int HIM6X60Initialize(struct _HACB *hacb);
int HIM6X60ISR(struct _HACB *hacb);
int HIM6X60QueueSCB(struct _HACB *hacb, struct _SCB *scb);
int HIM6X60AbortSCB(struct _HACB *hacb, struct _SCB *scb, struct _SCB *targetScb);

#endif
