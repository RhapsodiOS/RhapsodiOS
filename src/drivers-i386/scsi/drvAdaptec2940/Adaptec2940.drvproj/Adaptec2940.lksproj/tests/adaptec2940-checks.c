/* Compile and exercise production declarations and routines with I/O shims. */
#include <stdio.h>
#include <string.h>

#import "../Adaptec2940.h"
#import "../SCSIBus.h"

#ifndef A2940_FREESTANDING
struct Adaptec2940InstanceLayout { @defs(Adaptec2940); };
struct SCSIBusInstanceLayout { @defs(SCSIBus); };
#endif

#ifndef A2940_BUILD_HASH
#define A2940_BUILD_HASH "unrecorded"
#endif

/* The compiler's Objective-C class layout must preserve the IDA offsets. */
#ifndef A2940_FREESTANDING
A2940_LAYOUT_ASSERT(a2940_ivar_ioBase_at_296,
	offsetof(struct Adaptec2940InstanceLayout, ioBase) == 296);
A2940_LAYOUT_ASSERT(a2940_ivar_ioBase_pad_at_298,
	offsetof(struct Adaptec2940InstanceLayout, _pad_ioBase) == 298);
A2940_LAYOUT_ASSERT(a2940_ivar_channel_at_300,
	offsetof(struct Adaptec2940InstanceLayout, channelInfo) == 300);
A2940_LAYOUT_ASSERT(a2940_ivar_host_block_at_308,
	offsetof(struct Adaptec2940InstanceLayout, hspStructSave) == 308);
A2940_LAYOUT_ASSERT(a2940_ivar_host_block_size_at_312,
	offsetof(struct Adaptec2940InstanceLayout, hspStructFreeSize) == 312);
A2940_LAYOUT_ASSERT(a2940_ivar_interrupt_port_at_316,
	offsetof(struct Adaptec2940InstanceLayout, interruptPortKern) == 316);
A2940_LAYOUT_ASSERT(a2940_ivar_command_queue_at_320,
	offsetof(struct Adaptec2940InstanceLayout, commandQ) == 320);
A2940_LAYOUT_ASSERT(a2940_ivar_command_lock_at_328,
	offsetof(struct Adaptec2940InstanceLayout, commandLock) == 328);
A2940_LAYOUT_ASSERT(a2940_ivar_active_queue_at_332,
	offsetof(struct Adaptec2940InstanceLayout, activeQ) == 332);
A2940_LAYOUT_ASSERT(a2940_ivar_scb_queue_at_340,
	offsetof(struct Adaptec2940InstanceLayout, scbQ) == 340);
A2940_LAYOUT_ASSERT(a2940_ivar_scb_queue_length_at_348,
	offsetof(struct Adaptec2940InstanceLayout, scbQLength) == 348);
A2940_LAYOUT_ASSERT(a2940_ivar_bad_scb_queue_at_352,
	offsetof(struct Adaptec2940InstanceLayout, scbBadQ) == 352);
A2940_LAYOUT_ASSERT(a2940_ivar_flags_at_360,
	offsetof(struct Adaptec2940InstanceLayout, reinitChannel) - sizeof(unsigned int) == 360);
A2940_LAYOUT_ASSERT(a2940_ivar_reinit_channel_at_364,
	offsetof(struct Adaptec2940InstanceLayout, reinitChannel) == 364);
A2940_LAYOUT_ASSERT(a2940_ivar_reset_state_at_368,
	offsetof(struct Adaptec2940InstanceLayout, resetState) == 368);
A2940_LAYOUT_ASSERT(a2940_ivar_max_queue_at_372,
	offsetof(struct Adaptec2940InstanceLayout, maxQueueLen) == 372);
A2940_LAYOUT_ASSERT(a2940_ivar_queue_total_at_376,
	offsetof(struct Adaptec2940InstanceLayout, queueLenTotal) == 376);
A2940_LAYOUT_ASSERT(a2940_ivar_total_commands_at_380,
	offsetof(struct Adaptec2940InstanceLayout, totalCommands) == 380);
A2940_LAYOUT_ASSERT(a2940_ivar_outstanding_count_at_384,
	offsetof(struct Adaptec2940InstanceLayout, outstandingCount) == 384);
A2940_LAYOUT_ASSERT(a2940_ivar_bus_type_at_388,
	offsetof(struct Adaptec2940InstanceLayout, busType) == 388);
