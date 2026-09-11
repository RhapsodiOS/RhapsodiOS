#include "TASTime.h"

unsigned long TASTimeNormalize(unsigned long value)
{
    return value & TAS_TIME_MASK;
}

int TASTimeAdd(unsigned long base, unsigned long interval,
    unsigned long *result)
{
    if (result == 0 || interval >= TAS_TIME_HALF_RANGE)
        return 0;
    *result = TASTimeNormalize(TASTimeNormalize(base) + interval);
    return 1;
}

int TASTimeBefore(unsigned long left, unsigned long right)
{
    unsigned long distance;
    distance = TASTimeNormalize(right - left);
    return distance != 0UL && distance < TAS_TIME_HALF_RANGE;
}

int TASTimeAfter(unsigned long left, unsigned long right)
{
    return TASTimeBefore(right, left);
}

int TASTimeDue(unsigned long now, unsigned long deadline)
{
    now = TASTimeNormalize(now);
    deadline = TASTimeNormalize(deadline);
    return now == deadline || TASTimeAfter(now, deadline);
}

int TASTimeRemaining(unsigned long now, unsigned long deadline,
    unsigned long *remaining)
{
    if (remaining == 0)
        return 0;
    now = TASTimeNormalize(now);
    deadline = TASTimeNormalize(deadline);
    if (now == deadline) {
        *remaining = 0UL;
        return 1;
    }
    if (!TASTimeBefore(now, deadline)) {
        *remaining = 0UL;
        return 0;
    }
    *remaining = TASTimeNormalize(deadline - now);
    return 1;
}
