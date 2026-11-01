/* Recovered Optima sizing and host-map helpers. */
#include "Adaptec2940HIM.h"

#if defined(A2940_TEST)
extern void a2940_test_outb(unsigned short port, unsigned char value);
extern unsigned char a2940_test_inb(unsigned short port);
#define A2940_OPTIMA_OUTB(port, value) a2940_test_outb((unsigned short)(port), (unsigned char)(value))
#define A2940_OPTIMA_INB(port) a2940_test_inb((unsigned short)(port))
#else
#include <driverkit/i386/ioPorts.h>
#define A2940_OPTIMA_OUTB(port, value) outb((port), (value))
#define A2940_OPTIMA_INB(port) inb((port))
#endif

static unsigned char *a2940_optima_host(int address)
{
	return (unsigned char *)(unsigned long)(unsigned int)address;
}

static unsigned char *a2940_optima_block(unsigned char *host)
{
	return (unsigned char *)(unsigned long)*(unsigned int *)(host + 52);
}

static unsigned char *a2940_optima_scb(int address)
{
	return (unsigned char *)(unsigned long)(unsigned int)address;
}

int PH_CalcDataSize(int host_address, short count)
{
	(void)host_address;
	return (unsigned short)Ph_CalcOptimaSize((unsigned short)count);
}

int Ph_CalcOptimaSize(unsigned short count)
{
	if (count > 254)
		count = 254;
	return (unsigned short)(10 * (count + 1) + 1532);
}

int Ph_GetOptimaConfig(int host_address)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned short count = *(unsigned short *)(host + 66);
	int size;

	if (count == 0 || count > 254)
		count = 254;
	*(unsigned short *)(host + 66) = count;
	host[13] |= 1;
	size = Ph_CalcOptimaSize(count);
	*(unsigned short *)(host + 60) = (unsigned short)size;
	return size;
}

int Ph_OptimaIndexClearBusy(int host_address, unsigned char index)
{
	unsigned char *block = a2940_optima_block(
		a2940_optima_host(host_address));
	unsigned char *busy_map = (unsigned char *)(unsigned long)
		*(unsigned int *)(block + 504);

	busy_map[index] = 0xff;
	return (int)(unsigned long)busy_map;
}

int Ph_OptimaClearTargetBusy(int host_address, unsigned char target)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned int *scb_table = (unsigned int *)(unsigned long)
		*(unsigned int *)(block + 272);
	unsigned int scb_address = scb_table[target];
	unsigned char busy_index = *(unsigned char *)(
		(unsigned long)scb_address + 12);

	return Ph_OptimaIndexClearBusy(host_address, busy_index);
}

int Ph_OptimaRequestSense(int scb_address, char io_index)
{
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned int data_length = *(unsigned int *)(scb + 20) - 8;
	unsigned char target_flags = scb[53] & 0xe0;
	unsigned char i;
	unsigned char scatter_gather;
	int result;

	for (i = 0; i <= 5; ++i)
		scb[52 + i] = 0;
	scb[52] = 3;
	scb[53] |= target_flags;
	scb[56] = scb[48];
	scb[13] |= 0x80;
	scb[13] &= (unsigned char)~0x40;
	scb[13] &= (unsigned char)~0x20;
	scb[15] = 1;
	scb[14] = 6;
	*(unsigned int *)(scb + 16) = data_length;
	scb[24] = 0;
	*(unsigned int *)(scb + 28) = 0;
	for (scatter_gather = 4; scatter_gather <= 7; ++scatter_gather)
		*(unsigned int *)(scb + 4 * scatter_gather + 12) = 0;
	Ph_OptimaQHead(io_index, scb_address, (short)io_base);
	result = Ph_OptimaIndexClearBusy((int)(unsigned long)host, scb[12]);
	scb[11] = 8;
	return result;
}