A2940_LAYOUT_ASSERT(a2940_ivar_level_irq_at_392,
	offsetof(struct Adaptec2940InstanceLayout, levelIRQ) == 392);
A2940_LAYOUT_ASSERT(a2940_ivar_bus_number_at_393,
	offsetof(struct Adaptec2940InstanceLayout, busNumber) == 393);
A2940_LAYOUT_ASSERT(a2940_ivar_device_number_at_394,
	offsetof(struct Adaptec2940InstanceLayout, deviceNumber) == 394);
A2940_LAYOUT_ASSERT(a2940_ivar_function_number_at_395,
	offsetof(struct Adaptec2940InstanceLayout, functionNumber) == 395);
A2940_LAYOUT_ASSERT(a2940_bus_direct_at_580,
	offsetof(struct SCSIBusInstanceLayout, _direct) == 580);
A2940_LAYOUT_ASSERT(a2940_bus_channel_at_584,
	offsetof(struct SCSIBusInstanceLayout, _scsiChannel) == 584);
#endif /* !A2940_FREESTANDING */

static unsigned char sequencer_ram[A2940_SEQ_IMAGE_SIZE];
static unsigned int sequencer_address;
static unsigned int sequencer_writes;
static unsigned int sequencer_reads;
static unsigned int sequencer_barriers;
static int sequencer_fail_read = -1;
static unsigned short sequencer_trace_port[A2940_SEQ_IMAGE_SIZE + 32];
static unsigned char sequencer_trace_value[A2940_SEQ_IMAGE_SIZE + 32];
static unsigned int sequencer_trace_count;
static unsigned char test_registers[256];
static unsigned int test_read_count;
static int hcntrl_pause_after_reads = -1;
static int simulate_delay_pause;

void a2940_test_outb(unsigned short port, unsigned char value)
{
	unsigned int offset = (unsigned int)port - 0x100;
	if (sequencer_trace_count < A2940_SEQ_IMAGE_SIZE + 32) {
		sequencer_trace_port[sequencer_trace_count] = port;
		sequencer_trace_value[sequencer_trace_count++] = value;
	}
	++sequencer_barriers;
	test_registers[offset & 0xff] = value;
	if (offset == 0x87 && value == 0 && simulate_delay_pause) {
		hcntrl_pause_after_reads = 1;
		simulate_delay_pause = 0;
	}
	if (offset == AIC_SEQADDR0)
		sequencer_address = (sequencer_address & 0xffffff00U) | value;
	else if (offset == AIC_SEQADDR1)
		sequencer_address = (sequencer_address & 0xffff00ffU) | ((unsigned int)value << 8);
	else if (offset == AIC_SEQRAM && sequencer_address < A2940_SEQ_IMAGE_SIZE) {
		sequencer_ram[sequencer_address++] = value;
		++sequencer_writes;
	}
}

unsigned char a2940_test_inb(unsigned short port)
{
	unsigned int offset = (unsigned int)port - 0x100;
	unsigned int address;
	if (offset != AIC_SEQRAM) {
		++test_read_count;
		if (offset == 0x87 && hcntrl_pause_after_reads >= 0 &&
		    (test_registers[offset] & 4) == 0) {
			if (hcntrl_pause_after_reads == 0) {
				test_registers[offset] |= 4;
				hcntrl_pause_after_reads = -1;
			} else {
				--hcntrl_pause_after_reads;
			}
		}
		return test_registers[offset & 0xff];
	}
	address = sequencer_address++;
	if (address >= A2940_SEQ_IMAGE_SIZE)
		return 0;
	++sequencer_reads;
	if ((int)address == sequencer_fail_read)
		return sequencer_ram[address] ^ 1;
	return sequencer_ram[address];
}

#define A2940_TEST 1
#include "../Adaptec2940Sequencer.c"
#include "../Adaptec2940HIM.c"
#include "../Adaptec2940Optima.c"

