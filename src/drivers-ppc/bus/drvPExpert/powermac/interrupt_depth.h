#ifndef _POWERMAC_INTERRUPT_DEPTH_H_
#define _POWERMAC_INTERRUPT_DEPTH_H_

static int
PEInterruptDepthActive(unsigned int depth)
{
    return depth != 0;
}

static int
PEInterruptDepthEnter(unsigned int *depth)
{
    if (*depth == ~0u)
        return 0;
    (*depth)++;
    return 1;
}

static int
PEInterruptDepthLeave(unsigned int *depth)
{
    if (*depth == 0)
        return 0;
    (*depth)--;
    return 1;
}

static int
PEInterruptDepthEnterException(unsigned int *depth, int exception,
    int externalInterrupt, int decrementer)
{
    if (exception != externalInterrupt && exception != decrementer)
        return 0;
    return PEInterruptDepthEnter(depth);
}

static unsigned int
PEInterruptDepthMark(unsigned int depth)
{
    return depth;
}

static void
PEInterruptDepthRecover(unsigned int *depth, unsigned int mark)
{
    *depth = mark;
}

#endif /* _POWERMAC_INTERRUPT_DEPTH_H_ */