int Ph_OptimaCmdComplete(int host_address, unsigned char hcntrl, int status_word)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned char *qout_map = (unsigned char *)(unsigned long)
		*(unsigned int *)(block + 500);
	unsigned int qout_index = block[490];
	unsigned char scb_index = qout_map[qout_index];
	unsigned int result = (unsigned int)status_word;
	unsigned char *scb;
	unsigned int *scb_array;
	unsigned char *busy_map;
	unsigned char register_value;

	if (scb_index != 0xff) {
		scb_array = (unsigned int *)(unsigned long)*(unsigned int *)(block + 272);
		scb = (unsigned char *)(unsigned long)scb_array[scb_index];
		block[490] = (unsigned char)(qout_index + 1);
		if (scb[8] == 4) {
			unsigned char target = scb[12] >> 4;
			if ((host[target + 32] & 0x81) != 0)
				Ph_SetNeedNego(target, (short)io_base);
		}
		if (scb[8] == 0xff) {
			unsigned char busy_index = scb[12];
			busy_map = (unsigned char *)(unsigned long)
				*(unsigned int *)(block + 504);
			if (busy_map[busy_index] == scb_index)
				busy_map[busy_index] = 0xff;
			Ph_OptimaReturnFreeScb(host_address, scb_index);
		} else if (scb[11] != 68 || (scb[25] & 8) == 0) {
			result = (result & 0xffff00ffU) |
				((unsigned int)(((status_word >> 8) & 0xff) | 0x40) << 8);
			if (scb[11] == 8) {
				if (scb[43] != 72)
					scb[43] = 0;
				scb[11] = 4;
				scb[24] = 2;
			}
			Ph_TerminateCommand((int)(unsigned long)scb, (char)scb_index);
		}
		return (int)((result & 0x00ffffffU) | 0x01000000U);
	}

	Ph_Pause((int)io_base);
	register_value = A2940_OPTIMA_INB(io_base + 158);
	if ((register_value & 1) != (unsigned char)status_word) {
		Ph_WriteHcntrl((short)io_base, hcntrl);
		result = (unsigned int)status_word & 0x00ffffffU;
		result = (result & 0xffff00ffU) |
			((unsigned int)(((status_word >> 8) & 0xff) | 0x80) << 8);
		result = (result & 0x00ffffffU & 0xffffff00U) | 1U;
		return (int)(result | 0x01000000U);
	}
	if (qout_map[block[490]] != 0xff) {
		Ph_WriteHcntrl((short)io_base, hcntrl);
		return (int)((result & 0x00ffffffU) | 0x01000000U);
	}
	register_value = A2940_OPTIMA_INB(io_base + 158);
	if ((register_value & 1) == 0)
		A2940_OPTIMA_OUTB(io_base + 146, 2);
	register_value = A2940_OPTIMA_INB(io_base + 158);
	result = (unsigned int)status_word & 0x00ffffffU;
	if ((register_value & 1) != (unsigned char)status_word)
		result |= 0x01000000U;
	Ph_WriteHcntrl((short)io_base, hcntrl);
	return (int)result;
}

void Ph_OptimaClearDevQue(void)
{
	/* IDA body is an empty seven-byte prologue/epilogue. */
}

int Ph_OptimaClearQinFifo(int host_address)
{
	unsigned char *block = a2940_optima_block(
		a2940_optima_host(host_address));
	unsigned char *qin_map = (unsigned char *)(unsigned long)
		*(unsigned int *)(block + 496);
	int index;

	for (index = 0; index <= 255; ++index)
		qin_map[index] = 0xff;
	return (int)(unsigned long)qin_map;
}

void Ph_OptimaClearChannelBusy(void)
{
	/* IDA body is an empty seven-byte prologue/epilogue. */
}

unsigned char Ph_OptimaEnableNextScbArray(int scb_address)
{
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned short port = (unsigned short)(*(unsigned short *)(host + 4) +
		(scb[12] >> 4) + 70);
	unsigned char result = A2940_OPTIMA_INB(port);

	if (result <= 0x7e) {
		result |= 0x80;
		A2940_OPTIMA_OUTB(port, result);
	}
	return result;
}

