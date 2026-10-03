/* Recovered HIM routines. Each body is kept close to its IDA control flow. */
#ifndef A2940_HIM_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#else
extern void a2940_test_outb(unsigned short port, unsigned char value);
extern unsigned char a2940_test_inb(unsigned short port);
#endif

#if defined(A2940_TEST) || defined(A2940_HIM_STANDALONE)
#define A2940_HIM_OUTB(port, value) a2940_test_outb((unsigned short)(port), (unsigned char)(value))
#define A2940_HIM_INB(port) a2940_test_inb((unsigned short)(port))
#else
#define A2940_HIM_OUTB(port, value) outb((port), (value))
#define A2940_HIM_INB(port) inb((port))
#endif

int Ph_UnPause(int io_base);

#define A2940_CHAIN_HEAD_OFFSET 52
#define A2940_CHAIN_EMPTY_FLAG_OFFSET 13
#define A2940_CHAIN_EMPTY_FLAG 0x80
#define A2940_CHAIN_TARGET_OFFSET 62
#define A2940_CHAIN_LUN_OFFSET 64
#define A2940_CHAIN_TARGET_IN_SCB_OFFSET 268
#define A2940_CHAIN_LUN_IN_SCB_OFFSET 269
#define A2940_CHAIN_END 0xffffffffU
#ifndef A2940_HA_IO_BASE_OFFSET
#define A2940_HA_IO_BASE_OFFSET 4
#endif

static unsigned char *a2940_host_from_address(int address)
{
	return (unsigned char *)(unsigned long)(unsigned int)address;
}

static unsigned int *a2940_chain_from_host(unsigned char *host)
{
	return *(unsigned int **)(host + A2940_CHAIN_HEAD_OFFSET);
}

char Ph_ChainAppendEnd(int host_address, unsigned int *scb)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int *chain = a2940_chain_from_host(host);
	unsigned int *tail;
	unsigned int result = 0;

	*scb = A2940_CHAIN_END;
	if (chain[0] == A2940_CHAIN_END) {
		chain[0] = (unsigned int)scb;
		host[A2940_CHAIN_EMPTY_FLAG_OFFSET] &= (unsigned char)~A2940_CHAIN_EMPTY_FLAG;
		((unsigned char *)chain)[268] = host[A2940_CHAIN_TARGET_OFFSET];
		((unsigned char *)chain)[269] = host[A2940_CHAIN_LUN_OFFSET];
		result = host[A2940_CHAIN_LUN_OFFSET];
	} else {
		tail = (unsigned int *)chain[1];
		*tail = (unsigned int)scb;
		result = (unsigned int)tail;
	}
	tail = scb;
	while (*tail != A2940_CHAIN_END)
		tail = (unsigned int *)*tail;
	chain[1] = (unsigned int)tail;
	return (char)result;
}

int Ph_ChainPrevious(int *chain, int scb_address)
{
	unsigned int *node;
	unsigned int *head = (unsigned int *)chain[0];
	unsigned int target = (unsigned int)scb_address;

	if ((unsigned int)chain[0] == A2940_CHAIN_END)
		return -1;
	node = head;
	while (*node != target) {
		if ((unsigned int *)chain[1] == node || *node == A2940_CHAIN_END) {
			if (*node != target && (unsigned int)chain[0] != target)
				return -1;
			return (int)node;
		}
		node = (unsigned int *)*node;
	}
	return (int)node;
}

int Ph_ChainRemove(int host_address, unsigned int *scb)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int *chain = a2940_chain_from_host(host);
	int previous = -1;

	if ((unsigned int *)chain[0] == scb)
		chain[0] = *scb;
	else {
		previous = Ph_ChainPrevious((int *)chain, (int)scb);
		*(unsigned int *)previous = *scb;
	}
	if (*scb == A2940_CHAIN_END)
		chain[1] = (unsigned int)previous;
	if (chain[0] == A2940_CHAIN_END)
		host[A2940_CHAIN_EMPTY_FLAG_OFFSET] |= A2940_CHAIN_EMPTY_FLAG;
	return previous;
}