static int run_him_chain_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char chain[272];
	unsigned int *links = (unsigned int *)chain;
	Adaptec2940SCB a;
	Adaptec2940SCB b;
	Adaptec2940SCB c;
	int result;
	memset(&host, 0, sizeof(host));
	memset(&a, 0, sizeof(a));
	memset(&b, 0, sizeof(b));
	memset(&c, 0, sizeof(c));
	*(unsigned int **)(host.bytes + 52) = links;
	links[0] = links[1] = 0xffffffffU;
	host.bytes[13] = 0x80;
	host.bytes[62] = 0x37;
	host.bytes[64] = 0x42;
	if (Ph_ChainPrevious((int *)links, 0) != -1)
		return 0;
	Ph_ChainAppendEnd((int)&host, (unsigned int *)&a);
	if (links[0] != (unsigned int)&a || links[1] != (unsigned int)&a ||
	    ((unsigned char *)links)[268] != 0x37 ||
	    ((unsigned char *)links)[269] != 0x42 ||
	    (host.bytes[13] & 0x80) != 0 || a.chain_next != (void *)0xffffffffU)
		return 0;
	Ph_ChainAppendEnd((int)&host, (unsigned int *)&b);
	Ph_ChainAppendEnd((int)&host, (unsigned int *)&c);
	if (a.chain_next != (void *)&b || b.chain_next != (void *)&c ||
	    c.chain_next != (void *)0xffffffffU || links[1] != (unsigned int)&c)
		return 0;
	if (Ph_ChainPrevious((int *)links, (int)&c) != (int)&b)
		return 0;
	result = Ph_ChainRemove((int)&host, (unsigned int *)&b);
	if (result != (int)&a || a.chain_next != (void *)&c || links[1] != (unsigned int)&c)
		return 0;
	result = Ph_ChainRemove((int)&host, (unsigned int *)&c);
	if (result != (int)&a || a.chain_next != (void *)0xffffffffU ||
	    links[1] != (unsigned int)&a)
		return 0;
	result = Ph_ChainRemove((int)&host, (unsigned int *)&a);
	return result == -1 && links[0] == 0xffffffffU && links[1] == 0xffffffffU &&
	       (host.bytes[13] & 0x80) != 0;
}

static int run_him_hcntrl_checks(void)
{
	unsigned char result;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	sequencer_address = 0;
	result = Ph_WriteHcntrl(0x100, 0x20);
	if (result != 0x20 || sequencer_trace_count != 2 || test_read_count != 3 ||
	    sequencer_barriers != 2 || sequencer_trace_port[0] != 0x187 ||
	    sequencer_trace_value[0] != 4 || sequencer_trace_value[1] != 0x20)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 1;
	result = Ph_WriteHcntrl(0x100, 0x20);
	if (result != 0x24 || sequencer_trace_count != 2 || sequencer_trace_value[1] != 0x24)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x87] = 4;
	test_registers[0x91] = 8;
	if (Ph_ReadIntstat(0x100) != 8 || sequencer_trace_count != 0 || test_read_count != 2)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 8;
	if (Ph_ReadIntstat(0x100) != 8 || sequencer_trace_count != 2 ||
	    sequencer_barriers != 2 || sequencer_trace_value[0] != 4 ||
	    sequencer_trace_value[1] != 4)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	return Ph_Pause(0x100) == 4 && sequencer_trace_count == 1 &&
	       sequencer_trace_value[0] == 4;
}

static int run_him_status_checks(void)
{
	unsigned char chain[272];
	unsigned char scb[256];
	memset(chain, 0, sizeof(chain));
	memset(scb, 0, sizeof(scb));
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[3] = 0xc0;
	test_registers[176] = 0x78;
	test_registers[177] = 0x56;
	test_registers[178] = 0x34;
	test_registers[179] = 0x12;
	if (Ph_CheckLength((int)scb, 0x100) != (char)0xc0 ||
	    *(unsigned int *)(scb + 28) != 0x12345678 || scb[43] != 18 ||
	    sequencer_trace_count != 0 || test_read_count != 5)
		return 0;
	scb[10] = 0x40;
	scb[43] = 7;
	*(unsigned int *)(scb + 28) = 0xfeedface;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[3] = 0xc0;
	if (Ph_CheckLength((int)scb, 0x100) != (char)0xc0 || scb[43] != 7 ||
	    *(unsigned int *)(scb + 28) != 0xfeedface || test_read_count != 1)
		return 0;
	scb[24] = 20;
	scb[43] = 1;
	if (Ph_SetMgrStat(scb) != 20 || scb[11] != 4)
		return 0;
	chain[268] = 1;
	chain[269] = 2;
	chain[8] = 2;
	scb[12] = 0;
	if (Ph_GetScbStatus((int)chain, (int)scb) != 32)
		return 0;
	scb[13] = 0x20;
	return Ph_GetScbStatus((int)chain, (int)scb) == 16;
}

