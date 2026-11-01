/*
 * DECchip2104xInline.h
 * Inline helper functions for DEC 21040/21041 driver
 */

#ifndef _DECCHIP2104XINLINE_H
#define _DECCHIP2104XINLINE_H

#include <driverkit/generalFuncs.h>
#include <driverkit/kernelDriver.h>

/* Inline function to read a CSR register */
static inline unsigned int
DECchip_ReadCSR(volatile void *ioBase, unsigned int offset)
{
    return *((volatile unsigned int *)((unsigned char *)ioBase + offset));
}

/* Inline function to write a CSR register */
static inline void
DECchip_WriteCSR(volatile void *ioBase, unsigned int offset, unsigned int value)
{
    *((volatile unsigned int *)((unsigned char *)ioBase + offset)) = value;
}

/* Inline function to flush write buffer */
static inline void
DECchip_FlushWriteBuffer(volatile void *ioBase, unsigned int offset)
{
    (void)DECchip_ReadCSR(ioBase, offset);
}

#endif /* _DECCHIP2104XINLINE_H */
