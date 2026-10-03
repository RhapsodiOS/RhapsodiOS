/* Recovered normal SCSI message-in handler. */
#ifndef A2940_HANDLE_MSGI_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_MSGI_INB(port) inb(port)
#define A2940_MSGI_OUTB(port, value) outb((port), (value))
#else
extern unsigned char a2940_msgi_test_inb(unsigned short port);
extern void a2940_msgi_test_outb(unsigned short port, unsigned char value);
int Ph_Wt4Req(int, short);
int Ph_BadSeq(int, int);
int Ph_TargetAbort(int, int, int);
#define A2940_MSGI_INB(port) a2940_msgi_test_inb((unsigned short)(port))
#define A2940_MSGI_OUTB(port, value) a2940_msgi_test_outb((unsigned short)(port), (unsigned char)(value))
#endif

char Ph_HandleMsgi(int scb_address, int io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	unsigned char status;
	unsigned char message;
	unsigned char transfer_count;
	unsigned int value;
	unsigned int residual;
	if ((A2940_MSGI_INB(io_base + 3) & 0x10) != 0)
		return (char)A2940_MSGI_INB(io_base + 6);
	message = A2940_MSGI_INB(io_base + 18);
	if (message == 7) {
		status = A2940_MSGI_INB(io_base + 58);
		if ((status & 0xa0) != 0) {
			A2940_MSGI_OUTB(io_base + 3, 0xf0);
			A2940_MSGI_INB(io_base + 6);
			return (char)Ph_TargetAbort(host_address, scb_address, io_base);
		}
		return (char)A2940_MSGI_INB(io_base + 6);
	}
	if (message == 35) {
		A2940_MSGI_INB(io_base + 6);
		Ph_Wt4Req(scb_address, (short)io_base);
		transfer_count = A2940_MSGI_INB(io_base + 18);
		if (transfer_count != 0) {
			value = A2940_MSGI_INB(io_base + 8);
			value |= (unsigned int)A2940_MSGI_INB(io_base + 9) << 8;
			value |= (unsigned int)A2940_MSGI_INB(io_base + 10) << 16;
			value += transfer_count;
			A2940_MSGI_OUTB(io_base + 8, (unsigned char)value);
			A2940_MSGI_OUTB(io_base + 9, (unsigned char)(value >> 8));
			A2940_MSGI_OUTB(io_base + 10, (unsigned char)(value >> 16));
			*(unsigned int *)(scb + 28) = (*(unsigned int *)(scb + 28) & 0xf000U) |
				((*(unsigned int *)(scb + 28) + transfer_count) & 0xfffU);
			residual = A2940_MSGI_INB(io_base + 20);
			residual |= (unsigned int)A2940_MSGI_INB(io_base + 21) << 8;
			residual |= (unsigned int)A2940_MSGI_INB(io_base + 22) << 16;
			residual |= (unsigned int)A2940_MSGI_INB(io_base + 23) << 24;
			residual -= transfer_count;
			A2940_MSGI_OUTB(io_base + 136, (unsigned char)residual);
			A2940_MSGI_OUTB(io_base + 137, (unsigned char)(residual >> 8));
			A2940_MSGI_OUTB(io_base + 138, (unsigned char)(residual >> 16));
			A2940_MSGI_OUTB(io_base + 139, (unsigned char)(residual >> 24));
		}
		return (char)A2940_MSGI_INB(io_base + 6);
	}
	A2940_MSGI_OUTB(io_base + 3, 0xf0);
	do {
		A2940_MSGI_INB(io_base + 6);
		status = (unsigned char)Ph_Wt4Req(scb_address, (short)io_base);
	} while ((char)status == (char)-32);
	if ((char)status != (char)-96)
		return (char)Ph_BadSeq(host_address, io_base);
	A2940_MSGI_OUTB(io_base + 3, 0xa0);
	A2940_MSGI_OUTB(io_base + 12, 0x40);
	A2940_MSGI_OUTB(io_base + 6, 7);
	return 7;
}
