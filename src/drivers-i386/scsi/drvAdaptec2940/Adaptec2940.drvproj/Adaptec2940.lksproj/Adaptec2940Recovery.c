/* SCSI reset/recovery routines reconstructed from the IDA reference. */
#ifndef A2940_RECOVERY_STANDALONE
#include "Adaptec2940HIM.h"
#else
int Ph_UnPause(int);
unsigned char Ph_Delay(int, int);
unsigned char Ph_WriteHcntrl(short, unsigned char, ...);
void *Ph_PostNonActiveScb(int, int);
int Ph_SetHaData(int);
int Ph_ScbPrepare(int, int *);
int Ph_ReadIntstat(short);
int Ph_AsynchEvent(int, int, int);
int Ph_Wt4Req(int, short);
char Ph_CheckSyncNego(int);
char Ph_ResetChannel(int);
char Ph_InsertBookmark(int);
int Ph_RemoveBookmark(int);
#endif

#if defined(A2940_TEST) || defined(A2940_RECOVERY_STANDALONE)
extern void a2940_test_outb(unsigned short port, unsigned char value);
extern unsigned char a2940_test_inb(unsigned short port);
#define A2940_RECOVERY_OUTB(port, value) a2940_test_outb((unsigned short)(port), (unsigned char)(value))
#define A2940_RECOVERY_INB(port) a2940_test_inb((unsigned short)(port))
#else
#include <driverkit/i386/ioPorts.h>
#define A2940_RECOVERY_OUTB(port, value) outb((port), (value))
#define A2940_RECOVERY_INB(port) inb((port))
#endif

unsigned char Ph_ResetSCSI(int io_base)
{
	unsigned char saved176 = A2940_RECOVERY_INB(io_base + 176);
	unsigned char saved177 = A2940_RECOVERY_INB(io_base + 177);
	unsigned char saved16 = A2940_RECOVERY_INB(io_base + 16);
	unsigned char hcntrl;
	unsigned char scsi_signal;
	unsigned char value;

	A2940_RECOVERY_OUTB(io_base + 176, 0xff);
	A2940_RECOVERY_OUTB(io_base + 177, 0);
	A2940_RECOVERY_OUTB(io_base + 98, 4);
	A2940_RECOVERY_OUTB(io_base + 99, 0);
	A2940_RECOVERY_OUTB(io_base + 16, 0);
	A2940_RECOVERY_OUTB(io_base + 17, 0);
	A2940_RECOVERY_OUTB(io_base + 146, 0x0f);
	value = A2940_RECOVERY_INB(io_base);
	A2940_RECOVERY_OUTB(io_base, (unsigned char)((value & 0x32) | 1));
	Ph_UnPause(io_base);
	do {
		hcntrl = A2940_RECOVERY_INB(io_base + 135);
	} while ((hcntrl & 4) == 0);
	value = A2940_RECOVERY_INB(io_base);
	A2940_RECOVERY_OUTB(io_base, value & 0xfe);
	A2940_RECOVERY_OUTB(io_base + 12, 0x20);
	scsi_signal = A2940_RECOVERY_INB(io_base + 12);
	A2940_RECOVERY_OUTB(io_base + 11, 0xff);
	A2940_RECOVERY_OUTB(io_base + 12, scsi_signal & 0xef);
	A2940_RECOVERY_OUTB(io_base + 146, 5);
	Ph_Delay(io_base, 4000);
	A2940_RECOVERY_OUTB(io_base + 16, saved16);
	A2940_RECOVERY_OUTB(io_base + 17, 0xa4);
	A2940_RECOVERY_OUTB(io_base + 176, saved176);
	A2940_RECOVERY_OUTB(io_base + 177, saved177);
	return saved177;
}

unsigned char Ph_AbortChannel(int host_address, char status)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	unsigned int *queue = *(unsigned int **)(host + 52);
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned int saved_head;
	unsigned int saved_tail;
	unsigned int scb;
	unsigned char hcntrl = A2940_RECOVERY_INB(io_base + 135);

	Ph_WriteHcntrl((short)io_base, hcntrl | 4);
	while ((A2940_RECOVERY_INB(io_base + 135) & 4) == 0)
		;
	while (queue[0] != 0xffffffffU &&
	       *(unsigned char *)(unsigned long)(queue[0] + 8) != 0xff) {
		unsigned char *entry = (unsigned char *)(unsigned long)queue[0];
		entry[43] = (unsigned char)status;
		entry[11] = 4;
		Ph_PostNonActiveScb(host_address, (int)queue[0]);
	}
	saved_head = queue[0];
	saved_tail = queue[1];
	Ph_SetHaData(host_address);
	queue[0] = saved_head;
	queue[1] = saved_tail;
	for (scb = queue[0]; scb != 0xffffffffU; scb = *(unsigned int *)(unsigned long)scb) {
		if (*(unsigned char *)(unsigned long)(scb + 8) != 0xff)
			Ph_ScbPrepare(host_address, (int *)(unsigned long)scb);
	}
	return Ph_WriteHcntrl((short)io_base, hcntrl);
}