void Ph_ChainInsertFront(void)
{
	/* IDA body is a seven-byte prologue/epilogue with no state changes. */
}

char Ph_MemorySet(unsigned char *destination, char value, int length)
{
	short index;
	char result = value;

	for (index = 0; index < length; result = (char)index) {
		*destination++ = (unsigned char)value;
		++index;
	}
	return result;
}

unsigned char Ph_WriteHcntrl(short io_base, unsigned char value, ...)
{
	unsigned char control = value;
	unsigned char observed;

	if ((value & 0x04) == 0) {
		observed = A2940_HIM_INB(io_base + 0x87);
		if ((observed & 0x04) == 0) {
			A2940_HIM_OUTB(io_base + 0x87, observed | 0x04);
			do {
				observed = A2940_HIM_INB(io_base + 0x87);
			} while ((observed & 0x04) == 0);
		}
		observed = A2940_HIM_INB(io_base + 0x91);
		if ((observed & 0x0d) != 0)
			control = value | 0x04;
	}
	A2940_HIM_OUTB(io_base + 0x87, control);
	return control;
}

int Ph_ReadIntstat(short io_base)
{
	unsigned char original = A2940_HIM_INB(io_base + 0x87);
	unsigned char status;
	unsigned char restore;

	if ((original & 0x04) != 0)
		return A2940_HIM_INB(io_base + 0x91);
	A2940_HIM_OUTB(io_base + 0x87, original | 0x04);
	do {
		status = A2940_HIM_INB(io_base + 0x87);
	} while ((status & 0x04) == 0);
	status = A2940_HIM_INB(io_base + 0x91);
	restore = original;
	if ((status & 0x0d) != 0)
		restore |= 0x04;
	A2940_HIM_OUTB(io_base + 0x87, restore);
	return status;
}

int PH_PollInt(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char original = A2940_HIM_INB(io_base + 135);
	unsigned char control;
	unsigned char status;
	A2940_HIM_OUTB(io_base + 135, original | 0x04);
	do {
		control = A2940_HIM_INB(io_base + 135);
	} while ((control & 0x04) == 0);
	status = Ph_ReadIntstat((short)io_base) & 0x0f;
	Ph_WriteHcntrl((short)io_base, original);
	return status;
}

unsigned char Ph_Delay(int io_base, int count)
{
	unsigned char timer_low;
	unsigned char timer_high;
	unsigned char control;
	unsigned char result;
	int iteration;
	if (count != 0) {
		timer_low = A2940_HIM_INB(io_base + 176);
		timer_high = A2940_HIM_INB(io_base + 177);
		for (iteration = 0; iteration != count; ++iteration) {
			A2940_HIM_OUTB(io_base + 176, 0x54);
			A2940_HIM_OUTB(io_base + 177, 0x0b);
			A2940_HIM_OUTB(io_base + 98, 4);
			A2940_HIM_OUTB(io_base + 99, 0);
			Ph_UnPause(io_base);
			do {
				control = A2940_HIM_INB(io_base + 135);
			} while ((control & 0x04) == 0);
			A2940_HIM_OUTB(io_base + 146, 1);
		}
		A2940_HIM_OUTB(io_base + 176, timer_low);
		result = timer_high;
		A2940_HIM_OUTB(io_base + 177, timer_high);
	}
	return result;
}

unsigned char Ph_Pause(int io_base)
{
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	A2940_HIM_OUTB(io_base + 0x87, control | 0x04);
	do {
		control = A2940_HIM_INB(io_base + 0x87);
	} while ((control & 0x04) == 0);
	return control;
}

int Ph_UnPause(int io_base)
{
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	return Ph_WriteHcntrl((short)io_base, control & 0xfb);
}