static int run_him_misc_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char source[3] = {0x11, 0x22, 0x33};
	unsigned char destination[3] = {0, 0, 0};
	memset(&host, 0, sizeof(host));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_OutBuffer(0x120, (int)source, 3) != 0x33 || sequencer_trace_count != 3 ||
	    sequencer_trace_port[0] != 0x120 || sequencer_trace_value[0] != 0x11 ||
	    sequencer_trace_port[2] != 0x122 || sequencer_trace_value[2] != 0x33 ||
	    sequencer_barriers != 3)
		return 0;
	if (Ph_InBuffer(0x120, (int)destination, 3) != 0x33 ||
	    destination[0] != 0x11 || destination[1] != 0x22 || destination[2] != 0x33)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_SetNeedNego(3, 0x100) != (char)-113 || sequencer_trace_count != 1 ||
	    sequencer_trace_port[0] != 0x123 || sequencer_trace_value[0] != 0x8f)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (PH_EnableInt((int)&host) != 2 || sequencer_trace_count != 2 ||
	    sequencer_trace_value[0] != 4 || sequencer_trace_value[1] != 2)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	test_registers[0x87] = 6;
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (PH_DisableInt((int)&host) != 4 || sequencer_trace_count != 1 ||
	    sequencer_trace_value[0] != 4)
		return 0;
	Ph_Abort();
	Ph_BusReset();
	Ph_HaSoftReset();
	Ph_SoftReset();
	return Ph_SendTrmMsg(0, 0) == 0 && Ph_TrmCmplt() == 0;
}

static int run_him_bookmark_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char chain[512];
	memset(&host, 0, sizeof(host));
	memset(chain, 0, sizeof(chain));
	*(unsigned int **)(host.bytes + 52) = (unsigned int *)chain;
	*(unsigned int *)(host.bytes + 56) = 0x1000;
	host.bytes[13] = 0x80;
	*(unsigned int *)chain = 0xffffffffU;
	*(unsigned int *)(chain + 4) = 0xffffffffU;
	*(unsigned int *)(chain + 352) = 0xffffffffU;
	if (Ph_SetScbMark((int)&host) != (int)chain ||
	    *(unsigned int *)(chain + 372) != 0x1194 ||
	    *(unsigned int *)(chain + 356) != (unsigned int)&host)
		return 0;
	Ph_InsertBookmark((int)&host);
	if (*(unsigned int *)chain != (unsigned int)(chain + 352) ||
	    *(unsigned int *)(chain + 4) != (unsigned int)(chain + 352) ||
	    chain[360] != 0xff || *(unsigned int *)(chain + 352) != 0xffffffffU ||
	    (host.bytes[13] & 0x80) != 0)
		return 0;
	return Ph_RemoveBookmark((int)&host) == -1 &&
	       *(unsigned int *)chain == 0xffffffffU &&
	       *(unsigned int *)(chain + 4) == 0xffffffffU &&
	       (host.bytes[13] & 0x80) != 0;
}

static int run_him_scb_prepare_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char chain[512];
	unsigned char first[256];
	unsigned char second[256];
	memset(&host, 0, sizeof(host));
	memset(chain, 0, sizeof(chain));
	memset(first, 0, sizeof(first));
	memset(second, 0, sizeof(second));
	*(unsigned char **)(host.bytes + 52) = chain;
	chain[268] = 1;
	*(unsigned int *)first = (unsigned int)second;
	*(unsigned int *)second = 0xffffffffU;
	first[9] = second[9] = 0xaa;
	if (Ph_ScbPrepare((int)&host, (int *)first) != 32)
		return 0;
	return chain[8] == 2 && *(unsigned short *)(chain + 266) == 1 &&
	       first[9] == 0 && first[11] == 16 && second[9] == 0 && second[11] == 32;
}