int Ph_OptimaMoreFreeScb(int block_address, int scb_address)
{
	unsigned char *block = (unsigned char *)(unsigned long)(unsigned int)block_address;
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned short max_targets = *(unsigned short *)(host + 66);

	if ((scb[13] & 0x20) == 0 && max_targets > 29)
		return (unsigned char)(31 - block[488]);
	if ((scb[13] & 0x20) != 0 && max_targets > 29)
		return (unsigned char)(block[271] - (block[488] - 1));
	return (unsigned char)(host[66] - block[488] + 1);
}

int Ph_OptimaGetFreeScb(int block_address, int scb_address)
{
	unsigned char *block = (unsigned char *)(unsigned long)(unsigned int)block_address;
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned short max_targets = *(unsigned short *)(host + 66);
	unsigned char limit = max_targets <= 29 ? (unsigned char)max_targets : 30;
	unsigned char free_head = block[488];
	unsigned char free_tail = block[271];
	unsigned char *free_queue = (unsigned char *)(unsigned long)*(unsigned int *)(block + 276);
	unsigned char index;

	if ((scb[13] & 0x20) == 0) {
		if (free_head > limit || free_head > free_tail)
			return 0xff;
		index = free_head;
		block[488] = (unsigned char)(free_head + 1);
	} else {
		if (free_tail <= 30 && (free_tail > limit || free_head > free_tail))
			return 0xff;
		if (free_tail > limit) {
			index = free_tail;
			block[271] = (unsigned char)(free_tail - 1);
		} else {
			index = free_head;
			block[488] = (unsigned char)(free_head + 1);
		}
	}
	return free_queue[index];
}

int Ph_OptimaReturnFreeScb(int host_address, unsigned char scb_index)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned char *free_queue = (unsigned char *)(unsigned long)*(unsigned int *)(block + 276);
	unsigned int *scb_array = (unsigned int *)(unsigned long)*(unsigned int *)(block + 272);
	unsigned int *scb_command = (unsigned int *)(unsigned long)*(unsigned int *)(block + 492);
	unsigned char queue_index;

	if (scb_index > 30) {
		queue_index = (unsigned char)(block[271] + 1);
		block[271] = queue_index;
	} else {
		queue_index = (unsigned char)(block[488] - 1);
		block[488] = queue_index;
	}
	free_queue[queue_index] = scb_index;
	scb_command[scb_index] = 0xffffffffU;
	scb_array[scb_index] = 0xffffffffU;
	return scb_index;
}

int Ph_SetOptimaHaData(int host_address)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned char remaining = host[66];
	unsigned short max_targets = *(unsigned short *)(host + 66);
	unsigned int *scb_table = (unsigned int *)(unsigned long)(block + 508);
	unsigned char *free_queue = (unsigned char *)(unsigned long)
		((unsigned int)(unsigned long)(block + 508) + 4 * max_targets + 4);

	*(unsigned int *)(block + 272) = (unsigned int)(unsigned long)scb_table;
	*(unsigned int *)(block + 276) = (unsigned int)(unsigned long)free_queue;
	*(unsigned int *)(block + 280) = (unsigned int)(unsigned long)(free_queue + max_targets + 1);
	Ph_MemorySet((unsigned char *)scb_table, (char)0xff, 4 * max_targets + 1);
	if ((host[12] & 2) != 0)
		*scb_table = 0xfffffffeU;
	block[271] = host[66];
	for (block[271] = host[66]; block[271] != 0; --remaining)
		free_queue[block[271]--] = remaining;
	return Ph_SetOptimaScratch(host_address);
}

int PH_RelocatePointers(int host_address, unsigned short delta)
{
	unsigned char *host = a2940_optima_host(host_address);
	*(unsigned int *)(host + 52) -= delta;
	*(unsigned int *)(host + 56) -= delta;
	return Ph_SetOptimaHaData(host_address);
}

