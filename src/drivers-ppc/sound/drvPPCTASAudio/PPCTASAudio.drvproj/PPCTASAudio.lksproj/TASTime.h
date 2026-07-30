#ifndef TAS_TIME_H
#define TAS_TIME_H

#define TAS_TIME_MASK       0xffffffffUL
#define TAS_TIME_HALF_RANGE 0x80000000UL

unsigned long TASTimeNormalize(unsigned long);
int TASTimeAdd(unsigned long, unsigned long, unsigned long *);
int TASTimeBefore(unsigned long, unsigned long);
int TASTimeAfter(unsigned long, unsigned long);
int TASTimeDue(unsigned long, unsigned long);
int TASTimeRemaining(unsigned long, unsigned long, unsigned long *);

#endif