static int run_him_sync_map_checks(void)
{
	static const unsigned char periods[] = {
		0x00, 0x10, 0x11, 0x12, 0x13, 0x14, 0x19, 0x1a, 0x1f, 0x20,
		0x25, 0x26, 0x2b, 0x2c, 0x32, 0x33, 0x38, 0x39, 0x3e, 0x3f, 0xff
	};
	static const unsigned char expected[] = {
		16, 16, 32, 0, 32, 0, 0, 16, 16, 32, 32, 48, 48, 64, 64,
		80, 80, 96, 96, 112, 112
	};
	unsigned char scb[256];
	unsigned int i;
	for (i = 0; i < sizeof(periods); ++i) {
		scb[67] = periods[i];
		if (Ph_SyncSet((int)scb) != expected[i])
			return 0;
	}
	return 1;
}

static int run_him_negotiation_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char scb[256];
	memset(&host, 0, sizeof(host));
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	host.bytes[41] = 0x80;
	if (Ph_ScbRenego((int)&host, 0x90) != (char)-113 || sequencer_trace_count != 1 ||
	    sequencer_trace_port[0] != 0x129 || sequencer_trace_value[0] != 0x8f)
		return 0;
	host.bytes[41] = 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x29] = 0x8f;
	if (Ph_ScbRenego((int)&host, 0x90) != (char)-113 || host.bytes[41] != 0x81 ||
	    sequencer_trace_count != 1 || sequencer_trace_value[0] != 0x8f)
		return 0;
	host.bytes[41] = 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	if (Ph_ScbRenego((int)&host, 0x90) != 0 || sequencer_trace_count != 1 ||
	    sequencer_trace_value[0] != 0)
		return 0;
	scb[66] = 1;
	scb[12] = 0x90;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x31] = 0xff;
	test_registers[1] = 0xff;
	if (Ph_ClearFast20Reg((int)&host, (int)scb) != 0xdf || sequencer_trace_count != 2 ||
	    sequencer_trace_port[0] != 0x131 || sequencer_trace_value[0] != 0xfd ||
	    sequencer_trace_port[1] != 0x101 || sequencer_trace_value[1] != 0xdf)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	scb[67] = 0x18;
	Ph_LogFast20Map((int)&host, scb);
	if (sequencer_trace_count != 2 || sequencer_trace_value[0] != 2 ||
	    sequencer_trace_value[1] != 0x20)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x31] = 0xff;
	test_registers[1] = 0xff;
	scb[67] = 0x19;
	Ph_LogFast20Map((int)&host, scb);
	return sequencer_trace_count == 2 && sequencer_trace_value[0] == 0xfd &&
	       sequencer_trace_value[1] == 0xdf;
}

static int run_him_delay_checks(void)
{
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	sequencer_address = 0;
	hcntrl_pause_after_reads = -1;
	test_registers[0x87] = 4;
	test_registers[176] = 0xaa;
	test_registers[177] = 0xbb;
	simulate_delay_pause = 1;
	if (Ph_Delay(0x100, 1) != 0xbb || sequencer_trace_count != 8 ||
	    sequencer_barriers != 8)
		return 0;
	return sequencer_trace_port[0] == 0x1b0 && sequencer_trace_value[0] == 0x54 &&
	       sequencer_trace_port[1] == 0x1b1 && sequencer_trace_value[1] == 0x0b &&
	       sequencer_trace_port[2] == 0x162 && sequencer_trace_value[2] == 4 &&
	       sequencer_trace_port[3] == 0x163 && sequencer_trace_value[3] == 0 &&
	       sequencer_trace_port[4] == 0x187 && sequencer_trace_value[4] == 0 &&
	       sequencer_trace_port[5] == 0x192 && sequencer_trace_value[5] == 1 &&
	       sequencer_trace_port[6] == 0x1b0 && sequencer_trace_value[6] == 0xaa &&
	       sequencer_trace_port[7] == 0x1b1 && sequencer_trace_value[7] == 0xbb;
}

static int run_him_pollint_checks(void)
{
	Adaptec2940HostInfo host;
	memset(&host, 0, sizeof(host));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 0x0b;
	if (PH_PollInt((int)&host) != 0x0b || sequencer_trace_count != 2 ||
	    sequencer_trace_value[0] != 4 || sequencer_trace_value[1] != 4)
		return 0;
	memset(test_registers, 0, sizeof(test_registers));
	sequencer_trace_count = sequencer_barriers = test_read_count = 0;
	test_registers[0x91] = 0x80;
	return PH_PollInt((int)&host) == 0 && sequencer_trace_count == 2 &&
	       sequencer_trace_value[0] == 4 && sequencer_trace_value[1] == 0;
}