int Ph_ScbPageJustifyQIN(int host_address)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned int max_targets = *(unsigned short *)(host + 66);
	unsigned int qin_offset = 2 * max_targets + 2;
	unsigned int layout_size = qin_offset + 4 * max_targets + 4;
	unsigned int alignment = (unsigned char)qin_offset +
		4 * (unsigned char)max_targets + host[56];

	if (alignment != 0) {
		unsigned char padding = (unsigned char)(layout_size + host[56] - 4);
		return (int)(unsigned long)(block + layout_size + 508 +
			(unsigned char)(0 - padding));
	}
	return (int)(unsigned long)(block + layout_size + 508);
}

unsigned int Ph_MovPtrToScratch(short index, unsigned int value, int host_address)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned short port = (unsigned short)(*(unsigned short *)(host + 4) + index);
	unsigned char *bytes = (unsigned char *)&value;
	unsigned int i;

	for (i = 0; i != 4; ++i)
		A2940_OPTIMA_OUTB(port + i, bytes[i]);
	return bytes[3];
}

char Ph_SetOptimaScratch(int host_address)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned int qin = (unsigned int)Ph_ScbPageJustifyQIN(host_address);
	unsigned int *scb_command;
	unsigned char *qin_map;
	unsigned char *qout_map;
	unsigned char *busy_map;
	unsigned int i;
	short port;
	unsigned char result = 0x7f;

	A2940_OPTIMA_OUTB(io_base + 65, 0);
	block[489] = 0;
	block[490] = 0;
*(unsigned int *)(block + 496) = qin;
	*(unsigned int *)(block + 500) = qin + 256;
	*(unsigned int *)(block + 504) = qin + 512;
	*(unsigned int *)(block + 492) = qin + 768;
	qin_map = (unsigned char *)(unsigned long)*(unsigned int *)(block + 496);
	qout_map = (unsigned char *)(unsigned long)*(unsigned int *)(block + 500);
	busy_map = (unsigned char *)(unsigned long)*(unsigned int *)(block + 504);
	scb_command = (unsigned int *)(unsigned long)*(unsigned int *)(block + 492);
	Ph_MemorySet((unsigned char *)scb_command, (char)0xff,
		4 * *(unsigned short *)(host + 66) + 1);
	for (i = 0; i <= 255; ++i) {
		qin_map[i] = 0xff;
		qout_map[i] = 0xff;
		busy_map[i] = 0xff;
	}
	block[488] = 1;
	block[271] = host[66];
	A2940_OPTIMA_OUTB(io_base + 59, 0xff);
	A2940_OPTIMA_OUTB(io_base + 60, 0xff);
	Ph_MovPtrToScratch(61, *(unsigned int *)(host + 56) +
		*(unsigned int *)(block + 492) - (unsigned int)(unsigned long)block,
		host_address);
	Ph_MovPtrToScratch(66, *(unsigned int *)(host + 56) +
		*(unsigned int *)(block + 496) - (unsigned int)(unsigned long)block,
		host_address);
	Ph_MovPtrToScratch(86, *(unsigned int *)(host + 56) +
		*(unsigned int *)(block + 500) - (unsigned int)(unsigned long)block,
		host_address);
	Ph_MovPtrToScratch(90, *(unsigned int *)(host + 56) +
		*(unsigned int *)(block + 504) - (unsigned int)(unsigned long)block,
		host_address);
	for (i = 0, port = 70; i <= 15; ++i, ++port)
		A2940_OPTIMA_OUTB(io_base + port, result);
	return result;
}

unsigned char Ph_OptimaEnque(unsigned char index, int scb_address, short io_base)
{
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned char *block = a2940_optima_block(host);
	unsigned int *scb_command = (unsigned int *)(unsigned long)*(unsigned int *)(block + 492);
	unsigned int *scb_array = (unsigned int *)(unsigned long)*(unsigned int *)(block + 272);
	unsigned char *qin_map = (unsigned char *)(unsigned long)*(unsigned int *)(block + 496);
	unsigned char tail = block[489];
	unsigned char count;

	scb_command[index] = *(unsigned int *)(scb + 20) - 40;
	scb_array[index] = (unsigned int)(unsigned long)scb;
	qin_map[tail] = index;
	block[489] = (unsigned char)(tail + 1);
	count = A2940_OPTIMA_INB(io_base + 65);
	++count;
	A2940_OPTIMA_OUTB(io_base + 65, count);
	return count;
}

