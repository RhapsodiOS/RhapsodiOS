/*
 * Allow normal functions for i/o ops for debugging.
 */
 
#define	USE_COMPILED_IO		DEBUG

#if	USE_COMPILED_IO

#define inb	_inb
#define inw	_inw
#define inl	_inl
#define outb	_outb
#define outw	_outw
#define outl	_outl

extern unsigned char  _inb(unsigned short port);
extern unsigned short _inw(unsigned short port);
extern unsigned long  _inl(unsigned short port);
extern void _outb(unsigned short port, unsigned char data);
extern void _outs(unsigned short port, unsigned short data);
extern void _outl(unsigned short port, unsigned long data);


/*
 * Use ioPorts.c.
 */

#else	USE_COMPILED_IO

#import <driverkit/i386/ioPorts.h>

#endif	USE_COMPILED_IO