static int run_optima_size_checks(void)
{
	return Ph_CalcOptimaSize(0) == 1542 &&
	       Ph_CalcOptimaSize(1) == 1552 &&
	       Ph_CalcOptimaSize(254) == 4082 &&
	       Ph_CalcOptimaSize(255) == 4082 &&
	       PH_CalcDataSize(0, 254) == 4082 &&
	       PH_CalcDataSize(0, -1) == 4082;
}

static int run_optima_config_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	int host_address = (int)(unsigned long)host;

	memset(host, 0, sizeof(host));
	if (Ph_GetOptimaConfig(host_address) != 4082 ||
	    *(unsigned short *)(host + 66) != 254 ||
	    *(unsigned short *)(host + 60) != 4082 || host[13] != 1)
		return 0;
	*(unsigned short *)(host + 66) = 8;
	host[13] = 0xa0;
	return Ph_GetOptimaConfig(host_address) == 1622 &&
	       *(unsigned short *)(host + 66) == 8 &&
	       *(unsigned short *)(host + 60) == 1622 && host[13] == 0xa1;
}

static int run_optima_busy_map_checks(void)
{
	unsigned char host[A2940_HOST_INFO_SIZE];
	unsigned char block[768];
	unsigned char scb[A2940_SCB_SIZE];
	unsigned int host_address = (unsigned int)(unsigned long)host;
	unsigned int *scb_array;
	unsigned char *busy_map;
	int result;
	int index;

	memset(host, 0, sizeof(host));
	memset(block, 0, sizeof(block));
	memset(scb, 0, sizeof(scb));
	*(unsigned int *)(host + 52) = (unsigned int)(unsigned long)block;
	scb_array = (unsigned int *)(block + 272);
	busy_map = block + 504;
	scb[12] = 77;
	scb_array[0] = (unsigned int)(unsigned long)scb;
	result = Ph_OptimaClearTargetBusy((int)host_address, 0);
	if (result != (int)(unsigned long)busy_map || busy_map[77] != 0xff)
		return 0;
	busy_map[31] = 0;
	result = Ph_OptimaIndexClearBusy((int)host_address, 31);
	if (result != (int)(unsigned long)busy_map || busy_map[31] != 0xff)
		return 0;
	result = Ph_OptimaClearQinFifo((int)host_address);
	if (result != (int)(unsigned long)(block + 496))
		return 0;
	for (index = 0; index <= 255; ++index) {
		if (block[496 + index] != 0xff)
			return 0;
	}
	return 1;
}

static int run_optima_noop_checks(void)
{
	Ph_OptimaClearDevQue();
	Ph_OptimaClearChannelBusy();
	return 1;
}

static int run_optima_checks(void)
{
	return run_optima_size_checks() && run_optima_config_checks() &&
	       run_optima_busy_map_checks() && run_optima_noop_checks();
}

static int is_group(const char *value, const char *expected)
{
	return strcmp(value, expected) == 0;
}