char Ph_BadSeq(int host_address, int io_base)
{
	unsigned char status;

	Ph_AsynchEvent(1, host_address, 0);
	if ((Ph_ReadIntstat((short)io_base) & 4) == 0 ||
	    (A2940_RECOVERY_INB(io_base + 12) & 8) == 0) {
		Ph_ResetSCSI(io_base);
		Ph_CheckSyncNego(host_address);
		Ph_ResetChannel(host_address);
		Ph_AbortChannel(host_address, 20);
	}
	status = 0;
	A2940_RECOVERY_OUTB(io_base + 98, status);
	A2940_RECOVERY_OUTB(io_base + 99, 0);
	return 0;
}

char Ph_CdbAbort(int scb_address, int io_base)
{
	int host_address = *(int *)(unsigned long)((unsigned int)scb_address + 4);
	unsigned char status = A2940_RECOVERY_INB(io_base + 3);

	if ((status & 0xe0) != 0xe0)
		return Ph_BadSeq(host_address, io_base);
	if (A2940_RECOVERY_INB(io_base + 18) != 3) {
		int request_status;

		A2940_RECOVERY_OUTB(io_base + 3, 0xf0);
		do {
			A2940_RECOVERY_INB(io_base + 6);
			request_status = Ph_Wt4Req(scb_address, (short)io_base);
		} while ((char)request_status == (char)0xe0);
		if ((char)request_status != (char)0xa0)
			return Ph_BadSeq(host_address, io_base);
		A2940_RECOVERY_OUTB(io_base + 3, 0xa0);
		A2940_RECOVERY_OUTB(io_base + 12, 0x40);
		A2940_RECOVERY_OUTB(io_base + 6, 7);
		Ph_Wt4Req(scb_address, (short)io_base);
		A2940_RECOVERY_OUTB(io_base + 98, 3);
	} else {
		A2940_RECOVERY_OUTB(io_base + 3, 0xe0);
		A2940_RECOVERY_INB(io_base + 6);
		A2940_RECOVERY_OUTB(io_base + 98, 2);
	}
	A2940_RECOVERY_OUTB(io_base + 99, 0);
	return 0;
}

char Ph_IntSrst(int host_address)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	int io_base = *(int *)(host + 4);
	unsigned char status;

	while ((A2940_RECOVERY_INB(io_base + 12) & 0x20) != 0)
		A2940_RECOVERY_OUTB(io_base + 12, 0x20);
	Ph_AsynchEvent(0, host_address, 0);
	Ph_InsertBookmark(host_address);
	if ((signed char)host[13] < 0) {
		Ph_CheckSyncNego(host_address);
		Ph_ResetChannel(host_address);
	} else {
		status = A2940_RECOVERY_INB(io_base);
		A2940_RECOVERY_OUTB(io_base, status & 0x33);
		if (A2940_RECOVERY_INB(io_base + 3) != 0) {
			A2940_RECOVERY_OUTB(io_base + 1, 0x12);
			Ph_ResetSCSI(io_base);
		}
		Ph_CheckSyncNego(host_address);
		Ph_ResetChannel(host_address);
		Ph_AbortChannel(host_address, 5);
	}
	Ph_RemoveBookmark(host_address);
	A2940_RECOVERY_OUTB(io_base + 98, 0);
	A2940_RECOVERY_OUTB(io_base + 99, 0);
	return 0;
}

unsigned char Ph_HaHardReset(int host_address)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	unsigned char *ha = *(unsigned char **)(host + 52);
	int io_base = *(int *)(host + 4);
	unsigned char hcntrl = A2940_RECOVERY_INB(io_base + 135);
	unsigned char scb_index;
	unsigned char control;
	int scb_address;

	Ph_WriteHcntrl((short)io_base, hcntrl | 4);
	while ((A2940_RECOVERY_INB(io_base + 135) & 4) == 0)
		;
	A2940_RECOVERY_OUTB(io_base + 146, 0x0f);
	Ph_InsertBookmark(host_address);
	scb_index = A2940_RECOVERY_INB(io_base + 60);
	control = A2940_RECOVERY_INB(io_base + 17);
	if ((control & 8) == 0 || scb_index == 0xff)
		scb_address = -1;
	else
		scb_address = (*(int **)(ha + 272))[scb_index];
	Ph_AsynchEvent(3, host_address, scb_address);
	if ((host[12] & 0x40) != 0) {
		Ph_ResetSCSI(io_base);
		Ph_CheckSyncNego(host_address);
	}
	Ph_ResetChannel(host_address);
	Ph_AbortChannel(host_address, 5);
	Ph_RemoveBookmark(host_address);
	A2940_RECOVERY_OUTB(io_base + 98, 0);
	A2940_RECOVERY_OUTB(io_base + 99, 0);
	hcntrl = A2940_RECOVERY_INB(io_base + 135);
	return Ph_WriteHcntrl((short)io_base, hcntrl & 0xfb);
}
