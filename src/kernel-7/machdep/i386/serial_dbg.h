/*
 * serial_dbg.h -- polled 8250/16550 debug console for i386.
 *
 * Output only.  Safe with paging disabled, in interrupt context, and during
 * panic: no locks, no allocation, no interrupts, and a bounded spin so a
 * missing UART cannot wedge the kernel.
 */

#ifndef _MACHDEP_I386_SERIAL_DBG_
#define _MACHDEP_I386_SERIAL_DBG_

extern int	serial_dbg_port;	/* 0 disables; default 0x2f8 (COM2) */

void	serial_dbg_init(void);
void	serial_dbg_putc(char c);
void	serial_dbg_puts(const char *s);

#endif /* _MACHDEP_I386_SERIAL_DBG_ */