static int run_firmware_checks(void)
{
	Adaptec2940HostInfo host;
	unsigned char original = P_Seq_01[17];
	unsigned char expected;
	unsigned int i;
	int result;
	memset(&host, 0, sizeof(host));
	*(unsigned int *)(host.bytes + A2940_HA_IO_BASE_OFFSET) = 0x100;
	*(unsigned short *)(host.bytes + A2940_HA_MODE_OFFSET) = 0;
	sequencer_writes = sequencer_reads = sequencer_trace_count = sequencer_barriers = 0;
	sequencer_address = 0;
	result = Ph_LoadSequencer(&host);
	if (result != -2 || sequencer_writes != 0 || sequencer_reads != 0)
		return 0;

	*(unsigned short *)(host.bytes + A2940_HA_MODE_OFFSET) = 2;
	P_SeqExist[20] = 17;
	host.bytes[A2940_HA_OPTIONS_OFFSET] = 1;
	sequencer_address = sequencer_writes = sequencer_reads = sequencer_trace_count = sequencer_barriers = 0;
	sequencer_fail_read = -1;
	result = Ph_LoadSequencer(&host);
	if (result != 0 || P_Seq_01[17] != 0xff ||
	    sequencer_writes != 1960 || sequencer_reads != 1960 ||
	    sequencer_trace_count != 1968 || sequencer_barriers != 1968)
		return 0;
	if (sequencer_trace_port[0] != 0x160 || sequencer_trace_value[0] != 0x91 ||
	    sequencer_trace_port[1] != 0x162 || sequencer_trace_value[1] != 0 ||
	    sequencer_trace_port[2] != 0x163 || sequencer_trace_value[2] != 0 ||
	    sequencer_trace_port[1963] != 0x160 || sequencer_trace_value[1963] != 0x90 ||
	    sequencer_trace_port[1964] != 0x160 || sequencer_trace_value[1964] != 0x91 ||
	    sequencer_trace_port[1965] != 0x162 || sequencer_trace_value[1965] != 0 ||
	    sequencer_trace_port[1966] != 0x163 || sequencer_trace_value[1966] != 0 ||
	    sequencer_trace_port[1967] != 0x160 || sequencer_trace_value[1967] != 0x90)
		return 0;
	for (i = 0; i < 1960; ++i) {
		expected = i == 17 ? 0xff : P_Seq_01[i];
		if (sequencer_ram[i] != expected)
			return 0;
	}

	sequencer_address = sequencer_writes = sequencer_reads = sequencer_trace_count = sequencer_barriers = 0;
	sequencer_fail_read = 17;
	result = Ph_LoadSequencer(&host);
	sequencer_fail_read = -1;
	P_Seq_01[17] = original;
	P_SeqExist[20] = 0;
	return result == 255 && sequencer_writes == 1960 && sequencer_reads == 18 &&
	       sequencer_trace_count == 1967 && sequencer_barriers == 1967;
}

#ifdef A2940_FREESTANDING
void __objc_exec_class(void *module)
{
	(void)module;
}

void *memset(void *destination, int value, size_t length)
{
	unsigned char *bytes = (unsigned char *)destination;
	size_t i;
	for (i = 0; i < length; ++i)
		bytes[i] = (unsigned char)value;
	return destination;
}

extern __declspec(dllimport) __declspec(noreturn)
void __stdcall ExitProcess(unsigned int exitCode);

