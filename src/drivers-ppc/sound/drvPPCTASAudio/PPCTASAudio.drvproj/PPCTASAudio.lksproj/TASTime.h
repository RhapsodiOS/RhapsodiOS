#ifndef TAS_TIME_H
#define TAS_TIME_H

#define TAS_TIME_MASK       0xffffffffUL
#define TAS_TIME_HALF_RANGE 0x80000000UL

/* Deadlines are 32-bit serial numbers.  Equality is due and has zero
 * remaining time.  Exactly half a range is unordered and therefore fails
 * closed: neither Before nor After is true, Due is false, and Remaining
 * fails.  Add accepts only intervals strictly below the half range. */

unsigned long TASTimeNormalize(unsigned long);
int TASTimeAdd(unsigned long, unsigned long, unsigned long *);
int TASTimeBefore(unsigned long, unsigned long);
int TASTimeAfter(unsigned long, unsigned long);
int TASTimeDue(unsigned long, unsigned long);
int TASTimeRemaining(unsigned long, unsigned long, unsigned long *);

#endif
