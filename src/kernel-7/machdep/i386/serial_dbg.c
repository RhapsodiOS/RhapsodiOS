/*
 * serial_dbg.c -- polled 8250/16550 debug console for i386.
 *
 * The kernel console on i386 is VGA only, and kprintf() was a no-op, so
 * early-boot, driver and panic output could not be captured.  This drives a
 * UART directly with programmed I/O.
 *
 * Default port is COM2 (0x2f8); COM1 belongs to drvISASerialPort.  Override
 * with the "serial=" boot argument, e.g. "serial=0x3f8" or "serial=0".
 */

#import <machdep/i386/serial_dbg.h>
#import <machdep/i386/io_inline.h>

int	serial_dbg_port = 0x2f8;

/* 8250 register offsets */
#define	UART_DATA	0	/* data (DLAB=0) */
#define	UART_IER	1	/* interrupt enable */
#define	UART_DLL	0	/* divisor low  (DLAB=1) */
#define	UART_DLM	1	/* divisor high (DLAB=1) */
#define	UART_FCR	2	/* FIFO control */
#define	UART_LCR	3	/* line control */
#define	UART_MCR	4	/* modem control */
#define	UART_LSR	5	/* line status */

#define	LCR_DLAB	0x80
#define	LCR_8N1		0x03
#define	FCR_ENABLE	0x07	/* enable + clear both FIFOs */
#define	MCR_DTR_RTS	0x03
#define	LSR_THRE	0x20	/* transmit holding register empty */

#define	DIVISOR_115200	1	/* 115200 baud from a 1.8432 MHz clock */

/*
 * Bounded so a missing or wedged UART costs a dropped character rather than a
 * hung kernel.  Sized to be comfortably longer than one character time at
 * 115200 baud even on a slow machine.
 */
#define	TX_SPIN_LIMIT	100000

void
serial_dbg_init(void)
{
	int port = serial_dbg_port;

	if (port == 0)
		return;

	outb(port + UART_IER, 0x00);			/* no interrupts */
	outb(port + UART_LCR, LCR_DLAB);
	outb(port + UART_DLL, DIVISOR_115200);
	outb(port + UART_DLM, 0x00);
	outb(port + UART_LCR, LCR_8N1);			/* 8N1, DLAB off */
	outb(port + UART_FCR, FCR_ENABLE);
	outb(port + UART_MCR, MCR_DTR_RTS);
}

void
serial_dbg_putc(char c)
{
	int port = serial_dbg_port;
	int spin;

	if (port == 0)
		return;

	if (c == '\n')
		serial_dbg_putc('\r');

	for (spin = TX_SPIN_LIMIT; spin > 0; spin--) {
		if (inb(port + UART_LSR) & LSR_THRE) {
			outb(port + UART_DATA, c);
			return;
		}
	}
	/* Dropped: better than deadlocking the kernel. */
}

void
serial_dbg_puts(const char *s)
{
	while (*s)
		serial_dbg_putc(*s++);
}