void mainCRTStartup(void)
{
	ExitProcess(run_firmware_checks() && run_him_chain_checks() &&
	            run_him_hcntrl_checks() && run_him_status_checks() &&
	            run_him_misc_checks() && run_him_bookmark_checks() &&
	            run_him_scb_prepare_checks() && run_him_sync_map_checks() &&
	            run_him_negotiation_checks() && run_him_delay_checks() &&
	            run_him_pollint_checks() && run_optima_checks() ? 0 : 42);
}
#else
int main(int argc, char **argv)
{
	const char *group = argc > 1 ? argv[1] : "all";
	if (is_group(group, "layouts")) {
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"layouts\",\"ok\":true,"
		       "\"cases\":[{\"id\":\"shared-layouts\",\"result\":\"pass\"}],"
		       "\"build_hash\":\"%s\"}\n", A2940_BUILD_HASH);
		return 0;
	}
	if (is_group(group, "firmware")) {
		int ok = run_firmware_checks();
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"firmware\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"sequencer-absent\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-success\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-runtime-patch\",\"result\":\"%s\"},"
		       "{\"id\":\"register-width-order\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-readback-failure\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n", ok ? "true" : "false",
		       ok ? "pass" : "fail", ok ? "pass" : "fail", ok ? "pass" : "fail",
		       ok ? "pass" : "fail", ok ? "pass" : "fail",
		       A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (is_group(group, "optima")) {
		int size_ok = run_optima_size_checks();
		int config_ok = run_optima_config_checks();
		int busy_ok = run_optima_busy_map_checks();
		int noop_ok = run_optima_noop_checks();
		int ok = size_ok && config_ok && busy_ok && noop_ok;
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"optima\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"optima-size-bounds\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-host-config\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-busy-map\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-qin-fifo\",\"result\":\"%s\"},"
		       "{\"id\":\"optima-clear-noops\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n",
		       ok ? "true" : "false", size_ok ? "pass" : "fail",
		       config_ok ? "pass" : "fail", busy_ok ? "pass" : "fail",
		       busy_ok ? "pass" : "fail", noop_ok ? "pass" : "fail",
		       A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (is_group(group, "him")) {
		int chain_ok = run_him_chain_checks();
		int hcntrl_ok = run_him_hcntrl_checks();
		int status_ok = run_him_status_checks();
		int misc_ok = run_him_misc_checks();
		int bookmark_ok = run_him_bookmark_checks();
		int prepare_ok = run_him_scb_prepare_checks();
		int sync_map_ok = run_him_sync_map_checks();
		int negotiation_ok = run_him_negotiation_checks();
		int delay_ok = run_him_delay_checks();
		int pollint_ok = run_him_pollint_checks();
		int ok = chain_ok && hcntrl_ok && status_ok && misc_ok && bookmark_ok && prepare_ok && sync_map_ok && negotiation_ok && delay_ok && pollint_ok;
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"him\",\"ok\":%s,"
		       "\"cases\":[{\"id\":\"chain-empty\",\"result\":\"%s\"},"
		       "{\"id\":\"chain-front-middle-tail\",\"result\":\"%s\"},"
		       "{\"id\":\"chain-previous-miss\",\"result\":\"%s\"},"
		       "{\"id\":\"memory-set\",\"result\":\"%s\"},"
		       "{\"id\":\"hcntrl-write-mask\",\"result\":\"%s\"},"
		       "{\"id\":\"intstat-paused-unpaused\",\"result\":\"%s\"},"
		       "{\"id\":\"pause-unpause\",\"result\":\"%s\"},"
		       "{\"id\":\"short-transfer\",\"result\":\"%s\"},"
		       "{\"id\":\"port-buffer-transfer\",\"result\":\"%s\"},"
		       "{\"id\":\"interrupt-enable-disable\",\"result\":\"%s\"},"
		       "{\"id\":\"negotiation-marker\",\"result\":\"%s\"},"
		       "{\"id\":\"reset-trampolines\",\"result\":\"%s\"},"
		       "{\"id\":\"bookmark-insert-remove\",\"result\":\"%s\"},"
		       "{\"id\":\"scb-mark\",\"result\":\"%s\"},"
		       "{\"id\":\"scb-prepare-status-count\",\"result\":\"%s\"},"
		       "{\"id\":\"sync-period-map\",\"result\":\"%s\"},"
		       "{\"id\":\"renegotiation-marker\",\"result\":\"%s\"},"
		       "{\"id\":\"fast20-map\",\"result\":\"%s\"},"
		       "{\"id\":\"sequencer-delay\",\"result\":\"%s\"},"
		       "{\"id\":\"poll-interrupt-mask\",\"result\":\"%s\"}],"
		       "\"build_hash\":\"%s\"}\n", ok ? "true" : "false",
		       ok ? "pass" : "fail", ok ? "pass" : "fail",
		       ok ? "pass" : "fail", ok ? "pass" : "fail",
		       hcntrl_ok ? "pass" : "fail", hcntrl_ok ? "pass" : "fail",
		       hcntrl_ok ? "pass" : "fail", status_ok ? "pass" : "fail",
		       misc_ok ? "pass" : "fail", misc_ok ? "pass" : "fail",
		       misc_ok ? "pass" : "fail", misc_ok ? "pass" : "fail",
		       bookmark_ok ? "pass" : "fail", bookmark_ok ? "pass" : "fail",
		       prepare_ok ? "pass" : "fail",
		       sync_map_ok ? "pass" : "fail",
		       negotiation_ok ? "pass" : "fail", negotiation_ok ? "pass" : "fail",
		       delay_ok ? "pass" : "fail",
		       pollint_ok ? "pass" : "fail",
		       A2940_BUILD_HASH);
		return ok ? 0 : 1;
	}
	if (!is_group(group, "firmware") && !is_group(group, "him") &&
	    !is_group(group, "config") && !is_group(group, "optima") &&
	    !is_group(group, "integration") && !is_group(group, "all")) {
		printf("{\"schema_version\":\"adaptec2940-checks-v1\","
		       "\"group\":\"%s\",\"ok\":false,"
		       "\"error\":\"unknown group\",\"build_hash\":\"%s\"}\n",
		       group, A2940_BUILD_HASH);
		return 2;
	}
	printf("{\"schema_version\":\"adaptec2940-checks-v1\","
	       "\"group\":\"%s\",\"ok\":false,"
	       "\"error\":\"production routines for this group are not linked yet\","
	       "\"build_hash\":\"%s\"}\n", group, A2940_BUILD_HASH);
	return 2;
}
#endif /* A2940_FREESTANDING */