unsigned char Ph_OptimaQHead(char index, int scb_address, short io_base)
{
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned char *block = a2940_optima_block(host);
	unsigned char *qin = (unsigned char *)(unsigned long)*(unsigned int *)(block + 496);
	unsigned short scb_register = (unsigned short)(io_base + (scb[12] >> 4) + 70);
	unsigned char sequencer_index = A2940_OPTIMA_INB(scb_register);
	unsigned char count;
	unsigned char ring_index;

	if (sequencer_index != 0x7f) {
		A2940_OPTIMA_OUTB(scb_register, 0x7f);
		count = A2940_OPTIMA_INB(io_base + 66);
		A2940_OPTIMA_OUTB(io_base + 66, (unsigned char)(count - 1));
		count = A2940_OPTIMA_INB(io_base + 65);
		ring_index = (unsigned char)(block[489] - count - 1);
		qin[ring_index] = sequencer_index & 0x7f;
		A2940_OPTIMA_OUTB(io_base + 65, (unsigned char)(count + 1));
	}
	count = A2940_OPTIMA_INB(io_base + 66);
	A2940_OPTIMA_OUTB(io_base + 66, (unsigned char)(count - 1));
	count = A2940_OPTIMA_INB(io_base + 65);
	ring_index = (unsigned char)(block[489] - count - 1);
	qin[ring_index] = (unsigned char)index;
	++count;
	A2940_OPTIMA_OUTB(io_base + 65, count);
	return count;
}

int Ph_OptimaEnqueHead(unsigned char index, int scb_address, int io_base)
{
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned char *block = a2940_optima_block(host);
	unsigned int *scb_command = (unsigned int *)(unsigned long)*(unsigned int *)(block + 492);

	scb_command[index] = *(unsigned int *)(scb + 20) - 40;
	return Ph_OptimaQHead((char)index, scb_address, (short)io_base);
}