int PH_EnableInt(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	return Ph_WriteHcntrl((short)io_base, control | 0x02, io_base);
}

int PH_DisableInt(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	return Ph_WriteHcntrl((short)io_base, control & 0xfd, io_base);
}

unsigned char Ph_InBuffer(short port, int destination_address, int length)
{
	unsigned char *destination = (unsigned char *)(unsigned long)(unsigned int)destination_address;
	unsigned char result;
	int index;
	for (index = 0; index < length; ++index) {
		result = A2940_HIM_INB(port + index);
		destination[index] = result;
	}
	return result;
}

unsigned char Ph_OutBuffer(short port, int source_address, int length)
{
	unsigned char *source = (unsigned char *)(unsigned long)(unsigned int)source_address;
	unsigned char result;
	int index;
	for (index = 0; index < length; ++index) {
		result = source[index];
		A2940_HIM_OUTB(port + index, result);
	}
	return result;
}

char Ph_SetNeedNego(unsigned char target, short io_base)
{
	A2940_HIM_OUTB(io_base + target + 32, 0x8f);
	return (char)-113;
}

int Ph_SyncSet(int scb_address)
{
	unsigned char period = *(unsigned char *)((unsigned long)(unsigned int)scb_address + 67);
	if (period == 0x12 || (period >= 0x14 && period <= 0x19))
		return 0;
	if (period <= 0x10 || (period >= 0x1a && period <= 0x1f))
		return 16;
	if (period <= 0x25)
		return 32;
	if (period <= 0x2b)
		return 48;
	if (period <= 0x32)
		return 64;
	if (period <= 0x38)
		return 80;
	if (period <= 0x3e)
		return 96;
	return 112;
}

char Ph_ScbRenego(int host_address, unsigned char target_channel_lun)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char target = target_channel_lun >> 4;
	unsigned char *need_nego = host + target + 32;
	unsigned char value;
	if ((*need_nego & 0x81) != 0)
		return Ph_SetNeedNego(target, (short)io_base);
	value = A2940_HIM_INB(io_base + target + 32);
	if ((value & 0x8f) != 0) {
		if ((value & 0x0f) != 0)
			*need_nego |= 1;
		if ((signed char)value < 0)
			*need_nego |= 0x80;
		return Ph_SetNeedNego(target, (short)io_base);
	}
	A2940_HIM_OUTB(io_base + target + 32, 0);
	return 0;
}

unsigned char Ph_ClearFast20Reg(int host_address, int scb_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char target;
	unsigned char mask;
	unsigned short register_port;
	unsigned char value;
	unsigned char result;
	if (scb[66] == 1) {
		int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
		target = scb[12] >> 4;
		if (target > 7) {
			mask = (unsigned char)(1 << (target - 8));
			register_port = (unsigned short)(io_base + 49);
		} else {
			mask = (unsigned char)(1 << target);
			register_port = (unsigned short)(io_base + 48);
		}
		value = A2940_HIM_INB(register_port);
		A2940_HIM_OUTB(register_port, value & (unsigned char)~mask);
		result = A2940_HIM_INB(io_base + 1) & 0xdf;
		A2940_HIM_OUTB(io_base + 1, result);
	}
	return result;
}

void Ph_LogFast20Map(int host_address, unsigned char *scb)
{
	unsigned char target;
	unsigned char mask;
	unsigned short register_port;
	unsigned char map;
	unsigned char control;
	int io_base;
	if (scb[66] != 1)
		return;
	io_base = *(int *)(a2940_host_from_address(host_address) + A2940_HA_IO_BASE_OFFSET);
	target = scb[12] >> 4;
	if (target > 7) {
		mask = (unsigned char)(1 << (target - 8));
		register_port = (unsigned short)(io_base + 49);
	} else {
		mask = (unsigned char)(1 << target);
		register_port = (unsigned short)(io_base + 48);
	}
	map = A2940_HIM_INB(register_port);
	control = A2940_HIM_INB(io_base + 1);
	if (scb[67] > 0x18) {
		map &= (unsigned char)~mask;
		control &= 0xdf;
	} else {
		map |= mask;
		control |= 0x20;
	}
	A2940_HIM_OUTB(register_port, map);
	A2940_HIM_OUTB(io_base + 1, control);
}

