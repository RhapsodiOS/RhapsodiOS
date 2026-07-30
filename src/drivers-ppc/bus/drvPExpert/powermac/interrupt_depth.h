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

#endif /* _POWERMAC_INTERRUPT_DEPTH_H_ */