int Ph_OptimaAbortActive(int scb_address)
{
	unsigned char *scb = a2940_optima_scb(scb_address);
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned char *block = a2940_optima_block(host);
	unsigned int *scb_array = (unsigned int *)(unsigned long)*(unsigned int *)(block + 272);
	unsigned char *qin_map = (unsigned char *)(unsigned long)*(unsigned int *)(block + 496);
	unsigned char *qout_map = (unsigned char *)(unsigned long)*(unsigned int *)(block + 500);
	unsigned int target_count = *(unsigned short *)(host + 66) + 1;
	unsigned int scb_index;
	unsigned int i;
	unsigned char queue_head;
	unsigned char queue_position;
	unsigned char count;
	unsigned char value;
	unsigned char saved_mode;
	unsigned short port;
	int result = 2;

	value = A2940_OPTIMA_INB(io_base + 135);
	Ph_WriteHcntrl((short)io_base, value | 4);
	do {
		value = A2940_OPTIMA_INB(io_base + 135);
	} while ((value & 4) == 0);
	for (i = 0; i <= 999; ++i) {
		value = A2940_OPTIMA_INB(io_base + 148);
		if ((value & 0x10) == 0)
			break;
	}
	for (scb_index = 1; scb_index < target_count; ++scb_index)
		if (scb_array[scb_index] == (unsigned int)(unsigned long)scb)
			break;
	if (scb_index < target_count) {
		queue_head = block[490];
		queue_position = queue_head;
		for (i = 0; i < 256 && qout_map[queue_position] != 0xff; ++i) {
			if (qout_map[queue_position] == scb_index)
				break;
			++queue_position;
		}
		if (i < 256 && qout_map[queue_position] == scb_index) {
			if (queue_position != queue_head) {
				while (queue_position != queue_head) {
					unsigned char previous = (unsigned char)(queue_position - 1);
					qout_map[queue_position] = qout_map[previous];
					queue_position = previous;
				}
			}
			++block[490];
			result = 0;
		}
		if (result == 2) {
			unsigned char qin_head = A2940_OPTIMA_INB(io_base + 66);
			queue_position = qin_head;
			while (queue_position != block[489] && qin_map[queue_position] != scb_index)
				++queue_position;
			if (queue_position != block[489] &&
			    qin_map[queue_position] == scb_index) {
				if (qin_head == queue_position) {
					scb[25] |= 8;
					result = 1;
				} else {
					while (queue_position != block[489]) {
						unsigned char source = (unsigned char)(queue_position + 1);
						qin_map[queue_position] = qin_map[source];
						queue_position = source;
					}
					--block[489];
					count = A2940_OPTIMA_INB(io_base + 65);
					A2940_OPTIMA_OUTB(io_base + 65, (unsigned char)(count - 1));
					result = 0;
				}
			}
		}
		if (result == 2) {
			port = (unsigned short)(io_base + (scb[12] >> 4) + 70);
			if (scb_index == A2940_OPTIMA_INB(port)) {
				scb[25] |= 8;
			} else {
				if (scb_index == A2940_OPTIMA_INB(io_base + 60)) {
					saved_mode = A2940_OPTIMA_INB(io_base + 144);
					A2940_OPTIMA_OUTB(io_base + 144, 1);
					value = A2940_OPTIMA_INB(io_base + 173);
					A2940_OPTIMA_OUTB(io_base + 173, value | 2);
					A2940_OPTIMA_OUTB(io_base + 154, 0);
					A2940_OPTIMA_OUTB(io_base + 144, saved_mode);
				}
				scb[11] = 68;
				scb[25] |= 8;
				scb[13] |= 8;
				scb[15] = 0;
				*(unsigned int *)(scb + 16) = (scb[13] & 0x20) != 0 ? 13 : 6;
				value = A2940_OPTIMA_INB(io_base);
				if ((value & 0x40) == 0 ||
				    (A2940_OPTIMA_INB(io_base + 59) != scb_index)) {
					void (*callback)(int, int, int) =
						(void (*)(int, int, int))(unsigned long)
						*(unsigned int *)(block + 480);
					if (callback != 0)
						callback(scb_index, scb_address, (int)io_base);
				}
			}
			result = 1;
		}
	}
	value = A2940_OPTIMA_INB(io_base + 135);
	Ph_WriteHcntrl((short)io_base, value & 0xfb);
	return result;
}

unsigned int *Ph_OptimaLoadFuncPtrs(int host_address)
{
	unsigned int *function_table = (unsigned int *)a2940_optima_block(
		a2940_optima_host(host_address));

	function_table[110] = (unsigned int)(unsigned long)Ph_OptimaMoreFreeScb;
	function_table[119] = (unsigned int)(unsigned long)Ph_OptimaEnque;
	function_table[120] = (unsigned int)(unsigned long)Ph_OptimaEnqueHead;
	function_table[111] = (unsigned int)(unsigned long)Ph_OptimaCmdComplete;
	function_table[112] = (unsigned int)(unsigned long)Ph_OptimaGetFreeScb;
	function_table[113] = (unsigned int)(unsigned long)Ph_OptimaReturnFreeScb;
	function_table[114] = (unsigned int)(unsigned long)Ph_OptimaAbortActive;
	function_table[115] = (unsigned int)(unsigned long)Ph_OptimaClearQinFifo;
	function_table[116] = (unsigned int)(unsigned long)Ph_OptimaIndexClearBusy;
	function_table[117] = (unsigned int)(unsigned long)Ph_OptimaClearTargetBusy;
	function_table[118] = (unsigned int)(unsigned long)Ph_OptimaRequestSense;
	function_table[121] = (unsigned int)(unsigned long)Ph_OptimaEnableNextScbArray;
	return function_table;
}
