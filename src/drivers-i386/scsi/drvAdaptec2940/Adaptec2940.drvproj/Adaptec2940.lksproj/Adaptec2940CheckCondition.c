/* Recovered SCSI CHECK CONDITION interrupt response. */
#ifndef A2940_CHECK_CONDITION_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_CC_INB(port) inb(port)
#define A2940_CC_OUTB(port, value) outb((port), (value))
#else
extern unsigned char a2940_cc_test_inb(unsigned short port);
extern void a2940_cc_test_outb(unsigned short port, unsigned char value);
#define A2940_CC_INB(port) a2940_cc_test_inb((unsigned short)(port))
#define A2940_CC_OUTB(port, value) a2940_cc_test_outb((unsigned short)(port), (unsigned char)(value))
void Ph_TerminateCommand(int, char);
#endif

char Ph_CheckCondition(int scb_address, short io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	int *ha = *(int **)(host + 52);
	unsigned char scsi_status;
	unsigned char target_status;
	unsigned char value;
	unsigned short port;

	if (scb[11] == 8) {
		scb[43] = 27;
		scsi_status = 0;
	} else {
		scsi_status = A2940_CC_INB(io_base + 58);
		scb[24] = scsi_status;
	}
	target_status = A2940_CC_INB(io_base + 60);
	if (scsi_status == 2 && (scb[10] & 0x80) != 0) {
		scb[10] &= (unsigned char)~2;
		((void (__stdcall *)(int, unsigned char))ha[118])(scb_address, target_status);
	} else {
		((void (__stdcall *)(int, unsigned char))ha[117])(host_address, target_status);
		Ph_TerminateCommand(scb_address, (char)target_status);
	}
	if (scsi_status == 2) {
		port = (unsigned short)(io_base + (scb[12] >> 4) + 32);
		if ((host[14] & 1) != 0) {
			A2940_CC_OUTB(port, 0);
		} else if ((host[(scb[12] >> 4) + 32] & 0x81) != 0) {
			A2940_CC_OUTB(port, 0x8f);
		}
	}
	value = A2940_CC_INB(io_base + 1);
	A2940_CC_OUTB(io_base + 1, (unsigned char)(value | 2));
	value = A2940_CC_INB(io_base + 17);
	A2940_CC_OUTB(io_base + 17, (unsigned char)(value & 0xf7));
	(void)A2940_CC_INB(io_base + 6);
	A2940_CC_OUTB(io_base + 98, 0);
	A2940_CC_OUTB(io_base + 99, 0);
	return 0;
}
