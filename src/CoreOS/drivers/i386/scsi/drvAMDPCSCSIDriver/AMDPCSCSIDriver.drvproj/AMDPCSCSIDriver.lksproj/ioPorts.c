/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * Primitives for IO port access.
 *
 * HISTORY
 *
 * 30Mar94 Doug Mitchell
 *	Custom version for debugging - real functions, not static __inline__.
 * 16Feb93 David E. Bohman at NeXT
 *	Created.
 */

#import "ioPorts.h"

#if	USE_COMPILED_IO

#import <driverkit/i386/driverTypes.h>

unsigned char
inb(
    IOEISAPortAddress	port
)
{
    unsigned char	data;
    
    asm volatile(
    	"inb %1,%0"
	
	: "=a" (data)
	: "d" (port));
	
    return (data);
}
 
unsigned short
inw(
    IOEISAPortAddress	port
)
{
    unsigned short	data;
    
    asm volatile(
    	"inw %1,%0"
	
	: "=a" (data)
	: "d" (port));
	
    return (data);
}

unsigned long
inl(
    IOEISAPortAddress	port
)
{
    unsigned long	data;
    
    asm volatile(
    	"inl %1,%0"
	
	: "=a" (data)
	: "d" (port));
	
    return (data);
}

void
outb(
    IOEISAPortAddress	port,
    unsigned char	data
)
{
    static int		xxx;

    asm volatile(
    	"outb %2,%1; lock; incl %0"
	
	: "=m" (xxx)
	: "d" (port), "a" (data), "0" (xxx)
	: "cc");
}

void
outw(
    IOEISAPortAddress	port,
    unsigned short	data
)
{
    static int		xxx;

    asm volatile(
    	"outw %2,%1; lock; incl %0"
	
	: "=m" (xxx)
	: "d" (port), "a" (data), "0" (xxx)
	: "cc");
}

void
outl(
    IOEISAPortAddress	port,
    unsigned long	data
)
{
    static int		xxx;

    asm volatile(
    	"outl %2,%1; lock; incl %0"
	
	: "=m" (xxx)
	: "d" (port), "a" (data), "0" (xxx)
	: "cc");
}

#else	USE_COMPILED_IO

/* this file is a nop */

#endif	USE_COMPILED_IO