void Ph_Abort(void)
{
}

int Ph_SendTrmMsg(unsigned int unused_host, unsigned int unused_scb)
{
	(void)unused_host;
	(void)unused_scb;
	return 0;
}

int Ph_TrmCmplt(void)
{
	return 0;
}

void Ph_BusReset(void)
{
}

void Ph_HaSoftReset(void)
{
}

void Ph_SoftReset(void)
{
}

char Ph_CheckLength(int scb_address, short io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char phase = A2940_HIM_INB(io_base + 3);
	unsigned char control;
	unsigned int residual;
	unsigned char i;

	if ((phase & 0xe0) != 0xc0) {
		if ((signed char)phase >= 0) {
			A2940_HIM_OUTB(io_base + 3, phase & 0xe0);
			control = A2940_HIM_INB(io_base + 2);
			A2940_HIM_OUTB(io_base + 2, control | 0x80);
			while ((A2940_HIM_INB(io_base + 12) & 0x10) == 0)
				;
			*(unsigned int *)(scb + 28) = 0;
			A2940_HIM_OUTB(io_base + 2, control);
		}
		scb[43] = 18;
		return (char)phase;
	}
	if ((scb[10] & 0x40) == 0 && scb[24] != 2) {
		residual = 0;
		for (i = 0; i <= 3; ++i)
			residual |= (unsigned int)A2940_HIM_INB(io_base + 176 + i) << (8 * i);
		*(unsigned int *)(scb + 28) = residual;
		scb[43] = 18;
	}
	return (char)phase;
}

int Ph_GetScbStatus(int chain_address, int scb_address)
{
	unsigned char *chain = (unsigned char *)(unsigned long)(unsigned int)chain_address;
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char limit;
	if ((scb[13] & 0x20) != 0)
		limit = chain[269];
	else
		limit = chain[268];
	return chain[(unsigned int)scb[12] + 8] > limit ? 32 : 16;
}

unsigned char Ph_SetMgrStat(unsigned char *scb)
{
	unsigned char status;
	scb[11] = 1;
	if (scb[43] != 0)
		scb[11] = 4;
	status = scb[24];
	if (status != 4) {
		if (status <= 4) {
			if (status == 0)
				return status;
			scb[11] = 4;
		} else if (status != 16 && status != 20) {
			scb[11] = 4;
		}
	}
	return status;
}

int Ph_SetScbMark(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	*(unsigned int *)(chain + 372) = *(unsigned int *)(host + 56) + 404;
	*(unsigned int *)(chain + 356) = (unsigned int)host;
	return (int)chain;
}

int Ph_ScbPrepare(int host_address, int *first_scb)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	unsigned char *scb = (unsigned char *)first_scb;
	int result;
	do {
		scb[9] = 0;
		++chain[(unsigned int)scb[12] + 8];
		result = Ph_GetScbStatus((int)chain, (int)scb);
		scb[11] = (unsigned char)result;
		if ((unsigned char)result == 16)
			++*(unsigned short *)(chain + 266);
		if (*(unsigned int *)scb == A2940_CHAIN_END)
			break;
		scb = (unsigned char *)(unsigned long)*(unsigned int *)scb;
	} while (1);
	return result;
}

char Ph_InsertBookmark(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	*(unsigned char *)(chain + 360) = 0xff;
	return Ph_ChainAppendEnd(host_address, (unsigned int *)(chain + 352));
}

int Ph_RemoveBookmark(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	return Ph_ChainRemove(host_address, (unsigned int *)(chain + 352));
}
